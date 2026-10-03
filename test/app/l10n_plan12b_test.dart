import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 12b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.friendsInParty('Dune'), 'Nel watch party: Dune');
    expect(it.partyModePublic, 'Pubblico');
    expect(it.partyModePublicHint, 'Lo vedono tutti, avviso a tutti');
    expect(it.partyModeFriends, 'Solo amici');
    expect(it.partyModeFriendsHint, 'Lo vedono i tuoi amici, avviso solo a loro');
    expect(it.partyModePrivate, 'Privato');
    expect(it.partyModePrivateHint,
        'Nessun avviso; si entra con il codice o con un invito');
    expect(it.partyCreateFailed, 'Non è stato possibile creare il watch party');
    expect(it.partyHaveCode, 'Ho un codice');
    expect(it.partyCodeHint, 'Codice del party');
    expect(it.partyCodeJoin, 'Entra');
    expect(it.partyCodeInvalid, 'Codice non valido o party finito');
    expect(it.partyCodeTooMany, 'Troppi tentativi, riprova tra un minuto');
    expect(it.partyCode('K7P-Q2X'), 'Codice K7P-Q2X');
    expect(it.partyCodeCopied, 'Codice copiato');
    expect(it.partyPrivateCreated('K7P-Q2X'), 'Party privato · codice K7P-Q2X');
    expect(it.partyInviteFriends, 'Invita amici');
    expect(it.partyInvited, 'Invitato');
    expect(it.partyInviteSent('Luigi'), 'Invito mandato a Luigi');
    expect(it.partyNoFriendsToInvite, 'Nessun amico da invitare');
    expect(it.partyInviteTitle('Luigi'), 'Luigi ti invita');
    expect(en.friendsInParty('Dune'), 'In a watch party: Dune');
    expect(en.partyModePublic, 'Public');
    expect(en.partyModePublicHint, 'Everyone sees it and gets notified');
    expect(en.partyModeFriends, 'Friends only');
    expect(en.partyModeFriendsHint,
        'Only your friends see it and get notified');
    expect(en.partyModePrivate, 'Private');
    expect(en.partyModePrivateHint,
        'No notifications; join with the code or an invite');
    expect(en.partyCreateFailed, "Couldn't create the watch party");
    expect(en.partyHaveCode, 'I have a code');
    expect(en.partyCodeHint, 'Party code');
    expect(en.partyCodeJoin, 'Join');
    expect(en.partyCodeInvalid, 'Invalid code or the party has ended');
    expect(en.partyCodeTooMany, 'Too many attempts, try again in a minute');
    expect(en.partyCode('K7P-Q2X'), 'Code K7P-Q2X');
    expect(en.partyCodeCopied, 'Code copied');
    expect(en.partyPrivateCreated('K7P-Q2X'), 'Private party · code K7P-Q2X');
    expect(en.partyInviteFriends, 'Invite friends');
    expect(en.partyInvited, 'Invited');
    expect(en.partyInviteSent('Luigi'), 'Invite sent to Luigi');
    expect(en.partyNoFriendsToInvite, 'No friends to invite');
    expect(en.partyInviteTitle('Luigi'), 'Luigi invites you');
  });
}
