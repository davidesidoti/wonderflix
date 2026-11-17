import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/startup/unreachable_screen.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/fake_session_controller.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

/// Un profilo che non si è aperto, e un nuovo tentativo che aspetta.
class _SlowRetry extends FakeSessionController {
  _SlowRetry() : super(const SessionUnreachable(retryUserId: 'u2'));

  final opening = Completer<void>();

  @override
  Future<void> openProfile(String userId) async {
    await super.openProfile(userId);
    await opening.future;
  }
}

Future<FakeSessionController> pumpUnreachable(
  WidgetTester tester,
  SessionUnreachable state, {
  bool tv = false,
  Size surfaceSize = const Size(1440, 900),
  MotionLevel motion = MotionLevel.reduced,
  List<StoredProfile> profiles = const [],
}) async {
  final fake = FakeSessionController(state);
  await pumpApp(
    tester,
    const UnreachableScreen(),
    overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      profilesOf(profiles),
    ],
    tv: tv,
    surfaceSize: surfaceSize,
    motion: motion,
  );
  return fake;
}

/// La rubrica dei profili con [profiles].
Override profilesOf(List<StoredProfile> profiles) =>
    profilesProvider.overrideWith(() => FixedProfiles(ProfilesState(
        book: profiles.fold(const ProfileBook(), (b, p) => b.upsert(p)))));

final _saved = [testProfile(userId: 'u2', name: 'Luigi')];

LampState lamp(WidgetTester tester, String key) =>
    tester.widget<WfLamp>(find.byKey(Key(key))).state;

void main() {
  final switchButton = find.widgetWithText(WfButton, 'Cambia profilo');
  final retryButton = find.widgetWithText(WfButton, 'Riprova ora');

  testWidgets('nessuna risposta: Sei offline, prima lampada rossa e seconda '
      'spenta', (t) async {
    await pumpUnreachable(
      t,
      const SessionUnreachable(reason: UnreachableReason.offline),
    );
    expect(find.text('Sei offline'), findsOneWidget);
    expect(find.textContaining('avvisa l\'admin'), findsOneWidget);
    expect(lamp(t, 'lamp-connection'), LampState.broken);
    expect(lamp(t, 'lamp-server'), LampState.off);
  });

  testWidgets('503: il server si sta avviando, con la mezz\'ora', (t) async {
    await pumpUnreachable(
      t,
      const SessionUnreachable(reason: UnreachableReason.starting),
    );
    expect(find.text('Il server si sta avviando'), findsOneWidget);
    expect(find.textContaining('mezz\'ora'), findsOneWidget);
    expect(find.textContaining('avvisa l\'admin'), findsNothing);
    expect(lamp(t, 'lamp-connection'), LampState.ok);
    expect(lamp(t, 'lamp-server'), LampState.attention);
  });

  testWidgets('502/504: il server non risponde, senza la mezz\'ora', (t) async {
    await pumpUnreachable(
      t,
      const SessionUnreachable(reason: UnreachableReason.notResponding),
    );
    expect(find.text('Il server non risponde'), findsOneWidget);
    expect(find.textContaining('mezz\'ora'), findsNothing);
    expect(lamp(t, 'lamp-connection'), LampState.ok);
    expect(lamp(t, 'lamp-server'), LampState.attention);
  });

  testWidgets('il conto scende e riprova a 0', (t) async {
    final fake = await pumpUnreachable(t, const SessionUnreachable());
    expect(find.text('Riprovo tra 15 s'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Riprovo tra 12 s'), findsOneWidget);
    expect(fake.restoreCalls, 0);
    await t.pump(const Duration(seconds: 12));
    await t.pump(); // ricostruisce dopo la fine del tentativo
    expect(fake.restoreCalls, 1);
    expect(find.text('Riprovo tra 15 s'), findsOneWidget);
  });

  testWidgets('"Riprova ora" fa ripartire il conto', (t) async {
    final fake = await pumpUnreachable(t, const SessionUnreachable());
    await t.pump(const Duration(seconds: 10));
    await t.tap(find.text('Riprova ora'));
    await t.pump();
    expect(fake.restoreCalls, 1);
    expect(find.text('Riprovo tra 15 s'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    expect(fake.restoreCalls, 1);
    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(fake.restoreCalls, 2);
    expect(fake.openedProfiles, isEmpty);
  });

  testWidgets('"Riprovo…" durante il tentativo', (t) async {
    final fake = _SlowRetry();
    await pumpApp(
      t,
      const UnreachableScreen(),
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
    );
    await t.tap(find.text('Riprova ora'));
    await t.pump();
    expect(find.text('Riprovo…'), findsOneWidget);
    // Acceso (il focus della TV resta), ma non parte un secondo tentativo.
    await t.tap(find.text('Riprova ora'));
    await t.pump();
    // Il conto resta fermo mentre si riprova.
    await t.pump(const Duration(seconds: 20));
    expect(fake.openedProfiles, ['u2']);
    fake.opening.complete();
    // Il tentativo finisce dopo qualche microtask: due frame.
    await t.pump();
    await t.pump();
    expect(find.text('Riprovo tra 15 s'), findsOneWidget);
  });

  testWidgets('attese lunghe: In attesa da N min, anche se il motivo cambia', (
    t,
  ) async {
    final fake = await pumpUnreachable(
      t,
      const SessionUnreachable(reason: UnreachableReason.offline),
    );
    await t.pump(const Duration(seconds: 119));
    expect(find.textContaining('In attesa da'), findsNothing);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('In attesa da 2 min'), findsOneWidget);

    fake.set(const SessionUnreachable(reason: UnreachableReason.starting));
    await t.pump();
    expect(find.text('Il server si sta avviando'), findsOneWidget);
    expect(find.text('Sei offline'), findsNothing);
    expect(lamp(t, 'lamp-connection'), LampState.ok);
    expect(lamp(t, 'lamp-server'), LampState.attention);
    expect(find.text('In attesa da 2 min'), findsOneWidget);
  });

  testWidgets('TV: "Riprova ora" ha il focus', (t) async {
    await pumpUnreachable(
      t,
      const SessionUnreachable(retryUserId: 'u2'),
      tv: true,
      surfaceSize: const Size(960, 540),
    );
    await t.pump();
    expect(Focus.of(t.element(find.text('Riprova ora'))).hasFocus, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('TV: dopo un tentativo "Riprova ora" ha ancora il focus', (
    t,
  ) async {
    final fake = _SlowRetry();
    await pumpApp(
      t,
      const UnreachableScreen(),
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
      tv: true,
      surfaceSize: const Size(960, 540),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 15));
    expect(find.text('Riprovo…'), findsOneWidget);
    expect(Focus.of(t.element(find.text('Riprova ora'))).hasFocus, isTrue);
    fake.opening.complete();
    await t.pump();
    await t.pump();
    expect(find.text('Riprovo tra 15 s'), findsOneWidget);
    expect(Focus.of(t.element(find.text('Riprova ora'))).hasFocus, isTrue);
  });

  testWidgets('dal router: un nuovo motivo non riapre la schermata', (t) async {
    final fake = FakeSessionController(
      const SessionUnreachable(reason: UnreachableReason.offline),
    );
    await pumpAppRouterOf(
      t,
      (ref) => ref.watch(routerProvider),
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
    );
    await t.pump();
    expect(find.text('Sei offline'), findsOneWidget);
    await t.pump(const Duration(seconds: 120));
    expect(find.text('In attesa da 2 min'), findsOneWidget);

    fake.set(const SessionUnreachable(reason: UnreachableReason.starting));
    await t.pump();
    await t.pump();
    expect(find.text('Il server si sta avviando'), findsOneWidget);
    expect(find.text('In attesa da 2 min'), findsOneWidget);
  });

  testWidgets('dopo un tentativo la linea torna vuota di colpo', (t) async {
    await pumpUnreachable(
      t,
      const SessionUnreachable(),
      motion: MotionLevel.full,
    );
    double fill() => t
        .widget<FractionallySizedBox>(
          find.descendant(
            of: find.byKey(const Key('retry-line')),
            matching: find.byType(FractionallySizedBox),
          ),
        )
        .widthFactor!;
    await t.pump(const Duration(seconds: 14));
    await t.pump(const Duration(milliseconds: 999));
    expect(fill(), closeTo(14 / 15, 0.01));
    await t.pump(const Duration(milliseconds: 1)); // il tentativo
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(find.text('Riprovo tra 15 s'), findsOneWidget);
    expect(fill(), 0);
  });

  testWidgets('telefono: pulsanti a tutta larghezza, testo centrato, niente '
      'overflow', (t) async {
    await pumpUnreachable(
      t,
      const SessionUnreachable(
        retryUserId: 'u2',
        reason: UnreachableReason.offline,
      ),
      surfaceSize: const Size(390, 780),
      profiles: _saved,
    );
    expect(t.getSize(retryButton).width, 358);
    expect(t.getSize(switchButton).width, 358);
    expect(t.getSize(retryButton).height, 46);
    expect(
      t.widget<Text>(find.text('Sei offline')).textAlign,
      TextAlign.center,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('movimento ridotto: niente linea; completo: la linea c\'è', (
    t,
  ) async {
    await pumpUnreachable(t, const SessionUnreachable());
    expect(find.byKey(const Key('retry-line')), findsNothing);
    await pumpUnreachable(
      t,
      const SessionUnreachable(),
      motion: MotionLevel.full,
    );
    expect(find.byKey(const Key('retry-line')), findsOneWidget);
  });

  testWidgets('un profilo scelto che non si è aperto: si riprova quello', (
    t,
  ) async {
    final fake = await pumpUnreachable(
      t,
      const SessionUnreachable(retryUserId: 'u2'),
      profiles: _saved,
    );
    expect(switchButton, findsOneWidget);

    await t.pump(const Duration(seconds: 15));
    await t.pump();
    expect(fake.openedProfiles, ['u2']);

    await t.tap(find.text('Riprova ora'));
    await t.pump();
    expect(fake.openedProfiles, ['u2', 'u2']);
    expect(fake.restoreCalls, 0);
  });

  testWidgets('senza profili salvati niente "Cambia profilo"', (t) async {
    await pumpUnreachable(t, const SessionUnreachable(retryUserId: 'u2'));
    expect(switchButton, findsNothing);
  });

  testWidgets('un solo profilo, riaperto da restore: "Cambia profilo" c\'è', (
    t,
  ) async {
    final fake = await pumpUnreachable(
      t,
      const SessionUnreachable(),
      profiles: _saved,
    );
    await t.tap(switchButton);
    await t.pump();
    expect(fake.backToProfilesCalls, 1);
  });

  testWidgets('"Cambia profilo" torna a "Chi guarda?"', (t) async {
    final fake = await pumpUnreachable(
      t,
      const SessionUnreachable(retryUserId: 'u2'),
      profiles: _saved,
    );
    await t.tap(switchButton);
    await t.pump();
    expect(fake.backToProfilesCalls, 1);
    expect(fake.openedProfiles, isEmpty);
  });

  testWidgets('"Cambia profilo" funziona anche mentre si riprova', (t) async {
    final fake = _SlowRetry();
    await pumpApp(
      t,
      const UnreachableScreen(),
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        profilesOf(_saved),
      ],
    );

    await t.tap(find.text('Riprova ora'));
    await t.pump();
    expect(find.text('Riprovo…'), findsOneWidget);
    await t.tap(switchButton);
    await t.pump();
    expect(fake.backToProfilesCalls, 1);
    fake.opening.complete();
    await t.pump();
  });
}
