import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart' show tvRowFocusPadding;
import '../../ui/smooth_scroll.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/tv_lanes.dart';
import '../collections/collections_logic.dart';
import '../collections/collections_providers.dart';
import '../collections/sagas_search_section.dart';
import '../requests/requestables_controller.dart';
import '../requests/requestables_section.dart';
import '../requests/requests_providers.dart';
import 'recent_searches.dart';
import 'search_controller.dart';
import 'search_ranking.dart';
import 'search_results.dart';
import 'search_start.dart';
import 'search_tv.dart';

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
    // Mentre si affina, le saghe del termine dei risultati mostrati: la
    // pagina non cambia finché non arrivano quelli nuovi.
    final sagaTerm = (state.loading ? state.results?.term : null) ?? state.term;
    final sagas = state.term.length < SearchController.minLength
        ? const <CollectionSummary>[]
        : matchCollections(allSagas, sagaTerm,
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
    // Sulla TV ogni fila è una [TvLane]: Su e Giù passano da una all'altra.
    Widget lane(Widget child) => form.tv ? TvLane(child: child) : child;
    final starting = state.term.length < SearchController.minLength;
    final list = ListView(
      controller: _scroll,
      padding: EdgeInsets.only(top: form.compact ? 16 : 24, bottom: 32),
      children: [
        lane(padded(_searchField(context, l))),
        // Linea oro mentre la ricerca carica; lo spazio c'è sempre, così il
        // campo non salta.
        padded(SizedBox(
          height: 2,
          child: state.loading
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  color: WfColors.gold,
                  backgroundColor: Colors.transparent)
              : null,
        )),
        const SizedBox(height: 22),
        // Sempre montata (nascosta mentre si cerca): generi, aggiunti di
        // recente e Film/Serie restano quando si svuota il campo. Fuori dal
        // [WfSwitcher]: non resta a sfumare sotto i risultati.
        Offstage(
          offstage: !starting,
          child: ExcludeFocus(
              excluding: !starting,
              child: SearchStart(onRecent: _searchRecent, side: side)),
        ),
        if (!starting)
          form.tv
              // Le file hanno i loro margini (dentro scorrono fino al bordo).
              ? SearchTvResults(state: state, sagas: sagas, onOpened: _remember)
              : padded(SearchResultsView(
                  state: state, sagas: sagas, onOpened: _remember)),
        lane(Padding(
          // Sulla TV la fila ha già [tvRowFocusPadding] ai lati: il titolo
          // resta allineato a quelli sopra.
          padding: EdgeInsets.symmetric(
              horizontal: form.tv ? side - tvRowFocusPadding : side),
          child: RequestablesSection(
              library: _libraryMatches(state),
              term: state.term,
              onOpened: _remember),
        )),
      ],
    );
    return form.tv ? TvLanes(child: list) : list;
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
    if (state.results?.term == term && !state.loading) {
      _openWhenReady = null;
      _openBest();
      return;
    }
    // Un errore (o niente in corso) non aspetta: Riprova poi non aprirebbe.
    if (!state.loading) return;
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
        // Sulla TV chiudere la tastiera con Indietro manda l'azione: lì
        // niente Invio, aprirebbe un titolo senza volerlo.
        textInputAction: tv ? null : TextInputAction.search,
        onChanged: _setTerm,
        onSubmitted: tv ? null : _submit,
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

  /// Cosa ha trovato la libreria (id Jellyfin e TMDB di film e serie), per non
  /// ripeterlo in "Da richiedere"; `null` mentre la ricerca è in corso. Con un
  /// errore della libreria la sezione non aspetta.
  static LibraryMatches? _libraryMatches(SearchState state) {
    if (state.error != null) return const LibraryMatches();
    final results = state.results;
    if (state.loading || results == null) return null;
    return LibraryMatches.fromResults(results);
  }
}
