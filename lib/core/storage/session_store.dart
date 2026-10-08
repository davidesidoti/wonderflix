import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// La sessione unica delle versioni prima della 0.11.0.
class StoredSession {
  const StoredSession({required this.userId, required this.accessToken});

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
        userId: json['userId'] as String,
        accessToken: json['accessToken'] as String,
      );

  final String userId;
  final String accessToken;
}

/// Lettore della sessione unica delle versioni prima della 0.11.0, in
/// `flutter_secure_storage` (su Windows un file JSON cifrato con DPAPI).
/// Esiste solo per la migrazione 0.10 → 0.11 nei profili
/// (`SecureProfileStore`): si legge una volta e si cancella.
class SecureSessionStore {
  SecureSessionStore([FlutterSecureStorage? storage, String? storageKey])
      : _storage = storage ?? const FlutterSecureStorage(),
        storageKey = storageKey ?? key;

  static const key = 'wonderflix.session';

  final FlutterSecureStorage _storage;

  /// Chiave usata da questa istanza (diversa per un profilo di sviluppo).
  final String storageKey;

  /// `null` se non c'è. Un valore rovinato si cancella e dà `null`. Uno
  /// storage che non si legge lancia: la sessione può esserci ancora, e non
  /// si cancella.
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      try {
        await clear();
      } on Object {
        // Ignora: il valore era comunque inservibile.
      }
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: storageKey);
}
