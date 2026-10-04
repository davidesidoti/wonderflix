import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

enum PartyNoticeKind {
  paused,
  resumed,
  forcedResume,
  seeked,
  joined,
  left,
  nextEpisode,
  nowWatching,
  resync,

  /// Il gruppo non c'è più (sparito durante il rientro).
  ended,

  /// Il server ci ha tolto dal gruppo, che può esserci ancora.
  removed,

  /// Il codice del party privato appena creato da noi (spec F §9.4), in
  /// `title`.
  privateCode,

  /// Codice copiato negli appunti.
  codeCopied,

  /// Invito mandato a `name`.
  inviteSent,

  /// Invito non riuscito.
  inviteFailed,

  /// Troppi inviti in poco tempo (429).
  inviteRateLimited,

  /// Il gruppo è tornato al titolo prima (spec H §10), in `title`.
  previousItem,

  /// Ordine casuale acceso da qualcuno.
  shuffleOn,

  /// Ordine casuale spento da qualcuno.
  shuffleOff,

  /// Un comando della coda non è arrivato al server (solo per chi agisce).
  queueFailed,
}

/// Un avviso del watch party (spec B §5.7). Il testo lo compone
/// `partyNoticeText`.
class PartyNotice {
  const PartyNotice(this.kind,
      {this.mine = false, this.position, this.name, this.title});

  final PartyNoticeKind kind;

  /// Azione dell'utente stesso: testo in seconda persona ("Hai…").
  final bool mine;

  /// Per i salti.
  final Duration? position;

  /// Chi ha agito: nelle entrate e nelle uscite, e nelle azioni altrui
  /// annunciate dal plugin del watch party (spec E §8).
  final String? name;

  /// Per successivo, precedente e nuovo titolo.
  final String? title;

  /// Lo stesso avviso con il nome di chi ha agito.
  PartyNotice withName(String name) => PartyNotice(kind,
      mine: mine, position: position, name: name, title: title);
}

/// Chi annuncia un'azione dell'utente (vedi [PartyNotices.mine]).
typedef PartyActionCallback = void Function(PartyNoticeKind kind,
    {Duration? position});

/// Avviso di un'azione altrui in attesa del nome (vedi
/// [PartyNotices.attributionWait]).
class _WaitingNotice {
  _WaitingNotice(this.notice, this.action);

  final PartyNotice notice;
  final PartyAction action;
  Timer? timer;
}

/// Avvisi del watch party, uno alla volta per [showFor]. Lo stato è
/// l'avviso da mostrare adesso (`null` = nessuno).
class PartyNotices extends Notifier<PartyNotice?> {
  static const showFor = Duration(seconds: 3);

  /// Entro questo tempo lo `StateUpdate` di una nostra azione è la sua eco.
  static const echoWindow = Duration(seconds: 3);

  /// Attesa massima del nome di chi ha agito, con il canale del plugin
  /// attivo (spec E §8): l'annuncio arriva di solito insieme all'avviso di
  /// SyncPlay, poche decine di millisecondi prima o dopo.
  static const attributionWait = Duration(milliseconds: 300);

  /// Per quanto un annuncio del canale resta abbinabile a un avviso.
  static const announcementLifetime = Duration(seconds: 2);

  /// Le proprie azioni sulla coda (spec H §10): l'eco può arrivare più tardi
  /// di quella delle pause (per le aggiunte, fino alla conferma).
  static const queueEchoWindow = Duration(seconds: 4);

  static const _queueEchoKinds = {
    PartyNoticeKind.shuffleOn,
    PartyNoticeKind.shuffleOff,
  };

  static Duration _echoWindowOf(PartyNoticeKind kind) =>
      _queueEchoKinds.contains(kind) ? queueEchoWindow : echoWindow;

  final _queue = Queue<PartyNotice>();
  final _echoes = <({PartyNoticeKind kind, DateTime at})>[];
  Timer? _timer;
  GroupState? _groupState;
  String? _playing;

  /// Ordine casuale dell'ultima coda vista; `null` prima della prima.
  bool? _shuffled;
  Duration? _lastSeek;

  /// Il canale del plugin è attivo: gli avvisi altrui aspettano il nome.
  bool _attribution = false;

  /// Annunci arrivati prima del loro avviso.
  final _announcements = <({PartyActionEvent event, DateTime at})>[];

  /// Avvisi che aspettano il loro annuncio, in ordine di arrivo.
  final _waiting = <_WaitingNotice>[];

  @override
  PartyNotice? build() {
    // Nuovo utente = nuova sessione del gruppo: ci si iscrive di nuovo.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    final party = ref.read(watchPartySessionProvider);
    final session = ref.read(watchPartySessionProvider.notifier);
    _queue.clear();
    _echoes.clear();
    _timer = null;
    _groupState = party.inGroup ? party.groupState : null;
    _playing = party.queue?.playing?.playlistItemId;
    _shuffled = party.queue?.shuffled;
    _lastSeek = null;
    _attribution = false;
    _cancelWaiting();
    final subscriptions = [
      session.updates.listen(_onUpdate),
      session.commands.listen((command) {
        if (command.type == SyncPlayCommandType.seek) {
          _lastSeek = command.position;
        }
      }),
    ];
    ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
        (_, inGroup) {
      if (!inGroup) {
        _clear();
        return;
      }
      // `GroupJoined` non arriva negli aggiornamenti: lo stato del gruppo
      // all'ingresso si prende dalla sessione (es. una ripresa senza
      // aspettare subito dopo l'ingresso).
      final joined = ref.read(watchPartySessionProvider);
      _groupState = joined.groupState;
      _playing = joined.queue?.playing?.playlistItemId;
      _shuffled = joined.queue?.shuffled;
    });
    ref.onDispose(() {
      _timer?.cancel();
      _cancelWaiting();
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    });
    return null;
  }

  /// Mostra [notice] dopo quelli già in coda.
  void show(PartyNotice notice) {
    _queue.add(notice);
    if (_timer == null) _next();
  }

  /// Azione dell'utente: l'avviso compare subito, e l'eco del server (entro
  /// [echoWindow], o [queueEchoWindow] per l'ordine casuale) non ne produce
  /// un secondo. Con [show] `false` si registra solo l'eco: l'azione l'ha già
  /// mostrata la pillola del tasto (spec D §9.3).
  void mine(PartyNoticeKind kind, {Duration? position, bool show = true}) {
    _echoes.add((kind: kind, at: clock.now()));
    if (show) this.show(PartyNotice(kind, mine: true, position: position));
  }

  /// Toglie l'ultima eco registrata con [mine] per [kind]: la richiesta non è
  /// arrivata al server, quindi nessuna eco in arrivo, e un cambio uguale di
  /// un altro membro nei secondi dopo non va scartato.
  void forget(PartyNoticeKind kind) {
    final index = _echoes.lastIndexWhere((echo) => echo.kind == kind);
    if (index >= 0) _echoes.removeAt(index);
  }

  /// Il canale del plugin è attivo ([enabled]) o spento (spec E §8). Spento:
  /// gli avvisi in attesa escono subito senza nome.
  void setAttribution(bool enabled) {
    _attribution = enabled;
    if (enabled) return;
    final waiting = [..._waiting];
    _cancelWaiting();
    for (final entry in waiting) {
      show(entry.notice);
    }
  }

  /// Annuncio di un altro membro arrivato dal canale: dà il nome all'avviso
  /// che lo aspetta (il più vecchio), o resta da parte per
  /// [announcementLifetime].
  void attribute(PartyActionEvent event) {
    final index =
        _waiting.indexWhere((waiting) => waiting.action == event.action);
    if (index >= 0) {
      final waiting = _waiting.removeAt(index);
      waiting.timer?.cancel();
      show(waiting.notice.withName(event.userName));
      return;
    }
    _pruneAnnouncements();
    _announcements.add((event: event, at: clock.now()));
  }

  void _next() {
    _timer?.cancel();
    if (_queue.isEmpty) {
      _timer = null;
      if (ref.mounted) state = null;
      return;
    }
    if (ref.mounted) state = _queue.removeFirst();
    _timer = Timer(showFor, _next);
  }

  void _clear() {
    _queue.clear();
    _echoes.clear();
    _timer?.cancel();
    _timer = null;
    _groupState = null;
    _playing = null;
    _shuffled = null;
    _lastSeek = null;
    _cancelWaiting();
    if (ref.mounted) state = null;
  }

  /// `true` (e l'eco si consuma) se [kind] è l'eco di una nostra azione.
  bool _isEcho(PartyNoticeKind kind) {
    final now = clock.now();
    _echoes.removeWhere(
        (echo) => now.difference(echo.at) > _echoWindowOf(echo.kind));
    final index = _echoes.indexWhere((echo) =>
        echo.kind == kind ||
        (echo.kind == PartyNoticeKind.resumed &&
            kind == PartyNoticeKind.forcedResume));
    if (index < 0) return false;
    _echoes.removeAt(index);
    return true;
  }

  void _cancelWaiting() {
    for (final waiting in _waiting) {
      waiting.timer?.cancel();
    }
    _waiting.clear();
    _announcements.clear();
  }

  void _pruneAnnouncements() {
    final now = clock.now();
    _announcements.removeWhere(
        (announcement) => now.difference(announcement.at) > announcementLifetime);
  }

  /// Nome dell'annuncio più recente di [action] ancora valido; l'annuncio si
  /// consuma.
  String? _takeAnnouncement(PartyAction action) {
    _pruneAnnouncements();
    final index = _announcements
        .lastIndexWhere((announcement) => announcement.event.action == action);
    if (index < 0) return null;
    return _announcements.removeAt(index).event.userName;
  }

  /// Avviso di un'azione altrui (spec E §8): con il nome se l'annuncio di
  /// [action] è già arrivato; altrimenti, con il canale attivo, lo aspetta
  /// al massimo [attributionWait]. Senza [action] esce subito.
  void _showOthers(PartyNotice notice, PartyAction? action) {
    if (action == null) {
      show(notice);
      return;
    }
    final name = _takeAnnouncement(action);
    if (name != null) {
      show(notice.withName(name));
    } else if (!_attribution) {
      show(notice);
    } else {
      final waiting = _WaitingNotice(notice, action);
      waiting.timer = Timer(attributionWait, () {
        _waiting.remove(waiting);
        show(waiting.notice);
      });
      _waiting.add(waiting);
    }
  }

  static PartyAction? _actionOf(PartyNoticeKind kind) => switch (kind) {
        PartyNoticeKind.paused => PartyAction.pause,
        PartyNoticeKind.resumed ||
        PartyNoticeKind.forcedResume =>
          PartyAction.unpause,
        PartyNoticeKind.seeked => PartyAction.seek,
        _ => null,
      };

  void _onUpdate(GroupUpdate update) {
    switch (update) {
      case GroupStateUpdate(state: final groupState, :final reason):
        final previous = _groupState;
        _groupState = groupState;
        final kind = switch (reason) {
          'Pause' => PartyNoticeKind.paused,
          'Unpause' => previous == GroupState.waiting &&
                  groupState == GroupState.playing
              ? PartyNoticeKind.forcedResume
              : PartyNoticeKind.resumed,
          'Seek' => PartyNoticeKind.seeked,
          _ => null,
        };
        if (kind == null || _isEcho(kind)) return;
        if (kind == PartyNoticeKind.seeked) {
          final position = _lastSeek;
          if (position == null) return;
          _showOthers(
              PartyNotice(kind, position: position), _actionOf(kind));
        } else {
          _showOthers(PartyNotice(kind), _actionOf(kind));
        }
      case UserJoined(:final userName):
        show(PartyNotice(PartyNoticeKind.joined, name: userName));
      case UserLeft(:final userName):
        show(PartyNotice(PartyNoticeKind.left, name: userName));
      case PlayQueueUpdate(:final queue):
        _onQueue(queue);
      case GroupDoesNotExist():
        show(const PartyNotice(PartyNoticeKind.ended));
      case GroupLeft() || NotInGroup():
        show(const PartyNotice(PartyNoticeKind.removed));
      default:
        break;
    }
  }

  void _onQueue(PlayQueue queue) {
    final entry = queue.playing;
    final previous = _playing;
    final wasShuffled = _shuffled;
    _playing = entry?.playlistItemId;
    _shuffled = queue.shuffled;
    // Ordine casuale acceso o spento da qualcuno (spec H §10); la prima coda
    // dopo l'ingresso non è un cambio. L'elemento in corso resta lui.
    if (queue.reason == 'ShuffleMode') {
      if (wasShuffled == null || wasShuffled == queue.shuffled) return;
      final kind = queue.shuffled
          ? PartyNoticeKind.shuffleOn
          : PartyNoticeKind.shuffleOff;
      if (!_isEcho(kind)) {
        _showOthers(PartyNotice(kind), PartyAction.shuffleMode);
      }
      return;
    }
    if (entry == null || previous == null || previous == entry.playlistItemId) {
      return;
    }
    // Il nome viene dall'annuncio dell'azione che ha cambiato titolo; un
    // cambio per un altro motivo (per esempio una rimozione del titolo in
    // corso da un altro client) resta senza nome. [step]: il titolo è
    // l'episodio ("S1:E5 · Titolo"), come per successivo, precedente e salto
    // dalla coda; per un titolo nuovo è la serie o il film.
    final (kind, action, step) = switch (queue.reason) {
      'NextItem' => (PartyNoticeKind.nextEpisode, PartyAction.nextItem, true),
      'PreviousItem' => (
          PartyNoticeKind.previousItem,
          PartyAction.previousItem,
          true
        ),
      'SetCurrentItem' => (
          PartyNoticeKind.nowWatching,
          PartyAction.setCurrentItem,
          true
        ),
      'NewPlaylist' => (
          PartyNoticeKind.nowWatching,
          PartyAction.newQueue,
          false
        ),
      _ => (PartyNoticeKind.nowWatching, null, false),
    };
    unawaited(_announce(kind, entry.itemId, action, step: step));
  }

  Future<void> _announce(
      PartyNoticeKind kind, String itemId, PartyAction? action,
      {required bool step}) async {
    try {
      final item = await ref
          .read(libraryApiProvider)
          .item(ref.read(currentUserIdProvider), itemId);
      if (!ref.mounted) return;
      // Nel frattempo si è usciti dal gruppo o si guarda già altro.
      final party = ref.read(watchPartySessionProvider);
      if (!party.inGroup || party.queue?.playing?.itemId != itemId) return;
      _showOthers(
          PartyNotice(kind, title: _noticeTitle(item, step: step)), action);
    } on Object catch (error) {
      _log.info('titolo per l\'avviso non disponibile: $error');
    }
  }

  /// Con [step] un episodio ("S1:E5 · Titolo"); altrimenti, e per un film,
  /// la serie o il film.
  static String _noticeTitle(JellyfinItem item, {required bool step}) =>
      step && item.kind == ItemKind.episode
          ? cardSubtitle(item) ?? item.name
          : cardTitle(item);
}

final partyNoticesProvider =
    NotifierProvider<PartyNotices, PartyNotice?>(PartyNotices.new);
