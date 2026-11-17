import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 13a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.inboxTitle, 'Notifiche');
    expect(it.inboxClear, 'Svuota tutto');
    expect(it.inboxClearConfirm, 'Sì, svuota');
    expect(it.inboxRemove, 'Togli dalla lista');
    expect(it.inboxEmpty,
        'Niente di nuovo. Gli inviti e i consigli degli amici arrivano qui.');
    expect(it.inboxUnavailable,
        'Non riesco a leggere le notifiche. Controlla la connessione e riprova.');
    expect(it.inboxActionFailed,
        'Non è stato possibile aggiornare le notifiche');
    expect(it.notifInviteTitle('Luigi', 'Dune'),
        'Luigi ti invita a guardare Dune');
    expect(it.notifMatchInviteTitle('Luigi'), 'Luigi ti invita a un Match');
    expect(it.partyMembers(1), '1 nel party');
    expect(it.partyMembers(2), '2 nel party');
    expect(it.inboxAlreadyIn, 'Ci sei già');
    expect(it.inboxPartyEnded, 'Party finito');
    expect(it.inboxAnnouncement, 'Annuncio');
    expect(it.inboxNow, 'adesso');
    expect(it.inboxMinutesAgo(5), '5 min fa');
    expect(it.inboxHoursAgo(2), '2 h fa');
    expect(it.inboxYesterday, 'ieri');
    expect(it.inboxDaysAgo(3), '3 giorni fa');
    expect(en.inboxTitle, 'Notifications');
    expect(en.inboxClear, 'Clear all');
    expect(en.inboxClearConfirm, 'Yes, clear');
    expect(en.inboxRemove, 'Remove from list');
    expect(en.inboxEmpty,
        'Nothing new. Invites and tips from friends show up here.');
    expect(en.inboxUnavailable,
        "Can't load notifications. Check your connection and try again.");
    expect(en.inboxActionFailed, "Couldn't update notifications");
    expect(en.notifInviteTitle('Luigi', 'Dune'),
        'Luigi invites you to watch Dune');
    expect(en.notifMatchInviteTitle('Luigi'), 'Luigi invites you to a Match');
    expect(en.partyMembers(2), '2 in the party');
    expect(en.inboxAlreadyIn, "You're in it");
    expect(en.inboxPartyEnded, 'Party ended');
    expect(en.inboxAnnouncement, 'Announcement');
    expect(en.inboxNow, 'just now');
    expect(en.inboxMinutesAgo(5), '5 min ago');
    expect(en.inboxHoursAgo(2), '2 h ago');
    expect(en.inboxYesterday, 'yesterday');
    expect(en.inboxDaysAgo(3), '3 days ago');
  });
}
