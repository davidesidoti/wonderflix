import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_chat_bubble.dart';
import 'package:wonderflix/features/watch_party/party_chat_layer.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late StreamController<ServerEvent> events;
  late ValueNotifier<bool> open;

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi()..install();
    events = StreamController<ServerEvent>.broadcast();
    open = ValueNotifier(false);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined(
            'g1', testGroup(participants: ['Mario', 'Luigi']))));
      }
    };
  });

  tearDown(() => events.close());

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PartyChatLayer)));

  PartyChannelState channel(WidgetTester tester) =>
      container(tester).read(partyChannelProvider);

  /// Il livello della chat in basso a sinistra, nel gruppo `g1` con il
  /// canale attivo. [open] decide se è aperta.
  Future<void> pumpChat(WidgetTester tester) async {
    // Il focus del campo è di chi monta la chat, come nel player.
    final focusNode = FocusNode(debugLabel: 'party-chat');
    addTearDown(focusNode.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Stack(children: [
          Positioned(
            left: PartyChatLayer.left,
            bottom: PartyChatLayer.bottom,
            child: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, isOpen, _) => PartyChatLayer(
                open: isOpen,
                focusNode: focusNode,
                onOpen: () => open.value = true,
                onClose: () => open.value = false,
              ),
            ),
          ),
        ]),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider.overrideWithValue(channelApi),
      ],
    );
    unawaited(
        container(tester).read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    expect(channel(tester).active, isTrue);
  }

  /// Esce dal gruppo: l'orologio del gruppo non deve lasciare timer.
  Future<void> leave(WidgetTester tester) async {
    await container(tester).read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  Future<void> receive(WidgetTester tester, String text,
      {required String id, String userId = 'u2', String userName = 'Luigi'}) async {
    events.add(PartyChannelReceived(partyPayload({'Type': 'Chat', 'Text': text},
        id: id, userId: userId, userName: userName)));
    await tester.pump();
    await tester.pump();
  }

  Finder bubbles() => find.byType(PartyChatBubble);

  group('ChatLengthFormatter: limite di 200 (spec E §9.3)', () {
    const formatter = ChatLengthFormatter();

    /// Testo [before] + [after] con il cursore in mezzo.
    TextEditingValue at(String before, String after) => TextEditingValue(
        text: '$before$after',
        selection: TextSelection.collapsed(offset: before.length));

    test('sotto il limite non cambia nulla', () {
      final old = at('a' * 100, 'b' * 50);
      final typed = at('${'a' * 100}x', 'b' * 50);
      expect(formatter.formatEditUpdate(old, typed), same(typed));
    });

    test('al limite un tasto in mezzo non entra e la coda resta', () {
      final old = at('a' * 100, 'b' * (maxChatLength - 100));
      final typed = at('${'a' * 100}x', 'b' * (maxChatLength - 100));
      final result = formatter.formatEditUpdate(old, typed);
      expect(result.text, old.text);
      expect(result.selection, old.selection);
    });

    test('un incolla che sfora si taglia nel punto di inserimento', () {
      // 190 punti di codice: ne entrano 10, a punti di codice (emoji).
      final old = at('a' * 10, 'b' * 180);
      final pasted = at('${'a' * 10}${'😂' * 20}', 'b' * 180);
      final result = formatter.formatEditUpdate(old, pasted);
      expect(result.text, '${'a' * 10}${'😂' * 10}${'b' * 180}');
      expect(chatTextLength(result.text), maxChatLength);
      expect(result.selection,
          TextSelection.collapsed(offset: 10 + '😂'.length * 10));
    });

    test('al limite un incolla sopra una selezione la sostituisce fino al '
        'limite', () {
      final old = TextEditingValue(
          text: 'a' * maxChatLength,
          selection: const TextSelection(baseOffset: 50, extentOffset: 55));
      final pasted = at('${'a' * 50}${'x' * 8}', 'a' * (maxChatLength - 55));
      final result = formatter.formatEditUpdate(old, pasted);
      expect(result.text,
          '${'a' * 50}${'x' * 5}${'a' * (maxChatLength - 55)}');
      expect(result.selection, const TextSelection.collapsed(offset: 55));
    });
  });

  group('chat chiusa: bolle (spec E §9.2)', () {
    testWidgets('nome e testo; spariscono dopo 8 s', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao a tutti', id: 'c1');
      expect(bubbles(), findsOneWidget);
      expect(find.textContaining('Luigi'), findsOneWidget);
      expect(find.textContaining('ciao a tutti'), findsOneWidget);
      await tester.pump(PartyChatLayer.bubbleLifetime -
          const Duration(milliseconds: 1));
      expect(bubbles(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      // L'uscita è finita solo oltre la sua durata (la simulazione di un
      // `AnimationController` finisce quando il tempo la supera).
      await tester.pump(WfMotion.fast + const Duration(milliseconds: 1));
      await tester.pump();
      expect(bubbles(), findsNothing);
      await leave(tester);
    });

    testWidgets('al massimo 3: la più vecchia lascia il posto',
        (tester) async {
      await pumpChat(tester);
      for (var i = 1; i <= 4; i++) {
        await receive(tester, 'messaggio $i', id: 'c$i');
      }
      expect(bubbles(), findsNWidgets(PartyChatLayer.maxBubbles));
      expect(find.textContaining('messaggio 1'), findsNothing);
      expect(find.textContaining('messaggio 4'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('i nostri da un altro PC: "Tu"', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'dal portatile',
          id: 'c1', userId: 'u1', userName: 'Mario');
      expect(find.textContaining('Tu'), findsOneWidget);
      expect(find.textContaining('Mario'), findsNothing);
      await leave(tester);
    });

    testWidgets('a schermo i messaggi non contano come non letti',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao', id: 'c1');
      expect(channel(tester).unread, 0);
      await leave(tester);
    });

    testWidgets('una bolla il cui messaggio sparisce lascia il posto',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'uno', id: 'c1');
      // Un nostro messaggio mandato a chat chiusa, che poi non parte: sparisce
      // dallo storico, e con lui la bolla.
      channelApi.sendGate = Completer<void>();
      channelApi.sendFailures.add(PartyChannelFailure.network);
      final sending =
          container(tester).read(partyChannelProvider.notifier).sendChat('perso');
      await tester.pump();
      expect(find.textContaining('perso'), findsOneWidget);
      await receive(tester, 'due', id: 'c2');
      channelApi.sendGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(await sending, PartyChatSendResult.failed);
      expect(find.textContaining('perso'), findsNothing);
      // Il suo posto è libero: "uno" resta con gli altri due.
      await receive(tester, 'tre', id: 'c3');
      expect(bubbles(), findsNWidgets(PartyChatLayer.maxBubbles));
      expect(find.textContaining('uno'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('le bolle non prendono i clic', (tester) async {
      await pumpChat(tester);
      await receive(tester, 'ciao', id: 'c1');
      expect(
          find.ancestor(of: bubbles(), matching: find.byType(IgnorePointer)),
          findsWidgets);
      await leave(tester);
    });
  });

  Finder field() => find.byKey(const Key('party-chat-field'));

  Future<void> openChat(WidgetTester tester) async {
    open.value = true;
    await tester.pump();
    await tester.pump();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();
  }

  group('chat aperta (spec E §9.3, §9.4)', () {
    testWidgets('campo a fuoco e storico al posto delle bolle',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'primo', id: 'c1');
      await receive(tester, 'secondo', id: 'c2');
      await openChat(tester);
      expect(field(), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'party-chat');
      expect(find.byKey(const Key('party-chat-history')), findsOneWidget);
      expect(find.textContaining('primo'), findsOneWidget);
      expect(find.textContaining('secondo'), findsOneWidget);
      expect(find.byType(PartyChatBubble), findsNothing);
      await leave(tester);
    });

    testWidgets('Invio manda: in attesa, poi confermato; il campo si svuota',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      channelApi.sendGate = Completer<void>();
      await send(tester, 'che scena');
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'party-chat',
          reason: 'si continua a scrivere');
      Finder pending() => find.byWidgetPredicate((widget) =>
          widget is Opacity &&
          widget.opacity == PartyChatMessage.pendingOpacity);
      expect(find.textContaining('che scena'), findsOneWidget);
      expect(pending(), findsOneWidget);
      channelApi.sendGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(pending(), findsNothing);
      expect(find.textContaining('che scena'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('Invio a campo vuoto chiude', (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await send(tester, '   ');
      expect(open.value, isFalse);
      expect(field(), findsNothing);
      expect(channelApi.sent, isEmpty);
      await leave(tester);
    });

    testWidgets('troppi messaggi: testo rimesso e riga rossa, che sparisce '
        'al tasto dopo', (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      channelApi.sendFailures.add(PartyChannelFailure.rateLimited);
      await send(tester, 'ciao');
      expect(tester.widget<TextField>(field()).controller!.text, 'ciao');
      expect(find.text('Troppi messaggi, aspetta un attimo'), findsOneWidget);
      await tester.enterText(field(), 'ciao!');
      await tester.pump();
      expect(find.text('Troppi messaggi, aspetta un attimo'), findsNothing);
      await leave(tester);
    });

    testWidgets('invio fallito a chat chiusa: si riapre con il testo',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      channelApi.sendGate = Completer<void>();
      channelApi.sendFailures.add(PartyChannelFailure.network);
      await send(tester, 'ci siete?');
      open.value = false;
      await tester.pump();
      channelApi.sendGate!.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(open.value, isTrue);
      expect(tester.widget<TextField>(field()).controller!.text, 'ci siete?');
      expect(find.text('Non inviato, riprova'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('contatore da 180; limite di 200 punti di codice',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await tester.enterText(field(), 'x' * 179);
      await tester.pump();
      expect(find.text('179/200'), findsNothing);
      await tester.enterText(field(), 'x' * 180);
      await tester.pump();
      expect(find.text('180/200'), findsOneWidget);
      await tester.enterText(field(), '😂' * 250);
      await tester.pump();
      expect(
          tester.widget<TextField>(field()).controller!.text.runes.length, 200);
      await leave(tester);
    });

    testWidgets('a campo vuoto si chiude da sola dopo 20 s; con del testo no',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await tester.pump(PartyChatLayer.idleClose);
      expect(open.value, isFalse);
      await openChat(tester);
      await tester.enterText(field(), 'sto scrivendo');
      await tester.pump(PartyChatLayer.idleClose + const Duration(seconds: 1));
      expect(open.value, isTrue);
      await leave(tester);
    });

    testWidgets('aprire la chat azzera i non letti', (tester) async {
      await pumpChat(tester);
      final notifier = container(tester).read(partyChannelProvider.notifier)
        // Come fuori dal player: nessun livello chat a schermo.
        ..detachChatLayer();
      await receive(tester, 'mentre eri via', id: 'c1');
      expect(channel(tester).unread, 1);
      notifier.attachChatLayer();
      await openChat(tester);
      expect(channel(tester).unread, 0);
      await leave(tester);
    });

    Finder history() => find.byKey(const Key('party-chat-history'));
    Finder line(String key) => find.byKey(ValueKey('party-chat-line-$key'));

    /// Storico di 40 messaggi: brevi i vecchi, lunghi (molte righe) i più
    /// nuovi, così le altezze stimate dalla lista sono sbagliate.
    void longHistory() {
      final start = DateTime.utc(2026, 10, 2, 20);
      channelApi.history = [
        for (var i = 1; i <= 40; i++)
          testChatEvent(i <= 30 ? 'breve $i' : 'lungo $i ${'parola ' * 30}',
              id: 'h$i', sentAt: start.add(Duration(seconds: i))),
      ];
    }

    /// La riga del messaggio [key] è l'ultima, visibile in fondo allo
    /// storico.
    void expectAtBottom(WidgetTester tester, String key) {
      expect(line(key), findsOneWidget);
      final bottom = tester.getRect(history()).bottom;
      final rect = tester.getRect(line(key));
      expect(rect.bottom, lessThanOrEqualTo(bottom));
      expect(rect.bottom, greaterThan(bottom - 8));
    }

    testWidgets('storico ancorato in fondo: il più nuovo sopra il campo, '
        'anche con molti messaggi', (tester) async {
      longHistory();
      await pumpChat(tester);
      await openChat(tester);
      expectAtBottom(tester, 'h40');
      expect(
          tester.getRect(line('h40')).bottom,
          lessThan(tester.getRect(field()).top),
          reason: 'lo storico sta sopra il campo');
      await receive(tester, 'eccomi', id: 'c1');
      expectAtBottom(tester, 'c1');
      await leave(tester);
    });

    testWidgets('storico corto: stretto sopra il campo, il più nuovo in fondo',
        (tester) async {
      await pumpChat(tester);
      await receive(tester, 'primo', id: 'c1');
      await receive(tester, 'secondo', id: 'c2');
      await openChat(tester);
      expectAtBottom(tester, 'c2');
      final box = tester.getRect(history());
      expect(tester.getRect(line('c1')).top, greaterThan(box.top),
          reason: 'il più vecchio in cima, dentro lo storico');
      expect(tester.getRect(line('c1')).bottom,
          lessThanOrEqualTo(tester.getRect(line('c2')).top));
      expect(box.bottom + PartyChatBubble.gap,
          moreOrLessEquals(tester.getRect(field()).top));
      expect(box.height, lessThan(100), reason: 'non occupa il 40%');
      await leave(tester);
    });

    testWidgets('inviare da più su riporta in fondo', (tester) async {
      longHistory();
      await pumpChat(tester);
      await openChat(tester);
      final scroll = tester
          .widget<ListView>(
              find.descendant(of: history(), matching: find.byType(ListView)))
          .controller!;
      // Si legge più su; un messaggio degli altri non sposta in fondo.
      scroll.jumpTo(scroll.position.maxScrollExtent / 2);
      await tester.pump();
      await receive(tester, 'eccomi', id: 'c1');
      expect(
          line('c1').hitTestable(), findsNothing, reason: 'resta dov\'era');
      await send(tester, 'ci sono');
      expectAtBottom(tester, 'local-1');
      await leave(tester);
    });

    testWidgets('messaggio in arrivo a chat aperta: nello storico, niente bolla',
        (tester) async {
      await pumpChat(tester);
      await openChat(tester);
      await receive(tester, 'eccomi', id: 'c1');
      expect(find.textContaining('eccomi'), findsOneWidget);
      expect(find.byType(PartyChatBubble), findsNothing);
      await leave(tester);
    });
  });
}
