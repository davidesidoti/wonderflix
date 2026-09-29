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

/// Salva la sessione nel Gestore credenziali di Windows.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'wonderflix.session';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: key);
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
      _storage.write(key: key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: key);
}
