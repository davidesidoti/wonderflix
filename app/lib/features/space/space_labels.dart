import 'package:intl/intl.dart';

import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../downloads/download_labels.dart';

/// "12,35 GB" (spec U §8), come la scheda Download.
String spaceGb(AppLocalizations l, int bytes) => formatGb(l, bytes);

/// "1,23 TB" (10¹² byte).
String spaceTb(AppLocalizations l, int bytes) =>
    l.spaceTbUnit(NumberFormat('0.00', l.localeName).format(bytes / 1e12));

/// "8 mesi fa", o in giorni sotto il mese.
String _ago(AppLocalizations l, DateTime at, DateTime now) {
  var months = (now.year - at.year) * 12 + now.month - at.month;
  if (now.day < at.day) months--;
  return months >= 1
      ? l.spaceAgoMonths(months)
      : l.spaceAgoDays(now.difference(at).inDays.clamp(0, 31));
}

/// Mesi interi tra [at] e [now], almeno 1.
int _monthsSince(DateTime at, DateTime now) {
  var months = (now.year - at.year) * 12 + now.month - at.month;
  if (now.day < at.day) months--;
  return months < 1 ? 1 : months;
}

/// I segnali "via" di [c] in frasi (decisione 2 del piano 30b).
List<String> spaceViaLines(AppLocalizations l, SpaceCandidate c, DateTime now) {
  return [
    for (final code in c.via)
      switch (code) {
        'NobodyWatching' => _nobodyWatching(l, c, now),
        'NeverOpened' =>
          c.added == null
              ? l.spaceViaNeverOpenedPlain
              : l.spaceViaNeverOpened(
                  l.spaceMonths(_monthsSince(c.added!.toLocal(), now)),
                ),
        'LowRating' => l.spaceViaLowRating(
          NumberFormat('0.0', l.localeName).format(c.ratingAvg ?? 0),
          c.ratingCount,
        ),
        _ => code,
      },
  ];
}

String _nobodyWatching(AppLocalizations l, SpaceCandidate c, DateTime now) {
  final played = [
    for (final v in c.viewers)
      if (v.lastPlayed != null) v.lastPlayed!,
  ]..sort();
  final last = played.isEmpty
      ? ''
      : l.spaceViaLastWatched(_ago(l, played.last.toLocal(), now));
  final done = [
    for (final v in c.viewers)
      if (v.finished) v.name,
  ];
  final left = [
    for (final v in c.viewers)
      if (!v.finished) v.name,
  ];
  if (left.isEmpty && done.isNotEmpty) return l.spaceViaAllWatched(last);
  if (done.isEmpty) return l.spaceViaAllAbandoned(last);
  return l.spaceViaMixed(done.join(', '), left.join(', '), last);
}

/// I segnali "tienilo" di [c]; per `RecentRequest` la richiesta più recente.
List<String> spaceKeepLabels(AppLocalizations l, SpaceCandidate c) {
  return [
    for (final code in c.keep)
      switch (code) {
        'InProgress' => l.spaceKeepInProgress,
        'RecentRequest' => _recentRequest(l, c),
        'HighRating' => l.spaceKeepHighRating,
        'SequelComing' => l.spaceKeepSequelComing,
        _ => code,
      },
  ];
}

String _recentRequest(AppLocalizations l, SpaceCandidate c) {
  if (c.requests.isEmpty) return l.spaceKeepRequested;
  final r = c.requests.reduce((a, b) => b.at.isAfter(a.at) ? b : a);
  return l.spaceKeepRequestedBy(
    r.name,
    DateFormat.MMMMd(l.localeName).format(r.at.toLocal()),
  );
}

String _stepName(AppLocalizations l, String name) => switch (name) {
  'FindTorrents' => l.spaceStepFindTorrents,
  'RemoveFromQueue' => l.spaceStepRemoveFromQueue,
  'DeleteFromRadarr' => l.spaceStepDeleteFromRadarr,
  'DeleteFromSonarr' => l.spaceStepDeleteFromSonarr,
  'UnmonitorSeason' => l.spaceStepUnmonitorSeason,
  'DeleteEpisodeFiles' => l.spaceStepDeleteEpisodeFiles,
  'RemoveTorrents' => l.spaceStepRemoveTorrents,
  'RemoveFromSeerr' => l.spaceStepRemoveFromSeerr,
  'RefreshLibrary' => l.spaceStepRefreshLibrary,
  'DeleteFile' => l.spaceStepDeleteFile,
  'ReadQuota' => l.spaceStepReadQuota,
  _ => name,
};

String _stepDetail(AppLocalizations l, String detail) => switch (detail) {
  'NotConfigured' => l.spaceDetailNotConfigured,
  'Unauthorized' => l.spaceDetailUnauthorized,
  'Unreachable' => l.spaceDetailUnreachable,
  'Gone' => l.spaceDetailGone,
  'SeedRule' => l.spaceDetailSeedRule,
  'Failed' => l.spaceDetailFailed,
  _ => detail,
};

/// Nome del passo e, se c'è, il dettaglio o i conteggi dei torrent.
String spaceStepLabel(AppLocalizations l, SpaceStep step) {
  final name = _stepName(l, step.name);
  final done = step.done;
  if (step.name == 'RemoveTorrents' && done != null) {
    final waiting = step.waiting ?? 0;
    return l.spaceStepWithDetail(
      name,
      waiting > 0
          ? l.spaceStepTorrentsCounts(done, waiting)
          : l.spaceStepTorrentsDone(done),
    );
  }
  final detail = step.detail;
  if (detail == null || detail.isEmpty) return name;
  return l.spaceStepWithDetail(name, _stepDetail(l, detail));
}

String spaceFailureLabel(AppLocalizations l, SpaceFailure f) => switch (f) {
  SpaceFailure.invalid => l.spaceFailureInvalid,
  SpaceFailure.unknown => l.spaceFailureUnknown,
  SpaceFailure.busy => l.spaceFailureBusy,
  SpaceFailure.notReady => l.spaceFailureNotReady,
  SpaceFailure.notFound => l.spaceFailureNotFound,
  SpaceFailure.forbidden => l.errorAccountDisabled,
  SpaceFailure.network => l.errorServerUnreachable,
  SpaceFailure.server => l.spaceFailureServer,
};

/// L'errore dell'import a mano (Alleggerire): 404 non ha più niente da
/// importare, 502 dice il codice di Radarr/Sonarr.
String spaceImportFailureLabel(AppLocalizations l, SpaceException e) =>
    switch ((e.failure, e.reason)) {
      (SpaceFailure.unknown, _) => l.spaceImportNothing,
      (SpaceFailure.server, 'NoFiles') => l.spaceImportNoFiles,
      (SpaceFailure.server, final code?) => l.spaceImportFailed(code),
      _ => spaceFailureLabel(l, e.failure),
    };

/// La nota in cima alla scheda per un servizio in errore; null senza errore.
/// [service]: `radarr`, `sonarr`, `qbit`, `seerr` o `quota`.
String? spaceServiceError(AppLocalizations l, String service, String? code) {
  if (code == null) return null;
  if (service == 'quota') {
    return code == 'NotConfigured'
        ? l.spaceQuotaNotConfigured
        : l.spaceQuotaError;
  }
  final name = switch (service) {
    'radarr' => 'Radarr',
    'sonarr' => 'Sonarr',
    'qbit' => 'qBittorrent',
    'seerr' => 'Seerr',
    _ => service,
  };
  return switch (code) {
    'NotConfigured' => l.spaceServiceNotConfigured(name),
    'Unauthorized' =>
      service == 'qbit'
          ? l.spaceServiceUnauthorizedQbit(name)
          : l.spaceServiceUnauthorized(name),
    'Unreachable' => l.spaceServiceUnreachable(name),
    _ => l.spaceServiceError(name),
  };
}

/// I passi in parole per la conferma, nell'ordine del plugin (spec U §6.2).
List<String> spacePlannedSteps(AppLocalizations l, String kind) => [
  for (final s in switch (kind) {
    'Movie' => const [
      'FindTorrents',
      'RemoveFromQueue',
      'DeleteFromRadarr',
      'RemoveTorrents',
      'RemoveFromSeerr',
      'RefreshLibrary',
      'ReadQuota',
    ],
    'Series' => const [
      'FindTorrents',
      'RemoveFromQueue',
      'DeleteFromSonarr',
      'RemoveTorrents',
      'RemoveFromSeerr',
      'RefreshLibrary',
      'ReadQuota',
    ],
    'Season' => const [
      'FindTorrents',
      'RemoveFromQueue',
      'UnmonitorSeason',
      'DeleteEpisodeFiles',
      'RemoveTorrents',
      'RefreshLibrary',
      'ReadQuota',
    ],
    'Torrent' || 'AllTorrents' => const ['RemoveTorrents', 'ReadQuota'],
    _ => const ['DeleteFile', 'ReadQuota'],
  })
    _stepName(l, s),
];
