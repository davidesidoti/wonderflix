import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../friends/friends_controller.dart';
import '../friends/friends_panel.dart' show sortFriends;
import '../social/social_providers.dart';
import 'current_party.dart';
import 'party_badge.dart' show MemberAvatar;
import 'watch_party_session.dart';

final _log = Logger('social');

/// Esito di "Invita amici".
class InviteResult {
  const InviteResult(this.name, {this.failure});

  /// Chi abbiamo invitato.
  final String name;

  /// `null` se l'invito è partito.
  final SocialFailure? failure;
}

/// "Invita amici" (spec F §9.5): menu ancorato a [anchor] con gli amici non
/// ancora nel party, online prima; un clic manda l'invito. `null` se si
/// chiude senza scegliere.
Future<InviteResult?> showInviteFriendsMenu(
    BuildContext anchor, WidgetRef ref) async {
  final l = AppLocalizations.of(anchor);
  final groupId = ref.read(watchPartySessionProvider).group?.id;
  if (groupId == null) return null;
  // Lista fresca dal plugin: chi è online e chi è già dentro cambiano
  // spesso. Non con `FriendsController.reload`: un controller appena
  // (ri)costruito rilegge da sé e scarta la nostra risposta, e l'attesa
  // finirebbe con la lista vuota. Se la richiesta non riesce, quella che
  // l'app ha già.
  FriendsSnapshot? fresh;
  try {
    fresh = await ref.read(socialApiProvider).friends();
  } on SocialException catch (error) {
    _log.info('amici da invitare non riletti: ${error.failure.name}');
  }
  if (!anchor.mounted) return null;
  final all =
      fresh?.friends ?? ref.read(friendsControllerProvider).snapshot.friends;
  final members = {
    for (final member in ref.read(watchPartySessionProvider).members)
      member.toLowerCase(),
  };
  final friends = sortFriends(all)
      .where((friend) => !members.contains(friend.name.toLowerCase()))
      .toList();
  final invited = ref.read(currentPartyProvider)?.invited ?? const <String>{};
  final picked = await showMenu<String>(
    context: anchor,
    position: menuPositionBelow(anchor),
    popUpAnimationStyle: wfPopUpAnimation(anchor),
    items: friends.isEmpty
        ? [
            PopupMenuItem<String>(
                enabled: false, child: Text(l.partyNoFriendsToInvite)),
          ]
        : [
            for (final friend in friends)
              PopupMenuItem<String>(
                key: ValueKey('invite-${friend.userId}'),
                value: friend.userId,
                enabled: !invited.contains(friend.userId),
                child: Row(
                  children: [
                    MemberAvatar(name: friend.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(friend.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: friend.online
                                  ? WfColors.cream
                                  : WfColors.creamMuted)),
                    ),
                    if (invited.contains(friend.userId)) ...[
                      const Icon(LucideIcons.check,
                          size: 16, color: WfColors.gold),
                      const SizedBox(width: 4),
                      Text(l.partyInvited,
                          style: const TextStyle(
                              color: WfColors.creamMuted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
          ],
  );
  if (picked == null || !anchor.mounted) return null;
  final name = friends.firstWhere((friend) => friend.userId == picked).name;
  // Il widget di [ref] può chiudersi durante la richiesta (es. il player che
  // esce): dopo l'attesa si usa il container.
  final container = ProviderScope.containerOf(anchor, listen: false);
  try {
    await container.read(socialApiProvider).invite(groupId, [picked]);
    container.read(currentPartyProvider.notifier).invited(picked);
    return InviteResult(name);
  } on SocialException catch (error) {
    return InviteResult(name, failure: error.failure);
  }
}
