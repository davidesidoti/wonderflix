import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late RequestsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = RequestsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  RequestOptions last() => adapter.requests.last;

  test('Me e ricerca', () async {
    adapter.handler = (_) => const FakeResponse(
        200, {'CanRequest': true, 'CanManage': true, 'HasAccount': false});
    final me = await api.me();
    expect(last().path, '/WonderFlixWatchParty/Requests/Me');
    expect(me.canManage, isTrue);

    adapter.handler = (_) => const FakeResponse(200, [
          {'MediaType': 'movie', 'TmdbId': 841, 'Title': 'Dune', 'Status': 'None'},
        ]);
    final titles = await api.search('dune', language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/Search');
    expect(last().queryParameters, {'query': 'dune', 'language': 'it'});
    expect(titles.single.tmdbId, 841);
  });

  test('schede, richiesta, elenchi, servizi, approva e rifiuta', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'MediaType': 'tv',
          'TmdbId': 90228,
          'Title': 'Dune: Prophecy',
          'Status': 'None',
          'Seasons': [],
        });
    await api.title(RequestMediaType.tv, 90228, language: 'en');
    expect(last().path, '/WonderFlixWatchParty/Requests/Tv/90228');
    expect(last().queryParameters, {'language': 'en'});
    await api.title(RequestMediaType.movie, 841, language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/Movie/841');

    adapter.handler = (_) => const FakeResponse(200, {'Id': 7, 'Status': 'Pending'});
    final created = await api.create(RequestMediaType.tv, 90228, seasons: [1, 2]);
    expect(last().method, 'POST');
    expect(last().path, '/WonderFlixWatchParty/Requests');
    expect(last().data, {'MediaType': 'tv', 'TmdbId': 90228, 'Seasons': [1, 2]});
    expect(created.id, 7);
    await api.create(RequestMediaType.movie, 841);
    expect(last().data, {'MediaType': 'movie', 'TmdbId': 841});

    adapter.handler = (_) => const FakeResponse(200, {'Items': [], 'HasMore': false});
    await api.list(RequestsFilter.pending, skip: 20, take: 20, language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests');
    expect(last().queryParameters,
        {'filter': 'pending', 'skip': 20, 'take': 20, 'language': 'it'});

    adapter.handler = (_) => const FakeResponse(200, []);
    await api.services(RequestMediaType.movie);
    expect(last().path, '/WonderFlixWatchParty/Requests/Services/movie');

    adapter.handler = (_) => const FakeResponse(200, {
          'Id': 53,
          'MediaType': 'movie',
          'TmdbId': 841,
          'Title': 'Dune',
          'Seasons': [],
          'RequestedBy': {'Name': 'mario', 'IsMe': false},
          'CreatedAt': '2026-10-03T20:31:16+00:00',
          'Status': 'Approved',
        });
    await api.approve(53,
        const ApproveChoice(serverId: 1, profileId: 7, rootFolder: '/media/anime'),
        language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/53/Approve');
    expect(last().data, {'ServerId': 1, 'ProfileId': 7, 'RootFolder': '/media/anime'});
    expect(last().queryParameters, {'language': 'it'});
    final declined = await api.decline(53, language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/53/Decline');
    expect(declined.title, 'Dune');
  });

  test('errori con il codice del plugin', () async {
    Future<RequestsFailure> failureOf(int status, [Object? body]) async {
      adapter.handler = (_) => FakeResponse(status, body);
      try {
        await api.me();
      } on RequestsException catch (error) {
        return error.failure;
      }
      fail('nessun errore');
    }

    expect(await failureOf(404), RequestsFailure.unavailable);
    expect(await failureOf(503, {'Code': 'NotConfigured'}), RequestsFailure.notConfigured);
    expect(await failureOf(502, {'Code': 'SeerrUnavailable'}), RequestsFailure.seerrUnavailable);
    expect(await failureOf(502, {'Code': 'SeerrAuth'}), RequestsFailure.seerrUnavailable);
    expect(await failureOf(403, {'Code': 'NoPermission'}), RequestsFailure.noPermission);
    expect(await failureOf(403, {'Code': 'QuotaExceeded'}), RequestsFailure.quotaExceeded);
    expect(await failureOf(403, {'Code': 'Blocklisted'}), RequestsFailure.blocklisted);
    expect(await failureOf(409, {'Code': 'AlreadyRequested'}), RequestsFailure.alreadyRequested);
    expect(await failureOf(409, {'Code': 'NothingToRequest'}), RequestsFailure.nothingToRequest);
    expect(await failureOf(409, {'Code': 'AccountUnavailable'}), RequestsFailure.accountUnavailable);
    expect(await failureOf(409), RequestsFailure.network);
    expect(await failureOf(400, {'Code': 'Invalid'}), RequestsFailure.invalid);
    expect(await failureOf(500), RequestsFailure.network);
    expect(await failureOf(200, ['non', 'un', 'oggetto']), RequestsFailure.network);

    adapter.handler = (_) => throw const SocketException('rete');
    await expectLater(api.me(),
        throwsA(isA<RequestsException>().having((e) => e.failure, 'failure', RequestsFailure.network)));
  });

  test('una risposta di forma inattesa è un errore di rete', () async {
    // La ricerca risponde 200 ma non con un elenco.
    adapter.handler = (_) => const FakeResponse(200, {});
    await expectLater(
        api.search('dune', language: 'it'),
        throwsA(isA<RequestsException>()
            .having((e) => e.failure, 'failure', RequestsFailure.network)));

    // Una richiesta dell'elenco senza `CreatedAt`.
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'Id': 53,
              'MediaType': 'movie',
              'TmdbId': 841,
              'Title': 'Dune',
              'Seasons': [],
              'RequestedBy': {'Name': 'mario', 'IsMe': false},
              'Status': 'Approved',
            },
          ],
          'HasMore': false,
        });
    await expectLater(
        api.list(RequestsFilter.all, skip: 0, take: 20, language: 'it'),
        throwsA(isA<RequestsException>()
            .having((e) => e.failure, 'failure', RequestsFailure.network)));
  });

  test('la ricerca salta i tipi sconosciuti', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'MediaType': 'person', 'Id': 12, 'Name': 'Timothée Chalamet'},
          {'MediaType': 'movie', 'TmdbId': 841, 'Title': 'Dune', 'Status': 'None'},
        ]);
    final titles = await api.search('dune', language: 'it');
    expect(titles.map((t) => t.tmdbId), [841]);

    // Un tipo noto ma malformato fa ancora fallire la ricerca.
    adapter.handler = (_) => const FakeResponse(200, [
          {'MediaType': 'movie', 'Title': 'Dune'},
        ]);
    await expectLater(
        api.search('dune', language: 'it'),
        throwsA(isA<RequestsException>()
            .having((e) => e.failure, 'failure', RequestsFailure.network)));
  });

  test('una ricerca annullata resta annullata', () async {
    final cancel = CancelToken()..cancel();
    await expectLater(api.search('dune', language: 'it', cancelToken: cancel),
        throwsA(isA<RequestCancelledException>()));
  });
}
