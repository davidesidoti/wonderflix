import 'dart:ui';

import 'package:intl/intl.dart';

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
    RequestStatus.awaitingRelease => l.requestsStatusAwaitingRelease,
  };
}

/// Il colore dello stato: oro in attesa o in arrivo, crema approvata, verde
/// arrivata, rosso rifiutata o non riuscita (spec I §9.4).
Color requestStatusColor(RequestStatus status) => switch (status) {
      RequestStatus.pending ||
      RequestStatus.downloading ||
      RequestStatus.awaitingRelease =>
        WfColors.gold,
      RequestStatus.approved => WfColors.cream,
      RequestStatus.partial || RequestStatus.available => WfColors.online,
      RequestStatus.declined || RequestStatus.failed => WfColors.error,
    };

/// Una parte della riga delle date; [upcoming] = data dopo oggi (in oro).
typedef RequestDatePart = ({String text, bool upcoming});

/// La riga delle date di una richiesta (piano 25b, decisione 9). Film: giorno
/// UTC di cinema e digitale, niente per finiti o senza nessuna data. Serie:
/// il prossimo episodio, giorno locale. La prima parte comincia maiuscola.
List<RequestDatePart> requestDateParts(
    MediaRequest request, DateTime now, AppLocalizations l) {
  final today = DateTime.utc(now.year, now.month, now.day);
  String fmt(DateTime day) => (day.year == now.year
          ? DateFormat.MMMMd(l.localeName)
          : DateFormat.yMMMMd(l.localeName))
      .format(day);
  final parts = <RequestDatePart>[];
  if (request.mediaType == RequestMediaType.tv) {
    final airing = request.nextAiring?.toLocal();
    if (airing != null) {
      final day = DateTime.utc(airing.year, airing.month, airing.day);
      final season = request.nextSeasonNumber;
      final episode = request.nextEpisodeNumber;
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add((
        text: season != null && episode != null
            ? l.requestsNextEpisode('S${two(season)}E${two(episode)}', fmt(day))
            : l.requestsNextEpisodeDate(fmt(day)),
        upcoming: true,
      ));
    }
  } else {
    final cinema = request.inCinemas?.toUtc();
    final digital = request.digitalRelease?.toUtc();
    final finished = const {
      RequestStatus.available,
      RequestStatus.declined,
      RequestStatus.failed,
    }.contains(request.status);
    if (!finished && (cinema != null || digital != null)) {
      if (cinema != null) {
        final day = DateTime.utc(cinema.year, cinema.month, cinema.day);
        parts.add((
          text: l.requestsInCinemas(fmt(day)),
          upcoming: day.isAfter(today),
        ));
      }
      if (digital == null) {
        parts.add((text: l.requestsDigitalUnknown, upcoming: false));
      } else {
        final day = DateTime.utc(digital.year, digital.month, digital.day);
        final future = day.isAfter(today);
        parts.add((
          text: future
              ? l.requestsDigitalExpected(fmt(day))
              : l.requestsDigitalReleased(fmt(day)),
          upcoming: future,
        ));
      }
    }
  }
  if (parts.isNotEmpty) {
    final first = parts.first.text;
    parts[0] = (
      text: first[0].toUpperCase() + first.substring(1),
      upcoming: parts.first.upcoming,
    );
  }
  return parts;
}
