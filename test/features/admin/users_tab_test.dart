import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/users_tab.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakePluginAdminApi plugin;
  late FakeAdapter adapter;

  setUp(() {
    plugin = FakePluginAdminApi();
    adapter = FakeAdapter((_) => const FakeResponse(204));
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: UsersTab()), overrides: [
      ...adminTestOverrides(FakeAdminApi(),
          plugin: plugin,
          session: FakeSessionController(const SessionSignedIn(testAdmin)),
          features: const SocialFeatures(inbox: true, account: true)),
      authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
          baseUrl: testServerUrl,
          clientInfo: testClientInfo,
          adapter: adapter))),
    ]);
    await tester.pumpAndSettle();
  }

  /// Apre il menu della riga di [userId] e sceglie [label].
  Future<void> choose(WidgetTester tester, String userId, String label) async {
    await tester.tap(find.byKey(Key('user-menu-$userId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('userActions', () {
    const garg = AdminAccountUser(
        id: 'u2',
        name: 'garg',
        isAdmin: false,
        enabled: true,
        discordName: 'garg');

    test('un utente con un contatto: tutte e tre', () {
      expect(userActions(garg, isMe: false), [
        UserAction.setPassword,
        UserAction.sendRecovery,
        UserAction.unlink,
      ]);
    });

    test('la propria riga: niente "Imposta password"', () {
      expect(userActions(garg, isMe: true),
          [UserAction.sendRecovery, UserAction.unlink]);
    });

    test('senza contatti: solo "Imposta password"', () {
      const lucia = AdminAccountUser(
          id: 'u3', name: 'lucia', isAdmin: false, enabled: true);
      expect(userActions(lucia, isMe: false), [UserAction.setPassword]);
      expect(userActions(lucia, isMe: true), isEmpty);
    });

    test('admin o disattivato: niente codice', () {
      const admin = AdminAccountUser(
          id: 'u5',
          name: 'altro',
          isAdmin: true,
          enabled: true,
          maskedEmail: 'a•••@example.com');
      const disabled = AdminAccountUser(
          id: 'u4',
          name: 'vecchio',
          isAdmin: false,
          enabled: false,
          maskedEmail: 'v•••@example.com');
      expect(userActions(admin, isMe: false),
          [UserAction.setPassword, UserAction.unlink]);
      expect(userActions(disabled, isMe: false),
          [UserAction.setPassword, UserAction.unlink]);
    });
  });

  testWidgets('righe: nome, Admin, Disattivato, contatti nei tooltip',
      (tester) async {
    await pumpTab(tester);

    for (final name in ['garg', 'lucia', 'Mario', 'vecchio']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Disattivato'), findsOneWidget);
    expect(find.byTooltip('Discord: garg'), findsOneWidget);
    expect(find.byTooltip('Email: g•••@example.com'), findsOneWidget);
    expect(find.byTooltip('Discord non collegato'), findsNWidgets(2));
    expect(find.byTooltip('Email non collegata'), findsNWidgets(2));
  });

  testWidgets('il menu di garg ha le tre azioni', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byKey(const Key('user-menu-u2')));
    await tester.pumpAndSettle();

    expect(find.text('Imposta password'), findsOneWidget);
    expect(find.text('Invia codice di recupero'), findsOneWidget);
    expect(find.text('Scollega contatti'), findsOneWidget);
  });

  testWidgets('Invia codice di recupero: conferma, poi dove è arrivato',
      (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u2', 'Invia codice di recupero');
    expect(find.text('Mandare a garg un codice per cambiare la password?'),
        findsOneWidget);
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    expect(plugin.calls, contains('recovery:u2:it'));
    expect(find.text('Codice mandato su Discord ed email'), findsOneWidget);
  });

  testWidgets('Invia codice: l\'errore del plugin con il suo testo',
      (tester) async {
    plugin.actionError =
        const ServerErrorException(409, {'Code': 'NoContacts'});
    await pumpTab(tester);

    await choose(tester, 'u2', 'Invia codice di recupero');
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    expect(find.text('garg non ha contatti su un canale attivo'),
        findsOneWidget);
  });

  testWidgets('Scollega contatti: conferma e avviso', (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u2', 'Scollega contatti');
    expect(find.text('Scollegare i contatti di garg?'), findsOneWidget);
    await tester.tap(find.text('Scollega'));
    await tester.pumpAndSettle();

    expect(plugin.calls, contains('unlink:u2'));
    expect(find.text('Contatti di garg scollegati'), findsOneWidget);
    // La rilettura dopo l'azione: la riga non ha più contatti.
    expect(find.byTooltip('Discord: garg'), findsNothing);
    expect(find.byTooltip('Discord non collegato'), findsNWidgets(3));
  });

  testWidgets('Annulla: nessuna azione', (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u2', 'Scollega contatti');
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(plugin.calls.where((c) => c.startsWith('unlink')), isEmpty);
  });

  testWidgets('Imposta password: la finestra, poi l\'avviso', (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u3', 'Imposta password');
    expect(find.text('Imposta la password di lucia'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('set-password-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('set-password-confirm')), 'nuova123');
    await tester.tap(find.byKey(const Key('set-password-submit')));
    await tester.pumpAndSettle();

    expect(adapter.requests.single.queryParameters, {'userId': 'u3'});
    expect(find.text('Password impostata. Le sessioni di lucia sono state '
        'chiuse.'), findsOneWidget);
  });

  testWidgets('elenco non letto: errore e Riprova', (tester) async {
    plugin.accountUsersError = const ServerUnreachableException();
    await pumpTab(tester);
    expect(find.byType(ErrorView), findsOneWidget);

    plugin.accountUsersError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('garg'), findsOneWidget);
  });
}
