import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 15a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.requestsSectionTitle, 'Da richiedere');
    expect(it.requestsSectionSubtitle, 'Non sono ancora su WonderFlix');
    expect(it.requestsSeerrDown, 'Seerr non risponde');
    expect(it.requestsBadgeOnWonderflix, 'Su WonderFlix');
    expect(it.requestsRequestSeasons(1), 'Richiedi 1 stagione');
    expect(it.requestsRequestSeasons(3), 'Richiedi 3 stagioni');
    expect(it.requestsSeasonLine(2, 1), 'Stagione 2 · 1 episodio');
    expect(it.requestsSeasonLine(1, 8), 'Stagione 1 · 8 episodi');
    expect(it.requestsAlreadyRequested, "Qualcuno l'ha già chiesto");
    expect(en.requestsSectionTitle, 'Available to request');
    expect(en.requestsRequestSeasons(1), 'Request 1 season');
    expect(en.requestsRequestSeasons(3), 'Request 3 seasons');
    expect(en.requestsSeasonLine(1, 8), 'Season 1 · 8 episodes');
    expect(en.requestsQuota, "You've reached your request limit");
  });
}
