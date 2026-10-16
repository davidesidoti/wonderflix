import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import '../watch_party/invite_card_frame.dart';
import '../watch_party/watch_party_invites.dart';
import '../watch_party/watch_party_session.dart';
import 'match_actions.dart';
import 'match_room_controller.dart';

/// Invito a una sala del match appena arrivato (spec P §7.2): per
/// [showFor]; non con il player aperto né stando già in una sala. Si vede un
/// invito alla volta (piano 22b, decisione 6).
class MatchInvites extends Notifier<MatchInviteEvent?> {
  static const showFor = Duration(seconds: 10);

  Timer? _timer;

  @override
  MatchInviteEvent? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _timer?.cancel();
    _timer = null;
    ref.onDispose(() => _timer?.cancel());
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
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = null;
  }

  void _show(MatchInviteEvent event) {
    if (ref.read(playerActiveProvider)) return;
    final room = ref.read(matchRoomProvider);
    if (room != null && !room.closed) return;
    // Dentro un watch party (o mentre ci si entra) l'invito non si mostra.
    if (ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) return;
    ref.read(watchPartyInvitesProvider.notifier).dismiss();
    _timer?.cancel();
    state = event;
    _timer = Timer(showFor, dismiss);
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
              icon: LucideIcons.heartHandshake,
              title: l.matchInviteFrom(invite.fromName),
              onDismiss: invites.dismiss,
              onJoin: () {
                invites.dismiss();
                unawaited(joinMatchRoom(context, ref, invite.roomId));
              },
            ),
    );
  }
}
