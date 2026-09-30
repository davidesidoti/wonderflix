import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../app/navigation.dart';
import '../../app/router.dart';
import '../player/player_providers.dart';
import 'party_notices.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Dove si trova l'app e come aprire il player (sostituibile nei test).
abstract interface class PartyNavigator {
  /// Percorso attuale, es. `/play/m1?party=p1`.
  Uri get location;

  void open(String route);

  /// Sostituisce la pagina attuale (il player aperto).
  void replace(String route);
}

class _RouterNavigator implements PartyNavigator {
  _RouterNavigator(this._router);

  final GoRouter _router;

  /// Pagina in cima: dopo `push` e `pushReplacement` l'indirizzo del
  /// `routeInformationProvider` torna quello della pagina di base (es.
  /// `/home`), anche con un player aperto sopra.
  @override
  Uri get location {
    if (_router.routerDelegate.currentConfiguration.isEmpty) {
      return _router.routeInformationProvider.value.uri;
    }
    return _router.state.uri;
  }

  @override
  void open(String route) => unawaited(_router.push<void>(route));

  @override
  void replace(String route) =>
      unawaited(_router.pushReplacement<void>(route));
}

final partyNavigatorProvider = Provider<PartyNavigator>(
    (ref) => _RouterNavigator(ref.watch(routerProvider)));

/// Apre il player quando il gruppo sceglie cosa guardare (ingresso). Con un
/// player del gruppo già aperto il cambio lo fa il player. Lo osserva
/// `WonderflixApp`.
final watchPartyRoutingProvider = Provider<void>((ref) {
  // Gli avvisi devono vedere anche la prima coda del gruppo.
  ref.listen(partyNoticesProvider, (_, _) {});
  ref.listen(
      watchPartySessionProvider.select(
          (s) => s.inGroup ? s.queue?.playing?.playlistItemId : null),
      (_, playlistItemId) {
    if (playlistItemId != null) unawaited(_openParty(ref, playlistItemId));
  });
});

/// Apre il player dell'elemento [playlistItemId] del gruppo. Con un player
/// del gruppo già aperto non fa nulla (il cambio lo fa lui); con un player
/// da solo in cima ("Guarda insieme" dal player) lo sostituisce, lasciando
/// lo schermo intero com'è.
Future<void> _openParty(Ref ref, String playlistItemId) async {
  final navigator = ref.read(partyNavigatorProvider);
  final location = navigator.location;
  if (location.queryParameters.containsKey('party')) return;
  final entry = ref.read(watchPartySessionProvider).queue?.playing;
  if (entry == null || entry.playlistItemId != playlistItemId) return;
  String route(bool fullscreen) => playerRoute(entry.itemId,
      start: ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
      fullscreen: fullscreen,
      party: playlistItemId);
  if (!location.path.startsWith('/play/')) {
    navigator.open(route(false));
    return;
  }
  var fullscreen = false;
  try {
    fullscreen = await ref.read(playerWindowProvider).isFullScreen();
  } on Object catch (error) {
    _log.info('stato dello schermo intero non disponibile: $error');
  }
  // Nel frattempo il gruppo può essere passato ad altro.
  if (!ref.mounted) return;
  final party = ref.read(watchPartySessionProvider);
  if (!party.inGroup || party.queue?.playing?.playlistItemId != playlistItemId) {
    return;
  }
  navigator.replace(route(fullscreen));
}
