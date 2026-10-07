import 'dart:async';

import 'package:wonderflix/core/social/collections_api.dart';
import 'package:wonderflix/core/social/collections_models.dart';

/// `CollectionsApi` in memoria: elenco configurabile e chiamate contate.
class FakeCollectionsApi implements CollectionsApi {
  List<CollectionSummary> collectionsList = [];

  /// Se valorizzato, ogni chiamata lancia questo errore.
  Object? error;

  int calls = 0;

  /// Se valorizzato, ogni chiamata aspetta che si completi prima di
  /// rispondere (per provare lo stato di caricamento).
  Completer<void>? gate;

  @override
  Future<List<CollectionSummary>> collections() async {
    calls++;
    final pending = gate;
    if (pending != null) await pending.future;
    final failure = error;
    if (failure != null) throw failure;
    return collectionsList;
  }
}

/// Una saga di prova: `SortName` è il nome in minuscolo. Gli `itemIds` vanno
/// passati già normalizzati (minuscoli e senza trattini, come
/// `jellyfinIdKey`): il costruttore non li normalizza, lo fa solo
/// `CollectionSummary.fromJson`. L'`id` della saga resta com'è.
CollectionSummary testCollection({
  String id = 'c1',
  String name = 'Matrix - Collezione',
  List<String> itemIds = const ['m1', 'm2'],
  String? tag = 'tag-c1',
  DateTime? dateCreated,
}) =>
    CollectionSummary(
      id: id,
      name: name,
      sortName: name.toLowerCase(),
      primaryImageTag: tag,
      dateCreated: dateCreated,
      itemIds: itemIds,
    );
