import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/jellyfin/api_exception.dart';
import '../../../core/jellyfin/item_models.dart';
import '../../../core/jellyfin/item_query.dart';
import '../../library/library_providers.dart';
import '../../watch_party/watch_party_session.dart';

/// Una vista del pannello "Coda" (spec H §9.2). Due viste sono uguali se
/// mostrano la stessa cosa: serve a [QueuePanelNav.open].
sealed class QueuePanelPage {
  const QueuePanelPage();
}

/// La coda del gruppo.
final class QueuePanelQueue extends QueuePanelPage {
  const QueuePanelQueue();

  @override
  bool operator ==(Object other) => other is QueuePanelQueue;

  @override
  int get hashCode => (QueuePanelQueue).hashCode;
}

/// Ricerca e La mia lista.
final class QueuePanelAdd extends QueuePanelPage {
  const QueuePanelAdd();

  @override
  bool operator ==(Object other) => other is QueuePanelAdd;

  @override
  int get hashCode => (QueuePanelAdd).hashCode;
}

/// Le stagioni di una serie.
final class QueuePanelSeries extends QueuePanelPage {
  const QueuePanelSeries(this.series);

  final JellyfinItem series;

  @override
  bool operator ==(Object other) =>
      other is QueuePanelSeries && other.series.id == series.id;

  @override
  int get hashCode => Object.hash(QueuePanelSeries, series.id);
}

/// Gli episodi di una stagione.
final class QueuePanelSeason extends QueuePanelPage {
  const QueuePanelSeason(this.series, this.season);

  final JellyfinItem series;
  final JellyfinItem season;

  @override
  bool operator ==(Object other) =>
      other is QueuePanelSeason &&
      other.series.id == series.id &&
      other.season.id == season.id;

  @override
  int get hashCode => Object.hash(QueuePanelSeason, series.id, season.id);
}

/// Le viste aperte nel pannello, dalla Coda in giù (l'ultima è quella
/// mostrata). Globale: quando il gruppo cambia titolo il player si
/// sostituisce, e il pannello si riapre dov'era (spec H §9.1). Si azzera
/// aprendo il pannello dal pulsante e uscendo dal gruppo.
class QueuePanelNav extends Notifier<List<QueuePanelPage>> {
  @override
  List<QueuePanelPage> build() {
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) reset();
    });
    return const [QueuePanelQueue()];
  }

  /// Apre [page] sopra le altre. Se è già quella in cima non fa nulla: un
  /// doppio clic durante la dissolvenza tra due viste non la ripete.
  void open(QueuePanelPage page) {
    if (state.last == page) return;
    state = [...state, page];
  }

  /// Torna alla vista prima; la Coda resta.
  void back() {
    if (state.length > 1) state = state.sublist(0, state.length - 1);
  }

  void reset() => state = const [QueuePanelQueue()];
}

final queuePanelNavProvider =
    NotifierProvider<QueuePanelNav, List<QueuePanelPage>>(QueuePanelNav.new);

class QueueAddSearchState {
  const QueueAddSearchState({this.term = '', this.results, this.error});

  final String term;

  /// Film e serie trovati; `null` finché non c'è una risposta.
  final List<JellyfinItem>? results;
  final Object? error;
}

/// La ricerca della vista Aggiungi (spec H §9.2): film e serie, da
/// [minLength] lettere, [debounce] dopo l'ultimo tasto, al massimo [limit];
/// una ricerca nuova annulla la vecchia. Globale come [QueuePanelNav], e si
/// azzera con lei.
class QueueAddSearch extends Notifier<QueueAddSearchState> {
  /// Attesa dopo l'ultimo tasto prima di cercare.
  static const debounce = Duration(milliseconds: 300);

  /// Lettere minime per cercare.
  static const minLength = 2;

  /// Risultati al massimo.
  static const limit = 20;

  Timer? _debounce;
  CancelToken? _cancel;

  @override
  QueueAddSearchState build() {
    ref.onDispose(_stop);
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) reset();
    });
    return const QueueAddSearchState();
  }

  void setTerm(String raw) {
    final term = raw.trim();
    _stop();
    if (term.length < minLength) {
      state = QueueAddSearchState(term: term);
      return;
    }
    // I risultati di prima restano in vista finché arrivano quelli nuovi.
    state = QueueAddSearchState(term: term, results: state.results);
    _debounce = Timer(debounce, () => unawaited(_search(term)));
  }

  /// Rifà subito la ricerca di adesso (dopo un errore).
  void retry() {
    final term = state.term;
    if (term.length < minLength) return;
    _stop();
    state = QueueAddSearchState(term: term);
    unawaited(_search(term));
  }

  void reset() {
    _stop();
    state = const QueueAddSearchState();
  }

  void _stop() {
    _debounce?.cancel();
    _cancel?.cancel();
  }

  Future<void> _search(String term) async {
    final cancel = _cancel = CancelToken();
    try {
      // Letti qui dentro: un timer scattato dopo il logout non deve lanciare.
      final page = await ref.read(libraryApiProvider).items(
            ItemQuery(
                kinds: const {ItemKind.movie, ItemKind.series},
                searchTerm: term),
            userId: ref.read(currentUserIdProvider),
            startIndex: 0,
            limit: limit,
            cancelToken: cancel,
          );
      if (!ref.mounted || cancel.isCancelled) return;
      state = QueueAddSearchState(term: term, results: page.items);
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = QueueAddSearchState(term: term, error: error);
    }
  }
}

final queueAddSearchProvider =
    NotifierProvider<QueueAddSearch, QueueAddSearchState>(QueueAddSearch.new);

/// Tutti gli episodi veri di una serie, per le viste Serie e Stagione (spec H
/// §9.2): una richiesta sola.
final queueSeriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, String>((ref, seriesId) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .allEpisodes(ref.watch(currentUserIdProvider), seriesId);
});
