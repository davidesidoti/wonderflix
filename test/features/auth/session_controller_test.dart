import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/test_data.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late JellyfinHttp http;
  late ProviderContainer container;

  SessionController controller() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  setUp(() {
    auth = MockAuthService();
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    container = ProviderContainer.test(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        jellyfinHttpProvider.overrideWithValue(http),
      ],
      retry: (_, _) => null,
    );
  });

  test('parte in SessionStarting', () {
    expect(state(), isA<SessionStarting>());
  });

  test('restore: sessione valida → SignedIn', () async {
    when(() => auth.restore())
        .thenAnswer((_) async => const RestoredSession(testUser));
    await controller().restore();
    expect(state(), isA<SessionSignedIn>());
  });

  test('restore: nessuna sessione → SignedOut non scaduta', () async {
    when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
    await controller().restore();
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.expired, 'expired', false));
  });

  test('restore: token scaduto → SignedOut scaduta', () async {
    when(() => auth.restore())
        .thenAnswer((_) async => const StoredSessionExpired());
    await controller().restore();
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.expired, 'expired', true));
  });

  test('restore: server giù → Unreachable', () async {
    when(() => auth.restore())
        .thenAnswer((_) async => const RestoreServerUnreachable());
    await controller().restore();
    expect(state(), isA<SessionUnreachable>());
  });

  test('restore: errore inatteso (non ApiException) → Unreachable', () async {
    when(() => auth.restore()).thenThrow(StateError('boom'));
    await controller().restore();
    expect(state(), isA<SessionUnreachable>());
  });

  test('login riuscito → SignedIn; errore propagato e stato invariato',
      () async {
    when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
    await controller().restore();

    when(() => auth.loginWithPassword('mario', 'bad'))
        .thenThrow(const UnauthorizedException());
    await expectLater(controller().loginWithPassword('mario', 'bad'),
        throwsA(isA<UnauthorizedException>()));
    expect(state(), isA<SessionSignedOut>());

    when(() => auth.loginWithPassword('mario', 'ok'))
        .thenAnswer((_) async => testUser);
    await controller().loginWithPassword('mario', 'ok');
    expect(state(), isA<SessionSignedIn>());
  });

  test('quickConnectApproved → SignedIn', () {
    controller().quickConnectApproved(testUser);
    expect(state(), isA<SessionSignedIn>());
  });

  test('logout → SignedOut', () async {
    when(() => auth.logout()).thenAnswer((_) async {});
    controller().quickConnectApproved(testUser);
    await controller().logout();
    expect(state(), isA<SessionSignedOut>());
    verify(() => auth.logout()).called(1);
  });

  test('un 401 durante la sessione riporta al login come sessione scaduta',
      () async {
    when(() => auth.clearLocalSession()).thenAnswer((_) async {});
    controller().quickConnectApproved(testUser);

    http.onUnauthorized!.call();

    expect(state(),
        isA<SessionSignedOut>().having((s) => s.expired, 'expired', true));
    verify(() => auth.clearLocalSession()).called(1);
  });
}
