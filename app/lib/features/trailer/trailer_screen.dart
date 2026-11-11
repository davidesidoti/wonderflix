import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/trailers/trailers_api.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../player/player_overlay.dart';
import '../player/player_commands.dart';
import '../player/player_providers.dart';
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
      if (mounted) setState(() => _openFailed = true);
      return;
    }
    if (!mounted) return;
    setState(() {});
    // Il volume ricordato del player; il muto no.
    await engine.setVolume(ref.read(playerVolumeProvider));
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
    unawaited(engine.seek(target));
  }

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
      // Sulla TV "Chiudi" non prende il focus: OK lo preme.
      if (down) _unavailable ? _close() : _togglePlay();
      return KeyEventResult.handled;
    }
    // Sulla TV il volume lo regola il telecomando.
    if (!FormFactor.of(context).tv) {
      final volume = ref.read(playerVolumeProvider);
      if (key == LogicalKeyboardKey.arrowUp) {
        _setVolume(volume + volumeStep);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _setVolume(volume - volumeStep);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyM) {
        if (down) _toggleMute();
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
          onTap: _showControls,
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
                        focusable(
                          FilledButton(
                            onPressed: _close,
                            child: Text(l.trailerClose),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (engine == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: WfColors.gold),
                        const SizedBox(height: 24),
                        Text(l.trailerPreparing, style: WfText.display(28)),
                      ],
                    ),
                  ),
                IgnorePointer(
                  ignoring: !controls,
                  child: AnimatedOpacity(
                    opacity: controls ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: focusable(
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Row(
                              children: [
                                PlayerIconButton(
                                  icon: const Icon(LucideIcons.x),
                                  tooltip: l.trailerClose,
                                  onPressed: _close,
                                ),
                                const SizedBox(width: 12),
                                if (title != null)
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: WfText.display(28),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (playable)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 16,
                              child: Row(
                                children: [
                                  PlayerIconButton(
                                    icon: PlayPauseIcon(playing: _playing),
                                    tooltip: _playing
                                        ? l.playerPause
                                        : l.actionPlay,
                                    onPressed: _togglePlay,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    // Sulla TV si salta con le frecce.
                                    child: IgnorePointer(
                                      ignoring: tv,
                                      child: SeekBar(
                                        engine: engine,
                                        onSeek: (p) =>
                                            unawaited(engine.seek(p)),
                                      ),
                                    ),
                                  ),
                                  if (!tv) ...[
                                    PlayerIconButton(
                                      icon: Icon(_muted || volume == 0
                                          ? LucideIcons.volumeX
                                          : LucideIcons.volume2),
                                      tooltip: _muted
                                          ? l.playerUnmute
                                          : l.playerMute,
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
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                              trackHeight: 3,
                                              activeTrackColor: WfColors.cream,
                                              inactiveTrackColor: WfColors.cream
                                                  .withValues(alpha: 0.2),
                                              thumbColor: WfColors.cream,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                      enabledThumbRadius: 6),
                                            ),
                                            child: Slider(
                                              key: const Key(
                                                  'trailer-volume-slider'),
                                              value: _muted ? 0 : volume,
                                              max: 100,
                                              onChanged: _setVolume,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_blocked && playable)
                  Positioned.fill(
                    child: Center(
                      child: focusable(
                        IconButton(
                          key: const ValueKey('trailer-tap-to-play'),
                          iconSize: 96,
                          color: WfColors.cream,
                          tooltip: l.actionPlay,
                          icon: const Icon(LucideIcons.play),
                          onPressed: () => unawaited(engine.play()),
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
