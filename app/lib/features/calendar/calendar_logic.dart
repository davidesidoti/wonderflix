import 'dart:math';

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

/// Oggi e i sei giorni dopo, a mezzanotte locale.
List<DateTime> calendarWeekDays(DateTime today) {
  final t = dayKey(today);
  return [for (var i = 0; i < 7; i++) DateTime(t.year, t.month, t.day + i)];
}

/// I 7 giorni da oggi; `end` è escluso.
({DateTime start, DateTime end}) calendarWeekPeriod(DateTime today) {
  final t = dayKey(today);
  return (start: t, end: DateTime(t.year, t.month, t.day + 7));
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

/// Se l'uscita è già arrivata, manca o deve ancora uscire.
enum CalendarEntryState { arrived, missing, upcoming }

CalendarEntryState episodeState(UpcomingEpisode e, DateTime now) =>
    e.airDate.isAfter(now)
    ? CalendarEntryState.upcoming
    : e.onServer
    ? CalendarEntryState.arrived
    : CalendarEntryState.missing;

/// [day] è la chiave del giorno della casella: un film vale da tutto il suo
/// giorno; una serie dall'ora dei suoi episodi.
CalendarEntryState calendarEntryState(
  CalendarEntry entry, {
  required DateTime day,
  required DateTime now,
}) {
  if (entry.kind == CalendarEntryKind.movie || entry.episodes.isEmpty) {
    if (day.isAfter(dayKey(now))) return CalendarEntryState.upcoming;
    return entry.onServer
        ? CalendarEntryState.arrived
        : CalendarEntryState.missing;
  }
  final states = [for (final e in entry.episodes) episodeState(e, now)];
  if (states.contains(CalendarEntryState.missing)) {
    return CalendarEntryState.missing;
  }
  return states.contains(CalendarEntryState.upcoming)
      ? CalendarEntryState.upcoming
      : CalendarEntryState.arrived;
}

/// Una riga dell'elenco: un film, o un episodio (o blocco) di una serie.
class CalendarRow {
  const CalendarRow(this.entry, [this.episode]);
  final CalendarEntry entry;
  final UpcomingEpisode? episode;
}

/// Lo stato di una riga: un film come la sua casella, un episodio dalla sua ora.
CalendarEntryState calendarRowState(
  CalendarRow row, {
  required DateTime day,
  required DateTime now,
}) => row.episode == null
    ? calendarEntryState(row.entry, day: day, now: now)
    : episodeState(row.episode!, now);

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

int _byAirTime(UpcomingEpisode a, UpcomingEpisode b) {
  final t = a.airDate.compareTo(b.airDate);
  if (t != 0) return t;
  final n = _byName(a.seriesName, b.seriesName);
  if (n != 0) return n;
  final s = a.seasonNumber.compareTo(b.seasonNumber);
  return s != 0 ? s : a.episodeNumber.compareTo(b.episodeNumber);
}

/// Ordine delle righe: prima i film (per nome), poi gli episodi per ora.
List<CalendarRow> calendarRows(List<CalendarEntry> entries) {
  // Le serie senza episodi (solo dati di test) vanno coi film.
  final plain = [
    for (final e in entries)
      if (e.kind == CalendarEntryKind.movie || e.episodes.isEmpty) e,
  ]..sort((a, b) => _byName(a.title, b.title));
  final episodes = [
    for (final e in entries)
      for (final ep in e.episodes) CalendarRow(e, ep),
  ]..sort((a, b) => _byAirTime(a.episode!, b.episode!));
  return [for (final e in plain) CalendarRow(e), ...episodes];
}

/// `null` per un titolo mancante o segnaposto ("TBA", "TBD").
String? episodeTitleOrNull(String? title) {
  final t = title?.trim();
  if (t == null || t.isEmpty) return null;
  final u = t.toUpperCase();
  return u == 'TBA' || u == 'TBD' ? null : t;
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
    eps.sort(_byAirTime);
    final first = eps.first;
    (series[k.$1] ??= []).add(
      CalendarEntry(
        kind: CalendarEntryKind.series,
        title: first.seriesName,
        // Almeno uno a blocco, anche con dati sbagliati del plugin.
        count: eps.fold(
          0,
          (n, e) =>
              n +
              max(
                1,
                (e.lastEpisodeNumber ?? e.episodeNumber) - e.episodeNumber + 1,
              ),
        ),
        onServer: eps.every((e) => e.onServer),
        posterUrl: first.posterUrl ?? first.backdropUrl,
        tmdbId: first.tmdbId,
        jellyfinId: first.jellyfinSeriesId,
        episodes: eps,
      ),
    );
  });
  int byTime(CalendarEntry a, CalendarEntry b) {
    final t = a.episodes.first.airDate.compareTo(b.episodes.first.airDate);
    return t != 0 ? t : _byName(a.title, b.title);
  }

  for (final day in {...movies.keys, ...series.keys}) {
    result[day] = [
      ...(movies[day] ?? []).toList()
        ..sort((a, b) => _byName(a.title, b.title)),
      ...(series[day] ?? []).toList()..sort(byTime),
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
