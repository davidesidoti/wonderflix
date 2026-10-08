import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/avatar_fakes.dart';
import '../../support/profile_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeAvatarsApi api;

  setUp(() => api = FakeAvatarsApi()
    ..users = const [
      UserAvatarInfo(userId: 'u1', name: 'Mario', imageTag: 't1'),
      UserAvatarInfo(userId: 'u2', name: 'Luigi'),
    ]);

  group('AvatarDirectory', () {
    test('raccoglie le richieste di 50 ms in una sola chiamata', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        AvatarImage? byId;
        AvatarImage? sameAgain;
        AvatarImage? luigi = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('U-1')).then((v) => byId = v);
        async.elapse(const Duration(milliseconds: 20));
        directory.imageFor(AvatarLookup.byName('LUIGI')).then((v) => luigi = v);
        // La stessa richiesta: 'U-1' e 'u1' sono lo stesso id.
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => sameAgain = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(api.calls, hasLength(1));
        expect(api.calls.single.ids, ['u1']);
        // Il nome va al plugin com'è scritto: le maiuscole le ignora lui.
        expect(api.calls.single.names, ['LUIGI']);
        expect(byId, const AvatarImage('u1', 't1'));
        expect(sameAgain, const AvatarImage('u1', 't1'));
        // Luigi non ha un'immagine: l'iniziale.
        expect(luigi, isNull);
      });
    });

    test('per nome: l\'id viene dalla risposta, e vale anche per id', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        AvatarImage? byName;
        directory.imageFor(AvatarLookup.byName('Mario')).then((v) => byName = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(byName, const AvatarImage('u1', 't1'));

        AvatarImage? byId;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        async.flushMicrotasks();
        expect(byId, const AvatarImage('u1', 't1'));
        expect(api.calls, hasLength(1));
      });
    });

    test('un risultato vale 10 minuti', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);

        async.elapse(const Duration(minutes: 9));
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));

        async.elapse(const Duration(minutes: 2));
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(2));
      });
    });

    test('un errore lascia le iniziali, e si riprova dopo 10 minuti', () {
      fakeAsync((async) {
        api.error = const ServerUnreachableException();
        final directory = AvatarDirectory(api);
        AvatarImage? first = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => first = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(first, isNull);

        api.error = null;
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));

        async.elapse(AvatarDirectory.defaultTtl);
        AvatarImage? later;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => later = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(later, const AvatarImage('u1', 't1'));
      });
    });

    test('al massimo 100 voci per chiamata', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        for (var i = 0; i < 150; i++) {
          directory.imageFor(AvatarLookup.byId('id$i'));
        }
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(api.calls.map((call) => call.ids.length), [100, 50]);
      });
    });

    test('remember: un\'immagine appena cambiata vale subito', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api)
          ..remember(userId: 'U1', name: 'Mario', tag: 't9');
        AvatarImage? byId;
        AvatarImage? byName;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        directory.imageFor(AvatarLookup.byName('mario')).then((v) => byName = v);
        async.flushMicrotasks();

        expect(byId, const AvatarImage('u1', 't9'));
        expect(byName, const AvatarImage('u1', 't9'));
        expect(api.calls, isEmpty);
      });
    });

    test('dispose: le richieste in attesa finiscono con l\'iniziale', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        AvatarImage? pending = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => pending = v);
        directory.dispose();
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(pending, isNull);
        expect(api.calls, isEmpty);
      });
    });

    test('una richiesta già partita: si aspetta la sua risposta, niente '
        'seconda chiamata', () {
      fakeAsync((async) {
        final answer = Completer<void>();
        api.hold = answer.future;
        final directory = AvatarDirectory(api);
        AvatarImage? first;
        AvatarImage? during;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => first = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));

        directory.imageFor(AvatarLookup.byId('U-1')).then((v) => during = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));

        answer.complete();
        async.flushMicrotasks();
        expect(first, const AvatarImage('u1', 't1'));
        expect(during, const AvatarImage('u1', 't1'));
      });
    });

    test('remember durante una chiamata: la risposta non lo sovrascrive', () {
      fakeAsync((async) {
        final answer = Completer<void>();
        api.hold = answer.future;
        final directory = AvatarDirectory(api);
        AvatarImage? asked;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => asked = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);

        // L'immagine cambia mentre la risposta (con il tag di prima) viaggia.
        directory.remember(userId: 'u1', name: 'Mario', tag: 't9');
        answer.complete();
        async.flushMicrotasks();

        expect(asked, const AvatarImage('u1', 't9'));
        AvatarImage? byId;
        AvatarImage? byName;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        directory.imageFor(AvatarLookup.byName('Mario')).then((v) => byName = v);
        async.flushMicrotasks();
        expect(byId, const AvatarImage('u1', 't9'));
        expect(byName, const AvatarImage('u1', 't9'));
        expect(api.calls, hasLength(1));
      });
    });

    test('una chiamata fallita nel frattempo non copre la risposta di una '
        'partita prima', () {
      fakeAsync((async) {
        final answer = Completer<void>();
        api.hold = answer.future;
        final directory = AvatarDirectory(api);
        // La prima chiamata (per nome) resta in viaggio.
        directory.imageFor(AvatarLookup.byName('Mario'));
        async.elapse(AvatarDirectory.defaultBatchDelay);

        // La seconda (per id) parte dopo e fallisce subito.
        api
          ..hold = null
          ..error = const ServerUnreachableException();
        AvatarImage? failed = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => failed = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(failed, isNull);

        // La prima risponde: Mario è u1, con l'immagine.
        api.error = null;
        answer.complete();
        async.flushMicrotasks();

        AvatarImage? byId;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        async.flushMicrotasks();
        expect(byId, const AvatarImage('u1', 't1'));
        expect(api.calls, hasLength(2));
      });
    });

    test('una chiamata che fallisce dopo non copre un\'immagine trovata nel '
        'frattempo', () {
      fakeAsync((async) {
        final answer = Completer<void>();
        api.hold = answer.future;
        final directory = AvatarDirectory(api);
        // La prima chiamata (per id) resta in viaggio.
        AvatarImage? asked;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => asked = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);

        // La seconda (per nome) parte dopo e trova Mario, cioè u1.
        api.hold = null;
        directory.imageFor(AvatarLookup.byName('Mario'));
        async.elapse(AvatarDirectory.defaultBatchDelay);

        // La prima fallisce.
        api.error = const ServerUnreachableException();
        answer.complete();
        async.flushMicrotasks();

        expect(asked, const AvatarImage('u1', 't1'));
        AvatarImage? byId;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        async.flushMicrotasks();
        expect(byId, const AvatarImage('u1', 't1'));
        expect(api.calls, hasLength(2));
      });
    });

    test('id vuoto: l\'iniziale subito, senza chiamate', () {
      fakeAsync((async) {
        api.users = const [UserAvatarInfo(userId: '', name: 'Nessuno', imageTag: 't0')];
        final directory = AvatarDirectory(api);
        AvatarImage? empty = const AvatarImage('x', 'x');
        AvatarImage? dashes = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('')).then((v) => empty = v);
        // Senza i trattini non resta niente.
        directory.imageFor(AvatarLookup.byId('--')).then((v) => dashes = v);
        async.flushMicrotasks();
        expect(empty, isNull);
        expect(dashes, isNull);

        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, isEmpty);
      });
    });

    test('dispose durante una chiamata: tutto finisce con l\'iniziale, senza '
        'errori', () {
      fakeAsync((async) {
        final answer = Completer<void>();
        api.hold = answer.future;
        final directory = AvatarDirectory(api);
        AvatarImage? sent = const AvatarImage('x', 'x');
        AvatarImage? joined = const AvatarImage('x', 'x');
        AvatarImage? waiting = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => sent = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => joined = v);
        directory.imageFor(AvatarLookup.byId('u2')).then((v) => waiting = v);

        directory.dispose();
        async.flushMicrotasks();
        expect(sent, isNull);
        expect(joined, isNull);
        expect(waiting, isNull);

        // La risposta che arriva dopo non completa di nuovo niente.
        answer.complete();
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));
      });
    });

    test('nome vuoto: l\'iniziale subito, senza chiamate', () {
      fakeAsync((async) {
        api.users = const [UserAvatarInfo(userId: 'u3', name: '', imageTag: 't3')];
        final directory = AvatarDirectory(api);
        AvatarImage? byId;
        directory.imageFor(AvatarLookup.byId('u3')).then((v) => byId = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(byId, const AvatarImage('u3', 't3'));

        // L'utente senza nome non vale per il nome vuoto.
        AvatarImage? empty = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byName('')).then((v) => empty = v);
        async.flushMicrotasks();
        expect(empty, isNull);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));
      });
    });
  });

  group('provider', () {
    ProviderContainer container(FixedProfiles profiles,
            {SocialFeatures features = const SocialFeatures(avatars: true),
            FakeSocialAvailability? availability}) =>
        ProviderContainer.test(
          overrides: [
            profilesProvider.overrideWith(() => profiles),
            socialAvailabilityProvider.overrideWith(
                () => availability ?? FakeSocialAvailability(features)),
            avatarsApiProvider.overrideWithValue(api),
          ],
          retry: (_, _) => null,
        );

    test('senza un profilo aperto: niente cache, e la sessione non si crea', () {
      // Senza override della sessione: se si leggesse, lancerebbe
      // (clientInfoProvider va sovrascritto).
      final c = ProviderContainer.test(
        overrides: [avatarsApiProvider.overrideWithValue(api)],
        retry: (_, _) => null,
      );
      expect(c.read(avatarDirectoryProvider), isNull);
    });

    test('senza la funzione avatars: niente cache', () {
      final c = container(FixedProfiles(const ProfilesState(activeUserId: 'u1')),
          features: const SocialFeatures());
      expect(c.read(avatarDirectoryProvider), isNull);
    });

    test('una cache per profilo', () {
      final profiles = FixedProfiles(const ProfilesState(activeUserId: 'u1'));
      final c = container(profiles);
      final first = c.read(avatarDirectoryProvider);
      expect(first, isNotNull);

      profiles.set(const ProfilesState(activeUserId: 'u2'));
      final second = c.read(avatarDirectoryProvider);
      expect(second, isNotNull);
      expect(second, isNot(same(first)));
    });

    test('avatarImageProvider senza cache: null, nessuna chiamata', () async {
      final c = ProviderContainer.test(
        overrides: [avatarsApiProvider.overrideWithValue(api)],
        retry: (_, _) => null,
      );
      final lookup = AvatarLookup.byName('Mario');
      c.listen(avatarImageProvider(lookup), (_, _) {});

      expect(await c.read(avatarImageProvider(lookup).future), isNull);
      expect(api.calls, isEmpty);
    });

    test('un altro profilo chiude la cache di prima: le sue richieste '
        'finiscono con l\'iniziale', () async {
      final profiles = FixedProfiles(const ProfilesState(activeUserId: 'u1'));
      final c = container(profiles);
      final pending =
          c.read(avatarDirectoryProvider)!.imageFor(AvatarLookup.byId('u1'));

      profiles.set(const ProfilesState(activeUserId: 'u2'));
      c.read(avatarDirectoryProvider);

      expect(await pending, isNull);
      expect(api.calls, isEmpty);
    });

    test('la funzione avatars che arriva dopo crea la cache', () {
      final availability = FakeSocialAvailability(const SocialFeatures());
      final c = container(
          FixedProfiles(const ProfilesState(activeUserId: 'u1')),
          availability: availability);
      expect(c.read(avatarDirectoryProvider), isNull);

      availability.set(const SocialFeatures(avatars: true));
      expect(c.read(avatarDirectoryProvider), isNotNull);
    });

    test('un avatar sullo schermo si rilegge dopo il ttl: dopo un errore '
        'arriva l\'immagine', () {
      fakeAsync((async) {
        api.error = const ServerUnreachableException();
        final c = container(
            FixedProfiles(const ProfilesState(activeUserId: 'u1')));
        final lookup = AvatarLookup.byId('u1');
        c.listen(avatarImageProvider(lookup), (_, _) {});
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(c.read(avatarImageProvider(lookup)).value, isNull);
        expect(api.calls, hasLength(1));

        api.error = null;
        async.elapse(AvatarDirectory.defaultTtl);
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(api.calls, hasLength(2));
        expect(c.read(avatarImageProvider(lookup)).value,
            const AvatarImage('u1', 't1'));
      });
    });
  });
}
