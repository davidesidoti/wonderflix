import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del player', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerTrack(3), 'Traccia 3');
    expect(en.playerTrack(3), 'Track 3');
    expect(it.decimalSeparator, ',');
    expect(en.decimalSeparator, '.');
    expect(it.playerAudioAndSubtitles, 'Audio e sottotitoli');
    expect(en.playerAudioAndSubtitles, 'Audio & subtitles');
  });
}
