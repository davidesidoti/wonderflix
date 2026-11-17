import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;
  late ProviderContainer container;
  final provider = catalogControllerProvider(ItemKind.movie);

  List<JellyfinItem> items(int from, int count) =>
      [for (var i = from; i < from + count; i++) testItem(id: 'm$i')];

  setUp(() {
    api = FakeLibraryApi()
      ..onItems = (query, start, limit) =>
          pageOf(items(start, start + limit > 150 ? 150 - start : limit), 150);
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  // Il controller carica solo quando gli si dice il genere: start() fa
  // come la schermata.
  void start() {
    container.listen(provider, (_, _) {});
    unawaited(container.read(provider.notifier).showGenre(null));
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('senza showGenre non parte nessuna richiesta', () async {
    container.listen(provider, (_, _) {});
    await settle();
    expect(api.itemQueries, isEmpty);
    expect(container.read(provider).loading, isTrue);
    expect(container.read(provider).query.sort, CatalogSort.dateAdded);
  });

  test('showGenre: genere, ordine per voto, etichetta nello stato', () async {
    container.listen(provider, (_, _) {});
    await container.read(provider.notifier).showGenre('Horror');
    expect(api.itemQueries.single.genres, {'Horror'});
    expect(api.itemQueries.single.sort, CatalogSort.rating);
    expect(container.read(provider).genre, 'Horror');
    expect(container.read(provider).items, hasLength(100));
  });

  test('showGenre con una ricerca la mette nella query, poi la tiene',
      () async {
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await controller.showGenre(null, searchTerm: 'ist');
    expect(api.itemQueries.last.searchTerm, 'ist');
    await controller.showGenre('Dramma');
    expect(api.itemQueries.last.searchTerm, 'ist');
    expect(api.itemQueries.last.genres, isNotEmpty);
  });

  test('showGenre(null) torna a tutto, per data di aggiunta', () async {
    container.listen(provider, (_, _) {});
    await container.read(provider.notifier).showGenre('Horror');
    await container.read(provider.notifier).showGenre(null);
    expect(api.itemQueries.last.genres, isEmpty);
    expect(api.itemQueries.last.sort, CatalogSort.dateAdded);
    expect(container.read(provider).genre, isNull);
  });

  test('showGenre tiene il decennio e unisce i nomi del genere', () async {
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await controller.showGenre(null);
    await controller.setQuery(
        container.read(provider).query.copyWith(decade: 2010, reversed: true));
    await controller.showGenre('Dramma');
    final query = api.itemQueries.last;
    expect(query.decade, 2010);
    expect(query.genres, {'Dramma', 'Drama'});
    expect(query.reversed, isFalse);
    expect(container.read(provider).query.decade, 2010);
  });

  test('cambiando genere in fretta vince l\'ultimo, anche se risponde per primo',
      () async {
    final gates = <String, Completer<void>>{
      for (final g in ['Azione', 'Horror', 'Dramma']) g: Completer<void>(),
    };
    api.itemsGateFor = (q) => gates[q.genres.first];
    api.onItems = (query, start, limit) =>
        pageOf([testItem(id: query.genres.first)], 1);
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    final azione = controller.showGenre('Azione');
    final horror = controller.showGenre('Horror');
    final dramma = controller.showGenre('Dramma');
    await settle();
    // Le risposte arrivano in ordine inverso: Dramma, poi Horror e Azione.
    gates['Dramma']!.complete();
    await dramma;
    gates['Horror']!.complete();
    gates['Azione']!.complete();
    await Future.wait([azione, horror]);
    final state = container.read(provider);
    expect(state.genre, 'Dramma');
    expect(state.items.single.id, 'Dramma');
    expect(state.query.genres, {'Dramma', 'Drama'});
    expect(state.loading, isFalse);
  });

  test('prima pagina all\'avvio', () async {
    start();
    expect(container.read(provider).loading, isTrue);
    await settle();
    final state = container.read(provider);
    expect(state.items, hasLength(100));
    expect(state.total, 150);
    expect(state.hasMore, isTrue);
    expect(api.itemQueries.single.kinds, {ItemKind.movie});
  });

  test('loadMore aggiunge la pagina successiva e si ferma alla fine', () async {
    start();
    await settle();
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).items, hasLength(150));
    expect(container.read(provider).hasMore, isFalse);
    await container.read(provider.notifier).loadMore();
    expect(api.itemQueries, hasLength(2));
  });

  test('setQuery riparte da zero con i nuovi filtri', () async {
    start();
    await settle();
    await container
        .read(provider.notifier)
        .setQuery(const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.year));
    expect(container.read(provider).query.sort, CatalogSort.year);
    expect(container.read(provider).items.first.id, 'm0');
    expect(api.itemQueries.last.sort, CatalogSort.year);
  });

  test('errore e riprova', () async {
    api.error = const ServerUnreachableException();
    start();
    await settle();
    expect(container.read(provider).error, isA<ServerUnreachableException>());
    api.error = null;
    await container.read(provider.notifier).retry();
    expect(container.read(provider).items, hasLength(100));
    expect(container.read(provider).error, isNull);
  });

  test('dopo un errore di pagina loadMore non fa richieste', () async {
    start();
    await settle();
    api.error = const ServerUnreachableException();
    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).error, isA<ServerUnreachableException>());
    final requests = api.itemQueries.length;
    api.error = null;
    await container.read(provider.notifier).loadMore();
    expect(api.itemQueries, hasLength(requests));
    expect(container.read(provider).items, hasLength(100));

    // Il pulsante "Riprova" invece funziona.
    await container.read(provider.notifier).retry();
    expect(container.read(provider).items, hasLength(150));
  });

  test('una risposta superata da una query più recente viene ignorata', () async {
    start();
    await settle();
    api.delay = const Duration(milliseconds: 50);
    final controller = container.read(provider.notifier);
    final slow = controller.setQuery(
        const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.rating));
    api.delay = Duration.zero;
    await controller.setQuery(
        const ItemQuery(kinds: {ItemKind.movie}, sort: CatalogSort.year));
    await slow;
    expect(container.read(provider).query.sort, CatalogSort.year);
  });
}
