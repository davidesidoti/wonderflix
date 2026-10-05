import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late JellyfinHttp http;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    http = JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
  });

  test('403 e 409 portano il corpo della risposta (spec I §7.3)', () async {
    adapter.handler = (_) => const FakeResponse(403, {'Code': 'QuotaExceeded'});
    await expectLater(
        http.get('/x'),
        throwsA(isA<ForbiddenException>()
            .having((e) => e.body, 'body', {'Code': 'QuotaExceeded'})));

    adapter.handler = (_) => const FakeResponse(409, {'Code': 'AlreadyRequested'});
    await expectLater(
        http.post('/x'),
        throwsA(isA<ServerErrorException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.body, 'body', {'Code': 'AlreadyRequested'})));
  });

  test('senza corpo il campo è vuoto', () async {
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(
        http.get('/x'),
        throwsA(isA<ServerErrorException>()
            .having((e) => e.body, 'body', anyOf(isNull, ''))));
  });
}
