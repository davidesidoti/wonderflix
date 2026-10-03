import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import 'watch_party_providers.dart';

final _log = Logger('watchparty');

/// Gruppi attivi sul server, per il pulsante della barra in alto. Si
/// aggiorna ogni [interval], ma non con il player aperto (spec B §5.8).
/// Con la funzione `parties` legge `GET Parties` del plugin invece di
/// `/SyncPlay/List`.
class WatchPartyDirectory extends Notifier<List<GroupInfo>> {
  static const interval = Duration(seconds: 30);

  @override
  List<GroupInfo> build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null) return const [];
    // Senza accesso ai watch party l'elenco non serve.
    if (!ref.watch(syncPlayAccessProvider).canJoin) return const [];
    final timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    ref.onDispose(timer.cancel);
    ref.listen(playerActiveProvider, (_, active) {
      if (!active) unawaited(refresh());
    });
    unawaited(Future.microtask(refresh));
    return const [];
  }

  Future<void> refresh() async {
    if (ref.read(playerActiveProvider)) return;
    try {
      final groups = _partiesAvailable()
          ? await ref.read(socialApiProvider).parties()
          : await ref.read(syncPlayApiProvider).list();
      if (ref.mounted) state = groups;
    } on Object catch (error) {
      _log.info('elenco dei watch party non disponibile: $error');
    }
  }

  /// Con la funzione `parties` del plugin l'elenco è già filtrato per
  /// modalità (spec F §9.6). Se le funzioni non si possono leggere, come
  /// prima.
  bool _partiesAvailable() {
    try {
      return ref.read(socialAvailabilityProvider).parties;
    } on Object {
      return false;
    }
  }
}

final watchPartyDirectoryProvider =
    NotifierProvider<WatchPartyDirectory, List<GroupInfo>>(
        WatchPartyDirectory.new);
