import '../jellyfin/jellyfin_http.dart';
import '../jellyfin/json_fields.dart';

/// Un utente con il tag della sua immagine (spec K §7.2).
class UserAvatarInfo {
  const UserAvatarInfo({required this.userId, required this.name, this.imageTag});

  /// `null` senza `UserId`.
  static UserAvatarInfo? fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'UserId');
    if (id == null) return null;
    return UserAvatarInfo(
      userId: jellyfinIdKey(id),
      name: jsonString(json, 'Name') ?? '',
      imageTag: jsonString(json, 'ImageTag'),
    );
  }

  /// Senza trattini e in minuscolo ([jellyfinIdKey]).
  final String userId;
  final String name;

  /// `null` senza immagine (sul server vero il campo manca).
  final String? imageTag;
}

/// I tag delle immagini degli utenti chiesti, dal plugin (spec K §7.2). Gli
/// errori sono `ApiException`; un corpo di forma inattesa è
/// `ServerErrorException`.
class AvatarsApi {
  AvatarsApi(this._http);

  final JellyfinHttp _http;

  static const _path = '/WonderFlixWatchParty/Users/Avatars';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  /// Voci al massimo per chiamata, sommando id e nomi (oltre, il plugin
  /// risponde 400).
  static const maxEntries = 100;

  Future<List<UserAvatarInfo>> avatars({
    Iterable<String> ids = const [],
    Iterable<String> names = const [],
  }) async {
    final json = asJsonMap(await _http.get(_path,
        query: {
          if (ids.isNotEmpty) 'ids': ids.join(','),
          if (names.isNotEmpty) 'names': names.join(','),
        },
        quietStatuses: _quiet));
    return jsonList(json['Users'], UserAvatarInfo.fromJson);
  }
}
