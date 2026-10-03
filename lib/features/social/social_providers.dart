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

/// Chiede `Info` al plugin dopo il login e a ogni connessione del WebSocket,
/// anche la prima (spec F §7.2): se il controllo del login è fallito, quando
/// il WebSocket si connette il server è raggiungibile e ha una seconda
/// possibilità. Senza utente, senza accesso ai watch party o senza plugin:
/// nessuna funzione, e l'app si comporta come la 0.5.1.
class SocialAvailability extends Notifier<SocialFeatures> {
  /// Cresce a ogni cambio di utente (`build`) e a ogni controllo: vale solo
  /// il risultato dell'ultimo, uno più lento di un logout o di un altro
  /// utente si scarta.
  int _checks = 0;

  @override
  SocialFeatures build() {
    _checks++;
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null || !ref.watch(syncPlayAccessProvider).canJoin) {
      return SocialFeatures.none;
    }
    final subscription = ref.watch(watchPartyEventsProvider).listen((event) {
      if (event is ServerConnected) unawaited(refresh());
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    // Se prima del microtask il provider si ricostruisce (altro utente),
    // questo controllo non parte: ci pensa la nuova `build`.
    final built = _checks;
    unawaited(Future.microtask(() {
      if (built == _checks) unawaited(refresh());
    }));
    return SocialFeatures.none;
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final check = ++_checks;
    try {
      final info = await ref.read(socialApiProvider).info();
      if (!ref.mounted || check != _checks) return;
      state = SocialFeatures(
        friends: info.features.contains(PluginFeatures.friends),
        parties: info.features.contains(PluginFeatures.parties),
      );
    } on SocialException catch (error) {
      // Plugin assente, vecchio o senza permesso: niente funzioni. Un
      // errore di rete lascia quelle che c'erano.
      if (ref.mounted &&
          check == _checks &&
          error.failure != SocialFailure.network) {
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
