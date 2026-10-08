import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/profiles_screen.dart';

import '../support/fake_session_controller.dart';
import '../support/profile_fakes.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets(
      '"Chi guarda?" e accesso: ogni apertura del login prepara l\'accesso',
      (tester) async {
    final session = FakeSessionController(const SessionChoosingProfile());
    final book = const ProfileBook()
        .upsert(testProfile(userId: 'u1', name: 'Mario'))
        .upsert(testProfile(userId: 'u2', name: 'Luigi', expired: true));
    late GoRouter router;
    await pumpAppRouterOf(tester, (ref) => router = ref.watch(routerProvider),
        overrides: [
          sessionControllerProvider.overrideWith(() => session),
          profilesProvider
              .overrideWith(() => FixedProfiles(ProfilesState(book: book))),
          quickConnectEnabledProvider.overrideWith((ref) async => false),
        ]);
    await tester.pumpAndSettle();
    String location() => router.routerDelegate.currentConfiguration.uri.path;

    expect(location(), '/profiles');
    expect(find.byType(ProfilesScreen), findsOneWidget);
    expect(session.prepareLoginCalls, 0);

    // Aggiungi profilo: il login.
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.pumpAndSettle();
    expect(location(), '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(session.prepareLoginCalls, 1);

    // "Annulla": di nuovo "Chi guarda?".
    await tester.tap(find.byKey(const Key('login-cancel')));
    await tester.pumpAndSettle();
    expect(location(), '/profiles');
    expect(session.cancelLoginCalls, 1);

    // Di nuovo: la pagina del login è nuova, e l'accesso si riprepara.
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.pumpAndSettle();
    expect(location(), '/login');
    expect(session.prepareLoginCalls, 2);
    await tester.tap(find.byKey(const Key('login-cancel')));
    await tester.pumpAndSettle();

    // Il profilo scaduto: il login con il suo nome.
    await tester.tap(find.text('Luigi'));
    await tester.pumpAndSettle();
    expect(location(), '/login');
    expect(session.prepareLoginCalls, 3);
    expect(find.text('Sessione scaduta, accedi di nuovo.'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-username')))
            .controller!
            .text,
        'Luigi');
  });
}
