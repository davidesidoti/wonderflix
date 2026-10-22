import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;
  late ProviderContainer container;

  setUp(() {
    api = FakeLibraryApi();
    container = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
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

  test('togglePlayed: in caso di errore torna allo stato precedente', () async {
    final item = testItem(played: false);
    api.error = const ServerUnreachableException();
    await expectLater(overrides().togglePlayed(item),
        throwsA(isA<ServerUnreachableException>()));
    expect(overrides().effective(item).played, isFalse);
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
