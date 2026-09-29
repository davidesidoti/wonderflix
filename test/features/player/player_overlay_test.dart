import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_overlay.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<List<String>> pumpOverlay(
    WidgetTester tester,
    PlayerViewState view, {
    bool fullscreen = false,
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
}
