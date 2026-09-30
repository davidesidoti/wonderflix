import 'package:clock/clock.dart';
import 'package:wonderflix/core/syncplay/syncplay_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/watch_party/watch_party_routing.dart';

/// `SyncPlayApi` in memoria: registra le chiamate. Il server "risponde"
/// tramite [onCall], con cui i test mandano gli eventi del WebSocket.
class FakeSyncPlayApi implements SyncPlayApi {
  /// Chiamate in ordine, es. `create Mario · Dune`, `join g1`, `pause`,
  /// `seek 0:01:30.000000`, `ready`. `ping` e `utcTime` non compaiono.
  final calls = <String>[];
  final queues =
      <({List<String> itemIds, int playingIndex, Duration start})>[];
  final readyStates = <ClientPlaybackState>[];
  final bufferingStates = <ClientPlaybackState>[];
  final pings = <Duration>[];

  /// Risposta di [list].
  List<GroupInfo> groups = const [];

  /// Se valorizzato, ogni chiamata registrata lancia questo errore.
  Object? error;

  /// Orologio del server rispetto a `clock.now()`.
  Duration serverOffset = Duration.zero;

  /// Chiamato dopo aver registrato ogni chiamata.
  void Function(String call)? onCall;

  Future<void> _record(String call) async {
    calls.add(call);
    onCall?.call(call);
    final failure = error;
    if (failure != null) throw failure;
  }

  @override
  Future<void> create(String name) => _record('create $name');

  @override
  Future<void> join(String groupId) => _record('join $groupId');

  @override
  Future<void> leave() => _record('leave');

  @override
  Future<List<GroupInfo>> list() async {
    await _record('list');
    return groups;
  }

  @override
  Future<void> setNewQueue(List<String> itemIds,
      {int playingIndex = 0, Duration start = Duration.zero}) {
    queues.add((itemIds: itemIds, playingIndex: playingIndex, start: start));
    return _record('queue ${itemIds.join(',')}');
  }

  @override
  Future<void> pause() => _record('pause');

  @override
  Future<void> unpause() => _record('unpause');

  @override
  Future<void> seek(Duration position) => _record('seek $position');

  @override
  Future<void> buffering(ClientPlaybackState state) {
    bufferingStates.add(state);
    return _record('buffering');
  }

  @override
  Future<void> ready(ClientPlaybackState state) {
    readyStates.add(state);
    return _record('ready');
  }

  @override
  Future<void> ping(Duration ping) async => pings.add(ping);

  @override
  Future<UtcTime> utcTime() async {
    final now = clock.now().toUtc().add(serverOffset);
    return UtcTime(requestReceived: now, responseSent: now);
  }
}

/// Gruppo di prova: `g1`, "Mario · Dune", in pausa.
GroupInfo testGroup({
  String id = 'g1',
  String name = 'Mario · Dune',
  GroupState state = GroupState.paused,
  List<String> participants = const ['Mario'],
}) =>
    GroupInfo(
      id: id,
      name: name,
      state: state,
      participants: participants,
      lastUpdatedAt: DateTime.utc(2026, 9, 30, 10),
    );

/// Coda di prova con un solo elemento.
PlayQueue testQueue({
  String itemId = 'm1',
  String playlistItemId = 'p1',
  Duration start = Duration.zero,
  bool isPlaying = false,
  DateTime? lastUpdate,
}) =>
    PlayQueue(
      reason: 'NewPlaylist',
      lastUpdate: lastUpdate ?? DateTime.utc(2026, 9, 30, 10),
      entries: [PlayQueueEntry(itemId: itemId, playlistItemId: playlistItemId)],
      playingIndex: 0,
      startPosition: start,
      isPlaying: isPlaying,
    );

/// Navigazione in memoria: registra le aperture del player.
class FakePartyNavigator implements PartyNavigator {
  FakePartyNavigator([String location = '/home'])
      : location = Uri.parse(location);

  @override
  Uri location;

  final opened = <String>[];
  final replaced = <String>[];

  @override
  void open(String route) {
    opened.add(route);
    location = Uri.parse(route);
  }

  @override
  void replace(String route) {
    replaced.add(route);
    location = Uri.parse(route);
  }
}
