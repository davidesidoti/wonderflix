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
    this.inbox = false,
    this.requests = false,
    this.collections = false,
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

  /// La cassetta delle notifiche (spec G): c'è anche per chi non ha accesso
  /// ai watch party.
  final bool inbox;

  /// Le richieste con Seerr (spec I §8.2): non dipendono dai watch party.
  final bool requests;

  /// Le saghe (spec K §8.1): non dipendono dai watch party.
  final bool collections;

  /// `false` finché `Info` non dà una risposta certa: le funzioni, oppure
  /// un 400/401/403/404. Un errore di rete non basta (vedi
  /// [SocialAvailability]).
  final bool known;

  @override
  bool operator ==(Object other) =>
      other is SocialFeatures &&
      other.friends == friends &&
      other.parties == parties &&
      other.inbox == inbox &&
      other.requests == requests &&
      other.collections == collections &&
      other.known == known;

  @override
  int get hashCode =>
      Object.hash(friends, parties, inbox, requests, collections, known);

  @override
  String toString() => 'SocialFeatures(friends: $friends, parties: $parties, '
      'inbox: $inbox, requests: $requests, collections: $collections, '
      'known: $known)';
}

/// Chiede `Info` al plugin dopo il login e a ogni connessione del WebSocket,
/// anche la prima (spec F §7.2): se il controllo del login è fallito, quando
/// il WebSocket si connette il server è raggiungibile e ha una seconda
/// possibilità. Senza utente o senza plugin: nessuna funzione, e l'app si
/// comporta come la 0.5.1. Senza accesso ai watch party `Info` si chiede lo
/// stesso (la cassetta delle notifiche vale per tutti, spec G §7.2, e così le
/// richieste con Seerr, spec I §8.2, e le saghe, spec K §8.1), ma amici e
/// party restano spenti. Dal login alla prima risposta certa le funzioni sono
/// [SocialFeatures.unknown].
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

  /// L'utente può entrare nei watch party: senza, amici e party restano
  /// spenti anche se il plugin li ha.
  bool _canJoin = false;

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
    if (userId == null) {
      _canJoin = false;
      return SocialFeatures.none;
    }
    _canJoin = ref.watch(syncPlayAccessProvider.select((a) => a.canJoin));
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
        friends: _canJoin && info.features.contains(PluginFeatures.friends),
        parties: _canJoin && info.features.contains(PluginFeatures.parties),
        inbox: info.features.contains(PluginFeatures.inbox),
        requests: info.features.contains(PluginFeatures.requests),
        collections: info.features.contains(PluginFeatures.collections),
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

  /// Le funzioni appena sono note, aspettando al massimo [timeout]: subito
  /// se lo sono già; scaduto il tempo, quelle di quel momento (non note).
  /// Un cambio di utente o la chiusura del provider finiscono l'attesa con
  /// [SocialFeatures.unknown].
  Future<SocialFeatures> whenKnown(Duration timeout) {
    if (state.known) return Future.value(state);
    final known = Completer<SocialFeatures>();
    final timer = Timer(timeout, () {
      if (!known.isCompleted) known.complete(state);
    });
    final removeListener = listenSelf((_, next) {
      if (next.known && !known.isCompleted) known.complete(next);
    });
    final removeDispose = ref.onDispose(() {
      if (!known.isCompleted) known.complete(SocialFeatures.unknown);
    });
    return known.future.whenComplete(() {
      timer.cancel();
      removeListener();
      removeDispose();
    });
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
