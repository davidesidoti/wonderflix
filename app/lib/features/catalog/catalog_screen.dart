import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/tv_focusable.dart';
import '../collections/collections_grid.dart';
import '../collections/collections_providers.dart';
import '../social/social_providers.dart';
import 'catalog_band.dart';
import 'catalog_controller.dart';
import 'catalog_genre_index.dart';
import 'catalog_genres.dart';
import 'catalog_navigation.dart';
import 'catalog_tools.dart';

/// La sala di Film o Serie: cartellone del genere, riga dei generi e attrezzi
/// (ferma in cima fuori dalla TV) e griglia (spec §4).
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen(
      {super.key,
      required this.kind,
      this.view = CatalogView.titles,
      this.genre});

  final ItemKind kind;

  /// Genere da mostrare (dal parametro `genre` dell'indirizzo); null: tutti.
  final String? genre;

  /// Solo per i film. Senza la funzione `collections` del plugin vale come
  /// [CatalogView.titles].
  final CatalogView view;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = SmoothScrollController();

  /// Dissolvenza di entrata di ogni stato nuovo della griglia (scheletro,
  /// errore, vuoto, titoli): sono sliver, [WfSwitcher] non ci va.
  late final _fade = AnimationController(vsync: this, value: 1);

  /// Numero di elementi al momento dell'ultimo caricamento automatico: evita
  /// un ciclo infinito se il server risponde con pagine vuote.
  int _autoLoadedAt = -1;

  /// La query a cui si riferisce [_autoLoadedAt].
  ItemQuery? _autoLoadedQuery;

  @override
  void initState() {
    super.initState();
    // `?view=sagas` senza la funzione delle saghe mostra i titoli (vedi build).
    final sagasAvailable = widget.kind == ItemKind.movie &&
        ref.read(socialAvailabilityProvider).collections;
    if (widget.view == CatalogView.titles || !sagasAvailable) _showGenre();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) {
        unawaited(
            ref.read(catalogControllerProvider(widget.kind).notifier).loadMore());
      }
    });
  }

  /// Il controller non carica da solo: dopo il primo build gli dico di partire
  /// (anche tornando dalle saghe o cambiando genere).
  void _showGenre() => unawaited(Future.microtask(() {
        if (!mounted) return;
        unawaited(ref
            .read(catalogControllerProvider(widget.kind).notifier)
            .showGenre(widget.genre));
      }));

  @override
  void didUpdateWidget(CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router riusa la schermata cambiando `?genre=`.
    if (widget.view == CatalogView.titles &&
        (oldWidget.view != widget.view || oldWidget.genre != widget.genre)) {
      _showGenre();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sagasAvailable = widget.kind == ItemKind.movie &&
        ref.watch(socialAvailabilityProvider
            .select((features) => features.collections));
    final sagas = sagasAvailable && widget.view == CatalogView.sagas;
    final Widget tabs;
    if (widget.kind == ItemKind.series) {
      tabs = _BandTab(label: l.navSeries, selected: true);
    } else if (!sagasAvailable) {
      tabs = _BandTab(label: l.navMovies, selected: true);
    } else {
      tabs = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: FormFactor.of(context).compact ? 14 : 20,
        children: [
          _BandTab(
              key: ValueKey('catalog-view-${CatalogView.titles.name}'),
              label: l.navMovies,
              selected: !sagas,
              onTap: () => openCatalog(context, widget.kind)),
          _BandTab(
              key: ValueKey('catalog-view-${CatalogView.sagas.name}'),
              label: l.collectionsTab,
              selected: sagas,
              onTap: () =>
                  openCatalog(context, widget.kind, view: CatalogView.sagas)),
        ],
      );
    }
    final height = catalogBandHeight(context);

    if (sagas) {
      // Il catalogo dei titoli si legge solo nella vista dei titoli.
      final list = ref.watch(collectionsProvider).value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CatalogBand(
            title: l.collectionsTab,
            height: height,
            tabs: tabs,
            line: list == null || list.isEmpty
                ? null
                : TextSpan(text: l.collectionsCount(list.length)),
          ),
          const Expanded(child: CollectionsGrid()),
        ],
      );
    }
    return _titles(context, l, tabs, height);
  }

  /// Cartellone, generi e attrezzi, griglia dei titoli.
  Widget _titles(
      BuildContext context, AppLocalizations l, Widget tabs, double height) {
    final kind = widget.kind;
    final provider = catalogControllerProvider(kind);
    final state = ref.watch(provider);
    ref.listen(provider, (previous, next) {
      if (previous == null || _bodyKind(previous) == _bodyKind(next)) return;
      _fade
        ..duration = WfMotion.of(context).duration(WfMotion.medium)
        ..forward(from: 0);
    });
    final controller = ref.read(provider.notifier);
    final genres = ref.watch(catalogGenresProvider(kind));
    final all = ref.watch(catalogTotalsProvider((kind, null))).value;
    final totals = widget.genre == null
        ? all
        : ref.watch(catalogTotalsProvider((kind, widget.genre))).value;
    final form = FormFactor.of(context);
    final tv = form.tv;
    // La pagina parte dal bordo della finestra (`underBar: false`): la
    // testata ferma lascia sopra di sé lo spazio della barra in alto.
    final barGap = tv
        ? 0.0
        : (form.compact ? shellCompactBarHeight : shellBarHeight) +
            MediaQuery.paddingOf(context).top;

    // Su schermi grandi la prima pagina può non riempire la finestra: senza
    // scroll non scatterebbe mai il caricamento successivo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current = ref.read(provider);
      if (current.query != _autoLoadedQuery) {
        _autoLoadedQuery = current.query; // nuova query
        _autoLoadedAt = -1;
      }
      if (_scroll.position.extentAfter < 800 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(controller.loadMore());
      }
    });

    final band = CatalogBand(
      title: widget.genre ??
          (kind == ItemKind.series ? l.catalogAllSeries : l.catalogAllMovies),
      height: height,
      tabs: tabs,
      hero: catalogBandHero(state.items),
      line: catalogBandLine(l,
          kind: kind,
          sort: state.query.sort,
          reversed: state.query.reversed,
          totals: totals),
    );
    final side = tv ? 24.0 : (form.compact ? 16.0 : 32.0);
    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trasparente: sopra la barra in alto, da ferma; prima ci passa il
        // fondo del cartellone.
        SizedBox(height: barGap),
        ColoredBox(
          color: WfColors.bg,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CatalogGenreIndex(
                  kind: kind,
                  genres: genres,
                  total: all?.total,
                  selected: widget.genre,
                  onSelected: (genre) =>
                      openCatalog(context, kind, genre: genre),
                ),
                CatalogTools(
                  kind: kind,
                  query: state.query,
                  totals: totals,
                  onChanged: (query) => unawaited(controller.setQuery(query)),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return BatchedEntrance(
      itemCount: state.items.length,
      resetKey: state.query,
      child: CustomScrollView(
        controller: _scroll,
        primary: false,
        slivers: [
          // Il cartellone sporge di [barGap] sotto la testata, che lì è
          // trasparente: così la testata si ferma sotto la barra in alto.
          SliverToBoxAdapter(
            child: SizedBox(
              height: height - barGap,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: height,
                maxHeight: height,
                child: band,
              ),
            ),
          ),
          // Sulla TV la testata esce con il cartellone: la griglia ha tutto
          // lo schermo.
          if (tv)
            SliverToBoxAdapter(child: bar)
          else
            PinnedHeaderSliver(child: bar),
          SliverFadeTransition(
            opacity: _fade,
            sliver: SliverMainAxisGroup(
                slivers: _body(context, l, state, controller, side)),
          ),
        ],
      ),
    );
  }

  /// Quale stato mostra il corpo: cambiandolo, il corpo entra in dissolvenza.
  static String _bodyKind(CatalogState state) => state.items.isNotEmpty
      ? 'data'
      : state.loading
          ? 'loading'
          : state.error != null
              ? 'error'
              : 'empty';

  /// La griglia, o lo scheletro, l'errore, il vuoto (spec §12).
  List<Widget> _body(BuildContext context, AppLocalizations l,
      CatalogState state, CatalogController controller, double side) {
    if (state.items.isEmpty) {
      final Widget child;
      final error = state.error;
      if (state.loading) {
        child = const PosterGridSkeleton(
            key: ValueKey('loading'), shrinkWrap: true);
      } else if (error != null) {
        child = Padding(
          key: const ValueKey('error'),
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: ErrorView(
              error: error, onRetry: () => unawaited(controller.retry())),
        );
      } else {
        final series = widget.kind == ItemKind.series;
        final genre = widget.genre != null;
        child = Padding(
          key: const ValueKey('empty'),
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    switch ((series, genre)) {
                      (false, false) => l.catalogEmptyMovies,
                      (false, true) => l.catalogEmptyMoviesGenre,
                      (true, false) => l.catalogEmptySeries,
                      (true, true) => l.catalogEmptySeriesGenre,
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: WfColors.creamMuted)),
                if (state.query.hasRefinements)
                  TextButton(
                    onPressed: () => unawaited(
                        controller.setQuery(state.query.clearRefinements())),
                    child: Text(l.catalogClearFilters),
                  ),
              ],
            ),
          ),
        );
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.only(top: 16),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, 16, side, 24),
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
    ];
  }
}

/// Una scheda del cartellone (FILM, SAGHE, SERIE): parola in Bebas, crema se
/// scelta, al 32% l'altra. Senza [onTap] è solo il nome della pagina.
class _BandTab extends StatelessWidget {
  const _BandTab(
      {super.key, required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    final text = Text(
      label,
      style: WfText.display(
        form.tv ? 22 : (form.compact ? 26 : 30),
        color:
            selected ? WfColors.cream : WfColors.cream.withValues(alpha: 0.32),
      ).copyWith(height: 1, letterSpacing: 1),
    );
    final tap = onTap;
    if (tap == null) return text;
    return Semantics(
      button: true,
      selected: selected,
      child: TvFocusBorder(
        child: InkWell(
          onTap: selected ? null : tap,
          child: text,
        ),
      ),
    );
  }
}
