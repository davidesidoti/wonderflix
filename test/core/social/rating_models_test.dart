import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/rating_models.dart';

import '../../support/rating_fakes.dart';

void main() {
  test('una votazione scoperta', () {
    final round = RatingRound.fromJson(ratingRoundJson(
      phase: 'Revealed',
      rev: 3,
      endsAt: '2026-10-20T21:02:00Z',
      mine: {'Score': 8},
      voters: [
        {'UserId': 'u1', 'Name': 'Mario', 'Status': 'Voted'},
        {'UserId': 'u2', 'Name': 'Luigi', 'Status': 'Skipped'},
        {'UserId': 'u3', 'Name': 'Peach', 'Status': 'Waiting'},
      ],
      results: [
        {'UserId': 'u1', 'Name': 'Mario', 'Score': 9, 'Comment': 'Capolavoro'},
        {'UserId': 'u2', 'Name': 'Luigi', 'Score': 6, 'Comment': ''},
      ],
      average: 7.5,
    ));
    expect(round.phase, RatingPhase.revealed);
    expect(round.rev, 3);
    expect(round.endsAt.isUtc, isTrue);
    expect(round.endsAt, DateTime.utc(2026, 10, 20, 21, 2));
    expect(round.mine!.score, 8);
    expect(round.mine!.comment, isNull);
    expect(round.voters.map((v) => v.status), [
      RatingVoterStatus.voted,
      RatingVoterStatus.skipped,
      RatingVoterStatus.waiting,
    ]);
    expect(round.results[0].comment, 'Capolavoro');
    expect(round.results[1].comment, isNull);
    expect(round.average, 7.5);
    expect(round.votedCount, 1);
  });

  test('in Voting senza Results né Average', () {
    final round = testRatingRound();
    expect(round.phase, RatingPhase.voting);
    expect(round.results, isEmpty);
    expect(round.average, isNull);
    expect(round.mine, isNull);
    expect(testRatingRound(phase: 'Boh').phase, RatingPhase.revealed);
    expect(
        testRatingRound(voters: [
          {'UserId': 'u1', 'Name': 'Mario', 'Status': 'Boh'},
        ]).voters.single.status,
        RatingVoterStatus.waiting);
    expect(round.voter('U-1')?.name, 'Mario');
    expect(round.voter('u9'), isNull);
  });

  test('voti della scheda', () {
    final ratings = ItemRatings.fromJson({
      'CanRate': true,
      'Mine': {'Score': 7, 'Comment': 'Bello'},
      'Count': 2,
      'Average': 7.7,
      'Friends': [
        {
          'UserId': 'u2',
          'Name': 'Luigi',
          'Score': 8,
          'Comment': 'Ottimo',
          'UpdatedAt': '2026-10-19T20:00:00+02:00',
        },
        {
          'UserId': 'u3',
          'Name': 'Peach',
          'Score': 7,
          'UpdatedAt': '2026-10-18T20:00:00Z',
        },
      ],
    });
    expect(ratings.canRate, isTrue);
    expect(ratings.mine!.comment, 'Bello');
    expect(ratings.count, 2);
    expect(ratings.average, 7.7);
    expect(ratings.friends.first.comment, 'Ottimo');
    expect(ratings.friends.first.updatedAt.isUtc, isTrue);
    expect(ratings.friends.first.updatedAt, DateTime.utc(2026, 10, 19, 18));
    expect(ratings.friends.last.comment, isNull);

    final empty = ItemRatings.fromJson(
        {'CanRate': false, 'Count': 0, 'Friends': <Object>[]});
    expect(empty.mine, isNull);
    expect(empty.average, isNull);
  });

  test('pagina dei commenti', () {
    Map<String, dynamic> item(String user) => {
          'UserId': user,
          'UserName': 'Mario',
          'ItemId': 'm1',
          'Title': 'Dune (2021)',
          'Score': 9,
          'Comment': 'Bello',
          'UpdatedAt': '2026-10-19T10:00:00Z',
        };
    final page = AdminCommentsPage.fromJson({
      'Items': [item('u1'), item('u2')],
      'Next': '2026-10-19T10:00:00Z',
    });
    expect(page.items, hasLength(2));
    expect(page.items.first.title, 'Dune (2021)');
    expect(page.items.first.updatedAt, DateTime.utc(2026, 10, 19, 10));
    expect(page.next, '2026-10-19T10:00:00Z');
    expect(
        AdminCommentsPage.fromJson({
          'Items': [item('u1')],
        }).next,
        isNull);
  });
}
