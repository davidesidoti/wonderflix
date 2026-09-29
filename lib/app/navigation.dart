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
