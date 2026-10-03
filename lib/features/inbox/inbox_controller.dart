import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/social/inbox_models.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';

final _log = Logger('social');

/// La cassetta delle notifiche come la vede l'app (spec G §7.3).
class InboxState {
  const InboxState({
    this.snapshot = InboxSnapshot.empty,
    this.loaded = false,
    this.failed = false,
    this.highlighted = const {},
  });

  final InboxSnapshot snapshot;

  /// Almeno un caricamento è riuscito.
  final bool loaded;

  /// L'ultimo caricamento non è riuscito (resta la cassetta di prima).
  final bool failed;

  /// Id delle voci con il pallino dorato: non lette quando il pannello si è
  /// aperto, o arrivate a pannello aperto (spec G §7.5). Si svuota alla
  /// chiusura.
  final Set<String> highlighted;

  /// Il numero sull'icona.
  int get unread => snapshot.unread;

  InboxState copyWith({
    InboxSnapshot? snapshot,
    bool? loaded,
    bool? failed,
    Set<String>? highlighted,
  }) =>
      InboxState(
        snapshot: snapshot ?? this.snapshot,
        loaded: loaded ?? this.loaded,
        failed: failed ?? this.failed,
        highlighted: highlighted ?? this.highlighted,
      );
}

/// Legge la cassetta dal plugin: alla nascita, a ogni avviso
/// `InboxChanged`, a ogni riconnessione del WebSocket e all'apertura del
/// pannello. Con il pannello aperto le voci non lette diventano subito
/// lette (sul plugin fino alla più recente) e prendono il pallino.
class InboxController extends Notifier<InboxState> {
  /// Cresce a ogni caricamento e a ogni azione: vale solo la risposta
  /// dell'ultimo caricamento, e una lettura partita prima di un'azione non
  /// la disfa.
  int _loads = 0;

  /// Il pannello Notifiche è aperto (lo dice `ShellPanelController`).
  bool _panelOpen = false;

  @override
  InboxState build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _loads++;
    // Utente nuovo o logout: il pannello di prima non c'è più.
    _panelOpen = false;
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.inbox))) {
      return const InboxState();
    }
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is InboxChangedEvent) unawaited(reload());
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      // Gli avvisi persi mentre il WebSocket era giù.
      if (event is ServerConnected && event.isReconnect) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    unawaited(Future.microtask(reload));
    return const InboxState();
  }

  /// Rilegge la cassetta dal plugin.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(socialAvailabilityProvider).inbox) return;
    final load = ++_loads;
    try {
      final snapshot = await ref.read(socialApiProvider).inbox();
      if (!ref.mounted || load != _loads) return;
      state = _seenIfOpen(
          state.copyWith(snapshot: snapshot, loaded: true, failed: false));
    } on Object catch (error) {
      _log.info('notifiche non caricate: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
      if (!ref.mounted || load != _loads) return;
      state = state.copyWith(failed: true);
    }
  }

  /// Il pannello si è aperto: le non lette diventano lette, e si rilegge.
  void panelOpened() {
    if (_panelOpen) return;
    _panelOpen = true;
    state = _seenIfOpen(state);
    unawaited(reload());
  }

  /// Il pannello si è chiuso: niente più pallini.
  void panelClosed() {
    _panelOpen = false;
    if (state.highlighted.isNotEmpty) {
      state = state.copyWith(highlighted: const {});
    }
  }

  /// Toglie una voce; `null` se riuscita.
  Future<SocialFailure?> remove(String entryId) => _act(
      state.snapshot.without(entryId), (api) => api.removeInboxEntry(entryId));

  /// Svuota la cassetta; `null` se riuscita.
  Future<SocialFailure?> clear() =>
      _act(InboxSnapshot.empty, (api) => api.clearInbox());

  /// Con il pannello aperto le non lette diventano lette: sul plugin fino
  /// alla più recente, qui subito, con il pallino.
  InboxState _seenIfOpen(InboxState next) {
    final snapshot = next.snapshot;
    if (!_panelOpen || snapshot.unread == 0) return next;
    unawaited(_markRead(snapshot.maxSeq));
    return next.copyWith(
      snapshot: snapshot.markedRead(),
      highlighted: {
        ...next.highlighted,
        for (final entry in snapshot.entries)
          if (!entry.read) entry.id,
      },
    );
  }

  Future<void> _markRead(int upTo) async {
    try {
      await ref.read(socialApiProvider).markInboxRead(upTo);
    } on Object catch (error) {
      // Il numero torna alla prossima lettura (spec G §8): niente messaggio.
      _log.info('notifiche non segnate lette: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
    }
  }

  /// Mostra subito [optimistic]; se l'azione non riesce rilegge (nel
  /// frattempo la cassetta può essere cambiata). `null` se riuscita.
  Future<SocialFailure?> _act(
      InboxSnapshot optimistic, Future<void> Function(SocialApi api) action) async {
    // Una lettura partita prima non deve rimettere la voce tolta.
    _loads++;
    state = state.copyWith(snapshot: optimistic);
    try {
      await action(ref.read(socialApiProvider));
      return null;
    } on SocialException catch (error) {
      if (ref.mounted) unawaited(reload());
      return error.failure;
    } on Object catch (error) {
      _log.info('azione sulle notifiche non riuscita: ${error.runtimeType}');
      if (ref.mounted) unawaited(reload());
      return SocialFailure.network;
    }
  }
}

final inboxControllerProvider =
    NotifierProvider<InboxController, InboxState>(InboxController.new);
