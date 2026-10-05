import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/requests/requests_models.dart';
import '../search/search_controller.dart';
import 'requests_providers.dart';

class RequestablesState {
  const RequestablesState({
    this.term = '',
    this.titles,
    this.loading = false,
    this.error,
  });

  final String term;

  /// I titoli dell'ultima ricerca riuscita; restano mentre si scrive.
  final List<RequestableTitle>? titles;
  final bool loading;
  final Object? error;
}

/// I titoli per la sezione "Da richiedere" (spec I §8.3): segue il termine
/// della ricerca con la stessa attesa, ma è indipendente, così la libreria
/// non aspetta Seerr. Ogni nuova lettera annulla la ricerca precedente.
class RequestablesController extends Notifier<RequestablesState> {
  Timer? _debounce;
  CancelToken? _cancel;

  @override
  RequestablesState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const RequestablesState();
  }

  void setTerm(String raw, {required String language}) {
    final term = raw.trim();
    _debounce?.cancel();
    _cancel?.cancel();
    if (term.length < SearchController.minLength ||
        !ref.read(requestsAvailableProvider)) {
      state = RequestablesState(term: term);
      return;
    }
    state = RequestablesState(term: term, titles: state.titles, loading: true);
    _debounce = Timer(
        SearchController.debounce, () => unawaited(_search(term, language)));
  }

  /// Rifà subito la ricerca del termine di adesso (dopo un errore).
  void retry({required String language}) {
    final term = state.term;
    if (term.length < SearchController.minLength) return;
    _debounce?.cancel();
    _cancel?.cancel();
    state = RequestablesState(term: term, titles: state.titles, loading: true);
    unawaited(_search(term, language));
  }

  Future<void> _search(String term, String language) async {
    final cancel = _cancel = CancelToken();
    try {
      final titles = await ref
          .read(requestsApiProvider)
          .search(term, language: language, cancelToken: cancel);
      if (!ref.mounted || cancel.isCancelled) return;
      state = RequestablesState(term: term, titles: titles);
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = RequestablesState(term: term, error: error);
    }
  }
}

final requestablesControllerProvider =
    NotifierProvider.autoDispose<RequestablesController, RequestablesState>(
        RequestablesController.new);

/// Quello che la ricerca nella libreria ha già trovato (spec I §8.3), per non
/// ripeterlo in "Da richiedere". Un titolo di Seerr c'è già se ne conosce l'id
/// Jellyfin, ma anche se non lo conosce (dopo la scansione della notte Seerr
/// non ha l'id dei titoli nuovi) e coincidono tipo e id TMDB.
class LibraryMatches {
  const LibraryMatches({
    this.itemIds = const {},
    this.movieTmdbIds = const {},
    this.seriesTmdbIds = const {},
  });

  /// Dai film e dalle serie dei [results]; le persone non contano.
  factory LibraryMatches.fromResults(SearchResults results) => LibraryMatches(
        itemIds: {
          for (final item in [...results.movies, ...results.series])
            item.id.toLowerCase(),
        },
        movieTmdbIds: {for (final movie in results.movies) ?movie.tmdbId},
        seriesTmdbIds: {for (final series in results.series) ?series.tmdbId},
      );

  /// Id Jellyfin dei film e delle serie trovati, in minuscolo.
  final Set<String> itemIds;

  /// Id TMDB dei film trovati.
  final Set<int> movieTmdbIds;

  /// Id TMDB delle serie trovate.
  final Set<int> seriesTmdbIds;

  /// Se la libreria ha già [title]: per id Jellyfin, oppure per id TMDB dello
  /// stesso tipo (un film e una serie possono avere lo stesso id TMDB).
  bool contains(RequestableTitle title) {
    final itemId = title.jellyfinItemId;
    if (itemId != null && itemIds.contains(itemId.toLowerCase())) return true;
    final tmdbIds = switch (title.mediaType) {
      RequestMediaType.movie => movieTmdbIds,
      RequestMediaType.tv => seriesTmdbIds,
    };
    return tmdbIds.contains(title.tmdbId);
  }
}

/// I titoli da mostrare in "Da richiedere" (spec I §8.3): senza quelli che
/// la ricerca nella libreria ha già trovato ([library]).
List<RequestableTitle> visibleRequestables(
        List<RequestableTitle> titles, LibraryMatches library) =>
    [
      for (final title in titles)
        if (!library.contains(title)) title,
    ];
