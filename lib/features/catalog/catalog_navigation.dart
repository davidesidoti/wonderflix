import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Vista del catalogo Film: i titoli o le saghe (spec K §8.4). Sta
/// nell'indirizzo (`/movies?view=sagas`).
enum CatalogView {
  titles,
  sagas;

  /// Dal parametro `view` dell'indirizzo: senza, o con un valore
  /// sconosciuto, i titoli.
  static CatalogView parse(String? raw) => raw == sagas.name ? sagas : titles;
}

/// Apre il catalogo Film sulla vista [view].
void openMovies(BuildContext context,
        {CatalogView view = CatalogView.titles}) =>
    context.go(view == CatalogView.titles
        ? '/movies'
        : '/movies?view=${view.name}');
