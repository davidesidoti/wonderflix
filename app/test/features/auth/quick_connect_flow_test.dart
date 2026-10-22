import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';

import '../../support/test_data.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthApi api;
  late MockAuthService auth;
  late QuickConnectFlow flow;

  QuickConnectState qc(String code, String secret, {bool ok = false}) =>
      QuickConnectState(code: code, secret: secret, authenticated: ok);

  setUp(() {
    api = MockAuthApi();
    auth = MockAuthService();
    flow = QuickConnectFlow(api: api, auth: auth);
  });

  test('Quick Connect disattivato sul server', () {
    fakeAsync((async) {
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => false);
      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect(states.map((s) => s.runtimeType), [QcLoading, QcDisabled]);
    });
  });

  test('mostra il codice, attende e completa il login', () {
    fakeAsync((async) {
      var polls = 0;
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect())
          .thenAnswer((_) async => qc('482913', 's1'));
      when(() => api.quickConnectState('s1'))
          .thenAnswer((_) async => qc('482913', 's1', ok: ++polls >= 2));
      when(() => auth.completeQuickConnect('s1'))
          .thenAnswer((_) async => testUser);

      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect(states.last,
          isA<QcWaiting>().having((s) => s.code, 'code', '482913'));

      async.elapse(const Duration(seconds: 3));
      expect(states.last, isA<QcWaiting>(), reason: 'primo controllo: non ancora');

      async.elapse(const Duration(seconds: 3));
      expect(states.last,
          isA<QcApproved>().having((s) => s.user.id, 'user', 'u1'));
      verify(() => auth.completeQuickConnect('s1')).called(1);
    });
  });

  test('segreto scaduto: genera un nuovo codice', () {
    fakeAsync((async) {
      var initiations = 0;
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect()).thenAnswer((_) async {
        initiations++;
        return initiations == 1 ? qc('111111', 's1') : qc('222222', 's2');
      });
      when(() => api.quickConnectState('s1'))
          .thenThrow(const NotFoundException());
      when(() => api.quickConnectState('s2'))
          .thenAnswer((_) async => qc('222222', 's2'));

      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect((states.last as QcWaiting).code, '111111');

      async.elapse(const Duration(seconds: 3));
      expect((states.last as QcWaiting).code, '222222');
    });
  });

  test('server irraggiungibile: stato di errore', () {
    fakeAsync((async) {
      when(() => api.quickConnectEnabled())
          .thenThrow(const ServerUnreachableException());
      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect(states.last, isA<QcError>());
    });
  });

  test('Quick Connect disattivato durante l\'avvio (401 su initiate)', () {
    fakeAsync((async) {
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect())
          .thenThrow(const UnauthorizedException());

      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();

      expect(states.map((s) => s.runtimeType), [QcLoading, QcDisabled]);
    });
  });

  test('la cancellazione dell\'iscrizione non completa il login in silenzio', () {
    fakeAsync((async) {
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect())
          .thenAnswer((_) async => qc('482913', 's1'));
      when(() => api.quickConnectState('s1'))
          .thenAnswer((_) async => qc('482913', 's1', ok: true));
      when(() => auth.completeQuickConnect('s1'))
          .thenAnswer((_) async => testUser);

      final states = <QcState>[];
      final subscription = flow.run().listen(states.add);
      async.flushMicrotasks();

      subscription.cancel();
      async.elapse(const Duration(seconds: 3));

      verifyNever(() => auth.completeQuickConnect(any()));
    });
  });

  group('"Annulla" (iscrizione cancellata) ferma tutto', () {
    late int polls;

    setUp(() {
      polls = 0;
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect())
          .thenAnswer((_) async => qc('482913', 's1'));
      when(() => auth.completeQuickConnect('s1'))
          .thenAnswer((_) async => testUser);
    });

    test('durante l\'attesa: nessun altro controllo, nessun codice nuovo', () {
      fakeAsync((async) {
        when(() => api.quickConnectState('s1')).thenAnswer((_) async {
          polls++;
          return qc('482913', 's1');
        });
        final subscription = flow.run().listen((_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(polls, 1);

        subscription.cancel();
        async.elapse(const Duration(minutes: 15));

        expect(polls, 1);
        verify(() => api.initiateQuickConnect()).called(1);
        verifyNever(() => auth.completeQuickConnect(any()));
      });
    });

    test('mentre il codice scade: nessun nuovo Initiate', () {
      fakeAsync((async) {
        final answer = Completer<QuickConnectState>();
        when(() => api.quickConnectState('s1')).thenAnswer((_) {
          polls++;
          return answer.future;
        });
        final subscription = flow.run().listen((_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(polls, 1);

        subscription.cancel();
        answer.completeError(const NotFoundException());
        async.elapse(const Duration(minutes: 1));

        verify(() => api.initiateQuickConnect()).called(1);
        expect(polls, 1);
      });
    });

    test('durante un controllo che risulta approvato: l\'accesso non parte',
        () {
      fakeAsync((async) {
        final answer = Completer<QuickConnectState>();
        when(() => api.quickConnectState('s1')).thenAnswer((_) {
          polls++;
          return answer.future;
        });
        final subscription = flow.run().listen((_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        subscription.cancel();
        answer.complete(qc('482913', 's1', ok: true));
        async.elapse(const Duration(seconds: 10));

        verifyNever(() => auth.completeQuickConnect(any()));
        expect(polls, 1);
      });
    });
  });

  test('errore imprevisto (non ApiException): stato di errore', () {
    fakeAsync((async) {
      var polls = 0;
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect())
          .thenAnswer((_) async => qc('482913', 's1'));
      when(() => api.quickConnectState('s1'))
          .thenAnswer((_) async => qc('482913', 's1', ok: ++polls >= 1));
      when(() => auth.completeQuickConnect('s1')).thenThrow(StateError('boom'));

      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 3));
      expect(states.last, isA<QcError>());
    });
  });
}
