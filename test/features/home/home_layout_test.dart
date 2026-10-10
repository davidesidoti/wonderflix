import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/social/social_providers.dart';

void main() {
  List<String> ids(Iterable<HomeRowKind> rows) => [for (final r in rows) r.id];
  List<HomeRowKind> rows(List<String> ids) => parseHomeRows(ids);

  test('gli id delle righe e l\'ordine predefinito', () {
    expect(ids(HomeRowKind.values), [
      'resume', 'nextUp', 'requests', 'latestMovies', 'latestSeries',
      'becauseYouWatched', 'continueSaga', 'upcomingSeries', 'upcomingMovies',
      'myList',
    ]);
    expect(HomeRowKind.parse('myList'), HomeRowKind.myList);
    expect(HomeRowKind.parse('MyList'), isNull);
    expect([for (final r in HomeRowKind.values) if (!r.fromJellyfin) r], [
      HomeRowKind.requests,
      HomeRowKind.upcomingSeries,
      HomeRowKind.upcomingMovies,
    ]);
  });

  test('parseHomeRows: sconosciuti e doppioni via, ordine tenuto', () {
    expect(ids(rows(['myList', 'bogus', 'resume', 'myList'])),
        ['myList', 'resume']);
  });

  test('l\'esempio della spec (§6.4)', () {
    final layout = composeHomeLayout(
      adminRows: ['resume', 'nextUp', 'requests', 'upcomingSeries'],
      user: const HomeUserPrefs(
          rows: ['nextUp', 'resume'], hidden: ['requests']),
      available: (_) => true,
    );
    expect(ids(layout.order),
        ['nextUp', 'resume', 'requests', 'upcomingSeries']);
    expect(layout.hidden, {HomeRowKind.requests});
    expect(ids(layout.visible), ['nextUp', 'resume', 'upcomingSeries']);
  });

  test('senza Home dell\'admin: tutte, nell\'ordine predefinito', () {
    final layout = composeHomeLayout(
        adminRows: null, user: HomeUserPrefs.none, available: (_) => true);
    expect(layout.order, HomeRowKind.values);
    expect(layout.visible, HomeRowKind.values);
  });

  test('Home dell\'admin vuota: nessuna riga, qualunque cosa dica l\'utente',
      () {
    final layout = composeHomeLayout(
        adminRows: const [],
        user: const HomeUserPrefs(rows: ['resume']),
        available: (_) => true);
    expect(layout.order, isEmpty);
    expect(layout.visible, isEmpty);
  });

  test('una riga che l\'utente non ha sistemato va dopo quelle che la precedono',
      () {
    // A = resume, nextUp, requests, latestMovies; U = latestMovies, resume.
    expect(
        ids(homeRowOrder(
            admin: rows(['resume', 'nextUp', 'requests', 'latestMovies']),
            user: rows(['latestMovies', 'resume']))),
        ['latestMovies', 'resume', 'nextUp', 'requests']);
    // Nessuna riga la precede in A: in testa.
    expect(
        ids(homeRowOrder(
            admin: rows(['resume', 'nextUp', 'myList']),
            user: rows(['myList']))),
        ['resume', 'nextUp', 'myList']);
  });

  test('le righe dell\'utente che l\'admin ha spento non ci sono', () {
    expect(
        ids(homeRowOrder(
            admin: rows(['resume']), user: rows(['myList', 'resume']))),
        ['resume']);
  });

  test('righe non disponibili: nell\'ordine, ma non visibili', () {
    final layout = composeHomeLayout(
        adminRows: null,
        user: HomeUserPrefs.none,
        available: (row) => row != HomeRowKind.upcomingSeries);
    expect(layout.order, contains(HomeRowKind.upcomingSeries));
    expect(layout.visible, isNot(contains(HomeRowKind.upcomingSeries)));
  });

  test('id sconosciuti dell\'utente si ignorano', () {
    final layout = composeHomeLayout(
        adminRows: ['resume', 'myList'],
        user: const HomeUserPrefs(
            rows: ['rigaFutura', 'myList'], hidden: ['altraRiga']),
        available: (_) => true);
    // `resume` non è nell'ordine dell'utente e nessuna riga la precede in A.
    expect(ids(layout.order), ['resume', 'myList']);
    expect(layout.hidden, isEmpty);
    // L'id ignoto non toglie nulla all'ordine che l'utente ha dato davvero.
    final arranged = composeHomeLayout(
        adminRows: ['resume', 'myList'],
        user: const HomeUserPrefs(rows: ['rigaFutura', 'myList', 'resume']),
        available: (_) => true);
    expect(ids(arranged.order), ['myList', 'resume']);
  });

  test('homeRowGate (§6.5)', () {
    const none = SocialFeatures.none;
    const all = SocialFeatures(
        requests: true,
        collections: true,
        upcomingSeries: true,
        upcomingMovies: true);
    expect(homeRowGate(HomeRowKind.resume, none, seerrAccount: false),
        HomeRowGate.available);
    expect(homeRowGate(HomeRowKind.requests, none, seerrAccount: true),
        HomeRowGate.seerrOff);
    expect(homeRowGate(HomeRowKind.requests, all, seerrAccount: false),
        HomeRowGate.noSeerrAccount);
    expect(homeRowGate(HomeRowKind.requests, all, seerrAccount: true),
        HomeRowGate.available);
    expect(homeRowGate(HomeRowKind.continueSaga, none, seerrAccount: false),
        HomeRowGate.sagasOff);
    expect(homeRowGate(HomeRowKind.upcomingSeries, none, seerrAccount: false),
        HomeRowGate.sonarrOff);
    expect(homeRowGate(HomeRowKind.upcomingMovies, none, seerrAccount: false),
        HomeRowGate.radarrOff);
    for (final row in [
      HomeRowKind.continueSaga,
      HomeRowKind.upcomingSeries,
      HomeRowKind.upcomingMovies,
    ]) {
      expect(homeRowGate(row, all, seerrAccount: false), HomeRowGate.available);
    }
  });
}
