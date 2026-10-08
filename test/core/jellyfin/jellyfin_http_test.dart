import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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

    http.setCredentials(token: 'tok', deviceId: null);
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

    http.setCredentials(token: 'tok', deviceId: null);
    await expectLater(http.get('/a'), throwsA(isA<UnauthorizedException>()));
    expect(calls, 1);
  });

  test('401 per un token non più corrente non chiama onUnauthorized', () async {
    var calls = 0;
    http.onUnauthorized = () => calls++;
    http.setCredentials(token: 'A', deviceId: null);
    adapter.handler = (_) {
      // Simula un login effettuato mentre la richiesta con il vecchio
      // token era ancora in volo.
      http.setCredentials(token: 'B', deviceId: null);
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

  test('registra le richieste fallite, senza query né header', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    http.setCredentials(token: 'tok', deviceId: null);
    adapter.handler = (_) => const FakeResponse(500);

    await expectLater(http.get('/Items/x', query: {'api_key': 'k'}),
        throwsA(isA<ApiException>()));

    expect(records.single.loggerName, 'http');
    expect(records.single.level, Level.WARNING);
    expect(records.single.message, 'GET /Items/x: 500');
  });

  test('gli esiti attesi (quietStatuses) vanno nel log come info', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    adapter.handler = (_) => const FakeResponse(404);

    await expectLater(http.get('/Plugin/Info', quietStatuses: {404}),
        throwsA(isA<NotFoundException>()));
    await expectLater(http.post('/Plugin/Events', quietStatuses: {404}),
        throwsA(isA<NotFoundException>()));
    await expectLater(
        http.get('/Plugin/Info'), throwsA(isA<NotFoundException>()));
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(http.get('/Plugin/Info', quietStatuses: {404}),
        throwsA(isA<ServerErrorException>()));

    expect([
      for (final record in records)
        if (record.loggerName == 'http') (record.level, record.message),
    ], [
      (Level.INFO, 'GET /Plugin/Info: 404'),
      (Level.INFO, 'POST /Plugin/Events: 404'),
      (Level.WARNING, 'GET /Plugin/Info: 404'),
      (Level.WARNING, 'GET /Plugin/Info: 500'),
    ]);
  });

  group('credenziali del profilo (spec K §9.2)', () {
    test('token e DeviceId vanno nell\'intestazione insieme', () async {
      final adapter = FakeAdapter((_) => const FakeResponse(200, {}));
      final http = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      expect(http.deviceId, 'dev-test');

      http.setCredentials(token: 'tok-1', deviceId: 'dev-1');
      await http.get('/Users/Me');
      final header = adapter.requests.last.headers['Authorization'] as String;
      expect(header, contains('DeviceId="dev-1"'));
      expect(header, contains('Token="tok-1"'));
      expect(http.deviceId, 'dev-1');

      http.setCredentials(token: null, deviceId: null);
      await http.get('/System/Info/Public');
      final reset = adapter.requests.last.headers['Authorization'] as String;
      expect(reset, contains('DeviceId="dev-test"'));
      expect(reset, isNot(contains('Token=')));
    });

    test('withCredentials: un altro profilo, lo stesso server', () async {
      final adapter = FakeAdapter((_) => const FakeResponse(401));
      final http = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter)
        ..setCredentials(token: 'tok-attivo', deviceId: 'dev-attivo');
      var unauthorized = 0;
      http.onUnauthorized = () => unauthorized++;

      final other = http.withCredentials(token: 'tok-2', deviceId: 'dev-2');
      await expectLater(
          other.post('/Sessions/Logout'), throwsA(isA<UnauthorizedException>()));

      final header = adapter.requests.single.headers['Authorization'] as String;
      expect(header, contains('Token="tok-2"'));
      expect(header, contains('DeviceId="dev-2"'));
      expect(adapter.requests.single.uri.toString(),
          startsWith(testServerUrl.toString()));
      // Le credenziali attive restano, e il 401 di un altro profilo non fa
      // uscire nessuno.
      expect(http.token, 'tok-attivo');
      expect(http.deviceId, 'dev-attivo');
      expect(unauthorized, 0);
    });

    test('withCredentials: chiudere il client derivato non chiude l\'adattatore '
        'del principale', () async {
      final adapter =
          FakeAdapter((_) => const FakeResponse(200, {'ok': true}));
      final http = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      final other = http.withCredentials(token: 'tok-2', deviceId: 'dev-2');

      // Le richieste del derivato passano dall'adattatore del principale.
      expect(await other.get('/Users/Me'), {'ok': true});
      expect(adapter.requests, hasLength(1));

      other.dio.close();
      expect(adapter.closeCount, 0);
      // Il principale continua a funzionare...
      expect(await http.get('/Users/Me'), {'ok': true});
      expect(adapter.requests, hasLength(2));

      // ...e chiuderlo chiude l'adattatore, come prima.
      http.dio.close();
      expect(adapter.closeCount, 1);
    });
  });

  test('post con un corpo che non è JSON: il suo Content-Type', () async {
    await http.post('/UserImage', body: 'QUJD', contentType: 'image/png');

    final request = adapter.requests.last;
    expect(request.data, 'QUJD');
    expect(request.contentType, 'image/png');
  });
}
