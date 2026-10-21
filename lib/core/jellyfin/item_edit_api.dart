import 'dart:convert';
import 'dart:typed_data';

import 'api_exception.dart';
import 'item_edit_models.dart';
import 'item_models.dart';
import 'jellyfin_http.dart';

/// Quanto aspetta la risposta di `Apply`: Jellyfin fa un aggiornamento
/// completo prima di rispondere, e dai provider può volerci qualche minuto.
const identifyApplyTimeout = Duration(minutes: 3);

/// Quante immagini dei provider si chiedono alla volta.
const remoteImagesPageSize = 30;

/// Le chiamate da admin di Jellyfin per modificare un titolo (Spec R §7.8–7.11).
/// Gli errori sono [ApiException] così come arrivano: 403 per chi non è admin.
class ItemEditApi {
  ItemEditApi(this._http);

  final JellyfinHttp _http;

  /// Esiti attesi: richiesta non valida, non admin, titolo sparito. Nel log
  /// come info.
  static const quietStatuses = {400, 403, 404};

  /// L'item come lo manda Jellyfin: la finestra cambia solo le chiavi dei
  /// campi modificati e rimanda la `Map` intera, perché `UpdateItem` riscrive
  /// anche `Tags`, `People`, `ProviderIds`… e una `Map` parziale li cancella.
  Future<Map<String, dynamic>> rawItem(String userId, String itemId) async =>
      asJsonMap(await _http.get('/Items/$itemId',
          query: {'userId': userId}, quietStatuses: quietStatuses));

  Future<void> updateItem(String itemId, Map<String, dynamic> item) async {
    await _http.post('/Items/$itemId',
        body: item, quietStatuses: quietStatuses);
  }

  Future<List<ParentalRatingOption>> parentalRatings(String itemId) async {
    final json = asJsonMap(await _http.get('/Items/$itemId/MetadataEditor',
        quietStatuses: quietStatuses));
    final raw = json['ParentalRatingOptions'];
    if (raw is! List) return const [];
    return [
      for (final option in raw)
        parseJson(option, ParentalRatingOption.fromJson),
    ];
  }

  /// Cerca il titolo nei provider; [kind] è `Movie` o `Series`. Gli id vuoti
  /// non si mandano.
  Future<List<RemoteSearchResult>> searchRemote(
    ItemKind kind, {
    required String itemId,
    required String name,
    int? year,
    Map<String, String> providerIds = const {},
  }) async {
    final json = await _http.post(
        '/Items/RemoteSearch/${kind == ItemKind.series ? 'Series' : 'Movie'}',
        body: {
          'SearchInfo': {
            'Name': name,
            'Year': ?year,
            'ProviderIds': {
              for (final e in providerIds.entries)
                if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
            },
          },
          'ItemId': itemId,
          'IncludeDisabledProviders': false,
        },
        quietStatuses: quietStatuses);
    if (json is! List) throw const ServerErrorException(null);
    return [for (final raw in json) parseJson(raw, RemoteSearchResult.fromJson)];
  }

  /// Applica il risultato scelto, rimandato così com'è. Risponde dopo
  /// l'aggiornamento completo: timeout lungo.
  Future<void> applyIdentify(String itemId, RemoteSearchResult result,
      {required bool replaceAllImages}) async {
    await _http.post('/Items/RemoteSearch/Apply/$itemId',
        body: result.raw,
        query: {'replaceAllImages': replaceAllImages},
        receiveTimeout: identifyApplyTimeout,
        quietStatuses: quietStatuses);
  }

  Future<void> refresh(String itemId,
      {required bool replaceAllMetadata, required bool replaceAllImages}) async {
    await _http.post('/Items/$itemId/Refresh',
        query: {
          'metadataRefreshMode': 'FullRefresh',
          'imageRefreshMode': 'FullRefresh',
          'replaceAllMetadata': replaceAllMetadata,
          'replaceAllImages': replaceAllImages,
        },
        quietStatuses: quietStatuses);
  }

  Future<RemoteImagesPage> remoteImages(String itemId, EditImageType type,
          {int startIndex = 0, bool allLanguages = false}) async =>
      parseJson(
          await _http.get('/Items/$itemId/RemoteImages',
              query: {
                'type': type.apiName,
                'startIndex': startIndex,
                'limit': remoteImagesPageSize,
                'includeAllLanguages': allLanguages,
              },
              quietStatuses: quietStatuses),
          RemoteImagesPage.fromJson);

  Future<void> downloadImage(
      String itemId, EditImageType type, String imageUrl) async {
    await _http.post('/Items/$itemId/RemoteImages/Download',
        query: {'type': type.apiName, 'imageUrl': imageUrl},
        quietStatuses: quietStatuses);
  }

  /// Jellyfin vuole il corpo in base64, come testo.
  Future<void> uploadImage(String itemId, EditImageType type, Uint8List bytes,
      {required String mimeType}) async {
    await _http.post('/Items/$itemId/Images/${type.apiName}',
        body: base64Encode(bytes),
        contentType: mimeType,
        quietStatuses: quietStatuses);
  }

  /// Porta lo sfondo [fromIndex] in prima posizione.
  Future<void> moveBackdropFirst(String itemId, int fromIndex) async {
    await _http.post('/Items/$itemId/Images/Backdrop/$fromIndex/Index',
        query: {'newIndex': 0}, quietStatuses: quietStatuses);
  }
}
