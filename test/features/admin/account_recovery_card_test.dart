import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_recovery_card.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
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
}
