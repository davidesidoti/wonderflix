import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late SharedPreferences prefs;
  late FakeSessionController session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    library = FakeLibraryApi();
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() {
    final c = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(() => session),
      ],
      retry: (_, _) => null,
    );
    c.listen(tonightControllerProvider, (_, _) {});
    return c;
  }

  JellyfinItem movie(String id) =>
      testItem(id: id, name: id, runtimeMinutes: 100);
  JellyfinItem fresh(String id) => testItem(
      id: id,
      name: id,
      kind: ItemKind.series,
      recursiveCount: 8,
      unplayedCount: 8);
  JellyfinItem started(String id) => testItem(
      id: id,
      name: id,
      kind: ItemKind.series,
      recursiveCount: 8,
      unplayedCount: 3);

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  TonightState state(ProviderContainer c) => c.read(tonightControllerProvider);
  String? pickId(ProviderContainer c) => state(c).pick.value?.id;

  test('i filtri vengono dal profilo, e la prima pescata li usa', () async {
    await prefs.setString(tonightTypeKey, 'series');
    await prefs.setString(tonightDurationKey, '90');
    await prefs.setString(tonightGenreKey, 'Dramma');
    final c = container();
    await settle();
    expect(state(c).filters,
        const TonightFilters(
            type: TonightType.series,
            duration: TonightDuration.under90,
            genre: 'Dramma'));
    final call = library.randomCalls.single;
    expect(call.kinds, {ItemKind.series});
    expect(call.genre, 'Dramma');
    expect(call.limit, tonightBatch);
  });

  test('la prima pescata propone il primo titolo che va bene', () async {
    library.randomPages.add(pageOf([started('s1'), movie('m2'), fresh('s3')]));
    final c = container();
    expect(state(c).pick.isLoading, isTrue);
    await settle();
    expect(pickId(c), 'm2');
    expect(c.read(tonightSeenProvider), {'m2'});
  });

  test('Un altro prende il prossimo della pescata, senza chiamare', () async {
    library.randomPages.add(pageOf([movie('m1'), fresh('s2')]));
    final c = container();
    await settle();
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 's2');
    expect(library.randomCalls, hasLength(1));
  });

  test('finita la pescata se ne fa un\'altra, e i già proposti non tornano',
      () async {
    library.randomPages
      ..add(pageOf([movie('m1')], 200))
      ..add(pageOf([movie('m1'), movie('m2')], 200));
    final c = container();
    await settle();
    expect(pickId(c), 'm1');
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 'm2');
    expect(library.randomCalls, hasLength(2));
  });

  test('già proposti tutti: si ricomincia', () async {
    library.randomPages.add(pageOf([movie('m1')], 1));
    final c = container();
    await settle();
    expect(pickId(c), 'm1');
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 'm1', reason: 'invece di "Nessun titolo"');
    expect(library.randomCalls, hasLength(2),
        reason: 'la pescata era già tutto: una sola chiamata in più');
  });

  test('nessun titolo: al massimo tre pescate', () async {
    library.randomPages.add(pageOf([started('s1')], 500));
    final c = container();
    await settle();
    expect(state(c).pick, const AsyncData<JellyfinItem?>(null));
    expect(library.randomCalls, hasLength(tonightMaxBatches));

    library.randomCalls.clear();
    library.randomPages
      ..clear()
      ..add(pageOf([started('s1')], 1));
    await c.read(tonightControllerProvider.notifier).another();
    expect(state(c).pick.value, isNull);
    expect(library.randomCalls, hasLength(1),
        reason: 'il totale stava tutto in una pescata');
  });

  test('errore, poi Un altro riprova', () async {
    library.error = const ServerUnreachableException();
    final c = container();
    await settle();
    expect(state(c).pick.hasError, isTrue);
    library.error = null;
    library.randomPages.add(pageOf([movie('m1')]));
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 'm1');
  });

  test('cambiando i filtri si riparte da capo e si ricordano', () async {
    library.randomPages.add(pageOf([movie('m1'), movie('m2')]));
    final c = container();
    await settle();
    await c.read(tonightControllerProvider.notifier).setFilters(
        const TonightFilters(
            type: TonightType.movies,
            duration: TonightDuration.under90,
            genre: 'Azione'));
    await settle();
    expect(prefs.getString(tonightTypeKey), 'movies');
    expect(prefs.getString(tonightDurationKey), '90');
    expect(prefs.getString(tonightGenreKey), 'Azione');
    expect(library.randomCalls.last.genre, 'Azione');
    expect(library.randomCalls.last.kinds, {ItemKind.movie});
    expect(library.randomCalls, hasLength(2),
        reason: 'la coda della pescata di prima non vale più');

    await c
        .read(tonightControllerProvider.notifier)
        .setFilters(TonightFilters.defaults);
    await settle();
    expect(prefs.getString(tonightGenreKey), isNull);
  });

  test('una risposta arrivata dopo un cambio di filtri si ignora', () async {
    final gate = library.randomGate = Completer<void>();
    library.randomPages
      ..add(pageOf([movie('vecchio')]))
      ..add(pageOf([movie('nuovo')]));
    final c = container();
    await settle();
    unawaited(c
        .read(tonightControllerProvider.notifier)
        .setFilters(const TonightFilters(type: TonightType.movies)));
    await settle();
    library.randomGate = null;
    gate.complete();
    await settle();
    expect(pickId(c), 'nuovo');
  });

  test('i generi del menu: con Entrambi quelli di film e serie insieme',
      () async {
    library.filtersByKind
      ..[ItemKind.movie] =
          const LibraryFilters(genres: ['Dramma', 'azione', 'Anime'])
      ..[ItemKind.series] = const LibraryFilters(genres: ['Dramma', 'Giallo']);
    final c = container();
    Future<List<String>> genres(TonightType type) async {
      c.listen(tonightGenresProvider(type), (_, _) {});
      return c.read(tonightGenresProvider(type).future);
    }

    expect(await genres(TonightType.both),
        ['Anime', 'azione', 'Dramma', 'Giallo']);
    expect(await genres(TonightType.movies), ['Anime', 'azione', 'Dramma']);
    expect(await genres(TonightType.series), ['Dramma', 'Giallo']);
  });

  test('cambiando account i già proposti ripartono da zero', () async {
    library.randomPages.add(pageOf([movie('m1')]));
    final c = container();
    c.listen(tonightSeenProvider, (_, _) {});
    await settle();
    expect(c.read(tonightSeenProvider), {'m1'});
    session.set(
        const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
    await settle();
    expect(c.read(tonightSeenProvider), isEmpty);
  });
}
