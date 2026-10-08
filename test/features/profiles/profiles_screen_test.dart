import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/profiles_screen.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

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

  Future<void> pumpProfiles(
    WidgetTester tester,
    List<StoredProfile> list, {
    FakeSessionController? controller,
    String? lastUserId,
    Size surfaceSize = const Size(1440, 900),
    MotionLevel motion = MotionLevel.reduced,
  }) async {
    session =
        controller ?? FakeSessionController(const SessionChoosingProfile());
    var book = list.fold(const ProfileBook(), (b, p) => b.upsert(p));
    if (lastUserId != null) book = book.withLast(lastUserId);
    await pumpApp(tester, const ProfilesScreen(),
        surfaceSize: surfaceSize,
        motion: motion,
        overrides: [
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

  testWidgets('mentre un profilo si apre: indicatore visibile, altri clic niente',
      (tester) async {
    final gate = Completer<void>();
    await pumpProfiles(tester, [mario, luigi], controller: _SlowOpen(gate));
    // Il fuoco parte dal primo profilo: Invio lo apre.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Un velo scuro sull'avatar dorato, e lo spinner color crema.
    final scrim = find.byKey(const ValueKey('profile-opening-u1'));
    expect(scrim, findsOneWidget);
    expect(tester.getSize(scrim), const Size.square(profileAvatarSize));
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .color,
        WfColors.cream);

    await tester.tap(find.text('Luigi'));
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.tap(find.text('Gestisci profili'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u1']);
    expect(session.addProfileCalls, 0);
    expect(find.text('Fine'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(scrim, findsNothing);
    // Il fuoco è rimasto sulla card: Invio la apre di nuovo.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u1', 'u1']);
    await tester.tap(find.text('Luigi'));
    await tester.pump();
    expect(session.openedProfiles, ['u1', 'u1', 'u2']);
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

  testWidgets('Esc in "Gestisci profili": come "Fine"', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-remove-u1')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Gestisci profili'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-remove-u1')), findsNothing);
  });

  testWidgets('profilo senza nome: "Profilo" nella card e nella rimozione',
      (tester) async {
    // Un profilo migrato il cui primo `/Users/Me` non è riuscito.
    await pumpProfiles(tester, [mario, testProfile(userId: 'u2', name: '')]);
    expect(find.text('Profilo'), findsOneWidget);

    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();
    expect(find.byTooltip('Rimuovi Profilo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-remove-u2')));
    await tester.pumpAndSettle();
    expect(find.text('Rimuovere Profilo da questo PC?'), findsOneWidget);
  });

  testWidgets('accessibilità: le card sono pulsanti con il nome',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpProfiles(tester,
        [mario, testProfile(userId: 'u2', name: 'Luigi', expired: true)]);
    // Il nome si legge una volta sola (né l'iniziale né il testo sotto).
    expect(
        tester.getSemantics(find.byKey(const ValueKey('profile-u1'))),
        isSemantics(label: 'Mario', isButton: true, hasTapAction: true));
    expect(
        tester.getSemantics(find.byKey(const ValueKey('profile-u2'))),
        isSemantics(
            label: 'Luigi',
            hint: 'Accedi di nuovo',
            isButton: true,
            hasTapAction: true));
    expect(
        tester.getSemantics(find.byKey(const ValueKey('profile-add'))),
        isSemantics(
            label: 'Aggiungi profilo', isButton: true, hasTapAction: true));

    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();
    // Il pulsante Rimuovi dice di quale profilo.
    expect(find.byTooltip('Rimuovi Mario'), findsOneWidget);
    expect(find.byTooltip('Rimuovi Luigi'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('tastiera: Invio apre il primo profilo, Tab va al successivo',
      (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u1']);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u1', 'u2']);
  });

  testWidgets('tastiera: il fuoco parte dall\'ultimo profilo usato',
      (tester) async {
    await pumpProfiles(tester, [mario, luigi], lastUserId: 'u2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u2']);
  });

  testWidgets('finestra più piccola: tutto visibile, senza scorrere',
      (tester) async {
    // 1024×640 fuori, circa 1008×600 dentro.
    await pumpProfiles(
      tester,
      [
        mario,
        testProfile(userId: 'u2', name: 'Luigi', expired: true),
        testProfile(userId: 'u3', name: 'Peach'),
        testProfile(userId: 'u4', name: 'Toad'),
      ],
      surfaceSize: const Size(1008, 600),
    );
    expect(find.text('Accedi di nuovo'), findsOneWidget);
    expect(find.text('Aggiungi profilo'), findsOneWidget);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, 0);
    expect(tester.getRect(find.text('Gestisci profili')).bottom,
        lessThanOrEqualTo(600));
  });

  testWidgets('movimento completo: gli elementi entrano uno dopo l\'altro',
      (tester) async {
    await pumpProfiles(tester, [mario], motion: MotionLevel.full);
    expect(find.byType(StaggerGroup), findsOneWidget);
    double opacityOf(Finder finder) => tester
        .widget<Opacity>(
            find.ancestor(of: finder, matching: find.byType(Opacity)).first)
        .opacity;
    expect(opacityOf(find.text('Gestisci profili')), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacityOf(find.text('Chi guarda?')), 1);
    expect(opacityOf(find.text('Gestisci profili')), 1);
  });
}
