import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/social/activity_models.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_actions.dart';
import 'friends_controller.dart';

/// "Guarda insieme" con un amico che sta guardando (spec O §7.2): legge dove
/// è arrivato, apre un party privato sullo stesso titolo da lì, senza il
/// menu delle modalità, e lo invita. `false` se non parte.
Future<bool> watchWithFriend(
    BuildContext context, WidgetRef ref, FriendEntry friend) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final FriendPosition position;
  final JellyfinItem item;
  try {
    position =
        await container.read(socialApiProvider).friendNowPlaying(friend.userId);
  } on SocialException catch (error) {
    if (error.failure == SocialFailure.conflict) {
      // Piano 21b, decisione 4: testo e tasto spariscono subito.
      messenger?.showSnackBar(SnackBar(content: Text(l.friendsNoLongerWatching)));
      await container.read(friendsControllerProvider.notifier).reload();
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(l.watchPartyCreateError)));
    }
    return false;
  }
  try {
    item = await container
        .read(libraryApiProvider)
        .item(container.read(currentUserIdProvider), position.itemId);
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l.watchPartyCreateError)));
    return false;
  }
  if (!context.mounted) return false;
  return startWatchParty(context, ref, item,
      start: position.position, mode: PartyMode.private, invite: friend.userId);
}
