import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/item_actions_menu.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/item_edit/item_edit_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/item_edit_fakes.dart';
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
          [ItemAction.report],
          [ItemAction.editMetadata, ItemAction.refresh, ItemAction.images]
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

  test('voci admin per livello, e nessuna per chi non è admin', () {
    List<ItemAction> admin(ItemKind kind, {bool isAdmin = true}) => [
          for (final group in itemActionGroups(
              kind: kind,
              reports: false,
              canManageSubtitles: false,
              isAdmin: isAdmin))
            ...group
        ];
    const adminActions = [
      ItemAction.editMetadata,
      ItemAction.identify,
      ItemAction.refresh,
      ItemAction.images
    ];
    expect(admin(ItemKind.movie), [ItemAction.mediaInfo, ...adminActions]);
    expect(admin(ItemKind.series), adminActions);
    expect(admin(ItemKind.season),
        [ItemAction.editMetadata, ItemAction.refresh, ItemAction.images]);
    expect(admin(ItemKind.episode), [
      ItemAction.mediaInfo,
      ItemAction.editMetadata,
      ItemAction.refresh,
      ItemAction.images
    ]);
    expect(admin(ItemKind.movie, isAdmin: false), [ItemAction.mediaInfo]);
    expect(admin(ItemKind.series, isAdmin: false), isEmpty);
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
      FakeItemEditApi? editApi,
      JellyfinUser user = const JellyfinUser(
          id: 'u1', name: 'Mario', enableSubtitleManagement: true)}) async {
    await pumpApp(tester, Scaffold(body: ItemDetailScreen(itemId: id)),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          if (editApi != null) itemEditApiProvider.overrideWithValue(editApi),
          ...reportTestOverrides(),
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
    expect(find.text('Sottotitoli…'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
  });

  testWidgets('un admin vede le voci dei metadati e "Modifica metadati" apre '
      'la finestra', (tester) async {
    final editApi = FakeItemEditApi()
      ..items['m1'] = testRawItem(id: 'm1', name: 'Dune', type: 'Movie');
    await pumpDetail(tester, 'm1',
        editApi: editApi,
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Identifica'), findsOneWidget);
    expect(find.text('Aggiorna metadati…'), findsOneWidget);
    expect(find.text('Locandina e sfondo'), findsOneWidget);
    await tester.tap(find.text('Modifica metadati'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Titolo'), findsOneWidget);
    expect(editApi.calls, ['rawItem m1', 'parentalRatings m1']);
  });

  testWidgets('"Identifica" apre la finestra', (tester) async {
    final editApi = FakeItemEditApi()
      ..items['m1'] = testRawItem(id: 'm1', name: 'Dune', type: 'Movie');
    await pumpDetail(tester, 'm1',
        editApi: editApi,
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Identifica'));
    await tester.pumpAndSettle();
    expect(find.text('Cerca'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nome'), findsOneWidget);
    expect(editApi.calls, ['rawItem m1']);
  });

  testWidgets('un utente senza permessi admin non vede le voci dei metadati',
      (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica metadati'), findsNothing);
    expect(find.text('Identifica'), findsNothing);
  });

  testWidgets('"Segnala un problema" apre la finestra', (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segnala un problema'));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi dettagli (facoltativo)'), findsOneWidget);
  });

  testWidgets('"Sottotitoli…" apre la finestra', (tester) async {
    api.mediaInfoById['m1'] = testMediaInfo();
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sottotitoli…'));
    await tester.pumpAndSettle();
    expect(find.text('Tracce presenti'), findsOneWidget);
    expect(find.text('Dune'), findsWidgets);
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
