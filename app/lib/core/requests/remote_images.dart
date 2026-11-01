import '../jellyfin/image_urls.dart';
import 'tmdb_images.dart';

/// Immagini di Sonarr e Radarr, arrivate dal plugin come originali. Sul web
/// l'immagine si decodifica intera: gli originali esauriscono la memoria
/// grafica di iOS e le immagini diventano nere, quindi si chiede la misura
/// della card.
abstract final class RemoteImages {
  /// Sfondo nelle card delle righe, non lo sfondo intero della scheda.
  static const backdropRowSize = 'w780';

  static final _tmdb = RegExp(r'^(https://image\.tmdb\.org/t/p)/[^/]+/');
  static final _tvdbJpg = RegExp(
      r'^https://artworks\.thetvdb\.com/banners/.+(?<!_t)\.jpg$');

  static ImageRef poster(String url) => _resize(url, TmdbImages.posterSize);

  static ImageRef backdrop(String url) => _resize(url, backdropRowSize);

  static ImageRef _resize(String url, String tmdbSize) {
    if (_tvdbJpg.hasMatch(url)) {
      return ImageRef(url.replaceFirst(RegExp(r'\.jpg$'), '_t.jpg'));
    }
    return ImageRef(
        url.replaceFirstMapped(_tmdb, (m) => '${m[1]}/$tmdbSize/'));
  }
}
