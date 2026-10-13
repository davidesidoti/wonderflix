import 'dart:math';

import 'package:intl/intl.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/jellyfin/library_api.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/activity_models.dart';
import '../../core/social/collections_models.dart';
import '../../core/social/home_models.dart';
import '../../core/social/recommendation_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_row_content.dart';

/// Titoli al massimo in una riga della Home (spec M §8.3).
const homeRowLimit = 20;

/// Saghe al massimo in "Continua la saga".
const homeSagaLimit = 10;

/// Visioni lette per "Perché hai visto X": con molti episodi di fila della
/// stessa serie 10 non bastano a trovare tre titoli diversi (decisione 3 del
/// piano 19b).
const becauseHistoryLimit = 50;

/// Titoli di partenza provati, dal più recente.
const becauseSourcesTried = 3;

/// Simili chiesti a Jellyfin per ogni titolo di partenza.
const becauseSimilarLimit = 30;

/// Con meno simili di così si prova il titolo dopo.
const becauseMinimumItems = 4;

/// Richieste lette per "Le mie richieste".
const homeRequestsTake = 50;

/// Per quanto una richiesta disponibile resta nella riga, dalla creazione.
const recentAvailableRequest = Duration(days: 30);

/// Film visti letti per "Continua la saga".
const playedMoviesLimit = 500;

/// Anno dei titoli senza data d'uscita: in fondo.
const _unknownYear = 9999;

/// Un titolo di partenza di "Perché hai visto X".
typedef BecauseSource = ({String id, String name});

/// I titoli di partenza, dalle ultime visioni: un episodio vale come la sua
/// serie; senza doppioni; al massimo [becauseSourcesTried].
List<BecauseSource> becauseSources(List<JellyfinItem> history) {
  final seen = <String>{};
  final sources = <BecauseSource>[];
  for (final item in history) {
    final BecauseSource? source = switch (item.kind) {
      ItemKind.episode => switch ((item.seriesId, item.seriesName)) {
          (final String id, final String name) => (id: id, name: name),
          _ => null,
        },
      ItemKind.movie => (id: item.id, name: item.name),
      _ => null,
    };
    if (source == null || !seen.add(jellyfinIdKey(source.id))) continue;
    sources.add(source);
    if (sources.length == becauseSourcesTried) break;
  }
  return sources;
}

/// I simili da mostrare: film non visti e serie non finite, senza il titolo
/// di partenza; al massimo [homeRowLimit].
List<JellyfinItem> becauseItems(List<JellyfinItem> similar, String sourceId) {
  final source = jellyfinIdKey(sourceId);
  return [
    for (final item in similar)
      if ((item.kind == ItemKind.movie || item.kind == ItemKind.series) &&
          !item.userData.played &&
          jellyfinIdKey(item.id) != source)
        item,
  ].take(homeRowLimit).toList();
}

/// "Perché hai visto X" (spec M §8.3); `null` se nessun titolo di partenza
/// ha abbastanza simili.
Future<BecauseYouWatchedContent?> loadBecauseYouWatched(
    LibraryApi api, String userId) async {
  final history = await api.playHistory(userId, limit: becauseHistoryLimit);
  for (final source in becauseSources(history)) {
    final items = becauseItems(
        await api.similar(userId, source.id, limit: becauseSimilarLimit),
        source.id);
    if (items.length >= becauseMinimumItems) {
      return BecauseYouWatchedContent(sourceName: source.name, items: items);
    }
  }
  return null;
}

/// Le richieste ancora in corso.
const _openRequests = {
  RequestStatus.pending,
  RequestStatus.approved,
  RequestStatus.downloading,
  RequestStatus.partial,
};

/// "Le mie richieste" (spec M §8.3): prima quelle in corso, poi le
/// disponibili create negli ultimi [recentAvailableRequest]; ognuna dalla
/// più recente. Rifiutate e fallite no.
List<MediaRequest> homeRequests(List<MediaRequest> mine, DateTime now) {
  int newestFirst(MediaRequest a, MediaRequest b) =>
      b.createdAt.compareTo(a.createdAt);
  final open = [
    for (final request in mine)
      if (_openRequests.contains(request.status)) request,
  ]..sort(newestFirst);
  final arrived = [
    for (final request in mine)
      if (request.status == RequestStatus.available &&
          now.difference(request.createdAt) <= recentAvailableRequest)
        request,
  ]..sort(newestFirst);
  return [...open, ...arrived].take(homeRowLimit).toList();
}

/// Una saga da continuare, prima di leggere i suoi titoli: i non visti e
/// quanti sono visti.
typedef SagaCandidate = ({
  CollectionSummary saga,
  List<String> unwatched,
  int watched,
});

/// Le saghe con almeno un film visto e almeno un titolo non visto, contando
/// i soli titoli visibili; dalla saga col film visto più di recente
/// ([playedMovieIds] va dal più recente), a parità per nome; al massimo
/// [homeSagaLimit].
List<SagaCandidate> sagasToContinue(
    List<CollectionSummary> sagas, List<String> playedMovieIds) {
  final recency = <String, int>{};
  for (final (index, id) in playedMovieIds.indexed) {
    recency.putIfAbsent(jellyfinIdKey(id), () => index);
  }
  final found = <({SagaCandidate candidate, int recency})>[];
  for (final saga in sagas) {
    final played = [
      for (final id in saga.itemIds) ?recency[id],
    ];
    final unwatched = [
      for (final id in saga.itemIds)
        if (!recency.containsKey(id)) id,
    ];
    if (played.isEmpty || unwatched.isEmpty) continue;
    found.add((
      candidate: (saga: saga, unwatched: unwatched, watched: played.length),
      recency: played.reduce(min),
    ));
  }
  found.sort((a, b) {
    final byRecency = a.recency.compareTo(b.recency);
    return byRecency != 0
        ? byRecency
        : a.candidate.saga.sortName.compareTo(b.candidate.saga.sortName);
  });
  return [for (final f in found.take(homeSagaLimit)) f.candidate];
}

/// Il prossimo film di una saga: il primo non visto in ordine di uscita
/// (la regola della pagina della saga, spec K §8.2); `null` se nessuno.
JellyfinItem? nextInSaga(List<JellyfinItem> unwatched) {
  DateTime release(JellyfinItem item) =>
      item.premiereDate ?? DateTime.utc(item.productionYear ?? _unknownYear);
  final candidates = [
    for (final item in unwatched)
      if (!item.userData.played) item,
  ]..sort((a, b) {
      final byDate = release(a).compareTo(release(b));
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
  return candidates.isEmpty ? null : candidates.first;
}

/// "Continua la saga" (spec M §8.3): una lettura dei film visti e una sola
/// dei titoli non visti di tutte le saghe scelte.
Future<List<SagaProgress>> loadContinueSaga(
    LibraryApi api, String userId, List<CollectionSummary> sagas) async {
  if (sagas.isEmpty) return const [];
  final played = await api.playedMovies(userId, limit: playedMoviesLimit);
  final candidates =
      sagasToContinue(sagas, [for (final item in played) item.id]);
  if (candidates.isEmpty) return const [];
  final ids = {for (final c in candidates) ...c.unwatched}.toList();
  final byId = {
    for (final item in await api.itemsByIds(userId, ids))
      jellyfinIdKey(item.id): item,
  };
  return [
    for (final c in candidates)
      if (nextInSaga([for (final id in c.unwatched) ?byId[id]])
          case final next?)
        SagaProgress(saga: c.saga, next: next, watched: c.watched),
  ];
}

/// "Consigliati per te" (spec N §7.3): i titoli del plugin, al più
/// [homeRowLimit], letti da Jellyfin in una volta. Restano nell'ordine del
/// plugin; quelli che Jellyfin non dà (cancellati, non più visibili) si
/// saltano.
Future<List<RecommendedItem>> loadRecommended(
    LibraryApi api, String userId, List<Recommendation> recommendations) async {
  final wanted = recommendations.take(homeRowLimit).toList();
  if (wanted.isEmpty) return const [];
  final byId = {
    for (final item
        in await api.itemsByIds(userId, [for (final r in wanted) r.itemId]))
      jellyfinIdKey(item.id): item,
  };
  return [
    for (final r in wanted)
      if (byId[jellyfinIdKey(r.itemId)] case final item?)
        RecommendedItem(item: item, from: r.from),
  ];
}

/// "Visti dagli amici" (spec O §7.4): gli elementi da Jellyfin nell'ordine
/// del plugin; quelli che Jellyfin non dà si saltano.
Future<List<FriendsWatchedItem>> loadFriendsWatched(
    LibraryApi api, String userId, List<FriendsWatched> watched) async {
  final wanted = watched.take(homeRowLimit).toList();
  if (wanted.isEmpty) return const [];
  final byId = {
    for (final item
        in await api.itemsByIds(userId, [for (final w in wanted) w.itemId]))
      jellyfinIdKey(item.id): item,
  };
  return [
    for (final w in wanted)
      if (byId[jellyfinIdKey(w.itemId)] case final item?)
        FriendsWatchedItem(item: item, by: w.by),
  ];
}

/// Il giorno di un'uscita, nel fuso del PC (spec M §8.3): "Oggi" anche se è
/// passata, "Domani", poi giorno della settimana e data.
String upcomingDayLabel(DateTime when, DateTime now, AppLocalizations l) {
  final local = when.toLocal();
  final days = _calendarDays(now.toLocal(), local);
  if (days <= 0) return l.upcomingToday;
  if (days == 1) return l.upcomingTomorrow;
  return DateFormat.MMMEd(l.localeName).format(local);
}

/// "S02E05 · Domani", "S01E05–E06 · Oggi".
String upcomingEpisodeLabel(
    UpcomingEpisode episode, DateTime now, AppLocalizations l) {
  final day = upcomingDayLabel(episode.airDate, now, l);
  final season = _twoDigits(episode.seasonNumber);
  final first = _twoDigits(episode.episodeNumber);
  final last = episode.lastEpisodeNumber;
  return last == null
      ? l.upcomingEpisode(season, first, day)
      : l.upcomingEpisodes(season, first, _twoDigits(last), day);
}

/// "Digitale · 13 ott": una data di calendario, quindi il giorno UTC e non
/// quello del fuso del PC (decisione 5 del piano 19b).
String upcomingMovieLabel(UpcomingMovie movie, AppLocalizations l) {
  final release = movie.digitalRelease.toUtc();
  return l.upcomingDigital(DateFormat.MMMd(l.localeName)
      .format(DateTime(release.year, release.month, release.day)));
}

String _twoDigits(int number) => number.toString().padLeft(2, '0');

/// Giorni di calendario tra le due date (locali), senza l'effetto dell'ora
/// legale.
int _calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
