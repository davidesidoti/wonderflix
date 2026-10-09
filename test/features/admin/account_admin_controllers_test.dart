import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_admin_controllers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';

void main() {
  late FakePluginAdminApi plugin;
  late FakeSessionController session;
  late FakeAdapter adapter;

  setUp(() {
    plugin = FakePluginAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    adapter = FakeAdapter((_) => const FakeResponse(204));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: [
        ...adminTestOverrides(FakeAdminApi(),
            plugin: plugin,
            session: session,
            features: const SocialFeatures(inbox: true, account: true)),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
      retry: (_, _) => null,
    );
    container.listen(accountUsersControllerProvider, (_, _) {});
    container.listen(accountAdminControllerProvider, (_, _) {});
    return container;
  }

  test('legge gli utenti e lo stato del recupero', () async {
    final container = makeContainer();
    await pumpEventQueue();

    expect(
        container
            .read(accountUsersControllerProvider)
            .value!
            .map((u) => u.name),
        ['garg', 'lucia', 'Mario', 'vecchio']);
    expect(container.read(accountAdminControllerProvider).value!.withContacts,
        5);
  });

  test('azioni: chiamano il plugin e rileggono', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final users = container.read(accountUsersControllerProvider.notifier);

    expect(await users.sendRecoveryCode('u2', language: 'it'),
        [AccountChannel.discord, AccountChannel.email]);
    await users.unlinkContacts('u2');
    final result = await container
        .read(accountAdminControllerProvider.notifier)
        .test(language: 'it');

    expect(result.of(AccountChannel.discord), 'Ok');
    expect(plugin.calls,
        containsAllInOrder(['recovery:u2:it', 'unlink:u2', 'accountTest:it']));
    expect(plugin.count('accountUsers'), greaterThanOrEqualTo(3));
    expect(plugin.count('accountStatus'), greaterThanOrEqualTo(2));
  });

  test('scollegare i contatti: la rilettura mostra la riga senza contatti',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    AdminAccountUser garg() => container
        .read(accountUsersControllerProvider)
        .value!
        .singleWhere((u) => u.name == 'garg');
    expect(garg().hasContacts, isTrue);

    await container
        .read(accountUsersControllerProvider.notifier)
        .unlinkContacts('u2');

    expect(garg().hasContacts, isFalse);
    expect(garg().discordName, isNull);
    expect(garg().maskedEmail, isNull);
    // Gli altri utenti non cambiano.
    expect(
        container
            .read(accountUsersControllerProvider)
            .value!
            .singleWhere((u) => u.name == 'Mario')
            .discordName,
        'mario_d');
  });

  test('un 403 del plugin arriva a chi chiama e fa rileggere l\'utente',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    plugin.actionError = const ForbiddenException();

    await expectLater(
        container
            .read(accountUsersControllerProvider.notifier)
            .sendRecoveryCode('u2', language: 'it'),
        throwsA(isA<ForbiddenException>()));

    expect(session.refreshUserCalls, 1);
  });

  test('Imposta password: Jellyfin, senza la password attuale', () async {
    final container = makeContainer();
    await pumpEventQueue();

    await container
        .read(accountUsersControllerProvider.notifier)
        .setPassword('u3', 'nuova123');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u3'});
    expect(request.data, {'NewPw': 'nuova123'});
  });

  test('un 403 fa rileggere l\'utente', () async {
    final container = makeContainer();
    await pumpEventQueue();
    adapter.handler = (_) => const FakeResponse(403);

    await expectLater(
        container
            .read(accountUsersControllerProvider.notifier)
            .setPassword('u3', 'nuova123'),
        throwsA(isA<ForbiddenException>()));

    expect(session.refreshUserCalls, 1);
  });
}
