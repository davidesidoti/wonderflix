import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/hero_carousel.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_entry.dart';
import 'package:wonderflix/ui/form_factor.dart';
import 'package:wonderflix/ui/media_row.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

/// Il widget con il focus sta dentro [finder].
bool _focusIn(Finder finder) {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return false;
  final target = finder.evaluate().first;
  var inside = false;
  focused.context?.visitAncestorElements((e) {
    if (e == target) inside = true;
    return !inside;
  });
  return inside || focused.context == target;
}

void main() {
  testWidgets(
    'TV: Riproduci del carosello ha il focus, Match non c\'è, Stasera sì',
    (tester) async {
      final library = FakeLibraryApi()
        ..onItems = (query, start, limit) =>
            pageOf([testItem(id: 'm1', name: 'Dune')]);
      await pumpApp(
        tester,
        const FormFactorScope(tv: true, child: HomeScreen()),
        overrides: [
          ...homeOverrides(library: library),
          matchEntryProvider.overrideWithValue(true),
        ],
        surfaceSize: const Size(1440, 1600),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(find.byType(HeroCarousel), findsOneWidget);
      expect(
        _focusIn(
          find.ancestor(
            of: find.text('Riproduci'),
            matching: find.byType(FilledButton),
          ),
        ),
        isTrue,
      );
      expect(find.byKey(const Key('match-button')), findsNothing);
      expect(find.byKey(const Key('tonight-button')), findsOneWidget);
    },
  );

  testWidgets('fuori dalla TV Match c\'è', (tester) async {
    final library = FakeLibraryApi()
      ..onItems = (query, start, limit) =>
          pageOf([testItem(id: 'm1', name: 'Dune')]);
    await pumpApp(
      tester,
      const HomeScreen(),
      overrides: [
        ...homeOverrides(library: library),
        matchEntryProvider.overrideWithValue(true),
      ],
      surfaceSize: const Size(1440, 1600),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.byKey(const Key('match-button')), findsOneWidget);
  });

  testWidgets('TV: il carosello non avanza finché il focus è dentro', (
    tester,
  ) async {
    final items = [
      for (final n in ['Dune', 'Alien']) testItem(id: n, name: n),
    ];
    await pumpApp(
      tester,
      Scaffold(
        body: FormFactorScope(tv: true, child: HeroCarousel(items: items)),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
      carouselAutoplay: true,
    );
    await tester.pump();
    expect(
      _focusIn(
        find.ancestor(
          of: find.text('Riproduci'),
          matching: find.byType(FilledButton),
        ),
      ),
      isTrue,
    );
    await tester.pump(HeroCarousel.interval * 2);
    await tester.pump(WfMotion.fast);
    expect(find.text('DUNE'), findsOneWidget);
    expect(find.text('ALIEN'), findsNothing);
    // Il focus esce: il tempo riprende e la diapositiva cambia.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(HeroCarousel.interval);
    for (var i = 0; i < 10 && find.text('ALIEN').evaluate().isEmpty; i++) {
      await tester.pump(WfMotion.fast);
    }
    expect(find.text('ALIEN'), findsOneWidget);
  });

  testWidgets('TV: il titolo di una riga è raggiungibile e OK lo apre', (
    tester,
  ) async {
    var opened = 0;
    await pumpApp(
      tester,
      FormFactorScope(
        tv: true,
        child: Scaffold(
          body: MediaRow(
            title: 'Film',
            height: 100,
            itemCount: 1,
            onTitleTap: () => opened++,
            itemBuilder: (context, i) => const SizedBox(width: 50),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    final link = find.byKey(const Key('row-title-link'));
    // Il primo (e solo) elemento focalizzabile è il titolo.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(link)).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, 1);
  });
}
