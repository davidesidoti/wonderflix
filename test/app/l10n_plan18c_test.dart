import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 18c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.adminTabUsers, 'Utenti');
    expect(it.adminUsersPasswordSet('garg'),
        'Password impostata. Le sessioni di garg sono state chiuse.');
    expect(it.adminUsersSendRecoveryConfirm('garg'),
        'Mandare a garg un codice per cambiare la password?');
    expect(it.adminUsersNoContacts('garg'), 'garg non ha contatti collegati');
    expect(it.adminUsersUnlinkConfirm('garg'),
        'Scollegare Discord ed email di garg?');
    expect(it.adminRecoveryWithContacts(5, 23),
        '5 utenti su 23 hanno un contatto');
    expect(it.adminRecoveryWithContacts(1, 23),
        '1 utente su 23 ha un contatto');
    expect(it.adminRecoveryReminders(14), 'Promemoria ogni 14 giorni');
    expect(it.adminRecoveryReminders(1), 'Promemoria ogni giorno');
    expect(it.adminRecoveryLastError('DM chiusi', '2 h fa'),
        'Ultimo errore: DM chiusi, 2 h fa');
    expect(it.recoveryHaveCode, 'Ho già un codice');
    expect(en.adminTabUsers, 'Users');
    expect(en.adminRecoveryWithContacts(5, 23),
        '5 users out of 23 have a contact');
    expect(en.recoveryHaveCode, 'I already have a code');
  });
}
