import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_user_editor.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeHomeApi home;
  late FakeDisplayPreferencesApi prefs;
  late FakeSessionController session;

  setUp(() {
    home = FakeHomeApi();
    prefs = FakeDisplayPreferencesApi();
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer bare() => ProviderContainer.test(
        overrides: homeOverrides(
            library: FakeLibraryApi(),
            home: home,
            prefs: prefs,
            features: const SocialFeatures(home: true),
            session: session),
        retry: (_, _) => null,
      );

  ProviderContainer container() {
    final c = bare();
    c.listen(homeUserEditorProvider, (_, _) {});
    return c;
  }

  HomeUserEditorState value(ProviderContainer c) =>
      c.read(homeUserEditorProvider).requireValue;

  test('legge la Home dell\'utente e la combina con quella dell\'admin', () {
    fakeAsync((async) {
      home.layoutRows = ['resume', 'nextUp', 'myList'];
      prefs.prefs =
          const HomeUserPrefs(rows: ['myList', 'resume'], hidden: ['nextUp']);
      final c = container();
      async.flushMicrotasks();
      final state = value(c);
      expect(state.rows,
          [HomeRowKind.myList, HomeRowKind.resume, HomeRowKind.nextUp]);
      expect(state.hidden, {HomeRowKind.nextUp});
      expect(state.defaultRows,
          [HomeRowKind.resume, HomeRowKind.nextUp, HomeRowKind.myList]);
      expect(state.canReset, isTrue);
      expect(prefs.readUsers, ['u1']);
    });
  });

  test('una modifica si salva 500 ms dopo, e più modifiche una volta sola',
      () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      expect(value(c).canReset, isFalse);
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(const Duration(milliseconds: 300));
      editor.setVisible(HomeRowKind.nextUp, false);
      expect(value(c).canReset, isTrue, reason: 'c\'è una modifica');
      async.elapse(const Duration(milliseconds: 499));
      expect(prefs.written, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      final (user, saved) = prefs.written.single;
      expect(user, 'u1');
      expect(saved.rows.first, 'myList');
      expect(saved.hidden, ['nextUp']);
      expect(value(c).stored.rows.first, 'myList');
    });
  });

  test('salvando restano gli id che l\'elenco non mostra', () {
    fakeAsync((async) {
      // L'admin ha spento continueSaga; "future" è di una versione nuova.
      home.layoutRows = ['resume', 'myList'];
      prefs.prefs = const HomeUserPrefs(
          rows: ['continueSaga', 'future', 'myList', 'resume'],
          hidden: ['future']);
      final c = container();
      async.flushMicrotasks();
      expect(value(c).rows, [HomeRowKind.myList, HomeRowKind.resume]);
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.resume, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      final saved = prefs.written.single.$2;
      expect(saved.rows, ['continueSaga', 'future', 'resume', 'myList']);
      expect(saved.hidden, ['future']);
    });
  });

  test('salvataggio fallito: si torna all\'ultimo salvato', () {
    fakeAsync((async) {
      prefs.writeError = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      final before = value(c).rows;
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      expect(value(c).rows.first, HomeRowKind.myList);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(value(c).rows, before);
      expect(value(c).saveFailed, isTrue);

      prefs.writeError = null;
      c
          .read(homeUserEditorProvider.notifier)
          .setVisible(HomeRowKind.resume, false);
      expect(value(c).saveFailed, isFalse, reason: 'una nuova modifica');
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.prefs.hidden, ['resume']);
    });
  });

  test('due salvataggi non si sovrappongono, e vale l\'ultimo stato', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1), reason: 'il primo è in volo');

      editor.setVisible(HomeRowKind.nextUp, false);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1),
          reason: 'il secondo aspetta che il primo finisca');

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(prefs.written, hasLength(2));
      expect(prefs.written.last.$2.hidden, ['nextUp']);
      expect(prefs.written.last.$2.rows.first, 'myList');
    });
  });

  test('un salvataggio fallito ferma quelli in coda', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      prefs.writeError = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      editor.setVisible(HomeRowKind.nextUp, false);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();

      gate.complete();
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1),
          reason: 'il secondo non parte dopo un errore');
      expect(value(c).saveFailed, isTrue);
      expect(value(c).hidden, isEmpty);
    });
  });

  test('lettura fallita: errore e nessun salvataggio', () {
    fakeAsync((async) {
      prefs.error = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      expect(c.read(homeUserEditorProvider).hasError, isTrue);
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      editor.setVisible(HomeRowKind.resume, false);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(prefs.written, isEmpty);
    });
  });

  test('Ripristina toglie le due voci e la Home si rilegge', () {
    fakeAsync((async) {
      prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
      final c = container();
      c.listen(homeUserPrefsProvider, (_, _) {});
      async.flushMicrotasks();
      final reads = prefs.readUsers.length;
      unawaited(c.read(homeUserEditorProvider.notifier).reset());
      async.flushMicrotasks();
      expect(prefs.resets, ['u1']);
      expect(value(c).hidden, isEmpty);
      expect(value(c).rows, HomeRowKind.values);
      expect(value(c).canReset, isFalse);
      // Riverpod ricompone `homeUserPrefsProvider` con un timer a zero.
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.readUsers.length, greaterThan(reads),
          reason: 'homeUserPrefsProvider si rilegge');
    });
  });

  test('chiudendo prima dei 500 ms la modifica si salva lo stesso', () {
    fakeAsync((async) {
      final c = bare();
      final sub = c.listen(homeUserEditorProvider, (_, _) {});
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      sub.close();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      expect(prefs.written.single.$2.rows.first, 'myList');
    });
  });

  test('cambiando profilo si legge la Home del nuovo utente', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      session.set(
          const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
      // Riverpod ricompone il controller con un timer a zero.
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.readUsers, ['u1', 'u2']);
      expect(c.read(homeUserEditorProvider).hasValue, isTrue);
    });
  });

  test('cambiando profilo con una modifica in attesa, si salva per il vecchio',
      () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      session.set(
          const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      expect(prefs.written.single.$1, 'u1',
          reason: 'la Home di Mario non finisce a Luigi');
      expect(prefs.written.single.$2.rows.first, 'myList');
      expect(value(c).stored.isEmpty, isTrue,
          reason: 'lo stato di Luigi non prende i ritocchi di Mario');
      expect(value(c).canReset, isFalse);
    });
  });
}
