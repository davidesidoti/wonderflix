import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/item_edit/item_edit_providers.dart';
import 'package:wonderflix/features/item_edit/refresh_metadata_dialog.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/ui/wf_choice_tile.dart';
import 'package:wonderflix/ui/wf_dialog_parts.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/item_edit_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeItemEditApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeItemEditApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
  });

  Future<void> open(
    WidgetTester tester, {
    Size surfaceSize = const Size(1440, 900),
    JellyfinItem? item,
  }) async {
    await pumpApp(
      tester,
      surfaceSize: surfaceSize,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showRefreshMetadataDialog(
                context,
                item: item ?? testItem(id: 'i1'),
              ),
            ),
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

  int revision(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  ).read(libraryRevisionProvider);

  Finder tile(String title) => find.widgetWithText(WfChoiceTile, title);

  /// Il pulsante primario, che nel piede ripete la scelta.
  Finder primary(String label) => find.descendant(
    of: find.byType(WfDialogFooter),
    matching: find.text(label),
  );

  SwitchListTile imagesSwitch(WidgetTester tester) =>
      tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, it.refreshAlsoImages),
      );

  testWidgets('cerca dati mancanti: replace falsi', (tester) async {
    await open(tester);
    await tester.tap(primary(it.refreshMissing));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 false false']);
    expect(find.text(it.refreshStarted), findsOneWidget);
    expect(find.text(it.refreshTitle), findsNothing);
    // Il Timer del bump va fatto scadere: un Timer pendente fa fallire il test.
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('sostituisci tutto con immagini', (tester) async {
    await open(tester);
    await tester.tap(tile(it.refreshReplaceAll));
    await tester.pump();
    await tester.tap(find.text(it.refreshAlsoImages));
    await tester.pump();
    await tester.tap(primary(it.refreshReplaceAll));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 true true']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('sostituisci tutto senza immagini', (tester) async {
    await open(tester);
    await tester.tap(tile(it.refreshReplaceAll));
    await tester.pump();
    await tester.tap(primary(it.refreshReplaceAll));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 true false']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('la casella delle immagini è spenta con cerca dati mancanti', (
    tester,
  ) async {
    await open(tester);
    expect(imagesSwitch(tester).onChanged, isNull);

    // Spunta con "sostituisci", poi torna a "mancanti": non conta più.
    await tester.tap(tile(it.refreshReplaceAll));
    await tester.pump();
    await tester.tap(find.text(it.refreshAlsoImages));
    await tester.pump();
    expect(imagesSwitch(tester).value, isTrue);
    await tester.tap(tile(it.refreshMissing));
    await tester.pump();
    await tester.tap(primary(it.refreshMissing));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 false false']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('il pulsante ripete la scelta', (tester) async {
    await open(tester);
    expect(primary(it.refreshMissing), findsOneWidget);
    expect(primary(it.refreshReplaceAll), findsNothing);

    await tester.tap(tile(it.refreshReplaceAll));
    await tester.pump();
    expect(primary(it.refreshReplaceAll), findsOneWidget);
    expect(primary(it.refreshMissing), findsNothing);
  });

  testWidgets('serie: avviso con stagioni ed episodi', (tester) async {
    await open(
      tester,
      item: testItem(
        id: 'i1',
        kind: ItemKind.series,
        childCount: 2,
        recursiveCount: 16,
      ),
    );
    expect(
      find.text('Vale anche per le sue 2 stagioni e 16 episodi'),
      findsOneWidget,
    );
  });

  testWidgets('serie: una stagione e un episodio', (tester) async {
    await open(
      tester,
      item: testItem(
        id: 'i1',
        kind: ItemKind.series,
        childCount: 1,
        recursiveCount: 1,
      ),
    );
    expect(
      find.text('Vale anche per la sua stagione e 1 episodio'),
      findsOneWidget,
    );
  });

  testWidgets('serie senza conti: avviso generico', (tester) async {
    await open(
      tester,
      item: testItem(id: 'i1', kind: ItemKind.series),
    );
    expect(find.text(it.refreshSeriesNoteUnknown), findsOneWidget);
  });

  testWidgets('un film: nessun avviso', (tester) async {
    await open(tester);
    expect(find.textContaining('Vale anche'), findsNothing);
  });

  testWidgets('la testa dice quale titolo', (tester) async {
    await open(tester);
    expect(find.text('Dune: Parte Due · Film · 2024'), findsOneWidget);
  });

  testWidgets('bump 10 s dopo, non prima, anche a finestra chiusa', (
    tester,
  ) async {
    await open(tester);
    final before = revision(tester);
    await tester.tap(primary(it.refreshMissing));
    await tester.pumpAndSettle();
    expect(find.text(it.refreshTitle), findsNothing);

    expect(revision(tester), before);
    await tester.pump(refreshReloadDelay - const Duration(seconds: 1));
    expect(revision(tester), before);
    await tester.pump(const Duration(seconds: 1));
    expect(revision(tester), before + 1);
  });

  testWidgets('doppio clic: una sola chiamata', (tester) async {
    await open(tester);
    final gate = api.gate = Completer<void>();

    await tester.tap(primary(it.refreshMissing));
    await tester.pump();
    await tester.tap(primary(it.refreshMissing), warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 false false']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('un 403 rilegge l\'utente; niente bump', (tester) async {
    await open(tester);
    final before = revision(tester);
    api.nextFailure = const ForbiddenException();

    await tester.tap(primary(it.refreshMissing));
    await tester.pumpAndSettle();

    expect(find.text(it.editNoPermission), findsOneWidget);
    expect(session.refreshUserCalls, 1);
    expect(primary(it.refreshMissing), findsOneWidget);
    await tester.pump(refreshReloadDelay);
    expect(revision(tester), before);
  });

  testWidgets('un altro errore resta nella finestra', (tester) async {
    await open(tester);
    api.nextFailure = const ServerUnreachableException();

    await tester.tap(primary(it.refreshMissing));
    await tester.pumpAndSettle();

    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    expect(primary(it.refreshMissing), findsOneWidget);
    expect(session.refreshUserCalls, 0);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
      (tester) async {
        await open(tester, surfaceSize: size);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
