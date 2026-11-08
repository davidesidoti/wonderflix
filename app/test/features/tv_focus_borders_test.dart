import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/ratings/rating_widgets.dart';
import 'package:wonderflix/features/recommendations/recommend_panel.dart';
import 'package:wonderflix/features/requests/requestables_controller.dart';
import 'package:wonderflix/features/requests/requestables_section.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/requests/season_picker.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../support/pump_app.dart';
import '../support/social_fakes.dart';

class _SeerrDown extends RequestablesController {
  @override
  RequestablesState build() =>
      const RequestablesState(term: 'dune', error: 'down');
}

/// Il bordo largo 2 disegnato attorno a [child] da un `DecoratedBox` antenato.
Border? _ring(WidgetTester tester, Finder child) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.ancestor(of: child, matching: find.byType(DecoratedBox)),
  )) {
    final d = box.decoration;
    if (d is BoxDecoration &&
        d.border is Border &&
        (d.border! as Border).top.width == 2) {
      return d.border! as Border;
    }
  }
  return null;
}

/// Dà il focus al controllo che contiene [inner] (un suo discendente
/// foglia: `Focus.of` sale fino al suo nodo).
Future<void> _focus(WidgetTester tester, Finder inner) async {
  Focus.of(tester.element(inner.first)).requestFocus();
  await tester.pumpAndSettle();
}

/// Bordo del pulsante [button] (il Material dentro di lui).
BorderSide _side(WidgetTester tester, Finder button) {
  final material = tester.widget<Material>(
    find.descendant(of: button, matching: find.byType(Material)).first,
  );
  return (material.shape! as OutlinedBorder).side;
}

Finder _leaf(Finder box) =>
    find.descendant(of: box, matching: find.byType(CustomPaint)).last;

void main() {
  group('RatingScorePicker', () {
    Future<void> pump(WidgetTester tester, {required bool tv}) => pumpApp(
      tester,
      Scaffold(body: RatingScorePicker(selected: 4, onSelect: (_) {})),
      tv: tv,
    );

    testWidgets('TV: oro sugli altri, crema sul voto scelto', (tester) async {
      await pump(tester, tv: true);
      final other = find.byKey(const Key('rating-score-2'));
      expect(_ring(tester, other)?.top.color, Colors.transparent);
      await _focus(
        tester,
        find.descendant(of: other, matching: find.byType(Text)),
      );
      expect(_ring(tester, other)?.top.color, WfColors.gold);
      final chosen = find.byKey(const Key('rating-score-4'));
      await _focus(
        tester,
        find.descendant(of: chosen, matching: find.byType(Text)),
      );
      expect(_ring(tester, chosen)?.top.color, WfColors.cream);
    });

    testWidgets('fuori dalla TV nessun bordo largo 2', (tester) async {
      await pump(tester, tv: false);
      final other = find.byKey(const Key('rating-score-2'));
      await _focus(
        tester,
        find.descendant(of: other, matching: find.byType(Text)),
      );
      expect(_ring(tester, other), isNull);
    });
  });

  group('Consiglia: amici', () {
    Future<void> pump(WidgetTester tester, {required bool tv}) async {
      final api = FakeSocialApi()..install(features: const {});
      api.recommendationTargetsById['m1'] = [testTarget('u3', 'Peach')];
      await pumpApp(
        tester,
        const Scaffold(
          body: RecommendPanel(
            subject: RecommendSubject(itemId: 'm1', name: 'Dune'),
          ),
        ),
        overrides: socialTestOverrides(
          api,
          features: const SocialFeatures(friends: true, recommendations: true),
        ),
        tv: tv,
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('TV: la riga col focus ha il bordo oro largo 2', (
      tester,
    ) async {
      await pump(tester, tv: true);
      final row = find.byType(Checkbox);
      expect(_ring(tester, row)?.top.color, Colors.transparent);
      await _focus(tester, find.text('Peach'));
      expect(_ring(tester, row)?.top.color, WfColors.gold);
    });

    testWidgets('fuori dalla TV nessun bordo largo 2', (tester) async {
      await pump(tester, tv: false);
      await _focus(tester, find.text('Peach'));
      expect(_ring(tester, find.byType(Checkbox)), isNull);
    });
  });

  group('SeasonPicker', () {
    Future<void> pump(WidgetTester tester, {required bool tv}) => pumpApp(
      tester,
      Scaffold(
        body: SeasonPicker(
          seasons: const [SeasonInfo(seasonNumber: 2, episodeCount: 3)],
          selected: const {2},
          enabled: true,
          onToggle: (_) {},
          onToggleAll: () {},
        ),
      ),
      tv: tv,
    );

    testWidgets('TV: la riga col focus ha il bordo oro largo 2', (
      tester,
    ) async {
      await pump(tester, tv: true);
      final box = find.descendant(
        of: find.byKey(const ValueKey('season-2')),
        matching: find.byType(Checkbox),
      );
      expect(_ring(tester, box)?.top.color, Colors.transparent);
      await _focus(tester, _leaf(box));
      expect(_ring(tester, box)?.top.color, WfColors.gold);
    });

    testWidgets('fuori dalla TV nessun bordo largo 2', (tester) async {
      await pump(tester, tv: false);
      final box = find.descendant(
        of: find.byKey(const ValueKey('season-2')),
        matching: find.byType(Checkbox),
      );
      await _focus(tester, _leaf(box));
      expect(_ring(tester, box), isNull);
    });
  });

  group('Da richiedere: Riprova', () {
    Future<void> pump(WidgetTester tester, {required bool tv}) => pumpApp(
      tester,
      const Scaffold(body: RequestablesSection(library: null)),
      overrides: [
        requestsAvailableProvider.overrideWithValue(true),
        requestablesControllerProvider.overrideWith(_SeerrDown.new),
      ],
      tv: tv,
    );

    testWidgets('TV: col focus il bordo è crema largo 2', (tester) async {
      await pump(tester, tv: true);
      final button = find.byType(OutlinedButton);
      expect(_side(tester, button).width, 1);
      await _focus(tester, find.text('Riprova'));
      expect(_side(tester, button), tvFocusSideOnGold);
    });

    testWidgets('fuori dalla TV il bordo non cambia', (tester) async {
      await pump(tester, tv: false);
      final button = find.byType(OutlinedButton);
      await _focus(tester, find.text('Riprova'));
      expect(_side(tester, button), const BorderSide(color: WfColors.gold));
    });
  });
}
