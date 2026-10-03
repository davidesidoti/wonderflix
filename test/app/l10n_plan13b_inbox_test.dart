import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 13b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.inboxNewTitles('2 film, 10 episodi'), 'Novità: 2 film, 10 episodi');
    expect(it.inboxMovies(1), '1 film');
    expect(it.inboxMovies(3), '3 film');
    expect(it.inboxEpisodes(1), '1 episodio');
    expect(it.inboxEpisodes(10), '10 episodi');
    expect(it.inboxNewEpisodes(1), '1 episodio nuovo');
    expect(it.inboxNewEpisodes(3), '3 episodi nuovi');
    expect(it.inboxShowAll(12), 'Mostra tutto (12)');
    expect(it.inboxMore(1), '…e un altro titolo');
    expect(it.inboxMore(7), '…e altri 7 titoli');
    expect(en.inboxNewTitles('2 movies, 10 episodes'), 'New: 2 movies, 10 episodes');
    expect(en.inboxMovies(1), '1 movie');
    expect(en.inboxMovies(3), '3 movies');
    expect(en.inboxEpisodes(1), '1 episode');
    expect(en.inboxEpisodes(10), '10 episodes');
    expect(en.inboxNewEpisodes(1), '1 new episode');
    expect(en.inboxNewEpisodes(3), '3 new episodes');
    expect(en.inboxShowAll(12), 'Show all (12)');
    expect(en.inboxMore(1), '…and 1 more');
    expect(en.inboxMore(7), '…and 7 more');
  });
}
