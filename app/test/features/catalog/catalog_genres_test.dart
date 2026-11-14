import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_controller.dart';
import 'package:wonderflix/features/catalog/catalog_genres.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;
  late ProviderContainer container;

  setUp(() {
    api = FakeLibraryApi();
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  test('conteggi per genere: unisce i nomi, scarta i piccoli, ordina', () async {
    api.libraryFilters = const LibraryFilters(
        genres: ['Azione', 'Dramma', 'Psychological', 'Western']);
    // Drama e Dramma uniti si contano con una sola richiesta.
    api.onItems = (query, start, limit) {
      expect(limit, 0);
      final total = query.genres.contains('Dramma')
          ? 212
          : const {'Azione': 330, 'Western': 6, 'Psychological': 1}[
              query.genres.first]!;
      return pageOf(const [], total);
    };
    final result =
        await container.read(catalogGenresProvider(ItemKind.movie).future);
    expect(result, const [
      GenreCount('Azione', 330),
      GenreCount('Dramma', 212),
      GenreCount('Western', 6),
    ]);
    expect(
        api.itemQueries
            .firstWhere((q) => q.genres.contains('Dramma'))
            .genres,
        {'Dramma', 'Drama'});
  });

  test('una lettura che fallisce manda in errore i generi, non la griglia',
      () async {
    api.libraryFilters = const LibraryFilters(genres: ['Azione', 'Horror']);
    api.onItems = (query, start, limit) {
      if (limit == 0) throw StateError('boom');
      return pageOf([testItem(id: 'm1')], 1);
    };
    final genres = catalogGenresProvider(ItemKind.movie);
    container.listen(genres, (_, _) {});
    await expectLater(container.read(genres.future), throwsStateError);

    final grid = catalogControllerProvider(ItemKind.movie);
    container.listen(grid, (_, _) {});
    await container.read(grid.notifier).showGenre('Azione');
    expect(container.read(grid).error, isNull);
    expect(container.read(grid).items, hasLength(1));
  });

  test('totali dei film: tutti e visti, con i generi dell\'etichetta', () async {
    api.onItems = (query, start, limit) =>
        pageOf(const [], query.watched == WatchedFilter.watched ? 58 : 128);
    final totals = await container
        .read(catalogTotalsProvider((ItemKind.movie, 'Horror')).future);
    expect(totals, const CatalogTotals(128, 58));
    expect(api.itemQueries, hasLength(2));
    expect(api.itemQueries.every((q) => q.genres.contains('Horror')), isTrue);
    expect(api.itemQueries.last.watched, WatchedFilter.watched);
  });

  test('totali delle serie senza genere: la seconda lettura è "in corso"',
      () async {
    api.onItems = (query, start, limit) => pageOf(const [],
        query.seriesStatus == SeriesStatusFilter.continuing ? 9 : 40);
    final totals = await container
        .read(catalogTotalsProvider((ItemKind.series, null)).future);
    expect(totals, const CatalogTotals(40, 9));
    expect(api.itemQueries.every((q) => q.genres.isEmpty), isTrue);
    expect(api.itemQueries.last.seriesStatus, SeriesStatusFilter.continuing);
  });
}
