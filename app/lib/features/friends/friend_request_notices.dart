import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import 'friends_controller.dart';

/// Richiesta di amicizia appena arrivata, per la scheda in alto a destra
/// (spec F §8.4): per [showFor], non con il player aperto. Il numero
/// sull'icona Amici resta comunque.
class FriendRequestNotices extends Notifier<FriendRequestEvent?> {
  static const showFor = Duration(seconds: 10);

  Timer? _timer;

  @override
  FriendRequestEvent? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _timer?.cancel();
    _timer = null;
    ref.onDispose(() => _timer?.cancel());
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
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = null;
  }

  void _show(FriendRequestEvent event) {
    if (ref.read(playerActiveProvider)) return;
    _timer?.cancel();
    state = event;
    _timer = Timer(showFor, dismiss);
  }
}

final friendRequestNoticesProvider =
    NotifierProvider<FriendRequestNotices, FriendRequestEvent?>(
        FriendRequestNotices.new);
