import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/social/rating_models.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import '../watch_party/party_queue_items.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';

final _log = Logger('ratings');

/// Dopo `Revealed` la votazione resta nell'app questo tempo, poi se ne va da sé.
const ratingRoundKeep = Duration(minutes: 10);

/// Se questo tempo dopo `EndsAt` lo stato è ancora `Voting`, si rilegge: un
/// avviso perso non deve lasciare la coda ferma.
const ratingRevealGrace = Duration(seconds: 5);

/// Tempo massimo dell'apertura: il player non aspetta oltre.
const ratingOpenTimeout = Duration(seconds: 5);

/// Voto minimo e massimo.
const ratingMin = 1;
const ratingMax = 10;

/// Perché un voto non è partito.
enum RatingSendError { notSaved, tooMany }

/// La votazione di fine party vista dall'app (spec Q §7).
@immutable
class RatingRoundView {
  const RatingRoundView({
    required this.round,
    required this.playlistItemId,
    required this.userId,
    this.source,
    this.unavailable = false,
    this.draft,
    this.editing = false,
    this.sending = false,
    this.error,
  });

  final RatingRound round;

  /// L'elemento della coda che ha aperto la votazione.
  final String playlistItemId;

  /// Il titolo guardato (episodio o film); `null` finché la coda non lo ha.
  final JellyfinItem? source;
  final String userId;

  /// Il plugin non ha più la votazione (`{}`): non ferma la coda.
  final bool unavailable;

  /// Il numero scelto e non ancora mandato.
  final int? draft;

  /// "Cambia": i numeri tornano dopo un voto.
  final bool editing;
  final bool sending;
  final RatingSendError? error;

  RatingVoterStatus? get myStatus => round.voter(userId)?.status;

  bool get showsPicker =>
      !unavailable &&
      round.phase == RatingPhase.voting &&
      (myStatus == RatingVoterStatus.waiting || myStatus == null || editing);

  /// La coda è ferma solo nel player dell'elemento che ha aperto la votazione.
  bool holdsQueue(String playlistItemId) =>
      !unavailable &&
      round.phase == RatingPhase.voting &&
      jellyfinIdKey(this.playlistItemId) == jellyfinIdKey(playlistItemId);

  RatingRoundView copyWith({
    RatingRound? round,
    bool? unavailable,
    int? draft,
    bool? editing,
    bool? sending,
    RatingSendError? error,
    bool clearError = false,
  }) =>
      RatingRoundView(
        round: round ?? this.round,
        playlistItemId: playlistItemId,
        userId: userId,
        source: source,
        unavailable: unavailable ?? this.unavailable,
        draft: draft ?? this.draft,
        editing: editing ?? this.editing,
        sending: sending ?? this.sending,
        error: clearError ? null : error ?? this.error,
      );
}

/// L'unica votazione di fine party dell'app (come [MatchRoomController]): la
/// stessa votazione si riconosce da `ItemId` ed `EndsAt`, e dentro di essa
/// contano solo i `Rev` più alti (piano 23b, decisione 10).
class RatingRoundController extends Notifier<RatingRoundView?> {
  /// Apertura in corso: l'elemento della coda a cui appartiene.
  ({String playlistItemId, JellyfinItem item})? _opening;

  Timer? _recheck;
  Timer? _keep;

  /// La votazione chiusa dall'utente: un avviso ritardatario non la riporta.
  ({String itemId, DateTime endsAt})? _dismissed;

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  RatingRoundView? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    final enabled =
        ref.watch(socialAvailabilityProvider.select((f) => f.ratings));
    final group = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? jellyfinIdKey(s.group!.id) : null));
    _opening = null;
    _dismissed = null;
    _cancelTimers();
    ref.onDispose(_cancelTimers);
    if (!enabled || group == null) return null;
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is RatingRoundUpdatedEvent) _apply(event.state);
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      // Gli avvisi persi mentre il WebSocket era giù.
      if (event is ServerConnected && event.isReconnect) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    return null;
  }

  void _cancelTimers() {
    _recheck?.cancel();
    _recheck = null;
    _keep?.cancel();
    _keep = null;
  }

  String? get _groupKey {
    final party = ref.read(watchPartySessionProvider);
    return party.inGroup ? jellyfinIdKey(party.group!.id) : null;
  }

  static bool _same(RatingRound a, RatingRound b) =>
      a.itemId == b.itemId && a.endsAt.isAtSameMomentAs(b.endsAt);

  /// Apre la votazione per [item] (idempotente sul titolo, lato plugin).
  Future<void> open({
    required String groupId,
    required JellyfinItem item,
    required String playlistItemId,
  }) async {
    if (_groupKey == null || _opening != null) return;
    final current = state;
    if (current != null &&
        !current.unavailable &&
        jellyfinIdKey(current.playlistItemId) ==
            jellyfinIdKey(playlistItemId)) {
      return;
    }
    final ref = this.ref;
    _opening = (playlistItemId: playlistItemId, item: item);
    try {
      final next = await _api
          .openRatingRound(groupId, item.id)
          .timeout(ratingOpenTimeout);
      if (!ref.mounted) return;
      _apply(next);
    } on SocialException catch (error) {
      _log.info('votazione non aperta: ${error.failure.name}');
    } on Object catch (error) {
      _log.info('votazione non aperta: ${error.runtimeType}');
    } finally {
      if (ref.mounted) _opening = null;
    }
  }

  /// Applica uno stato; [acceptSame] anche con lo stesso `Rev` (la risposta a
  /// un'azione nostra).
  void _apply(RatingRound next, {bool acceptSame = false}) {
    if (_groupKey != jellyfinIdKey(next.groupId)) return;
    final current = state;
    if (current != null && _same(current.round, next)) {
      final stale = acceptSame ? next.rev < current.round.rev
          : next.rev <= current.round.rev;
      if (stale && !current.unavailable) return;
      state = current.copyWith(round: next, unavailable: false);
    } else {
      final dismissed = _dismissed;
      if (dismissed != null &&
          dismissed.itemId == next.itemId &&
          dismissed.endsAt.isAtSameMomentAs(next.endsAt)) {
        return;
      }
      final playing = ref.read(watchPartySessionProvider).queue?.playing;
      final opening = _opening;
      final playlistItemId = opening?.playlistItemId ?? playing?.playlistItemId;
      if (playlistItemId == null) return;
      _keep?.cancel();
      _keep = null;
      state = RatingRoundView(
        round: next,
        playlistItemId: playlistItemId,
        userId: ref.read(currentUserIdProvider),
        source: opening?.item ??
            (playing == null
                ? null
                : ref.read(partyQueueItemsProvider)[playing.itemId]),
        draft: next.mine?.score,
      );
    }
    _schedule(next);
  }

  void _schedule(RatingRound round) {
    _recheck?.cancel();
    _recheck = null;
    if (round.phase == RatingPhase.voting) {
      final wait = round.endsAt.add(ratingRevealGrace).difference(clock.now());
      _recheck = Timer(wait > Duration.zero ? wait : ratingRevealGrace, () {
        _recheck = null;
        unawaited(reload());
      });
    } else {
      _keep ??= Timer(ratingRoundKeep, () {
        _keep = null;
        state = null;
      });
    }
  }

  /// Rilegge lo stato; `{}` vuol dire che la votazione non c'è più.
  Future<void> reload() async {
    final current = state;
    final group = _groupKey;
    if (current == null || group == null) return;
    final ref = this.ref;
    try {
      final next = await _api.ratingRound(current.round.groupId);
      if (!ref.mounted) return;
      if (next != null) {
        _apply(next);
      } else if (state case final now?) {
        _recheck?.cancel();
        _recheck = null;
        state = now.copyWith(unavailable: true);
      }
    } on SocialException catch (error) {
      _log.info('votazione non riletta: ${error.failure.name}');
    } on Object catch (error) {
      _log.info('votazione non riletta: ${error.runtimeType}');
    }
  }

  /// Sceglie il voto (1–10) fra i numeri visibili.
  void select(int score) {
    final current = state;
    if (current == null ||
        !current.showsPicker ||
        score < ratingMin ||
        score > ratingMax) {
      return;
    }
    state = current.copyWith(draft: score, clearError: true);
  }

  /// Sposta il voto di [delta], senza uscire da 1–10.
  void step(int delta) {
    final current = state;
    if (current == null) return;
    select(max(ratingMin, min(ratingMax, (current.draft ?? 0) + delta)));
  }

  /// "Cambia": i numeri tornano, con il voto dato.
  void edit() {
    final current = state;
    if (current == null ||
        current.unavailable ||
        current.round.phase != RatingPhase.voting) {
      return;
    }
    state = current.copyWith(
        editing: true,
        draft: current.round.mine?.score ?? current.draft,
        clearError: true);
  }

  Future<void> vote(String? comment) {
    final score = state?.draft;
    if (score == null) return Future.value();
    final text = comment?.trim();
    return _send((group) => _api.voteInRound(
        group, score, text == null || text.isEmpty ? null : text));
  }

  Future<void> skip() => _send(_api.skipRound);

  Future<void> reveal() => _send(_api.revealRound);

  /// Un'azione sulla votazione: una sola in volo; la risposta è lo stato.
  Future<void> _send(Future<RatingRound> Function(String groupId) call) async {
    final current = state;
    if (current == null || current.sending) return;
    final ref = this.ref;
    state = current.copyWith(sending: true, clearError: true);
    try {
      final next = await call(current.round.groupId);
      if (!ref.mounted) return;
      _apply(next, acceptSame: true);
      state = state?.copyWith(sending: false, editing: false);
    } on SocialException catch (error) {
      if (!ref.mounted) return;
      _log.info('azione sulla votazione non riuscita: ${error.failure.name}');
      state = state?.copyWith(
        sending: false,
        error: switch (error.failure) {
          SocialFailure.rateLimited => RatingSendError.tooMany,
          SocialFailure.conflict => null,
          _ => RatingSendError.notSaved,
        },
      );
      // Chiusa nel frattempo: si rilegge lo stato vero.
      if (error.failure == SocialFailure.conflict) await reload();
    } on Object catch (error) {
      if (!ref.mounted) return;
      _log.info('azione sulla votazione non riuscita: ${error.runtimeType}');
      state = state?.copyWith(sending: false, error: RatingSendError.notSaved);
    }
  }

  /// La votazione esce dall'app (spec Q §7.2).
  void dismiss() {
    final current = state;
    if (current == null) return;
    _dismissed = (itemId: current.round.itemId, endsAt: current.round.endsAt);
    _cancelTimers();
    state = null;
  }
}

final ratingRoundProvider =
    NotifierProvider<RatingRoundController, RatingRoundView?>(
        RatingRoundController.new);
