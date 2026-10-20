/// Modelli dei voti degli amici (spec Q §6), come li manda il plugin.
library;

import '../jellyfin/json_fields.dart';

/// Un `Comment` vuoto o assente vale `null`.
String? _comment(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

DateTime _date(Object? raw) => DateTime.parse(raw as String).toUtc();

/// Fase della votazione di fine party.
enum RatingPhase {
  voting('Voting'),
  revealed('Revealed');

  const RatingPhase(this.wire);

  final String wire;

  /// Un valore sconosciuto vale `revealed`: una votazione che non capiamo non
  /// deve fermare la coda.
  static RatingPhase fromWire(Object? value) =>
      value == voting.wire ? voting : revealed;
}

/// Cosa ha fatto un presente nella votazione.
enum RatingVoterStatus {
  waiting('Waiting'),
  voted('Voted'),
  skipped('Skipped');

  const RatingVoterStatus(this.wire);

  final String wire;

  /// Un valore sconosciuto vale `waiting`.
  static RatingVoterStatus fromWire(Object? value) => values
      .firstWhere((s) => s.wire == value, orElse: () => RatingVoterStatus.waiting);
}

/// Il voto di chi guarda.
class MyRating {
  const MyRating({required this.score, this.comment});

  factory MyRating.fromJson(Map<String, dynamic> json) => MyRating(
        score: (json['Score'] as num).toInt(),
        comment: _comment(json['Comment']),
      );

  final int score;
  final String? comment;
}

/// Un presente nella votazione e il suo stato (mai il voto).
class RatingVoter {
  const RatingVoter(
      {required this.userId, required this.name, required this.status});

  factory RatingVoter.fromJson(Map<String, dynamic> json) => RatingVoter(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        status: RatingVoterStatus.fromWire(json['Status']),
      );

  final String userId;
  final String name;
  final RatingVoterStatus status;
}

/// Un voto scoperto, solo in `Revealed`.
class RatingResult {
  const RatingResult({
    required this.userId,
    required this.name,
    required this.score,
    this.comment,
  });

  factory RatingResult.fromJson(Map<String, dynamic> json) => RatingResult(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        score: (json['Score'] as num).toInt(),
        comment: _comment(json['Comment']),
      );

  final String userId;
  final String name;
  final int score;
  final String? comment;
}

/// Lo stato della votazione di fine party visto da chi guarda.
class RatingRound {
  const RatingRound({
    required this.groupId,
    required this.itemId,
    required this.phase,
    required this.rev,
    required this.endsAt,
    required this.canReveal,
    this.mine,
    this.voters = const [],
    this.results = const [],
    this.average,
  });

  factory RatingRound.fromJson(Map<String, dynamic> json) => RatingRound(
        groupId: json['GroupId'] as String,
        itemId: json['ItemId'] as String,
        phase: RatingPhase.fromWire(json['Phase']),
        rev: (json['Rev'] as num).toInt(),
        endsAt: _date(json['EndsAt']),
        canReveal: json['CanReveal'] as bool? ?? false,
        mine: json['Mine'] is Map<String, dynamic>
            ? MyRating.fromJson(json['Mine'] as Map<String, dynamic>)
            : null,
        voters: [
          for (final raw in json['Voters'] as List? ?? const [])
            RatingVoter.fromJson(raw as Map<String, dynamic>),
        ],
        results: [
          for (final raw in json['Results'] as List? ?? const [])
            RatingResult.fromJson(raw as Map<String, dynamic>),
        ],
        average: (json['Average'] as num?)?.toDouble(),
      );

  final String groupId;
  final String itemId;
  final RatingPhase phase;

  /// Cresce a ogni cambio di stato dentro la stessa votazione.
  final int rev;

  /// In UTC: quando i voti si scoprono da soli.
  final DateTime endsAt;

  /// Chi guarda è il creatore e la fase è `voting`.
  final bool canReveal;
  final MyRating? mine;
  final List<RatingVoter> voters;

  /// Solo in `revealed`.
  final List<RatingResult> results;

  /// Solo in `revealed`.
  final double? average;

  /// Il presente [userId] (id confrontati senza trattini).
  RatingVoter? voter(String userId) {
    final key = jellyfinIdKey(userId);
    for (final voter in voters) {
      if (jellyfinIdKey(voter.userId) == key) return voter;
    }
    return null;
  }

  int get votedCount =>
      voters.where((v) => v.status == RatingVoterStatus.voted).length;
}

/// Il voto di un amico nella scheda.
class FriendRating {
  const FriendRating({
    required this.userId,
    required this.name,
    required this.score,
    required this.updatedAt,
    this.comment,
  });

  factory FriendRating.fromJson(Map<String, dynamic> json) => FriendRating(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        score: (json['Score'] as num).toInt(),
        comment: _comment(json['Comment']),
        updatedAt: _date(json['UpdatedAt']),
      );

  final String userId;
  final String name;
  final int score;
  final String? comment;

  /// In UTC.
  final DateTime updatedAt;
}

/// `GET Ratings`: la scheda di un titolo.
class ItemRatings {
  const ItemRatings({
    required this.canRate,
    required this.count,
    required this.friends,
    this.mine,
    this.average,
  });

  factory ItemRatings.fromJson(Map<String, dynamic> json) => ItemRatings(
        canRate: json['CanRate'] as bool? ?? false,
        mine: json['Mine'] is Map<String, dynamic>
            ? MyRating.fromJson(json['Mine'] as Map<String, dynamic>)
            : null,
        average: (json['Average'] as num?)?.toDouble(),
        count: (json['Count'] as num?)?.toInt() ?? 0,
        friends: [
          for (final raw in json['Friends'] as List? ?? const [])
            FriendRating.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final bool canRate;
  final MyRating? mine;
  final double? average;
  final int count;
  final List<FriendRating> friends;
}

/// Un commento nell'elenco admin.
class AdminComment {
  const AdminComment({
    required this.userId,
    required this.userName,
    required this.itemId,
    required this.title,
    required this.score,
    required this.comment,
    required this.updatedAt,
  });

  factory AdminComment.fromJson(Map<String, dynamic> json) => AdminComment(
        userId: json['UserId'] as String,
        userName: json['UserName'] as String,
        itemId: json['ItemId'] as String,
        title: json['Title'] as String,
        score: (json['Score'] as num).toInt(),
        comment: json['Comment'] as String? ?? '',
        updatedAt: _date(json['UpdatedAt']),
      );

  final String userId;
  final String userName;
  final String itemId;
  final String title;
  final int score;
  final String comment;

  /// In UTC.
  final DateTime updatedAt;
}

/// Una pagina di commenti admin.
class AdminCommentsPage {
  const AdminCommentsPage({required this.items, this.next});

  factory AdminCommentsPage.fromJson(Map<String, dynamic> json) =>
      AdminCommentsPage(
        items: [
          for (final raw in json['Items'] as List? ?? const [])
            AdminComment.fromJson(raw as Map<String, dynamic>),
        ],
        next: json['Next'] as String?,
      );

  final List<AdminComment> items;

  /// Da passare come `before` per la pagina dopo; `null` a fine elenco.
  final String? next;
}
