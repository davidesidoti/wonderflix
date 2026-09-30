import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
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
import '../watch_party/party_waiting_overlay.dart';
import '../watch_party/watch_party_session.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'player_extras.dart';
import 'player_active.dart';
import 'player_overlay.dart';
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

  /// Inattività del mouse dopo cui i controlli spariscono.
  static const hideDelay = Duration(seconds: 3);

  /// Attesa massima del report di fine alla chiusura della finestra.
  static const closeTimeout = Duration(seconds: 2);

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerWindow _window;
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _tracksOpen = false;
  late bool _fullscreen = widget.fullscreen;
  bool _leaving = false;

  /// Si passa all'episodio successivo: la finestra resta com'è.
  bool _handingOver = false;

  /// L'utente ha chiuso la scheda "Prossimo episodio".
  bool _nextCardDismissed = false;

  late final PlayerActiveController _playerActive;
  late final MediaSession _mediaSession;
  StreamSubscription<MediaButton>? _mediaButtons;
  Timer? _timelineTimer;

  /// Nel watch party: applica i comandi del gruppo al motore.
  GroupPlaybackDriver? _driver;

  bool get _inParty => widget.args.party != null;

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.args).notifier);

  @override
  void initState() {
    super.initState();
    _playerActive = ref.read(playerActiveProvider.notifier)..enter();
    _window = ref.read(playerWindowProvider);
    _window.addCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(true));
    // Sessione condivisa: con l'episodio successivo la nuova schermata
    // parte prima che la vecchia sia chiusa.
    _mediaSession = ref.read(mediaSessionProvider);
    _mediaButtons = _mediaSession.buttons.listen(_onMediaButton);
    // Il "successivo" dell'episodio precedente non vale per questo: si
    // riattiva quando arriva il suo episodio successivo.
    unawaited(_mediaSession.setNextEnabled(false));
    _timelineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendTimeline());
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _window.removeCloseListener(_onWindowClose);
    unawaited(_window.setPreventClose(false));
    if (_fullscreen && !_handingOver) unawaited(_window.setFullScreen(false));
    _timelineTimer?.cancel();
    unawaited(_mediaButtons?.cancel());
    // Uscendo dal player il pannello media sparisce; passando all'episodio
    // successivo resta alla nuova schermata. Non si chiude mai: è dell'app.
    if (!_handingOver) unawaited(_mediaSession.clear());
    _playerActive.leave();
    unawaited(_driver?.dispose());
    super.dispose();
  }

  Future<void> _onWindowClose() async {
    await Future.wait([
      _controller.close(),
      if (_inParty) ref.read(watchPartySessionProvider.notifier).leave(),
    ]).timeout(PlayerScreen.closeTimeout, onTimeout: () => const []);
    await _window.destroy();
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  /// I controlli si nascondono solo durante la riproduzione e a pannello
  /// chiuso.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerScreen.hideDelay, () {
      if (!mounted || _tracksOpen) return;
      if (!ref.read(playerControllerProvider(widget.args)).playing) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleTracks() {
    setState(() => _tracksOpen = !_tracksOpen);
    _showControls();
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
    final view = ref.read(playerControllerProvider(widget.args));
    final next = view.nextEpisode;
    if (next == null || _leaving || _inParty) return;
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
        playerRoute(next.id, start: start, fullscreen: _fullscreen));
  }

  /// Fine del video: episodio successivo se previsto, altrimenti uscita.
  void _onFinished() {
    // Nel watch party la fine la decide il gruppo: si resta sul video.
    if (_inParty) return;
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
    if (party == null || _driver != null) return;
    final current = ref.read(watchPartySessionProvider);
    final session = ref.read(watchPartySessionProvider.notifier);
    final serverClock = session.serverClock;
    if (!current.inGroup || serverClock == null) return;
    _driver = GroupPlaybackDriver(
      engine: controller.engine,
      api: session.api,
      clock: serverClock,
      playlistItemId: party,
      commands: session.commands,
      lastCommand: session.lastCommand,
    )..start();
    controller.setAuthority(
        GroupAuthority(api: session.api, engine: controller.engine));
  }

  /// Il server ci ha tolto dal gruppo: si continua da soli.
  void _detachParty() {
    final driver = _driver;
    _driver = null;
    unawaited(driver?.dispose());
    _controller.setAuthority(null);
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

  /// Tasti del pannello media e della tastiera multimediale.
  void _onMediaButton(MediaButton button) {
    if (!mounted || _leaving) return;
    switch (button) {
      case MediaButton.play:
        unawaited(_controller.play());
      case MediaButton.pause:
        unawaited(_controller.pause());
      case MediaButton.next:
        _playNext();
      case MediaButton.stop:
        _exit();
    }
  }

  void _escape() {
    if (_tracksOpen) {
      setState(() => _tracksOpen = false);
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

  void _run(PlayerCommand command) {
    final controller = _controller;
    switch (command) {
      case PlayerCommand.togglePlay:
        unawaited(controller.togglePlay());
      case PlayerCommand.seekBack:
        unawaited(controller.seekBy(-seekStep));
      case PlayerCommand.seekForward:
        unawaited(controller.seekBy(seekStep));
      case PlayerCommand.volumeUp:
        unawaited(controller.changeVolumeBy(volumeStep));
      case PlayerCommand.volumeDown:
        unawaited(controller.changeVolumeBy(-volumeStep));
      case PlayerCommand.toggleMute:
        unawaited(controller.toggleMute());
      case PlayerCommand.subtitleDelayDown:
        unawaited(controller.shiftSubtitleDelay(-subtitleDelayStep));
      case PlayerCommand.subtitleDelayUp:
        unawaited(controller.shiftSubtitleDelay(subtitleDelayStep));
      case PlayerCommand.toggleFullscreen:
        unawaited(_toggleFullscreen());
      case PlayerCommand.nextEpisode:
        _playNext();
        return;
      case PlayerCommand.escape:
        _escape();
        return;
      case PlayerCommand.exit:
        _exit();
        return;
    }
    _showControls();
  }

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

    ref.listen(provider.select((s) => s.finished), (_, finished) {
      if (finished) _onFinished();
    });
    ref.listen(provider.select((s) => s.playing), (_, playing) {
      if (playing) _scheduleHide();
      unawaited(_mediaSession.setPlaying(playing));
    });
    ref.listen(provider.select((s) => s.item), (_, item) {
      if (item != null) _publishMetadata(item);
    });
    ref.listen(provider.select((s) => s.nextEpisode != null), (_, hasNext) {
      unawaited(_mediaSession.setNextEnabled(hasNext));
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
        if (previous == PlayerStatus.ready) _driver?.onUnloaded();
        return;
      }
      final driver = _driver;
      if (driver != null) {
        unawaited(driver.onLoaded());
      } else if (_inParty) {
        // Gruppo non disponibile: il player parte da solo.
        unawaited(controller.play());
      }
    });
    if (_inParty) {
      ref.listen(watchPartySessionProvider.select((s) => s.inGroup),
          (_, inGroup) {
        if (!inGroup && _driver != null) _detachParty();
      });
    }

    final loading = view.status == PlayerStatus.loading ||
        (view.status == PlayerStatus.ready && view.buffering);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) _exit();
          },
          child: MouseRegion(
            cursor: _controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onHover: (_) => _showControls(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_tracksOpen) {
                      setState(() => _tracksOpen = false);
                    } else {
                      unawaited(controller.togglePlay());
                    }
                  },
                  onDoubleTap: () => unawaited(_toggleFullscreen()),
                  child: controller.engine.buildView(),
                ),
                if (loading)
                  const Center(
                      child: CircularProgressIndicator(color: WfColors.gold)),
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
                  _PlayerError(
                    error: view.error,
                    onRetry: () => unawaited(controller.retry()),
                    onBack: _exit,
                  )
                else
                  // I controlli non prendono il focus della tastiera: le
                  // scorciatoie restano sempre attive.
                  ExcludeFocus(
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        key: const Key('player-controls'),
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: PlayerOverlay(
                          view: view,
                          engine: controller.engine,
                          fullscreen: _fullscreen,
                          onBack: _exit,
                          onTogglePlay: () =>
                              unawaited(controller.togglePlay()),
                          onSeekBy: (offset) =>
                              unawaited(controller.seekBy(offset)),
                          onSeekTo: (position) =>
                              unawaited(controller.seekTo(position)),
                          onVolume: (volume) =>
                              unawaited(controller.setVolume(volume)),
                          onToggleMute: () =>
                              unawaited(controller.toggleMute()),
                          onToggleTracks: _toggleTracks,
                          onToggleFullscreen: () =>
                              unawaited(_toggleFullscreen()),
                          onNextEpisode:
                              next == null || _inParty ? null : _playNext,
                          chapters: view.item?.chapters ?? const [],
                          preview: _previewFor(view),
                          partyBadge: party != null && party.inGroup
                              ? PartyBadge(onLeave: _exit)
                              : null,
                        ),
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
                  if (next != null && !_nextCardDismissed && !_inParty)
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
                                  countdown: settings.autoplayNext,
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
                if (_tracksOpen && view.plan != null)
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

class _PlayerError extends StatelessWidget {
  const _PlayerError({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final failure = error;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.circleAlert, size: 44, color: WfColors.error),
          const SizedBox(height: 16),
          Text(l.playerErrorTitle, style: WfText.display(34)),
          const SizedBox(height: 8),
          Text(
            failure == null ? l.errorGeneric : describeError(l, failure),
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            children: [
              WfButton.primary(
                  label: l.retry,
                  icon: LucideIcons.rotateCcw,
                  onPressed: onRetry),
              WfButton.secondary(
                  label: l.playerBack,
                  icon: LucideIcons.arrowLeft,
                  onPressed: onBack),
            ],
          ),
        ],
      ),
    );
  }
}
