import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/features/admin/maintenance_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi()
      ..librariesValue = testLibraries()
      ..tasksValue = testTasks();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(maintenanceControllerProvider, (_, _) {});
    return container;
  }

  test('attività per categoria e per nome; la scansione della libreria a parte',
      () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);

      final snapshot = container.read(maintenanceControllerProvider).value!;
      expect(snapshot.libraries, hasLength(4));
      expect(snapshot.groups.map((g) => g.category), [
        'Applicazione',
        'Auto Collections',
        'Intro Skipper',
        'Libreria',
        'Manutenzione',
        'Trakt',
      ]);
      expect(snapshot.groups[3].tasks.map((t) => t.name), [
        'Estrattore di Keyframe',
        'Scansione della libreria',
        'Webhook Item Added Notifier',
      ]);
      expect(snapshot.scanTask!.id, 't-scan');
      expect(snapshot.busy, isTrue);
    });
  });

  test('qualcosa in corso: ogni 2 s; tutto fermo: ogni 15 s', () {
    fakeAsync((async) {
      makeContainer();
      async.elapse(Duration.zero);
      expect(api.count('tasks'), 1);
      async.elapse(const Duration(seconds: 2));
      expect(api.count('tasks'), 2);

      // Finisce tutto: la lettura dopo lo vede e rallenta.
      api
        ..librariesValue = [
          for (final library in testLibraries())
            LibraryFolder(
                itemId: library.itemId, name: library.name, kind: library.kind),
        ]
        ..tasksValue = [
          for (final task in testTasks())
            if (task.state == TaskState.idle) task,
        ];
      async.elapse(const Duration(seconds: 2));
      expect(api.count('tasks'), 3);
      async.elapse(const Duration(seconds: 14));
      expect(api.count('tasks'), 3);
      async.elapse(const Duration(seconds: 1));
      expect(api.count('tasks'), 4);
    });
  });

  test('azioni: chiamano Jellyfin e la scheda si rilegge subito', () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);
      final controller = container.read(maintenanceControllerProvider.notifier);

      unawaited(controller.scanAll());
      unawaited(controller.scanLibrary('a656b907eb3a73532e40e44b968d0225'));
      unawaited(controller.startTask('t-optimize'));
      unawaited(controller.stopTask('t-autocol'));
      async.elapse(Duration.zero);

      expect(
          api.calls,
          containsAllInOrder([
            'start:t-scan',
            'scan:a656b907eb3a73532e40e44b968d0225',
            'start:t-optimize',
            'stop:t-autocol',
          ]));
      expect(api.count('tasks'), greaterThanOrEqualTo(2));
    });
  });

  test('"Scansiona tutte" avvia l\'attività della scansione, non /Library/Refresh',
      () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);

      unawaited(container.read(maintenanceControllerProvider.notifier).scanAll());
      async.elapse(Duration.zero);

      expect(api.calls.where((c) => c.startsWith('start:')), ['start:t-scan']);
      expect(api.calls, isNot(contains('scanAll')));
    });
  });

  test('senza l\'attività della scansione: scanAll non parte e dà un errore',
      () {
    fakeAsync((async) {
      api.tasksValue = [
        for (final task in testTasks())
          if (task.key != ScheduledTask.refreshLibraryKey) task,
      ];
      final container = makeContainer();
      async.elapse(Duration.zero);

      Object? caught;
      unawaited(container
          .read(maintenanceControllerProvider.notifier)
          .scanAll()
          .catchError((Object error) {
        caught = error;
      }));
      async.elapse(Duration.zero);

      expect(caught, isA<StateError>());
      expect(api.calls.where((c) => c.startsWith('start:')), isEmpty);
    });
  });

  test('azione rifiutata (403): rilegge l\'utente e l\'errore arriva', () {
    fakeAsync((async) {
      api.actionError = const ForbiddenException();
      final container = makeContainer();
      async.elapse(Duration.zero);

      Object? caught;
      unawaited(container
          .read(maintenanceControllerProvider.notifier)
          .startTask('t-optimize')
          .catchError((Object error) {
        caught = error;
      }));
      async.elapse(Duration.zero);

      expect(caught, isA<ForbiddenException>());
      expect(session.refreshUserCalls, 1);
    });
  });

  test('un errore di una delle due letture è un errore della scheda', () {
    fakeAsync((async) {
      api.tasksError = const ServerUnreachableException();
      final container = makeContainer();
      async.elapse(Duration.zero);

      final data = container.read(maintenanceControllerProvider);
      expect(data.value, isNull);
      expect(data.error, isA<ServerUnreachableException>());
    });
  });
}
