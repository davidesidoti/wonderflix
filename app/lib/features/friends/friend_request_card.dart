import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import 'friend_request_notices.dart';
import 'friends_controller.dart';
import 'friends_panel.dart';

/// Diametro dell'avatar di chi chiede l'amicizia.
const _requestAvatarSize = 24.0;

/// Spazio tra l'avatar e il titolo; i pulsanti si allineano al titolo.
const _requestAvatarGap = 8.0;

/// Scheda "X vuole essere tuo amico" in alto a destra (spec F §8.4): entra
/// da destra e se ne va in dissolvenza, come l'invito ai watch party.
class FriendRequestCard extends ConsumerWidget {
  const FriendRequestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(friendRequestNoticesProvider);
    final current = request == null
        ? const SizedBox.shrink(key: ValueKey('no-friend-request'))
        : KeyedSubtree(
            key: ValueKey('request-${request.fromUserId}'),
            child: _card(context, ref, request));
    return AnimatedSwitcher(
      duration: WfMotion.of(context).duration(WfMotion.medium),
      transitionBuilder: (child, animation) => IgnorePointer(
        // La scheda che se ne va non accetta più clic.
        ignoring: child.key != current.key,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.3, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation, curve: WfMotion.emphasized)),
            child: child,
          ),
        ),
      ),
      child: current,
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

    return Material(
      key: const Key('friend-request-card'),
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
                  UserAvatar.lookup(
                    userId: request.fromUserId,
                    name: request.fromName,
                    size: _requestAvatarSize,
                    muted: true,
                  ),
                  const SizedBox(width: _requestAvatarGap),
                  Expanded(
                    child: Text(l.friendRequestTitle(request.fromName),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: l.watchPartyDismiss,
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: notices.dismiss,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(
                    left: _requestAvatarSize + _requestAvatarGap),
                // Wrap e non Row: con testi lunghi o ingranditi i due
                // pulsanti vanno a capo invece di uscire dalla scheda.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WfButton.primary(
                      label: l.friendsAccept,
                      icon: LucideIcons.userCheck,
                      onPressed: () =>
                          answer(() => friends.accept(request.fromUserId)),
                    ),
                    WfButton.secondary(
                      label: l.friendsDecline,
                      icon: LucideIcons.userX,
                      onPressed: () =>
                          answer(() => friends.decline(request.fromUserId)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
