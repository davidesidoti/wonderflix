import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../core/jellyfin/json_fields.dart';
import '../library/library_providers.dart';

class SearchResults {
  const SearchResults({
    required this.movies,
    required this.series,
    required this.people,
    required this.movieTotal,
    required this.seriesTotal,
    required this.peopleTotal,
    this.facts,
    List<JellyfinItem>? peopleRanked,
  }) : _peopleRanked = peopleRanked;

  final List<JellyfinItem> movies;
  final List<JellyfinItem> series;
  /// Nell'ordine del server, uguale prima e dopo [facts]: `bestResult` lo usa.
  final List<JellyfinItem> people;
  final List<JellyfinItem>? _peopleRanked;

  /// Da mostrare: le prime persone per numero di titoli, poi le altre.
  List<JellyfinItem> get peopleRanked => _peopleRanked ?? people;
  final int movieTotal;
  final int seriesTotal;
  final int peopleTotal;

  /// Dati delle prime persone, per id; `null` finché arrivano.
  final Map<String, PersonFacts>? facts;

  bool get isEmpty => movies.isEmpty && series.isEmpty && people.isEmpty;
}

/// Il titolo più votato di una persona e quanti ne ha in libreria.
class PersonFacts {
  const PersonFacts({required this.knownFor, required this.titles, this.roleType});

  final JellyfinItem knownFor;
  final int titles;

  /// Il `Type` della persona nel cast di [knownFor] ("Actor", "Director"…).
  final String? roleType;
}

class SearchState {
  const SearchState({this.term = '', this.results, this.loading = false, this.error});

  final String term;
  final SearchResults? results;
  final bool loading;
  final Object? error;
}

/// Ricerca con attesa di 300 ms: ogni nuova lettera annulla la precedente.
class SearchController extends Notifier<SearchState> {
  static const debounce = Duration(milliseconds: 300);
  static const minLength = 2;
  static const peopleWithFacts = 6;

  Timer? _debounce;
  CancelToken? _cancel;

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const SearchState();
  }

  void setTerm(String raw) {
    final term = raw.trim();
    _debounce?.cancel();
    _cancel?.cancel();
    if (term.length < minLength) {
      state = SearchState(term: term);
      return;
    }
    state = SearchState(term: term, results: state.results, loading: true);
    _debounce = Timer(debounce, () => unawaited(_search(term)));
  }

  /// Invio: cerca subito il termine che aspetta ancora i 300 ms. Con una
  /// richiesta già partita non fa niente: chi apre il miglior risultato
  /// aspetta `state.term == term && !state.loading && state.results != null`.
  void submit() {
    if (!(_debounce?.isActive ?? false)) return;
    _debounce!.cancel();
    unawaited(_search(state.term));
  }

  Future<void> _search(String term) async {
    final cancel = _cancel = CancelToken();
    try {
      // Letti qui dentro: un timer scattato dopo il logout non deve lanciare.
      final api = ref.read(libraryApiProvider);
      final userId = ref.read(currentUserIdProvider);
      Future<ItemPage> items(ItemKind kind) => api.items(
            // `ProviderIds`: l'id TMDB serve a nascondere in "Da richiedere"
            // i titoli che Seerr non sa ancora in libreria.
            ItemQuery(
                kinds: {kind},
                searchTerm: term,
                includeProviderIds: true,
                includeOverview: true,
                includeSearchFields: true),
            userId: userId,
            startIndex: 0,
            limit: 24,
            cancelToken: cancel,
          );
      final pages = await Future.wait([
        items(ItemKind.movie),
        items(ItemKind.series),
        api.searchPeople(userId, term, limit: 12, cancelToken: cancel),
      ]);
      if (!ref.mounted || cancel.isCancelled) return;
      final results = SearchResults(
        movies: pages[0].items,
        series: pages[1].items,
        people: pages[2].items,
        movieTotal: pages[0].totalCount,
        seriesTotal: pages[1].totalCount,
        peopleTotal: pages[2].totalCount,
      );
      state = SearchState(term: term, results: results);

      Future<PersonFacts?> factsOf(JellyfinItem person) async {
        try {
          final page = await api.items(
            ItemQuery(
                kinds: {ItemKind.movie, ItemKind.series},
                personId: person.id,
                sort: CatalogSort.rating,
                includePeople: true),
            userId: userId,
            startIndex: 0,
            limit: 1,
            cancelToken: cancel,
          );
          if (page.items.isEmpty) return null;
          final knownFor = page.items.first;
          final key = jellyfinIdKey(person.id);
          return PersonFacts(
            knownFor: knownFor,
            titles: page.totalCount,
            roleType: knownFor.people
                .where((p) => jellyfinIdKey(p.id) == key)
                .firstOrNull
                ?.type,
          );
        } on Object {
          return null; // Una persona senza dati non è un errore della ricerca.
        }
      }

      final first = results.people.take(peopleWithFacts).toList();
      final found = await Future.wait(first.map(factsOf));
      if (!ref.mounted || cancel.isCancelled) return;
      final facts = {
        for (var i = 0; i < first.length; i++) first[i].id: ?found[i],
      };
      // Indice come spareggio: `sort` non è stabile.
      final order = List.generate(first.length, (i) => i)
        ..sort((a, b) {
          final byTitles =
              (found[b]?.titles ?? -1).compareTo(found[a]?.titles ?? -1);
          return byTitles != 0 ? byTitles : a.compareTo(b);
        });
      state = SearchState(
        term: term,
        results: SearchResults(
          movies: results.movies,
          series: results.series,
          people: results.people,
          peopleRanked: [
            for (final i in order) first[i],
            ...results.people.skip(peopleWithFacts),
          ],
          movieTotal: results.movieTotal,
          seriesTotal: results.seriesTotal,
          peopleTotal: results.peopleTotal,
          facts: facts,
        ),
      );
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = SearchState(term: term, error: error);
    }
  }
}

final searchControllerProvider =
    NotifierProvider.autoDispose<SearchController, SearchState>(SearchController.new);
