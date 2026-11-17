import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../collections/collections_logic.dart';
import '../library/library_providers.dart';
import 'search_controller.dart';

/// Le ultime ricerche, dalla più recente, salvate sul dispositivo per profilo.
class RecentSearches extends Notifier<List<String>> {
  static const max = 8;

  String get _key => 'search.recent.${ref.read(currentUserIdProvider)}';

  @override
  List<String> build() {
    final userId = ref.watch(currentUserIdProvider);
    return ref.watch(sharedPreferencesProvider).getStringList('search.recent.$userId') ??
        const [];
  }

  void add(String term) {
    final trimmed = term.trim();
    if (trimmed.length < SearchController.minLength) return;
    final folded = foldForSearch(trimmed);
    _save([
      trimmed,
      for (final old in state)
        if (foldForSearch(old) != folded) old,
    ].take(max).toList());
  }

  void remove(String term) {
    final folded = foldForSearch(term);
    _save([
      for (final old in state)
        if (foldForSearch(old) != folded) old,
    ]);
  }

  void clear() => _save(const []);

  void _save(List<String> terms) {
    state = terms;
    ref.read(sharedPreferencesProvider).setStringList(_key, terms);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);
