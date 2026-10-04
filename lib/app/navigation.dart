import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/jellyfin/item_models.dart';
import '../features/library/library_providers.dart';
import 'hero_launch.dart';

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

/// Apre [item]. Con [heroSource] (la card cliccata) la pagina riceve un
/// [HeroLaunch] e l'immagine vola nella testata.
void openItem(BuildContext context, JellyfinItem item, {String? heroSource}) {
  HeroLaunch? launch;
  if (heroSource != null) {
    final urls = ProviderScope.containerOf(context, listen: false)
        .read(imageUrlsProvider);
    launch = HeroLaunch(
      tag: WfHeroTag(item.id, heroSource),
      image: urls.backdrop(item),
      fallback: urls.poster(item),
      title: item.name,
    );
  }
  unawaited(context.push(itemRoute(item), extra: launch));
}

/// Apre la scheda di un film o di una serie di cui si conosce solo l'id (es.
/// una riga delle novità nella cassetta, spec G §7.6).
void openItemById(BuildContext context, String itemId) =>
    unawaited(context.push('/item/$itemId'));

/// Apre la pagina di [person]; con [heroSource] la foto vola dal cast.
void openPerson(BuildContext context, PersonRef person, {String? heroSource}) {
  HeroLaunch? launch;
  if (heroSource != null) {
    final urls = ProviderScope.containerOf(context, listen: false)
        .read(imageUrlsProvider);
    launch = HeroLaunch(
      tag: WfHeroTag(person.id, heroSource),
      // 400 px come `urls.poster` nella pagina della persona: stesso URL,
      // la foto non cambia all'arrivo dei dati.
      image: urls.person(person, maxWidth: 400),
      title: person.name,
    );
  }
  unawaited(context.push('/person/${person.id}', extra: launch));
}

/// `extra` di un player che ne sostituisce un altro (episodio successivo,
/// passaggio al player del gruppo): sotto la transizione serve il nero,
/// altrimenti si vedrebbe la pagina sotto i due player (spec D §6.3).
class PlayerReplacement {
  const PlayerReplacement();
}

const playerReplacement = PlayerReplacement();

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
