import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/ratings/rating_widgets.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/l10n/gen/app_localizations_it.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('dieci numeri; il tocco sceglie', (tester) async {
    int? picked;
    await pumpApp(tester, Scaffold(body: RatingScorePicker(onSelect: (n) => picked = n)));
    for (var n = 1; n <= 10; n++) {
      expect(find.byKey(Key('rating-score-$n')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('rating-score-7')));
    expect(picked, 7);
  });

  testWidgets('il commento si ferma a 200 punti di codice', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var submitted = 0;
    await pumpApp(
        tester,
        Scaffold(
            body: RatingCommentField(
                controller: controller, onSubmitted: () => submitted++)));
    await tester.enterText(find.byType(TextField), '${'a' * 199}😀x');
    expect(controller.text.runes.length, 200);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 1);
    expect(controller.text.contains('\n'), isFalse);
  });

  test('media con la virgola in italiano', () {
    expect(formatRatingAverage(7.7, 'it'), '7,7');
    expect(formatRatingAverage(8, 'en'), '8.0');
  });

  test('titolo del voto', () {
    final l = AppLocalizationsIt();
    expect(ratingTitle(l, testItem(name: 'Il Padrino')), 'Il Padrino');
    expect(
        ratingTitle(
            l,
            testItem(
                kind: ItemKind.episode,
                name: 'Pilot',
                seriesName: 'Breaking Bad',
                seasonIndex: 2)),
        'Breaking Bad · Stagione 2');
    expect(
        ratingTitle(
            l,
            testItem(
                kind: ItemKind.episode,
                name: 'Extra',
                seriesName: 'Breaking Bad',
                seasonIndex: 0)),
        'Breaking Bad · Speciali');
  });
}
