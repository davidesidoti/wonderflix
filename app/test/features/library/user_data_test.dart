import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;
  late FakeDisplayPreferencesApi prefs;
  late ProviderContainer container;

  setUp(() {
    api = FakeLibraryApi();
    prefs = FakeDisplayPreferencesApi();
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        displayPreferencesApiProvider.overrideWithValue(prefs),
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(const SessionSignedIn(testUser))),
      ],
      retry: (_, _) => null,
    );
  });

  UserDataOverrides overrides() => container.read(userDataOverridesProvider.notifier);

  test('currentUserId viene dalla sessione', () {
    expect(container.read(currentUserIdProvider), 'u1');
  });

  test('toggleFavorite: aggiornamento immediato e conferma del server', () async {
    final item = testItem(favorite: false);
    final pending = overrides().toggleFavorite(item);
    expect(overrides().effective(item).isFavorite, isTrue, reason: 'ottimistico');
    await pending;
    expect(api.favoriteCalls, [('m1', true)]);
    expect(overrides().effective(item).isFavorite, isTrue);
  });

  test('il cuore non cancella gli avanzamenti di una serie', () async {
    // Il server risponde senza PlayedPercentage né UnplayedItemCount, come per
    // una serie.
    final series = testItem(
        id: 's',
        kind: ItemKind.series,
        favorite: true,
        playedPercentage: 40,
        unplayedCount: 3);
    await overrides().toggleFavorite(series);
    final data = container.read(userDataOverridesProvider)['s']!;
    expect(data.isFavorite, isFalse);
    expect(data.playedPercentage, 40);
    expect(data.unplayedItemCount, 3);
  });

  group('La mia lista: la data', () {
    final d0 = DateTime.utc(2026, 1, 2);

    test('cuore acceso: la data di adesso; spento: la voce sparisce', () async {
      final item = testItem(id: 'a', favorite: false);
      await withClock(Clock.fixed(DateTime.utc(2026, 11, 15, 10)),
          () => overrides().toggleFavorite(item));
      expect(prefs.myListAddedWrites.last, {'a': DateTime.utc(2026, 11, 15, 10)});
      await overrides().toggleFavorite(item);
      expect(prefs.myListAddedWrites.last, isEmpty);
    });

    test('data non salvata: il cuore resta acceso', () async {
      prefs.myListAddedWriteError = Exception('no');
      final item = testItem(id: 'a', favorite: false);
      await overrides().toggleFavorite(item);
      expect(overrides().effective(item).isFavorite, isTrue);
    });

    test('setFavorites: una scrittura sola della data per tutti', () async {
      final items = [for (final id in ['a', 'b', 'c']) testItem(id: id, favorite: true)];
      prefs.myListAdded = {'a': d0, 'b': d0, 'c': d0, 'x': d0};
      final failed = await overrides().setFavorites(items, favorite: false);
      expect(failed, isEmpty);
      expect(
          api.favoriteCalls,
          unorderedEquals([('a', false), ('b', false), ('c', false)]));
      expect(prefs.myListAddedWrites, hasLength(1));
      expect(prefs.myListAddedWrites.single, {'x': d0});
    });

    test('setFavorites con addedAt rimette le date di prima', () async {
      final a = testItem(id: 'a', favorite: false);
      await overrides().setFavorites([a], favorite: true, addedAt: {'a': d0});
      expect(prefs.myListAddedWrites.last['a'], d0);
      expect(overrides().effective(a).isFavorite, isTrue);
    });

    test("setFavorites: un fallimento torna com'era ed è nel risultato", () async {
      final a = testItem(id: 'a', favorite: true);
      final b = testItem(id: 'b', favorite: true);
      api.favoriteErrors['b'] = ServerUnreachableException();
      final failed = await overrides().setFavorites([a, b], favorite: false);
      expect(failed.map((i) => i.id), ['b']);
      expect(container.read(userDataOverridesProvider)['b']!.isFavorite, isTrue);
      expect(container.read(userDataOverridesProvider)['a']!.isFavorite, isFalse);
      expect(prefs.myListAddedWrites, hasLength(1));
    });

    test('setFavorites salta un titolo con una richiesta in corso', () async {
      final a = testItem(id: 'a', favorite: false);
      final b = testItem(id: 'b', favorite: false);
      final gate = api.favoriteGates['a'] = Completer<void>();
      final inFlight = overrides().toggleFavorite(a);
      final all = overrides().setFavorites([a, b], favorite: true);
      gate.complete();
      await Future.wait([inFlight, all]);
      expect(api.favoriteCalls.where((c) => c.$1 == 'a'), hasLength(1));
      expect(api.favoriteCalls.where((c) => c.$1 == 'b'), hasLength(1));
      expect(prefs.myListAdded.keys, unorderedEquals(['a', 'b']));
    });
  });

  test('togglePlayed: in caso di errore torna allo stato precedente', () async {
    final item = testItem(played: false);
    api.error = const ServerUnreachableException();
    await expectLater(overrides().togglePlayed(item),
        throwsA(isA<ServerUnreachableException>()));
    expect(overrides().effective(item).played, isFalse);
  });

  test('setPlaybackPosition: subito a 0 senza avanzamento, visto intatto',
      () async {
    final item = testItem(positionTicks: 500, playedPercentage: 20, played: true);
    final pending = overrides().setPlaybackPosition(item, 0);
    final now = overrides().effective(item);
    expect(now.playbackPositionTicks, 0, reason: 'ottimistico');
    expect(now.progress, isNull);
    expect(now.played, isTrue);
    await pending;
    expect(api.positionCalls, [('m1', 0)]);
    expect(api.playedCalls, isEmpty);
  });

  test('setPlaybackPosition: in caso di errore torna il punto di prima',
      () async {
    final item = testItem(positionTicks: 500, playedPercentage: 20);
    api.error = const ServerUnreachableException();
    await expectLater(overrides().setPlaybackPosition(item, 0),
        throwsA(isA<ServerUnreachableException>()));
    expect(overrides().effective(item).playbackPositionTicks, 500);
    expect(overrides().effective(item).progress, closeTo(0.2, 1e-9));
  });

  test('secondo tocco mentre il primo è in corso: ignorato', () async {
    final item = testItem(favorite: false);
    final first = overrides().toggleFavorite(item);
    final second = overrides().toggleFavorite(item);
    await Future.wait([first, second]);
    expect(api.favoriteCalls, [('m1', true)], reason: 'una sola richiesta');
    expect(overrides().effective(item).isFavorite, isTrue);

    // Finita la richiesta si può di nuovo cambiare.
    await overrides().toggleFavorite(item);
    expect(api.favoriteCalls.last, ('m1', false));
  });

  test('applyAll e clear', () {
    final data = testItem().userData;
    overrides().applyAll({
      'a': data.copyWith(played: true),
      'b': data.copyWith(isFavorite: true),
    });
    expect(container.read(userDataOverridesProvider).keys, ['a', 'b']);
    overrides().clear();
    expect(container.read(userDataOverridesProvider), isEmpty);
  });

  test('apply da evento server', () {
    final item = testItem();
    overrides().apply('m1', item.userData.copyWith(played: true));
    expect(container.read(userDataOverridesProvider)['m1']?.played, isTrue);
  });

  test('libraryRevision aumenta', () {
    container.read(libraryRevisionProvider.notifier).bump();
    expect(container.read(libraryRevisionProvider), 1);
  });
}
