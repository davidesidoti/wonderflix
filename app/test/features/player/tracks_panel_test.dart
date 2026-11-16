import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
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

  final l = lookupAppLocalizations(const Locale('it'));

  test('dettaglio delle tracce', () {
    expect(
        trackDetail(
            l,
            const MediaStreamInfo(
                index: 1,
                kind: StreamKind.audio,
                codec: 'ac3',
                channelLayout: '5.1',
                isDefault: true)),
        'AC-3 5.1 · predefinita');
    expect(
        trackDetail(
            l,
            const MediaStreamInfo(
                index: 2, kind: StreamKind.audio, codec: 'aac', channels: 2)),
        'AAC 2.0');
    expect(
        trackDetail(
            l,
            const MediaStreamInfo(
                index: 3,
                kind: StreamKind.subtitle,
                codec: 'subrip',
                isExternal: true)),
        'SRT · esterno');
    expect(
        trackDetail(
            l,
            const MediaStreamInfo(
                index: 4,
                kind: StreamKind.subtitle,
                codec: 'subrip',
                title: 'Forzati',
                isForced: true)),
        'SRT · Forzati · forzati · nel file');
  });

  TracksPanel panel({
    List<MediaStreamInfo>? audio,
    JellyfinItem? item,
    double rate = 1,
    ValueChanged<double>? onRate,
    bool party = false,
    List<MediaStreamInfo>? subtitles,
    ValueChanged<int>? onAudio,
    ValueChanged<int?>? onSubtitle,
    ValueChanged<Duration>? onDelayStep,
    ValueChanged<double>? onSubtitleScale,
    VoidCallback? onClose,
    VoidCallback? onSearchSubtitles,
  }) =>
      TracksPanel(
        onSearchSubtitles: onSearchSubtitles,
        item: item,
        rate: rate,
        onRate: party ? null : (onRate ?? (_) {}),
        audio: audio ??
            const [
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
    final semantics = tester.ensureSemantics();
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
    expect(find.text('Dimensione · Grandi'), findsOneWidget);
    for (final label in [
      'Molto piccoli',
      'Piccoli',
      'Normali',
      'Grandi',
      'Molto grandi',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }

    // La traccia scelta è un pulsante "selezionato" per chi usa lo screen reader.
    expect(
        tester.getSemantics(find.text('Nessuno')),
        matchesSemantics(
            label: 'Nessuno',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true));
    await tester.tap(find.text('English - AAC'));
    expect(audioPicked, 2);
    await tester.tap(find.text('Italiano - ASS'));
    expect(subtitlePicked, 3);
    await tester.tap(find.text('Nessuno'));
    expect(subtitlePicked, isNull);
    expect(find.text('G'), findsOneWidget, reason: 'i tasti accanto');
    expect(find.text('H'), findsOneWidget);
    expect(find.text("− prima, + dopo l'audio"), findsOneWidget);
    await tester.tap(find.byTooltip('Sottotitoli prima'));
    expect(step, const Duration(milliseconds: -100));
    await tester.tap(find.byTooltip('Sottotitoli dopo'));
    expect(step, const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('subtitle-scale-1.0')));
    expect(scale, 1.0);
    await tester.tap(find.byKey(const ValueKey('subtitle-scale-0.45')));
    expect(scale, 0.45);
    await tester.tap(find.byTooltip('Chiudi'));
    expect(closed, 1);
    semantics.dispose();
  });

  testWidgets('Cerca sottotitoli solo con il callback', (tester) async {
    Future<void> pumpPanel(VoidCallback? onSearch) => pumpApp(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: TracksPanel.width,
                child: panel(onSearchSubtitles: onSearch),
              ),
            ),
          ),
        );

    await pumpPanel(null);
    expect(find.text('Cerca sottotitoli'), findsNothing);

    var searched = 0;
    await pumpPanel(() => searched++);
    final button = find.text('Cerca sottotitoli');
    expect(button, findsOneWidget);
    expect(find.byIcon(LucideIcons.search), findsOneWidget);
    // Sotto le tracce dei sottotitoli, sopra il ritardo.
    expect(tester.getTopLeft(button).dy,
        greaterThan(tester.getTopLeft(find.text('Traccia 7')).dy));
    expect(tester.getTopLeft(button).dy,
        lessThan(tester.getTopLeft(find.text('Ritardo dei sottotitoli')).dy));
    await tester.tap(button);
    expect(searched, 1);
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
    // 2 sezioni, 2 audio, "Nessuno", i sottotitoli, ritardo (titolo e
    // pulsanti), dimensione e velocità (titolo e scelte).
    expect(items.length, 2 + 2 + 1 + subtitleCount + 2 + 2 + 2);
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
    // Largo 380 px (al massimo il 40% della finestra).
    expect(tester.getSize(find.byType(TracksPanel)).width, TracksPanel.width);

    open.value = false;
    await tester.pump();
    expect(find.byType(TracksPanel), findsOneWidget, reason: 'sta uscendo');
    await tester.pumpAndSettle();
    expect(find.byType(TracksPanel), findsNothing);
  });

  testWidgets('foglio: maniglia, angoli, si chiude trascinando giù',
      (tester) async {
    var closed = 0;
    Future<void> pumpSheet() => pumpApp(
          tester,
          Scaffold(
            body: PlayerSidePanelHost(
              open: true,
              panel: const SizedBox.expand(),
              onClose: () => closed++,
            ),
          ),
          surfaceSize: const Size(390, 780),
          touch: true,
        );
    await pumpSheet();
    final handle = find.byKey(const Key('panel-sheet-handle'));
    expect(handle, findsOneWidget);
    expect(tester.getSize(handle), const Size(36, 4));
    expect(tester.getCenter(handle).dx, 195);
    final clip =
        tester.widget<ClipRRect>(find.byKey(const Key('panel-sheet')));
    expect(clip.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(16)));

    // Un trascinamento corto e lento non chiude.
    await tester.timedDrag(
        handle, const Offset(0, 40), const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(closed, 0);
    await tester.drag(handle, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('desktop e TV: nessuna maniglia', (tester) async {
    for (final (size, tv) in [
      (const Size(1440, 900), false),
      (const Size(960, 540), true),
    ]) {
      await pumpApp(
        tester,
        Scaffold(
          body: PlayerSidePanelHost(
              open: true, panel: const SizedBox.expand(), onClose: () {}),
        ),
        surfaceSize: size,
        tv: tv,
      );
      expect(find.byKey(const Key('panel-sheet-handle')), findsNothing,
          reason: '$size');
    }
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

  const episode = JellyfinItem(
    id: 'e4',
    name: 'La scatola',
    kind: ItemKind.episode,
    seriesName: "L'Istituto",
    parentIndexNumber: 1,
    indexNumber: 4,
  );
  const italianAc3 = [
    MediaStreamInfo(
        index: 1,
        kind: StreamKind.audio,
        language: 'ita',
        codec: 'ac3',
        channelLayout: '5.1',
        isDefault: true),
    MediaStreamInfo(index: 2, kind: StreamKind.audio, language: 'eng'),
  ];

  Future<void> pumpPanel(WidgetTester tester, TracksPanel panel,
          {bool tv = false, bool touch = false}) =>
      pumpApp(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: TracksPanel.width, child: panel),
          ),
        ),
        tv: tv,
        touch: touch,
        surfaceSize: tv ? const Size(960, 540) : const Size(1440, 900),
      );

  /// La riga (l'`InkWell`) che contiene [text].
  Finder rowOf(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;

  testWidgets('testa col titolo e righe col dettaglio', (tester) async {
    await pumpPanel(tester, panel(item: episode, audio: italianAc3));
    expect(find.text("L'Istituto"), findsOneWidget);
    expect(find.text('S1:E4 · La scatola'), findsOneWidget);
    expect(find.text('Italiano'), findsOneWidget);
    expect(find.text('Inglese'), findsOneWidget);
    expect(find.text('AC-3 5.1 · predefinita'), findsOneWidget);
    expect(tester.getSize(rowOf('Italiano')).height, greaterThanOrEqualTo(44));
  });

  testWidgets('col dito niente tasti G e H', (tester) async {
    await pumpPanel(tester, panel(), touch: true);
    expect(find.text('Ritardo dei sottotitoli'), findsOneWidget);
    expect(find.text('G'), findsNothing);
    expect(find.text('H'), findsNothing);
  });

  testWidgets('Dimensione dice la scelta', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: SizedBox(
          width: TracksPanel.width,
          child: TracksPanel(
            audio: const [],
            subtitles: const [],
            audioIndex: null,
            subtitleIndex: null,
            subtitleDelay: Duration.zero,
            subtitleScale: 0.8,
            onAudio: (_) {},
            onSubtitle: (_) {},
            onDelayStep: (_) {},
            onSubtitleScale: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Dimensione · Normali'), findsOneWidget);
  });

  testWidgets('Velocità sceglie', (tester) async {
    double? picked;
    await pumpPanel(tester, panel(rate: 1.5, onRate: (r) => picked = r));
    expect(find.text('Velocità'), findsOneWidget);
    for (final label in ['0,75×', '1×', '1,25×', '1,5×', '2×']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('In compagnia la velocità resta 1×'), findsNothing);
    final chip = find.byKey(const ValueKey('playback-rate-1.25'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    expect(picked, 1.25);
  });

  testWidgets('Velocità nel party: 1× e la frase', (tester) async {
    await pumpPanel(tester, panel(rate: 1.5, party: true));
    expect(find.text('In compagnia la velocità resta 1×'), findsOneWidget);
    final two = find.byKey(const ValueKey('playback-rate-2.0'));
    await tester.ensureVisible(two);
    // Spenta: il tocco non fa niente (onRate è null, non c'è chi chiamare).
    await tester.tap(two, warnIfMissed: false);
    await tester.pump();
    // La scelta mostrata è 1× anche se il video andava a 1,5×.
    expect(tester.widget<Text>(find.text('1×')).style?.fontWeight,
        FontWeight.w600);
    expect(tester.widget<Text>(find.text('1,5×')).style?.fontWeight,
        isNot(FontWeight.w600));
  });

  testWidgets('TV: righe alte 52, niente ritardo, pannello largo 380',
      (tester) async {
    await pumpPanel(tester, panel(item: episode, audio: italianAc3), tv: true);
    expect(tester.getSize(rowOf('Italiano')).height, greaterThanOrEqualTo(52));
    expect(find.text('Ritardo dei sottotitoli'), findsNothing);

    await pumpApp(
      tester,
      Scaffold(
        body: PlayerSidePanelHost(
            open: true, panel: panel(item: episode, audio: italianAc3)),
      ),
      tv: true,
      surfaceSize: const Size(960, 540),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TracksPanel)).width, 380);
  });
}
