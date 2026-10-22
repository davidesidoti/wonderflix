import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/activity_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/activity_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('Sta guardando: film, episodio, episodio senza numeri o senza serie', () {
    expect(friendNowPlayingText(l, const FriendNowPlaying(itemId: 'm1', title: 'Dune')),
        'Sta guardando Dune');
    expect(
        friendNowPlayingText(
            l,
            const FriendNowPlaying(
                itemId: 'e1', title: 'Pilot', seriesName: 'The Bear', season: 2, episode: 3)),
        'Sta guardando The Bear · S2 E3');
    expect(
        friendNowPlayingText(
            l, const FriendNowPlaying(itemId: 'e1', title: 'Pilot', seriesName: 'The Bear', season: 2)),
        'Sta guardando The Bear');
    expect(friendNowPlayingText(l, const FriendNowPlaying(itemId: 'e1', title: 'Speciale')),
        'Sta guardando Speciale');
  });

  test('Visto da: uno, due, tre o più', () {
    FriendWatcher w(String name) =>
        FriendWatcher(userId: name, name: name, watchedAt: DateTime.utc(2026));
    expect(friendsWatchedBy(l, [w('Luca')]), 'Visto da Luca');
    expect(friendsWatchedBy(l, [w('Luca'), w('Marta')]), 'Visto da Luca e Marta');
    expect(friendsWatchedBy(l, [w('Luca'), w('Marta'), w('Sara')]), 'Visto da Luca e altri 2');
    expect(friendsWatchedBy(l, const []), '');
  });
}
