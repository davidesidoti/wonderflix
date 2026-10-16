import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/match/match_queue.dart';
import 'package:wonderflix/features/watch_party/party_queue.dart';
import 'package:wonderflix/features/watch_party/party_queue_rules.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';

void main() {
  group('matchPartyOrder', () {
    test('theChosenTitleGoesFirst', () {
      final state = testMatchState(
          matches: ['a', 'b'],
          nearMatches: [const MatchNearMatch(itemId: 'n', yes: 1, of: 2)]);
      expect(matchPartyOrder(state), ['a', 'b']);
      expect(matchPartyOrder(state, first: 'b'), ['b', 'a']);
      expect(matchPartyOrder(state, first: 'n'), ['n', 'a', 'b']);
      expect(matchPartyOrder(state, first: 'x'), ['a', 'b']);
      expect(
          matchPartyOrder(testMatchState(nearMatches: [
            const MatchNearMatch(itemId: 'n', yes: 1, of: 2),
            const MatchNearMatch(itemId: 'o', yes: 1, of: 2),
          ])),
          ['n']);
      expect(matchPartyOrder(testMatchState()), isEmpty);
    });
  });

  group('buildMatchQueue', () {
    late FakeLibraryApi library;
    JellyfinItem episode(String id, String series, int season) => testItem(
        id: id, kind: ItemKind.episode, seriesId: series, seasonIndex: season);
    JellyfinItem series(String id) => testItem(id: id, kind: ItemKind.series);

    setUp(() => library = FakeLibraryApi());

    Future<List<String>> queueOf(List<JellyfinItem> titles) async =>
        (await buildMatchQueue(library, 'u1', titles)).queue;

    test('aSeriesFirstStartsFromItsFirstEpisodeWithTheFollowing', () async {
      library.seriesEpisodes['s1'] = [
        episode('e0', 's1', 0),
        episode('e1', 's1', 1),
        episode('e2', 's1', 1),
        episode('e3', 's1', 1),
      ];
      expect(await queueOf([series('s1'), testItem(id: 'f1')]),
          ['e1', 'e2', 'e3', 'f1']);
      library.seriesEpisodes['s2'] = [
        for (var i = 0; i < 60; i++) episode('x$i', 's2', 1),
      ];
      expect((await queueOf([series('s2')])).length, maxPartyQueue);
    });

    test('laterTitlesAddOneItemEach', () async {
      library.seriesEpisodes['s2'] = [
        episode('e1', 's2', 1),
        episode('e2', 's2', 1),
      ];
      expect(await queueOf([testItem(id: 'f0'), testItem(id: 'f1'), series('s2')]),
          ['f0', 'f1', 'e1']);
    });

    test('aSeriesWithoutEpisodesIsSkipped', () async {
      final built = await buildMatchQueue(
          library, 'u1', [series('s1'), testItem(id: 'f1')]);
      expect(built.queue, ['f1']);
      // Il titolo da cui parte la coda, non la serie saltata.
      expect(built.head?.id, 'f1');
      final none = await buildMatchQueue(library, 'u1', [series('s1')]);
      expect(none.queue, isEmpty);
      expect(none.head, isNull);
    });

    test('theQueueStopsAtTheLimit', () async {
      library.seriesEpisodes['s1'] = [
        for (var i = 0; i < 50; i++) episode('e$i', 's1', 1),
      ];
      final titles = [
        series('s1'),
        for (var i = 0; i < 60; i++) testItem(id: 'f$i'),
      ];
      expect((await queueOf(titles)).length, partyQueueLimit);
    });
  });
}
