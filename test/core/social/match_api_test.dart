import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/match_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

const _state = {
  'RoomId': 'r1',
  'Rev': 2,
  'Phase': 'Waiting',
  'CreatorId': 'u1',
  'CreatorName': 'Mario',
  'Members': [
    {'UserId': 'u1', 'Name': 'Mario', 'Voted': 0},
  ],
  'Stack': [],
  'Matches': [],
  'NearMatches': [],
};

void main() {
  late FakeAdapter adapter;
  late MatchApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, _state));
    api = MatchApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  ({String method, String path, Object? data}) last() {
    final request = adapter.requests.last;
    return (method: request.method, path: request.path, data: request.data);
  }

  test('apertura, stato, ingresso, inizio e altri 30 danno lo stato', () async {
    expect((await api.open()).roomId, 'r1');
    expect(last(), (method: 'POST', path: '/WonderFlixWatchParty/Match', data: null));

    expect((await api.state('r1')).rev, 2);
    expect(last().method, 'GET');
    expect(last().path, '/WonderFlixWatchParty/Match/r1');

    await api.join('r1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Join');

    await api.start('r1', type: 'movies', duration: '90', genre: 'Horror');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Start');
    expect(last().data, {'Type': 'movies', 'Duration': '90', 'Genre': 'Horror'});

    await api.start('r1', type: 'both', duration: 'any');
    expect(last().data, {'Type': 'both', 'Duration': 'any', 'Genre': null});

    await api.more('r1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/More');
  });

  test('inviti, uscita, voto e party', () async {
    adapter.handler = (_) => const FakeResponse(204);

    await api.invite('r1', ['u2', 'u3']);
    expect(last().method, 'POST');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Invites');
    expect(last().data, {'UserIds': ['u2', 'u3']});

    await api.leave('r1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Leave');

    await api.vote('r1', 'm1', yes: false);
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Votes');
    expect(last().data, {'ItemId': 'm1', 'Yes': false});

    await api.party('r1', 'g1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Party');
    expect(last().data, {'GroupId': 'g1'});
  });

  Future<MatchException> failure(FakeResponse response) async {
    adapter.handler = (_) => response;
    try {
      await api.join('r1');
    } on MatchException catch (error) {
      return error;
    }
    fail('nessuna eccezione');
  }

  test('i 409 dicono il motivo; InAnotherRoom anche la propria sala',
      () async {
    final another = await failure(const FakeResponse(
        409, {'Reason': 'InAnotherRoom', 'RoomId': 'r9'}));
    expect(another.failure, MatchFailure.inAnotherRoom);
    expect(another.roomId, 'r9');

    const reasons = {
      'NotMember': MatchFailure.notMember,
      'NotCreator': MatchFailure.notCreator,
      'Started': MatchFailure.started,
      'Closed': MatchFailure.closed,
      'Full': MatchFailure.full,
      'NotInvited': MatchFailure.notInvited,
      'NotEnoughMembers': MatchFailure.notEnoughMembers,
      'NotStarted': MatchFailure.notStarted,
      'NotNext': MatchFailure.notNext,
      'NotFinished': MatchFailure.notFinished,
      'NotYourParty': MatchFailure.notYourParty,
      'Boh': MatchFailure.conflict,
    };
    for (final MapEntry(:key, :value) in reasons.entries) {
      final error = await failure(FakeResponse(409, {'Reason': key}));
      expect(error.failure, value, reason: key);
      expect(error.roomId, isNull, reason: key);
    }
    expect((await failure(const FakeResponse(409))).failure,
        MatchFailure.conflict);
  });

  test('gli altri errori', () async {
    expect((await failure(const FakeResponse(404))).failure,
        MatchFailure.unavailable);
    expect((await failure(const FakeResponse(400))).failure,
        MatchFailure.invalid);
    expect((await failure(const FakeResponse(403))).failure,
        MatchFailure.invalid);
    expect((await failure(const FakeResponse(429))).failure,
        MatchFailure.rateLimited);
    expect((await failure(const FakeResponse(500))).failure,
        MatchFailure.network);
    expect((await failure(const FakeResponse(200, ['non', 'uno', 'stato'])))
        .failure, MatchFailure.network);
  });
}
