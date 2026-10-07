import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../../ui/wf_tab_button.dart';
import '../collections/collections_grid.dart';
import '../collections/collections_providers.dart';
import '../social/social_providers.dart';
import 'catalog_controller.dart';
import 'catalog_filters_bar.dart';

/// Vista del catalogo Film: i titoli o le saghe (spec K §8.4). Sta
/// nell'indirizzo (`/movies?view=sagas`).
enum CatalogView {
  titles,
  sagas;

  static CatalogView parse(String? value) => value == 'sagas' ? sagas : titles;
}

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen(
      {super.key, required this.kind, this.view = CatalogView.titles});

  final ItemKind kind;

  /// Solo per i film. Senza la funzione `collections` del plugin vale come
  /// [CatalogView.titles].
  final CatalogView view;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _scroll = SmoothScrollController();

  /// Numero di elementi al momento dell'ultimo caricamento automatico: evita
  /// un ciclo infinito se il server risponde con pagine vuote.
  int _autoLoadedAt = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) {
        unawaited(
            ref.read(catalogControllerProvider(widget.kind).notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sagasAvailable = widget.kind == ItemKind.movie &&
        ref.watch(socialAvailabilityProvider
            .select((features) => features.collections));
    final sagas = sagasAvailable && widget.view == CatalogView.sagas;
    final title = widget.kind == ItemKind.series ? l.navSeries : l.navMovies;
    final String? count;
    if (sagas) {
      final list = ref.watch(collectionsProvider).value;
      count = list == null || list.isEmpty
          ? null
          : l.collectionsCount(list.length);
    } else {
      final total = ref.watch(catalogControllerProvider(widget.kind)).total;
      count = total > 0 ? l.catalogCount(total) : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title.toUpperCase(), style: WfText.display(40)),
              const SizedBox(width: 16),
              if (count != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(count,
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
            ],
          ),
        ),
        if (sagasAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
            child: Row(
              children: [
                WfTabButton(
                    label: l.navMovies,
                    selected: !sagas,
                    onTap: () => context.go('/movies')),
                const SizedBox(width: 20),
                WfTabButton(
                    label: l.collectionsTab,
                    selected: sagas,
                    onTap: () => context.go('/movies?view=sagas')),
              ],
            ),
          ),
        if (sagas)
          const Expanded(child: CollectionsGrid())
        else
          ..._titles(context, l),
      ],
    );
  }

  /// Filtri e griglia dei titoli.
  List<Widget> _titles(BuildContext context, AppLocalizations l) {
    final provider = catalogControllerProvider(widget.kind);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final filters = ref.watch(catalogFiltersProvider(widget.kind)).value ??
        const LibraryFilters();

    // Su schermi grandi la prima pagina può non riempire la finestra: senza
    // scroll non scatterebbe mai il caricamento successivo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current = ref.read(provider);
      if (current.items.isEmpty) _autoLoadedAt = -1; // nuova query
      if (_scroll.position.maxScrollExtent == 0 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(controller.loadMore());
      }
    });

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: CatalogFiltersBar(
          filters: filters,
          query: state.query,
          onChanged: (query) => unawaited(controller.setQuery(query)),
        ),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: WfSwitcher(
          expand: true,
          child: _body(context, l, state, controller),
        ),
      ),
    ];
  }

  /// Contenuto sotto i filtri, con una chiave per stato (per [WfSwitcher]).
  Widget _body(BuildContext context, AppLocalizations l, CatalogState state,
      CatalogController controller) {
    if (state.items.isEmpty) {
      if (state.loading) {
        return const PosterGridSkeleton(key: ValueKey('loading'));
      }
      final error = state.error;
      if (error != null) {
        return ErrorView(
            key: const ValueKey('error'),
            error: error,
            onRetry: () => unawaited(controller.retry()));
      }
      return Center(
        key: const ValueKey('empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.catalogEmpty, style: const TextStyle(color: WfColors.creamMuted)),
            if (state.query.hasFilters)
              TextButton(
                onPressed: () => unawaited(
                    controller.setQuery(state.query.clearFilters())),
                child: Text(l.catalogClearFilters),
              ),
          ],
        ),
      );
    }
    // Cambiando i filtri la griglia vecchia sfuma mentre arriva la nuova:
    // `_scroll` va solo a quella che entra (vedi `WfSwitcher.isOutgoing`).
    return KeyedSubtree(
      key: const ValueKey('data'),
      child: Builder(
        builder: (context) => _grid(context, l, state, controller),
      ),
    );
  }

  Widget _grid(BuildContext context, AppLocalizations l, CatalogState state,
      CatalogController controller) {
    final outgoing = WfSwitcher.isOutgoing(context);
    // Entrano solo le card di ogni pagina nuova; cambiando i filtri si
    // riparte dall'inizio.
    return BatchedEntrance(
      itemCount: state.items.length,
      resetKey: state.query,
      child: CustomScrollView(
        controller: outgoing ? null : _scroll,
        primary: false,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
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
                  child: PosterCard(
                    item: state.items[i],
                    heroSource: 'catalog.${widget.kind.name}.$i',
                  ),
                ),
                childCount: state.items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: state.loading
                  ? const LoadingView()
                  : state.error != null
                      ? Center(
                          child: TextButton(
                            onPressed: () => unawaited(controller.retry()),
                            child: Text(l.retry),
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
