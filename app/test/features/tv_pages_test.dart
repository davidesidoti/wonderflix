import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';
import 'package:wonderflix/features/auth/quick_connect_panel.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/request_row.dart';
import 'package:wonderflix/features/requests/requestables_section.dart';
import 'package:wonderflix/features/search/search_screen.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';
import 'package:wonderflix/features/update/update_controller.dart';
import 'package:wonderflix/features/update/update_gate.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/tv_focusable.dart';

import '../support/fake_session_controller.dart';
import '../support/home_fakes.dart';
import '../support/library_fakes.dart';
import '../support/profile_fakes.dart';
import '../support/pump_app.dart';
import '../support/requests_fakes.dart';
import '../support/settings_fakes.dart';
import '../support/test_data.dart';
import '../support/update_fakes.dart';

/// 1080p a densità 2: lo schermo che vede l'app sulla TV.
const _tvSize = Size(960, 540);

/// Quick Connect che non arriva mai al codice.
class _IdleRunner implements QuickConnectRunner {
  const _IdleRunner();

  @override
  Stream<QcState> run() => const Stream.empty();
}

void main() {
  group('Cerca', () {
    final library = FakeLibraryApi()
      ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
          ? pageOf([testItem(id: 'ee39bef06f503dd0e9dbd20593df417f', name: 'Dune')])
          : pageOf([]))
      ..people = [];
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [testRequestable(title: 'Dune - Parte due')];

    Future<void> pumpSearch(WidgetTester tester) => pumpApp(
          tester,
          const Scaffold(body: SearchScreen()),
          tv: true,
          surfaceSize: _tvSize,
          overrides: [
            libraryApiProvider.overrideWithValue(library),
            sessionControllerProvider.overrideWith(
                () => FakeSessionController(const SessionSignedIn(testUser))),
            ...requestsTestOverrides(requests),
          ],
        );

    bool fieldFocused(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode
        .hasFocus;

    testWidgets("il campo non ha il focus all'apertura; Giù lo raggiunge e OK "
        'lo attiva', (tester) async {
      await pumpSearch(tester);
      expect(fieldFocused(tester), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(fieldFocused(tester), isFalse, reason: 'raggiunto, non attivo');
      expect(
          find.ancestor(
              of: find.byType(TextField), matching: find.byType(TvFocusable)),
          findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(fieldFocused(tester), isTrue);
    });

    testWidgets('risultati e "Da richiedere" sono focalizzabili',
        (tester) async {
      await pumpSearch(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'dune');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(
          find.descendant(
              of: find.byType(PosterCard), matching: find.byType(TvFocusable)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(RequestablesSection),
              matching: find.byType(TvFocusable)),
          findsOneWidget);
    });
  });

  testWidgets('Richieste: la riga è focalizzabile e OK la apre', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: RequestRow(
          request: testMediaRequest(),
          now: DateTime.utc(2026, 10, 5, 12),
          onTap: () => taps++,
        ),
      ),
      tv: true,
      surfaceSize: _tvSize,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(taps, 1);
    // Una sola tappa: TvFocusable, non anche l'InkWell.
    expect(
        find.descendant(
            of: find.byType(RequestRow), matching: find.byType(TvFocusable)),
        findsOneWidget);
  });

  group('Login', () {
    Future<void> pumpLogin(WidgetTester tester, {required bool tv}) =>
        pumpApp(tester, const LoginScreen(),
            tv: tv,
            surfaceSize: _tvSize,
            overrides: [
              sessionControllerProvider.overrideWith(
                  () => FakeSessionController(const SessionSignedOut())),
              quickConnectEnabledProvider.overrideWith((ref) async => true),
              quickConnectRunnerProvider
                  .overrideWithValue(const _IdleRunner()),
              profilesProvider.overrideWith(() =>
                  FixedProfiles(const ProfilesState(book: ProfileBook()))),
            ]);

    testWidgets('TV: parte da Quick Connect, il nome utente non ha il focus',
        (tester) async {
      await pumpLogin(tester, tv: true);
      await tester.pump();

      expect(DefaultTabController.of(tester.element(find.byType(TabBar))).index,
          1);
      expect(find.byType(QuickConnectPanel), findsOneWidget);
      // Nello stretto la scheda Password è sotto, fuori scena.
      final username = tester.widget<TextField>(
          find.byKey(const Key('login-username'), skipOffstage: false));
      expect(username.autofocus, isFalse);
    });

    testWidgets('fuori dalla TV: parte dalla password', (tester) async {
      await pumpLogin(tester, tv: false);
      await tester.pump();

      expect(DefaultTabController.of(tester.element(find.byType(TabBar))).index,
          0);
    });
  });

  testWidgets('Impostazioni: sulla TV solo lingua, player e lingue di '
      'riproduzione', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        tv: true,
        surfaceSize: const Size(960, 2400),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountAvailableProvider.overrideWithValue(false),
          clientInfoProvider.overrideWithValue(testClientInfo),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
          ...homeSettingsOverrides(),
        ]);
    await tester.pump();

    for (final title in ['Lingua', 'Player', 'Lingue di riproduzione']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    for (final title in [
      'Account',
      'Notifiche',
      'Aspetto',
      'Home',
      'Discord',
      'Supporto',
    ]) {
      expect(find.text(title), findsNothing, reason: title);
    }
  });

  testWidgets('il banner di aggiornamento non compare sulla TV', (tester) async {
    await pumpApp(tester, const UpdateGate(child: Text('app')),
        tv: true,
        overrides: [
          updateControllerProvider.overrideWith(() => FakeUpdateController(
              UpdateState(
                  release: testRelease(), installer: File('setup.exe')))),
        ]);
    expect(find.text('app'), findsOneWidget);
    expect(find.text('Riavvia ora'), findsNothing);
  });

  test('sulla TV le pagine escluse portano a /home', () {
    for (final path in [
      '/calendar',
      '/admin',
      '/friends',
      '/inbox',
      '/match/x',
    ]) {
      expect(tvRedirect(path, tv: true), '/home', reason: path);
      expect(tvRedirect(path, tv: false), isNull, reason: path);
    }
    for (final path in ['/home', '/search', '/settings', '/item/x', '/play/x']) {
      expect(tvRedirect(path, tv: true), isNull, reason: path);
    }
  });
}
