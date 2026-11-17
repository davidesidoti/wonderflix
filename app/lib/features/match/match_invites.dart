import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/bold_spans.dart';
import '../../ui/sender_avatar.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import '../watch_party/invite_card_frame.dart';
import '../watch_party/watch_party_invites.dart';
import '../watch_party/watch_party_session.dart';
import 'match_actions.dart';
import 'match_room_controller.dart';

/// Invito a una sala del match appena arrivato (spec P §7.2), finché la
/// carta non si chiude; non con il player aperto né stando già in una sala.
/// Si vede un invito alla volta (piano 22b, decisione 6).
class MatchInvites extends Notifier<MatchInviteEvent?> {
  @override
  MatchInviteEvent? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.match))) {
      return null;
    }
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is MatchInviteEvent) _show(event);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    ref.listen(playerActiveProvider, (_, active) {
      if (active) dismiss();
    });
    // Un invito al party arrivato dopo prende il posto di questo.
    ref.listen(watchPartyInvitesProvider, (_, invite) {
      if (invite != null) dismiss();
    });
    return null;
  }

  void dismiss() {
    if (ref.mounted) state = null;
  }

  void _show(MatchInviteEvent event) {
    if (ref.read(playerActiveProvider)) return;
    final room = ref.read(matchRoomProvider);
    if (room != null && !room.closed) return;
    // Dentro un watch party (o mentre ci si entra) l'invito non si mostra.
    if (ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) return;
    ref.read(watchPartyInvitesProvider.notifier).dismiss();
    state = event;
    ref.read(newestInviteProvider.notifier).set(InviteKind.match);
  }
}

final matchInvitesProvider =
    NotifierProvider<MatchInvites, MatchInviteEvent?>(MatchInvites.new);

/// La carta dell'invito al match, nello stesso posto di quella del party.
class MatchInviteCard extends ConsumerWidget {
  const MatchInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final invite = ref.watch(matchInvitesProvider);
    final invites = ref.read(matchInvitesProvider.notifier);
    return InviteCardSlot(
      id: invite?.roomId,
      card: invite == null
          ? null
          : InviteCardFrame(
              key: const Key('match-invite'),
              leading: SenderAvatar(
                  name: invite.fromName, badge: LucideIcons.heartHandshake),
              sentence: boldSpans(
                  l.notifMatchInviteTitle(invite.fromName), [invite.fromName]),
              primaryLabel: l.watchPartyJoin,
              primaryIcon: LucideIcons.play,
              onPrimary: () {
                invites.dismiss();
                unawaited(joinMatchRoom(context, ref, invite.roomId));
              },
              secondaryLabel: l.inviteLater,
              secondaryIcon: LucideIcons.clock,
              onSecondary: invites.dismiss,
              newest: ref.watch(newestInviteProvider) == InviteKind.match,
              onTimeout: invites.dismiss,
            ),
    );
  }
}
