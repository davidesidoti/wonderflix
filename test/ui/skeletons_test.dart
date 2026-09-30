import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/mylist/my_list_screen.dart';
import 'package:wonderflix/ui/shimmer.dart';
import 'package:wonderflix/ui/skeletons.dart';
import 'package:wonderflix/ui/states.dart';
import 'package:wonderflix/ui/wf_switcher.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  testWidgets('scheda in caricamento: scheletro con l\'onda, niente spinner',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      overrides: [
        itemProvider('m1').overrideWith((ref) => Completer<JellyfinItem>().future),
      ],
      motion: MotionLevel.full,
    );
    expect(find.byType(DetailSkeleton), findsOneWidget);
    expect(find.byType(WfShimmer), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('La mia lista in caricamento: griglia di scheletri',
      (tester) async {
    final api = FakeLibraryApi()..favoritesGate = Completer<void>();
    await pumpApp(tester, const Scaffold(body: MyListScreen()),
        overrides: [libraryApiProvider.overrideWithValue(api), signedIn]);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
  });

  testWidgets('WfSwitcher: dissolvenza verso il contenuto', (tester) async {
    Widget tree(bool loaded) => MaterialApp(
          home: WfMotionScope(
            motion: const WfMotion(MotionLevel.full),
            child: WfSwitcher(
              expand: true,
              child: loaded
                  ? const Text('contenuto', key: ValueKey('dati'))
                  : const PosterGridSkeleton(key: ValueKey('attesa')),
            ),
          ),
        );
    await tester.pumpWidget(tree(false));
    await tester.pumpWidget(tree(true));
    await tester.pump(const Duration(milliseconds: 100));
    // A metà: ci sono tutti e due.
    expect(find.text('contenuto'), findsOneWidget);
    expect(find.byType(PosterGridSkeleton), findsOneWidget);
    await tester.pump(WfMotion.medium);
    expect(find.byType(PosterGridSkeleton), findsNothing);
  });

  testWidgets('WfSwitcher: chi esce lascia il controller e spegne gli Hero',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget list(String name) => KeyedSubtree(
          key: ValueKey(name),
          child: Builder(
            builder: (context) => ListView(
              primary: false,
              controller: WfSwitcher.isOutgoing(context) ? null : controller,
              children: [Hero(tag: 'h', child: Text(name))],
            ),
          ),
        );
    Widget tree(Widget child) => MaterialApp(
          home: WfMotionScope(
            motion: const WfMotion(MotionLevel.full),
            child: WfSwitcher(expand: true, child: child),
          ),
        );
    await tester.pumpWidget(tree(list('vecchi')));
    await tester.pumpWidget(
        tree(const PosterGridSkeleton(key: ValueKey('attesa'))));
    await tester.pump(const Duration(milliseconds: 100));
    // Stesso stato di nuovo mentre il vecchio sta ancora sfumando.
    await tester.pumpWidget(tree(list('nuovi')));
    expect(find.text('vecchi'), findsOneWidget);
    expect(find.text('nuovi'), findsOneWidget);
    expect(controller.positions, hasLength(1));
    HeroMode modeOf(String text) => tester.widget<HeroMode>(find
        .ancestor(of: find.text(text), matching: find.byType(HeroMode))
        .first);
    expect(modeOf('vecchi').enabled, isFalse);
    expect(modeOf('nuovi').enabled, isTrue);
    await tester.pump(WfMotion.medium);
    await tester.pump(WfMotion.medium);
    expect(find.text('vecchi'), findsNothing);
    expect(find.byType(PosterGridSkeleton), findsNothing);
    expect(controller.positions, hasLength(1));
  });
}
