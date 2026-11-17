import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/item_models.dart';

/// Vista del catalogo Film: i titoli o le saghe (spec K §8.4). Sta
/// nell'indirizzo (`/movies?view=sagas`).
enum CatalogView {
  titles,
  sagas;

  /// Dal parametro `view` dell'indirizzo: senza, o con un valore
  /// sconosciuto, i titoli.
  static CatalogView parse(String? raw) => raw == sagas.name ? sagas : titles;
}

/// Apre il catalogo di [kind] sulla vista [view] e, se c'è, sul [genre]
/// (`/series?genre=Dramma`): il genere sta nell'indirizzo, così Indietro e i
/// link lo ritrovano.
void openCatalog(BuildContext context, ItemKind kind,
    {CatalogView view = CatalogView.titles, String? genre}) {
  final path = kind == ItemKind.series ? '/series' : '/movies';
  final query = {
    if (view != CatalogView.titles) 'view': view.name,
    'genre': ?genre,
  };
  context.go(Uri(path: path, queryParameters: query.isEmpty ? null : query)
      .toString());
}

/// Apre il catalogo di [kind] con la ricerca [term] già scritta
/// (`/movies?q=…`): con push, così Indietro torna a Cerca coi risultati.
void openCatalogSearch(BuildContext context, ItemKind kind, String term) {
  final path = kind == ItemKind.series ? '/series' : '/movies';
  unawaited(context
      .push(Uri(path: path, queryParameters: {'q': term}).toString()));
}
