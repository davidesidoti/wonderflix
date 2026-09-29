import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/library/user_data.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';

class _Socket implements EventSocket {
  final controller = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String message) {}

  @override
  Future<void> close() => controller.close();
}

void main() {
  test('UserDataChanged e LibraryChanged aggiornano lo stato', () async {
    final socket = _Socket();
    final container = ProviderContainer.test(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        serverEventsClientProvider.overrideWith((ref) => ServerEventsClient(
              serverUrl: Uri.parse('https://media.example.com'),
              authorizationHeader: () => 'x',
              connector: (uri, headers) async => socket,
            )),
      ],
      retry: (_, _) => null,
    );

    container.read(serverEventsBindingProvider);
    await Future<void>.delayed(Duration.zero);

    socket.controller.add('{"MessageType":"UserDataChanged","Data":{"UserId":"u1",'
        '"UserDataList":[{"ItemId":"m1","Played":true}]}}');
    socket.controller.add('{"MessageType":"LibraryChanged","Data":{}}');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(userDataOverridesProvider)['m1']?.played, isTrue);
    expect(container.read(libraryRevisionProvider), 1);
  });

  test('eventi di un altro utente vengono ignorati', () async {
    final socket = _Socket();
    final container = ProviderContainer.test(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        serverEventsClientProvider.overrideWith((ref) => ServerEventsClient(
              serverUrl: Uri.parse('https://media.example.com'),
              authorizationHeader: () => 'x',
              connector: (uri, headers) async => socket,
            )),
      ],
      retry: (_, _) => null,
    );
    container.read(serverEventsBindingProvider);
    await Future<void>.delayed(Duration.zero);

    socket.controller.add('{"MessageType":"UserDataChanged","Data":{"UserId":"altro",'
        '"UserDataList":[{"ItemId":"m1","Played":true}]}}');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(userDataOverridesProvider), isEmpty);
  });
}
