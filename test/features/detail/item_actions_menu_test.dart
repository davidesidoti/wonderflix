import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/item_actions_menu.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  test('voci per ruolo e livello (spec §7.2)', () {
    expect(
        itemActionGroups(
            kind: ItemKind.movie,
            reports: true,
            canManageSubtitles: true,
            isAdmin: false),
        [
          [ItemAction.report, ItemAction.mediaInfo],
          [ItemAction.subtitles]
        ]);
    expect(
        itemActionGroups(
            kind: ItemKind.season,
            reports: true,
            canManageSubtitles: true,
            isAdmin: true),
        [
          [ItemAction.report]
        ]);
    expect(
        itemActionGroups(
            kind: ItemKind.series,
            reports: false,
            canManageSubtitles: false,
            isAdmin: false),
        isEmpty);
    expect(
        itemActionGroups(
            kind: ItemKind.episode,
            reports: false,
            canManageSubtitles: false,
            isAdmin: false),
        [
          [ItemAction.mediaInfo]
        ]);
  });

  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune')
      ..itemsById['s1'] = testItem(
          id: 's1', name: 'The Last of Us', kind: ItemKind.series, childCount: 1)
      ..seasonsBySeries['s1'] = [
        testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
      ]
      ..episodesBySeason['se1'] = [
        testItem(
            id: 'e1',
            name: 'Episodio 1',
            kind: ItemKind.episode,
            seriesId: 's1',
            seasonId: 'se1',
            seasonIndex: 1,
            index: 1),
      ];
  });

  Future<void> pumpDetail(WidgetTester tester, String id,
      {bool reports = true,
      JellyfinUser user = const JellyfinUser(
          id: 'u1', name: 'Mario', enableSubtitleManagement: true)}) async {
    await pumpApp(tester, Scaffold(body: ItemDetailScreen(itemId: id)),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          ...socialTestOverrides(FakeSocialApi(),
              features: SocialFeatures(reports: reports), session: false),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(SessionSignedIn(user))),
        ]);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('il bottone non c\'è senza voci', (tester) async {
    await pumpDetail(tester, 's1', reports: false);
    // Né la serie né la stagione hanno voci; restano gli episodi (Info
    // tecniche).
    expect(find.byTooltip('Altre azioni'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(DetailHeader),
            matching: find.byTooltip('Altre azioni')),
        findsNothing);
  });

  testWidgets('il menu di un film mostra le voci e il separatore',
      (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Segnala un problema'), findsOneWidget);
    expect(find.text('Info tecniche'), findsOneWidget);
    expect(find.text('Sottotitoli'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
  });

  testWidgets('"Info tecniche" apre la finestra', (tester) async {
    api.mediaInfoById['m1'] = testMediaInfo();
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info tecniche'));
    await tester.pumpAndSettle();
    expect(find.text('mkv'), findsOneWidget);
  });

  testWidgets('il bottone su un episodio non fa partire la riproduzione',
      (tester) async {
    await pumpDetail(tester, 's1');
    // Uno per la stagione, uno per l'episodio.
    expect(find.byTooltip('Altre azioni'), findsNWidgets(3));
    final tile = find.ancestor(
        of: find.text('1. Episodio 1'), matching: find.byType(InkWell));
    final button = find.descendant(
        of: tile.first, matching: find.byTooltip('Altre azioni'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Il menu si apre; se il tocco arrivasse all'episodio, `playItem` senza
    // router lancerebbe e il test fallirebbe.
    expect(find.text('Info tecniche'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
