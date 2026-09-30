import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

import '../support/library_fakes.dart';
import '../support/pump_app.dart';

void main() {
  test('WfHeroTag: uguale solo con stesso titolo e stessa sorgente', () {
    expect(const WfHeroTag('m1', 'home.latest.0'),
        const WfHeroTag('m1', 'home.latest.0'));
    expect(const WfHeroTag('m1', 'home.latest.0') == const WfHeroTag('m1', 'home.latest.1'),
        isFalse);
    expect(const WfHeroTag('m1', 'a').hashCode, const WfHeroTag('m1', 'a').hashCode);
  });

  testWidgets("WfHeroScope: sorgente legata all'istanza della pagina",
      (tester) async {
    final sources = <String>[];
    Widget probe() => Builder(builder: (context) {
          sources.add(WfHeroScope.source(context, 'cast.0'));
          return const SizedBox();
        });
    await tester.pumpWidget(Column(children: [
      probe(),
      WfHeroScope(id: 'a', child: probe()),
      WfHeroScope(id: 'b', child: probe()),
    ]));
    expect(sources, ['cast.0', 'a|cast.0', 'b|cast.0']);
  });

  testWidgets('WfHero: Hero solo con tag e animazioni complete', (tester) async {
    const tag = WfHeroTag('m1', 'x');
    Widget tree(MotionLevel level, WfHeroTag? heroTag) => Directionality(
          textDirection: TextDirection.ltr,
          child: WfMotionScope(
            motion: WfMotion(level),
            child: WfHero(tag: heroTag, child: const SizedBox()),
          ),
        );
    await tester.pumpWidget(tree(MotionLevel.full, tag));
    expect(tester.widget<Hero>(find.byType(Hero)).tag, tag);
    await tester.pumpWidget(tree(MotionLevel.reduced, tag));
    expect(find.byType(Hero), findsNothing);
    await tester.pumpWidget(tree(MotionLevel.full, null));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('volo: dissolvenza dalla card alla pagina', (tester) async {
    // I due Hero restano montati (fuori scena) mentre si disegna il volo:
    // wfHeroFlight legge i loro widget dai contesti.
    Widget tree(Widget flight) => Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [
            const Offstage(
              child: Column(children: [
                Hero(tag: 'card', child: Text('card')),
                Hero(tag: 'pagina', child: Text('pagina')),
              ]),
            ),
            flight,
          ]),
        );
    await tester.pumpWidget(tree(const SizedBox()));
    final card = tester.element(find.byType(Hero, skipOffstage: false).first);
    final page = tester.element(find.byType(Hero, skipOffstage: false).last);
    Future<void> flight(double t, HeroFlightDirection direction) async {
      final from = direction == HeroFlightDirection.push ? card : page;
      final to = direction == HeroFlightDirection.push ? page : card;
      await tester.pumpWidget(
          tree(wfHeroFlight(card, AlwaysStoppedAnimation(t), direction, from, to)));
    }

    double opacity(String text) => tester
        .widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)))
        .opacity;

    await flight(0, HeroFlightDirection.push);
    expect(opacity('card'), 1);
    expect(opacity('pagina'), 0);
    await flight(1, HeroFlightDirection.push);
    expect(opacity('card'), 0);
    expect(opacity('pagina'), 1);
    // Indietro: l'animazione scende da 1 a 0, la pagina sfuma nella card.
    await flight(1, HeroFlightDirection.pop);
    expect(opacity('pagina'), 1);
    await flight(0, HeroFlightDirection.pop);
    expect(opacity('card'), 1);
  });

  testWidgets('volo: gli angoli passano da quelli della card a quelli della '
      'pagina, con un solo ritaglio', (tester) async {
    const flightKey = Key('volo');
    Widget tree(Widget flight) => Directionality(
          textDirection: TextDirection.ltr,
          child: WfMotionScope(
            motion: const WfMotion(MotionLevel.full),
            child: Stack(children: [
              Offstage(
                child: Column(children: [
                  WfHero(
                    tag: const WfHeroTag('p9', 'cast.0'),
                    borderRadius: BorderRadius.circular(45),
                    child: const SizedBox(width: 90, height: 90),
                  ),
                  WfHero(
                    tag: const WfHeroTag('p9', 'persona'),
                    borderRadius: BorderRadius.circular(8),
                    child: const SizedBox(width: 200, height: 300),
                  ),
                ]),
              ),
              KeyedSubtree(key: flightKey, child: flight),
            ]),
          ),
        );
    await tester.pumpWidget(tree(const SizedBox()));
    final cast = tester.element(find.byType(Hero, skipOffstage: false).first);
    final person = tester.element(find.byType(Hero, skipOffstage: false).last);
    Future<List<ClipRRect>> clipsAt(
        double t, HeroFlightDirection direction) async {
      final push = direction == HeroFlightDirection.push;
      await tester.pumpWidget(tree(wfHeroFlight(cast, AlwaysStoppedAnimation(t),
          direction, push ? cast : person, push ? person : cast)));
      return tester
          .widgetList<ClipRRect>(find.descendant(
              of: find.byKey(flightKey), matching: find.byType(ClipRRect)))
          .toList();
    }

    var clips = await clipsAt(0, HeroFlightDirection.push);
    expect(clips, hasLength(1), reason: 'nessun doppio ritaglio');
    expect(clips.single.borderRadius, BorderRadius.circular(45));
    clips = await clipsAt(1, HeroFlightDirection.push);
    expect(clips, hasLength(1));
    expect(clips.single.borderRadius, BorderRadius.circular(8));
    // Indietro: la foto torna nel cerchio.
    clips = await clipsAt(0, HeroFlightDirection.pop);
    expect(clips.single.borderRadius, BorderRadius.circular(45));
  });

  testWidgets('WfHero ritaglia anche senza Hero', (tester) async {
    Widget tree(MotionLevel level, WfHeroTag? tag) => Directionality(
          textDirection: TextDirection.ltr,
          child: WfMotionScope(
            motion: WfMotion(level),
            child: WfHero(
              tag: tag,
              borderRadius: BorderRadius.circular(45),
              child: const SizedBox(width: 90, height: 90),
            ),
          ),
        );
    for (final (level, tag) in [
      (MotionLevel.reduced, const WfHeroTag('p9', 'cast.0')),
      (MotionLevel.full, null),
      (MotionLevel.full, const WfHeroTag('p9', 'cast.0')),
    ]) {
      await tester.pumpWidget(tree(level, tag));
      expect(tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
          BorderRadius.circular(45),
          reason: '$level, $tag');
    }
  });

  testWidgets('WfHero: per default gli angoli delle card', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: WfHero(tag: null, child: SizedBox()),
    ));
    expect(tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
        BorderRadius.circular(5));
  });

  testWidgets('openItem con sorgente passa HeroLaunch alla scheda',
      (tester) async {
    Object? extra;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TextButton(
          onPressed: () => openItem(context, testItem(id: 'm1'),
              heroSource: 'home.latest.2'),
          child: const Text('apri'),
        ),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) {
          extra = state.extra;
          return const Text('scheda');
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(testAppConfig)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    final launch = extra! as HeroLaunch;
    expect(launch.tag, const WfHeroTag('m1', 'home.latest.2'));
    expect(launch.image!.url, contains('/Items/m1/Images/Backdrop/0'));
    expect(launch.fallback!.url, contains('/Items/m1/Images/Primary'));
    expect(launch.title, 'Dune: Parte Due');
  });

  testWidgets('openItem senza sorgente: nessun HeroLaunch', (tester) async {
    Object? extra = 'non toccato';
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TextButton(
          onPressed: () => openItem(context, testItem(id: 'm1', kind: ItemKind.movie)),
          child: const Text('apri'),
        ),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) {
          extra = state.extra;
          return const Text('scheda');
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(testAppConfig)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(extra, isNull);
  });
}
