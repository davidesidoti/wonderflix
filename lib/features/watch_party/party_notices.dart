import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

enum PartyNoticeKind {
  paused,
  resumed,
  forcedResume,
  seeked,
  joined,
  left,
  nextEpisode,
  nowWatching,
  resync,

  /// Il gruppo non c'è più (sparito durante il rientro).
  ended,

  /// Il server ci ha tolto dal gruppo, che può esserci ancora.
  removed,
}

/// Un avviso del watch party (spec B §5.7). Il testo lo compone
/// `partyNoticeText`.
class PartyNotice {
  const PartyNotice(this.kind,
      {this.mine = false, this.position, this.name, this.title});

  final PartyNoticeKind kind;

  /// Azione dell'utente stesso: testo in seconda persona ("Hai…").
  final bool mine;

  /// Per i salti.
  final Duration? position;

  /// Per entrate e uscite.
  final String? name;

  /// Per episodio successivo e nuovo titolo.
  final String? title;
}

/// Chi annuncia un'azione dell'utente (vedi [PartyNotices.mine]).
typedef PartyActionCallback = void Function(PartyNoticeKind kind,
    {Duration? position});

/// Avvisi del watch party, uno alla volta per [showFor]. Lo stato è
/// l'avviso da mostrare adesso (`null` = nessuno).
class PartyNotices extends Notifier<PartyNotice?> {
  static const showFor = Duration(seconds: 3);

  /// Entro questo tempo lo `StateUpdate` di una nostra azione è la sua eco.
  static const echoWindow = Duration(seconds: 3);

  final _queue = Queue<PartyNotice>();
  final _echoes = <({PartyNoticeKind kind, DateTime at})>[];
  Timer? _timer;
  GroupState? _groupState;
  String? _playing;
  Duration? _lastSeek;

  @override
  PartyNotice? build() {
    // Nuovo utente = nuova sessione del gruppo: ci si iscrive di nuovo.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    final party = ref.read(watchPartySessionProvider);
    final session = ref.read(watchPartySessionProvider.notifier);
    _queue.clear();
    _echoes.clear();
    _timer = null;
    _groupState = party.inGroup ? party.groupState : null;
    _playing = party.queue?.playing?.playlistItemId;
    _lastSeek = null;
    final subscriptions = [
      session.updates.listen(_onUpdate),
      session.commands.listen((command) {
        if (command.type == SyncPlayCommandType.seek) {
          _lastSeek = command.position;
        }
      }),
    ];
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) {
        _clear();
        return;
      }
      // `GroupJoined` non arriva negli aggiornamenti: lo stato del gruppo
      // all'ingresso si prende dalla sessione (es. una ripresa senza
      // aspettare subito dopo l'ingresso).
      final joined = ref.read(watchPartySessionProvider);
      _groupState = joined.groupState;
      _playing = joined.queue?.playing?.playlistItemId;
    });
    ref.onDispose(() {
      _timer?.cancel();
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    });
    return null;
  }

  /// Mostra [notice] dopo quelli già in coda.
  void show(PartyNotice notice) {
    _queue.add(notice);
    if (_timer == null) _next();
  }

  /// Azione dell'utente: l'avviso compare subito, e l'eco del server (entro
  /// [echoWindow]) non ne produce un secondo.
  void mine(PartyNoticeKind kind, {Duration? position}) {
    _echoes.add((kind: kind, at: clock.now()));
    show(PartyNotice(kind, mine: true, position: position));
  }

  void _next() {
    _timer?.cancel();
    if (_queue.isEmpty) {
      _timer = null;
      if (ref.mounted) state = null;
      return;
    }
    if (ref.mounted) state = _queue.removeFirst();
    _timer = Timer(showFor, _next);
  }

  void _clear() {
    _queue.clear();
    _echoes.clear();
    _timer?.cancel();
    _timer = null;
    _groupState = null;
    _playing = null;
    _lastSeek = null;
    if (ref.mounted) state = null;
  }

  /// `true` (e l'eco si consuma) se [kind] è l'eco di una nostra azione.
  bool _isEcho(PartyNoticeKind kind) {
    final now = clock.now();
    _echoes.removeWhere((echo) => now.difference(echo.at) > echoWindow);
    final index = _echoes.indexWhere((echo) =>
        echo.kind == kind ||
        (echo.kind == PartyNoticeKind.resumed &&
            kind == PartyNoticeKind.forcedResume));
    if (index < 0) return false;
    _echoes.removeAt(index);
    return true;
  }

  void _onUpdate(GroupUpdate update) {
    switch (update) {
      case GroupStateUpdate(state: final groupState, :final reason):
        final previous = _groupState;
        _groupState = groupState;
        final kind = switch (reason) {
          'Pause' => PartyNoticeKind.paused,
          'Unpause' => previous == GroupState.waiting &&
                  groupState == GroupState.playing
              ? PartyNoticeKind.forcedResume
              : PartyNoticeKind.resumed,
          'Seek' => PartyNoticeKind.seeked,
          _ => null,
        };
        if (kind == null || _isEcho(kind)) return;
        if (kind == PartyNoticeKind.seeked) {
          final position = _lastSeek;
          if (position == null) return;
          show(PartyNotice(kind, position: position));
        } else {
          show(PartyNotice(kind));
        }
      case UserJoined(:final userName):
        show(PartyNotice(PartyNoticeKind.joined, name: userName));
      case UserLeft(:final userName):
        show(PartyNotice(PartyNoticeKind.left, name: userName));
      case PlayQueueUpdate(:final queue):
        _onQueue(queue);
      case GroupDoesNotExist():
        show(const PartyNotice(PartyNoticeKind.ended));
      case GroupLeft() || NotInGroup():
        show(const PartyNotice(PartyNoticeKind.removed));
      default:
        break;
    }
  }

  void _onQueue(PlayQueue queue) {
    final entry = queue.playing;
    final previous = _playing;
    _playing = entry?.playlistItemId;
    if (entry == null || previous == null || previous == entry.playlistItemId) {
      return;
    }
    final kind = queue.reason == 'NextItem'
        ? PartyNoticeKind.nextEpisode
        : PartyNoticeKind.nowWatching;
    unawaited(_announce(kind, entry.itemId));
  }

  Future<void> _announce(PartyNoticeKind kind, String itemId) async {
    try {
      final item = await ref
          .read(libraryApiProvider)
          .item(ref.read(currentUserIdProvider), itemId);
      if (!ref.mounted) return;
      // Nel frattempo si è usciti dal gruppo o si guarda già altro.
      final party = ref.read(watchPartySessionProvider);
      if (!party.inGroup || party.queue?.playing?.itemId != itemId) return;
      show(PartyNotice(kind,
          title: kind == PartyNoticeKind.nextEpisode
              ? cardSubtitle(item) ?? item.name
              : cardTitle(item)));
    } on Object catch (error) {
      _log.info('titolo per l\'avviso non disponibile: $error');
    }
  }
}

final partyNoticesProvider =
    NotifierProvider<PartyNotices, PartyNotice?>(PartyNotices.new);
