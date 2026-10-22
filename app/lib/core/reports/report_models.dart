/// Il tipo di una segnalazione (spec R §6.2): i valori del plugin.
enum ReportType {
  subtitles('Subtitles'),
  metadata('Metadata'),
  audioVideo('AudioVideo'),
  other('Other');

  const ReportType(this.wire);

  final String wire;

  /// `null` per un valore sconosciuto (un plugin più nuovo).
  static ReportType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// Come un admin chiude una segnalazione.
enum ReportOutcome {
  fixed('Fixed'),
  cannotFix('CannotFix');

  const ReportOutcome(this.wire);

  final String wire;

  static ReportOutcome? fromWire(Object? value) {
    for (final outcome in values) {
      if (outcome.wire == value) return outcome;
    }
    return null;
  }
}

/// Il tipo del titolo segnalato; vuoto se il titolo non c'è più.
enum ReportItemType {
  movie('Movie'),
  series('Series'),
  season('Season'),
  episode('Episode');

  const ReportItemType(this.wire);

  final String wire;

  /// `null` per un valore vuoto o sconosciuto.
  static ReportItemType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// Una segnalazione aperta (`ReportDto`, spec R §6.2). Note, nomi e titoli
/// sono testo dell'utente o della libreria: si mostrano sempre come testo
/// semplice.
class ItemReport {
  const ItemReport({
    required this.id,
    required this.type,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.userName,
    required this.itemId,
    this.itemType,
    required this.itemName,
    required this.titleId,
    required this.titleName,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String id;
  final ReportType type;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId;
  final String userName;
  final String itemId;

  /// `null` se il titolo non c'è più.
  final ReportItemType? itemType;
  final String itemName;

  /// La serie di un episodio o di una stagione; per gli altri, lo stesso
  /// [itemId].
  final String titleId;
  final String titleName;
  final int? seasonNumber;
  final int? episodeNumber;

  /// `null` se il `Type` è sconosciuto o mancano campi: la voce si salta.
  static ItemReport? fromJson(Map<dynamic, dynamic> json) {
    try {
      final type = ReportType.fromWire(json['Type']);
      if (type == null) return null;
      return ItemReport(
        id: json['Id'] as String,
        type: type,
        note: json['Note'] as String?,
        createdAt: DateTime.parse(json['CreatedAt'] as String).toUtc(),
        updatedAt: DateTime.parse(json['UpdatedAt'] as String).toUtc(),
        userId: json['UserId'] as String,
        userName: json['UserName'] as String,
        itemId: json['ItemId'] as String,
        itemType: ReportItemType.fromWire(json['ItemType']),
        itemName: json['ItemName'] as String? ?? '',
        titleId: json['TitleId'] as String,
        titleName: json['TitleName'] as String? ?? '',
        seasonNumber: (json['SeasonNumber'] as num?)?.toInt(),
        episodeNumber: (json['EpisodeNumber'] as num?)?.toInt(),
      );
    } on Object {
      return null;
    }
  }

  /// Legge `Items` e salta le voci non valide.
  static List<ItemReport> listFromJson(Object? json) {
    final items = json is Map ? json['Items'] : null;
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) ?fromJson(item),
    ];
  }
}
