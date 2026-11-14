import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/item_query.dart';
import 'package:wonderflix/features/catalog/catalog_band.dart';
import 'package:wonderflix/features/catalog/catalog_genres.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';

JellyfinItem _item(String id, {bool backdrop = false}) => JellyfinItem(
  id: id,
  name: id,
  kind: ItemKind.movie,
  backdropTags: backdrop ? ['b$id'] : const [],
);

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  test('catalogBandHero salta i titoli senza fondale', () {
    expect(
      catalogBandHero([
        _item('a'),
        _item('b', backdrop: true),
        _item('c', backdrop: true),
      ])?.id,
      'b',
    );
    expect(catalogBandHero([_item('a')]), isNull);
    expect(catalogBandHero(const []), isNull);
  });

  test('catalogBandLine: conteggi e ordine', () {
    expect(
      catalogBandLine(
        it,
        kind: ItemKind.movie,
        sort: CatalogSort.rating,
        reversed: false,
        totals: const CatalogTotals(243, 211),
      ),
      '243 film, 211 già visti. I più votati per primi.',
    );
    expect(
      catalogBandLine(
        it,
        kind: ItemKind.movie,
        sort: CatalogSort.rating,
        reversed: false,
      ),
      'I più votati per primi.',
    );
    expect(
      catalogBandLine(
        it,
        kind: ItemKind.series,
        sort: CatalogSort.dateAdded,
        reversed: true,
        totals: const CatalogTotals(138, 41),
      ),
      '138 serie, 41 in corso. Le ferme da più tempo per prime.',
    );
    expect(
      catalogBandLine(
        it,
        kind: ItemKind.series,
        sort: CatalogSort.dateAdded,
        reversed: false,
      ),
      'Nuovi episodi per prime.',
    );
    expect(
      catalogBandLine(
        it,
        kind: ItemKind.movie,
        sort: CatalogSort.title,
        reversed: true,
      ),
      'Dalla Z alla A.',
    );
  });

  testWidgets('senza titolo con fondale: solo testo, nessuna immagine', (
    tester,
  ) async {
    var built = 0;
    await pumpApp(
      tester,
      const Scaffold(
        body: CatalogBand(title: 'Western', height: 320, line: 'Riga.'),
      ),
      overrides: [
        imageBuilderProvider.overrideWithValue((image, fit) {
          built++;
          return const SizedBox();
        }),
      ],
    );
    expect(built, 0);
    expect(find.text('Western'), findsOneWidget);
    expect(find.text('Riga.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mostra il fondale del titolo dato, fuori dalla semantica', (
    tester,
  ) async {
    final urls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: CatalogBand(
          title: 'Azione',
          height: 320,
          hero: catalogBandHero([_item('a'), _item('x', backdrop: true)]),
          tabs: const Text('schede'),
        ),
      ),
      overrides: [
        imageBuilderProvider.overrideWithValue((image, fit) {
          urls.add(image.url);
          return const SizedBox();
        }),
      ],
    );
    expect(urls, isNotEmpty);
    expect(urls.every((u) => u.contains('/Items/x/Images/Backdrop')), isTrue);
    expect(find.text('schede'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(WfImage),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });
}
