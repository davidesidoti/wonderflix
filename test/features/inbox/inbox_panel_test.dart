import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;
  late FakeSyncPlayApi syncPlay;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    syncPlay = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    syncPlay.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// Cinque minuti fa: l'ora relativa è "5 min fa" qualunque sia il giorno
  /// della prova.
  DateTime fiveMinutesAgo() =>
      clock.now().toUtc().subtract(const Duration(minutes: 5));

  Future<void> pumpPanel(WidgetTester tester,
      {List<GroupInfo> parties = const [],
      double width = InboxPanel.width,
      double textScale = 1}) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: width, child: const InboxPanel()),
            ),
          ),
        ),
      ),
      overrides: [
        ...socialTestOverrides(api,
            events: events.stream,
            features: const SocialFeatures(parties: true, inbox: true)),
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory(parties)),
        syncPlayApiProvider.overrideWithValue(syncPlay),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
      ],
    );
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));

  testWidgets('vuota: "Nessuna notifica", niente Svuota', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Notifiche'), findsOneWidget);
    expect(find.text('Nessuna notifica'), findsOneWidget);
    expect(find.text('Svuota'), findsNothing);
  });

  testWidgets('caricamento non riuscito: "Notifiche non disponibili" e Riprova',
      (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    expect(find.text('Notifiche non disponibili'), findsOneWidget);

    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stasera manutenzione'), findsOneWidget);
  });

  testWidgets('annuncio: etichetta, testo, ora; la × compare al passaggio e '
      'toglie la voce', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    expect(find.text('Annuncio'), findsOneWidget);
    expect(find.text('Stasera manutenzione'), findsOneWidget);
    expect(find.text('5 min fa'), findsOneWidget);

    Opacity removeOpacity() => tester.widget<Opacity>(find
        .ancestor(of: find.byTooltip('Rimuovi'), matching: find.byType(Opacity))
        .first);
    expect(removeOpacity().opacity, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Annuncio')));
    await tester.pump();
    expect(removeOpacity().opacity, 1);

    // Il plugin, dopo la rimozione, restituisce la cassetta senza la voce
    // (la rilettura dopo l'azione la rimette a posto).
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.byTooltip('Rimuovi'));
    await tester.pump();
    expect(api.calls, contains('remove-entry a1'));
    expect(find.text('Stasera manutenzione'), findsNothing);
  });

  testWidgets('× non riuscita: lo dice', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.network;
    await tester.tap(find.byTooltip('Rimuovi'));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile aggiornare le notifiche'),
        findsOneWidget);
  });

  testWidgets('invito: Unisciti se il party è nell\'elenco, altrimenti '
      '"Party finito"', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
      testInvite(
          id: 'i2',
          groupId: 'g2',
          title: 'Alien',
          createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester, parties: [testGroup()]);
    expect(find.text('Luigi ti invita a guardare'), findsNWidgets(2));
    expect(find.text('Dune'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i2')), findsNothing);
    expect(find.text('Party finito'), findsOneWidget);
  });

  testWidgets('invito: Unisciti entra e chiude il pannello; poi "Ci sei già"',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: [testGroup()]);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();

    await tester.tap(find.byKey(const Key('inbox-join-i1')));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, contains('join g1'));
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(find.text('Ci sei già'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsNothing);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('pallino dorato sulle voci non lette all\'apertura',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a2', seq: 2, createdAt: fiveMinutesAgo()),
      testAnnouncement(
          id: 'a1', seq: 1, read: true, createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('inbox-unread-a2')), findsOneWidget);
    expect(find.byKey(const Key('inbox-unread-a1')), findsNothing);
    expect(api.calls, contains('read 2'));
  });

  testWidgets('Svuota → Conferma per 4 s; Conferma svuota', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);

    await tester.tap(find.text('Svuota'));
    await tester.pump();
    expect(find.text('Conferma'), findsOneWidget);
    await tester.pump(InboxPanel.clearConfirmFor);
    expect(find.text('Svuota'), findsOneWidget);

    await tester.tap(find.text('Svuota'));
    await tester.pump();
    // Il plugin, dopo lo svuotamento, restituisce la cassetta vuota (la
    // rilettura dopo l'azione la rimette a posto).
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.text('Conferma'));
    await tester.pump();
    expect(api.calls, contains('clear-inbox'));
    expect(find.text('Nessuna notifica'), findsOneWidget);
  });

  /// Quante volte il server ha ricevuto "entra nel gruppo".
  int joinCalls() => syncPlay.calls.where((c) => c.startsWith('join')).length;

  /// Un invito per il gruppo `g1` nell'elenco e il pannello Notifiche aperto
  /// (come lo apre la barra).
  Future<ProviderContainer> pumpInvite(WidgetTester tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: [testGroup()]);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    return container;
  }

  testWidgets('invito: un secondo clic su Unisciti non entra due volte e il '
      'pannello si chiude solo a ingresso riuscito', (tester) async {
    // Il server non conferma finché non lo dice la prova.
    syncPlay.onCall = null;
    final container = await pumpInvite(tester);
    final join = find.byKey(const Key('inbox-join-i1'));

    await tester.tap(join);
    await tester.pump();
    expect(tester.widget<TextButton>(join).onPressed, isNull,
        reason: 'Unisciti è spento mentre si entra');
    await tester.tap(join);
    await tester.pump();
    expect(joinCalls(), 1);
    expect(container.read(shellPanelProvider), ShellPanel.inbox);

    events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
    await tester.pumpAndSettle();
    expect(joinCalls(), 1);
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(find.text('Ci sei già'), findsOneWidget);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('invito: Unisciti non riuscito lascia il pannello aperto, lo '
      'dice, rilegge l\'elenco e si può riprovare', (tester) async {
    syncPlay.onCall = null;
    syncPlay.error = const ServerUnreachableException();
    final container = await pumpInvite(tester);
    final directory = container.read(watchPartyDirectoryProvider.notifier)
        as FakeWatchPartyDirectory;
    final refreshed = directory.refreshCalls;

    await tester.tap(find.byKey(const Key('inbox-join-i1')));
    await tester.pumpAndSettle();
    expect(joinCalls(), 1);
    expect(find.text('Non è stato possibile entrare nel watch party.'),
        findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.inbox);
    expect(directory.refreshCalls, refreshed + 1);
    expect(
        tester
            .widget<TextButton>(find.byKey(const Key('inbox-join-i1')))
            .onPressed,
        isNotNull);
  });

  testWidgets('invito: il nome di chi invita è in grassetto', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: [testGroup()]);
    expect(find.text('Luigi ti invita a guardare'), findsOneWidget);

    final texts = tester.widgetList<RichText>(find.descendant(
        of: find.byKey(const ValueKey('inbox-i1')),
        matching: find.byType(RichText)));
    var boldName = false;
    var plainRest = false;
    for (final rich in texts) {
      rich.text.visitChildren((span) {
        if (span is! TextSpan) return true;
        if (span.text == 'Luigi' && span.style?.fontWeight == FontWeight.w600) {
          boldName = true;
        }
        if (span.text == ' ti invita a guardare' && span.style == null) {
          plainRest = true;
        }
        return true;
      });
    }
    expect(boldName, isTrue);
    expect(plainRest, isTrue);
  });

  testWidgets('invito: con font grandi e poco spazio lo stato non va fuori '
      'dal riquadro', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
      testInvite(
          id: 'i2',
          groupId: 'g2',
          title: 'Alien',
          createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester,
        parties: [testGroup()], width: 300, textScale: 2);
    expect(find.byKey(const Key('inbox-join-i1')), findsOneWidget);
    expect(find.text('Party finito'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tastiera: con Tab il fuoco arriva alla × della voce, che si '
      'vede; Invio la toglie', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);

    Opacity removeOpacity() => tester.widget<Opacity>(find
        .ancestor(of: find.byTooltip('Rimuovi'), matching: find.byType(Opacity))
        .first);
    expect(removeOpacity().opacity, 0);
    for (var i = 0; i < 6 && removeOpacity().opacity == 0; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(removeOpacity().opacity, 1);

    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(api.calls, contains('remove-entry a1'));
    expect(find.text('Stasera manutenzione'), findsNothing);
  });

  testWidgets('la × della voce resta nella semantica anche se non si vede',
      (tester) async {
    final semantics = tester.ensureSemantics();
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    // Trasparente finché non ha il mouse o il fuoco, ma il nodo c'è.
    final node = tester.getSemantics(find.byTooltip('Rimuovi'));
    expect(node.getSemanticsData().tooltip, 'Rimuovi');
    semantics.dispose();
  });

  testWidgets('novità: riepilogo, prime 5 righe, Mostra tutto, altri titoli',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testNewTitles(
        createdAt: fiveMinutesAgo(),
        movies: [
          for (var i = 1; i <= 4; i++)
            NewTitleMovie(itemId: 'm$i', name: 'Film $i', year: 2020 + i),
        ],
        series: const [
          NewTitleSeries(seriesId: 's1', name: 'The Bear', episodes: [
            NewTitleEpisode(season: 3, episode: 1),
            NewTitleEpisode(season: 3, episode: 2),
          ]),
          NewTitleSeries(seriesId: 's2', name: 'Senza numeri', episodes: [
            NewTitleEpisode(),
            NewTitleEpisode(season: 1, episode: 4),
          ]),
        ],
        more: 7,
      ),
    ], unread: 1);
    await pumpPanel(tester);

    expect(find.text('Novità: 4 film, 4 episodi'), findsOneWidget);
    expect(find.text('Film 1 (2021)'), findsOneWidget);
    expect(find.text('The Bear · S3 E1–E2'), findsOneWidget);
    expect(find.text('Senza numeri · 2 episodi nuovi'), findsNothing,
        reason: 'sesta riga, nascosta');
    expect(find.text('…e altri 7 titoli'), findsOneWidget);
    expect(find.text('5 min fa'), findsOneWidget);

    await tester.tap(find.text('Mostra tutto (6)'));
    await tester.pump();

    expect(find.text('Senza numeri · 2 episodi nuovi'), findsOneWidget);
    expect(find.text('Mostra tutto (6)'), findsNothing);
  });

  testWidgets('novità: con esattamente 5 righe niente Mostra tutto',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testNewTitles(
        createdAt: fiveMinutesAgo(),
        movies: [
          for (var i = 1; i <= InboxPanel.newTitlesPreview; i++)
            NewTitleMovie(itemId: 'm$i', name: 'Film $i'),
        ],
      ),
    ], unread: 1);
    await pumpPanel(tester);

    expect(find.textContaining('Mostra tutto'), findsNothing);
    for (var i = 1; i <= InboxPanel.newTitlesPreview; i++) {
      expect(find.text('Film $i'), findsOneWidget);
    }
  });

  testWidgets('novità: Mostra tutto porta il fuoco sulla prima riga nuova',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testNewTitles(
        createdAt: fiveMinutesAgo(),
        movies: [
          for (var i = 1; i <= InboxPanel.newTitlesPreview + 2; i++)
            NewTitleMovie(itemId: 'm$i', name: 'Film $i'),
        ],
      ),
    ], unread: 1);
    await pumpPanel(tester);

    // Da tastiera: il fuoco è sul bottone, poi Invio lo attiva.
    Focus.of(tester.element(find.text('Mostra tutto (7)'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    final firstNew = find.byKey(
        Key('inbox-title-m${InboxPanel.newTitlesPreview + 1}'));
    expect(firstNew, findsOneWidget);
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(
        find.descendant(
            of: firstNew,
            matching: find.byWidgetPredicate((widget) =>
                widget is Focus && widget.focusNode == focused)),
        findsOneWidget,
        reason: 'il fuoco è sulla sesta riga, non perso');
  });

  testWidgets('novità solo di film o solo di episodi', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testNewTitles(id: 'n1', seq: 2, createdAt: fiveMinutesAgo(), movies: const [
        NewTitleMovie(itemId: 'm1', name: 'Senza anno'),
      ]),
      testNewTitles(id: 'n2', seq: 1, createdAt: fiveMinutesAgo(), series: const [
        NewTitleSeries(seriesId: 's1', name: 'The Bear', episodes: [
          NewTitleEpisode(season: 1, episode: 1),
        ]),
      ]),
    ], unread: 2);
    await pumpPanel(tester);

    expect(find.text('Novità: 1 film'), findsOneWidget);
    expect(find.text('Senza anno'), findsOneWidget);
    expect(find.text('Novità: 1 episodio'), findsOneWidget);
    expect(find.textContaining('Mostra tutto'), findsNothing);
  });
}
