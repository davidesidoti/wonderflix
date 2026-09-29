import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

  testWidgets('tracce, selezione e ritardo', (tester) async {
    int? audioPicked;
    int? subtitlePicked = -99;
    Duration? step;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: TracksPanel(
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
            onAudio: (i) => audioPicked = i,
            onSubtitle: (i) => subtitlePicked = i,
            onDelayStep: (s) => step = s,
          ),
        ),
      ),
    );

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Sottotitoli'), findsOneWidget);
    expect(find.text('Traccia 7'), findsOneWidget, reason: 'senza nome');
    expect(find.text('+0,3 s'), findsOneWidget);
    // Selezionati: audio 1 e "Nessuno".
    expect(find.byIcon(LucideIcons.check), findsNWidgets(2));

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
  });
}
