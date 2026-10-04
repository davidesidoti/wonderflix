import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel.dart';
import 'package:wonderflix/features/player/queue_panel/queue_rows.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  JellyfinItem episode(String id, String name, int index) => testItem(
        id: id,
        name: name,
        kind: ItemKind.episode,
        seriesName: 'The Office',
        seriesId: 's1',
        index: index,
        seasonIndex: 2,
        runtimeMinutes: 22,
      );

  /// e3 già visto (p1), e4 in riproduzione (p2), poi e5 (p3), il film m1
  /// (p4) e x9 non disponibile (p5).
  PlayQueue queue(
          {bool shuffled = false,
          DateTime? lastUpdate,
          List<String>? upcoming}) =>
      PlayQueue(
        reason: 'NewPlaylist',
        lastUpdate: lastUpdate ?? DateTime.utc(2026, 10, 4, 10),
        entries: [
          const PlayQueueEntry(itemId: 'e3', playlistItemId: 'p1'),
          const PlayQueueEntry(itemId: 'e4', playlistItemId: 'p2'),
          for (final id in upcoming ?? const ['p3', 'p4', 'p5'])
            PlayQueueEntry(
                itemId: const {'p3': 'e5', 'p4': 'm1', 'p5': 'x9'}[id]!,
                playlistItemId: id),
        ],
        playingIndex: 1,
        startPosition: Duration.zero,
        isPlaying: true,
        shuffled: shuffled,
      );

  final items = <String, JellyfinItem?>{
    'e3': episode('e3', 'Ufficio in fiamme', 3),
    'e4': episode('e4', 'La festa', 4),
    'e5': episode('e5', 'Halloween', 5),
    'm1': testItem(id: 'm1', name: 'Alien', year: 1979, runtimeMinutes: 117),
    'x9': null,
  };

  Future<List<String>> pumpPanel(WidgetTester tester,
      {ValueNotifier<PlayQueue>? notifier,
      Map<String, JellyfinItem?>? details}) async {
    final calls = <String>[];
    final current = notifier ?? ValueNotifier(queue());
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: QueuePanel.width,
            height: 900,
            child: ValueListenableBuilder<PlayQueue>(
              valueListenable: current,
              builder: (context, value, _) => QueuePanel(
                queue: value,
                items: details ?? items,
                onJump: (id) => calls.add('jump $id'),
                onRemove: (id) => calls.add('remove $id'),
                onMove: (id, index) => calls.add('move $id $index'),
                onShuffle: (on) => calls.add('shuffle $on'),
                onClose: () => calls.add('close'),
              ),
            ),
          ),
        ),
      ),
    );
    return calls;
  }

  Finder row(String playlistItemId) =>
      find.byKey(ValueKey('party-queue-$playlistItemId'));

  Finder inRow(String playlistItemId, Finder finder) =>
      find.descendant(of: row(playlistItemId), matching: finder);

  test('riga secondaria: episodio, film, in riproduzione', () {
    expect(queueRowDetails(l, items['e5']!), 'The Office · S2:E5 · 22m');
    expect(queueRowDetails(l, items['m1']!), 'Film · 1979 · 1h 57m');
    expect(queueRowDetails(l, items['e4']!, playing: true),
        'The Office · S2:E4 · ora');
  });

  testWidgets('sezioni, righe e riepilogo (spec H §9.2)', (tester) async {
    await pumpPanel(tester);
    expect(find.text(l.partyQueueTitle), findsOneWidget);
    // Prossimi: e5 (22m) e Alien (1h 57m); x9 non ha durata.
    expect(find.text('5 titoli · 2h 19m dopo questo'), findsOneWidget);
    expect(find.text(l.partyQueueWatched), findsOneWidget);
    expect(find.text(l.partyQueuePlaying), findsOneWidget);
    expect(find.text(l.partyQueueUpcoming), findsOneWidget);
    expect(find.text('Ufficio in fiamme'), findsOneWidget);
    expect(find.text('The Office · S2:E4 · ora'), findsOneWidget);
    expect(find.text('Film · 1979 · 1h 57m'), findsOneWidget);
    expect(find.text(l.partyQueueUnavailable), findsOneWidget);
    // Le righe già viste sono attenuate.
    expect(
        tester
            .widget<Opacity>(find
                .ancestor(of: find.text('Ufficio in fiamme'),
                    matching: find.byType(Opacity))
                .first)
            .opacity,
        QueueRow.watchedOpacity);
  });

  testWidgets('primo titolo in riproduzione: niente "Già visti"',
      (tester) async {
    await pumpPanel(tester,
        notifier: ValueNotifier(PlayQueue(
          reason: 'NewPlaylist',
          lastUpdate: DateTime.utc(2026, 10, 4, 10),
          entries: const [
            PlayQueueEntry(itemId: 'e4', playlistItemId: 'p2'),
            PlayQueueEntry(itemId: 'e5', playlistItemId: 'p3'),
          ],
          playingIndex: 0,
          startPosition: Duration.zero,
          isPlaying: true,
        )));
    expect(find.text(l.partyQueueWatched), findsNothing);
    expect(find.text('2 titoli · 22m dopo questo'), findsOneWidget);
  });

  testWidgets('clic su una riga: ci si va; quella in corso non fa nulla',
      (tester) async {
    final calls = await pumpPanel(tester);
    await tester.tap(find.text('Halloween'));
    await tester.tap(find.text('Ufficio in fiamme'));
    await tester.tap(find.text('La festa'));
    expect(calls, ['jump p3', 'jump p1']);
  });

  testWidgets('togli: sui prossimi e sui già visti, non su quella in corso',
      (tester) async {
    final calls = await pumpPanel(tester);
    expect(inRow('p2', find.byTooltip(l.partyQueueRemove)), findsNothing);
    await tester.tap(inRow('p3', find.byTooltip(l.partyQueueRemove)));
    await tester.tap(inRow('p1', find.byTooltip(l.partyQueueRemove)));
    expect(calls, ['remove p3', 'remove p1']);
  });

  testWidgets('passando sopra una riga compaiono maniglia e ✕',
      (tester) async {
    await pumpPanel(tester);
    double opacityOf(Finder finder) => tester
        .widget<AnimatedOpacity>(find
            .ancestor(of: finder, matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    final remove = inRow('p3', find.byTooltip(l.partyQueueRemove));
    final grip = inRow('p3', find.byIcon(LucideIcons.gripVertical));
    expect(opacityOf(remove), 0);
    expect(opacityOf(grip), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Halloween')));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(opacityOf(remove), 1);
    expect(opacityOf(grip), 1);
    expect(inRow('p2', find.byIcon(LucideIcons.gripVertical)), findsNothing,
        reason: 'la riga in corso non si trascina');
    expect(inRow('p1', find.byIcon(LucideIcons.gripVertical)), findsNothing,
        reason: 'i già visti non si trascinano');
  });

  testWidgets('trascinamento tra i prossimi: la riga resta dove la si lascia, '
      'poi vale la coda del server', (tester) async {
    final notifier = ValueNotifier(queue());
    final calls = await pumpPanel(tester, notifier: notifier);
    double top(String id) => tester.getTopLeft(row(id)).dy;
    final rowHeight = tester.getSize(row('p3')).height;
    final gesture = await tester.startGesture(
        tester.getCenter(inRow('p4', find.byIcon(LucideIcons.gripVertical))));
    await tester.pump();
    await gesture.moveBy(Offset(0, -rowHeight));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, ['move p4 0']);
    expect(top('p4'), lessThan(top('p3')),
        reason: 'prima della coda nuova la riga resta dove la si è lasciata');

    // La coda nuova del server.
    notifier.value = queue(
        lastUpdate: DateTime.utc(2026, 10, 4, 10, 1),
        upcoming: const ['p4', 'p3', 'p5']);
    await tester.pump();
    expect(top('p4'), lessThan(top('p3')));
  });

  testWidgets('trascinamento verso il basso: indice dopo aver tolto la '
      'riga', (tester) async {
    final calls = await pumpPanel(tester);
    double top(String id) => tester.getTopLeft(row(id)).dy;
    final rowHeight = tester.getSize(row('p3')).height;
    final gesture = await tester.startGesture(
        tester.getCenter(inRow('p3', find.byIcon(LucideIcons.gripVertical))));
    await tester.pump();
    // Scendendo, la riga passa quando il suo bordo basso cade nella metà
    // bassa della seguente: con un passo intero si salterebbe oltre.
    for (var step = 0; step < 3; step++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.3));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, ['move p3 1']);
    expect(top('p3'), greaterThan(top('p4')));
  });

  testWidgets('trascinamento senza risposta: dopo 4 s torna l\'ordine della '
      'coda', (tester) async {
    await pumpPanel(tester);
    double top(String id) => tester.getTopLeft(row(id)).dy;
    final rowHeight = tester.getSize(row('p3')).height;
    final gesture = await tester.startGesture(
        tester.getCenter(inRow('p4', find.byIcon(LucideIcons.gripVertical))));
    await tester.pump();
    await gesture.moveBy(Offset(0, -rowHeight));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(top('p4'), lessThan(top('p3')));
    await tester.pump(QueuePanel.pendingTimeout);
    await tester.pumpAndSettle();
    expect(top('p4'), greaterThan(top('p3')));
  });

  testWidgets('ordine casuale: il pulsante dice lo stato e lo cambia',
      (tester) async {
    final notifier = ValueNotifier(queue());
    final calls = await pumpPanel(tester, notifier: notifier);
    final button = find.byKey(const Key('party-queue-shuffle'));
    expect(tester.widget<IconButton>(button).isSelected, isFalse);
    await tester.tap(button);
    notifier.value =
        queue(shuffled: true, lastUpdate: DateTime.utc(2026, 10, 4, 10, 1));
    await tester.pump();
    expect(tester.widget<IconButton>(button).isSelected, isTrue);
    await tester.tap(button);
    expect(calls, ['shuffle true', 'shuffle false']);
  });

  testWidgets('chiudi', (tester) async {
    final calls = await pumpPanel(tester);
    await tester.tap(find.byTooltip(l.playerClosePanel));
    expect(calls, ['close']);
  });

  testWidgets('dettagli in arrivo: righe senza titolo, poi complete',
      (tester) async {
    await pumpPanel(tester, details: const {});
    expect(find.text('…'), findsNWidgets(5));
    expect(find.text('5 titoli'), findsOneWidget, reason: 'nessuna durata nota');
  });
}
