import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/detail/movie_detail_view.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/ui/backdrop_image.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  const launch = HeroLaunch(
    tag: WfHeroTag('m1', 'home.latest.0'),
    image: ImageRef('https://media.example.com/Items/m1/Images/Backdrop/0'),
    title: 'Dune',
  );

  testWidgets('scheda in caricamento: sfondo e Hero già presenti',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1', launch: launch)),
      overrides: [itemProvider('m1').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, launch.tag);
    expect(find.byType(BackdropImage), findsOneWidget);
    expect(find.byType(DetailRowsSkeleton), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
  });

  testWidgets('scheda con volo: dal caricamento ai dati resta lo stesso Hero '
      'e lo scroll passa alla lista dei dati', (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1', launch: launch)),
      overrides: [
        itemProvider('m1').overrideWith((ref) => pending.future),
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      motion: MotionLevel.full,
    );
    final hero = tester.state(find.byType(Hero));
    // La lista di caricamento non usa il controller della pagina: durante
    // la dissolvenza verso i dati ci sono due liste.
    final loadingList = find.ancestor(
        of: find.byType(DetailRowsSkeleton), matching: find.byType(ListView));
    expect(tester.widget<ListView>(loadingList).controller, isNull);

    pending.complete(testItem(id: 'm1', name: 'Dune'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'un solo ScrollView per volta sul controller');
    // A metà dissolvenza: scheletro e dati insieme, un solo ScrollView sul
    // controller.
    expect(find.byType(DetailRowsSkeleton), findsOneWidget);
    final controller =
        tester.widget<MovieDetailView>(find.byType(MovieDetailView)).controller!;
    expect(controller.positions, hasLength(1));
    // Fine della dissolvenza (l'onda è continua: niente pumpAndSettle).
    await tester.pump(WfMotion.medium);
    await tester.pump(WfMotion.medium);
    expect(find.byType(DetailRowsSkeleton), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.text('DUNE'), findsOneWidget);
    // Stesso Hero (stesso State): la destinazione del volo non si ricrea.
    expect(tester.state(find.byType(Hero)), same(hero));
    expect(tester.widget<Hero>(find.byType(Hero)).tag, launch.tag);
    expect(controller.positions, hasLength(1));
    final scrollables = find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.controller == controller);
    expect(scrollables, findsOneWidget);
    expect(
        find.ancestor(of: scrollables, matching: find.byType(MovieDetailView)),
        findsOneWidget);
  });

  testWidgets('scheda in caricamento senza volo: solo lo scheletro',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      overrides: [itemProvider('m1').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(BackdropImage), findsNothing);
    expect(find.byType(DetailSkeleton), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
  });

  testWidgets('persona in caricamento: foto (Hero) e nome già presenti',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    const personLaunch = HeroLaunch(
      tag: WfHeroTag('p9', 'cast.m1.0'),
      image: ImageRef('https://media.example.com/Items/p9/Images/Primary'),
      title: 'Zendaya',
    );
    await pumpApp(
      tester,
      const Scaffold(body: PersonScreen(personId: 'p9', launch: personLaunch)),
      overrides: [itemProvider('p9').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, personLaunch.tag);
    expect(find.text('ZENDAYA'), findsOneWidget);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(scroll.controller, isA<SmoothScrollController>());
  });
}
