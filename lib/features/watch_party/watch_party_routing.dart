import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../app/router.dart';
import 'party_notices.dart';
import 'watch_party_session.dart';

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

  @override
  Uri get location => _router.routeInformationProvider.value.uri;

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
    if (playlistItemId == null) return;
    final entry = ref.read(watchPartySessionProvider).queue!.playing!;
    final navigator = ref.read(partyNavigatorProvider);
    final location = navigator.location;
    // Un player del gruppo è già aperto: il cambio di elemento lo fa lui,
    // mantenendo lo schermo intero e segnando l'episodio visto.
    if (location.queryParameters.containsKey('party')) return;
    final route = playerRoute(entry.itemId,
        start: ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
        party: playlistItemId);
    if (location.path.startsWith('/play/')) {
      navigator.replace(route);
    } else {
      navigator.open(route);
    }
  });
});
