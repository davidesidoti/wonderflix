import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/ui/user_avatar.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/avatar_fakes.dart';
import '../support/pump_app.dart';

void main() {
  late List<String> urls;

  Override captureImages() =>
      imageBuilderProvider.overrideWithValue((image, fit) {
        urls.add(image.url);
        return const SizedBox.expand();
      });

  /// Come il provider vero: la cache si chiude con lo scope (una richiesta
  /// partita alla fine del test lascerebbe il suo timer in sospeso).
  Override directoryOf(FakeAvatarsApi api) =>
      avatarDirectoryProvider.overrideWith((ref) {
        final directory = AvatarDirectory(api);
        ref.onDispose(directory.dispose);
        return directory;
      });

  setUp(() => urls = []);

  Color background(WidgetTester tester) =>
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor!;

  testWidgets('con il tag: l\'immagine sopra l\'iniziale', (tester) async {
    await pumpApp(
        tester,
        const Center(
            child: UserAvatar(userId: 'u1', name: 'mario', size: 40, imageTag: 't1')),
        overrides: [captureImages()]);

    expect(urls.last, 'https://media.example.com/UserImage?userId=u1&tag=t1');
    // L'iniziale resta sotto: si vede finché l'immagine non c'è.
    expect(find.text('M'), findsOneWidget);
    expect(tester.getSize(find.byType(UserAvatar)), const Size(40, 40));
  });

  testWidgets('senza tag: solo l\'iniziale, scura su oro', (tester) async {
    await pumpApp(
        tester, const Center(child: UserAvatar(userId: 'u1', name: '', size: 30)),
        overrides: [captureImages()]);

    expect(urls, isEmpty);
    expect(find.text('?'), findsOneWidget);
    expect(background(tester), WfColors.gold);
  });

  testWidgets('muted: l\'iniziale dorata su grigio', (tester) async {
    await pumpApp(
        tester,
        const Center(
            child: UserAvatar(userId: 'u1', name: 'Luigi', size: 26, muted: true)),
        overrides: [captureImages()]);

    expect(background(tester), WfColors.surfaceHigh);
  });

  testWidgets('lookup senza un profilo aperto: l\'iniziale, nessuna chiamata',
      (tester) async {
    final api = FakeAvatarsApi();
    await pumpApp(tester,
        const Center(child: UserAvatar.lookup(name: 'Mario', size: 26)),
        overrides: [captureImages(), avatarsApiProvider.overrideWithValue(api)]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);

    expect(urls, isEmpty);
    expect(api.calls, isEmpty);
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('lookup per nome: l\'immagine con l\'id della risposta',
      (tester) async {
    final api = FakeAvatarsApi()
      ..users = const [UserAvatarInfo(userId: 'u1', name: 'Mario', imageTag: 't1')];
    await pumpApp(tester,
        const Center(child: UserAvatar.lookup(name: 'Mario', size: 26, muted: true)),
        overrides: [captureImages(), directoryOf(api)]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    expect(api.calls.single.names, ['Mario']);
    expect(urls.last, 'https://media.example.com/UserImage?userId=u1&tag=t1');
  });

  testWidgets('con il tag: l\'id come quello delle immagini cercate',
      (tester) async {
    await pumpApp(
        tester,
        const Center(
            child: UserAvatar(
                userId: 'AB-CD', name: 'Mario', size: 40, imageTag: 't1')),
        overrides: [captureImages()]);

    expect(urls.last, 'https://media.example.com/UserImage?userId=abcd&tag=t1');
  });

  testWidgets('decorativo per i lettori di schermo', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(
        tester,
        const Column(children: [
          UserAvatar(userId: 'u1', name: 'Mario', size: 40, imageTag: 't1'),
          UserAvatar(userId: 'u2', name: 'Luigi', size: 40),
        ]),
        overrides: [captureImages()]);

    expect(find.bySemanticsLabel('M'), findsNothing);
    expect(find.bySemanticsLabel('L'), findsNothing);
    semantics.dispose();
  });
}
