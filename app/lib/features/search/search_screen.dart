import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../collections/collections_logic.dart';
import '../collections/collections_providers.dart';
import '../collections/sagas_search_section.dart';
import '../library/library_providers.dart';
import '../requests/requestables_controller.dart';
import '../requests/requestables_section.dart';
import '../requests/requests_providers.dart';
import 'search_controller.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _scroll = SmoothScrollController();

  /// Il campo sulla TV: prende il focus solo con OK (vedi [_searchField]).
  final _fieldFocus = FocusNode(debugLabel: 'search-field');

  /// Sulla TV: OK ha attivato il campo (fino a che perde il focus).
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus && _typing) setState(() => _typing = false);
    });
  }

  @override
  void dispose() {
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    // L'elenco delle saghe si legge una volta all'apertura della ricerca, poi
    // è in cache: così la sezione "Saghe" non arriva dopo i risultati.
    final allSagas =
        ref.watch(collectionsProvider).value ?? const <CollectionSummary>[];
    final sagas = state.term.length < SearchController.minLength
        ? const <CollectionSummary>[]
        : matchCollections(allSagas, state.term,
            max: SagasSearchSection.maxResults);
    // La lista costruisce la sezione "Da richiedere" solo quando è vicina allo
    // schermo: se esce, il controller (autoDispose) resterebbe senza
    // ascoltatori e perderebbe timer, richiesta e titoli. Qui lo si tiene
    // vivo, senza `watch`: lo schermo non si ricostruisce a ogni suo stato.
    ref.listen(requestablesControllerProvider, (_, _) {});
    // La funzione può arrivare quando il termine è già scritto (il controllo
    // del plugin ritenta dopo 30 secondi): la ricerca parte da sola, senza
    // aspettare un altro tasto.
    ref.listen(requestsAvailableProvider, (previous, next) {
      if (next && previous != true) {
        ref.read(requestablesControllerProvider.notifier).setTerm(
            ref.read(searchControllerProvider).term,
            language: Localizations.localeOf(context).languageCode);
      }
    });
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(32),
      children: [
        _searchField(context, l, controller),
        const SizedBox(height: 24),
        SagasSearchSection(sagas: sagas),
        WfSwitcher(
            child: _results(context, l, state, hasSagas: sagas.isNotEmpty)),
        RequestablesSection(library: _libraryMatches(state)),
      ],
    );
  }

  /// Il campo di ricerca. Sulla TV il focus iniziale aprirebbe subito la
  /// tastiera: il campo non lo prende da solo (né col fuoco di ripiego della
  /// barra), lo raggiunge il telecomando con la cornice e OK lo attiva.
  Widget _searchField(
      BuildContext context, AppLocalizations l, SearchController controller) {
    final tv = FormFactor.of(context).tv;
    final field = TextField(
      autofocus: !tv,
      focusNode: tv ? _fieldFocus : null,
      onChanged: (value) {
        controller.setTerm(value);
        ref.read(requestablesControllerProvider.notifier).setTerm(value,
            language: Localizations.localeOf(context).languageCode);
      },
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        hintText: l.searchHint,
        prefixIcon: const Icon(LucideIcons.search, color: WfColors.creamMuted),
      ),
    );
    if (!tv) return field;
    // Il campo non è raggiungibile finché non è attivo: la cornice
    // (`TvFocusable`) è l'unica tappa del telecomando.
    return TvFocusable(
      onActivate: () {
        setState(() => _typing = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _fieldFocus.requestFocus());
      },
      child: ExcludeFocus(excluding: !_typing, child: field),
    );
  }

  /// Risultati, con una chiave per stato (per [WfSwitcher]). Con delle saghe
  /// trovate ([hasSagas]) "Nessun risultato" non compare.
  Widget _results(BuildContext context, AppLocalizations l, SearchState state,
      {required bool hasSagas}) {
    const muted = TextStyle(color: WfColors.creamMuted);
    if (state.term.length < SearchController.minLength) {
      return Text(l.searchPrompt, key: const ValueKey('prompt'), style: muted);
    }
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
    if (results.isEmpty) {
      if (hasSagas) return const SizedBox.shrink(key: ValueKey('sagas-only'));
      return Text(l.searchNoResults(state.term),
          key: const ValueKey('empty'), style: muted);
    }
    return Column(
      key: const ValueKey('data'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (results.movies.isNotEmpty)
          _posterSection(
              l.navMovies, results.movies, 'search.movies', results),
        if (results.series.isNotEmpty)
          _posterSection(
              l.navSeries, results.series, 'search.series', results),
        if (results.people.isNotEmpty) _peopleSection(context, l, results.people),
      ],
    );
  }

  /// Cosa ha trovato la libreria (id Jellyfin e TMDB di film e serie), per non
  /// ripeterlo in "Da richiedere"; `null` mentre la ricerca è in corso. Con un
  /// errore della libreria la sezione non aspetta.
  static LibraryMatches? _libraryMatches(SearchState state) {
    if (state.error != null) return const LibraryMatches();
    final results = state.results;
    if (state.loading || results == null) return null;
    return LibraryMatches.fromResults(results);
  }

  /// Sezione di locandine; le card entrano di nuovo a ogni ricerca
  /// completata ([results]), non a ogni lettera (mentre si scrive restano
  /// i risultati di prima).
  Widget _posterSection(String title, List<JellyfinItem> items, String source,
          SearchResults results) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: WfText.display(26)),
            const SizedBox(height: 12),
            BatchedEntrance(
              itemCount: items.length,
              resetKey: results,
              child: Wrap(
                spacing: 16,
                runSpacing: 24,
                children: [
                  for (final (i, item) in items.indexed)
                    BatchedEntranceItem(
                      index: i,
                      child: PosterCard(
                          item: item, width: 150, heroSource: '$source.$i'),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _peopleSection(
      BuildContext context, AppLocalizations l, List<JellyfinItem> people) {
    final urls = ref.watch(imageUrlsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.searchPeople, style: WfText.display(26)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final person in people)
              TvFocusable(
                onActivate: () => openItem(context, person),
                child: GestureDetector(
                onTap: () => openItem(context, person),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 90,
                            height: 90,
                            child: WfImage(
                                image: urls.poster(person),
                                fallbackIcon: LucideIcons.user),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(person.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
