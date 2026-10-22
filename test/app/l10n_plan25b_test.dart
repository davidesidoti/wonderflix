import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

/// Le chiavi del piano 25b (i Task successivi le estendono).
const _keys = [
  'requestsStatusAwaitingRelease',
  'requestsInCinemas',
  'requestsDigitalExpected',
  'requestsDigitalReleased',
  'requestsDigitalUnknown',
  'requestsNextEpisode',
  'requestsNextEpisodeDate',
  'calendarSeriesCount',
];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/app_$name.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('tutte le chiavi del piano 25b ci sono, non vuote, in it ed en', () {
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

  test('testi e segnaposto delle richieste', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.requestsStatusAwaitingRelease, "In attesa dell'uscita");
    expect(it.requestsInCinemas('25 settembre'), 'Al cinema dal 25 settembre');
    expect(it.requestsDigitalExpected('12 novembre'),
        'in digitale previsto il 12 novembre');
    expect(it.requestsDigitalReleased('20 ottobre'),
        'uscito in digitale il 20 ottobre');
    expect(it.requestsDigitalUnknown, 'in digitale: data non ancora nota');
    expect(it.requestsNextEpisode('S01E04', '2 novembre'),
        'Prossimo episodio: S01E04 il 2 novembre');
    expect(it.requestsNextEpisodeDate('2 novembre'),
        'Prossimo episodio il 2 novembre');
    expect(it.calendarSeriesCount('Andor', 4), 'Andor ×4');
    expect(en.calendarSeriesCount('Andor', 4), 'Andor ×4');
    expect(en.requestsStatusAwaitingRelease, 'Waiting for release');
    expect(en.requestsInCinemas('Sep 25'), 'In cinemas from Sep 25');
    expect(en.requestsDigitalExpected('Nov 12'), 'digital expected on Nov 12');
    expect(en.requestsDigitalReleased('Oct 20'), 'out digitally on Oct 20');
    expect(en.requestsDigitalUnknown, 'digital: date not known yet');
    expect(en.requestsNextEpisode('S01E04', 'Nov 2'),
        'Next episode: S01E04 on Nov 2');
    expect(en.requestsNextEpisodeDate('Nov 2'), 'Next episode on Nov 2');
  });
}
