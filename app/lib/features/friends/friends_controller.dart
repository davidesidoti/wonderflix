import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';

final _log = Logger('social');

/// Amici e richieste dell'utente (spec F §8.1).
class FriendsState {
  const FriendsState({
    this.snapshot = FriendsSnapshot.empty,
    this.loaded = false,
    this.failed = false,
  });

  final FriendsSnapshot snapshot;

  /// Almeno un caricamento è riuscito.
  final bool loaded;

  /// L'ultimo caricamento non è riuscito (resta l'elenco di prima).
  final bool failed;

  /// Richieste in arrivo: il numero sull'icona Amici.
  int get incomingCount => snapshot.incoming.length;
}

/// Legge amici e richieste dal plugin: alla nascita, a ogni avviso
/// `FriendRequest`/`FriendsChanged`, a ogni riconnessione del WebSocket e
/// dopo ogni azione. Niente controlli periodici.
class FriendsController extends Notifier<FriendsState> {
  /// Cresce a ogni caricamento: vale solo la risposta dell'ultimo.
  int _loads = 0;

  @override
  FriendsState build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _loads++;
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.friends))) {
      return const FriendsState();
    }
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is FriendRequestEvent || event is FriendsChangedEvent) {
        unawaited(reload());
      }
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      // Gli avvisi persi mentre il WebSocket era giù.
      if (event is ServerConnected && event.isReconnect) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    unawaited(Future.microtask(reload));
    return const FriendsState();
  }

  /// Rilegge amici e richieste dal plugin.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(socialAvailabilityProvider).friends) return;
    final load = ++_loads;
    try {
      final snapshot = await ref.read(socialApiProvider).friends();
      if (!ref.mounted || load != _loads) return;
      state = FriendsState(snapshot: snapshot, loaded: true);
    } on Object catch (error) {
      _log.info('amici non caricati: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
      if (!ref.mounted || load != _loads) return;
      state = FriendsState(
          snapshot: state.snapshot, loaded: state.loaded, failed: true);
    }
  }

  Future<SocialFailure?> request(String userId) =>
      _act((api) => api.request(userId));

  Future<SocialFailure?> accept(String userId) =>
      _act((api) => api.accept(userId));

  Future<SocialFailure?> decline(String userId) =>
      _act((api) => api.decline(userId));

  Future<SocialFailure?> cancel(String userId) =>
      _act((api) => api.cancel(userId));

  Future<SocialFailure?> remove(String userId) =>
      _act((api) => api.remove(userId));

  /// Esegue un'azione e rilegge, anche se non è riuscita (nel frattempo
  /// lo stato può essere cambiato). `null` se è riuscita.
  Future<SocialFailure?> _act(Future<void> Function(SocialApi api) action) async {
    SocialFailure? failure;
    try {
      await action(ref.read(socialApiProvider));
    } on SocialException catch (error) {
      failure = error.failure;
    } on Object catch (error) {
      _log.info('azione sugli amici non riuscita: ${error.runtimeType}');
      failure = SocialFailure.network;
    }
    if (ref.mounted) unawaited(reload());
    return failure;
  }
}

final friendsControllerProvider =
    NotifierProvider<FriendsController, FriendsState>(FriendsController.new);
