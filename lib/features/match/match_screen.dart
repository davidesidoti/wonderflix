import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/match_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../friends/friends_controller.dart';
import '../friends/friends_panel.dart';
import '../library/library_providers.dart';
import '../profiles/profile_preferences.dart';
import '../tonight/tonight_controller.dart';
import '../tonight/tonight_filters_bar.dart';
import '../tonight/tonight_logic.dart';
import 'match_actions.dart';
import 'match_members_bar.dart';
import 'match_room_controller.dart';

const _muted = TextStyle(color: WfColors.creamMuted);

/// La sala del match (spec P §7.3). In questo piano l'attesa; la votazione
/// arriva nel piano 22c. Lasciare la pagina fa uscire dalla sala.
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

  @override
  void initState() {
    super.initState();
    _controller = ref.read(matchRoomProvider.notifier);
    _filters = readTonightFilters(ref.read(profilePreferencesProvider));
  }

  @override
  void dispose() {
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
    final notice = ours &&
        view!.state?.closedReason != MatchClosedReason.partyStarted;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (notice) {
        messenger?.showSnackBar(SnackBar(content: Text(l.matchClosed)));
      }
      final router = GoRouter.of(context);
      if (router.canPop()) router.pop();
    });
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
    ref.listen(matchRoomProvider, (_, view) => _onRoom(view));
    final view = ref.watch(matchRoomProvider);
    final state = _isThisRoom(view) ? view!.state : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Text(l.matchTitle.toUpperCase(), style: WfText.display(40)),
        ),
        Expanded(
          child: state == null
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  children: [
                    MatchMembersBar(state: state),
                    const SizedBox(height: 32),
                    if (state.phase == MatchPhase.waiting) _waiting(l, state),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _waiting(AppLocalizations l, MatchState state) {
    if (!state.isCreator(ref.watch(currentUserIdProvider))) {
      return Text(l.matchWaitingFor(state.creatorName),
          style: _muted.copyWith(fontSize: 16));
    }
    final enough = state.members.length >= matchMinMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TonightFiltersBar(filters: _filters, onChanged: _setFilters),
        const SizedBox(height: 32),
        _InviteFriends(state: state, invited: _invited, onInvite: _invite),
        const SizedBox(height: 32),
        Row(
          children: [
            WfButton.primary(
              key: const Key('match-start'),
              label: l.matchStart,
              icon: LucideIcons.play,
              onPressed: enough && !_starting ? () => unawaited(_start()) : null,
            ),
            if (!enough) ...[
              const SizedBox(width: 16),
              Flexible(child: Text(l.matchNeedFriend, style: _muted)),
            ],
          ],
        ),
      ],
    );
  }
}

/// Diametro degli avatar degli amici da invitare.
const _friendAvatarSize = 32.0;

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
        Text(l.matchFriendsOnline,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (online.isEmpty) Text(l.matchNoFriendsOnline, style: _muted),
        for (final friend in online)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                UserAvatar.lookup(
                    userId: friend.userId,
                    name: friend.name,
                    size: _friendAvatarSize),
                const SizedBox(width: 12),
                Expanded(child: Text(friend.name)),
                TextButton(
                  key: Key('match-invite-${friend.userId}'),
                  onPressed: () => unawaited(onInvite(friend.userId)),
                  style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                  child: Text(invited.contains(friend.userId)
                      ? l.matchInvited
                      : l.matchInviteFriend),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
