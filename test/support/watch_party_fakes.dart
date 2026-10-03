import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_routing.dart';

import 'test_data.dart';

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

  /// Risposta di [group] (`null` = gruppo non trovato).
  GroupInfo? groupInfo;

  /// Id chiesti a [group] (non compaiono in [calls]).
  final groupRequests = <String>[];

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

  /// Lancia [error], se valorizzato.
  @override
  Future<GroupInfo?> group(String groupId) async {
    groupRequests.add(groupId);
    final failure = error;
    if (failure != null) throw failure;
    return groupInfo;
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
  Future<void> nextItem(String playlistItemId) =>
      _record('next $playlistItemId');

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
  Future<void> setIgnoreWait(bool ignore) => _record('ignore-wait $ignore');

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

/// Coda di una serie: episodi [itemIds] con id nella coda `p1`, `p2`, …;
/// in riproduzione quello di indice [playingIndex].
PlayQueue testSeriesQueue({
  List<String> itemIds = const ['e4', 'e5', 'e6'],
  int playingIndex = 0,
  String reason = 'NewPlaylist',
  DateTime? lastUpdate,
}) =>
    PlayQueue(
      reason: reason,
      lastUpdate: lastUpdate ?? DateTime.utc(2026, 9, 30, 10),
      entries: [
        for (var i = 0; i < itemIds.length; i++)
          PlayQueueEntry(itemId: itemIds[i], playlistItemId: 'p${i + 1}'),
      ],
      playingIndex: playingIndex,
      startPosition: Duration.zero,
      isPlaying: false,
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

extension GroupInfoWithMode on GroupInfo {
  /// Lo stesso gruppo con la modalità del plugin (solo per i test).
  GroupInfo copyWithMode(PartyMode mode) => GroupInfo(
        id: id,
        name: name,
        state: state,
        participants: participants,
        lastUpdatedAt: lastUpdatedAt,
        mode: mode,
      );
}

/// Elenco dei gruppi fisso, senza richieste né timer.
class FakeWatchPartyDirectory extends WatchPartyDirectory {
  FakeWatchPartyDirectory([this.initial = const []]);

  final List<GroupInfo> initial;
  int refreshCalls = 0;

  @override
  List<GroupInfo> build() => initial;

  @override
  Future<void> refresh() async => refreshCalls++;

  /// Simula una nuova lettura dell'elenco. Come una risposta del server è
  /// sempre una lista nuova: anche `const []` due volte avvisa chi ascolta.
  void set(List<GroupInfo> groups) => state = [...groups];
}

/// Avvisi fissi: registra quelli mostrati e le azioni proprie, senza timer.
class FakePartyNotices extends PartyNotices {
  FakePartyNotices([this.initial]);

  final PartyNotice? initial;
  final shown = <PartyNotice>[];
  final mineCalls = <(PartyNoticeKind, Duration?)>[];

  /// Azioni registrate con `show: false` (solo l'eco, nessun avviso).
  final hiddenMineCalls = <PartyNoticeKind>[];

  /// Chiamate di `setAttribution`, in ordine.
  final attributionCalls = <bool>[];

  /// Annunci passati ad `attribute`.
  final attributed = <PartyActionEvent>[];

  @override
  void setAttribution(bool enabled) => attributionCalls.add(enabled);

  @override
  void attribute(PartyActionEvent event) => attributed.add(event);

  @override
  PartyNotice? build() => initial;

  @override
  void show(PartyNotice notice) => shown.add(notice);

  @override
  void mine(PartyNoticeKind kind, {Duration? position, bool show = true}) {
    mineCalls.add((kind, position));
    if (!show) hiddenMineCalls.add(kind);
  }
}

/// Invito fisso: registra le chiusure, senza timer.
class FakeWatchPartyInvites extends WatchPartyInvites {
  FakeWatchPartyInvites([this.initial]);

  final GroupInfo? initial;
  int dismissed = 0;

  @override
  WatchPartyInvite? build() {
    final group = initial;
    return group == null ? null : WatchPartyInvite(group);
  }

  @override
  void dismiss() {
    dismissed++;
    state = null;
  }

  /// Un invito arriva (come un gruppo nuovo nell'elenco, o di un amico).
  void show(GroupInfo group, {String? invitedBy}) =>
      state = WatchPartyInvite(group, invitedBy: invitedBy);
}

/// `PartyChannelApi` in memoria. Di default il plugin è assente: `info`
/// lancia `unavailable`, come un server senza plugin, e i test che non
/// parlano del canale restano come prima.
class FakePartyChannelApi implements PartyChannelApi {
  /// Risposta di [info]; `null` = plugin assente (404).
  PartyPluginInfo? pluginInfo;

  /// Storico restituito da [join].
  List<PartyChatEvent> history = const [];

  /// Errore di [join], se valorizzato.
  PartyChannelFailure? joinFailure;

  /// Se valorizzato, [join] aspetta che si completi.
  Completer<void>? joinGate;

  /// Errori delle prossime [send], uno per chiamata.
  final sendFailures = <PartyChannelFailure>[];

  /// Se valorizzato, [send] aspetta che si completi.
  Completer<void>? sendGate;

  /// Chiamate in ordine: `info`, `join g1`, `leave g1`, `send g1 Chat`.
  final calls = <String>[];

  /// Eventi passati a [send], anche quelli falliti.
  final sent = <PartyOutgoing>[];

  int _ids = 0;

  /// Plugin presente, con il nostro protocollo.
  void install({String version = '1.0.0'}) => pluginInfo =
      PartyPluginInfo(version: version, protocol: partyChannelProtocol);

  @override
  Future<PartyPluginInfo> info() async {
    calls.add('info');
    final info = pluginInfo;
    if (info == null) {
      throw const PartyChannelException(PartyChannelFailure.unavailable);
    }
    return info;
  }

  @override
  Future<List<PartyChatEvent>> join(String groupId) async {
    calls.add('join $groupId');
    await joinGate?.future;
    final failure = joinFailure;
    if (failure != null) throw PartyChannelException(failure);
    return history;
  }

  @override
  Future<void> leave(String groupId) async => calls.add('leave $groupId');

  /// Timbra l'evento come il plugin, con [testUser] e id `srv-1`, `srv-2`, …
  @override
  Future<PartyEvent> send(String groupId, PartyOutgoing event) async {
    final json = event.toJson();
    calls.add('send $groupId ${json['Type']}');
    sent.add(event);
    await sendGate?.future;
    if (sendFailures.isNotEmpty) {
      throw PartyChannelException(sendFailures.removeAt(0));
    }
    return parsePartyEvent(jsonDecode(partyPayload(json,
        id: 'srv-${++_ids}',
        groupId: groupId,
        userId: testUser.id,
        userName: testUser.name,
        sentAt: clock.now().toUtc())))!;
  }
}

/// Evento timbrato di prova come lo inoltra il plugin (stringa JSON):
/// [fields] sopra i campi comuni.
String partyPayload(
  Map<String, dynamic> fields, {
  String id = 'e1',
  String groupId = 'g1',
  String userId = 'u2',
  String userName = 'Luigi',
  DateTime? sentAt,
}) =>
    jsonEncode({
      'Protocol': partyChannelProtocol,
      'Id': id,
      'GroupId': groupId,
      'UserId': userId,
      'UserName': userName,
      'SentAt': (sentAt ?? DateTime.utc(2026, 10, 2, 21)).toIso8601String(),
      ...fields,
    });

PartyChatEvent testChatEvent(
  String text, {
  String id = 'e1',
  String userId = 'u2',
  String userName = 'Luigi',
  DateTime? sentAt,
}) =>
    parsePartyEvent(partyPayload({'Type': 'Chat', 'Text': text},
        id: id, userId: userId, userName: userName, sentAt: sentAt))!
        as PartyChatEvent;

PartyActionEvent testActionEvent(
  PartyAction action, {
  String id = 'e1',
  String userName = 'Luigi',
  Duration? position,
}) =>
    parsePartyEvent(partyPayload({
      'Type': 'Action',
      'Action': action.wire,
      if (position != null) 'PositionTicks': durationToTicks(position),
    }, id: id, userName: userName))! as PartyActionEvent;
