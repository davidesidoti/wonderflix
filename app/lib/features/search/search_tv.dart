import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/hero_launch.dart';
import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/states.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../catalog/catalog_navigation.dart';
import '../collections/collection_card.dart';
import '../library/library_providers.dart';
import 'people_search_screen.dart';
import 'search_best.dart';
import 'search_controller.dart';
import 'search_ranking.dart';
import 'search_results.dart' show SearchNoTitles;

/// Margine della pagina sulla TV.
const _side = 24.0;

/// I risultati di Cerca sulla TV (spec §8.3): una fila per sezione, il
/// miglior risultato è la prima carta (larga) della sua fila, l'ultima carta
/// di una fila tagliata è "Vedi tutti". Mentre si affina i risultati vecchi
/// restano, attenuati, e il focus non ci va.
class SearchTvResults extends ConsumerWidget {
  const SearchTvResults({
    super.key,
    required this.state,
    required this.sagas,
    required this.onOpened,
  });

  final SearchState state;
  final List<CollectionSummary> sagas;

  /// Chiamata prima di ogni apertura (lo schermo salva il termine).
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refining = state.loading && state.results != null;
    return IgnorePointer(
      ignoring: refining,
      child: ExcludeFocus(
        excluding: refining,
        child: AnimatedOpacity(
          opacity: refining ? 0.4 : 1,
          duration: WfMotion.of(context).duration(WfMotion.fast),
          child: WfSwitcher(child: _content(context, ref)),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref) {
    Widget padded(Key key, Widget child) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: _side),
      child: child,
    );
    final error = state.error;
    if (error != null) {
      return padded(
        const ValueKey('error'),
        ErrorView(
          error: error,
          onRetry: () =>
              ref.read(searchControllerProvider.notifier).setTerm(state.term),
        ),
      );
    }
    final results = state.results;
    if (results == null) {
      return padded(const ValueKey('loading'), const SearchResultsSkeleton());
    }
    if (results.isEmpty && sagas.isEmpty) {
      return padded(
        const ValueKey('empty'),
        SearchNoTitles(term: results.term, results: results),
      );
    }
    return _Rows(
      key: const ValueKey('data'),
      term: results.term,
      results: results,
      sagas: sagas,
      onOpened: onOpened,
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({
    super.key,
    required this.term,
    required this.results,
    required this.sagas,
    required this.onOpened,
  });

  final String term;
  final SearchResults results;
  final List<CollectionSummary> sagas;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final size = rowPosterSize(context);
    final best = bestResult(
      term,
      movies: results.movies,
      series: results.series,
      people: results.people,
    );
    final bestSection = switch (best?.kind) {
      null => null,
      ItemKind.person => SearchSection.people,
      ItemKind.series => SearchSection.series,
      _ => SearchSection.movies,
    };
    final movies = originalLast(term, results.movies);
    final series = originalLast(term, results.series);
    final people = results.peopleRanked;
    // La fila del miglior risultato comincia con lui: conta il suo nome.
    String first(SearchSection section, List<JellyfinItem> items) =>
        section == bestSection ? best!.name : items.first.name;
    final order = sectionOrder(
      term,
      {
        if (sagas.isNotEmpty) SearchSection.sagas: sagas.first.name,
        if (movies.isNotEmpty)
          SearchSection.movies: first(SearchSection.movies, movies),
        if (series.isNotEmpty)
          SearchSection.series: first(SearchSection.series, series),
        if (people.isNotEmpty)
          SearchSection.people: first(SearchSection.people, people),
      },
      firstOriginals: {
        if (movies.isNotEmpty) SearchSection.movies: movies.first.originalTitle,
        if (series.isNotEmpty) SearchSection.series: series.first.originalTitle,
      },
    );

    /// Le carte di una fila: il miglior risultato in testa (se è suo), gli
    /// altri senza ripeterlo, "Vedi tutti" in fondo se la lista è tagliata.
    Widget row({
      required SearchSection section,
      required String title,
      required int total,
      required List<JellyfinItem> items,
      required int received,
      required double height,
      required double bestHeight,
      required Widget Function(JellyfinItem item, int i) card,
      required String seeAllLabel,
      required Size seeAllSize,
      required VoidCallback onSeeAll,
    }) {
      final others = [
        for (final item in items)
          if (item.id != best?.id || section != bestSection) item,
      ];
      final cards = [
        if (section == bestSection)
          _TvBestCard(
            key: ValueKey('best-${best!.id}'),
            item: best,
            term: term,
            height: bestHeight,
            onOpened: onOpened,
          ),
        for (final (i, item) in others.indexed) card(item, i),
        if (total > received)
          _SeeAllCard(
            key: const ValueKey('see-all'),
            size: seeAllSize,
            label: seeAllLabel,
            onTap: () {
              onOpened();
              onSeeAll();
            },
          ),
      ];
      return MediaRow(
        key: ValueKey('search-tv-${section.name}'),
        title: title,
        count: '$total',
        titleSize: 22,
        side: _side,
        height: height,
        itemCount: cards.length,
        itemBuilder: (_, i) => cards[i],
      );
    }

    Widget titles(
      SearchSection section,
      ItemKind kind,
      List<JellyfinItem> items,
      int total,
      int received,
    ) {
      final source = kind == ItemKind.series
          ? 'search.series'
          : 'search.movies';
      return row(
        section: section,
        title: kind == ItemKind.series ? l.navSeries : l.navMovies,
        total: total,
        items: items,
        received: received,
        height: size.rowHeight,
        bestHeight: size.width * 3 / 2,
        seeAllLabel: l.searchSeeAll,
        seeAllSize: Size(size.width, size.width * 3 / 2),
        onSeeAll: () => openCatalogSearch(context, kind, term),
        card: (item, i) => PosterCard(
          key: ValueKey(item.id),
          item: item,
          width: size.width,
          heroSource: '$source.$i',
          subtitle:
              matchScore(term, item.name, originalTitle: item.originalTitle) ==
                  3
              ? l.searchOriginalTitle(item.originalTitle!)
              : null,
          onTap: () {
            onOpened();
            openItem(
              context,
              item,
              heroSource: WfHeroScope.source(context, '$source.$i'),
            );
          },
        ),
      );
    }

    // Tondo 72, spazio, nome su due righe e titoli (come sul telefono).
    final peopleHeight = 80 + MediaQuery.textScalerOf(context).scale(56);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in order)
          switch (section) {
            SearchSection.sagas => MediaRow(
              key: const ValueKey('search-tv-sagas'),
              title: l.collectionsTab,
              count: '${sagas.length}',
              titleSize: 22,
              side: _side,
              height: size.rowHeight,
              itemCount: sagas.length,
              itemBuilder: (_, i) => CollectionCard(
                key: ValueKey(sagas[i].id),
                collection: sagas[i],
                width: size.width,
              ),
            ),
            SearchSection.movies => titles(
              SearchSection.movies,
              ItemKind.movie,
              movies,
              results.movieTotal,
              results.movies.length,
            ),
            SearchSection.series => titles(
              SearchSection.series,
              ItemKind.series,
              series,
              results.seriesTotal,
              results.series.length,
            ),
            SearchSection.people => row(
              section: SearchSection.people,
              title: l.searchPeople,
              total: results.peopleTotal,
              items: people,
              received: results.people.length,
              height: peopleHeight,
              bestHeight: peopleHeight - 32,
              seeAllLabel: l.searchSeeAllPeople,
              // Accanto ai tondi da 72: larga quanto una persona.
              seeAllSize: const Size(96, 72),
              onSeeAll: () => openPeopleSearch(context, term),
              card: (person, _) => SearchPersonTile(
                key: ValueKey('person-${person.id}'),
                person: person,
                facts: results.facts?[person.id],
                term: term,
                onOpened: onOpened,
              ),
            ),
          },
      ],
    );
  }
}

/// Il miglior risultato in testa alla sua fila: 16:9 alto [height], col
/// fondale (la foto per una persona) e il nome sottolineato. OK apre la scheda.
class _TvBestCard extends ConsumerWidget {
  const _TvBestCard({
    super.key,
    required this.item,
    required this.term,
    required this.height,
    required this.onOpened,
  });

  final JellyfinItem item;
  final String term;
  final double height;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final person = item.kind == ItemKind.person;
    void open() {
      onOpened();
      openItem(context, item, heroSource: 'search.best');
    }

    final width = height * 16 / 9;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvFocusable(
            onActivate: open,
            child: GestureDetector(
              onTap: open,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      WfImage(
                        image: person ? urls.poster(item) : urls.backdrop(item),
                        fallbackIcon: person ? LucideIcons.user : null,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xD90A0A0A), Colors.transparent],
                            stops: [0, 0.6],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 8,
                        child: highlightedName(
                          item.name,
                          term,
                          WfText.display(person ? 22 : 30),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                l.searchBestLabel,
                style: const TextStyle(
                  color: WfColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: Text(
                  ' · ${switch (item.kind) {
                    ItemKind.person => l.searchPeople,
                    ItemKind.series => l.navSeries,
                    _ => l.navMovies,
                  }}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WfColors.creamMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// L'ultima carta di una fila tagliata: una locandina vuota con la freccia.
class _SeeAllCard extends StatelessWidget {
  const _SeeAllCard({
    super.key,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final Size size;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: TvFocusable(
      onActivate: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.fromSize(
          size: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: WfColors.surfaceHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.arrowRight,
                  color: WfColors.gold,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
