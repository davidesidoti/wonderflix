import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/activity_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';

import '../../support/admin_json.dart';

void main() {
  test('una pagina del registro', () {
    final page = parseActivityPage(activityJson);

    expect(page.total, 12134);
    expect(page.items.map((e) => e.id), [12134, 12130, 12125, 11950, 11904]);

    final session = page.items[0];
    expect(session.name, 'anna si è disconnesso da FireTV Soggiorno');
    expect(session.shortOverview, 'Indirizzo IP: 203.0.113.7');
    expect(session.type, 'SessionEnded');
    expect(session.userId, '6a48860fd4d94124b1890173d68c9de3');
    expect(session.itemId, isNull);
    expect(session.date, DateTime.parse('2026-10-06T03:39:07.114171Z'));
    expect(session.severity, ActivitySeverity.info);

    expect(page.items[1].itemId, 'e1');
    expect(page.items[2].userId, isNull, reason: 'id di soli zeri');
    expect(page.items[3].severity, ActivitySeverity.warning);
    expect(page.items[4].severity, ActivitySeverity.error);
    expect(page.items[4].overview, 'Nome utente o password non validi.');
  });

  test('voci strane e corpi sbagliati', () {
    final page = parseActivityPage({
      'Items': [
        {'Name': 'senza id'},
        {'Id': 7, 'Severity': 'Critical', 'ItemId': '00000000000000000000000000000000'},
      ],
    });

    expect(page.items.single.id, 7);
    expect(page.items.single.name, '');
    expect(page.items.single.severity, ActivitySeverity.error);
    expect(page.items.single.itemId, isNull);
    expect(page.total, 1, reason: 'senza TotalRecordCount, le voci lette');
    expect(() => parseActivityPage(<Object>[]),
        throwsA(isA<ServerErrorException>()));
    expect(() => parseActivityPage({'TotalRecordCount': 3}),
        throwsA(isA<ServerErrorException>()));
  });
}
