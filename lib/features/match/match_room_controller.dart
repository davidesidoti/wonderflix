import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/social/match_api.dart';
import '../../core/social/match_models.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import '../tonight/tonight_logic.dart';
import '../watch_party/watch_party_providers.dart';
import 'match_providers.dart';

final _log = Logger('match');

/// La sala del match dell'app (spec P §7.3).
@immutable
class MatchRoomView {
  const MatchRoomView(
      {required this.roomId, this.state, this.gone = false, this.sent = 0});

  final String roomId;

  /// L'ultimo stato ricevuto; `null` finché non ne arriva uno.
  final MatchState? state;

  /// Non siamo più nella sala (409 `NotMember` rileggendo): la pagina si
  /// chiude con "Sala chiusa".
  final bool gone;

  /// Voti mandati da questo client e non ancora confermati da uno stato: la
  /// carta passa subito, senza aspettare il plugin.
  final int sent;

  bool get closed => gone || state?.phase == MatchPhase.closed;

  /// A che punto della pila è [userId]: il più avanti tra il voto in volo e
  /// quello confermato (0 se non è un membro).
  int position(String userId) {
    final voted = state?.members
            .where((m) => m.userId == userId)
            .map((m) => m.voted)
            .firstOrNull ??
        0;
    return voted > sent ? voted : sent;
  }

  MatchRoomView copyWith({MatchState? state, bool? gone, int? sent}) =>
      MatchRoomView(
        roomId: roomId,
        state: state ?? this.state,
        gone: gone ?? this.gone,
        sent: sent ?? this.sent,
      );
}

/// L'unica sala del match dell'app: il plugin ne tiene una per utente (piano
/// 22b, decisione 3). Accetta solo stati della sua sala più recenti di
/// quello che ha (decisione 9), rilegge a ogni riconnessione, esce quando
/// la pagina si chiude o si cambia profilo.
class MatchRoomController extends Notifier<MatchRoomView?> {
  bool _entering = false;

  /// Stati arrivati mentre si entra, quando la sala non c'è ancora: si
  /// applicano appena c'è (quelli di altre sale cadono in [_apply]).
  final _pendingUpdates = <MatchState>[];

  /// Un'apertura o un ingresso è in corso: un secondo clic non ne fa un altro.
  bool get entering => _entering;

  MatchApi get _api => ref.read(matchApiProvider);

  @override
  MatchRoomView? build() {
    // Cambiando account la sala di prima non è più nostra.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.match))) {
      return null;
    }
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is! MatchUpdatedEvent) return;
      if (_entering && state == null) {
        _pendingUpdates.add(event.state);
      } else {
        _apply(event.state);
      }
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      // Gli stati persi mentre il WebSocket era giù.
      if (event is ServerConnected && event.isReconnect) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    return null;
  }

  /// Apre una sala nuova (spec P §7.2); `null` se è riuscito.
  Future<MatchFailure?> open() => _enter(_api.open);

  /// Entra nella sala [roomId] su invito; `null` se è riuscito.
  Future<MatchFailure?> join(String roomId) => _enter(() => _api.join(roomId));

  /// Un 409 `InAnotherRoom` con una sala che l'app non sta mostrando è una
  /// sala rimasta da un crash o da un'uscita persa: se ne esce e si riprova
  /// una volta (piano 22b, decisione 4).
  Future<MatchFailure?> _enter(Future<MatchState> Function() request) async {
    if (_entering) return MatchFailure.conflict;
    // Il Ref di questa build: dopo un rebuild (altro profilo, funzione spenta)
    // quello vecchio non è più montato e la risposta in volo si scarta.
    final ref = this.ref;
    _entering = true;
    try {
      for (var attempt = 0;; attempt++) {
        try {
          final next = await request();
          if (!ref.mounted) return null;
          state = MatchRoomView(roomId: next.roomId, state: next);
          _pendingUpdates.forEach(_apply);
          return null;
        } on MatchException catch (error) {
          final other = error.roomId;
          if (error.failure != MatchFailure.inAnotherRoom ||
              other == null ||
              attempt > 0 ||
              _shows(other)) {
            _log.info('sala del match non raggiunta: ${error.failure.name}');
            return error.failure;
          }
          try {
            await _api.leave(other);
          } on MatchException catch (leaveError) {
            _log.info('uscita dalla sala rimasta: ${leaveError.failure.name}');
            return error.failure;
          }
          if (!ref.mounted) return null;
        }
      }
    } finally {
      _entering = false;
      _pendingUpdates.clear();
    }
  }

  /// L'app mostra la sala aperta [roomId].
  bool _shows(String roomId) {
    final current = state;
    return current != null &&
        !current.closed &&
        normalizeMatchId(current.roomId) == normalizeMatchId(roomId);
  }

  void _apply(MatchState next) {
    final current = state;
    if (current == null ||
        normalizeMatchId(current.roomId) != normalizeMatchId(next.roomId)) {
      return;
    }
    final have = current.state;
    if (have != null && next.rev <= have.rev) return;
    state = current.copyWith(state: next);
  }

  /// Rilegge lo stato; fuori dalla sala la vista diventa [MatchRoomView.gone].
  Future<void> reload() async {
    final current = state;
    if (current == null || current.closed) return;
    final ref = this.ref;
    try {
      final next = await _api.state(current.roomId);
      if (!ref.mounted) return;
      _apply(next);
    } on MatchException catch (error) {
      if (!ref.mounted) return;
      final now = state;
      if (error.failure == MatchFailure.notMember &&
          now != null &&
          normalizeMatchId(now.roomId) == normalizeMatchId(current.roomId)) {
        state = now.copyWith(gone: true);
      } else {
        _log.info('sala del match non riletta: ${error.failure.name}');
      }
    }
  }

  /// Esce dalla sala (spec P §7.3): con [roomId], solo se è quella. La sala
  /// sparisce subito dall'app; una sala chiusa non va lasciata.
  Future<void> leave([String? roomId]) async {
    // La pagina chiama dopo lo smontaggio: l'app può già essere chiusa.
    if (!ref.mounted) return;
    final current = state;
    if (current == null) return;
    if (roomId != null &&
        normalizeMatchId(roomId) != normalizeMatchId(current.roomId)) {
      return;
    }
    state = null;
    if (current.closed) return;
    try {
      await _api.leave(current.roomId);
    } on MatchException catch (error) {
      // La pulizia del plugin la chiuderà comunque (spec P §6.1).
      _log.info('uscita dalla sala del match: ${error.failure.name}');
    }
  }

  /// Invita amici (solo chi ha aperto, in attesa).
  Future<MatchFailure?> invite(List<String> userIds) async {
    final current = state;
    if (current == null || current.closed) return MatchFailure.closed;
    try {
      await _api.invite(current.roomId, userIds);
      return null;
    } on MatchException catch (error) {
      return error.failure;
    }
  }

  /// "Inizia" con i filtri di "Cosa guardo stasera?" (piano 22b, decisione 2).
  Future<MatchFailure?> start(TonightFilters filters) async {
    final current = state;
    if (current == null || current.closed) return MatchFailure.closed;
    final ref = this.ref;
    try {
      final next = await _api.start(current.roomId,
          type: filters.type.wire,
          duration: filters.duration.wire,
          genre: filters.genre);
      if (ref.mounted) _apply(next);
      return null;
    } on MatchException catch (error) {
      return error.failure;
    }
  }

  /// Un voto: la carta passa subito (`sent`) e torna se il voto non parte.
  Future<MatchFailure?> vote(String itemId, {required bool yes}) async {
    final current = state;
    final room = current?.state;
    if (current == null || room == null || current.closed) {
      return MatchFailure.closed;
    }
    if (room.phase != MatchPhase.voting) return MatchFailure.notStarted;
    final ref = this.ref;
    final pos = current.position(ref.read(currentUserIdProvider));
    if (pos >= room.stack.length || room.stack[pos] != itemId) {
      return MatchFailure.notNext;
    }
    state = current.copyWith(sent: pos + 1);
    try {
      await _api.vote(current.roomId, itemId, yes: yes);
      return null;
    } on MatchException catch (error) {
      if (!ref.mounted) return error.failure;
      if (error.failure == MatchFailure.notNext) {
        _resetSent(current.roomId, 0);
        await reload();
      } else {
        _resetSent(current.roomId, pos);
      }
      return error.failure;
    }
  }

  /// Rimette `sent` a [value] se la vista è ancora della sala [roomId].
  void _resetSent(String roomId, int value) {
    final now = state;
    if (now != null && now.roomId == roomId) {
      state = now.copyWith(sent: value);
    }
  }

  /// "Altri 30": nuovi titoli, come [start].
  Future<MatchFailure?> more() async {
    final current = state;
    if (current == null || current.closed) return MatchFailure.closed;
    final ref = this.ref;
    try {
      final next = await _api.more(current.roomId);
      if (ref.mounted) _apply(next);
      return null;
    } on MatchException catch (error) {
      return error.failure;
    }
  }

  /// Dice al plugin il gruppo del party partito dalla sala; niente stato.
  Future<MatchFailure?> party(String groupId) async {
    final current = state;
    if (current == null || current.closed) return MatchFailure.closed;
    try {
      await _api.party(current.roomId, groupId);
      return null;
    } on MatchException catch (error) {
      return error.failure;
    }
  }
}

final matchRoomProvider =
    NotifierProvider<MatchRoomController, MatchRoomView?>(
        MatchRoomController.new);
