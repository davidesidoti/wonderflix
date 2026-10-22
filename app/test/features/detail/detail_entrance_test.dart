import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/detail_rows.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/detail/movie_detail_view.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(
          id: 'm1', name: 'Dune', overview: 'Paul Atreides e i Fremen.')
      ..similarItems = [testItem(id: 'm2', name: 'Arrival')];
  });

  Future<void> pumpDetail(WidgetTester tester,
      {required MotionLevel motion, HeroLaunch? launch}) async {
    await pumpApp(
      tester,
      Scaffold(body: ItemDetailScreen(itemId: 'm1', launch: launch)),
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      motion: motion,
    );
    await tester.pump();
    await tester.pump();
  }

  /// Opacità effettiva di [finder]: prodotto delle `Opacity` sopra.
  double opacityOf(WidgetTester tester, Finder finder) => tester
      .widgetList<Opacity>(find.ancestor(of: finder, matching: find.byType(Opacity)))
      .fold(1.0, (value, widget) => value * widget.opacity);

  testWidgets('animazioni ridotte: la testata è subito visibile',
      (tester) async {
    await pumpDetail(tester, motion: MotionLevel.reduced);
    await tester.pumpAndSettle();
    expect(find.text('DUNE'), findsOneWidget);
    expect(opacityOf(tester, find.text('DUNE')), 1);
    expect(opacityOf(tester, find.text('Paul Atreides e i Fremen.')), 1);
  });

  testWidgets('animazioni complete: la testata entra scaglionata',
      (tester) async {
    await pumpDetail(tester, motion: MotionLevel.full);
    final group = tester.widget<StaggerGroup>(find
        .ancestor(
            of: find.byType(DetailHeader), matching: find.byType(StaggerGroup))
        .first);
    expect(group.count, detailEntranceCount);
    expect(group.delay, Duration.zero);
    // La trama (elemento 3) parte dopo il titolo (elemento 0).
    await tester.pump(WfMotion.stagger * 2);
    expect(opacityOf(tester, find.text('DUNE')),
        greaterThan(opacityOf(tester, find.text('Paul Atreides e i Fremen.'))));
    // L'onda degli scheletri è continua: niente pumpAndSettle.
    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(tester, find.text('DUNE')), 1);
    expect(opacityOf(tester, find.text('Paul Atreides e i Fremen.')), 1);
  });

  testWidgets('aperta con un volo: l\'entrata aspetta la fine del volo',
      (tester) async {
    const launch = HeroLaunch(
      tag: WfHeroTag('m1', 'home.latest.0'),
      image: ImageRef('https://media.example.com/Items/m1/Images/Backdrop/0'),
      title: 'Dune',
    );
    await pumpDetail(tester, motion: MotionLevel.full, launch: launch);
    await tester.pump(WfMotion.medium);
    final group = tester.widget<StaggerGroup>(find
        .ancestor(
            of: find.byType(DetailHeader), matching: find.byType(StaggerGroup))
        .first);
    expect(group.delay, WfMotion.hero);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('aperta con un volo: le card del cast volano con la loro riga',
      (tester) async {
    api.itemsById['m1'] = testItem(id: 'm1', name: 'Dune', people: [
      {'Id': 'p1', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
      {'Id': 'p2', 'Name': 'Rebecca Ferguson', 'Type': 'Actor'},
    ]);
    const launch = HeroLaunch(
      tag: WfHeroTag('m1', 'home.latest.0'),
      image: ImageRef('https://media.example.com/Items/m1/Images/Backdrop/0'),
      title: 'Dune',
    );
    await pumpDetail(tester, motion: MotionLevel.full, launch: launch);
    // La riga del cast (elemento 5) compare dopo il volo e cinque passi.
    await tester.pump(
        WfMotion.hero + WfMotion.stagger * 5 + const Duration(milliseconds: 100));
    expect(opacityOf(tester, find.byType(CastRow)), greaterThan(0));
    final card = tester.widget<Transform>(find
        .ancestor(of: find.text('Zendaya'), matching: find.byType(Transform))
        .first);
    expect(card.transform.getTranslation().x, greaterThan(0),
        reason: 'la prima card vola mentre la riga è visibile');
    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(tester, find.text('Zendaya')), 1);
  });

  testWidgets('scorrendo, il testo della testata sfuma salendo',
      (tester) async {
    await pumpDetail(tester, motion: MotionLevel.full);
    await tester.pump(const Duration(seconds: 2));
    final controller =
        tester.widget<MovieDetailView>(find.byType(MovieDetailView)).controller!;
    controller.jumpTo(detailHeaderHeight / 2);
    await tester.pump();
    expect(opacityOf(tester, find.text('DUNE')), closeTo(0.2, 1e-6));
    controller.jumpTo(400);
    await tester.pump();
    expect(opacityOf(tester, find.text('DUNE')), 0);
    await tester.pump(const Duration(seconds: 1));
  });
}
