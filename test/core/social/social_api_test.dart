import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SocialApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SocialApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('info', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Version': '1.1.0',
          'Protocol': 1,
          'Features': ['friends'],
        });
    final info = await api.info();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Info');
    expect(info.features, {'friends'});
  });

  test('amici', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'Party': null},
          ],
          'Incoming': [],
          'Outgoing': [],
        });
    final snapshot = await api.friends();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Friends');
    expect(snapshot.friends.single.name, 'Luigi');
  });

  test('ricerca', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'None'},
        ]);
    final results = await api.search('lui');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Users/Search');
    expect(adapter.requests.single.queryParameters, {'q': 'lui'});
    expect(results.single.relation, FriendRelation.none);
  });

  test('azioni', () async {
    await api.request('u2');
    await api.accept('u2');
    await api.decline('u2');
    await api.cancel('u2');
    await api.remove('u2');
    expect(
        adapter.requests.map((r) => '${r.method} ${r.path}'),
        [
          'POST /WonderFlixWatchParty/Friends/Requests/u2',
          'POST /WonderFlixWatchParty/Friends/Requests/u2/Accept',
          'POST /WonderFlixWatchParty/Friends/Requests/u2/Decline',
          'DELETE /WonderFlixWatchParty/Friends/Requests/u2',
          'DELETE /WonderFlixWatchParty/Friends/u2',
        ]);
  });

  test('errori', () async {
    Future<SocialFailure?> failureOf(FakeResponse response) async {
      adapter.handler = (_) => response;
      try {
        await api.request('u2');
        return null;
      } on SocialException catch (error) {
        return error.failure;
      }
    }

    expect(await failureOf(const FakeResponse(404)), SocialFailure.unavailable);
    expect(await failureOf(const FakeResponse(400)), SocialFailure.forbidden);
    expect(await failureOf(const FakeResponse(403)), SocialFailure.forbidden);
    expect(await failureOf(const FakeResponse(409)), SocialFailure.conflict);
    expect(
        await failureOf(const FakeResponse(429)), SocialFailure.rateLimited);
    expect(await failureOf(const FakeResponse(500)), SocialFailure.network);
    adapter.handler = (_) => throw const SocketException('giù');
    await expectLater(
        api.friends(),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.network)));
    adapter.handler = (_) => const FakeResponse(200, {'Version': 3});
    await expectLater(
        api.info(),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.network)));
  });

  test('esiti previsti nel log come info, il resto come avviso', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    // Accettare una richiesta già annullata è una corsa normale (403).
    for (final status in [403, 404, 409, 429, 500]) {
      adapter.handler = (_) => FakeResponse(status);
      await expectLater(
          api.accept('u2'), throwsA(isA<SocialException>()));
    }

    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], [Level.INFO, Level.INFO, Level.INFO, Level.INFO, Level.WARNING]);
  });
}
