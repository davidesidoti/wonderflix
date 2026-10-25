import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/item_edit/item_edit_providers.dart';
import 'package:wonderflix/features/item_edit/refresh_metadata_dialog.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/item_edit_fakes.dart';
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
  }) async {
    await pumpApp(
      tester,
      surfaceSize: surfaceSize,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                unawaited(showRefreshMetadataDialog(context, itemId: 'i1')),
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

  bool? imagesChecked(WidgetTester tester) => tester
      .widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, it.refreshAlsoImages),
      )
      .value;

  testWidgets('cerca dati mancanti: replace falsi', (tester) async {
    await open(tester);
    await tester.tap(find.text(it.refreshStart));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 false false']);
    expect(find.text(it.refreshStarted), findsOneWidget);
    expect(find.text(it.refreshTitle), findsNothing);
    // Il Timer del bump va fatto scadere: un Timer pendente fa fallire il test.
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('sostituisci tutto con immagini', (tester) async {
    await open(tester);
    await tester.tap(find.text(it.refreshReplaceAll));
    await tester.pump();
    await tester.tap(find.text(it.refreshAlsoImages));
    await tester.pump();
    await tester.tap(find.text(it.refreshStart));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 true true']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('sostituisci tutto senza immagini', (tester) async {
    await open(tester);
    await tester.tap(find.text(it.refreshReplaceAll));
    await tester.pump();
    await tester.tap(find.text(it.refreshStart));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 true false']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('la casella delle immagini è spenta con cerca dati mancanti', (
    tester,
  ) async {
    await open(tester);
    final box = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, it.refreshAlsoImages),
    );
    expect(box.onChanged, isNull);

    // Spunta con "sostituisci", poi torna a "mancanti": non conta più.
    await tester.tap(find.text(it.refreshReplaceAll));
    await tester.pump();
    await tester.tap(find.text(it.refreshAlsoImages));
    await tester.pump();
    expect(imagesChecked(tester), isTrue);
    await tester.tap(find.text(it.refreshMissing));
    await tester.pump();
    await tester.tap(find.text(it.refreshStart));
    await tester.pumpAndSettle();

    expect(api.calls, ['refresh i1 false false']);
    await tester.pump(refreshReloadDelay);
  });

  testWidgets('bump 10 s dopo, non prima, anche a finestra chiusa', (
    tester,
  ) async {
    await open(tester);
    final before = revision(tester);
    await tester.tap(find.text(it.refreshStart));
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

    await tester.tap(find.text(it.refreshStart));
    await tester.pump();
    await tester.tap(find.text(it.refreshStart), warnIfMissed: false);
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

    await tester.tap(find.text(it.refreshStart));
    await tester.pumpAndSettle();

    expect(find.text(it.editNoPermission), findsOneWidget);
    expect(session.refreshUserCalls, 1);
    expect(find.text(it.refreshStart), findsOneWidget);
    await tester.pump(refreshReloadDelay);
    expect(revision(tester), before);
  });

  testWidgets('un altro errore resta nella finestra', (tester) async {
    await open(tester);
    api.nextFailure = const ServerUnreachableException();

    await tester.tap(find.text(it.refreshStart));
    await tester.pumpAndSettle();

    expect(find.textContaining('non è raggiungibile'), findsOneWidget);
    expect(find.text(it.refreshStart), findsOneWidget);
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
