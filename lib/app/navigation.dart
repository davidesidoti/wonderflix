import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/jellyfin/item_models.dart';

/// Percorso da aprire per [item]: episodi e stagioni aprono la serie.
String itemRoute(JellyfinItem item) {
  final seriesId = item.seriesId;
  switch (item.kind) {
    case ItemKind.person:
      return '/person/${item.id}';
    case ItemKind.season when seriesId != null:
      return Uri(path: '/item/$seriesId', queryParameters: {'season': item.id})
          .toString();
    case ItemKind.episode when seriesId != null:
      final seasonId = item.seasonId;
      return Uri(
        path: '/item/$seriesId',
        queryParameters: seasonId == null ? null : {'season': seasonId},
      ).toString();
    default:
      return '/item/${item.id}';
  }
}

void openItem(BuildContext context, JellyfinItem item) =>
    context.push(itemRoute(item));

void openPerson(BuildContext context, PersonRef person) =>
    context.push('/person/${person.id}');

/// Percorso del player; [start] è la posizione di partenza, [fullscreen]
/// dice che la finestra è già a schermo intero (passaggio all'episodio
/// successivo), [party] è l'id dell'elemento nella coda del watch party.
String playerRoute(String itemId,
    {Duration start = Duration.zero, bool fullscreen = false, String? party}) {
  final query = {
    if (start > Duration.zero) 'start': '${start.inMilliseconds}',
    if (fullscreen) 'fs': '1',
    'party': ?party,
  };
  return Uri(
    path: '/play/$itemId',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// Posizione di partenza dal parametro `start` (millisecondi) del percorso.
Duration playerStartFrom(Uri uri) => Duration(
    milliseconds: int.tryParse(uri.queryParameters['start'] ?? '') ?? 0);
