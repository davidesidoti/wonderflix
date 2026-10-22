import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class FakeResponse {
  const FakeResponse(this.status, [this.body]);
  final int status;
  final Object? body;
}

/// Una risposta subito, o un `Future` per una risposta che arriva più tardi.
typedef FakeHandler = FutureOr<FakeResponse> Function(RequestOptions options);

/// Adapter dio che non va in rete: registra le richieste e risponde con [handler].
/// Se [handler] lancia un'eccezione (es. SocketException), dio la riceve come
/// errore di rete.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  FakeHandler handler;
  final requests = <RequestOptions>[];

  /// Quante volte è stato chiuso.
  int closeCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final answer = handler(options);
    final response = answer is FakeResponse ? answer : await answer;
    // Come un vero 204: nessun corpo e nessun content-type.
    if (response.body == null) {
      return ResponseBody.fromString('', response.status);
    }
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) => closeCount++;
}
