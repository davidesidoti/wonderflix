import 'dart:async';

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

/// Attesa massima della lista fresca degli amici: poi vale quella che l'app
/// ha già (il menu non deve farsi aspettare).
const inviteFriendsTimeout = Duration(seconds: 2);

/// "Invita amici" in corso, per app (container): un secondo clic mentre si
/// legge la lista o il menu è aperto non ne apre un altro sopra.
final _inviting = Expando<bool>('inviting');

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
/// chiude senza scegliere, se un altro "Invita amici" è già in corso o se
/// intanto è cambiato qualcosa (pagina, menu sopra, gruppo).
Future<InviteResult?> showInviteFriendsMenu(
    BuildContext anchor, WidgetRef ref) async {
  final container = ProviderScope.containerOf(anchor, listen: false);
  if (_inviting[container] ?? false) return null;
  _inviting[container] = true;
  try {
    return await _inviteFriends(anchor, ref, container);
  } finally {
    _inviting[container] = null;
  }
}

Future<InviteResult?> _inviteFriends(
    BuildContext anchor, WidgetRef ref, ProviderContainer container) async {
  final l = AppLocalizations.of(anchor);
  final groupId = ref.read(watchPartySessionProvider).group?.id;
  if (groupId == null) return null;
  // Lista fresca dal plugin: chi è online e chi è già dentro cambiano
  // spesso. Non con `FriendsController.reload`: un controller appena
  // (ri)costruito rilegge da sé e scarta la nostra risposta, e l'attesa
  // finirebbe con la lista vuota. Se la richiesta non riesce, o ci mette
  // più di [inviteFriendsTimeout], quella che l'app ha già.
  FriendsSnapshot? fresh;
  try {
    fresh = await ref
        .read(socialApiProvider)
        .friends()
        .timeout(inviteFriendsTimeout);
  } on SocialException catch (error) {
    _log.info('amici da invitare non riletti: ${error.failure.name}');
  } on TimeoutException {
    _log.info('amici da invitare non riletti: nessuna risposta in tempo');
  }
  // Nel frattempo il widget si è chiuso, sopra c'è un'altra pagina o un
  // menu, o siamo in un altro gruppo: niente menu.
  if (!anchor.mounted ||
      !(ModalRoute.of(anchor)?.isCurrent ?? true) ||
      ref.read(watchPartySessionProvider).group?.id != groupId) {
    return null;
  }
  final List<FriendEntry> all;
  var unavailable = false;
  if (fresh != null) {
    all = fresh.friends;
  } else {
    // Solo qui: leggere il controller lo costruisce (e rilegge).
    final known = ref.read(friendsControllerProvider);
    all = known.snapshot.friends;
    // Né la lista fresca né una già letta: non si sa chi invitare.
    unavailable = !known.loaded;
  }
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
    items: unavailable || friends.isEmpty
        ? [
            PopupMenuItem<String>(
                enabled: false,
                child: Text(unavailable
                    ? l.friendsUnavailable
                    : l.partyNoFriendsToInvite)),
          ]
        : [
            for (final friend in friends)
              PopupMenuItem<String>(
                key: ValueKey('invite-${friend.userId}'),
                value: friend.userId,
                enabled: !invited.contains(friend.userId),
                child: Row(
                  children: [
                    MemberAvatar(name: friend.name, userId: friend.userId),
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
  // Usciti dal gruppo a menu aperto: niente invito.
  if (ref.read(watchPartySessionProvider).group?.id != groupId) return null;
  final name = friends.firstWhere((friend) => friend.userId == picked).name;
  // Il widget di [ref] può chiudersi durante la richiesta (es. il player che
  // esce): dopo l'attesa si usa il container.
  try {
    await container.read(socialApiProvider).invite(groupId, [picked]);
    container.read(currentPartyProvider.notifier).invited(groupId, picked);
    return InviteResult(name);
  } on SocialException catch (error) {
    return InviteResult(name, failure: error.failure);
  }
}
