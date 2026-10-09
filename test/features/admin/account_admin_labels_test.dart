import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_admin_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('dove è arrivato il codice', () {
    expect(
        recoverySentLabel(
            l, const [AccountChannel.discord, AccountChannel.email]),
        'Codice mandato su Discord ed email');
    expect(recoverySentLabel(l, const [AccountChannel.discord]),
        'Codice mandato su Discord');
    expect(recoverySentLabel(l, const [AccountChannel.email]),
        'Codice mandato per email');
  });

  test('errori delle azioni: i Code del plugin, poi describeError', () {
    expect(
        accountAdminErrorText(
            l, const ForbiddenException({'Code': 'NotAllowed'}), 'garg'),
        'Gli admin e gli utenti disattivati non possono usare il recupero '
        'automatico');
    expect(
        accountAdminErrorText(
            l, const ServerErrorException(409, {'Code': 'NoContacts'}), 'garg'),
        'garg non ha contatti collegati');
    expect(
        accountAdminErrorText(
            l, const ServerErrorException(502, {'Code': 'SendFailed'}), 'garg'),
        'Invio non riuscito, riprova più tardi');
    expect(
        accountAdminErrorText(
            l, const ServerErrorException(400, {'Code': 'UnknownUser'}), 'garg'),
        'Questo utente non c\'è più');
    expect(
        accountAdminErrorText(l, const ServerUnreachableException(), 'garg'),
        'WonderFlix non è raggiungibile. Controlla la connessione.');
  });

  test('ultimo errore di un canale', () {
    expect(sendErrorLabel(l, 'DmClosed'), 'DM chiusi');
    expect(sendErrorLabel(l, 'Invalid'), 'token o server non validi');
    expect(sendErrorLabel(l, 'SendFailed'), 'invio non riuscito');
    expect(sendErrorLabel(l, 'Altro'), 'invio non riuscito');
  });

  test('esito della prova', () {
    expect(
        testResultLabel(
            l, const AccountTestResult(discord: 'Ok', email: 'NoContact')),
        'Discord: inviato · Email: collega prima il tuo contatto');
    expect(
        testResultLabel(l,
            const AccountTestResult(discord: 'Invalid', email: 'NotConfigured')),
        'Discord: token o server non validi · Email: non configurato');
    expect(
        testResultLabel(
            l, const AccountTestResult(discord: 'DmClosed', email: 'SendFailed')),
        'Discord: il bot non riesce a scriverti · Email: invio non riuscito');
  });
}
