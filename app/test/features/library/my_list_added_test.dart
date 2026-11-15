import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/my_list_added.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

final _d0 = DateTime.utc(2026, 11, 1);
final _d1 = DateTime.utc(2026, 11, 2);
final _d2 = DateTime.utc(2026, 11, 3);

void main() {
  late FakeDisplayPreferencesApi prefs;
  late FakeSessionController session;

  setUp(() {
    prefs = FakeDisplayPreferencesApi();
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() => ProviderContainer.test(
    overrides: homeOverrides(
      library: FakeLibraryApi(),
      prefs: prefs,
      session: session,
    ),
    retry: (_, _) => null,
  );

  Future<MyListAdded> open(ProviderContainer c) async {
    c.listen(myListAddedProvider, (_, _) {});
    await c.read(myListAddedProvider.future);
    return c.read(myListAddedProvider.notifier);
  }

  test('legge le date dell\'utente', () async {
    prefs.myListAdded = {'a': _d1};
    final c = container();
    await open(c);
    expect(c.read(myListAddedProvider).value, {'a': _d1});
  });

  test(
    'due change di fila: due scritture, la seconda ha anche la prima',
    () async {
      final c = container();
      final notifier = await open(c);
      prefs.myListAddedWriteGate = Completer();
      final first = notifier.change({'a': _d1});
      final second = notifier.change({'b': _d2});
      await pumpEventQueue();
      expect(prefs.myListAddedWrites, hasLength(1));
      prefs.myListAddedWriteGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(prefs.myListAddedWrites, hasLength(2));
      expect(prefs.myListAddedWrites.last, {'a': _d1, 'b': _d2});
    },
  );

  test('un change con più voci è una sola scrittura', () async {
    final c = container();
    final notifier = await open(c);
    expect(await notifier.change({'a': _d1, 'b': _d2}), isTrue);
    expect(prefs.myListAddedWrites.single, {'a': _d1, 'b': _d2});
  });

  test('null toglie la voce', () async {
    prefs.myListAdded = {'a': _d1};
    final c = container();
    final notifier = await open(c);
    expect(await notifier.change({'a': null}), isTrue);
    expect(prefs.myListAddedWrites.last, isEmpty);
    expect(c.read(myListAddedProvider).value, isEmpty);
  });

  test(
    'lettura fallita: prima di scrivere rilegge, le date del server restano',
    () async {
      prefs.myListAddedReadError = Exception('giù');
      final c = container();
      final notifier = await open(c);
      expect(c.read(myListAddedProvider).value, isEmpty);
      prefs
        ..myListAddedReadError = null
        ..myListAdded = {'x': _d0};
      expect(await notifier.change({'a': _d1}), isTrue);
      expect(prefs.myListAddedWrites.single, {'x': _d0, 'a': _d1});
    },
  );

  test('lettura fallita anche alla rilettura: false, niente scritto', () async {
    prefs.myListAddedReadError = Exception('giù');
    final c = container();
    final notifier = await open(c);
    expect(await notifier.change({'a': _d1}), isFalse);
    expect(prefs.myListAddedWrites, isEmpty);
  });

  test('scrittura fallita: false e lo stato torna com\'era', () async {
    prefs.myListAdded = {'a': _d1};
    final c = container();
    final notifier = await open(c);
    prefs.myListAddedWriteError = Exception('giù');
    expect(await notifier.change({'a': null, 'b': _d2}), isFalse);
    expect(c.read(myListAddedProvider).value, {'a': _d1});
  });

  test(
    'prima scrittura fallita: la seconda non manda la voce tornata',
    () async {
      final c = container();
      final notifier = await open(c);
      prefs
        ..myListAddedWriteGate = Completer()
        ..myListAddedWriteError = Exception('giù');
      final first = notifier.change({'a': _d1});
      final second = notifier.change({'b': _d2});
      await pumpEventQueue();
      prefs.myListAddedWriteGate!.complete();
      expect(await first, isFalse);
      await second;
      expect(prefs.myListAddedWrites[1], {'b': _d2});
    },
  );

  test(
    'retainOnly non scrive; la scrittura dopo non ha le voci tolte',
    () async {
      prefs.myListAdded = {'a': _d1, 'b': _d2};
      final c = container();
      final notifier = await open(c);
      notifier.retainOnly({'a'});
      expect(c.read(myListAddedProvider).value, {'a': _d1});
      expect(prefs.myListAddedWrites, isEmpty);
      expect(await notifier.change({'c': _d0}), isTrue);
      expect(prefs.myListAddedWrites.single, {'a': _d1, 'c': _d0});
    },
  );

  test('retainOnly senza niente da togliere lascia lo stato com\'era', () async {
    prefs.myListAdded = {'a': _d1};
    final c = container();
    final notifier = await open(c);
    final before = c.read(myListAddedProvider);
    notifier.retainOnly({'a', 'b'});
    expect(identical(c.read(myListAddedProvider), before), isTrue);
  });

  test('al cambio di utente si rilegge', () async {
    prefs.myListAdded = {'a': _d1};
    final c = container();
    await open(c);
    prefs.myListAdded = {};
    session.quickConnectApproved(const JellyfinUser(id: 'u2', name: 'Luigi'));
    expect(await c.read(myListAddedProvider.future), isEmpty);
  });
}
