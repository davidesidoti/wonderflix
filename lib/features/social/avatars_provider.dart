import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/avatars_api.dart';
import '../auth/profiles_state.dart';
import 'social_providers.dart';

final _log = Logger('avatars');

/// Chi cercare (spec K §10.5): per id, o per nome quando c'è solo quello (i
/// membri del party: SyncPlay dà solo i nomi). Come chiave della cache, id
/// senza trattini e nomi in minuscolo.
class AvatarLookup {
  AvatarLookup.byId(String userId)
      : userId = jellyfinIdKey(userId),
        name = null,
        query = null;

  AvatarLookup.byName(String name)
      : userId = null,
        name = name.toLowerCase(),
        query = name;

  final String? userId;
  final String? name;

  /// Il nome com'è scritto, da mandare al plugin (fuori da `==`): il plugin
  /// lo confronta senza maiuscole a modo suo (.NET `OrdinalIgnoreCase`), e su
  /// qualche lettera (İ, il segno del kelvin, ẞ) `toLowerCase` di Dart non
  /// è d'accordo.
  final String? query;

  /// Con l'id vuoto, o senza id e con il nome vuoto: nessuno da cercare.
  bool get _isEmpty => (userId?.isEmpty ?? true) && (name?.isEmpty ?? true);

  @override
  bool operator ==(Object other) =>
      other is AvatarLookup && other.userId == userId && other.name == name;

  @override
  int get hashCode => Object.hash(userId, name);

  @override
  String toString() =>
      userId != null ? 'AvatarLookup(id: $userId)' : 'AvatarLookup(name: $name)';
}

/// L'immagine di un utente: il suo id (anche cercandolo per nome) e il tag.
class AvatarImage {
  const AvatarImage(this.userId, this.tag);

  final String userId;
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is AvatarImage && other.userId == userId && other.tag == tag;

  @override
  int get hashCode => Object.hash(userId, tag);

  @override
  String toString() => 'AvatarImage($userId, $tag)';
}

/// I tag delle immagini degli altri utenti, chiesti al plugin (spec K §10.5).
///
/// - Le richieste dei widget si raccolgono per [batchDelay] e partono in una
///   sola chiamata, con al massimo [AvatarsApi.maxEntries] voci (le altre in
///   una chiamata subito dopo).
/// - Una richiesta già partita non ne fa un'altra: si aspetta la sua risposta.
/// - Un risultato vale [ttl]; anche un errore, che lascia le iniziali: si
///   riprova dopo [ttl].
/// - Un utente trovato vale per id e per nome.
class AvatarDirectory {
  AvatarDirectory(this._api,
      {this.batchDelay = defaultBatchDelay, this.ttl = defaultTtl});

  /// Quanto si aspettano altre richieste prima di chiamare il plugin.
  static const defaultBatchDelay = Duration(milliseconds: 50);

  /// Quanto vale un risultato.
  static const defaultTtl = Duration(minutes: 10);

  final AvatarsApi _api;
  final Duration batchDelay;
  final Duration ttl;

  final _cache = <AvatarLookup, _Cached>{};
  final _waiting = <AvatarLookup, Completer<AvatarImage?>>{};

  /// Le richieste già partite, finché il plugin non risponde.
  final _inFlight = <AvatarLookup, Completer<AvatarImage?>>{};
  Timer? _timer;
  bool _disposed = false;

  /// L'immagine di [lookup]; `null` senza immagine, per un utente che non
  /// c'è o dopo un errore: si mostra l'iniziale.
  Future<AvatarImage?> imageFor(AvatarLookup lookup) {
    if (_disposed || lookup._isEmpty) return Future.value(null);
    final cached = _cache[lookup];
    if (cached != null && clock.now().difference(cached.at) < ttl) {
      return Future.value(cached.image);
    }
    final pending = _waiting[lookup] ?? _inFlight[lookup];
    if (pending != null) return pending.future;
    final completer = Completer<AvatarImage?>();
    _waiting[lookup] = completer;
    _timer ??= Timer(batchDelay, _flush);
    return completer.future;
  }

  /// Un'immagine appena cambiata (spec K §10.4): vale subito, per id e per
  /// nome (non per il nome vuoto). Una risposta del plugin già in viaggio
  /// non la sovrascrive.
  void remember(
      {required String userId, required String name, required String? tag}) {
    final entry = _Cached(
        tag == null ? null : AvatarImage(jellyfinIdKey(userId), tag),
        clock.now(),
        remembered: true);
    _cache[AvatarLookup.byId(userId)] = entry;
    if (name.isNotEmpty) _cache[AvatarLookup.byName(name)] = entry;
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = _waiting.keys.take(AvatarsApi.maxEntries).toList();
    final completers = [for (final key in batch) _waiting.remove(key)!];
    for (var i = 0; i < batch.length; i++) {
      _inFlight[batch[i]] = completers[i];
    }
    // Oltre il limite: un'altra chiamata, subito.
    if (_waiting.isNotEmpty) _timer = Timer(Duration.zero, _flush);
    // Quello che entra nella cache da qui in poi può valere più della
    // risposta (vedi sotto).
    final started = clock.now();
    final found = <AvatarLookup, AvatarImage?>{};
    try {
      final users = await _api.avatars(
        ids: [for (final key in batch) ?key.userId],
        names: [for (final key in batch) ?key.query],
      );
      for (final user in users) {
        final tag = user.imageTag;
        final image = tag == null ? null : AvatarImage(user.userId, tag);
        found[AvatarLookup.byId(user.userId)] = image;
        // Un utente senza nome non vale per il nome vuoto.
        if (user.name.isNotEmpty) found[AvatarLookup.byName(user.name)] = image;
      }
    } on Object catch (error) {
      final message = 'immagini degli utenti non lette: ${error.runtimeType}';
      if (error is ApiException) {
        _log.info(message);
      } else {
        _log.warning(message);
      }
    }
    // Dopo dispose le richieste sono già finite con l'iniziale.
    if (_disposed) return;
    for (final key in batch) {
      _inFlight.remove(key);
      // Chiesto e non trovato: l'iniziale.
      found.putIfAbsent(key, () => null);
    }
    final now = clock.now();
    for (final MapEntry(:key, :value) in found.entries) {
      final cached = _cache[key];
      // Entrati dopo la partenza, un'immagine appena cambiata (remember) o
      // un'immagine trovata da un'altra chiamata valgono più della risposta.
      // Un errore o un "senza immagine" di un'altra chiamata no: una
      // chiamata fallita nel frattempo non copre questa.
      if (cached != null &&
          !cached.at.isBefore(started) &&
          (cached.remembered || cached.image != null)) {
        continue;
      }
      _cache[key] = _Cached(value, now);
    }
    for (var i = 0; i < batch.length; i++) {
      completers[i].complete(_cache[batch[i]]?.image);
    }
  }

  /// Le richieste in attesa, e quelle già partite, finiscono con l'iniziale.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final completer in [..._waiting.values, ..._inFlight.values]) {
      completer.complete(null);
    }
    _waiting.clear();
    _inFlight.clear();
  }
}

class _Cached {
  const _Cached(this.image, this.at, {this.remembered = false});

  final AvatarImage? image;
  final DateTime at;

  /// Scritto da [AvatarDirectory.remember]: un'immagine appena cambiata.
  final bool remembered;
}

final avatarsApiProvider =
    Provider<AvatarsApi>((ref) => AvatarsApi(ref.watch(jellyfinHttpProvider)));

/// La cache degli avatar del profilo aperto (spec K §10.5). `null` senza un
/// profilo aperto o senza la funzione `avatars` del plugin: nessuna
/// chiamata, solo iniziali. Un altro profilo ha una cache nuova.
final avatarDirectoryProvider = Provider<AvatarDirectory?>((ref) {
  // Prima i profili, che non dipendono dal client HTTP: senza un profilo
  // aperto la sessione non si crea (nei widget test senza sessione
  // lancerebbe).
  final userId = ref
      .watch(profilesProvider.select((profiles) => profiles.activeUserId));
  if (userId == null) return null;
  final available = ref.watch(
      socialAvailabilityProvider.select((features) => features.avatars));
  if (!available) return null;
  final directory = AvatarDirectory(ref.watch(avatarsApiProvider));
  ref.onDispose(directory.dispose);
  return directory;
});

/// L'immagine di un utente (spec K §10.5); `null`: l'iniziale.
final avatarImageProvider = FutureProvider.autoDispose
    .family<AvatarImage?, AvatarLookup>((ref, lookup) async {
  final directory = ref.watch(avatarDirectoryProvider);
  if (directory == null) return null;
  final image = await directory.imageFor(lookup);
  if (!ref.mounted) return image;
  // Un risultato vale [AvatarDirectory.ttl]: poi, finché è sullo schermo, si
  // rilegge (spec K §10.5: dopo un errore si riprova dopo 10 minuti). Il
  // timer parte dalla risposta, così alla rilettura la cache è scaduta.
  final expiry = Timer(directory.ttl, ref.invalidateSelf);
  ref.onDispose(expiry.cancel);
  return image;
});
