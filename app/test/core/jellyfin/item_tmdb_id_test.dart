import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

void main() {
  JellyfinItem item(Object? providerIds) => JellyfinItem.fromJson({
        'Id': 'ee39bef06f503dd0e9dbd20593df417f',
        'Name': 'Dune',
        'Type': 'Movie',
        'ProviderIds': providerIds,
      });

  test('tmdbId dai ProviderIds (spec I §8.1)', () {
    expect(item({'Tmdb': '438631', 'Imdb': 'tt1160419'}).tmdbId, 438631);
    expect(item({'Imdb': 'tt1160419'}).tmdbId, isNull);
    expect(item({'Tmdb': 'abc'}).tmdbId, isNull);
    expect(item(null).tmdbId, isNull);
  });
}
