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
  });
}
