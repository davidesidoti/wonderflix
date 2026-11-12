import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/features/downloads/weight_ruler.dart';

import '../../support/pump_app.dart';

const _gb = 1000000000;

DownloadCandidate _c(int rank, int gb,
        {int score = 100, bool? fullSeason, bool choice = false}) =>
    DownloadCandidate(
      rank: rank,
      release: DownloadRelease(
        guid: 'g$rank',
        indexerId: 1,
        indexer: 'Idx',
        title: 'R$rank',
        quality: 'x',
        resolution: 1080,
        sizeBytes: gb * _gb,
        score: score,
        fullSeason: fullSeason,
      ),
      isChoice: choice,
      wouldImport: true,
    );

DownloadSearch _s(
  List<DownloadCandidate> candidates, {
  DownloadKind kind = DownloadKind.movie,
  int runtime = 180,
  DownloadCurrentFile? current,
}) =>
    DownloadSearch(
      key: 'k',
      kind: kind,
      title: 'T',
      runtimeMinutes: runtime,
      current: current,
      candidates: candidates,
      validCount: candidates.length,
      totalCount: candidates.length,
    );

void main() {
  test('a season shows only its full packs', () {
    final s = _s([
      _c(1, 1, fullSeason: false),
      _c(2, 1, fullSeason: false),
      _c(3, 1, fullSeason: false),
      _c(4, 10, fullSeason: true, choice: true),
      _c(5, 12, fullSeason: true),
    ], kind: DownloadKind.season);
    final marks = rulerMarks(s);
    expect(marks, hasLength(2));
    expect(marks.where((m) => m.isChoice), hasLength(1));
  });

  test('a season with one full pack has no ruler', () {
    final s = _s([
      _c(1, 1, fullSeason: false),
      _c(2, 1, fullSeason: false),
      _c(3, 10, fullSeason: true),
    ], kind: DownloadKind.season);
    expect(rulerMarks(s), isEmpty);
  });

  test('a movie with a single release has no ruler', () {
    expect(rulerMarks(_s([_c(1, 4)])), isEmpty);
  });

  testWidgets('equal scores and equal sizes: no exception, equal heights',
      (tester) async {
    final marks = rulerMarks(_s([_c(1, 4, choice: true), _c(2, 4), _c(3, 4)]));
    expect(marks, hasLength(3));
    expect(rulerHeights(marks).toSet(), {64.0});
    await pumpApp(tester, Scaffold(body: WeightRuler(marks: marks)),
        surfaceSize: const Size(375, 400));
    expect(tester.takeException(), isNull);
  });

  test('heights go from 14 to 64 with the score', () {
    final h = rulerHeights(rulerMarks(
        _s([_c(1, 4, score: 100), _c(2, 5, score: 150), _c(3, 6, score: 200)])));
    expect(h, [14, 39, 64]);
  });

  testWidgets('draws the choice and the current file labels', (tester) async {
    final marks = rulerMarks(_s([_c(1, 16, choice: true), _c(2, 20)]));
    await pumpApp(
        tester, Scaffold(body: WeightRuler(marks: marks, currentBytes: 78 * _gb)),
        surfaceSize: const Size(1200, 400));
    expect(tester.takeException(), isNull);
    expect(find.text('scelta 16,00 GB'), findsOneWidget);
    expect(find.text('attuale 78,00 GB'), findsOneWidget);
  });

  test('freedBytes: the heavier file minus the choice', () {
    final current = DownloadCurrentFile(
        sizeBytes: 78 * _gb, score: 100, quality: 'x');
    expect(
        freedBytes(_s([_c(1, 16, choice: true)], current: current)), 62 * _gb);
    expect(freedBytes(_s([_c(1, 16, choice: true)])), isNull);
    expect(
        freedBytes(_s([_c(1, 90, choice: true)], current: current)), isNull);
  });

  test('freedBytes: a season whose choice is not a full pack is null', () {
    final current = DownloadCurrentFile(
        sizeBytes: 20 * _gb, score: 100, quality: 'x');
    expect(
        freedBytes(_s([_c(1, 1, fullSeason: false, choice: true)],
            kind: DownloadKind.season, current: current)),
        isNull);
  });

  test('gbPerHour only for movies with a runtime', () {
    expect(gbPerHour(_s([], kind: DownloadKind.season), 16 * _gb), isNull);
    expect(gbPerHour(_s([], runtime: 0), 16 * _gb), isNull);
    expect(gbPerHour(_s([]), 16 * _gb), closeTo(5.33, 0.01));
  });
}
