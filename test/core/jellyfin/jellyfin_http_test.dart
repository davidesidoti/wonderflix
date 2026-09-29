import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late JellyfinHttp http;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'ok': true}));
    http = JellyfinHttp(
      baseUrl: Uri.parse('https://media.example.com/jf'),
      clientInfo: testClientInfo,
      adapter: adapter,
    );
  });

  test('unisce indirizzo base e percorso', () async {
    await http.get('/Users/Me');
    expect(adapter.requests.single.uri.toString(),
        'https://media.example.com/jf/Users/Me');
  });

  test('invia l\'header Authorization, con token solo se presente', () async {
    await http.get('/a');
    expect(adapter.requests.last.headers['Authorization'],
        isNot(contains('Token=')));

    http.token = 'tok';
    await http.get('/a');
    expect(adapter.requests.last.headers['Authorization'],
        contains('Token="tok"'));
  });

  test('restituisce il JSON decodificato', () async {
    expect(await http.get('/a'), {'ok': true});
  });

  test('401 diventa UnauthorizedException e chiama onUnauthorized se c\'è un token',
      () async {
    var calls = 0;
    http.onUnauthorized = () => calls++;
    adapter.handler = (_) => const FakeResponse(401);

    await expectLater(http.get('/a'), throwsA(isA<UnauthorizedException>()));
    expect(calls, 0, reason: 'senza token non è una sessione scaduta');

    http.token = 'tok';
    await expectLater(http.get('/a'), throwsA(isA<UnauthorizedException>()));
    expect(calls, 1);
  });

  test('401 per un token non più corrente non chiama onUnauthorized', () async {
    var calls = 0;
    http.onUnauthorized = () => calls++;
    http.token = 'A';
    adapter.handler = (_) {
      // Simula un login effettuato mentre la richiesta con il vecchio
      // token era ancora in volo.
      http.token = 'B';
      return const FakeResponse(401);
    };

    await expectLater(http.get('/a'), throwsA(isA<UnauthorizedException>()));
    expect(calls, 0, reason: 'il 401 riguarda un token ormai sostituito');
  });

  test('403, 404 e 500 vengono mappati', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(http.get('/a'), throwsA(isA<ForbiddenException>()));
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(http.get('/a'), throwsA(isA<NotFoundException>()));
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(
      http.get('/a'),
      throwsA(isA<ServerErrorException>()
          .having((e) => e.statusCode, 'statusCode', 500)),
    );
  });

  test('errore di rete diventa ServerUnreachableException', () async {
    adapter.handler = (_) => throw const SocketException('down');
    await expectLater(
        http.get('/a'), throwsA(isA<ServerUnreachableException>()));
  });

  test('asJsonMap rifiuta risposte che non sono oggetti', () {
    expect(asJsonMap({'a': 1}), {'a': 1});
    expect(() => asJsonMap(null), throwsA(isA<ServerErrorException>()));
  });

  test('delete usa il metodo DELETE', () async {
    await http.delete('/UserFavoriteItems/i1', query: {'userId': 'u1'});
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.queryParameters, {'userId': 'u1'});
  });

  test('richiesta annullata diventa RequestCancelledException', () async {
    final token = CancelToken()..cancel();
    await expectLater(http.get('/a', cancelToken: token),
        throwsA(isA<RequestCancelledException>()));
  });
}
