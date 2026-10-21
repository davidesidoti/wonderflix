import 'dart:async';
import 'dart:typed_data';

import 'package:wonderflix/core/jellyfin/item_edit_api.dart';
import 'package:wonderflix/core/jellyfin/item_edit_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

/// Un item di Jellyfin come lo manda `GET /Items/{id}`: con i campi che un
/// salvataggio parziale cancellerebbe (`Tags`, `ProviderIds`, `People`…).
Map<String, dynamic> testRawItem({
  String id = 'i1',
  String name = 'Dark',
  String type = 'Series',
  String? overview = 'Una storia di viaggi nel tempo.',
  int? productionYear = 2017,
  List<String> genres = const ['Drammatico', 'Fantascienza'],
  List<String> lockedFields = const [],
  bool lockData = false,
  List<String> backdropImageTags = const ['b1'],
}) =>
    {
      'Id': id,
      'Name': name,
      'OriginalTitle': 'Dark (originale)',
      'ForcedSortName': '',
      'Type': type,
      'Overview': overview,
      'Taglines': ['Cosa sai?'],
      'ProductionYear': ?productionYear,
      'PremiereDate': '2017-12-01T00:00:00.0000000Z',
      'OfficialRating': 'TV-MA',
      'Genres': genres,
      'Tags': ['cult', 'tedesco'],
      'ProviderIds': {'Tmdb': '70523', 'Imdb': 'tt5753856'},
      'People': [
        {'Name': 'Louis Hofmann', 'Id': 'p1', 'Type': 'Actor'},
      ],
      'Studios': [
        {'Name': 'Netflix', 'Id': 's1'},
      ],
      'LockedFields': lockedFields,
      'LockData': lockData,
      'BackdropImageTags': backdropImageTags,
      'ImageTags': {'Primary': 'p1'},
      'UserData': {'Played': true, 'IsFavorite': true},
    };

/// `ItemEditApi` in memoria.
class FakeItemEditApi implements ItemEditApi {
  /// Gli item per id: risposta di [rawItem], aggiornati da [updateItem].
  final items = <String, Map<String, dynamic>>{};

  /// Chiamate in ordine: `rawItem i1`, `updateItem i1`,
  /// `applyIdentify i1 true`, `refresh i1 false true`, `remoteImages i1
  /// Primary 0 false`, `downloadImage i1 Backdrop url`,
  /// `uploadImage i1 Primary 4 image/png`, `moveBackdropFirst i1 2`,
  /// `parentalRatings i1`, `searchRemote i1 Movie nome`.
  final calls = <String>[];

  /// Errore della prossima chiamata, una volta sola.
  Object? nextFailure;

  /// Se valorizzato, ogni chiamata aspetta che si completi (dopo averla
  /// registrata).
  Completer<void>? gate;

  List<RemoteSearchResult> results = [];
  RemoteImagesPage page = const RemoteImagesPage(images: [], total: 0);
  List<ParentalRatingOption> ratings = const [
    ParentalRatingOption(name: 'Nessuna'),
    ParentalRatingOption(name: 'T', value: 0),
    ParentalRatingOption(name: 'TV-MA', value: 17),
  ];

  /// L'ultima `Map` mandata a [updateItem] (una copia).
  Map<String, dynamic>? lastUpdate;

  Future<void> _enter(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    throw failure;
  }

  @override
  Future<Map<String, dynamic>> rawItem(String userId, String itemId) async {
    await _enter('rawItem $itemId');
    final item = items[itemId];
    if (item == null) throw StateError('item $itemId non preparato');
    return Map<String, dynamic>.of(item);
  }

  @override
  Future<void> updateItem(String itemId, Map<String, dynamic> item) async {
    await _enter('updateItem $itemId');
    lastUpdate = Map<String, dynamic>.of(item);
    items[itemId] = Map<String, dynamic>.of(item);
  }

  @override
  Future<List<ParentalRatingOption>> parentalRatings(String itemId) async {
    await _enter('parentalRatings $itemId');
    return ratings;
  }

  @override
  Future<List<RemoteSearchResult>> searchRemote(
    ItemKind kind, {
    required String itemId,
    required String name,
    int? year,
    Map<String, String> providerIds = const {},
  }) async {
    await _enter('searchRemote $itemId ${kind.apiName} $name');
    return results;
  }

  @override
  Future<void> applyIdentify(String itemId, RemoteSearchResult result,
      {required bool replaceAllImages}) =>
      _enter('applyIdentify $itemId $replaceAllImages');

  @override
  Future<void> refresh(String itemId,
          {required bool replaceAllMetadata,
          required bool replaceAllImages}) =>
      _enter('refresh $itemId $replaceAllMetadata $replaceAllImages');

  @override
  Future<RemoteImagesPage> remoteImages(String itemId, EditImageType type,
      {int startIndex = 0, bool allLanguages = false}) async {
    await _enter('remoteImages $itemId ${type.apiName} $startIndex '
        '$allLanguages');
    return page;
  }

  @override
  Future<void> downloadImage(
          String itemId, EditImageType type, String imageUrl) =>
      _enter('downloadImage $itemId ${type.apiName} $imageUrl');

  @override
  Future<void> uploadImage(String itemId, EditImageType type, Uint8List bytes,
          {required String mimeType}) =>
      _enter('uploadImage $itemId ${type.apiName} ${bytes.length} $mimeType');

  @override
  Future<void> moveBackdropFirst(String itemId, int fromIndex) =>
      _enter('moveBackdropFirst $itemId $fromIndex');
}
