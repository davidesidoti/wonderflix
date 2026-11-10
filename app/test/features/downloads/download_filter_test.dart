import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/features/downloads/download_filter.dart';

DownloadItem row(
  String key, {
  String title = 'Serie · S01E01',
  DownloadKind kind = DownloadKind.episode,
  DownloadState state = DownloadState.waiting,
  int? seriesId = 7,
  bool canRush = true,
  bool rush = false,
}) =>
    DownloadItem(
      key: key,
      kind: kind,
      title: title,
      posterUrl: 'poster-$key',
      state: state,
      availableSince: DateTime.utc(2026, 11, 1),
      seriesId: seriesId,
      canRush: canRush,
      rush: rush,
    );

void main() {
  test('titleMatches ignores case, accents and surrounding spaces', () {
    expect(titleMatches('Pokémon · S01E02', 'pokemon'), isTrue);
    expect(titleMatches('Dune (2021)', '  DUNE '), isTrue);
    expect(titleMatches('Dune (2021)', 'arrival'), isFalse);
    expect(titleMatches('Dune (2021)', ''), isTrue);
    expect(titleMatches('Pokemon', 'pokémon'), isTrue);
    expect(titleMatches('Ōkami · S01E01', 'okami'), isTrue);
  });

  group('rushGroups', () {
    test('episodes of one series make one group counting all rows', () {
      final groups = rushGroups(
          [row('a'), row('b', title: 'Serie · S01E02'), row('c')], '');
      expect(groups, hasLength(1));
      expect(groups.single.title, 'Serie');
      expect(groups.single.missing, 3);
      expect(groups.single.posterUrl, 'poster-a');
    });

    test('missing leaves out rows that cannot be rushed', () {
      final groups = rushGroups([
        row('a'),
        row('b', rush: true),
        row('c', state: DownloadState.downloading, canRush: false),
        row('d', state: DownloadState.upgradeWatch, canRush: false),
      ], '');
      expect(groups.single.missing, 2);
    });

    test('the poster is the first one the group has', () {
      final group = rushGroups([
        DownloadItem(
          key: 'a',
          kind: DownloadKind.episode,
          title: 'Serie · S01E01',
          state: DownloadState.waiting,
          availableSince: DateTime.utc(2026, 11, 1),
          seriesId: 7,
          canRush: true,
        ),
        row('b'),
      ], '').single;
      expect(group.posterUrl, 'poster-b');
    });

    test('the series name is what comes before the last separator', () {
      final groups = rushGroups([row('a', title: 'A · B · S01E01')], '');
      expect(groups.single.title, 'A · B');
    });

    test('a filter matching one row still counts the whole group', () {
      final groups = rushGroups([
        row('a', title: 'Serie · S01E01'),
        row('b', title: 'Serie · S01E02'),
        row('c', title: 'Serie · S02E01'),
      ], 'S02');
      expect(groups.single.missing, 3);
    });

    test('a group with nothing matching is left out', () {
      expect(rushGroups([row('a')], 'altro'), isEmpty);
    });

    test('rows needing you can be pressed', () {
      final groups = rushGroups([
        row('a', state: DownloadState.needsYou),
        row('b', state: DownloadState.needsYou),
      ], '');
      expect(groups.single.canPress, isTrue);
      expect(groups.single.pending, isFalse);
    });

    test('rows only downloading, with no canRush or rush, make no group', () {
      expect(
          rushGroups([
            row('a', state: DownloadState.downloading, canRush: false),
          ], ''),
          isEmpty);
    });

    test('rows already rushed are pending and cannot be pressed', () {
      final groups =
          rushGroups([row('a', rush: true), row('b', rush: true)], '');
      expect(groups.single.pending, isTrue);
      expect(groups.single.canPress, isFalse);
    });

    test('a mix of rushed and free rows can still be pressed', () {
      final groups = rushGroups([row('a', rush: true), row('b')], '');
      expect(groups.single.canPress, isTrue);
      expect(groups.single.pending, isFalse);
      expect(groups.single.key, 'b');
    });

    test('a rushed row without canRush keeps the group visible', () {
      final groups = rushGroups([row('a', canRush: false, rush: true)], '');
      expect(groups.single.pending, isTrue);
    });

    test('a movie is a single group with its whole title', () {
      final groups = rushGroups([
        row('m1',
            title: 'Dune · Parte due',
            kind: DownloadKind.movie,
            seriesId: null),
        row('m2', title: 'Arrival', kind: DownloadKind.movie, seriesId: null),
      ], '');
      expect(groups.map((g) => g.title), ['Dune · Parte due', 'Arrival']);
      expect(groups.map((g) => g.missing), [1, 1]);
    });

    test('same-named series with different ids are two groups', () {
      final groups = rushGroups([
        row('a', seriesId: 1),
        row('b', seriesId: 2),
        row('c', seriesId: 1),
      ], '');
      expect(groups, hasLength(2));
      expect(groups.map((g) => g.missing), [2, 1]);
    });

    test('the key is a canRush row of the group', () {
      final groups = rushGroups([
        row('a', canRush: false),
        row('b', rush: true),
        row('c'),
      ], '');
      expect(groups.single.key, 'c');
    });
  });
}
