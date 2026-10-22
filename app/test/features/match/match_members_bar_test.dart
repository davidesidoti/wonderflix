import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/match/match_members_bar.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, MatchPhase phase, int voted) =>
      pumpApp(
          tester,
          Scaffold(
              body: MatchMembersBar(
                  state: testMatchState(
                      phase: phase,
                      stack: const ['m1', 'm2'],
                      members: [
                MatchMember(userId: 'u1', name: 'Mario', voted: voted)
              ]))));

  testWidgets('countsAndCheckWhileVoting', (tester) async {
    await pumpBar(tester, MatchPhase.voting, 1);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);

    await pumpBar(tester, MatchPhase.voting, 2);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
  });

  testWidgets('noCountWhileWaiting', (tester) async {
    await pumpBar(tester, MatchPhase.waiting, 0);

    expect(find.textContaining('/'), findsNothing);
  });
}
