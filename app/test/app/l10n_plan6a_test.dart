import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 6a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.settingsAppearance, 'Aspetto');
    expect(en.settingsAppearance, 'Appearance');
    expect(it.settingsAnimations, 'Animazioni');
    expect(it.settingsAnimationsSystem, 'Come Windows');
    expect(it.settingsAnimationsFull, 'Complete');
    expect(it.settingsAnimationsReduced, 'Ridotte');
    expect(en.settingsAnimationsSystem, 'Same as Windows');
    expect(en.settingsAnimationsReduced, 'Reduced');
  });
}
