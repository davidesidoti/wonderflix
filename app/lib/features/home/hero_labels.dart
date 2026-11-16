import 'package:intl/intl.dart';

import '../../core/jellyfin/genre_labels.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'home_rows_logic.dart';

/// "Film · arrivato ieri", "Serie · arrivata il 3 novembre". `null` per un
/// elemento che non è un film o una serie, o senza data di arrivo.
String? heroArrivalLabel(JellyfinItem item, DateTime now, AppLocalizations l) {
  final created = item.dateCreated;
  final isMovie = item.kind == ItemKind.movie;
  if (created == null || !(isMovie || item.kind == ItemKind.series)) {
    return null;
  }
  final local = created.toLocal();
  final days = calendarDays(local, now.toLocal());
  final when = days <= 0
      ? l.heroArrivedToday
      : days == 1
          ? l.heroArrivedYesterday
          : days < 7
              ? DateFormat.EEEE(l.localeName).format(local)
              : l.heroArrivedOn(DateFormat.MMMMd(l.localeName).format(local));
  return isMovie ? l.heroArrivedMovie(when) : l.heroArrivedSeries(when);
}

/// "2026 · 2h 37m · Fantascienza · Mistero": anno, durata o stagioni, al
/// massimo due generi tradotti e senza doppioni. Vuota se non c'è nulla.
String heroMeta(JellyfinItem item, AppLocalizations l) {
  final runtime = item.runtime;
  final seasons = item.childCount;
  return [
    if (item.productionYear != null) '${item.productionYear}',
    if (item.kind == ItemKind.movie && runtime != null) formatRuntime(runtime),
    if (item.kind == ItemKind.series && seasons != null)
      l.detailSeasons(seasons),
    ...displayGenres(item.genres),
  ].join(' · ');
}
