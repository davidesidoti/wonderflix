import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 23b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.ratingYourVote, 'Il tuo voto');
    expect(it.ratingVote, 'Vota');
    expect(it.ratingSkip, 'Salta');
    expect(it.ratingChange, 'Cambia');
    expect(it.ratingVoted(8), 'Hai votato 8');
    expect(it.ratingVotedCount(2, 4), 'Hanno votato 2 su 4');
    expect(it.ratingSkipped, 'ha saltato');
    expect(it.ratingReveal, 'Scopri i voti');
    expect(it.ratingWaiting, 'In attesa dei voti');
    expect(it.ratingPartyAverage(1), 'media del party · 1 voto');
    expect(it.ratingPartyAverage(3), 'media del party · 3 voti');
    expect(it.ratingYou, 'Tu');
    expect(it.ratingChangeLater,
        'Puoi cambiare il tuo voto dalla scheda del film');
    expect(it.ratingRoundUnavailable,
        'Votazione non disponibile: puoi votare dalla scheda');
    expect(it.ratingCommentHint, 'Commento (facoltativo)');
    expect(it.ratingFriendsRow, 'Voti degli amici');
    expect(it.ratingFriendsRowSeason('Stagione 2'),
        'Voti degli amici · Stagione 2');
    expect(it.ratingFriendsCount(1), '1 amico');
    expect(it.ratingFriendsCount(3), '3 amici');
    expect(it.ratingNoFriendsYet, 'Ancora nessun voto degli amici');
    expect(it.ratingMine(8), 'Il tuo voto: 8');
    expect(it.ratingSave, 'Salva');
    expect(it.ratingRemove, 'Togli il mio voto');
    expect(it.ratingNotSaved, 'Voto non salvato');
    expect(it.ratingTooMany, 'Troppi voti: riprova più tardi');
    expect(it.adminCommentsTitle, 'Commenti degli utenti');
    expect(it.adminCommentDelete, 'Cancella commento');
    expect(it.adminCommentsNeedPlugin, 'Serve il plugin 1.11.0');
    expect(it.ratingSeason(2), 'Stagione 2');
    expect(it.ratingSpecials, 'Speciali');
    expect(it.ratingYouSkipped, 'Hai saltato');
    expect(it.ratingPartyPill, 'Voti del party');
    expect(it.ratingRevealedPill, 'Voti scoperti');
    expect(it.ratingTimeLeft('0:42'), 'Ancora 0:42');
    expect(it.adminCommentsMore, 'Altri');
    expect(it.adminCommentsEmpty, 'Nessun commento');
    expect(it.adminCommentDeleteTitle, 'Cancellare il commento?');
    expect(it.adminCommentDeleteMessage('Mario', 'Dune'),
        'Il commento di Mario su Dune sparisce; il voto resta.');

    expect(en.ratingYourVote, 'Your rating');
    expect(en.ratingVoted(8), 'You rated it 8');
    expect(en.ratingVotedCount(2, 4), '2 of 4 have rated');
    expect(en.ratingPartyAverage(1), 'party average · 1 rating');
    expect(en.ratingPartyAverage(3), 'party average · 3 ratings');
    expect(en.ratingFriendsRow, "Friends' ratings");
    expect(en.ratingFriendsCount(1), '1 friend');
    expect(en.ratingFriendsCount(3), '3 friends');
    expect(en.adminCommentsNeedPlugin, 'Requires plugin 1.11.0');
    expect(en.ratingSeason(2), 'Season 2');
    expect(en.ratingSpecials, 'Specials');
    expect(en.ratingYouSkipped, 'You skipped');
    expect(en.ratingPartyPill, 'Party ratings');
    expect(en.ratingRevealedPill, 'Ratings revealed');
    expect(en.ratingTimeLeft('0:42'), '0:42 left');
    expect(en.adminCommentsMore, 'More');
    expect(en.adminCommentsEmpty, 'No comments');
    expect(en.adminCommentDeleteTitle, 'Delete the comment?');
    expect(en.adminCommentDeleteMessage('Mario', 'Dune'),
        "Mario's comment on Dune will be removed; the rating stays.");
  });
}
