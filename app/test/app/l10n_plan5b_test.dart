import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 5b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.watchPartyNoticePaused, 'Pausa');
    expect(it.watchPartyNoticePausedByYou, 'Hai messo in pausa');
    expect(it.watchPartyNoticeResumed, 'Ripresa');
    expect(it.watchPartyNoticeResumedByYou, 'Hai ripreso');
    expect(it.watchPartyNoticeForcedResume, 'Si riprende senza aspettare');
    expect(it.watchPartyNoticeSeek('32:10'), 'Salto a 32:10');
    expect(it.watchPartyNoticeSeekByYou('32:10'), 'Hai saltato a 32:10');
    expect(it.watchPartyNoticeNextEpisode('S1:E5 · Titolo'),
        'Episodio successivo: S1:E5 · Titolo');
    expect(it.watchPartyNoticeNowWatching('Dune'), 'Si guarda: Dune');
    expect(it.watchPartyNoticeJoined('Luigi'), 'Luigi è nel watch party');
    expect(it.watchPartyNoticeLeft('Luigi'),
        'Luigi ha lasciato il watch party');
    expect(it.watchPartyNoticeResync, 'Riallineamento al gruppo');
    expect(en.watchPartyNoticeSeekByYou('32:10'), 'You jumped to 32:10');
    expect(en.watchPartyNoticeJoined('Luigi'), 'Luigi joined the watch party');
    expect(en.watchPartyNoticeResync, 'Resyncing with the group');
  });
}
