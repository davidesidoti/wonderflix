import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/media_session/media_session.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../detail/primary_action.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../watch_party/group_authority.dart';
import '../watch_party/group_playback_driver.dart';
import '../watch_party/party_badge.dart';
import '../watch_party/party_channel.dart';
import '../watch_party/party_chat_layer.dart';
import '../watch_party/party_mode_menu.dart';
import '../watch_party/party_notices.dart';
import '../watch_party/party_queue_items.dart';
import '../watch_party/party_reactions_layer.dart';
import '../watch_party/party_reactions_tray.dart';
import '../watch_party/party_waiting_overlay.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';
import 'pause_screen.dart';
import 'post_play.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'player_extras.dart';
import 'player_active.dart';
import 'player_chrome.dart';
import 'player_handover.dart';
import 'player_loading.dart';
import 'player_overlay.dart';
import 'player_pill.dart';
import 'player_providers.dart';
import 'player_settings.dart';
import 'player_side_panel_host.dart';
import 'player_volume.dart';
import 'player_window.dart';
import 'queue_panel/queue_panel.dart';
import 'segments.dart';
import 'skip_button.dart';
import 'tracks_panel.dart';
import 'trickplay.dart';
import 'trickplay_preview.dart';

final _log = Logger('player');

/// Schermata del player: video a tutta finestra, controlli in
/// sovrimpressione, tastiera, schermo intero, salta intro, prossimo
/// episodio e chiusura sicura della finestra (prima si segnala la fine a
/// Jellyfin).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args, this.fullscreen = false});

  final PlayerArgs args;

  /// La finestra è già a schermo intero (arrivo dall'episodio precedente).
  final bool fullscreen;

  /// Attesa massima del report di fine alla chiusura della finestra.
  static const closeTimeout = Duration(seconds: 2);

  /// Se il motore non segnala il primo fotogramma entro questo tempo da
  /// `ready` (per esempio un video del gruppo aperto in pausa), il
  /// caricamento sfuma comunque.
  static const firstFrameTimeout = Duration(seconds: 3);

  /// Al massimo una reazione ogni questo tempo, da tasti e barretta (spec E
  /// §10.3).
  static const reactionInterval = Duration(milliseconds: 200);

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerWindow _window;

  /// Controlli, pannello e riscontro dei tasti (spec D §5.1).
  final _chrome = PlayerChromeController();

  /// Focus del player: i tasti arrivano a `_onKey`. Chiusa la chat (che
  /// aveva il focus nel suo campo) torna qui (spec E §11).
  final _focusNode = FocusNode(debugLabel: 'player');
  bool _chatWasOpen = false;

  /// Focus del campo della chat del watch party: è del player, che glielo
  /// rimette se un tasto arriva a chat aperta mentre il campo non ce l'ha.
  final _chatFocusNode = FocusNode(debugLabel: 'party-chat');

  /// Invio apre la chat. Non `const`: le chiavi ridefiniscono `==`.
  static final _openChatKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  /// Cifre e tasti del tastierino da 1 a 6, nell'ordine di
  /// [PartyReaction.key].
  static const _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
  ];
  static const _numpadKeys = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
  ];

  /// Tasti delle reazioni (spec E §10.3): 1–6 e tastierino, dal tasto di
  /// ogni reazione. Non `const`: le chiavi ridefiniscono `==`.
  static final _reactionKeys = {
    for (final reaction in PartyReaction.values) ...{
      _digitKeys[reaction.key - 1]: reaction,
      _numpadKeys[reaction.key - 1]: reaction,
    },
  };

  /// Aggancio della barretta delle reazioni al suo pulsante.
  final _reactionsLink = LayerLink();

  /// Ultima reazione mandata (limite di [PlayerScreen.reactionInterval]).
  DateTime? _lastReactionAt;

  /// Il motore ha disegnato il primo fotogramma (o è passato
  /// [PlayerScreen.firstFrameTimeout] da `ready`): il caricamento sfuma.
  bool _firstFrame = false;
  Timer? _firstFrameTimer;
  late bool _fullscreen = widget.fullscreen;
  bool _leaving = false;

  /// Si passa all'episodio successivo: la finestra resta com'è.
  bool _handingOver = false;

  /// "Guarda insieme" in corso: il pulsante sparisce, un secondo tocco non
  /// fa nulla.
  bool _startingParty = false;

  /// Il menu delle modalità di "Guarda insieme" è aperto: il pulsante resta,
  /// ma un secondo tocco non ne apre un altro.
  bool _choosingMode = false;

  /// Il routing del watch party segnala qui che sostituisce questo player
  /// da solo con quello del gruppo (letto alla chiusura, senza `ref`).
  late final PlayerHandover _handover;

  /// Dove si è rispetto alla fine dell'episodio (spec D §12): cambia poche
  /// volte, e solo allora la schermata si ricostruisce.
  EndZone _endZone = EndZone.none;
  StreamSubscription<Duration>? _positions;
  StreamSubscription<Duration>? _durations;
  StreamSubscription<SkipKind>? _autoSkips;

  /// Il post-play era mostrato all'ultima costruzione: quando cambia,
  /// pannello e schermata di pausa lo seguono (vedi [build]).
  bool _postPlayWasShown = false;

  /// Entrata degli strati del post-play e della scheda: il contenuto nuovo
  /// è subito opaco, perché entra già con la sua animazione (altrimenti
  /// sfumerebbe due volte); quello che esce sfuma comunque in
  /// [WfMotion.fast] accelerando, come le altre uscite (spec D §6.1): con
  /// [WfMotion.accelerateReverse], perché `switchOutCurve` si percorre da 1
  /// a 0.
  static const _offerSwitchInCurve = Threshold(0);

  late final PlayerActiveController _playerActive;
  late final MediaSession _mediaSession;
  StreamSubscription<MediaButton>? _mediaButtons;
  Timer? _timelineTimer;

  /// Nel watch party: applica i comandi del gruppo al motore.
  GroupPlaybackDriver? _driver;

  /// Nel watch party: manda al gruppo pausa, ripresa e salti.
  GroupAuthority? _authority;

  /// Il server ci ha tolto dal gruppo: il player continua da solo, come
  /// fuori da un watch party.
  bool _partyDetached = false;

  bool get _inParty => widget.args.party != null && !_partyDetached;

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.args).notifier);

  @override
  void initState() {
    super.initState();
    _playerActive = ref.read(playerActiveProvider.notifier)..enter();
    _handover = ref.read(playerHandoverProvider);
    _window = ref.read(playerWindowProvider);
    _window.addCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(true));
    // Sessione condivisa: con l'episodio successivo la nuova schermata
    // parte prima che la vecchia sia chiusa.
    _mediaSession = ref.read(mediaSessionProvider);
    _mediaButtons = _mediaSession.buttons.listen(_onMediaButton);
    // Il "successivo" dell'episodio precedente non vale per questo: si
    // riattiva quando arriva il suo episodio successivo. Nel gruppo segue la
    // coda, che c'è già.
    final party = _inParty ? ref.read(watchPartySessionProvider) : null;
    unawaited(_mediaSession.setNextEnabled(
        party != null && party.inGroup && party.hasNext));
    unawaited(_mediaSession.setPreviousEnabled(
        party != null && party.inGroup && party.hasPrevious));
    // Discord: quante persone nel watch party (`null` fuori da un gruppo).
    unawaited(_mediaSession.setParty(
        party != null && party.inGroup ? party.members.length : null));
    _timelineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendTimeline());
    // Il gruppo ha sostituito il player del titolo prima: la coda, se era
    // aperta, resta aperta (spec H §9.1). Prima del listener, il pannello è
    // aperto fin dal primo fotogramma.
    if (widget.args.party != null &&
        ref.read(partyQueuePanelCarryProvider).take()) {
      _chrome.openPopup(PlayerPopup.queue);
    }
    _chrome.addListener(_onChromeChanged);
    // Un menu aperto dai controlli (modalità di "Guarda insieme", distintivo
    // del party) è una rotta sopra il player: finché c'è, i controlli non si
    // nascondono (il mouse sul menu non arriva al player).
    _chrome.isCovered =
        () => mounted && !(ModalRoute.isCurrentOf(context) ?? true);
    // Il caricamento resta finché il motore non disegna il primo
    // fotogramma (spec D §10.1). Se il controller nativo fallisce il futuro
    // finisce in errore: si ignora, il conto di 3 s toglie comunque il
    // caricamento.
    unawaited(_controller.engine.firstFrame
        .then((_) => _onFirstFrame(), onError: (Object _) {}));
    final engine = _controller.engine;
    _positions = engine.positionStream.listen(_updateEndZone);
    _durations = engine.durationStream.listen((_) => _updateEndZone());
    // Salto automatico di intro o riassunto: lo dice la pillola.
    _autoSkips = _controller.autoSkips
        .listen((kind) => _chrome.showFeedback(SkipFeedback(kind)));
  }

  @override
  void dispose() {
    // Player da solo sostituito dal routing con quello del gruppo: come
    // passando all'episodio successivo.
    final handingOver = _handingOver ||
        (widget.args.party == null && _handover.consume(widget.args.itemId));
    _chrome
      ..removeListener(_onChromeChanged)
      ..dispose();
    _focusNode.dispose();
    _chatFocusNode.dispose();
    _window.removeCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(false));
    if (_fullscreen && !handingOver) unawaited(_window.setFullScreen(false));
    _timelineTimer?.cancel();
    _firstFrameTimer?.cancel();
    unawaited(_positions?.cancel());
    unawaited(_durations?.cancel());
    unawaited(_autoSkips?.cancel());
    unawaited(_mediaButtons?.cancel());
    // Uscendo dal player il pannello media sparisce; passando all'episodio
    // successivo resta alla nuova schermata. Non si chiude mai: è dell'app.
    if (!handingOver) unawaited(_mediaSession.clear());
    if (!handingOver) unawaited(_mediaSession.setParty(null));
    _playerActive.leave();
    unawaited(_driver?.dispose());
    _authority?.dispose();
    super.dispose();
  }

  Future<void> _onWindowClose() async {
    // Letti subito: dopo il primo await la schermata può essere già smontata.
    final controller = _controller;
    final party =
        _inParty ? ref.read(watchPartySessionProvider.notifier) : null;
    final volume = ref.read(playerVolumeProvider.notifier);
    // La finestra sparisce e il film tace subito: fine della sessione sul
    // server, uscita dal party e volume vanno avanti senza farsi vedere né
    // sentire. Prima la finestra restava ferma a video nero finché non
    // finivano (issue #8). Il muto è solo del motore, e non si aspetta
    // (durante l'apertura il motore lo farebbe attendere): il volume salvato
    // e quello mandato al server restano quelli scelti.
    controller.engine.setVolume(0).ignore();
    try {
      await _window.hide();
    } on Object {
      // Se non si nasconde, si chiude comunque come prima.
    }
    try {
      await Future.wait([
        controller.close(),
        if (party != null) party.leave(),
        // Il provider dell'app non viene mai chiuso: il volume cambiato da
        // meno di [PlayerVolumeController.saveDelay] va scritto adesso
        // (issue #3).
        volume.flush(),
      ]).timeout(PlayerScreen.closeTimeout, onTimeout: () => const []);
    } on Object catch (error) {
      // Un errore qui non deve lasciare l'app viva e invisibile: terrebbe il
      // blocco dell'istanza unica e WonderFlix non si riaprirebbe più.
      _log.warning('chiusura della finestra: $error');
    }
    await _window.destroy();
  }

  void _onChromeChanged() {
    if (!mounted) return;
    final chatOpen = _chrome.chatOpen;
    if (chatOpen != _chatWasOpen) {
      _chatWasOpen = chatOpen;
      // Chiusa la chat (Esc, clic sul film, pannello, chiusura automatica):
      // i tasti tornano al player. Con un menu o un dialogo sopra il player
      // il focus resta a loro: chiusi, la storia del focus lo riporta qui.
      if (!chatOpen && (ModalRoute.isCurrentOf(context) ?? true)) {
        _focusNode.requestFocus();
      }
    }
    setState(() {});
  }

  /// La chat del watch party si può aprire: nel gruppo, con il canale del
  /// plugin attivo (spec E §9.5).
  bool get _chatAvailable =>
      _inParty && ref.read(partyChannelProvider).active;

  /// Manda una reazione (tasti o barretta), al massimo una ogni
  /// [PlayerScreen.reactionInterval]. Se l'orologio di sistema è tornato
  /// indietro la reazione passa: altrimenti resterebbero bloccate finché
  /// l'ora non torna dov'era.
  void _sendReaction(PartyReaction reaction) {
    final now = clock.now();
    final last = _lastReactionAt;
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) < PlayerScreen.reactionInterval) {
      return;
    }
    _lastReactionAt = now;
    ref.read(partyChannelProvider.notifier).sendReaction(reaction);
  }

  void _onFirstFrame() {
    _firstFrameTimer?.cancel();
    if (!mounted || _firstFrame) return;
    setState(() => _firstFrame = true);
    // Il conto per nascondere i controlli è partito con `playing`, sotto il
    // caricamento: con il primo fotogramma tardivo scadrebbe appena lo strato
    // sfuma. Ripartire da qui li mostra e rifà i 3 s da quando si vede il video.
    _chrome.pointerActivity();
  }

  /// Dice al controller dell'interfaccia se si sta guardando e se la
  /// schermata di pausa è ammessa adesso (spec D §11.1): file pronto e
  /// fermo, niente buffering, video non finito, elemento arrivato, gruppo
  /// non in attesa.
  void _syncPlayback() {
    final view = ref.read(playerControllerProvider(widget.args));
    final party = _inParty ? ref.read(watchPartySessionProvider) : null;
    final groupWaiting = party != null &&
        party.inGroup &&
        party.groupState == GroupState.waiting;
    _chrome.setPlayback(
      playing: view.playing,
      canShowPauseScreen: view.status == PlayerStatus.ready &&
          !view.playing &&
          !view.buffering &&
          !view.finished &&
          view.item != null &&
          !groupWaiting &&
          !_postPlayShown(view),
    );
  }

  /// Ricalcola la zona di fine episodio con la posizione ([position], o
  /// quella del motore), i segmenti e la durata di adesso: ognuno può
  /// arrivare per ultimo (es. i segmenti a video fermo nei titoli). Pannello
  /// e schermata di pausa seguono il post-play in [build], non la zona.
  void _updateEndZone([Duration? position]) {
    if (!mounted) return;
    final view = ref.read(playerControllerProvider(widget.args));
    final engine = _controller.engine;
    final zone = endZoneAt(
        view.segments, engine.duration, position ?? engine.position);
    if (zone != _endZone) setState(() => _endZone = zone);
  }

  /// Il titolo proposto come prossimo (spec H §9.1): da soli l'episodio
  /// successivo della serie; nel gruppo il prossimo della coda (anche un
  /// film), appena se ne conoscono i dettagli.
  JellyfinItem? _nextOffer(PlayerViewState view) {
    if (!_inParty) return view.nextEpisode;
    final entry = ref.read(watchPartySessionProvider).nextEntry;
    return entry == null
        ? null
        : ref.read(partyQueueItemsProvider)[entry.itemId];
  }

  /// "Prossimo episodio", o "Prossimo nella coda" se nel gruppo il prossimo
  /// non è l'episodio che segue nella libreria.
  String _nextOfferLabel(
          AppLocalizations l, PlayerViewState view, JellyfinItem offer) =>
      !_inParty || offer.id == view.nextEpisode?.id
          ? l.playerNextEpisodeTitle
          : l.playerNextInQueueTitle;

  /// C'è un titolo da proporre ([_nextOffer]), il caricamento è finito
  /// (primo fotogramma: aprendo nei titoli il post-play e il suo conto non
  /// partono sotto il caricamento) e l'utente non l'ha rifiutato.
  bool _canOfferNext(PlayerViewState view) =>
      _nextOffer(view) != null &&
      view.status == PlayerStatus.ready &&
      _firstFrame &&
      !_chrome.postPlayDismissed;

  /// Post-play: titoli di coda noti (spec D §12.1).
  bool _postPlayShown(PlayerViewState view) =>
      _endZone == EndZone.credits && _canOfferNext(view);

  /// Scheda piccola: ultimi 30 s senza titoli noti (spec D §12.2).
  bool _cardShown(PlayerViewState view) =>
      _endZone == EndZone.lastSeconds && _canOfferNext(view);

  /// "Guarda i titoli", "Annulla", Esc, clic sul film piccolo. A video
  /// finito (post-play rimasto aperto senza conto alla rovescia) da soli si
  /// esce: non c'è più niente da guardare. Nel gruppo si chiude soltanto,
  /// perché uscire dal player vorrebbe dire lasciare il gruppo.
  void _dismissNext() {
    if (!_inParty && ref.read(playerControllerProvider(widget.args)).finished) {
      _exit();
      return;
    }
    _chrome.dismissPostPlay();
    _syncPlayback();
  }

  /// "Riproduci ora" (pulsante o conto alla rovescia) della scheda o del
  /// post-play: vale solo se l'offerta è ancora mostrata. Uscendo
  /// (`AnimatedSwitcher`) il pulsante resta montato un attimo e il suo conto
  /// potrebbe scadere dopo che l'utente l'ha chiusa.
  void _playOffered() {
    final view = ref.read(playerControllerProvider(widget.args));
    if (_postPlayShown(view) || _cardShown(view)) _playNext();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    await _window.setFullScreen(next);
  }

  void _exit() {
    if (_leaving) return;
    _leaving = true;
    // Chiudere il player fa uscire dal watch party: gli altri continuano.
    if (_inParty) {
      _detachParty();
      unawaited(ref.read(watchPartySessionProvider.notifier).leave());
    }
    unawaited(_controller.close());
    if (_fullscreen) {
      _fullscreen = false;
      unawaited(_window.setFullScreen(false));
    }
    // Gli avvisi di conversione riguardano il player: non devono restare
    // (né arrivare dalla coda) sulla schermata a cui si torna.
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    if (context.canPop()) {
      // Un menu aperto sopra il player (modalità, distintivo, inviti) è una
      // rotta dello stesso navigatore: `pop` chiuderebbe quello, e il player
      // resterebbe aperto ma già in uscita, senza più rispondere. Prima si
      // chiude quel che c'è sopra.
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        Navigator.of(context).popUntil((other) => other == route);
      }
      context.pop();
    } else {
      context.go('/home');
    }
  }

  /// Passa all'episodio successivo (da dove era rimasto, se iniziato),
  /// mantenendo lo schermo intero. Se l'episodio in corso è finito, o si è
  /// già nei titoli di coda (da dove compare la scheda "Prossimo
  /// episodio"), lo si segna come visto: altrimenti resterebbe "in corso".
  void _playNext({bool finished = false}) {
    // Nel gruppo l'episodio lo cambia il gruppo: il player passa a quello
    // nuovo quando arriva la coda (vedi [_handOverTo]).
    if (_inParty) {
      // A fine coda non c'è niente da chiedere: il `Seek` in sospeso resta.
      if (!_leaving && ref.read(watchPartySessionProvider).hasNext) {
        // Il `Seek` non dice l'elemento: partito dopo il cambio, salterebbe
        // nell'episodio nuovo.
        _authority?.cancelPendingSeek();
        unawaited(_requestNextInParty(widget.args.party!));
      }
      return;
    }
    final view = ref.read(playerControllerProvider(widget.args));
    final next = view.nextEpisode;
    if (next == null || _leaving) return;
    _leaving = true;
    _handingOver = true;
    final engine = _controller.engine;
    final from = nextEpisodeCardFrom(view.segments, engine.duration);
    final watched = finished || (from != null && engine.position >= from);
    unawaited(_controller.close(watched: watched));
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    final userData =
        ref.read(userDataOverridesProvider)[next.id] ?? next.userData;
    final action = primaryActionFor(next, userData);
    final start = action is ResumeAction ? action.position : Duration.zero;
    context.pushReplacement(
        playerRoute(next.id, start: start, fullscreen: _fullscreen),
        extra: playerReplacement);
  }

  /// Chiede al gruppo l'elemento dopo [playlistItemId] e, se la richiesta
  /// arriva al server, la annuncia agli altri (spec E §7.4). Il canale si prende prima
  /// dell'attesa: nel frattempo il player può chiudersi.
  Future<void> _requestNextInParty(String playlistItemId) async {
    final channel = ref.read(partyChannelProvider.notifier);
    final requested = await ref
        .read(watchPartySessionProvider.notifier)
        .nextItem(playlistItemId);
    if (requested) channel.announce(PartyAction.nextItem);
  }

  /// Torna al titolo precedente (spec H §9.1). Nel gruppo lo chiede al
  /// gruppo; da soli apre l'episodio prima, da dove era rimasto, senza
  /// segnare come visto quello che si lascia.
  void _playPrevious() {
    if (_inParty) {
      // Sul primo della coda non c'è niente da chiedere: il `Seek` in
      // sospeso resta.
      if (!_leaving && ref.read(watchPartySessionProvider).hasPrevious) {
        // Come per il successivo: un `Seek` in sospeso salterebbe
        // nell'elemento nuovo.
        _authority?.cancelPendingSeek();
        unawaited(_requestPreviousInParty(widget.args.party!));
      }
      return;
    }
    final previous =
        ref.read(playerControllerProvider(widget.args)).previousEpisode;
    if (previous == null || _leaving) return;
    _leaving = true;
    _handingOver = true;
    unawaited(_controller.close());
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    final userData =
        ref.read(userDataOverridesProvider)[previous.id] ?? previous.userData;
    final action = primaryActionFor(previous, userData);
    final start = action is ResumeAction ? action.position : Duration.zero;
    context.pushReplacement(
        playerRoute(previous.id, start: start, fullscreen: _fullscreen),
        extra: playerReplacement);
  }

  /// Chiede al gruppo l'elemento prima di [playlistItemId] e, se la
  /// richiesta arriva al server, la annuncia agli altri (spec H §10).
  Future<void> _requestPreviousInParty(String playlistItemId) async {
    final channel = ref.read(partyChannelProvider.notifier);
    final requested = await ref
        .read(watchPartySessionProvider.notifier)
        .previousItem(playlistItemId);
    if (requested) channel.announce(PartyAction.previousItem);
  }

  /// Fine del video: episodio successivo se previsto, altrimenti uscita.
  void _onFinished() {
    // Nel gruppo si passa all'elemento dopo della coda (il server scarta le
    // richieste doppie degli altri). A fine coda si resta sul video.
    if (_leaving) return;
    if (_inParty) {
      unawaited(ref
          .read(watchPartySessionProvider.notifier)
          .nextItem(widget.args.party!));
      return;
    }
    final view = ref.read(playerControllerProvider(widget.args));
    final autoplay = ref.read(playerSettingsProvider).autoplayNext;
    if (view.nextEpisode != null && autoplay && !_chrome.postPlayDismissed) {
      _playNext(finished: true);
    } else if (!_postPlayShown(view)) {
      _exit();
    }
    // Post-play aperto e nessun conto alla rovescia: si resta lì (film
    // fermo sull'ultimo fotogramma) finché non si sceglie (spec D §12.1).
  }

  void _publishMetadata(JellyfinItem item) {
    unawaited(_mediaSession.setMetadata(
      title: cardTitle(item),
      subtitle: cardSubtitle(item),
      thumbnailUrl: ref.read(imageUrlsProvider).poster(item)?.url,
    ));
  }

  /// Nel watch party il player segue il gruppo: il driver applica i comandi,
  /// l'autorità manda al gruppo pausa, ripresa e salti.
  void _attachParty(PlayerController controller) {
    final party = widget.args.party;
    // Uscendo dal player (o passando all'elemento dopo) non si ricollega.
    if (party == null || _driver != null || _leaving) return;
    final current = ref.read(watchPartySessionProvider);
    final session = ref.read(watchPartySessionProvider.notifier);
    final serverClock = session.serverClock;
    if (!current.inGroup || serverClock == null) return;
    final notices = ref.read(partyNoticesProvider.notifier);
    final channel = ref.read(partyChannelProvider.notifier);
    _driver = GroupPlaybackDriver(
      engine: controller.engine,
      api: session.api,
      clock: serverClock,
      playlistItemId: party,
      commands: session.commands,
      lastCommand: session.lastCommand,
      onResync: () =>
          notices.show(const PartyNotice(PartyNoticeKind.resync)),
      startLag: session.startLag,
      onDrift: (drift) => session.lastDrift = drift,
      waitExclusion: session,
    )..start();
    final authority = GroupAuthority(
      api: session.api,
      engine: controller.engine,
      // Spec D §9.3: un'azione appena data da tastiera ha già la sua
      // pillola; l'avviso "Hai…" registra solo l'eco.
      onAction: (kind, {position}) {
        notices.mine(kind,
            position: position, show: !_chrome.isRecentKeyAction(kind));
        // Spec E §7.4: gli altri vedono il nostro nome.
        channel.announceMine(kind, position: position);
      },
    );
    _authority = authority;
    controller.setAuthority(authority);
  }

  /// Il player smette di seguire il gruppo: uscita, passaggio all'elemento
  /// dopo, o il server ci ha tolto dal gruppo (si continua da soli).
  void _detachParty() {
    final driver = _driver;
    _driver = null;
    unawaited(driver?.dispose());
    _authority?.dispose();
    _authority = null;
    _controller.setAuthority(null);
  }

  /// Il gruppo è passato a un altro elemento della coda (episodio
  /// successivo, nuovo titolo): questo player lascia il posto a quello
  /// nuovo, con lo schermo intero com'è. L'episodio lasciato finito o sui
  /// titoli di coda si segna come visto.
  void _handOverTo(PlayQueueEntry entry) {
    if (_leaving) return;
    _leaving = true;
    _handingOver = true;
    // Driver e autorità si fermano subito, non alla chiusura della pagina:
    // un `Seek` in sospeso (senza elemento) salterebbe nell'episodio nuovo.
    _detachParty();
    final view = ref.read(playerControllerProvider(widget.args));
    final engine = _controller.engine;
    final from = nextEpisodeCardFrom(view.segments, engine.duration);
    final watched = view.finished || (from != null && engine.position >= from);
    unawaited(_controller.close(watched: watched));
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    // La coda aperta resta aperta nel player nuovo.
    ref
        .read(partyQueuePanelCarryProvider)
        .carry(open: _chrome.popup == PlayerPopup.queue);
    context.pushReplacement(
        playerRoute(
          entry.itemId,
          start:
              ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
          fullscreen: _fullscreen,
          party: entry.playlistItemId,
        ),
        extra: playerReplacement);
  }

  /// "Guarda insieme" mentre si guarda da soli (spec B §5.2): il gruppo parte
  /// da qui, e il routing riapre il player sullo stesso punto in modalità
  /// gruppo (sostituendo questo, vedi [PlayerHandover]). Se la coda non
  /// arriva, o si esce prima, questo player esce come sempre. Riuscita la
  /// richiesta il pulsante non torna: si aspetta il player del gruppo. Il
  /// menu delle modalità (spec F §9.1) è ancorato a [buttonContext]: mentre
  /// è aperto il pulsante resta, e chiuso senza scegliere non cambia nulla.
  /// Il punto di partenza si legge dopo la scelta.
  Future<void> _watchTogether(BuildContext buttonContext) async {
    final item = ref.read(playerControllerProvider(widget.args)).item;
    if (item == null || _leaving || _startingParty || _choosingMode) return;
    _choosingMode = true;
    final bool started;
    try {
      started = await watchTogether(
        context,
        ref,
        item,
        startAt: () => _controller.engine.position,
        menuAnchor: buttonContext,
        onStarting: () {
          _choosingMode = false;
          if (mounted) setState(() => _startingParty = true);
        },
      );
    } finally {
      _choosingMode = false;
    }
    if (!mounted || _leaving) return;
    if (!started && _startingParty) setState(() => _startingParty = false);
  }

  void _sendTimeline() {
    if (!mounted) return;
    if (ref.read(playerControllerProvider(widget.args)).status !=
        PlayerStatus.ready) {
      return;
    }
    final engine = _controller.engine;
    unawaited(_mediaSession.setTimeline(
        position: engine.position, duration: engine.duration));
  }

  /// Tasti del pannello media e della tastiera multimediale. Play e pausa
  /// danno la stessa pillola di Spazio, prima del comando (vedi [_run]).
  void _onMediaButton(MediaButton button) {
    if (!mounted || _leaving) return;
    switch (button) {
      case MediaButton.play:
        _showPlayFeedback(playing: true);
        unawaited(_controller.play());
      case MediaButton.pause:
        _showPlayFeedback(playing: false);
        unawaited(_controller.pause());
      case MediaButton.next:
        _playNext();
      case MediaButton.previous:
        _playPrevious();
      case MediaButton.stop:
        _exit();
    }
  }

  /// Pillola di play/pausa, solo a player pronto (come per Spazio).
  void _showPlayFeedback({required bool playing}) {
    final ready = ref.read(playerControllerProvider(widget.args)).status ==
        PlayerStatus.ready;
    if (ready) _chrome.showFeedback(PlayFeedback(playing: playing));
  }

  /// Esc: pannello o chat → post-play o scheda → schermo intero → uscita
  /// (spec D §9.1, spec E §11). A video finito il post-play non si chiude:
  /// si esce.
  void _escape() {
    final view = ref.read(playerControllerProvider(widget.args));
    if (_chrome.popup != null) {
      _chrome.closePopup();
    } else if ((_postPlayShown(view) && !view.finished) || _cardShown(view)) {
      _dismissNext();
    } else if (_fullscreen) {
      unawaited(_toggleFullscreen());
    } else {
      _exit();
    }
  }

  /// Chat aperta: i tasti vanno al suo campo (lettere, Spazio, frecce,
  /// Backspace, Invio), tranne Esc che la chiude (spec E §11). Contano
  /// comunque come attività.
  KeyEventResult _onChatKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    _chrome.keyActivity();
    final key = event.logicalKey;
    if (event is KeyDownEvent && key == LogicalKeyboardKey.escape) {
      _chrome.closePopup(PlayerPopup.chat);
      return KeyEventResult.handled;
    }
    // I tasti multimediali non scrivono nulla: fanno il loro comando.
    if (isMediaKey(key)) {
      final command = _commandFor(event);
      if (command == null) return KeyEventResult.ignored;
      _run(command);
      return KeyEventResult.handled;
    }
    // Il focus è finito fuori dal campo (per esempio al player): il tasto
    // lo riporta lì e basta, altrimenti la tastiera non scriverebbe più.
    if (!_chatFocusNode.hasFocus) {
      _chatFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    // Tab e Maiusc+Tab porterebbero il focus fuori dal campo.
    if (key == LogicalKeyboardKey.tab) return KeyEventResult.handled;
    // Invio tenuto premuto dopo aver aperto la chat (o mandato un
    // messaggio): la ripetizione manderebbe il campo vuoto, chiudendola.
    if (event is KeyRepeatEvent && _openChatKeys.contains(key)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Comando del player per [event]. I tasti multimediali valgono solo se
  /// non li riceve già la sessione media di sistema.
  PlayerCommand? _commandFor(KeyEvent event) => playerCommandFor(event,
      altPressed: HardwareKeyboard.instance.isAltPressed,
      mediaKeys: !_mediaSession.handlesMediaKeys);

  /// Ctrl, Alt o Meta premuti: i numeri non mandano reazioni.
  bool get _shortcutModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_chrome.chatOpen) return _onChatKey(event);
    // Invio apre la chat del watch party, solo con il focus al player: su
    // un pulsante (per esempio "Riprova") lo preme.
    if (event is KeyDownEvent &&
        _openChatKeys.contains(event.logicalKey) &&
        _focusNode.hasPrimaryFocus &&
        _chatAvailable) {
      _chrome
        ..keyActivity()
        ..openPopup(PlayerPopup.chat);
      return KeyEventResult.handled;
    }
    // 1–6 mandano una reazione (spec E §10.3), solo con il focus al player:
    // niente controlli né pillola, e tenendo premuto non si ripete. Con
    // Ctrl, Alt o Meta premuti sono scorciatoie, non reazioni: il tasto
    // prosegue come gli altri.
    final reaction = _reactionKeys[event.logicalKey];
    if (reaction != null &&
        !_shortcutModifierPressed &&
        _focusNode.hasPrimaryFocus &&
        _chatAvailable) {
      if (event is KeyDownEvent) _sendReaction(reaction);
      if (event is! KeyUpEvent) _chrome.keyActivity();
      return KeyEventResult.handled;
    }
    final command = _commandFor(event);
    // Qualsiasi tasto premuto (anche senza comando) chiude "Stai guardando"
    // e rifà gli 8 s (spec D §5.1); il rilascio non conta.
    var dismissingPause = false;
    if (event is! KeyUpEvent) {
      dismissingPause = _chrome.pauseScreen;
      _chrome.keyActivity();
    }
    // Con "Stai guardando" aperta Esc la chiude soltanto: non esce dal
    // player (né dal watch party).
    if (dismissingPause && command == PlayerCommand.escape) {
      return KeyEventResult.handled;
    }
    if (command == null) return KeyEventResult.ignored;
    _run(command);
    return KeyEventResult.handled;
  }

  /// Rotella del mouse: volume come ↑/↓ (issue #4), con la pillola e senza
  /// mostrare i controlli. Si registra nel `pointerSignalResolver`, dove
  /// vince il widget più interno: sul pannello "Audio e sottotitoli" la
  /// rotella resta al pannello.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    // Orizzontale (o tilt della rotella): niente.
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _chrome.keyActivity();
      _run(dy < 0 ? PlayerCommand.volumeUp : PlayerCommand.volumeDown);
    });
  }

  /// Comando da tastiera (o dalla rotella, per il volume): la pillola mostra
  /// il riscontro (spec D §9), i controlli non compaiono. Il riscontro va
  /// dato **prima** del comando: nel watch party l'avviso "Hai…" che segue
  /// controlla che la pillola ci sia già (vedi [_attachParty]).
  void _run(PlayerCommand command) {
    final controller = _controller;
    final ready = ref.read(playerControllerProvider(widget.args)).status ==
        PlayerStatus.ready;
    switch (command) {
      case PlayerCommand.togglePlay:
        if (ready) {
          _chrome.showFeedback(
              PlayFeedback(playing: !controller.engine.playing));
        }
        unawaited(controller.togglePlay());
      case PlayerCommand.seekBack:
        _seekBy(-seekStep, ready: ready);
      case PlayerCommand.seekForward:
        _seekBy(seekStep, ready: ready);
      case PlayerCommand.volumeUp:
        unawaited(controller.changeVolumeBy(volumeStep));
        _showVolume();
      case PlayerCommand.volumeDown:
        unawaited(controller.changeVolumeBy(-volumeStep));
        _showVolume();
      case PlayerCommand.toggleMute:
        unawaited(controller.toggleMute());
        _showVolume();
      case PlayerCommand.subtitleDelayDown:
        unawaited(controller.shiftSubtitleDelay(-subtitleDelayStep));
        _showSubtitleDelay();
      case PlayerCommand.subtitleDelayUp:
        unawaited(controller.shiftSubtitleDelay(subtitleDelayStep));
        _showSubtitleDelay();
      case PlayerCommand.toggleFullscreen:
        unawaited(_toggleFullscreen());
      case PlayerCommand.nextEpisode:
        _playNext();
      case PlayerCommand.previous:
        _playPrevious();
      case PlayerCommand.escape:
        _escape();
      case PlayerCommand.exit:
        _exit();
    }
  }

  /// Salto da tastiera con la pillola (i salti di fila si sommano).
  void _seekBy(Duration step, {required bool ready}) {
    final engine = _controller.engine;
    if (ready) {
      _chrome.seek(step, from: engine.position, duration: engine.duration);
    }
    unawaited(_controller.seekBy(step));
  }

  /// Volume e muto dopo il tasto: il controller li aggiorna subito.
  void _showVolume() {
    final view = ref.read(playerControllerProvider(widget.args));
    _chrome.showFeedback(VolumeFeedback(volume: view.volume, muted: view.muted));
  }

  void _showSubtitleDelay() => _chrome.showFeedback(SubtitleDelayFeedback(
      ref.read(playerControllerProvider(widget.args)).subtitleDelay));

  /// Anteprima trickplay per la barra; `null` se il server non ne ha.
  Widget? Function(Duration)? _previewFor(PlayerViewState view) {
    final item = view.item;
    final plan = view.plan;
    if (item == null || plan == null) return null;
    final trickplay = pickTrickplay(item, plan.mediaSource.id);
    if (trickplay == null) return null;
    final (:mediaSourceId, :info) = trickplay;
    final serverUrl = ref.read(appConfigProvider).serverUrl;
    return (position) {
      final tile = trickplayTileAt(info, position);
      if (tile == null) return null;
      return TrickplayPreview(
        url: trickplaySheetUrl(serverUrl,
            itemId: item.id,
            width: info.width,
            sheet: tile.sheet,
            mediaSourceId: mediaSourceId),
        info: info,
        tile: tile,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = playerControllerProvider(widget.args);
    final view = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final settings = ref.watch(playerSettingsProvider);
    final next = view.nextEpisode;
    if (_inParty) _attachParty(controller);
    final party = _inParty ? ref.watch(watchPartySessionProvider) : null;
    // I dettagli dei titoli in coda arrivano dopo: il post-play li aspetta.
    if (_inParty) ref.watch(partyQueueItemsProvider);
    final offer = _nextOffer(view);
    final canWatchTogether = widget.args.party == null &&
        ref.watch(syncPlayAccessProvider).canCreate &&
        view.item != null &&
        !_startingParty;
    // Chat del watch party: c'è con il canale del plugin attivo (spec E §9).
    final chat = widget.args.party != null
        ? ref.watch(partyChannelProvider
            .select((s) => (active: s.active, unread: s.unread)))
        : null;
    final chatActive = _inParty && (chat?.active ?? false);

    ref.listen(provider.select((s) => s.finished), (_, finished) {
      if (finished) _onFinished();
    });
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      _syncPlayback();
      unawaited(_mediaSession.setPlaying(playing));
    });
    ref.listen(
        provider.select(
            (s) => (s.status, s.buffering, s.finished, s.item != null)),
        (_, _) => _syncPlayback());
    ref.listen(provider.select((s) => s.item), (_, item) {
      if (item != null) _publishMetadata(item);
    });
    // I segmenti arrivano dopo la partenza: a video fermo nessuna posizione
    // nuova ricalcolerebbe la zona.
    ref.listen(provider.select((s) => s.segments), (_, _) => _updateEndZone());
    ref.listen(provider.select((s) => s.nextEpisode != null), (_, hasNext) {
      // Nel gruppo il "successivo" segue la coda (vedi sotto).
      if (!_inParty) unawaited(_mediaSession.setNextEnabled(hasNext));
    });
    ref.listen(provider.select((s) => s.previousEpisode != null),
        (_, hasPrevious) {
      // Nel gruppo il "precedente" segue la coda.
      if (!_inParty) unawaited(_mediaSession.setPreviousEnabled(hasPrevious));
    });
    ref.listen(provider.select((s) => s.transcodingFallback), (_, fallback) {
      if (fallback) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.playerTranscoding)));
      }
    });
    ref.listen(provider.select((s) => s.status), (previous, status) {
      // Una riapertura non riuscita (cambio di traccia) mentre il pannello è
      // aperto: lo strato dell'errore non deve avere il pannello a fianco
      // (le tracce, o la coda del gruppo).
      // La barretta delle reazioni, sparito il suo pulsante con i controlli,
      // resterebbe aperta senza vedersi (e il primo Esc sarebbe suo).
      if (status == PlayerStatus.error) {
        _chrome
          ..closePanel()
          ..closePopup(PlayerPopup.reactions)
          ..closePopup(PlayerPopup.queue);
      }
      if (status != PlayerStatus.ready) {
        // Errore, "Riprova" o ripiego: i comandi del gruppo aspettano il
        // prossimo caricamento.
        if (previous == PlayerStatus.ready || status == PlayerStatus.error) {
          _driver?.onUnloaded(failed: status == PlayerStatus.error);
        }
        return;
      }
      if (!_firstFrame) {
        _firstFrameTimer?.cancel();
        _firstFrameTimer =
            Timer(PlayerScreen.firstFrameTimeout, _onFirstFrame);
      }
      final driver = _driver;
      if (driver != null) {
        unawaited(driver.onLoaded());
      } else if (widget.args.party != null) {
        // Gruppo non disponibile (o tolto dal server): il player parte da
        // solo (il controller di un player del gruppo non lo fa).
        unawaited(controller.play());
      }
    });
    if (widget.args.party != null) {
      ref.listen(
          watchPartySessionProvider
              .select((s) => s.inGroup ? s.members.length : null),
          (_, members) => unawaited(_mediaSession.setParty(members)));
      // Canale spento (plugin tolto) con la chat o la barretta delle
      // reazioni aperte: si chiudono.
      ref.listen(partyChannelProvider.select((s) => s.active), (_, active) {
        if (active) return;
        _chrome
          ..closePopup(PlayerPopup.chat)
          ..closePopup(PlayerPopup.reactions);
      });
    }
    if (_inParty) {
      ref.listen(
          watchPartySessionProvider.select(
              (s) => s.inGroup && s.groupState == GroupState.waiting),
          (_, _) => _syncPlayback());
      ref.listen(
          watchPartySessionProvider.select((s) => s.inGroup && s.hasNext),
          (_, hasNext) {
        if (_inParty && !_leaving) {
          unawaited(_mediaSession.setNextEnabled(hasNext));
        }
      });
      ref.listen(
          watchPartySessionProvider.select((s) => s.inGroup && s.hasPrevious),
          (_, hasPrevious) {
        if (_inParty && !_leaving) {
          unawaited(_mediaSession.setPreviousEnabled(hasPrevious));
        }
      });
      ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
          (_, inGroup) {
        if (inGroup || _leaving) return;
        // Il server ci ha tolto dal gruppo: si continua da soli, con
        // l'episodio successivo come fuori da un watch party.
        setState(() => _partyDetached = true);
        _chrome
          ..closePopup(PlayerPopup.chat)
          ..closePopup(PlayerPopup.reactions)
          ..closePopup(PlayerPopup.queue);
        _detachParty();
        _controller.leaveParty();
        unawaited(_mediaSession
            .setNextEnabled(ref.read(provider).nextEpisode != null));
        unawaited(_mediaSession
            .setPreviousEnabled(ref.read(provider).previousEpisode != null));
      });
      ref.listen(
          watchPartySessionProvider.select((s) =>
              s.inGroup ? s.queue?.playing?.playlistItemId : null),
          (_, playlistItemId) {
        if (playlistItemId == null || playlistItemId == widget.args.party) {
          return;
        }
        final entry = ref.read(watchPartySessionProvider).queue?.playing;
        if (entry != null) _handOverTo(entry);
      });
      ref.listen(watchPartySessionProvider.select((s) => s.rejoins),
          (_, _) => unawaited(_driver?.onRejoined()));
    }

    // Caricamento: finché il file non è pronto e il motore non ha disegnato
    // il primo fotogramma (spec D §10.1).
    final loading = view.status == PlayerStatus.loading ||
        (view.status == PlayerStatus.ready && !_firstFrame);
    final postPlay = _postPlayShown(view);
    final card = _cardShown(view);
    // Il gruppo aspetta qualcuno: nel post-play l'attesa sta sopra di lui
    // (vince l'attesa, spec D §15.3), altrimenti sotto i controlli.
    final groupWaiting = party != null &&
        view.status == PlayerStatus.ready &&
        party.inGroup &&
        party.groupState == GroupState.waiting &&
        !view.buffering;
    void resumeGroup() => unawaited(controller.play());
    // Il post-play compare o sparisce anche senza un cambio di zona (la coda
    // del gruppo, l'uscita dal gruppo, l'episodio successivo arrivato tardi,
    // lo stato del file): dopo il fotogramma, all'arrivo il pannello si
    // chiude (sotto c'è il post-play; vale anche per la coda del gruppo), e
    // con lui la barretta delle reazioni (spariti i controlli con il suo
    // pulsante resterebbe aperta senza vedersi, e il primo Esc sarebbe
    // suo); la schermata di pausa segue (spec D §12.1: non c'è durante il
    // post-play).
    if (postPlay != _postPlayWasShown) {
      _postPlayWasShown = postPlay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (postPlay) {
          _chrome
            ..closePanel()
            ..closePopup(PlayerPopup.reactions)
            ..closePopup(PlayerPopup.queue);
        }
        _syncPlayback();
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) _exit();
          },
          // Col tasto premuto (trascinamento della barra) `onHover` non
          // scatta: i movimenti tengono vivi i controlli.
          onPointerMove: (_) => _chrome.pointerActivity(),
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
            // Nel post-play i controlli non ci sono ma il cursore resta.
            cursor: _chrome.controlsVisible || postPlay
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _chrome.pointerActivity(),
            // Ogni strato ha una chiave: i figli dello `Stack` si abbinano
            // per posizione, e quando uno strato condizionale compare o
            // sparisce quelli sotto di lui (con il loro stato) verrebbero
            // rimontati.
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Il film: nel post-play si rimpicciolisce (spec D §12.1).
                // Lo spinner del buffering è sul film e lo segue: nel
                // post-play resta sul film piccolo, non sotto l'immagine
                // dell'episodio. Le chiavi tengono fermo il video quando lo
                // spinner entra o esce (non si rimonta).
                PostPlayFrame(
                  key: const ValueKey('player-video'),
                  active: postPlay,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        key: const ValueKey('player-video-view'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_chrome.popup != null) {
                            // Pannello o chat aperti: il clic li chiude e
                            // basta.
                            _chrome.closePopup();
                          } else if (_postPlayShown(ref.read(provider))) {
                            // Clic sul film piccolo: torna a tutto schermo.
                            _dismissNext();
                          } else {
                            unawaited(controller.togglePlay());
                          }
                        },
                        onDoubleTap: () => unawaited(_toggleFullscreen()),
                        child: controller.engine.buildView(),
                      ),
                      if (view.status == PlayerStatus.ready && !loading)
                        BufferingSpinner(
                            key: const ValueKey('player-spinner'),
                            buffering: view.buffering),
                    ],
                  ),
                ),
                // Attesa del gruppo nella riproduzione normale: sotto i
                // controlli, che restano usabili. Nel post-play c'è quella
                // sopra di lui (vedi sotto).
                if (party != null && view.status == PlayerStatus.ready)
                  Positioned.fill(
                    key: const ValueKey('player-party-waiting'),
                    child: ExcludeFocus(
                      child: PartyWaitingOverlay(
                        waiting: groupWaiting && !postPlay,
                        onResume: resumeGroup,
                      ),
                    ),
                  ),
                // "Stai guardando" sopra il fermo immagine, sotto i
                // controlli (spec D §11).
                if (view.status == PlayerStatus.ready && view.item != null)
                  Positioned.fill(
                    key: const ValueKey('player-pause-layer'),
                    child: ExcludeFocus(
                      child: PauseScreen(
                          item: view.item!, visible: _chrome.pauseScreen),
                    ),
                  ),
                if (view.status == PlayerStatus.error)
                  PlayerErrorLayer(
                    key: const ValueKey('player-error'),
                    item: view.item,
                    error: view.error,
                    onRetry: () => unawaited(controller.retry()),
                    onBack: _exit,
                    // Nel gruppo uscire dal player è uscire dal gruppo.
                    backLabel: _inParty ? l.watchPartyLeave : l.playerBack,
                  )
                else
                  // I controlli non prendono il focus della tastiera: le
                  // scorciatoie restano sempre attive.
                  ExcludeFocus(
                    key: const ValueKey('player-controls'),
                    child: IgnorePointer(
                      ignoring: !_chrome.controlsVisible || loading || postPlay,
                      child: PlayerOverlay(
                        // Durante il caricamento la freccia per uscire sta
                        // nello strato del caricamento; nel post-play i
                        // controlli non ci sono.
                        visible:
                            _chrome.controlsVisible && !loading && !postPlay,
                        view: view,
                        engine: controller.engine,
                        fullscreen: _fullscreen,
                        onBack: _exit,
                        onTogglePlay: () => unawaited(controller.togglePlay()),
                        onSeekBy: (offset) =>
                            unawaited(controller.seekBy(offset)),
                        onSeekTo: (position) =>
                            unawaited(controller.seekTo(position)),
                        onVolume: (volume) =>
                            unawaited(controller.setVolume(volume)),
                        onToggleMute: () => unawaited(controller.toggleMute()),
                        onToggleTracks: _chrome.togglePanel,
                        onToggleFullscreen: () =>
                            unawaited(_toggleFullscreen()),
                        onNextEpisode: _inParty
                            ? (party != null && party.hasNext
                                ? _playNext
                                : null)
                            : (next == null ? null : _playNext),
                        onPrevious: _inParty
                            ? (party != null && party.hasPrevious
                                ? _playPrevious
                                : null)
                            : (view.previousEpisode == null
                                ? null
                                : _playPrevious),
                        partyQueue: _inParty,
                        chapters: view.item?.chapters ?? const [],
                        preview: _previewFor(view),
                        partyBadge: party != null && party.inGroup
                            ? PartyBadge(onLeave: _exit)
                            : null,
                        onWatchTogether: canWatchTogether
                            ? (buttonContext) =>
                                unawaited(_watchTogether(buttonContext))
                            : null,
                        onToggleChat: chatActive
                            ? () => _chrome.togglePopup(PlayerPopup.chat)
                            : null,
                        chatUnread: (chat?.unread ?? 0) > 0,
                        onToggleReactions: chatActive
                            ? () => _chrome.togglePopup(PlayerPopup.reactions)
                            : null,
                        reactionsLink: _reactionsLink,
                        onToggleQueue: party != null &&
                                party.inGroup &&
                                party.queue != null
                            ? () => _chrome.togglePopup(PlayerPopup.queue)
                            : null,
                      ),
                    ),
                  ),
                // Caricamento sopra il film e i controlli; sfumato via esce
                // dall'albero. Ha una chiave: i figli dello `Stack` si
                // abbinano per posizione, e quando compaiono altri strati
                // prima di lui (spinner, "salta intro") senza chiave
                // perderebbe lo stato (e l'`onEnd` che lo toglie dall'albero).
                if (view.status != PlayerStatus.error)
                  Positioned.fill(
                    key: const ValueKey('player-loading-layer'),
                    child: ExcludeFocus(
                      child: PlayerLoadingLayer(
                        item: view.item,
                        visible: loading,
                        onBack: _exit,
                      ),
                    ),
                  ),
                if (view.status == PlayerStatus.ready) ...[
                  // Salta intro / riassunto: visibile anche a controlli
                  // nascosti.
                  Positioned(
                    key: const ValueKey('player-skip'),
                    right: 32,
                    bottom: 150,
                    child: ExcludeFocus(
                      child: SkipSegmentButton(
                        engine: controller.engine,
                        segments: view.segments,
                        onSkip: () =>
                            unawaited(controller.skipCurrentSegment()),
                      ),
                    ),
                  ),
                  // Scheda piccola negli ultimi 30 s senza titoli noti
                  // (spec D §12.2); sempre presente, il contenuto cambia.
                  Positioned(
                    key: const ValueKey('player-next-card'),
                    right: 32,
                    bottom: 150,
                    child: ExcludeFocus(
                      child: AnimatedSwitcher(
                        duration: WfMotion.fast,
                        switchInCurve: _offerSwitchInCurve,
                        switchOutCurve: WfMotion.accelerateReverse,
                        child: card && offer != null
                            ? NextEpisodeCard(
                                key: ValueKey(offer.id),
                                episode: offer,
                                label: _nextOfferLabel(l, view, offer),
                                // La coda del gruppo può mescolare serie: se
                                // il prossimo è di un'altra, si dice quale.
                                showSeries: offer.kind == ItemKind.episode &&
                                    offer.seriesId != view.item?.seriesId,
                                // Nel gruppo nessun conto alla rovescia: si
                                // va avanti con il pulsante o a fine video.
                                countdown: !_inParty && settings.autoplayNext,
                                paused: !view.playing || view.buffering,
                                onPlay: _playOffered,
                                onCancel: _dismissNext,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
                // Post-play: informazioni e pulsanti accanto al film piccolo
                // (spec D §12.1); sempre presente, il contenuto cambia.
                Positioned.fill(
                  key: const ValueKey('player-post-play'),
                  child: ExcludeFocus(
                    child: AnimatedSwitcher(
                      duration: WfMotion.fast,
                      switchInCurve: _offerSwitchInCurve,
                      switchOutCurve: WfMotion.accelerateReverse,
                      child: postPlay && offer != null
                          ? SizedBox.expand(
                              key: ValueKey(offer.id),
                              child: PostPlayLayer(
                                episode: offer,
                                label: _nextOfferLabel(l, view, offer),
                                countdown: !_inParty && settings.autoplayNext,
                                paused: !view.playing || view.buffering,
                                onPlay: _playOffered,
                                onWatchCredits: _dismissNext,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                // Attesa del gruppo durante il post-play: sopra di lui, come
                // sopra "Stai guardando" (spec D §15.3, §19: i due momenti
                // non si sovrappongono). Sempre presente: sparita, non è
                // nell'albero. Se il post-play compare o si chiude durante
                // l'attesa, l'attesa passa da uno strato all'altro e torna
                // dopo il suo secondo di ritardo.
                Positioned.fill(
                  key: const ValueKey('player-party-waiting-post-play'),
                  child: ExcludeFocus(
                    child: PartyWaitingOverlay(
                      waiting: groupWaiting && postPlay,
                      onResume: resumeGroup,
                    ),
                  ),
                ),
                // Reazioni in volo (spec E §10.4): in basso a destra, sotto
                // la chat; non prendono i clic.
                if (chatActive)
                  const Positioned(
                    key: ValueKey('player-party-reactions'),
                    right: PartyReactionsLayer.right,
                    bottom: PartyReactionsLayer.bottom,
                    child: PartyReactionsLayer(),
                  ),
                // Chat del watch party (spec E §9): in basso a sinistra,
                // sopra post-play e attese, sotto la pillola e il pannello.
                // Non è dentro `ExcludeFocus`: il suo campo prende il focus.
                if (chatActive)
                  Positioned(
                    key: const ValueKey('player-party-chat'),
                    left: PartyChatLayer.left,
                    bottom: PartyChatLayer.bottom,
                    child: PartyChatLayer(
                      open: _chrome.chatOpen,
                      focusNode: _chatFocusNode,
                      onOpen: () => _chrome.openPopup(PlayerPopup.chat),
                      onClose: () => _chrome.closePopup(PlayerPopup.chat),
                    ),
                  ),
                // Barretta delle reazioni (spec E §10.2): segue il suo
                // pulsante nei controlli; sopra chat, "Salta intro" e scheda.
                if (chatActive)
                  Positioned(
                    key: const ValueKey('player-party-reactions-tray'),
                    left: 0,
                    top: 0,
                    child: CompositedTransformFollower(
                      link: _reactionsLink,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.topRight,
                      followerAnchor: Alignment.bottomRight,
                      offset: const Offset(0, -PartyReactionsTray.gap),
                      child: ExcludeFocus(
                        child: PartyReactionsTray(
                          open: _chrome.popup == PlayerPopup.reactions,
                          onReaction: _sendReaction,
                          onClose: () =>
                              _chrome.closePopup(PlayerPopup.reactions),
                        ),
                      ),
                    ),
                  ),
                // Riscontro dei tasti e avvisi del watch party (anche dopo
                // l'uscita dal gruppo: "terminato" e "non sei più nel watch
                // party" devono vedersi).
                Positioned(
                  key: const ValueKey('player-pill-layer'),
                  top: 96,
                  left: 0,
                  right: 0,
                  child: ExcludeFocus(
                    child: IgnorePointer(
                      child: Center(
                        child: RepaintBoundary(
                          child: widget.args.party == null
                              ? PlayerPill(feedback: _chrome.feedback)
                              : Consumer(
                                  builder: (context, ref, _) => PlayerPill(
                                    feedback: _chrome.feedback,
                                    notice: ref.watch(partyNoticesProvider),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Pannello "Audio e sottotitoli": scorre da destra, a tutta
                // altezza sopra i controlli (spec D §14).
                Positioned.fill(
                  key: const ValueKey('player-tracks-panel'),
                  child: ExcludeFocus(
                    child: PlayerSidePanelHost(
                      open: _chrome.panelOpen && view.plan != null,
                      panel: TracksPanel(
                        audio: view.audioStreams,
                        subtitles: view.subtitleStreams,
                        audioIndex: view.audioIndex,
                        subtitleIndex: view.subtitleIndex,
                        subtitleDelay: view.subtitleDelay,
                        subtitleScale: settings.subtitleScale,
                        onAudio: (index) =>
                            unawaited(controller.selectAudio(index)),
                        onSubtitle: (index) =>
                            unawaited(controller.selectSubtitle(index)),
                        onDelayStep: (step) =>
                            unawaited(controller.shiftSubtitleDelay(step)),
                        onSubtitleScale: (scale) =>
                            unawaited(controller.setSubtitleScale(scale)),
                        onClose: _chrome.closePanel,
                      ),
                    ),
                  ),
                ),
                // Pannello "Coda" del watch party (spec H §9.1): come quello
                // delle tracce, a destra sopra i controlli.
                if (party != null)
                  Positioned.fill(
                    key: const ValueKey('player-queue-panel'),
                    child: ExcludeFocus(
                      child: PlayerSidePanelHost(
                        open: _chrome.popup == PlayerPopup.queue &&
                            party.inGroup,
                        panel: PartyQueuePanel(
                          onClose: () =>
                              _chrome.closePopup(PlayerPopup.queue),
                          // Come ⏮ e ⏭: il `Seek` in sospeso non deve
                          // arrivare dopo il salto di riga.
                          onBeforeJump: () => _authority?.cancelPendingSeek(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
