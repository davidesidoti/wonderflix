import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/account_settings_section.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAccountApi api;

  setUp(() => api = FakeAccountApi());

  Future<void> pumpSection(
    WidgetTester tester, {
    bool available = true,
    JellyfinUser user = testUser,
    List<Override> extra = const [],
  }) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: AccountSettingsSection())),
      overrides: [
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
        ...accountTestOverrides(api, available: available),
        ...extra,
      ],
    );
    // I contatti arrivano.
    await tester.pump();
  }

  testWidgets('senza la funzione account: il cambio password, niente contatti',
      (tester) async {
    await pumpSection(tester, available: false);

    expect(find.text('Cambia password'), findsOneWidget);
    expect(find.text('Accesso come Mario'), findsOneWidget);
    expect(find.text('Contatti per il recupero'), findsNothing);
    expect(api.contactsCalls, 0);
  });

  testWidgets('righe: collegato, canale spento, il testo sotto',
      (tester) async {
    api.contactsResult = const AccountContacts(
        discordAvailable: true, emailAvailable: false, discordName: 'garg');
    await pumpSection(tester);

    expect(find.text('Contatti per il recupero'), findsOneWidget);
    expect(find.text('Collegato: garg'), findsOneWidget);
    expect(find.text('Non disponibile su questo server'), findsOneWidget);
    expect(find.text('Cambia'), findsOneWidget);
    expect(find.byKey(const Key('account-unlink-Discord')), findsOneWidget);
    expect(find.byKey(const Key('account-link-Email')), findsNothing);
    expect(find.byKey(const Key('account-unlink-Email')), findsNothing);
    expect(find.text('Servono per recuperare la password se la dimentichi.'),
        findsOneWidget);
  });

  testWidgets('contatti in arrivo: lo spinner, poi le righe', (tester) async {
    api.contactsGate = Completer<void>();
    await pumpSection(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('account-contact-Discord')), findsNothing);

    // Mentre c'è lo spinner `pumpAndSettle` non finirebbe: si usa `pump`.
    api.contactsGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('account-contact-Discord')), findsOneWidget);
  });

  testWidgets('i pulsanti dicono il canale allo screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    api.contactsResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, discordName: 'garg');
    await pumpSection(tester);

    expect(find.bySemanticsLabel('Cambia Discord'), findsOneWidget);
    expect(find.bySemanticsLabel('Scollega Discord'), findsOneWidget);
    expect(find.bySemanticsLabel('Collega Email'), findsOneWidget);
    // Prima della fine del test: dopo, `flutter_test` la darebbe per persa.
    semantics.dispose();
  });

  testWidgets('righe: su uno schermo largo restano vicine al contatto',
      (tester) async {
    await pumpSection(tester);

    final row = find.byKey(const Key('account-contact-Discord'));
    expect(tester.getSize(row).width, lessThanOrEqualTo(640));
  });

  testWidgets('canale spento con il contatto: si può scollegare',
      (tester) async {
    api.contactsResult = const AccountContacts(
        discordAvailable: true, email: 'a@example.com');
    await pumpSection(tester);

    expect(find.text('Non disponibile su questo server'), findsOneWidget);
    expect(find.byKey(const Key('account-link-Email')), findsNothing);
    expect(find.byKey(const Key('account-unlink-Email')), findsOneWidget);
  });

  testWidgets('admin: anche la frase sul recupero automatico', (tester) async {
    await pumpSection(tester,
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));

    expect(
        find.text('Servono per recuperare la password se la dimentichi. '
            'Gli admin non possono usare il recupero automatico.'),
        findsOneWidget);
  });

  testWidgets('Collega: la finestra, poi la riga collegata', (tester) async {
    api.confirmResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, email: 'a@example.com');
    await pumpSection(tester);
    expect(find.text('Non collegato'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('account-link-Email')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('link-target')), 'a@example.com');
    await tester.tap(find.byKey(const Key('link-submit')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('link-code')), '123456');
    await tester.tap(find.byKey(const Key('link-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Collegato: a@example.com'), findsOneWidget);
    expect(find.text('Contatto collegato'), findsOneWidget);
    // I contatti nuovi vengono da Confirm, senza rileggerli.
    expect(api.contactsCalls, 1);
  });

  testWidgets('Scollega: la password, poi i contatti riletti', (tester) async {
    api.contactsResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, discordName: 'garg');
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('account-unlink-Discord')));
    await tester.pumpAndSettle();
    api.contactsResult =
        const AccountContacts(discordAvailable: true, emailAvailable: true);
    await tester.enterText(find.byKey(const Key('unlink-password')), 'segreta');
    await tester.tap(find.byKey(const Key('unlink-submit')));
    await tester.pumpAndSettle();

    expect(api.unlinkCalls.single, (AccountChannel.discord, 'segreta'));
    expect(find.text('Contatto scollegato'), findsOneWidget);
    expect(find.text('Non collegato'), findsNWidgets(2));
    expect(api.contactsCalls, 2);
  });

  testWidgets('contatti non letti: messaggio e Riprova', (tester) async {
    api.contactsFailure = AccountFailure.network;
    await pumpSection(tester);
    expect(find.text('Non è stato possibile leggere i contatti'),
        findsOneWidget);

    api.contactsFailure = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Non collegato'), findsNWidgets(2));
  });

  testWidgets('Cambia password: avviso dopo il cambio', (tester) async {
    final adapter = FakeAdapter((_) => const FakeResponse(204));
    await pumpSection(tester, available: false, extra: [
      authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
          baseUrl: testServerUrl,
          clientInfo: testClientInfo,
          adapter: adapter))),
    ]);

    await tester.tap(find.byKey(const Key('settings-change-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('change-password-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('change-password-confirm')), 'nuova123');
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Password cambiata. Gli altri dispositivi dovranno rientrare.'),
        findsOneWidget);
  });
}
