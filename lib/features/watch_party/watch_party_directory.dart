import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import 'watch_party_providers.dart';

final _log = Logger('watchparty');

/// Da dove si legge l'elenco (spec F §9.6).
enum _Source { plugin, jellyfin }

/// Gruppi attivi sul server, per il pulsante della barra in alto. Si
/// aggiorna ogni [interval], a ogni riconnessione del WebSocket e quando
/// cambiano le funzioni del plugin, ma non con il player aperto (spec B
/// §5.8). Con la funzione `parties` legge `GET Parties` del plugin invece di
/// `/SyncPlay/List`; finché le funzioni non sono note non legge nulla,
/// perché l'elenco di Jellyfin non è filtrato per modalità.
class WatchPartyDirectory extends Notifier<List<GroupInfo>> {
  static const interval = Duration(seconds: 30);

  /// Cresce a ogni ricostruzione e a ogni lettura: vale solo la risposta
  /// dell'ultima, una più lenta (magari dall'altra fonte) si scarta.
  int _loads = 0;

  @override
  List<GroupInfo> build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null) return const [];
    // Senza accesso ai watch party l'elenco non serve.
    if (!ref.watch(syncPlayAccessProvider).canJoin) return const [];
    _loads++;
    final timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    ref.onDispose(timer.cancel);
    ref.listen(playerActiveProvider, (_, active) {
      if (!active) unawaited(refresh());
    });
    // Le funzioni del plugin diventano note o cambiano: cambia la fonte.
    ref.listen(
      socialAvailabilityProvider.select((f) => (f.known, f.parties)),
      (_, features) {
        // Quel che c'è viene da `/SyncPlay/List`, non filtrato: via subito.
        if (features.$1 && features.$2) state = const [];
        unawaited(refresh());
      },
      onError: (_, _) {},
    );
    // Gli avvisi persi mentre il WebSocket era giù (spec F §10).
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      if (event is ServerConnected && event.isReconnect) {
        unawaited(refresh());
      }
    });
    ref.onDispose(() => unawaited(connections.cancel()));
    unawaited(Future.microtask(refresh));
    return const [];
  }

  Future<void> refresh() async {
    if (ref.read(playerActiveProvider)) return;
    final source = _source();
    if (source == null) return;
    final load = ++_loads;
    try {
      final groups = switch (source) {
        _Source.plugin => await ref.read(socialApiProvider).parties(),
        _Source.jellyfin => await ref.read(syncPlayApiProvider).list(),
      };
      // Intanto le funzioni (e quindi la fonte) possono essere cambiate.
      if (ref.mounted && load == _loads && _source() == source) {
        state = groups;
      }
    } on Object catch (error) {
      _log.info('elenco dei watch party non disponibile: $error');
    }
  }

  /// La fonte dell'elenco: con la funzione `parties` del plugin l'elenco è
  /// già filtrato per modalità (spec F §9.6); `null` finché le funzioni non
  /// sono note. Se non si possono leggere, come prima (Jellyfin).
  _Source? _source() {
    try {
      final features = ref.read(socialAvailabilityProvider);
      if (!features.known) return null;
      return features.parties ? _Source.plugin : _Source.jellyfin;
    } on Object {
      return _Source.jellyfin;
    }
  }
}

final watchPartyDirectoryProvider =
    NotifierProvider<WatchPartyDirectory, List<GroupInfo>>(
        WatchPartyDirectory.new);
