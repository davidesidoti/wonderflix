import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 3b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerNextEpisodeIn(7), 'Inizia tra 7 s');
    expect(en.playerNextEpisodeIn(7), 'Starts in 7 s');
    expect(it.settingsQualityOriginal, 'Massima (originale)');
    expect(it.settingsQualityHigh(20), 'Alta (20 Mbps)');
    expect(it.settingsQualityMedium(8), 'Media (8 Mbps)');
    expect(it.settingsQualityLow(4), 'Bassa (4 Mbps)');
    expect(en.settingsQualityMedium(8), 'Medium (8 Mbps)');
    expect(it.playerSkipIntro, 'Salta intro');
    expect(en.settingsSubtitleModeOnlyForced, 'Forced only');
  });
}
