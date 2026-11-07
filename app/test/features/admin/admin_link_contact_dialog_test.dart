import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/users_tab.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakePluginAdminApi plugin;

  setUp(() {
    plugin = FakePluginAdminApi()
      ..accountStatusValue = testChannelsStatus(discord: true, email: true);
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: UsersTab()),
      overrides: adminTestOverrides(FakeAdminApi(),
          plugin: plugin,
          features: const SocialFeatures(
              inbox: true, account: true, accountAdminLink: true)),
      surfaceSize: const Size(1440, 900),
    );
    await tester.pumpAndSettle();
  }

  /// Poche pump: mentre il dialogo è aperto la riga ha lo spinner, che non
  /// si ferma mai.
  Future<void> pumpBusy(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Apre il dialogo [label] dal menu di lucia (u3, senza contatti).
  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('user-menu-u3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await pumpBusy(tester);
  }

  final field = find.byKey(const Key('admin-link-field'));
  final submit = find.byKey(const Key('admin-link-submit'));

  Finder submitText(String text) =>
      find.descendant(of: submit, matching: find.text(text));

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(submit);
    await pumpBusy(tester);
  }

  testWidgets('Discord: Cerca, anteprima, Associa', (tester) async {
    plugin.lookupValue = const AdminDiscordMember(
        id: 'd42', username: 'Mario', displayName: 'Mario Rossi');
    await pumpTab(tester);
    await open(tester, 'Associa Discord');
    expect(find.text('Associa Discord a lucia'), findsOneWidget);
    expect(submitText('Cerca'), findsOneWidget);

    await tester.enterText(field, 'mario');
    await tapSubmit(tester);
    expect(plugin.calls, contains('lookup:mario'));
    expect(find.text('@Mario'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(submitText('Associa'), findsOneWidget);

    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(plugin.calls, contains('setDiscord:u3:d42'));
    expect(find.text('Associa Discord a lucia'), findsNothing);
    expect(find.text('Discord associato a lucia'), findsOneWidget);
    final icon = find.descendant(
        of: find.byTooltip('Discord: Mario'),
        matching: find.byIcon(LucideIcons.messageCircle));
    expect(tester.widget<Icon>(icon).color, WfColors.gold);
  });

  testWidgets('Discord: cambiare il nome toglie l\'anteprima', (tester) async {
    plugin.lookupValue =
        const AdminDiscordMember(id: 'd42', username: 'Mario');
    await pumpTab(tester);
    await open(tester, 'Associa Discord');

    await tester.enterText(field, 'mario');
    await tapSubmit(tester);
    expect(find.text('@Mario'), findsOneWidget);

    await tester.enterText(field, 'mario2');
    await pumpBusy(tester);
    expect(find.text('@Mario'), findsNothing);
    expect(submitText('Cerca'), findsOneWidget);

    await tapSubmit(tester);
    expect(plugin.calls, contains('lookup:mario2'));
    expect(plugin.calls.where((c) => c.startsWith('setDiscord')), isEmpty);
  });

  testWidgets('Discord: nome cambiato durante la ricerca: niente anteprima',
      (tester) async {
    plugin.lookupValue =
        const AdminDiscordMember(id: 'd42', username: 'Mario');
    final gate = plugin.lookupGate = Completer<void>();
    await pumpTab(tester);
    await open(tester, 'Associa Discord');

    await tester.enterText(field, 'mario');
    await tapSubmit(tester);
    await tester.enterText(field, 'mario2');
    gate.complete();
    await pumpBusy(tester);

    expect(plugin.calls, contains('lookup:mario'));
    expect(find.text('@Mario'), findsNothing);
    expect(submitText('Cerca'), findsOneWidget);
  });

  testWidgets('Discord: Cerca con il campo vuoto non fa niente',
      (tester) async {
    await pumpTab(tester);
    await open(tester, 'Associa Discord');

    await tapSubmit(tester);
    expect(plugin.calls.where((c) => c.startsWith('lookup')), isEmpty);
  });

  testWidgets('Discord: nome non trovato sotto il campo, dialogo aperto',
      (tester) async {
    await pumpTab(tester);
    await open(tester, 'Associa Discord');

    await tester.enterText(field, 'nessuno');
    await tapSubmit(tester);
    expect(find.text('Nome non trovato nel server Discord'), findsOneWidget);
    expect(find.text('Associa Discord a lucia'), findsOneWidget);
    expect(submitText('Cerca'), findsOneWidget);
  });

  testWidgets('Discord: canale spento sul server', (tester) async {
    plugin.lookupError = const ServerErrorException(503, {'Code': 'ChannelOff'});
    await pumpTab(tester);
    await open(tester, 'Associa Discord');

    await tester.enterText(field, 'mario');
    await tapSubmit(tester);
    expect(find.text('Canale non configurato sul server'), findsOneWidget);
  });

  testWidgets('email: Associa, poi l\'avviso', (tester) async {
    await pumpTab(tester);
    await open(tester, 'Associa email');
    expect(find.text('Associa email a lucia'), findsOneWidget);

    await tester.enterText(field, 'mario@example.com');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(plugin.calls, contains('setEmail:u3:mario@example.com'));
    expect(find.text('Email associata a lucia'), findsOneWidget);
    expect(find.byTooltip('Email: m•••@example.com'), findsOneWidget);
  });

  testWidgets('email: indirizzo non valido sotto il campo', (tester) async {
    plugin.actionError =
        const ServerErrorException(400, {'Code': 'InvalidTarget'});
    await pumpTab(tester);
    await open(tester, 'Associa email');

    await tester.enterText(field, 'nope');
    await tapSubmit(tester);
    expect(find.text('Email non valida'), findsOneWidget);
    expect(find.text('Associa email a lucia'), findsOneWidget);
  });

  testWidgets('durante la richiesta il pulsante è spento e il dialogo resta',
      (tester) async {
    final gate = plugin.accountActionGate = Completer<void>();
    await pumpTab(tester);
    await open(tester, 'Associa email');

    await tester.enterText(field, 'mario@example.com');
    await tapSubmit(tester);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tapAt(const Offset(5, 5));
    await pumpBusy(tester);
    expect(find.text('Associa email a lucia'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Email associata a lucia'), findsOneWidget);
  });
}
