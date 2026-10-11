import '../../core/jellyfin/display_preferences_api.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_layout.dart';

/// Sposta [row] alla posizione [to], contata dopo averla tolta (come
/// `onReorderItem`); fuori dai limiti va al bordo più vicino. Una riga che
/// non c'è non cambia niente.
List<HomeRowKind> moveRow(List<HomeRowKind> rows, HomeRowKind row, int to) {
  final from = rows.indexOf(row);
  if (from < 0) return rows;
  final next = [...rows]..removeAt(from);
  next.insert(to.clamp(0, next.length), row);
  return next;
}

/// [edited] più gli id di [stored] che l'elenco non mostra: sconosciuti a
/// questa versione, o di righe spente dall'admin (spec M §8.5, note per il
/// 19c). Ognuno resta dopo l'id che lo precedeva in [stored], o in testa.
List<String> keepForeignIds(
    {required List<String> stored, required List<String> edited}) {
  final shown = edited.toSet();
  final result = [...edited];
  // Dove va il prossimo id estraneo: dopo l'ultimo id mostrato incontrato
  // la prima volta; un id ripetuto in [stored] non sposta più il cursore.
  var cursor = 0;
  final seen = <String>{};
  for (final id in stored) {
    if (shown.contains(id)) {
      if (seen.add(id)) cursor = result.indexOf(id) + 1;
    } else if (!result.contains(id)) {
      result.insert(cursor, id);
      cursor++;
    }
  }
  return result;
}

/// La Home dell'utente da salvare: l'ordine e le nascoste dell'elenco, più
/// gli id che l'elenco non mostra (decisione 10 del piano 19c).
HomeUserPrefs homeUserPrefsToSave({
  required List<HomeRowKind> rows,
  required Set<HomeRowKind> hidden,
  required HomeUserPrefs stored,
}) {
  final shown = {for (final row in rows) row.id};
  return HomeUserPrefs(
    rows: keepForeignIds(
        stored: stored.rows, edited: [for (final row in rows) row.id]),
    hidden: {
      for (final row in rows)
        if (hidden.contains(row)) row.id,
      for (final id in stored.hidden)
        if (!shown.contains(id)) id,
    }.toList(),
  );
}

/// L'elenco della card "Home per tutti" (spec M §8.6): le righe accese
/// nell'ordine dell'admin, poi le spente nell'ordine predefinito. `null`:
/// mai impostata, tutte accese.
List<HomeRowKind> adminEditorRows(List<String>? saved) {
  if (saved == null) return [...HomeRowKind.values];
  final on = parseHomeRows(saved);
  return [
    ...on,
    for (final row in HomeRowKind.values)
      if (!on.contains(row)) row,
  ];
}

/// Le righe accese di [saved]; `null` le accende tutte.
Set<HomeRowKind> adminEditorOn(List<String>? saved) =>
    saved == null ? HomeRowKind.values.toSet() : parseHomeRows(saved).toSet();

/// La Home dell'admin da salvare: le righe accese, nell'ordine dell'elenco.
List<String> adminRowsToSave(List<HomeRowKind> rows, Set<HomeRowKind> on) => [
      for (final row in rows)
        if (on.contains(row)) row.id,
    ];

/// La Home dell'admin com'è davvero: `null` vale tutte le righe
/// nell'ordine predefinito; gli id sconosciuti non contano.
List<String> adminRowsEffective(List<String>? saved) => [
      for (final row
          in saved == null ? HomeRowKind.values : parseHomeRows(saved))
        row.id,
    ];

/// Il nome di una riga nell'elenco. "Perché hai visto X" qui non ha un
/// titolo (decisione 2 del piano 19c).
String homeRowName(AppLocalizations l, HomeRowKind row) => switch (row) {
      HomeRowKind.resume => l.homeContinueWatching,
      HomeRowKind.nextUp => l.homeNextUp,
      HomeRowKind.requests => l.homeMyRequests,
      HomeRowKind.latestMovies => l.homeLatestMovies,
      HomeRowKind.latestSeries => l.homeLatestSeries,
      HomeRowKind.becauseYouWatched => l.homeRowsBecauseYouWatched,
      HomeRowKind.continueSaga => l.homeContinueSaga,
      HomeRowKind.upcomingSeries => l.homeUpcomingSeries,
      HomeRowKind.upcomingMovies => l.homeUpcomingMovies,
      HomeRowKind.myList => l.navMyList,
    };

/// La fonte esterna, in piccolo sotto il nome; `null` per le righe di
/// Jellyfin.
String? homeRowSource(AppLocalizations l, HomeRowKind row) => switch (row) {
      HomeRowKind.requests => l.homeRowsSourceSeerr,
      HomeRowKind.upcomingSeries => l.homeRowsSourceSonarr,
      HomeRowKind.upcomingMovies => l.homeRowsSourceRadarr,
      _ => null,
    };

/// Perché una riga non c'è (spec M §6.5, §10); `null` se è disponibile.
String? homeRowGateReason(AppLocalizations l, HomeRowGate gate) =>
    switch (gate) {
      HomeRowGate.available => null,
      HomeRowGate.seerrOff => l.homeRowUnavailableRequests,
      HomeRowGate.noSeerrAccount => l.homeRowUnavailableSeerr,
      HomeRowGate.sagasOff => l.homeRowUnavailableSagas,
      HomeRowGate.sonarrOff => l.homeRowUnavailableSonarr,
      HomeRowGate.radarrOff => l.homeRowUnavailableRadarr,
    };
