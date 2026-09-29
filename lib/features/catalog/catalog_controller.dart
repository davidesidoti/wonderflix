import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  });

  final ItemQuery query;
  final List<JellyfinItem> items;
  final int total;
  final bool loading;
  final Object? error;

  bool get hasMore => items.length < total;
}

/// Griglia paginata di Film o Serie con ordinamento e filtri.
class CatalogController extends Notifier<CatalogState> {
  CatalogController(this.kind);

  final ItemKind kind;

  static const pageSize = 100;

  int _generation = 0;

  @override
  CatalogState build() {
    final query = ItemQuery(kinds: {kind});
    unawaited(Future.microtask(() => _load(query, reset: true)));
    return CatalogState(query: query, loading: true);
  }

  Future<void> setQuery(ItemQuery query) => _load(query, reset: true);

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
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
          query: query, items: [...previous, ...page.items], total: page.totalCount);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = CatalogState(
          query: query, items: previous, total: state.total, error: error);
    }
  }
}

final catalogControllerProvider = NotifierProvider.autoDispose
    .family<CatalogController, CatalogState, ItemKind>(CatalogController.new);

final catalogFiltersProvider =
    FutureProvider.autoDispose.family<LibraryFilters, ItemKind>((ref, kind) =>
        ref.watch(libraryApiProvider).filters(ref.watch(currentUserIdProvider), kind));
