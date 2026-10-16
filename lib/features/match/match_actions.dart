import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../core/social/match_api.dart';
import '../../core/social/match_models.dart';
import '../../l10n/gen/app_localizations.dart';
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
