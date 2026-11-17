import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/social/inbox_models.dart';
import '../../core/social/social_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/bold_spans.dart';
import '../../ui/sender_avatar.dart';
import '../auth/session_controller.dart';
import '../inbox/inbox_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import 'invite_card_frame.dart';
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

/// La scheda d'invito: un gruppo appena nato o un invito di un amico.
class WatchPartyInvite {
  const WatchPartyInvite(this.group, {this.invitedBy});

  final GroupInfo group;

  /// Chi ci ha invitato (`PartyInvite`); `null` per un gruppo appena nato.
  final String? invitedBy;
}

/// Invito a un watch party appena nato (spec B §5.8): l'ultimo gruppo nuovo
/// comparso nell'elenco; la carta si chiude da sola. I gruppi della prima lettura dopo
/// il login non sono inviti, né quelli in cui siamo stati. Niente inviti
/// dentro un gruppo (o entrando), con il player aperto o senza il permesso
/// di entrare.
class WatchPartyInvites extends Notifier<WatchPartyInvite?> {
  /// Gruppi dell'ultima lettura; `null` prima della prima.
  Set<String>? _known;

  /// Gruppi in cui siamo entrati o che abbiamo creato: usciti noi, gli
  /// altri possono restarci, e la lettura dopo non deve proporli.
  final _visited = <String>{};

  @override
  WatchPartyInvite? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _known = null;
    _visited.clear();
    // Spec F §9.6: con la funzione `parties` le schede le annuncia il
    // plugin; senza, nascono dal confronto tra due letture dell'elenco.
    // Finché le funzioni non sono note niente: l'elenco di Jellyfin non è
    // filtrato per modalità.
    final (known, parties) = ref.watch(
        socialAvailabilityProvider.select((f) => (f.known, f.parties)));
    if (parties) {
      final subscription =
          ref.watch(socialEventsProvider).listen(_onSocialEvent);
      ref.onDispose(() => unawaited(subscription.cancel()));
    } else if (known) {
      ref.listen(watchPartyDirectoryProvider, (_, groups) => _onGroups(groups));
    }
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
    return null;
  }

  void dismiss() {
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
    _offer(WatchPartyInvite(fresh.last));
  }

  void _onSocialEvent(SocialEvent event) {
    final invite = switch (event) {
      PartyStartedEvent() =>
        WatchPartyInvite(_group(event.groupId, event.name, event.mode)),
      PartyInviteEvent() => WatchPartyInvite(
          _group(event.groupId, event.name, null),
          invitedBy: event.fromName),
      _ => null,
    };
    if (invite == null) return;
    // Il party nuovo (o quello in cui siamo invitati) entra subito
    // nell'elenco del chip.
    unawaited(ref.read(watchPartyDirectoryProvider.notifier).refresh());
    _offer(invite);
  }

  GroupInfo _group(String id, String name, PartyMode? mode) => GroupInfo(
        id: id,
        name: name,
        state: GroupState.idle,
        participants: const [],
        lastUpdatedAt: DateTime.utc(1970),
        mode: mode,
      );

  /// Mostra [invite], con le regole di sempre: non per i
  /// gruppi già visitati, non dentro un gruppo o entrando, non con il player
  /// aperto, non senza il permesso di entrare.
  void _offer(WatchPartyInvite invite) {
    if (_visited.contains(_normalizeId(invite.group.id))) return;
    if (!ref.read(syncPlayAccessProvider).canJoin ||
        ref.read(playerActiveProvider) ||
        ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
      return;
    }
    state = invite;
    ref.read(newestInviteProvider.notifier).set(InviteKind.party);
  }
}

final watchPartyInvitesProvider =
    NotifierProvider<WatchPartyInvites, WatchPartyInvite?>(
        WatchPartyInvites.new);

/// Scheda dell'invito, in alto a destra nella shell (spec §7.4).
class WatchPartyInviteCard extends ConsumerWidget {
  const WatchPartyInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invite = ref.watch(watchPartyInvitesProvider);
    return InviteCardSlot(
      id: invite?.group.id,
      card: invite == null ? null : _card(context, ref, invite),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, WatchPartyInvite invite) {
    final l = AppLocalizations.of(context);
    final invites = ref.read(watchPartyInvitesProvider.notifier);
    final names = partyNameParts(invite.group);
    final invitedBy = invite.invitedBy;
    final Widget leading;
    final InlineSpan sentence;
    final String? detail;
    if (invitedBy == null) {
      leading = SenderAvatar(name: names.host, badge: LucideIcons.users);
      sentence = boldSpans(l.watchPartyInviteTitle(names.host), [names.host]);
      detail = names.title;
    } else {
      final groupId = invite.group.id;
      // La locandina dall'invito nella cassetta, se c'è.
      final poster = ref.watch(inboxControllerProvider.select((s) {
        for (final entry in s.snapshot.entries) {
          if (entry is InviteEntry &&
              _normalizeId(entry.groupId) == _normalizeId(groupId)) {
            return entry.imageItemId;
          }
        }
        return null;
      }));
      final members = ref.watch(watchPartyDirectoryProvider.select((groups) =>
          listedGroup(groups, groupId)?.participants.length ?? 0));
      leading = SenderAvatar(
          name: invitedBy,
          posterItemId: poster,
          badge: poster == null ? LucideIcons.users : null);
      sentence = boldSpans(l.notifInviteTitle(invitedBy, names.title),
          [invitedBy, names.title]);
      detail = members > 0 ? l.partyMembers(members) : null;
    }
    return InviteCardFrame(
      key: const Key('watch-party-invite'),
      leading: leading,
      sentence: sentence,
      detail: detail,
      primaryLabel: l.watchPartyJoin,
      primaryIcon: LucideIcons.play,
      onPrimary: () {
        invites.dismiss();
        unawaited(joinWatchParty(context, ref, invite.group.id));
      },
      secondaryLabel: l.inviteLater,
      secondaryIcon: LucideIcons.clock,
      onSecondary: invites.dismiss,
      newest: ref.watch(newestInviteProvider) == InviteKind.party,
      onTimeout: invites.dismiss,
    );
  }
}
