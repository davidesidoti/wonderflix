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

  testWidgets(
      'TV: il cambio di diapositiva non prende il focus perso da un\'altra '
      'riga', (tester) async {
    final items = [
      for (final n in ['Dune', 'Alien', 'Heat']) testItem(id: n, name: n),
    ];
    final other = ValueNotifier(true);
    addTearDown(other.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: FormFactorScope(
          tv: true,
          child: Column(
            children: [
              HeroCarousel(items: items),
              ValueListenableBuilder(
                valueListenable: other,
                builder: (context, show, _) => show
                    ? TextButton(onPressed: () {}, child: const Text('altro'))
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
      surfaceSize: const Size(1440, 900),
      carouselAutoplay: true,
    );
    await tester.pump();
    final play = find.ancestor(
      of: find.text('Riproduci'),
      matching: find.byType(FilledButton),
    );
    expect(_focusIn(play), isTrue);
    Future<void> nextSlide() async {
      await tester.pump(HeroCarousel.interval);
      for (var i = 0; i < 10; i++) {
        await tester.pump(WfMotion.fast);
      }
    }

    // Il focus va su un'altra riga; la diapositiva dell'apertura se ne va.
    Focus.of(tester.element(find.text('altro'))).requestFocus();
    await tester.pump();
    await nextSlide();
    expect(find.text('ALIEN'), findsOneWidget);
    // L'elemento col focus sparisce (la riga si è ricaricata).
    other.value = false;
    await tester.pump();
    await nextSlide();
    expect(find.text('HEAT'), findsOneWidget);
    expect(_focusIn(play), isFalse);
  });

  group('diapositive col telecomando', () {
    final items = [
      for (final n in ['Dune', 'Alien', 'Heat']) testItem(id: n, name: n),
    ];

    Future<void> pumpCarousel(WidgetTester tester, {required bool tv}) =>
        pumpApp(
          tester,
          Scaffold(
            body: FormFactorScope(tv: tv, child: HeroCarousel(items: items)),
          ),
          overrides: [
            libraryApiProvider.overrideWithValue(FakeLibraryApi()),
            sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser)),
            ),
          ],
          carouselAutoplay: true,
        );

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      for (var i = 0; i < 10; i++) {
        await tester.pump(WfMotion.fast);
      }
    }

    final play = find.ancestor(
      of: find.text('Riproduci'),
      matching: find.byType(FilledButton),
    );
    final details = find.ancestor(
      of: find.text('Dettagli'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );

    testWidgets(
        'TV: Destra sull\'ultimo pulsante passa alla successiva, in giro, '
        'con il focus sul primo pulsante', (tester) async {
      await pumpCarousel(tester, tv: true);
      await tester.pump();
      expect(_focusIn(play), isTrue);
      for (final next in ['ALIEN', 'HEAT', 'DUNE']) {
        // Riproduci → Dettagli, poi Dettagli → diapositiva successiva.
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(_focusIn(details), isTrue);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(find.text(next), findsOneWidget);
        expect(_focusIn(play), isTrue, reason: next);
      }
      // Col focus dentro la rotazione resta ferma.
      await tester.pump(HeroCarousel.interval * 2);
      await tester.pump(WfMotion.fast);
      expect(find.text('DUNE'), findsOneWidget);
    });

    testWidgets('TV: ⏩ e ⏪ cambiano diapositiva', (tester) async {
      await pumpCarousel(tester, tv: true);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.mediaFastForward);
      expect(find.text('ALIEN'), findsOneWidget);
      expect(_focusIn(play), isTrue);
      await press(tester, LogicalKeyboardKey.mediaRewind);
      expect(find.text('DUNE'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.mediaRewind);
      expect(find.text('HEAT'), findsOneWidget);
      expect(_focusIn(play), isTrue);
    });

    testWidgets('fuori dalla TV Destra e ⏩ non cambiano diapositiva', (
      tester,
    ) async {
      await pumpCarousel(tester, tv: false);
      await tester.pump();
      Focus.of(tester.element(find.text('Dettagli'))).requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.mediaFastForward);
      expect(find.text('DUNE'), findsOneWidget);
    });
  });

  testWidgets(
      'TV: se il titolo della diapositiva col focus cambia, il focus va sui '
      'pulsanti di quella nuova', (tester) async {
    final shown = ValueNotifier([
      for (final n in ['Dune', 'Alien']) testItem(id: n, name: n),
    ]);
    addTearDown(shown.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: FormFactorScope(
          tv: true,
          child: ValueListenableBuilder(
            valueListenable: shown,
            builder: (context, items, _) => HeroCarousel(items: items),
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    await tester.pump();
    final play = find.ancestor(
      of: find.text('Riproduci'),
      matching: find.byType(FilledButton),
    );
    expect(_focusIn(play), isTrue);
    // La rilettura porta un altro titolo al posto di quello mostrato.
    shown.value = [
      for (final n in ['Heat', 'Alien']) testItem(id: n, name: n),
    ];
    await tester.pump();
    await tester.pump();
    expect(find.text('HEAT'), findsOneWidget);
    expect(_focusIn(play), isTrue);
  });
}
