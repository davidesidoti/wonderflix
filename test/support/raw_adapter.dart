import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Adapter dio che risponde sempre con gli stessi byte (testo o file).
class RawAdapter implements HttpClientAdapter {
  RawAdapter(this.bytes,
      {this.status = 200, this.contentType = 'application/octet-stream'});

  final List<int> bytes;
  final int status;
  final String contentType;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(bytes, status, headers: {
      Headers.contentTypeHeader: [contentType],
      Headers.contentLengthHeader: ['${bytes.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}
