import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../../core/syncplay/syncplay_models.dart';
import 'party_channel.dart';
import 'party_notices.dart';
import 'party_queue_rules.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Esito di [PartyQueueEditor.add] (spec H §8.3).
enum PartyQueueAddOutcome {
  /// La coda del server ha i titoli (anche solo una parte, per il tetto).
  added,

  /// Erano già tutti in coda: niente richiesta, niente avviso.
  alreadyQueued,

  /// Coda piena: niente richiesta.
  full,

  /// Il server non l'ha presa entro [PartyQueueEditor.addConfirmTimeout].
  rejected,

  /// Richiesta non riuscita, o fuori dal gruppo.
  failed,
}

/// Comandi sulla coda del gruppo (spec H §8.3): salto, rimozione,
/// spostamento, ordine casuale. Lavorano sempre sulla coda **attuale**: fuori
/// da un gruppo, o con un elemento non più nella coda, non fanno nulla. Una
/// richiesta non riuscita dà l'avviso "Non riuscito, riprova" (spec H §10).
class PartyQueueEditor {
  PartyQueueEditor(this._ref);

  final Ref _ref;

  /// Dopo la risposta del server la coda nuova arriva dal WebSocket: se non
  /// arriva entro questo tempo, una richiesta di ordine casuale non si
  /// considera più in corso e se ne può fare un'altra.
  static const shuffleSettleTimeout = Duration(seconds: 4);

  /// Ordine casuale richiesto e non ancora visto nella coda del server: il
  /// valore voluto e quando il server ha risposto (`null` = risposta ancora
  /// in attesa, senza scadenza).
  ({bool target, DateTime? at})? _shuffleRequest;

  /// La coda nuova del server, dopo la richiesta, deve arrivare entro questo
  /// tempo: altrimenti il server ha scartato l'aggiunta, perché qualcuno nel
  /// party non può vedere un titolo (spec H §3).
  static const addConfirmTimeout = Duration(seconds: 4);

  /// Id di un'aggiunta che aspetta ancora la conferma: un'altra aggiunta non
  /// li rimanda.
  final _pendingAdds = <String>{};

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
  /// ordinata fa rispondere 500 al server (spec H §3). Una richiesta alla
  /// volta: `queue.shuffled` cambia solo quando arriva la coda del server, e
  /// un secondo clic prima di allora manderebbe `Sorted` due volte.
  Future<void> setShuffle(bool shuffle) async {
    final queue = _queue;
    if (queue == null) {
      _shuffleRequest = null;
      return;
    }
    final pending = _shuffleRequest;
    if (pending != null) {
      final settled = queue.shuffled == pending.target;
      final answeredAt = pending.at;
      final expired = answeredAt != null &&
          clock.now().difference(answeredAt) >= shuffleSettleTimeout;
      if (!settled && !expired) return;
      _shuffleRequest = null;
    }
    if (queue.shuffled == shuffle) return;
    _shuffleRequest = (target: shuffle, at: null);
    final channel = _ref.read(partyChannelProvider.notifier);
    final notices = _ref.read(partyNoticesProvider.notifier);
    final kind =
        shuffle ? PartyNoticeKind.shuffleOn : PartyNoticeKind.shuffleOff;
    // La coda che torna dal server è nostra: niente avviso (spec H §10).
    notices.mine(kind, show: false);
    if (await _send(
        'ordine casuale', (api) => api.setShuffleMode(shuffle: shuffle))) {
      // Il tempo per la coda nuova conta dalla risposta del server.
      _shuffleRequest = (target: shuffle, at: clock.now());
      channel.announce(PartyAction.shuffleMode);
    } else {
      // Nessuna eco in arrivo: il cambio di un altro membro nei prossimi
      // secondi non va scartato, e si può riprovare subito.
      _shuffleRequest = null;
      notices.forget(kind);
    }
  }

  /// Aggiunge [items] in fondo alla coda o, con [next], subito dopo il titolo
  /// in corso (spec H §8.3): senza i titoli già in coda, tagliati al tetto.
  /// Aspetta la coda del server con i titoli nuovi, poi mostra "Hai…" (o
  /// l'avviso di errore).
  Future<PartyQueueAddOutcome> add(List<JellyfinItem> items,
      {required bool next}) async {
    final queue = _queue;
    if (queue == null || items.isEmpty) return PartyQueueAddOutcome.failed;
    final notices = _ref.read(partyNoticesProvider.notifier);
    final plan = partyQueueAddPlan(queue, [for (final item in items) item.id],
        pending: _pendingAdds);
    if (plan.send.isEmpty) {
      if (plan.cut == 0) return PartyQueueAddOutcome.alreadyQueued;
      notices.show(const PartyNotice(PartyNoticeKind.queueFull, mine: true));
      return PartyQueueAddOutcome.full;
    }
    final session = _ref.read(watchPartySessionProvider.notifier);
    final channel = _ref.read(partyChannelProvider.notifier);
    final kind = next ? PartyNoticeKind.queuedNext : PartyNoticeKind.queued;
    final before = {for (final entry in queue.entries) entry.playlistItemId};
    final confirmed = Completer<void>();
    // In ascolto prima della richiesta: la coda può arrivare prima della
    // risposta HTTP.
    final subscription = session.updates.listen((update) {
      if (update is PlayQueueUpdate &&
          _confirms(update.queue, before, plan.send) &&
          !confirmed.isCompleted) {
        confirmed.complete();
      }
    });
    _pendingAdds.addAll(plan.send);
    // La coda che torna dal server è nostra: l'avviso lo dà la conferma.
    notices.mine(kind, show: false);
    try {
      if (!await _send(
          'aggiunta alla coda', (api) => api.queue(plan.send, next: next))) {
        notices.forget(kind);
        return PartyQueueAddOutcome.failed;
      }
      channel.announce(next ? PartyAction.queueNext : PartyAction.queue);
      try {
        await confirmed.future.timeout(addConfirmTimeout);
      } on TimeoutException {
        notices.forget(kind);
        if (_ref.mounted && _ref.read(watchPartySessionProvider).inGroup) {
          notices.show(
              const PartyNotice(PartyNoticeKind.queueRejected, mine: true));
        }
        return PartyQueueAddOutcome.rejected;
      }
      final sent = [
        for (final id in plan.send) items.firstWhere((item) => item.id == id),
      ];
      final addition = partyQueueAddition(sent);
      notices.show(plan.cut > 0
          ? PartyNotice(PartyNoticeKind.queuePartial,
              mine: true,
              count: plan.send.length,
              total: plan.send.length + plan.cut,
              series: addition.series)
          : PartyNotice(kind,
              mine: true,
              title: addition.title,
              count: addition.count,
              series: addition.series));
      return PartyQueueAddOutcome.added;
    } finally {
      _pendingAdds.removeAll(plan.send);
      // Senza attendere: l'annullamento di un ascolto è immediato, e
      // aspettarlo ritarda l'esito.
      unawaited(subscription.cancel());
    }
  }

  /// La coda [queue] ha, tra gli elementi che non c'erano ([before]), tutti
  /// i titoli [sent] (un titolo già visto può tornare due volte).
  static bool _confirms(PlayQueue queue, Set<String> before, List<String> sent) {
    if (queue.reason != 'Queue' && queue.reason != 'QueueNext') return false;
    final added = [
      for (final entry in queue.entries)
        if (!before.contains(entry.playlistItemId)) entry.itemId,
    ];
    for (final id in sent) {
      if (!added.remove(id)) return false;
    }
    return true;
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
