import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/watch_party/party_queue_rules.dart';

import '../../support/library_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  /// e3 (p1), e4 (p2), e5 (p3), e6 (p4); in riproduzione [playingIndex].
  PlayQueue queue({int playingIndex = 1}) => testSeriesQueue(
      itemIds: const ['e3', 'e4', 'e5', 'e6'], playingIndex: playingIndex);

  List<String> ids(List<PlayQueueEntry> entries) =>
      [for (final entry in entries) entry.playlistItemId];

  test('sezioni: già visti, in riproduzione, prossimi (spec H §9.2)', () {
    final sections = partyQueueSections(queue());
    expect(ids(sections.watched), ['p1']);
    expect(sections.playing?.playlistItemId, 'p2');
    expect(ids(sections.upcoming), ['p3', 'p4']);

    final first = partyQueueSections(queue(playingIndex: 0));
    expect(first.watched, isEmpty);
    expect(ids(first.upcoming), ['p2', 'p3', 'p4']);

    final last = partyQueueSections(queue(playingIndex: 3));
    expect(ids(last.watched), ['p1', 'p2', 'p3']);
    expect(last.upcoming, isEmpty);
  });

  test('sezioni senza elemento in riproduzione: tutto tra i prossimi', () {
    final sections = partyQueueSections(queue(playingIndex: -1));
    expect(sections.watched, isEmpty);
    expect(sections.playing, isNull);
    expect(ids(sections.upcoming), ['p1', 'p2', 'p3', 'p4']);
  });

  test('indice dello spostamento: dopo l\'elemento in riproduzione', () {
    expect(partyQueueMoveIndex(queue(), 0), 2);
    expect(partyQueueMoveIndex(queue(), 1), 3);
    expect(partyQueueMoveIndex(queue(playingIndex: 0), 0), 1);
    expect(partyQueueMoveIndex(queue(playingIndex: -1), 2), 2);
    expect(partyQueueMoveIndex(queue(playingIndex: 4), 2), 2,
        reason: 'indice oltre la fine: nessun elemento in riproduzione');
  });

  test('durata dei prossimi: solo quelli noti con una durata', () {
    final items = <String, JellyfinItem?>{
      'e4': testItem(id: 'e4', runtimeMinutes: 30),
      'e5': testItem(id: 'e5', runtimeMinutes: 22),
      'e6': null,
    };
    expect(partyQueueUpcomingRuntime(queue(), items),
        const Duration(minutes: 22),
        reason: 'e4 è in riproduzione, e6 non è disponibile');
    expect(partyQueueUpcomingRuntime(queue(), const {}), isNull);
    expect(
        partyQueueUpcomingRuntime(queue(playingIndex: 3), items), isNull);
  });

  test('ordine provvisorio: vale solo con gli stessi elementi', () {
    final upcoming = partyQueueSections(queue(playingIndex: 0)).upcoming;
    expect(ids(partyQueueInOrder(upcoming, null)), ['p2', 'p3', 'p4']);
    expect(ids(partyQueueInOrder(upcoming, const ['p4', 'p2', 'p3'])),
        ['p4', 'p2', 'p3']);
    expect(ids(partyQueueInOrder(upcoming, const ['p4', 'p2'])),
        ['p2', 'p3', 'p4'], reason: 'un elemento in più nella coda');
    expect(ids(partyQueueInOrder(upcoming, const ['p4', 'p2', 'p9'])),
        ['p2', 'p3', 'p4'], reason: 'un elemento tolto');
    expect(ids(partyQueueInOrder(upcoming, const ['p2', 'p2', 'p3'])),
        ['p2', 'p3', 'p4'], reason: 'un elemento ripetuto');
  });

  test('tetto della coda', () {
    expect(partyQueueLimit, 100);
  });

  group('aggiunta (spec H §8.2)', () {
    test('posto libero e titoli già in coda', () {
      final q = queue(); // e3 già visto, e4 in corso, e5, e6
      expect(partyQueueRoom(q), partyQueueLimit - 4);
      expect(partyQueueQueuedIds(q), {'e4', 'e5', 'e6'},
          reason: 'il già visto si può riaggiungere');
      final full = testSeriesQueue(
          itemIds: [for (var i = 0; i < 101; i++) 'x$i'], playingIndex: 0);
      expect(partyQueueRoom(full), 0);
    });

    test('piano: toglie i già in coda, i doppioni e quelli in attesa, '
        'taglia al posto libero', () {
      final q = queue();
      final plan = partyQueueAddPlan(
          q, const ['e3', 'e5', 'm1', 'm1', 'm2', 'm3'],
          pending: const {'m3'});
      expect(plan.send, ['e3', 'm1', 'm2']);
      expect(plan.alreadyQueued, 2, reason: 'e5 e m3 (in attesa)');
      expect(plan.cut, 0);

      final nearlyFull = testSeriesQueue(
          itemIds: [for (var i = 0; i < 98; i++) 'x$i'], playingIndex: 0);
      final cut = partyQueueAddPlan(nearlyFull, const ['a', 'b', 'c', 'd']);
      expect(cut.send, ['a', 'b']);
      expect(cut.cut, 2);
    });

    test('cosa dice l\'avviso: un film, un episodio, episodi della stessa '
        'serie, titoli misti', () {
      final film = testItem(id: 'm1', name: 'Alien');
      JellyfinItem episode(String id, int index,
              {String series = 'Dark', String seriesId = 's1'}) =>
          testItem(
              id: id,
              name: 'E$index',
              kind: ItemKind.episode,
              seriesName: series,
              seriesId: seriesId,
              index: index,
              seasonIndex: 1);

      final one = partyQueueAddition([film]);
      expect((one.count, one.title, one.series), (1, 'Alien', null));

      final single = partyQueueAddition([episode('e1', 1)]);
      expect(single.title, 'Dark · S1:E1');

      final season = partyQueueAddition([episode('e1', 1), episode('e2', 2)]);
      expect((season.count, season.title, season.series), (2, null, 'Dark'));

      final mixed = partyQueueAddition([episode('e1', 1), film]);
      expect((mixed.count, mixed.title, mixed.series), (2, null, null));

      final twoSeries = partyQueueAddition([
        episode('e1', 1),
        episode('x1', 1, series: 'Lost', seriesId: 's2'),
      ]);
      expect(twoSeries.series, isNull);

      // Dettagli di una parte soltanto: si dice solo quanti.
      final partial = partyQueueAddition([episode('e1', 1)], count: 3);
      expect((partial.count, partial.title, partial.series), (3, null, null));
    });
  });
}
