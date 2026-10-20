import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/rating_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../player/player_side_panel_host.dart';
import '../player/post_play.dart';
import 'rating_round_controller.dart';
import 'rating_widgets.dart';

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);

/// Quanto salgono le righe dei risultati entrando.
const _revealRise = 12.0;

/// Il pannello del voto di fine party (spec Q §7): lo stesso nel post-play e
/// nel pannello a lato del player.
class RatingRoundPanel extends ConsumerStatefulWidget {
  const RatingRoundPanel({super.key, required this.onClose, this.commentFocusNode});

  final VoidCallback onClose;
  final FocusNode? commentFocusNode;

  @override
  ConsumerState<RatingRoundPanel> createState() => _RatingRoundPanelState();
}

class _RatingRoundPanelState extends ConsumerState<RatingRoundPanel> {
  late final TextEditingController _comment;

  @override
  void initState() {
    super.initState();
    _comment = TextEditingController(
        text: ref.read(ratingRoundProvider)?.round.mine?.comment ?? '');
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  RatingRoundController get _controller =>
      ref.read(ratingRoundProvider.notifier);

  void _vote() => unawaited(_controller.vote(_comment.text));

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(ratingRoundProvider);
    if (view == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final source = view.source;
    final title = source == null ? null : ratingTitle(l, source);
    final revealed = !view.unavailable && view.round.phase == RatingPhase.revealed;
    final header = revealed
        ? (title ?? l.ratingPartyPill)
        : [l.ratingYourVote, ?title].join(' · ');
    // La rotella sul pannello non arriva al volume del player.
    return PanelWheelBarrier(
      child: Material(
        key: const Key('rating-panel'),
        color: WfColors.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(postPlayRadius)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(header,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: l.friendsClose,
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: view.unavailable
                    ? Text(l.ratingRoundUnavailable, style: _mutedStyle)
                    : revealed
                        ? _revealed(context, l, view)
                        : _voting(l, view),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voting(AppLocalizations l, RatingRoundView view) {
    final round = view.round;
    final canVote = view.draft != null && !view.sending;
    final score = round.mine?.score ?? view.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.showsPicker) ...[
          RatingScorePicker(
            selected: view.draft,
            enabled: !view.sending,
            onSelect: _controller.select,
          ),
          const SizedBox(height: 12),
          RatingCommentField(
            controller: _comment,
            focusNode: widget.commentFocusNode,
            onSubmitted: canVote ? _vote : null,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              WfButton.secondary(
                label: l.ratingSkip,
                icon: LucideIcons.skipForward,
                onPressed:
                    view.sending ? null : () => unawaited(_controller.skip()),
              ),
              WfButton.primary(
                label: l.ratingVote,
                icon: LucideIcons.check,
                onPressed: canVote ? _vote : null,
              ),
            ],
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: Text(
                  view.myStatus == RatingVoterStatus.skipped
                      ? l.ratingYouSkipped
                      : l.ratingVoted(score ?? 0),
                  style: const TextStyle(
                      color: WfColors.gold, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _controller.edit,
                style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                child: Text(l.ratingChange),
              ),
            ],
          ),
        if (view.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              view.error == RatingSendError.tooMany
                  ? l.ratingTooMany
                  : l.ratingNotSaved,
              style: const TextStyle(color: WfColors.error, fontSize: 13),
            ),
          ),
        const SizedBox(height: 16),
        Text(l.ratingVotedCount(round.votedCount, round.voters.length),
            style: _mutedStyle),
        const SizedBox(height: 8),
        for (final voter in round.voters) _VoterRow(voter: voter),
        const SizedBox(height: 8),
        _TimeLeft(endsAt: round.endsAt),
        if (round.canReveal) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: WfButton.secondary(
              label: l.ratingReveal,
              icon: LucideIcons.eye,
              onPressed:
                  view.sending ? null : () => unawaited(_controller.reveal()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _revealed(BuildContext context, AppLocalizations l, RatingRoundView view) {
    final round = view.round;
    final average = round.average;
    final motion = WfMotion.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (average != null)
          Text(
            formatRatingAverage(
                average, Localizations.localeOf(context).toString()),
            textAlign: TextAlign.center,
            style: WfText.display(56, color: WfColors.gold),
          ),
        Text(l.ratingPartyAverage(round.results.length),
            textAlign: TextAlign.center, style: _mutedStyle),
        const SizedBox(height: 16),
        for (final result in round.results) _ResultRow(result: result, view: view),
        const SizedBox(height: 8),
        Text(l.ratingChangeLater, style: _mutedStyle),
      ],
    );
    // Tutte le righe entrano insieme; con le animazioni ridotte sono già lì.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: motion.isReduced ? 1 : 0, end: 1),
      duration: motion.duration(WfMotion.medium),
      curve: WfMotion.emphasized,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
            offset: Offset(0, _revealRise * (1 - t)), child: child),
      ),
      child: body,
    );
  }
}

class _VoterRow extends StatelessWidget {
  const _VoterRow({required this.voter});

  final RatingVoter voter;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          UserAvatar.lookup(userId: voter.userId, name: voter.name, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(voter.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          switch (voter.status) {
            RatingVoterStatus.voted => Icon(LucideIcons.check,
                key: Key('rating-voter-done-${voter.userId}'),
                size: 18,
                color: WfColors.gold),
            RatingVoterStatus.skipped =>
              Text(l.ratingSkipped, style: _mutedStyle),
            RatingVoterStatus.waiting => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.view});

  final RatingResult result;
  final RatingRoundView view;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mine = jellyfinIdKey(result.userId) == jellyfinIdKey(view.userId);
    final comment = result.comment;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar.lookup(userId: result.userId, name: result.name, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mine ? l.ratingYou : result.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                // Sempre testo semplice, mai interpretato.
                if (comment != null) Text(comment, style: _mutedStyle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${result.score}',
              style: const TextStyle(
                  color: WfColors.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// "Ancora m:ss", aggiornato ogni secondo.
class _TimeLeft extends StatefulWidget {
  const _TimeLeft({required this.endsAt});

  final DateTime endsAt;

  @override
  State<_TimeLeft> createState() => _TimeLeftState();
}

class _TimeLeftState extends State<_TimeLeft> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // shortcut: orologio del PC, non quello del server; da cambiare se gli
    // scarti danno fastidio.
    _tick = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(clock.now());
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final time = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Text(AppLocalizations.of(context).ratingTimeLeft(time),
        style: _mutedStyle);
  }
}

/// La pillola "Voti del party" / "Voti scoperti": apre il pannello a lato.
class RatingRoundPill extends StatelessWidget {
  const RatingRoundPill({super.key, required this.phase, required this.onTap});

  final RatingPhase phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      key: const Key('rating-pill'),
      color: WfColors.surfaceHigh.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: WfColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.star, size: 18, color: WfColors.gold),
              const SizedBox(width: 8),
              Text(
                phase == RatingPhase.voting
                    ? l.ratingPartyPill
                    : l.ratingRevealedPill,
                maxLines: 1,
                style: const TextStyle(color: WfColors.cream),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
