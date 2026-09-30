import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import 'watch_party_actions.dart';
import 'watch_party_directory.dart';
import 'watch_party_providers.dart';
import 'watch_party_session.dart';

/// Chi ha avviato il gruppo e cosa si guarda, dal nome "Davide · Dune" che
/// gli dà WonderFlix; altrimenti il primo membro e il nome intero.
({String host, String title}) partyNameParts(GroupInfo group) {
  final parts = group.name.split(' · ');
  if (parts.length >= 2) {
    return (host: parts.first, title: parts.sublist(1).join(' · '));
  }
  final host =
      group.participants.isEmpty ? group.name : group.participants.first;
  return (host: host, title: group.name);
}

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Invito a un watch party appena nato (spec B §5.8): l'ultimo gruppo nuovo
/// comparso nell'elenco, per [showFor]. I gruppi della prima lettura dopo
/// il login non sono inviti, né quelli in cui siamo stati. Niente inviti
/// dentro un gruppo (o entrando), con il player aperto o senza il permesso
/// di entrare.
class WatchPartyInvites extends Notifier<GroupInfo?> {
  static const showFor = Duration(seconds: 10);

  /// Gruppi dell'ultima lettura; `null` prima della prima.
  Set<String>? _known;

  /// Gruppi in cui siamo entrati o che abbiamo creato: usciti noi, gli
  /// altri possono restarci, e la lettura dopo non deve proporli.
  final _visited = <String>{};
  Timer? _timer;

  @override
  GroupInfo? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _known = null;
    _visited.clear();
    _timer = null;
    ref.listen(watchPartyDirectoryProvider, (_, groups) => _onGroups(groups));
    ref.listen(playerActiveProvider, (_, active) {
      if (active) dismiss();
    });
    ref.listen(watchPartySessionProvider.select((s) => s.group?.id),
        (_, groupId) {
      if (groupId != null) _visited.add(_normalizeId(groupId));
    }, fireImmediately: true);
    ref.listen(watchPartySessionProvider.select((s) => s.phase), (_, phase) {
      if (phase != WatchPartyPhase.none) dismiss();
    });
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = null;
  }

  void _onGroups(List<GroupInfo> groups) {
    final known = _known;
    _known = {for (final group in groups) group.id};
    if (known == null) return;
    final fresh = [
      for (final group in groups)
        if (!known.contains(group.id) &&
            !_visited.contains(_normalizeId(group.id)))
          group,
    ];
    if (fresh.isEmpty) return;
    if (!ref.read(syncPlayAccessProvider).canJoin ||
        ref.read(playerActiveProvider) ||
        ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
      return;
    }
    _timer?.cancel();
    state = fresh.last;
    _timer = Timer(showFor, dismiss);
  }
}

final watchPartyInvitesProvider =
    NotifierProvider<WatchPartyInvites, GroupInfo?>(WatchPartyInvites.new);

/// Scheda dell'invito, in alto a destra nella shell.
class WatchPartyInviteCard extends ConsumerWidget {
  const WatchPartyInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(watchPartyInvitesProvider);
    if (group == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final names = partyNameParts(group);
    final invites = ref.read(watchPartyInvitesProvider.notifier);
    return Material(
      key: const Key('watch-party-invite'),
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.users, size: 18, color: WfColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.watchPartyInviteTitle(names.host),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: l.watchPartyDismiss,
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: invites.dismiss,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, right: 8),
                child: Text(names.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: WfColors.creamMuted)),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: WfButton.primary(
                  label: l.watchPartyJoin,
                  icon: LucideIcons.play,
                  onPressed: () {
                    invites.dismiss();
                    unawaited(joinWatchParty(context, ref, group.id));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
