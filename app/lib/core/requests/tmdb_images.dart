import '../jellyfin/image_urls.dart';

/// Immagini di TMDB per i titoli che non sono nella libreria (spec I §8.1).
abstract final class TmdbImages {
  static const _base = 'https://image.tmdb.org/t/p';

  /// Larghezza delle locandine: card larghe 150 su schermi fino a 2x.
  static const posterSize = 'w342';

  /// Larghezza degli sfondi della scheda.
  static const backdropSize = 'w1280';

  static ImageRef? poster(String? path) => _ref(posterSize, path);

  static ImageRef? backdrop(String? path) => _ref(backdropSize, path);

  static ImageRef? _ref(String size, String? path) =>
      path == null || !path.startsWith('/') ? null : ImageRef('$_base/$size$path');
}
