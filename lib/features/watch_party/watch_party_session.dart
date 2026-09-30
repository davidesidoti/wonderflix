import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/syncplay/server_clock.dart';
import '../../core/syncplay/start_lag.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import 'watch_party_providers.dart';

final _log = Logger('watchparty');

enum WatchPartyPhase { none, joining, inGroup }

enum WatchPartyFailure { groupGone, accessDenied, timeout, network }

class WatchPartyException implements Exception {
  const WatchPartyException(this.failure);

  final WatchPartyFailure failure;

  @override
  String toString() => 'WatchPartyException(${failure.name})';
}

class WatchPartyState {
  const WatchPartyState({
    this.phase = WatchPartyPhase.none,
    this.group,
    this.groupState = GroupState.idle,
    this.queue,
    this.rejoins = 0,
  });

  final WatchPartyPhase phase;
  final GroupInfo? group;
  final GroupState groupState;
  final PlayQueue? queue;

  /// Rientri nel gruppo dopo una caduta del WebSocket: a ogni rientro il
  /// player rimanda `Ready`.
  final int rejoins;

  bool get inGroup => phase == WatchPartyPhase.inGroup;

  /// Membri senza ripetizioni: lo stesso utente può avere più sessioni.
  List<String> get members => {...?group?.participants}.toList();

  /// Elemento dopo quello in riproduzione; `null` a fine coda.
  PlayQueueEntry? get nextEntry {
    final queue = this.queue;
    if (queue == null || queue.playingIndex < 0) return null;
    final index = queue.playingIndex + 1;
    return index < queue.entries.length ? queue.entries[index] : null;
  }

  bool get hasNext => nextEntry != null;

  WatchPartyState copyWith(
          {GroupInfo? group,
          GroupState? groupState,
          PlayQueue? queue,
          int? rejoins}) =>
      WatchPartyState(
        phase: phase,
        group: group ?? this.group,
        groupState: groupState ?? this.groupState,
        queue: queue ?? this.queue,
        rejoins: rejoins ?? this.rejoins,
      );
}

/// Titolo nel nome del gruppo: l'elenco dei gruppi del server non dice cosa
/// si sta guardando. Per un episodio vale il nome della serie.
String partyTitle(JellyfinItem item) => item.seriesName ?? item.name;

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Il watch party dell'utente (spec B §5): creare, entrare, uscire, stato
/// del gruppo, coda, comandi e orologio del server. Non conosce il player.
class WatchPartySession extends Notifier<WatchPartyState> {
  static const joinTimeout = Duration(seconds: 10);

  /// Intervallo minimo tra due uscite da un gruppo fantasma.
  static const ghostLeaveInterval = Duration(seconds: 30);

  /// Attesa massima dei membri riletti dal server dopo un'entrata o
  /// un'uscita.
  static const membersTimeout = Duration(seconds: 3);

  late SyncPlayApi _api;

  // Creati una volta sola, non in `build`: chi si iscrive (gli avvisi) lo fa
  // una volta e resta iscritto anche se la sessione si ricostruisce (con
  // Riverpod 3 il notifier resta lo stesso, ma `onDispose` scatta anche a
  // ogni ricostruzione, quindi non si chiudono lì). Non si chiudono mai:
  // senza iscritti, con il notifier, li raccoglie il garbage collector.
  final _commands = StreamController<SyncPlayCommand>.broadcast();
  final _updates = StreamController<GroupUpdate>.broadcast();
  ServerClock? _clock;
  StartLag? _startLag;
  SyncPlayCommand? _lastCommand;
  Completer<void>? _joining;
  DateTime? _joinedAt;
  DateTime? _ghostLeftAt;

  /// Gruppo in cui stiamo rientrando dopo una riconnessione.
  String? _rejoining;

  /// Cambia a ogni ingresso e uscita: una rilettura dei membri partita in
  /// un gruppo precedente non vale più.
  int _generation = 0;

  /// Ultima rilettura dei membri chiesta: solo quella aggiorna lo stato.
  int _membersRequest = 0;

  @override
  WatchPartyState build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _api = ref.watch(syncPlayApiProvider);
    _clock = null;
    _startLag = null;
    _lastCommand = null;
    _joining = null;
    _joinedAt = null;
    _ghostLeftAt = null;
    _rejoining = null;
    _generation++;
    ref.onDispose(_stopClock);
    if (userId == null) return const WatchPartyState();
    final subscription = ref.watch(watchPartyEventsProvider).listen(_onEvent);
    ref.onDispose(() => unawaited(subscription.cancel()));
    return const WatchPartyState();
  }

  SyncPlayApi get api => _api;

  /// Orologio del server; `null` fuori da un gruppo.
  ServerClock? get serverClock => _clock;

  /// Ritardo con cui il player riparte dopo una ripresa programmata, per
  /// tutto il watch party (ogni episodio ha un player nuovo); `null` fuori
  /// da un gruppo.
  StartLag? get startLag => _startLag;

  /// Comandi del gruppo, già filtrati (solo il nostro gruppo, nessuno più
  /// vecchio dell'ingresso).
  Stream<SyncPlayCommand> get commands => _commands.stream;

  SyncPlayCommand? get lastCommand => _lastCommand;

  /// Aggiornamenti del nostro gruppo (entrate, uscite, stato, coda), già
  /// applicati allo stato. Servono agli avvisi. Entrate e uscite arrivano
  /// dopo aver riletto i membri, e solo se cambiano i nomi dei membri (vedi
  /// [_refreshMembers]).
  Stream<GroupUpdate> get updates => _updates.stream;

  /// Crea un gruppo per [item] con la coda [queue] (di default solo [item])
  /// e ci fa partire la riproduzione da [start]. Lancia [WatchPartyException].
  Future<void> create(JellyfinItem item,
      {List<String>? queue, Duration start = Duration.zero}) async {
    if (state.phase == WatchPartyPhase.joining) return;
    final session = ref.read(sessionControllerProvider);
    final userName = session is SessionSignedIn ? session.user.name : '';
    await _enter(() => _api.create('$userName · ${partyTitle(item)}'));
    try {
      await _api.setNewQueue(queue ?? [item.id], start: start);
    } on ApiException catch (error) {
      _log.warning('coda del watch party non impostata: $error');
      await leave();
      throw const WatchPartyException(WatchPartyFailure.network);
    }
  }

  /// Nuova coda per il gruppo in cui siamo ("Guarda insieme" dentro un
  /// gruppo): cambia il titolo per tutti. Fuori da un gruppo non fa nulla.
  /// Lancia [WatchPartyException].
  Future<void> setQueue(List<String> queue,
      {Duration start = Duration.zero}) async {
    if (!state.inGroup) return;
    try {
      await _api.setNewQueue(queue, start: start);
    } on ApiException catch (error) {
      _log.warning('nuova coda del watch party non impostata: $error');
      throw const WatchPartyException(WatchPartyFailure.network);
    }
  }

  /// Il gruppo passa all'elemento successivo della coda (pulsante, tasto N,
  /// fine del video), se è ancora in riproduzione [fromPlaylistItemId]
  /// (quello del player che lo chiede). `false` se il gruppo è già altrove
  /// o non c'è un elemento dopo.
  Future<bool> nextItem(String fromPlaylistItemId) async {
    final playing = state.queue?.playing;
    if (!state.inGroup ||
        playing == null ||
        playing.playlistItemId != fromPlaylistItemId ||
        !state.hasNext) {
      return false;
    }
    try {
      await _api.nextItem(playing.playlistItemId);
    } on Object catch (error) {
      _log.warning('episodio successivo non chiesto: $error');
    }
    return true;
  }

  /// Lancia [WatchPartyException].
  Future<void> join(String groupId) async {
    if (state.phase == WatchPartyPhase.joining) return;
    await _enter(() => _api.join(groupId));
  }

  /// Esce dal gruppo. Se la richiesta non arriva al server, la sessione
  /// scade da sola.
  Future<void> leave() async {
    if (state.phase == WatchPartyPhase.none) return;
    _reset();
    try {
      await _api.leave();
    } on Object catch (error) {
      _log.info('uscita dal watch party non inviata: $error');
    }
  }

  /// Posizione da cui aprire l'elemento in riproduzione nel gruppo. Se è
  /// lontana più di 500 ms il server la corregge con un `Seek`.
  Duration estimatedPosition() {
    final queue = state.queue;
    final playing = queue?.playing;
    if (queue == null || playing == null) return Duration.zero;
    final command = _lastCommand;
    if (command != null && command.playlistItemId == playing.playlistItemId) {
      if (command.type != SyncPlayCommandType.unpause) return command.position;
      final now = _clock?.serverNow() ?? clock.now().toUtc();
      final elapsed = now.difference(command.when);
      return elapsed.isNegative ? command.position : command.position + elapsed;
    }
    return queue.startPosition;
  }

  Future<void> _enter(Future<void> Function() request) async {
    if (state.inGroup) await leave();
    final joining = _joining = Completer<void>();
    // L'esito può arrivare dal WebSocket prima che la richiesta HTTP finisca.
    joining.future.ignore();
    state = const WatchPartyState(phase: WatchPartyPhase.joining);
    try {
      await request();
      await joining.future.timeout(joinTimeout,
          onTimeout: () =>
              throw const WatchPartyException(WatchPartyFailure.timeout));
    } on WatchPartyException catch (error) {
      _log.warning('ingresso nel watch party non riuscito: $error');
      if (!state.inGroup) {
        _reset();
        // Il server può averci messo nel gruppo senza che la conferma sia
        // arrivata: si esce, per non restare in un gruppo fantasma.
        if (error.failure == WatchPartyFailure.timeout) _leaveQuietly();
      }
      rethrow;
    } on ApiException catch (error) {
      _log.warning('ingresso nel watch party non riuscito: $error');
      _reset();
      _leaveQuietly();
      throw const WatchPartyException(WatchPartyFailure.network);
    } finally {
      if (identical(_joining, joining)) _joining = null;
    }
  }

  void _reset() {
    _stopClock();
    _startLag = null;
    _lastCommand = null;
    _joinedAt = null;
    _rejoining = null;
    _generation++;
    if (ref.mounted) state = const WatchPartyState();
  }

  /// Uscita senza attendere l'esito: fuori da un gruppo il server risponde
  /// solo `NotInGroup`.
  void _leaveQuietly() {
    _ghostLeftAt = clock.now();
    unawaited(_api.leave().catchError((Object error) =>
        _log.info('uscita dal watch party non inviata: $error')));
  }

  /// Arriva qualcosa di un gruppo mentre non siamo in nessuno: per il server
  /// siamo ancora dentro (es. uscita non arrivata). Si esce, al massimo ogni
  /// [ghostLeaveInterval]. Durante l'ingresso gli eventi sono normali.
  void _leaveGhostGroup() {
    if (state.phase != WatchPartyPhase.none) return;
    final last = _ghostLeftAt;
    if (last != null && clock.now().difference(last) < ghostLeaveInterval) {
      return;
    }
    _log.info('eventi di un watch party fuori da un gruppo: uscita');
    _leaveQuietly();
  }

  /// Dopo una caduta del WebSocket il server può averci tolto dal gruppo o
  /// averci perso dei comandi: si rientra nello stesso gruppo (spec B §5.5).
  /// Il server rimanda gruppo, coda e stato; il player rimanda `Ready`.
  void _rejoin() {
    final group = state.group;
    if (!state.inGroup || group == null) return;
    _rejoining = group.id;
    _log.info('WebSocket riconnesso: rientro nel watch party');
    unawaited(_api.join(group.id).catchError((Object error) =>
        _log.warning('rientro nel watch party non riuscito: $error')));
  }

  void _stopClock() {
    _clock?.stop();
    _clock = null;
  }

  void _startClock() {
    _stopClock();
    _clock = ServerClock(
      fetch: () async {
        final time = await _api.utcTime();
        return (
          serverReceived: time.requestReceived,
          serverSent: time.responseSent,
        );
      },
      onPing: (ping) => unawaited(_api.ping(ping).catchError(
          (Object error) => _log.info('ping non inviato: $error'))),
    )..start();
  }

  bool _isCurrent(String groupId) {
    final id = state.group?.id;
    return id != null && _normalizeId(id) == _normalizeId(groupId);
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case SyncPlayGroupUpdated(:final update):
        _onGroupUpdate(update);
      case SyncPlayCommandReceived(:final command):
        _onCommand(command);
      case ServerConnected(isReconnect: true):
        _rejoin();
      default:
        break;
    }
  }

  void _onGroupUpdate(GroupUpdate update) {
    switch (update) {
      case GroupJoined(:final info):
        if (_rejoining != null && state.inGroup && _isCurrent(info.id)) {
          _rejoining = null;
          // I comandi di prima della caduta non valgono più.
          _joinedAt = info.lastUpdatedAt;
          state = state.copyWith(
              group: info, groupState: info.state, rejoins: state.rejoins + 1);
          _log.info('rientrati nel watch party '
              '(${info.participants.length} membri)');
          return;
        }
        if (state.phase != WatchPartyPhase.joining) {
          // Conferma arrivata dopo un timeout o un'uscita.
          if (!state.inGroup) {
            unawaited(_api.leave().catchError((Object error) =>
                _log.info('uscita dal watch party non inviata: $error')));
          }
          return;
        }
        _joinedAt = info.lastUpdatedAt;
        state = WatchPartyState(
          phase: WatchPartyPhase.inGroup,
          group: info,
          groupState: info.state,
        );
        _startClock();
        _startLag = StartLag();
        final joining = _joining;
        if (joining != null && !joining.isCompleted) joining.complete();
        _log.info('nel watch party (${info.participants.length} membri)');
      case UserJoined(:final groupId, :final userName) when _isCurrent(groupId):
        final wasMember = state.members.contains(userName);
        state = state.copyWith(
            group: state.group!.copyWith(
                participants: [...state.group!.participants, userName]));
        unawaited(_refreshMembers(update, userName, wasMember: wasMember));
      case UserLeft(:final groupId, :final userName) when _isCurrent(groupId):
        final wasMember = state.members.contains(userName);
        final participants = [...state.group!.participants]..remove(userName);
        state = state.copyWith(
            group: state.group!.copyWith(participants: participants));
        unawaited(_refreshMembers(update, userName, wasMember: wasMember));
      case GroupStateUpdate(:final groupId, state: final groupState)
          when _isCurrent(groupId):
        state = state.copyWith(groupState: groupState);
        _updates.add(update);
      case PlayQueueUpdate(:final groupId, :final queue)
          when _isCurrent(groupId):
        final current = state.queue;
        if (current != null && queue.lastUpdate.isBefore(current.lastUpdate)) {
          return;
        }
        state = state.copyWith(queue: queue);
        _updates.add(update);
      case UserJoined() ||
          UserLeft() ||
          GroupStateUpdate() ||
          PlayQueueUpdate():
        _leaveGhostGroup();
      case GroupLeft() || NotInGroup():
        if (state.inGroup) {
          _log.info('il server ci ha tolto dal watch party');
          _reset();
          // Gli avvisi mostrano "terminato" (dopo essersi svuotati).
          _updates.add(update);
        }
      case GroupDoesNotExist():
        if (_rejoining != null) {
          _log.info('il watch party non esiste più');
          _reset();
          _updates.add(update);
          return;
        }
        _failJoin(WatchPartyFailure.groupGone);
      case LibraryAccessDenied():
        _failJoin(WatchPartyFailure.accessDenied);
    }
  }

  /// Dopo un'entrata o un'uscita ([update], già applicata allo stato) i
  /// membri si rileggono dal server: `UserJoined`/`UserLeft` arrivano per
  /// ogni sessione, mentre i `Participants` del server sono per nome utente
  /// (lo stesso utente può avere due sessioni, e al nostro ingresso compare
  /// una volta sola). Se la rilettura non riesce vale l'aggiornamento
  /// locale. Agli avvisi [update] arriva dopo, e solo se [userName] è
  /// davvero entrato o uscito (confronto dei nomi dei membri prima e dopo).
  Future<void> _refreshMembers(GroupUpdate update, String userName,
      {required bool wasMember}) async {
    final groupId = state.group!.id;
    final generation = _generation;
    final request = ++_membersRequest;
    GroupInfo? info;
    try {
      info = await _api.group(groupId).timeout(membersTimeout);
    } on Object catch (error) {
      _log.info('membri del watch party non riletti: $error');
    }
    // Usciti dal gruppo (o sessione chiusa) nel frattempo: niente.
    if (!ref.mounted || generation != _generation || !state.inGroup) return;
    if (info != null && request == _membersRequest) {
      state = state.copyWith(
          group: state.group!.copyWith(participants: info.participants));
    }
    if (state.members.contains(userName) != wasMember) _updates.add(update);
  }

  void _failJoin(WatchPartyFailure failure) {
    final joining = _joining;
    if (joining != null && !joining.isCompleted) {
      joining.completeError(WatchPartyException(failure));
    }
  }

  void _onCommand(SyncPlayCommand command) {
    if (state.phase == WatchPartyPhase.none) {
      _leaveGhostGroup();
      return;
    }
    if (!state.inGroup || !_isCurrent(command.groupId)) return;
    final joinedAt = _joinedAt;
    if (joinedAt != null && command.emittedAt.isBefore(joinedAt)) return;
    _lastCommand = command;
    _commands.add(command);
  }
}

final watchPartySessionProvider =
    NotifierProvider<WatchPartySession, WatchPartyState>(
        WatchPartySession.new);
