import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/downloads/download_models.dart';

Map<String, dynamic> releaseJson({Object? size = 4000000000, String guid = 'g1'}) =>
    {
      'Guid': guid,
      'IndexerId': 3,
      'Indexer': 'Idx',
      'Title': 'Film.2025.1080p',
      'Quality': 'WEBRip-1080p',
      'Resolution': 1080,
      'SizeBytes': size,
      'Score': 120,
      'Seeders': null,
    };

void main() {
  group('DownloadSearch.hasLighter on a season', () {
    DownloadSearch season(int sizeBytes, bool? fullSeason) => DownloadSearch(
          key: 'season:1:1',
          kind: DownloadKind.season,
          title: 'Serie',
          runtimeMinutes: 45,
          current: const DownloadCurrentFile(
              sizeBytes: 20000000000, score: 100, quality: 'x'),
          candidates: [
            DownloadCandidate(
              rank: 1,
              release: DownloadRelease(
                guid: 'g',
                indexerId: 1,
                indexer: 'i',
                title: 't',
                quality: 'q',
                resolution: 1080,
                sizeBytes: sizeBytes,
                score: 100,
                fullSeason: fullSeason,
              ),
              isChoice: false,
              wouldImport: true,
            ),
          ],
          validCount: 1,
          totalCount: 1,
        );

    test('a single episode does not count', () {
      expect(season(2000000000, false).hasLighter, isFalse);
    });

    test('a lighter whole pack counts', () {
      expect(season(10000000000, true).hasLighter, isTrue);
    });

    test('with a plugin that does not say, it counts', () {
      expect(season(2000000000, null).hasLighter, isTrue);
    });
  });

  group('DownloadSearchStatus', () {
    Map<String, dynamic> statusJson(String state,
            {Object? startedAt, Object? result}) =>
        {
          'Key': 'movie:1',
          'State': state,
          'StartedAt': startedAt,
          'Service': 'Radarr',
          'Result': result,
        };

    test('RunningKeepsTheStartTime', () {
      final status = DownloadSearchStatus.fromJson(
          statusJson('Running', startedAt: '2026-11-01T10:00:00+01:00'))!;
      expect(status.key, 'movie:1');
      expect(status.state, DownloadSearchJobState.running);
      expect(status.startedAt, DateTime.parse('2026-11-01T10:00:00+01:00'));
      expect(status.service, 'Radarr');
      expect(status.result, isNull);
    });

    test('DoneCarriesTheSearch', () {
      final status = DownloadSearchStatus.fromJson(statusJson('Done', result: {
        'Key': 'movie:1',
        'Kind': 'Movie',
        'Title': 'Film',
        'RuntimeMinutes': 100,
        'ValidCount': 0,
        'TotalCount': 0,
      }))!;
      expect(status.state, DownloadSearchJobState.done);
      expect(status.result?.title, 'Film');
    });

    test('MissingAndNoneNeedNothingElse', () {
      expect(DownloadSearchStatus.fromJson(statusJson('Missing'))?.state,
          DownloadSearchJobState.missing);
      expect(DownloadSearchStatus.fromJson(statusJson('None'))?.state,
          DownloadSearchJobState.none);
    });

    test('UnknownStateOrBrokenDoneIsNull', () {
      expect(DownloadSearchStatus.fromJson(statusJson('Boh')), isNull);
      expect(DownloadSearchStatus.fromJson(statusJson('Done')), isNull);
      expect(
          DownloadSearchStatus.fromJson(
              statusJson('Done', result: {'Key': 'movie:1'})),
          isNull);
      expect(DownloadSearchStatus.fromJson({'Boh': 1}), isNull);
    });
  });

  test('AnOverviewParses', () {
    final overview = DownloadsOverview.fromJson({
      'Enabled': true,
      'Recent': [
        {
          'Key': 'movie:1',
          'Kind': 'Movie',
          'Title': 'Film',
          'PosterUrl': null,
          'At': '2026-10-28T10:00:00+02:00',
          'Release': releaseJson(),
          'PreviousSizeBytes': 9000000000,
          'PreviousScore': 80,
          'ByAdmin': true,
        }
      ],
      'Waiting': [
        {
          'Key': 'season:5:2',
          'Kind': 'Season',
          'Title': 'Serie S2',
          'PosterUrl': null,
          'State': 'NeedsYou',
          'Reason': 'BelowMinScore',
          'AvailableSince': '2026-10-20T00:00:00Z',
          'LastSearchAt': '2026-10-28T00:00:00Z',
          'NextSearchAt': null,
        }
      ],
      'Review': [
        {
          'Key': 'episode:9',
          'Kind': 'Episode',
          'Title': 'Pilot',
          'PosterUrl': null,
          'Score': 40,
          'SizeBytes': 500000000,
          'Quality': 'SDTV',
        },
        {
          'Key': 'movie:3',
          'Kind': 'Movie',
          'Title': 'Film',
          'PosterUrl': null,
          'Score': 40,
          'SizeBytes': 500000000,
          'Quality': 'SDTV',
          'CanHunt': true,
        }
      ],
      'ReviewAt': null,
      'SonarrError': null,
      'RadarrError': 'Unreachable',
    })!;
    expect(overview.enabled, isTrue);
    final choice = overview.recent.single;
    expect(choice.kind, DownloadKind.movie);
    expect(choice.at, DateTime.utc(2026, 10, 28, 8));
    expect(choice.release.sizeBytes, 4000000000);
    expect(choice.release.seeders, isNull);
    expect((choice.previousScore, choice.byAdmin), (80, true));
    final item = overview.waiting.single;
    expect((item.kind, item.state, item.reason),
        (DownloadKind.season, DownloadState.needsYou, DownloadReason.belowMinScore));
    expect(item.nextSearchAt, isNull);
    expect(overview.review.first.quality, 'SDTV');
    // Senza CanHunt (plugin vecchio) niente "Cerca un upgrade".
    expect(overview.review.map((r) => r.canHunt), [false, true]);
    expect((overview.sonarrError, overview.radarrError), (null, 'Unreachable'));
    expect(DownloadsOverview.empty.waiting, isEmpty);
    // Senza Unknown (plugin vecchio) niente sezione.
    expect(overview.unknown, isEmpty);
  });

  test('UnknownDownloadsParse', () {
    final overview = DownloadsOverview.fromJson({
      'Enabled': true,
      'Recent': <Object>[],
      'Waiting': <Object>[],
      'Review': <Object>[],
      'Unknown': [
        {
          'Service': 'Sonarr',
          'DownloadId': 'D1',
          'Title': 'Outlander 2015 S01',
          'SizeBytes': 27000000000,
          'Message': 'Series title mismatch',
        },
        {'Service': 'Radarr', 'DownloadId': 'D2', 'Title': 'Film', 'SizeBytes': 1, 'Message': null},
        {'Service': 'Sonarr'},
      ],
    })!;
    expect(overview.unknown.map((u) => (u.service, u.downloadId, u.title, u.sizeBytes, u.message)), [
      ('Sonarr', 'D1', 'Outlander 2015 S01', 27000000000, 'Series title mismatch'),
      ('Radarr', 'D2', 'Film', 1, null),
    ]);
  });

  test('ASearchParses', () {
    final search = DownloadSearch.fromJson({
      'Key': 'movie:1',
      'Kind': 'Movie',
      'Title': 'Film',
      'RuntimeMinutes': 100,
      'Current': {'SizeBytes': 9000000000, 'Score': 80, 'Quality': 'HDTV-720p'},
      'Candidates': [
        {
          'Rank': 1,
          'Release': releaseJson(),
          'IsChoice': true,
          'WouldImport': true
        }
      ],
      'Rejected': [
        {'Release': releaseJson(guid: 'g2'), 'Reason': 'TooSmall', 'Detail': '0.57'},
        {'Release': releaseJson(guid: 'g3'), 'Reason': 'Arr', 'Detail': null},
      ],
      'ValidCount': 1,
      'TotalCount': 3,
      'Error': null,
      'ExternalSearchUrl': 'https://mircrew.example/search?q=Film',
    })!;
    expect(search.current!.score, 80);
    expect(search.externalSearchUrl, 'https://mircrew.example/search?q=Film');
    expect(search.candidates.single.isChoice, isTrue);
    expect(search.rejected.first.reason, RejectedReason.tooSmall);
    expect(search.rejected.first.detail, '0.57');
    expect(search.rejected.last.detail, isNull);
    expect((search.validCount, search.totalCount, search.error), (1, 3, null));
  });

  test('EpisodeChoicesParseTolerantly', () {
    Map<String, dynamic> base([Object? choices = 'absent']) => {
          'Key': 'season:1',
          'Kind': 'Season',
          'Title': 'Serie S1',
          'RuntimeMinutes': 45,
          'Current': null,
          'Candidates': [],
          'Rejected': [],
          'ValidCount': 0,
          'TotalCount': 0,
          'Error': null,
          if (choices != 'absent') 'EpisodeChoices': choices,
        };

    // Plugin 1.14.0: il campo manca.
    expect(DownloadSearch.fromJson(base())!.episodeChoices, isEmpty);
    // Plugin più vecchio: niente ExternalSearchUrl, è null.
    expect(DownloadSearch.fromJson(base())!.externalSearchUrl, isNull);

    final choices = DownloadSearch.fromJson(base([
      {'EpisodeNumber': 1, 'Release': releaseJson(guid: 'a'), 'WouldImport': true, 'CurrentScore': 90},
      {'EpisodeNumber': 2, 'Release': null, 'WouldImport': false},
      {'EpisodeNumber': 3, 'Release': releaseJson(size: 'tanti'), 'WouldImport': true},
      {'EpisodeNumber': 'x', 'Release': null, 'WouldImport': false},
      {'EpisodeNumber': 4, 'Release': releaseJson(guid: 'd'), 'WouldImport': false, 'CurrentScore': 'x'},
    ]))!
        .episodeChoices;

    // La release rotta e il numero rotto saltano la riga; "nessuno" resta.
    expect(choices.map((c) => c.episodeNumber), [1, 2, 4]);
    expect(choices[0].release!.guid, 'a');
    // CurrentScore: presente, assente (null o plugin vecchio) e rotto non fanno cadere la riga.
    expect(choices[0].currentScore, 90);
    expect(choices[1].currentScore, isNull);
    expect(choices[2].currentScore, isNull);
    expect(choices[1].release, isNull);
    expect(choices[2].wouldImport, isFalse);
  });

  test('ABrokenRowIsSkipped', () {
    final releases = DownloadRelease.listFromJson([
      releaseJson(guid: 'a'),
      releaseJson(size: 'tanti', guid: 'b'),
      releaseJson(guid: 'c'),
    ]);
    expect(releases.map((r) => r.guid), ['a', 'c']);
    // Anche la riga con una `Release` non valida si salta.
    expect(
        DownloadCandidate.listFromJson([
          {
            'Rank': 1,
            'Release': releaseJson(size: 'tanti'),
            'IsChoice': true,
            'WouldImport': true
          }
        ]),
        isEmpty);
  });

  test('UnknownValuesAreUnknown', () {
    final item = DownloadItem.fromJson({
      'Key': 'movie:1',
      'Kind': 'Boh',
      'Title': 'Film',
      'State': 'Exploded',
      'Reason': 'Mah',
      'AvailableSince': '2026-10-20T00:00:00Z',
    })!;
    expect(item.state, DownloadState.unknown);
    expect(item.kind, DownloadKind.unknown);
    expect(item.reason, DownloadReason.unknown);
    expect(RejectedReason.fromWire('X'), RejectedReason.unknown);
  });

  test('GrabRefusedReason', () {
    expect(DownloadReason.fromWire('GrabRefused'), DownloadReason.grabRefused);
  });

  test('ActionsSummaryAndBlockedMessageAreRead', () {
    final item = DownloadItem.fromJson({
      'Key': 'movie:1',
      'Kind': 'Movie',
      'Title': 'Film',
      'State': 'NeedsYou',
      'AvailableSince': '2026-10-20T00:00:00Z',
      'Actions': ['GrabBest', 'Nuova', 'Pick', 'Import', 'ExternalSearch'],
      'ExternalSearchUrl': 'https://mircrew.example/search?q=Film',
      'Summary': {
        'Found': 5,
        'BestScore': 90,
        'MinScore': 100,
        'TooSmall': 1,
        'ArrRejected': 2,
        'TopRejection': 'Not enough seeders',
        'StopgapAvailable': true,
      },
      'BlockedMessage': 'Bloccato',
      'Snoozed': true,
    })!;
    expect(item.actions, [
      DownloadAction.grabBest,
      DownloadAction.pick,
      DownloadAction.import,
      DownloadAction.externalSearch,
    ]);
    expect(item.externalSearchUrl, 'https://mircrew.example/search?q=Film');
    expect(item.summary!.found, 5);
    expect(item.summary!.bestScore, 90);
    expect(item.summary!.minScore, 100);
    expect(item.summary!.tooSmall, 1);
    expect(item.summary!.arrRejected, 2);
    expect(item.summary!.topRejection, 'Not enough seeders');
    expect(item.summary!.stopgapAvailable, isTrue);
    expect(item.blockedMessage, 'Bloccato');
    expect(item.snoozed, isTrue);
  });

  test('AnItemFromPlugin117HasNoActions', () {
    final item = DownloadItem.fromJson({
      'Key': 'movie:1',
      'Kind': 'Movie',
      'Title': 'Film',
      'State': 'Waiting',
      'AvailableSince': '2026-10-20T00:00:00Z',
    })!;
    expect(item.actions, isEmpty);
    expect(item.summary, isNull);
    expect(item.blockedMessage, isNull);
    expect(item.snoozed, isFalse);
    expect(item.externalSearchUrl, isNull);
  });

  group('SearchPhase', () {
    Map<String, dynamic> json([Object? phase = _absent]) => {
          'Key': 'movie:1',
          'Kind': 'Movie',
          'Title': 'Film',
          'State': 'Waiting',
          'AvailableSince': '2026-10-20T00:00:00Z',
          if (!identical(phase, _absent)) 'SearchPhase': phase,
        };

    test('KnownPhasesAreParsed', () {
      expect(DownloadItem.fromJson(json('Queued'))!.searchPhase,
          DownloadSearchPhase.queued);
      expect(DownloadItem.fromJson(json('Searching'))!.searchPhase,
          DownloadSearchPhase.searching);
    });

    test('UnknownNullOrAbsentIsNull', () {
      expect(DownloadItem.fromJson(json('Boh'))!.searchPhase, isNull);
      expect(DownloadItem.fromJson(json(null))!.searchPhase, isNull);
      expect(DownloadItem.fromJson(json())!.searchPhase, isNull);
    });
  });

  group('Progress', () {
    Map<String, dynamic> json([Object? progress = _absent]) => {
          'Key': 'movie:1',
          'Kind': 'Movie',
          'Title': 'Film',
          'State': 'Downloading',
          'AvailableSince': '2026-10-20T00:00:00Z',
          if (!identical(progress, _absent)) 'Progress': progress,
        };

    test('AProgressIsParsed', () {
      final p = DownloadItem.fromJson(json({
        'SizeBytes': 3100000000,
        'SizeLeftBytes': 1178000000,
        'EstimatedCompletion': '2026-11-01T10:25:00Z',
        'Status': 'downloading',
      }))!
          .progress!;
      expect(p.sizeBytes, 3100000000);
      expect(p.sizeLeftBytes, 1178000000);
      expect(p.estimatedCompletion, DateTime.utc(2026, 11, 1, 10, 25));
      expect(p.status, 'downloading');
      expect(p.fraction, closeTo(0.62, 0.001));
    });

    test('AMalformedProgressIsNullAndTheItemSurvives', () {
      for (final bad in [
        {'SizeBytes': 'x', 'SizeLeftBytes': 1, 'Status': 'queued'},
        {'SizeBytes': 10, 'SizeLeftBytes': 1},
        {'SizeBytes': 10, 'SizeLeftBytes': 1, 'Status': 'queued',
         'EstimatedCompletion': 'non una data'},
        'testo',
      ]) {
        final item = DownloadItem.fromJson(json(bad));
        expect(item, isNotNull);
        expect(item!.progress, isNull);
      }
    });

    test('MissingOrNullProgressIsNull', () {
      expect(DownloadItem.fromJson(json())!.progress, isNull);
      expect(DownloadItem.fromJson(json(null))!.progress, isNull);
    });

    test('SinceIsParsedAndTolerant', () {
      Map<String, dynamic> raw(Object? since) => {
            'SizeBytes': 0,
            'SizeLeftBytes': 0,
            'Status': 'metadata',
            'Since': since,
          };
      expect(DownloadProgress.fromJson(raw('2026-11-01T08:00:00Z'))!.since,
          DateTime.utc(2026, 11, 1, 8));
      expect(DownloadProgress.fromJson(raw(null))!.since, isNull);
      expect(DownloadProgress.fromJson(raw('boh')), isNull);
    });

    test('TheFractionIsClamped', () {
      DownloadProgress p(int size, int left) => DownloadProgress(
          sizeBytes: size, sizeLeftBytes: left, status: 'downloading');
      expect(p(0, 0).fraction, 0);
      expect(p(100, 150).fraction, 0);
      expect(p(100, -5).fraction, 1);
    });
  });
}

const _absent = Object();
