import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_shell.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../catalog/catalog_band.dart';
import '../catalog/catalog_filters_bar.dart';
import '../catalog/catalog_tools.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';
import 'saga_fan_card.dart';

/// Larghezza del campo di ricerca della vista "Saghe".
const collectionsSearchWidth = 260.0;

/// Vista "Saghe" del catalogo Film (spec §9): cartellone, attrezzi (fermi in
/// cima fuori dalla TV) e griglia delle saghe a ventaglio. Niente pagine:
/// l'elenco è già tutto in cache ([collectionsProvider]). Ricerca, ordine e
/// filtro restano nella vista.
class CollectionsGrid extends ConsumerStatefulWidget {
  const CollectionsGrid({super.key, required this.tabs, required this.height});

  /// Le schede FILM / SAGHE del cartellone.
  final Widget tabs;

  /// Altezza del cartellone ([catalogBandHeight]).
  final double height;

  @override
  ConsumerState<CollectionsGrid> createState() => _CollectionsGridState();
}

class _CollectionsGridState extends ConsumerState<CollectionsGrid> {
  final _scroll = SmoothScrollController();
  String _query = '';
  CollectionSort _sort = CollectionSort.name;
  bool _reversed = false;
  bool _hideDone = false;

  /// Di quanto scorre la pagina prima che gli attrezzi si fermino in cima.
  double _bandScroll = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Cambia ricerca, ordine o filtro e riparte dall'inizio dell'elenco, con
  /// il cartellone chiuso se lo era (gli attrezzi restano dove sono).
  void _update(VoidCallback change) {
    setState(change);
    if (_scroll.hasClients && _scroll.offset > _bandScroll) {
      _scroll.jumpTo(_bandScroll);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final tv = form.tv;
    final list = ref.watch(collectionsProvider).value;
    final items = ref.watch(sagaItemsProvider).value;
    // Come la vista dei titoli: la testata ferma lascia sopra di sé lo
    // spazio della barra in alto.
    final barGap = tv
        ? 0.0
        : (form.compact ? shellCompactBarHeight : shellBarHeight) +
              MediaQuery.paddingOf(context).top;
    _bandScroll = max(0, widget.height - barGap);
    final side = tv ? 24.0 : (form.compact ? 16.0 : 32.0);

    final band = CatalogBand(
      title: l.collectionsTab,
      height: widget.height,
      tabs: widget.tabs,
      hero: _hero(list, items),
      line: _line(l, list, items),
    );
    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: barGap),
        ColoredBox(
          color: WfColors.bg,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: _tools(l, form),
          ),
        ),
      ],
    );
    final (kind, body) = _body(l, side, list, items);
    return CustomScrollView(
      controller: _scroll,
      primary: false,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: _bandScroll,
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: widget.height,
              maxHeight: widget.height,
              child: band,
            ),
          ),
        ),
        if (tv)
          SliverToBoxAdapter(child: bar)
        else
          PinnedHeaderSliver(child: bar),
        // Ogni stato nuovo (scheletro, errore, vuoto, saghe) entra in
        // dissolvenza, come la griglia dei titoli.
        TweenAnimationBuilder<double>(
          key: ValueKey(kind),
          tween: Tween(begin: 0, end: 1),
          duration: WfMotion.of(context).duration(WfMotion.medium),
          builder: (context, opacity, child) =>
              SliverOpacity(opacity: opacity, sliver: child),
          child: body,
        ),
      ],
    );
  }

  /// Il fondale del primo film con un fondale della saga aggiunta più di
  /// recente (o della prima saga, andando indietro, che ne ha uno).
  JellyfinItem? _hero(
    List<CollectionSummary>? list,
    Map<String, JellyfinItem>? items,
  ) {
    if (list == null || items == null) return null;
    for (final saga in sortCollections(list, CollectionSort.added)) {
      final hero = catalogBandHero(sagaFilms(saga, items));
      if (hero != null) return hero;
    }
    return null;
  }

  /// "**100 saghe**, 23 finite."; finché i film non ci sono, solo il numero.
  InlineSpan? _line(
    AppLocalizations l,
    List<CollectionSummary>? list,
    Map<String, JellyfinItem>? items,
  ) {
    if (list == null || list.isEmpty) return null;
    const bold = TextStyle(color: WfColors.cream, fontWeight: FontWeight.w600);
    if (items == null) {
      return TextSpan(text: l.collectionsCount(list.length), style: bold);
    }
    final done = list.where((saga) => sagaDone(saga, items)).length;
    final text = l.sagasBandLine(list.length, done);
    final comma = text.indexOf(',');
    final count = comma < 0 ? text : text.substring(0, comma);
    return TextSpan(
      children: [
        TextSpan(text: count, style: bold),
        TextSpan(text: text.substring(count.length)),
      ],
    );
  }

  Widget _tools(AppLocalizations l, FormFactor form) {
    final controls = <Widget>[
      FilterPicker<CollectionSort>(
        value: _sort,
        items: {
          for (final (sort, name) in [
            (CollectionSort.name, l.collectionsSortName),
            (CollectionSort.added, l.collectionsSortAdded),
            (CollectionSort.size, l.collectionsSortSize),
          ])
            sort: form.compact ? name : '${l.catalogSortShort}: $name',
        },
        // Cambiare ordine riparte dal verso naturale.
        onChanged: (sort) => _update(() {
          _sort = sort;
          _reversed = false;
        }),
      ),
      IconButton(
        tooltip: l.catalogReverse,
        onPressed: () => _update(() => _reversed = !_reversed),
        icon: Icon(
          _reversed ? LucideIcons.arrowUp : LucideIcons.arrowDown,
          size: 18,
        ),
      ),
      CatalogSwitch(
        on: _hideDone,
        label: l.sagasHideDone,
        onToggle: () => _update(() => _hideDone = !_hideDone),
      ),
    ];
    final search = SizedBox(
      height: 36,
      child: TextField(
        key: const Key('collections-search'),
        onChanged: (value) => _update(() => _query = value),
        style: const TextStyle(fontSize: 13, color: WfColors.cream),
        decoration: InputDecoration(
          isDense: true,
          hintText: l.collectionsSearchHint,
          prefixIcon: const Icon(
            LucideIcons.search,
            size: 16,
            color: WfColors.creamMuted,
          ),
        ),
      ),
    );
    final wrap = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: controls,
    );
    final Widget row;
    if (form.tv) {
      // Sulla TV niente ricerca: c'è Cerca nella barra laterale.
      row = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 12, children: controls),
      );
    } else if (form.compact) {
      row = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [wrap, search],
      );
    } else {
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: wrap),
          const SizedBox(width: 12),
          SizedBox(width: collectionsSearchWidth, child: search),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: form.tv ? 6 : 10),
      child: row,
    );
  }

  /// Il contenuto sotto gli attrezzi e il nome del suo stato (per la
  /// dissolvenza).
  (String, Widget) _body(
    AppLocalizations l,
    double side,
    List<CollectionSummary>? list,
    Map<String, JellyfinItem>? items,
  ) {
    const muted = TextStyle(color: WfColors.creamMuted);
    Widget message(String text) => SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      sliver: SliverToBoxAdapter(
        child: Center(child: Text(text, style: muted)),
      ),
    );
    final skeleton = (
      'loading',
      SliverPadding(
        padding: const EdgeInsets.only(top: 16),
        sliver: SliverToBoxAdapter(
          child: PosterGridSkeleton(shrinkWrap: true, catalogSide: side),
        ),
      ),
    );
    final async = ref.watch(collectionsProvider);
    final noSagas = list == null || list.isEmpty;
    // Con un nuovo tentativo Riverpod tiene l'errore o l'elenco di prima
    // mentre carica: finché non c'è un elenco con delle saghe, uno scheletro
    // (così "Nessuna saga" non compare un attimo dopo che la funzione del
    // plugin passa da sconosciuta a nota, e "Riprova" mostra il caricamento).
    if (async.isLoading && noSagas) return skeleton;
    // Senza saghe da mostrare l'errore vince anche sull'elenco vuoto di prima
    // (Riverpod lo tiene nell'errore): Riprova, non "Nessuna saga".
    final error = async.error;
    if (error != null && noSagas) {
      return (
        'error',
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          sliver: SliverToBoxAdapter(
            child: ErrorView(
              error: error,
              onRetry: () => ref.invalidate(collectionsProvider),
            ),
          ),
        ),
      );
    }
    if (list == null) return skeleton;
    if (list.isEmpty) return ('empty', message(l.collectionsEmpty));
    var shown = filterCollections(list, _query);
    if (_hideDone && items != null) {
      shown = [
        for (final saga in shown)
          if (!sagaDone(saga, items)) saga,
      ];
    }
    shown = sortCollections(shown, _sort);
    if (_reversed) shown = shown.reversed.toList();
    if (shown.isEmpty) return ('no-match', message(l.collectionsNoMatch));
    return (
      'data',
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, 22, side, 36),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            const maxWidth = 220.0, gap = 22.0;
            final extent = constraints.crossAxisExtent;
            final columns = (extent / (maxWidth + gap)).ceil();
            final width = (extent - gap * (columns - 1)) / columns;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: maxWidth,
                mainAxisSpacing: 30,
                crossAxisSpacing: gap,
                mainAxisExtent: sagaCardExtent(
                  width,
                  MediaQuery.textScalerOf(context),
                ),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => SagaFanCard(collection: shown[i]),
                childCount: shown.length,
              ),
            );
          },
        ),
      ),
    );
  }
}
