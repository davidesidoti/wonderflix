import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell_panels.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import '../watch_party/invite_card_frame.dart';
import 'friends_controller.dart';

/// Richiesta di amicizia appena arrivata, per la scheda in alto a destra
/// (spec F §8.4), finché la carta non si chiude; non con il player aperto.
/// Il numero sull'icona Amici resta comunque.
class FriendRequestNotices extends Notifier<FriendRequestEvent?> {
  /// Il pannello Amici, ascoltato solo con una carta in vista: un ascolto
  /// fisso terrebbe vivo il pannello anche senza la shell.
  ProviderSubscription<ShellPanel>? _panel;

  @override
  FriendRequestEvent? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    // Le sottoscrizioni della build di prima sono già chiuse.
    _panel = null;
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.friends))) {
      return null;
    }
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is FriendRequestEvent) _show(event);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    ref.listen(playerActiveProvider, (_, active) {
      if (active) dismiss();
    });
    // Accettata o rifiutata altrove (pannello, altro dispositivo): c'era
    // tra le richieste in arrivo e non c'è più.
    ref.listen(friendsControllerProvider.select((s) => s.snapshot.incoming),
        (previous, incoming) {
      final shown = state;
      if (shown == null) return;
      bool has(List<PersonEntry>? people) =>
          people?.any((p) => p.userId == shown.fromUserId) ?? false;
      if (has(previous) && !has(incoming)) dismiss();
    });
    return null;
  }

  void dismiss() {
    _panel?.close();
    _panel = null;
    if (ref.mounted) state = null;
  }

  void _show(FriendRequestEvent event) {
    if (ref.read(playerActiveProvider)) return;
    state = event;
    ref.read(newestInviteProvider.notifier).set(InviteKind.friend);
    // Il pannello Amici mostra la richiesta: la carta (che con il movimento
    // ridotto non si chiude da sola) se ne va.
    _panel ??= ref.listen(shellPanelProvider, (_, panel) {
      if (panel == ShellPanel.friends) dismiss();
    });
  }
}

final friendRequestNoticesProvider =
    NotifierProvider<FriendRequestNotices, FriendRequestEvent?>(
        FriendRequestNotices.new);
