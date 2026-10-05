import 'package:flutter/material.dart';
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
}
