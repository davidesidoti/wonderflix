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

  /// La risposta di [testArr].
  ArrTestResults arrTest = const ArrTestResults(
    sonarr: ArrTestResult(configured: true, ok: true, version: '4.0.20'),
    radarr: ArrTestResult(configured: true, ok: true, version: '6.4.4'),
  );
  Object? arrTestError;
  int arrTestCalls = 0;

  Object? setLayoutError;

  /// Se valorizzato, [setLayout] aspetta che si completi.
  Completer<void>? setLayoutGate;

  @override
  Future<ArrTestResults> testArr() async {
    arrTestCalls++;
    final error = arrTestError;
    if (error != null) throw error;
    return arrTest;
  }

  @override
  Future<List<String>?> setLayout(List<String>? rows) async {
    setLayoutCalls.add(rows);
    final gate = setLayoutGate;
    if (gate != null) await gate.future;
    final error = setLayoutError;
    if (error != null) throw error;
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

  CalendarPage calendarPage = const CalendarPage();
  Object? calendarError;
  final calendarCalls = <(DateTime, DateTime)>[];

  @override
  Future<CalendarPage> calendar(DateTime start, DateTime end) async {
    calendarCalls.add((start, end));
    final error = calendarError;
    if (error != null) throw error;
    return calendarPage;
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

  /// Se valorizzato, [readHome] aspetta che si completi (dopo aver
  /// registrato la chiamata).
  Completer<void>? readGate;

  @override
  Future<HomeUserPrefs> readHome(String userId) async {
    readUsers.add(userId);
    final gate = readGate;
    if (gate != null) await gate.future;
    final failure = error;
    if (failure != null) throw failure;
    return prefs;
  }

  Object? writeError;
  Object? resetError;

  /// Se valorizzato, [writeHome] aspetta che si completi (dopo aver
  /// registrato la chiamata).
  Completer<void>? writeGate;

  @override
  Future<void> writeHome(String userId, HomeUserPrefs prefs) async {
    written.add((userId, prefs));
    final gate = writeGate;
    if (gate != null) await gate.future;
    final error = writeError;
    if (error != null) throw error;
    this.prefs = prefs;
  }

  /// Se valorizzato, [resetHome] aspetta che si completi (dopo aver
  /// registrato la chiamata).
  Completer<void>? resetGate;

  @override
  Future<void> resetHome(String userId) async {
    resets.add(userId);
    final gate = resetGate;
    if (gate != null) await gate.future;
    final error = resetError;
    if (error != null) throw error;
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
  FakeSocialApi? social,
}) =>
    [
      socialApiProvider.overrideWithValue(social ?? FakeSocialApi()),
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

/// Quello che serve alla sezione Home delle Impostazioni: va aggiunto ai test
/// che montano `SettingsScreen`, che hanno già l'utente collegato.
List<Override> homeSettingsOverrides({
  FakeDisplayPreferencesApi? prefs,
  FakeHomeApi? home,
  SocialFeatures features = SocialFeatures.none,
  FakeSocialApi? social,
}) =>
    [
      socialApiProvider.overrideWithValue(social ?? FakeSocialApi()),
      displayPreferencesApiProvider
          .overrideWithValue(prefs ?? FakeDisplayPreferencesApi()),
      homeApiProvider.overrideWithValue(home ?? FakeHomeApi()),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ];
