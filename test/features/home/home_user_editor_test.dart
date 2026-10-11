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

  const luigi = SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi'));

  test('il salvataggio di Mario finisce dopo che Luigi è già letto', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1), reason: 'quello di Mario è in volo');

      session.set(luigi);
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.readUsers, ['u1', 'u2'],
          reason: 'Luigi non aspetta il salvataggio di Mario');
      expect(value(c).canReset, isFalse);

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(prefs.written.single.$1, 'u1');
      expect(value(c).stored.isEmpty, isTrue);
      expect(value(c).canReset, isFalse);
      expect(value(c).rows.first, isNot(HomeRowKind.myList));
    });
  });

  test('il salvataggio fallito di Mario non tocca Luigi né quelli suoi', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      prefs.writeError = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();

      session.set(luigi);
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(value(c).saveFailed, isFalse);

      prefs.writeError = null;
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(2));
      expect(prefs.written.last.$1, 'u2', reason: 'quello di Luigi parte');
      expect(value(c).saveFailed, isFalse);
    });
  });

  test('chiudendo prima dei 500 ms la Home si ricompone con la modifica', () {
    fakeAsync((async) {
      final c = bare();
      final sub = c.listen(homeUserEditorProvider, (_, _) {});
      c.listen(homeUserPrefsProvider, (_, _) {});
      async.flushMicrotasks();
      final reads = prefs.readUsers.length;
      final timers = async.nonPeriodicTimerCount;
      final gate = prefs.writeGate = Completer<void>();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      sub.close();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1), reason: 'subito, senza i 500 ms');
      expect(c.exists(homeUserEditorProvider), isTrue,
          reason: 'resta aperto finché salva');

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.readUsers.length, greaterThan(reads),
          reason: 'la Home dell\'utente si rilegge');
      expect(c.exists(homeUserEditorProvider), isFalse,
          reason: 'finito di salvare si chiude');
      expect(async.nonPeriodicTimerCount, timers);
    });
  });

  test('riaprendo le Impostazioni durante il salvataggio, è lo stesso', () {
    fakeAsync((async) {
      final c = bare();
      final sub = c.listen(homeUserEditorProvider, (_, _) {});
      async.flushMicrotasks();
      final gate = prefs.writeGate = Completer<void>();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      sub.close();
      async.elapse(Duration.zero);
      async.flushMicrotasks();

      c.listen(homeUserEditorProvider, (_, _) {});
      async.flushMicrotasks();
      expect(prefs.readUsers, ['u1'], reason: 'non si rilegge');
      expect(value(c).rows.first, HomeRowKind.myList);

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(value(c).stored.rows.first, 'myList');
    });
  });

  test('rileggendo con un salvataggio in volo, vale quello salvato', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));

      c.invalidate(homeUserEditorProvider);
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.readUsers, ['u1'],
          reason: 'aspetta che il salvataggio finisca');

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(prefs.readUsers, ['u1', 'u1']);
      expect(value(c).rows.first, HomeRowKind.myList);
      expect(value(c).stored.rows.first, 'myList');
    });
  });

  test('rileggendo con una modifica in attesa, si salva e poi si legge', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);

      c.invalidate(homeAdminRowsProvider);
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      expect(value(c).rows.first, HomeRowKind.myList);
      expect(value(c).stored.rows.first, 'myList');

      // L'elenco che si vede è quello del server: una seconda modifica non
      // cancella la prima.
      c
          .read(homeUserEditorProvider.notifier)
          .setVisible(HomeRowKind.nextUp, false);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written.last.$2.rows.first, 'myList');
      expect(prefs.written.last.$2.hidden, ['nextUp']);
    });
  });

  test('Ripristina cambia subito l\'elenco e aspetta un salvataggio in volo',
      () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1), reason: 'il salvataggio è in volo');

      unawaited(editor.reset());
      expect(value(c).rows, HomeRowKind.values, reason: 'subito');
      expect(value(c).canReset, isFalse);
      async.flushMicrotasks();
      expect(prefs.resets, isEmpty, reason: 'dopo il salvataggio');

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(prefs.resets, ['u1']);
      expect(prefs.prefs.isEmpty, isTrue, reason: 'prima salva, poi toglie');
      expect(value(c).rows, HomeRowKind.values);
      expect(value(c).stored.isEmpty, isTrue);
      expect(value(c).canReset, isFalse);
    });
  });

  test('Ripristina fallito: si torna all\'ultimo salvato', () {
    fakeAsync((async) {
      prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
      prefs.resetError = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      final before = value(c).rows;
      final editor = c.read(homeUserEditorProvider.notifier);
      unawaited(editor.reset());
      expect(value(c).hidden, isEmpty, reason: 'subito');
      editor.setVisible(HomeRowKind.nextUp, false);
      async.flushMicrotasks();

      expect(prefs.resets, ['u1']);
      expect(value(c).rows, before);
      expect(value(c).hidden, {HomeRowKind.resume});
      expect(value(c).stored.rows, ['myList']);
      expect(value(c).saveFailed, isTrue);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, isEmpty,
          reason: 'la modifica fatta dopo Ripristina non parte');
      expect(prefs.prefs.hidden, ['resume']);
    });
  });

  test('una modifica dopo Ripristina parte dalla Home predefinita', () {
    fakeAsync((async) {
      prefs.prefs = const HomeUserPrefs(
          rows: ['future', 'myList'], hidden: ['resume', 'future']);
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      unawaited(editor.reset());
      editor.setVisible(HomeRowKind.nextUp, false);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();

      expect(prefs.resets, ['u1']);
      final saved = prefs.written.single.$2;
      expect(saved.hidden, ['nextUp'], reason: 'senza i vecchi id');
      expect(saved.rows, [for (final row in HomeRowKind.values) row.id]);
      expect(prefs.prefs.hidden, ['nextUp'], reason: 'dopo il ripristino');
      expect(value(c).saveFailed, isFalse);
    });
  });

  test('mentre si rilegge l\'elenco non si modifica', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      c.invalidate(homeUserEditorProvider);
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      final loading = c.read(homeUserEditorProvider);
      expect(loading.isLoading, isTrue, reason: 'aspetta il salvataggio');
      expect(loading.hasValue, isTrue);

      editor.move(HomeRowKind.latestSeries, 0);
      editor.setVisible(HomeRowKind.resume, false);
      unawaited(editor.reset());
      async.elapse(homeEditorSaveDelay * 2);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      expect(prefs.resets, isEmpty);

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      async.elapse(homeEditorSaveDelay * 2);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      expect(prefs.resets, isEmpty);
      expect(value(c).rows.first, HomeRowKind.myList);
      expect(value(c).hidden, isEmpty);
      expect(value(c).stored.rows.first, 'myList');
    });
  });

  test('Ripristina con un salvataggio in volo: i suoi id non tornano', () {
    fakeAsync((async) {
      prefs.prefs = const HomeUserPrefs(
          rows: ['future', 'myList'], hidden: ['future']);
      final writeGate = prefs.writeGate = Completer<void>();
      final resetGate = prefs.resetGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.nextUp, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written.single.$2.rows, contains('future'));

      unawaited(editor.reset());
      prefs.writeGate = null;
      writeGate.complete();
      async.flushMicrotasks();
      expect(prefs.resets, ['u1'], reason: 'il ripristino è in volo');
      expect(value(c).stored.isEmpty, isTrue,
          reason: 'il salvataggio di prima non rimette i suoi id');
      expect(value(c).canReset, isFalse);

      editor.setVisible(HomeRowKind.resume, false);
      prefs.resetGate = null;
      resetGate.complete();
      async.flushMicrotasks();
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      final saved = prefs.written.last.$2;
      expect(saved.hidden, ['resume']);
      expect(saved.rows, isNot(contains('future')));
      expect(prefs.prefs.rows, isNot(contains('future')));
      expect(prefs.prefs.hidden, ['resume']);
    });
  });

  test('Ripristina senza la Home letta non fa niente', () {
    fakeAsync((async) {
      prefs.error = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      unawaited(c.read(homeUserEditorProvider.notifier).reset());
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(prefs.resets, isEmpty);
      expect(c.read(homeUserEditorProvider).hasError, isTrue);
    });
  });
}
