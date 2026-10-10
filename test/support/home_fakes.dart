import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/social/home_api.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import 'collections_fakes.dart';
import 'fake_session_controller.dart';
import 'library_fakes.dart';
import 'requests_fakes.dart';
import 'social_fakes.dart';
import 'test_data.dart';

/// `HomeApi` in memoria: Home dell'admin e uscite configurabili, chiamate
/// contate.
class FakeHomeApi implements HomeApi {
  List<String>? layoutRows;
  Object? layoutError;
  int layoutCalls = 0;
  final setLayoutCalls = <List<String>?>[];

  UpcomingPage<UpcomingEpisode> series = const UpcomingPage();
  UpcomingPage<UpcomingMovie> movies = const UpcomingPage();
  Object? seriesError;
  Object? moviesError;

  /// Se valorizzato, [upcomingSeries] aspetta che si completi.
  Completer<void>? seriesGate;
  int seriesCalls = 0;
  int moviesCalls = 0;

  @override
  Future<List<String>?> layout() async {
    layoutCalls++;
    final error = layoutError;
    if (error != null) throw error;
    return layoutRows;
  }

  @override
  Future<List<String>?> setLayout(List<String>? rows) async {
    setLayoutCalls.add(rows);
    layoutRows = rows;
    return rows;
  }

  @override
  Future<UpcomingPage<UpcomingEpisode>> upcomingSeries() async {
    seriesCalls++;
    final gate = seriesGate;
    if (gate != null) await gate.future;
    final error = seriesError;
    if (error != null) throw error;
    return series;
  }

  @override
  Future<UpcomingPage<UpcomingMovie>> upcomingMovies() async {
    moviesCalls++;
    final error = moviesError;
    if (error != null) throw error;
    return movies;
  }
}

/// `DisplayPreferencesApi` in memoria.
class FakeDisplayPreferencesApi implements DisplayPreferencesApi {
  HomeUserPrefs prefs = HomeUserPrefs.none;
  Object? error;
  final readUsers = <String>[];
  final written = <(String, HomeUserPrefs)>[];
  final resets = <String>[];

  @override
  Future<HomeUserPrefs> readHome(String userId) async {
    readUsers.add(userId);
    final failure = error;
    if (failure != null) throw failure;
    return prefs;
  }

  @override
  Future<void> writeHome(String userId, HomeUserPrefs prefs) async {
    written.add((userId, prefs));
    this.prefs = prefs;
  }

  @override
  Future<void> resetHome(String userId) async {
    resets.add(userId);
    prefs = HomeUserPrefs.none;
  }
}

UpcomingEpisode testEpisode({
  String seriesName = 'The Bear',
  int season = 2,
  int episode = 5,
  int? last,
  DateTime? airDate,
  int? tmdbId = 136315,
  String? jellyfinSeriesId,
  String? backdropUrl = 'https://artworks.thetvdb.com/f.jpg',
}) =>
    UpcomingEpisode(
      seriesName: seriesName,
      seasonNumber: season,
      episodeNumber: episode,
      lastEpisodeNumber: last,
      airDate: airDate ?? DateTime.utc(2026, 10, 12, 1),
      tmdbId: tmdbId,
      jellyfinSeriesId: jellyfinSeriesId,
      backdropUrl: backdropUrl,
    );

UpcomingMovie testUpcomingMovie({
  String title = 'Hope',
  int tmdbId = 1058424,
  DateTime? digitalRelease,
}) =>
    UpcomingMovie(
      title: title,
      tmdbId: tmdbId,
      year: 2026,
      digitalRelease: digitalRelease ?? DateTime.utc(2026, 10, 13),
      posterUrl: 'https://image.tmdb.org/t/p/original/p.jpg',
    );

/// I provider della Home nei test: libreria, plugin, Seerr, saghe e
/// preferenze finti; funzioni del plugin [features], oppure [availability]
/// per cambiarle durante il test.
List<Override> homeOverrides({
  required FakeLibraryApi library,
  FakeHomeApi? home,
  FakeDisplayPreferencesApi? prefs,
  SocialFeatures features = SocialFeatures.none,
  FakeSocialAvailability? availability,
  FakeRequestsApi? requests,
  FakeCollectionsApi? collections,
  FakeSessionController? session,
}) =>
    [
      libraryApiProvider.overrideWithValue(library),
      homeApiProvider.overrideWithValue(home ?? FakeHomeApi()),
      displayPreferencesApiProvider
          .overrideWithValue(prefs ?? FakeDisplayPreferencesApi()),
      socialAvailabilityProvider.overrideWith(
          () => availability ?? FakeSocialAvailability(features)),
      requestsApiProvider.overrideWithValue(requests ?? FakeRequestsApi()),
      collectionsApiProvider
          .overrideWithValue(collections ?? FakeCollectionsApi()),
      sessionControllerProvider.overrideWith(() =>
          session ?? FakeSessionController(const SessionSignedIn(testUser))),
    ];
