import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger('discord');

/// Tipi di frame del protocollo IPC di Discord. L'indice è il valore
/// sul protocollo.
enum DiscordOpcode { handshake, frame, close, ping, pong }

/// Un messaggio ricevuto o inviato sulla pipe.
class DiscordFrame {
  const DiscordFrame(this.opcode, this.json);

  final DiscordOpcode opcode;
  final Map<String, dynamic> json;
}

/// 8 byte di intestazione (opcode e lunghezza, little-endian) più il JSON.
Uint8List encodeDiscordFrame(DiscordOpcode opcode, Map<String, Object?> json) {
  final payload = utf8.encode(jsonEncode(json));
  final bytes = Uint8List(8 + payload.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, opcode.index, Endian.little)
    ..setUint32(4, payload.length, Endian.little);
  bytes.setAll(8, payload);
  return bytes;
}

/// Ricompone i frame da byte che possono arrivare a pezzi. I frame con
/// opcode sconosciuto o JSON non valido vengono saltati.
class DiscordFrameReader {
  final _pending = <int>[];

  void add(List<int> bytes) => _pending.addAll(bytes);

  List<DiscordFrame> takeFrames() {
    final frames = <DiscordFrame>[];
    while (_pending.length >= 8) {
      final header =
          ByteData.sublistView(Uint8List.fromList(_pending.sublist(0, 8)));
      final opcode = header.getUint32(0, Endian.little);
      final length = header.getUint32(4, Endian.little);
      if (_pending.length < 8 + length) break;
      final payload = _pending.sublist(8, 8 + length);
      _pending.removeRange(0, 8 + length);
      if (opcode >= DiscordOpcode.values.length) continue;
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(payload));
      } on FormatException {
        continue;
      }
      frames.add(DiscordFrame(DiscordOpcode.values[opcode],
          json is Map<String, dynamic> ? json : const {}));
    }
    return frames;
  }
}

/// La pipe locale di Discord. Tutte le operazioni sono sincrone e non
/// bloccano: [read] restituisce solo i byte già arrivati.
abstract class DiscordPipe {
  /// Apre `\\.\pipe\discord-ipc-0..9`; `false` se Discord non è aperto.
  bool open();

  /// Lancia [DiscordPipeException] se la pipe è chiusa.
  void write(Uint8List bytes);

  /// Byte già arrivati (vuoto se nessuno). Lancia [DiscordPipeException] se
  /// la pipe è chiusa.
  Uint8List read();

  void close();
}

class DiscordPipeException implements Exception {
  const DiscordPipeException(this.message);
  final String message;

  @override
  String toString() => 'DiscordPipeException: $message';
}

/// Connessione a Discord per la Rich Presence: handshake, attesa di
/// `READY`, invio dell'attività.
class DiscordIpcClient {
  DiscordIpcClient(
    this._pipe, {
    required this.clientId,
    this.pollInterval = const Duration(milliseconds: 100),
    this.readyTimeout = const Duration(seconds: 5),
  }) : assert(pollInterval > Duration.zero);

  final DiscordPipe _pipe;

  /// Application ID del Discord Developer Portal.
  final String clientId;
  final Duration pollInterval;
  final Duration readyTimeout;

  final _reader = DiscordFrameReader();
  bool _connected = false;
  int _nonce = 0;
  bool _commandError = false;
  Object? _closeCode;

  bool get connected => _connected;

  /// Discord ha rifiutato l'Application ID all'handshake (close con codice
  /// 4000): riprovare non serve.
  bool get rejected => _closeCode == 4000;

  /// `true` (una volta sola) se dall'ultima chiamata Discord ha risposto
  /// `ERROR` a un comando: l'attività inviata non è stata applicata.
  bool takeCommandError() {
    final error = _commandError;
    _commandError = false;
    return error;
  }

  /// `true` quando Discord ha risposto `READY`; `false` se non è aperto,
  /// rifiuta l'Application ID o non risponde entro [readyTimeout].
  Future<bool> connect() async {
    if (!_pipe.open()) return false;
    try {
      _pipe.write(encodeDiscordFrame(
          DiscordOpcode.handshake, {'v': 1, 'client_id': clientId}));
      var waited = Duration.zero;
      while (waited < readyTimeout) {
        _reader.add(_pipe.read());
        for (final frame in _reader.takeFrames()) {
          if (frame.opcode == DiscordOpcode.frame &&
              frame.json['evt'] == 'READY') {
            _connected = true;
            return true;
          }
          if (frame.opcode == DiscordOpcode.close) {
            // Chi usa il client decide se e come segnalarlo (vedi [rejected]).
            _log.fine('Discord ha rifiutato la connessione: ${frame.json}');
            _closeCode = frame.json['code'];
            _pipe.close();
            return false;
          }
        }
        await Future<void>.delayed(pollInterval);
        waited += pollInterval;
      }
      _log.info('Discord non ha risposto all\'handshake');
    } on DiscordPipeException catch (e) {
      _log.fine('pipe di Discord: $e');
    }
    _pipe.close();
    return false;
  }

  /// Imposta l'attività, o la cancella con `null`. `false` se la
  /// connessione è caduta: il client va ricreato.
  bool setActivity(Map<String, Object?>? activity, {required int pid}) {
    if (!_connected) return false;
    try {
      _drain();
      if (!_connected) return false;
      _pipe.write(encodeDiscordFrame(DiscordOpcode.frame, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': ?activity},
        'nonce': '${++_nonce}',
      }));
      return true;
    } on DiscordPipeException catch (e) {
      _log.fine('pipe di Discord: $e');
      close();
      return false;
    }
  }

  /// Legge quello che Discord ha mandato (risponde ai ping). `false` se non
  /// connesso o se la connessione è caduta: il client va ricreato.
  bool poll() {
    if (!_connected) return false;
    try {
      _drain();
    } on DiscordPipeException catch (e) {
      _log.fine('pipe di Discord: $e');
      close();
      return false;
    }
    return _connected;
  }

  void close() {
    _connected = false;
    _pipe.close();
  }

  /// Legge quello che Discord ha mandato nel frattempo: ping, chiusura,
  /// errori sui comandi.
  void _drain() {
    _reader.add(_pipe.read());
    for (final frame in _reader.takeFrames()) {
      switch (frame.opcode) {
        case DiscordOpcode.ping:
          _pipe.write(encodeDiscordFrame(DiscordOpcode.pong, frame.json));
        case DiscordOpcode.close:
          _log.info('Discord ha chiuso la connessione: ${frame.json}');
          close();
          return;
        case DiscordOpcode.frame:
          if (frame.json['evt'] == 'ERROR') {
            _log.warning('Discord: ${frame.json['data']}');
            _commandError = true;
          }
        case DiscordOpcode.handshake:
        case DiscordOpcode.pong:
          break;
      }
    }
  }
}
