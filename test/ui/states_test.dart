import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/ui/states.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('ErrorView mostra il messaggio e riprova', (tester) async {
    var retries = 0;
    await pumpApp(
      tester,
      ErrorView(
          error: const ServerUnreachableException(), onRetry: () => retries++),
    );
    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    await tester.tap(find.text('Riprova'));
    expect(retries, 1);
  });
}
