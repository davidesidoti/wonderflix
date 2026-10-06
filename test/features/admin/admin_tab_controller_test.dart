import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/admin/admin_tab_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

/// Risposte delle letture della scheda finta, in ordine: un numero, oppure
/// un errore da lanciare. Finite le risposte, il numero della lettura.
final _answers = <Object>[];
var _reads = 0;

class _TestController extends AdminTabController<int> {
  @override
  Duration get interval => const Duration(seconds: 5);

  @override
  Future<int> fetch() async {
    _reads++;
    final next = _answers.isEmpty ? _reads : _answers.removeAt(0);
    if (next is int) return next;
    throw next;
  }
}

final _testProvider =
    NotifierProvider.autoDispose<_TestController, AdminData<int>>(
        _TestController.new);

void main() {
  late FakeSessionController session;
  late FakeAdminForeground foreground;

  setUp(() {
    _answers.clear();
    _reads = 0;
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    foreground = FakeAdminForeground();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(FakeAdminApi(),
          session: session, foreground: foreground),
      retry: (_, _) => null,
    );
    container.listen(_testProvider, (_, _) {});
    return container;
  }

  test('legge subito e ogni 5 s, con l\'ora dell\'ultima lettura', () {
    fakeAsync((async) {
      final container = makeContainer();
      expect(container.read(_testProvider).value, isNull);

      async.elapse(Duration.zero);
      final first = container.read(_testProvider);
      expect(first.value, 1);
      expect(first.error, isNull);
      expect(first.stale, isFalse);
      expect(first.updatedAt, isNotNull);

      async.elapse(const Duration(seconds: 5));
      expect(container.read(_testProvider).value, 2);
      expect(container.read(_testProvider).updatedAt!.difference(first.updatedAt!),
          const Duration(seconds: 5));
    }, initialTime: DateTime(2026, 10, 6, 12));
  });

  test('errore dopo i dati: restano i dati e l\'ora, con l\'errore', () {
    fakeAsync((async) {
      _answers.addAll([7, const ServerUnreachableException()]);
      final container = makeContainer();
      async.elapse(Duration.zero);
      final updatedAt = container.read(_testProvider).updatedAt;

      async.elapse(const Duration(seconds: 5));
      final data = container.read(_testProvider);
      expect(data.value, 7);
      expect(data.error, isA<ServerUnreachableException>());
      expect(data.stale, isTrue);
      expect(data.updatedAt, updatedAt);

      async.elapse(const Duration(seconds: 5));
      expect(container.read(_testProvider).stale, isFalse,
          reason: 'la lettura dopo è riuscita');
    });
  });

  test('errore senza dati: solo l\'errore', () {
    fakeAsync((async) {
      _answers.add(const ServerUnreachableException());
      final container = makeContainer();
      async.elapse(Duration.zero);

      final data = container.read(_testProvider);
      expect(data.value, isNull);
      expect(data.error, isA<ServerUnreachableException>());
      expect(data.stale, isFalse);
    });
  });

  test('un 403 fa rileggere l\'utente', () {
    fakeAsync((async) {
      _answers.add(const ForbiddenException());
      makeContainer();
      async.elapse(Duration.zero);

      expect(session.refreshUserCalls, 1);
    });
  });

  test('finestra nascosta: si ferma; tornata: legge subito', () {
    fakeAsync((async) {
      makeContainer();
      async.elapse(Duration.zero);
      expect(_reads, 1);

      foreground.set(false);
      async.elapse(const Duration(seconds: 30));
      expect(_reads, 1);

      foreground.set(true);
      async.elapse(Duration.zero);
      expect(_reads, 2);
    });
  });

  test('refresh legge subito; dopo un riavvio si rilegge da soli', () {
    fakeAsync((async) {
      final container = makeContainer();
      async.elapse(Duration.zero);
      expect(_reads, 1);

      unawaited(container.read(_testProvider.notifier).refresh());
      async.elapse(Duration.zero);
      expect(_reads, 2);

      container.read(adminEpochProvider.notifier).bump();
      async.elapse(Duration.zero);
      expect(_reads, 3);
    });
  });
}
