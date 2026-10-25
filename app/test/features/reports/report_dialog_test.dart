import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/reports/reports_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/reports/report_dialog.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/l10n/gen/app_localizations_it.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';
import '../../support/test_data.dart';

void main() {
  final AppLocalizations l = AppLocalizationsIt();

  JellyfinItem episode({String? seasonId = 'se1', int? season = 1}) => testItem(
    id: 'e1',
    name: 'Pilot',
    kind: ItemKind.episode,
    seriesId: 's1',
    seriesName: 'Dark',
    seasonId: seasonId,
    seasonIndex: season,
    index: 2,
  );

  group('reportTargets', () {
    test('da un episodio: episodio, stagione, serie', () {
      final targets = reportTargets(l, episode());
      expect(
        [for (final t in targets) (t.itemId, t.label)],
        [
          ('e1', 'Questo episodio'),
          ('se1', 'Stagione 1'),
          ('s1', 'Tutta la serie'),
        ],
      );
    });

    test('da una stagione: stagione e serie', () {
      final targets = reportTargets(
        l,
        testItem(
          id: 'se1',
          kind: ItemKind.season,
          seriesId: 's1',
          seriesName: 'Dark',
          index: 2,
        ),
      );
      expect(
        [for (final t in targets) (t.itemId, t.label)],
        [('se1', 'Questa stagione'), ('s1', 'Tutta la serie')],
      );
    });

    test('stagione 0: Speciali', () {
      final targets = reportTargets(l, episode(season: 0));
      expect(targets[1].label, 'Speciali');
    });

    test('episodio senza seasonId: senza la voce della stagione', () {
      final targets = reportTargets(l, episode(seasonId: null));
      expect([for (final t in targets) t.itemId], ['e1', 's1']);
    });

    test('film e serie: un solo bersaglio', () {
      expect(reportTargets(l, testItem(id: 'm1')), hasLength(1));
      expect(
        reportTargets(l, testItem(id: 's1', kind: ItemKind.series)).single,
        isA<ReportTarget>().having((t) => t.itemId, 'itemId', 's1'),
      );
    });
  });

  group('finestra', () {
    late FakeReportsApi api;
    late FakeSessionController session;

    setUp(() {
      api = FakeReportsApi();
      session = FakeSessionController(const SessionSignedIn(testUser));
    });

    Future<void> open(
      WidgetTester tester,
      JellyfinItem item, {
      Size surfaceSize = const Size(1440, 900),
    }) async {
      await pumpApp(
        tester,
        surfaceSize: surfaceSize,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(showReportDialog(context, item)),
              child: const Text('apri'),
            ),
          ),
        ),
        overrides: [
          ...reportTestOverrides(reports: api),
          sessionControllerProvider.overrideWith(() => session),
        ],
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(390, 844), Size(844, 390)]) {
      testWidgets(
        'episodio ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
        (tester) async {
          await open(tester, episode(), surfaceSize: size);
          expect(find.byType(ChoiceChip), findsNWidgets(3 + 4));
          expect(tester.takeException(), isNull);
        },
      );
    }

    // `WfButton.primary` è un `FilledButton.icon`, sottoclasse privata.
    Finder submit() => find.ancestor(
      of: find.text('Invia segnalazione'),
      matching: find.bySubtype<FilledButton>(),
    );

    bool submitEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(submit()).onPressed != null;

    testWidgets('titolo, riga del contenuto e livelli di un episodio', (
      tester,
    ) async {
      await open(tester, episode());

      expect(find.text('Segnala un problema'), findsOneWidget);
      expect(find.text('Dark · S1 E2 “Pilot”'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(3 + 4));
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Questo episodio'),
            )
            .selected,
        isTrue,
      );
    });

    testWidgets('un film non ha la riga dei livelli', (tester) async {
      await open(tester, testItem(id: 'm1', name: 'Dune'));

      expect(find.text('Dune'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(4));
    });

    testWidgets('Invia spento finché non si sceglie il tipo', (tester) async {
      await open(tester, testItem(id: 'm1'));
      expect(submitEnabled(tester), isFalse);

      await tester.tap(find.text('Sottotitoli'));
      await tester.pump();

      expect(submitEnabled(tester), isTrue);
    });

    testWidgets('invia al bersaglio scelto con tipo e nota', (tester) async {
      await open(tester, episode());

      await tester.tap(find.text('Tutta la serie'));
      await tester.pump();
      await tester.tap(find.text('Audio o video'));
      await tester.enterText(find.byType(TextField), 'manca la voce');
      await tester.pump();
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(api.calls, contains('create s1 AudioVideo manca la voce'));
      expect(find.text('Segnala un problema'), findsNothing);
      expect(find.text('Segnalazione inviata agli admin'), findsOneWidget);
    });

    testWidgets('doppione: avviso e nota precompilata', (tester) async {
      api.mineById['m1'] = [
        testReport(
          itemId: 'm1',
          type: ReportType.subtitles,
          note: 'vecchia',
          itemType: ReportItemType.movie,
        ),
      ];
      await open(tester, testItem(id: 'm1'));
      expect(find.textContaining('Hai già segnalato'), findsNothing);

      await tester.tap(find.text('Audio o video'));
      await tester.pump();
      expect(find.textContaining('Hai già segnalato'), findsNothing);

      await tester.tap(find.text('Sottotitoli'));
      await tester.pump();

      expect(find.textContaining('Hai già segnalato'), findsOneWidget);
      expect(find.text('vecchia'), findsOneWidget);
    });

    testWidgets('doppione: la nota già scritta non si tocca', (tester) async {
      api.mineById['m1'] = [
        testReport(
          itemId: 'm1',
          note: 'vecchia',
          itemType: ReportItemType.movie,
        ),
      ];
      await open(tester, testItem(id: 'm1'));
      await tester.enterText(find.byType(TextField), 'nuova');

      await tester.tap(find.text('Sottotitoli'));
      await tester.pump();

      expect(find.textContaining('Hai già segnalato'), findsOneWidget);
      expect(find.text('nuova'), findsOneWidget);
      expect(find.text('vecchia'), findsNothing);
    });

    testWidgets('cambio di bersaglio: nuova lettura delle proprie', (
      tester,
    ) async {
      await open(tester, episode());
      expect(api.calls, ['mine e1']);

      await tester.tap(find.text('Tutta la serie'));
      await tester.pump();

      expect(api.calls, ['mine e1', 'mine s1']);
    });

    testWidgets('cambio di bersaglio: via avviso e nota del precedente', (
      tester,
    ) async {
      api.mineById['e1'] = [
        testReport(type: ReportType.subtitles, note: 'vecchia'),
      ];
      await open(tester, episode());
      await tester.tap(find.text('Sottotitoli'));
      await tester.pump();
      expect(find.textContaining('Hai già segnalato'), findsOneWidget);
      expect(find.text('vecchia'), findsOneWidget);

      // La lettura del nuovo bersaglio è ancora in corso.
      final gate = api.gate = Completer<void>();
      await tester.tap(find.text('Tutta la serie'));
      await tester.pump();

      expect(find.textContaining('Hai già segnalato'), findsNothing);
      expect(find.text('vecchia'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('un errore nella lettura delle proprie non si mostra', (
      tester,
    ) async {
      api.nextFailure = ReportsFailure.network;
      await open(tester, testItem(id: 'm1'));

      await tester.tap(find.text('Sottotitoli'));
      await tester.pump();

      expect(find.textContaining('Hai già segnalato'), findsNothing);
      expect(find.text('Qualcosa è andato storto. Riprova.'), findsNothing);
      expect(submitEnabled(tester), isTrue);
    });

    testWidgets('contatore della nota da 450 punti di codice', (tester) async {
      await open(tester, testItem(id: 'm1'));
      expect(find.textContaining('/500'), findsNothing);

      await tester.enterText(find.byType(TextField), 'a' * 450);
      await tester.pump();
      expect(find.text('450/500'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a' * 600);
      await tester.pump();
      expect(find.text('500/500'), findsOneWidget);
    });

    testWidgets('limite raggiunto: messaggio nella finestra che resta aperta', (
      tester,
    ) async {
      await open(tester, testItem(id: 'm1'));
      await tester.tap(find.text('Altro'));
      await tester.pump();
      api.nextFailure = ReportsFailure.limitReached;

      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.textContaining('Hai già 20 segnalazioni'), findsOneWidget);
      expect(find.text('Segnala un problema'), findsOneWidget);
      expect(submitEnabled(tester), isTrue);
    });

    testWidgets('permesso tolto: messaggio e rilettura dell\'utente', (
      tester,
    ) async {
      await open(tester, testItem(id: 'm1'));
      await tester.tap(find.text('Altro'));
      await tester.pump();
      api.nextFailure = ReportsFailure.forbidden;

      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.text('Non hai il permesso per farlo'), findsOneWidget);
      expect(session.refreshUserCalls, 1);
    });

    testWidgets('doppio clic su Invia: una sola chiamata', (tester) async {
      await open(tester, testItem(id: 'm1'));
      await tester.tap(find.text('Altro'));
      await tester.pump();
      api.calls.clear();
      final gate = api.gate = Completer<void>();

      await tester.tap(submit());
      await tester.pump();
      expect(submitEnabled(tester), isFalse);
      await tester.tap(submit(), warnIfMissed: false);
      await tester.pump();

      expect(api.calls.where((c) => c.startsWith('create')), hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Segnalazione inviata agli admin'), findsOneWidget);
    });
  });
}
