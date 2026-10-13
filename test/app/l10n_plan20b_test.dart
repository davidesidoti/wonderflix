import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 20b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.recommendButton, 'Consiglia a…');
    expect(it.recommendCannotSee, 'Non può vederlo');
    expect(it.recommendSent(1), 'Consiglio inviato');
    expect(it.recommendSent(3), 'Consiglio inviato a 3 amici');
    expect(it.recommendMaxReached(30), 'Al massimo 30 amici alla volta');
    expect(it.homeRowRecommended, 'Consigliati per te');
    expect(it.recommendedFromOne('Luca'), 'Da Luca');
    expect(it.recommendedFromTwo('Luca', 'Marta'), 'Da Luca e Marta');
    expect(it.recommendedFromMany('Luca', 2), 'Da Luca e altri 2');
    expect(it.recommendationQuote('Luca', 'da vedere'), 'Luca: «da vedere»');
    expect(it.inboxRecommendation('Luca', 'Dune (2021)'), 'Luca ti consiglia Dune (2021)');
    expect(it.homeRowUnavailableRecommendations,
        "Serve il plugin 1.8.0 e l'accesso ai watch party");
    expect(it.inboxRecommendationMessage('ciao'), '«ciao»');
    expect(it.recommendNoFriends, 'Nessun amico a cui consigliarlo');
    expect(en.inboxRecommendationMessage('hi'), '“hi”');
    expect(en.recommendNoFriends, 'No friends to recommend it to');
    expect(en.homeRowUnavailableRecommendations,
        'Needs plugin 1.8.0 and watch party access');
    expect(en.recommendButton, 'Recommend to…');
    expect(en.recommendSent(1), 'Recommendation sent');
    expect(en.recommendSent(3), 'Recommendation sent to 3 friends');
    expect(en.recommendedFromMany('Luca', 2), 'From Luca and 2 others');
    expect(en.inboxRecommendation('Luca', 'Dune (2021)'), 'Luca recommends Dune (2021)');
  });
}
