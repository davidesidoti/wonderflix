import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/rating_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SocialApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SocialApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('apre la votazione', () async {
    adapter.handler = (_) => FakeResponse(200, ratingRoundJson(itemId: 'e4'));
    final round = await api.openRatingRound('g1', 'e4');
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Ratings/Rounds');
    expect(request.data, {'GroupId': 'g1', 'ItemId': 'e4'});
    expect(round.itemId, 'e4');
    expect(round.phase, RatingPhase.voting);
  });

  test('legge la votazione; {} vuol dire nessuna', () async {
    adapter.handler = (_) => FakeResponse(200, ratingRoundJson());
    expect((await api.ratingRound('g1'))!.groupId, 'g1');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/WonderFlixWatchParty/Ratings/Rounds/g1');

    adapter.handler = (_) => const FakeResponse(200, <String, dynamic>{});
    expect(await api.ratingRound('g1'), isNull);
  });

  test('voto, salta, scopri', () async {
    adapter.handler = (_) => FakeResponse(200, ratingRoundJson());
    await api.voteInRound('g1', 8, null);
    var request = adapter.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Ratings/Rounds/g1/Vote');
    expect(request.data, {'Score': 8, 'Comment': null});

    await api.skipRound('g1');
    expect(adapter.requests.last.path,
        '/WonderFlixWatchParty/Ratings/Rounds/g1/Skip');

    final revealed = await api.revealRound('g1');
    request = adapter.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Ratings/Rounds/g1/Reveal');
    expect(revealed, isA<RatingRound>());
  });

  test('voti della scheda, voto e togli voto', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'CanRate': true,
          'Count': 0,
          'Friends': <Object>[],
        });
    final ratings = await api.itemRatings('m1');
    var request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/WonderFlixWatchParty/Ratings');
    expect(request.queryParameters['itemId'], 'm1');
    expect(ratings.canRate, isTrue);

    adapter.handler = (_) => const FakeResponse(204);
    await api.rate('m1', 7, 'Bello');
    request = adapter.requests.last;
    expect(request.method, 'PUT');
    expect(request.path, '/WonderFlixWatchParty/Ratings/m1');
    expect(request.data, {'Score': 7, 'Comment': 'Bello'});

    await api.deleteRating('m1');
    request = adapter.requests.last;
    expect(request.method, 'DELETE');
    expect(request.path, '/WonderFlixWatchParty/Ratings/m1');
  });

  test('errori', () async {
    Future<void> expectFailure(int status, SocialFailure failure) async {
      adapter.handler = (_) => FakeResponse(status);
      await expectLater(
          api.voteInRound('g1', 8, null),
          throwsA(isA<SocialException>()
              .having((e) => e.failure, 'failure', failure)));
    }

    await expectFailure(400, SocialFailure.forbidden);
    await expectFailure(409, SocialFailure.conflict);
    await expectFailure(429, SocialFailure.rateLimited);
    await expectFailure(404, SocialFailure.unavailable);
  });
}
