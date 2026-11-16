import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/social/match_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';

/// Posti della sala: il massimo del plugin (`MatchRoom.MaxMembers`).
const matchMaxMembers = 8;

const _seatWidth = 68.0;
const _chairWidth = 56.0;
const _chairHeight = 62.0;
const _barHeight = 6.0;
const _avatarSize = 36.0;
final _chairRadius = BorderRadius.vertical(
    top: Radius.circular(14), bottom: Radius.circular(6));

/// I posti della sala (spec §5.2). In attesa: tutti gli 8, i liberi
/// tratteggiati, con "In sala, n su 8" sopra. In votazione: solo gli occupati,
/// con una barra e "12 su 30" (o "finito") sotto.
///
/// [votedOf] dà i voti di un membro: chi guarda passa il proprio conteggio
/// ottimistico, che precede quello del server.
class MatchSeats extends StatelessWidget {
  const MatchSeats(
      {super.key, required this.state, this.votedOf = _serverVoted});

  final MatchState state;
  final int Function(MatchMember) votedOf;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final voting = state.phase == MatchPhase.voting;
    final free = voting ? 0 : matchMaxMembers - state.members.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!voting) ...[
          Text(l.matchSeatsCount(state.members.length, matchMaxMembers),
              style: const TextStyle(
                  color: WfColors.creamMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final member in state.members)
              _Seat(
                  key: ValueKey('match-seat-${member.userId}'),
                  member: member,
                  voted: votedOf(member),
                  total: voting ? state.stack.length : null),
            for (var i = 0; i < free; i++)
              _Seat(key: ValueKey('match-seat-free-$i')),
          ],
        ),
      ],
    );
  }
}

int _serverVoted(MatchMember m) => m.voted;

class _Seat extends StatelessWidget {
  const _Seat({super.key, this.member, this.voted = 0, this.total});

  /// `null`: posto libero.
  final MatchMember? member;

  final int voted;

  /// Pila intera, solo in votazione.
  final int? total;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final member = this.member;
    final total = this.total;
    final taken = member != null;
    final color = taken ? WfColors.gold : WfColors.border;
    final done = taken && total != null && total > 0 && voted >= total;
    return SizedBox(
      width: _seatWidth,
      child: Column(
        children: [
          SizedBox(
            width: _chairWidth,
            height: _chairHeight + _barHeight,
            child: Stack(
              children: [
                SizedBox(
                  width: _chairWidth,
                  height: _chairHeight,
                  child: taken
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: _chairRadius,
                            color: WfColors.gold.withValues(alpha: 0.08),
                            border: Border.all(color: color, width: 2),
                          ),
                          child: Center(
                              child: UserAvatar.lookup(
                                  userId: member.userId,
                                  name: member.name,
                                  size: _avatarSize)),
                        )
                      : const CustomPaint(painter: _DashedChairPainter()),
                ),
                // La barretta sotto la seduta.
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 0,
                  height: _barHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius:
                          const BorderRadius.vertical(bottom: Radius.circular(4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(taken ? member.name : l.matchSeatFree,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: taken ? WfColors.cream : WfColors.creamMuted,
                  fontSize: 11.5)),
          if (taken && total != null) ...[
            Container(
              key: ValueKey('match-seat-bar-${member.userId}'),
              height: 3,
              margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                  color: WfColors.border, borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: ValueKey('match-seat-fill-${member.userId}'),
                widthFactor: total == 0 ? 0 : (voted / total).clamp(0, 1),
                child: const ColoredBox(color: WfColors.gold),
              ),
            ),
            const SizedBox(height: 2),
            Text(done ? l.matchDone : l.matchVotedOf(voted, total),
                maxLines: 1,
                style: TextStyle(
                    color: done ? WfColors.gold : WfColors.creamMuted,
                    fontSize: 11.5,
                    fontFeatures: const [ui.FontFeature.tabularFigures()])),
          ],
        ],
      ),
    );
  }
}

/// Il bordo tratteggiato della poltrona libera (dash 4, vuoto 3, spessore 2).
class _DashedChairPainter extends CustomPainter {
  const _DashedChairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(_chairRadius
          .toRRect(Offset.zero & size)
          .deflate(1)); // il tratto è largo 2, centrato sul bordo
    final paint = Paint()
      ..color = WfColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedChairPainter old) => false;
}
