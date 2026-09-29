import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/discord/discord_ipc.dart';
import 'package:wonderflix/features/discord/discord_activity.dart';
import 'package:wonderflix/features/discord/discord_presence.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';

import '../../support/discord_fakes.dart';

void main() {
  late FakeDiscordPipe pipe;
  late DiscordSettings settings;
  const labels = DiscordLabels(paused: 'In pausa', button: 'Entra in WonderFlix');
  const poster = 'https://media.example.com/p.jpg';

  setUp(() {
    pipe = FakeDiscordPipe();
    settings = const DiscordSettings();
  });

  DiscordPresence presence() => DiscordPresence(
        createClient: () => DiscordIpcClient(pipe,
            clientId: '123', pollInterval: const Duration(milliseconds: 10)),
        settings: () => settings,
        labels: () => labels,
        supportUrl: Uri.parse('https://discord.gg/abc'),
        processId: 42,
      );

  /// Avvia un episodio e aspetta il primo invio.
  DiscordPresence started(FakeAsync async) {
    final p = presence();
    unawaited(p.setMetadata(
        title: 'Breaking Bad', subtitle: 'S1:E4 · Pilot', thumbnailUrl: poster));
    async.flushMicrotasks();
    return p;
  }

  test('all\'avvio: titolo, episodio, locandina e pulsante', () {
    fakeAsync((async) {
      started(async);
      expect(pipe.handshakes, [
        {'v': 1, 'client_id': '123'},
      ]);
      expect(pipe.activities.single, {
        'type': 3,
        'details': 'Breaking Bad',
        'state': 'S1:E4 · Pilot',
        'assets': {'large_image': poster, 'large_text': 'Breaking Bad'},
        'buttons': [
          {'label': 'Entra in WonderFlix', 'url': 'https://discord.gg/abc'},
        ],
      });
      expect(pipe.pids.single, 42);
    });
  });

  test('tempi dalla posizione, al massimo un invio ogni 5 s', () {
    fakeAsync((async) {
      final t0 = clock.now();
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 47)));
      async.flushMicrotasks();
      expect(pipe.activities, hasLength(1));

      async.elapse(const Duration(seconds: 5));
      final begin = t0.subtract(const Duration(minutes: 10));
      expect(pipe.activities, hasLength(2));
      expect(pipe.activities.last!['timestamps'], {
        'start': begin.millisecondsSinceEpoch,
        'end': begin.add(const Duration(minutes: 47)).millisecondsSinceEpoch,
      });
    });
  });

  test('piccoli scarti di posizione non si inviano, i salti sì', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 10));
      expect(pipe.activities, hasLength(2));

      // 10 s dopo la posizione è avanzata di 11 s: scarto di 1 s.
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10, seconds: 11),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities, hasLength(2));

      // Salto in avanti di 20 minuti.
      unawaited(p.setTimeline(
          position: const Duration(minutes: 30, seconds: 15),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities, hasLength(3));
    });
  });

  test('in pausa: "In pausa" senza tempi', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 47)));
      unawaited(p.setPlaying(false));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last!['state'], 'In pausa');
      expect(pipe.activities.last!.containsKey('timestamps'), isFalse);
    });
  });

  test('ripresa dopo la pausa: inizio dalla posizione, non dall\'ultimo tick',
      () {
    fakeAsync((async) {
      final t0 = clock.now();
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(seconds: 52),
          duration: const Duration(minutes: 47)));
      unawaited(p.setPlaying(false));
      async.elapse(const Duration(seconds: 3));
      unawaited(p.setPlaying(true));
      async.elapse(const Duration(seconds: 2));
      final resumed = t0.add(const Duration(seconds: 3));
      expect((pipe.activities.last!['timestamps'] as Map)['start'],
          resumed.subtract(const Duration(seconds: 52)).millisecondsSinceEpoch);
    });
  });

  test('uscita dal player: attività cancellata', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.clear());
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last, isNull);
    });
  });

  test('Discord chiuso: riprova ogni 30 s, poi mostra l\'attività', () {
    fakeAsync((async) {
      pipe.available = false;
      final p = started(async);
      unawaited(p.setPlaying(false));
      async.flushMicrotasks();
      expect(pipe.opens, 1);
      expect(pipe.activities, isEmpty);

      async.elapse(const Duration(seconds: 29));
      expect(pipe.opens, 1);
      async.elapse(const Duration(seconds: 1));
      expect(pipe.opens, 2);

      pipe.available = true;
      async.elapse(const Duration(seconds: 30));
      expect(pipe.opens, 3);
      expect(pipe.activities.single!['state'], 'In pausa');
    });
  });

  test('connessione persa: riprova dopo 30 s e rimanda lo stato', () {
    fakeAsync((async) {
      final p = started(async);
      async.elapse(const Duration(seconds: 5));
      pipe.broken = true;
      unawaited(p.setPlaying(false));
      async.flushMicrotasks();
      expect(pipe.activities, hasLength(1));

      pipe.broken = false;
      async.elapse(const Duration(seconds: 30));
      expect(pipe.opens, 2);
      expect(pipe.activities.last!['state'], 'In pausa');
    });
  });

  test('Discord chiuso e riaperto durante la visione: l\'attività ricompare',
      () {
    fakeAsync((async) {
      final p = started(async);
      var position = const Duration(minutes: 10);
      // La timeline arriva ogni 5 s, coerente con il tempo che passa.
      void tick() {
        unawaited(p.setTimeline(
            position: position, duration: const Duration(minutes: 47)));
        async.elapse(const Duration(seconds: 5));
        position += const Duration(seconds: 5);
      }

      tick();
      tick();
      final sent = pipe.activities.length;
      expect(sent, 2);

      pipe.broken = true;
      tick();
      pipe.broken = false;
      for (var i = 0; i < 7; i++) {
        tick();
      }
      expect(pipe.opens, 2);
      expect(pipe.activities, hasLength(sent + 1));
      expect(pipe.activities.last!['timestamps'], isNotNull);
    });
  });

  test('ERROR di Discord su SET_ACTIVITY: rimanda lo stato al tick dopo', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities, hasLength(2));

      pipe.push(DiscordOpcode.frame, {
        'cmd': 'SET_ACTIVITY',
        'evt': 'ERROR',
        'data': {'code': 4000, 'message': 'child "activity" fails'},
      });
      async.elapse(const Duration(seconds: 5));
      // Stessa timeline, 5 s dopo l'ultimo invio.
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10, seconds: 10),
          duration: const Duration(minutes: 47)));
      async.flushMicrotasks();
      expect(pipe.activities, hasLength(3));
      expect(pipe.activities.last, pipe.activities[1]);

      // Nessun altro errore: niente invii in più.
      async.elapse(const Duration(seconds: 5));
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10, seconds: 15),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities, hasLength(3));
    });
  });

  test('niente da mostrare: non si collega', () {
    fakeAsync((async) {
      final p = presence();
      unawaited(p.setPlaying(true));
      unawaited(p.clear());
      async.elapse(const Duration(minutes: 1));
      expect(pipe.opens, 0);
    });
  });

  test('impostazioni: spenta cancella, senza locandina usa il logo', () {
    fakeAsync((async) {
      final p = started(async);
      settings = const DiscordSettings(showPoster: false);
      p.refresh();
      async.elapse(const Duration(seconds: 5));
      expect((pipe.activities.last!['assets'] as Map)['large_image'], 'logo');

      settings = const DiscordSettings(enabled: false);
      p.refresh();
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last, isNull);
    });
  });

  test('dispose: cancella l\'attività e chiude la pipe', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.dispose());
      async.flushMicrotasks();
      expect(pipe.activities.last, isNull);
      expect(pipe.closed, isTrue);
    });
  });
}
