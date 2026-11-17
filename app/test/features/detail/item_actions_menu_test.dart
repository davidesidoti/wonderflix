import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import '../../support/test_data.dart';

void main() {
  testWidgets('il menu sta sopra una barra del guscio, non sotto',
      (tester) async {
    var picked = false;
    await pumpApp(
      tester,
      Scaffold(
        body: Stack(children: [
          // Un navigatore annidato come quello di una pagina del guscio.
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Align(
                alignment: Alignment.centerRight,
                child: ItemActionsButton(
                  item: testItem(id: 'm1', name: 'Film'),
                  extra: [
                    (
                      label: 'Voce A',
                      icon: LucideIcons.plus,
                      onSelected: () {},
                    ),
                    (
                      label: 'Voce B',
                      icon: LucideIcons.plus,
                      onSelected: () {},
                    ),
                    (
                      label: 'Voce C',
                      icon: LucideIcons.plus,
                      onSelected: () => picked = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // La barra in basso: sta sopra la pagina, non sopra il menu.
          Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: 460,
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const ColoredBox(color: Colors.red))),
        ]),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
    );
    await tester.tap(find.byType(ItemActionsButton));
    await tester.pumpAndSettle();
    // La terza voce cade dove sta la barra: si tocca solo se il menu è sopra.
    await tester.tap(find.text('Voce C'));
    await tester.pumpAndSettle();
    expect(picked, isTrue);
  });

  test('voci per ruolo e livello (spec §7.2)', () {
    expect(
        itemActionGroups(
            kind: ItemKind.movie,
            reports: true,
            canManageSubtitles: true,
            isAdmin: false),
        [
          [ItemAction.report, ItemAction.mediaInfo, ItemAction.subtitles]
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

  testWidgets('la testata della serie senza voci non ha il ⋯', (tester) async {
    await pumpDetail(tester, 's1', reports: false);
    // La serie non ha voci; restano la stagione (Segna come vista) e gli
    // episodi (Info tecniche).
    expect(find.byTooltip('Altre azioni'), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byType(DetailHeader),
            matching: find.byTooltip('Altre azioni')),
        findsNothing);
  });

  testWidgets('il menu di un film mostra le voci, in un solo gruppo',
      (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Controlla e segnala'), findsOneWidget);
    expect(find.text('Segnala un problema…'), findsOneWidget);
    expect(find.text('Info tecniche…'), findsOneWidget);
    expect(find.text('Sottotitoli…'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsNothing);
  });

  Future<void> pumpButton(WidgetTester tester,
      {bool tv = false, bool admin = false}) async {
    if (tv) {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: tv ? Alignment.bottomCenter : Alignment.topCenter,
          child: ItemActionsButton(
            tvOnly: tv,
            item: testItem(id: 'm1', name: 'Dune'),
            extra: [
              (
                label: 'Togli da Continua a guardare',
                icon: LucideIcons.history,
                onSelected: () {},
              ),
            ],
          ),
        ),
      ),
      tv: tv,
      surfaceSize: tv ? const Size(960, 540) : const Size(1440, 900),
      overrides: [
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            SessionSignedIn(JellyfinUser(
                id: 'u1',
                name: 'Mario',
                isAdministrator: admin,
                enableSubtitleManagement: true)))),
        ...socialTestOverrides(FakeSocialApi(),
            features: const SocialFeatures(reports: true), session: false),
      ],
    );
    await tester.tap(find.byType(ItemActionsButton));
    await tester.pumpAndSettle();
  }

  testWidgets('menu di un admin: gruppi con nome, icone e puntini',
      (tester) async {
    await pumpButton(tester, admin: true);
    final mine = tester.getTopLeft(find.text('La tua visione')).dy;
    final check = tester.getTopLeft(find.text('Controlla e segnala')).dy;
    final admin = tester.getTopLeft(find.text('Admin')).dy;
    expect(mine < check && check < admin, isTrue);
    expect(find.text('Togli da Continua a guardare'), findsOneWidget);
    for (final label in [
      'Segnala un problema…',
      'Info tecniche…',
      'Modifica metadati…',
      'Identifica…',
      'Locandina e sfondo…',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(PopupMenuDivider), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.ancestor(
                of: find.text('Identifica…'),
                matching: find.byType(PopupMenuItem<Object>)),
            matching: find.byIcon(LucideIcons.scanSearch)),
        findsOneWidget);
  });

  testWidgets('i nomi dei gruppi non si scelgono', (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controlla e segnala'));
    await tester.pumpAndSettle();
    expect(find.text('Info tecniche…'), findsOneWidget);
    expect(find.text('Aggiungi dettagli (facoltativo)'), findsNothing);
  });

  testWidgets('TV: voci di oggi, righe alte 44, menu sopra il ⋯ in fondo',
      (tester) async {
    await pumpButton(tester, tv: true, admin: true);
    expect(find.text('Togli da Continua a guardare'), findsOneWidget);
    expect(find.text('Segnala un problema…'), findsOneWidget);
    expect(find.text('Info tecniche…'), findsOneWidget);
    expect(find.text('Sottotitoli…'), findsNothing);
    expect(find.text('Admin'), findsNothing);
    final info = find.ancestor(
        of: find.text('Info tecniche…'),
        matching: find.byType(PopupMenuItem<Object>));
    expect(tester.widget<PopupMenuItem<Object>>(info).height, 44);
    final button = find.byType(ItemActionsButton);
    expect(tester.getBottomLeft(info).dy,
        lessThanOrEqualTo(tester.getTopLeft(button).dy));
    // Il primo elemento selezionabile ha il focus all'apertura.
    final first = find.ancestor(
        of: find.text('Togli da Continua a guardare'),
        matching: find.byType(InkWell));
    expect(Focus.of(tester.element(first.first)).hasFocus, isTrue);
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
    expect(find.text('Identifica…'), findsOneWidget);
    expect(find.text('Aggiorna metadati…'), findsOneWidget);
    expect(find.text('Locandina e sfondo…'), findsOneWidget);
    await tester.tap(find.text('Modifica metadati…'));
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
    await tester.tap(find.text('Identifica…'));
    await tester.pumpAndSettle();
    expect(find.text('Cerca'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nome'), findsOneWidget);
    expect(editApi.calls, ['rawItem m1']);
  });

  testWidgets('"Locandina e sfondo" apre la finestra', (tester) async {
    final editApi = FakeItemEditApi()
      ..items['m1'] = testRawItem(id: 'm1', name: 'Dune', type: 'Movie');
    await pumpDetail(tester, 'm1',
        editApi: editApi,
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Locandina e sfondo…'));
    await tester.pumpAndSettle();
    expect(find.text('Carica un file…'), findsOneWidget);
    expect(editApi.calls, ['remoteImages m1 Primary 0 false']);
  });

  testWidgets('"Aggiorna metadati…" apre la finestra e avvia il lavoro',
      (tester) async {
    final editApi = FakeItemEditApi()
      ..items['m1'] = testRawItem(id: 'm1', name: 'Dune', type: 'Movie');
    await pumpDetail(tester, 'm1',
        editApi: editApi,
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiorna metadati…'));
    await tester.pumpAndSettle();
    expect(find.text('Cosa aggiorno?'), findsOneWidget);
    await tester.tap(find.text('Completa i dati').last);
    await tester.pumpAndSettle();
    expect(editApi.calls.last, 'refresh m1 false false');
    // Il Timer del bump va fatto scadere: un Timer pendente fa fallire il test.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('un utente senza permessi admin non vede le voci dei metadati',
      (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica metadati…'), findsNothing);
    expect(find.text('Identifica…'), findsNothing);
  });

  testWidgets('"Segnala un problema" apre la finestra', (tester) async {
    await pumpDetail(tester, 'm1');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segnala un problema…'));
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
    await tester.tap(find.text('Info tecniche…'));
    await tester.pumpAndSettle();
    expect(find.text('mkv'), findsOneWidget);
  });

  testWidgets('il bottone su un episodio non fa partire la riproduzione',
      (tester) async {
    await pumpDetail(tester, 's1');
    // Uno per la stagione, uno per l'episodio.
    expect(find.byTooltip('Altre azioni'), findsNWidgets(3));
    final tile = find.ancestor(
        of: find.text('Episodio 1'), matching: find.byType(InkWell));
    final button = find.descendant(
        of: tile.first, matching: find.byTooltip('Altre azioni'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Il menu si apre; se il tocco arrivasse all'episodio, `playItem` senza
    // router lancerebbe e il test fallirebbe.
    expect(find.text('Info tecniche…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
