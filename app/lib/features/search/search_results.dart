import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../catalog/catalog_navigation.dart';
import '../collections/sagas_search_section.dart';
import '../requests/requestables_controller.dart';
import '../requests/requests_providers.dart';
import 'search_best.dart';
import 'people_search_screen.dart';
import 'search_controller.dart';
import 'search_ranking.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Quanti titoli per sezione sul telefono: due file da due.
const _phoneTitles = 4;

/// I risultati di Cerca su desktop e telefono (spec §8.2, §8.3): miglior
/// risultato con le persone, poi le sezioni per pertinenza. Mentre si affina
/// i risultati vecchi restano, attenuati, e non si aprono.
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({
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
    // Lo scheletro della prima ricerca non si attenua.
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

  /// Con una chiave per stato (per [WfSwitcher]).
  Widget _content(BuildContext context, WidgetRef ref) {
    final error = state.error;
    if (error != null) {
      return ErrorView(
        key: const ValueKey('error'),
        error: error,
        onRetry: () =>
            ref.read(searchControllerProvider.notifier).setTerm(state.term),
      );
    }
    final results = state.results;
    if (results == null) {
      return const SearchResultsSkeleton(key: ValueKey('loading'));
    }
    if (results.isEmpty && sagas.isEmpty) {
      return _NoTitles(
          key: const ValueKey('empty'), term: results.term, results: results);
    }
    return _Sections(
        key: const ValueKey('data'),
        term: results.term,
        results: results,
        sagas: sagas,
        onOpened: onOpened);
  }
}

/// "Nessun titolo per …", con "nemmeno su TMDB" quando "Da richiedere" ha
/// finito senza titoli da mostrare.
class _NoTitles extends ConsumerWidget {
  const _NoTitles({super.key, required this.term, required this.results});

  final String term;
  final SearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final requests = ref.watch(requestablesControllerProvider);
    final titles = requests.titles;
    final nowhere = ref.watch(requestsAvailableProvider) &&
        requests.term == term &&
        !requests.loading &&
        requests.error == null &&
        titles != null &&
        visibleRequestables(titles, LibraryMatches.fromResults(results))
            .isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Text(
          nowhere ? l.searchNoTitlesAnywhere(term) : l.searchNoTitles(term),
          style: const TextStyle(color: WfColors.creamMuted)),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({
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
    final form = FormFactor.of(context);
    final phone = form.compact && !form.tv;
    final best = bestResult(term,
        movies: results.movies, series: results.series, people: results.people);
    // Con una persona come miglior risultato, la lista ha le altre.
    final people = [
      for (final person in results.peopleRanked)
        if (person.id != best?.id) person,
    ];
    final movies = originalLast(term, results.movies);
    final series = originalLast(term, results.series);
    // Le persone stanno accanto alla carta (sotto, sul telefono) quando c'è.
    final peopleInSections = best == null && people.isNotEmpty;
    final order = sectionOrder(term, {
      if (sagas.isNotEmpty) SearchSection.sagas: sagas.first.name,
      if (movies.isNotEmpty) SearchSection.movies: movies.first.name,
      if (series.isNotEmpty) SearchSection.series: series.first.name,
      if (peopleInSections) SearchSection.people: people.first.name,
    }, firstOriginals: {
      if (movies.isNotEmpty) SearchSection.movies: movies.first.originalTitle,
      if (series.isNotEmpty) SearchSection.series: series.first.originalTitle,
    });

    Widget peopleBlock() => phone
        ? _PeopleRow(
            people: people, results: results, term: term, onOpened: onOpened)
        : SearchPeopleList(
            people: people,
            facts: results.facts,
            term: term,
            total: results.peopleTotal,
            onSeeAll: () {
              onOpened();
              openPeopleSearch(context, term);
            },
            onOpened: onOpened);

    final bestCard = best == null
        ? null
        : SearchBestCard(
            item: best,
            term: term,
            facts: results.facts?[best.id],
            onOpened: onOpened);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bestCard != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: phone
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bestCard,
                      if (people.isNotEmpty) peopleBlock(),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: bestCard),
                      if (people.isNotEmpty) ...[
                        const SizedBox(width: 24),
                        SizedBox(width: 380, child: peopleBlock()),
                      ],
                    ],
                  ),
          ),
        for (final section in order)
          switch (section) {
            // shortcut: aprire una saga non salva il termine (CollectionCard
            // non ha onTap); da aggiungere se serve.
            SearchSection.sagas => SagasSearchSection(sagas: sagas),
            SearchSection.movies => _TitlesSection(
                title: l.navMovies,
                kind: ItemKind.movie,
                items: movies,
                total: results.movieTotal,
                term: term,
                results: results,
                onOpened: onOpened),
            SearchSection.series => _TitlesSection(
                title: l.navSeries,
                kind: ItemKind.series,
                items: series,
                total: results.seriesTotal,
                term: term,
                results: results,
                onOpened: onOpened),
            SearchSection.people => Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: peopleBlock()),
          },
      ],
    );
  }
}

/// Le persone sul telefono: una fila che scorre.
class _PeopleRow extends StatelessWidget {
  const _PeopleRow({
    required this.people,
    required this.results,
    required this.term,
    required this.onOpened,
  });

  final List<JellyfinItem> people;
  final SearchResults results;
  final String term;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) => MediaRow(
        title: AppLocalizations.of(context).searchPeople,
        count: '${results.peopleTotal}',
        titleSize: 26,
        side: 0,
        trailing: results.peopleTotal > results.people.length
            ? SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    onOpened();
                    openPeopleSearch(context, term);
                  },
                  child: Text(AppLocalizations.of(context)
                      .searchSeeAllPeopleCount(results.peopleTotal)),
                ),
              )
            : null,
        // Tondo 72, spazio, nome su due righe e titoli.
        height: 80 + MediaQuery.textScalerOf(context).scale(56),
        itemCount: people.length,
        itemBuilder: (context, i) => SearchPersonTile(
          key: ValueKey('person-${people[i].id}'),
          person: people[i],
          facts: results.facts?[people[i].id],
          term: term,
          onOpened: onOpened,
        ),
      );
}

/// Una sezione Film o Serie: testa col totale e "Vedi tutti", e una fila
/// della griglia del catalogo (due file da due sul telefono).
class _TitlesSection extends StatelessWidget {
  const _TitlesSection({
    required this.title,
    required this.kind,
    required this.items,
    required this.total,
    required this.term,
    required this.results,
    required this.onOpened,
  });

  final String title;
  final ItemKind kind;
  final List<JellyfinItem> items;
  final int total;
  final String term;

  /// Le card entrano di nuovo a ogni ricerca completata, non a ogni lettera.
  final SearchResults results;
  final VoidCallback onOpened;

  void _seeAll(BuildContext context) {
    onOpened();
    openCatalogSearch(context, kind, term);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final phone = form.compact && !form.tv;
    final source = kind == ItemKind.series ? 'search.series' : 'search.movies';
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final count = phone ? _phoneTitles : catalogColumnCount(width);
        final shown = items.take(count).toList();
        final cut = total > shown.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title,
                    style: WfText.display(form.tv ? 22 : (phone ? 26 : 30))),
                const SizedBox(width: 10),
                Text('$total',
                    style: const TextStyle(
                        color: WfColors.creamMuted,
                        fontSize: 12.5,
                        fontFeatures: _tabular)),
                const Spacer(),
                if (cut && !phone)
                  TextButton(
                      onPressed: () => _seeAll(context),
                      child: Text(l.searchSeeAll)),
              ],
            ),
            const SizedBox(height: 12),
            BatchedEntrance(
              itemCount: shown.length,
              resetKey: results,
              child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 24,
                  mainAxisExtent: catalogCellExtent(
                      width, MediaQuery.textScalerOf(context)),
                ),
                children: [
                  for (final (i, item) in shown.indexed)
                    BatchedEntranceItem(
                      index: i,
                      child: PosterCard(
                        item: item,
                        catalogStyle: true,
                        heroSource: '$source.$i',
                        subtitle: matchScore(term, item.name,
                                    originalTitle: item.originalTitle) ==
                                3
                            ? l.searchOriginalTitle(item.originalTitle!)
                            : null,
                        onTap: () {
                          onOpened();
                          openItem(context, item,
                              heroSource:
                                  WfHeroScope.source(context, '$source.$i'));
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (phone && total > _phoneTitles)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => _seeAll(context),
                  child: Text(kind == ItemKind.series
                      ? l.searchSeeAllSeriesCount(total)
                      : l.searchSeeAllMoviesCount(total)),
                ),
              ),
          ],
        );
      }),
    );
  }
}
