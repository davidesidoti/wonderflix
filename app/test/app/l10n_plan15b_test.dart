import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 15b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.navRequests, 'Richieste');
    expect(it.requestsTabPendingCount('3'), 'Da approvare (3)');
    expect(it.requestsSeasonsList(1, '2'), 'Stagione 2');
    expect(it.requestsSeasonsList(2, '1–2'), 'Stagioni 1–2');
    expect(it.requestsStatusDownloading(45), 'In arrivo · 45%');
    expect(it.requestsRequestedBy('Garg'), 'chiesto da Garg');
    expect(it.requestsApproveTitle('Dune'), 'Approva: Dune');
    expect(it.requestsServerDefault('Radarr'), 'Predefinito (Radarr)');
    expect(it.inboxRequestAvailable('Dune (2021)'), 'Ora disponibile: Dune (2021)');
    expect(it.inboxRequestPending('Garg', 'Dune (2021)'), 'Garg ha chiesto Dune (2021)');
    expect(it.requestsWorking, 'Operazione in corso');
    expect(it.requestsDeclineConfirmLabel, 'Conferma il rifiuto');
    expect(it.inboxRequestPendingNoName('Dune (2021)'), 'Nuova richiesta: Dune (2021)');
    expect(it.inboxRequestTitleSeasons('Brothers (2026)', 2, '1–2'),
        'Brothers (2026), stagioni 1–2');
    expect(it.inboxRequestTitleSeasons('Brothers (2026)', 1, '3'),
        'Brothers (2026), stagione 3');
    expect(en.navRequests, 'Requests');
    expect(en.requestsTabPendingCount('50+'), 'To approve (50+)');
    expect(en.requestsSeasonsList(2, '1–2'), 'Seasons 1–2');
    expect(en.inboxRequestPending('Garg', 'Dune'), 'Garg requested Dune');
    expect(en.requestsWorking, 'Working on it');
    expect(en.requestsDeclineConfirmLabel, 'Confirm decline');
    expect(en.inboxRequestPendingNoName('Dune'), 'New request: Dune');
    expect(en.requestsEmptyMine,
        "You haven't requested anything yet. Search for a missing title and press Request.");
  });
}
