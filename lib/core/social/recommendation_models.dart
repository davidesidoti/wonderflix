/// Modelli dei consigli tra amici (spec N §6.2), come li manda il plugin.
library;

/// Un amico nel pannello "Consiglia a…": spento se non può vedere il titolo.
class RecommendationTarget {
  const RecommendationTarget({
    required this.userId,
    required this.name,
    required this.online,
    required this.canSee,
  });

  factory RecommendationTarget.fromJson(Map<String, dynamic> json) =>
      RecommendationTarget(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        online: json['Online'] as bool? ?? false,
        canSee: json['CanSee'] as bool? ?? false,
      );

  final String userId;
  final String name;
  final bool online;
  final bool canSee;
}

/// Chi ha consigliato un titolo, con il suo messaggio (`null` se nessuno).
class RecommendationSender {
  const RecommendationSender({
    required this.userId,
    required this.name,
    required this.createdAt,
    this.message,
  });

  factory RecommendationSender.fromJson(Map<String, dynamic> json) {
    final message = json['Message'] as String?;
    return RecommendationSender(
      userId: json['UserId'] as String,
      name: json['Name'] as String,
      message: message == null || message.isEmpty ? null : message,
      createdAt: DateTime.parse(json['CreatedAt'] as String).toUtc(),
    );
  }

  final String userId;
  final String name;
  final String? message;

  /// In UTC.
  final DateTime createdAt;
}

/// Un titolo consigliato all'utente, con i mittenti dal più recente.
class Recommendation {
  const Recommendation({required this.itemId, required this.from});

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        itemId: json['ItemId'] as String,
        from: [
          for (final raw in json['From'] as List? ?? const [])
            RecommendationSender.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String itemId;
  final List<RecommendationSender> from;
}
