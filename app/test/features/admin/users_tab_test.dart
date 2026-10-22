import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
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

  /// La scheda; [session] è l'admin che guarda (di default `testAdmin`).
  Future<void> pumpTab(
    WidgetTester tester, {
    FakeSessionController? session,
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await pumpApp(
      tester,
      const Scaffold(body: UsersTab()),
      overrides: [
        ...adminTestOverrides(FakeAdminApi(),
            plugin: plugin,
            session: session ??
                FakeSessionController(const SessionSignedIn(testAdmin)),
            features: const SocialFeatures(inbox: true, account: true)),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
      surfaceSize: surfaceSize,
    );
    await tester.pumpAndSettle();
  }

  /// Poche pump al posto di `pumpAndSettle`, per quando una riga è al lavoro:
  /// il suo spinner non si ferma mai, e `pumpAndSettle` andrebbe in timeout.
  Future<void> pumpBusy(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Apre il menu della riga di [userId] e sceglie [label]. Da lì la riga è
  /// al lavoro (anche con la finestra di conferma aperta): [pumpBusy].
  Future<void> choose(WidgetTester tester, String userId, String label) async {
    await tester.tap(find.byKey(Key('user-menu-$userId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await pumpBusy(tester);
  }

  /// "Invia codice di recupero" a [userId], confermato: con il cancello
  /// dell'azione chiuso, resta in corso.
  Future<void> startSending(WidgetTester tester, String userId) async {
    await choose(tester, userId, 'Invia codice di recupero');
    await tester.tap(find.text('Invia'));
    await pumpBusy(tester);
  }

  bool menuEnabled(WidgetTester tester, String userId) => tester
      .widget<PopupMenuButton<UserAction>>(
          find.byKey(Key('user-menu-$userId')))
      .enabled;

  /// Lo spinner al posto dell'icona del menu di [userId].
  Finder spinnerOf(String userId) => find.descendant(
      of: find.byKey(Key('user-menu-$userId')),
      matching: find.byType(CircularProgressIndicator));

  /// L'icona del menu di [userId].
  Finder iconOf(String userId) => find.descendant(
      of: find.byKey(Key('user-menu-$userId')),
      matching: find.byIcon(LucideIcons.ellipsisVertical));

  /// Garg e gli altri di [testAccountUsers], poi [count] utenti senza
  /// contatti: una lista che in una finestra bassa si scorre.
  List<AdminAccountUser> longList(int count) => [
        ...testAccountUsers(),
        for (var i = 0; i < count; i++)
          AdminAccountUser(
              id: 'p$i', name: 'utente $i', isAdmin: false, enabled: true),
      ];

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

  testWidgets('il pulsante del menu dice di chi sono le azioni',
      (tester) async {
    await pumpTab(tester);

    expect(find.byTooltip('Azioni per garg'), findsOneWidget);
    expect(find.byTooltip('Azioni per lucia'), findsOneWidget);
  });

  testWidgets('la propria riga: niente "Imposta password", anche con l\'id '
      'scritto in un altro modo', (tester) async {
    // Jellyfin dà l'id dell'admin con i trattini e maiuscole, il plugin in
    // formato `N`: si confrontano con `jellyfinIdKey`.
    await pumpTab(tester,
        session: FakeSessionController(const SessionSignedIn(JellyfinUser(
            id: 'U-1', name: 'Mario', isAdministrator: true))));

    await tester.tap(find.byKey(const Key('user-menu-u1')));
    await tester.pumpAndSettle();

    expect(find.text('Scollega contatti'), findsOneWidget);
    expect(find.text('Imposta password'), findsNothing);
  });

  testWidgets('una riga senza azioni non ha il menu', (tester) async {
    // La propria riga, senza contatti: niente password (è la propria), niente
    // codice (è admin), niente scollegamento.
    plugin.accountUsersValue = const [
      AdminAccountUser(id: 'u1', name: 'Mario', isAdmin: true, enabled: true),
      AdminAccountUser(id: 'u3', name: 'lucia', isAdmin: false, enabled: true),
    ];
    await pumpTab(tester);

    expect(find.byKey(const Key('user-menu-u1')), findsNothing);
    expect(find.byKey(const Key('user-menu-u3')), findsOneWidget);
    expect(find.byTooltip('Azioni per Mario'), findsNothing);
  });

  testWidgets('elenco vuoto: Nessun utente', (tester) async {
    plugin.accountUsersValue = const [];
    await pumpTab(tester);

    expect(find.text('Nessun utente'), findsOneWidget);
  });

  testWidgets('azione in corso: lo spinner al posto del menu, che è spento',
      (tester) async {
    final gate = plugin.accountActionGate = Completer<void>();
    await pumpTab(tester);
    expect(menuEnabled(tester, 'u2'), isTrue);
    expect(spinnerOf('u2'), findsNothing);
    final menuSize = tester.getSize(find.byKey(const Key('user-menu-u2')));

    await startSending(tester, 'u2');

    expect(plugin.calls, contains('recovery:u2:it'));
    expect(menuEnabled(tester, 'u2'), isFalse);
    expect(spinnerOf('u2'), findsOneWidget);
    expect(tester.getSize(spinnerOf('u2')), const Size(16, 16));
    expect(iconOf('u2'), findsNothing, reason: 'lo spinner prende il posto');
    // Lo stesso posto: la riga non cambia altezza.
    expect(tester.getSize(find.byKey(const Key('user-menu-u2'))), menuSize);
    expect(menuEnabled(tester, 'u3'), isTrue, reason: 'le altre righe no');
    expect(spinnerOf('u3'), findsNothing);
    expect(iconOf('u3'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Codice mandato su Discord ed email'), findsOneWidget);
    expect(menuEnabled(tester, 'u2'), isTrue);
    expect(spinnerOf('u2'), findsNothing);
    expect(iconOf('u2'), findsOneWidget, reason: 'il menu torna');
  });

  testWidgets('riga fuori vista durante l\'azione: l\'avviso arriva e il '
      'menu resta spento', (tester) async {
    plugin.accountUsersValue = longList(40);
    final gate = plugin.accountActionGate = Completer<void>();
    await pumpTab(tester, surfaceSize: const Size(1440, 400));
    await startSending(tester, 'u2');

    // Si scorre lontano: la lista smonta le righe fuori vista, ma non
    // quella con l'azione in corso.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await pumpBusy(tester);
    expect(find.byKey(const Key('user-menu-u2')), findsNothing,
        reason: 'la riga è fuori vista');

    // Tornando su la riga è la stessa: il menu è ancora spento, con lo
    // spinner.
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await pumpBusy(tester);
    expect(menuEnabled(tester, 'u2'), isFalse);
    expect(spinnerOf('u2'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await pumpBusy(tester);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Codice mandato su Discord ed email'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, 'u2'), isTrue);
    expect(spinnerOf('u2'), findsNothing);
  });

  testWidgets('nome lungo: occupa tutto lo spazio fino ai contatti',
      (tester) async {
    final name = 'n' * 80;
    plugin.accountUsersValue = [
      AdminAccountUser(id: 'u9', name: name, isAdmin: false, enabled: true),
    ];
    await pumpTab(tester, surfaceSize: const Size(420, 800));

    final nameRight = tester.getTopRight(find.text(name)).dx;
    final contactLeft =
        tester.getTopLeft(find.byTooltip('Discord non collegato')).dx;
    // Resta solo il respiro fra il nome e l'icona: lo spazio non si divide a
    // metà con uno spazio vuoto.
    expect(contactLeft - nameRight, lessThanOrEqualTo(12));
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
