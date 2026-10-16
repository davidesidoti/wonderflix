import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../app/navigation.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/match_api.dart';
import '../../core/social/match_models.dart';
import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/library_providers.dart';
import '../watch_party/watch_party_actions.dart';
import 'match_queue.dart';
import 'match_room_controller.dart';

/// Il testo dell'avviso per un no del plugin (spec P §7.2).
String matchFailureText(AppLocalizations l, MatchFailure failure) =>
    switch (failure) {
      MatchFailure.started => l.matchAlreadyStarted,
      MatchFailure.closed ||
      MatchFailure.notInvited ||
      MatchFailure.notMember =>
        l.matchClosed,
      MatchFailure.full => l.matchFull,
      MatchFailure.inAnotherRoom => l.matchInAnotherRoom,
      _ => l.matchFailed,
    };

/// "Match": apre una sala nuova e la sua pagina (spec P §7.2). `false` se
/// non è partita (l'avviso lo dice).
Future<bool> openMatchRoom(BuildContext context, WidgetRef ref) =>
    _enter(context, ref, (controller) => controller.open());

/// "Unisciti" a un invito: entra nella sala e apre la sua pagina.
Future<bool> joinMatchRoom(
    BuildContext context, WidgetRef ref, String roomId) {
  // La sala già mostrata: niente seconda pagina (uscirne farebbe uscire
  // dalla sala).
  final room = ref.read(matchRoomProvider);
  if (room != null &&
      !room.closed &&
      normalizeMatchId(room.roomId) == normalizeMatchId(roomId)) {
    return Future.value(true);
  }
  return _enter(context, ref, (controller) => controller.join(roomId));
}

Future<bool> _enter(BuildContext context, WidgetRef ref,
    Future<MatchFailure?> Function(MatchRoomController) action) async {
  // Tutto quello che serve dopo l'attesa si prende prima: chi ha chiamato
  // (il pannello Amici, la carta) può sparire nel frattempo.
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = ref.read(matchRoomProvider.notifier);
  if (controller.entering) return false;
  final failure = await action(controller);
  if (failure != null) {
    messenger?.showSnackBar(SnackBar(content: Text(matchFailureText(l, failure))));
    return false;
  }
  final room = container.read(matchRoomProvider);
  if (room == null) return false;
  unawaited(router.push(matchRoute(room.roomId)));
  return true;
}

final _log = Logger('MatchParty');

/// "Guarda insieme" dai match della sala (spec P §7.4): un party privato con
/// i match (prima [first], se dato) e poi il plugin sa del gruppo. `false`
/// con l'avviso se non c'è niente da guardare; la sala resta aperta.
Future<bool> startMatchParty(BuildContext context, WidgetRef ref,
    {String? first}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final controller = ref.read(matchRoomProvider.notifier);
  final library = ref.read(libraryApiProvider);
  final userId = ref.read(currentUserIdProvider);
  final state = ref.read(matchRoomProvider)?.state;
  final ids = state == null ? const <String>[] : matchPartyOrder(state, first: first);
  List<String> queue = const [];
  JellyfinItem? head;
  try {
    final found = {
      for (final item in await library.itemsByIds(userId, ids)) item.id: item,
    };
    final titles = [for (final id in ids) ?found[id]];
    queue = await buildMatchQueue(library, userId, titles);
    // Il titolo da cui parte davvero la coda: un titolo saltato (serie senza
    // episodi) non può dare il nome al party.
    for (final title in titles) {
      if (title.id == queue.firstOrNull ||
          (title.kind == ItemKind.series &&
              (await library.allEpisodes(userId, title.id))
                  .any((e) => e.id == queue.firstOrNull))) {
        head = title;
        break;
      }
    }
  } on Object catch (error) {
    _log.warning('queue failed: ${error.runtimeType}');
  }
  if (queue.isEmpty || head == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l.matchFailed)));
    return false;
  }
  if (!context.mounted) return false;
  return startWatchParty(context, ref, head,
      mode: PartyMode.private,
      queue: queue,
      onRegistered: (groupId) => unawaited(controller.party(groupId)));
}
