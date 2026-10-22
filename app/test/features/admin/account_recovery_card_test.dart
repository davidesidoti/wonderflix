import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_recovery_card.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakePluginAdminApi plugin;

  setUp(() => plugin = FakePluginAdminApi());

  Future<void> pumpCard(WidgetTester tester,
      {SocialFeatures features =
          const SocialFeatures(inbox: true, account: true)}) async {
    await pumpApp(
        tester,
        const Scaffold(
            body: SingleChildScrollView(child: AccountRecoveryCard())),
        overrides: adminTestOverrides(FakeAdminApi(),
            plugin: plugin, features: features));
    await tester.pumpAndSettle();
  }

  testWidgets('senza la funzione account: niente card, niente letture',
      (tester) async {
    await pumpCard(tester, features: const SocialFeatures(inbox: true));

    expect(find.text('Recupero password'), findsNothing);
    expect(plugin.count('accountStatus'), 0);
  });

  testWidgets('canali, ultimo errore, conteggi, promemoria, dove si configura',
      (tester) async {
    await pumpCard(tester);

    expect(find.text('Recupero password'), findsOneWidget);
    expect(find.text('Discord: configurato'), findsOneWidget);
    expect(find.text('Email: non configurato'), findsOneWidget);
    expect(find.textContaining('Ultimo errore: DM chiusi'), findsOneWidget);
    expect(find.text('5 utenti su 23 hanno un contatto'), findsOneWidget);
    expect(find.text('Promemoria ogni 14 giorni'), findsOneWidget);
    expect(
        find.text(
            'Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix'),
        findsOneWidget);
  });

  testWidgets('promemoria spenti', (tester) async {
    plugin.accountStatusValue = const AccountAdminStatus(
      discord: AccountChannelStatus(configured: true),
      email: AccountChannelStatus(configured: true),
      withContacts: 2,
      users: 23,
      reminderDays: 0,
    );
    await pumpCard(tester);

    expect(find.text('Promemoria spenti'), findsOneWidget);
    expect(find.textContaining('Ultimo errore'), findsNothing);
  });

  testWidgets('Invia prova a me: l\'esito per canale', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.text('Invia prova a me'));
    await tester.pumpAndSettle();

    expect(plugin.calls, contains('accountTest:it'));
    expect(find.text('Discord: inviato · Email: collega prima il tuo contatto'),
        findsOneWidget);
  });

  testWidgets('lettura fallita: l\'errore della card', (tester) async {
    plugin.accountStatusError = const ServerUnreachableException();
    await pumpCard(tester);

    expect(find.byType(AdminCardError), findsOneWidget);
  });

  testWidgets('lettura fallita, poi Riprova: la card si riempie',
      (tester) async {
    plugin.accountStatusError = const ServerUnreachableException();
    await pumpCard(tester);
    expect(find.text('Discord: configurato'), findsNothing);

    plugin.accountStatusError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.byType(AdminCardError), findsNothing);
    expect(find.text('Discord: configurato'), findsOneWidget);
  });

  testWidgets('rilettura fallita con i dati di prima: "Dati non aggiornati"',
      (tester) async {
    await pumpCard(tester);
    expect(find.textContaining('Dati non aggiornati'), findsNothing);

    plugin.accountStatusError = const ServerUnreachableException();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
    expect(find.text('Discord: configurato'), findsOneWidget,
        reason: 'i dati di prima restano');
  });

  testWidgets('prova non riuscita: l\'avviso, e nessun esito vecchio',
      (tester) async {
    await pumpCard(tester);
    await tester.tap(find.text('Invia prova a me'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Discord: inviato'), findsOneWidget);

    plugin.actionError = const ServerUnreachableException();
    await tester.tap(find.text('Invia prova a me'));
    await tester.pumpAndSettle();

    expect(find.text(it.errorServerUnreachable), findsOneWidget);
    expect(find.textContaining('Discord: inviato'), findsNothing);
  });

  group('card fuori vista durante la prova', () {
    /// La card in una lista lunga, in una finestra bassa: scorrendo la card
    /// esce dalla vista.
    Future<void> pumpScrolling(WidgetTester tester) async {
      await pumpApp(
          tester,
          Scaffold(
              body: ListView(children: const [
            AccountRecoveryCard(),
            SizedBox(height: 3000),
          ])),
          overrides: adminTestOverrides(FakeAdminApi(),
              plugin: plugin,
              features: const SocialFeatures(inbox: true, account: true)),
          surfaceSize: const Size(1440, 400));
      await tester.pumpAndSettle();
    }

    Future<void> scroll(WidgetTester tester, double dy) async {
      await tester.drag(find.byType(ListView), Offset(0, dy));
      await tester.pumpAndSettle();
    }

    testWidgets('l\'esito arriva anche se si è scorso via', (tester) async {
      final gate = plugin.accountActionGate = Completer<void>();
      await pumpScrolling(tester);

      await tester.tap(find.text('Invia prova a me'));
      await tester.pump();
      await scroll(tester, -2500);
      expect(find.text('Invia prova a me'), findsNothing,
          reason: 'la card è fuori vista');

      gate.complete();
      await tester.pumpAndSettle();
      await scroll(tester, 2500);

      expect(find.text('Discord: inviato · Email: collega prima il tuo '
          'contatto'), findsOneWidget);
    });

    testWidgets('la card tiene lo stato: il pulsante resta spento',
        (tester) async {
      plugin.accountActionGate = Completer<void>();
      await pumpScrolling(tester);

      await tester.tap(find.text('Invia prova a me'));
      await tester.pump();
      await scroll(tester, -2500);
      await scroll(tester, 2500);

      final button = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('Invia prova a me'),
          matching: find.bySubtype<OutlinedButton>()));
      expect(button.onPressed, isNull, reason: 'la prova è ancora in corso');
    });
  });
}
