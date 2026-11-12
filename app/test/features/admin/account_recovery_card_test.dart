import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_recovery_card.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakePluginAdminApi plugin;

  setUp(() => plugin = FakePluginAdminApi());

  /// La fascia con il dettaglio già aperto (dove stanno canali e conteggi).
  Future<void> pumpCard(WidgetTester tester) async {
    await pumpApp(
        tester,
        const Scaffold(
            body: SingleChildScrollView(child: AccountRecoveryBand())),
        overrides: adminTestOverrides(FakeAdminApi(),
            plugin: plugin,
            features: const SocialFeatures(inbox: true, account: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recupero password'));
    await tester.pumpAndSettle();
  }

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

  group('fascia fuori vista durante la prova', () {
    /// La fascia in una lista lunga, in una finestra bassa: scorrendo esce
    /// dalla vista.
    Future<void> pumpScrolling(WidgetTester tester) async {
      await pumpApp(
          tester,
          Scaffold(
              body: ListView(children: const [
            AccountRecoveryBand(),
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
          reason: 'la fascia è fuori vista');

      gate.complete();
      await tester.pumpAndSettle();
      await scroll(tester, 2500);

      expect(find.text('Discord: inviato · Email: collega prima il tuo '
          'contatto'), findsOneWidget);
    });

    testWidgets('la fascia tiene lo stato: il pulsante resta spento',
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

  group('AccountRecoveryBand', () {
    Future<void> pumpBand(WidgetTester tester) async {
      await pumpApp(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AccountRecoveryBand())),
          overrides: adminTestOverrides(FakeAdminApi(),
              plugin: plugin,
              features: const SocialFeatures(inbox: true, account: true)));
      await tester.pumpAndSettle();
    }

    Finder lamp(LampState state, String label) => find.byWidgetPredicate(
        (w) => w is WfLamp && w.state == state && w.label.contains(label));

    testWidgets('una spia per canale: Discord configurato, email spenta',
        (tester) async {
      plugin.accountStatusValue = const AccountAdminStatus(
        discord: AccountChannelStatus(configured: true),
        email: AccountChannelStatus(configured: false),
        withContacts: 5,
        users: 23,
        reminderDays: 14,
      );
      await pumpBand(tester);

      expect(find.text('Recupero password'), findsOneWidget);
      expect(lamp(LampState.ok, 'Discord'), findsOneWidget);
      expect(lamp(LampState.off, 'Email'), findsOneWidget);
      expect(find.text('Promemoria ogni 14 giorni'), findsNothing,
          reason: 'il dettaglio è chiuso');
    });

    testWidgets('con un ultimo errore la spia è rossa', (tester) async {
      await pumpBand(tester);

      expect(lamp(LampState.broken, 'Discord'), findsOneWidget);
      expect(find.textContaining('DM chiusi'), findsOneWidget);
    });

    testWidgets('cliccando la fascia si apre il dettaglio, e si richiude',
        (tester) async {
      await pumpBand(tester);

      await tester.tap(find.text('Recupero password'));
      await tester.pumpAndSettle();
      expect(find.text('5 utenti su 23 hanno un contatto'), findsOneWidget);
      expect(find.text('Promemoria ogni 14 giorni'), findsOneWidget);
      expect(
          find.text(
              'Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix'),
          findsOneWidget);

      await tester.tap(find.text('Recupero password'));
      await tester.pumpAndSettle();
      expect(find.text('Promemoria ogni 14 giorni'), findsNothing);
    });

    testWidgets('Invia prova a me: l\'esito, senza aprire il dettaglio',
        (tester) async {
      await pumpBand(tester);

      await tester.tap(find.text('Invia prova a me'));
      await tester.pumpAndSettle();

      expect(plugin.calls, contains('accountTest:it'));
      expect(
          find.text('Discord: inviato · Email: collega prima il tuo contatto'),
          findsOneWidget);
      expect(find.text('Promemoria ogni 14 giorni'), findsNothing);
    });

    testWidgets('lettura fallita: l\'errore, poi Riprova', (tester) async {
      plugin.accountStatusError = const ServerUnreachableException();
      await pumpBand(tester);
      expect(find.byType(AdminCardError), findsOneWidget);

      plugin.accountStatusError = null;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminCardError), findsNothing);
      expect(lamp(LampState.broken, 'Discord'), findsOneWidget);
    });

    testWidgets('senza la funzione account: niente fascia', (tester) async {
      await pumpApp(tester, const Scaffold(body: AccountRecoveryBand()),
          overrides: adminTestOverrides(FakeAdminApi(),
              plugin: plugin, features: const SocialFeatures(inbox: true)));
      await tester.pumpAndSettle();

      expect(find.text('Recupero password'), findsNothing);
      expect(plugin.count('accountStatus'), 0);
    });
  });
}
