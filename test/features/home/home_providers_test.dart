import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_rows_logic.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeHomeApi home;
  late FakeDisplayPreferencesApi prefs;
  late FakeRequestsApi requests;
  late FakeCollectionsApi collections;
  late FakeSocialAvailability availability;
  late FakeSessionController session;

  setUp(() {
    library = FakeLibraryApi();
    home = FakeHomeApi();
    prefs = FakeDisplayPreferencesApi();
    requests = FakeRequestsApi();
    collections = FakeCollectionsApi();
    availability = FakeSocialAvailability(SocialFeatures.none);
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: homeOverrides(
            library: library,
            home: home,
            prefs: prefs,
            availability: availability,
            requests: requests,
            collections: collections,
            session: session),
        retry: (_, _) => null,
      );

  Future<HomeLayout> layout(ProviderContainer c) {
    c.listen(homeLayoutProvider, (_, _) {});
    return c.read(homeLayoutProvider.future);
  }

  /// La Home dopo che Seerr ha risposto: la composizione non lo aspetta, si
  /// ricompone quando arriva.
  Future<HomeLayout> settledLayout(ProviderContainer c) async {
    c.listen(homeLayoutProvider, (_, _) {});
    await pumpEventQueue();
    return c.read(homeLayoutProvider.future);
  }

  Future<HomeRowContent> row(ProviderContainer c, HomeRowKind kind,
      {String language = 'it'}) {
    final key = (kind: kind, language: language);
    c.listen(homeRowProvider(key), (_, _) {});
    return c.read(homeRowProvider(key).future);
  }

  test('senza plugin: righe della libreria, ordine predefinito, nessuna chiamata al plugin',
      () async {
    final c = container();
    final result = await layout(c);
    expect(result.visible, [
      HomeRowKind.resume,
      HomeRowKind.nextUp,
      HomeRowKind.latestMovies,
      HomeRowKind.latestSeries,
      HomeRowKind.becauseYouWatched,
      HomeRowKind.myList,
    ]);
    expect(home.layoutCalls, 0);
    expect(prefs.readUsers, ['u1']);
    expect(requests.calls, isEmpty);
  });

  test('con il plugin: Home dell\'admin, ritocchi dell\'utente e righe disponibili',
      () async {
    availability = FakeSocialAvailability(const SocialFeatures(
        home: true,
        requests: true,
        collections: true,
        upcomingSeries: true,
        upcomingMovies: true));
    home.layoutRows = ['upcomingSeries', 'requests', 'resume', 'continueSaga'];
    prefs.prefs = const HomeUserPrefs(rows: ['resume'], hidden: ['continueSaga']);
    final result = await settledLayout(container());
    expect(result.visible,
        [HomeRowKind.upcomingSeries, HomeRowKind.requests, HomeRowKind.resume]);
    expect(home.layoutCalls, 1);
    expect(requests.calls, contains('me'));
  });

  test('Le mie richieste solo per chi è collegato a Seerr', () async {
    availability =
        FakeSocialAvailability(const SocialFeatures(requests: true));
    requests.meValue =
        const RequestsMe(canRequest: true, canManage: false, hasAccount: false);
    final result = await settledLayout(container());
    expect(requests.calls, contains('me'), reason: 'Seerr ha risposto');
    expect(result.visible, isNot(contains(HomeRowKind.requests)));
  });

  test('Seerr che non risponde: la Home si compone lo stesso, senza Le mie richieste',
      () {
    fakeAsync((async) {
      availability =
          FakeSocialAvailability(const SocialFeatures(requests: true));
      requests.meGate = Completer<void>();
      final c = container();
      HomeLayout? result;
      c.listen(homeLayoutProvider, (_, next) => result = next.value,
          fireImmediately: true);
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(requests.calls, ['me'], reason: '/Me è partito e non risponde');
      expect(result?.visible, [
        HomeRowKind.resume,
        HomeRowKind.nextUp,
        HomeRowKind.latestMovies,
        HomeRowKind.latestSeries,
        HomeRowKind.becauseYouWatched,
        HomeRowKind.myList,
      ]);
      c.dispose();
    });
  });

  test('Seerr risponde dopo: la Home si ricompone e aggiunge Le mie richieste',
      () {
    fakeAsync((async) {
      availability =
          FakeSocialAvailability(const SocialFeatures(home: true, requests: true));
      home.layoutRows = ['requests', 'resume'];
      final gate = requests.meGate = Completer<void>();
      final c = container();
      HomeLayout? result;
      c.listen(homeLayoutProvider, (_, next) => result = next.value,
          fireImmediately: true);
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(result?.visible, [HomeRowKind.resume]);
      gate.complete();
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(result?.visible, [HomeRowKind.requests, HomeRowKind.resume]);
      expect(home.layoutCalls, 1, reason: 'ricomporre non rilegge la Home');
      expect(prefs.readUsers, ['u1'], reason: 'né le preferenze');
      c.dispose();
    });
  });

  test('errori di lettura: ordine predefinito e nessun ritocco', () async {
    availability = FakeSocialAvailability(const SocialFeatures(home: true));
    home.layoutError = const ServerUnreachableException();
    prefs.error = const ServerUnreachableException();
    final result = await layout(container());
    expect(result.order, HomeRowKind.values);
  });

  test('homeUserPrefsProvider si rilegge al cambio di utente', () async {
    final c = container();
    await layout(c);
    session.set(const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
    await c.read(homeLayoutProvider.future);
    expect(prefs.readUsers, ['u1', 'u2']);
  });

  test('funzioni non ancora note: si aspetta, poi si ricompone', () {
    fakeAsync((async) {
      availability = FakeSocialAvailability(SocialFeatures.unknown);
      final c = container();
      HomeLayout? result;
      c.listen(homeLayoutProvider, (_, next) => result = next.value,
          fireImmediately: true);
      async.elapse(homeFeaturesWait - const Duration(milliseconds: 100));
      expect(result, isNull, reason: 'si aspettano le funzioni');
      availability.set(const SocialFeatures(upcomingSeries: true));
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(result?.visible, contains(HomeRowKind.upcomingSeries));
      c.dispose();
    });
  });

  test('funzioni mai arrivate: dopo l\'attesa la Home si compone senza', () {
    fakeAsync((async) {
      availability = FakeSocialAvailability(SocialFeatures.unknown);
      final c = container();
      HomeLayout? result;
      c.listen(homeLayoutProvider, (_, next) => result = next.value,
          fireImmediately: true);
      async.elapse(homeFeaturesWait + const Duration(milliseconds: 100));
      expect(result?.visible, contains(HomeRowKind.resume));
      expect(result?.visible, isNot(contains(HomeRowKind.upcomingSeries)));
      c.dispose();
    });
  });

  test('funzioni non ancora note, Home chiusa: nessun timer in sospeso', () {
    fakeAsync((async) {
      availability = FakeSocialAvailability(SocialFeatures.unknown);
      final c = container();
      c.listen(homeLayoutProvider, (_, _) {}, fireImmediately: true);
      async.elapse(const Duration(milliseconds: 100));
      c.dispose();
      async.flushMicrotasks();
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('righe della libreria: limiti e prossimi episodi dell\'ultimo anno',
      () async {
    library
      ..resumeItems = [testItem(id: 'r1')]
      ..nextUpItems = [testItem(id: 'n1', kind: ItemKind.episode)]
      ..onItems = (query, start, limit) => query.favoritesOnly
          ? pageOf([testItem(id: 'f1')])
          : pageOf([testItem(id: 'm1')]);
    final c = container();
    expect(((await row(c, HomeRowKind.resume)) as ItemsRowContent).items.single.id,
        'r1');
    expect(((await row(c, HomeRowKind.nextUp)) as ItemsRowContent).items.single.id,
        'n1');
    final cutoff = library.nextUpCutoffs.single!;
    expect(DateTime.now().difference(cutoff).inDays, inInclusiveRange(364, 365));
    expect(((await row(c, HomeRowKind.myList)) as ItemsRowContent).items.single.id,
        'f1');
    expect(
        ((await row(c, HomeRowKind.latestMovies)) as ItemsRowContent)
            .items
            .single
            .id,
        'm1');
    expect(library.itemQueries.where((q) => q.favoritesOnly).single.kinds,
        {ItemKind.movie, ItemKind.series});
  });

  test('Perché hai visto X e Continua la saga dai loro caricamenti', () async {
    availability =
        FakeSocialAvailability(const SocialFeatures(collections: true));
    library
      ..playHistoryItems = [testItem(id: 'm9', name: 'Dune')]
      ..similarById['m9'] = [
        for (final id in ['a', 'b', 'c', 'd']) testItem(id: id),
      ]
      ..playedMovieItems = [testItem(id: 'm1')]
      ..itemsById['m2'] = testItem(id: 'm2', name: 'Matrix Reloaded');
    collections.collectionsList = [
      testCollection(id: 'c1', name: 'Matrix', itemIds: ['m1', 'm2']),
    ];
    final c = container();
    final because =
        await row(c, HomeRowKind.becauseYouWatched) as BecauseYouWatchedContent;
    expect(because.sourceName, 'Dune');
    final sagas = await row(c, HomeRowKind.continueSaga) as SagasRowContent;
    expect(sagas.sagas.single.next.name, 'Matrix Reloaded');
  });

  test('Le mie richieste: filtro mine, lingua della Home, regole della riga',
      () async {
    requests.lists[RequestsFilter.mine] = [
      testMediaRequest(id: 1, status: RequestStatus.declined),
      testMediaRequest(id: 2, status: RequestStatus.pending),
    ];
    final content = await row(container(), HomeRowKind.requests,
        language: 'en') as RequestsRowContent;
    expect(content.requests.map((r) => r.id), [2]);
    expect(requests.calls, contains('list:mine:0:$homeRequestsTake'));
    expect(requests.listLanguages, ['en']);
  });

  test('uscite: elenco limitato, errore del plugin come riga vuota', () async {
    home
      ..series = UpcomingPage(items: [for (var i = 0; i < 25; i++) testEpisode(episode: i + 1)])
      ..movies = const UpcomingPage(error: UpcomingError.unreachable);
    final c = container();
    expect(
        ((await row(c, HomeRowKind.upcomingSeries)) as UpcomingSeriesRowContent)
            .episodes,
        hasLength(homeRowLimit));
    expect((await row(c, HomeRowKind.upcomingMovies)).isEmpty, isTrue);
  });

  test('righe esterne: tenute 5 minuti senza ascoltatori', () {
    fakeAsync((async) {
      final c = container();
      final key = (kind: HomeRowKind.upcomingSeries, language: 'it');
      final sub = c.listen(homeRowProvider(key), (_, _) {});
      async.flushMicrotasks();
      sub.close();
      async.elapse(const Duration(minutes: 4));
      c.listen(homeRowProvider(key), (_, _) {}).close();
      async.flushMicrotasks();
      expect(home.seriesCalls, 1, reason: 'entro 5 minuti non si rilegge');
      async.elapse(homeExternalRefresh);
      c.listen(homeRowProvider(key), (_, _) {});
      async.flushMicrotasks();
      expect(home.seriesCalls, 2);
      c.dispose();
    });
  });

  test('riga esterna chiusa mentre legge: il risultato non si tiene', () {
    fakeAsync((async) {
      final gate = home.seriesGate = Completer<void>();
      final c = container();
      final key = (kind: HomeRowKind.upcomingSeries, language: 'it');
      final sub = c.listen(homeRowProvider(key), (_, _) {});
      async.flushMicrotasks();
      expect(home.seriesCalls, 1);
      sub.close();
      async.elapse(Duration.zero);
      gate.complete();
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      c.listen(homeRowProvider(key), (_, _) {});
      async.flushMicrotasks();
      expect(home.seriesCalls, 2, reason: 'la lettura chiusa non è in memoria');
      c.dispose();
    });
  });

  group('righe esterne e cambio di utente', () {
    const luigi = SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi'));

    /// Nell'app la sessione c'è sempre; qui nessuno la legge prima del
    /// cambio, e un notifier mai letto non si può cambiare.
    ProviderContainer appContainer() {
      final c = container();
      c.listen(sessionControllerProvider, (_, _) {});
      return c;
    }

    int listCalls() =>
        requests.calls.where((call) => call.startsWith('list:')).length;

    test('Le mie richieste: tenute in memoria, non passano al nuovo utente',
        () async {
      requests.lists[RequestsFilter.mine] = [
        testMediaRequest(id: 1, status: RequestStatus.pending),
      ];
      final c = appContainer();
      final key = (kind: HomeRowKind.requests, language: 'it');
      final sub = c.listen(homeRowProvider(key), (_, _) {});
      final first = await c.read(homeRowProvider(key).future);
      expect((first as RequestsRowContent).requests.map((r) => r.id), [1]);
      sub.close();

      session.set(luigi);
      requests.lists[RequestsFilter.mine] = [
        testMediaRequest(id: 2, status: RequestStatus.pending),
      ];
      final second = await row(c, HomeRowKind.requests);
      expect(listCalls(), 2, reason: 'le richieste di Mario non sono di Luigi');
      expect((second as RequestsRowContent).requests.map((r) => r.id), [2]);
    });

    test('Le mie richieste: con la Home aperta si rilegge al cambio di utente',
        () async {
      requests.lists[RequestsFilter.mine] = [
        testMediaRequest(id: 1, status: RequestStatus.pending),
      ];
      final c = appContainer();
      final key = (kind: HomeRowKind.requests, language: 'it');
      final seen = <List<int>>[];
      c.listen(homeRowProvider(key), (_, next) {
        final content = next.value;
        if (content is RequestsRowContent) {
          seen.add([for (final r in content.requests) r.id]);
        }
      });
      await c.read(homeRowProvider(key).future);

      requests.lists[RequestsFilter.mine] = [
        testMediaRequest(id: 2, status: RequestStatus.pending),
      ];
      session.set(luigi);
      await pumpEventQueue();
      expect(listCalls(), 2);
      expect(seen.last, [2]);
    });

    test('Serie in arrivo: tenute in memoria, non passano al nuovo utente',
        () async {
      home.series = UpcomingPage(
          items: [testEpisode(seriesName: 'The Bear', jellyfinSeriesId: 's-mario')]);
      final c = appContainer();
      final key = (kind: HomeRowKind.upcomingSeries, language: 'it');
      final sub = c.listen(homeRowProvider(key), (_, _) {});
      final first = await c.read(homeRowProvider(key).future);
      expect((first as UpcomingSeriesRowContent).episodes.single.jellyfinSeriesId,
          's-mario');
      sub.close();

      session.set(luigi);
      home.series = UpcomingPage(
          items: [testEpisode(seriesName: 'The Bear', jellyfinSeriesId: 's-luigi')]);
      final second = await row(c, HomeRowKind.upcomingSeries);
      expect(home.seriesCalls, 2);
      expect((second as UpcomingSeriesRowContent).episodes.single.jellyfinSeriesId,
          's-luigi');
    });

    test('Serie in arrivo: con la Home aperta si rilegge al cambio di utente',
        () async {
      final c = appContainer();
      final key = (kind: HomeRowKind.upcomingSeries, language: 'it');
      c.listen(homeRowProvider(key), (_, _) {});
      await c.read(homeRowProvider(key).future);
      session.set(luigi);
      await pumpEventQueue();
      expect(home.seriesCalls, 2);
    });

    test('Film in arrivo: tenuti in memoria, non passano al nuovo utente',
        () async {
      home.movies =
          UpcomingPage(items: [testUpcomingMovie(title: 'Hope', tmdbId: 1)]);
      final c = appContainer();
      final key = (kind: HomeRowKind.upcomingMovies, language: 'it');
      final sub = c.listen(homeRowProvider(key), (_, _) {});
      await c.read(homeRowProvider(key).future);
      sub.close();

      session.set(luigi);
      home.movies =
          UpcomingPage(items: [testUpcomingMovie(title: 'Alien', tmdbId: 2)]);
      final second = await row(c, HomeRowKind.upcomingMovies);
      expect(home.moviesCalls, 2);
      expect((second as UpcomingMoviesRowContent).movies.single.title, 'Alien');
    });

    test('Film in arrivo: con la Home aperta si rilegge al cambio di utente',
        () async {
      final c = appContainer();
      final key = (kind: HomeRowKind.upcomingMovies, language: 'it');
      c.listen(homeRowProvider(key), (_, _) {});
      await c.read(homeRowProvider(key).future);
      session.set(luigi);
      await pumpEventQueue();
      expect(home.moviesCalls, 2);
    });
  });

  test('keepFor su un provider già eliminato non fa nulla', () {
    fakeAsync((async) {
      Ref? kept;
      final provider = Provider.autoDispose((ref) {
        kept = ref;
        return 0;
      });
      final c = ProviderContainer();
      c.read(provider);
      c.dispose();
      expect(() => keepFor(kept!, homeExternalRefresh), returnsNormally);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('carosello: serie non lette, restano i film; con tutte e due, l\'errore',
      () async {
    library.onItems = (query, start, limit) {
      if (query.kinds.contains(ItemKind.series)) {
        throw const ServerUnreachableException();
      }
      return pageOf([testItem(id: 'm1')]);
    };
    final c = container();
    c.listen(homeFeaturedProvider, (_, _) {});
    expect((await c.read(homeFeaturedProvider.future)).map((i) => i.id), ['m1']);

    library.error = const ServerUnreachableException();
    c.invalidate(homeLatestMoviesProvider);
    c.invalidate(homeLatestSeriesProvider);
    await expectLater(c.read(homeFeaturedProvider.future),
        throwsA(isA<ServerUnreachableException>()));
  });

  test('carosello: film non letti, restano le serie', () async {
    library.onItems = (query, start, limit) {
      if (query.kinds.contains(ItemKind.movie)) {
        throw const ServerUnreachableException();
      }
      return pageOf([testItem(id: 's1', kind: ItemKind.series)]);
    };
    final c = container();
    c.listen(homeFeaturedProvider, (_, _) {});
    expect((await c.read(homeFeaturedProvider.future)).map((i) => i.id), ['s1']);
  });
}
