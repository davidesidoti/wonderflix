import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friend_search.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() {
    api = FakeSocialApi()
      ..searchResults['lu'] = [testSearchResult('u9', 'Lucia')]
      ..searchResults['lui'] = [testSearchResult('u2', 'Luigi')];
  });

  ProviderContainer container() {
    final c = ProviderContainer.test(overrides: socialTestOverrides(api));
    c.listen(friendSearchProvider, (_, _) {});
    return c;
  }

  /// Le ricerche fatte: la lista amici, che si rilegge da sola, non conta.
  List<String> searches() => [
        for (final call in api.calls)
          if (call.startsWith('search')) call,
      ];

  test('cerca 300 ms dopo l\'ultima lettera, da 2 lettere', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('l');
      async.elapse(FriendSearch.debounce);
      expect(searches(), isEmpty);
      expect(c.read(friendSearchProvider).active, isFalse);

      search.setQuery('lu');
      async.elapse(const Duration(milliseconds: 200));
      search.setQuery(' lui ');
      expect(c.read(friendSearchProvider).searching, isTrue);
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();

      expect(searches(), ['search lui']);
      final state = c.read(friendSearchProvider);
      expect(state.query, 'lui');
      expect(state.results.single.name, 'Luigi');
      expect(state.searching, isFalse);
    });
  });

  test('la risposta di una ricerca superata si scarta', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      final gate = api.searchGate = Completer<void>();
      search.setQuery('lu');
      async.elapse(FriendSearch.debounce);
      api.searchGate = null;
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      gate.complete();
      async.flushMicrotasks();
      expect(c.read(friendSearchProvider).results.single.name, 'Luigi');
    });
  });

  test('sotto 2 lettere i risultati spariscono', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      search.setQuery('l');
      expect(c.read(friendSearchProvider).results, isEmpty);
      expect(c.read(friendSearchProvider).active, isFalse);
    });
  });

  test('errore: lo dice e tiene i risultati; rerun ripete', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      api.nextFailure = SocialFailure.rateLimited;
      unawaited(search.rerun());
      async.flushMicrotasks();
      expect(c.read(friendSearchProvider).failure, SocialFailure.rateLimited);
      expect(c.read(friendSearchProvider).results.single.name, 'Luigi');
      unawaited(search.rerun());
      async.flushMicrotasks();
      expect(c.read(friendSearchProvider).failure, isNull);
      expect(searches(), ['search lui', 'search lui', 'search lui']);
    });
  });

  test('cambia la lista amici: la ricerca si ripete con la relazione nuova', () {
    fakeAsync((async) {
      final events = StreamController<ServerEvent>.broadcast();
      final c = ProviderContainer.test(
          overrides: socialTestOverrides(api, events: events.stream));
      c.listen(friendSearchProvider, (_, _) {});
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      expect(searches(), ['search lui']);
      expect(c.read(friendSearchProvider).results.single.relation,
          FriendRelation.none);

      // L'altra parte accetta mentre "lui" è ancora scritto.
      api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
      api.searchResults['lui'] = [
        testSearchResult('u2', 'Luigi', FriendRelation.friend),
      ];
      events.add(friendsChangedReceived());
      async.flushMicrotasks();

      expect(searches(), ['search lui', 'search lui']);
      expect(c.read(friendSearchProvider).results.single.relation,
          FriendRelation.friend);

      // Sotto le 2 lettere non c'è niente da ripetere.
      search.setQuery('l');
      api.snapshot = FriendsSnapshot.empty;
      events.add(friendsChangedReceived());
      async.flushMicrotasks();
      expect(searches(), ['search lui', 'search lui']);
      unawaited(events.close());
    });
  });
}
