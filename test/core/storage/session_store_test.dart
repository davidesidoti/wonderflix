import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/storage/session_store.dart';

/// Storage finto che fallisce in lettura, come farebbe il Gestore
/// credenziali di Windows se non disponibile.
class _ThrowingReadStorage extends FlutterSecureStorage {
  const _ThrowingReadStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: 'boom');
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('scrive, legge e cancella la sessione', () async {
    final store = SecureSessionStore();
    expect(await store.read(), isNull);

    await store.write(const StoredSession(userId: 'u1', accessToken: 'tok'));
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

  test('uno storage che fallisce in lettura restituisce null', () async {
    final store = SecureSessionStore(const _ThrowingReadStorage());
    expect(await store.read(), isNull);
  });

  test('chiave personalizzata: sessioni separate', () async {
    final first = SecureSessionStore();
    final other = SecureSessionStore(null, 'wonderflix.session.b');
    await first.write(const StoredSession(userId: 'u1', accessToken: 'a'));
    await other.write(const StoredSession(userId: 'u2', accessToken: 'b'));
    expect((await first.read())?.userId, 'u1');
    expect((await other.read())?.userId, 'u2');
    await other.clear();
    expect(await other.read(), isNull);
    expect((await first.read())?.userId, 'u1');
  });
}
