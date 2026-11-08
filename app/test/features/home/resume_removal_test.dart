import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/ui/landscape_card.dart';

import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeLibraryApi library;

  setUp(() => library = FakeLibraryApi());

  final dune = testItem(id: 'm1', positionTicks: 500, playedPercentage: 20);
  final arrival = testItem(id: 'm2', name: 'Arrival', positionTicks: 900);

  Future<void> pumpRow(WidgetTester tester, List<JellyfinItem> items) =>
      pumpApp(
        tester,
        Scaffold(
          body: HomeRowView(
            kind: HomeRowKind.resume,
            content: ItemsRowContent(items),
            animateEntrance: false,
          ),
        ),
        overrides: homeOverrides(library: library),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeRowView)));

  void dismiss(WidgetTester tester, String id) => tester
      .widget<LandscapeCard>(find.byKey(ValueKey('resume-$id')))
      .previewExtra!
      .onDismiss!();

  testWidgets('togliere: sparisce, SnackBar e Annulla rimanda il punto', (
    tester,
  ) async {
    await pumpRow(tester, [dune, arrival]);
    dismiss(tester, 'm1');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-m1')), findsNothing);
    expect(find.byKey(const ValueKey('resume-m2')), findsOneWidget);
    expect(library.positionCalls, [('m1', 0)]);
    expect(library.playedCalls, isEmpty, reason: 'il visto non si tocca');
    expect(find.text('Tolto da Continua a guardare'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // la SnackBar entra
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    await tester.pump();
    expect(library.positionCalls.last, ('m1', 500));
    expect(find.byKey(const ValueKey('resume-m1')), findsOneWidget);
  });

  testWidgets('tutti tolti: la riga non c\'è', (tester) async {
    await pumpRow(tester, [dune]);
    expect(find.text('Continua a guardare'), findsOneWidget);
    dismiss(tester, 'm1');
    await tester.pump();
    await tester.pump();
    expect(find.text('Continua a guardare'), findsNothing);
  });

  testWidgets('togliere non riuscito: la card torna e la SnackBar lo dice', (
    tester,
  ) async {
    await pumpRow(tester, [dune]);
    library.error = const ServerUnreachableException();
    dismiss(tester, 'm1');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-m1')), findsOneWidget);
    expect(
      find.text('Continua a guardare non aggiornato: riprova'),
      findsOneWidget,
    );
    expect(
      containerOf(tester)
          .read(userDataOverridesProvider.notifier)
          .effective(dune)
          .playbackPositionTicks,
      500,
    );
  });
}
