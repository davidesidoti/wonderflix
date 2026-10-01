import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/watch_party/party_badge.dart';

import '../../support/pump_app.dart';

void main() {
  Future<ValueNotifier<List<String>>> pumpStack(WidgetTester tester,
      List<String> members,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final state = ValueNotifier(members);
    addTearDown(state.dispose);
    await pumpApp(
      tester,
      Center(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: state,
          builder: (context, value, _) => MemberAvatarStack(members: value),
        ),
      ),
      motion: motion,
    );
    return state;
  }

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
}
