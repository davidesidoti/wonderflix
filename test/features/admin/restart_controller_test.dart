import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/admin/restart_controller.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';

void main() {
  late FakeAdminApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: adminTestOverrides(api, session: session),
      retry: (_, _) => null,
    );
    container.listen(restartControllerProvider, (_, _) {});
    return container;
  }

  RestartController controller(ProviderContainer container) =>
      container.read(restartControllerProvider.notifier);

  test('giù e poi su: tornato, e le schede rileggono', () {
    fakeAsync((async) {
      api.upAnswers.addAll([true, false, false, true]);
      final container = makeContainer();
      var epoch = 0;
      container.listen<int>(adminEpochProvider, (_, next) => epoch = next);
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(api.calls, ['restart']);
      expect(container.read(restartControllerProvider), RestartPhase.waiting);

      // 3 s: ancora su (non è caduto); 6 e 9 s: giù.
      async.elapse(const Duration(seconds: 9));
      expect(outcome, isNull);
      // 12 s: di nuovo su dopo essere caduto.
      async.elapse(const Duration(seconds: 3));
      expect(outcome, RestartOutcome.back);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(epoch, 1);
      expect(api.count('up'), 4);
    });
  });

  test('mai caduto in 60 s: tornato', () {
    fakeAsync((async) {
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.elapse(const Duration(seconds: 57));
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 3));
      expect(outcome, RestartOutcome.back);
    });
  });

  test('giù per 3 minuti: non risponde ancora; Ricontrolla aspetta di nuovo',
      () {
    fakeAsync((async) {
      api.upAnswers.addAll(List.filled(60, false));
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.elapse(const Duration(seconds: 177));
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 3));
      expect(outcome, RestartOutcome.timedOut);
      expect(container.read(restartControllerProvider), RestartPhase.timedOut);

      RestartOutcome? again;
      unawaited(controller(container).recheck().then((o) => again = o));
      expect(container.read(restartControllerProvider), RestartPhase.waiting);
      async.elapse(const Duration(seconds: 3));
      expect(again, RestartOutcome.back,
          reason: 'era già giù: la prima risposta basta');
    });
  });

  test('errore di rete sul POST: il riavvio è partito', () {
    fakeAsync((async) {
      api.restartError = const ServerUnreachableException();
      final container = makeContainer();

      unawaited(controller(container).restart());
      async.flushMicrotasks();
      expect(container.read(restartControllerProvider), RestartPhase.waiting);
      async.elapse(const Duration(seconds: 60));
    });
  });

  test('403 sul POST: non riuscito, e si rilegge l\'utente', () {
    fakeAsync((async) {
      api.restartError = const ForbiddenException();
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.failed);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(session.refreshUserCalls, 1);
      expect(api.count('up'), 0);
    });
  });

  test('altro errore sul POST: non riuscito', () {
    fakeAsync((async) {
      api.restartError = const ServerErrorException(500);
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.failed);
      expect(session.refreshUserCalls, 0);
    });
  });

  test('errore qualunque sul POST: non riuscito, e non resta in invio', () {
    fakeAsync((async) {
      api.restartError = StateError('inatteso');
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.failed);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(api.count('up'), 0);
    });
  });

  test('401 sul POST: annullato senza avviso (l\'app esce da sola)', () {
    fakeAsync((async) {
      api.restartError = const UnauthorizedException();
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).restart().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.cancelled);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(session.refreshUserCalls, 0);
      expect(api.count('up'), 0);
    });
  });

  test('un secondo riavvio durante l\'attesa: annullato, un solo POST', () {
    fakeAsync((async) {
      final container = makeContainer();
      RestartOutcome? first;
      RestartOutcome? second;

      unawaited(controller(container).restart().then((o) => first = o));
      async.flushMicrotasks();
      expect(container.read(restartControllerProvider), RestartPhase.waiting);

      unawaited(controller(container).restart().then((o) => second = o));
      async.flushMicrotasks();
      expect(second, RestartOutcome.cancelled);
      expect(api.count('restart'), 1);
      expect(container.read(restartControllerProvider), RestartPhase.waiting,
          reason: 'la prima attesa continua');

      async.elapse(const Duration(seconds: 60));
      expect(first, RestartOutcome.back);
    });
  });

  test('Ricontrolla senza il tempo scaduto: annullato, nessuna domanda', () {
    fakeAsync((async) {
      final container = makeContainer();
      RestartOutcome? outcome;

      unawaited(controller(container).recheck().then((o) => outcome = o));
      async.flushMicrotasks();
      expect(outcome, RestartOutcome.cancelled);
      expect(container.read(restartControllerProvider), RestartPhase.idle);
      expect(api.count('up'), 0);
    });
  });

  test('502/503/504 di nginx sul POST: il riavvio è partito', () {
    for (final status in [502, 503, 504]) {
      fakeAsync((async) {
        api.restartError = ServerErrorException(status);
        final container = makeContainer();

        unawaited(controller(container).restart());
        async.flushMicrotasks();
        expect(container.read(restartControllerProvider), RestartPhase.waiting,
            reason: '$status');
        async.elapse(const Duration(seconds: 60));
      });
    }
  });

  test('pagina chiusa durante l\'attesa: l\'attesa si ferma', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: adminTestOverrides(api, session: session),
        retry: (_, _) => null,
      );
      container.listen(restartControllerProvider, (_, _) {});
      RestartOutcome? outcome;

      unawaited(container
          .read(restartControllerProvider.notifier)
          .restart()
          .then((o) => outcome = o));
      async.elapse(const Duration(seconds: 3));
      container.dispose();
      async.elapse(const Duration(seconds: 60));

      expect(outcome, RestartOutcome.cancelled);
      expect(api.count('up'), 1);
    });
  });
}
