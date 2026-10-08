import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import '../jellyfin/json_fields.dart';
import 'session_store.dart';

final _log = Logger('profiles');

const Object _keep = Object();

bool _sameUser(String a, String b) => jellyfinIdKey(a) == jellyfinIdKey(b);

/// Un profilo salvato su questo PC (spec K §9.1): un account Jellyfin con il
/// suo token e il suo DeviceId.
class StoredProfile {
  const StoredProfile({
    required this.userId,
    required this.name,
    required this.accessToken,
    required this.deviceId,
    this.imageTag,
    this.lastUsedAt,
    this.expired = false,
  });

  /// `null` senza id, token o DeviceId: il profilo non si può usare.
  static StoredProfile? fromJson(Map<String, dynamic> json) {
    final userId = jsonString(json, 'userId');
    final accessToken = jsonString(json, 'accessToken');
    final deviceId = jsonString(json, 'deviceId');
    if (userId == null || accessToken == null || deviceId == null) return null;
    return StoredProfile(
      userId: userId,
      name: jsonString(json, 'name') ?? '',
      accessToken: accessToken,
      deviceId: deviceId,
      imageTag: jsonString(json, 'imageTag'),
      lastUsedAt: jsonDate(json, 'lastUsedAt'),
      expired: json['expired'] == true,
    );
  }

  final String userId;

  /// Nome dell'utente Jellyfin; vuoto finché non si legge (profilo migrato).
  final String name;
  final String accessToken;

  /// Il DeviceId con cui si è ottenuto il token.
  final String deviceId;

  /// Tag dell'immagine dell'utente (spec K §10); `null` senza immagine.
  final String? imageTag;
  final DateTime? lastUsedAt;

  /// Il server ha rifiutato il token (401): serve un nuovo accesso.
  final bool expired;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'accessToken': accessToken,
        'deviceId': deviceId,
        'imageTag': ?imageTag,
        'lastUsedAt': ?lastUsedAt?.toUtc().toIso8601String(),
        if (expired) 'expired': true,
      };

  StoredProfile copyWith({
    String? name,
    String? accessToken,
    String? deviceId,
    Object? imageTag = _keep,
    DateTime? lastUsedAt,
    bool? expired,
  }) =>
      StoredProfile(
        userId: userId,
        name: name ?? this.name,
        accessToken: accessToken ?? this.accessToken,
        deviceId: deviceId ?? this.deviceId,
        imageTag: identical(imageTag, _keep) ? this.imageTag : imageTag as String?,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        expired: expired ?? this.expired,
      );
}

/// I profili salvati su questo PC e l'ultimo usato (spec K §9.1). Immutabile:
/// ogni modifica dà un elenco nuovo.
class ProfileBook {
  const ProfileBook({this.profiles = const [], this.lastUserId});

  /// Profili al massimo su un PC (spec K §4).
  static const maxProfiles = 5;

  /// Versione del formato salvato.
  static const _version = 1;

  /// Tollerante: salta i profili senza id, token o DeviceId e i doppioni, ne
  /// tiene al massimo [maxProfiles]; un ultimo usato che non c'è più non vale.
  factory ProfileBook.fromJson(Map<String, dynamic> json) {
    final profiles = <StoredProfile>[];
    final list = json['profiles'];
    for (final raw in list is List ? list : const []) {
      final map = jsonMap(raw);
      final profile = map == null ? null : StoredProfile.fromJson(map);
      if (profile == null ||
          profiles.any((p) => _sameUser(p.userId, profile.userId))) {
        continue;
      }
      if (profiles.length < maxProfiles) profiles.add(profile);
    }
    final last = jsonString(json, 'lastUserId');
    return ProfileBook(
      profiles: List.unmodifiable(profiles),
      lastUserId: last != null && profiles.any((p) => _sameUser(p.userId, last))
          ? last
          : null,
    );
  }

  /// Nell'ordine in cui sono stati aggiunti.
  final List<StoredProfile> profiles;

  /// L'ultimo profilo aperto (la lingua di "Chi guarda?", spec K §9.4).
  final String? lastUserId;

  bool get isEmpty => profiles.isEmpty;

  /// Nessun profilo in più: "Aggiungi profilo" non c'è.
  bool get isFull => profiles.length >= maxProfiles;

  StoredProfile? byId(String userId) {
    for (final profile in profiles) {
      if (_sameUser(profile.userId, userId)) return profile;
    }
    return null;
  }

  /// [profile] al posto di quello dello stesso utente, o in fondo.
  ProfileBook upsert(StoredProfile profile) {
    final next = profiles.toList();
    final index = next.indexWhere((p) => _sameUser(p.userId, profile.userId));
    // Un utente nuovo in un elenco pieno non deve arrivare qui: chi chiama
    // (`AuthService`) controlla prima `isFull`.
    assert(!isFull || index >= 0, 'elenco dei profili pieno: utente nuovo');
    if (index >= 0) {
      next[index] = profile;
    } else {
      next.add(profile);
    }
    return ProfileBook(profiles: List.unmodifiable(next), lastUserId: lastUserId);
  }

  ProfileBook remove(String userId) => ProfileBook(
        profiles: List.unmodifiable(
            profiles.where((p) => !_sameUser(p.userId, userId))),
        lastUserId: lastUserId != null && _sameUser(lastUserId!, userId)
            ? null
            : lastUserId,
      );

  ProfileBook withLast(String userId) =>
      ProfileBook(profiles: profiles, lastUserId: userId);

  Map<String, dynamic> toJson() => {
        'version': _version,
        'profiles': [for (final profile in profiles) profile.toJson()],
        'lastUserId': ?lastUserId,
      };
}

/// Un profilo in più del massimo (spec K §4).
class ProfileLimitException implements Exception {
  const ProfileLimitException();

  @override
  String toString() => 'ProfileLimitException';
}

/// Dove stanno i profili (spec K §9.1).
abstract interface class ProfileStore {
  /// I profili salvati; vuoto se non ce ne sono o se non si leggono. Non
  /// lancia mai. La prima lettura porta nei profili la sessione unica di prima
  /// della 0.11.0, se c'è (vedi [SecureProfileStore]).
  Future<ProfileBook> read();

  /// Salva [book] e dà l'elenco salvato davvero: dopo una lettura non
  /// riuscita ci sono anche i profili che lo storage aveva (vedi
  /// [SecureProfileStore]). Lancia se non si può salvare senza perderne.
  Future<ProfileBook> write(ProfileBook book);
}

/// I profili in `flutter_secure_storage`: su Windows un file JSON cifrato con
/// DPAPI (`flutter_secure_storage.dat` nella cartella dei dati dell'app). Una
/// lettura non riuscita non fa perdere i profili salvati (vedi [write]).
class SecureProfileStore implements ProfileStore {
  SecureProfileStore({
    FlutterSecureStorage? storage,
    this.key = defaultKey,
    this.legacyKey = SecureSessionStore.key,
    required this.legacyDeviceId,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultKey = 'wonderflix.profiles';

  final FlutterSecureStorage _storage;
  final String key;

  /// La sessione unica delle versioni prima della 0.11.0.
  final String legacyKey;

  /// Il DeviceId di quella sessione (`device_id` delle preferenze, o quello
  /// dell'istanza di sviluppo).
  final String legacyDeviceId;

  /// L'ultima lettura non è riuscita (per esempio il file bloccato
  /// all'avvio): i profili salvati possono esserci ancora, e un salvataggio
  /// non deve sovrascriverli alla cieca.
  bool _readFailed = false;

  @override
  Future<ProfileBook> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: key);
    } on Object catch (error) {
      _readFailed = true;
      _log.warning('profili non letti: ${error.runtimeType}');
      return const ProfileBook();
    }
    _readFailed = false;
    if (raw == null) return _migrate();
    try {
      return ProfileBook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      // Come una sessione illeggibile: si rifà l'accesso (spec K §9.1).
      _log.warning('profili illeggibili: ${error.runtimeType}');
      return const ProfileBook();
    }
  }

  /// Prima della 0.11.0 c'era una sessione sola: diventa il primo profilo,
  /// con il DeviceId di allora, così il token resta valido (spec K §9.1).
  Future<ProfileBook> _migrate() async {
    final legacy = SecureSessionStore(_storage, legacyKey);
    final StoredSession? session;
    try {
      session = await legacy.read();
    } on Object catch (error) {
      // `read()` cancella un valore rovinato: se anche questo fallisce, si
      // riparte senza profili.
      _log.warning('sessione di prima non letta: ${error.runtimeType}');
      return const ProfileBook();
    }
    if (session == null) return const ProfileBook();
    final book = ProfileBook(
      profiles: List.unmodifiable([
        StoredProfile(
          userId: session.userId,
          name: '',
          accessToken: session.accessToken,
          deviceId: legacyDeviceId,
        ),
      ]),
      lastUserId: session.userId,
    );
    try {
      await write(book);
    } on Object catch (error) {
      // La sessione di prima resta: se nessun salvataggio riesce, si riprova
      // al prossimo avvio.
      _log.warning('profili non salvati: ${error.runtimeType}');
      return book;
    }
    try {
      await legacy.clear();
    } on Object catch (error) {
      // I profili ci sono già: la sessione di prima resta, ma non serve più
      // (con i profili salvati la lettura non migra).
      _log.warning('sessione di prima non cancellata: ${error.runtimeType}');
    }
    _log.info('sessione di prima portata nei profili');
    return book;
  }

  /// Solo dati rovinati si sovrascrivono. Dopo una lettura non riuscita si
  /// rilegge prima: se non riesce ancora non si salva (lancia), altrimenti si
  /// tengono anche i profili salvati che [book] non ha.
  @override
  Future<ProfileBook> write(ProfileBook book) async {
    var toWrite = book;
    if (_readFailed) {
      final stored = await read();
      if (_readFailed) {
        throw StateError('profili non riletti: non si sovrascrivono');
      }
      toWrite = _withStored(book, stored);
    }
    await _storage.write(key: key, value: jsonEncode(toWrite.toJson()));
    return toWrite;
  }

  /// [book] con davanti i profili di [stored] che non ha, finché c'è posto
  /// (al massimo [ProfileBook.maxProfiles]): quelli di [book] restano tutti
  /// e vincono, e vale il suo ultimo usato.
  static ProfileBook _withStored(ProfileBook book, ProfileBook stored) {
    final room = ProfileBook.maxProfiles - book.profiles.length;
    final recovered = [
      for (final profile in stored.profiles)
        if (book.byId(profile.userId) == null) profile,
    ].take(room < 0 ? 0 : room).toList();
    if (recovered.isEmpty) return book;
    _log.info('profili recuperati dopo una lettura non riuscita: '
        '${recovered.length}');
    return ProfileBook(
      profiles: List.unmodifiable([...recovered, ...book.profiles]),
      lastUserId: book.lastUserId,
    );
  }
}
