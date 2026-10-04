import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/player/queue_panel/queue_add_view.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel_state.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  late FakeLibraryApi library;

  final heat = testItem(id: 'm1', name: 'Heat', year: 1995, sortName: 'heat');
  final alien =
      testItem(id: 'm2', name: 'Alien', year: 1979, sortName: 'alien');
  final dark = testItem(
      id: 's1',
      name: 'Dark',
      kind: ItemKind.series,
      childCount: 3,
      sortName: 'dark');

  setUp(() {
    library = FakeLibraryApi()
      ..onItems = (query, start, limit) => query.favoritesOnly
          ? pageOf([heat, dark, alien])
          : pageOf([alien]);
  });

  /// La vista con la coda e4 (in corso), m2 (Alien, già in coda).
  Future<List<String>> pumpView(WidgetTester tester,
      {PlayQueue? queue, FocusNode? focusNode}) async {
    final calls = <String>[];
    final node = focusNode ?? FocusNode();
    addTearDown(node.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 360,
            height: 900,
            child: QueueAddView(
              queue: queue ?? testSeriesQueue(itemIds: const ['e4', 'm2']),
              focusNode: node,
              onAdd: (items, {required next}) async => calls.add(
                  '${next ? 'next' : 'end'} ${items.map((i) => i.id).join(',')}'),
              onOpenSeries: (series) => calls.add('series ${series.id}'),
              onBack: () => calls.add('back'),
              onClose: () => calls.add('close'),
            ),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        libraryApiProvider.overrideWithValue(library),
        // La ricerca ascolta la sessione del party: niente WebSocket.
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    await tester.pump();
    return calls;
  }

  testWidgets('campo vuoto: La mia lista in ordine di titolo, il campo ha il '
      'focus', (tester) async {
    final node = FocusNode();
    await pumpView(tester, focusNode: node);
    expect(find.text(l.partyQueueMyList), findsOneWidget);
    final titles = [
      for (final name in ['Alien', 'Dark', 'Heat'])
        tester.getTopLeft(find.text(name)).dy,
    ];
    expect(titles, orderedEquals([...titles]..sort()));
    expect(find.text('Film · 1995 · 2h'), findsOneWidget);
    expect(find.text('Serie · 3 stagioni'), findsOneWidget);
    expect(node.hasFocus, isTrue);
  });

  testWidgets('film: riproduci dopo e in coda; già in coda → ✓', (tester) async {
    final calls = await pumpView(tester);
    final heatRow = find.byKey(const ValueKey('queue-add-m1'));
    await tester.tap(
        find.descendant(of: heatRow, matching: find.byTooltip(l.partyQueuePlayNext)));
    await tester.pump();
    await tester.tap(
        find.descendant(of: heatRow, matching: find.byTooltip(l.partyQueueAddToEnd)));
    await tester.pump();
    expect(calls, ['next m1', 'end m1']);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('queue-add-m2')),
            matching: find.text(l.partyQueueInQueue)),
        findsOneWidget);
  });

  testWidgets('serie: il clic apre le stagioni', (tester) async {
    final calls = await pumpView(tester);
    await tester.tap(find.text('Dark'));
    expect(calls, ['series s1']);
  });

  testWidgets('ricerca: da 2 lettere i risultati sostituiscono La mia lista',
      (tester) async {
    await pumpView(tester);
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(QueueAddSearch.debounce);
    await tester.pump();
    expect(find.text(l.partyQueueResults), findsOneWidget);
    expect(find.text(l.partyQueueMyList), findsNothing);
    expect(find.text('Heat'), findsNothing);
    expect(find.text('Alien'), findsOneWidget);
  });

  testWidgets('Esc: prima svuota il campo, poi chiude', (tester) async {
    final calls = await pumpView(tester);
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
    expect(calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['close']);
  });

  testWidgets('← torna indietro', (tester) async {
    final calls = await pumpView(tester);
    await tester.tap(find.byTooltip(l.navBack));
    expect(calls, ['back']);
  });

  testWidgets('coda piena: pulsanti spenti', (tester) async {
    final calls = await pumpView(tester,
        queue: testSeriesQueue(
            itemIds: [for (var i = 0; i < 100; i++) 'x$i'], playingIndex: 0));
    await tester.tap(find
        .descendant(
            of: find.byKey(const ValueKey('queue-add-m1')),
            matching: find.byTooltip(l.partyQueueFull(100)))
        .first);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('lista vuota ed errore con Riprova', (tester) async {
    library.onItems = (query, start, limit) => pageOf(const []);
    await pumpView(tester);
    expect(find.text(l.partyQueueMyListEmpty), findsOneWidget);

    library.error = const ServerUnreachableException();
    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pump(QueueAddSearch.debounce);
    await tester.pump();
    expect(find.text(l.partyQueueLoadFailed), findsOneWidget);
    library.error = null;
    await tester.tap(find.text(l.retry));
    await tester.pump();
    await tester.pump();
    expect(find.text(l.partyQueueNoResults), findsOneWidget);
  });
}
