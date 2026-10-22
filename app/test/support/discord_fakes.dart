import 'dart:typed_data';

import 'package:wonderflix/core/discord/discord_ipc.dart';

/// Pipe di Discord in memoria: registra i frame scritti e risponde
/// all'handshake come Discord.
class FakeDiscordPipe implements DiscordPipe {
  /// Discord aperto: [open] riesce.
  bool available = true;

  /// Pipe interrotta (Discord chiuso a connessione aperta): lettura e
  /// scrittura lanciano.
  bool broken = false;

  /// Risposta all'handshake; `null` = nessuna risposta.
  ({DiscordOpcode opcode, Map<String, Object?> json})? handshakeReply = (
    opcode: DiscordOpcode.frame,
    json: {'cmd': 'DISPATCH', 'evt': 'READY'},
  );

  int opens = 0;
  bool closed = false;
  final written = <DiscordFrame>[];
  final _incoming = <int>[];

  /// Simula un frame in arrivo da Discord.
  void push(DiscordOpcode opcode, Map<String, Object?> json) =>
      _incoming.addAll(encodeDiscordFrame(opcode, json));

  List<Map<String, dynamic>> get handshakes => [
        for (final frame in written)
          if (frame.opcode == DiscordOpcode.handshake) frame.json,
      ];

  List<Map<String, dynamic>> get commands => [
        for (final frame in written)
          if (frame.opcode == DiscordOpcode.frame) frame.json,
      ];

  /// Attività inviate con SET_ACTIVITY, in ordine; `null` = cancellata.
  List<Map<String, dynamic>?> get activities => [
        for (final command in commands)
          if (command['cmd'] == 'SET_ACTIVITY')
            (command['args'] as Map<String, dynamic>)['activity']
                as Map<String, dynamic>?,
      ];

  List<int> get pids => [
        for (final command in commands)
          if (command['cmd'] == 'SET_ACTIVITY')
            (command['args'] as Map<String, dynamic>)['pid'] as int,
      ];

  @override
  bool open() {
    opens++;
    if (!available) return false;
    closed = false;
    return true;
  }

  @override
  void write(Uint8List bytes) {
    if (broken) throw const DiscordPipeException('pipe interrotta');
    final frames = (DiscordFrameReader()..add(bytes)).takeFrames();
    written.addAll(frames);
    final reply = handshakeReply;
    if (reply != null &&
        frames.any((frame) => frame.opcode == DiscordOpcode.handshake)) {
      push(reply.opcode, reply.json);
    }
  }

  @override
  Uint8List read() {
    if (broken) throw const DiscordPipeException('pipe interrotta');
    final data = Uint8List.fromList(_incoming);
    _incoming.clear();
    return data;
  }

  @override
  void close() {
    closed = true;
  }
}
