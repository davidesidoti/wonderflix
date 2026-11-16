import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 8c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.playerPlayNowIn(7), 'Riproduci tra 7 s');
    expect(it.playerWatchCredits, 'Guarda i titoli');
    expect(it.playerIntroSkipped, 'Intro saltata');
    expect(it.playerRecapSkipped, 'Riassunto saltato');
    expect(en.playerPlayNowIn(7), 'Play in 7 s');
    expect(en.playerWatchCredits, 'Watch credits');
    expect(en.playerIntroSkipped, 'Intro skipped');
    expect(en.playerRecapSkipped, 'Recap skipped');
  });
}
