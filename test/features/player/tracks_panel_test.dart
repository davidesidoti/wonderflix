import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/player_side_panel_host.dart';
import 'package:wonderflix/features/player/tracks_panel.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

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
    List<MediaStreamInfo>? subtitles,
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
        subtitles: subtitles ??
            const [
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
    for (final label in [
      'Molto piccoli',
      'Piccoli',
      'Normali',
      'Grandi',
      'Molto grandi',
    ]) {
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
    expect(scale, 1.0);
    await tester.tap(find.text('Molto piccoli'));
    expect(scale, 0.45);
    await tester.tap(find.byTooltip('Chiudi'));
    expect(closed, 1);
  });

  testWidgets('scaglionamento: solo voci vere e con un tetto', (tester) async {
    const subtitleCount = 20;
    // Finestra alta: la lista è pigra e deve costruire tutte le voci.
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: TracksPanel.width,
            child: panel(subtitles: [
              for (var i = 0; i < subtitleCount; i++)
                MediaStreamInfo(
                    index: 10 + i,
                    kind: StreamKind.subtitle,
                    displayTitle: 'Sottotitolo $i'),
            ]),
          ),
        ),
      ),
      surfaceSize: const Size(1440, 4000),
      motion: MotionLevel.full,
    );

    final group = tester.widget<StaggerGroup>(find.byType(StaggerGroup));
    expect(group.count, lessThanOrEqualTo(TracksPanel.staggeredItems),
        reason: 'con molte tracce l\'entrata non si allunga');

    final items = tester.widgetList<StaggerItem>(find.byType(StaggerItem));
    // Titolo, 2 sezioni, 2 audio, "Nessuno", i sottotitoli, ritardo,
    // etichetta della dimensione, scelte della dimensione.
    expect(items.length, 1 + 2 + 2 + 1 + subtitleCount + 1 + 1 + 1);
    for (final item in items) {
      final child = item.child;
      expect(child is SizedBox && child.child == null, isFalse,
          reason: 'niente distanziatori tra le voci');
    }
    await tester.pumpAndSettle();
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
              PlayerSidePanelHost(open: value, panel: panel()),
        ),
      ),
      motion: motion,
    );
    return open;
  }

  // Lo scorrimento del pannello: solo dentro l'host (anche le transizioni di
  // pagina dell'app usano `FractionalTranslation`, più in alto nell'albero).
  final slideFinder = find.descendant(
      of: find.byType(PlayerSidePanelHost),
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

  testWidgets('host: uscendo parte piano e accelera', (tester) async {
    final open = await pumpHost(tester, motion: MotionLevel.full);
    open.value = true;
    await tester.pumpAndSettle();
    open.value = false;
    await tester.pump();
    await tester.pump(WfMotion.fast * 0.1);
    // Al 10% dell'uscita si è appena mosso (con `accelerate` percorsa al
    // contrario sarebbe già oltre il 15%).
    expect(tester.widget<FractionalTranslation>(slideFinder).translation.dx,
        lessThan(0.05));
    await tester.pumpAndSettle();
  });

  testWidgets('host: animazioni ridotte, solo dissolvenza', (tester) async {
    final open = await pumpHost(tester);
    open.value = true;
    await tester.pumpAndSettle();
    expect(slideFinder, findsNothing);
    expect(find.byType(TracksPanel), findsOneWidget);
  });

  /// Il pannello a destra, dentro un `Listener` che conta le rotelle che
  /// arrivano fin lì (come il player sotto il pannello).
  Future<int Function()> pumpOverPlayer(WidgetTester tester,
      {List<MediaStreamInfo>? subtitles}) async {
    var outside = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) => GestureBinding
              .instance.pointerSignalResolver
              .register(event, (_) => outside++),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: TracksPanel.width,
              child: panel(subtitles: subtitles),
            ),
          ),
        ),
      ),
    );
    return () => outside;
  }

  testWidgets('rotella: lista corta, non esce dal pannello', (tester) async {
    final outside = await pumpOverPlayer(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(TracksPanel))));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    expect(outside(), 0);

    // Fuori dal pannello arriva a chi sta sotto.
    await tester.sendEventToBinding(wheel.hover(const Offset(200, 450)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    expect(outside(), 1);
  });

  testWidgets('rotella: una lista lunga scorre', (tester) async {
    final outside = await pumpOverPlayer(tester, subtitles: [
      for (var i = 0; i < 20; i++)
        MediaStreamInfo(
            index: 10 + i,
            kind: StreamKind.subtitle,
            displayTitle: 'Sottotitolo $i'),
    ]);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    final position = tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(TracksPanel), matching: find.byType(Scrollable)))
        .position;
    await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.byType(TracksPanel))));

    // In cima, rotella in su: la lista non può scorrere, il pannello se la
    // tiene.
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
    await tester.pump();
    expect(position.pixels, 0);
    expect(outside(), 0);

    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    expect(outside(), 0);
  });
}
