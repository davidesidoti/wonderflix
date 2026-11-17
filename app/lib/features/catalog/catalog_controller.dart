import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/genre_labels.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../library/library_providers.dart';

class CatalogState {
  const CatalogState({
    required this.query,
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.error,
    this.genre,
  });

  final ItemQuery query;
  final List<JellyfinItem> items;
  final int total;
  final bool loading;
  final Object? error;

  /// L'etichetta del genere mostrato (null: tutto il catalogo).
  final String? genre;

  bool get hasMore => items.length < total;
}

/// Con un genere il cartellone parte dai meglio votati, senza dai più recenti.
CatalogSort catalogDefaultSort(String? genre) =>
    genre == null ? CatalogSort.dateAdded : CatalogSort.rating;

/// Griglia paginata di Film o Serie con ordinamento e filtri.
class CatalogController extends Notifier<CatalogState> {
  CatalogController(this.kind);

  final ItemKind kind;

  static const pageSize = 100;

  int _generation = 0;
  String? _genre;

  /// Non carica da solo: la schermata dice quale genere mostrare con
  /// [showGenre].
  @override
  CatalogState build() {
    _genre = null;
    return CatalogState(
        query: ItemQuery(kinds: {kind}, sort: CatalogSort.dateAdded),
        loading: true);
  }

  /// Mostra [genre] (null: tutto), con l'ordine di partenza del genere; tiene
  /// decennio, stato, visti e ricerca. Con [searchTerm] cerca quello (vuoto:
  /// nessuna ricerca).
  Future<void> showGenre(String? genre, {String? searchTerm}) {
    _genre = genre;
    return _load(
        state.query.copyWith(
          searchTerm: searchTerm == null
              ? state.query.searchTerm
              : (searchTerm.isEmpty ? null : searchTerm),
          genres: genre == null ? const {} : genreServerNames(genre).toSet(),
          sort: catalogDefaultSort(genre),
          reversed: false,
        ),
        reset: true);
  }

  Future<void> setQuery(ItemQuery query) => _load(query, reset: true);

  Future<void> loadMore() async {
    // Dopo un errore si riprova solo dal pulsante, non a ogni scroll.
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load(state.query, reset: false);
  }

  Future<void> retry() => _load(state.query, reset: state.items.isEmpty);

  Future<void> _load(ItemQuery query, {required bool reset}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final previous = reset ? const <JellyfinItem>[] : state.items;
    state = CatalogState(
      query: query,
      items: previous,
      total: reset ? 0 : state.total,
      loading: true,
      genre: _genre,
    );
    try {
      final page = await ref.read(libraryApiProvider).items(
            query,
            userId: ref.read(currentUserIdProvider),
            startIndex: previous.length,
            limit: pageSize,
          );
      if (!ref.mounted || generation != _generation) return;
      state = CatalogState(
          query: query,
          items: [...previous, ...page.items],
          total: page.totalCount,
          genre: _genre);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = CatalogState(
          query: query,
          items: previous,
          total: state.total,
          error: error,
          genre: _genre);
    }
  }
}

final catalogControllerProvider = NotifierProvider.autoDispose
    .family<CatalogController, CatalogState, ItemKind>(CatalogController.new);

final catalogFiltersProvider =
    FutureProvider.autoDispose.family<LibraryFilters, ItemKind>((ref, kind) =>
        ref.watch(libraryApiProvider).filters(ref.watch(currentUserIdProvider), kind));
