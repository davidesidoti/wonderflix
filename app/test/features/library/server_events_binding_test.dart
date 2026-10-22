import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

const _userDataMessage = '{"MessageType":"UserDataChanged","Data":{"UserId":"u1",'
    '"UserDataList":[{"ItemId":"m1","Played":true}]}}';
const _libraryMessage = '{"MessageType":"LibraryChanged","Data":{}}';

ProviderContainer _container(List<_Socket> sockets) => ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        serverEventsClientProvider.overrideWith((ref) => ServerEventsClient(
              serverUrl: Uri.parse('https://media.example.com'),
              authorizationHeader: () => 'x',
              connector: (uri, headers) async {
                final socket = _Socket();
                sockets.add(socket);
                return socket;
              },
            )),
      ],
      retry: (_, _) => null,
    );

void main() {
  test('UserDataChanged applica i dati subito e ricarica le righe dopo 2 s', () {
    fakeAsync((async) {
      final sockets = <_Socket>[];
      final container = _container(sockets);
      container.read(serverEventsBindingProvider);
      async.flushMicrotasks();

      var overrideUpdates = 0;
      container.listen(userDataOverridesProvider, (_, _) => overrideUpdates++);

      sockets.single.controller.add(_userDataMessage);
      async.flushMicrotasks();
      expect(container.read(userDataOverridesProvider)['m1']?.played, isTrue);
      expect(overrideUpdates, 1, reason: 'un solo aggiornamento dello stato');
      expect(container.read(userDataRevisionProvider), 0);

      async.elapse(const Duration(seconds: 1));
      expect(container.read(userDataRevisionProvider), 0);
      async.elapse(const Duration(seconds: 1));
      expect(container.read(userDataRevisionProvider), 1);

      container.dispose();
    });
  });

  test('LibraryChanged: una sola modifica dopo 5 s anche con più eventi', () {
    fakeAsync((async) {
      final sockets = <_Socket>[];
      final container = _container(sockets);
      container.read(serverEventsBindingProvider);
      async.flushMicrotasks();

      sockets.single.controller.add(_libraryMessage);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      sockets.single.controller.add(_libraryMessage);
      sockets.single.controller.add(_libraryMessage);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(container.read(libraryRevisionProvider), 0,
          reason: 'il timer riparte a ogni evento');
      async.elapse(const Duration(seconds: 2));
      expect(container.read(libraryRevisionProvider), 1);
      async.elapse(const Duration(seconds: 30));
      expect(container.read(libraryRevisionProvider), 1);

      container.dispose();
    });
  });

  test('riconnessione: azzera i dati locali e ricarica la libreria', () {
    fakeAsync((async) {
      final sockets = <_Socket>[];
      final container = _container(sockets);
      container.read(serverEventsBindingProvider);
      async.flushMicrotasks();

      sockets.single.controller.add(_userDataMessage);
      async.flushMicrotasks();
      expect(container.read(userDataOverridesProvider), isNotEmpty);
      expect(container.read(libraryRevisionProvider), 0,
          reason: 'la prima connessione non ricarica nulla');

      // Il server chiude: dopo 2 s si riconnette.
      unawaited(sockets.single.controller.close());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(sockets, hasLength(2));

      expect(container.read(userDataOverridesProvider), isEmpty);
      expect(container.read(libraryRevisionProvider), 1,
          reason: 'subito, senza debounce');

      container.dispose();
    });
  });

  test('eventi di un altro utente vengono ignorati', () {
    fakeAsync((async) {
      final sockets = <_Socket>[];
      final container = _container(sockets);
      container.read(serverEventsBindingProvider);
      async.flushMicrotasks();

      sockets.single.controller.add(
          '{"MessageType":"UserDataChanged","Data":{"UserId":"altro",'
          '"UserDataList":[{"ItemId":"m1","Played":true}]}}');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));

      expect(container.read(userDataOverridesProvider), isEmpty);
      expect(container.read(userDataRevisionProvider), 0);

      container.dispose();
    });
  });
}
