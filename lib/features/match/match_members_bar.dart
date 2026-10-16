import 'package:flutter/material.dart';

import '../../core/social/match_models.dart';
import '../../ui/user_avatar.dart';

/// Diametro degli avatar dei membri.
const _avatarSize = 40.0;

/// I membri della sala con l'avatar e il nome, chi ha aperto per primo (spec
/// P §7.3). La votazione aggiunge i conteggi (piano 22c).
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
              ],
            ),
        ],
      );
}
