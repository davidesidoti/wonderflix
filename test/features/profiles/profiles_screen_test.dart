import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/profiles_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

/// Un'apertura che aspetta [gate].
class _SlowOpen extends FakeSessionController {
  _SlowOpen(this.gate) : super(const SessionChoosingProfile());

  final Completer<void> gate;

  @override
  Future<void> openProfile(String userId) async {
    openedProfiles.add(userId);
    await gate.future;
  }
}

void main() {
  late FakeSessionController session;

  Future<void> pumpProfiles(WidgetTester tester, List<StoredProfile> list,
      {FakeSessionController? controller}) async {
    session =
        controller ?? FakeSessionController(const SessionChoosingProfile());
    final book = list.fold(const ProfileBook(), (b, p) => b.upsert(p));
    await pumpApp(tester, const ProfilesScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => session),
      profilesProvider
          .overrideWith(() => FixedProfiles(ProfilesState(book: book))),
    ]);
    await tester.pump();
  }

  final mario = testProfile(userId: 'u1', name: 'Mario');
  final luigi = testProfile(userId: 'u2', name: 'Luigi');

  testWidgets('titolo, profili e "Aggiungi profilo"', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    expect(find.text('Chi guarda?'), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('Aggiungi profilo'), findsOneWidget);
    expect(find.text('Gestisci profili'), findsOneWidget);
  });

  testWidgets('clic su un profilo: lo apre', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.tap(find.text('Luigi'));
    await tester.pump();
    expect(session.openedProfiles, ['u2']);
  });

  testWidgets('mentre un profilo si apre: indicatore, gli altri clic niente',
      (tester) async {
    final gate = Completer<void>();
    await pumpProfiles(tester, [mario, luigi], controller: _SlowOpen(gate));
    await tester.tap(find.text('Mario'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Luigi'));
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();
    expect(session.openedProfiles, ['u1']);
    expect(session.addProfileCalls, 0);
    expect(find.text('Fine'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Luigi'));
    await tester.pump();
    expect(session.openedProfiles, ['u1', 'u2']);
  });

  testWidgets('profilo scaduto: "Accedi di nuovo", e il clic rifà l\'accesso',
      (tester) async {
    await pumpProfiles(
        tester, [mario, testProfile(userId: 'u2', name: 'Luigi', expired: true)]);
    expect(find.text('Accedi di nuovo'), findsOneWidget);
    await tester.tap(find.text('Luigi'));
    await tester.pump();
    expect(session.reloginProfiles, ['u2']);
    expect(session.openedProfiles, isEmpty);
  });

  testWidgets('"Aggiungi profilo": il login per un profilo nuovo',
      (tester) async {
    await pumpProfiles(tester, [mario]);
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.pump();
    expect(session.addProfileCalls, 1);
  });

  testWidgets('con 5 profili "Aggiungi profilo" non c\'è', (tester) async {
    await pumpProfiles(tester, [
      for (var i = 1; i <= ProfileBook.maxProfiles; i++)
        testProfile(userId: 'u$i', name: 'P$i'),
    ]);
    expect(find.text('Aggiungi profilo'), findsNothing);
  });

  testWidgets('"Gestisci profili": Rimuovi con conferma', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();
    expect(find.text('Fine'), findsOneWidget);
    // In modifica il clic non apre il profilo.
    await tester.tap(find.text('Mario'));
    await tester.pump();
    expect(session.openedProfiles, isEmpty);

    await tester.tap(find.byKey(const ValueKey('profile-remove-u2')));
    await tester.pumpAndSettle();
    expect(find.text('Rimuovere Luigi da questo PC?'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(session.removedProfiles, isEmpty);

    await tester.tap(find.byKey(const ValueKey('profile-remove-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rimuovi'));
    await tester.pumpAndSettle();
    expect(session.removedProfiles, ['u2']);
  });

  testWidgets('tastiera: Tab porta al primo profilo, Invio lo apre',
      (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u1']);
  });
}
