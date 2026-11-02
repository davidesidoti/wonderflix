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

/// Un'azione offerta dal plugin su un titolo; la prima della lista è la
/// consigliata. Un valore sconosciuto (plugin più nuovo) si salta.
enum DownloadAction {
  grabBest('GrabBest'),
  pick('Pick'),
  searchNow('SearchNow'),
  snooze('Snooze'),
  import('Import'),
  discard('Discard'),

  /// Apre la ricerca sul tracker esterno (MIRCrew) nel browser.
  externalSearch('ExternalSearch');

  const DownloadAction(this.wire);
  final String wire;

  static DownloadAction? fromWire(Object? value) {
    for (final v in values) {
      if (v.wire == value) return v;
    }
    return null;
  }
}

/// La fase della ricerca di una voce (plugin 1.18.0): in coda per il prossimo
/// giro o cercata adesso. Assente o sconosciuta (plugin più nuovo) è `null`.
enum DownloadSearchPhase {
  queued('Queued'),
  searching('Searching');

  const DownloadSearchPhase(this.wire);
  final String wire;

  static DownloadSearchPhase? fromWire(Object? value) {
    for (final v in values) {
      if (v.wire == value) return v;
    }
    return null;
  }
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

/// Il riassunto dell'ultima ricerca di un titolo da guardare (plugin 1.18.0).
class DownloadSummary {
  const DownloadSummary({
    required this.found,
    this.bestScore,
    required this.minScore,
    required this.tooSmall,
    required this.arrRejected,
    this.topRejection,
    required this.stopgapAvailable,
  });

  final int found;
  final int? bestScore;
  final int minScore;
  final int tooSmall;
  final int arrRejected;
  final String? topRejection;
  final bool stopgapAvailable;

  static DownloadSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return DownloadSummary(
        found: (json['Found'] as num).toInt(),
        bestScore: _intOrNull(json['BestScore']),
        minScore: (json['MinScore'] as num).toInt(),
        tooSmall: (json['TooSmall'] as num).toInt(),
        arrRejected: (json['ArrRejected'] as num).toInt(),
        topRejection: json['TopRejection'] as String?,
        stopgapAvailable: json['StopgapAvailable'] as bool,
      );
    } on Object {
      return null;
    }
  }
}

/// L'avanzamento di un download in corso (plugin 1.18.0+): il `Status` è
/// quello di Sonarr/Radarr, com'è ("downloading", "paused", ...), oppure
/// "metadata" se il torrent è fermo sul recupero dei metadati: allora [since]
/// dice da quando (la dimensione è 0).
class DownloadProgress {
  const DownloadProgress({
    required this.sizeBytes,
    required this.sizeLeftBytes,
    this.estimatedCompletion,
    required this.status,
    this.since,
  });

  final int sizeBytes;
  final int sizeLeftBytes;
  final DateTime? estimatedCompletion;
  final String status;
  final DateTime? since;

  /// Torrent fermo sul recupero dei metadati: niente percentuale né barra.
  bool get isFetchingMetadata => status.toLowerCase() == 'metadata';

  /// Da 0 a 1; 0 se la dimensione non è nota.
  double get fraction =>
      sizeBytes <= 0 ? 0 : ((sizeBytes - sizeLeftBytes) / sizeBytes).clamp(0, 1);

  static DownloadProgress? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return DownloadProgress(
        sizeBytes: (json['SizeBytes'] as num).toInt(),
        sizeLeftBytes: (json['SizeLeftBytes'] as num).toInt(),
        estimatedCompletion: _dateOrNull(json['EstimatedCompletion']),
        status: json['Status'] as String,
        since: _dateOrNull(json['Since']),
      );
    } on Object {
      return null;
    }
  }
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
    this.actions = const [],
    this.summary,
    this.blockedMessage,
    this.snoozed = false,
    this.progress,
    this.searchPhase,
    this.externalSearchUrl,
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

  /// Dal plugin 1.18.0, la consigliata per prima; vuota con un plugin più vecchio.
  final List<DownloadAction> actions;
  final DownloadSummary? summary;

  /// Il messaggio di Sonarr/Radarr per un import bloccato, così com'è.
  final String? blockedMessage;
  final bool snoozed;

  /// Solo per i titoli in download.
  final DownloadProgress? progress;

  /// Dal plugin 1.18.0: la ricerca in coda o in corso; `null` altrimenti.
  final DownloadSearchPhase? searchPhase;

  /// La pagina di ricerca del tracker esterno, già col titolo; `null` senza
  /// (o con un plugin più vecchio).
  final String? externalSearchUrl;

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
        actions: switch (json['Actions']) {
          final List list => [
              for (final a in list) ?DownloadAction.fromWire(a),
            ],
          _ => const [],
        },
        summary: DownloadSummary.fromJson(json['Summary']),
        blockedMessage: json['BlockedMessage'] as String?,
        snoozed: json['Snoozed'] as bool? ?? false,
        progress: DownloadProgress.fromJson(json['Progress']),
        searchPhase: DownloadSearchPhase.fromWire(json['SearchPhase']),
        externalSearchUrl: json['ExternalSearchUrl'] as String?,
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
    this.canHunt = false,
  });

  final String key;
  final DownloadKind kind;
  final String title;
  final String? posterUrl;
  final int score;
  final int sizeBytes;
  final String quality;

  /// "Cerca un upgrade" può partire; falso da un plugin che non lo manda.
  final bool canHunt;

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
        canHunt: json['CanHunt'] == true,
      );
    } on Object {
      return null;
    }
  }

  static List<ReviewItem> listFromJson(Object? json) => _list(json, fromJson);
}

/// Un download fermo all'import senza serie né film: l'import si fa da Sonarr
/// o Radarr, da qui si può solo togliere.
class UnknownDownload {
  const UnknownDownload({
    required this.service,
    required this.downloadId,
    required this.title,
    required this.sizeBytes,
    this.message,
  });

  /// "Sonarr" o "Radarr".
  final String service;
  final String downloadId;
  final String title;
  final int sizeBytes;
  final String? message;

  static UnknownDownload? fromJson(Map<String, dynamic> json) {
    try {
      return UnknownDownload(
        service: json['Service'] as String,
        downloadId: json['DownloadId'] as String,
        title: json['Title'] as String,
        sizeBytes: (json['SizeBytes'] as num).toInt(),
        message: json['Message'] as String?,
      );
    } on Object {
      return null;
    }
  }

  static List<UnknownDownload> listFromJson(Object? json) =>
      _list(json, fromJson);
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
    this.unknown = const [],
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

  /// Vuoto con un plugin che non lo manda.
  final List<UnknownDownload> unknown;

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
        unknown: UnknownDownload.listFromJson(json['Unknown']),
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
    this.currentScore,
  });

  final int episodeNumber;
  final DownloadRelease? release;
  final bool wouldImport;

  /// Il punteggio del file di quell'episodio (il peggiore se più d'uno); null
  /// senza file o con un plugin che non lo manda.
  final int? currentScore;

  /// La release non migliora il file attuale (punteggio pari o più basso).
  bool get lowersScore =>
      release != null && currentScore != null && release!.score <= currentScore!;

  /// Serve la conferma (decisione 4): non migliora il file o Sonarr non lo
  /// importerebbe.
  bool get needsConfirm => !wouldImport || lowersScore;

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
        currentScore: switch (json['CurrentScore']) {
          final num n => n.toInt(),
          _ => null,
        },
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
    this.externalSearchUrl,
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

  /// La pagina di ricerca del tracker esterno, già col titolo; `null` senza
  /// (o con un plugin più vecchio).
  final String? externalSearchUrl;

  /// La stessa ricerca con altri [episodeChoices].
  DownloadSearch withEpisodeChoices(List<DownloadEpisodeChoice> choices) =>
      DownloadSearch(
        key: key,
        kind: kind,
        title: title,
        runtimeMinutes: runtimeMinutes,
        current: current,
        candidates: candidates,
        rejected: rejected,
        validCount: validCount,
        totalCount: totalCount,
        error: error,
        episodeChoices: choices,
        externalSearchUrl: externalSearchUrl,
      );

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
        externalSearchUrl: json['ExternalSearchUrl'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

/// Stato del lavoro di ricerca in background di un titolo (spec W).
enum DownloadSearchJobState {
  running('Running'),
  done('Done'),

  /// Radarr/Sonarr non hanno il titolo, o la chiave non è valida (400 nella
  /// vecchia `Search`). Un lavoro scaduto invece è `none`.
  missing('Missing'),

  /// Nessun lavoro: mai partito, o plugin riavviato.
  none('None');

  const DownloadSearchJobState(this.wire);

  final String wire;
}

/// Risposta di `SearchStart` e `SearchStatus`.
class DownloadSearchStatus {
  const DownloadSearchStatus({
    required this.key,
    required this.state,
    this.startedAt,
    required this.service,
    this.result,
  });

  final String key;
  final DownloadSearchJobState state;

  /// Quando il plugin ha avviato la ricerca (ora del server).
  final DateTime? startedAt;

  /// `Radarr` o `Sonarr`.
  final String service;

  /// Il risultato, solo con [DownloadSearchJobState.done].
  final DownloadSearch? result;

  /// `null` con uno stato sconosciuto o un `Done` senza risultato valido.
  static DownloadSearchStatus? fromJson(Map<String, dynamic> json) {
    try {
      final state = DownloadSearchJobState.values
          .where((s) => s.wire == json['State'])
          .firstOrNull;
      if (state == null) return null;
      final raw = json['Result'];
      final result =
          raw == null ? null : DownloadSearch.fromJson((raw as Map).cast());
      if (state == DownloadSearchJobState.done && result == null) return null;
      final startedAt = json['StartedAt'];
      return DownloadSearchStatus(
        key: json['Key'] as String,
        state: state,
        startedAt:
            startedAt == null ? null : DateTime.parse(startedAt as String),
        service: json['Service'] as String,
        result: result,
      );
    } on Object {
      return null;
    }
  }
}
