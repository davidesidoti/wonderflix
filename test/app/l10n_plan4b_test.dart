import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 4b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.updateReadyTitle('0.2.0'), 'Aggiornamento pronto: WonderFlix 0.2.0');
    expect(en.updateReadyTitle('0.2.0'), 'Update ready: WonderFlix 0.2.0');
    expect(it.updateRestartNow, 'Riavvia ora');
    expect(it.updateWhatsNew, 'Novità');
    expect(it.updateLater, 'Più tardi');
    expect(it.updateRequiredTitle, 'Aggiornamento necessario');
    expect(
        it.updateRequiredBody('0.2.0'),
        'Questa versione di WonderFlix non è più supportata. '
        'Installa la versione 0.2.0 per continuare.');
    expect(it.updateDownloading(42), 'Download in corso… 42%');
    expect(en.updateDownloading(42), 'Downloading… 42%');
    expect(it.updateInstallNow, 'Aggiorna ora');
    expect(en.updateDownloadFailed,
        'Download failed. Check your connection and try again.');
  });
}
