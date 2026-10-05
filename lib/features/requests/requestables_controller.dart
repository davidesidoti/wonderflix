import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/requests/requests_models.dart';
import '../search/search_controller.dart';
import 'requests_providers.dart';

class RequestablesState {
  const RequestablesState({
    this.term = '',
    this.titles,
    this.loading = false,
    this.error,
  });

  final String term;

  /// I titoli dell'ultima ricerca riuscita; restano mentre si scrive.
  final List<RequestableTitle>? titles;
  final bool loading;
  final Object? error;
}

/// I titoli per la sezione "Da richiedere" (spec I §8.3): segue il termine
/// della ricerca con la stessa attesa, ma è indipendente, così la libreria
/// non aspetta Seerr. Ogni nuova lettera annulla la ricerca precedente.
class RequestablesController extends Notifier<RequestablesState> {
  Timer? _debounce;
  CancelToken? _cancel;

  @override
  RequestablesState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const RequestablesState();
  }

  void setTerm(String raw, {required String language}) {
    final term = raw.trim();
    _debounce?.cancel();
    _cancel?.cancel();
    if (term.length < SearchController.minLength ||
        !ref.read(requestsAvailableProvider)) {
      state = RequestablesState(term: term);
      return;
    }
    state = RequestablesState(term: term, titles: state.titles, loading: true);
    _debounce = Timer(
        SearchController.debounce, () => unawaited(_search(term, language)));
  }

  /// Rifà subito la ricerca del termine di adesso (dopo un errore).
  void retry({required String language}) {
    final term = state.term;
    if (term.length < SearchController.minLength) return;
    _debounce?.cancel();
    _cancel?.cancel();
    state = RequestablesState(term: term, titles: state.titles, loading: true);
    unawaited(_search(term, language));
  }

  Future<void> _search(String term, String language) async {
    final cancel = _cancel = CancelToken();
    try {
      final titles = await ref
          .read(requestsApiProvider)
          .search(term, language: language, cancelToken: cancel);
      if (!ref.mounted || cancel.isCancelled) return;
      state = RequestablesState(term: term, titles: titles);
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = RequestablesState(term: term, error: error);
    }
  }
}

final requestablesControllerProvider =
    NotifierProvider.autoDispose<RequestablesController, RequestablesState>(
        RequestablesController.new);

/// I titoli da mostrare in "Da richiedere" (spec I §8.3): senza quelli che
/// la ricerca nella libreria ha già trovato ([libraryIds], in minuscolo).
List<RequestableTitle> visibleRequestables(
        List<RequestableTitle> titles, Set<String> libraryIds) =>
    [
      for (final title in titles)
        if (title.jellyfinItemId == null ||
            !libraryIds.contains(title.jellyfinItemId!.toLowerCase()))
          title,
    ];
