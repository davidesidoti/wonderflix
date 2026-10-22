import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/home/home_data.dart';

import '../../support/library_fakes.dart';

void main() {
  test('pickFeatured: alterna film e serie, solo con sfondo, al massimo 5', () {
    const noBackdrop = JellyfinItem(id: 'x', name: 'x', kind: ItemKind.movie);
    final movies = [for (var i = 0; i < 5; i++) testItem(id: 'm$i'), noBackdrop];
    final series = [testItem(id: 's0', kind: ItemKind.series)];
    expect(pickFeatured(movies, series).map((i) => i.id),
        ['m0', 's0', 'm1', 'm2', 'm3']);
  });

  test('nextUpCutoff', () {
    expect(nextUpCutoff(DateTime.utc(2026, 9, 29)), DateTime.utc(2025, 9, 29));
  });
}
