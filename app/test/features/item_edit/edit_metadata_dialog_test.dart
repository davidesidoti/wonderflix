import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/item_edit/edit_metadata_dialog.dart';
import 'package:wonderflix/features/item_edit/item_edit_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/item_edit_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  group('applyMetadataEdits', () {
    test('il DTO mandato è quello letto con solo i campi cambiati', () {
      final original = testRawItem();
      final snapshot = testRawItem();

      final sent = applyMetadataEdits(
        original,
        const MetadataEdits(name: 'Dark 2'),
      );

      expect(sent['Name'], 'Dark 2');
      for (final key in ['Tags', 'ProviderIds', 'People', 'Studios']) {
        expect(sent[key], original[key], reason: key);
      }
      expect(sent.keys, original.keys);
      // L'originale non si tocca, nemmeno nelle liste annidate.
      expect(original, snapshot);
      expect(identical(sent, original), isFalse);
    });

    test('non muta le liste annidate dell\'originale', () {
      final original = testRawItem(lockedFields: ['Overview']);
      final snapshot = testRawItem(lockedFields: ['Overview']);

      final sent = applyMetadataEdits(
        original,
        const MetadataEdits(
          name: 'Altro',
          genres: ['Giallo'],
          lockedFields: {'Overview', 'Genres'},
        ),
      );

      expect(sent['Genres'], ['Giallo']);
      expect(sent['LockedFields'], containsAll(['Overview', 'Genres', 'Name']));
      expect(original, snapshot);
    });

    test('un campo bloccabile cambiato entra in LockedFields, uno non '
        'bloccabile no', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        const MetadataEdits(
          name: 'Nuovo',
          originalTitle: 'Orig',
          sortName: 'Sort',
        ),
      );

      expect(sent['LockedFields'], ['Name']);
    });

    test('un valore uguale all\'originale non blocca niente', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        const MetadataEdits(name: 'Dark'),
      );
      expect(sent['LockedFields'], isEmpty);
    });

    test('lucchetto tolto a mano: il campo esce da LockedFields', () {
      final sent = applyMetadataEdits(
        testRawItem(lockedFields: ['Name', 'Overview']),
        const MetadataEdits(
          name: 'Nuovo',
          lockedFields: {'Overview'},
          unlockedFields: {'Name'},
        ),
      );

      expect(sent['LockedFields'], ['Overview']);
    });

    test('tagline in Taglines[0]', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        const MetadataEdits(tagline: 'Il passato'),
      );
      expect(sent['Taglines'], ['Il passato']);
      expect(sent['LockedFields'], isEmpty);
    });

    test('data a mezzanotte UTC', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        MetadataEdits(premiereDate: DateTime(2020, 3, 5)),
      );
      expect(
        DateTime.parse(sent['PremiereDate'] as String),
        DateTime.utc(2020, 3, 5),
      );
    });

    test('classificazione nessuna → null', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        const MetadataEdits(rating: ''),
      );
      expect(sent.containsKey('OfficialRating'), isTrue);
      expect(sent['OfficialRating'], isNull);
      expect(sent['LockedFields'], ['OfficialRating']);
    });

    test('anno e trama', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        const MetadataEdits(year: 1999, overview: 'Nuova trama'),
      );
      expect(sent['ProductionYear'], 1999);
      expect(sent['Overview'], 'Nuova trama');
      expect(sent['LockedFields'], ['Overview']);
    });

    test('lockAll → LockData true', () {
      final sent = applyMetadataEdits(
        testRawItem(),
        const MetadataEdits(lockAll: true),
      );
      expect(sent['LockData'], isTrue);
      final back = applyMetadataEdits(
        testRawItem(lockData: true),
        const MetadataEdits(),
      );
      expect(back['LockData'], isFalse);
    });
  });

  group('finestra', () {
    final it = lookupAppLocalizations(const Locale('it'));
    late FakeItemEditApi api;
    late FakeSessionController session;

    setUp(() {
      api = FakeItemEditApi()
        ..items['i1'] = testRawItem()
        ..items['e1'] = testRawItem(id: 'e1', name: 'Pilot', type: 'Episode')
        ..items['m1'] = testRawItem(id: 'm1', name: 'Film', type: 'Movie');
      session = FakeSessionController(const SessionSignedIn(testAdmin));
    });

    Future<void> open(
      WidgetTester tester, {
      String id = 'i1',
      ItemKind kind = ItemKind.series,
      Size surfaceSize = const Size(1440, 900),
    }) async {
      await pumpApp(
        tester,
        surfaceSize: surfaceSize,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showEditMetadataDialog(context, itemId: id, kind: kind),
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

    Finder field(String label) => find.widgetWithText(TextField, label);

    String textOf(WidgetTester tester, String label) =>
        tester.widget<TextField>(field(label)).controller!.text;

    Finder save() => find.text('Salva');

    int revision(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    ).read(libraryRevisionProvider);

    for (final size in const [Size(390, 844), Size(844, 390)]) {
      testWidgets(
        'telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
        (tester) async {
          await open(tester, surfaceSize: size);
          expect(find.text('Salva'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('campi precompilati dalla Map e tagline nascosta per un '
        'episodio', (tester) async {
      await open(tester);
      expect(textOf(tester, 'Titolo'), 'Dark');
      expect(textOf(tester, 'Titolo originale'), 'Dark (originale)');
      expect(textOf(tester, 'Tagline'), 'Cosa sai?');
      expect(textOf(tester, 'Trama'), 'Una storia di viaggi nel tempo.');
      expect(textOf(tester, 'Anno'), '2017');
      expect(textOf(tester, 'Data di uscita'), '2017-12-01');
      expect(find.text('Drammatico'), findsOneWidget);
      expect(find.text('Fantascienza'), findsOneWidget);
      expect(find.text('TV-MA'), findsOneWidget);
    });

    testWidgets('la tagline non c\'è per un episodio', (tester) async {
      await open(tester, id: 'e1', kind: ItemKind.episode);
      expect(textOf(tester, 'Titolo'), 'Pilot');
      expect(field('Tagline'), findsNothing);
    });

    testWidgets('durante il caricamento c\'è la rotella', (tester) async {
      api.gate = Completer<void>();
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showEditMetadataDialog(
                  context,
                  itemId: 'i1',
                  kind: ItemKind.series,
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
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(save(), findsNothing);
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(save(), findsOneWidget);
    });

    testWidgets('Salva: updateItem, bump, snackbar', (tester) async {
      await open(tester);
      await tester.enterText(field('Titolo'), 'Dark 2');
      await tester.pump();
      final before = revision(tester);

      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(api.calls, ['rawItem i1', 'parentalRatings i1', 'updateItem i1']);
      final sent = api.lastUpdate!;
      expect(sent['Name'], 'Dark 2');
      expect(sent['Tags'], ['cult', 'tedesco']);
      expect(sent['People'], isNotEmpty);
      // Il titolo cambiato si blocca da solo.
      expect(sent['LockedFields'], ['Name']);
      expect(revision(tester), before + 1);
      expect(find.text('Metadati salvati'), findsOneWidget);
      expect(save(), findsNothing);
    });

    testWidgets('genere aggiunto con Invio e tolto con la X', (tester) async {
      await open(tester);
      await tester.enterText(field('Aggiungi un genere'), 'Thriller');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Thriller'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Drammatico'),
          matching: find.byIcon(LucideIcons.x),
        ),
      );
      await tester.pump();
      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(api.lastUpdate!['Genres'], ['Fantascienza', 'Thriller']);
      expect(api.lastUpdate!['LockedFields'], ['Genres']);
    });

    testWidgets('lucchetto e blocca tutto', (tester) async {
      await open(tester);
      // Cambiando la trama il lucchetto si chiude; a mano lo si riapre.
      await tester.enterText(field('Trama'), 'Un\'altra trama');
      await tester.pump();
      await tester.tap(find.byTooltip('Sblocca questo campo'));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();

      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(api.lastUpdate!['Overview'], 'Un\'altra trama');
      expect(api.lastUpdate!['LockedFields'], isEmpty);
      expect(api.lastUpdate!['LockData'], isTrue);
    });

    testWidgets('titolo vuoto o data impossibile: Salva spento', (
      tester,
    ) async {
      await open(tester);
      bool enabled() =>
          tester.widget<WfButton>(find.byType(WfButton)).onPressed != null;
      expect(enabled(), isTrue);

      await tester.enterText(field('Titolo'), '   ');
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.enterText(field('Titolo'), 'Dark');
      await tester.pump();
      expect(enabled(), isTrue);

      // 30 febbraio: DateTime.tryParse lo sposterebbe al 1 marzo.
      await tester.enterText(field('Data di uscita'), '2020-02-30');
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.enterText(field('Data di uscita'), '2020-02-29');
      await tester.pump();
      expect(enabled(), isTrue);
    });

    testWidgets('etichetta dei generi e suggerimento delle cartelle', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Generi'), findsOneWidget);
      expect(find.text(it.editLockAllHintFolder), findsOneWidget);
      expect(find.text(it.editLockAllHint), findsNothing);
    });

    testWidgets('un film mostra il suggerimento semplice', (tester) async {
      await open(tester, id: 'm1', kind: ItemKind.movie);
      expect(find.text(it.editLockAllHint), findsOneWidget);
      expect(find.text(it.editLockAllHintFolder), findsNothing);
    });

    testWidgets('doppio clic: una sola chiamata', (tester) async {
      await open(tester);
      await tester.enterText(field('Titolo'), 'Dark 2');
      await tester.pump();
      api.calls.clear();
      final gate = api.gate = Completer<void>();

      await tester.tap(save());
      await tester.pump();
      await tester.tap(save(), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(api.calls, ['updateItem i1']);
    });

    testWidgets('un 403 al salvataggio rilegge l\'utente', (tester) async {
      await open(tester);
      await tester.enterText(field('Titolo'), 'Dark 2');
      await tester.pump();
      final before = revision(tester);
      api.nextFailure = const ForbiddenException();

      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(find.text('Non hai il permesso per farlo'), findsOneWidget);
      expect(session.refreshUserCalls, 1);
      expect(textOf(tester, 'Titolo'), 'Dark 2');
      expect(revision(tester), before);
    });

    testWidgets('errore di rete: messaggio e dati rimasti', (tester) async {
      await open(tester);
      await tester.enterText(field('Titolo'), 'Dark 2');
      await tester.pump();
      api.nextFailure = const ServerUnreachableException();

      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(find.textContaining('non è raggiungibile'), findsOneWidget);
      expect(textOf(tester, 'Titolo'), 'Dark 2');
      expect(save(), findsOneWidget);
      expect(session.refreshUserCalls, 0);
    });

    testWidgets('errore di lettura: l\'errore e niente form', (tester) async {
      api.nextFailure = const ServerUnreachableException();
      await open(tester);
      expect(find.textContaining('non è raggiungibile'), findsOneWidget);
      expect(save(), findsNothing);
    });
  });
}
