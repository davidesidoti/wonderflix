import 'dart:convert';

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

  test('Prossimi episodi tolti: serie → episodio, id normalizzati', () async {
    adapter.handler = (_) => FakeResponse(
        200,
        serverPrefs({
          'nextUpHidden': 'AB-CD:EF12, s2:e2,storta,:e3',
          'homeRows': 'resume',
        }));
    expect(await api.readNextUpHidden('u1'), {'abcd': 'ef12', 's2': 'e2'});
    expect(adapter.requests.single.queryParameters,
        {'userId': 'u1', 'client': 'wonderflix'});
  });

  test('Prossimi episodi tolti: senza voce, mappa vuota', () async {
    expect(await api.readNextUpHidden('u1'), isEmpty);
  });

  test('scrivere i tolti lascia le altre voci', () async {
    adapter.handler = (options) => options.method == 'GET'
        ? FakeResponse(200, serverPrefs({'homeRows': 'myList'}))
        : const FakeResponse(204);
    await api.writeNextUpHidden('u1', {'s1': 'e1', 's2': 'e2'});
    final post = adapter.requests.last;
    expect(post.method, 'POST');
    expect(post.queryParameters, {'userId': 'u1', 'client': 'wonderflix'});
    final body = post.data as Map<String, dynamic>;
    expect(body['SortBy'], 'SortName');
    expect(body['CustomPrefs'], {
      'chromecastVersion': 'stable',
      'tvhome': null,
      'homeRows': 'myList',
      'nextUpHidden': 's1:e1,s2:e2',
    });
  });

  test('nessuna serie tolta: la voce sparisce', () async {
    adapter.handler = (options) => options.method == 'GET'
        ? FakeResponse(200, serverPrefs({'nextUpHidden': 's1:e1'}))
        : const FakeResponse(204);
    await api.writeNextUpHidden('u1', const {});
    final body = adapter.requests.last.data as Map<String, dynamic>;
    expect(body['CustomPrefs'], {'chromecastVersion': 'stable', 'tvhome': null});
  });

  test('La mia lista: date di aggiunta, id normalizzati, voci storte saltate',
      () async {
    adapter.handler = (_) => FakeResponse(
        200,
        serverPrefs({
          'myListAdded': jsonEncode({
            'AB-CD': '2026-11-01T10:00:00.000Z',
            'ef12': '2026-11-02T10:00:00+01:00',
            'storta': 'non una data',
            'numero': 5,
          }),
        }));
    expect(await api.readMyListAdded('u1'), {
      'abcd': DateTime.utc(2026, 11, 1, 10),
      'ef12': DateTime.utc(2026, 11, 2, 9),
    });
  });

  test('La mia lista: senza voce o con JSON storto, mappa vuota', () async {
    expect(await api.readMyListAdded('u1'), isEmpty);
    adapter.handler =
        (_) => FakeResponse(200, serverPrefs({'myListAdded': '{rotto'}));
    expect(await api.readMyListAdded('u1'), isEmpty);
    adapter.handler =
        (_) => FakeResponse(200, serverPrefs({'myListAdded': '[1,2]'}));
    expect(await api.readMyListAdded('u1'), isEmpty);
  });

  test('scrivere le date lascia le altre voci; vuota la toglie', () async {
    adapter.handler = (options) => options.method == 'GET'
        ? FakeResponse(
            200,
            serverPrefs({
              'homeRows': 'myList',
              'nextUpHidden': 's1:e1',
              'myListAdded': '{}',
            }))
        : const FakeResponse(204);
    await api.writeMyListAdded('u1', {'AB-CD': DateTime.utc(2026, 11, 1, 10)});
    var custom = (adapter.requests.last.data
        as Map<String, dynamic>)['CustomPrefs'] as Map<String, dynamic>;
    expect(custom['homeRows'], 'myList');
    expect(custom['nextUpHidden'], 's1:e1');
    expect(jsonDecode(custom['myListAdded'] as String),
        {'abcd': '2026-11-01T10:00:00.000Z'});
    await api.writeMyListAdded('u1', const {});
    custom = (adapter.requests.last.data
        as Map<String, dynamic>)['CustomPrefs'] as Map<String, dynamic>;
    expect(custom.containsKey('myListAdded'), isFalse);
    expect(custom['homeRows'], 'myList');
    expect(custom['nextUpHidden'], 's1:e1');
  });

  /// Un server che tiene l'oggetto: GET lo dà più tardi, POST lo sostituisce
  /// (con [failPosts] POST che falliscono, i primi).
  void storing({int failPosts = 0}) {
    var stored = serverPrefs();
    adapter.handler = (options) async {
      await Future<void>.delayed(Duration.zero);
      if (options.method == 'GET') return FakeResponse(200, stored);
      if (failPosts > 0) {
        failPosts--;
        return const FakeResponse(500);
      }
      stored = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
      return const FakeResponse(204);
    };
  }

  Map<String, dynamic> storedCustom() =>
      (adapter.requests.lastWhere((r) => r.method == 'POST').data
          as Map<String, dynamic>)['CustomPrefs'] as Map<String, dynamic>;

  // Review m5: due scritture insieme leggevano lo stesso oggetto, e l'ultima
  // cancellava la voce dell'altra.
  test('due scritture insieme: una dopo l\'altra, restano tutte e due', () async {
    storing();
    await Future.wait([
      api.writeMyListAdded('u1', {'a': DateTime.utc(2026, 11, 1)}),
      api.writeNextUpHidden('u1', {'s1': 'e1'}),
      api.writeHome('u1', const HomeUserPrefs(rows: ['myList'])),
    ]);
    expect(
      [for (final r in adapter.requests) r.method],
      ['GET', 'POST', 'GET', 'POST', 'GET', 'POST'],
    );
    final custom = storedCustom();
    expect(custom['myListAdded'], isNotNull);
    expect(custom['nextUpHidden'], 's1:e1');
    expect(custom['homeRows'], 'myList');
  });

  test('una scrittura fallita non ferma quella dopo', () async {
    storing(failPosts: 1);
    final first = api.writeNextUpHidden('u1', {'s1': 'e1'});
    final second = api.writeHome('u1', const HomeUserPrefs(rows: ['myList']));
    await expectLater(first, throwsA(isA<ApiException>()));
    await second;
    expect(storedCustom()['homeRows'], 'myList');
  });

  test('un errore di Jellyfin arriva a chi chiama', () async {
    adapter.handler = (_) => const FakeResponse(401);
    await expectLater(api.readHome('u1'), throwsA(isA<ApiException>()));
  });
}
