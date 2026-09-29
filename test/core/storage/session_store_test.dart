import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/storage/session_store.dart';

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
}
