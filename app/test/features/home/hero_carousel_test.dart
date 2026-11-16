import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/hero_carousel.dart';
import 'package:wonderflix/features/home/hero_queue.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/card_preview.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  final three = [
    for (final n in ['Dune', 'Alien', 'Heat']) testItem(id: n, name: n),
  ];

  Future<ValueNotifier<List<JellyfinItem>>> pumpHero(WidgetTester tester,
      {bool autoplay = false,
      MotionLevel motion = MotionLevel.reduced,
      List<JellyfinItem>? start,
      ValueChanged<JellyfinItem>? onCurrentChanged,
      Size surfaceSize = const Size(1440, 900),
      bool touch = false}) async {
    final items = ValueNotifier(start ?? three);
    addTearDown(items.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder(
          valueListenable: items,
          builder: (context, value, _) =>
              HeroCarousel(items: value, onCurrentChanged: onCurrentChanged),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      carouselAutoplay: autoplay,
      motion: motion,
      surfaceSize: surfaceSize,
      touch: touch,
    );
    return items;
  }

  /// Avanza a passi di `WfMotion.fast` finché si vede [shown] (e non più
  /// [gone]); fallisce dopo [maxSteps] passi. Così il test non dipende da
  /// quanti fotogrammi servono al tempo e alla dissolvenza per finire.
  Future<void> pumpUntilShown(WidgetTester tester, String shown,
      {String? gone, int maxSteps = 10}) async {
    bool done() =>
        find.text(shown).evaluate().isNotEmpty &&
        (gone == null || find.text(gone).evaluate().isEmpty);
    for (var i = 0; i < maxSteps && !done(); i++) {
      await tester.pump(WfMotion.fast);
    }
    expect(done(), isTrue, reason: '$shown non compare entro $maxSteps passi');
  }

  testWidgets('le locandine della coda sono cliccabili', (tester) async {
    await pumpHero(tester);
    expect(find.text('DUNE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hero-queue-2')));
    await tester.pumpAndSettle();
    expect(find.text('HEAT'), findsOneWidget);
    expect(find.text('DUNE'), findsNothing);
  });

  testWidgets("meno elementi dell'indice corrente: si riposiziona",
      (tester) async {
    final items = await pumpHero(tester);
    await tester.tap(find.byKey(const ValueKey('hero-queue-2')));
    await tester.pumpAndSettle();
    expect(find.text('HEAT'), findsOneWidget);

    items.value = three.take(2).toList();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ALIEN'), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-queue-2')), findsNothing);
  });

  testWidgets("non avanza se la Home è coperta da un'altra pagina",
      (tester) async {
    await pumpHero(tester, autoplay: true);
    final context = tester.element(find.byType(HeroCarousel));
    unawaited(Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
    await tester.pumpAndSettle();
    await tester.pump(HeroCarousel.interval * 2);
    Navigator.of(context).pop();
    // Con l'autoplay l'animazione non si ferma mai: niente pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('DUNE'), findsOneWidget,
        reason: 'nessuna transizione mentre era coperta');
    // Il tempo passato sotto l'altra pagina non conta: tornando non cambia
    // subito diapositiva, riprende da dove era.
    expect(find.text('ALIEN'), findsNothing);
  });

  testWidgets('autoplay: dopo 8 s passa alla diapositiva successiva',
      (tester) async {
    await pumpHero(tester, autoplay: true);
    expect(find.text('DUNE'), findsOneWidget);
    await tester.pump(HeroCarousel.interval);
    await pumpUntilShown(tester, 'ALIEN', gone: 'DUNE');
    expect(find.text('ALIEN'), findsOneWidget);
    expect(find.text('DUNE'), findsNothing);
  });

  testWidgets('mouse sopra: il carosello si ferma', (tester) async {
    await pumpHero(tester, autoplay: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(HeroCarousel)));
    await tester.pump();
    await tester.pump(HeroCarousel.interval * 2);
    expect(find.text('DUNE'), findsOneWidget);
    await mouse.moveTo(const Offset(5, 895));
    await tester.pump();
    await tester.pump(HeroCarousel.interval);
    await pumpUntilShown(tester, 'ALIEN');
    expect(find.text('ALIEN'), findsOneWidget);
  });

  testWidgets("con un'anteprima aperta il carosello si ferma", (tester) async {
    await pumpHero(tester, autoplay: true);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HeroCarousel)));
    final preview = Object();
    container.read(cardPreviewProvider.notifier).open(preview);
    await tester.pump();
    await tester.pump(HeroCarousel.interval * 2);
    await tester.pump(WfMotion.fast);
    expect(find.text('DUNE'), findsOneWidget);
    expect(find.text('ALIEN'), findsNothing);
    container.read(cardPreviewProvider.notifier).close(preview);
    await tester.pump();
    await tester.pump(HeroCarousel.interval);
    await pumpUntilShown(tester, 'ALIEN');
    expect(find.text('ALIEN'), findsOneWidget);
  });

  testWidgets('coda: la linea sotto la prima si riempie col tempo', (tester) async {
    await pumpHero(tester, autoplay: true);
    double fill() => tester
        .widget<FractionallySizedBox>(find.byKey(const Key('hero-queue-fill')))
        .widthFactor!;
    expect(fill(), closeTo(0, 0.01));
    await tester.pump(HeroCarousel.interval ~/ 2);
    expect(fill(), closeTo(0.5, 0.02));
  });

  testWidgets('completa: Ken Burns sullo sfondo attivo', (tester) async {
    await pumpHero(tester, autoplay: true, motion: MotionLevel.full);
    Matrix4 kenBurns() => tester
        .widget<Transform>(find.byKey(const Key('hero-ken-burns')).first)
        .transform;
    final start = kenBurns().getMaxScaleOnAxis();
    await tester.pump(HeroCarousel.interval ~/ 2);
    expect(kenBurns().getMaxScaleOnAxis(), greaterThan(start));
  });

  testWidgets('completa: i testi uscenti sfumano in 250 ms', (tester) async {
    await pumpHero(tester, motion: MotionLevel.full);
    await tester.tap(find.byKey(const ValueKey('hero-queue-1')));
    await tester.pump();
    // La dissolvenza più vicina al titolo è quella dei testi.
    double textFade() => tester
        .widget<FadeTransition>(find
            .ancestor(of: find.text('DUNE'), matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;
    // "Riproduci" della diapositiva [id] non riceve clic.
    bool playIgnored(String id) => tester
        .widgetList<IgnorePointer>(find.ancestor(
            of: find.descendant(
                of: find.byKey(ValueKey('slide-$id')),
                matching: find.text('Riproduci')),
            matching: find.byType(IgnorePointer)))
        .any((w) => w.ignoring);
    // Nessun clic sui pulsanti di chi esce né su quelli ancora invisibili
    // di chi entra.
    expect(playIgnored('Dune'), isTrue);
    expect(playIgnored('Alien'), isTrue);
    await tester.pump(const Duration(milliseconds: 125));
    expect(textFade(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 135));
    expect(textFade(), 0);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DUNE'), findsNothing);
    expect(playIgnored('Alien'), isFalse);
  });

  testWidgets('ridotta: i testi uscenti sfumano con la diapositiva',
      (tester) async {
    await pumpHero(tester);
    await tester.tap(find.byKey(const ValueKey('hero-queue-1')));
    await tester.pump();
    double textFade() => tester
        .widget<FadeTransition>(find
            .ancestor(of: find.text('DUNE'), matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;
    expect(textFade(), 1);
    await tester.pump(WfMotion.fast ~/ 2);
    expect(textFade(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsNothing);
  });

  testWidgets('completa: lo sfondo ingrandito non esce dal carosello',
      (tester) async {
    await pumpHero(tester, autoplay: true, motion: MotionLevel.full);
    await tester.pump(HeroCarousel.interval ~/ 2);
    // La scala allunga lo sfondo oltre i 460 px: un ritaglio dentro il
    // carosello lo tiene nei suoi bordi.
    expect(
      find.descendant(
        of: find.byType(HeroCarousel),
        matching: find.ancestor(
            of: find.byKey(const Key('hero-ken-burns')).first,
            matching: find.byType(ClipRect)),
      ),
      findsWidgets,
    );
  });

  testWidgets('carosello: trascinare a sinistra passa al titolo dopo',
      (tester) async {
    await pumpHero(tester, touch: true);
    expect(find.text('DUNE'), findsOneWidget);
    await tester.drag(find.byType(HeroCarousel), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('ALIEN'), findsOneWidget);
    expect(find.text('DUNE'), findsNothing);
    // A destra torna indietro.
    await tester.drag(find.byType(HeroCarousel), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);
  });

  testWidgets('stretto: alto al massimo 1,1 volte la larghezza',
      (tester) async {
    await pumpHero(tester, surfaceSize: const Size(390, 844), touch: true);
    final slide = tester.getRect(find.byKey(const ValueKey('slide-Dune')));
    expect(slide.height, 390 * 1.1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stretto in orizzontale: alto al massimo 0,8 volte la finestra',
      (tester) async {
    await pumpHero(tester, surfaceSize: const Size(844, 390), touch: true);
    final slide = tester.getRect(find.byKey(const ValueKey('slide-Dune')));
    expect(slide.height, 390 * 0.8);
    expect(tester.takeException(), isNull);
  });

  final five = [
    for (final n in ['Dune', 'Alien', 'Heat', 'Up', 'Coco'])
      testItem(id: n, name: n),
  ];

  List<String> queueNames(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.descendant(
            of: find.byType(HeroQueue), matching: find.byType(Text))))
          t.data!,
      ];

  testWidgets('la coda mostra i prossimi tre', (tester) async {
    await pumpHero(tester, start: five);
    expect(queueNames(tester), ['Alien', 'Heat', 'Up']);
    await tester.tap(find.byKey(const ValueKey('hero-queue-2')));
    await tester.pumpAndSettle();
    expect(find.text('HEAT'), findsOneWidget);
    expect(queueNames(tester), ['Up', 'Coco', 'Dune']);
  });

  testWidgets('con due titoli la coda ne ha uno, con uno niente coda',
      (tester) async {
    final items = await pumpHero(tester, start: three.take(2).toList());
    expect(queueNames(tester), ['Alien']);
    items.value = three.take(1).toList();
    await tester.pumpAndSettle();
    expect(queueNames(tester), isEmpty);
  });

  testWidgets('nello stretto tacche al posto della coda', (tester) async {
    await pumpHero(tester,
        surfaceSize: const Size(390, 780), touch: true, start: five);
    expect(find.byType(HeroTicks), findsOneWidget);
    expect(find.byType(HeroQueue), findsNothing);
    for (var i = 0; i < 5; i++) {
      expect(tester.getSize(find.byKey(ValueKey('hero-tick-$i'))).height,
          greaterThanOrEqualTo(44));
    }
    // Le tacche stanno sotto i pulsanti.
    expect(tester.getTopLeft(find.byType(HeroTicks)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Riproduci')).dy));
    await tester.tap(find.byKey(const ValueKey('hero-tick-3')));
    await tester.pumpAndSettle();
    expect(find.text('UP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('riga "perché è qui" e nome grande', (tester) async {
    final today = DateTime.now().toUtc().toIso8601String();
    await pumpHero(tester,
        start: [testItem(id: 'Dune', name: 'Dune', dateCreated: today)],
        surfaceSize: const Size(1280, 800));
    expect(find.text('Film · arrivato oggi'), findsOneWidget);
    expect(tester.widget<Text>(find.text('DUNE')).style!.fontSize, 104);
  });

  testWidgets('nome a 62 nello stretto', (tester) async {
    await pumpHero(tester, surfaceSize: const Size(390, 780), touch: true);
    expect(tester.widget<Text>(find.text('DUNE')).style!.fontSize, 62);
    expect(tester.takeException(), isNull);
  });

  testWidgets('altezze: 500 su desktop, al massimo 470 nello stretto',
      (tester) async {
    await pumpHero(tester, surfaceSize: const Size(1280, 800));
    expect(tester.getSize(find.byKey(const ValueKey('slide-Dune'))).height,
        500);
    await pumpHero(tester, surfaceSize: const Size(390, 780), touch: true);
    expect(tester.getSize(find.byKey(const ValueKey('slide-Dune'))).height,
        lessThanOrEqualTo(470));
  });

  testWidgets('onCurrentChanged col titolo nuovo a ogni cambio',
      (tester) async {
    final seen = <String>[];
    await pumpHero(tester, onCurrentChanged: (item) => seen.add(item.id));
    await tester.tap(find.byKey(const ValueKey('hero-queue-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hero-queue-0')));
    await tester.pumpAndSettle();
    // Il primo all'avvio, poi a ogni cambio.
    expect(seen, ['Dune', 'Alien', 'Dune']);
  });
}
