import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../catalog/catalog_filters_bar.dart';
import 'collection_card.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';

/// Larghezza del campo di ricerca della vista "Saghe".
const collectionsSearchWidth = 280.0;

/// Vista "Saghe" del catalogo Film (spec K §8.4): ricerca per nome,
/// ordinamento e griglia delle saghe. Niente pagine: l'elenco è già tutto in
/// cache ([collectionsProvider]). Ricerca e ordinamento restano nella vista.
class CollectionsGrid extends ConsumerStatefulWidget {
  const CollectionsGrid({super.key});

  @override
  ConsumerState<CollectionsGrid> createState() => _CollectionsGridState();
}

class _CollectionsGridState extends ConsumerState<CollectionsGrid> {
  final _scroll = SmoothScrollController();
  String _query = '';
  CollectionSort _sort = CollectionSort.name;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: collectionsSearchWidth,
                height: filtersBarHeight,
                child: TextField(
                  key: const Key('collections-search'),
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: l.collectionsSearchHint,
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.search,
                        size: 18, color: WfColors.creamMuted),
                  ),
                ),
              ),
              FilterPicker<CollectionSort>(
                value: _sort,
                items: {
                  CollectionSort.name:
                      '${l.catalogSortLabel}: ${l.collectionsSortName}',
                  CollectionSort.size:
                      '${l.catalogSortLabel}: ${l.collectionsSortSize}',
                  CollectionSort.dateAdded:
                      '${l.catalogSortLabel}: ${l.catalogSortDateAdded}',
                },
                onChanged: (sort) => setState(() => _sort = sort),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: WfSwitcher(expand: true, child: _body(l))),
      ],
    );
  }

  /// Contenuto sotto ricerca e ordinamento, con una chiave per stato (per
  /// [WfSwitcher]).
  Widget _body(AppLocalizations l) {
    const muted = TextStyle(color: WfColors.creamMuted);
    final async = ref.watch(collectionsProvider);
    final list = async.value;
    // Con un nuovo tentativo Riverpod tiene l'errore o l'elenco di prima
    // mentre carica: finché non c'è un elenco con delle saghe, uno scheletro
    // (così "Nessuna saga" non compare un attimo dopo che la funzione del
    // plugin passa da sconosciuta a nota, e "Riprova" mostra il caricamento).
    if (async.isLoading && (list == null || list.isEmpty)) {
      return const PosterGridSkeleton(key: ValueKey('loading'));
    }
    if (list == null) {
      final error = async.error;
      if (error != null) {
        return ErrorView(
            key: const ValueKey('error'),
            error: error,
            onRetry: () => ref.invalidate(collectionsProvider));
      }
      return const PosterGridSkeleton(key: ValueKey('loading'));
    }
    if (list.isEmpty) {
      return Center(
          key: const ValueKey('empty'),
          child: Text(l.collectionsEmpty, style: muted));
    }
    final shown = sortCollections(filterCollections(list, _query), _sort);
    if (shown.isEmpty) {
      return Center(
          key: const ValueKey('no-match'),
          child: Text(l.collectionsNoMatch, style: muted));
    }
    return KeyedSubtree(
      key: const ValueKey('data'),
      child: Builder(builder: (context) => _grid(context, shown)),
    );
  }

  Widget _grid(BuildContext context, List<CollectionSummary> shown) {
    // La griglia che esce in dissolvenza non tiene `_scroll` (vedi il catalogo).
    final outgoing = WfSwitcher.isOutgoing(context);
    return CustomScrollView(
      controller: outgoing ? null : _scroll,
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
              (context, i) => CollectionCard(
                  key: ValueKey(shown[i].id), collection: shown[i]),
              childCount: shown.length,
            ),
          ),
        ),
      ],
    );
  }
}
