import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../jellyfin/jellyfin_http.dart';
import '../jellyfin/media_url.dart';
import '../jellyfin/playback_models.dart' show resolveServerUrl;

/// Di che titolo si vuole il trailer: uno della libreria o uno di TMDB.
sealed class TrailerSubject {
  const TrailerSubject();
}

class LibraryTrailer extends TrailerSubject {
  const LibraryTrailer(this.itemId);

  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is LibraryTrailer && other.itemId == itemId;

  @override
  int get hashCode => Object.hash('library', itemId);
}

class TmdbTrailer extends TrailerSubject {
  /// [type]: `'movie'` o `'tv'`.
  const TmdbTrailer(this.type, this.tmdbId);

  final String type;
  final int tmdbId;

  @override
  bool operator ==(Object other) =>
      other is TmdbTrailer && other.type == type && other.tmdbId == tmdbId;

  @override
  int get hashCode => Object.hash('tmdb', type, tmdbId);
}

enum TrailerState { none, downloading, ready, failed }

class TrailerStatus {
  const TrailerStatus(this.key, this.state);

  /// `null` se il plugin non ha un trailer per il titolo.
  final String? key;
  final TrailerState state;

  factory TrailerStatus.fromJson(Map<String, dynamic> json) {
    final key = json['Key'];
    return TrailerStatus(key is String ? key : null, switch (json['State']) {
      'None' => TrailerState.none,
      'Downloading' => TrailerState.downloading,
      'Ready' => TrailerState.ready,
      _ => TrailerState.failed,
    });
  }
}

/// Plugin vecchio (404), trailer che non c'è più o errore di rete.
class TrailerUnavailableException implements Exception {
  const TrailerUnavailableException();

  @override
  String toString() => 'TrailerUnavailableException';
}

/// Endpoint dei trailer del plugin.
class TrailersApi {
  TrailersApi(this._http);

  static const _base = '/WonderFlixWatchParty/Trailers';

  /// 404: plugin vecchio o chiave sconosciuta, non è un errore da segnalare.
  static const _quiet = {404};

  final JellyfinHttp _http;

  /// `false` anche su 404 (plugin vecchio) e su qualunque errore: il
  /// pulsante del trailer semplicemente non compare.
  Future<bool> available(TrailerSubject s) async {
    try {
      final json = asJsonMap(
        await _http.get(
          '$_base/Info',
          query: switch (s) {
            LibraryTrailer(:final itemId) => {'itemId': itemId},
            TmdbTrailer(:final type, :final tmdbId) => {
              'tmdbId': tmdbId,
              'type': type,
            },
          },
          quietStatuses: _quiet,
        ),
      );
      return json['Available'] == true;
    } on Object {
      return false;
    }
  }

  Future<TrailerStatus> start(TrailerSubject s) => _status(
    () async => _http.post(
      '$_base/Start',
      body: switch (s) {
        LibraryTrailer(:final itemId) => {'ItemId': itemId},
        TmdbTrailer(:final type, :final tmdbId) => {
          'Type': type,
          'TmdbId': tmdbId,
        },
      },
      quietStatuses: _quiet,
    ),
  );

  Future<TrailerStatus> status(String key) => _status(
    () =>
        _http.get('$_base/Status', query: {'key': key}, quietStatuses: _quiet),
  );

  /// Nel browser l'elemento video non può mandare l'header: il token va
  /// nell'URL.
  String streamUrl(String key) {
    final url = resolveServerUrl(_http.serverUrl, '$_base/$key/Stream');
    final token = _http.token;
    return token == null ? url : withApiKey(url, token);
  }

  Future<TrailerStatus> _status(Future<dynamic> Function() request) async {
    try {
      return TrailerStatus.fromJson(asJsonMap(await request()));
    } on Object {
      throw const TrailerUnavailableException();
    }
  }
}

final trailersApiProvider = Provider<TrailersApi>(
  (ref) => TrailersApi(ref.watch(jellyfinHttpProvider)),
);

/// Il titolo ha un trailer da mostrare.
final trailerAvailableProvider = FutureProvider.autoDispose
    .family<bool, TrailerSubject>(
      (ref, subject) => ref.watch(trailersApiProvider).available(subject),
    );
