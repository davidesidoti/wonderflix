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
}
