import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import 'party_badge.dart';
import 'party_channel.dart';
import 'party_mode_labels.dart';
import 'watch_party_actions.dart';
import 'watch_party_directory.dart';
import 'watch_party_providers.dart';
import 'watch_party_routing.dart';
import 'watch_party_session.dart';

/// Pulsante del watch party nella barra in alto. Fuori da un gruppo:
/// "Watch party · N", solo se esiste almeno un gruppo, apre l'elenco con
/// "Unisciti". Dentro un gruppo: "Nel watch party" con "Torna al player" ed
/// "Esci dal watch party".
class WatchPartyButton extends ConsumerWidget {
  const WatchPartyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(syncPlayAccessProvider).canJoin) {
      return const SizedBox.shrink();
    }
    if (ref.watch(watchPartySessionProvider.select((s) => s.inGroup))) {
      return const _InPartyButton();
    }
    final groups = ref.watch(watchPartyDirectoryProvider);
    if (groups.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const Key('watch-party-button'),
      tooltip: l.watchPartyListTitle,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: wfPopUpAnimation(context),
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
                Row(
                  children: [
                    if (group.mode != null) ...[
                      Icon(partyModeIcon(group.mode!),
                          size: 14, color: WfColors.creamMuted),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
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

/// Stando in un gruppo (spec B §7.1): tornare al player o uscire.
class _InPartyButton extends ConsumerWidget {
  const _InPartyButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final party = ref.watch(watchPartySessionProvider);
    final playing = party.queue?.playing;
    // Messaggi arrivati fuori dal player (spec E §9.5).
    final unread = ref.watch(partyChannelProvider.select((s) => s.unread));
    return PopupMenuButton<String>(
      key: const Key('watch-party-in-party'),
      tooltip: party.group?.name,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: wfPopUpAnimation(context),
      onSelected: (value) {
        final session = ref.read(watchPartySessionProvider.notifier);
        switch (value) {
          case 'back':
            final entry = ref.read(watchPartySessionProvider).queue?.playing;
            if (entry == null) return;
            ref.read(partyNavigatorProvider).open(playerRoute(entry.itemId,
                start: session.estimatedPosition(),
                party: entry.playlistItemId));
          case 'leave':
            unawaited(session.leave());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'back',
          enabled: playing != null,
          child: Row(
            children: [
              const Icon(LucideIcons.play, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Flexible(
                child: Text(l.watchPartyBackToPlayer,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'leave',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.error),
              const SizedBox(width: 12),
              Flexible(
                child: Text(l.watchPartyLeave,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ],
      child: PartyChip(label: l.watchPartyInParty, count: unread),
    );
  }
}
