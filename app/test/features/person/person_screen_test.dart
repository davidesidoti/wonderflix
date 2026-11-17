import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/ui/media_row.dart';
import 'package:wonderflix/ui/poster_card.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  testWidgets('biografia e filmografia sul server', (tester) async {
    final api = FakeLibraryApi()
      ..itemsById['p9'] = testItem(
          id: 'p9',
          name: 'Zendaya',
          kind: ItemKind.person,
          year: null,
          overview: 'Attrice statunitense.')
      ..onItems = (query, start, limit) => query.personId == 'p9'
          ? pageOf([testItem(id: 'm1', name: 'Dune'), testItem(id: 'm2', name: 'Challengers')])
          : pageOf([]);

    await pumpApp(tester, const Scaffold(body: PersonScreen(personId: 'p9')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider
              .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('ZENDAYA'), findsOneWidget);
    expect(find.text('Attrice statunitense.'), findsOneWidget);
    expect(find.text('Su WonderFlix'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Challengers'), findsOneWidget);
    expect(api.itemQueries.last.kinds, {ItemKind.movie, ItemKind.series});
  });

  testWidgets('TV: la Persona ha la foto accanto al nome', (tester) async {
    final api = FakeLibraryApi()
      ..itemsById['p9'] = testItem(
          id: 'p9', name: 'Zendaya', kind: ItemKind.person, year: null)
      ..onItems = (query, start, limit) => pageOf([]);

    await pumpApp(tester, const Scaffold(body: PersonScreen(personId: 'p9')),
        surfaceSize: const Size(960, 540),
        tv: true,
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider
              .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();

    final photo = find.byType(WfImage).first;
    expect(tester.getTopLeft(find.text('ZENDAYA')).dx,
        greaterThan(tester.getTopRight(photo).dx));
  });

  final longBio = List.filled(60, 'Attrice e produttrice statunitense.').join(' ');

  Future<void> pumpPerson(
    WidgetTester tester, {
    String? overview,
    List<JellyfinItem> titles = const [],
    Size size = const Size(1440, 900),
    bool tv = false,
    bool scaffold = true,
  }) async {
    final api = FakeLibraryApi()
      ..itemsById['p9'] = testItem(
          id: 'p9',
          name: 'Zendaya',
          kind: ItemKind.person,
          year: null,
          overview: overview)
      ..onItems = (query, start, limit) => pageOf(titles);
    const screen = PersonScreen(personId: 'p9');
    await pumpApp(tester, scaffold ? const Scaffold(body: screen) : screen,
        surfaceSize: size,
        tv: tv,
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider
              .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('senza titoli: niente Su WonderFlix, l\'invito a Richieste',
      (tester) async {
    await pumpPerson(tester);

    expect(find.text('Su WonderFlix'), findsNothing);
    expect(find.text('Nessun suo titolo è sul server.'), findsOneWidget);
    expect(find.text('Cerca in Richieste'), findsOneWidget);
  });

  testWidgets('biografia lunga: 4 righe e Altro, anche senza Scaffold',
      (tester) async {
    // Senza Scaffold sopra l'InkWell di "Altro" non troverebbe un Material.
    await pumpPerson(tester, overview: longBio, scaffold: false);

    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text(longBio)).maxLines, 4);
    await tester.tap(find.text('Altro'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(longBio)).maxLines, isNull);
  });

  testWidgets('stretto: margini 16', (tester) async {
    await pumpPerson(tester, size: const Size(390, 780));

    expect(tester.getTopLeft(find.text('ZENDAYA')).dx, 16);
  });

  testWidgets('TV: biografia col focus e titoli in una fila', (tester) async {
    await pumpPerson(tester,
        overview: longBio,
        titles: [testItem(id: 'm1', name: 'Dune')],
        size: const Size(960, 540),
        tv: true);

    expect(find.byType(MediaRow), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);
    // Sullo stesso bordo della foto (il nome le sta accanto), corpo 28.
    final rowTitle = find.text('Su WonderFlix');
    expect(tester.getTopLeft(rowTitle).dx,
        tester.getTopLeft(find.byType(WfImage).first).dx);
    expect(tester.widget<Text>(rowTitle).style!.fontSize, 28);
    Focus.of(tester.element(find.text(longBio)), scopeOk: true).nextFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(tester.widget<Text>(find.text(longBio)).maxLines, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
        find.ancestor(
            of: find.byElementPredicate((e) => e == focused),
            matching: find.byType(PosterCard)),
        findsOneWidget);
  });
}
