import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../catalog/catalog_band.dart';
import '../catalog/catalog_navigation.dart';
import '../catalog/catalog_screen.dart';
import '../library/library_providers.dart';
import '../library/my_list_added.dart';
import '../library/user_data.dart';
import 'my_list_band.dart';
import 'my_list_groups.dart';
import 'my_list_tools.dart';
import 'my_list_view.dart';

/// Il limite della richiesta della lista.
const _favoritesLimit = 500;

final favoritesProvider = FutureProvider.autoDispose<List<JellyfinItem>>((
  ref,
) async {
  ref.watch(libraryRevisionProvider);
  final page = await ref
      .watch(libraryApiProvider)
      .items(
        const ItemQuery(
          kinds: {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.dateAdded,
          favoritesOnly: true,
          // Ordine e filtri si applicano nell'app (`buildMyListView`).
          includeSortFields: true,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: _favoritesLimit,
      );
  return page.items;
});

/// Apre La mia lista sulla scheda [tab] (`/mylist?kind=movies`): la scheda
/// sta nell'indirizzo, così Indietro la ritrova.
void openMyList(BuildContext context, MyListTab tab) => context.go(
  Uri(
    path: '/mylist',
    queryParameters: tab == MyListTab.all ? null : {'kind': tab.name},
  ).toString(),
);

/// La mia lista (spec §4): cartellone con le schede, attrezzi e gruppi, in
/// una sola pagina che scorre.
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key, this.tab = MyListTab.all});

  final MyListTab tab;

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = SmoothScrollController();

  /// Dissolvenza di entrata di ogni stato nuovo (scheletro, errore, lista).
  late final _fade = AnimationController(vsync: this, value: 1);

  /// Ordine, genere e ricerca: si applicano alla lista già caricata.
  MyListFilters _filters = const MyListFilters();
  bool _watchedOpen = false;

  @override
  void didUpdateWidget(MyListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router riusa la pagina cambiando `?kind=`: genere e ricerca sono
    // della scheda di prima.
    if (oldWidget.tab != widget.tab) {
      _filters = _filters.copyWith(genre: null, search: '');
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Toglie le date dei titoli usciti dalla lista, quando ci sono sia la
  /// lista sia le date (`retainOnly` non fa nulla finché le date caricano).
  void _prune() {
    final items = ref.read(favoritesProvider).value;
    // shortcut: oltre il limite della richiesta la lista non è intera e non
    // si pulisce; da rivedere se la lista si legge a pagine.
    if (items == null || items.length >= _favoritesLimit) return;
    // Anche i cuori accesi in questa sessione: un titolo aggiunto da una
    // scheda aperta sopra la pagina non è ancora nella risposta.
    final overrides = ref.read(userDataOverridesProvider);
    ref.read(myListAddedProvider.notifier).retainOnly({
      for (final i in items) jellyfinIdKey(i.id),
      for (final MapEntry(:key, :value) in overrides.entries)
        if (value.isFavorite) jellyfinIdKey(key),
    });
  }

  static String _bodyKind(AsyncValue<Object?> state) => state.hasValue
      ? 'data'
      : state.hasError
      ? 'error'
      : 'loading';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final tv = form.tv;
    final side = tv ? 24.0 : (form.compact ? 16.0 : 32.0);

    // Si pulisce solo con una lista nuova o all'arrivo delle date, non a ogni
    // data cambiata.
    ref.listen(favoritesProvider, (previous, next) {
      if (next.hasValue && !identical(next.value, previous?.value)) _prune();
      if (previous == null || _bodyKind(previous) == _bodyKind(next)) return;
      _fade
        ..duration = WfMotion.of(context).duration(WfMotion.medium)
        ..forward(from: 0);
    });
    ref.listen(myListAddedProvider, (previous, next) {
      if (next.hasValue && !(previous?.hasValue ?? false)) _prune();
    });
    final overrides = ref.watch(userDataOverridesProvider);
    // Le date arrivano dopo: intanto si ordina per data di creazione.
    final added = ref.watch(myListAddedProvider).value ?? const {};

    final tabs = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: form.compact ? 14 : 20,
      children: [
        for (final (tab, label) in [
          (MyListTab.all, l.catalogAll),
          (MyListTab.movies, l.navMovies),
          (MyListTab.series, l.navSeries),
        ])
          CatalogBandTab(
            key: ValueKey('mylist-tab-${tab.name}'),
            label: label,
            selected: widget.tab == tab,
            onTap: () => openMyList(context, tab),
          ),
      ],
    );
    // Sulla TV col focus nel cartellone o negli attrezzi la pagina torna in
    // cima, nei gruppi scorre oltre il cartellone (spec §13).
    Widget top(Widget sliver) => tv
        ? tvScrollOnFocus(scroll: _scroll, offset: () => 0, child: sliver)
        : sliver;
    // La pagina parte dal bordo della finestra (`underBar: false`): il
    // cartellone passa sotto la barra in alto, e gli attrezzi, che non
    // restano fermi, vengono dopo tutto il cartellone.
    Widget band({
      required double height,
      Widget? tabs,
      JellyfinItem? hero,
      InlineSpan? line,
      Widget? action,
    }) => top(
      SliverToBoxAdapter(
        child: CatalogBand(
          title: l.navMyList.toUpperCase(),
          height: height,
          tabs: tabs,
          hero: hero,
          line: line,
          action: action,
        ),
      ),
    );
    final plainHeight = myListBandHeight(context, action: false);
    final actionHeight = myListBandHeight(context, action: true);

    final slivers = ref
        .watch(favoritesProvider)
        .when(
          // Ricaricando dopo un cambio sul server resta la lista vecchia
          // finché arriva la nuova.
          skipLoadingOnReload: true,
          loading: () => [
            // Alto come col pulsante, che c'è quasi sempre: niente salto.
            band(height: actionHeight, tabs: tabs),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: PosterGridSkeleton(
                  key: const ValueKey('loading'),
                  shrinkWrap: true,
                  catalogSide: side,
                ),
              ),
            ),
          ],
          error: (error, _) => [
            band(height: plainHeight, tabs: tabs),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(favoritesProvider),
                ),
              ),
            ),
          ],
          data: (items) {
            final view = buildMyListView(
              items,
              widget.tab,
              // Nelle finestre strette (e in TV) il campo di ricerca non c'è.
              form.compact ? _filters.copyWith(search: '') : _filters,
              overrides,
              added,
            );
            if (view.listEmpty) {
              return [
                band(
                  height: actionHeight,
                  line: TextSpan(text: l.myListEmpty),
                  action: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [_go(l, ItemKind.movie), _go(l, ItemKind.series)],
                  ),
                ),
              ];
            }
            if (view.tabCount == 0) {
              final movies = widget.tab == MyListTab.movies;
              return [
                band(
                  height: actionHeight,
                  tabs: tabs,
                  line: TextSpan(
                    text: movies ? l.myListEmptyMovies : l.myListEmptySeries,
                  ),
                  action: _go(l, movies ? ItemKind.movie : ItemKind.series),
                ),
              ];
            }
            final hero = view.hero;
            // Una sola altezza per il cartellone e per lo scorrimento TV.
            final height = hero == null ? plainHeight : actionHeight;
            final groups = myListGroupSlivers(
              context,
              view: view,
              side: side,
              watchedOpen: _watchedOpen,
              onToggleWatched: () =>
                  setState(() => _watchedOpen = !_watchedOpen),
            );
            return [
              band(
                height: height,
                tabs: tabs,
                // Il fondale del punta, se no del primo titolo che ne ha uno.
                hero: catalogBandHero([
                  ?hero,
                  ...view.resume,
                  ...view.start,
                  ...view.watched,
                ]),
                line: myListBandLine(l, widget.tab, view),
                action: hero == null
                    ? null
                    : MyListBandAction(
                        hero: hero,
                        resuming: view.resumeCount > 0,
                        autofocus: tv,
                      ),
              ),
              top(
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverToBoxAdapter(
                    child: MyListTools(
                      view: view,
                      filters: _filters,
                      autofocus: tv && hero == null,
                      onChanged: (filters) =>
                          setState(() => _filters = filters),
                    ),
                  ),
                ),
              ),
              if (view.noResults)
                SliverToBoxAdapter(child: _noResults(l))
              else if (tv)
                tvScrollOnFocus(
                  scroll: _scroll,
                  offset: () => max(_scroll.offset, height),
                  child: SliverMainAxisGroup(slivers: groups),
                )
              else
                ...groups,
            ];
          },
        );
    return CustomScrollView(
      controller: _scroll,
      primary: false,
      slivers: [
        slivers.first,
        if (slivers.length > 1)
          SliverFadeTransition(
            opacity: _fade,
            sliver: SliverMainAxisGroup(slivers: slivers.sublist(1)),
          ),
      ],
    );
  }

  /// "Vai ai film" (oro) e "Vai alle serie" (bordato).
  Widget _go(AppLocalizations l, ItemKind kind) => kind == ItemKind.movie
      ? FilledButton(
          // Sulla TV il focus parte da qui (spec §11).
          autofocus: FormFactor.of(context).tv,
          onPressed: () => openCatalog(context, ItemKind.movie),
          child: Text(l.myListGoMovies),
        )
      : OutlinedButton(
          onPressed: () => openCatalog(context, ItemKind.series),
          child: Text(l.myListGoSeries),
        );

  Widget _noResults(AppLocalizations l) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.myListNoResults,
            textAlign: TextAlign.center,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          TextButton(
            onPressed: () => setState(
              () => _filters = _filters.copyWith(genre: null, search: ''),
            ),
            child: Text(l.catalogClearFilters),
          ),
        ],
      ),
    ),
  );
}
