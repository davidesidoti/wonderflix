import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';

void main() {
  SyncPlayAccess accessFor(SessionState session) {
    final container = ProviderContainer.test(overrides: [
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(session)),
    ]);
    return container.read(syncPlayAccessProvider);
  }

  test('dell\'utente collegato; nessuno senza sessione', () {
    expect(
        accessFor(const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.joinOnly))),
        SyncPlayAccess.joinOnly);
    expect(accessFor(const SessionSignedIn(JellyfinUser(id: 'u1', name: 'Mario'))),
        SyncPlayAccess.createAndJoin);
    expect(accessFor(const SessionSignedOut()), SyncPlayAccess.none);
  });
}
