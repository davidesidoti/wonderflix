import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'server_events.dart';

/// Nel browser gli header non si possono impostare: token e deviceId vanno in
/// query, letti a ogni connessione (il profilo può essere cambiato).
EventSocketConnector defaultEventSocketConnector({
  required String Function() token,
  required String Function() deviceId,
}) =>
    (uri, headers) {
      final ws = web.WebSocket(
          browserSocketUri(uri, token: token(), deviceId: deviceId())
              .toString());
      final opened = Completer<EventSocket>();
      final messages = StreamController<dynamic>();
      ws.onopen = (web.Event _) {
        if (!opened.isCompleted) opened.complete(_WebEventSocket(ws, messages));
      }.toJS;
      ws.onmessage = (web.MessageEvent e) {
        final data = e.data;
        if (data.isA<JSString>()) messages.add((data as JSString).toDart);
      }.toJS;
      ws.onerror = (web.Event _) {
        if (!opened.isCompleted) opened.completeError(StateError('WebSocket'));
      }.toJS;
      ws.onclose = (web.Event _) {
        if (!opened.isCompleted) opened.completeError(StateError('WebSocket'));
        if (!messages.isClosed) messages.close();
      }.toJS;
      return opened.future;
    };

class _WebEventSocket implements EventSocket {
  _WebEventSocket(this._ws, this._messages);

  final web.WebSocket _ws;
  final StreamController<dynamic> _messages;

  @override
  Stream<dynamic> get stream => _messages.stream;

  @override
  void send(String message) => _ws.send(message.toJS);

  @override
  Future<void> close() async {
    _ws.close();
    if (!_messages.isClosed) await _messages.close();
  }
}
