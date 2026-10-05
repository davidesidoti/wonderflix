import 'dart:ui';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Le stagioni in ordine, quelle di fila unite: "1–3, 5" (spec I §9.4).
String formatSeasonList(Iterable<int> seasons) {
  final sorted = seasons.toSet().toList()..sort();
  if (sorted.isEmpty) return '';
  final runs = <String>[];
  var start = sorted.first;
  var previous = start;
  for (final season in sorted.skip(1)) {
    if (season == previous + 1) {
      previous = season;
      continue;
    }
    runs.add(start == previous ? '$start' : '$start–$previous');
    start = previous = season;
  }
  runs.add(start == previous ? '$start' : '$start–$previous');
  return runs.join(', ');
}

/// L'etichetta dello stato di una richiesta (spec I §9.4).
String requestStatusLabel(AppLocalizations l, MediaRequest request) {
  final progress = request.progress;
  return switch (request.status) {
    RequestStatus.pending => l.requestsStatusPending,
    RequestStatus.approved => l.requestsStatusApproved,
    RequestStatus.downloading => progress == null
        ? l.requestsBadgeComing
        : l.requestsStatusDownloading((progress.clamp(0, 1) * 100).round()),
    RequestStatus.partial => l.requestsPartlyAvailable,
    RequestStatus.available => l.requestsStatusAvailable,
    RequestStatus.declined => l.requestsStatusDeclined,
    RequestStatus.failed => l.requestsStatusFailed,
  };
}

/// Il colore dello stato: oro in attesa o in arrivo, crema approvata, verde
/// arrivata, rosso rifiutata o non riuscita (spec I §9.4).
Color requestStatusColor(RequestStatus status) => switch (status) {
      RequestStatus.pending || RequestStatus.downloading => WfColors.gold,
      RequestStatus.approved => WfColors.cream,
      RequestStatus.partial || RequestStatus.available => WfColors.online,
      RequestStatus.declined || RequestStatus.failed => WfColors.error,
    };
