import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

/// Le DisplayPreferences mai salvate come le dà Jellyfin 10.11.9 (2026-10-10).
Map<String, dynamic> serverPrefs([Map<String, dynamic>? extra]) => {
      'Id': 'd0c1a2b3',
      'SortBy': 'SortName',
      'RememberIndexing': false,
      'PrimaryImageHeight': 250,
      'PrimaryImageWidth': 250,
      'CustomPrefs': {
        'chromecastVersion': 'stable',
        'tvhome': null,
        ...?extra,
      },
      'ScrollDirection': 'Horizontal',
      'ShowBackdrop': true,
      'RememberSorting': false,
      'SortOrder': 'Ascending',
      'ShowSidebar': false,
      'Client': 'wonderflix',
    };

void main() {
  late FakeAdapter adapter;
  late DisplayPreferencesApi api;

  setUp(() {
    adapter = FakeAdapter((_) => FakeResponse(200, serverPrefs()));
    api = DisplayPreferencesApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('leggere: id, utente e client; senza voci nessun ritocco', () async {
    final prefs = await api.readHome('u1');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/DisplayPreferences/wonderflix-home');
    expect(request.queryParameters, {'userId': 'u1', 'client': 'wonderflix'});
    expect(prefs.isEmpty, isTrue);
  });

  test('leggere: ordine e nascoste, senza spazi e voci vuote', () async {
    adapter.handler = (_) => FakeResponse(
        200,
        serverPrefs(
            {'homeRows': 'myList, resume,,nextUp', 'homeHidden': 'requests'}));
    final prefs = await api.readHome('u1');
    expect(prefs.rows, ['myList', 'resume', 'nextUp']);
    expect(prefs.hidden, ['requests']);
  });

  test('scrivere conserva il resto dell\'oggetto, anche i valori nulli',
      () async {
    await api.writeHome('u1',
        const HomeUserPrefs(rows: ['resume', 'myList'], hidden: <String>[]));
    final post = adapter.requests.last;
    expect(post.method, 'POST');
    expect(post.path, '/DisplayPreferences/wonderflix-home');
    expect(post.queryParameters, {'userId': 'u1', 'client': 'wonderflix'});
    final body = post.data as Map<String, dynamic>;
    expect(body['SortBy'], 'SortName');
    expect(body['ShowSidebar'], false);
    expect(body['CustomPrefs'], {
      'chromecastVersion': 'stable',
      'tvhome': null,
      'homeRows': 'resume,myList',
      'homeHidden': '',
    });
  });

  test('ripristinare toglie solo le due voci', () async {
    adapter.handler = (options) => options.method == 'GET'
        ? FakeResponse(200,
            serverPrefs({'homeRows': 'myList', 'homeHidden': 'resume'}))
        : const FakeResponse(204);
    await api.resetHome('u1');
    final body = adapter.requests.last.data as Map<String, dynamic>;
    expect(body['CustomPrefs'], {'chromecastVersion': 'stable', 'tvhome': null});
  });

  test('un errore di Jellyfin arriva a chi chiama', () async {
    adapter.handler = (_) => const FakeResponse(401);
    await expectLater(api.readHome('u1'), throwsA(isA<ApiException>()));
  });
}
