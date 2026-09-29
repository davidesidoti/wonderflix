import 'dart:io';

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
}
