import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/library_api.dart';
import '../auth/session_controller.dart';
import 'library_providers.dart';

/// Dati utente aggiornati dopo il caricamento (azioni locali ed eventi del
/// server), per id elemento. Le card leggono da qui prima che da `item.userData`.
class UserDataOverrides extends Notifier<Map<String, UserItemData>> {
  @override
  Map<String, UserItemData> build() {
    // Si azzera quando cambia l'utente.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return const {};
  }

  /// Richieste di modifica in corso, per id elemento.
  final _pending = <String>{};

  void apply(String itemId, UserItemData data) =>
      state = {...state, itemId: data};

  /// Applica più modifiche con un solo aggiornamento dello stato.
  void applyAll(Map<String, UserItemData> changes) {
    if (changes.isEmpty) return;
    state = {...state, ...changes};
  }

  /// Dimentica tutte le modifiche (es. dopo una riconnessione).
  void clear() => state = const {};

  UserItemData effective(JellyfinItem item) => state[item.id] ?? item.userData;

  Future<void> toggleFavorite(JellyfinItem item) => _toggle(
        item,
        (data) => data.copyWith(isFavorite: !data.isFavorite),
        (api, userId, next) =>
            api.setFavorite(userId, item.id, favorite: next.isFavorite),
      );

  Future<void> togglePlayed(JellyfinItem item) => _toggle(
        item,
        (data) => data.copyWith(played: !data.played),
        (api, userId, next) => api.setPlayed(userId, item.id, played: next.played),
      );

  Future<void> _toggle(
    JellyfinItem item,
    UserItemData Function(UserItemData current) change,
    Future<UserItemData> Function(LibraryApi api, String userId, UserItemData next)
        send,
  ) async {
    // Un secondo tocco mentre la richiesta è in corso viene ignorato.
    if (!_pending.add(item.id)) return;
    final before = effective(item);
    final next = change(before);
    apply(item.id, next);
    try {
      final confirmed = await send(ref.read(libraryApiProvider),
          ref.read(currentUserIdProvider), next);
      if (!ref.mounted) return;
      apply(item.id, confirmed);
    } on Object {
      if (!ref.mounted) return;
      apply(item.id, before);
      rethrow;
    } finally {
      _pending.remove(item.id);
    }
  }
}

final userDataOverridesProvider =
    NotifierProvider<UserDataOverrides, Map<String, UserItemData>>(
        UserDataOverrides.new);

/// Dati utente aggiornati di [item], da usare nel `build` dei widget.
UserItemData watchUserData(WidgetRef ref, JellyfinItem item) =>
    ref.watch(userDataOverridesProvider.select((m) => m[item.id])) ??
    item.userData;
