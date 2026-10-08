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
    expect(it.profilesRemoveTitle('Luigi'), 'Rimuovere Luigi da questo PC?');
    expect(it.profilesRemoveBody, 'Per usarlo di nuovo servirà l\'accesso.');
    expect(it.profilesLimit, 'Massimo 5 profili');
    expect(it.profilesCancel, 'Annulla');
    expect(it.profilesSwitch, 'Cambia profilo');
    expect(it.profilesSwitchLeavesParty, 'Uscirai dal watch party.');
    expect(en.profilesTitle, 'Who\'s watching?');
    expect(en.profilesRemoveTitle('Luigi'), 'Remove Luigi from this PC?');
    expect(en.profilesSwitch, 'Switch profile');

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
      ], everyElement(isNotEmpty));
    }
  });
}
