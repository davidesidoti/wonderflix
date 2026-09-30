import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/library_providers.dart';
import 'party_queue.dart';
import 'watch_party_session.dart';

/// "Guarda insieme": crea il gruppo con la coda di [item] (per un episodio:
/// anche i successivi), oppure, stando già in un gruppo, gli cambia la coda.
/// Il player si apre quando il server conferma la coda
/// (`watchPartyRoutingProvider`).
Future<void> startWatchParty(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  Duration start = Duration.zero,
}) =>
    _run(
      context,
      () async {
        final queue = await buildPartyQueue(ref.read(libraryApiProvider),
            ref.read(currentUserIdProvider), item);
        final session = ref.read(watchPartySessionProvider.notifier);
        if (ref.read(watchPartySessionProvider).inGroup) {
          await session.setQueue(queue, start: start);
        } else {
          await session.create(item, queue: queue, start: start);
        }
      },
      creating: true,
    );

/// "Unisciti" dall'elenco dei gruppi.
Future<void> joinWatchParty(
        BuildContext context, WidgetRef ref, String groupId) =>
    _run(
      context,
      () => ref.read(watchPartySessionProvider.notifier).join(groupId),
      creating: false,
    );

Future<void> _run(BuildContext context, Future<void> Function() action,
    {required bool creating}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(
        content: Text(watchPartyErrorText(l, error, creating: creating))));
  }
}

String watchPartyErrorText(AppLocalizations l, Object error,
        {required bool creating}) =>
    switch (error) {
      WatchPartyException(failure: WatchPartyFailure.groupGone) =>
        l.watchPartyGone,
      WatchPartyException(failure: WatchPartyFailure.accessDenied) =>
        l.watchPartyAccessDenied,
      _ => creating ? l.watchPartyCreateError : l.watchPartyJoinError,
    };

String groupStateLabel(AppLocalizations l, GroupState state) =>
    switch (state) {
      GroupState.idle => l.watchPartyStateIdle,
      GroupState.waiting => l.watchPartyStateWaiting,
      GroupState.paused => l.watchPartyStatePaused,
      GroupState.playing => l.watchPartyStatePlaying,
    };
