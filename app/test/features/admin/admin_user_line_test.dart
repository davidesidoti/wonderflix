import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';

import '../../support/avatar_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('l\'immagine dell\'utente della sessione, dal tag di Jellyfin',
      (tester) async {
    final urls = <String>[];
    await pumpApp(
        tester,
        const AdminUserLine(
            name: 'Mario', detail: 'PC', userId: 'u1', imageTag: 't1'),
        overrides: [captureImageUrls(urls)]);

    expect(urls.last, 'https://media.example.com/UserImage?userId=u1&tag=t1');
    expect(find.text('Mario'), findsOneWidget);
  });

  testWidgets('senza tag: l\'iniziale', (tester) async {
    final urls = <String>[];
    await pumpApp(tester, const AdminUserLine(name: 'Mario', userId: 'u1'),
        overrides: [captureImageUrls(urls)]);

    expect(urls, isEmpty);
    expect(find.text('M'), findsOneWidget);
  });
}
