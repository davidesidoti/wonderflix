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
    expect(overview.review.single.quality, 'SDTV');
    expect((overview.sonarrError, overview.radarrError), (null, 'Unreachable'));
    expect(DownloadsOverview.empty.waiting, isEmpty);
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
    })!;
    expect(search.current!.score, 80);
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
}
