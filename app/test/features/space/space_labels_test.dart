import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/core/space/space_models.dart';
import 'package:wonderflix/features/space/space_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

SpaceCandidate candidate({
  List<String> via = const [],
  List<String> keep = const [],
  List<SpaceViewer> viewers = const [],
  List<SpaceRequest> requests = const [],
  double? ratingAvg,
  int ratingCount = 0,
  DateTime? added,
}) => SpaceCandidate(
  key: 'k',
  kind: 'Movie',
  title: 't',
  sizeBytes: 1,
  freeNowBytes: 1,
  freeLaterBytes: 0,
  inPackBytes: 0,
  via: via,
  keep: keep,
  viewers: viewers,
  requests: requests,
  ratingAvg: ratingAvg,
  ratingCount: ratingCount,
  added: added,
  genres: const [],
);

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 10, 30);
  final last = DateTime(2026, 2, 28);

  setUpAll(() async {
    await initializeDateFormatting('it');
    await initializeDateFormatting('en');
  });

  test('AllFinishedSaysWatchedByEveryone', () {
    final c = candidate(
      via: ['NobodyWatching'],
      viewers: [
        SpaceViewer(name: 'Anna', finished: true, lastPlayed: last),
        SpaceViewer(name: 'Luca', finished: true, lastPlayed: last),
      ],
    );
    expect(spaceViaLines(it, c, now), [
      'Visto da tutti, ultima visione 8 mesi fa',
    ]);
    expect(spaceViaLines(en, c, now), [
      'Watched by everyone, last watched 8 months ago',
    ]);
  });

  test('MixedNamesWhoFinishedAndWhoNot', () {
    final c = candidate(
      via: ['NobodyWatching'],
      viewers: [
        SpaceViewer(name: 'Anna', finished: true, lastPlayed: last),
        SpaceViewer(name: 'Luca', finished: false),
      ],
    );
    expect(spaceViaLines(it, c, now), [
      'Visto da Anna, abbandonato da Luca, ultima visione 8 mesi fa',
    ]);
  });

  test('NobodyFinishedAndRecentDaysAndNeverOpenedAndRating', () {
    final c = candidate(
      via: ['NobodyWatching', 'NeverOpened', 'LowRating', 'Boh'],
      viewers: [
        SpaceViewer(
          name: 'Anna',
          finished: false,
          lastPlayed: DateTime(2026, 10, 20),
        ),
      ],
      added: DateTime(2026, 3, 30),
      ratingAvg: 3,
      ratingCount: 2,
    );
    expect(spaceViaLines(it, c, now), [
      'Abbandonato da tutti, ultima visione 10 giorni fa',
      'Mai aperto da 7 mesi',
      'Voto medio 3,0/10 su 2 voti',
      'Boh',
    ]);
    expect(spaceViaLines(en, c, now)[2], 'Average rating 3.0/10 from 2 votes');
  });

  test('KeepLabelsUseTheLatestRequest', () {
    final c = candidate(
      keep: ['InProgress', 'RecentRequest', 'HighRating', 'SequelComing'],
      requests: [
        SpaceRequest(name: 'Luca', at: DateTime(2026, 9, 1)),
        SpaceRequest(name: 'Anna', at: DateTime(2026, 10, 3)),
      ],
    );
    expect(spaceKeepLabels(it, c), [
      'In visione',
      'Richiesto da Anna il 3 ottobre',
      'Voti alti',
      'Seguito in arrivo',
    ]);
  });

  test('GbHasTwoDecimalsAndComma', () {
    expect(spaceGb(it, 12345000000), '12,35 GB');
    expect(spaceTb(it, 1234000000000), '1,23 TB');
    expect(spaceTb(en, 1234000000000), '1.23 TB');
  });

  test('TheRemoveTorrentsStepCounts', () {
    const step = SpaceStep(
      name: 'RemoveTorrents',
      state: 'Done',
      done: 1,
      waiting: 2,
    );
    expect(
      spaceStepLabel(it, step),
      'Tolgo i torrent: tolti 1, 2 in attesa del seed',
    );
  });

  test('ASkippedGoneStep', () {
    const step = SpaceStep(
      name: 'DeleteFromRadarr',
      state: 'Skipped',
      detail: 'Gone',
    );
    expect(
      spaceStepLabel(it, step),
      "Elimino da Radarr con i file: non c'era più",
    );
  });

  test('UnknownCodesFallBackToTheRawCode', () {
    expect(
      spaceStepLabel(
        it,
        const SpaceStep(name: 'X', state: 'Done', detail: 'Y'),
      ),
      'X: Y',
    );
    expect(spaceServiceError(it, 'qbit', 'Boh'), 'qBittorrent: errore');
    expect(spaceServiceError(it, 'qbit', null), isNull);
  });

  test('ServiceErrorsAndFailures', () {
    expect(
      spaceServiceError(it, 'qbit', 'NotConfigured'),
      'qBittorrent non configurato',
    );
    expect(
      spaceServiceError(it, 'qbit', 'Unauthorized'),
      'qBittorrent: utente o password sbagliati',
    );
    expect(
      spaceServiceError(it, 'radarr', 'Unreachable'),
      'Radarr non risponde',
    );
    expect(
      spaceServiceError(it, 'quota', 'NotConfigured'),
      'Quota non disponibile: manca il file della quota (README del plugin)',
    );
    for (final f in SpaceFailure.values) {
      expect(spaceFailureLabel(it, f), isNotEmpty);
      expect(spaceFailureLabel(en, f), isNotEmpty);
    }
    expect(it.spaceScanFailed, 'Calcolo non riuscito');
  });

  test('PlannedStepsForAMovie', () {
    final steps = spacePlannedSteps(it, 'Movie');
    expect(steps, hasLength(7));
    expect(steps[2], 'Elimino da Radarr con i file');
    expect(spacePlannedSteps(it, 'Season'), hasLength(7));
    expect(spacePlannedSteps(it, 'Season')[1], 'Tolgo i download in coda');
  });
}
