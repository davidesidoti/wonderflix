import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/reports/reports_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

/// Un `ReportDto` come lo manda il plugin.
Map<String, dynamic> reportJson({
  String id = 'r1',
  String type = 'Subtitles',
  String? note,
  String itemType = 'Episode',
}) =>
    {
      'Id': id,
      'Type': type,
      'Note': ?note,
      'CreatedAt': '2026-10-21T10:00:00+00:00',
      'UpdatedAt': '2026-10-21T10:05:00+00:00',
      'UserId': 'u1',
      'UserName': 'Mario',
      'ItemId': 'e1',
      'ItemType': itemType,
      'ItemName': 'Pilot',
      'TitleId': 's1',
      'TitleName': 'Dark',
      'SeasonNumber': 1,
      'EpisodeNumber': 2,
    };

void main() {
  late FakeAdapter adapter;
  late ReportsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = ReportsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Future<ReportsFailure> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on ReportsException catch (e) {
      return e.failure;
    }
    fail('nessuna eccezione');
  }

  test('create manda ItemId, Type e la nota, e legge il ReportDto', () async {
    adapter.handler = (_) => FakeResponse(200, reportJson(id: 'r1'));
    final report =
        await api.create(itemId: 'e1', type: ReportType.subtitles, note: 'Mancano');
    final request = adapter.requests.single;
    expect((request.method, request.path), ('POST', '/WonderFlixWatchParty/Reports'));
    expect(request.data, {'ItemId': 'e1', 'Type': 'Subtitles', 'Note': 'Mancano'});
    expect(report.id, 'r1');
    expect(report.itemType, ReportItemType.episode);
    expect(report.titleName, 'Dark');
    expect((report.seasonNumber, report.episodeNumber), (1, 2));
    expect(report.createdAt, DateTime.utc(2026, 10, 21, 10));
  });

  test('una nota vuota non si manda', () async {
    adapter.handler = (_) => FakeResponse(200, reportJson());
    await api.create(itemId: 'e1', type: ReportType.other, note: '');
    expect(adapter.requests.single.data, {'ItemId': 'e1', 'Type': 'Other'});
  });

  test('i 409 diventano limitReached e closed', () async {
    adapter.handler = (_) => FakeResponse(409, {'Reason': 'LimitReached'});
    await expectLater(
        api.create(itemId: 'e1', type: ReportType.other),
        throwsA(isA<ReportsException>()
            .having((e) => e.failure, 'failure', ReportsFailure.limitReached)));
    adapter.handler = (_) => FakeResponse(409, {'Reason': 'Closed'});
    await expectLater(
        api.resolve('r1', ReportOutcome.fixed),
        throwsA(isA<ReportsException>()
            .having((e) => e.failure, 'failure', ReportsFailure.closed)));
    adapter.handler = (_) => FakeResponse(409, {'Reason': 'Boh'});
    expect(await failure(() => api.all()), ReportsFailure.invalid);
  });

  test('404 è un plugin vecchio, 403 è il permesso, 400 non valido', () async {
    adapter.handler = (_) => const FakeResponse(404);
    expect(await failure(() => api.all()), ReportsFailure.unavailable);
    adapter.handler = (_) => const FakeResponse(403);
    expect(await failure(() => api.all()), ReportsFailure.forbidden);
    adapter.handler = (_) => const FakeResponse(401);
    expect(await failure(() => api.all()), ReportsFailure.forbidden);
    adapter.handler = (_) => const FakeResponse(400);
    expect(await failure(() => api.all()), ReportsFailure.invalid);
    adapter.handler = (_) => const FakeResponse(500);
    expect(await failure(() => api.all()), ReportsFailure.network);
  });

  test('mine e all leggono Items e saltano un tipo sconosciuto', () async {
    adapter.handler = (_) => FakeResponse(200, {
          'Items': [
            reportJson(id: 'a'),
            reportJson(id: 'b', type: 'Boh'),
            reportJson(id: 'c', type: 'Other'),
          ]
        });
    final mine = await api.mine('e1');
    var request = adapter.requests.last;
    expect((request.method, request.path),
        ('GET', '/WonderFlixWatchParty/Reports/Mine'));
    expect(request.queryParameters, {'itemId': 'e1'});
    expect(mine.map((r) => r.id), ['a', 'c']);

    final all = await api.all();
    request = adapter.requests.last;
    expect((request.method, request.path), ('GET', '/WonderFlixWatchParty/Reports'));
    expect(all.map((r) => r.id), ['a', 'c']);
  });

  test('resolve manda Outcome e Note, senza Note se vuota', () async {
    await api.resolve('r1', ReportOutcome.cannotFix, note: 'Non c\'è');
    var request = adapter.requests.last;
    expect((request.method, request.path),
        ('POST', '/WonderFlixWatchParty/Reports/r1/Resolve'));
    expect(request.data, {'Outcome': 'CannotFix', 'Note': 'Non c\'è'});

    await api.resolve('r1', ReportOutcome.fixed, note: '');
    expect(adapter.requests.last.data, {'Outcome': 'Fixed'});
    await api.resolve('r1', ReportOutcome.fixed);
    expect(adapter.requests.last.data, {'Outcome': 'Fixed'});
  });

  test('ItemType vuoto o sconosciuto: nessun tipo', () {
    expect(ItemReport.fromJson(reportJson(itemType: ''))!.itemType, isNull);
    expect(ItemReport.fromJson(reportJson(itemType: 'Boh'))!.itemType, isNull);
    expect(ReportItemType.fromWire('Season'), ReportItemType.season);
    expect(ReportType.fromWire('AudioVideo'), ReportType.audioVideo);
    expect(ReportType.fromWire(null), isNull);
    expect(ReportOutcome.fromWire('Fixed'), ReportOutcome.fixed);
    expect(ReportOutcome.fromWire('x'), isNull);
    expect(ItemReport.listFromJson('boh'), isEmpty);
  });
}
