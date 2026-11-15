import '../../core/jellyfin/item_models.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_layout.dart';
import 'home_rows_logic.dart';

/// Un blocco della Home: una riga sola o due righe unite (spec §4).
sealed class HomeSection {
  String get id;
  List<HomeRowKind> get rows;
}

final class RowSection extends HomeSection {
  RowSection(this.kind);

  final HomeRowKind kind;

  @override
  String get id => kind.id;

  @override
  List<HomeRowKind> get rows => [kind];
}

/// Continua a guardare e Prossimi episodi.
final class TonightSection extends HomeSection {
  TonightSection(this.rows);

  @override
  final List<HomeRowKind> rows;

  @override
  String get id => 'tonight';
}

/// Serie in arrivo e Film in arrivo.
final class UpcomingSection extends HomeSection {
  UpcomingSection(this.rows);

  @override
  final List<HomeRowKind> rows;

  @override
  String get id => 'upcoming';
}

const _tonightRows = [HomeRowKind.resume, HomeRowKind.nextUp];
const _upcomingRows = [HomeRowKind.upcomingSeries, HomeRowKind.upcomingMovies];

/// Le sezioni dalle righe visibili: ogni unione sta al posto della prima delle
/// sue righe e contiene quelle presenti, nell'ordine di [visible].
List<HomeSection> homeSections(List<HomeRowKind> visible) {
  final sections = <HomeSection>[];
  final placed = <HomeRowKind>{};
  for (final row in visible) {
    if (placed.contains(row)) continue;
    final group = _tonightRows.contains(row)
        ? _tonightRows
        : _upcomingRows.contains(row)
            ? _upcomingRows
            : null;
    if (group == null) {
      sections.add(RowSection(row));
      continue;
    }
    final rows = [
      for (final r in visible)
        if (group.contains(r)) r,
    ];
    placed.addAll(rows);
    sections.add(
        group == _tonightRows ? TonightSection(rows) : UpcomingSection(rows));
  }
  return sections;
}

/// Un biglietto di Stasera: [resumed] se viene da Continua a guardare.
class TonightTicket {
  const TonightTicket(this.item, {required this.resumed});

  final JellyfinItem item;
  final bool resumed;
}

/// Prima i titoli da riprendere, poi i prossimi episodi, senza le serie (o
/// i titoli) che hanno già un biglietto (spec §6.1).
List<TonightTicket> tonightTickets({
  required List<JellyfinItem> resume,
  required List<JellyfinItem> nextUp,
}) {
  final ids = {for (final i in resume) i.id};
  final series = {
    for (final i in resume)
      if (i.seriesId != null) i.seriesId,
  };
  return [
    for (final i in resume) TonightTicket(i, resumed: true),
    for (final i in nextUp)
      if (!ids.contains(i.id) && !series.contains(i.seriesId))
        TonightTicket(i, resumed: false),
  ];
}

sealed class UpcomingEntry {}

class UpcomingEpisodeEntry extends UpcomingEntry {
  UpcomingEpisodeEntry(this.episode);

  final UpcomingEpisode episode;
}

class UpcomingMovieEntry extends UpcomingEntry {
  UpcomingMovieEntry(this.movie);

  final UpcomingMovie movie;
}

class UpcomingDay {
  const UpcomingDay(this.day, this.entries);

  /// Mezzanotte locale del giorno di calendario.
  final DateTime day;
  final List<UpcomingEntry> entries;
}

/// Le uscite raggruppate per giorno, dal più vicino; nel giorno prima gli
/// episodi poi i film, ognuno nell'ordine d'arrivo. Il giorno di un episodio
/// è locale, quello di un film UTC (spec §8.1).
List<UpcomingDay> upcomingDays({
  required List<UpcomingEpisode> episodes,
  required List<UpcomingMovie> movies,
}) {
  DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  final days = {
    for (final e in episodes) dayOf(e.airDate.toLocal()),
    for (final m in movies) dayOf(m.digitalRelease.toUtc()),
  }.toList();
  // I giorni sono tutti diversi, quindi l'instabilità del sort non conta.
  days.sort();
  return [
    for (final day in days)
      UpcomingDay(day, [
        for (final e in episodes)
          if (dayOf(e.airDate.toLocal()) == day) UpcomingEpisodeEntry(e),
        for (final m in movies)
          if (dayOf(m.digitalRelease.toUtc()) == day) UpcomingMovieEntry(m),
      ]),
  ];
}

/// "S2:E8", "S2:E8–E10".
String upcomingEpisodeCode(UpcomingEpisode e) {
  final last = e.lastEpisodeNumber;
  final range = last != null && last > e.episodeNumber ? '–E$last' : '';
  return 'S${e.seasonNumber}:E${e.episodeNumber}$range';
}

/// "oggi", "domani", "dopodomani" entro due giorni, se no `null`.
String? upcomingDayNote(DateTime day, DateTime now, AppLocalizations l) {
  final days = calendarDays(now.toLocal(), day);
  if (days <= 0) return l.homeDayToday;
  if (days == 1) return l.homeDayTomorrow;
  if (days == 2) return l.homeDayAfterTomorrow;
  return null;
}

/// Minuti che mancano alla fine, arrotondati per eccesso; `null` se il titolo
/// non è iniziato o non ha durata.
int? remainingMinutes(JellyfinItem item) {
  final total = item.runTimeTicks;
  final position = item.userData.playbackPositionTicks;
  if (total == null || position <= 0 || position >= total) return null;
  const minute = 600000000;
  return ((total - position) / minute).ceil();
}
