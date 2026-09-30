import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'catalog_controller.dart';
import 'catalog_filters_bar.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.kind});

  final ItemKind kind;

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
    final provider = catalogControllerProvider(widget.kind);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final title = widget.kind == ItemKind.series ? l.navSeries : l.navMovies;

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
              if (state.total > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(l.catalogCount(state.total),
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: CatalogFiltersBar(
            kind: widget.kind,
            query: state.query,
            onChanged: (query) => unawaited(controller.setQuery(query)),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _body(context, l, state, controller)),
      ],
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, CatalogState state,
      CatalogController controller) {
    if (state.items.isEmpty) {
      if (state.loading) return const LoadingView();
      final error = state.error;
      if (error != null) {
        return ErrorView(error: error, onRetry: () => unawaited(controller.retry()));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.catalogEmpty, style: const TextStyle(color: WfColors.creamMuted)),
            if (state.query.hasFilters)
              TextButton(
                onPressed: () => unawaited(controller.setQuery(
                    ItemQuery(kinds: state.query.kinds, sort: state.query.sort))),
                child: Text(l.catalogClearFilters),
              ),
          ],
        ),
      );
    }
    return CustomScrollView(
      controller: _scroll,
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
              (context, i) => PosterCard(
                item: state.items[i],
                heroSource: 'catalog.${widget.kind.name}.$i',
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
    );
  }
}
