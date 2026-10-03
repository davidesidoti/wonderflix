import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../social/social_providers.dart';
import 'friends_controller.dart';

/// Ricerca di utenti nel pannello Amici (spec F §8.1, §8.3).
class FriendSearchState {
  const FriendSearchState({
    this.query = '',
    this.results = const [],
    this.searching = false,
    this.failure,
  });

  /// Testo cercato, senza spazi ai lati.
  final String query;
  final List<UserSearchResult> results;

  /// Una ricerca sta per partire o è in corso.
  final bool searching;

  /// Perché l'ultima ricerca non è riuscita; `null` se è riuscita.
  final SocialFailure? failure;

  /// Il pannello mostra i risultati al posto delle liste.
  bool get active => query.length >= FriendSearch.minLength;
}

class FriendSearch extends Notifier<FriendSearchState> {
  /// Attesa dall'ultima lettera alla ricerca.
  static const debounce = Duration(milliseconds: 300);

  /// Lettere minime, come nel plugin (spec F §6.2).
  static const minLength = 2;

  Timer? _timer;

  /// Cresce a ogni ricerca e a ogni testo nuovo: vale solo l'ultima.
  int _runs = 0;

  @override
  FriendSearchState build() {
    ref.onDispose(() => _timer?.cancel());
    // Gli amici cambiano (azione fatta qui, avviso dell'altra parte, altro
    // dispositivo): la relazione dei risultati è cambiata, si ripete. Se la
    // ricerca aspetta ancora il debounce, partirà lei con i dati nuovi.
    ref.listen(friendsControllerProvider.select((s) => s.snapshot), (_, _) {
      if (state.active && !(_timer?.isActive ?? false)) {
        unawaited(_run(state.query));
      }
    });
    return const FriendSearchState();
  }

  void setQuery(String text) {
    final query = text.trim();
    if (query == state.query) return;
    _timer?.cancel();
    _runs++;
    if (query.length < minLength) {
      state = FriendSearchState(query: query);
      return;
    }
    state = FriendSearchState(
        query: query, results: state.results, searching: true);
    _timer = Timer(debounce, () => unawaited(_run(query)));
  }

  /// Ripete la ricerca corrente (dopo un'azione su un risultato). Il
  /// pannello può essersi chiuso nel frattempo.
  Future<void> rerun() async {
    if (ref.mounted && state.active) await _run(state.query);
  }

  Future<void> _run(String query) async {
    final run = ++_runs;
    try {
      final results = await ref.read(socialApiProvider).search(query);
      if (!ref.mounted || run != _runs) return;
      state = FriendSearchState(query: query, results: results);
    } on Object catch (error) {
      if (!ref.mounted || run != _runs) return;
      state = FriendSearchState(
        query: query,
        results: state.results,
        failure: error is SocialException ? error.failure : SocialFailure.network,
      );
    }
  }
}

/// Vive finché il pannello è aperto.
final friendSearchProvider =
    NotifierProvider.autoDispose<FriendSearch, FriendSearchState>(
        FriendSearch.new);
