import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('KeyCap ha la misura della bozza', (tester) async {
    await pumpApp(tester, const Scaffold(body: Center(child: KeyCap('M'))));
    final size = tester.getSize(find.byType(KeyCap));
    expect(size.height, 22);
    expect(size.width, greaterThanOrEqualTo(22));
  });
}
