/// Modelli di "cosa guardano gli amici" (spec O §6.5, §6.6), come li manda
/// il plugin.
library;

/// Dove è arrivato un amico, per "Guarda insieme" (spec O §6.5).
class FriendPosition {
  const FriendPosition({required this.itemId, required this.position});

  factory FriendPosition.fromJson(Map<String, dynamic> json) => FriendPosition(
        itemId: json['ItemId'] as String,
        // Un tick di Jellyfin è 100 ns (piano 21b, decisione 2).
        position: Duration(
            microseconds: (json['PositionTicks'] as num? ?? 0).toInt() ~/ 10),
      );

  final String itemId;
  final Duration position;
}

/// Un amico che ha visto un titolo della riga, e quando l'ultima volta.
class FriendWatcher {
  const FriendWatcher({
    required this.userId,
    required this.name,
    required this.watchedAt,
  });

  factory FriendWatcher.fromJson(Map<String, dynamic> json) => FriendWatcher(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        watchedAt: DateTime.parse(json['WatchedAt'] as String).toUtc(),
      );

  final String userId;
  final String name;

  /// In UTC.
  final DateTime watchedAt;
}

/// Un titolo di "Visti dagli amici", con chi l'ha visto dal più recente.
class FriendsWatched {
  const FriendsWatched({required this.itemId, required this.by});

  factory FriendsWatched.fromJson(Map<String, dynamic> json) => FriendsWatched(
        itemId: json['ItemId'] as String,
        by: [
          for (final raw in json['By'] as List? ?? const [])
            FriendWatcher.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String itemId;
  final List<FriendWatcher> by;
}
