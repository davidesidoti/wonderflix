import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/catalog/catalog_genre_index.dart';
import 'package:wonderflix/features/catalog/catalog_genres.dart';

import '../../support/pump_app.dart';

void main() {
  Future<List<String?>> pump(
    WidgetTester tester, {
    ItemKind kind = ItemKind.movie,
    AsyncValue<List<GenreCount>>? genres,
    String? selected,
    bool tv = false,
  }) async {
    final picked = <String?>[];
    await pumpApp(
      tester,
      Scaffold(
        body: CatalogGenreIndex(
          kind: kind,
          genres:
              genres ??
              const AsyncData([
                GenreCount('Azione', 330),
                GenreCount('Horror', 12),
              ]),
          total: 801,
          selected: selected,
          onSelected: picked.add,
        ),
      ),
      tv: tv,
    );
    return picked;
  }

  testWidgets('nomi e numeri nell ordine in cui arrivano', (tester) async {
    await pump(tester);
    expect(find.text('801'), findsOneWidget);
    expect(find.text('330'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    final xs = [
      for (final t in ['Tutti', 'Azione', 'Horror'])
        tester.getTopLeft(find.text(t)).dx,
    ];
    expect(xs, [...xs]..sort());
  });

  testWidgets('un tocco sceglie il genere, Tutti lo toglie', (tester) async {
    final picked = await pump(tester, selected: 'Azione');
    await tester.tap(find.text('Horror'));
    await tester.tap(find.text('Tutti'));
    expect(picked, ['Horror', null]);
  });

  testWidgets('con un errore, senza generi o in attesa resta solo Tutti', (
    tester,
  ) async {
    for (final genres in <AsyncValue<List<GenreCount>>>[
      AsyncError(Exception('x'), StackTrace.empty),
      const AsyncData([]),
      const AsyncLoading(),
    ]) {
      await pump(tester, genres: genres);
      expect(find.text('Tutti'), findsOneWidget);
      expect(find.text('Azione'), findsNothing);
    }
  });

  testWidgets('per le serie la prima voce è Tutte', (tester) async {
    await pump(tester, kind: ItemKind.series);
    expect(find.text('Tutte'), findsOneWidget);
    expect(find.text('Tutti'), findsNothing);
  });

  testWidgets('sulla TV il genere scelto prende il focus', (tester) async {
    await pump(tester, selected: 'Horror', tv: true);
    await tester.pump();
    // Il focus primario avvolge il genere scelto e non Tutti.
    final focused = FocusManager.instance.primaryFocus!.context!;
    Finder inside(String label) => find.descendant(
      of: find.byElementPredicate((e) => e == focused),
      matching: find.text(label),
    );
    expect(inside('Horror'), findsOneWidget);
    expect(inside('Tutti'), findsNothing);
  });
}
