// Modelli dello spazio del seedbox (spec U §7.4): i DTO del plugin 1.16.0.
// Lettura tollerante: un campo obbligatorio mancante o di tipo sbagliato
// salta la riga (o la panoramica, se manca un blocco), mai la pagina.

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toUtc();
int _int(Object? v) => (v as num).toInt();
int? _intOrNull(Object? v) => (v as num?)?.toInt();
double _double(Object? v) => (v as num).toDouble();
List<String> _strings(Object? v) =>
    v is List ? [for (final s in v) if (s is String) s] : const [];

/// Legge una lista con [parse], saltando le righe non valide.
List<T> _list<T>(Object? json, T? Function(Object?) parse) =>
    json is! List ? const [] : [for (final item in json) ?parse(item)];

/// [body] solo se [json] è un oggetto; una forma sbagliata dà null.
T? _guard<T>(Object? json, T Function(Map<String, dynamic> j) body) {
  if (json is! Map<String, dynamic>) return null;
  try {
    return body(json);
  } on Object {
    return null;
  }
}

class SpaceQuota {
  const SpaceQuota({required this.usedBytes, required this.limitBytes});

  final int usedBytes;
  final int limitBytes;

  static SpaceQuota? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceQuota(
          usedBytes: _int(j['UsedBytes']), limitBytes: _int(j['LimitBytes'])));
}

class SpaceBreakdown {
  const SpaceBreakdown({
    required this.moviesBytes,
    required this.seriesBytes,
    required this.animeBytes,
    required this.torrentOnlyBytes,
    required this.otherBytes,
  });

  final int moviesBytes;
  final int seriesBytes;
  final int animeBytes;
  final int torrentOnlyBytes;
  final int otherBytes;

  static SpaceBreakdown? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceBreakdown(
            moviesBytes: _int(j['MoviesBytes']),
            seriesBytes: _int(j['SeriesBytes']),
            animeBytes: _int(j['AnimeBytes']),
            torrentOnlyBytes: _int(j['TorrentOnlyBytes']),
            otherBytes: _int(j['OtherBytes']),
          ));
}

class SpaceViewer {
  const SpaceViewer({
    required this.name,
    required this.finished,
    this.lastPlayed,
  });

  final String name;
  final bool finished;
  final DateTime? lastPlayed;

  static SpaceViewer? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceViewer(
            name: j['Name'] as String,
            finished: j['Finished'] as bool,
            lastPlayed: _date(j['LastPlayed']),
          ));
}

class SpaceRequest {
  const SpaceRequest({required this.name, required this.at});

  final String name;
  final DateTime at;

  static SpaceRequest? fromJson(Object? json) => _guard(
      json, (j) => SpaceRequest(name: j['Name'] as String, at: _date(j['At'])!));
}

/// Una riga di Cancellare: film, serie o stagione.
class SpaceCandidate {
  const SpaceCandidate({
    required this.key,
    required this.kind,
    required this.title,
    this.year,
    this.seasonNumber,
    this.seriesKey,
    this.itemId,
    this.posterUrl,
    required this.sizeBytes,
    required this.freeNowBytes,
    required this.freeLaterBytes,
    this.freeLaterAt,
    required this.inPackBytes,
    required this.via,
    required this.keep,
    required this.viewers,
    required this.requests,
    this.ratingAvg,
    required this.ratingCount,
    this.lastOpened,
    this.added,
    required this.genres,
  });

  final String key;
  final String kind;
  final String title;
  final int? year;
  final int? seasonNumber;
  final String? seriesKey;
  final String? itemId;
  final String? posterUrl;
  final int sizeBytes;
  final int freeNowBytes;
  final int freeLaterBytes;
  final DateTime? freeLaterAt;
  final int inPackBytes;
  final List<String> via;
  final List<String> keep;
  final List<SpaceViewer> viewers;
  final List<SpaceRequest> requests;

  /// Media dei voti da 1 a 10.
  final double? ratingAvg;
  final int ratingCount;
  final DateTime? lastOpened;
  final DateTime? added;
  final List<String> genres;

  static SpaceCandidate? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceCandidate(
            key: j['Key'] as String,
            kind: j['Kind'] as String,
            title: j['Title'] as String,
            year: _intOrNull(j['Year']),
            seasonNumber: _intOrNull(j['SeasonNumber']),
            seriesKey: j['SeriesKey'] as String?,
            itemId: j['ItemId'] as String?,
            posterUrl: j['PosterUrl'] as String?,
            sizeBytes: _int(j['SizeBytes']),
            freeNowBytes: _int(j['FreeNowBytes']),
            freeLaterBytes: _int(j['FreeLaterBytes']),
            freeLaterAt: _date(j['FreeLaterAt']),
            inPackBytes: _int(j['InPackBytes']),
            via: _strings(j['Via']),
            keep: _strings(j['Keep']),
            viewers: _list(j['Viewers'], SpaceViewer.fromJson),
            requests: _list(j['Requests'], SpaceRequest.fromJson),
            ratingAvg: (j['RatingAvg'] as num?)?.toDouble(),
            ratingCount: _int(j['RatingCount']),
            lastOpened: _date(j['LastOpened']),
            added: _date(j['Added']),
            genres: _strings(j['Genres']),
          ));
}

/// Una riga di Alleggerire: oltre la soglia di GB all'ora.
class SpaceLighten {
  const SpaceLighten({
    required this.key,
    required this.kind,
    required this.title,
    this.seasonNumber,
    this.itemId,
    this.posterUrl,
    required this.sizeBytes,
    required this.excessBytes,
    required this.gbPerHour,
  });

  final String key;
  final String kind;
  final String title;
  final int? seasonNumber;
  final String? itemId;
  final String? posterUrl;
  final int sizeBytes;
  final int excessBytes;
  final double gbPerHour;

  static SpaceLighten? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceLighten(
            key: j['Key'] as String,
            kind: j['Kind'] as String,
            title: j['Title'] as String,
            seasonNumber: _intOrNull(j['SeasonNumber']),
            itemId: j['ItemId'] as String?,
            posterUrl: j['PosterUrl'] as String?,
            sizeBytes: _int(j['SizeBytes']),
            excessBytes: _int(j['ExcessBytes']),
            gbPerHour: _double(j['GbPerHour']),
          ));
}

/// Un torrent senza copia in libreria; [tracker] è l'host.
class SpaceTorrent {
  const SpaceTorrent({
    required this.key,
    required this.hash,
    required this.name,
    required this.tracker,
    required this.sizeBytes,
    required this.ratio,
    required this.seedingDays,
    required this.canRemoveNow,
    this.expectedAt,
  });

  final String key;
  final String hash;
  final String name;
  final String tracker;
  final int sizeBytes;
  final double ratio;
  final double seedingDays;
  final bool canRemoveNow;
  final DateTime? expectedAt;

  static SpaceTorrent? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceTorrent(
            key: j['Key'] as String,
            hash: j['Hash'] as String,
            name: j['Name'] as String,
            tracker: j['Tracker'] as String,
            sizeBytes: _int(j['SizeBytes']),
            ratio: _double(j['Ratio']),
            seedingDays: _double(j['SeedingDays']),
            canRemoveNow: j['CanRemoveNow'] as bool,
            expectedAt: _date(j['ExpectedAt']),
          ));
}

/// Un file orfano o doppione; [linked]: ha altri hardlink, cancellarlo non
/// libera spazio.
class SpaceFile {
  const SpaceFile({
    required this.key,
    required this.path,
    required this.sizeBytes,
    required this.linked,
  });

  final String key;
  final String path;
  final int sizeBytes;
  final bool linked;

  static SpaceFile? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceFile(
            key: j['Key'] as String,
            path: j['Path'] as String,
            sizeBytes: _int(j['SizeBytes']),
            linked: j['Linked'] as bool,
          ));
}

class SpaceCleanup {
  const SpaceCleanup({
    this.torrents = const [],
    this.orphans = const [],
    this.duplicates = const [],
  });

  final List<SpaceTorrent> torrents;
  final List<SpaceFile> orphans;
  final List<SpaceFile> duplicates;

  static SpaceCleanup? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceCleanup(
            torrents: _list(j['Torrents'], SpaceTorrent.fromJson),
            orphans: _list(j['Orphans'], SpaceFile.fromJson),
            duplicates: _list(j['Duplicates'], SpaceFile.fromJson),
          ));
}

/// Un torrent in attesa della fine del seed obbligatorio.
class SpacePending {
  const SpacePending({
    required this.hash,
    required this.name,
    required this.tracker,
    required this.sizeBytes,
    this.expectedAt,
    required this.title,
  });

  final String hash;
  final String name;
  final String tracker;
  final int sizeBytes;
  final DateTime? expectedAt;
  final String title;

  static SpacePending? fromJson(Object? json) => _guard(
      json,
      (j) => SpacePending(
            hash: j['Hash'] as String,
            name: j['Name'] as String,
            tracker: j['Tracker'] as String,
            sizeBytes: _int(j['SizeBytes']),
            expectedAt: _date(j['ExpectedAt']),
            title: j['Title'] as String,
          ));
}

/// Un titolo tenuto con "Tienilo".
class SpaceKept {
  const SpaceKept({required this.key, required this.title});

  final String key;
  final String title;

  static SpaceKept? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceKept(key: j['Key'] as String, title: j['Title'] as String));
}

class SpaceStep {
  const SpaceStep({
    required this.name,
    required this.state,
    this.detail,
    this.done,
    this.waiting,
  });

  final String name;
  final String state;
  final String? detail;
  final int? done;
  final int? waiting;

  static SpaceStep? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceStep(
            name: j['Name'] as String,
            state: j['State'] as String,
            detail: j['Detail'] as String?,
            done: _intOrNull(j['Done']),
            waiting: _intOrNull(j['Waiting']),
          ));
}

class SpaceOperation {
  const SpaceOperation({
    required this.id,
    required this.kind,
    required this.key,
    required this.title,
    required this.state,
    required this.auto,
    required this.startedAt,
    this.endedAt,
    required this.estimatedFreedBytes,
    required this.pendingBytes,
    this.quotaBeforeBytes,
    this.quotaAfterBytes,
    required this.steps,
  });

  final String id;
  final String kind;
  final String key;
  final String title;
  final String state;
  final bool auto;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int estimatedFreedBytes;
  final int pendingBytes;
  final int? quotaBeforeBytes;
  final int? quotaAfterBytes;
  final List<SpaceStep> steps;

  /// In coda o in corso.
  bool get running => state == 'Queued' || state == 'Running';

  static SpaceOperation? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceOperation(
            id: j['Id'] as String,
            kind: j['Kind'] as String,
            key: j['Key'] as String,
            title: j['Title'] as String,
            state: j['State'] as String,
            auto: j['Auto'] as bool,
            startedAt: _date(j['StartedAt'])!,
            endedAt: _date(j['EndedAt']),
            estimatedFreedBytes: _int(j['EstimatedFreedBytes']),
            pendingBytes: _int(j['PendingBytes']),
            quotaBeforeBytes: _intOrNull(j['QuotaBeforeBytes']),
            quotaAfterBytes: _intOrNull(j['QuotaAfterBytes']),
            steps: _list(j['Steps'], SpaceStep.fromJson),
          ));
}

/// Per ogni servizio: `NotConfigured`, `Unauthorized`, `Unreachable` o null.
class SpaceErrors {
  const SpaceErrors(
      {this.radarr, this.sonarr, this.qbit, this.seerr, this.quota});

  final String? radarr;
  final String? sonarr;
  final String? qbit;
  final String? seerr;
  final String? quota;

  static SpaceErrors? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceErrors(
            radarr: j['Radarr'] as String?,
            sonarr: j['Sonarr'] as String?,
            qbit: j['Qbit'] as String?,
            seerr: j['Seerr'] as String?,
            quota: j['Quota'] as String?,
          ));
}

class SpaceOverview {
  const SpaceOverview({
    this.scannedAt,
    required this.scanning,
    this.quota,
    required this.breakdown,
    required this.delete,
    required this.lighten,
    required this.cleanup,
    required this.pending,
    required this.kept,
    required this.operations,
    required this.topGenres,
    required this.errors,
  });

  final DateTime? scannedAt;
  final bool scanning;
  final SpaceQuota? quota;
  final SpaceBreakdown breakdown;
  final List<SpaceCandidate> delete;
  final List<SpaceLighten> lighten;
  final SpaceCleanup cleanup;
  final List<SpacePending> pending;
  final List<SpaceKept> kept;
  final List<SpaceOperation> operations;
  final List<String> topGenres;
  final SpaceErrors errors;

  static SpaceOverview? fromJson(Object? json) => _guard(
      json,
      (j) => SpaceOverview(
            scannedAt: _date(j['ScannedAt']),
            scanning: j['Scanning'] as bool,
            quota: SpaceQuota.fromJson(j['Quota']),
            breakdown: SpaceBreakdown.fromJson(j['Breakdown'])!,
            delete: _list(j['Delete'], SpaceCandidate.fromJson),
            lighten: _list(j['Lighten'], SpaceLighten.fromJson),
            cleanup: SpaceCleanup.fromJson(j['Cleanup'])!,
            pending: _list(j['Pending'], SpacePending.fromJson),
            kept: _list(j['Kept'], SpaceKept.fromJson),
            operations: _list(j['Operations'], SpaceOperation.fromJson),
            topGenres: _strings(j['TopGenres']),
            errors: SpaceErrors.fromJson(j['Errors'])!,
          ));
}
