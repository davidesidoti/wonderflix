import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';

import '../../support/pump_app.dart';

void main() {
  test('formatSubtitleDelay', () {
    expect(formatSubtitleDelay(Duration.zero, ','), '0,0 s');
    expect(formatSubtitleDelay(const Duration(milliseconds: 300), ','),
        '+0,3 s');
    expect(formatSubtitleDelay(const Duration(milliseconds: -1200), '.'),
        '-1.2 s');
  });

  TracksPanel panel({
    ValueChanged<int>? onAudio,
    ValueChanged<int?>? onSubtitle,
    ValueChanged<Duration>? onDelayStep,
    ValueChanged<double>? onSubtitleScale,
    VoidCallback? onClose,
  }) =>
      TracksPanel(
        audio: const [
          MediaStreamInfo(
              index: 1,
              kind: StreamKind.audio,
              displayTitle: 'Italiano - E-AC3 5.1'),
          MediaStreamInfo(
              index: 2, kind: StreamKind.audio, displayTitle: 'English - AAC'),
        ],
        subtitles: const [
          MediaStreamInfo(
              index: 3,
              kind: StreamKind.subtitle,
              displayTitle: 'Italiano - ASS'),
          MediaStreamInfo(index: 7, kind: StreamKind.subtitle),
        ],
        audioIndex: 1,
        subtitleIndex: null,
        subtitleDelay: const Duration(milliseconds: 300),
        subtitleScale: 1.0,
        onAudio: onAudio ?? (_) {},
        onSubtitle: onSubtitle ?? (_) {},
        onDelayStep: onDelayStep ?? (_) {},
        onSubtitleScale: onSubtitleScale ?? (_) {},
        onClose: onClose ?? () {},
      );

  testWidgets('tracce, selezione, ritardo, dimensione e chiusura',
      (tester) async {
    int? audioPicked;
    int? subtitlePicked = -99;
    Duration? step;
    double? scale;
    var closed = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: TracksPanel.width,
            child: panel(
              onAudio: (i) => audioPicked = i,
              onSubtitle: (i) => subtitlePicked = i,
              onDelayStep: (s) => step = s,
              onSubtitleScale: (s) => scale = s,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Audio e sottotitoli'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Sottotitoli'), findsOneWidget);
    expect(find.text('Traccia 7'), findsOneWidget, reason: 'senza nome');
    expect(find.text('+0,3 s'), findsOneWidget);
    // Selezionati: audio 1 e "Nessuno".
    expect(find.byIcon(LucideIcons.check), findsNWidgets(2));
    expect(find.text('Dimensione'), findsOneWidget);
    for (final label in ['Piccoli', 'Normali', 'Grandi', 'Molto grandi']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('English - AAC'));
    expect(audioPicked, 2);
    await tester.tap(find.text('Italiano - ASS'));
    expect(subtitlePicked, 3);
    await tester.tap(find.text('Nessuno'));
    expect(subtitlePicked, isNull);
    await tester.tap(find.byTooltip('Sottotitoli prima (G)'));
    expect(step, const Duration(milliseconds: -100));
    await tester.tap(find.byTooltip('Sottotitoli dopo (H)'));
    expect(step, const Duration(milliseconds: 100));
    await tester.tap(find.text('Grandi'));
    expect(scale, 1.25);
    await tester.tap(find.byTooltip('Chiudi'));
    expect(closed, 1);
  });

  Future<ValueNotifier<bool>> pumpHost(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final open = ValueNotifier(false);
    addTearDown(open.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, value, _) =>
              TracksPanelHost(open: value, panel: panel()),
        ),
      ),
      motion: motion,
    );
    return open;
  }

  // Lo scorrimento del pannello: solo dentro l'host (anche le transizioni di
  // pagina dell'app usano `FractionalTranslation`, più in alto nell'albero).
  final slideFinder = find.descendant(
      of: find.byType(TracksPanelHost),
      matching: find.byType(FractionalTranslation));

  testWidgets('host: entra scorrendo da destra, esce e lascia l\'albero',
      (tester) async {
    final open = await pumpHost(tester, motion: MotionLevel.full);
    expect(find.byType(TracksPanel), findsNothing);

    open.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final slide = tester.widget<FractionalTranslation>(slideFinder);
    expect(slide.translation.dx, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tester.widget<FractionalTranslation>(slideFinder).translation.dx, 0);
    // Largo 360 px (al massimo il 35% della finestra).
    expect(tester.getSize(find.byType(TracksPanel)).width, TracksPanel.width);

    open.value = false;
    await tester.pump();
    expect(find.byType(TracksPanel), findsOneWidget, reason: 'sta uscendo');
    await tester.pumpAndSettle();
    expect(find.byType(TracksPanel), findsNothing);
  });

  testWidgets('host: animazioni ridotte, solo dissolvenza', (tester) async {
    final open = await pumpHost(tester);
    open.value = true;
    await tester.pumpAndSettle();
    expect(slideFinder, findsNothing);
    expect(find.byType(TracksPanel), findsOneWidget);
  });
}
