import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
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
import 'recent_searches.dart';
import 'search_controller.dart';
import 'search_ranking.dart';
import 'search_start.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _scroll = SmoothScrollController();
  final _text = TextEditingController();

  /// Sulla TV prende il focus solo con OK (vedi [_searchField]).
  final _fieldFocus = FocusNode(debugLabel: 'search-field');

  /// Invio su un termine che aspetta ancora i risultati: si apre il miglior
  /// risultato quando arrivano, se il termine è ancora questo.
  String? _openWhenReady;

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
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);
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
    ref.listen(searchControllerProvider, (_, next) {
      final want = _openWhenReady;
      if (want == null) return;
      if (next.term != want) {
        _openWhenReady = null;
      } else if (!next.loading) {
        // Prima di aprire: ogni termine arriva due volte (senza e con i dati
        // delle persone).
        _openWhenReady = null;
        if (next.results != null) _openBest();
      }
    });
    final form = FormFactor.of(context);
    final side = form.tv ? 24.0 : (form.compact ? 16.0 : 32.0);
    Widget padded(Widget child) => Padding(
        key: child.key,
        padding: EdgeInsets.symmetric(horizontal: side),
        child: child);
    final results = _results(context, l, state, hasSagas: sagas.isNotEmpty);
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(top: form.compact ? 16 : 24, bottom: 32),
      children: [
        padded(_searchField(context, l)),
        const SizedBox(height: 24),
        padded(SagasSearchSection(sagas: sagas)),
        // Fuori dal [WfSwitcher]: la pagina d'inizio non resta a sfumare
        // sotto i risultati.
        if (state.term.length < SearchController.minLength)
          SearchStart(onRecent: _searchRecent, side: side)
        else
          WfSwitcher(child: padded(results)),
        padded(RequestablesSection(library: _libraryMatches(state))),
      ],
    );
  }

  void _setTerm(String value) {
    ref.read(searchControllerProvider.notifier).setTerm(value);
    ref.read(requestablesControllerProvider.notifier).setTerm(value,
        language: Localizations.localeOf(context).languageCode);
  }

  void _searchRecent(String term) {
    _text.value = TextEditingValue(
        text: term, selection: TextSelection.collapsed(offset: term.length));
    _setTerm(term);
  }

  void _clear() {
    _openWhenReady = null;
    _text.clear();
    _setTerm('');
    _fieldFocus.requestFocus();
  }

  /// Salva nei recenti il termine cercato (aprendo un risultato).
  void _remember() =>
      ref.read(recentSearchesProvider.notifier).add(
          ref.read(searchControllerProvider).term);

  /// Apre il miglior risultato del termine mostrato, se c'è.
  void _openBest() {
    final state = ref.read(searchControllerProvider);
    final results = state.results;
    if (results == null) return;
    final best = bestResult(state.term,
        movies: results.movies,
        series: results.series,
        people: results.people);
    if (best != null) openItem(context, best, heroSource: 'search.best');
  }

  /// Invio: salva il termine e apre il suo miglior risultato, subito se c'è
  /// già, sennò quando arriva.
  void _submit(String value) {
    final term = value.trim();
    if (term.length < SearchController.minLength) return;
    final state = ref.read(searchControllerProvider);
    _remember(); // `onChanged` ha già dato il termine al controller.
    if (state.term == term && !state.loading && state.results != null) {
      _openWhenReady = null;
      _openBest();
      return;
    }
    _openWhenReady = term;
    ref.read(searchControllerProvider.notifier).submit();
  }

  /// Il campo di ricerca. Sulla TV il focus iniziale aprirebbe subito la
  /// tastiera: il campo non lo prende da solo (né col fuoco di ripiego della
  /// barra), lo raggiunge il telecomando con la cornice e OK lo attiva.
  Widget _searchField(BuildContext context, AppLocalizations l) {
    final tv = FormFactor.of(context).tv;
    final field = SizedBox(
      height: 56,
      child: TextField(
        controller: _text,
        autofocus: !tv,
        focusNode: _fieldFocus,
        textInputAction: TextInputAction.search,
        onChanged: _setTerm,
        onSubmitted: _submit,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          hintText: l.searchHint,
          prefixIcon:
              const Icon(LucideIcons.search, color: WfColors.creamMuted),
          suffixIcon: tv || _text.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.x),
                  tooltip: l.searchClear,
                  onPressed: _clear),
        ),
      ),
    );
    if (!tv) {
      // Esc col testo svuota; col campo vuoto passa oltre.
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape ||
              _text.text.isEmpty) {
            return KeyEventResult.ignored;
          }
          _clear();
          return KeyEventResult.handled;
        },
        child: field,
      );
    }
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
