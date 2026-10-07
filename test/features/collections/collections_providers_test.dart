import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
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

  setUp(() {
    collections = FakeCollectionsApi()
      ..collectionsList = [testCollection(id: 'c1', itemIds: ['m1', 'm2'])];
    library = FakeLibraryApi();
    availability =
        FakeSocialAvailability(const SocialFeatures(collections: true));
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: [
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
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

  test('senza la funzione: vuoto e nessuna chiamata', () async {
    availability = FakeSocialAvailability(SocialFeatures.none);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), isEmpty);
    expect(c.read(collectionsByItemProvider), isEmpty);
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

  test('errore: l\'indice resta vuoto', () async {
    collections.error = const ServerErrorException(null);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    await expectLater(c.read(collectionsProvider.future),
        throwsA(isA<ServerErrorException>()));
    expect(c.read(collectionsByItemProvider), isEmpty);
  });

  test('i titoli di una saga', () async {
    library.itemsByCollection['c1'] = [testItem(id: 'm1'), testItem(id: 'm2')];
    final c = container();
    c.listen(collectionItemsProvider('c1'), (_, _) {});
    final items = await c.read(collectionItemsProvider('c1').future);
    expect(items.map((item) => item.id), ['m1', 'm2']);
    expect(library.collectionItemsCalls, ['c1']);
  });
}
