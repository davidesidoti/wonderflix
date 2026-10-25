import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

/// Le chiavi del piano 28 (i Task successivi le estendono).
const _keys = [
  'navMore',
  'playerMoreControls',
];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/app_$name.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('tutte le chiavi del piano 28 ci sono, non vuote, in it ed en', () {
    for (final lang in ['it', 'en']) {
      final arb = _arb(lang);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$lang: manca $key');
        expect((value as String).trim(), isNotEmpty,
            reason: '$lang: $key vuota');
      }
    }
  });

  test('testi della navigazione stretta', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.navMore, 'Altro');
    expect(en.navMore, 'More');
  });

  test('menu dei controlli del player', () {
    expect(lookupAppLocalizations(const Locale('it')).playerMoreControls,
        'Altri controlli');
    expect(lookupAppLocalizations(const Locale('en')).playerMoreControls,
        'More controls');
  });
}
