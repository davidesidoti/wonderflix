import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 5a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.watchPartyWatchTogether, 'Guarda insieme');
    expect(en.watchPartyWatchTogether, 'Watch together');
    expect(it.watchPartyButton(3), 'Watch party · 3');
    expect(it.watchPartyListTitle, 'Watch party attivi');
    expect(it.watchPartyJoin, 'Unisciti');
    expect(it.watchPartyMembers(1), '1 persona');
    expect(it.watchPartyMembers(3), '3 persone');
    expect(en.watchPartyMembers(3), '3 people');
    expect(it.watchPartyStateIdle, 'Fermo');
    expect(it.watchPartyStateWaiting, 'In attesa');
    expect(it.watchPartyStatePaused, 'In pausa');
    expect(it.watchPartyStatePlaying, 'In riproduzione');
    expect(it.watchPartyLeave, 'Esci dal watch party');
    expect(it.watchPartyWaiting, 'In attesa degli altri membri…');
    expect(it.watchPartyResumeNow, 'Riprendi senza aspettare');
    expect(en.watchPartyResumeNow, 'Resume without waiting');
    expect(it.watchPartyCreateError,
        'Non è stato possibile avviare il watch party.');
    expect(it.watchPartyJoinError,
        'Non è stato possibile entrare nel watch party.');
    expect(it.watchPartyGone, 'Questo watch party non esiste più.');
    expect(it.watchPartyAccessDenied, 'Non hai accesso a questo contenuto.');
  });
}
