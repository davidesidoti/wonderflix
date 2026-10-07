import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/item_models.dart';
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
/// libreria o l'utente. Resta in cache (non `autoDispose`): la usano la
/// scheda del film, il catalogo e la ricerca.
final collectionsProvider =
    FutureProvider<List<CollectionSummary>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final available = ref.watch(
      socialAvailabilityProvider.select((features) => features.collections));
  if (!available) return const [];
  ref.watch(currentUserIdProvider);
  final api = ref.watch(collectionsApiProvider);
  try {
    return await api.collections();
  } on Object catch (error) {
    // Solo il tipo: il messaggio può citare la risposta.
    _log.warning('saghe non lette: ${error.runtimeType}');
    rethrow;
  }
});

/// Le saghe di ogni titolo, per `collectionKey` dell'id (spec K §8.3);
/// vuoto finché l'elenco non c'è o se non si è potuto leggere.
final collectionsByItemProvider =
    Provider<Map<String, List<CollectionSummary>>>((ref) =>
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
