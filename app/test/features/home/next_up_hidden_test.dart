import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/home/home_rows_logic.dart';
import 'package:wonderflix/features/home/next_up_hidden.dart';
import 'package:wonderflix/ui/landscape_card.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

JellyfinItem _episode(String id, String seriesId, String name) => testItem(
  id: id,
  name: 'Episodio $id',
  kind: ItemKind.episode,
  seriesId: seriesId,
  seriesName: name,
);

void main() {
  late FakeLibraryApi library;
  late FakeDisplayPreferencesApi prefs;
  late FakeSessionController session;

  setUp(() {
    library = FakeLibraryApi();
    prefs = FakeDisplayPreferencesApi();
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() => ProviderContainer.test(
    overrides: homeOverrides(library: library, prefs: prefs, session: session),
    retry: (_, _) => null,
  );

  Future<Map<String, String>> hidden(ProviderContainer c) {
    c.listen(nextUpHiddenProvider, (_, _) {});
    return c.read(nextUpHiddenProvider.future);
  }

  group('hiddenFromNextUp', () {
    final episode = _episode('E-1', 'S-1', 'The Bear');
    test('serie tolta con lo stesso episodio: fuori', () {
      expect(hiddenFromNextUp({'s1': 'e1'}, episode), isTrue);
    });
    test('Jellyfin propone un altro episodio: la serie torna', () {
      expect(hiddenFromNextUp({'s1': 'e0'}, episode), isFalse);
    });
    test('serie non tolta o episodio senza serie: dentro', () {
      expect(hiddenFromNextUp({'s2': 'e1'}, episode), isFalse);
      expect(hiddenFromNextUp({'s1': 'e1'}, testItem(id: 'e1')), isFalse);
    });
  });

  test('legge la lista dell\'utente', () async {
    prefs.nextUpHidden = {'s1': 'e1'};
    expect(await hidden(container()), {'s1': 'e1'});
  });

  test('lettura fallita: lista vuota', () async {
    prefs
      ..nextUpHidden = {'s1': 'e1'}
      ..nextUpReadError = Exception('giù');
    expect(await hidden(container()), isEmpty);
  });

  test('togliere: subito nello stato, poi salvato', () async {
    final c = container();
    await hidden(c);
    prefs.nextUpWriteGate = Completer();
    final done = c.read(nextUpHiddenProvider.notifier).hide('S-1', 'E-1');
    await pumpEventQueue();
    expect(c.read(nextUpHiddenProvider).value, {'s1': 'e1'});
    prefs.nextUpWriteGate!.complete();
    expect(await done, isTrue);
    final (user, written) = prefs.nextUpWritten.single;
    expect(user, 'u1');
    expect(written, {'s1': 'e1'});
  });

  test('salvataggio fallito: torna lo stato di prima', () async {
    prefs.nextUpHidden = {'s1': 'e0'};
    final c = container();
    await hidden(c);
    prefs.nextUpWriteError = Exception('giù');
    expect(
      await c.read(nextUpHiddenProvider.notifier).hide('s1', 'e1'),
      isFalse,
    );
    expect(c.read(nextUpHiddenProvider).value, {'s1': 'e0'});
    expect(await c.read(nextUpHiddenProvider.notifier).unhide('s1'), isFalse);
    expect(c.read(nextUpHiddenProvider).value, {'s1': 'e0'});
  });

  test('rimettere toglie la serie dalla lista', () async {
    prefs.nextUpHidden = {'s1': 'e1', 's2': 'e2'};
    final c = container();
    await hidden(c);
    expect(await c.read(nextUpHiddenProvider.notifier).unhide('s1'), isTrue);
    expect(prefs.nextUpHidden, {'s2': 'e2'});
  });

  test(
    'due modifiche di fila: una scrittura alla volta, l\'ultima ha tutto',
    () async {
      final c = container();
      await hidden(c);
      prefs.nextUpWriteGate = Completer();
      final notifier = c.read(nextUpHiddenProvider.notifier);
      final first = notifier.hide('s1', 'e1');
      final second = notifier.hide('s2', 'e2');
      await pumpEventQueue();
      expect(prefs.nextUpWritten, hasLength(1));
      prefs.nextUpWriteGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(prefs.nextUpWritten.last.$2, {'s1': 'e1', 's2': 'e2'});
    },
  );

  test(
    'lettura fallita: prima di scrivere si rilegge, le serie restano',
    () async {
      prefs
        ..nextUpHidden = {'s1': 'e1'}
        ..nextUpReadError = Exception('giù');
      final c = container();
      expect(await hidden(c), isEmpty);
      prefs.nextUpReadError = null;
      expect(
        await c.read(nextUpHiddenProvider.notifier).hide('s2', 'e2'),
        isTrue,
      );
      expect(prefs.nextUpHidden, {'s1': 'e1', 's2': 'e2'});
    },
  );

  test(
    'prima scrittura fallita: la seconda non manda la serie tornata',
    () async {
      final c = container();
      await hidden(c);
      prefs
        ..nextUpWriteGate = Completer()
        ..nextUpWriteError = Exception('giù');
      final notifier = c.read(nextUpHiddenProvider.notifier);
      final first = notifier.hide('s1', 'e1');
      final second = notifier.hide('s2', 'e2');
      await pumpEventQueue();
      prefs.nextUpWriteGate!.complete();
      expect(await first, isFalse);
      await second;
      expect(prefs.nextUpWritten[1].$2, {'s2': 'e2'});
    },
  );

  test(
    'lettura fallita e due modifiche insieme: si rilegge una volta, restano '
    'tutte e due',
    () async {
      prefs
        ..nextUpHidden = {'s1': 'e1'}
        ..nextUpReadError = Exception('giù');
      final c = container();
      expect(await hidden(c), isEmpty);
      prefs.nextUpReadError = null;
      final notifier = c.read(nextUpHiddenProvider.notifier);
      final first = notifier.hide('s2', 'e2');
      final second = notifier.hide('s3', 'e3');
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(prefs.nextUpHidden, {'s1': 'e1', 's2': 'e2', 's3': 'e3'});
    },
  );

  test('al cambio di utente si rilegge', () async {
    prefs.nextUpHidden = {'s1': 'e1'};
    final c = container();
    expect(await hidden(c), {'s1': 'e1'});
    prefs.nextUpHidden = {};
    session.quickConnectApproved(const JellyfinUser(id: 'u2', name: 'Luigi'));
    expect(await c.read(nextUpHiddenProvider.future), isEmpty);
  });

  test('la riga chiede il doppio degli episodi', () async {
    final c = container();
    final key = (kind: HomeRowKind.nextUp, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    await c.read(homeRowProvider(key).future);
    expect(library.nextUpLimits.single, homeRowLimit * 2);
  });

  Future<void> pumpRow(WidgetTester tester, List<JellyfinItem> items) =>
      pumpApp(
        tester,
        Scaffold(
          body: HomeRowView(
            kind: HomeRowKind.nextUp,
            content: ItemsRowContent(items),
            animateEntrance: false,
          ),
        ),
        overrides: homeOverrides(library: library, prefs: prefs),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeRowView)));

  testWidgets('la riga salta le serie tolte con l\'episodio proposto', (
    tester,
  ) async {
    prefs.nextUpHidden = {'s1': 'e1', 's2': 'e0'};
    await pumpRow(tester, [
      _episode('e1', 's1', 'The Bear'),
      _episode('e2', 's2', 'Severance'),
    ]);
    await tester.pump();
    expect(find.text('The Bear'), findsNothing);
    expect(find.text('Severance'), findsOneWidget);
  });

  testWidgets('tutte tolte: la riga non c\'è', (tester) async {
    prefs.nextUpHidden = {'s1': 'e1'};
    await pumpRow(tester, [_episode('e1', 's1', 'The Bear')]);
    await tester.pump();
    expect(find.text('Prossimi episodi'), findsNothing);
  });

  testWidgets('togliere dalla riga: sparisce, SnackBar e Annulla la rimette', (
    tester,
  ) async {
    await pumpRow(tester, [
      _episode('e1', 's1', 'The Bear'),
      _episode('e2', 's2', 'Severance'),
    ]);
    await tester.pump();
    final card = tester.widget<LandscapeCard>(
      find.byKey(const ValueKey('next-up-e1')),
    );
    card.previewExtra!.onDismiss!();
    await tester.pump();
    await tester.pump();
    expect(find.text('The Bear'), findsNothing);
    expect(prefs.nextUpHidden, {'s1': 'e1'});
    expect(find.text('Tolto da Prossimi episodi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // la SnackBar entra
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    await tester.pump();
    expect(find.text('The Bear'), findsOneWidget);
    expect(prefs.nextUpHidden, isEmpty);
  });

  testWidgets('togliere non riuscito: la card torna e la SnackBar lo dice', (
    tester,
  ) async {
    await pumpRow(tester, [_episode('e1', 's1', 'The Bear')]);
    await tester.pump();
    prefs.nextUpWriteError = Exception('giù');
    final card = tester.widget<LandscapeCard>(
      find.byKey(const ValueKey('next-up-e1')),
    );
    card.previewExtra!.onDismiss!();
    await tester.pump();
    await tester.pump();
    expect(find.text('The Bear'), findsOneWidget);
    expect(
      find.text('Prossimi episodi non aggiornati: riprova'),
      findsOneWidget,
    );
    expect(containerOf(tester).read(nextUpHiddenProvider).value, isEmpty);
  });
}
