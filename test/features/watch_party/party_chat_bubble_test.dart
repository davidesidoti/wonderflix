import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_chat_bubble.dart';
import 'package:wonderflix/ui/user_avatar.dart';

import '../../support/avatar_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  PartyChatEntry entry(String text,
          {bool mine = false, bool pending = false}) =>
      PartyChatEntry(testChatEvent(text), mine: mine, pending: pending);

  testWidgets('riga: nome in oro e testo, emoji di Windows come ripiego',
      (tester) async {
    await pumpApp(
        tester, Scaffold(body: PartyChatMessage(entry: entry('che scena'))));
    expect(find.textContaining('Luigi'), findsOneWidget);
    expect(find.textContaining('che scena'), findsOneWidget);
    final rich = tester.widget<Text>(find.byType(Text).first);
    expect(rich.style?.fontFamilyFallback, ['Segoe UI Emoji']);
    // Prima l'avatar, poi il nome.
    final name = (rich.textSpan! as TextSpan).children![1] as TextSpan;
    expect(name.text, 'Luigi');
    expect(name.style?.color, WfColors.gold);
  });

  testWidgets('accanto al nome l\'avatar del mittente, cercato per id',
      (tester) async {
    final urls = <String>[];
    await pumpApp(
        tester, Scaffold(body: PartyChatMessage(entry: entry('che scena'))),
        overrides: [
          captureImageUrls(urls),
          // Il nome non corrisponde: il mittente si cerca per id.
          avatarsFor(const [
            UserAvatarInfo(userId: 'u2', name: 'Luigi Verdi', imageTag: 't2'),
          ]),
        ]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
    expect(avatar.size, partyChatAvatarSize);
    expect(avatar.muted, isTrue);
    expect(urls.toSet(), {'https://media.example.com/UserImage?userId=u2&tag=t2'});
  });

  testWidgets('i nostri: "Tu"; in attesa più trasparenti', (tester) async {
    await pumpApp(
        tester,
        Scaffold(
            body: PartyChatMessage(
                entry: entry('ci siamo', mine: true, pending: true))));
    expect(find.textContaining('Tu'), findsOneWidget);
    expect(find.textContaining('Luigi'), findsNothing);
    expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        PartyChatMessage.pendingOpacity);
  });

  testWidgets('bolla: al massimo 4 righe e 360 px', (tester) async {
    await pumpApp(
        tester,
        Scaffold(
            body: Align(
                alignment: Alignment.bottomLeft,
                child: PartyChatBubble(entry: entry('parola ' * 200)))));
    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.maxLines, PartyChatBubble.maxLines);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byType(PartyChatBubble)).width,
        lessThanOrEqualTo(PartyChatBubble.width));
  });

  testWidgets('bolla animata: esce sfumando e poi avvisa', (tester) async {
    var gone = 0;
    final leaving = ValueNotifier(false);
    await pumpApp(
        tester,
        Scaffold(
            body: ValueListenableBuilder<bool>(
                valueListenable: leaving,
                builder: (context, isLeaving, _) => AnimatedChatBubble(
                    entry: entry('ciao'),
                    leaving: isLeaving,
                    onGone: () => gone++))));
    await tester.pump(const Duration(seconds: 1));
    expect(gone, 0);
    leaving.value = true;
    await tester.pumpAndSettle();
    expect(gone, 1);
  });
}
