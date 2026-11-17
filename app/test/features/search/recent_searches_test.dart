import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/search/recent_searches.dart';

import '../../support/fake_session_controller.dart';

void main() {
  late SharedPreferences prefs;

  ProviderContainer makeContainer({String userId = 'u1'}) {
    final container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            SessionSignedIn(JellyfinUser(id: userId, name: userId)))),
      ],
      retry: (_, _) => null,
    );
    container.listen(recentSearchesProvider, (_, _) {});
    return container;
  }

  late ProviderContainer container;
  RecentSearches recent() => container.read(recentSearchesProvider.notifier);
  List<String> state() => container.read(recentSearchesProvider);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = makeContainer();
  });

  test('il più recente in cima, al massimo 8', () {
    for (var i = 1; i <= 9; i++) {
      recent().add('termine $i');
    }
    expect(state(), hasLength(8));
    expect(state().first, 'termine 9');
    expect(state(), isNot(contains('termine 1')));
  });

  test('un doppione torna in cima una volta sola', () {
    recent()
      ..add('dune')
      ..add('dark')
      ..add('Dune ');
    expect(state(), ['Dune', 'dark']);
  });

  test('i doppioni non badano agli accenti', () {
    recent()
      ..add('citta')
      ..add('dark')
      ..add('Città');
    expect(state(), ['Città', 'dark']);
  });

  test('sotto le 2 lettere non si salva', () {
    recent().add(' d ');
    expect(state(), isEmpty);
    expect(prefs.getStringList('search.recent.u1'), isNull);
  });

  test('resta sul dispositivo dopo un riavvio', () {
    recent().add('chernobyl');
    expect(makeContainer().read(recentSearchesProvider), ['chernobyl']);
  });

  test('ogni profilo ha le sue', () {
    recent().add('dune');
    final other = makeContainer(userId: 'u2');
    expect(other.read(recentSearchesProvider), isEmpty);
    other.read(recentSearchesProvider.notifier).add('dark');
    expect(state(), ['dune']);
    expect(prefs.getStringList('search.recent.u2'), ['dark']);
  });

  test('togli e cancella', () {
    recent()
      ..add('dune')
      ..add('dark');
    recent().remove('Dune');
    expect(state(), ['dark']);
    expect(prefs.getStringList('search.recent.u1'), ['dark']);
    recent().clear();
    expect(state(), isEmpty);
    expect(prefs.getStringList('search.recent.u1'), isEmpty);
  });
}
