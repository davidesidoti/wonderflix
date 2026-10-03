import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
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

  test('cerca 300 ms dopo l\'ultima lettera, da 2 lettere', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('l');
      async.elapse(FriendSearch.debounce);
      expect(api.calls, isEmpty);
      expect(c.read(friendSearchProvider).active, isFalse);

      search.setQuery('lu');
      async.elapse(const Duration(milliseconds: 200));
      search.setQuery(' lui ');
      expect(c.read(friendSearchProvider).searching, isTrue);
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();

      expect(api.calls, ['search lui']);
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
      expect(api.calls, ['search lui', 'search lui', 'search lui']);
    });
  });
}
