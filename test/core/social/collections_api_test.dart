import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/collections_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late CollectionsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'Collections': []}));
    api = CollectionsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('legge le saghe con i loro titoli', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Collections': [
            {
              'Id': 'c1',
              'Name': 'Matrix - Collezione',
              'SortName': 'matrix - collezione',
              'PrimaryImageTag': 't1',
              // Il formato che Jellyfin scrive davvero: sette cifre decimali.
              'DateCreated': '2026-05-01T10:00:00.0000000Z',
              'ItemIds': ['m1', 'm2', 'm3'],
            },
          ],
        });
    final saga = (await api.collections()).single;
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Collections');
    expect(saga.id, 'c1');
    expect(saga.name, 'Matrix - Collezione');
    expect(saga.sortName, 'matrix - collezione');
    expect(saga.primaryImageTag, 't1');
    expect(saga.dateCreated, DateTime.utc(2026, 5, 1, 10));
    expect(saga.itemIds, ['m1', 'm2', 'm3']);
    expect(saga.size, 3);
  });

  test('letture tolleranti: senza Id la voce si scarta, il resto ha dei valori di partenza',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Collections': [
            {'Name': 'Senza id', 'ItemIds': ['m1']},
            'non un oggetto',
            // Tag nullo scritto in modo esplicito.
            {'Id': 'c2', 'Name': 'Alien', 'PrimaryImageTag': null, 'ItemIds': 5},
            // Jellyfin omette i campi nulli: qui manca la chiave del tag.
            {
              'Id': 'c3',
              'Name': 'Dune',
              'DateCreated': '2026-05-01T10:00:00.0000000Z',
              'ItemIds': ['m4'],
            },
          ],
        });
    final sagas = await api.collections();
    expect(sagas.map((saga) => saga.id), ['c2', 'c3']);

    final alien = sagas.first;
    expect(alien.sortName, 'alien');
    expect(alien.primaryImageTag, isNull);
    expect(alien.dateCreated, isNull);
    expect(alien.itemIds, isEmpty);

    final dune = sagas.last;
    expect(dune.sortName, 'dune');
    expect(dune.primaryImageTag, isNull);
    expect(dune.dateCreated, DateTime.utc(2026, 5, 1, 10));
    expect(dune.itemIds, ['m4']);
  });

  test('corpo di forma inattesa: errore del server', () async {
    adapter.handler = (_) => const FakeResponse(200, ['no']);
    await expectLater(api.collections(), throwsA(isA<ServerErrorException>()));
    adapter.handler = (_) => const FakeResponse(200, {'Collections': 'no'});
    await expectLater(api.collections(), throwsA(isA<ServerErrorException>()));
  });

  test('plugin senza l\'endpoint: 404', () async {
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(api.collections(), throwsA(isA<NotFoundException>()));
  });
}
