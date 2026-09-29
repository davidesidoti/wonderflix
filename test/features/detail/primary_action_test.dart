import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/detail/primary_action.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('film non iniziato → Riproduci', () {
    final movie = testItem();
    final action = primaryActionFor(movie, movie.userData);
    expect(action, isA<PlayAction>());
    expect(primaryActionLabel(l, action), 'Riproduci');
  });

  test('film iniziato → Riprendi da mm:ss', () {
    final movie = testItem(positionTicks: 13940000000, playedPercentage: 20);
    final action = primaryActionFor(movie, movie.userData);
    expect(action, isA<ResumeAction>());
    expect(primaryActionLabel(l, action), 'Riprendi da 23:14');
  });

  test('film già visto → Riproduci', () {
    final movie = testItem(played: true, positionTicks: 100);
    expect(primaryActionFor(movie, movie.userData), isA<PlayAction>());
  });

  test('episodio: codice nella label', () {
    final ep = testItem(id: 'e5', kind: ItemKind.episode, index: 5, seasonIndex: 1);
    expect(primaryActionLabel(l, primaryActionFor(ep, ep.userData)),
        'Riproduci S1:E5');
    final started = testItem(
        id: 'e4',
        kind: ItemKind.episode,
        index: 4,
        seasonIndex: 1,
        positionTicks: 13940000000,
        playedPercentage: 50);
    expect(primaryActionLabel(l, primaryActionFor(started, started.userData)),
        'Riprendi S1:E4 · 23:14');
  });
}
