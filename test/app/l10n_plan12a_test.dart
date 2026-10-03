import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 12a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.friendsTitle, 'Amici');
    expect(it.friendsClose, 'Chiudi');
    expect(it.friendsSearchHint, 'Cerca per nome');
    expect(it.friendsSearchEmpty, 'Nessun utente trovato');
    expect(it.friendsAdd, 'Aggiungi');
    expect(it.friendsSent, 'Inviata');
    expect(it.friendsCancel, 'Annulla');
    expect(it.friendsAccept, 'Accetta');
    expect(it.friendsDecline, 'Rifiuta');
    expect(it.friendsAlready, 'Amici');
    expect(it.friendsRequests(3), 'Richieste (3)');
    expect(it.friendsPending, 'In attesa');
    expect(it.friendsEmpty,
        'Nessun amico ancora. Cerca qualcuno per nome qui sopra.');
    expect(it.friendsMore, 'Altre azioni');
    expect(it.friendsRemove, 'Rimuovi dagli amici');
    expect(it.friendsRemoveConfirm, 'Conferma rimozione');
    expect(it.friendsUnavailable, 'Amici non disponibili');
    expect(it.friendsActionFailed, 'Operazione non riuscita');
    expect(it.friendsTooMany, 'Troppe richieste, riprova più tardi');
    expect(it.friendsOnline, 'Online');
    expect(it.friendsOffline, 'Offline');
    expect(it.friendRequestTitle('Luigi'), 'Luigi vuole essere tuo amico');
    expect(en.friendsTitle, 'Friends');
    expect(en.friendsClose, 'Close');
    expect(en.friendsSearchHint, 'Search by name');
    expect(en.friendsSearchEmpty, 'No users found');
    expect(en.friendsAdd, 'Add');
    expect(en.friendsSent, 'Sent');
    expect(en.friendsCancel, 'Cancel');
    expect(en.friendsAccept, 'Accept');
    expect(en.friendsDecline, 'Decline');
    expect(en.friendsAlready, 'Friends');
    expect(en.friendsRequests(3), 'Requests (3)');
    expect(en.friendsPending, 'Pending');
    expect(en.friendsEmpty, 'No friends yet. Search for someone by name above.');
    expect(en.friendsMore, 'More actions');
    expect(en.friendsRemove, 'Remove friend');
    expect(en.friendsRemoveConfirm, 'Confirm removal');
    expect(en.friendsUnavailable, 'Friends unavailable');
    expect(en.friendsActionFailed, 'Something went wrong');
    expect(en.friendsTooMany, 'Too many requests, try again later');
    expect(en.friendsOnline, 'Online');
    expect(en.friendsOffline, 'Offline');
    expect(en.friendRequestTitle('Luigi'), 'Luigi wants to be your friend');
  });
}
