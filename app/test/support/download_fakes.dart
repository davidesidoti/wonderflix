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

DownloadEpisodeChoice testEpisodeChoice(
  int number, {
  bool hasRelease = true,
  bool wouldImport = true,
  int? currentScore,
}) =>
    DownloadEpisodeChoice(
      episodeNumber: number,
      release: hasRelease ? testRelease(guid: 'e$number') : null,
      wouldImport: hasRelease && wouldImport,
      currentScore: currentScore,
    );

/// Una stagione senza un pack conveniente: la lista completa più i singoli.
DownloadSearch testSeasonSearch(
  List<DownloadEpisodeChoice> choices, [
  String key = 'season:1',
]) =>
    DownloadSearch(
      key: key,
      kind: DownloadKind.season,
      title: 'Serie S1',
      runtimeMinutes: 45,
      candidates: [testCandidate()],
      validCount: 1,
      totalCount: 1,
      episodeChoices: choices,
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

  /// Se non vuota, ogni [grab] o [accept] aspetta la prima, che toglie: per
  /// guardare cosa succede tra un grab e l'altro.
  final actionGates = <Completer<void>>[];

  /// Errore della prossima [grab] o [accept], una volta sola.
  DownloadsFailure? nextActionFailure;

  /// Se valorizzato, [overview] fallisce con questo.
  Object? overviewError;

  @override
  Future<DownloadsOverview> overview() async {
    calls.add('overview');
    if (overviewError case final e?) throw e;
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
    if (actionGates.isNotEmpty) await actionGates.removeAt(0).future;
    await actionGate?.future;
    final failure = nextActionFailure;
    if (failure == null) return;
    nextActionFailure = null;
    throw DownloadsException(failure);
  }

  @override
  Future<void> grab(String key, String guid, int indexerId,
          {bool lighten = false}) =>
      _action('grab $key $guid $indexerId${lighten ? ' lighten' : ''}');

  @override
  Future<void> accept(String key) => _action('accept $key');

  @override
  Future<void> searchNow(String key) => _action('searchNow $key');
}
