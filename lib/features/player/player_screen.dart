import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/media_session/media_session.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../detail/primary_action.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../watch_party/group_authority.dart';
import '../watch_party/group_playback_driver.dart';
import '../watch_party/party_badge.dart';
import '../watch_party/party_notices.dart';
import '../watch_party/party_waiting_overlay.dart';
import '../watch_party/watch_party_actions.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';
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
import 'player_window.dart';
import 'segments.dart';
import 'tracks_panel.dart';
import 'trickplay.dart';
import 'trickplay_preview.dart';

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

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerWindow _window;

  /// Controlli, pannello e riscontro dei tasti (spec D §5.1).
  final _chrome = PlayerChromeController();

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

  /// Il routing del watch party segnala qui che sostituisce questo player
  /// da solo con quello del gruppo (letto alla chiusura, senza `ref`).
  late final PlayerHandover _handover;

  /// L'utente ha chiuso la scheda "Prossimo episodio".
  bool _nextCardDismissed = false;

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
    // Discord: quante persone nel watch party (`null` fuori da un gruppo).
    unawaited(_mediaSession.setParty(
        party != null && party.inGroup ? party.members.length : null));
    _timelineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendTimeline());
    _chrome.addListener(_onChromeChanged);
    // Il caricamento resta finché il motore non disegna il primo
    // fotogramma (spec D §10.1).
    unawaited(_controller.engine.firstFrame.then((_) => _onFirstFrame()));
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
    _window.removeCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(false));
    if (_fullscreen && !handingOver) unawaited(_window.setFullScreen(false));
    _timelineTimer?.cancel();
    _firstFrameTimer?.cancel();
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
    await Future.wait([
      _controller.close(),
      if (_inParty) ref.read(watchPartySessionProvider.notifier).leave(),
    ]).timeout(PlayerScreen.closeTimeout, onTimeout: () => const []);
    await _window.destroy();
  }

  void _onChromeChanged() {
    if (mounted) setState(() {});
  }

  void _onFirstFrame() {
    _firstFrameTimer?.cancel();
    if (mounted && !_firstFrame) setState(() => _firstFrame = true);
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
      if (!_leaving) {
        // Il `Seek` non dice l'elemento: partito dopo il cambio, salterebbe
        // nell'episodio nuovo.
        _authority?.cancelPendingSeek();
        unawaited(ref
            .read(watchPartySessionProvider.notifier)
            .nextItem(widget.args.party!));
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
    if (view.nextEpisode != null && autoplay && !_nextCardDismissed) {
      _playNext(finished: true);
    } else {
      _exit();
    }
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
      onAction: (kind, {position}) => notices.mine(kind,
          position: position, show: !_chrome.isRecentKeyAction(kind)),
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
  /// richiesta il pulsante non torna: si aspetta il player del gruppo.
  Future<void> _watchTogether() async {
    final item = ref.read(playerControllerProvider(widget.args)).item;
    if (item == null || _leaving || _startingParty) return;
    final start = _controller.engine.position;
    setState(() => _startingParty = true);
    final started = await startWatchParty(context, ref, item, start: start);
    if (!mounted || _leaving) return;
    if (!started) setState(() => _startingParty = false);
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

  void _escape() {
    if (_chrome.panelOpen) {
      _chrome.closePanel();
    } else if (_fullscreen) {
      unawaited(_toggleFullscreen());
    } else {
      _exit();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final command = playerCommandFor(event,
        altPressed: HardwareKeyboard.instance.isAltPressed,
        mediaKeys: !_mediaSession.handlesMediaKeys);
    if (command == null) return KeyEventResult.ignored;
    _run(command);
    return KeyEventResult.handled;
  }

  /// Comando da tastiera: la pillola mostra il riscontro (spec D §9), i
  /// controlli non compaiono. Il riscontro va dato **prima** del comando:
  /// nel watch party l'avviso "Hai…" che segue controlla che la pillola ci
  /// sia già (vedi [_attachParty]).
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
    final canWatchTogether = widget.args.party == null &&
        ref.watch(syncPlayAccessProvider).canCreate &&
        view.item != null &&
        !_startingParty;

    ref.listen(provider.select((s) => s.finished), (_, finished) {
      if (finished) _onFinished();
    });
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      _chrome.setPlayback(playing: playing);
      unawaited(_mediaSession.setPlaying(playing));
    });
    ref.listen(provider.select((s) => s.item), (_, item) {
      if (item != null) _publishMetadata(item);
    });
    ref.listen(provider.select((s) => s.nextEpisode != null), (_, hasNext) {
      // Nel gruppo il "successivo" segue la coda (vedi sotto).
      if (!_inParty) unawaited(_mediaSession.setNextEnabled(hasNext));
    });
    ref.listen(provider.select((s) => s.transcodingFallback), (_, fallback) {
      if (fallback) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.playerTranscoding)));
      }
    });
    ref.listen(provider.select((s) => s.status), (previous, status) {
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
    }
    if (_inParty) {
      ref.listen(
          watchPartySessionProvider.select((s) => s.inGroup && s.hasNext),
          (_, hasNext) {
        if (_inParty && !_leaving) {
          unawaited(_mediaSession.setNextEnabled(hasNext));
        }
      });
      ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
          (_, inGroup) {
        if (inGroup || _leaving) return;
        // Il server ci ha tolto dal gruppo: si continua da soli, con
        // l'episodio successivo come fuori da un watch party.
        setState(() => _partyDetached = true);
        _detachParty();
        _controller.leaveParty();
        unawaited(_mediaSession
            .setNextEnabled(ref.read(provider).nextEpisode != null));
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) _exit();
          },
          // Col tasto premuto (trascinamento della barra) `onHover` non
          // scatta: i movimenti tengono vivi i controlli.
          onPointerMove: (_) => _chrome.pointerActivity(),
          child: MouseRegion(
            cursor: _chrome.controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _chrome.pointerActivity(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_chrome.panelOpen) {
                      _chrome.closePanel();
                    } else {
                      unawaited(controller.togglePlay());
                    }
                  },
                  onDoubleTap: () => unawaited(_toggleFullscreen()),
                  child: controller.engine.buildView(),
                ),
                if (view.status == PlayerStatus.ready && !loading)
                  BufferingSpinner(buffering: view.buffering),
                if (party != null && view.status == PlayerStatus.ready)
                  Positioned.fill(
                    child: ExcludeFocus(
                      child: PartyWaitingOverlay(
                        waiting: party.inGroup &&
                            party.groupState == GroupState.waiting &&
                            !view.buffering,
                        onResume: () => unawaited(controller.play()),
                      ),
                    ),
                  ),
                if (view.status == PlayerStatus.error)
                  PlayerErrorLayer(
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
                    child: IgnorePointer(
                      ignoring: !_chrome.controlsVisible || loading,
                      child: PlayerOverlay(
                        // Durante il caricamento la freccia per uscire sta
                        // nello strato del caricamento.
                        visible: _chrome.controlsVisible && !loading,
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
                        chapters: view.item?.chapters ?? const [],
                        preview: _previewFor(view),
                        partyBadge: party != null && party.inGroup
                            ? PartyBadge(onLeave: _exit)
                            : null,
                        onWatchTogether: canWatchTogether
                            ? () => unawaited(_watchTogether())
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
                    right: 32,
                    bottom: 150,
                    child: ExcludeFocus(
                      child: PositionSelector<SkipKind?>(
                        engine: controller.engine,
                        select: (position) =>
                            skipTargetAt(view.segments, position)?.kind,
                        builder: (context, kind) => kind == null
                            ? const SizedBox.shrink()
                            : WfButton.secondary(
                                label: kind == SkipKind.intro
                                    ? l.playerSkipIntro
                                    : l.playerSkipRecap,
                                icon: LucideIcons.skipForward,
                                onPressed: () =>
                                    unawaited(controller.skipCurrentSegment()),
                              ),
                      ),
                    ),
                  ),
                  // Nel gruppo solo se l'episodio successivo della libreria è
                  // il prossimo della coda (che è quello che parte).
                  if (next != null &&
                      !_nextCardDismissed &&
                      (!_inParty || next.id == party?.nextEntry?.itemId))
                    Positioned(
                      right: 32,
                      bottom: 150,
                      child: ExcludeFocus(
                        child: PositionSelector<bool>(
                          engine: controller.engine,
                          select: (position) {
                            final from = nextEpisodeCardFrom(
                                view.segments, controller.engine.duration);
                            return from != null && position >= from;
                          },
                          builder: (context, show) => show
                              ? NextEpisodeCard(
                                  episode: next,
                                  // Nel gruppo nessun conto alla rovescia:
                                  // si va avanti con il pulsante o a fine
                                  // video (Piano 5b).
                                  countdown: !_inParty && settings.autoplayNext,
                                  paused: !view.playing || view.buffering,
                                  onPlay: _playNext,
                                  onCancel: () =>
                                      setState(() => _nextCardDismissed = true),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
                // Riscontro dei tasti e avvisi del watch party (anche dopo
                // l'uscita dal gruppo: "terminato" e "non sei più nel watch
                // party" devono vedersi).
                Positioned(
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
                if (_chrome.panelOpen && view.plan != null)
                  Positioned(
                    right: 24,
                    bottom: 120,
                    child: ExcludeFocus(
                      child: TracksPanel(
                        audio: view.audioStreams,
                        subtitles: view.subtitleStreams,
                        audioIndex: view.audioIndex,
                        subtitleIndex: view.subtitleIndex,
                        subtitleDelay: view.subtitleDelay,
                        onAudio: (index) =>
                            unawaited(controller.selectAudio(index)),
                        onSubtitle: (index) =>
                            unawaited(controller.selectSubtitle(index)),
                        onDelayStep: (step) =>
                            unawaited(controller.shiftSubtitleDelay(step)),
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
