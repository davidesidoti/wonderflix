import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/item_models.dart';
import '../jellyfin/jellyfin_http.dart';
import 'syncplay_models.dart';

final _log = Logger('watchparty');

/// I due istanti di `/GetUtcTime` (orario del server).
class UtcTime {
  const UtcTime({required this.requestReceived, required this.responseSent});

  final DateTime requestReceived;
  final DateTime responseSent;
}

/// Stato del nostro player da riferire al gruppo (`Buffering` e `Ready`).
class ClientPlaybackState {
  const ClientPlaybackState({
    required this.when,
    required this.position,
    required this.isPlaying,
    required this.playlistItemId,
  });

  /// Orario del server a cui si riferisce [position].
  final DateTime when;
  final Duration position;
  final bool isPlaying;
  final String playlistItemId;

  Map<String, dynamic> toJson() => {
        'When': when.toUtc().toIso8601String(),
        'PositionTicks': durationToTicks(position),
        'IsPlaying': isPlaying,
        'PlaylistItemId': playlistItemId,
      };
}

/// Endpoint SyncPlay di Jellyfin 10.11. Lancia solo `ApiException`. Le
/// conferme arrivano dal WebSocket (`SyncPlayGroupUpdate`).
class SyncPlayApi {
  SyncPlayApi(this._http);

  final JellyfinHttp _http;

  /// Crea un gruppo e ci entra.
  Future<void> create(String name) =>
      _post('/SyncPlay/New', {'GroupName': name});

  Future<void> join(String groupId) =>
      _post('/SyncPlay/Join', {'GroupId': groupId});

  Future<void> leave() => _post('/SyncPlay/Leave');

  /// Gruppi di cui l'utente può vedere la coda.
  Future<List<GroupInfo>> list() async {
    final data = await _http.get('/SyncPlay/List');
    if (data is! List) throw const ServerErrorException(null);
    final groups = <GroupInfo>[];
    for (final json in data.whereType<Map<String, dynamic>>()) {
      try {
        groups.add(GroupInfo.fromJson(json));
      } on Object catch (error) {
        _log.warning('gruppo non valido: $error');
      }
    }
    return groups;
  }

  /// Nuova coda del gruppo: si parte da [itemIds][[playingIndex]] a [start].
  Future<void> setNewQueue(List<String> itemIds,
          {int playingIndex = 0, Duration start = Duration.zero}) =>
      _post('/SyncPlay/SetNewQueue', {
        'PlayingQueue': itemIds,
        'PlayingItemPosition': playingIndex,
        'StartPositionTicks': durationToTicks(start),
      });

  Future<void> pause() => _post('/SyncPlay/Pause');

  /// Riprende; con il gruppo in attesa riparte senza aspettare gli altri.
  Future<void> unpause() => _post('/SyncPlay/Unpause');

  Future<void> seek(Duration position) =>
      _post('/SyncPlay/Seek', {'PositionTicks': durationToTicks(position)});

  /// Passa all'elemento successivo della coda. [playlistItemId] è quello in
  /// riproduzione: il server ignora le richieste doppie degli altri membri.
  Future<void> nextItem(String playlistItemId) =>
      _post('/SyncPlay/NextItem', {'PlaylistItemId': playlistItemId});

  Future<void> buffering(ClientPlaybackState state) =>
      _post('/SyncPlay/Buffering', state.toJson());

  Future<void> ready(ClientPlaybackState state) =>
      _post('/SyncPlay/Ready', state.toJson());

  /// Ping verso il server, che lo usa per calcolare i ritardi dei comandi.
  Future<void> ping(Duration ping) =>
      _post('/SyncPlay/Ping', {'Ping': ping.inMilliseconds});

  Future<UtcTime> utcTime() async {
    final json = asJsonMap(await _http.get('/GetUtcTime'));
    final received = DateTime.tryParse(
        json['RequestReceptionTime'] as String? ?? '');
    final sent = DateTime.tryParse(
        json['ResponseTransmissionTime'] as String? ?? '');
    if (received == null || sent == null) {
      throw const ServerErrorException(null);
    }
    return UtcTime(requestReceived: received.toUtc(), responseSent: sent.toUtc());
  }

  Future<void> _post(String path, [Map<String, dynamic>? body]) async {
    await _http.post(path, body: body);
  }
}
