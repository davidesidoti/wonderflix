import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/party_channel/party_channel_models.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import 'party_channel.dart';
import 'party_notices.dart';
import 'party_queue_rules.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Comandi sulla coda del gruppo (spec H §8.3): salto, rimozione,
/// spostamento, ordine casuale. Lavorano sempre sulla coda **attuale**: fuori
/// da un gruppo, o con un elemento non più nella coda, non fanno nulla. Una
/// richiesta non riuscita dà l'avviso "Non riuscito, riprova" (spec H §10).
class PartyQueueEditor {
  PartyQueueEditor(this._ref);

  final Ref _ref;

  PlayQueue? get _queue {
    final party = _ref.read(watchPartySessionProvider);
    return party.inGroup ? party.queue : null;
  }

  /// Il gruppo passa a [playlistItemId], da 0; annunciato agli altri.
  Future<void> jumpTo(String playlistItemId) async {
    final queue = _queue;
    if (queue == null ||
        queue.playing?.playlistItemId == playlistItemId ||
        !_contains(queue, playlistItemId)) {
      return;
    }
    // Il canale si prende prima dell'attesa: nel frattempo il player può
    // chiudersi.
    final channel = _ref.read(partyChannelProvider.notifier);
    if (await _send('salto nella coda',
        (api) => api.setPlaylistItem(playlistItemId))) {
      channel.announce(PartyAction.setCurrentItem);
    }
  }

  /// Toglie [playlistItemId] dalla coda: mai quello in riproduzione (spec H
  /// §3). Nessun avviso.
  Future<void> remove(String playlistItemId) async {
    final queue = _queue;
    if (queue == null ||
        queue.playing?.playlistItemId == playlistItemId ||
        !_contains(queue, playlistItemId)) {
      return;
    }
    await _send('rimozione dalla coda',
        (api) => api.removeFromPlaylist(playlistItemId));
  }

  /// Porta il prossimo [playlistItemId] alla posizione [upcomingIndex] tra i
  /// prossimi (contata dopo averlo tolto). Nessun avviso.
  Future<void> move(String playlistItemId, int upcomingIndex) async {
    final queue = _queue;
    if (queue == null) return;
    final upcoming = partyQueueSections(queue).upcoming;
    final from =
        upcoming.indexWhere((entry) => entry.playlistItemId == playlistItemId);
    if (from < 0 ||
        upcomingIndex < 0 ||
        upcomingIndex >= upcoming.length ||
        upcomingIndex == from) {
      return;
    }
    await _send(
        'spostamento nella coda',
        (api) => api.movePlaylistItem(
            playlistItemId, partyQueueMoveIndex(queue, upcomingIndex)));
  }

  /// Ordine casuale acceso o spento, solo se cambia: `Sorted` su una coda già
  /// ordinata fa rispondere 500 al server (spec H §3).
  Future<void> setShuffle(bool shuffle) async {
    final queue = _queue;
    if (queue == null || queue.shuffled == shuffle) return;
    final channel = _ref.read(partyChannelProvider.notifier);
    final notices = _ref.read(partyNoticesProvider.notifier);
    final kind =
        shuffle ? PartyNoticeKind.shuffleOn : PartyNoticeKind.shuffleOff;
    // La coda che torna dal server è nostra: niente avviso (spec H §10).
    notices.mine(kind, show: false);
    if (await _send(
        'ordine casuale', (api) => api.setShuffleMode(shuffle: shuffle))) {
      channel.announce(PartyAction.shuffleMode);
    } else {
      // Nessuna eco in arrivo: il cambio di un altro membro nei prossimi
      // secondi non va scartato.
      notices.forget(kind);
    }
  }

  bool _contains(PlayQueue queue, String playlistItemId) =>
      queue.entries.any((entry) => entry.playlistItemId == playlistItemId);

  /// `true` se [request] è arrivata al server.
  Future<bool> _send(
      String what, Future<void> Function(SyncPlayApi api) request) async {
    final api = _ref.read(watchPartySessionProvider.notifier).api;
    final notices = _ref.read(partyNoticesProvider.notifier);
    try {
      await request(api);
      return true;
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.warning('$what non riuscito: ${error.runtimeType}');
      // Se nel frattempo si è usciti dal gruppo l'avviso non ha più senso.
      if (_ref.mounted && _ref.read(watchPartySessionProvider).inGroup) {
        notices
            .show(const PartyNotice(PartyNoticeKind.queueFailed, mine: true));
      }
      return false;
    }
  }
}

final partyQueueEditorProvider =
    Provider<PartyQueueEditor>(PartyQueueEditor.new);
