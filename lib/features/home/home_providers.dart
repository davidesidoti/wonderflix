import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/display_preferences_api.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/requests/requests_models.dart';
import '../../core/social/home_api.dart';
import '../../core/social/home_models.dart';
import '../../core/social/recommendation_models.dart';
import '../../core/social/social_api.dart';
import '../collections/collections_providers.dart';
import '../library/library_providers.dart';
import '../requests/requests_providers.dart';
import '../social/social_providers.dart';
import 'home_data.dart';
import 'home_layout.dart';
import 'home_row_content.dart';
import 'home_rows_logic.dart';

final _log = Logger('home');

final homeApiProvider =
    Provider<HomeApi>((ref) => HomeApi(ref.watch(jellyfinHttpProvider)));

final displayPreferencesApiProvider = Provider<DisplayPreferencesApi>(
    (ref) => DisplayPreferencesApi(ref.watch(jellyfinHttpProvider)));

/// Per quanto si tengono in memoria, anche senza ascoltatori, le righe che
/// non vengono da Jellyfin e la Home dell'admin (spec M §8.2 punto 5): il
/// tempo conta dalla fine della lettura, non da quando se ne va l'ultimo
/// ascoltatore. Tornando alla Home entro questo tempo non si rileggono.
const homeExternalRefresh = Duration(minutes: 5);

/// Quanto la composizione aspetta le funzioni del plugin, se all'apertura non
/// sono ancora note (decisione 7 del piano 19b).
const homeFeaturesWait = Duration(seconds: 2);

/// Tiene il risultato del provider per [duration] dalla fine della lettura,
/// anche senza ascoltatori. Se il provider è già stato eliminato (nessuno lo
/// guardava più mentre leggeva) non fa nulla: quel risultato non si tiene.
void keepFor(Ref ref, Duration duration) {
  if (!ref.mounted) return;
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}

/// La Home dell'admin (spec M §6.2): solo con la funzione `home`. Senza, o se
/// la lettura fallisce, `null` (vale l'ordine predefinito).
final homeAdminRowsProvider =
    FutureProvider.autoDispose<List<String>?>((ref) async {
  if (!ref.watch(socialAvailabilityProvider.select((f) => f.home))) {
    return null;
  }
  try {
    final rows = await ref.watch(homeApiProvider).layout();
    keepFor(ref, homeExternalRefresh);
    return rows;
  } on Object catch (error) {
    _log.info('Home dell\'admin non letta: ${error.runtimeType}');
    return null;
  }
});

/// La Home dell'utente (spec M §6.3); se non si legge, nessun ritocco. Si
/// rilegge al cambio di utente (profilo).
final homeUserPrefsProvider =
    FutureProvider.autoDispose<HomeUserPrefs>((ref) async {
  try {
    final userId = ref.watch(currentUserIdProvider);
    return await ref.watch(displayPreferencesApiProvider).readHome(userId);
  } on Object catch (error) {
    _log.info('Home dell\'utente non letta: ${error.runtimeType}');
    return HomeUserPrefs.none;
  }
});

/// La Home combinata e le righe da mostrare (spec M §6.4, §6.5, §8.2 punto
/// 1). Si ricompone quando cambiano le funzioni del plugin. Non aspetta
/// Seerr: finché `/Me` non risponde, o se non risponde, "Le mie richieste"
/// non c'è e le altre righe si vedono; quando risponde, la Home si
/// ricompone e la riga si aggiunge.
final homeLayoutProvider = FutureProvider.autoDispose<HomeLayout>((ref) async {
  final features = ref.watch(socialAvailabilityProvider);
  final adminRows = ref.watch(homeAdminRowsProvider.future);
  final userPrefs = ref.watch(homeUserPrefsProvider.future);
  var hasSeerrAccount = false;
  if (features.requests) {
    final me = ref.watch(requestsMeProvider);
    if (me.hasError && !me.hasValue) {
      _log.info('Seerr non letto: ${me.error.runtimeType}');
    }
    hasSeerrAccount = me.value?.hasAccount ?? false;
  }
  if (!features.known) {
    // Il timer dell'attesa è del notifier delle funzioni, non di questo
    // provider: finisce appena le funzioni sono note, allo scadere di
    // [homeFeaturesWait] o quando il notifier si chiude. Se la Home si chiude
    // prima, può restare in sospeso fino a 2 s e poi finisce da solo.
    await ref
        .read(socialAvailabilityProvider.notifier)
        .whenKnown(homeFeaturesWait);
  }
  return composeHomeLayout(
    adminRows: await adminRows,
    user: await userPrefs,
    available: (row) =>
        homeRowGate(row, features, seerrAccount: hasSeerrAccount) ==
        HomeRowGate.available,
  );
});

Future<List<JellyfinItem>> _latest(Ref ref, ItemKind kind) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  return api
      .items(ItemQuery(kinds: {kind}, sort: CatalogSort.dateAdded),
          userId: userId, startIndex: 0, limit: homeRowLimit)
      .then((page) => page.items);
}

final homeLatestMoviesProvider = FutureProvider.autoDispose<List<JellyfinItem>>(
    (ref) => _latest(ref, ItemKind.movie));

final homeLatestSeriesProvider = FutureProvider.autoDispose<List<JellyfinItem>>(
    (ref) => _latest(ref, ItemKind.series));

/// Il carosello (spec M §6.1): i titoli aggiunti di recente, anche se
/// l'utente nasconde quelle righe. Con una lettura fallita restano i titoli
/// dell'altra; con tutte e due, l'errore (decisione 9 del piano 19b).
final homeFeaturedProvider =
    FutureProvider.autoDispose<List<JellyfinItem>>((ref) async {
  Object? failure;
  Future<List<JellyfinItem>?> guarded(Future<List<JellyfinItem>> future) =>
      future.then<List<JellyfinItem>?>((items) => items,
          onError: (Object error) {
        _log.info('Carosello: lettura non riuscita: ${error.runtimeType}');
        failure = error;
        return null;
      });
  final movies = guarded(ref.watch(homeLatestMoviesProvider.future));
  final series = guarded(ref.watch(homeLatestSeriesProvider.future));
  final movieItems = await movies;
  final seriesItems = await series;
  if (movieItems == null && seriesItems == null) throw failure!;
  return pickFeatured(movieItems ?? const [], seriesItems ?? const []);
});

/// Una riga della Home: il tipo e la lingua delle richieste (decisione 8
/// del piano 19b).
typedef HomeRowKey = ({HomeRowKind kind, String language});

/// Il contenuto di una riga (spec M §8.3). Un provider per riga: le righe
/// nascoste o non disponibili non sono guardate, quindi non chiamano.
final homeRowProvider = FutureProvider.autoDispose
    .family<HomeRowContent, HomeRowKey>((ref, key) async {
  switch (key.kind) {
    case HomeRowKind.latestMovies:
      return ItemsRowContent(await ref.watch(homeLatestMoviesProvider.future));
    case HomeRowKind.latestSeries:
      return ItemsRowContent(await ref.watch(homeLatestSeriesProvider.future));
    case HomeRowKind.requests:
      // L'API non cambia con l'utente (cambia il token sotto): senza questo
      // la riga tenuta in memoria passerebbe al profilo successivo.
      ref.watch(currentUserIdProvider);
      final api = ref.watch(requestsApiProvider);
      final page = await api.list(RequestsFilter.mine,
          skip: 0, take: homeRequestsTake, language: key.language);
      keepFor(ref, homeExternalRefresh);
      return RequestsRowContent(homeRequests(page.items, clock.now()));
    case HomeRowKind.upcomingSeries:
      ref.watch(currentUserIdProvider); // come per le richieste
      final page = await ref.watch(homeApiProvider).upcomingSeries();
      keepFor(ref, homeExternalRefresh);
      _logUpcoming('serie', page.error);
      return UpcomingSeriesRowContent(
          page.items.take(homeRowLimit).toList());
    case HomeRowKind.upcomingMovies:
      ref.watch(currentUserIdProvider); // come per le richieste
      final page = await ref.watch(homeApiProvider).upcomingMovies();
      keepFor(ref, homeExternalRefresh);
      _logUpcoming('film', page.error);
      return UpcomingMoviesRowContent(page.items.take(homeRowLimit).toList());
    case HomeRowKind.recommended:
      // Niente `keepFor`: si rilegge a ogni apertura della Home (piano 20b,
      // decisione 3). Tutti i watch prima dell'attesa.
      // La Home resta montata sotto /item/:id: si rilegge se cambiano i dati.
      ref.watch(libraryRevisionProvider);
      ref.watch(userDataRevisionProvider);
      final userId = ref.watch(currentUserIdProvider);
      final api = ref.watch(libraryApiProvider);
      final social = ref.watch(socialApiProvider);
      final List<Recommendation> recommendations;
      try {
        recommendations = await social.recommendations();
      } catch (error) {
        _log.info('consigli non disponibili: '
            '${error is SocialException ? error.failure.name : error.runtimeType}');
        rethrow; // la riga resta in errore, quindi nascosta
      }
      return RecommendedRowContent(
          await loadRecommended(api, userId, recommendations));
    case HomeRowKind.resume ||
          HomeRowKind.nextUp ||
          HomeRowKind.myList ||
          HomeRowKind.becauseYouWatched ||
          HomeRowKind.continueSaga:
      return _libraryRow(ref, key.kind);
  }
});

/// Le righe di Jellyfin: si rileggono quando cambiano la libreria o i dati
/// dell'utente (spec M §8.2 punto 5).
Future<HomeRowContent> _libraryRow(Ref ref, HomeRowKind kind) async {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  switch (kind) {
    case HomeRowKind.resume:
      return ItemsRowContent(await api.resume(userId, limit: homeRowLimit));
    case HomeRowKind.nextUp:
      return ItemsRowContent(await api.nextUp(userId,
          limit: homeRowLimit, dateCutoff: nextUpCutoff(clock.now())));
    case HomeRowKind.myList:
      final page = await api.items(
          const ItemQuery(
              kinds: {ItemKind.movie, ItemKind.series},
              sort: CatalogSort.dateAdded,
              favoritesOnly: true),
          userId: userId,
          startIndex: 0,
          limit: homeRowLimit);
      return ItemsRowContent(page.items);
    case HomeRowKind.becauseYouWatched:
      return await loadBecauseYouWatched(api, userId) ??
          const ItemsRowContent([]);
    case HomeRowKind.continueSaga:
      final sagas = ref.watch(collectionsProvider.future);
      return SagasRowContent(await loadContinueSaga(api, userId, await sagas));
    case HomeRowKind.latestMovies ||
          HomeRowKind.latestSeries ||
          HomeRowKind.recommended ||
          HomeRowKind.requests ||
          HomeRowKind.upcomingSeries ||
          HomeRowKind.upcomingMovies:
      throw StateError('non è una riga della libreria: $kind');
  }
}

void _logUpcoming(String what, UpcomingError? error) {
  if (error != null) _log.info('$what in arrivo non disponibili: ${error.wire}');
}
