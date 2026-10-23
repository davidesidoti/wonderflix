import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'api_exception.dart';

/// POST con `fetch` e `keepalive`: il browser lo completa anche se la scheda
/// si chiude. Lancia solo [ApiException].
Future<void> keepalivePost(
    Uri url, Map<String, String> headers, String jsonBody) async {
  final web.Response response;
  try {
    response = await web.window
        .fetch(
          url.toString().toJS,
          web.RequestInit(
            method: 'POST',
            headers: headers.jsify()! as web.HeadersInit,
            body: jsonBody.toJS,
            keepalive: true,
          ),
        )
        .toDart;
  } on Object catch (error) {
    throw ServerUnreachableException(error);
  }
  if (!response.ok) throw ServerErrorException(response.status);
}
