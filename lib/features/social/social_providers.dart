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
  const SocialFeatures({
    this.friends = false,
    this.parties = false,
    this.known = true,
  });

  /// Plugin assente o senza funzioni (già verificato).
  static const none = SocialFeatures();

  /// Dopo il login, finché `Info` non ha risposto: non si sa ancora se
  /// l'elenco dei party va chiesto al plugin o a Jellyfin. Chi mostra i
  /// party aspetta, perché `/SyncPlay/List` non è filtrato per modalità.
  static const unknown = SocialFeatures(known: false);

  final bool friends;
  final bool parties;

  /// `false` finché `Info` non dà una risposta certa: le funzioni, oppure
  /// un 400/401/403/404. Un errore di rete non basta (vedi
  /// [SocialAvailability]).
  final bool known;

  @override
  bool operator ==(Object other) =>
      other is SocialFeatures &&
      other.friends == friends &&
      other.parties == parties &&
      other.known == known;

  @override
  int get hashCode => Object.hash(friends, parties, known);

  @override
  String toString() =>
      'SocialFeatures(friends: $friends, parties: $parties, known: $known)';
}

/// Chiede `Info` al plugin dopo il login e a ogni connessione del WebSocket,
/// anche la prima (spec F §7.2): se il controllo del login è fallito, quando
/// il WebSocket si connette il server è raggiungibile e ha una seconda
/// possibilità. Senza utente, senza accesso ai watch party o senza plugin:
/// nessuna funzione, e l'app si comporta come la 0.5.1. Dal login alla prima
/// risposta certa le funzioni sono [SocialFeatures.unknown].
///
/// Un errore di rete (anche timeout, errore del server, risposta di forma
/// inattesa, troppe richieste) non dice nulla del plugin: le funzioni
/// restano come sono. Se non sono ancora note restano non note, e i party
/// nascosti, perché l'elenco di Jellyfin non è filtrato per modalità; si
/// riprova dopo [retryDelay] e a ogni connessione del WebSocket.
class SocialAvailability extends Notifier<SocialFeatures> {
  /// Attesa prima di richiedere `Info` dopo un errore di rete, finché le
  /// funzioni non sono note: intanto i party restano nascosti, quindi non
  /// si aspetta la prossima riconnessione del WebSocket (che può non
  /// arrivare per ore). Come l'intervallo dell'elenco dei party, così il
  /// server non riceve più richieste del solito.
  static const retryDelay = Duration(seconds: 30);

  /// Cresce a ogni cambio di utente (`build`): il risultato di un
  /// controllo partito per un utente precedente (o prima di un logout) si
  /// scarta.
  int _generation = 0;

  /// Numera i controlli in ordine di partenza.
  int _checks = 0;

  /// Il controllo la cui risposta riuscita vale ora, per l'utente di
  /// adesso; `null` se nessuna. Una risposta riuscita di un controllo
  /// partito prima la scarta (vale la più recente); un errore no.
  int? _success;

  /// Quanti controlli erano partiti quando è arrivata la risposta riuscita
  /// di [_success]: quelli fino a lì erano in corso insieme a lei (al login
  /// partono insieme il primo controllo e quello della connessione del
  /// WebSocket), e un loro errore non la scarta.
  int _startedBeforeSuccess = 0;

  Timer? _retry;

  @override
  SocialFeatures build() {
    _generation++;
    _success = null;
    _startedBeforeSuccess = 0;
    // Utente nuovo, logout o provider chiuso: niente tentativi in sospeso.
    _stopRetry();
    ref.onDispose(_stopRetry);
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
    final generation = _generation;
    unawaited(Future.microtask(() {
      if (generation == _generation) unawaited(refresh());
    }));
    return SocialFeatures.unknown;
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = _generation;
    final check = ++_checks;
    try {
      final info = await ref.read(socialApiProvider).info();
      if (!_isCurrent(generation)) return;
      final success = _success;
      if (success != null && success > check) return;
      _success = check;
      _startedBeforeSuccess = _checks;
      _apply(SocialFeatures(
        friends: info.features.contains(PluginFeatures.friends),
        parties: info.features.contains(PluginFeatures.parties),
      ));
    } on SocialException catch (error) {
      if (!_isCurrent(generation)) return;
      switch (error.failure) {
        case SocialFailure.unavailable || SocialFailure.forbidden:
          // 404: plugin assente o vecchio; 400/401/403: problema della
          // sessione. Risposta certa, niente funzioni; ma non scarta una
          // risposta riuscita arrivata mentre questo controllo era in corso.
          // Vale invece se il controllo è partito dopo (es. plugin tolto e
          // server riavviato: lo dice la riconnessione).
          if (_success == null || check > _startedBeforeSuccess) {
            _apply(SocialFeatures.none);
          }
        case SocialFailure.network ||
              SocialFailure.conflict ||
              SocialFailure.rateLimited:
          // Non dice nulla del plugin: si tiene quel che c'è.
          if (!state.known) _scheduleRetry();
      }
    } on Object catch (error) {
      // Un errore che non viene dal plugin, di solito un provider che non si
      // può creare (es. nei test senza plugin finto): non passa riprovando.
      // Vale come plugin assente, altrimenti le funzioni non sarebbero mai
      // note (e nei test i tentativi resterebbero in sospeso).
      _log.info('funzioni del plugin non verificate: ${error.runtimeType}');
      if (_isCurrent(generation) && !state.known) _apply(SocialFeatures.none);
    }
  }

  bool _isCurrent(int generation) =>
      ref.mounted && generation == _generation;

  void _apply(SocialFeatures features) {
    _stopRetry();
    state = features;
  }

  void _scheduleRetry() {
    if (_retry != null) return;
    _retry = Timer(retryDelay, () {
      _retry = null;
      if (ref.mounted && !state.known) unawaited(refresh());
    });
  }

  void _stopRetry() {
    _retry?.cancel();
    _retry = null;
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
