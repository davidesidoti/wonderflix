import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/startup/unreachable_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('riprova da solo ogni 15 s e con il pulsante', (tester) async {
    final fake = FakeSessionController(const SessionUnreachable());
    await pumpApp(tester, const UnreachableScreen(),
        overrides: [sessionControllerProvider.overrideWith(() => fake)]);

    expect(find.text('WonderFlix non è raggiungibile'), findsOneWidget);
    expect(fake.restoreCalls, 0);

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
}
