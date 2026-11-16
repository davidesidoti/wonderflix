import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_keys.dart';
import 'package:wonderflix/features/player/player_overlay.dart';

import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    bool touch = false,
    bool tv = false,
    Size size = const Size(1440, 900),
  }) {
    return pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
          view: const PlayerViewState(status: PlayerStatus.ready, playing: true),
          engine: FakeVideoEngine(),
          fullscreen: false,
          onBack: () {},
          backLabel: 'Torna alla scheda',
          onTogglePlay: () {},
          onSeekBy: (_) {},
          onSeekTo: (_) {},
          onVolume: (_) {},
          onToggleMute: () {},
          onToggleTracks: () {},
          onToggleFullscreen: () {},
          onNextEpisode: () {},
          onPrevious: () {},
          onToggleChat: () {},
          onToggleReactions: () {},
        ),
      ),
      touch: touch,
      tv: tv,
      surfaceSize: size,
    );
  }

  KeyTooltip tip(WidgetTester tester, String message) => tester.widget(
      find.byWidgetPredicate((w) => w is KeyTooltip && w.message == message));

  testWidgets('il tooltip di Pausa mostra Spazio', (tester) async {
    await pumpOverlay(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byTooltip('Pausa')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Pausa'), findsOneWidget);
    expect(find.descendant(of: find.byType(KeyCap), matching: find.text('Spazio')),
        findsOneWidget);
  });

  testWidgets('ogni comando ha il suo tasto', (tester) async {
    await pumpOverlay(tester);
    const keys = {
      'Pausa': 'Spazio',
      'Indietro di 10 secondi': '←',
      'Avanti di 10 secondi': '→',
      'Disattiva audio': 'M',
      'Schermo intero': 'F',
      'Episodio successivo': 'N',
      'Episodio precedente': 'P',
      'Chat': 'Invio',
      'Reazioni': '1–6',
      'Volume': '↑/↓',
    };
    keys.forEach((message, key) => expect(tip(tester, message).shortcut, key,
        reason: message));
  });

  testWidgets('col dito e in TV nessun tasto', (tester) async {
    for (final (touch, tv, size) in [
      (true, false, const Size(1440, 900)),
      (false, true, const Size(960, 540)),
    ]) {
      await pumpOverlay(tester, touch: touch, tv: tv, size: size);
      final tips = tester.widgetList<KeyTooltip>(find.byType(KeyTooltip));
      expect(tips, isNotEmpty);
      expect(tips.where((t) => t.shortcut != null), isEmpty,
          reason: 'touch $touch tv $tv');
    }
  });

  testWidgets('il tooltip col tasto usa il font del tema (Inter)',
      (tester) async {
    // Senza Material sopra l'overlay: il testo prende lo stile solo dal tema.
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Theme(
          data: buildWonderflixTheme(),
          child: Overlay(initialEntries: [
            OverlayEntry(
              builder: (_) => const Center(
                child: KeyTooltip(
                  message: 'Pausa',
                  shortcut: 'Spazio',
                  child: SizedBox(width: 48, height: 48),
                ),
              ),
            ),
          ]),
        ),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(SizedBox)));
    await tester.pump(const Duration(seconds: 1));
    for (final text in ['Pausa', 'Spazio']) {
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.text.style?.fontFamily, 'Inter', reason: text);
    }
  });

  testWidgets('finestra stretta col mouse: i comandi compatti hanno il tasto',
      (tester) async {
    await pumpOverlay(tester, size: const Size(700, 800));
    final tips = tester.widgetList<KeyTooltip>(find.byType(KeyTooltip));
    final keys = {for (final t in tips) t.message: t.shortcut};
    expect(keys['Pausa'], 'Spazio');
    expect(keys['Indietro di 10 secondi'], '←');
    // Schermo intero e Chat stanno in "Altro", con la parola.
  });

  testWidgets('KeyCap ha la misura della bozza', (tester) async {
    await pumpApp(tester, const Scaffold(body: Center(child: KeyCap('M'))));
    final size = tester.getSize(find.byType(KeyCap));
    expect(size.height, 22);
    expect(size.width, greaterThanOrEqualTo(22));
  });

  testWidgets('la scheda elenca tutti i tasti', (tester) async {
    await pumpApp(tester, const Scaffold(body: Center(child: PlayerKeysCard())));
    for (final k in [
      'Spazio', '←', '→', '↑', '↓', 'M', 'F', 'N', 'P', 'G', 'H', 'Invio', //
      '1–6', 'Esc',
    ]) {
      expect(
          find.descendant(
              of: find.byType(PlayerKeysCard),
              matching: find.descendant(
                  of: find.byType(KeyCap), matching: find.text(k))),
          findsOneWidget,
          reason: k);
    }
    expect(find.text('Tasti'), findsOneWidget);
    expect(find.text('Episodi e sottotitoli'), findsOneWidget);
    expect(find.text('Chiudi un pannello o esci'), findsOneWidget);
    expect(tester.getSize(find.byType(PlayerKeysCard)).width, 420);
    expect(tester.takeException(), isNull);
  });
}
