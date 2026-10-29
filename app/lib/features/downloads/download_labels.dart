import 'package:intl/intl.dart';

import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../../l10n/gen/app_localizations.dart';

const _bytesPerGb = 1000000000;

/// "1,89 GB" (con la virgola in italiano), come le informazioni del file.
String formatGb(AppLocalizations l, int bytes) => l.downloadsGb(
  NumberFormat('0.00', l.localeName).format(bytes / _bytesPerGb),
);

String downloadReasonLabel(AppLocalizations l, DownloadReason r) => switch (r) {
  DownloadReason.nothingFound => l.downloadReasonNothingFound,
  DownloadReason.belowMinScore => l.downloadReasonBelowMinScore,
  DownloadReason.importBlocked => l.downloadReasonImportBlocked,
  DownloadReason.searchFailed => l.downloadReasonSearchFailed,
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

String downloadsFailureLabel(AppLocalizations l, DownloadsFailure f) =>
    switch (f) {
      DownloadsFailure.unavailable => l.downloadsFailureUnavailable,
      DownloadsFailure.invalid => l.downloadsFailureInvalid,
      DownloadsFailure.forbidden => l.errorAccountDisabled,
      DownloadsFailure.expired => l.downloadsFailureExpired,
      DownloadsFailure.busy => l.downloadsFailureBusy,
      DownloadsFailure.arrUnavailable => l.downloadsFailureArrUnavailable,
      DownloadsFailure.refused => l.downloadsFailureRefused,
      DownloadsFailure.network => l.errorServerUnreachable,
    };

String rejectedLabel(AppLocalizations l, DownloadRejected r) {
  final detail = r.detail ?? '';
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
