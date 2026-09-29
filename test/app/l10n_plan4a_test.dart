import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 4a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.discordPaused, 'In pausa');
    expect(en.discordPaused, 'Paused');
    expect(it.discordAccessButton, "Chiedi l'accesso");
    expect(en.discordAccessButton, 'Ask for access');
    // Limite di Discord per le etichette dei pulsanti.
    expect(it.discordAccessButton.length, lessThanOrEqualTo(32));
    expect(en.discordAccessButton.length, lessThanOrEqualTo(32));
    expect(it.settingsDiscordEnabled, 'Mostra su Discord cosa sto guardando');
    expect(it.settingsCopyDiagnostics, 'Copia diagnostica');
    expect(en.settingsCopyDiagnostics, 'Copy diagnostics');
    expect(it.settingsDiagnosticsCopied, 'Diagnostica copiata negli appunti');
    expect(en.settingsOpenLogs, 'Open the log folder');
    expect(it.settingsDiagnosticsCopyError,
        'Impossibile copiare la diagnostica.');
    expect(en.settingsDiagnosticsCopyError, "Couldn't copy the diagnostics.");
  });
}
