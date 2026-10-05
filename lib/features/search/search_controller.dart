import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../library/library_providers.dart';

class SearchResults {
  const SearchResults({
    required this.movies,
    required this.series,
    required this.people,
  });

  final List<JellyfinItem> movies;
  final List<JellyfinItem> series;
  final List<JellyfinItem> people;

  bool get isEmpty => movies.isEmpty && series.isEmpty && people.isEmpty;
}

class SearchState {
  const SearchState({this.term = '', this.results, this.loading = false, this.error});

  final String term;
  final SearchResults? results;
  final bool loading;
  final Object? error;
}

/// Ricerca con attesa di 300 ms: ogni nuova lettera annulla la precedente.
class SearchController extends Notifier<SearchState> {
  static const debounce = Duration(milliseconds: 300);
  static const minLength = 2;

  Timer? _debounce;
  CancelToken? _cancel;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const SearchState();
  }

  void setTerm(String raw) {
    final term = raw.trim();
    _debounce?.cancel();
    _cancel?.cancel();
    if (term.length < minLength) {
      state = SearchState(term: term);
      return;
    }
    state = SearchState(term: term, results: state.results, loading: true);
    _debounce = Timer(debounce, () => unawaited(_search(term)));
  }

  Future<void> _search(String term) async {
    final cancel = _cancel = CancelToken();
    try {
      // Letti qui dentro: un timer scattato dopo il logout non deve lanciare.
      final api = ref.read(libraryApiProvider);
      final userId = ref.read(currentUserIdProvider);
      Future<List<JellyfinItem>> items(ItemKind kind) async => (await api.items(
            // `ProviderIds`: l'id TMDB serve a nascondere in "Da richiedere"
            // i titoli che Seerr non sa ancora in libreria.
            ItemQuery(
                kinds: {kind}, searchTerm: term, includeProviderIds: true),
            userId: userId,
            startIndex: 0,
            limit: 24,
            cancelToken: cancel,
          ))
              .items;
      final results = await Future.wait([
        items(ItemKind.movie),
        items(ItemKind.series),
        api.searchPeople(userId, term, limit: 12, cancelToken: cancel),
      ]);
      if (!ref.mounted || cancel.isCancelled) return;
      state = SearchState(
        term: term,
        results: SearchResults(
            movies: results[0], series: results[1], people: results[2]),
      );
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = SearchState(term: term, error: error);
    }
  }
}

final searchControllerProvider =
    NotifierProvider.autoDispose<SearchController, SearchState>(SearchController.new);
