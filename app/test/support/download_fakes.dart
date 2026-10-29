import 'dart:async';

import 'package:dio/dio.dart';
import 'package:wonderflix/core/downloads/download_models.dart';
import 'package:wonderflix/core/downloads/downloads_api.dart';

DownloadRelease testRelease({String guid = 'g1', int score = 120}) =>
    DownloadRelease(
      guid: guid,
      indexerId: 3,
      indexer: 'Idx',
      title: 'Film.2025.1080p',
      quality: 'WEBRip-1080p',
      resolution: 1080,
      sizeBytes: 4000000000,
      score: score,
    );

DownloadCandidate testCandidate({int rank = 1, String guid = 'g1'}) =>
    DownloadCandidate(
      rank: rank,
      release: testRelease(guid: guid),
      isChoice: rank == 1,
      wouldImport: true,
    );

DownloadSearch testSearch([String key = 'movie:1']) => DownloadSearch(
  key: key,
  kind: DownloadKind.movie,
  title: 'Film',
  runtimeMinutes: 100,
  candidates: [testCandidate()],
  validCount: 1,
  totalCount: 1,
);

/// I download automatici in memoria.
class FakeDownloadsApi implements DownloadsApi {
  var overviewValue = const DownloadsOverview(enabled: true);

  /// Chiamate in ordine: `overview`, `search movie:1`, `grab movie:1 g1 3`,
  /// `accept movie:1`.
  final calls = <String>[];

  /// Se valorizzato, [overview] aspetta e dà il suo valore.
  final overviewGates = <Completer<DownloadsOverview>>[];

  /// La risposta di [search] se non è [searchGate]; senza, [testSearch].
  DownloadSearch? searchValue;

  /// Se valorizzato, [search] aspetta; un token annullato la fa fallire.
  Completer<DownloadSearch>? searchGate;
  CancelToken? searchToken;

  /// Se valorizzato, [grab] e [accept] aspettano.
  Completer<void>? actionGate;

  /// Errore della prossima [grab] o [accept], una volta sola.
  DownloadsFailure? nextActionFailure;

  @override
  Future<DownloadsOverview> overview() async {
    calls.add('overview');
    if (overviewGates.isEmpty) return overviewValue;
    return overviewGates.removeAt(0).future;
  }

  @override
  Future<DownloadSearch> search(String key, {CancelToken? cancelToken}) async {
    calls.add('search $key');
    searchToken = cancelToken;
    final gate = searchGate;
    if (gate == null) return searchValue ?? testSearch(key);
    final done = Completer<DownloadSearch>();
    unawaited(gate.future.then(done.complete, onError: done.completeError));
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!done.isCompleted) {
          done.completeError(
            const DownloadsException(DownloadsFailure.network),
          );
        }
      }),
    );
    return done.future;
  }

  Future<void> _action(String call) async {
    calls.add(call);
    await actionGate?.future;
    final failure = nextActionFailure;
    if (failure == null) return;
    nextActionFailure = null;
    throw DownloadsException(failure);
  }

  @override
  Future<void> grab(String key, String guid, int indexerId) =>
      _action('grab $key $guid $indexerId');

  @override
  Future<void> accept(String key) => _action('accept $key');

  @override
  Future<void> searchNow(String key) => _action('searchNow $key');
}
