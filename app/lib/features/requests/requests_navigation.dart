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

/// Le schede della pagina Richieste (spec I §9.4).
enum RequestsTab {
  mine(RequestsFilter.mine),
  pending(RequestsFilter.pending),
  all(RequestsFilter.all);

  const RequestsTab(this.filter);

  final RequestsFilter filter;

  /// Dal parametro `tab` dell'indirizzo; `null` se manca o non vale.
  static RequestsTab? parse(String? raw) => switch (raw) {
        'mine' => mine,
        'pending' => pending,
        'all' => all,
        _ => null,
      };
}

/// Apre la pagina Richieste, sulla scheda [tab] se c'è (spec I §9.6).
void openRequests(BuildContext context, {RequestsTab? tab}) =>
    context.go(tab == null ? '/requests' : '/requests?tab=${tab.name}');

/// Apre una richiesta (spec I §9.4): la scheda della libreria se il titolo
/// c'è, altrimenti la scheda da richiedere.
void openRequest(BuildContext context, MediaRequest request) {
  final itemId = request.jellyfinItemId;
  if (itemId != null) {
    openItemById(context, itemId);
    return;
  }
  unawaited(context.push(tmdbRoute(request.mediaType, request.tmdbId)));
}
