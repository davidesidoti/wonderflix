import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_edit_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/item_edit/identify_dialog.dart';
import 'package:wonderflix/features/item_edit/item_edit_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/item_edit_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeItemEditApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeItemEditApi()
      ..items['i1'] = testRawItem()
      ..items['m1'] = testRawItem(id: 'm1', name: 'Film', type: 'Movie')
      ..items['l1'] = testRawItem(id: 'l1', lockedFields: ['Name'])
      ..results = [
        RemoteSearchResult.fromJson({
          'Name': 'Dark Serie',
          'ProductionYear': 2017,
          'SearchProviderName': 'TheMovieDb',
          'Overview': 'Una trama molto lunga ' * 20,
          'ImageUrl': 'https://img.example.com/p.jpg',
          'ProviderIds': {'Tmdb': '70523'},
        }),
        RemoteSearchResult.fromJson({
          'Name': 'Altro titolo',
          'ProviderIds': {'Tmdb': '1'},
        }),
      ];
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  Future<void> open(
    WidgetTester tester, {
    String id = 'i1',
    ItemKind kind = ItemKind.series,
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
                showIdentifyDialog(context, itemId: id, kind: kind)),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        itemEditApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(() => session),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  String textOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;

  int revision(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .read(libraryRevisionProvider);

  /// Cerca e sceglie il primo risultato.
  Future<void> searchAndChoose(WidgetTester tester) async {
    await tester.tap(find.text(it.identifySearch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Serie'));
    await tester.pumpAndSettle();
  }

  testWidgets('campi precompilati; Tvdb solo per le serie', (tester) async {
    await open(tester);
    expect(textOf(tester, it.identifyName), 'Dark');
    expect(textOf(tester, it.identifyYear), '2017');
    expect(textOf(tester, it.identifyTmdb), '70523');
    expect(textOf(tester, it.identifyImdb), 'tt5753856');
    expect(field(it.identifyTvdb), findsOneWidget);
    expect(textOf(tester, it.identifyTvdb), '');
  });

  testWidgets('niente Tvdb per un film', (tester) async {
    await open(tester, id: 'm1', kind: ItemKind.movie);
    expect(textOf(tester, it.identifyName), 'Film');
    expect(field(it.identifyTvdb), findsNothing);
  });

  testWidgets('ricerca e risultati', (tester) async {
    await open(tester);
    await tester.enterText(field(it.identifyName), 'Dark Matter');
    await tester.tap(find.text(it.identifySearch));
    await tester.pumpAndSettle();

    expect(api.calls, ['rawItem i1', 'searchRemote i1 Series Dark Matter']);
    expect(find.text('Dark Serie'), findsOneWidget);
    expect(find.text('Altro titolo'), findsOneWidget);
    expect(find.textContaining('2017'), findsWidgets);
    expect(find.textContaining('TheMovieDb'), findsOneWidget);
    // La locandina c'è solo per il risultato che ha un indirizzo.
    expect(find.byType(WfImage), findsOneWidget);
  });

  testWidgets('nessun risultato', (tester) async {
    api.results = [];
    await open(tester);
    await tester.tap(find.text(it.identifySearch));
    await tester.pumpAndSettle();
    expect(find.text(it.identifyNoResults), findsOneWidget);
  });

  testWidgets('conferma senza la casella di sblocco se non ci sono blocchi',
      (tester) async {
    await open(tester);
    await searchAndChoose(tester);

    expect(find.text(it.identifyConfirm('Dark Serie (2017)')), findsOneWidget);
    expect(find.text(it.identifyReplaceImages), findsOneWidget);
    expect(find.text(it.identifyUnlock), findsNothing);
    expect(find.text(it.identifyApply), findsOneWidget);
  });

  testWidgets('sblocco: updateItem con LockData false e LockedFields vuoti, '
      'poi apply', (tester) async {
    await open(tester, id: 'l1');
    await searchAndChoose(tester);
    expect(find.text(it.identifyUnlock), findsOneWidget);

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(api.calls, [
      'rawItem l1',
      'searchRemote l1 Series Dark',
      'updateItem l1',
      'applyIdentify l1 true',
    ]);
    final sent = api.lastUpdate!;
    expect(sent['LockData'], isFalse);
    expect(sent['LockedFields'], isEmpty);
    // Il resto della Map è quello letto.
    expect(sent['Tags'], ['cult', 'tedesco']);
    expect(sent['Name'], 'Dark');
  });

  testWidgets('sblocco spento: niente updateItem; immagini non sostituite',
      (tester) async {
    await open(tester, id: 'l1');
    await searchAndChoose(tester);
    await tester.tap(find.text(it.identifyUnlock));
    await tester.tap(find.text(it.identifyReplaceImages));
    await tester.pump();

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(api.calls, [
      'rawItem l1',
      'searchRemote l1 Series Dark',
      'applyIdentify l1 false',
    ]);
  });

  testWidgets('Apply riuscito: bump e snackbar', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    final before = revision(tester);

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(api.calls.last, 'applyIdentify i1 true');
    expect(revision(tester), before + 1);
    expect(find.text(it.identifyDone), findsOneWidget);
    expect(find.text(it.identifyApply), findsNothing);
  });

  testWidgets('Apply che scade: messaggio e rilettura', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    final before = revision(tester);
    api.nextFailure = const ServerUnreachableException();

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(revision(tester), before + 1);
    expect(find.text(it.identifyStillWorking), findsOneWidget);
    expect(find.text(it.identifyApply), findsNothing);
    expect(session.refreshUserCalls, 0);
  });

  testWidgets('Apply che scade con un 504 del gateway: "sta lavorando"',
      (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    final before = revision(tester);
    api.nextFailure = const ServerErrorException(504);

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(revision(tester), before + 1);
    expect(find.text(it.identifyStillWorking), findsOneWidget);
    expect(find.text(it.identifyApply), findsNothing);
  });

  testWidgets('senza immagini la conferma non le nomina', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    await tester.tap(find.text(it.identifyReplaceImages));
    await tester.pump();

    expect(find.text(it.identifyConfirmNoImages('Dark Serie (2017)')),
        findsOneWidget);
    expect(find.text(it.identifyConfirm('Dark Serie (2017)')), findsNothing);
  });

  testWidgets('rete giù durante lo sblocco: errore, non "sta lavorando"',
      (tester) async {
    await open(tester, id: 'l1');
    await searchAndChoose(tester);
    final before = revision(tester);
    api.nextFailure = const ServerUnreachableException();

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(find.text(it.identifyStillWorking), findsNothing);
    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    expect(find.text(it.identifyApply), findsOneWidget);
    expect(api.calls.last, 'updateItem l1');
    expect(revision(tester), before);
  });

  testWidgets('doppio clic su Applica: una sola chiamata', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    api.calls.clear();
    final gate = api.gate = Completer<void>();

    await tester.tap(find.text(it.identifyApply));
    await tester.pump();
    expect(find.text(it.identifyWorking), findsOneWidget);
    await tester.tap(find.text(it.identifyApply), warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(api.calls, ['applyIdentify i1 true']);
  });

  testWidgets('un 403 rilegge l\'utente e la finestra resta', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    final before = revision(tester);
    api.nextFailure = const ForbiddenException();

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(find.text(it.editNoPermission), findsOneWidget);
    expect(session.refreshUserCalls, 1);
    expect(find.text(it.identifyApply), findsOneWidget);
    expect(revision(tester), before);
  });

  testWidgets('un altro errore resta nella finestra', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    api.nextFailure = const ServerErrorException(500);

    await tester.tap(find.text(it.identifyApply));
    await tester.pumpAndSettle();

    expect(find.text(it.identifyApply), findsOneWidget);
    expect(find.text(it.identifyDone), findsNothing);
  });

  testWidgets('Annulla nella conferma torna ai risultati', (tester) async {
    await open(tester);
    await searchAndChoose(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('Altro titolo'), findsOneWidget);
    expect(find.text(it.identifyApply), findsNothing);
  });
}
