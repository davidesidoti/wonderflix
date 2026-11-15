import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/mylist/my_list_band.dart';
import 'package:wonderflix/features/mylist/my_list_view.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

MyListView _view({
  JellyfinItem? hero,
  int tab = 0,
  int resume = 0,
  int start = 0,
  int watched = 0,
}) => MyListView(
  hero: hero,
  resume: const [],
  start: const [],
  watched: const [],
  tabCount: tab,
  resumeCount: resume,
  startCount: start,
  watchedCount: watched,
  genres: const [],
  showRefinements: false,
  listEmpty: false,
  removableWatched: const [],
  noResults: false,
);

const _minute = 600000000;

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  group('myListBandLine', () {
    test('conteggio in grassetto crema e pezzi diversi da zero', () {
      final line = myListBandLine(
        it,
        MyListTab.all,
        _view(tab: 8, resume: 1, start: 4, watched: 3),
      );
      expect(
        line.toPlainText(),
        '8 titoli: 1 da continuare, 4 da iniziare, 3 visti.',
      );
      final bold = line.children!.first as TextSpan;
      expect(bold.text, '8 titoli');
      expect(bold.style?.fontWeight, FontWeight.w600);
      expect(bold.style?.color, WfColors.cream);
    });

    test('scheda Serie', () {
      expect(
        myListBandLine(
          it,
          MyListTab.series,
          _view(tab: 3, resume: 1, start: 2),
        ).toPlainText(),
        '3 serie: 1 da continuare, 2 da iniziare.',
      );
    });

    test('scheda Film e un solo visto', () {
      expect(
        myListBandLine(
          it,
          MyListTab.movies,
          _view(tab: 1, watched: 1),
        ).toPlainText(),
        '1 film: 1 visto.',
      );
    });

    test('senza pezzi: solo il conteggio', () {
      expect(
        myListBandLine(it, MyListTab.all, _view(tab: 8)).toPlainText(),
        '8 titoli.',
      );
    });
  });

  group('MyListBandAction', () {
    late FakeLibraryApi library;
    setUp(() => library = FakeLibraryApi());

    Future<void> pump(
      WidgetTester tester,
      JellyfinItem hero, {
      bool resuming = false,
      List<Override> overrides = const [],
      Size surface = const Size(1440, 900),
    }) {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: MyListBandAction(hero: hero, resuming: resuming),
            ),
          ),
          GoRoute(
            path: '/item/:id',
            builder: (_, state) => Text('scheda ${state.pathParameters['id']}'),
          ),
          GoRoute(
            path: '/play/:id',
            builder: (_, state) => Text(
              'player ${state.pathParameters['id']} ${state.uri.queryParameters['start'] ?? '-'}',
            ),
          ),
        ],
      );
      return pumpAppRouter(
        tester,
        router,
        surfaceSize: surface,
        overrides: [
          libraryApiProvider.overrideWithValue(library),
          sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser)),
          ),
          ...overrides,
        ],
      );
    }

    testWidgets('film iniziato: Riprendi e "ne restano 66 min"', (
      tester,
    ) async {
      await pump(
        tester,
        testItem(
          id: 'm1',
          name: 'Dune',
          runtimeMinutes: 120,
          positionTicks: 54 * _minute,
        ),
        resuming: true,
      );
      expect(find.text('Riprendi'), findsOneWidget);
      expect(
        find.textContaining('Da dove eri rimasto: Dune, ne restano 66 min'),
        findsOneWidget,
      );
    });

    testWidgets('film non iniziato: Riproduci e "Il prossimo:"', (
      tester,
    ) async {
      await pump(tester, testItem(id: 'm1', name: 'Dune'));
      expect(find.text('Riproduci'), findsOneWidget);
      expect(find.textContaining('Il prossimo: Dune'), findsOneWidget);
      expect(find.textContaining('restano'), findsNothing);
    });

    testWidgets('serie: Riproduci finché arriva l\'episodio, poi Riprendi', (
      tester,
    ) async {
      final next = Completer<JellyfinItem?>();
      await pump(
        tester,
        testItem(
          id: 's1',
          name: 'Lost',
          kind: ItemKind.series,
          unplayedCount: 1,
        ),
        resuming: true,
        overrides: [
          seriesNextEpisodeProvider.overrideWith((ref, id) => next.future),
        ],
      );
      expect(find.text('Riproduci'), findsOneWidget);
      expect(find.textContaining('Da dove eri rimasto: Lost'), findsOneWidget);
      expect(find.textContaining("l'ultimo episodio"), findsOneWidget);

      next.complete(
        testItem(
          id: 'e8',
          name: 'Otto',
          kind: ItemKind.episode,
          seriesId: 's1',
          seasonIndex: 1,
          index: 8,
          positionTicks: 5 * _minute,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Riprendi S1:E8'), findsOneWidget);
      expect(find.text('Riproduci'), findsNothing);
      expect(
        find.textContaining(
          'Da dove eri rimasto: Lost, S1:E8, l\'ultimo episodio',
        ),
        findsOneWidget,
      );
    });

    testWidgets('serie con episodio non iniziato: Riproduci S1:E3', (
      tester,
    ) async {
      await pump(
        tester,
        testItem(
          id: 's1',
          name: 'Lost',
          kind: ItemKind.series,
          unplayedCount: 5,
        ),
        overrides: [
          seriesNextEpisodeProvider.overrideWith(
            (ref, id) => testItem(
              id: 'e3',
              kind: ItemKind.episode,
              seriesId: 's1',
              seasonIndex: 1,
              index: 3,
            ),
          ),
        ],
      );
      await tester.pump();
      expect(find.text('Riproduci S1:E3'), findsOneWidget);
      expect(find.textContaining("l'ultimo"), findsNothing);
    });

    testWidgets('il pulsante avvia playItem', (tester) async {
      await pump(
        tester,
        testItem(id: 'm1', positionTicks: 23 * 60 * 10000000),
        resuming: true,
      );
      await tester.tap(find.text('Riprendi'));
      await tester.pumpAndSettle();
      expect(find.text('player m1 1380000'), findsOneWidget);
    });

    testWidgets(
      'serie senza episodio ancora arrivato: il pulsante apre la scheda',
      (tester) async {
        await pump(
          tester,
          testItem(id: 's1', kind: ItemKind.series),
          overrides: [
            seriesNextEpisodeProvider.overrideWith(
              (ref, id) => Completer<JellyfinItem?>().future,
            ),
          ],
        );
        await tester.tap(find.text('Riproduci'));
        await tester.pumpAndSettle();
        expect(find.text('scheda s1'), findsOneWidget);
      },
    );

    testWidgets('il nome del titolo apre la scheda', (tester) async {
      await pump(tester, testItem(id: 'm1', name: 'Dune'));
      await tester.tapOnText(find.textRange.ofSubstring('Dune'));
      await tester.pumpAndSettle();
      expect(find.text('scheda m1'), findsOneWidget);
    });

    testWidgets('i dati utente di sessione cambiano il pulsante', (
      tester,
    ) async {
      await pump(tester, testItem(id: 'm1'));
      expect(find.text('Riproduci'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MyListBandAction)),
      );
      container
          .read(userDataOverridesProvider.notifier)
          .apply('m1', const UserItemData(playbackPositionTicks: 10 * _minute));
      await tester.pump();
      expect(find.text('Riprendi'), findsOneWidget);
    });

    testWidgets('sul telefono la frase sta sotto il pulsante', (tester) async {
      await pump(
        tester,
        testItem(id: 'm1', name: 'Dune'),
        surface: const Size(390, 800),
      );
      final button = tester.getRect(find.byType(FilledButton));
      final phrase = tester.getRect(find.textContaining('Il prossimo'));
      expect(phrase.top, greaterThanOrEqualTo(button.bottom));
    });
  });
}
