import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/profile_switch.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

/// Un watch party fisso: [leave] aspetta [gate], se c'è.
class _Party extends WatchPartySession {
  _Party({required this.inGroup, this.gate});

  final bool inGroup;
  final Completer<void>? gate;
  int leaveCalls = 0;

  @override
  WatchPartyState build() => WatchPartyState(
      phase: inGroup ? WatchPartyPhase.inGroup : WatchPartyPhase.none);

  @override
  Future<void> leave() async {
    leaveCalls++;
    await gate?.future;
    state = const WatchPartyState();
  }
}

void main() {
  late FakeSessionController session;
  late _Party party;

  Future<void> pumpButton(WidgetTester tester,
      {bool inGroup = false, Completer<void>? gate, bool add = false}) async {
    session = FakeSessionController(const SessionSignedIn(testUser));
    party = _Party(inGroup: inGroup, gate: gate);
    await pumpApp(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                unawaited(switchProfile(context, ref, addProfile: add)),
            child: const Text('vai'),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        watchPartySessionProvider.overrideWith(() => party),
      ],
    );
  }

  testWidgets('senza party: si cambia subito', (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('vai'));
    await tester.pump();
    expect(session.switchCalls, 1);
    expect(party.leaveCalls, 0);
  });

  testWidgets('"Aggiungi profilo": lo stesso cambio, poi l\'accesso',
      (tester) async {
    await pumpButton(tester, add: true);
    await tester.tap(find.text('vai'));
    await tester.pump();
    expect(session.addProfileCalls, 1);
    expect(session.switchCalls, 0);
  });

  testWidgets('in un party: conferma, poi uscita e cambio', (tester) async {
    await pumpButton(tester, inGroup: true);
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
    expect(find.text('Uscirai dal watch party.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cambia profilo'));
    await tester.pumpAndSettle();
    expect(party.leaveCalls, 1);
    expect(session.switchCalls, 1);
  });

  testWidgets('in un party, "Annulla": niente', (tester) async {
    await pumpButton(tester, inGroup: true);
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(party.leaveCalls, 0);
    expect(session.switchCalls, 0);
  });

  testWidgets('uscita lenta: dopo 3 s si cambia lo stesso', (tester) async {
    final gate = Completer<void>();
    await pumpButton(tester, inGroup: true, gate: gate);
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cambia profilo'));
    await tester.pump();
    expect(session.switchCalls, 0);

    await tester.pump(partyLeaveTimeout);
    await tester.pump();
    expect(session.switchCalls, 1);
    gate.complete();
  });
}
