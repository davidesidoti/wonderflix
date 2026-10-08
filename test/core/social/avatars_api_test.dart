import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/avatars_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AvatarsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'Users': []}));
    api = AvatarsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('chiede id e nomi separati da virgole', () async {
    await api.avatars(ids: ['u1', 'u2'], names: ['mario']);

    final request = adapter.requests.single;
    expect(request.path, '/WonderFlixWatchParty/Users/Avatars');
    expect(request.queryParameters, {'ids': 'u1,u2', 'names': 'mario'});

    await api.avatars(names: ['luigi']);
    expect(adapter.requests.last.queryParameters, {'names': 'luigi'});
  });

  test('letture tolleranti: id senza trattini, tag assente, voci rotte saltate',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Users': [
            {'UserId': 'AB-CD', 'Name': 'Mario', 'ImageTag': 't1'},
            {'UserId': 'ef01', 'Name': 'Luigi'},
            {'Name': 'senza id'},
            'non un oggetto',
          ]
        });

    final users = await api.avatars(ids: ['abcd']);

    expect(users.map((user) => user.userId), ['abcd', 'ef01']);
    expect(users[0].name, 'Mario');
    expect(users[0].imageTag, 't1');
    expect(users[1].imageTag, isNull);
  });

  test('corpo di forma inattesa; plugin assente', () async {
    adapter.handler = (_) => const FakeResponse(200, ['x']);
    await expectLater(
        api.avatars(ids: ['u1']), throwsA(isA<ServerErrorException>()));

    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(
        api.avatars(ids: ['u1']), throwsA(isA<NotFoundException>()));
  });
}
