import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/sender_avatar.dart';
import 'package:wonderflix/ui/user_avatar.dart';

import '../support/avatar_fakes.dart';
import '../support/pump_app.dart';

void main() {
  Future<void> pump(WidgetTester t, Widget child) => pumpApp(
      t, Scaffold(body: Center(child: child)),
      overrides: [avatarsFor(const [])]);

  testWidgets('avatar con la locandina sovrapposta', (t) async {
    await pump(t, const SenderAvatar(name: 'Luigi', posterItemId: 'm1'));
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.byKey(const Key('sender-poster')), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('sender-poster'))), const Size(18, 27));
    expect(t.getSize(find.byType(SenderAvatar)), const Size(40, 40));
  });

  testWidgets('senza locandina, il simbolo', (t) async {
    await pump(t,
        const SenderAvatar(name: 'Garg', badge: LucideIcons.heartHandshake));
    expect(find.byKey(const Key('sender-badge')), findsOneWidget);
    expect(find.byKey(const Key('sender-poster')), findsNothing);
    expect(t.getSize(find.byKey(const Key('sender-badge'))), const Size(18, 18));
  });

  testWidgets('la locandina vince sul simbolo', (t) async {
    await pump(
        t,
        const SenderAvatar(
            name: 'Garg',
            posterItemId: 'm1',
            badge: LucideIcons.heartHandshake));
    expect(find.byKey(const Key('sender-poster')), findsOneWidget);
    expect(find.byKey(const Key('sender-badge')), findsNothing);
  });

  testWidgets('lo spazio quasi pieno è rosso', (t) async {
    Color? iconColor() => t.widget<Icon>(find.byType(Icon)).color;

    await pump(t, const SystemAvatar(icon: LucideIcons.hardDrive, alarm: true));
    expect(iconColor(), WfColors.error);

    await pump(t, const SystemAvatar(icon: LucideIcons.rotateCw));
    expect(iconColor(), WfColors.gold);
    expect(t.getSize(find.byType(SystemAvatar)), const Size(40, 40));
  });

  testWidgets('il cerchio di sistema ha la locandina e niente semantica',
      (t) async {
    await pump(t,
        const SystemAvatar(icon: LucideIcons.rotateCw, posterItemId: 'm1'));
    expect(find.byKey(const Key('sender-poster')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SystemAvatar),
            matching: find.byType(ExcludeSemantics)),
        findsWidgets);
  });
}
