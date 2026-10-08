import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/device/dev_profile.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/core/storage/session_store.dart';

/// Storage finto che fallisce in lettura.
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

StoredProfile profile(String userId,
        {String name = 'Mario', bool expired = false, String? imageTag}) =>
    StoredProfile(
      userId: userId,
      name: name,
      accessToken: 'tok-$userId',
      deviceId: 'dev-$userId',
      imageTag: imageTag,
      lastUsedAt: DateTime.utc(2026, 10, 8, 20),
      expired: expired,
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  SecureProfileStore store() =>
      SecureProfileStore(legacyDeviceId: 'dev-installazione');

  group('ProfileBook', () {
    test('upsert sostituisce lo stesso utente al suo posto e aggiunge gli altri',
        () {
      final book = const ProfileBook()
          .upsert(profile('u1'))
          .upsert(profile('u2', name: 'Luigi'))
          .upsert(profile('U1', name: 'Mario Rossi'));
      expect(book.profiles.map((p) => p.name), ['Mario Rossi', 'Luigi']);
      expect(book.byId('u1')!.name, 'Mario Rossi');
    });

    test('remove toglie anche l\'ultimo usato', () {
      final book = const ProfileBook()
          .upsert(profile('u1'))
          .upsert(profile('u2'))
          .withLast('u2');
      expect(book.remove('u2').lastUserId, isNull);
      expect(book.remove('u1').lastUserId, 'u2');
      expect(book.remove('u1').profiles.single.userId, 'u2');
    });

    test('byId confronta senza trattini e maiuscole; isFull a 5', () {
      var book = const ProfileBook()
          .upsert(profile('ab8240c5-0000-0000-0000-00000000000a'));
      expect(book.byId('AB8240C500000000000000000000000A'), isNotNull);
      for (var i = 0; i < 4; i++) {
        book = book.upsert(profile('u$i'));
      }
      expect(book.profiles, hasLength(ProfileBook.maxProfiles));
      expect(book.isFull, isTrue);
    });

    test('fromJson: scarta i profili rotti e i doppioni, al massimo 5', () {
      final book = ProfileBook.fromJson({
        'version': 1,
        'profiles': [
          profile('u1').toJson(),
          {'userId': 'senza-token'},
          'non un oggetto',
          profile('U1', name: 'Doppione').toJson(),
          for (var i = 2; i <= 7; i++) profile('u$i').toJson(),
        ],
        'lastUserId': 'u9',
      });
      expect(book.profiles.map((p) => p.userId), ['u1', 'u2', 'u3', 'u4', 'u5']);
      expect(book.profiles.first.name, 'Mario');
      // Un ultimo usato che non c'è più non vale.
      expect(book.lastUserId, isNull);
    });
  });

  test('senza niente salvato: nessun profilo', () async {
    expect((await store().read()).profiles, isEmpty);
  });

  test('scrive e rilegge profili, ultimo usato, immagine e scadenza', () async {
    final written = const ProfileBook()
        .upsert(profile('u1', imageTag: 'img1'))
        .upsert(profile('u2', name: 'Luigi', expired: true))
        .withLast('u1');
    await store().write(written);

    final read = await store().read();
    expect(read.lastUserId, 'u1');
    final mario = read.byId('u1')!;
    expect(mario.accessToken, 'tok-u1');
    expect(mario.deviceId, 'dev-u1');
    expect(mario.imageTag, 'img1');
    expect(mario.lastUsedAt, DateTime.utc(2026, 10, 8, 20));
    expect(mario.expired, isFalse);
    expect(read.byId('u2')!.expired, isTrue);
  });

  test('migrazione: la sessione di prima diventa il primo profilo', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureSessionStore.key:
          jsonEncode({'userId': 'u1', 'accessToken': 'tok-vecchio'}),
    });

    final book = await store().read();

    final migrated = book.profiles.single;
    expect(migrated.userId, 'u1');
    expect(migrated.accessToken, 'tok-vecchio');
    // Il DeviceId di prima: il token resta valido.
    expect(migrated.deviceId, 'dev-installazione');
    // Il nome si legge al primo /Users/Me.
    expect(migrated.name, '');
    expect(book.lastUserId, 'u1');
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: SecureSessionStore.key), isNull);
    expect(await storage.read(key: SecureProfileStore.defaultKey), isNotNull);
    // Una seconda lettura non migra di nuovo.
    expect((await store().read()).profiles.single.accessToken, 'tok-vecchio');
  });

  test('profili illeggibili: nessun profilo, nessuna eccezione', () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureProfileStore.defaultKey: 'non-json'});
    expect((await store().read()).profiles, isEmpty);
  });

  test('uno storage che fallisce in lettura: nessun profilo', () async {
    final failing = SecureProfileStore(
        storage: const _ThrowingReadStorage(), legacyDeviceId: 'dev');
    expect((await failing.read()).profiles, isEmpty);
  });

  test('istanza di sviluppo: chiavi separate', () async {
    final dev = SecureProfileStore(
        key: profilesKeyFor('b'),
        legacyKey: sessionKeyFor('b'),
        legacyDeviceId: 'dev-b');
    expect(profilesKeyFor(null), SecureProfileStore.defaultKey);
    expect(profilesKeyFor('b'), 'wonderflix.profiles.b');
    await store().write(const ProfileBook().upsert(profile('u1')));
    await dev.write(const ProfileBook().upsert(profile('u2')));
    expect((await store().read()).profiles.single.userId, 'u1');
    expect((await dev.read()).profiles.single.userId, 'u2');
  });
}
