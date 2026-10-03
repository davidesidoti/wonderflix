import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import 'current_party.dart';
import 'party_channel.dart';
import 'party_queue.dart';
import 'watch_party_session.dart';

/// "Guarda insieme": crea il gruppo con la coda di [item] (per un episodio:
/// anche i successivi), oppure, stando già in un gruppo, gli cambia la coda.
/// Il player si apre quando il server conferma la coda
/// (`watchPartyRoutingProvider`). Con [mode] il party si registra nel plugin
/// con quella modalità (spec F §9.1–9.2); `null` = come la 0.5.1.
Future<bool> startWatchParty(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  Duration start = Duration.zero,
  PartyMode? mode,
}) =>
    _run(
      context,
      () async {
        // Il widget di [ref] può chiudersi durante le richieste (es. il
        // player da solo sostituito da quello del gruppo): tutto quel che
        // serve si prende prima della prima attesa; dopo, il container.
        final container = ProviderScope.containerOf(context, listen: false);
        final session = ref.read(watchPartySessionProvider.notifier);
        final queue = await buildPartyQueue(ref.read(libraryApiProvider),
            ref.read(currentUserIdProvider), item);
        if (container.read(watchPartySessionProvider).inGroup) {
          await session.setQueue(queue, start: start);
          // Spec E §7.4: gli altri vedono chi ha scelto il titolo.
          container
              .read(partyChannelProvider.notifier)
              .announce(PartyAction.newQueue);
        } else {
          await session.create(
            item,
            queue: queue,
            start: start,
            // Spec F §9.2: la modalità si registra prima della coda. Il
            // plugin e il party corrente si leggono solo con una modalità.
            register: mode == null
                ? null
                : (groupId) async {
                    final social = container.read(socialApiProvider);
                    final code = await social.registerParty(groupId, mode);
                    container
                        .read(currentPartyProvider.notifier)
                        .registered(groupId, mode, code);
                  },
          );
        }
      },
      creating: true,
    );

/// "Unisciti" dall'elenco dei gruppi.
Future<bool> joinWatchParty(
        BuildContext context, WidgetRef ref, String groupId) =>
    _run(
      context,
      () => ref.read(watchPartySessionProvider.notifier).join(groupId),
      creating: false,
    );

/// `true` se [action] è riuscita; altrimenti mostra l'errore e `false`.
Future<bool> _run(BuildContext context, Future<void> Function() action,
    {required bool creating}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(
        content: Text(watchPartyErrorText(l, error, creating: creating))));
    return false;
  }
}

String watchPartyErrorText(AppLocalizations l, Object error,
        {required bool creating}) =>
    switch (error) {
      WatchPartyException(failure: WatchPartyFailure.groupGone) =>
        l.watchPartyGone,
      WatchPartyException(failure: WatchPartyFailure.accessDenied) =>
        l.watchPartyAccessDenied,
      WatchPartyException(failure: WatchPartyFailure.registration) =>
        l.partyCreateFailed,
      _ => creating ? l.watchPartyCreateError : l.watchPartyJoinError,
    };

String groupStateLabel(AppLocalizations l, GroupState state) =>
    switch (state) {
      GroupState.idle => l.watchPartyStateIdle,
      GroupState.waiting => l.watchPartyStateWaiting,
      GroupState.paused => l.watchPartyStatePaused,
      GroupState.playing => l.watchPartyStatePlaying,
    };
