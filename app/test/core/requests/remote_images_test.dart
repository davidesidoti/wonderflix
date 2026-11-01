import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/remote_images.dart';

void main() {
  const tmdb = 'https://image.tmdb.org/t/p';
  const tvdb = 'https://artworks.thetvdb.com/banners/v4/series/1/posters';

  test('TMDB: locandina a w342 e sfondo a w780, da qualsiasi misura', () {
    expect(RemoteImages.poster('$tmdb/original/abc.jpg').url,
        '$tmdb/w342/abc.jpg');
    expect(RemoteImages.poster('$tmdb/w500/abc.jpg').url, '$tmdb/w342/abc.jpg');
    expect(RemoteImages.backdrop('$tmdb/original/abc.jpg').url,
        '$tmdb/w780/abc.jpg');
    expect(
        RemoteImages.backdrop('$tmdb/w500/abc.jpg').url, '$tmdb/w780/abc.jpg');
  });

  test('TVDB: la miniatura _t per i .jpg, mai due volte', () {
    expect(RemoteImages.poster('$tvdb/64e9f1a384db5.jpg').url,
        '$tvdb/64e9f1a384db5_t.jpg');
    expect(RemoteImages.backdrop('$tvdb/64e9f1a384db5.jpg').url,
        '$tvdb/64e9f1a384db5_t.jpg');
    expect(RemoteImages.poster('$tvdb/64e9f1a384db5_t.jpg').url,
        '$tvdb/64e9f1a384db5_t.jpg');
  });

  test('il resto resta invariato', () {
    for (final url in [
      '$tvdb/clearlogo.png',
      'https://jf.example/jellyfin/Items/1/Images/Primary?maxWidth=120',
      'https://altro.example/poster.jpg',
    ]) {
      expect(RemoteImages.poster(url).url, url);
      expect(RemoteImages.backdrop(url).url, url);
    }
  });
}
