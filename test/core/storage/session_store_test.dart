import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/storage/session_store.dart';

import '../../support/throwing_secure_storage.dart';

/// La sessione di prima della 0.11.0 come la scriveva la 0.10.
String legacySession(String userId, String token) =>
    jsonEncode({'userId': userId, 'accessToken': token});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('legge e cancella la sessione di prima', () async {
    final store = SecureSessionStore();
    expect(await store.read(), isNull);

    FlutterSecureStorage.setMockInitialValues(
        {SecureSessionStore.key: legacySession('u1', 'tok')});
    final read = await store.read();
    expect(read?.userId, 'u1');
    expect(read?.accessToken, 'tok');

    await store.clear();
    expect(await store.read(), isNull);
  });

  test('un valore corrotto viene scartato e cancellato', () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureSessionStore.key: 'non-json'});
    final store = SecureSessionStore();
    expect(await store.read(), isNull);
    expect(await const FlutterSecureStorage().read(key: SecureSessionStore.key),
        isNull);
  });

  test('uno storage che fallisce in lettura lancia, e la sessione resta',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureSessionStore.key: legacySession('u1', 'tok')});
    final store = SecureSessionStore(const ThrowingReadStorage());

    await expectLater(store.read(), throwsException);

    expect(await const FlutterSecureStorage().read(key: SecureSessionStore.key),
        isNotNull);
  });

  test('chiave personalizzata: sessioni separate', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureSessionStore.key: legacySession('u1', 'a'),
      'wonderflix.session.b': legacySession('u2', 'b'),
    });
    final first = SecureSessionStore();
    final other = SecureSessionStore(null, 'wonderflix.session.b');
    expect((await first.read())?.userId, 'u1');
    expect((await other.read())?.userId, 'u2');
    await other.clear();
    expect(await other.read(), isNull);
    expect((await first.read())?.userId, 'u1');
  });
}
