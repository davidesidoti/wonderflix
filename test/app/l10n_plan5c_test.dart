import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 5c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.watchPartyInviteTitle('Davide'),
        'Davide ha avviato un watch party');
    expect(en.watchPartyInviteTitle('Davide'), 'Davide started a watch party');
    expect(it.watchPartyInParty, 'Nel watch party');
    expect(it.watchPartyBackToPlayer, 'Torna al player');
    expect(it.watchPartyDismiss, 'Chiudi');
    expect(it.watchPartyNoticeEnded, 'Il watch party è terminato');
    expect(en.watchPartyNoticeEnded, 'The watch party has ended');
    expect(it.discordWatchParty(1), 'Watch party · 1 persona');
    expect(it.discordWatchParty(3), 'Watch party · 3 persone');
    expect(en.discordWatchParty(3), 'Watch party · 3 people');
  });
}
