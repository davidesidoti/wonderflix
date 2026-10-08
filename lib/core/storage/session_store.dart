import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({required this.userId, required this.accessToken});

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
        userId: json['userId'] as String,
        accessToken: json['accessToken'] as String,
      );

  final String userId;
  final String accessToken;

  Map<String, dynamic> toJson() => {'userId': userId, 'accessToken': accessToken};
}

abstract interface class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// La sessione unica delle versioni prima della 0.11.0, in
/// `flutter_secure_storage` (su Windows un file JSON cifrato con DPAPI). Dalla
/// 0.11.0 serve solo alla migrazione nei profili (`SecureProfileStore`).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage, String? storageKey])
      : _storage = storage ?? const FlutterSecureStorage(),
        storageKey = storageKey ?? key;

  static const key = 'wonderflix.session';

  final FlutterSecureStorage _storage;

  /// Chiave usata da questa istanza (diversa per un profilo di sviluppo).
  final String storageKey;

  @override
  Future<StoredSession?> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: storageKey);
    } on Object {
      try {
        await clear();
      } on Object {
        // Ignora: la lettura era già fallita.
      }
      return null;
    }
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: storageKey, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}
