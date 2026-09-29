import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../support/test_data.dart';

void main() {
  const signedIn = SessionSignedIn(testUser);

  test('avvio: tutto porta allo splash', () {
    expect(sessionRedirect(const SessionStarting(), '/home'), '/splash');
    expect(sessionRedirect(const SessionStarting(), '/splash'), isNull);
  });

  test('non autenticato: tutto porta al login', () {
    expect(sessionRedirect(const SessionSignedOut(), '/home'), '/login');
    expect(sessionRedirect(const SessionSignedOut(), '/login'), isNull);
  });

  test('server irraggiungibile: schermata dedicata', () {
    expect(sessionRedirect(const SessionUnreachable(), '/splash'),
        '/unreachable');
    expect(sessionRedirect(const SessionUnreachable(), '/unreachable'), isNull);
  });

  test('autenticato: dalle schermate di ingresso alla Home, altrimenti resta',
      () {
    expect(sessionRedirect(signedIn, '/splash'), '/home');
    expect(sessionRedirect(signedIn, '/login'), '/home');
    expect(sessionRedirect(signedIn, '/unreachable'), '/home');
    expect(sessionRedirect(signedIn, '/home'), isNull);
  });
}
