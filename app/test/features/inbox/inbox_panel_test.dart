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
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';
import 'package:wonderflix/ui/sender_avatar.dart';

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
      double textScale = 1,
      bool admin = false}) async {
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
        isAdminProvider.overrideWithValue(admin),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
      ],
    );
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));

  const emptyText =
      'Niente di nuovo. Gli inviti e i consigli degli amici arrivano qui.';

  testWidgets('vuota: la frase che invita, niente Svuota tutto',
      (tester) async {
    await pumpPanel(tester);
    expect(find.text('Notifiche'), findsOneWidget);
    expect(find.text(emptyText), findsOneWidget);
    expect(find.text('Svuota tutto'), findsNothing);
  });

  testWidgets('caricamento non riuscito: la frase e Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    expect(
        find.text('Non riesco a leggere le notifiche. Controlla la '
            'connessione e riprova.'),
        findsOneWidget);

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
        .ancestor(of: find.byTooltip('Togli dalla lista'), matching: find.byType(Opacity))
        .first);
    expect(removeOpacity().opacity, 0.4);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Annuncio')));
    await tester.pump();
    expect(removeOpacity().opacity, 1);

    // Il plugin, dopo la rimozione, restituisce la cassetta senza la voce
    // (la rilettura dopo l'azione la rimette a posto).
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.byTooltip('Togli dalla lista'));
    await tester.pump();
    expect(api.calls, contains('remove-entry a1'));
    expect(find.text('Stasera manutenzione'), findsNothing);
  });

  testWidgets('× non riuscita: lo dice', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.network;
    await tester.tap(find.byTooltip('Togli dalla lista'));
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
    expect(find.text('Luigi ti invita a guardare Dune'), findsOneWidget);
    expect(find.text('Luigi ti invita a guardare Alien'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i2')), findsNothing);
    expect(find.text('5 min fa · 1 nel party'), findsOneWidget);
    expect(find.text('5 min fa · Party finito'), findsOneWidget);
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
    expect(find.text('5 min fa · Ci sei già'), findsOneWidget);
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
    Finder dotOf(String id) => find.descendant(
        of: find.byKey(ValueKey('inbox-$id')),
        matching: find.byKey(const Key('inbox-unread')));
    expect(dotOf('a2'), findsOneWidget);
    expect(dotOf('a1'), findsNothing);
    expect(api.calls, contains('read 2'));
  });

  testWidgets('Svuota tutto → Svuota tutto? per 4 s; chi non è admin: Sì, '
      'svuota svuota tutto', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);

    await tester.tap(find.text('Svuota tutto'));
    await tester.pump();
    expect(find.text('Svuota tutto?'), findsOneWidget);
    expect(find.byKey(const Key('inbox-clear-confirm')), findsOneWidget);
    await tester.pump(InboxPanel.clearConfirmFor);
    expect(find.text('Svuota tutto'), findsOneWidget);
    expect(find.text('Sì, svuota'), findsNothing);

    await tester.tap(find.text('Svuota tutto'));
    await tester.pump();
    // Il plugin, dopo lo svuotamento, restituisce la cassetta vuota (la
    // rilettura dopo l'azione la rimette a posto).
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.text('Sì, svuota'));
    await tester.pump();
    expect(api.calls, contains('clear-inbox'));
    expect(find.text(emptyText), findsOneWidget);
  });

  testWidgets('gruppi: Oggi, Ieri, Prima', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 16, 12)), () async {
      api.inboxSnapshot = InboxSnapshot(entries: [
        testAnnouncement(id: 'a3', seq: 3, createdAt: DateTime(2026, 11, 16, 9)),
        testAnnouncement(id: 'a2', seq: 2, createdAt: DateTime(2026, 11, 15, 9)),
        testAnnouncement(id: 'a1', seq: 1, createdAt: DateTime(2026, 11, 1, 9)),
      ], unread: 0);
      await pumpPanel(tester);
      expect(find.text('Oggi'), findsOneWidget);
      expect(find.text('Ieri'), findsOneWidget);
      expect(find.text('Prima'), findsOneWidget);
      expect(find.text('Questa settimana'), findsNothing);
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      double entryY(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('inbox-$id'))).dy;
      expect(y('Oggi'), lessThan(entryY('a3')));
      expect(entryY('a3'), lessThan(y('Ieri')));
      expect(y('Ieri'), lessThan(entryY('a2')));
      expect(entryY('a2'), lessThan(y('Prima')));
      expect(y('Prima'), lessThan(entryY('a1')));
    });
  });

  testWidgets('chi non è admin non vede Per te · Server, e vede tutto',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2, createdAt: fiveMinutesAgo()),
      testRequestPending(id: 'p1', seq: 1, createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester);
    expect(find.text('Per te'), findsNothing);
    expect(find.text('Server'), findsNothing);
    expect(find.byKey(const ValueKey('inbox-i1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-p1')), findsOneWidget);
  });

  /// Admin col pannello aperto: un invito, una richiesta e un riavvio, tutti
  /// non letti.
  Future<void> pumpAdmin(WidgetTester tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 3, createdAt: fiveMinutesAgo()),
      testRequestPending(id: 'p1', seq: 2, createdAt: fiveMinutesAgo()),
      RestartPendingEntry(
          id: 'r1', seq: 1, createdAt: fiveMinutesAgo(), read: false),
    ], unread: 3);
    await pumpPanel(tester, admin: true);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    await tester.pump();
  }

  const serverHint = 'Avvisi per gli admin: download, spazio, riavvii, '
      'recupero account, richieste in attesa e segnalazioni.';

  testWidgets('admin: le voci del server stanno in Server, col numero',
      (tester) async {
    await pumpAdmin(tester);
    final you = find.byKey(const Key('inbox-view-you'));
    final server = find.byKey(const Key('inbox-view-server'));
    expect(find.descendant(of: you, matching: find.text('Per te')),
        findsOneWidget);
    expect(find.descendant(of: you, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: server, matching: find.text('Server')),
        findsOneWidget);
    expect(
        find.descendant(of: server, matching: find.text('2')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-i1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-p1')), findsNothing);
    expect(find.text(serverHint), findsNothing);

    await tester.tap(server);
    await tester.pump();
    expect(find.byKey(const ValueKey('inbox-i1')), findsNothing);
    expect(find.byKey(const ValueKey('inbox-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-r1')), findsOneWidget);
    expect(find.text(serverHint), findsOneWidget);
  });

  testWidgets('admin: Svuota tutto in Server toglie solo quelle',
      (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('inbox-view-server')));
    await tester.pump();
    await tester.tap(find.text('Svuota tutto'));
    await tester.pump();
    expect(find.text('Svuota tutto?'), findsOneWidget);
    // Il plugin, dopo, ha solo l'invito.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 3, read: true, createdAt: fiveMinutesAgo()),
    ], unread: 0);
    await tester.tap(find.text('Sì, svuota'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, containsAll(['remove-entry p1', 'remove-entry r1']));
    expect(api.calls, isNot(contains('clear-inbox')));
    expect(find.text('Nessun avviso del server.'), findsOneWidget);
    expect(find.text('Svuota tutto'), findsNothing);

    await tester.tap(find.byKey(const Key('inbox-view-you')));
    await tester.pump();
    expect(find.byKey(const ValueKey('inbox-i1')), findsOneWidget);
  });

  testWidgets('admin: Svuota tutto non riuscito lo dice e torna come sul '
      'plugin', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('inbox-view-server')));
    await tester.pump();
    await tester.tap(find.text('Svuota tutto'));
    await tester.pump();
    api.nextFailure = SocialFailure.network;
    await tester.tap(find.text('Sì, svuota'));
    await tester.pump(); // azione e rilettura
    await tester.pump(); // snackbar
    await tester.pump(const Duration(milliseconds: 750)); // entrata
    expect(api.calls, isNot(contains('remove-entry r1')));
    expect(find.text('Non è stato possibile aggiornare le notifiche'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-r1')), findsOneWidget);
  });

  testWidgets('admin con Per te vuota: Svuota tutto toglie solo le voci '
      'viste, mai tutta la cassetta', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestPending(id: 'p1', seq: 1, createdAt: fiveMinutesAgo()),
    ], unread: 0);
    await pumpPanel(tester, admin: true);
    await tester.tap(find.byKey(const Key('inbox-view-server')));
    await tester.pump();
    await tester.tap(find.text('Svuota tutto'));
    await tester.pump();
    api.inboxSnapshot = InboxSnapshot.empty;
    await tester.tap(find.text('Sì, svuota'));
    await tester.pump();
    expect(api.calls, contains('remove-entry p1'));
    expect(api.calls, isNot(contains('clear-inbox')));
  });

  /// Quante volte il server ha ricevuto "entra nel gruppo".
  int joinCalls() => syncPlay.calls.where((c) => c.startsWith('join')).length;

  /// Un invito per il gruppo `g1` nell'elenco e il pannello Notifiche aperto
  /// (come lo apre la barra).
  Future<ProviderContainer> pumpInvite(WidgetTester tester,
      {List<GroupInfo>? parties}) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: parties ?? [testGroup()]);
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
    expect(find.text('5 min fa · Ci sei già'), findsOneWidget);

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

  testWidgets('invito: il nome di chi invita e il titolo sono in grassetto',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: [testGroup()]);
    expect(find.text('Luigi ti invita a guardare Dune'), findsOneWidget);

    final texts = tester.widgetList<RichText>(find.descendant(
        of: find.byKey(const ValueKey('inbox-i1')),
        matching: find.byType(RichText)));
    var boldName = false;
    var boldTitle = false;
    var plainRest = false;
    for (final rich in texts) {
      rich.text.visitChildren((span) {
        if (span is! TextSpan) return true;
        if (span.text == 'Luigi' && span.style?.fontWeight == FontWeight.w700) {
          boldName = true;
        }
        if (span.text == 'Dune' && span.style?.fontWeight == FontWeight.w700) {
          boldTitle = true;
        }
        if (span.text == ' ti invita a guardare ' && span.style == null) {
          plainRest = true;
        }
        return true;
      });
    }
    expect(boldName, isTrue);
    expect(boldTitle, isTrue);
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
    expect(find.text('5 min fa · Party finito'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tastiera: con Tab il fuoco arriva alla × della voce, che si '
      'vede; Invio la toglie', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);

    Opacity removeOpacity() => tester.widget<Opacity>(find
        .ancestor(of: find.byTooltip('Togli dalla lista'), matching: find.byType(Opacity))
        .first);
    expect(removeOpacity().opacity, 0.4);
    for (var i = 0; i < 6 && removeOpacity().opacity < 1; i++) {
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
    // Attenuata finché non ha il mouse o il fuoco, ma il nodo c'è.
    final node = tester.getSemantics(find.byTooltip('Togli dalla lista'));
    expect(node.getSemanticsData().tooltip, 'Togli dalla lista');
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
    expect(find.text('The Bear · S3:E1–E2'), findsOneWidget);
    expect(find.text('Senza numeri · 2 episodi nuovi'), findsNothing,
        reason: 'sesta riga, nascosta');
    expect(find.text('…e altri 7 titoli'), findsOneWidget);
    expect(find.text('5 min fa'), findsOneWidget);
    // Ogni riga con la sua locandina 24×36; le novità non hanno "Apri".
    expect(
        find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 24 && w.height == 36),
        findsNWidgets(InboxPanel.newTitlesPreview));
    expect(find.text('Apri'), findsNothing);

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

  testWidgets('richieste: "Ora disponibile" e "ha chiesto", con le stagioni',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestAvailable(
          id: 'r1',
          seq: 2,
          title: 'Brothers (2026)',
          seasons: const [1, 2],
          createdAt: fiveMinutesAgo()),
      testRequestPending(id: 'p1', seq: 1, createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester);

    expect(find.text('Ora disponibile: Brothers (2026), stagioni 1–2'), findsOneWidget);
    expect(find.text('Garg ha chiesto Dune (2021)'), findsOneWidget);
    expect(find.text('5 min fa'), findsNWidgets(2));
  });

  testWidgets('"ha chiesto" con le stagioni: "Garg ha chiesto Brothers (2026), stagioni 1–2"',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestPending(
          title: 'Brothers (2026)',
          seasons: const [1, 2],
          createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester);

    expect(find.text('Garg ha chiesto Brothers (2026), stagioni 1–2'),
        findsOneWidget);
  });

  testWidgets('"ha chiesto" senza il nome di chi chiede: "Nuova richiesta"',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestPending(
          id: 'p1', seq: 2, requesterName: '', createdAt: fiveMinutesAgo()),
      testRequestPending(
          id: 'p2',
          seq: 1,
          requesterName: '  ',
          title: 'Brothers (2026)',
          createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester);

    expect(find.text('Nuova richiesta: Dune (2021)'), findsOneWidget);
    expect(find.text('Nuova richiesta: Brothers (2026)'), findsOneWidget);
    expect(find.textContaining('ha chiesto'), findsNothing);
  });

  testWidgets('un titolo molto lungo: al massimo tre righe con i puntini',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestAvailable(
          title: 'Un titolo lunghissimo ' * 10,
          seasons: const [1, 2, 3],
          createdAt: fiveMinutesAgo()),
      testRequestPending(
          id: 'p1',
          seq: 2,
          title: 'Un titolo lunghissimo ' * 10,
          createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester);

    for (final id in ['r1', 'p1']) {
      final text = tester.widget<Text>(find.descendant(
          of: find.byKey(Key('inbox-request-$id')),
          matching: find.textContaining('Un titolo lunghissimo')));
      expect(text.maxLines, 3, reason: id);
      expect(text.overflow, TextOverflow.ellipsis, reason: id);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('invito: avatar con la locandina, frase unica, "2 nel party"',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(fromName: 'Luigi', title: 'Dune', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester,
        parties: [testGroup(id: 'g1', participants: ['Luigi', 'Peach'])]);
    expect(find.text('Luigi ti invita a guardare Dune', findRichText: true),
        findsOneWidget);
    expect(find.text('5 min fa · 2 nel party'), findsOneWidget);
    expect(find.byType(SenderAvatar), findsOneWidget);
    expect(find.byKey(const Key('sender-poster')), findsOneWidget);
    expect(find.text('Unisciti'), findsOneWidget);

    // L'azione sta sul bordo destro della riga dell'ora e l'ora prende
    // tutto lo spazio fino all'azione, non metà riga. (Col font dei test,
    // un em per lettera, la misura del testo non direbbe niente.)
    final meta = find.text('5 min fa · 2 nel party');
    final join = find.byKey(const Key('inbox-join-i1'));
    final metaRow =
        find.ancestor(of: meta, matching: find.byType(Row)).first;
    expect(tester.getTopRight(join).dx,
        moreOrLessEquals(tester.getTopRight(metaRow).dx, epsilon: 2));
    expect(tester.getTopRight(meta).dx,
        moreOrLessEquals(tester.getTopLeft(join).dx, epsilon: 2));
  });

  testWidgets('invito: Unisciti non è un passo in più per Tab, ma si preme',
      (tester) async {
    final container = await pumpInvite(tester);
    final join = find.byKey(const Key('inbox-join-i1'));
    expect(
        find.ancestor(of: join, matching: find.byType(ExcludeFocus)),
        findsOneWidget);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(syncPlay.calls, contains('join g1'));
    expect(container.read(shellPanelProvider), ShellPanel.none);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('invito a un party finito: la riga non apre niente',
      (tester) async {
    final container = await pumpInvite(tester, parties: const []);
    expect(find.text('5 min fa · Party finito'), findsOneWidget);
    expect(find.text('Unisciti'), findsNothing);
    await tester.tap(find.text('Luigi ti invita a guardare Dune'));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, isEmpty);
    expect(container.read(shellPanelProvider), ShellPanel.inbox);
  });

  testWidgets('invito: toccare la riga entra come Unisciti', (tester) async {
    final container = await pumpInvite(tester);
    await tester.tap(find.text('Luigi ti invita a guardare Dune'));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, contains('join g1'));
    expect(container.read(shellPanelProvider), ShellPanel.none);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('annuncio: niente azione, la riga non apre', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    expect(find.text('Apri'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is SystemAvatar && !w.alarm),
        findsOneWidget);
    expect(
        tester
            .widget<InkWell>(find
                .ancestor(
                    of: find.text('Annuncio'), matching: find.byType(InkWell))
                .first)
            .onTap,
        isNull);
  });

  testWidgets('richiesta in attesa: avatar di chi chiede, senza nome il '
      'cerchio del sistema; Apri su tutte e due', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testRequestPending(id: 'p1', seq: 2, createdAt: fiveMinutesAgo()),
      testRequestPending(
          id: 'p2', seq: 1, requesterName: '', createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester);
    expect(find.byType(SenderAvatar), findsOneWidget);
    expect(find.byType(SystemAvatar), findsOneWidget);
    expect(find.text('Apri'), findsNWidgets(2));

    // Un'azione corta resta sul bordo destro, non a metà riga.
    final open = find
        .ancestor(of: find.text('Apri').first, matching: find.byType(TextButton))
        .first;
    final metaRow = find
        .ancestor(of: find.text('5 min fa').first, matching: find.byType(Row))
        .first;
    expect(tester.getTopRight(open).dx,
        moreOrLessEquals(tester.getTopRight(metaRow).dx, epsilon: 2));
  });
}
