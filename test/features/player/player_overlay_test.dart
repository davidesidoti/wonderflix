import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_overlay.dart';
import 'package:wonderflix/features/player/seek_bar.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<List<String>> pumpOverlay(
    WidgetTester tester,
    PlayerViewState view, {
    bool fullscreen = false,
    bool chat = false,
    bool chatUnread = false,
  }) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
          view: view,
          engine: FakeVideoEngine(),
          fullscreen: fullscreen,
          onBack: () => calls.add('back'),
          onTogglePlay: () => calls.add('play'),
          onSeekBy: (offset) => calls.add('seek ${offset.inSeconds}'),
          onSeekTo: (_) => calls.add('seekTo'),
          onVolume: (_) => calls.add('volume'),
          onToggleMute: () => calls.add('mute'),
          onToggleTracks: () => calls.add('tracks'),
          onToggleFullscreen: () => calls.add('fullscreen'),
          onToggleChat: chat ? () => calls.add('chat') : null,
          chatUnread: chatUnread,
        ),
      ),
    );
    return calls;
  }

  testWidgets('titolo, episodio e comandi', (tester) async {
    final calls = await pumpOverlay(
      tester,
      PlayerViewState(
        status: PlayerStatus.ready,
        playing: true,
        item: testItem(
          id: 'e4',
          name: 'Pilot',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 4,
          seasonIndex: 1,
        ),
      ),
    );
    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);

    await tester.tap(find.byTooltip('Indietro'));
    await tester.tap(find.byTooltip('Pausa'));
    await tester.tap(find.byTooltip('Indietro di 10 secondi'));
    await tester.tap(find.byTooltip('Avanti di 10 secondi'));
    await tester.tap(find.byTooltip('Disattiva audio'));
    await tester.tap(find.byTooltip('Audio e sottotitoli'));
    await tester.tap(find.byTooltip('Schermo intero'));
    expect(calls,
        ['back', 'play', 'seek -10', 'seek 10', 'mute', 'tracks', 'fullscreen']);
  });

  testWidgets('in pausa, muto e a schermo intero', (tester) async {
    await pumpOverlay(
      tester,
      const PlayerViewState(
          status: PlayerStatus.ready, playing: false, muted: true),
      fullscreen: true,
    );
    expect(find.byTooltip('Riproduci'), findsOneWidget);
    expect(find.byTooltip('Riattiva audio'), findsOneWidget);
    expect(find.byTooltip('Esci da schermo intero'), findsOneWidget);
    expect(find.byIcon(LucideIcons.volumeX), findsOneWidget);
    expect(
        tester.widget<Slider>(find.byKey(const Key('volume-slider'))).value, 0);
  });

  testWidgets('episodio successivo, capitoli e anteprima', (tester) async {
    var next = 0;
    await pumpApp(
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
          onNextEpisode: () => next++,
          chapters: const [ChapterMark(start: Duration(minutes: 10))],
          preview: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Episodio successivo'));
    expect(next, 1);
    final bar = tester.widget<SeekBar>(find.byType(SeekBar));
    expect(bar.chapters, hasLength(1));
    expect(bar.preview, isNotNull);
    expect(bar.zones, isEmpty);
  });

  testWidgets('senza episodio successivo: nessun pulsante', (tester) async {
    await pumpOverlay(tester,
        const PlayerViewState(status: PlayerStatus.ready, playing: true));
    expect(find.byTooltip('Episodio successivo'), findsNothing);
  });

  Widget overlay({required bool visible}) => PlayerOverlay(
        visible: visible,
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
      );

  double opacityOf(WidgetTester tester, String key) =>
      tester.widget<AnimatedOpacity>(find.byKey(Key(key))).opacity;

  double shiftOf(WidgetTester tester, String key) => tester
      .widget<AnimatedContainer>(find
          .descendant(
              of: find.byKey(Key(key)), matching: find.byType(AnimatedContainer))
          .first)
      .transform!
      .getTranslation()
      .y;

  testWidgets('controlli nascosti: sfumano e scivolano verso i bordi',
      (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, value, _) => overlay(visible: value),
        ),
      ),
      motion: MotionLevel.full,
    );
    expect(opacityOf(tester, 'player-controls-top'), 1);
    expect(shiftOf(tester, 'player-controls-top'), 0);

    visible.value = false;
    await tester.pump();
    expect(opacityOf(tester, 'player-controls-top'), 0);
    expect(opacityOf(tester, 'player-controls-bottom'), 0);
    expect(shiftOf(tester, 'player-controls-top'), -PlayerOverlay.hiddenShift);
    expect(shiftOf(tester, 'player-controls-bottom'), PlayerOverlay.hiddenShift);
    await tester.pumpAndSettle();
  });

  testWidgets('animazioni ridotte: i controlli sfumano senza spostarsi',
      (tester) async {
    await pumpApp(tester, Scaffold(body: overlay(visible: false)));
    expect(opacityOf(tester, 'player-controls-bottom'), 0);
    expect(shiftOf(tester, 'player-controls-bottom'), 0);
  });

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    return gesture;
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<AnimatedScale>(find.descendant(
          of: find.byType(PlayerIconButton),
          matching: find.byType(AnimatedScale)))
      .scale;

  List<BoxShadow>? glowOf(WidgetTester tester) => (tester
          .widget<AnimatedContainer>(find.byKey(const Key('player-button-glow')))
          .decoration! as BoxDecoration)
      .boxShadow;

  Widget captionsButton() => Scaffold(
        body: Center(
          child: PlayerIconButton(
            icon: const Icon(LucideIcons.captions),
            tooltip: 'Audio e sottotitoli',
            onPressed: () {},
          ),
        ),
      );

  testWidgets('pulsante: alone oro e scala 1,08 al passaggio del mouse',
      (tester) async {
    await pumpApp(tester, captionsButton(), motion: MotionLevel.full);
    expect(scaleOf(tester), 1);
    expect(glowOf(tester), isEmpty);
    await hover(tester, find.byType(PlayerIconButton));
    expect(scaleOf(tester), 1.08);
    expect(glowOf(tester), isNotEmpty);
  });

  testWidgets('pulsante: animazioni ridotte, alone senza scala',
      (tester) async {
    await pumpApp(tester, captionsButton());
    await hover(tester, find.byType(PlayerIconButton));
    expect(scaleOf(tester), 1);
    expect(glowOf(tester), isNotEmpty);
  });

  testWidgets('pulsante premuto: scala 0,97; rilasciato, torna al passaggio',
      (tester) async {
    await pumpApp(tester, captionsButton(), motion: MotionLevel.full);
    final gesture = await hover(tester, find.byType(PlayerIconButton));
    expect(scaleOf(tester), 1.08);

    await gesture.down(tester.getCenter(find.byType(PlayerIconButton)));
    await tester.pump();
    expect(scaleOf(tester), 0.97);
    expect(glowOf(tester), isNotEmpty, reason: 'il mouse è ancora sopra');

    await gesture.up();
    await tester.pump();
    expect(scaleOf(tester), 1.08);
    await tester.pumpAndSettle();
  });

  testWidgets('pulsante disattivato: né scala né alone al passaggio',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Center(
          child: PlayerIconButton(
            icon: Icon(LucideIcons.captions),
            tooltip: 'Audio e sottotitoli',
            onPressed: null,
          ),
        ),
      ),
      motion: MotionLevel.full,
    );
    await hover(tester, find.byType(PlayerIconButton));
    expect(scaleOf(tester), 1);
    expect(glowOf(tester), isEmpty);
  });

  testWidgets('play/pausa: l\'icona cambia sfumando', (tester) async {
    final playing = ValueNotifier(true);
    addTearDown(playing.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: playing,
          builder: (context, value, _) => PlayPauseIcon(playing: value),
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.pause), findsOneWidget);
    playing.value = false;
    await tester.pump();
    expect(find.byIcon(LucideIcons.play), findsOneWidget);
    expect(find.byIcon(LucideIcons.pause), findsOneWidget,
        reason: 'la vecchia sta ancora sfumando');
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.pause), findsNothing);
  });

  testWidgets('chat del watch party: pulsante e puntino dei non letti '
      '(spec E §9.5)', (tester) async {
    final view = PlayerViewState(status: PlayerStatus.ready);
    await pumpOverlay(tester, view);
    expect(find.byTooltip('Chat (Invio)'), findsNothing);

    final calls = await pumpOverlay(tester, view, chat: true);
    expect(find.byKey(const Key('player-chat-unread')), findsNothing);
    await tester.tap(find.byTooltip('Chat (Invio)'));
    expect(calls, ['chat']);

    await pumpOverlay(tester, view, chat: true, chatUnread: true);
    expect(find.byKey(const Key('player-chat-unread')), findsOneWidget);
  });
}
