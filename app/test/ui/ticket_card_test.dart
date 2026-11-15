import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/card_preview_host.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/ticket_card.dart';

import '../support/fake_session_controller.dart';
import '../support/library_fakes.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  final signedIn = sessionControllerProvider
      .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser)));

  JellyfinItem episode({
    int? runtimeMinutes = 60,
    int positionMinutes = 0,
    double? playedPercentage,
  }) =>
      testItem(
        id: 'e8',
        name: 'Per sempre',
        kind: ItemKind.episode,
        seriesName: 'The Last of Us',
        index: 8,
        seasonIndex: 1,
        runtimeMinutes: runtimeMinutes,
        positionTicks: positionMinutes * 600000000,
        playedPercentage: playedPercentage,
      );

  Future<void> pumpTicket(
    WidgetTester tester,
    JellyfinItem item, {
    bool resumed = true,
    Size size = const Size(1280, 800),
    bool tv = false,
    bool autofocus = false,
    CardPreviewExtra? previewExtra,
  }) =>
      pumpApp(
        tester,
        Center(
          child: TicketCard(
              item: item,
              resumed: resumed,
              autofocus: autofocus,
              previewExtra: previewExtra),
        ),
        overrides: [signedIn],
        surfaceSize: size,
        tv: tv,
      );

  testWidgets('iniziato: minuti che restano', (tester) async {
    await pumpTicket(
        tester, episode(positionMinutes: 8, playedPercentage: 13.3));
    expect(find.text('52 min'), findsOneWidget);
    expect(find.text('restano'), findsOneWidget);
    expect(find.text('Prossimo'), findsNothing);
    expect(find.byType(ProgressStrip), findsOneWidget);
  });

  testWidgets('da Prossimi episodi: Prossimo e durata', (tester) async {
    await pumpTicket(tester, episode(runtimeMinutes: 58), resumed: false);
    expect(find.text('Prossimo'), findsOneWidget);
    expect(find.text('58 min'), findsOneWidget);
    expect(find.text('restano'), findsNothing);
    expect(find.byType(ProgressStrip), findsNothing);
  });

  testWidgets('senza durata niente minuti', (tester) async {
    await pumpTicket(tester, episode(runtimeMinutes: null));
    expect(find.textContaining('min'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.text('restano'), findsNothing);
    // Nemmeno da Prossimi episodi: solo "Prossimo".
    await pumpTicket(tester, episode(runtimeMinutes: null), resumed: false);
    expect(find.text('Prossimo'), findsOneWidget);
    expect(find.textContaining('min'), findsNothing);
  });

  testWidgets('testi: titolo e riga come nelle altre card', (tester) async {
    await pumpTicket(tester, episode(positionMinutes: 8));
    expect(find.text('The Last of Us'), findsOneWidget);
    expect(find.text('S1:E8 · Per sempre'), findsOneWidget);
  });

  testWidgets('tap apre la scheda; l\'anteprima ha le note', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
                body: Center(
                  child: TicketCard(
                    item: testItem(id: 'm1', name: 'Dune'),
                    resumed: true,
                    previewExtra: const CardPreviewExtra(notes: ['nota']),
                  ),
                ),
              )),
      GoRoute(
          path: '/item/:id',
          builder: (_, state) => Text('scheda ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: [signedIn]);
    expect(
        tester.widget<CardPreviewHost>(find.byType(CardPreviewHost)).extra,
        isNotNull);
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.text('scheda m1'), findsOneWidget);
  });

  group('misure', () {
    Future<void> check(WidgetTester tester, Size surface, bool tv,
        TicketSize expected) async {
      await pumpTicket(tester, episode(positionMinutes: 8, playedPercentage: 13),
          size: surface, tv: tv);
      expect(tester.getSize(find.byType(TicketCard)),
          Size(expected.width, expected.height));
      // L'immagine è larga `image`: la linea dello strappo è lì.
      expect(tester.getSize(find.byKey(const Key('ticket-image'))).width,
          expected.image);
      expect(tester.takeException(), isNull);
    }

    testWidgets('desktop 1280: 392x124', (tester) async {
      await check(tester, const Size(1280, 800), false,
          (width: 392, height: 124, image: 220));
    });

    testWidgets('stretto 390: 300x104', (tester) async {
      await check(tester, const Size(390, 780), false,
          (width: 300, height: 104, image: 150));
    });

    testWidgets('TV: 330x108', (tester) async {
      await check(tester, const Size(1280, 720), true,
          (width: 330, height: 108, image: 182));
    });

    testWidgets('stretto, Prossimo con un titolo lungo: niente overflow',
        (tester) async {
      await pumpTicket(
          tester,
          testItem(
              name: 'Un titolo davvero molto ma molto lungo da non stare',
              runtimeMinutes: 158),
          resumed: false,
          size: const Size(390, 780));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('TV: autofocus prende il focus', (tester) async {
    await pumpTicket(tester, episode(),
        tv: true, autofocus: true, size: const Size(1280, 720));
    expect(Focus.of(tester.element(find.text('The Last of Us'))).hasFocus,
        isTrue);
  });
}
