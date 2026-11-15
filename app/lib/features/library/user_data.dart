import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/jellyfin/library_api.dart';
import '../auth/session_controller.dart';
import 'library_providers.dart';
import 'my_list_added.dart';

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

  /// Cuore del server: lo stato nuovo, con l'avanzamento di prima se il
  /// server non lo rimanda.
  static Future<UserItemData> _sendFavorite(
      LibraryApi api, String userId, String itemId, UserItemData next) async {
    final confirmed =
        await api.setFavorite(userId, itemId, favorite: next.isFavorite);
    // Per una serie il server non rimanda l'avanzamento: resta quello di prima.
    return UserItemData(
      played: confirmed.played,
      isFavorite: confirmed.isFavorite,
      playbackPositionTicks: confirmed.playbackPositionTicks,
      playedPercentage: confirmed.playedPercentage ?? next.playedPercentage,
      unplayedItemCount: confirmed.unplayedItemCount ?? next.unplayedItemCount,
    );
  }

  /// Accende o spegne il cuore; quando il server conferma, scrive (o toglie)
  /// la data di aggiunta a "La mia lista". Se la data non si salva il cuore
  /// resta e l'errore non sale.
  Future<void> toggleFavorite(JellyfinItem item) async {
    final confirmed = await _toggle(
      item,
      (data) => data.copyWith(isFavorite: !data.isFavorite),
      (api, userId, next) => _sendFavorite(api, userId, item.id, next),
    );
    if (confirmed == null || !ref.mounted) return;
    await ref.read(myListAddedProvider.notifier).change({
      jellyfinIdKey(item.id): confirmed.isFavorite ? clock.now().toUtc() : null,
    });
  }

  /// Accende o spegne il cuore di [items], una richiesta per titolo in
  /// parallelo (come [toggleFavorite]); i titoli con una richiesta in corso si
  /// saltano. Alla fine una sola scrittura delle date: [addedAt] (o adesso)
  /// per i riusciti accesi, `null` per i riusciti spenti. Restituisce i
  /// titoli non riusciti; non lancia errori.
  Future<List<JellyfinItem>> setFavorites(
    List<JellyfinItem> items, {
    required bool favorite,
    Map<String, DateTime> addedAt = const {},
  }) async {
    final failed = <JellyfinItem>[];
    final done = <String>[];
    await Future.wait([
      for (final item in items)
        () async {
          try {
            final confirmed = await _toggle(
              item,
              (data) => data.copyWith(isFavorite: favorite),
              (api, userId, next) => _sendFavorite(api, userId, item.id, next),
            );
            if (confirmed != null) done.add(item.id);
          } on Object {
            failed.add(item);
          }
        }(),
    ]);
    if (done.isNotEmpty && ref.mounted) {
      final now = clock.now().toUtc();
      await ref.read(myListAddedProvider.notifier).change({
        for (final id in done)
          jellyfinIdKey(id): favorite ? addedAt[id] ?? now : null,
      });
    }
    return failed;
  }

  Future<void> togglePlayed(JellyfinItem item) => _toggle(
        item,
        (data) => data.copyWith(played: !data.played),
        (api, userId, next) => api.setPlayed(userId, item.id, played: next.played),
      );

  /// Punto di ripresa di [item] a [ticks] (0: fuori da "Continua a
  /// guardare"); lo stato "visto" resta.
  Future<void> setPlaybackPosition(JellyfinItem item, int ticks) => _toggle(
        item,
        (data) => UserItemData(
          played: data.played,
          isFavorite: data.isFavorite,
          playbackPositionTicks: ticks,
          // A 0 la barra dell'avanzamento sparisce subito.
          playedPercentage: ticks == 0 ? null : data.playedPercentage,
          unplayedItemCount: data.unplayedItemCount,
        ),
        (api, userId, next) => api.setPlaybackPosition(userId, item.id, ticks),
      );

  /// Lo stato confermato dal server, o `null` se il titolo aveva già una
  /// richiesta in corso (saltato). Se la richiesta fallisce torna com'era e
  /// rilancia.
  Future<UserItemData?> _toggle(
    JellyfinItem item,
    UserItemData Function(UserItemData current) change,
    Future<UserItemData> Function(LibraryApi api, String userId, UserItemData next)
        send,
  ) async {
    // Un secondo tocco mentre la richiesta è in corso viene ignorato.
    if (!_pending.add(item.id)) return null;
    final before = effective(item);
    final next = change(before);
    apply(item.id, next);
    try {
      final confirmed = await send(ref.read(libraryApiProvider),
          ref.read(currentUserIdProvider), next);
      if (!ref.mounted) return null;
      apply(item.id, confirmed);
      return confirmed;
    } on Object {
      if (!ref.mounted) return null;
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
