import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'watch_party_session.dart';

/// Etichetta con bordo oro e icona del gruppo (barra in alto e player).
class PartyChip extends StatelessWidget {
  const PartyChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: WfColors.gold),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.users, size: 16, color: WfColors.gold),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: WfColors.gold, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Iniziale di un membro: il server dà solo i nomi utente.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 13,
        backgroundColor: WfColors.surfaceHigh,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
                color: WfColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );
}

/// "Watch party · N" nei controlli del player: apre i membri ed "Esci dal
/// watch party".
class PartyBadge extends ConsumerWidget {
  const PartyBadge({super.key, required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final party = ref.watch(watchPartySessionProvider);
    final members = party.members;
    return PopupMenuButton<String>(
      key: const Key('party-badge'),
      tooltip: party.group?.name,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'leave') onLeave();
      },
      itemBuilder: (context) => [
        for (final member in members)
          PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                MemberAvatar(name: member),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(member,
                      style: const TextStyle(color: WfColors.cream)),
                ),
              ],
            ),
          ),
        if (members.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'leave',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.error),
              const SizedBox(width: 12),
              Flexible(child: Text(l.watchPartyLeave)),
            ],
          ),
        ),
      ],
      child: PartyChip(label: l.watchPartyButton(members.length)),
    );
  }
}
