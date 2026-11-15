import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/collections_api.dart';
import '../../core/social/collections_models.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import 'collections_logic.dart';

final _log = Logger('collections');

final collectionsApiProvider = Provider<CollectionsApi>(
    (ref) => CollectionsApi(ref.watch(jellyfinHttpProvider)));

/// Le saghe dell'utente (spec K §8.1): solo con la funzione `collections`
/// del plugin; senza, vuoto e nessuna chiamata. Si rilegge quando cambia la
/// libreria o l'utente. Dopo una lettura riuscita resta in cache anche senza
/// ascoltatori (la usano la scheda del film, il catalogo e la ricerca); un
/// errore no: si riprova quando qualcuno torna ad ascoltare.
final collectionsProvider =
    FutureProvider.autoDispose<List<CollectionSummary>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final available = ref.watch(
      socialAvailabilityProvider.select((features) => features.collections));
  // Questo `return` sta prima di `currentUserIdProvider`, che lancia senza
  // utente: senza la funzione non serve (e può non esserci) un utente.
  if (!available) return const [];
  ref.watch(currentUserIdProvider);
  final api = ref.watch(collectionsApiProvider);
  // Tutti i `ref.watch` stanno prima dell'`await`. Il collegamento tiene in
  // vita il risultato; si chiude se la lettura fallisce.
  final link = ref.keepAlive();
  try {
    return List.unmodifiable(await api.collections());
  } on Object catch (error) {
    link.close();
    // Solo il tipo: il messaggio può citare la risposta. Gli errori dell'API
    // sono già nel log dello strato HTTP (e 502/503/504, con Jellyfin che si
    // riavvia, sono silenziosi apposta): qui bastano come info.
    final message = 'saghe non lette: ${error.runtimeType}';
    if (error is ApiException) {
      _log.info(message);
    } else {
      _log.warning(message);
    }
    rethrow;
  }
});

/// Le saghe di ogni titolo, per `jellyfinIdKey` dell'id (spec K §8.3);
/// vuoto finché l'elenco non c'è o se non si è potuto leggere.
final collectionsByItemProvider =
    Provider.autoDispose<Map<String, List<CollectionSummary>>>((ref) =>
        indexCollections(ref.watch(collectionsProvider).value ?? const []));

/// I titoli di una saga che l'utente vede, in ordine di uscita (spec K §8.1).
final collectionItemsProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, String>((ref, collectionId) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .collectionItems(ref.watch(currentUserIdProvider), collectionId);
});

/// I film di tutte le saghe, con i dati dell'utente, per `jellyfinIdKey`
/// (spec §9): una sola lettura per tutti gli `itemIds`. Come
/// [collectionsProvider] resta in cache dopo una lettura riuscita; si rilegge
/// quando cambiano la libreria o i dati dell'utente.
final sagaItemsProvider =
    FutureProvider.autoDispose<Map<String, JellyfinItem>>((ref) async {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  final api = ref.watch(libraryApiProvider);
  final sagas = await ref.watch(collectionsProvider.future);
  final ids = {for (final saga in sagas) ...saga.itemIds}.toList();
  if (ids.isEmpty) return const {};
  // L'utente c'è: senza, le saghe sarebbero vuote (vedi sopra).
  final userId = ref.read(currentUserIdProvider);
  final link = ref.keepAlive();
  try {
    final items = await api.itemsByIds(userId, ids);
    return Map.unmodifiable({for (final item in items) jellyfinIdKey(item.id): item});
  } on Object catch (error) {
    link.close();
    _log.info('film delle saghe non letti: ${error.runtimeType}');
    rethrow;
  }
});
