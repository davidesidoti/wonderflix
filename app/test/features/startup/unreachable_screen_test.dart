import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/startup/unreachable_screen.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

/// Un profilo che non si è aperto, e un nuovo tentativo che aspetta.
class _SlowRetry extends FakeSessionController {
  _SlowRetry() : super(const SessionUnreachable(retryUserId: 'u2'));

  final opening = Completer<void>();

  @override
  Future<void> openProfile(String userId) async {
    await super.openProfile(userId);
    await opening.future;
  }
}

void main() {
  final switchButton = find.widgetWithText(WfButton, 'Cambia profilo');

  testWidgets('riprova da solo ogni 15 s e con il pulsante', (tester) async {
    final fake = FakeSessionController(const SessionUnreachable());
    await pumpApp(tester, const UnreachableScreen(),
        overrides: [sessionControllerProvider.overrideWith(() => fake)]);

    expect(find.text('WonderFlix non è raggiungibile'), findsOneWidget);
    expect(fake.restoreCalls, 0);
    // Senza un profilo scelto non c'è da tornare a "Chi guarda?".
    expect(switchButton, findsNothing);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(); // ricostruisce dopo la fine del tentativo
    expect(fake.restoreCalls, 1);

    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(fake.restoreCalls, 2);
    expect(fake.openedProfiles, isEmpty);
  });

  testWidgets('un profilo scelto che non si è aperto: si riprova quello',
      (tester) async {
    final fake =
        FakeSessionController(const SessionUnreachable(retryUserId: 'u2'));
    await pumpApp(tester, const UnreachableScreen(),
        overrides: [sessionControllerProvider.overrideWith(() => fake)]);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(fake.openedProfiles, ['u2']);

    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(fake.openedProfiles, ['u2', 'u2']);
    expect(fake.restoreCalls, 0);
  });

  testWidgets('"Cambia profilo" torna a "Chi guarda?"', (tester) async {
    final fake =
        FakeSessionController(const SessionUnreachable(retryUserId: 'u2'));
    await pumpApp(tester, const UnreachableScreen(),
        overrides: [sessionControllerProvider.overrideWith(() => fake)]);

    expect(switchButton, findsOneWidget);
    await tester.tap(switchButton);
    await tester.pump();

    expect(fake.backToProfilesCalls, 1);
    expect(fake.openedProfiles, isEmpty);
  });

  testWidgets('"Cambia profilo" spento mentre si riprova', (tester) async {
    final fake = _SlowRetry();
    await pumpApp(tester, const UnreachableScreen(),
        overrides: [sessionControllerProvider.overrideWith(() => fake)]);

    await tester.tap(find.text('Riprova'));
    // Lo spinner di "Riprova" non si ferma: niente pumpAndSettle.
    await tester.pump();
    expect(tester.widget<WfButton>(switchButton).onPressed, isNull);

    fake.opening.complete();
    await tester.pump();
    expect(tester.widget<WfButton>(switchButton).onPressed, isNotNull);
  });
}
