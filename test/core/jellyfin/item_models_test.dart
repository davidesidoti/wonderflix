import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

void main() {
  test('film completo', () {
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'Dune: Parte Due',
      'Type': 'Movie',
      'Overview': 'Paul Atreides…',
      'ProductionYear': 2024,
      'OfficialRating': 'PG-13',
      'CommunityRating': 8.4,
      'RunTimeTicks': 99600000000,
      'Genres': ['Fantascienza', 'Avventura'],
      'ImageTags': {'Primary': 'p1', 'Logo': 'l1'},
      'BackdropImageTags': ['b1'],
      'ImageBlurHashes': {
        'Primary': {'p1': 'LEHV6nWB2yk8'},
      },
      'UserData': {
        'Played': false,
        'IsFavorite': true,
        'PlaybackPositionTicks': 13940000000,
        'PlayedPercentage': 14.0,
      },
      'People': [
        {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor', 'PrimaryImageTag': 'pp9'},
      ],
      'RemoteTrailers': [
        {'Url': 'https://youtube.com/watch?v=x', 'Name': 'Trailer'},
      ],
      'LocalTrailerCount': 1,
    });

    expect(item.kind, ItemKind.movie);
    expect(item.runtime, const Duration(hours: 2, minutes: 46));
    expect(item.genres, ['Fantascienza', 'Avventura']);
    expect(item.imageTags['Logo'], 'l1');
    expect(item.backdropTags, ['b1']);
    expect(item.blurHashes['Primary']?['p1'], 'LEHV6nWB2yk8');
    expect(item.userData.isFavorite, isTrue);
    expect(item.userData.playbackPosition, const Duration(minutes: 23, seconds: 14));
    expect(item.userData.progress, closeTo(0.14, 0.0001));
    expect(item.people.single.role, 'Chani');
    expect(item.remoteTrailers.single.url, 'https://youtube.com/watch?v=x');
    expect(item.localTrailerCount, 1);
  });

  test('trailer senza indirizzo vengono scartati', () {
    final item = JellyfinItem.fromJson({
      'Id': 'm1',
      'Name': 'X',
      'Type': 'Movie',
      'RemoteTrailers': [
        {'Url': null},
        {'Url': ''},
        {'Url': 'https://y'},
      ],
    });
    expect(item.remoteTrailers.single.url, 'https://y');
  });

  test('episodio', () {
    final item = JellyfinItem.fromJson({
      'Id': 'e4',
      'Name': 'Please Hold to My Hand',
      'Type': 'Episode',
      'SeriesId': 's1',
      'SeriesName': 'The Last of Us',
      'SeasonId': 'se1',
      'IndexNumber': 4,
      'ParentIndexNumber': 1,
      'SeriesPrimaryImageTag': 'sp1',
      'ParentBackdropItemId': 's1',
      'ParentBackdropImageTags': ['sb1'],
    });
    expect(item.kind, ItemKind.episode);
    expect(item.seriesName, 'The Last of Us');
    expect(item.indexNumber, 4);
    expect(item.parentIndexNumber, 1);
    expect(item.parentBackdropTags, ['sb1']);
  });

  test('campi mancanti e tipo sconosciuto hanno valori di default', () {
    final item = JellyfinItem.fromJson({'Id': 'x', 'Type': 'Folder'});
    expect(item.kind, ItemKind.other);
    expect(item.name, '');
    expect(item.genres, isEmpty);
    expect(item.userData.played, isFalse);
    expect(item.userData.progress, isNull);
    expect(item.runtime, isNull);
  });

  test('progress è null se già visto', () {
    const data = UserItemData(played: true, playedPercentage: 50);
    expect(data.progress, isNull);
    expect(data.copyWith(played: false).progress, 0.5);
  });

  test('ItemKind.parse', () {
    expect(ItemKind.parse('Series'), ItemKind.series);
    expect(ItemKind.parse(''), ItemKind.other);
    expect(ItemKind.parse(null), ItemKind.other);
  });

  test('durationToTicks è l\'inverso di ticksToDuration', () {
    expect(durationToTicks(const Duration(seconds: 90)), 900000000);
    expect(ticksToDuration(durationToTicks(const Duration(minutes: 23))),
        const Duration(minutes: 23));
  });

  test('copyWith aggiorna minutaggio e percentuale', () {
    const data = UserItemData(
        isFavorite: true, playbackPositionTicks: 10, playedPercentage: 1);
    final next =
        data.copyWith(playbackPositionTicks: 600000000, playedPercentage: 50);
    expect(next.playbackPositionTicks, 600000000);
    expect(next.playedPercentage, 50);
    expect(next.isFavorite, isTrue);
    expect(data.copyWith(played: true).playbackPositionTicks, 10);
  });
}
