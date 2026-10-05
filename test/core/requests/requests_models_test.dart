import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/requests/tmdb_images.dart';

void main() {
  test('Me', () {
    final me = RequestsMe.fromJson(
        {'CanRequest': true, 'CanManage': false, 'HasAccount': true});
    expect((me.canRequest, me.canManage, me.hasAccount), (true, false, true));
    expect(RequestsMe.none.canRequest, isFalse);
  });

  test('titolo della ricerca', () {
    final title = RequestableTitle.fromJson({
      'MediaType': 'tv',
      'TmdbId': 90228,
      'Title': 'Dune: Prophecy',
      'Year': 2024,
      'PosterPath': '/p.jpg',
      'Status': 'Processing',
      'JellyfinItemId': null,
    });
    expect(title.mediaType, RequestMediaType.tv);
    expect(title.tmdbId, 90228);
    expect(title.title, 'Dune: Prophecy');
    expect(title.year, 2024);
    expect(title.status, TitleStatus.processing);
    expect(title.jellyfinItemId, isNull);
    expect(() => RequestableTitle.fromJson({'MediaType': 'person', 'TmdbId': 1}),
        throwsFormatException);
  });

  test('stati sconosciuti', () {
    expect(TitleStatus.parse('Boh'), TitleStatus.none);
    expect(TitleStatus.none.isRequestable, isTrue);
    expect(TitleStatus.pending.isRequestable, isFalse);
    expect(RequestStatus.parse('Downloading'), RequestStatus.downloading);
    expect(RequestStatus.parse('Boh'), RequestStatus.approved);
  });

  test('scheda di una serie: stagioni da chiedere', () {
    final details = TitleDetails.fromJson({
      'MediaType': 'tv',
      'TmdbId': 250203,
      'Title': 'Brothers',
      'Year': 2026,
      'Overview': 'Due fratelli',
      'Genres': ['Commedia'],
      'RuntimeMinutes': null,
      'PosterPath': '/p.jpg',
      'BackdropPath': '/b.jpg',
      'TrailerUrl': 'https://www.youtube.com/watch?v=x',
      'Status': 'Partial',
      'JellyfinItemId': '6d1c8ea33a794f76fdbe92a216959073',
      'RequestedByMe': false,
      'Requested': true,
      'Seasons': [
        {'SeasonNumber': 1, 'EpisodeCount': 8, 'Status': 'Partial'},
        {'SeasonNumber': 2, 'EpisodeCount': 8, 'Status': 'None'},
      ],
    });
    expect(details.genres, ['Commedia']);
    expect(details.trailerUrl, 'https://www.youtube.com/watch?v=x');
    expect(details.seasons.map((s) => s.seasonNumber), [1, 2]);
    expect(details.requestableSeasons.map((s) => s.seasonNumber), [2]);
    expect(details.canBeRequested, isTrue);
    expect(details.requested, isTrue);
  });

  test('scheda di un film', () {
    final details = TitleDetails.fromJson({
      'MediaType': 'movie',
      'TmdbId': 841,
      'Title': 'Dune',
      'Genres': [],
      'RuntimeMinutes': 137,
      'Status': 'Pending',
      'RequestedByMe': true,
      'Requested': true,
    });
    expect(details.seasons, isEmpty);
    expect(details.runtimeMinutes, 137);
    expect(details.canBeRequested, isFalse);
  });

  test('richiesta, pagina, servizi, nuova richiesta', () {
    final page = RequestPage.fromJson({
      'Items': [
        {
          'Id': 434,
          'MediaType': 'tv',
          'TmdbId': 59941,
          'Title': 'Grey\'s Anatomy',
          'Year': 2005,
          'PosterPath': null,
          'Seasons': [14],
          'RequestedBy': {'Name': 'sronweb', 'IsMe': false},
          'CreatedAt': '2026-10-03T20:31:16+00:00',
          'Status': 'Downloading',
          'Progress': 0.75,
          'JellyfinItemId': null,
        },
      ],
      'HasMore': true,
    });
    final request = page.items.single;
    expect(page.hasMore, isTrue);
    expect(request.seasons, [14]);
    expect(request.requestedBy.name, 'sronweb');
    expect(request.createdAt, DateTime.utc(2026, 10, 3, 20, 31, 16));
    expect(request.status, RequestStatus.downloading);
    expect(request.progress, 0.75);

    final service = ServiceOption.fromJson({
      'Id': 1,
      'Name': 'Radarr Anime',
      'IsDefault': false,
      'Profiles': [
        {'Id': 7, 'Name': 'Anime Main Profile'},
      ],
      'RootFolders': ['/media/anime'],
      'DefaultProfileId': 7,
      'DefaultRootFolder': '/media/anime',
    });
    expect(service.profiles.single.name, 'Anime Main Profile');
    expect(service.rootFolders, ['/media/anime']);

    expect(CreatedRequest.fromJson({'Id': 7, 'Status': 'Pending'}).status,
        RequestStatus.pending);
    expect(ApproveChoice.defaults.toJson(), isEmpty);
    expect(
        const ApproveChoice(serverId: 1, profileId: 7, rootFolder: '/media/anime')
            .toJson(),
        {'ServerId': 1, 'ProfileId': 7, 'RootFolder': '/media/anime'});
  });

  test('immagini TMDB', () {
    expect(TmdbImages.poster('/p.jpg')!.url, 'https://image.tmdb.org/t/p/w342/p.jpg');
    expect(TmdbImages.backdrop('/b.jpg')!.url,
        'https://image.tmdb.org/t/p/w1280/b.jpg');
    expect(TmdbImages.poster(null), isNull);
    expect(TmdbImages.poster('p.jpg'), isNull);
  });
}
