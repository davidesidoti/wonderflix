import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../party_channel/party_channel_models.dart';
import '../syncplay/syncplay_models.dart';
import 'item_models.dart';

sealed class ServerEvent {
  const ServerEvent();
}

/// Dati utente cambiati (anche da altri dispositivi), per id elemento.
final class UserDataChanged extends ServerEvent {
  const UserDataChanged(this.userId, this.changes);

  final String userId;
  final Map<String, UserItemData> changes;
}

final class LibraryChanged extends ServerEvent {
  const LibraryChanged();
}

/// Socket stabilito. [isReconnect] è `false` per la prima connessione dopo
/// `start()`, `true` per le successive: nel frattempo potremmo aver perso
/// eventi.
final class ServerConnected extends ServerEvent {
  const ServerConnected(this.isReconnect);

  final bool isReconnect;
}

/// Il server chiede un `KeepAlive` entro [seconds] secondi.
final class ForceKeepAlive extends ServerEvent {
  const ForceKeepAlive(this.seconds);

  final int seconds;
}

/// Comando del gruppo SyncPlay di cui facciamo parte.
final class SyncPlayCommandReceived extends ServerEvent {
  const SyncPlayCommandReceived(this.command);

  final SyncPlayCommand command;
}

/// Aggiornamento del gruppo SyncPlay (membri, stato, coda, errori).
final class SyncPlayGroupUpdated extends ServerEvent {
  const SyncPlayGroupUpdated(this.update);

  final GroupUpdate update;
}

/// Evento del plugin "WonderFlix Watch Party" (spec E §7.1): il JSON
/// dell'evento timbrato, da leggere con `parsePartyEvent`.
final class PartyChannelReceived extends ServerEvent {
  const PartyChannelReceived(this.payload);

  final String payload;
}

/// Messaggio del WebSocket → evento; `null` per messaggi ignorati o non validi.
ServerEvent? parseServerMessage(Object? raw) {
  if (raw is! String) return null;
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    final data = json['Data'];
    switch (json['MessageType']) {
      case 'UserDataChanged':
        if (data is! Map<String, dynamic>) return null;
        final list = (data['UserDataList'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        return UserDataChanged(data['UserId'] as String? ?? '', {
          for (final entry in list)
            if (entry['ItemId'] is String)
              entry['ItemId'] as String: UserItemData.fromJson(entry),
        });
      case 'LibraryChanged':
        return const LibraryChanged();
      case 'ForceKeepAlive':
        return ForceKeepAlive((data as num?)?.toInt() ?? 60);
      case 'SyncPlayCommand':
        if (data is! Map<String, dynamic>) return null;
        final command = SyncPlayCommand.fromJson(data);
        return command == null ? null : SyncPlayCommandReceived(command);
      case 'SyncPlayGroupUpdate':
        final update = parseGroupUpdate(data);
        return update == null ? null : SyncPlayGroupUpdated(update);
      case 'GeneralCommand':
        // Il plugin del watch party inoltra i suoi eventi come `SendString`
        // con una chiave sua (spec E §6.3). Gli altri comandi non ci
        // riguardano.
        if (data is! Map<String, dynamic> || data['Name'] != 'SendString') {
          return null;
        }
        final arguments = data['Arguments'];
        final payload = arguments is Map<String, dynamic>
            ? arguments[partyChannelArgumentKey]
            : null;
        return payload is String ? PartyChannelReceived(payload) : null;
      default:
        return null;
    }
  } on Object {
    return null;
  }
}

Uri socketUri(Uri serverUrl) => serverUrl.replace(
      scheme: serverUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '${serverUrl.path}/socket',
    );

/// Connessione minima di cui ha bisogno il client (sostituibile nei test).
abstract interface class EventSocket {
  Stream<dynamic> get stream;
  void send(String message);
  Future<void> close();
}

typedef EventSocketConnector = Future<EventSocket> Function(
    Uri uri, Map<String, String> headers);

Future<EventSocket> connectIoSocket(Uri uri, Map<String, String> headers) async {
  final ws = await WebSocket.connect(uri.toString(), headers: headers);
  // Ping di livello protocollo: rileva le connessioni cadute in silenzio.
  ws.pingInterval = const Duration(seconds: 30);
  return _IoEventSocket(ws);
}

class _IoEventSocket implements EventSocket {
  _IoEventSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}

/// Client WebSocket di Jellyfin: riconnessione automatica e keep-alive.
class ServerEventsClient {
  ServerEventsClient({
    required Uri serverUrl,
    required String Function() authorizationHeader,
    EventSocketConnector connector = connectIoSocket,
    List<Duration> retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
  })  : _uri = socketUri(serverUrl),
        _authorizationHeader = authorizationHeader,
        _connector = connector,
        _retryDelays = retryDelays;

  final Uri _uri;
  final String Function() _authorizationHeader;
  final EventSocketConnector _connector;
  final List<Duration> _retryDelays;
  final _events = StreamController<ServerEvent>.broadcast();

  EventSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepAlive;
  Timer? _retry;
  bool _running = false;
  bool _hasConnected = false;
  int _attempt = 0;

  /// Cambia a ogni `start()`/`stop()`: le connessioni e i callback di un ciclo
  /// precedente si riconoscono e vengono ignorati.
  int _epoch = 0;

  Stream<ServerEvent> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    _hasConnected = false;
    _epoch++;
    unawaited(_connect());
  }

  Future<void> stop() async {
    _running = false;
    _epoch++;
    _retry?.cancel();
    _keepAlive?.cancel();
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    // Avvia entrambe le operazioni prima di attendere: la chiusura del socket
    // non deve dipendere dal completamento della cancellazione.
    final cancelling = subscription?.cancel();
    final closing = socket?.close();
    await cancelling;
    await closing;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<void> _connect() async {
    if (!_running) return;
    final epoch = _epoch;
    try {
      final socket =
          await _connector(_uri, {'Authorization': _authorizationHeader()});
      if (epoch != _epoch || !_running) {
        await socket.close();
        return;
      }
      _socket = socket;
      _attempt = 0;
      _subscription = socket.stream.listen(
        _onMessage,
        onDone: () => _onClosed(epoch),
        onError: (Object _) => _onClosed(epoch),
        cancelOnError: true,
      );
      final isReconnect = _hasConnected;
      _hasConnected = true;
      if (!_events.isClosed) _events.add(ServerConnected(isReconnect));
    } on Object {
      if (epoch == _epoch) _scheduleReconnect();
    }
  }

  void _onClosed(int epoch) {
    if (epoch == _epoch) _scheduleReconnect();
  }

  void _onMessage(dynamic raw) {
    final event = parseServerMessage(raw);
    if (event == null) return;
    if (event is ForceKeepAlive) _startKeepAlive(event.seconds);
    if (!_events.isClosed) _events.add(event);
  }

  void _startKeepAlive(int seconds) {
    _keepAlive?.cancel();
    final period = Duration(seconds: (seconds ~/ 2).clamp(5, 60));
    _sendKeepAlive();
    _keepAlive = Timer.periodic(period, (_) => _sendKeepAlive());
  }

  void _sendKeepAlive() =>
      _socket?.send(jsonEncode({'MessageType': 'KeepAlive'}));

  void _scheduleReconnect() {
    _keepAlive?.cancel();
    _socket = null;
    _subscription = null;
    if (!_running) return;
    final delay = _retryDelays[min(_attempt, _retryDelays.length - 1)];
    _attempt++;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(_connect()));
  }
}
