import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/match_api.dart';
import '../../core/social/match_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../friends/friends_controller.dart';
import '../friends/friends_panel.dart';
import '../library/library_providers.dart';
import '../profiles/profile_preferences.dart';
import '../tonight/ask_parts.dart';
import '../tonight/ask_sentence.dart';
import '../tonight/tonight_controller.dart';
import '../tonight/tonight_logic.dart';
import '../watch_party/watch_party_actions.dart';
import 'match_actions.dart';
import 'match_celebration.dart';
import 'match_column.dart';
import 'match_room_controller.dart';
import 'match_seats.dart';
import 'match_swipe_deck.dart';
import 'match_titles.dart';

const _muted = TextStyle(color: WfColors.creamMuted);

/// Le etichette piccole della sala ("Amici online", "Si vota tra").
const _label = TextStyle(
    color: WfColors.creamMuted, fontSize: 13, fontWeight: FontWeight.w600);

/// Riga delle regole: circa 62 caratteri a 14.
const _leadMaxWidth = 560.0;

/// Pausa prima di riprovare un "no" automatico che non è partito.
const _autoRetryDelay = Duration(seconds: 2);

/// Larghezza massima del mazzo.
const _deckMaxWidth = 560.0;

/// La sala del match (spec P §7.3): attesa e votazione. Lasciare la pagina fa uscire dalla sala.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  late final MatchRoomController _controller;
  late TonightFilters _filters;

  /// Amici invitati da questa pagina: il pulsante dice "Invitato".
  final _invited = <String>{};
  bool _starting = false;
  bool _closing = false;

  /// Il testo "Sala chiusa" è ancora da mostrare (la chiusura può attendere).
  bool _closeNotice = false;
  bool _closeDone = false;

  /// Titoli già votati "no" da soli perché la libreria non li ha più.
  final _autoVoted = <String>{};
  Timer? _autoRetry;

  /// Match già visti: `null` finché la votazione non si vede la prima volta
  /// (quelli di allora non si festeggiano). I nuovi vanno in [_celebrate].
  Set<String>? _seenMatches;
  final _celebrate = <String>[];

  /// Il match scelto per partire per primo nel party; `null` = il primo in ordine.
  String? _firstChoice;
  bool _partyStarting = false;
  bool _moreLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(matchRoomProvider.notifier);
    _filters = readTonightFilters(ref.read(profilePreferencesProvider));
    // ref.listen non scatta per il valore già presente: una sala già chiusa
    // all'apertura della pagina si controlla qui.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onRoom(ref.read(matchRoomProvider));
      _trackMatches(ref.read(matchRoomProvider));
      _autoVote();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cambia quando la rotta torna in cima (isCurrent): la chiusura rimasta
    // in attesa può partire.
    if (_closing) WidgetsBinding.instance.addPostFrameCallback((_) => _close());
  }

  @override
  void dispose() {
    _autoRetry?.cancel();
    // Lasciare la pagina fa uscire dalla sala (spec P §7.3). In un microtask:
    // dentro lo smontaggio dell'albero i provider non si cambiano.
    final controller = _controller;
    final roomId = widget.roomId;
    scheduleMicrotask(() => unawaited(controller.leave(roomId)));
    super.dispose();
  }

  bool _isThisRoom(MatchRoomView? view) =>
      view != null &&
      normalizeMatchId(view.roomId) == normalizeMatchId(widget.roomId);

  /// La sala è chiusa, persa o lasciata altrove: la pagina si chiude, con
  /// "Sala chiusa" se non è partito il party (piano 22b, decisione 8).
  void _onRoom(MatchRoomView? view) {
    if (_closing) return;
    final ours = _isThisRoom(view);
    if (ours && !view!.closed) return;
    _closing = true;
    // Il party è partito dalla sala: chi non l'ha aperta ci entra da sé. Se
    // non riesce, joinWatchParty avvisa e la pagina si chiude lo stesso.
    final groupId = ours ? view!.state?.partyGroupId : null;
    if (groupId != null &&
        !view!.state!.isCreator(ref.read(currentUserIdProvider))) {
      unawaited(joinWatchParty(context, ref, groupId));
    }
    _closeNotice =
        ours && view!.state?.closedReason != MatchClosedReason.partyStarted;
    WidgetsBinding.instance.addPostFrameCallback((_) => _close());
  }

  /// Chiude la pagina solo se la sua rotta è in cima: con un'altra pagina
  /// sopra (scheda, player) un pop toglierebbe quella; si attende.
  void _close() {
    if (!mounted || !_closing || _closeDone) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _closeDone = true;
    if (_closeNotice) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).matchClosed)));
    }
    final router = GoRouter.of(context);
    if (router.canPop()) router.pop();
  }

  void _setFilters(TonightFilters next) {
    setState(() => _filters = next);
    unawaited(writeTonightFilters(ref.read(profilePreferencesProvider), next));
  }

  Future<void> _invite(String userId) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = await _controller.invite([userId]);
    if (!mounted) return;
    if (failure == null) {
      setState(() => _invited.add(userId));
    } else {
      messenger?.showSnackBar(
          SnackBar(content: Text(matchFailureText(l, failure))));
    }
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _starting = true);
    final failure = await _controller.start(_filters);
    if (!mounted) return;
    setState(() => _starting = false);
    if (failure != null) {
      messenger?.showSnackBar(
          SnackBar(content: Text(matchFailureText(l, failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(matchRoomProvider, (_, view) {
      _onRoom(view);
      _trackMatches(view);
      _autoVote();
    });
    ref.listen(matchTitlesProvider, (_, _) => _autoVote());
    final view = ref.watch(matchRoomProvider);
    final state = _isThisRoom(view) ? view!.state : null;
    final compact = FormFactor.of(context).compact;
    final side = compact ? 16.0 : 32.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 22, side, 40),
      children: [
        Text(l.matchPageTitle.toUpperCase(),
            style: WfText.display(compact ? 40 : 56)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _leadMaxWidth),
            child: Text(l.matchLead, style: _muted.copyWith(fontSize: 14)),
          ),
        ),
        const SizedBox(height: 28),
        if (state != null && state.phase == MatchPhase.voting) ...[
          MatchSeats(state: state),
          const SizedBox(height: 32),
          _voting(l, view!, state),
        ] else if (state != null)
          _waiting(l, state, compact),
      ],
    );
  }

  /// I match comparsi dopo la prima vista della votazione vanno in coda alla festa.
  void _trackMatches(MatchRoomView? view) {
    final state = _isThisRoom(view) ? view!.state : null;
    if (state == null || state.phase != MatchPhase.voting) return;
    final seen = _seenMatches;
    if (seen == null) {
      _seenMatches = {...state.matches};
      return;
    }
    final fresh = [
      for (final id in state.matches)
        if (seen.add(id)) id,
    ];
    if (fresh.isNotEmpty) setState(() => _celebrate.addAll(fresh));
  }

  /// Il voto della carta in cima; se non parte, la carta torna da sola e si
  /// avvisa (un `notNext` si riallinea in silenzio). `true` se è partito.
  Future<bool> _vote(String itemId, bool yes, {bool silent = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = await _controller.vote(itemId, yes: yes);
    if (!silent && failure != null && failure != MatchFailure.notNext) {
      messenger?.showSnackBar(SnackBar(content: Text(l.matchVoteNotSent)));
    }
    return failure == null;
  }

  /// Titolo sparito dalla libreria in cima alla pila: "no" e si va avanti.
  /// Se il voto non parte, si riprova dopo [_autoRetryDelay].
  void _autoVote() {
    final view = ref.read(matchRoomProvider);
    final state = _isThisRoom(view) ? view!.state : null;
    if (state == null || state.phase != MatchPhase.voting) return;
    final mine = view!.position(ref.read(currentUserIdProvider));
    final topId = state.stack.skip(mine).firstOrNull;
    final titles = ref.read(matchTitlesProvider);
    if (topId == null ||
        !titles.containsKey(topId) ||
        titles[topId] != null ||
        !_autoVoted.add(topId)) {
      return;
    }
    unawaited(_vote(topId, false, silent: true).then((sent) {
      if (sent || !mounted) return;
      _autoRetry?.cancel();
      _autoRetry = Timer(_autoRetryDelay, () {
        _autoVoted.remove(topId);
        if (mounted) _autoVote();
      });
    }));
  }

  Future<void> _more() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _moreLoading = true);
    final failure = await _controller.more();
    if (!mounted) return;
    setState(() => _moreLoading = false);
    if (failure != null) {
      messenger?.showSnackBar(
          SnackBar(content: Text(matchFailureText(l, failure))));
    }
  }

  Future<void> _startParty() async {
    if (_partyStarting) return;
    setState(() => _partyStarting = true);
    await startMatchParty(context, ref, first: _firstChoice);
    if (mounted) setState(() => _partyStarting = false);
  }

  /// Fine della pila: attesa degli altri, o "Altri 30 titoli" per chi ha aperto
  /// quando hanno finito tutti.
  Widget _endOfStack(AppLocalizations l, MatchRoomView view, MatchState state) {
    final me = ref.watch(currentUserIdProvider);
    final everyone = state.members.every((m) =>
        (m.userId == me ? view.position(me) : m.voted) >= state.stack.length);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(state.stack.isEmpty ? l.matchEmpty : l.matchAllVoted,
            textAlign: TextAlign.center, style: _muted.copyWith(fontSize: 16)),
        if (everyone && state.isCreator(me)) ...[
          const SizedBox(height: 16),
          WfButton.secondary(
            key: const Key('match-more'),
            label: l.matchMore,
            icon: LucideIcons.refreshCw,
            onPressed: _moreLoading ? null : () => unawaited(_more()),
          ),
        ],
      ],
    );
  }

  /// Il mazzo a sinistra; a destra la colonna dei match (piano 22c, Task 4).
  Widget _voting(AppLocalizations l, MatchRoomView view, MatchState state) {
    final titles = ref.watch(matchTitlesProvider);
    final mine = view.position(ref.watch(currentUserIdProvider));
    final ids = state.stack.skip(mine).toList();
    final topId = ids.firstOrNull;
    final loaded = topId != null && titles.containsKey(topId);
    // Se in cima non c'è un titolo vero la votazione resta ferma sul "no".
    final cards = loaded && titles[topId] != null
        ? <JellyfinItem>[
            for (final id in ids) ?titles[id],
          ]
        : const <JellyfinItem>[];
    final celebrating = _celebrate.firstOrNull;
    final deck = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _deckMaxWidth),
        child: topId == null
            ? _endOfStack(l, view, state)
            : !loaded
            ? const Center(child: CircularProgressIndicator())
            : MatchSwipeDeck(
                cards: cards,
                onVote: (yes) => _vote(cards.first.id, yes),
              ),
      ),
    );
    final matches = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatchColumn(
          state: state,
          titles: titles,
          chosen: _firstChoice,
          onChoose: state.isCreator(ref.watch(currentUserIdProvider))
              ? (id) => setState(() => _firstChoice = id)
              : null,
        ),
        if (state.isCreator(ref.watch(currentUserIdProvider)) &&
            (state.matches.isNotEmpty || state.nearMatches.isNotEmpty)) ...[
          const SizedBox(height: 24),
          WfButton.primary(
            key: const Key('match-start-party'),
            label: l.matchStartParty,
            icon: LucideIcons.play,
            onPressed: _partyStarting ? null : () => unawaited(_startParty()),
          ),
        ],
      ],
    );
    // Nello stretto il mazzo sta sopra e i match sotto: affiancati non ci
    // stanno.
    final row = FormFactor.of(context).compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [deck, const SizedBox(height: 32), matches],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: deck),
              const SizedBox(width: 32),
              Expanded(flex: 2, child: matches),
            ],
          );
    if (celebrating == null) return row;
    return Stack(
      children: [
        row,
        Positioned.fill(
          child: MatchCelebration(
            key: const ValueKey('match-celebration'),
            id: celebrating,
            item: titles[celebrating],
            onDone: () => setState(() => _celebrate.remove(celebrating)),
          ),
        ),
      ],
    );
  }

  /// Posti e amici a sinistra, il riquadro con la frase e "Inizia" a destra
  /// (spec §5.3); nello stretto uno sotto l'altro.
  Widget _waiting(AppLocalizations l, MatchState state, bool compact) {
    final creator = state.isCreator(ref.watch(currentUserIdProvider));
    final enough = state.members.length >= matchMinMembers;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatchSeats(state: state),
        // Solo chi ha aperto può invitare (il plugin risponde NotCreator).
        if (creator) ...[
          const SizedBox(height: 26),
          _InviteFriends(state: state, invited: _invited, onInvite: _invite),
        ],
      ],
    );
    final panel = Container(
      key: const Key('match-panel'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: !creator
          ? Text(l.matchWaitingFor(state.creatorName),
              style: _muted.copyWith(fontSize: 16))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.matchVoteAmong, style: _label),
                const SizedBox(height: 12),
                AskSentence(
                  filters: _filters,
                  voice: AskVoice.match,
                  onChanged: _setFilters,
                  fontSize: 19,
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    WfButton.primary(
                      key: const Key('match-start'),
                      label: l.matchStart,
                      icon: LucideIcons.play,
                      onPressed: enough && !_starting
                          ? () => unawaited(_start())
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                          enough ? l.matchNoLateJoin : l.matchNeedFriend,
                          style: _muted),
                    ),
                  ],
                ),
              ],
            ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [left, const SizedBox(height: 28), panel],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: left),
        const SizedBox(width: 48),
        Expanded(flex: 4, child: panel),
      ],
    );
  }
}

/// Diametro degli avatar degli amici da invitare.
const _friendAvatarSize = 32.0;

/// Larghezza minima del nome di un amico da invitare.
const _friendNameMin = 160.0;

/// Gli amici online, fuori da un watch party e non ancora nella sala, con
/// "Invita" (spec P §7.3). Un nuovo clic su "Invitato" rimanda l'invito.
class _InviteFriends extends ConsumerWidget {
  const _InviteFriends(
      {required this.state, required this.invited, required this.onInvite});

  final MatchState state;
  final Set<String> invited;
  final Future<void> Function(String userId) onInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final friends = ref.watch(friendsControllerProvider.select(
        (s) => s.snapshot.friends));
    final online = [
      for (final FriendEntry friend in sortFriends(friends))
        if (friend.online && friend.party == null && !state.hasMember(friend.userId))
          friend,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.matchFriendsOnline, style: _label),
        const SizedBox(height: 12),
        if (online.isEmpty) Text(l.matchNoFriendsOnline, style: _muted),
        for (final friend in online)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: WfColors.surface))),
            child: Row(
              children: [
                UserAvatar.lookup(
                    userId: friend.userId,
                    name: friend.name,
                    size: _friendAvatarSize),
                const SizedBox(width: 12),
                // "Invita" subito dopo il nome, non in fondo alla riga.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: _friendNameMin),
                    child: Text(friend.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 12),
                WfButton.secondary(
                  key: Key('match-invite-${friend.userId}'),
                  // Col dito si tocca su almeno 44: nello stretto è alto.
                  small: !FormFactor.of(context).compact,
                  icon: invited.contains(friend.userId)
                      ? LucideIcons.check
                      : LucideIcons.userPlus,
                  label: invited.contains(friend.userId)
                      ? l.matchInvited
                      : l.matchInviteFriend,
                  onPressed: () => unawaited(onInvite(friend.userId)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
