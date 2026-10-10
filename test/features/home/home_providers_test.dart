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

  Future<HomeRowContent> row(ProviderContainer c, HomeRowKind kind) {
    final key = (kind: kind, language: 'it');
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
    final result = await layout(container());
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
    expect((await layout(container())).visible,
        isNot(contains(HomeRowKind.requests)));
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
    final content =
        await row(container(), HomeRowKind.requests) as RequestsRowContent;
    expect(content.requests.map((r) => r.id), [2]);
    expect(requests.calls, contains('list:mine:0:$homeRequestsTake'));
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

  test('carosello: con una lettura fallita restano i titoli dell\'altra',
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
}
