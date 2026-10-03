import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../watch_party/watch_party_providers.dart';

final _log = Logger('social');

final socialApiProvider =
    Provider<SocialApi>((ref) => SocialApi(ref.watch(jellyfinHttpProvider)));

/// Funzioni del plugin che l'app può usare (spec F §7.2).
class SocialFeatures {
  const SocialFeatures({this.friends = false, this.parties = false});

  static const none = SocialFeatures();

  final bool friends;
  final bool parties;

  @override
  bool operator ==(Object other) =>
      other is SocialFeatures &&
      other.friends == friends &&
      other.parties == parties;

  @override
  int get hashCode => Object.hash(friends, parties);

  @override
  String toString() => 'SocialFeatures(friends: $friends, parties: $parties)';
}

/// Chiede `Info` al plugin dopo il login e a ogni riconnessione del
/// WebSocket (spec F §7.2). Senza utente, senza accesso ai watch party o
/// senza plugin: nessuna funzione, e l'app si comporta come la 0.5.1.
class SocialAvailability extends Notifier<SocialFeatures> {
  @override
  SocialFeatures build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null || !ref.watch(syncPlayAccessProvider).canJoin) {
      return SocialFeatures.none;
    }
    final subscription = ref.watch(watchPartyEventsProvider).listen((event) {
      if (event is ServerConnected && event.isReconnect) unawaited(refresh());
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    unawaited(Future.microtask(refresh));
    return SocialFeatures.none;
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    try {
      final info = await ref.read(socialApiProvider).info();
      if (!ref.mounted) return;
      state = SocialFeatures(
        friends: info.features.contains(PluginFeatures.friends),
        parties: info.features.contains(PluginFeatures.parties),
      );
    } on SocialException catch (error) {
      // Plugin assente, vecchio o senza permesso: niente funzioni. Un
      // errore di rete lascia quelle che c'erano.
      if (ref.mounted && error.failure != SocialFailure.network) {
        state = SocialFeatures.none;
      }
    } on Object catch (error) {
      // Anche un provider che non si può creare (es. nei test).
      _log.info('funzioni del plugin non verificate: ${error.runtimeType}');
    }
  }
}

final socialAvailabilityProvider =
    NotifierProvider<SocialAvailability, SocialFeatures>(
        SocialAvailability.new);

/// Avvisi del plugin fuori dal canale di un gruppo (spec F §7.3).
final socialEventsProvider = Provider<Stream<SocialEvent>>((ref) => ref
    .watch(watchPartyEventsProvider)
    .map((event) =>
        event is PartyChannelReceived ? parseSocialEvent(event.payload) : null)
    .where((event) => event != null)
    .cast<SocialEvent>());
