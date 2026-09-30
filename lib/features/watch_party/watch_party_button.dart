import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'party_badge.dart';
import 'watch_party_actions.dart';
import 'watch_party_directory.dart';
import 'watch_party_providers.dart';

/// "Watch party · N" nella barra in alto: compare solo se esiste almeno un
/// gruppo e apre l'elenco con "Unisciti".
class WatchPartyButton extends ConsumerWidget {
  const WatchPartyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(syncPlayAccessProvider).canJoin) {
      return const SizedBox.shrink();
    }
    final groups = ref.watch(watchPartyDirectoryProvider);
    if (groups.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const Key('watch-party-button'),
      tooltip: l.watchPartyListTitle,
      position: PopupMenuPosition.under,
      onOpened: () =>
          unawaited(ref.read(watchPartyDirectoryProvider.notifier).refresh()),
      onSelected: (groupId) => unawaited(joinWatchParty(context, ref, groupId)),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(l.watchPartyListTitle.toUpperCase(),
              style: const TextStyle(
                  color: WfColors.creamMuted,
                  fontSize: 12,
                  letterSpacing: 1)),
        ),
        for (final group in groups)
          PopupMenuItem<String>(
            value: group.id,
            height: 64,
            child: _GroupTile(group: group),
          ),
      ],
      child: PartyChip(label: l.watchPartyButton(groups.length)),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final GroupInfo group;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12);
    return SizedBox(
      width: 320,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    '${l.watchPartyMembers(group.participants.length)} · '
                    '${groupStateLabel(l, group.state)}',
                    style: muted),
                if (group.participants.isNotEmpty)
                  Text(group.participants.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(l.watchPartyJoin,
              style: const TextStyle(
                  color: WfColors.gold, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
