import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
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

/// La ricerca delle release di un titolo (la chiave, opaca) e le scelte
/// dell'admin (spec T §8.2). Smontando il provider la ricerca in corso viene
/// annullata.
class DownloadSearchController extends AsyncNotifier<DownloadSearch> {
  DownloadSearchController(this.key);

  final String key;
  CancelToken? _token;

  @override
  Future<DownloadSearch> build() {
    // Tiene vivo il flag finché vive la ricerca.
    ref.listen(downloadGrabbingProvider(key), (_, _) {});
    ref.listen(downloadGrabProgressProvider(key), (_, _) {});
    ref.onDispose(() => _token?.cancel());
    return _search();
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

  Future<void> searchAgain() async {
    _token?.cancel();
    state = const AsyncLoading();
    try {
      final search = await _search();
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
