import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/features/watch_party/party_badge.dart';

import '../../support/avatar_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<ValueNotifier<List<String>>> pumpStack(WidgetTester tester,
      List<String> members,
      {MotionLevel motion = MotionLevel.reduced,
      Alignment alignment = Alignment.center}) async {
    final state = ValueNotifier(members);
    addTearDown(state.dispose);
    await pumpApp(
      tester,
      Align(
        alignment: alignment,
        child: ValueListenableBuilder<List<String>>(
          valueListenable: state,
          builder: (context, value, _) => MemberAvatarStack(members: value),
        ),
      ),
      motion: motion,
    );
    return state;
  }

  final animatedSize = find.descendant(
      of: find.byType(MemberAvatarStack), matching: find.byType(AnimatedSize));

  testWidgets('al massimo 3 iniziali, poi "+N"', (tester) async {
    await pumpStack(tester, ['Mario', 'Luigi', 'Sara', 'Anna']);
    await tester.pumpAndSettle();
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('chi entra compare con un "pop"', (tester) async {
    final state = await pumpStack(tester, ['Mario'], motion: MotionLevel.full);
    await tester.pumpAndSettle();
    state.value = ['Mario', 'Luigi'];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    // Scala su x (non `getMaxScaleOnAxis`: la scala su z resta 1).
    final pop = tester
        .widget<Transform>(find
            .ancestor(of: find.text('L'), matching: find.byType(Transform))
            .first)
        .transform
        .entry(0, 0);
    expect(pop, lessThan(1));
    await tester.pumpAndSettle();
  });

  testWidgets('chi esce: la fila si stringe e le iniziali restano ferme',
      (tester) async {
    // Ancorata a sinistra, come nel badge: il bordo sinistro non si muove.
    final state = await pumpStack(tester, ['Mario', 'Luigi', 'Sara'],
        motion: MotionLevel.full, alignment: Alignment.centerLeft);
    await tester.pumpAndSettle();
    expect(animatedSize, findsOneWidget);
    final width = tester.getSize(find.byType(MemberAvatarStack)).width;
    final left = tester.getTopLeft(find.text('M')).dx;

    state.value = ['Mario', 'Luigi'];
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.text('M')).dx, closeTo(left, 0.01),
          reason: 'fotogramma $i');
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MemberAvatarStack)).width,
        closeTo(width - (MemberAvatarStack.avatarSize - MemberAvatarStack.overlap),
            0.01));
    expect(tester.getTopLeft(find.text('M')).dx, closeTo(left, 0.01));
  });

  testWidgets('"+N" sparisce quando si torna a 3', (tester) async {
    final state = await pumpStack(tester, ['Mario', 'Luigi', 'Sara', 'Anna']);
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsOneWidget);
    state.value = ['Mario', 'Luigi', 'Sara'];
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsNothing);
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('animazioni ridotte: la larghezza cambia senza animarsi',
      (tester) async {
    final state = await pumpStack(tester, ['Mario', 'Luigi', 'Sara']);
    await tester.pumpAndSettle();
    expect(animatedSize, findsNothing);
    final width = tester.getSize(find.byType(MemberAvatarStack)).width;
    state.value = ['Mario', 'Luigi'];
    await tester.pump();
    expect(tester.getSize(find.byType(MemberAvatarStack)).width,
        lessThan(width));
    await tester.pumpAndSettle();
  });

  testWidgets('alta quanto un\'iniziale anche con spazio in più',
      (tester) async {
    await pumpStack(tester, ['Mario', 'Luigi']);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MemberAvatarStack)).height,
        MemberAvatarStack.avatarSize);
  });

  testWidgets('i membri con un\'immagine la mostrano, cercati per nome',
      (tester) async {
    final urls = <String>[];
    await pumpApp(tester, const MemberAvatarStack(members: ['Mario', 'Luigi']),
        overrides: [
          captureImageUrls(urls),
          avatarsFor(const [
            UserAvatarInfo(userId: 'u1', name: 'Mario', imageTag: 't1'),
          ]),
        ]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    expect(urls.toSet(), {'https://media.example.com/UserImage?userId=u1&tag=t1'});
    // Luigi non ha un'immagine: l'iniziale.
    expect(find.text('L'), findsOneWidget);
  });
}
