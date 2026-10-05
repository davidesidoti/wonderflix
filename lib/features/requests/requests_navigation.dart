import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../core/requests/requests_models.dart';

/// La rotta della scheda da richiedere (spec I §9.2).
String tmdbRoute(RequestMediaType type, int tmdbId) =>
    '/tmdb/${type.wire}/$tmdbId';

/// Apre un titolo di Seerr: la scheda della libreria se c'è già tutto
/// ("Su WonderFlix"), altrimenti la scheda da richiedere.
void openRequestable(BuildContext context, RequestableTitle title) {
  final itemId = title.jellyfinItemId;
  if (title.status == TitleStatus.available && itemId != null) {
    openItemById(context, itemId);
    return;
  }
  unawaited(context.push(tmdbRoute(title.mediaType, title.tmdbId)));
}
