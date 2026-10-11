import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/home/home_rows_editor.dart';
import 'package:wonderflix/features/home/home_user_editor.dart';
import 'package:wonderflix/features/settings/home_settings_section.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeDisplayPreferencesApi prefs;
  late FakeHomeApi home;
  late FakeRequestsApi requests;

  setUp(() {
    prefs = FakeDisplayPreferencesApi();
    home = FakeHomeApi();
    requests = FakeRequestsApi();
  });

  Future<void> pumpSection(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(home: true),
      FakeSocialAvailability? availability}) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: HomeSettingsSection())),
      surfaceSize: const Size(1440, 1400),
      overrides: homeOverrides(
          library: FakeLibraryApi(),
          home: home,
          prefs: prefs,
          features: features,
          availability: availability,
          requests: requests),
    );
    await tester.pump();
    await tester.pump();
  }

  bool resetEnabled(WidgetTester tester) =>
      tester
          .widget<OutlinedButton>(find.descendant(
              of: find.byKey(const Key('home-rows-reset')),
              matching: find.bySubtype<OutlinedButton>()))
          .onPressed !=
      null;

  testWidgets('l\'elenco con i motivi delle righe che non ci sono',
      (tester) async {
    requests.meValue = const RequestsMe(
        canRequest: true, canManage: false, hasAccount: false);
    await pumpSection(tester,
        features: const SocialFeatures(home: true, requests: true));
    expect(find.byType(HomeRowsEditor), findsOneWidget);
    expect(find.text('Collega il tuo account a Seerr'), findsOneWidget);
    expect(find.text('Sonarr non è configurato'), findsOneWidget);
    expect(find.text('Radarr non è configurato'), findsOneWidget);
    expect(find.text('Vale per questo account su tutti i PC.'), findsOneWidget);
  });

  testWidgets('mentre /Me si legge, Le mie richieste non ha un motivo',
      (tester) async {
    requests.meGate = Completer<void>();
    await pumpSection(tester,
        features: const SocialFeatures(home: true, requests: true));
    expect(find.text('Collega il tuo account a Seerr'), findsNothing);
    expect(find.text('Seerr non è configurato'), findsNothing);
    requests.meGate!.complete();
  });

  testWidgets('se /Me non si legge, Le mie richieste non ha un motivo',
      (tester) async {
    requests.meFailure = RequestsFailure.seerrUnavailable;
    await pumpSection(tester,
        features: const SocialFeatures(home: true, requests: true));
    expect(find.byType(HomeRowsEditor), findsOneWidget);
    expect(find.text('Collega il tuo account a Seerr'), findsNothing,
        reason: 'non si sa se l\'account c\'è');
    expect(find.text('Seerr non è configurato'), findsNothing);
    // Le altre righe dicono il loro motivo.
    expect(find.text('Sonarr non è configurato'), findsOneWidget);
  });

  testWidgets('finché le funzioni del plugin non sono note nessuna riga ha un '
      'motivo', (tester) async {
    final availability = FakeSocialAvailability(SocialFeatures.unknown);
    await pumpSection(tester, availability: availability);
    expect(find.byType(HomeRowsEditor), findsOneWidget);
    for (final reason in [
      'Seerr non è configurato',
      'Collega il tuo account a Seerr',
      'Serve il plugin 1.5.0',
      'Sonarr non è configurato',
      'Radarr non è configurato',
    ]) {
      expect(find.text(reason), findsNothing, reason: reason);
    }

    // Note le funzioni, i motivi compaiono.
    availability.set(const SocialFeatures(home: true));
    await tester.pump();
    expect(find.text('Sonarr non è configurato'), findsOneWidget);
    expect(find.text('Serve il plugin 1.5.0'), findsOneWidget);
  });

  testWidgets('un interruttore si salva da solo dopo 500 ms', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
    await tester.pump();
    expect(prefs.written, isEmpty);
    await tester.pump(homeEditorSaveDelay);
    await tester.pump();
    expect(prefs.written.single.$2.hidden, ['nextUp']);
  });

  testWidgets('salvataggio fallito: "Non salvato, riprova"', (tester) async {
    prefs.writeError = const ServerUnreachableException();
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
    await tester.pump(homeEditorSaveDelay);
    await tester.pump();
    expect(find.byKey(const Key('home-rows-save-failed')), findsOneWidget);
    expect(
        tester
            .widget<Switch>(find.byKey(const Key('home-rows-switch-nextUp')))
            .value,
        isTrue,
        reason: 'l\'elenco è tornato all\'ultimo stato salvato');
  });

  testWidgets('Ripristina: spento senza ritocchi, acceso con, poi li toglie',
      (tester) async {
    await pumpSection(tester);
    expect(resetEnabled(tester), isFalse);

    prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
    // Smontato davvero: un `ProviderScope` che si aggiorna terrebbe il
    // controller già letto, con le preferenze di prima.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSection(tester);
    expect(resetEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('home-rows-reset')));
    await tester.pump();
    await tester.pump();
    expect(prefs.resets, ['u1']);
    expect(resetEnabled(tester), isFalse);
  });

  testWidgets('lettura fallita: errore e Riprova', (tester) async {
    prefs.error = const ServerUnreachableException();
    await pumpSection(tester);
    expect(find.byType(HomeRowsEditor), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);
    prefs.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeRowsEditor), findsOneWidget);
  });

  testWidgets('rilettura fallita: errore e Riprova, non l\'elenco di prima',
      (tester) async {
    prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
    await pumpSection(tester);
    expect(find.byType(HomeRowsEditor), findsOneWidget);

    // La rilettura fallisce: l'editor ha l'errore e, sotto, il vecchio
    // elenco, ma l'elenco non è più modificabile.
    prefs.error = const ServerUnreachableException();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeSettingsSection)));
    container.invalidate(homeUserEditorProvider);
    await tester.pump();
    await tester.pump();
    final state = container.read(homeUserEditorProvider);
    expect(state.hasError, isTrue);
    expect(state.hasValue, isTrue);
    expect(find.byType(HomeRowsEditor), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.byKey(const Key('home-rows-reset')), findsNothing);

    prefs.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeRowsEditor), findsOneWidget);
    expect(resetEnabled(tester), isTrue);
  });

  testWidgets(
      'mentre l\'elenco si rilegge non si tocca: attenuato, e Ripristina spento',
      (tester) async {
    prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
    await pumpSection(tester);
    bool ignoring() => tester
        .widget<IgnorePointer>(find.byKey(const Key('home-rows-list')))
        .ignoring;
    double opacity() => tester
        .widget<Opacity>(find.ancestor(
            of: find.byType(HomeRowsEditor), matching: find.byType(Opacity)))
        .opacity;
    expect(ignoring(), isFalse);
    expect(opacity(), 1);
    expect(resetEnabled(tester), isTrue);

    // Una rilettura dello stesso utente: l'elenco ha ancora il valore di
    // prima, ma sta per essere sostituito.
    prefs.readGate = Completer<void>();
    ProviderScope.containerOf(tester.element(find.byType(HomeSettingsSection)))
        .invalidate(homeUserEditorProvider);
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeRowsEditor), findsOneWidget);
    expect(ignoring(), isTrue);
    expect(opacity(), lessThan(1));
    expect(resetEnabled(tester), isFalse);

    prefs.readGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(ignoring(), isFalse);
    expect(opacity(), 1);
    expect(resetEnabled(tester), isTrue);
  });
}
