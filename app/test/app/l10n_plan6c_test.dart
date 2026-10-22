import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 6c', () {
    expect(lookupAppLocalizations(const Locale('it')).previewResume, 'Riprendi');
    expect(lookupAppLocalizations(const Locale('en')).previewResume, 'Resume');
  });
}
