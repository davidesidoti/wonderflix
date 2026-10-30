import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/core/space/space_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/space/space_actions.dart';
import 'package:wonderflix/features/space/space_providers.dart';
import 'package:wonderflix/features/space/space_title_dialog.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/space_fakes.dart';

SpaceStep _step(String name, String state, {String? detail}) =>
    SpaceStep(name: name, state: state, detail: detail);

SpaceOperation _op(
  String state,
  List<SpaceStep> steps, {
  int freed = 0,
  int pending = 0,
  int? before,
  int? after,
}) => SpaceOperation(
  id: 'op1',
  kind: 'Movie',
  key: 'movie:1',
  title: 'Film Raro',
  state: state,
  auto: false,
  startedAt: DateTime.utc(2026, 10, 30),
  estimatedFreedBytes: freed,
  pendingBytes: pending,
  quotaBeforeBytes: before,
  quotaAfterBytes: after,
  steps: steps,
);

SpaceCandidate _candidate() => const SpaceCandidate(
  key: 'movie:1',
  kind: 'Movie',
  title: 'Film Raro',
  sizeBytes: 5000000000,
  freeNowBytes: 5000000000,
  freeLaterBytes: 0,
  inPackBytes: 0,
  via: [],
  keep: [],
  viewers: [],
  requests: [],
  ratingCount: 0,
  genres: [],
);

void main() {
  late FakeSpaceApi api;

  setUp(() => api = FakeSpaceApi());

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => unawaited(
              startSpaceOperation(
                context,
                ref,
                kind: 'Movie',
                key: 'movie:1',
                title: 'Film Raro',
                sizeBytes: 5000000000,
              ),
            ),
            child: const Text('via'),
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
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pump();
  }

  int reads() => api.calls.where((c) => c.startsWith('operation')).length;

  testWidgets('StepsUpdateLive', (tester) async {
    api.operationResults.addAll([
      _op('Running', [
        _step('FindTorrents', 'Running'),
        _step('RemoveFromQueue', 'Pending'),
      ]),
      _op('Running', [
        _step('FindTorrents', 'Done'),
        _step('RemoveFromQueue', 'Running'),
      ]),
      _op(
        'Done',
        [_step('FindTorrents', 'Done'), _step('RemoveFromQueue', 'Done')],
        freed: 1,
        pending: 2000000000,
        before: 10000000000,
        after: 5000000000,
      ),
    ]);
    await open(tester);
    await tester.pump();
    expect(find.text('Cerco i torrent'), findsOneWidget);
    expect(find.text('Liberati 5,00 GB'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(reads(), 2);
    final overviews = api.calls.where((c) => c == 'overview').length;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Liberati 5,00 GB'), findsOneWidget);
    expect(find.text('2,00 GB in attesa del seed'), findsOneWidget);
    expect(
      api.calls.where((c) => c == 'overview').length,
      greaterThan(overviews),
    );

    await tester.pump(const Duration(seconds: 3));
    expect(reads(), 3);
  });

  testWidgets('FreedFallsBackToTheEstimate', (tester) async {
    api.operationResults.add(_op('Done', const [], freed: 3000000000));
    await open(tester);
    await tester.pump();
    expect(find.text('Liberati 3,00 GB'), findsOneWidget);
  });

  testWidgets('AFailedStepShowsWhy', (tester) async {
    api.operationResults.add(
      _op('Failed', [
        _step('RemoveTorrents', 'Failed', detail: 'Unreachable'),
        _step('RemoveFromSeerr', 'NotDone'),
      ]),
    );
    await open(tester);
    await tester.pump();
    expect(find.text('Tolgo i torrent: non risponde'), findsOneWidget);
    expect(find.text('Tolgo da Seerr: non fatto'), findsOneWidget);
  });

  testWidgets('AMissingOperationStopsPolling', (tester) async {
    api.operationResults.add(const SpaceException(SpaceFailure.notFound));
    await open(tester);
    await tester.pump();
    expect(find.text('Operazione non trovata'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(reads(), 1);
  });

  testWidgets('DeleteIsDisabledWhileStarting', (tester) async {
    api.startGate = Completer<void>();
    api.operationResults.add(
      _op('Running', [_step('FindTorrents', 'Running')]),
    );
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSpaceTitle(
              context,
              _candidate(),
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
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina').last);
    await tester.pumpAndSettle();
    // `start` aspetta: Elimina è spento e un altro tocco non lo richiama.
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pump();

    expect(api.calls.where((c) => c.startsWith('start')), hasLength(1));
    api.startGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Cerco i torrent'), findsOneWidget);
  });

  testWidgets('ClosingKeepsTheOperationRunning', (tester) async {
    api.operationResults.add(
      _op('Running', [_step('FindTorrents', 'Running')]),
    );
    await open(tester);
    await tester.pump();
    expect(reads(), 1);

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(reads(), 1);
    expect(api.calls.where((c) => c.startsWith('start')), hasLength(1));
    expect(api.calls.any((c) => c.startsWith('cancel')), isFalse);
  });
}
