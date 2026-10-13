import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 21b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.friendsWatching('Dune'), 'Sta guardando Dune');
    expect(it.friendsWatchingEpisode('The Bear', 2, 3), 'Sta guardando The Bear · S2 E3');
    expect(it.friendsWatchTogether, 'Guarda insieme');
    expect(it.friendsNoLongerWatching, 'Non sta più guardando');
    expect(it.friendsInviteNotSent, 'Invito non inviato');
    expect(it.settingsShareActivity, 'Mostra agli amici cosa guardo');
    expect(it.settingsShareActivityHint,
        'Gli amici vedono il titolo che stai guardando e quelli che hai visto negli ultimi 30 giorni in WonderFlix');
    expect(it.settingsShareActivityLoadError, 'Impossibile caricare l\'impostazione');
    expect(it.settingsShareActivitySaveError, 'Impostazione non salvata');
    expect(it.homeRowFriendsWatched, 'Visti dagli amici');
    expect(it.friendsWatchedByOne('Luca'), 'Visto da Luca');
    expect(it.friendsWatchedByTwo('Luca', 'Marta'), 'Visto da Luca e Marta');
    expect(it.friendsWatchedByMany('Luca', 2), 'Visto da Luca e altri 2');
    expect(it.homeRowUnavailableFriendsActivity,
        'Serve il plugin 1.9.0 e l\'accesso ai watch party');
    expect(en.friendsWatching('Dune'), 'Watching Dune');
    expect(en.friendsWatchingEpisode('The Bear', 2, 3), 'Watching The Bear · S2 E3');
    expect(en.friendsWatchTogether, 'Watch together');
    expect(en.settingsShareActivity, 'Show friends what I watch');
    expect(en.homeRowFriendsWatched, 'Watched by friends');
    expect(en.friendsWatchedByMany('Luca', 2), 'Watched by Luca and 2 others');
    expect(en.homeRowUnavailableFriendsActivity, 'Needs plugin 1.9.0 and watch party access');
  });
}
