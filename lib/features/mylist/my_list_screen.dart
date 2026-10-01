import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../catalog/catalog_filters_bar.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import 'my_list_view.dart';

final favoritesProvider = FutureProvider.autoDispose<List<JellyfinItem>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final page = await ref.watch(libraryApiProvider).items(
        const ItemQuery(
          kinds: {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.dateAdded,
          favoritesOnly: true,
          // Ordine e filtri si applicano nell'app (`buildMyListView`).
          includeSortFields: true,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: 500,
      );
  return page.items;
});

/// Spazio tra la barra dei filtri e la griglia.
const _filtersGap = 16.0;

class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  final _scroll = SmoothScrollController();

  /// Ordinamento e filtri scelti: si applicano alla lista già caricata.
  ItemQuery _filters = myListInitialFilters;

  /// Cresce a ogni scelta nella barra: la griglia nuova sostituisce la
  /// vecchia in dissolvenza e le card rientrano. Togliere un cuore non lo
  /// cambia: il titolo sparisce e basta.
  int _revision = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setFilters(ItemQuery filters) => setState(() {
        _filters = filters;
        _revision++;
      });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final overrides = ref.watch(userDataOverridesProvider);
    // Come nel catalogo il titolo sta fermo: sfuma solo quello che sta sotto.
    final (count, content) = ref.watch(favoritesProvider).when(
          loading: () => (
            0,
            const Column(
              key: ValueKey('loading'),
              children: [
                // Lo spazio della barra resta libero: la griglia è dove
                // sarà.
                SizedBox(height: filtersBarHeight + _filtersGap),
                Expanded(child: PosterGridSkeleton()),
              ],
            ),
          ),
          error: (error, _) => (
            0,
            ErrorView(
                key: const ValueKey('error'),
                error: error,
                onRetry: () => ref.invalidate(favoritesProvider)),
          ),
          data: (items) {
            final view = buildMyListView(items, _filters, overrides);
            if (view.listEmpty) return (0, _empty(l));
            return (
              view.items.length,
              KeyedSubtree(
                key: const ValueKey('data'),
                child: Builder(builder: (context) => _content(context, view)),
              ),
            );
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l, count: count),
        Expanded(child: WfSwitcher(expand: true, child: content)),
      ],
    );
  }

  /// Titolo della pagina, fuori dal [WfSwitcher]: non sfuma col contenuto.
  /// Con [count] anche il numero dei titoli mostrati, come nel catalogo.
  Widget _title(AppLocalizations l, {int count = 0}) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(l.navMyList.toUpperCase(), style: WfText.display(40)),
            if (count > 0) ...[
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l.catalogCount(count),
                    style: const TextStyle(color: WfColors.creamMuted)),
              ),
            ],
          ],
        ),
      );

  /// Nessun preferito: niente barra né conteggio.
  Widget _empty(AppLocalizations l) => Padding(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(l.myListEmpty,
            style: const TextStyle(color: WfColors.creamMuted)),
      );

  Widget _content(BuildContext context, MyListView view) {
    final l = AppLocalizations.of(context);
    // Ricaricando la lista, la pagina vecchia sfuma mentre arriva la nuova:
    // `_scroll` va solo alla griglia che entra in entrambi i `WfSwitcher`.
    final leaving = WfSwitcher.isOutgoing(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: CatalogFiltersBar(
            filters: view.options,
            query: _filters,
            onChanged: _setFilters,
          ),
        ),
        const SizedBox(height: _filtersGap),
        Expanded(
          child: WfSwitcher(
            expand: true,
            child: view.items.isEmpty
                ? _noResults(l)
                : KeyedSubtree(
                    key: ValueKey(('grid', _revision)),
                    child: Builder(
                      builder: (context) => _grid(view.items,
                          attachScroll:
                              !leaving && !WfSwitcher.isOutgoing(context)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _noResults(AppLocalizations l) => Center(
        key: const ValueKey('no-results'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.catalogEmpty,
                style: const TextStyle(color: WfColors.creamMuted)),
            if (_filters.hasFilters)
              TextButton(
                onPressed: () => _setFilters(_filters.clearFilters()),
                child: Text(l.catalogClearFilters),
              ),
          ],
        ),
      );

  Widget _grid(List<JellyfinItem> items, {required bool attachScroll}) =>
      BatchedEntrance(
        itemCount: items.length,
        child: CustomScrollView(
          controller: attachScroll ? _scroll : null,
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.55,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => BatchedEntranceItem(
                    index: i,
                    child: PosterCard(item: items[i], heroSource: 'mylist.$i'),
                  ),
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
      );
}
