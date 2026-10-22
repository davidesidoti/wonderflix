import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeCollectionsApi collections;
  late FakeLibraryApi library;
  late FakeSocialAvailability availability;
  late FakeSessionController session;

  setUp(() {
    collections = FakeCollectionsApi()
      ..collectionsList = [testCollection(id: 'c1', itemIds: ['m1', 'm2'])];
    library = FakeLibraryApi();
    availability =
        FakeSocialAvailability(const SocialFeatures(collections: true));
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: [
          sessionControllerProvider.overrideWith(() => session),
          socialAvailabilityProvider.overrideWith(() => availability),
          collectionsApiProvider.overrideWithValue(collections),
          libraryApiProvider.overrideWithValue(library),
        ],
        retry: (_, _) => null,
      );

  test('con la funzione: legge le saghe e costruisce l\'indice', () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), hasLength(1));
    expect(c.read(collectionsByItemProvider)['m1']!.single.id, 'c1');
    expect(collections.calls, 1);
  });

  test('l\'elenco letto non si può modificare', () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    final sagas = await c.read(collectionsProvider.future);
    expect(() => sagas.add(testCollection(id: 'c9')), throwsUnsupportedError);
  });

  test('senza la funzione: vuoto e nessuna chiamata', () async {
    availability = FakeSocialAvailability(SocialFeatures.none);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), isEmpty);
    expect(c.read(collectionsByItemProvider), isEmpty);
    expect(collections.calls, 0);
  });

  test('senza la funzione e senza utente: vuoto, senza errori', () async {
    availability = FakeSocialAvailability(SocialFeatures.none);
    session = FakeSessionController(const SessionSignedOut());
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), isEmpty);
    expect(collections.calls, 0);
  });

  test('la funzione che arriva dopo fa leggere le saghe', () async {
    availability = FakeSocialAvailability(SocialFeatures.unknown);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), isEmpty);
    availability.set(const SocialFeatures(collections: true));
    expect(await c.read(collectionsProvider.future), hasLength(1));
  });

  test('una libreria cambiata fa rileggere le saghe', () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    await c.read(collectionsProvider.future);
    c.read(libraryRevisionProvider.notifier).bump();
    await c.read(collectionsProvider.future);
    expect(collections.calls, 2);
  });

  test('un altro utente fa rileggere le saghe', () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    await c.read(collectionsProvider.future);
    session.set(const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
    await c.read(collectionsProvider.future);
    expect(collections.calls, 2);
  });

  test('errore: l\'indice resta vuoto', () async {
    collections.error = const ServerErrorException(null);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    await expectLater(c.read(collectionsProvider.future),
        throwsA(isA<ServerErrorException>()));
    expect(c.read(collectionsByItemProvider), isEmpty);
  });

  test('una rilettura che fallisce, con qualcuno in ascolto, lascia l\'indice com\'era',
      () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    c.listen(collectionsByItemProvider, (_, _) {});
    await c.read(collectionsProvider.future);
    collections.error = const ServerErrorException(null);
    c.read(libraryRevisionProvider.notifier).bump();
    await expectLater(c.read(collectionsProvider.future),
        throwsA(isA<ServerErrorException>()));
    expect(c.read(collectionsProvider).hasError, isTrue);
    // Il valore di prima c'è ancora, e con lui l'indice.
    expect(c.read(collectionsProvider).value, hasLength(1));
    expect(c.read(collectionsByItemProvider)['m1']!.single.id, 'c1');
  });

  test('un errore non resta in cache: tornando ad ascoltare si riprova',
      () async {
    collections.error = const ServerErrorException(null);
    final c = container();
    final first = c.listen(collectionsProvider, (_, _) {});
    await expectLater(c.read(collectionsProvider.future),
        throwsA(isA<ServerErrorException>()));
    first.close();
    await pumpEventQueue();
    collections.error = null;
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), hasLength(1));
    expect(collections.calls, 2);
  });

  test('una lettura riuscita resta in cache anche senza ascoltatori',
      () async {
    final c = container();
    final first = c.listen(collectionsProvider, (_, _) {});
    await c.read(collectionsProvider.future);
    first.close();
    await pumpEventQueue();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), hasLength(1));
    expect(collections.calls, 1);
  });

  test('i titoli di una saga', () async {
    library.itemsByCollection['c1'] = [testItem(id: 'm1'), testItem(id: 'm2')];
    final c = container();
    c.listen(collectionItemsProvider('c1'), (_, _) {});
    final items = await c.read(collectionItemsProvider('c1').future);
    expect(items.map((item) => item.id), ['m1', 'm2']);
    expect(library.collectionItemsCalls, ['c1']);
  });

  test('i titoli di una saga si rileggono quando cambiano i dati utente',
      () async {
    library.itemsByCollection['c1'] = [testItem(id: 'm1')];
    final c = container();
    c.listen(collectionItemsProvider('c1'), (_, _) {});
    await c.read(collectionItemsProvider('c1').future);
    c.read(userDataRevisionProvider.notifier).bump();
    await c.read(collectionItemsProvider('c1').future);
    expect(library.collectionItemsCalls, ['c1', 'c1']);
  });
}
