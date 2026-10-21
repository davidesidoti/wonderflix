import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_edit_api.dart';
import 'package:wonderflix/core/jellyfin/item_edit_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late ItemEditApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = ItemEditApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('rawItem e updateItem: la Map torna identica', () async {
    final item = {
      'Id': 'i1',
      'Name': 'Dark',
      'Tags': ['a'],
      'ProviderIds': {'Tmdb': '1'},
      'Unknown': {'x': 1},
    };
    adapter.handler = (_) => FakeResponse(200, item);
    final raw = await api.rawItem('u1', 'i1');
    var request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/Items/i1');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(raw, item);

    adapter.handler = (_) => const FakeResponse(204);
    await api.updateItem('i1', raw);
    request = adapter.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/Items/i1');
    expect(request.data,
        {'Id': 'i1', 'Name': 'Dark', 'Tags': ['a'], 'ProviderIds': {'Tmdb': '1'}});
  });

  test('updateItem manda solo i campi che Jellyfin rilegge, come jellyfin-web',
      () async {
    // Trickplay arriva in lettura ma il server non lo sa rileggere (500).
    final item = <String, dynamic>{
      'Id': 'i1',
      'Type': 'Movie',
      'Name': 'Dark',
      'OriginalTitle': 'Dunkel',
      'People': [
        {'Name': 'A', 'Role': 'X', 'Type': 'Actor'},
      ],
      'Studios': [
        {'Name': 'S', 'Id': 's1'},
      ],
      'LockedFields': ['Name'],
      'LockData': false,
      'RunTimeTicks': 100,
      'Trickplay': {'x': {}},
      'MediaSources': [{}],
      'UserData': {'Played': true},
      'ImageTags': {'Primary': 't'},
    };
    adapter.handler = (_) => const FakeResponse(204);
    await api.updateItem('i1', item);
    expect(adapter.requests.single.data, {
      'Id': 'i1',
      'Name': 'Dark',
      'OriginalTitle': 'Dunkel',
      'People': item['People'],
      'Studios': item['Studios'],
      'LockedFields': ['Name'],
      'LockData': false,
      'Tags': <String>[],
      'ProviderIds': <String, dynamic>{},
    });
  });

  test('updateItem: RunTimeTicks solo per le serie', () async {
    adapter.handler = (_) => const FakeResponse(204);
    await api.updateItem('s1', {'Id': 's1', 'Type': 'Series', 'RunTimeTicks': 5});
    expect((adapter.requests.single.data as Map)['RunTimeTicks'], 5);
  });

  test('parentalRatings legge il menu del MetadataEditor', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'ParentalRatingOptions': [
            {'Name': 'Nessuna'},
            {'Name': 'T', 'Value': 1},
          ],
        });
    final ratings = await api.parentalRatings('i1');
    expect(adapter.requests.single.path, '/Items/i1/MetadataEditor');
    expect(ratings.map((r) => r.name), ['Nessuna', 'T']);
    expect(ratings.first.value, isNull);
  });

  test('searchRemote: Movie o Series e corpo con i soli id non vuoti',
      () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {
            'Name': 'Dark',
            'ProductionYear': 2017,
            'ProviderIds': {'Tmdb': '70523'},
            'ImageUrl': 'https://img/x.jpg',
            'SearchProviderName': 'TheMovieDb',
            'Overview': 'Trama',
          },
        ]);
    final results = await api.searchRemote(ItemKind.series,
        itemId: 'i1',
        name: 'Dark',
        year: 2017,
        providerIds: {'Tmdb': '70523', 'Imdb': '', 'Tvdb': ' '});
    var request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/RemoteSearch/Series');
    expect(request.data, {
      'SearchInfo': {
        'Name': 'Dark',
        'Year': 2017,
        'ProviderIds': {'Tmdb': '70523'},
      },
      'ItemId': 'i1',
      'IncludeDisabledProviders': false,
    });
    expect(results.single.name, 'Dark');
    expect(results.single.year, 2017);
    expect(results.single.provider, 'TheMovieDb');
    expect(results.single.raw['ProviderIds'], {'Tmdb': '70523'});

    await api.searchRemote(ItemKind.movie, itemId: 'i2', name: 'Heat');
    request = adapter.requests.last;
    expect(request.path, '/Items/RemoteSearch/Movie');
    expect(request.data['SearchInfo'], {'Name': 'Heat', 'ProviderIds': {}});
  });

  test('applyIdentify manda il risultato grezzo e replaceAllImages',
      () async {
    final result = RemoteSearchResult.fromJson({
      'Name': 'Dark',
      'ProviderIds': {'Tmdb': '1'},
      'Extra': 5,
    });
    await api.applyIdentify('i1', result, replaceAllImages: true);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/RemoteSearch/Apply/i1');
    expect(request.queryParameters, {'replaceAllImages': true});
    expect(request.data, result.raw);
    expect(request.receiveTimeout, identifyApplyTimeout);
  });

  test('refresh con le query giuste per le due scelte', () async {
    await api.refresh('i1', replaceAllMetadata: false, replaceAllImages: false);
    var request = adapter.requests.last;
    expect(request.method, 'POST');
    expect(request.path, '/Items/i1/Refresh');
    expect(request.queryParameters, {
      'metadataRefreshMode': 'FullRefresh',
      'imageRefreshMode': 'FullRefresh',
      'replaceAllMetadata': false,
      'replaceAllImages': false,
    });

    await api.refresh('i1', replaceAllMetadata: true, replaceAllImages: true);
    request = adapter.requests.last;
    expect(request.queryParameters['replaceAllMetadata'], true);
    expect(request.queryParameters['replaceAllImages'], true);
  });

  test('remoteImages con type, startIndex, limit 30 e includeAllLanguages',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Images': [
            {
              'ProviderName': 'TheMovieDb',
              'Url': 'https://img/a.jpg',
              'ThumbnailUrl': 'https://img/t.jpg',
              'Width': 1000,
              'Height': 1500,
              'Language': 'it',
              'CommunityRating': 5.5,
              'Type': 'Primary',
            },
          ],
          'TotalRecordCount': 61,
        });
    final page = await api.remoteImages('i1', EditImageType.backdrop,
        startIndex: 30, allLanguages: true);
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/Items/i1/RemoteImages');
    expect(request.queryParameters, {
      'type': 'Backdrop',
      'startIndex': 30,
      'limit': remoteImagesPageSize,
      'includeAllLanguages': true,
    });
    expect(remoteImagesPageSize, 30);
    expect(page.total, 61);
    final image = page.images.single;
    expect(image.url, 'https://img/a.jpg');
    expect(image.provider, 'TheMovieDb');
    expect(image.thumbnailUrl, 'https://img/t.jpg');
    expect(image.width, 1000);
    expect(image.height, 1500);
    expect(image.language, 'it');
    expect(image.rating, 5.5);
  });

  test('downloadImage manda type e imageUrl', () async {
    await api.downloadImage('i1', EditImageType.primary, 'https://img/a.jpg');
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/i1/RemoteImages/Download');
    expect(request.queryParameters,
        {'type': 'Primary', 'imageUrl': 'https://img/a.jpg'});
  });

  test('uploadImage manda base64 con il content type', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 250]);
    await api.uploadImage('i1', EditImageType.primary, bytes,
        mimeType: 'image/png');
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/i1/Images/Primary');
    expect(request.data, base64Encode(bytes));
    expect(request.contentType, 'image/png');
  });

  test('moveBackdropFirst chiama Index con newIndex=0', () async {
    await api.moveBackdropFirst('i1', 2);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Items/i1/Images/Backdrop/2/Index');
    expect(request.queryParameters, {'newIndex': 0});
  });
}
