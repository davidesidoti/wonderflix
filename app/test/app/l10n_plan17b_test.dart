import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 17b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.profilesTitle, 'Chi guarda?');
    expect(it.profilesAdd, 'Aggiungi profilo');
    expect(it.profilesManage, 'Gestisci profili');
    expect(it.profilesDone, 'Fine');
    expect(it.profilesSignInAgain, 'Accedi di nuovo');
    expect(it.profilesRemove, 'Rimuovi');
    expect(it.profilesRemoveTitle('Luigi', 'pc'), 'Rimuovere Luigi da questo PC?');
    expect(it.profilesRemoveBody, 'Per usarlo di nuovo servirà l\'accesso.');
    expect(it.profilesLimit, 'Massimo 5 profili');
    expect(it.profilesCancel, 'Annulla');
    expect(it.profilesSwitch, 'Cambia profilo');
    expect(it.profilesSwitchLeavesParty, 'Uscirai dal watch party.');
    expect(it.profilesEdit, 'Modifica');
    expect(it.profilesEditNamed('Luigi'), 'Modifica Luigi');
    expect(it.profilesRemoveNamed('Luigi'), 'Rimuovi Luigi');
    expect(it.profilesUnnamed, 'Profilo');
    expect(en.profilesTitle, 'Who\'s watching?');
    expect(en.profilesRemoveTitle('Luigi', 'pc'), 'Remove Luigi from this PC?');
    expect(en.profilesSwitch, 'Switch profile');
    expect(en.profilesEdit, 'Edit');
    expect(en.profilesEditNamed('Luigi'), 'Edit Luigi');
    expect(en.profilesRemoveNamed('Luigi'), 'Remove Luigi');
    expect(en.profilesUnnamed, 'Profile');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.profilesTitle,
        l.profilesAdd,
        l.profilesManage,
        l.profilesDone,
        l.profilesSignInAgain,
        l.profilesRemove,
        l.profilesRemoveBody,
        l.profilesLimit,
        l.profilesCancel,
        l.profilesSwitch,
        l.profilesSwitchLeavesParty,
        l.profilesEdit,
        l.profilesEditNamed('Luigi'),
        l.profilesRemoveNamed('Luigi'),
        l.profilesUnnamed,
      ], everyElement(isNotEmpty));
    }
  });

  test('i testi nominano il dispositivo', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.profilesRemoveTitle('Luigi', 'pc'), 'Rimuovere Luigi da questo PC?');
    expect(it.profilesRemoveTitle('Luigi', 'tv'), 'Rimuovere Luigi da questa TV?');
    expect(it.profilesRemoveTitle('Luigi', 'browser'),
        'Rimuovere Luigi da questo browser?');
    expect(it.profilesRemoveTitle('Luigi', 'phone'),
        'Rimuovere Luigi da questo telefono?');
    expect(it.profilesCount(4, 5, 'pc'), '4 profili su 5 su questo PC');
    expect(it.profilesCount(1, 5, 'tv'), '1 profilo su 5 su questa TV');
    expect(it.profilesFull(5, 'tv'),
        '5 profili su questa TV: rimuovine uno per aggiungerne un altro.');
    expect(en.profilesRemoveTitle('Luigi', 'phone'),
        'Remove Luigi from this phone?');
    expect(en.profilesCount(1, 5, 'browser'), '1 of 5 profiles on this browser');
    expect(en.profilesFull(5, 'tv'),
        '5 profiles on this TV: remove one to add another.');
  });
}
