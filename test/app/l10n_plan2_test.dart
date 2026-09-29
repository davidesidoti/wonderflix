import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe con parametri e plurali', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.actionResumeAt('23:14'), 'Riprendi da 23:14');
    expect(it.actionPlayEpisode('S1:E5'), 'Riproduci S1:E5');
    expect(it.detailSeasons(1), '1 stagione');
    expect(it.detailSeasons(3), '3 stagioni');
    expect(it.catalogCount(250), '250 titoli');
    expect(it.searchNoResults('dune'), 'Nessun risultato per "dune"');
    expect(en.detailSeasons(2), '2 seasons');
    expect(en.settingsVersion('1.0.0'), 'Version 1.0.0');
  });
}
