import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 13a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.inboxTitle, 'Notifiche');
    expect(it.inboxClear, 'Svuota');
    expect(it.inboxClearConfirm, 'Conferma');
    expect(it.inboxRemove, 'Rimuovi');
    expect(it.inboxEmpty, 'Nessuna notifica');
    expect(it.inboxUnavailable, 'Notifiche non disponibili');
    expect(it.inboxActionFailed,
        'Non è stato possibile aggiornare le notifiche');
    expect(it.inboxInviteFrom('Luigi'), 'Luigi ti invita a guardare');
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
    expect(en.inboxClearConfirm, 'Confirm');
    expect(en.inboxRemove, 'Remove');
    expect(en.inboxEmpty, 'No notifications');
    expect(en.inboxUnavailable, 'Notifications unavailable');
    expect(en.inboxActionFailed, "Couldn't update notifications");
    expect(en.inboxInviteFrom('Luigi'), 'Luigi invited you to watch');
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
