import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 8b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerWatching, 'Stai guardando');
    expect(it.playerSubtitleSizeValue('Normali'), 'Dimensione · Normali');
    expect(it.playerClosePanel, 'Chiudi');
    expect(en.playerWatching, "You're watching");
    expect(en.playerSubtitleSizeValue('Normal'), 'Size · Normal');
    expect(en.playerClosePanel, 'Close');
  });
}
