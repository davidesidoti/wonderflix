import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/space/space_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/space/space_providers.dart';
import 'package:wonderflix/features/space/space_title_dialog.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/space_fakes.dart';

SpaceCandidate _candidate({
  String? itemId,
  int later = 0,
  DateTime? laterAt,
  int pack = 0,
}) => SpaceCandidate(
  key: 'movie:1',
  kind: 'Movie',
  title: 'Film Raro',
  year: 2019,
  itemId: itemId,
  sizeBytes: 5000000000,
  freeNowBytes: 5000000000,
  freeLaterBytes: later,
  freeLaterAt: laterAt,
  inPackBytes: pack,
  via: const ['LowRating'],
  keep: const [],
  viewers: [
    SpaceViewer(
      name: 'Anna',
      finished: true,
      lastPlayed: DateTime.utc(2026, 3, 4),
    ),
  ],
  requests: [SpaceRequest(name: 'Luca', at: DateTime.utc(2026, 1, 9))],
  ratingAvg: 1.5,
  ratingCount: 2,
  genres: const ['Dramma'],
);

void main() {
  late FakeSpaceApi api;

  setUp(() => api = FakeSpaceApi());

  Future<void> open(WidgetTester tester, SpaceCandidate c) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSpaceTitle(
              context,
              c,
              favoriteGenre: false,
              canLighten: false,
            ),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        ...adminTestOverrides(
          FakeAdminApi(),
          features: const SocialFeatures(space: true, known: true),
        ),
        spaceApiProvider.overrideWithValue(api),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  testWidgets('ShowsViewersRequestsAndButtons', (tester) async {
    await open(tester, _candidate());

    expect(find.text('Film Raro'), findsOneWidget);
    expect(find.textContaining('Anna: finito'), findsOneWidget);
    expect(find.textContaining('4 mar 2026'), findsOneWidget);
    expect(find.textContaining('Luca'), findsOneWidget);
    expect(find.textContaining('9 gen 2026'), findsOneWidget);
    expect(find.text('Voto medio 1,5 su 2 voti'), findsOneWidget);
    expect(find.text('Elimina'), findsOneWidget);
    expect(find.text('Tienilo'), findsOneWidget);
    expect(find.text('Alleggerisci'), findsNothing);
  });

  testWidgets('WithoutItemIdStillWorks', (tester) async {
    await open(tester, _candidate());

    expect(find.text('Trailer'), findsNothing);
    expect(find.text('Elimina'), findsOneWidget);
    expect(find.text('Tienilo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KeepCallsTheApiAndCloses', (tester) async {
    await open(tester, _candidate());

    await tester.tap(find.text('Tienilo'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('keep movie:1 Film Raro'));
    expect(find.text('Film Raro'), findsNothing);
  });

  testWidgets('KeepShowsASpinnerWhileWaiting', (tester) async {
    await open(tester, _candidate());
    final gate = api.actionGate = Completer<void>();

    await tester.tap(find.text('Tienilo'));
    await tester.pump();

    final keep = find.byKey(const ValueKey('space-keep'));
    expect(
      find.descendant(of: keep, matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    await tester.tap(find.text('Tienilo'), warnIfMissed: false);
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('keep')), hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Film Raro'), findsNothing);
  });

  testWidgets('ConfirmShowsTheDateWhenKnown', (tester) async {
    await open(
      tester,
      _candidate(later: 2000000000, laterAt: DateTime.utc(2026, 5, 6)),
    );
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Libera subito 5,00 GB.'), findsOneWidget);
    expect(
      find.textContaining('Altri 2,00 GB dopo il seed, dal 6 mag.'),
      findsOneWidget,
    );
  });

  testWidgets('ConfirmWithoutDateSaysAfterSeeding', (tester) async {
    await open(tester, _candidate(later: 2000000000));
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Altri 2,00 GB dopo il seed.'), findsOneWidget);
  });

  testWidgets('ConfirmShowsThePackNote', (tester) async {
    await open(tester, _candidate(pack: 1000000000));
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('1,00 GB restano: il pack contiene'),
      findsOneWidget,
    );
  });

  testWidgets('DeleteIsDisabledWhileTheConfirmIsOpen', (tester) async {
    await open(tester, _candidate());
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    final buttons = tester
        .widgetList<FilledButton>(find.widgetWithText(FilledButton, 'Elimina'))
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons.any((b) => b.onPressed == null), isTrue);
  });
}
