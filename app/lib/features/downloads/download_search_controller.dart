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
  Future<DownloadsFailure?> grab(DownloadCandidate candidate) => _act(
    () => ref
        .read(downloadsApiProvider)
        .grab(key, candidate.release.guid, candidate.release.indexerId),
  );

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
