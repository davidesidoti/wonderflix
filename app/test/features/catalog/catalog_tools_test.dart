import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/catalog/catalog_genres.dart';
import 'package:wonderflix/features/catalog/catalog_tools.dart';

import '../../support/pump_app.dart';

void main() {
  const movies = ItemQuery(kinds: {ItemKind.movie});
  const series = ItemQuery(kinds: {ItemKind.series});

  Future<List<ItemQuery>> pump(
    WidgetTester tester, {
    ItemQuery query = movies,
    CatalogTotals? totals,
    Size size = const Size(1440, 900),
    bool tv = false,
  }) async {
    final changes = <ItemQuery>[];
    await pumpApp(
      tester,
      Scaffold(
        body: CatalogTools(
          kind: query.kinds.first,
          query: query,
          onChanged: changes.add,
          totals: totals,
        ),
      ),
      surfaceSize: size,
      tv: tv,
    );
    return changes;
  }

  Future<void> choose(WidgetTester tester, String current, String next) async {
    await tester.tap(find.text(current));
    await tester.pumpAndSettle();
    await tester.tap(find.text(next).last);
    await tester.pumpAndSettle();
  }

  testWidgets('cambiare l ordine azzera il verso', (tester) async {
    final changes = await pump(
      tester,
      query: movies.copyWith(sort: CatalogSort.rating, reversed: true),
    );
    await choose(tester, 'Ordina: Voto', 'Ordina: Titolo');
    expect(changes.single.sort, CatalogSort.title);
    expect(changes.single.reversed, isFalse);
  });

  testWidgets('per le serie il primo ordine è Nuovi episodi', (tester) async {
    await pump(tester, query: series.copyWith(sort: CatalogSort.dateAdded));
    expect(find.text('Ordina: Nuovi episodi'), findsOneWidget);
  });

  testWidgets('la freccia inverte il verso', (tester) async {
    final changes = await pump(tester);
    await tester.tap(find.byTooltip("Inverti l'ordine"));
    expect(changes.single.reversed, isTrue);
  });

  testWidgets('Prima vale olderDecades', (tester) async {
    final changes = await pump(tester);
    await choose(tester, 'Decennio: Tutti', 'Decennio: Prima');
    expect(changes.single.decade, ItemQuery.olderDecades);
  });

  testWidgets('Nascondi i visti accende e spegne', (tester) async {
    var changes = await pump(tester);
    await tester.tap(find.text('Nascondi i visti'));
    expect(changes.single.watched, WatchedFilter.unwatched);
    changes = await pump(
      tester,
      query: movies.copyWith(watched: WatchedFilter.unwatched),
    );
    await tester.tap(find.text('Nascondi i visti'));
    expect(changes.single.watched, WatchedFilter.all);
  });

  testWidgets('serie: stato con i numeri, e Nascondi le viste', (tester) async {
    var changes = await pump(
      tester,
      query: series,
      totals: const CatalogTotals(188, 66),
    );
    expect(find.text('Nascondi le viste'), findsOneWidget);
    expect(find.text('In corso 66'), findsOneWidget);
    await tester.tap(find.text('Concluse 122'));
    expect(changes.single.seriesStatus, SeriesStatusFilter.ended);
    changes = await pump(tester, query: series);
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Tutte'), findsOneWidget);
  });

  testWidgets('i film non hanno lo stato', (tester) async {
    await pump(tester);
    expect(find.text('Concluse'), findsNothing);
  });

  testWidgets('Azzera filtri solo con un raffinamento', (tester) async {
    await pump(tester);
    expect(find.text('Azzera filtri'), findsNothing);
    final changes = await pump(tester, query: movies.copyWith(decade: 2010));
    await tester.tap(find.text('Azzera filtri'));
    expect(changes.single.decade, isNull);
    expect(changes.single.hasRefinements, isFalse);
  });

  testWidgets('la ricerca aspetta 300 ms dall ultimo tasto', (tester) async {
    final changes = await pump(tester);
    for (final text in ['d', 'du', 'dun', 'dune']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(changes, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    expect(changes.single.searchTerm, 'dune');
  });

  testWidgets('svuotare il campo toglie la ricerca', (tester) async {
    final changes = await pump(
      tester,
      query: movies.copyWith(searchTerm: 'dune'),
    );
    expect(find.text('dune'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(changes.single.searchTerm, '');
  });

  testWidgets('stretto: occhio, lente e il campo al posto della riga', (
    tester,
  ) async {
    final changes = await pump(tester, size: const Size(390, 800));
    expect(find.byTooltip('Nascondi i visti'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Cerca tra i film'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Chiudi'), findsOneWidget);
    expect(find.byTooltip("Inverti l'ordine"), findsNothing);
    await tester.tap(find.text('Chiudi'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(changes, isEmpty);
    await tester.tap(find.byTooltip('Nascondi i visti'));
    expect(changes.single.watched, WatchedFilter.unwatched);
  });

  testWidgets('stretto, serie: Filtri con dentro lo stato', (tester) async {
    final changes = await pump(
      tester,
      query: series,
      size: const Size(390, 800),
      totals: const CatalogTotals(188, 66),
    );
    expect(find.text('Concluse 122'), findsNothing);
    await tester.tap(find.text('Filtri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concluse 122'));
    await tester.pumpAndSettle();
    expect(changes.single.seriesStatus, SeriesStatusFilter.ended);
  });

  testWidgets('stretto, serie: decennio e stato nel foglio si sommano', (
    tester,
  ) async {
    final changes = await pump(
      tester,
      query: series,
      size: const Size(390, 800),
      totals: const CatalogTotals(188, 66),
    );
    await tester.tap(find.text('Filtri'));
    await tester.pumpAndSettle();
    await choose(tester, 'Decennio: Tutti', 'Decennio: 2010');
    // Il menu del foglio mostra la scelta appena fatta.
    expect(find.text('Decennio: 2010'), findsOneWidget);
    await tester.tap(find.text('Concluse 122'));
    await tester.pumpAndSettle();
    expect(changes.last.decade, 2010);
    expect(changes.last.seriesStatus, SeriesStatusFilter.ended);
  });

  testWidgets('stretto: Chiudi toglie la ricerca attiva', (tester) async {
    final changes = await pump(
      tester,
      query: movies.copyWith(searchTerm: 'dune'),
      size: const Size(390, 800),
    );
    await tester.tap(find.byTooltip('Cerca tra i film'));
    await tester.pump();
    expect(find.text('dune'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pump();
    expect(changes.single.searchTerm, isNull);
  });

  testWidgets('TV: niente ricerca, gli altri attrezzi ci sono', (tester) async {
    await pump(tester, size: const Size(960, 540), tv: true);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip("Inverti l'ordine"), findsOneWidget);
    expect(find.text('Nascondi i visti'), findsOneWidget);
  });
}
