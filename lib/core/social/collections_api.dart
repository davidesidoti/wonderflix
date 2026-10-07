import '../jellyfin/json_fields.dart';
import '../jellyfin/jellyfin_http.dart';
import 'collections_models.dart';

/// L'elenco delle saghe del plugin (spec K §7.1). Gli errori sono
/// `ApiException`; un corpo di forma inattesa è `ServerErrorException`.
class CollectionsApi {
  CollectionsApi(this._http);

  final JellyfinHttp _http;

  static const _path = '/WonderFlixWatchParty/Collections';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  Future<List<CollectionSummary>> collections() async {
    final json = asJsonMap(await _http.get(_path, quietStatuses: _quiet));
    return jsonList(json['Collections'], CollectionSummary.fromJson);
  }
}
