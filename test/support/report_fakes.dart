import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';
import 'package:wonderflix/core/reports/report_models.dart';
import 'package:wonderflix/core/reports/reports_api.dart';
import 'package:wonderflix/core/subtitles/subtitle_models.dart';
import 'package:wonderflix/core/subtitles/subtitles_api.dart';
import 'package:wonderflix/features/reports/reports_providers.dart';

/// Le segnalazioni del plugin in memoria.
class FakeReportsApi implements ReportsApi {
  /// Le segnalazioni aperte: risposta di [all] e, filtrate per titolo, di
  /// [mine] (a meno di una voce in [mineById]). [create] ne aggiunge una.
  final reports = <ItemReport>[];

  /// Risposta di [mine] per titolo, al posto del filtro su [reports].
  final mineById = <String, List<ItemReport>>{};

  /// Chiamate in ordine: `create e1 Subtitles nota`, `mine e1`, `all`,
  /// `resolve r1 Fixed nota`.
  final calls = <String>[];

  /// Errore della prossima chiamata, una volta sola.
  ReportsFailure? nextFailure;

  /// Se valorizzato, ogni chiamata aspetta che si completi (dopo averla
  /// registrata).
  Completer<void>? gate;

  Future<void> _enter(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    throw ReportsException(failure);
  }

  @override
  Future<ItemReport> create(
      {required String itemId, required ReportType type, String? note}) async {
    await _enter('create $itemId ${type.wire} ${note ?? '-'}');
    final report = testReport(
        id: 'r${reports.length + 1}', itemId: itemId, type: type, note: note);
    reports.add(report);
    return report;
  }

  @override
  Future<List<ItemReport>> mine(String itemId) async {
    await _enter('mine $itemId');
    return mineById[itemId] ??
        [
          for (final report in reports)
            if (report.itemId == itemId) report,
        ];
  }

  @override
  Future<List<ItemReport>> all() async {
    await _enter('all');
    return List.of(reports);
  }

  @override
  Future<void> resolve(String reportId, ReportOutcome outcome,
      {String? note}) async {
    await _enter('resolve $reportId ${outcome.wire} ${note ?? '-'}');
    reports.removeWhere((report) => report.id == reportId);
  }
}

/// I sottotitoli del plugin e di Jellyfin in memoria.
class FakeSubtitlesApi implements SubtitlesApi {
  /// Risposta di [search].
  final results = <RemoteSubtitle>[];

  /// Chiamate in ordine: `search e1 ita true`, `download e1 s1`,
  /// `upload e1 ita srt`, `delete e1 3`.
  final calls = <String>[];

  /// Errore della prossima chiamata, una volta sola.
  SubtitlesFailure? nextFailure;

  /// Se valorizzato, ogni chiamata aspetta che si completi (dopo averla
  /// registrata).
  Completer<void>? gate;

  Future<void> _enter(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    throw SubtitlesException(failure);
  }

  @override
  Future<List<RemoteSubtitle>> search(String itemId, String language,
      {bool? perfectMatch}) async {
    await _enter('search $itemId $language ${perfectMatch ?? '-'}');
    return List.of(results);
  }

  @override
  Future<void> download(String itemId, String subtitleId) =>
      _enter('download $itemId $subtitleId');

  @override
  Future<void> upload(String itemId, SubtitleUpload upload) =>
      _enter('upload $itemId ${upload.language} ${upload.format}');

  @override
  Future<void> delete(String itemId, int streamIndex) =>
      _enter('delete $itemId $streamIndex');
}

/// Una segnalazione di un episodio, con i valori di prova.
ItemReport testReport({
  String id = 'r1',
  ReportType type = ReportType.subtitles,
  String? note,
  String userId = 'u2',
  String userName = 'Luigi',
  String itemId = 'e1',
  ReportItemType? itemType = ReportItemType.episode,
  String itemName = 'Pilot',
  String titleId = 's1',
  String titleName = 'Dark',
  int? seasonNumber = 1,
  int? episodeNumber = 2,
  DateTime? createdAt,
}) {
  final at = createdAt ?? DateTime.utc(2026, 10, 21, 10);
  return ItemReport(
    id: id,
    type: type,
    note: note,
    createdAt: at,
    updatedAt: at,
    userId: userId,
    userName: userName,
    itemId: itemId,
    itemType: itemType,
    itemName: itemName,
    titleId: titleId,
    titleName: titleName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
}

RemoteSubtitle testSubtitle({
  String id = 'sub1',
  String providerName = 'OpenSubtitles',
  String name = 'Dark.S01E02.it',
  String language = 'ita',
  String format = 'srt',
  double? communityRating,
  int? downloadCount,
  bool isHashMatch = false,
  bool hearingImpaired = false,
  bool forced = false,
  bool machineTranslated = false,
}) =>
    RemoteSubtitle(
      id: id,
      providerName: providerName,
      name: name,
      language: language,
      format: format,
      communityRating: communityRating,
      downloadCount: downloadCount,
      isHashMatch: isHashMatch,
      hearingImpaired: hearingImpaired,
      forced: forced,
      machineTranslated: machineTranslated,
    );

/// Un file con una versione, una traccia video, una audio e le tracce
/// [subtitles].
ItemMediaInfo testMediaInfo({List<SubtitleTrack> subtitles = const []}) =>
    ItemMediaInfo(versions: [
      MediaVersion(
        id: 'v1',
        name: 'Dark 1080p',
        container: 'mkv',
        fileName: 'Dark.S01E02.mkv',
        size: 1500000000,
        bitrate: 6000000,
        duration: const Duration(minutes: 52),
        video: const VideoTrack(
            codec: 'h264', range: 'SDR', width: 1920, height: 1080, fps: 24),
        audio: const [
          AudioTrack(
              index: 1,
              language: 'ita',
              codec: 'ac3',
              title: 'Italiano',
              channels: 6,
              isDefault: true),
        ],
        subtitles: subtitles,
      ),
    ]);

/// Gli override per i test di segnalazioni e sottotitoli.
List<Override> reportTestOverrides(
        {FakeReportsApi? reports, FakeSubtitlesApi? subtitles}) =>
    [
      reportsApiProvider.overrideWithValue(reports ?? FakeReportsApi()),
      subtitlesApiProvider.overrideWithValue(subtitles ?? FakeSubtitlesApi()),
    ];
