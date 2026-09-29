import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/home/home_data.dart';

import '../../support/library_fakes.dart';

void main() {
  test('loadHome raccoglie tutte le righe', () async {
    final api = FakeLibraryApi()
      ..resumeItems = [testItem(id: 'r1')]
      ..nextUpItems = [testItem(id: 'n1', kind: ItemKind.episode)]
      ..onItems = (query, start, limit) {
        if (query.favoritesOnly) return pageOf([testItem(id: 'f1')]);
        if (query.kinds.contains(ItemKind.series)) {
          return pageOf([testItem(id: 's1', kind: ItemKind.series)]);
        }
        return pageOf([testItem(id: 'm1'), testItem(id: 'm2')]);
      };

    final home = await loadHome(api, 'u1');

    expect(home.resume.single.id, 'r1');
    expect(home.nextUp.single.id, 'n1');
    expect(home.latestMovies.map((i) => i.id), ['m1', 'm2']);
    expect(home.latestSeries.single.id, 's1');
    expect(home.favorites.single.id, 'f1');
    expect(home.featured.map((i) => i.id), ['m1', 's1', 'm2']);
    expect(home.isEmpty, isFalse);
  });

  test('pickFeatured: alterna film e serie, solo con sfondo, al massimo 5', () {
    const noBackdrop = JellyfinItem(id: 'x', name: 'x', kind: ItemKind.movie);
    final movies = [for (var i = 0; i < 5; i++) testItem(id: 'm$i'), noBackdrop];
    final series = [testItem(id: 's0', kind: ItemKind.series)];
    expect(pickFeatured(movies, series).map((i) => i.id),
        ['m0', 's0', 'm1', 'm2', 'm3']);
  });
}
