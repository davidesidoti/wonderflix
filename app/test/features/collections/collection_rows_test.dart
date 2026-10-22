import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collection_rows.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/card_preview.dart';
import 'package:wonderflix/ui/poster_card.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeCollectionsApi collections;

  setUp(() {
    library = FakeLibraryApi()
      ..itemsByCollection['c1'] = [
        testItem(id: 'm1', name: 'Matrix'),
        testItem(id: 'm2', name: 'Matrix Reloaded'),
      ]
      ..itemsByCollection['c2'] = [
        testItem(id: 'm1', name: 'Matrix'),
        testItem(id: 'm9', name: 'Animatrix'),
        testItem(id: 'm2', name: 'Matrix Reloaded'),
      ];
    collections = FakeCollectionsApi()
      ..collectionsList = [
        testCollection(id: 'c2', name: 'Universo Matrix', itemIds: ['m1', 'm9', 'm2']),
        testCollection(id: 'c1', name: 'Matrix - Collezione', itemIds: ['m1', 'm2']),
        testCollection(id: 'c3', name: 'Solo Matrix', itemIds: ['m1']),
      ];
  });

  List<Override> overrides(
          {SocialFeatures features = const SocialFeatures(collections: true)}) =>
      [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialAvailabilityProvider
            .overrideWith(() => FakeSocialAvailability(features)),
        collectionsApiProvider.overrideWithValue(collections),
      ];

  const rows = Scaffold(
      body: SingleChildScrollView(child: CollectionRows(itemId: 'm1')));

  Future<void> pumpRows(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(collections: true)}) async {
    await pumpApp(tester, rows,
        overrides: overrides(features: features),
        surfaceSize: const Size(1440, 1400));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('una riga per saga con almeno 2 film, dalla più piccola',
      (tester) async {
    await pumpRows(tester);
    final small = find.text('Fa parte di: Matrix - Collezione');
    final big = find.text('Fa parte di: Universo Matrix');
    expect(small, findsOneWidget);
    expect(big, findsOneWidget);
    expect(tester.getTopLeft(small).dy, lessThan(tester.getTopLeft(big).dy));
    expect(find.text('Fa parte di: Solo Matrix'), findsNothing);
    expect(find.text('Animatrix'), findsOneWidget);
    // Il film aperto è segnato in tutte e due le righe.
    expect(find.text('Questo film'), findsNWidgets(2));
  });

  testWidgets('plugin senza saghe: nessuna riga e nessuna chiamata',
      (tester) async {
    await pumpRows(tester, features: SocialFeatures.none);
    expect(find.textContaining('Fa parte di'), findsNothing);
    expect(collections.calls, 0);
    expect(library.collectionItemsCalls, isEmpty);
  });

  testWidgets('titoli della saga non letti: nessuna riga', (tester) async {
    library.collectionItemsError = const ServerErrorException(500);
    await pumpRows(tester);
    expect(library.collectionItemsCalls, isNotEmpty);
    expect(find.textContaining('Fa parte di'), findsNothing);
  });

  /// Le righe come pagina `/`, con la saga e la scheda come pagine di prova.
  Future<void> pumpRoutedRows(WidgetTester tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => rows),
      GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              Scaffold(body: Text('saga ${state.pathParameters['id']}'))),
      GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Scaffold(body: Text('scheda ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(tester, router,
        overrides: overrides(), surfaceSize: const Size(1440, 1400));
    await tester.pump();
    await tester.pump();
  }

  Finder cardOf(String text) => find.ancestor(
      of: find.text(text).first, matching: find.byType(PosterCard));

  /// Muove un mouse sopra [target] e aspetta il ritardo dell'anteprima.
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    await tester.pump(previewHoverDelay);
    await tester.pump();
    return mouse;
  }

  testWidgets('il titolo della riga apre la pagina della saga', (tester) async {
    await pumpRoutedRows(tester);
    await tester.tap(find.text('Fa parte di: Matrix - Collezione'));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });

  testWidgets('anche lo spazio tra il titolo e la freccia apre la saga',
      (tester) async {
    await pumpRoutedRows(tester);
    final link = find.byKey(const Key('row-title-link')).first;
    final title = tester.getRect(find.text('Fa parte di: Matrix - Collezione'));
    // A metà dello spazio che separa il testo dalla freccia.
    await tester.tapAt(Offset(title.right + 4, tester.getCenter(link).dy));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });

  testWidgets('"Questo film" non apre niente: né clic né anteprima',
      (tester) async {
    await pumpRoutedRows(tester);
    final current = cardOf('Questo film');
    await hover(tester, current);
    expect(find.byType(CardPreview), findsNothing);
    await tester.tap(current);
    await tester.pumpAndSettle();
    expect(find.textContaining('scheda'), findsNothing);
    expect(find.textContaining('saga'), findsNothing);
  });

  testWidgets('le altre card si aprono: anteprima al passaggio, scheda al clic',
      (tester) async {
    await pumpRoutedRows(tester);
    final other = cardOf('Animatrix');
    final mouse = await hover(tester, other);
    expect(find.byType(CardPreview), findsOneWidget);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreview), findsNothing);
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(find.text('scheda m9'), findsOneWidget);
  });
}
