import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 18b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.settingsChangePassword, 'Cambia password');
    expect(it.accountWrongPassword, 'Password attuale sbagliata');
    expect(it.accountPasswordChanged,
        'Password cambiata. Gli altri dispositivi dovranno rientrare.');
    expect(it.accountLinked('garg'), 'Collegato: garg');
    expect(it.accountLinkTitle('Discord'), 'Collega Discord');
    expect(it.accountUnlinkTitle('Email'), 'Scollegare Email?');
    expect(it.accountCodeSentEmail('a@example.com'),
        'Ti abbiamo mandato un codice a a@example.com');
    expect(it.accountResendIn(42), 'Rimanda tra 42 s');
    expect(it.accountErrorRateLimited, 'Troppe richieste: riprova più tardi');
    expect(it.recoveryCodeSent,
        "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato "
        'un codice su Discord o per email.');
    expect(it.recoveryTooMany,
        "Troppi tentativi: riprova tra un'ora o contatta l'amministratore");
    expect(it.recoveryChanged, 'Password cambiata: accedi con quella nuova.');
    expect(it.inboxContactReminderTitle, 'Proteggi il tuo account');
    expect(en.recoveryChanged, 'Password changed: sign in with the new one.');
    expect(en.settingsChangePassword, 'Change password');
    expect(en.accountResendIn(42), 'Resend in 42 s');
    expect(en.inboxContactReminderTitle, 'Protect your account');
  });

  test('app_it.arb e app_en.arb hanno le stesse chiavi', () {
    Set<String> keys(String path) => {
          for (final key
              in (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
                  .keys)
            if (!key.startsWith('@')) key,
        };
    expect(keys('l10n/app_en.arb'), keys('l10n/app_it.arb'));
  });
}
