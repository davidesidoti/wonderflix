import 'device_profile.dart';
import 'item_models.dart';
import 'jellyfin_http.dart';
import 'playback_models.dart';

/// Endpoint della riproduzione (Jellyfin 10.11). Lancia solo `ApiException`.
class PlaybackApi {
  PlaybackApi(this._http);

  final JellyfinHttp _http;

  /// Come riprodurre [itemId]: sorgenti, tracce, direct play o transcodifica.
  /// - Con [allowDirect] a `false` il server propone solo la transcodifica.
  /// - Senza indici il server sceglie le tracce secondo le preferenze
  ///   dell'utente. [subtitleStreamIndex] `-1` = nessun sottotitolo.
  Future<PlaybackInfoResult> playbackInfo(
    String itemId, {
    required String userId,
    required Duration start,
    required int maxBitrate,
    required bool allowDirect,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final data = await _http.post('/Items/$itemId/PlaybackInfo', body: {
      'UserId': userId,
      'StartTimeTicks': durationToTicks(start),
      'MaxStreamingBitrate': maxBitrate,
      'DeviceProfile': buildDeviceProfile(maxBitrate: maxBitrate),
      'EnableDirectPlay': allowDirect,
      'EnableDirectStream': allowDirect,
      'EnableTranscoding': true,
      'AutoOpenLiveStream': true,
      'MediaSourceId': ?mediaSourceId,
      'AudioStreamIndex': ?audioStreamIndex,
      'SubtitleStreamIndex': ?subtitleStreamIndex,
    });
    return parseJson(data, PlaybackInfoResult.fromJson);
  }

  Future<void> reportStart(PlaybackReport report) async {
    await _http.post('/Sessions/Playing', body: report.toJson());
  }

  Future<void> reportProgress(PlaybackReport report) async {
    await _http.post('/Sessions/Playing/Progress', body: report.toJson());
  }

  Future<void> reportStopped(PlaybackReport report) async {
    await _http.post('/Sessions/Playing/Stopped', body: report.toStoppedJson());
  }

  /// Intro, riassunti, crediti… dell'elemento. Vuota se il server non ha un
  /// plugin che li riconosce.
  Future<List<MediaSegment>> mediaSegments(String itemId) async => parseJson(
        await _http.get('/MediaSegments/$itemId'),
        (json) => (json['Items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSegment.fromJson)
            .toList(),
      );

  /// Dati utente aggiornati di un elemento (minutaggio, visto).
  Future<UserItemData> userData(String userId, String itemId) async =>
      parseJson(
          await _http
              .get('/UserItems/$itemId/UserData', query: {'userId': userId}),
          UserItemData.fromJson);
}
