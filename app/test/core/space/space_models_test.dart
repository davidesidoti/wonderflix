import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/space/space_models.dart';

Map<String, dynamic> _candidate({Object? size = 1000, String key = 'movie:1'}) =>
    {
      'Key': key,
      'Kind': 'Movie',
      'Title': 'Film',
      'Year': 1999,
      'SeasonNumber': null,
      'SeriesKey': null,
      'ItemId': 'abc',
      'PosterUrl': '/p.jpg',
      'SizeBytes': size,
      'FreeNowBytes': 900,
      'FreeLaterBytes': 100,
      'FreeLaterAt': '2026-11-02T10:00:00Z',
      'InPackBytes': 0,
      'Via': ['NobodyWatching'],
      'Keep': <String>[],
      'Viewers': [
        {'Name': 'Anna', 'Finished': true, 'LastPlayed': '2026-10-01T10:00:00Z'},
      ],
      'Requests': [
        {'Name': 'Bob', 'At': '2026-09-01T10:00:00Z'},
      ],
      'RatingAvg': 7.5,
      'RatingCount': 2,
      'LastOpened': null,
      'Added': '2026-01-01T00:00:00Z',
      'Genres': ['Dramma'],
    };

Map<String, dynamic> _overview({List<Object?>? delete, Object? quota}) => {
      'ScannedAt': '2026-10-30T08:00:00Z',
      'Scanning': false,
      'Quota': quota,
      'Breakdown': {
        'MoviesBytes': 1,
        'SeriesBytes': 2,
        'AnimeBytes': 3,
        'TorrentOnlyBytes': 4,
        'OtherBytes': 5,
      },
      'Delete': delete ?? [_candidate()],
      'Lighten': [
        {
          'Key': 'movie:2',
          'Kind': 'Movie',
          'Title': 'Pesante',
          'SeasonNumber': null,
          'ItemId': null,
          'PosterUrl': null,
          'SizeBytes': 9000,
          'ExcessBytes': 4000,
          'GbPerHour': 12.5,
        },
      ],
      'Cleanup': {
        'Torrents': [
          {
            'Key': 't:h1',
            'Hash': 'h1',
            'Name': 'Torrent',
            'Tracker': 'tr.example',
            'SizeBytes': 50,
            'Ratio': 1.5,
            'SeedingDays': 3,
            'CanRemoveNow': false,
            'ExpectedAt': '2026-11-05T00:00:00Z',
          },
        ],
        'Orphans': [
          {'Key': 'f:1', 'Path': '/a/b.mkv', 'SizeBytes': 70, 'Linked': true},
        ],
        'Duplicates': <Object?>[],
      },
      'Pending': [
        {
          'Hash': 'h2',
          'Name': 'N',
          'Tracker': 'tr',
          'SizeBytes': 5,
          'ExpectedAt': null,
          'Title': 'T',
        },
      ],
      'Kept': [
        {'Key': 'movie:9', 'Title': 'Tenuto'},
      ],
      'Operations': [
        {
          'Id': 'op1',
          'Kind': 'Delete',
          'Key': 'movie:1',
          'Title': 'Film',
          'State': 'Running',
          'Auto': false,
          'StartedAt': '2026-10-30T09:00:00Z',
          'EndedAt': null,
          'EstimatedFreedBytes': 900,
          'PendingBytes': 100,
          'QuotaBeforeBytes': 5000,
          'QuotaAfterBytes': null,
          'Steps': [
            {'Name': 'Radarr', 'State': 'Done', 'Detail': null, 'Done': null, 'Waiting': null},
            {'Name': 'Torrent', 'State': 'Waiting', 'Detail': 'seed', 'Done': 1, 'Waiting': 2},
          ],
        },
      ],
      'TopGenres': ['Dramma'],
      'Errors': {
        'Radarr': null,
        'Sonarr': 'Unreachable',
        'Qbit': null,
        'Seerr': null,
        'Quota': null,
      },
    };

void main() {
  test('AFullOverviewIsRead', () {
    final o = SpaceOverview.fromJson(
        _overview(quota: {'UsedBytes': 10, 'LimitBytes': 100}))!;
    expect(o.scannedAt, DateTime.utc(2026, 10, 30, 8));
    expect(o.quota!.limitBytes, 100);
    expect(o.breakdown.otherBytes, 5);

    final c = o.delete.single;
    expect((c.key, c.kind, c.title, c.year), ('movie:1', 'Movie', 'Film', 1999));
    expect(c.seasonNumber, isNull);
    expect((c.itemId, c.posterUrl), ('abc', '/p.jpg'));
    expect((c.sizeBytes, c.freeNowBytes, c.freeLaterBytes, c.inPackBytes),
        (1000, 900, 100, 0));
    expect(c.freeLaterAt, DateTime.utc(2026, 11, 2, 10));
    expect(c.via, ['NobodyWatching']);
    expect(c.viewers.single.name, 'Anna');
    expect(c.viewers.single.finished, isTrue);
    expect(c.viewers.single.lastPlayed, DateTime.utc(2026, 10, 1, 10));
    expect(c.requests.single.name, 'Bob');
    expect((c.ratingAvg, c.ratingCount), (7.5, 2));
    expect(c.lastOpened, isNull);
    expect(c.added, DateTime.utc(2026));
    expect(c.genres, ['Dramma']);

    final l = o.lighten.single;
    expect((l.key, l.sizeBytes, l.excessBytes, l.gbPerHour),
        ('movie:2', 9000, 4000, 12.5));

    final t = o.cleanup.torrents.single;
    expect((t.hash, t.tracker, t.ratio, t.seedingDays, t.canRemoveNow),
        ('h1', 'tr.example', 1.5, 3.0, false));
    expect(t.expectedAt, DateTime.utc(2026, 11, 5));
    final f = o.cleanup.orphans.single;
    expect((f.path, f.sizeBytes, f.linked), ('/a/b.mkv', 70, true));
    expect(o.cleanup.duplicates, isEmpty);
    expect(o.pending.single.hash, 'h2');
    expect(o.kept.single.title, 'Tenuto');

    final op = o.operations.single;
    expect(op.running, isTrue);
    expect((op.id, op.kind, op.auto), ('op1', 'Delete', false));
    expect((op.quotaBeforeBytes, op.quotaAfterBytes), (5000, null));
    expect(op.steps.map((s) => s.name), ['Radarr', 'Torrent']);
    expect((op.steps[1].detail, op.steps[1].done, op.steps[1].waiting),
        ('seed', 1, 2));
    expect(o.topGenres, ['Dramma']);
    expect((o.errors.sonarr, o.errors.radarr), ('Unreachable', null));
  });

  test('ABrokenRowIsSkipped', () {
    final o = SpaceOverview.fromJson(_overview(delete: [
      _candidate(size: 'tanto', key: 'movie:1'),
      _candidate(key: 'movie:2'),
    ]))!;
    expect(o.delete.map((c) => c.key), ['movie:2']);
  });

  test('NullsAreAccepted', () {
    final json = _overview()..['ScannedAt'] = null;
    final o = SpaceOverview.fromJson(json)!;
    expect(o.quota, isNull);
    expect(o.scannedAt, isNull);
  });

  test('AWrongShapeIsNull', () {
    expect(SpaceOverview.fromJson('boh'), isNull);
    expect(SpaceOverview.fromJson(_overview()..remove('Breakdown')), isNull);
  });
}
