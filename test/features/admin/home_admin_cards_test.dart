import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/admin/home_admin_cards.dart';
import 'package:wonderflix/features/admin/wonderflix_tab.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeHomeApi home;

  setUp(() => home = FakeHomeApi());

  const all = SocialFeatures(
      inbox: true,
      home: true,
      requests: true,
      collections: true,
      upcomingSeries: true,
      upcomingMovies: true);

  Future<void> pumpTab(WidgetTester tester,
      {SocialFeatures features = all,
      Size size = const Size(1440, 2600)}) async {
    await pumpApp(tester, const Scaffold(body: WonderflixTab()),
        overrides: adminTestOverrides(FakeAdminApi(),
            home: home, features: features),
        surfaceSize: size);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, Key key) =>
      tester
          .widget<OutlinedButton>(find.descendant(
              of: find.byKey(key), matching: find.bySubtype<OutlinedButton>()))
          .onPressed !=
      null;

  Switch toggle(WidgetTester tester, HomeRowKind row) => tester
      .widget<Switch>(find.byKey(ValueKey('home-rows-switch-${row.id}')));

  testWidgets('senza la funzione home: "Serve il plugin 1.7.0", nessuna '
      'chiamata', (tester) async {
    await pumpTab(tester, features: const SocialFeatures(inbox: true));
    expect(find.text('Serve il plugin 1.7.0'), findsNWidgets(2));
    expect(home.layoutCalls, 0);
    expect(home.arrTestCalls, 0);
  });

  testWidgets('le due card dopo Novità e prima di Seerr', (tester) async {
    await pumpTab(tester);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Novità'), lessThan(y('Home per tutti')));
    expect(y('Home per tutti'), lessThan(y('Sonarr e Radarr')));
    expect(y('Sonarr e Radarr'), lessThan(y('Seerr')));
  });

  group('Home per tutti', () {
    testWidgets('Salva solo con modifiche, poi la Home dell\'admin si rilegge',
        (tester) async {
      await pumpTab(tester);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(WonderflixTab)));
      container.listen(homeAdminRowsProvider, (_, _) {});
      await tester.pump();
      expect(toggle(tester, HomeRowKind.nextUp).value, isTrue);
      expect(enabled(tester, const Key('admin-home-save')), isFalse);

      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();
      expect(enabled(tester, const Key('admin-home-save')), isTrue);

      final calls = home.layoutCalls;
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls.last, [
        for (final row in HomeRowKind.values)
          if (row != HomeRowKind.nextUp) row.id,
      ]);
      expect(enabled(tester, const Key('admin-home-save')), isFalse);
      expect(home.layoutCalls, greaterThan(calls),
          reason: 'homeAdminRowsProvider invalidato');
    });

    testWidgets('l\'ordine nuovo si salva', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.text('Prossimi episodi'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-rows-up')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls.last!.take(2), ['nextUp', 'resume']);
    });

    testWidgets('Ripristina chiede conferma', (tester) async {
      home.layoutRows = ['myList'];
      await pumpTab(tester);
      expect(toggle(tester, HomeRowKind.resume).value, isFalse);
      expect(enabled(tester, const Key('admin-home-reset')), isTrue);

      await tester.tap(find.byKey(const Key('admin-home-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Tornare alla Home predefinita per tutti?'),
          findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls, isEmpty);

      await tester.tap(find.byKey(const Key('admin-home-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FilledButton, 'Ripristina la Home predefinita'));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls, [null]);
      expect(toggle(tester, HomeRowKind.resume).value, isTrue);
      expect(enabled(tester, const Key('admin-home-reset')), isFalse);
    });

    testWidgets('una riga non disponibile ha il motivo ma si accende',
        (tester) async {
      home.layoutRows = ['resume'];
      // Con `requests` il plugin ha Seerr: se contasse l'account di chi
      // guarda (che qui non c'è), "Le mie richieste" direbbe "Collega il tuo
      // account a Seerr".
      await pumpTab(tester,
          features: const SocialFeatures(
              inbox: true, home: true, requests: true));
      expect(find.text('Sonarr non è configurato'), findsOneWidget);
      expect(find.text('Collega il tuo account a Seerr'), findsNothing,
          reason: 'per tutti conta solo il plugin');
      expect(find.text('Seerr non è configurato'), findsNothing,
          reason: 'il plugin ha Seerr');
      expect(toggle(tester, HomeRowKind.upcomingSeries).onChanged, isNotNull);
    });

    testWidgets('senza Seerr nel plugin "Le mie richieste" lo dice',
        (tester) async {
      home.layoutRows = ['resume'];
      await pumpTab(tester,
          features: const SocialFeatures(inbox: true, home: true));
      expect(find.text('Seerr non è configurato'), findsOneWidget);
      expect(toggle(tester, HomeRowKind.requests).onChanged, isNotNull);
    });

    testWidgets('Home salvata senza righe: tutto spento, Ripristina serve',
        (tester) async {
      home.layoutRows = [];
      await pumpTab(tester);
      for (final row in HomeRowKind.values) {
        expect(toggle(tester, row).value, isFalse, reason: row.id);
      }
      expect(enabled(tester, const Key('admin-home-save')), isFalse);
      expect(enabled(tester, const Key('admin-home-reset')), isTrue);
    });

    testWidgets('una modifica mentre si salva non si perde', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();

      final gate = home.setLayoutGate = Completer<void>();
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pump();
      expect(home.setLayoutCalls, hasLength(1));

      // Il salvataggio è in corso e l'elenco si può ancora cambiare.
      await tester.tap(find.byKey(const Key('home-rows-switch-latestMovies')));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(toggle(tester, HomeRowKind.nextUp).value, isFalse);
      expect(toggle(tester, HomeRowKind.latestMovies).value, isFalse,
          reason: 'la modifica fatta durante il salvataggio resta');
      expect(enabled(tester, const Key('admin-home-save')), isTrue);
      expect(home.setLayoutCalls.single, [
        for (final row in HomeRowKind.values)
          if (row != HomeRowKind.nextUp) row.id,
      ], reason: 'il primo salvataggio non conteneva la seconda modifica');

      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls.last, [
        for (final row in HomeRowKind.values)
          if (row != HomeRowKind.nextUp && row != HomeRowKind.latestMovies)
            row.id,
      ]);
      expect(enabled(tester, const Key('admin-home-save')), isFalse);
    });

    testWidgets('un riordino mentre si salva non si perde', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();

      final gate = home.setLayoutGate = Completer<void>();
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pump();

      await tester.tap(find.text('La mia lista'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-rows-up')));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(enabled(tester, const Key('admin-home-save')), isTrue);
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      final sent = home.setLayoutCalls.last!;
      expect(sent.sublist(sent.length - 2), ['myList', 'upcomingMovies']);
    });

    testWidgets('una modifica mentre si ripristina non si perde',
        (tester) async {
      home.layoutRows = ['myList', 'resume'];
      await pumpTab(tester);

      final gate = home.setLayoutGate = Completer<void>();
      await tester.tap(find.byKey(const Key('admin-home-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FilledButton, 'Ripristina la Home predefinita'));
      await tester.pump();
      expect(home.setLayoutCalls, [null]);

      await tester.tap(find.byKey(const Key('home-rows-switch-resume')));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(toggle(tester, HomeRowKind.resume).value, isFalse,
          reason: 'la modifica fatta durante il ripristino resta');
      expect(enabled(tester, const Key('admin-home-save')), isTrue);
      expect(enabled(tester, const Key('admin-home-reset')), isTrue);
    });

    testWidgets('la bozza resta scorrendo', (tester) async {
      await pumpTab(tester, size: const Size(1440, 700));
      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, -4000));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 4000));
      await tester.pumpAndSettle();
      expect(toggle(tester, HomeRowKind.nextUp).value, isFalse);
      expect(enabled(tester, const Key('admin-home-save')), isTrue);
    });

    testWidgets('lettura fallita: Riprova', (tester) async {
      home.layoutError = const ServerUnreachableException();
      await pumpTab(tester);
      expect(find.text('Riprova'), findsOneWidget);
      home.layoutError = null;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-home-save')), findsOneWidget);
    });

    testWidgets('salvataggio fallito: l\'errore e la bozza resta',
        (tester) async {
      home.setLayoutError = const ServerUnreachableException();
      await pumpTab(tester);
      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(enabled(tester, const Key('admin-home-save')), isTrue);
      expect(toggle(tester, HomeRowKind.nextUp).value, isFalse);
    });
  });

  group('uscendo dalla scheda durante il salvataggio', () {
    // Il salvataggio che parte dalla card continua anche se l'admin lascia la
    // scheda (la card si smonta e il controller non ha più ascoltatori):
    // quando il server risponde la Home dell'admin si rilegge lo stesso.
    ProviderContainer open() {
      final container = ProviderContainer.test(
        overrides: homeOverrides(
            library: FakeLibraryApi(), home: home, features: all),
        retry: (_, _) => null,
      );
      // Chi guarda la Home dell'admin (la Home, per esempio): si rilegge
      // quando viene invalidata.
      container.listen(homeAdminRowsProvider, (_, _) {});
      return container;
    }

    Future<void> idle() => Future<void>.delayed(Duration.zero);

    test("Salva: la Home dell'admin si rilegge", () async {
      final container = open();
      final card = container.listen(adminHomeEditorProvider, (_, _) {});
      await container.read(adminHomeEditorProvider.future);
      await container.read(homeAdminRowsProvider.future);
      final editor = container.read(adminHomeEditorProvider.notifier);
      editor.setOn(HomeRowKind.nextUp, false);

      final gate = home.setLayoutGate = Completer<void>();
      final saving = editor.save();
      await idle();
      expect(home.setLayoutCalls, hasLength(1));
      card.close(); // l'admin lascia la scheda
      await idle();
      await idle();
      expect(container.exists(adminHomeEditorProvider), isTrue,
          reason: 'resta aperto finché il server non risponde');

      final calls = home.layoutCalls;
      gate.complete();
      await saving;
      await idle();
      await idle();
      expect(home.layoutCalls, greaterThan(calls),
          reason: 'homeAdminRowsProvider invalidato dopo il salvataggio');
      expect(container.exists(adminHomeEditorProvider), isFalse,
          reason: 'finito, si chiude');
    });

    test("Ripristina: la Home dell'admin si rilegge", () async {
      home.layoutRows = ['myList'];
      final container = open();
      final card = container.listen(adminHomeEditorProvider, (_, _) {});
      await container.read(adminHomeEditorProvider.future);
      await container.read(homeAdminRowsProvider.future);
      final editor = container.read(adminHomeEditorProvider.notifier);

      final gate = home.setLayoutGate = Completer<void>();
      final resetting = editor.reset();
      await idle();
      expect(home.setLayoutCalls, [null]);
      card.close();
      await idle();
      await idle();

      final calls = home.layoutCalls;
      gate.complete();
      await resetting;
      await idle();
      await idle();
      expect(home.layoutCalls, greaterThan(calls));
      expect(container.exists(adminHomeEditorProvider), isFalse);
    });

    test('un salvataggio fallito chiude lo stesso il controller', () async {
      final container = open();
      final card = container.listen(adminHomeEditorProvider, (_, _) {});
      await container.read(adminHomeEditorProvider.future);
      final editor = container.read(adminHomeEditorProvider.notifier);
      editor.setOn(HomeRowKind.nextUp, false);

      home.setLayoutError = const ServerUnreachableException();
      final gate = home.setLayoutGate = Completer<void>();
      final saving = editor.save();
      await idle();
      card.close();
      gate.complete();
      await expectLater(saving, throwsA(isA<ServerUnreachableException>()));
      await idle();
      await idle();
      expect(container.exists(adminHomeEditorProvider), isFalse,
          reason: 'il blocco si toglie anche se il server ha dato errore');
    });
  });

  group('Sonarr e Radarr', () {
    testWidgets('configurati o no, poi l\'esito della prova', (tester) async {
      await pumpTab(tester,
          features: const SocialFeatures(
              inbox: true, home: true, upcomingSeries: true));
      expect(
          find.descendant(
              of: find.byKey(const Key('arr-radarr')),
              matching: find.text('Non configurato')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('arr-sonarr')),
              matching: find.text('Non configurato')),
          findsNothing);
      // Configurato ma non ancora provato: una riga con la sua scritta, non
      // vuota.
      expect(
          find.descendant(
              of: find.byKey(const Key('arr-sonarr')),
              matching: find.text('Configurato')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('arr-radarr')),
              matching: find.text('Configurato')),
          findsNothing);

      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(home.arrTestCalls, 1);
      expect(find.text('Collegato (versione 4.0.20)'), findsOneWidget);
      expect(find.text('Collegato (versione 6.4.4)'), findsOneWidget);
      expect(find.text('Configurato'), findsNothing,
          reason: 'dopo la prova conta l\'esito');

      home.arrTest = const ArrTestResults(
        sonarr: ArrTestResult(
            configured: true, ok: false, error: UpcomingError.unauthorized),
        radarr: ArrTestResult(
            configured: true, ok: false, error: UpcomingError.unreachable),
      );
      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(find.text('Chiave API rifiutata'), findsOneWidget);
      expect(find.text("Non raggiungibile: controlla l'indirizzo"),
          findsOneWidget);
    });

    testWidgets('prova fallita: l\'errore nello SnackBar', (tester) async {
      home.arrTestError = const ServerUnreachableException();
      await pumpTab(tester);
      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('arrTestLabel', () {
    final it = lookupAppLocalizations(const Locale('it'));

    test('non configurato', () {
      expect(arrTestLabel(it, const ArrTestResult(configured: false, ok: false)),
          'Non configurato');
    });

    test('riuscita, con la versione o senza', () {
      expect(
          arrTestLabel(it,
              const ArrTestResult(configured: true, ok: true, version: '4.0.20')),
          'Collegato (versione 4.0.20)');
      expect(arrTestLabel(it, const ArrTestResult(configured: true, ok: true)),
          'Collegato (versione ?)');
    });

    test('chiave rifiutata', () {
      expect(
          arrTestLabel(
              it,
              const ArrTestResult(
                  configured: true,
                  ok: false,
                  error: UpcomingError.unauthorized)),
          'Chiave API rifiutata');
    });

    test('non raggiungibile', () {
      expect(
          arrTestLabel(
              it,
              const ArrTestResult(
                  configured: true,
                  ok: false,
                  error: UpcomingError.unreachable)),
          "Non raggiungibile: controlla l'indirizzo");
    });

    test('NotConfigured anche se il servizio risulta configurato', () {
      expect(
          arrTestLabel(
              it,
              const ArrTestResult(
                  configured: true,
                  ok: false,
                  error: UpcomingError.notConfigured)),
          'Non configurato');
    });

    test('un codice sconosciuto vale come irraggiungibile', () {
      final result = ArrTestResult.fromJson(
          {'Configured': true, 'Ok': false, 'Error': 'Mistero'});
      expect(result.error, UpcomingError.unreachable);
      expect(arrTestLabel(it, result),
          "Non raggiungibile: controlla l'indirizzo");
    });

    test('configurato e non riuscito, senza errore: non raggiungibile', () {
      expect(arrTestLabel(it, const ArrTestResult(configured: true, ok: false)),
          "Non raggiungibile: controlla l'indirizzo");
    });
  });
}
