import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/trailers/trailers_api.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../player/player_chrome.dart';
import '../player/player_commands.dart';
import '../player/player_keys.dart';
import '../player/player_loading.dart';
import '../player/player_overlay.dart';
import '../player/player_pill.dart';
import '../player/player_providers.dart';
import '../player/player_time.dart';
import '../player/player_volume.dart';
import '../player/seek_bar.dart';
import 'trailer_controller.dart';

/// Trailer a schermo intero: aspetta che il plugin lo prepari (sullo sfondo
/// del titolo), lo riproduce e si chiude alla fine.
class TrailerScreen extends ConsumerStatefulWidget {
  const TrailerScreen({
    super.key,
    required this.subject,
    this.title,
    this.backdropItemId,
  });

  final TrailerSubject subject;
  final String? title;
  final String? backdropItemId;

  /// Come nel player: i controlli spariscono dopo 3 s senza input.
  static const hideDelay = Duration(seconds: 3);
  static const seekStep = Duration(seconds: 10);

  @override
  ConsumerState<TrailerScreen> createState() => _TrailerScreenState();
}

class _TrailerScreenState extends ConsumerState<TrailerScreen> {
  late final TrailerController _controller;
  final _focusNode = FocusNode(debugLabel: 'trailer');

  /// Solo per il riscontro dei tasti (pastiglia): il resto resta qui.
  final _chrome = PlayerChromeController();
  final _subscriptions = <StreamSubscription<Object?>>[];
  VideoEngine? _engine;
  bool _openFailed = false;
  bool _playing = false;
  bool _blocked = false;
  bool _muted = false;
  bool _controlsVisible = true;
  bool _leaving = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller =
        TrailerController(ref.read(trailersApiProvider), widget.subject)
          ..addListener(_onPhase)
          ..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    _hideTimer?.cancel();
    _chrome.dispose();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_engine?.dispose());
    _focusNode.dispose();
    super.dispose();
  }

  void _onPhase() {
    if (!mounted) return;
    setState(() {});
    final phase = _controller.value;
    // Il "Chiudi" al centro ha l'autofocus: vale solo se il focus è libero.
    if (phase is TrailerUnavailable) _focusNode.unfocus();
    if (phase is TrailerReady) unawaited(_open(phase.url));
  }

  Future<void> _open(String url) async {
    final engine = ref.read(videoEngineFactoryProvider)();
    _engine = engine;
    _subscriptions
      ..add(
        engine.playingStream.listen((playing) {
          if (!mounted) return;
          setState(() {
            _playing = playing;
            if (playing) _blocked = false;
          });
          _showControls();
        }),
      )
      ..add(
        engine.playBlockedStream.listen((_) {
          if (mounted) setState(() => _blocked = true);
        }),
      )
      ..add(
        engine.completedStream.listen((completed) {
          if (completed) _close();
        }),
      );
    try {
      // media_kit e Media3 usano l'header; il browser il token nell'URL.
      await engine.open(
        VideoSource(
          url: url,
          headers: {
            'Authorization': ref.read(jellyfinHttpProvider).authorizationHeader,
          },
        ),
      );
    } on EngineOpenException {
      if (mounted) {
        _focusNode.unfocus();
        setState(() => _openFailed = true);
      }
      return;
    }
    if (!mounted) return;
    setState(() {});
    // Il volume ricordato del player; il muto no.
    await engine.setVolume(_muted ? 0 : ref.read(playerVolumeProvider));
    await engine.play();
  }

  /// 0–100: toglie il muto e diventa il volume ricordato anche per i film.
  void _setVolume(double volume) {
    final value = volume.clamp(0.0, 100.0);
    ref.read(playerVolumeProvider.notifier).set(value);
    setState(() => _muted = false);
    unawaited(_engine?.setVolume(value));
  }

  void _toggleMute() {
    final muted = !_muted;
    setState(() => _muted = muted);
    unawaited(_engine?.setVolume(muted ? 0 : ref.read(playerVolumeProvider)));
  }

  /// Mostra i controlli; in riproduzione si nascondono dopo [hideDelay].
  void _showControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (!_playing) return;
    _hideTimer = Timer(TrailerScreen.hideDelay, () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    final engine = _engine;
    if (engine == null) return;
    unawaited(engine.playing ? engine.pause() : engine.play());
  }

  void _seekBy(Duration delta) {
    final engine = _engine;
    if (engine == null) return;
    var target = engine.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (engine.duration > Duration.zero && target > engine.duration) {
      target = engine.duration;
    }
    _chrome.seek(delta, from: engine.position, duration: engine.duration);
    unawaited(engine.seek(target));
  }

  void _volumeFeedback() => _chrome.showFeedback(
      VolumeFeedback(volume: ref.read(playerVolumeProvider), muted: _muted));

  void _close() {
    if (_leaving || !mounted) return;
    _leaving = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  bool get _unavailable =>
      _openFailed || _controller.value is TrailerUnavailable;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    // Su Android il Back arriva prima come tasto e poi come pop di sistema:
    // chiude solo il pop.
    if (key == LogicalKeyboardKey.goBack || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    _showControls();
    final down = event is KeyDownEvent;
    if (key == LogicalKeyboardKey.escape) {
      if (down) _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      // Senza trailer il "Chiudi" ha il focus, ma OK lo preme anche da qui.
      if (down) _unavailable ? _close() : _togglePlay();
      return KeyEventResult.handled;
    }
    // Sulla TV il volume lo regola il telecomando; senza trailer non c'è nulla
    // da regolare (e il volume ricordato non va toccato).
    if (!FormFactor.of(context).tv && _engine != null && !_unavailable) {
      final volume = ref.read(playerVolumeProvider);
      if (key == LogicalKeyboardKey.arrowUp) {
        _setVolume(volume + volumeStep);
        _volumeFeedback();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _setVolume(volume - volumeStep);
        _volumeFeedback();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyM) {
        if (down) {
          _toggleMute();
          _volumeFeedback();
        }
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(TrailerScreen.seekStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-TrailerScreen.seekStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tv = FormFactor.of(context).tv;
    final touch = FormFactor.of(context).touch;
    final volume = ref.watch(playerVolumeProvider);
    final engine = _engine;
    final unavailable = _unavailable;
    final playable = engine != null && !unavailable;
    final backdropId = widget.backdropItemId;
    final title = widget.title;
    final controls = !playable || _controlsVisible;

    // Sulla TV i tasti fanno tutto: nessun pulsante prende il focus.
    Widget focusable(Widget child) => tv ? ExcludeFocus(child: child) : child;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: controls ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _showControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Col mouse un clic sul video è pausa (come nel player), col dito
          // mostra i controlli.
          onTap: touch ? _showControls : _togglePlay,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (playable)
                  engine.buildView()
                else if (backdropId != null)
                  Opacity(
                    opacity: 0.35,
                    child: WfImage(
                      image: ref
                          .watch(imageUrlsProvider)
                          .backdropOf(backdropId, maxWidth: 1920),
                      fallbackIcon: null,
                    ),
                  ),
                if (unavailable)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.trailerUnavailable, style: WfText.display(34)),
                        const SizedBox(height: 24),
                        // Anche sulla TV prende il focus: è l'unico pulsante.
                        WfButton.secondary(
                          label: l.trailerClose,
                          icon: LucideIcons.x,
                          autofocus: true,
                          onPressed: _close,
                        ),
                      ],
                    ),
                  )
                else if (engine == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LoadingLine(),
                        const SizedBox(height: 24),
                        Text(l.trailerPreparing, style: WfText.display(28)),
                      ],
                    ),
                  ),
                // Sotto i comandi: il "Chiudi" resta cliccabile.
                if (_blocked && playable)
                  PlayBlockedLayer(
                    key: const ValueKey('trailer-tap-to-play'),
                    onPlay: () => unawaited(engine.play()),
                  ),
                IgnorePointer(
                  ignoring: !controls,
                  child: AnimatedOpacity(
                    opacity: controls ? 1 : 0,
                    duration: controls
                        ? WfMotion.of(context).duration(WfMotion.medium)
                        : WfMotion.fast,
                    curve: controls ? WfMotion.emphasized : WfMotion.accelerate,
                    child: focusable(
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _gradient(
                              top: true,
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(24, 16, 24, 48),
                                  child: Row(
                                    children: [
                                      if (title != null)
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: WfText.display(28),
                                          ),
                                        )
                                      else
                                        const Spacer(),
                                      // Senza trailer il "Chiudi" è quello
                                      // al centro.
                                      if (!unavailable) ...[
                                        const SizedBox(width: 16),
                                        WfButton.secondary(
                                          label: l.trailerClose,
                                          icon: LucideIcons.x,
                                          onPressed: _close,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (playable)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _gradient(
                                top: false,
                                child: SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 48, 24, 16),
                                    child: _bottomRow(
                                        context, l, engine, volume, tv, touch),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (playable)
                  Positioned.fill(
                    child: ExcludeFocus(
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 96),
                            child: ListenableBuilder(
                              listenable: _chrome,
                              builder: (context, _) =>
                                  PlayerPill(feedback: _chrome.feedback),
                            ),
                          ),
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

  /// Sfumatura scura sotto i comandi, come in `PlayerOverlay`.
  Widget _gradient({required bool top, required Widget child}) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [
              WfColors.bg.withValues(alpha: top ? 0.8 : 0.9),
              WfColors.bg.withValues(alpha: 0),
            ],
          ),
        ),
        child: child,
      );

  Widget _bottomRow(BuildContext context, AppLocalizations l,
      VideoEngine engine, double volume, bool tv, bool touch) {
    return Row(
      children: [
        PlayerIconButton(
          icon: PlayPauseIcon(playing: _playing),
          tooltip: _playing ? l.playerPause : l.actionPlay,
          shortcut: l.playerKeySpace,
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 12),
        RepaintBoundary(child: PositionLabel(engine: engine)),
        const SizedBox(width: 12),
        Expanded(
          // Sulla TV si salta con le frecce.
          child: IgnorePointer(
            ignoring: tv,
            child: SeekBar(
              engine: engine,
              onSeek: (p) => unawaited(engine.seek(p)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        RepaintBoundary(child: RemainingLabel(engine: engine, withEnd: false)),
        if (!tv) ...[
          const SizedBox(width: 4),
          PlayerIconButton(
            icon: Icon(_muted || volume == 0
                ? LucideIcons.volumeX
                : LucideIcons.volume2),
            tooltip: _muted ? l.playerUnmute : l.playerMute,
            shortcut: 'M',
            onPressed: _toggleMute,
          ),
          // Col dito il volume è quello del telefono.
          if (!touch)
            SizedBox(
              width: 120,
              // Lo Slider vuole un Material sopra di sé.
              child: Material(
                type: MaterialType.transparency,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: WfColors.gold,
                    inactiveTrackColor: WfColors.cream.withValues(alpha: 0.25),
                    thumbColor: WfColors.gold,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: KeyTooltip(
                    message: l.playerVolume,
                    shortcut: '↑/↓',
                    child: Slider(
                      key: const Key('trailer-volume-slider'),
                      value: _muted ? 0 : volume,
                      max: 100,
                      onChanged: _setVolume,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
