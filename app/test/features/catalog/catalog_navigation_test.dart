import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/catalog/catalog_navigation.dart';

void main() {
  test('la vista dall\'indirizzo: le saghe solo con view=sagas', () {
    expect(CatalogView.parse('sagas'), CatalogView.sagas);
    expect(CatalogView.parse('titles'), CatalogView.titles);
    expect(CatalogView.parse(null), CatalogView.titles);
    expect(CatalogView.parse('altro'), CatalogView.titles);
  });

  testWidgets('openCatalog: indirizzi con vista e genere', (tester) async {
    late BuildContext ctx;
    final router = GoRouter(initialLocation: '/start', routes: [
      GoRoute(
          path: '/:p',
          builder: (c, s) {
            ctx = c;
            return const SizedBox();
          }),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();
    Future<void> open(ItemKind kind, {CatalogView? view, String? genre}) async {
      view == null && genre == null
          ? openCatalog(ctx, kind)
          : openCatalog(ctx, kind,
              view: view ?? CatalogView.titles, genre: genre);
      await tester.pumpAndSettle();
    }

    await open(ItemKind.movie);
    expect(location(), '/movies');
    await open(ItemKind.movie, genre: 'Fantascienza');
    expect(location(), '/movies?genre=Fantascienza');
    await open(ItemKind.movie, genre: 'Slice of Life');
    expect(Uri.parse(location()).queryParameters['genre'], 'Slice of Life');
    await open(ItemKind.movie, view: CatalogView.sagas);
    expect(location(), '/movies?view=sagas');
    await open(ItemKind.series, genre: 'Dramma');
    expect(location(), '/series?genre=Dramma');
  });

  testWidgets('openCatalogSearch apre il catalogo con la ricerca e Indietro '
      'torna', (tester) async {
    late BuildContext ctx;
    final router = GoRouter(initialLocation: '/search', routes: [
      GoRoute(
          path: '/:p',
          builder: (c, s) {
            ctx = c;
            return const SizedBox();
          }),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    String location() =>
        router.state.uri.toString();

    openCatalogSearch(ctx, ItemKind.movie, 'ist');
    await tester.pumpAndSettle();
    expect(location(), '/movies?q=ist');
    router.pop();
    await tester.pumpAndSettle();
    expect(location(), '/search');

    openCatalogSearch(ctx, ItemKind.series, 'l’ist');
    await tester.pumpAndSettle();
    expect(Uri.parse(location()).path, '/series');
    expect(Uri.parse(location()).queryParameters['q'], 'l’ist');
  });
}
