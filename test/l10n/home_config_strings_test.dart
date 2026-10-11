import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('i testi della configurazione della Home (spec M §10)', () {
    expect(it.homeCustomize, 'Personalizza la Home');
    expect(en.homeCustomize, 'Customize Home');
    expect(it.settingsHome, 'Home');
    expect(it.homeRowsBecauseYouWatched, 'Perché hai visto…');
    expect(en.homeRowsBecauseYouWatched, 'Because you watched…');
    expect(it.homeRowsSourceSonarr, 'da Sonarr');
    expect(en.homeRowsMoveDown, 'Move down');
    expect(it.homeRowsReset, 'Ripristina la Home predefinita');
    expect(it.homeRowsSaveFailed, 'Non salvato, riprova');
    expect(it.homeRowsAllPcs, 'Vale per questo account su tutti i PC.');
    expect(it.homeRowUnavailableSeerr, 'Collega il tuo account a Seerr');
    expect(en.homeRowUnavailableSagas, 'Needs plugin 1.5.0');
  });

  test('i testi delle card dell\'admin', () {
    expect(it.adminHomeTitle, 'Home per tutti');
    expect(it.adminHomeResetConfirm, 'Tornare alla Home predefinita per tutti?');
    expect(it.adminNeedsPlugin170, 'Serve il plugin 1.7.0');
    expect(it.adminArrTitle, 'Sonarr e Radarr');
    expect(it.adminArrOk('4.0.20'), 'Collegato (versione 4.0.20)');
    expect(en.adminArrOk('4.0.20'), 'Connected (version 4.0.20)');
    expect(it.adminArrUnreachable, "Non raggiungibile: controlla l'indirizzo");
  });

  test('i testi di "Cosa guardo stasera?"', () {
    expect(it.tonightButton, 'Cosa guardo stasera?');
    expect(en.tonightButton, 'What should I watch tonight?');
    expect(it.tonightTypeBoth, 'Entrambi');
    expect(it.tonightDuration90, 'Meno di 90 min');
    expect(en.tonightDuration120, 'Under 2 h');
    expect(it.tonightAnother, 'Un altro');
    expect(it.tonightEmpty, 'Nessun titolo con questi filtri');
    expect(it.tonightClearFilters, 'Togli i filtri');
  });
}
