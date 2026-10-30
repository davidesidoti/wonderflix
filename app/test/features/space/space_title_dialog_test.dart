import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/space/space_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/space/space_providers.dart';
import 'package:wonderflix/features/space/space_title_dialog.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/space_fakes.dart';

SpaceCandidate _candidate({String? itemId}) => SpaceCandidate(
  key: 'movie:1',
  kind: 'Movie',
  title: 'Film Raro',
  year: 2019,
  itemId: itemId,
  sizeBytes: 5000000000,
  freeNowBytes: 5000000000,
  freeLaterBytes: 0,
  inPackBytes: 0,
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
}
