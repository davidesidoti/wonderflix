import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/hero_carousel.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  final three = [
    for (final n in ['Dune', 'Alien', 'Heat']) testItem(id: n, name: n),
  ];

  Future<ValueNotifier<List<JellyfinItem>>> pumpHero(WidgetTester tester) async {
    final items = ValueNotifier(three);
    addTearDown(items.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder(
          valueListenable: items,
          builder: (context, value, _) => HeroCarousel(items: value),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
    );
    return items;
  }

  testWidgets('i puntini sono cliccabili', (tester) async {
    await pumpHero(tester);
    expect(find.text('DUNE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hero-dot-2')));
    await tester.pumpAndSettle();
    expect(find.text('HEAT'), findsOneWidget);
    expect(find.text('DUNE'), findsNothing);
  });

  testWidgets("meno elementi dell'indice corrente: si riposiziona",
      (tester) async {
    final items = await pumpHero(tester);
    await tester.tap(find.byKey(const ValueKey('hero-dot-2')));
    await tester.pumpAndSettle();
    expect(find.text('HEAT'), findsOneWidget);

    items.value = three.take(2).toList();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ALIEN'), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-dot-2')), findsNothing);
  });

  testWidgets("non avanza se la Home è coperta da un'altra pagina",
      (tester) async {
    await pumpHero(tester);
    final context = tester.element(find.byType(HeroCarousel));
    unawaited(Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.pump(HeroCarousel.interval * 2);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget,
        reason: 'nessuna transizione mentre era coperta');
  });
}
