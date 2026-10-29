// Modelli dei download automatici (spec T §8): i DTO del plugin 1.14.0
// (`EpisodeChoices` dalla 1.15.0).
// Lettura tollerante: un campo obbligatorio mancante o di tipo sbagliato
// salta la riga, mai la pagina.

enum DownloadKind {
  movie('Movie'),
  episode('Episode'),
  season('Season'),
  unknown('');

  const DownloadKind(this.wire);
  final String wire;

  static DownloadKind fromWire(String? value) => values
      .firstWhere((v) => v.wire == value && v != unknown, orElse: () => unknown);
}

enum DownloadState {
  waiting('Waiting'),
  downloading('Downloading'),
  upgradeWatch('UpgradeWatch'),
  needsYou('NeedsYou'),
  unknown('');

  const DownloadState(this.wire);
  final String wire;

  static DownloadState fromWire(String? value) => values
      .firstWhere((v) => v.wire == value && v != unknown, orElse: () => unknown);
}

enum DownloadReason {
  nothingFound('NothingFound'),
  belowMinScore('BelowMinScore'),
  importBlocked('ImportBlocked'),
  searchFailed('SearchFailed'),
  grabRefused('GrabRefused'),
  unknown('');

  const DownloadReason(this.wire);
  final String wire;

  static DownloadReason fromWire(String? value) => values
      .firstWhere((v) => v.wire == value && v != unknown, orElse: () => unknown);
}

enum RejectedReason {
  arr('Arr'),
  tooSmall('TooSmall'),
  unknown('');

  const RejectedReason(this.wire);
  final String wire;

  static RejectedReason fromWire(String? value) => values
      .firstWhere((v) => v.wire == value && v != unknown, orElse: () => unknown);
}

DateTime _date(Object? value) => DateTime.parse(value as String).toUtc();
DateTime? _dateOrNull(Object? value) => value == null ? null : _date(value);
int? _intOrNull(Object? value) => (value as num?)?.toInt();

/// Legge una lista di oggetti con [parse], saltando le righe non valide.
List<T> _list<T>(Object? json, T? Function(Map<String, dynamic>) parse) {
  if (json is! List) return const [];
  return [
    for (final item in json)
      if (item is Map<String, dynamic>) ?parse(item),
  ];
}

class DownloadRelease {
  const DownloadRelease({
    required this.guid,
    required this.indexerId,
    required this.indexer,
    required this.title,
    required this.quality,
    required this.resolution,
    required this.sizeBytes,
    required this.score,
    this.seeders,
  });

  final String guid;
  final int indexerId;
  final String indexer;
  final String title;
  final String quality;
  final int resolution;
  final int sizeBytes;
  final int score;
  final int? seeders;

  static DownloadRelease? fromJson(Map<String, dynamic> json) {
    try {
      return DownloadRelease(
        guid: json['Guid'] as String,
        indexerId: (json['IndexerId'] as num).toInt(),
        indexer: json['Indexer'] as String,
        title: json['Title'] as String,
        quality: json['Quality'] as String,
        resolution: (json['Resolution'] as num).toInt(),
        sizeBytes: (json['SizeBytes'] as num).toInt(),
        score: (json['Score'] as num).toInt(),
        seeders: _intOrNull(json['Seeders']),
      );
    } on Object {
      return null;
    }
  }

  static List<DownloadRelease> listFromJson(Object? json) =>
      _list(json, fromJson);
}

/// Una scelta già fatta, dalla regola o dall'admin.
class DownloadChoice {
  const DownloadChoice({
    required this.key,
    required this.kind,
    required this.title,
    this.posterUrl,
    required this.at,
    required this.release,
    this.previousSizeBytes,
    this.previousScore,
    required this.byAdmin,
  });

  final String key;
  final DownloadKind kind;
  final String title;
  final String? posterUrl;
  final DateTime at;
  final DownloadRelease release;
  final int? previousSizeBytes;
  final int? previousScore;
  final bool byAdmin;

  static DownloadChoice? fromJson(Map<String, dynamic> json) {
    try {
      final release = DownloadRelease.fromJson(
          (json['Release'] as Map).cast<String, dynamic>());
      if (release == null) return null;
      return DownloadChoice(
        key: json['Key'] as String,
        kind: DownloadKind.fromWire(json['Kind'] as String?),
        title: json['Title'] as String,
        posterUrl: json['PosterUrl'] as String?,
        at: _date(json['At']),
        release: release,
        previousSizeBytes: _intOrNull(json['PreviousSizeBytes']),
        previousScore: _intOrNull(json['PreviousScore']),
        byAdmin: json['ByAdmin'] as bool,
      );
    } on Object {
      return null;
    }
  }

  static List<DownloadChoice> listFromJson(Object? json) =>
      _list(json, fromJson);
}

/// Un titolo in attesa (include `NeedsYou`).
class DownloadItem {
  const DownloadItem({
    required this.key,
    required this.kind,
    required this.title,
    this.posterUrl,
    required this.state,
    this.reason,
    required this.availableSince,
    this.lastSearchAt,
    this.nextSearchAt,
  });

  final String key;
  final DownloadKind kind;
  final String title;
  final String? posterUrl;
  final DownloadState state;
  final DownloadReason? reason;
  final DateTime availableSince;
  final DateTime? lastSearchAt;
  final DateTime? nextSearchAt;

  static DownloadItem? fromJson(Map<String, dynamic> json) {
    try {
      final reason = json['Reason'] as String?;
      return DownloadItem(
        key: json['Key'] as String,
        kind: DownloadKind.fromWire(json['Kind'] as String?),
        title: json['Title'] as String,
        posterUrl: json['PosterUrl'] as String?,
        state: DownloadState.fromWire(json['State'] as String?),
        reason: reason == null ? null : DownloadReason.fromWire(reason),
        availableSince: _date(json['AvailableSince']),
        lastSearchAt: _dateOrNull(json['LastSearchAt']),
        nextSearchAt: _dateOrNull(json['NextSearchAt']),
      );
    } on Object {
      return null;
    }
  }

  static List<DownloadItem> listFromJson(Object? json) => _list(json, fromJson);
}

/// Un titolo da ripassare (file sotto la soglia di qualità).
class ReviewItem {
  const ReviewItem({
    required this.key,
    required this.kind,
    required this.title,
    this.posterUrl,
    required this.score,
    required this.sizeBytes,
    required this.quality,
  });

  final String key;
  final DownloadKind kind;
  final String title;
  final String? posterUrl;
  final int score;
  final int sizeBytes;
  final String quality;

  static ReviewItem? fromJson(Map<String, dynamic> json) {
    try {
      return ReviewItem(
        key: json['Key'] as String,
        kind: DownloadKind.fromWire(json['Kind'] as String?),
        title: json['Title'] as String,
        posterUrl: json['PosterUrl'] as String?,
        score: (json['Score'] as num).toInt(),
        sizeBytes: (json['SizeBytes'] as num).toInt(),
        quality: json['Quality'] as String,
      );
    } on Object {
      return null;
    }
  }

  static List<ReviewItem> listFromJson(Object? json) => _list(json, fromJson);
}

class DownloadsOverview {
  const DownloadsOverview({
    required this.enabled,
    this.recent = const [],
    this.waiting = const [],
    this.review = const [],
    this.reviewAt,
    this.sonarrError,
    this.radarrError,
  });

  /// Per chi non è admin: niente da mostrare.
  static const empty = DownloadsOverview(enabled: false);

  final bool enabled;
  final List<DownloadChoice> recent;
  final List<DownloadItem> waiting;
  final List<ReviewItem> review;
  final DateTime? reviewAt;
  final String? sonarrError;
  final String? radarrError;

  static DownloadsOverview? fromJson(Map<String, dynamic> json) {
    try {
      return DownloadsOverview(
        enabled: json['Enabled'] as bool,
        recent: DownloadChoice.listFromJson(json['Recent']),
        waiting: DownloadItem.listFromJson(json['Waiting']),
        review: ReviewItem.listFromJson(json['Review']),
        reviewAt: _dateOrNull(json['ReviewAt']),
        sonarrError: json['SonarrError'] as String?,
        radarrError: json['RadarrError'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

class DownloadCandidate {
  const DownloadCandidate({
    required this.rank,
    required this.release,
    required this.isChoice,
    required this.wouldImport,
  });

  /// Da 1; il 1 è la scelta della regola.
  final int rank;
  final DownloadRelease release;
  final bool isChoice;
  final bool wouldImport;

  static DownloadCandidate? fromJson(Map<String, dynamic> json) {
    try {
      final release = DownloadRelease.fromJson(
          (json['Release'] as Map).cast<String, dynamic>());
      if (release == null) return null;
      return DownloadCandidate(
        rank: (json['Rank'] as num).toInt(),
        release: release,
        isChoice: json['IsChoice'] as bool,
        wouldImport: json['WouldImport'] as bool,
      );
    } on Object {
      return null;
    }
  }

  static List<DownloadCandidate> listFromJson(Object? json) =>
      _list(json, fromJson);
}

class DownloadRejected {
  const DownloadRejected({
    required this.release,
    required this.reason,
    this.detail,
  });

  final DownloadRelease release;
  final RejectedReason reason;

  /// Arr: il primo motivo; TooSmall: GB/ora con due decimali e il punto.
  final String? detail;

  static DownloadRejected? fromJson(Map<String, dynamic> json) {
    try {
      final release = DownloadRelease.fromJson(
          (json['Release'] as Map).cast<String, dynamic>());
      if (release == null) return null;
      return DownloadRejected(
        release: release,
        reason: RejectedReason.fromWire(json['Reason'] as String?),
        detail: json['Detail'] as String?,
      );
    } on Object {
      return null;
    }
  }

  static List<DownloadRejected> listFromJson(Object? json) =>
      _list(json, fromJson);
}

class DownloadCurrentFile {
  const DownloadCurrentFile({
    required this.sizeBytes,
    required this.score,
    required this.quality,
  });

  final int sizeBytes;
  final int score;
  final String quality;

  static DownloadCurrentFile? fromJson(Map<String, dynamic> json) {
    try {
      return DownloadCurrentFile(
        sizeBytes: (json['SizeBytes'] as num).toInt(),
        score: (json['Score'] as num).toInt(),
        quality: json['Quality'] as String,
      );
    } on Object {
      return null;
    }
  }
}

/// Il singolo migliore di un episodio di una stagione senza un pack
/// conveniente (spec T §5.4, §8.2). [release] null: nessun singolo valido.
class DownloadEpisodeChoice {
  const DownloadEpisodeChoice({
    required this.episodeNumber,
    this.release,
    required this.wouldImport,
  });

  final int episodeNumber;
  final DownloadRelease? release;
  final bool wouldImport;

  static DownloadEpisodeChoice? fromJson(Map<String, dynamic> json) {
    try {
      final raw = json['Release'];
      final release = raw == null
          ? null
          : DownloadRelease.fromJson((raw as Map).cast<String, dynamic>());
      // Una release presente ma rotta salta la riga, non diventa "nessuno".
      if (raw != null && release == null) return null;
      return DownloadEpisodeChoice(
        episodeNumber: (json['EpisodeNumber'] as num).toInt(),
        release: release,
        wouldImport: json['WouldImport'] as bool,
      );
    } on Object {
      return null;
    }
  }

  static List<DownloadEpisodeChoice> listFromJson(Object? json) =>
      _list(json, fromJson);
}

class DownloadSearch {
  const DownloadSearch({
    required this.key,
    required this.kind,
    required this.title,
    required this.runtimeMinutes,
    this.current,
    this.candidates = const [],
    this.rejected = const [],
    required this.validCount,
    required this.totalCount,
    this.error,
    this.episodeChoices = const [],
  });

  final String key;
  final DownloadKind kind;
  final String title;
  final int runtimeMinutes;
  final DownloadCurrentFile? current;
  final List<DownloadCandidate> candidates;
  final List<DownloadRejected> rejected;
  final int validCount;
  final int totalCount;

  /// Codice d'errore (come `SonarrError`/`RadarrError`) se la ricerca è fallita.
  final String? error;

  /// I migliori singoli per episodio (plugin 1.15.0, solo per una stagione
  /// senza un pack scelto); vuota altrimenti e con un plugin più vecchio.
  final List<DownloadEpisodeChoice> episodeChoices;

  static DownloadSearch? fromJson(Map<String, dynamic> json) {
    try {
      final current = json['Current'];
      return DownloadSearch(
        key: json['Key'] as String,
        kind: DownloadKind.fromWire(json['Kind'] as String?),
        title: json['Title'] as String,
        runtimeMinutes: (json['RuntimeMinutes'] as num).toInt(),
        current: current is Map<String, dynamic>
            ? DownloadCurrentFile.fromJson(current)
            : null,
        candidates: DownloadCandidate.listFromJson(json['Candidates']),
        rejected: DownloadRejected.listFromJson(json['Rejected']),
        validCount: (json['ValidCount'] as num).toInt(),
        totalCount: (json['TotalCount'] as num).toInt(),
        error: json['Error'] as String?,
        episodeChoices: DownloadEpisodeChoice.listFromJson(
            json['EpisodeChoices']),
      );
    } on Object {
      return null;
    }
  }
}
