import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

import '../support/library_fakes.dart';

void main() {
  test('itemRoute', () {
    expect(itemRoute(testItem(id: 'm1')), '/item/m1');
    expect(itemRoute(testItem(id: 's1', kind: ItemKind.series)), '/item/s1');
    expect(
      itemRoute(testItem(
          id: 'e4', kind: ItemKind.episode, seriesId: 's1', seasonId: 'se1')),
      '/item/s1?season=se1',
    );
    expect(
      itemRoute(testItem(id: 'e4', kind: ItemKind.episode, seriesId: 's1')),
      '/item/s1',
    );
    expect(itemRoute(testItem(id: 'se1', kind: ItemKind.season, seriesId: 's1')),
        '/item/s1?season=se1');
    expect(itemRoute(testItem(id: 'p9', kind: ItemKind.person)), '/person/p9');
  });

  test('playerRoute e playerStartFrom', () {
    expect(playerRoute('m1'), '/play/m1');
    expect(playerRoute('m1', start: const Duration(minutes: 23)),
        '/play/m1?start=1380000');
    expect(playerStartFrom(Uri.parse('/play/m1?start=1380000')),
        const Duration(minutes: 23));
    expect(playerStartFrom(Uri.parse('/play/m1')), Duration.zero);
    expect(playerStartFrom(Uri.parse('/play/m1?start=abc')), Duration.zero);
  });
}
