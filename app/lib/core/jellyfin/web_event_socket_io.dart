import 'dart:io';

import 'server_events.dart';

EventSocketConnector defaultEventSocketConnector({
  required String Function() token,
  required String Function() deviceId,
}) =>
    connectIoSocket;

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
