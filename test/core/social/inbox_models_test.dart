import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/inbox_models.dart';

import '../../support/social_fakes.dart';

void main() {
  test('voci della cassetta: invito, annuncio; i tipi sconosciuti si saltano',
      () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 3,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00.1234567+00:00',
          'Read': false,
          'GroupId': 'g1',
          'FromName': 'Luigi',
          'Title': 'Dune',
          'ImageItemId': 'm1',
        },
        {
          'Id': 'n1',
          'Seq': 2,
          'Type': 'Reminder',
          'CreatedAt': '2026-10-03T19:00:00+00:00',
          'Read': false,
        },
        {
          'Id': 'a1',
          'Seq': 1,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+02:00',
          'Read': true,
          'Text': 'Stasera manutenzione',
        },
      ],
      'Unread': 2,
    });

    expect(snapshot.entries, hasLength(2));
    // Il `Unread: 2` del server conta anche la voce di tipo sconosciuto, che
    // l'app non mostra e non può segnare letta: vale solo l'invito.
    expect(snapshot.unread, 1);
    expect(snapshot.maxSeq, 3);
    final invite = snapshot.entries.first as InviteEntry;
    expect(invite.id, 'i1');
    expect(invite.seq, 3);
    expect(invite.read, isFalse);
    expect(invite.groupId, 'g1');
    expect(invite.fromName, 'Luigi');
    expect(invite.title, 'Dune');
    expect(invite.imageItemId, 'm1');
    expect(invite.createdAt, DateTime.utc(2026, 10, 3, 20, 0, 0, 123, 456));
    final announcement = snapshot.entries.last as AnnouncementEntry;
    expect(announcement.text, 'Stasera manutenzione');
    expect(announcement.read, isTrue);
    expect(announcement.createdAt, DateTime.utc(2026, 10, 3, 16));
  });

  test('una voce malformata si salta, le altre restano', () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 3,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'GroupId': 'g1',
          'FromName': 'Luigi',
        },
        {
          'Id': 'a0',
          'Seq': 2,
          'Type': 'Announcement',
          'CreatedAt': 'non una data',
          'Text': 'Stasera manutenzione',
        },
        {
          'Id': 'a2',
          'Seq': 4,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+00:00',
          'Text': 7,
        },
        {
          'Id': 'a1',
          'Seq': 1,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+00:00',
          'Text': 'Stasera manutenzione',
        },
      ],
      'Unread': 4,
    });

    expect(snapshot.entries.map((e) => e.id), ['a1']);
    expect(snapshot.unread, 1);
    expect(snapshot.maxSeq, 1);
  });

  test('cassetta vuota; invito senza locandina', () {
    expect(InboxSnapshot.fromJson(const {}).entries, isEmpty);
    expect(InboxSnapshot.fromJson(const {}).unread, 0);
    expect(InboxSnapshot.empty.maxSeq, 0);
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 1,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'GroupId': 'g1',
          'FromName': 'Luigi',
          'Title': 'Dune',
        },
      ],
      'Unread': 1,
    });
    final invite = snapshot.entries.single as InviteEntry;
    expect(invite.imageItemId, isNull);
    expect(invite.read, isFalse);
  });

  test('tutto letto; senza una voce', () {
    final snapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);

    expect(snapshot.markedRead().unread, 0);
    expect(snapshot.markedRead().entries, hasLength(2));
    final without = snapshot.without('i1');
    expect(without.entries.map((e) => e.id), ['a1']);
    expect(without.unread, 0);
    expect(snapshot.without('a1').unread, 1);
    expect(identical(snapshot.without('x'), snapshot), isTrue);
  });

  test('film, serie ed episodi nuovi dal JSON', () {
    final movie = NewTitleMovie.fromJson(
        const {'ItemId': 'm1', 'Name': 'Dune', 'Year': 2024});
    expect((movie.itemId, movie.name, movie.year), ('m1', 'Dune', 2024));
    expect(NewTitleMovie.fromJson(const {'ItemId': 'm2', 'Name': 'X'}).year,
        isNull);
    final series = NewTitleSeries.fromJson(const {
      'SeriesId': 's1',
      'Name': 'The Bear',
      'Episodes': [
        {'Season': 3, 'Episode': 1},
        <String, dynamic>{},
      ],
    });
    expect(series.seriesId, 's1');
    expect(series.name, 'The Bear');
    expect(series.episodes.first.season, 3);
    expect(series.episodes.first.episode, 1);
    expect(series.episodes.last.season, isNull);
    expect(
        NewTitleSeries.fromJson(const {'SeriesId': 's2', 'Name': 'Y'})
            .episodes,
        isEmpty);
  });

  test('episodi in intervalli', () {
    List<NewTitleEpisode> episodes(List<(int, int)> list) => [
          for (final (season, episode) in list)
            NewTitleEpisode(season: season, episode: episode),
        ];
    expect(
        formatEpisodeRanges(episodes([for (var e = 1; e <= 10; e++) (3, e)])),
        'S3 E1–E10');
    expect(
        formatEpisodeRanges(
            episodes([(3, 6), (3, 1), (3, 2), (3, 3), (3, 4)])),
        'S3 E1–E4, E6');
    expect(formatEpisodeRanges(episodes([(3, 1), (2, 10), (3, 3), (3, 2)])),
        'S2 E10 · S3 E1–E3');
    expect(formatEpisodeRanges(episodes([(1, 5)])), 'S1 E5');
    expect(formatEpisodeRanges(episodes([(1, 5), (1, 5)])), 'S1 E5',
        reason: 'doppioni');
    expect(
        formatEpisodeRanges(const [
          NewTitleEpisode(season: 1, episode: 1),
          NewTitleEpisode(season: 1),
        ]),
        isNull,
        reason: 'basta un numero mancante');
    expect(formatEpisodeRanges(const []), isNull);
  });

  test('voce delle novità', () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'n1',
          'Seq': 2,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-04T20:00:00+00:00',
          'Read': false,
          'Movies': [
            {'ItemId': 'm1', 'Name': 'Dune', 'Year': 2024},
          ],
          'Series': [
            {
              'SeriesId': 's1',
              'Name': 'The Bear',
              'Episodes': [
                {'Season': 3, 'Episode': 1},
                {'Season': 3, 'Episode': 2},
              ],
            },
          ],
          'More': 4,
        },
        {
          'Id': 'n2',
          'Seq': 1,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'Read': true,
        },
      ],
    });

    final first = snapshot.entries.first as NewTitlesEntry;
    expect(first.movies.single.name, 'Dune');
    expect(first.series.single.episodes, hasLength(2));
    expect(first.episodeCount, 2);
    expect(first.more, 4);
    final second = snapshot.entries.last as NewTitlesEntry;
    expect(second.movies, isEmpty);
    expect(second.series, isEmpty);
    expect(second.more, 0);
    expect(snapshot.unread, 1);
  });

  test('una voce delle novità malformata si salta, la valida resta', () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'n1',
          'Seq': 3,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-04T20:00:00+00:00',
          'Movies': [
            {'ItemId': 'm1', 'Name': 'Dune'},
          ],
        },
        {
          'Id': 'n2',
          'Seq': 2,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-04T19:00:00+00:00',
          'Movies': [
            {'ItemId': 'm2'},
          ],
        },
        {
          'Id': 'n3',
          'Seq': 1,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-04T18:00:00+00:00',
          'Movies': 'non una lista',
        },
      ],
    });

    expect(snapshot.entries.map((e) => e.id), ['n1']);
    expect((snapshot.entries.single as NewTitlesEntry).movies.single.name,
        'Dune');
  });

  test('voci delle richieste', () {
    final available = inboxEntryFromJson({
      'Id': 'r1',
      'Seq': 3,
      'Type': 'RequestAvailable',
      'CreatedAt': '2026-10-05T12:00:00+00:00',
      'Read': false,
      'RequestId': 53,
      'MediaType': 'tv',
      'TmdbId': 250203,
      'Title': 'Brothers (2026)',
      'Seasons': [1, 2],
      'ItemId': '6d1c8ea33a794f76fdbe92a216959073',
    }) as RequestAvailableEntry;
    expect(available.title, 'Brothers (2026)');
    expect(available.seasons, [1, 2]);
    expect(available.itemId, '6d1c8ea33a794f76fdbe92a216959073');

    final pending = inboxEntryFromJson({
      'Id': 'r2',
      'Seq': 4,
      'Type': 'RequestPending',
      'CreatedAt': '2026-10-05T12:00:00+00:00',
      'Read': true,
      'RequestId': 54,
      'MediaType': 'movie',
      'TmdbId': 438631,
      'Title': 'Dune (2021)',
      'RequesterName': 'Garg',
    }) as RequestPendingEntry;
    expect(pending.title, 'Dune (2021)');
    expect(pending.requesterName, 'Garg');
    expect(pending.seasons, isEmpty);
    expect(pending.read, isTrue);
  });
}
