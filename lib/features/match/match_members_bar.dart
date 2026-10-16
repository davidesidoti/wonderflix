import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/match_models.dart';
import '../../ui/user_avatar.dart';

/// Diametro degli avatar dei membri.
const _avatarSize = 40.0;

/// I membri della sala con l'avatar e il nome, chi ha aperto per primo (spec
/// P §7.3). In votazione accanto al nome "votati/pila", con ✓ a pila finita.
class MatchMembersBar extends StatelessWidget {
  const MatchMembersBar({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          for (final member in state.members)
            Row(
              key: ValueKey('match-member-${member.userId}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar.lookup(
                    userId: member.userId, name: member.name, size: _avatarSize),
                const SizedBox(width: 8),
                Text(member.name),
                if (state.phase == MatchPhase.voting) ...[
                  const SizedBox(width: 8),
                  Text('${member.voted}/${state.stack.length}',
                      style: const TextStyle(color: WfColors.creamMuted)),
                  if (state.stack.isNotEmpty && member.voted >= state.stack.length)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(LucideIcons.check,
                          size: 16, color: WfColors.gold),
                    ),
                ],
              ],
            ),
        ],
      );
}
