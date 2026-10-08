import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/device/dev_profile.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/core/storage/session_store.dart';

import '../../support/throwing_secure_storage.dart';

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

    test('fromJson: l\'ultimo usato con maiuscole e trattini diversi vale', () {
      const id = 'ab8240c5-0000-0000-0000-00000000000a';
      const last = 'AB8240C500000000000000000000000A';
      final book = ProfileBook.fromJson({
        'profiles': [profile(id).toJson()],
        'lastUserId': last,
      });
      expect(book.lastUserId, last);
      // E anche togliendo il profilo si riconosce.
      expect(book.remove(id).lastUserId, isNull);
    });

    test('fromJson: senza un elenco di profili il risultato è vuoto', () {
      expect(ProfileBook.fromJson({'profiles': 'non una lista'}).profiles,
          isEmpty);
      expect(ProfileBook.fromJson(const {}).profiles, isEmpty);
    });

    test('upsert in un elenco pieno: un utente già presente si aggiorna, '
        'uno nuovo no', () {
      var book = const ProfileBook();
      for (var i = 0; i < ProfileBook.maxProfiles; i++) {
        book = book.upsert(profile('u$i'));
      }
      expect(book.isFull, isTrue);
      expect(book.upsert(profile('u0', name: 'Nuovo nome')).byId('u0')!.name,
          'Nuovo nome');
      // L'elenco pieno lo controlla chi chiama: qui è un errore di
      // programmazione, che l'assert fa vedere.
      expect(() => book.upsert(profile('u9')), throwsA(isA<AssertionError>()));
    });
  });

  group('StoredProfile.copyWith', () {
    test('senza argomenti tiene tutto, compresa l\'immagine', () {
      final copy = profile('u1', imageTag: 'img1', expired: true).copyWith();
      expect(copy.imageTag, 'img1');
      expect(copy.expired, isTrue);
      expect(copy.name, 'Mario');
      expect(copy.accessToken, 'tok-u1');
      expect(copy.deviceId, 'dev-u1');
      expect(copy.lastUsedAt, DateTime.utc(2026, 10, 8, 20));
    });

    test('imageTag: null la toglie, un valore la cambia', () {
      final tagged = profile('u1', imageTag: 'img1');
      expect(tagged.copyWith(imageTag: null).imageTag, isNull);
      expect(tagged.copyWith(imageTag: 'img2').imageTag, 'img2');
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

  test(
      'migrazione: se il salvataggio dei profili fallisce, read() non lancia '
      'e la sessione di prima resta', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureSessionStore.key:
          jsonEncode({'userId': 'u1', 'accessToken': 'tok-vecchio'}),
    });
    final failing = SecureProfileStore(
        storage: const ThrowingWriteStorage(),
        legacyDeviceId: 'dev-installazione');

    final book = await failing.read();

    expect(book.profiles.single.userId, 'u1');
    expect(book.profiles.single.accessToken, 'tok-vecchio');
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: SecureSessionStore.key), isNotNull);
    expect(await storage.read(key: SecureProfileStore.defaultKey), isNull);
    // Al prossimo avvio, con lo storage di nuovo sano, si migra davvero.
    expect((await store().read()).profiles.single.accessToken, 'tok-vecchio');
    expect(await storage.read(key: SecureSessionStore.key), isNull);
    expect(await storage.read(key: SecureProfileStore.defaultKey), isNotNull);
  });

  test(
      'migrazione: se la sessione di prima non si cancella, read() non lancia '
      'e i profili sono salvati', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureSessionStore.key:
          jsonEncode({'userId': 'u1', 'accessToken': 'tok-vecchio'}),
    });
    final failing = SecureProfileStore(
        storage: const ThrowingDeleteStorage(),
        legacyDeviceId: 'dev-installazione');

    final book = await failing.read();

    expect(book.profiles.single.userId, 'u1');
    expect(book.lastUserId, 'u1');
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: SecureProfileStore.defaultKey), isNotNull);
    // La sessione di prima è ancora lì, ma i profili hanno la precedenza.
    expect(await storage.read(key: SecureSessionStore.key), isNotNull);
    final again = await failing.read();
    expect(again.profiles.single.userId, 'u1');
    expect(again.profiles.single.deviceId, 'dev-installazione');
  });

  test(
      'migrazione: una sessione di prima rovinata che non si cancella dà '
      'nessun profilo, senza eccezioni', () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureSessionStore.key: 'non-json'});
    final failing = SecureProfileStore(
        storage: const ThrowingDeleteStorage(), legacyDeviceId: 'dev');
    expect((await failing.read()).profiles, isEmpty);
  });

  test('migrazione nell\'istanza di sviluppo: le sue chiavi e il suo DeviceId',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      sessionKeyFor('b'):
          jsonEncode({'userId': 'u2', 'accessToken': 'tok-b'}),
    });
    final dev = SecureProfileStore(
        key: profilesKeyFor('b'),
        legacyKey: sessionKeyFor('b'),
        legacyDeviceId: 'dev-b');

    final book = await dev.read();

    final migrated = book.profiles.single;
    expect(migrated.userId, 'u2');
    expect(migrated.accessToken, 'tok-b');
    expect(migrated.deviceId, 'dev-b');
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: sessionKeyFor('b')), isNull);
    expect(await storage.read(key: profilesKeyFor('b')), isNotNull);
    // L'istanza normale non vede niente e non scrive niente.
    expect((await store().read()).profiles, isEmpty);
    expect(await storage.read(key: SecureProfileStore.defaultKey), isNull);
  });

  test('profili illeggibili: nessun profilo, nessuna eccezione', () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureProfileStore.defaultKey: 'non-json'});
    expect((await store().read()).profiles, isEmpty);
  });

  test('JSON valido ma non un oggetto: nessun profilo, nessuna eccezione',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureProfileStore.defaultKey: '[]'});
    expect((await store().read()).profiles, isEmpty);
  });

  test('JSON con i profili che non sono un elenco: nessun profilo', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureProfileStore.defaultKey:
          jsonEncode({'version': 1, 'profiles': 'non una lista'}),
    });
    expect((await store().read()).profiles, isEmpty);
  });

  test('uno storage che fallisce in lettura: nessun profilo', () async {
    final failing = SecureProfileStore(
        storage: const ThrowingReadStorage(), legacyDeviceId: 'dev');
    expect((await failing.read()).profiles, isEmpty);
  });

  group('dopo una lettura non riuscita (spec K §9.1)', () {
    late FlakyReadStorage flaky;
    late SecureProfileStore failing;

    List<String> ids(ProfileBook book) =>
        [for (final p in book.profiles) p.userId];

    setUp(() async {
      await store().write(const ProfileBook()
          .upsert(profile('u1'))
          .upsert(profile('u2', name: 'Luigi'))
          .withLast('u2'));
      flaky = FlakyReadStorage();
      failing = SecureProfileStore(storage: flaky, legacyDeviceId: 'dev');
      expect((await failing.read()).profiles, isEmpty);
    });

    test('il salvataggio rilegge e tiene i profili che c\'erano', () async {
      flaky.failing = false;

      final written = await failing.write(const ProfileBook()
          .upsert(profile('u3', name: 'Peach'))
          .withLast('u3'));

      expect(ids(written), ['u1', 'u2', 'u3']);
      expect(written.lastUserId, 'u3');
      final read = await store().read();
      expect(ids(read), ['u1', 'u2', 'u3']);
      expect(read.lastUserId, 'u3');
    });

    test('i profili nuovi vincono su quelli salvati', () async {
      flaky.failing = false;

      final written = await failing.write(const ProfileBook()
          .upsert(profile('u1').copyWith(accessToken: 'tok-nuovo')));

      expect(ids(written), ['u2', 'u1']);
      expect(written.byId('u1')!.accessToken, 'tok-nuovo');
    });

    test('al massimo 5 profili: quelli nuovi restano tutti', () async {
      await store().write([
        for (var i = 1; i <= ProfileBook.maxProfiles; i++) profile('u$i'),
      ].fold(const ProfileBook(), (book, p) => book.upsert(p)));
      flaky.failing = false;

      final written =
          await failing.write(const ProfileBook().upsert(profile('u9')));

      expect(ids(written), ['u1', 'u2', 'u3', 'u4', 'u9']);
    });

    test('se la rilettura fallisce ancora, non si sovrascrive', () async {
      await expectLater(
          failing.write(const ProfileBook().upsert(profile('u3'))),
          throwsStateError);
      expect(ids(await store().read()), ['u1', 'u2']);
    });

    test('la sessione di prima che non si legge non si perde', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureSessionStore.key:
            jsonEncode({'userId': 'u1', 'accessToken': 'tok-vecchio'}),
      });
      final legacyFlaky = FlakyReadStorage(onlyKey: SecureSessionStore.key);
      final migrating = SecureProfileStore(
          storage: legacyFlaky, legacyDeviceId: 'dev-installazione');
      expect((await migrating.read()).profiles, isEmpty);
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: SecureSessionStore.key), isNotNull);

      legacyFlaky.failing = false;
      final written = await migrating.write(
          const ProfileBook().upsert(profile('u2')).withLast('u2'));

      // Il primo salvataggio migra la sessione di prima e la tiene.
      expect(ids(written), ['u1', 'u2']);
      expect(written.byId('u1')!.accessToken, 'tok-vecchio');
      expect(written.byId('u1')!.deviceId, 'dev-installazione');
      expect(written.lastUserId, 'u2');
      expect(await storage.read(key: SecureSessionStore.key), isNull);
      expect(ids(await store().read()), ['u1', 'u2']);
    });

    test('dopo il primo salvataggio riuscito si scrive come sempre', () async {
      flaky.failing = false;
      final merged =
          await failing.write(const ProfileBook().upsert(profile('u3')));

      await failing.write(merged.remove('u1'));

      expect(ids(await store().read()), ['u2', 'u3']);
    });
  });

  test('profili illeggibili (dati rovinati): il salvataggio li sostituisce',
      () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureProfileStore.defaultKey: 'non-json'});
    final corrupt = store();
    expect((await corrupt.read()).profiles, isEmpty);

    final written =
        await corrupt.write(const ProfileBook().upsert(profile('u3')));

    expect(written.profiles.single.userId, 'u3');
    expect((await store().read()).profiles.single.userId, 'u3');
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
