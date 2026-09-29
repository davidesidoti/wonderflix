import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// Il server chiede un `KeepAlive` entro [seconds] secondi.
final class ForceKeepAlive extends ServerEvent {
  const ForceKeepAlive(this.seconds);

  final int seconds;
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

Future<EventSocket> connectIoSocket(Uri uri, Map<String, String> headers) async =>
    _IoEventSocket(await WebSocket.connect(uri.toString(), headers: headers));

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
  int _attempt = 0;

  Stream<ServerEvent> get events => _events.stream;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  Future<void> stop() async {
    _running = false;
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
    try {
      final socket =
          await _connector(_uri, {'Authorization': _authorizationHeader()});
      if (!_running) {
        await socket.close();
        return;
      }
      _socket = socket;
      _attempt = 0;
      _subscription = socket.stream.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (Object _) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on Object {
      _scheduleReconnect();
    }
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
