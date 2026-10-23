import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/video/text_subtitle_cache.dart';

/// Risposta del server: stato e testo così com'è (non JSON).
typedef _Answer = (int, String);

const _srt = '1\n00:00:01,000 --> 00:00:02,000\nCiao\n';

class _TextAdapter implements HttpClientAdapter {
  FutureOr<_Answer> Function() handler = () => (200, _srt);
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = await handler();
    return ResponseBody.fromString(body, status);
  }

  @override
  void close({bool force = false}) {}
}

const _url =
    'https://jf.example/Videos/1/2/Subtitles/6/0/Stream.subrip?ApiKey=t';

void main() {
  late _TextAdapter adapter;
  late TextSubtitleCache cache;

  setUp(() {
    adapter = _TextAdapter();
    cache = TextSubtitleCache(dio: Dio()..httpClientAdapter = adapter);
  });

  test('una risposta lenta del server si aspetta una volta sola', () async {
    // Alla prima richiesta Jellyfin estrae tutti i sottotitoli del file:
    // anche minuti. Chi la chiede di nuovo intanto non ne fa un'altra.
    final answer = Completer<_Answer>();
    adapter.handler = () => answer.future;
    final first = cache.load(_url, const {'Authorization': 'MediaBrowser x'});
    final second = cache.load(_url, const {});
    answer.complete((200, _srt));
    expect((await first).single.text, 'Ciao');
    expect(await second, same(await first));
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.toString(), _url);
    expect(adapter.requests.single.headers['Authorization'], 'MediaBrowser x');
  });

  test('un download fallito si riprova alla richiesta dopo', () async {
    adapter.handler = () => (500, '');
    await expectLater(
        cache.load(_url, const {}), throwsA(isA<DioException>()));
    adapter.handler = () => (200, _srt);
    expect((await cache.load(_url, const {})).single.text, 'Ciao');
    expect(adapter.requests, hasLength(2));
  });

  test('clear dimentica i sottotitoli scaricati', () async {
    await cache.load(_url, const {});
    await cache.load(_url, const {});
    expect(adapter.requests, hasLength(1));
    cache.clear();
    await cache.load(_url, const {});
    expect(adapter.requests, hasLength(2));
  });
}
