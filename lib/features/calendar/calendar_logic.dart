import 'package:intl/intl.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

/// La griglia del mese: sei settimane intere, dal lunedì.
const calendarGridLength = 42;

DateTime calendarMonthOf(DateTime day) => DateTime(day.year, day.month);

DateTime dayKey(DateTime local) => DateTime(local.year, local.month, local.day);

/// I 42 giorni locali a mezzanotte; `DateTime(y, m, d + i)` e non somme di
/// `Duration`, che con l'ora legale sbagliano giorno.
List<DateTime> gridDaysOf(DateTime month) {
  final first = DateTime(month.year, month.month);
  final from = 1 - (first.weekday - DateTime.monday);
  return [
    for (var i = 0; i < calendarGridLength; i++)
      DateTime(month.year, month.month, from + i),
  ];
}

/// Dal primo giorno della griglia al giorno dopo l'ultimo.
({DateTime start, DateTime end}) calendarPeriod(DateTime month) {
  final days = gridDaysOf(month);
  final last = days.last;
  return (
    start: days.first,
    end: DateTime(last.year, last.month, last.day + 1),
  );
}

enum CalendarEntryKind { movie, series }

/// Una voce di un giorno: un film, o tutti gli episodi di una serie.
class CalendarEntry {
  const CalendarEntry({
    required this.kind,
    required this.title,
    this.count = 1,
    this.onServer = false,
    this.posterUrl,
    this.tmdbId,
    this.jellyfinId,
    this.episodes = const [],
    this.movie,
  });

  final CalendarEntryKind kind;
  final String title;
  final int count;
  final bool onServer;
  final String? posterUrl;
  final int? tmdbId;
  final String? jellyfinId;
  final List<UpcomingEpisode> episodes;
  final UpcomingMovie? movie;
}

/// Le voci per giorno. Gli episodi stanno nel giorno locale, i film nel
/// giorno UTC (sono date di calendario a mezzanotte UTC).
Map<DateTime, List<CalendarEntry>> entriesByDay(CalendarPage page) {
  final movies = <DateTime, List<CalendarEntry>>{};
  final groups = <(DateTime, String), List<UpcomingEpisode>>{};
  for (final m in page.movies) {
    final u = m.digitalRelease.toUtc();
    (movies[DateTime(u.year, u.month, u.day)] ??= []).add(
      CalendarEntry(
        kind: CalendarEntryKind.movie,
        title: m.title,
        onServer: m.onServer,
        posterUrl: m.posterUrl ?? m.backdropUrl,
        tmdbId: m.tmdbId,
        jellyfinId: m.jellyfinItemId,
        movie: m,
      ),
    );
  }
  for (final e in page.episodes) {
    final key = e.tvdbId != null
        ? 'tvdb:${e.tvdbId}'
        : e.tmdbId != null
        ? 'tmdb:${e.tmdbId}'
        : 'name:${e.seriesName.toLowerCase()}';
    (groups[(dayKey(e.airDate.toLocal()), key)] ??= []).add(e);
  }

  final result = <DateTime, List<CalendarEntry>>{};
  final series = <DateTime, List<CalendarEntry>>{};
  groups.forEach((k, eps) {
    final first = eps.first;
    (series[k.$1] ??= []).add(
      CalendarEntry(
        kind: CalendarEntryKind.series,
        title: first.seriesName,
        count: eps.fold(
          0,
          (n, e) =>
              n +
              (e.lastEpisodeNumber ?? e.episodeNumber) -
              e.episodeNumber +
              1,
        ),
        onServer: eps.every((e) => e.onServer),
        posterUrl: first.posterUrl ?? first.backdropUrl,
        tmdbId: first.tmdbId,
        jellyfinId: first.jellyfinSeriesId,
        episodes: eps,
      ),
    );
  });
  int byTitle(CalendarEntry a, CalendarEntry b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  for (final day in {...movies.keys, ...series.keys}) {
    result[day] = [
      ...(movies[day] ?? []).toList()..sort(byTitle),
      ...(series[day] ?? []).toList()..sort(byTitle),
    ];
  }
  return result;
}

String calendarEntryLabel(CalendarEntry entry, AppLocalizations l) =>
    entry.kind == CalendarEntryKind.series && entry.count > 1
    ? l.calendarSeriesCount(entry.title, entry.count)
    : entry.title;

String episodeCode(int season, int episode, {int? last}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final base = 'S${two(season)}E${two(episode)}';
  return last == null ? base : '$base–E${two(last)}';
}

/// Dove porta una voce: la scheda della libreria, oppure quella da
/// richiedere (solo con le richieste), altrimenti da nessuna parte.
String? calendarEntryRoute(CalendarEntry entry, {required bool canRequest}) {
  final id = entry.jellyfinId;
  if (id != null) return '/item/$id';
  final tmdb = entry.tmdbId;
  if (tmdb == null || !canRequest) return null;
  return tmdbRoute(
    entry.kind == CalendarEntryKind.movie
        ? RequestMediaType.movie
        : RequestMediaType.tv,
    tmdb,
  );
}

String _capitalized(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String calendarMonthTitle(DateTime month, AppLocalizations l) =>
    _capitalized(DateFormat.yMMMM(l.localeName).format(month));

String calendarDayTitle(DateTime day, AppLocalizations l) =>
    _capitalized(DateFormat.MMMMEEEEd(l.localeName).format(day));
