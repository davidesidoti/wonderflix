import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../social/social_providers.dart';
import 'downloads_controller.dart';
import 'downloads_providers.dart';

/// Vero mentre `grab` o `accept` di un titolo (la chiave) aspettano la
/// risposta: la pagina disabilita i pulsanti.
class DownloadGrabbing extends Notifier<bool> {
  DownloadGrabbing(this.key);

  final String key;

  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final downloadGrabbingProvider = NotifierProvider.autoDispose
    .family<DownloadGrabbing, bool, String>(DownloadGrabbing.new);

/// L'avanzamento di "Scarica tutti" di un titolo: (grab in corso, totale), o
/// null quando nessun "Scarica tutti" è in corso.
class DownloadGrabProgress extends Notifier<(int, int)?> {
  DownloadGrabProgress(this.key);

  final String key;

  @override
  (int, int)? build() => null;

  void set((int, int)? value) => state = value;
}

final downloadGrabProgressProvider = NotifierProvider.autoDispose
    .family<DownloadGrabProgress, (int, int)?, String>(
      DownloadGrabProgress.new,
    );

/// Una ricerca in background in corso: quando è partita (ora del server), su
/// quale servizio, e se l'ultima richiesta dello stato è fallita per la rete.
typedef DownloadSearchRunning = ({
  DateTime startedAt,
  String service,
  bool reconnecting,
});

/// La ricerca in background di un titolo (la chiave) mentre è in corso; null
/// altrimenti (spec W §5.2).
class DownloadSearchRunningNotifier extends Notifier<DownloadSearchRunning?> {
  DownloadSearchRunningNotifier(this.key);

  final String key;

  @override
  DownloadSearchRunning? build() => null;

  void set(DownloadSearchRunning? value) => state = value;
}

final downloadSearchRunningProvider = NotifierProvider.autoDispose
    .family<DownloadSearchRunningNotifier, DownloadSearchRunning?, String>(
      DownloadSearchRunningNotifier.new,
    );

/// La ricerca delle release di un titolo (la chiave, opaca) e le scelte
/// dell'admin (spec T §8.2). Smontando il provider la ricerca in corso viene
/// annullata. Con `downloadsSearchJobs` la ricerca gira sul plugin e il
/// controller ne chiede lo stato (spec W §5.2): smontando si ferma solo il
/// polling.
class DownloadSearchController extends AsyncNotifier<DownloadSearch> {
  DownloadSearchController(this.key);

  static const pollInterval = Duration(seconds: 3);

  /// Errori di rete di fila durante il polling prima di mostrare l'errore.
  static const maxPollFailures = 3;

  final String key;
  CancelToken? _token;
  Timer? _timer;

  /// Cresce a ogni ricerca: un polling vecchio vede che non è più il suo.
  var _run = 0;

  @override
  Future<DownloadSearch> build() {
    // Tiene vivo il flag finché vive la ricerca.
    ref.listen(downloadGrabbingProvider(key), (_, _) {});
    ref.listen(downloadGrabProgressProvider(key), (_, _) {});
    ref.listen(downloadSearchRunningProvider(key), (_, _) {});
    ref.onDispose(() {
      _token?.cancel();
      _timer?.cancel();
    });
    return _jobs ? _job() : _search();
  }

  bool get _jobs => ref.read(socialAvailabilityProvider).downloadsSearchJobs;

  /// Avvia (o riprende) la ricerca sul plugin e ne chiede lo stato finché non
  /// è finita.
  Future<DownloadSearch> _job({bool again = false}) async {
    final run = ++_run;
    _timer?.cancel();
    final api = ref.read(downloadsApiProvider);
    final running = ref.read(downloadSearchRunningProvider(key).notifier);
    // Provider smontato o ricerca nuova: la risposta non serve a nessuno.
    final stale = Completer<DownloadSearch>().future;
    var failures = 0;
    try {
      var status = await api.startSearch(key, again: again);
      while (true) {
        if (!ref.mounted || run != _run) return await stale;
        switch (status.state) {
          case DownloadSearchJobState.done:
            return status.result!;
          case DownloadSearchJobState.missing:
            throw const DownloadsException(DownloadsFailure.invalid);
          case DownloadSearchJobState.running:
            running.set((
              startedAt: status.startedAt ?? DateTime.now(),
              service: status.service,
              reconnecting: false,
            ));
          case DownloadSearchJobState.none:
            break;
        }
        // None: il plugin è stato riavviato e non ha più il lavoro.
        final restart = status.state == DownloadSearchJobState.none;
        while (true) {
          final tick = Completer<void>();
          _timer = Timer(pollInterval, tick.complete);
          await tick.future;
          if (!ref.mounted || run != _run) return await stale;
          try {
            status = restart
                ? await api.startSearch(key)
                : await api.searchStatus(key);
            failures = 0;
            break;
          } on DownloadsException catch (error) {
            if (!ref.mounted || run != _run) return await stale;
            if (error.failure != DownloadsFailure.network ||
                ++failures >= maxPollFailures) {
              rethrow;
            }
            if (ref.read(downloadSearchRunningProvider(key)) case final r?) {
              running.set((
                startedAt: r.startedAt,
                service: r.service,
                reconnecting: true,
              ));
            }
          }
        }
      }
    } finally {
      if (ref.mounted && run == _run) running.set(null);
    }
  }

  Future<DownloadSearch> _search() async {
    final token = _token = CancelToken();
    try {
      return await ref
          .read(downloadsApiProvider)
          .search(key, cancelToken: token);
    } on DownloadsException {
      // Annullata (provider smontato o nuova ricerca): non è un errore da
      // mostrare, e la risposta non serve a nessuno.
      if (token.isCancelled) return Completer<DownloadSearch>().future;
      rethrow;
    }
  }

  bool get grabbing => ref.read(downloadGrabbingProvider(key));

  /// Rilancia la ricerca (sul plugin: `again`, anche se ha già un risultato).
  Future<void> searchAgain() => _restart(again: true);

  /// Dopo un errore: riprende a chiedere lo stato senza rilanciare la ricerca
  /// sul plugin.
  Future<void> retry() => _restart(again: false);

  Future<void> _restart({required bool again}) async {
    _token?.cancel();
    state = const AsyncLoading();
    try {
      final search = await (_jobs ? _job(again: again) : _search());
      if (ref.mounted) state = AsyncData(search);
    } on Object catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    }
  }

  /// Scarica [candidate]. Dà l'errore, o null se è andata: in caso d'errore la
  /// ricerca resta a schermo.
  Future<DownloadsFailure?> grab(
    DownloadCandidate candidate, {
    bool lighten = false,
  }) => grabRelease(candidate.release, lighten: lighten);

  /// Come [grab], per una release che non è un candidato (il singolo di un
  /// episodio, spec T §8.2).
  Future<DownloadsFailure?> grabRelease(
    DownloadRelease release, {
    bool lighten = false,
  }) => _act(
    () => ref
        .read(downloadsApiProvider)
        .grab(key, release.guid, release.indexerId, lighten: lighten),
  );

  /// Scarica [releases] una dopo l'altra (il plugin le segue come voci degli
  /// episodi, ruling 13). `grabbing` resta vero per tutta la serie; un
  /// fallimento non ferma le altre; si ferma se il provider viene smontato
  /// (pagina chiusa). La panoramica si ricarica una volta sola, alla fine.
  /// Gli episodi partiti escono dalla ricerca a schermo: riprovando non si
  /// scaricano due volte.
  Future<({int started, int failed, DownloadsFailure? firstFailure})> grabAll(
    List<DownloadRelease> releases, {
    bool lighten = false,
  }) async {
    final api = ref.read(downloadsApiProvider);
    final flag = ref.read(downloadGrabbingProvider(key).notifier)..set(true);
    final progress = ref.read(downloadGrabProgressProvider(key).notifier);
    var started = 0;
    var failed = 0;
    final startedGuids = <String>{};
    DownloadsFailure? firstFailure;
    try {
      for (final (i, release) in releases.indexed) {
        if (!ref.mounted) break;
        progress.set((i + 1, releases.length));
        try {
          await api.grab(key, release.guid, release.indexerId, lighten: lighten);
          started++;
          startedGuids.add(release.guid);
        } on DownloadsException catch (error) {
          failed++;
          firstFailure ??= error.failure;
        }
      }
      if (started > 0 && ref.mounted) {
        ref.invalidate(downloadsControllerProvider);
        if (state.value case final search?) {
          state = AsyncData(search.withEpisodeChoices([
            for (final c in search.episodeChoices)
              if (!startedGuids.contains(c.release?.guid)) c,
          ]));
        }
      }
    } finally {
      if (ref.mounted) {
        flag.set(false);
        progress.set(null);
      }
    }
    return (started: started, failed: failed, firstFailure: firstFailure);
  }

  /// "Tieni il file attuale": accetta com'è.
  Future<DownloadsFailure?> accept() =>
      _act(() => ref.read(downloadsApiProvider).accept(key));

  Future<DownloadsFailure?> _act(Future<void> Function() call) async {
    final flag = ref.read(downloadGrabbingProvider(key).notifier)..set(true);
    try {
      await call();
      if (ref.mounted) ref.invalidate(downloadsControllerProvider);
      return null;
    } on DownloadsException catch (error) {
      return error.failure;
    } finally {
      if (ref.mounted) flag.set(false);
    }
  }
}

final downloadSearchControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DownloadSearchController, DownloadSearch, String>(
      DownloadSearchController.new,
    );
