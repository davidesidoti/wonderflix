import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/admin/wonderflix_tab.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/home_fakes.dart';
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
      await pumpTab(tester,
          features: const SocialFeatures(inbox: true, home: true));
      expect(find.text('Sonarr non è configurato'), findsOneWidget);
      expect(find.text('Collega il tuo account a Seerr'), findsNothing,
          reason: 'per tutti conta solo il plugin');
      expect(toggle(tester, HomeRowKind.upcomingSeries).onChanged, isNotNull);
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

      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(home.arrTestCalls, 1);
      expect(find.text('Collegato (versione 4.0.20)'), findsOneWidget);
      expect(find.text('Collegato (versione 6.4.4)'), findsOneWidget);

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
}
