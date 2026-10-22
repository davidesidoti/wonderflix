import 'dart:convert';

import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/rating_models.dart';

/// Il JSON di una votazione, come lo manda il plugin: Mario (`u1`) e Luigi
/// (`u2`) in attesa, `Voting`, scade alle 21:02 UTC.
Map<String, dynamic> ratingRoundJson({
  String groupId = 'g1',
  String itemId = 's1',
  String phase = 'Voting',
  int rev = 1,
  bool canReveal = false,
  Map<String, dynamic>? mine,
  List<Map<String, dynamic>>? voters,
  List<Map<String, dynamic>>? results,
  num? average,
  String endsAt = '2026-10-20T21:02:00Z',
}) =>
    {
      'GroupId': groupId,
      'ItemId': itemId,
      'Phase': phase,
      'Rev': rev,
      'EndsAt': endsAt,
      'CanReveal': canReveal,
      'Mine': ?mine,
      'Voters': voters ??
          [
            {'UserId': 'u1', 'Name': 'Mario', 'Status': 'Waiting'},
            {'UserId': 'u2', 'Name': 'Luigi', 'Status': 'Waiting'},
          ],
      'Results': ?results,
      'Average': ?average,
    };

/// Una [RatingRound] di prova (stessi parametri di [ratingRoundJson]).
RatingRound testRatingRound({
  String groupId = 'g1',
  String itemId = 's1',
  String phase = 'Voting',
  int rev = 1,
  bool canReveal = false,
  Map<String, dynamic>? mine,
  List<Map<String, dynamic>>? voters,
  List<Map<String, dynamic>>? results,
  num? average,
  String endsAt = '2026-10-20T21:02:00Z',
}) =>
    RatingRound.fromJson(ratingRoundJson(
      groupId: groupId,
      itemId: itemId,
      phase: phase,
      rev: rev,
      canReveal: canReveal,
      mine: mine,
      voters: voters,
      results: results,
      average: average,
      endsAt: endsAt,
    ));

/// Come arriva dal WebSocket l'avviso di una votazione.
PartyChannelReceived ratingRoundUpdatedReceived(Map<String, dynamic> state) =>
    PartyChannelReceived(jsonEncode(
        {'Protocol': 1, 'Type': 'RatingRoundUpdated', 'State': state}));

/// I voti di una scheda: per default si può votare, nessun voto.
ItemRatings testItemRatings({
  bool canRate = true,
  MyRating? mine,
  double? average,
  int count = 0,
  List<FriendRating> friends = const [],
}) =>
    ItemRatings(
      canRate: canRate,
      mine: mine,
      average: average,
      count: count,
      friends: friends,
    );

FriendRating testFriendRating(String userId, String name, int score,
        {String? comment}) =>
    FriendRating(
      userId: userId,
      name: name,
      score: score,
      comment: comment,
      updatedAt: DateTime.utc(2026, 10, 19, 20),
    );
