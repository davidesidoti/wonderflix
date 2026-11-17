import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/bold_spans.dart';
import '../../ui/sender_avatar.dart';
import '../watch_party/invite_card_frame.dart';
import 'friend_request_notices.dart';
import 'friends_controller.dart';
import 'friends_panel.dart';

/// Scheda "X vuole essere tuo amico" in alto a destra (spec F §8.4), con la
/// forma e il posto delle carte d'invito.
class FriendRequestCard extends ConsumerWidget {
  const FriendRequestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(friendRequestNoticesProvider);
    return InviteCardSlot(
      id: request == null ? null : 'request-${request.fromUserId}',
      card: request == null ? null : _card(context, ref, request),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, FriendRequestEvent request) {
    final l = AppLocalizations.of(context);
    final notices = ref.read(friendRequestNoticesProvider.notifier);
    final friends = ref.read(friendsControllerProvider.notifier);
    void answer(Future<SocialFailure?> Function() action) {
      notices.dismiss();
      unawaited(runFriendAction(context, action));
    }

    return InviteCardFrame(
      key: const Key('friend-request-card'),
      leading: SenderAvatar(
          name: request.fromName,
          userId: request.fromUserId,
          badge: LucideIcons.userPlus),
      sentence: boldSpans(
          l.friendRequestTitle(request.fromName), [request.fromName]),
      primaryLabel: l.friendsAccept,
      primaryIcon: LucideIcons.userCheck,
      onPrimary: () => answer(() => friends.accept(request.fromUserId)),
      secondaryLabel: l.friendsDecline,
      secondaryIcon: LucideIcons.userX,
      onSecondary: () => answer(() => friends.decline(request.fromUserId)),
      newest: ref.watch(newestInviteProvider) == InviteKind.friend,
      onTimeout: notices.dismiss,
    );
  }
}
