import 'package:intl/intl.dart';

import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../l10n/gen/app_localizations.dart';

const _bytesPerGb = 1000000000;

/// "1,89 GB" (con la virgola in italiano), come le informazioni del file.
String formatGb(AppLocalizations l, int bytes) => l.downloadsGb(
  NumberFormat('0.00', l.localeName).format(bytes / _bytesPerGb),
);

/// "62% · 1,20 GB di 3,10 GB · finisce tra 25 min". Lo stato di
/// Sonarr/Radarr arriva com'è ("downloading", "downloadClientUnavailable"):
/// si confronta senza badare alle maiuscole. Senza coda da dire, niente.
String downloadProgressLabel(
  AppLocalizations l,
  DownloadProgress p,
  DateTime now,
) {
  if (p.isFetchingMetadata) {
    final since = p.since;
    return since == null
        ? l.downloadsProgressMetadataNow
        : l.downloadsProgressMetadata(_durationLabel(l, _atLeastZero(now.difference(since))));
  }
  final line = l.downloadsProgressLine(
    (p.fraction * 100).round(),
    formatGb(l, (p.fraction * p.sizeBytes).round()),
    formatGb(l, p.sizeBytes),
  );
  final eta = p.estimatedCompletion;
  final tail = switch (p.status.toLowerCase()) {
    'downloading' when eta != null => _etaLabel(l, eta, now),
    'paused' => l.downloadsProgressPaused,
    'queued' || 'delay' => l.downloadsProgressQueued,
    'warning' => l.downloadsProgressStalled,
    'downloadclientunavailable' => l.downloadsProgressClientDown,
    _ => '',
  };
  return tail.isEmpty ? line : '$line · $tail';
}

// Un orologio indietro rispetto al server darebbe una durata negativa.
Duration _atLeastZero(Duration d) => d.isNegative ? Duration.zero : d;

/// "45 min", "2 h 5 min", "2 g 12 h": la parte piccola sparisce se è 0.
String _durationLabel(AppLocalizations l, Duration d) {
  if (d.inMinutes < 60) return l.downloadsDurationMinutes(d.inMinutes);
  if (d.inHours < 24) {
    final minutes = d.inMinutes % 60;
    return minutes == 0
        ? l.downloadsDurationHours(d.inHours)
        : l.downloadsDurationHoursMinutes(d.inHours, minutes);
  }
  final hours = d.inHours % 24;
  return hours == 0
      ? l.downloadsDurationDays(d.inDays)
      : l.downloadsDurationDaysHours(d.inDays, hours);
}

String _etaLabel(AppLocalizations l, DateTime eta, DateTime now) {
  final left = eta.difference(now);
  if (left.inMinutes < 1) return l.downloadsEtaSoon;
  if (left.inMinutes < 60) return l.downloadsEtaMinutes(left.inMinutes);
  if (left.inHours < 24) {
    final minutes = left.inMinutes % 60;
    return minutes == 0
        ? l.downloadsEtaHours(left.inHours)
        : l.downloadsEtaHoursMinutes(left.inHours, minutes);
  }
  return l.downloadsEtaOn(DateFormat.MMMd(l.localeName).format(eta.toLocal()));
}

String downloadReasonLabel(AppLocalizations l, DownloadReason r) => switch (r) {
  DownloadReason.nothingFound => l.downloadReasonNothingFound,
  DownloadReason.belowMinScore => l.downloadReasonBelowMinScore,
  DownloadReason.importBlocked => l.downloadReasonImportBlocked,
  DownloadReason.searchFailed => l.downloadReasonSearchFailed,
  DownloadReason.grabRefused => l.downloadReasonGrabRefused,
  DownloadReason.unknown => '',
};

String downloadStateLabel(AppLocalizations l, DownloadItem item) {
  switch (item.state) {
    case DownloadState.downloading:
      return l.downloadStateDownloading;
    case DownloadState.upgradeWatch:
      return l.downloadStateUpgradeWatch;
    case DownloadState.needsYou:
      final reason = item.reason;
      final why = reason == null ? '' : downloadReasonLabel(l, reason);
      return why.isEmpty
          ? l.downloadStateNeedsYou
          : l.downloadStateNeedsYouWhy(why);
    case DownloadState.waiting:
    case DownloadState.unknown:
      return l.downloadStateWaiting;
  }
}

/// La frase sotto una riga "Serve te" (spec "Serve te" §4); vuota quando
/// non c'è niente da spiegare. [service] è `Radarr` o `Sonarr`.
String downloadExplanation(
  AppLocalizations l,
  DownloadItem item,
  String service,
) {
  if (item.state != DownloadState.needsYou) return '';
  final summary = item.summary;
  switch (item.reason) {
    case DownloadReason.belowMinScore:
      final best = summary?.bestScore;
      if (summary == null || best == null) return '';
      return l.downloadsExplainLowScore(summary.found, best, summary.minScore);
    case DownloadReason.nothingFound:
      if (summary == null) return '';
      if (summary.found == 0) return l.downloadsExplainNoResults;
      final top = summary.topRejection;
      final parts = [
        if (summary.tooSmall > 0) l.downloadsExplainTooSmall(summary.tooSmall),
        if (summary.arrRejected > 0)
          l.downloadsExplainArrRejected(summary.arrRejected, service) +
              (top == null ? '' : ' ($top)'),
      ];
      // Scartati per altri motivi (es. punteggio): niente da elencare.
      if (parts.isEmpty) return '';
      final text = l.downloadsExplainAllRejected(summary.found, parts.join(', '));
      return summary.stopgapAvailable
          ? '$text ${l.downloadsExplainStopgapHint}'
          : text;
    case DownloadReason.importBlocked:
      final blocked = l.downloadsExplainBlocked(service);
      return item.blockedMessage == null
          ? blocked
          : '$blocked ${l.downloadsExplainBlockedWhy(service)}';
    case DownloadReason.grabRefused:
      return l.downloadsExplainRefused;
    case _:
      return '';
  }
}

String downloadsFailureLabel(AppLocalizations l, DownloadsFailure f) =>
    switch (f) {
      DownloadsFailure.unavailable => l.downloadsFailureUnavailable,
      DownloadsFailure.invalid => l.downloadsFailureInvalid,
      DownloadsFailure.forbidden => l.errorAccountDisabled,
      DownloadsFailure.expired => l.downloadsFailureExpired,
      DownloadsFailure.busy => l.downloadsFailureBusy,
      DownloadsFailure.arrUnavailable => l.downloadsFailureArrUnavailable,
      DownloadsFailure.refused => l.downloadsFailureRefused,
      DownloadsFailure.nothingToGrab => l.downloadsFailureNothingToGrab,
      DownloadsFailure.changed => l.downloadsFailureChanged,
      DownloadsFailure.noFiles => l.downloadsFailureNoFiles,
      DownloadsFailure.importFailed => l.downloadsFailureImportFailed,
      DownloadsFailure.network => l.errorServerUnreachable,
    };

String rejectedLabel(AppLocalizations l, DownloadRejected r) {
  final detail = r.detail ?? '';
  final reason = switch (r.reason) {
    RejectedReason.wrongTitle => l.downloadsRejectedWrongTitle,
    RejectedReason.notWanted => l.downloadsRejectedNotWanted,
    RejectedReason.restricted => l.downloadsRejectedRestricted,
    RejectedReason.blocklisted => l.downloadsRejectedBlocklisted,
    _ => null,
  };
  if (reason != null) {
    return detail.isEmpty
        ? reason
        : l.downloadsRejectedWithDetail(reason, detail);
  }
  if (r.reason != RejectedReason.tooSmall) return detail;
  // Il plugin manda "0.62" col punto: in italiano la virgola.
  final rate = double.tryParse(detail);
  return l.downloadsRejectedTooSmall(
      rate == null ? detail : NumberFormat('0.00', l.localeName).format(rate));
}

/// Perché la regola ha scelto [c] (decisione 2 del piano 29b).
String choiceWhy(AppLocalizations l, DownloadCandidate c) =>
    l.downloadsChoiceWhy(c.release.score, c.release.resolution);

/// "prossima ricerca tra 3 h" / "domani" / "il 2 nov"; vuoto senza data.
String nextSearchLabel(AppLocalizations l, DateTime? at, DateTime now) {
  if (at == null) return '';
  final local = at.toLocal();
  final minutes = local.difference(now).inMinutes;
  if (minutes < 24 * 60) {
    return l.downloadsNextSearchHours(((minutes + 59) ~/ 60).clamp(1, 24));
  }
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 1) return l.downloadsNextSearchTomorrow;
  return l.downloadsNextSearchOn(DateFormat.MMMd(l.localeName).format(local));
}

/// La riga sotto la barra della coda: "In pausa", "Stima in calcolo…" o
/// "Fine stimata (domani | il 12/11) verso le 15:10 (~14 h)".
String backlogEndLabel(AppLocalizations l, SearchProgress p, DateTime now) {
  if (p.manualSearch) return l.downloadsBacklogManualSearch;
  if (p.paused) return l.downloadsBacklogPaused;
  final end = p.estimatedEnd?.toLocal();
  if (end == null) return l.downloadsBacklogEstimating;
  final left = _atLeastZero(end.difference(now));
  final duration = left.inMinutes < 60
      ? l.downloadsDurationMinutes(left.inMinutes)
      : l.downloadsDurationHours((left.inMinutes / 60).round());
  final time = DateFormat.Hm(l.localeName).format(end);
  // Arrotondato: un giorno di cambio dell'ora dura 23 o 25 ore.
  final days = (DateTime(end.year, end.month, end.day)
              .difference(DateTime(now.year, now.month, now.day))
              .inHours /
          24)
      .round();
  return switch (days) {
    <= 0 => l.downloadsBacklogEndToday(time, duration),
    1 => l.downloadsBacklogEndTomorrow(time, duration),
    _ => l.downloadsBacklogEndOn(
      DateFormat('dd/MM').format(end),
      time,
      duration,
    ),
  };
}
