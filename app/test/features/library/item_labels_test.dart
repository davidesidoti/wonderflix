import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/library/item_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {
  test('formatRuntime', () {
    expect(formatRuntime(const Duration(hours: 2, minutes: 46)), '2h 46m');
    expect(formatRuntime(const Duration(minutes: 45)), '45m');
    expect(formatRuntime(const Duration(hours: 2)), '2h');
  });

  test("shortDuration: minuti per eccesso sotto l'ora", () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(shortDuration(l, const Duration(minutes: 17, seconds: 1)), '18 min');
    expect(shortDuration(l, const Duration(minutes: 59, seconds: 30)), '1h');
    expect(shortDuration(l, const Duration(hours: 1, minutes: 15)), '1h 15m');
  });

  test('formatClock', () {
    expect(formatClock(const Duration(minutes: 23, seconds: 14)), '23:14');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  test('episodeCode, cardTitle, cardSubtitle', () {
    const ep = JellyfinItem(
      id: 'e',
      name: 'Please Hold',
      kind: ItemKind.episode,
      seriesName: 'The Last of Us',
      indexNumber: 4,
      parentIndexNumber: 1,
    );
    const movie = JellyfinItem(
        id: 'm', name: 'Dune', kind: ItemKind.movie, productionYear: 2024);
    expect(episodeCode(ep), 'S1:E4');
    expect(cardTitle(ep), 'The Last of Us');
    expect(cardSubtitle(ep), 'S1:E4 · Please Hold');
    expect(cardTitle(movie), 'Dune');
    expect(cardSubtitle(movie), '2024');
    expect(episodeCode(movie), isNull);
  });

  test('riga del titolo', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(
      itemContextLine(
        l,
        testItem(
          kind: ItemKind.episode,
          name: 'La scatola',
          seriesName: "L'Istituto",
          seasonIndex: 1,
          index: 4,
        ),
      ),
      "L'Istituto · S1:E4 La scatola",
    );
    expect(
      itemContextLine(
        l,
        testItem(kind: ItemKind.season, name: 'Stagione 1', seriesName: "L'Istituto"),
      ),
      "L'Istituto · Stagione 1",
    );
    expect(itemContextLine(l, testItem(name: 'The Wrestler', year: 2008)),
        'The Wrestler · Film · 2008');
    expect(
      itemContextLine(l, testItem(kind: ItemKind.series, name: "L'Istituto", year: 2025)),
      "L'Istituto · Serie · 2025",
    );
    expect(itemContextLine(l, testItem(name: 'Senza anno', year: null)), 'Senza anno · Film');
  });
}
