import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..resumeItems = [testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)]
      ..onItems = (query, start, limit) => query.kinds.contains(ItemKind.series)
          ? pageOf([testItem(id: 's1', name: 'The Bear', kind: ItemKind.series)])
          : pageOf([testItem(id: 'm1', name: 'Dune')]);
  });

  List<Override> overrides() => [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ];

  testWidgets('prima volta: le righe entrano scaglionate', (tester) async {
    await pumpApp(tester, const HomeScreen(),
        overrides: overrides(), motion: MotionLevel.full);
    await tester.pump();
    await tester.pump();
    expect(find.byType(StaggerGroup), findsWidgets);
    final rows = tester.widget<StaggerGroup>(find.byKey(const Key('home-rows')));
    expect(rows.play, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  // La "sessione" è il ProviderScope: togliere e rimettere la Home nello
  // stesso scope è come cambiare voce nella barra e tornare.
  testWidgets('seconda volta nella stessa sessione: nessuna entrata',
      (tester) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, value, _) =>
            value ? const HomeScreen() : const SizedBox(),
      ),
      overrides: overrides(),
      motion: MotionLevel.full,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    // Via e di nuovo (come cambiare voce e tornare alla Home).
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    await tester.pump();
    final rows = tester.widget<StaggerGroup>(find.byKey(const Key('home-rows')));
    expect(rows.play, isFalse);
    // Nemmeno le card delle righe volano dentro: nessun gruppo nelle righe.
    expect(find.byType(StaggerGroup), findsOneWidget);
  });
}
