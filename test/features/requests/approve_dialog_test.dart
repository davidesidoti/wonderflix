import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/approve_dialog.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;

  setUp(() {
    api = FakeRequestsApi()
      ..servicesByType[RequestMediaType.movie] = const [
        ServiceOption(
          id: 0,
          name: 'Radarr',
          isDefault: true,
          profiles: [ProfileOption(id: 8, name: 'Main Profile')],
          rootFolders: ['/media/movies'],
          defaultProfileId: 8,
          defaultRootFolder: '/media/movies',
        ),
        ServiceOption(
          id: 1,
          name: 'Radarr Anime',
          isDefault: false,
          profiles: [
            ProfileOption(id: 7, name: 'Anime Main Profile'),
            ProfileOption(id: 8, name: 'Main Profile'),
          ],
          rootFolders: ['/media/anime', '/media/movies'],
          defaultProfileId: 7,
          defaultRootFolder: '/media/anime',
        ),
      ];
  });

  /// Apre la finestra e restituisce come leggere la scelta.
  Future<ApproveChoice? Function()> openDialog(WidgetTester tester) async {
    ApproveChoice? result;
    var closed = false;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showApproveDialog(
                  context, testMediaRequest(id: 53, title: 'Dune'));
              closed = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: requestsTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    return () {
      expect(closed, isTrue);
      return result;
    };
  }

  testWidgets('"Predefinito": nessun profilo né cartella, decide Seerr',
      (tester) async {
    final choice = await openDialog(tester);

    expect(find.text('Approva: Dune'), findsOneWidget);
    expect(find.text('Predefinito (Radarr)'), findsOneWidget);
    expect(find.text('Profilo'), findsNothing);

    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();

    final result = choice()!;
    expect((result.serverId, result.profileId, result.rootFolder), (null, null, null));
    expect(api.calls, ['services:movie']);
  });

  testWidgets('un altro server: profilo e cartella, con i suoi predefiniti',
      (tester) async {
    final choice = await openDialog(tester);

    await tester.tap(find.byKey(const Key('approve-server')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radarr Anime').last);
    await tester.pumpAndSettle();

    expect(find.text('Profilo'), findsOneWidget);
    expect(find.text('Anime Main Profile'), findsOneWidget);
    expect(find.text('/media/anime'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/media/movies').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();

    final result = choice()!;
    expect((result.serverId, result.profileId, result.rootFolder), (1, 7, '/media/movies'));
  });

  testWidgets('server non disponibili: solo "Predefinito" con una nota',
      (tester) async {
    api.servicesFailure = RequestsFailure.seerrUnavailable;
    final choice = await openDialog(tester);

    expect(find.text('Predefinito'), findsOneWidget);
    expect(find.text('Server non disponibili: si approva con i valori predefiniti'),
        findsOneWidget);

    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();
    expect(choice()!.serverId, isNull);
  });

  testWidgets('Annulla: nessuna scelta', (tester) async {
    final choice = await openDialog(tester);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(choice(), isNull);
  });

  testWidgets('Invio approva subito: "Approva" ha il fuoco all\'apertura',
      (tester) async {
    final choice = await openDialog(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final result = choice()!;
    expect((result.serverId, result.profileId, result.rootFolder), (null, null, null));
  });

  testWidgets('nessun server predefinito: si parte dal primo, con i suoi valori',
      (tester) async {
    api.servicesByType[RequestMediaType.movie] = const [
      ServiceOption(
        id: 2,
        name: 'Radarr Uno',
        isDefault: false,
        profiles: [
          ProfileOption(id: 4, name: 'Basso'),
          ProfileOption(id: 5, name: 'Alto'),
        ],
        rootFolders: ['/media/a', '/media/b'],
        defaultProfileId: 5,
        defaultRootFolder: '/media/b',
      ),
      ServiceOption(
        id: 6,
        name: 'Radarr Due',
        isDefault: false,
        profiles: [ProfileOption(id: 9, name: 'Unico')],
        rootFolders: ['/media/c'],
      ),
    ];
    final choice = await openDialog(tester);

    // Senza un predefinito Seerr non manderebbe niente a Radarr: il primo
    // server è già scelto, con il suo profilo e la sua cartella.
    expect(find.text('Radarr Uno'), findsOneWidget);
    expect(find.text('Profilo'), findsOneWidget);
    expect(find.text('Alto'), findsOneWidget);
    expect(find.text('/media/b'), findsOneWidget);

    // "Predefinito" resta tra le voci, ma la scelta di partenza è un'altra:
    // una scelta dell'utente non viene toccata dai ricaricamenti.
    await tester.tap(find.byKey(const Key('approve-server')));
    await tester.pumpAndSettle();
    expect(find.text('Predefinito'), findsOneWidget);
    await tester.tap(find.text('Predefinito'));
    await tester.pumpAndSettle();
    expect(find.text('Profilo'), findsNothing);

    await tester.tap(find.byKey(const Key('approve-server')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radarr Uno').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approva'));
    await tester.pumpAndSettle();

    final result = choice()!;
    expect((result.serverId, result.profileId, result.rootFolder), (2, 5, '/media/b'));
  });

  testWidgets('con un server predefinito, si parte da "Predefinito"',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Predefinito (Radarr)'), findsOneWidget);
    expect(find.text('Profilo'), findsNothing);
  });

  testWidgets('nomi lunghi: una riga con i puntini, in ogni menu', (tester) async {
    const long = 'Un nome di server, di profilo o di cartella molto lungo, '
        'più lungo di quanto la finestra possa mostrare in una riga sola';
    api.servicesByType[RequestMediaType.movie] = const [
      ServiceOption(
        id: 0,
        name: long,
        isDefault: true,
        profiles: [ProfileOption(id: 8, name: long)],
        rootFolders: ['/media/$long'],
        defaultProfileId: 8,
        defaultRootFolder: '/media/$long',
      ),
    ];
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('approve-server')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(long).last);
    await tester.pumpAndSettle();

    for (final key in ['approve-server', 'approve-profile', 'approve-folder']) {
      final labels = tester.widgetList<Text>(find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(Text)));
      expect(labels, isNotEmpty, reason: key);
      for (final label in labels) {
        expect(label.maxLines, 1, reason: key);
        expect(label.overflow, TextOverflow.ellipsis, reason: key);
      }
    }
  });

  testWidgets('la finestra ha il titolo come nome per chi usa lo screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openDialog(tester);

    expect(
      find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.namesRoute == true &&
          w.properties.scopesRoute == true &&
          w.properties.label == 'Approva: Dune'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
