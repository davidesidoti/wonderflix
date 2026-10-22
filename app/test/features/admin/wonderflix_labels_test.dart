import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/wonderflix_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  test('tipo dell\'ultimo evento di Seerr', () {
    expect(seerrEventLabel(it, 'MEDIA_PENDING'), 'Richiesta in attesa');
    expect(seerrEventLabel(it, 'MEDIA_AVAILABLE'), 'Richiesta disponibile');
    expect(seerrEventLabel(it, 'TEST_NOTIFICATION'), 'Messaggio di prova');
    expect(seerrEventLabel(it, 'MEDIA_FAILED'), 'MEDIA_FAILED');
  });

  test('esito della prova di Seerr', () {
    expect(seerrTestLabel(it, const SeerrTestResult(ok: true, version: '3.4.1')),
        'Collegato a Seerr 3.4.1');
    expect(seerrTestLabel(it, const SeerrTestResult(ok: true)),
        'Collegato a Seerr');
    expect(
        seerrTestLabel(
            it, const SeerrTestResult(ok: false, error: 'NotConfigured')),
        'Seerr non è configurato');
    expect(seerrTestLabel(it, const SeerrTestResult(ok: false, error: 'SeerrAuth')),
        'Seerr ha rifiutato la chiave');
    expect(
        seerrTestLabel(
            it, const SeerrTestResult(ok: false, error: 'SeerrUnavailable')),
        'Seerr non risponde');
    expect(seerrTestLabel(it, const SeerrTestResult(ok: false)),
        'Seerr non risponde');
  });

  test('novità', () {
    expect(
        newTitlesStatusLabel(
            it, const NewTitlesStatus(enabled: true, pending: 3)),
        '3 titoli in attesa del prossimo riepilogo');
    expect(
        newTitlesStatusLabel(
            it, const NewTitlesStatus(enabled: true, pending: 0)),
        'Nessun titolo in attesa');
    expect(
        newTitlesStatusLabel(
            it, const NewTitlesStatus(enabled: false, pending: 3)),
        'Le novità non vengono raccolte');
    expect(
        newTitlesSentLabel(
            it, const NewTitlesSent(titles: 3, recipients: 12)),
        'Inviati 3 titoli a 12 persone');
    expect(
        newTitlesSentLabel(it, const NewTitlesSent(titles: 1, recipients: 1)),
        'Inviato 1 titolo a 1 persona');
  });
}
