import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'seek_bar.dart';
import 'seek_segments.dart';

/// Controlli in sovrimpressione: in alto indietro e titolo, in basso barra
/// di avanzamento e comandi. A controlli nascosti ([visible] `false`) la
/// parte alta sale e la bassa scende mentre sfumano (spec D §7.1).
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.view,
    required this.engine,
    required this.fullscreen,
    required this.onBack,
    required this.onTogglePlay,
    required this.onSeekBy,
    required this.onSeekTo,
    required this.onVolume,
    required this.onToggleMute,
    required this.onToggleTracks,
    required this.onToggleFullscreen,
    this.visible = true,
    this.onNextEpisode,
    this.onPrevious,
    this.partyQueue = false,
    this.chapters = const [],
    this.preview,
    this.partyBadge,
    this.onWatchTogether,
    this.onToggleChat,
    this.chatUnread = false,
    this.onToggleReactions,
    this.reactionsLink,
  });

  final PlayerViewState view;
  final VideoEngine engine;
  final bool fullscreen;
  final VoidCallback onBack;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleTracks;
  final VoidCallback onToggleFullscreen;

  /// Controlli mostrati.
  final bool visible;

  /// `null` se non c'è un episodio successivo.
  final VoidCallback? onNextEpisode;

  /// `null` se non c'è un titolo prima (spec H §9.1).
  final VoidCallback? onPrevious;

  /// Nel watch party ⏮ e ⏭ seguono la coda, che può avere anche film: i
  /// suggerimenti dicono "Titolo", non "Episodio".
  final bool partyQueue;
  final List<ChapterMark> chapters;
  final Widget? Function(Duration position)? preview;

  /// Distintivo del watch party, in alto a destra; `null` fuori dal gruppo.
  final Widget? partyBadge;

  /// "Guarda insieme" (solo da soli e con il permesso); `null` = nessun
  /// pulsante. Riceve il contesto del pulsante, per ancorare il menu delle
  /// modalità.
  final ValueChanged<BuildContext>? onWatchTogether;

  /// Chat del watch party (spec E §9.5): solo nel gruppo con il canale del
  /// plugin attivo; `null` = nessun pulsante. Sta dove fuori dal gruppo c'è
  /// "Guarda insieme".
  final VoidCallback? onToggleChat;

  /// Messaggi arrivati fuori dal player e non ancora letti: puntino oro.
  final bool chatUnread;

  /// Barretta delle reazioni del watch party (spec E §10.2): alle stesse
  /// condizioni della chat; `null` = nessun pulsante.
  final VoidCallback? onToggleReactions;

  /// Aggancio della barretta al pulsante (la barretta è un livello a sé del
  /// player).
  final LayerLink? reactionsLink;

  /// Di quanto la parte alta sale e la bassa scende a controlli nascosti.
  static const hiddenShift = 24.0;

  /// [child] agganciato a [link] (se c'è), per un livello che lo segue.
  static Widget _anchored(LayerLink? link, Widget child) => link == null
      ? child
      : CompositedTransformTarget(link: link, child: child);

  /// Parte alta o bassa: sfuma e scivola verso il suo bordo. Entrata
  /// `medium`, uscita `fast`; con le animazioni ridotte solo dissolvenza.
  Widget _part(BuildContext context,
      {required Key key, required bool top, required Widget child}) {
    final motion = WfMotion.of(context);
    final duration =
        visible ? motion.duration(WfMotion.medium) : WfMotion.fast;
    final curve = visible ? WfMotion.emphasized : WfMotion.accelerate;
    final shift = visible || motion.isReduced
        ? 0.0
        : (top ? -hiddenShift : hiddenShift);
    return AnimatedOpacity(
      key: key,
      opacity: visible ? 1 : 0,
      duration: duration,
      curve: curve,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        transform: Matrix4.translationValues(0, shift, 0),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = view.item;
    final episode = item != null && item.kind == ItemKind.episode
        ? cardSubtitle(item)
        : null;
    final volume = view.muted ? 0.0 : view.volume;

    return IconButtonTheme(
      data: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: WfColors.cream)),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _part(
              context,
              key: const Key('player-controls-top'),
              top: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      WfColors.bg.withValues(alpha: 0.8),
                      WfColors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 24, 48),
                  child: Row(
                    children: [
                      PlayerIconButton(
                        icon: const Icon(LucideIcons.arrowLeft),
                        tooltip: l.navBack,
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 8),
                      if (item != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cardTitle(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WfText.display(28)),
                              if (episode != null)
                                Text(episode,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: WfColors.creamMuted)),
                            ],
                          ),
                        ),
                      if (partyBadge != null) ...[
                        if (item == null) const Spacer(),
                        const SizedBox(width: 16),
                        partyBadge!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _part(
              context,
              key: const Key('player-controls-bottom'),
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      WfColors.bg.withValues(alpha: 0.9),
                      WfColors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SeekBar(
                        engine: engine,
                        onSeek: onSeekTo,
                        chapters: chapters,
                        zones: seekZones(view.segments),
                        preview: preview,
                      ),
                      Row(
                        children: [
                          PlayerIconButton(
                            icon: const Icon(LucideIcons.rewind),
                            tooltip: l.playerRewind,
                            onPressed: () => onSeekBy(-seekStep),
                          ),
                          PlayerIconButton(
                            iconSize: 34,
                            icon: PlayPauseIcon(playing: view.playing),
                            tooltip:
                                view.playing ? l.playerPause : l.actionPlay,
                            onPressed: onTogglePlay,
                          ),
                          PlayerIconButton(
                            icon: const Icon(LucideIcons.fastForward),
                            tooltip: l.playerForward,
                            onPressed: () => onSeekBy(seekStep),
                          ),
                          const SizedBox(width: 8),
                          PlayerIconButton(
                            icon: Icon(volume == 0
                                ? LucideIcons.volumeX
                                : LucideIcons.volume2),
                            tooltip:
                                view.muted ? l.playerUnmute : l.playerMute,
                            onPressed: onToggleMute,
                          ),
                          SizedBox(
                            width: 120,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: WfColors.cream,
                                inactiveTrackColor:
                                    WfColors.cream.withValues(alpha: 0.2),
                                thumbColor: WfColors.cream,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                key: const Key('volume-slider'),
                                value: volume,
                                max: 100,
                                onChanged: onVolume,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          RepaintBoundary(child: TimeLabel(engine: engine)),
                          const Spacer(),
                          if (onPrevious != null)
                            PlayerIconButton(
                              icon: const Icon(LucideIcons.skipBack),
                              tooltip: partyQueue
                                  ? l.playerPreviousInQueue
                                  : l.playerPreviousEpisode,
                              onPressed: onPrevious,
                            ),
                          if (onNextEpisode != null)
                            PlayerIconButton(
                              icon: const Icon(LucideIcons.skipForward),
                              tooltip: partyQueue
                                  ? l.playerNextInQueue
                                  : l.playerNextEpisode,
                              onPressed: onNextEpisode,
                            ),
                          if (onWatchTogether != null)
                            Builder(
                              builder: (buttonContext) => PlayerIconButton(
                                icon: const Icon(LucideIcons.users),
                                tooltip: l.watchPartyWatchTogether,
                                onPressed: () =>
                                    onWatchTogether!(buttonContext),
                              ),
                            ),
                          if (onToggleChat != null)
                            PlayerIconButton(
                              key: const Key('player-chat-button'),
                              icon: _WithDot(
                                show: chatUnread,
                                child: const Icon(LucideIcons.messageCircle),
                              ),
                              tooltip: l.partyChatOpen,
                              onPressed: onToggleChat,
                            ),
                          if (onToggleReactions != null)
                            _anchored(
                              reactionsLink,
                              PlayerIconButton(
                                key: const Key('player-reactions-button'),
                                icon: const Icon(LucideIcons.smilePlus),
                                tooltip: l.partyReactionsOpen,
                                onPressed: onToggleReactions,
                              ),
                            ),
                          PlayerIconButton(
                            icon: const Icon(LucideIcons.captions),
                            tooltip: l.playerAudioAndSubtitles,
                            onPressed: onToggleTracks,
                          ),
                          PlayerIconButton(
                            icon: Icon(fullscreen
                                ? LucideIcons.minimize
                                : LucideIcons.maximize),
                            tooltip: fullscreen
                                ? l.playerExitFullscreen
                                : l.playerFullscreen,
                            onPressed: onToggleFullscreen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icona dei controlli del player con il linguaggio di `WfButton` (spec D
/// §7.2): al passaggio fondo crema tenue, alone oro e scala 1,08; premuta,
/// 0,97. Con le animazioni ridotte niente scala.
class PlayerIconButton extends StatefulWidget {
  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 24,
  });

  /// Di solito un `Icon`; play/pausa passa un [PlayPauseIcon].
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<PlayerIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final enabled = widget.onPressed != null;
    final hovered = enabled && _hovered;
    final scale = !enabled || motion.isReduced
        ? 1.0
        : _pressed
            ? 0.97
            : hovered
                ? 1.08
                : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: WfMotion.fast,
          curve: WfMotion.emphasized,
          child: AnimatedContainer(
            key: const Key('player-button-glow'),
            duration: WfMotion.fast,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: hovered
                  ? [
                      BoxShadow(
                          color: WfColors.gold.withValues(alpha: 0.35),
                          blurRadius: 16),
                    ]
                  : const [],
            ),
            child: IconButton(
              icon: widget.icon,
              iconSize: widget.iconSize,
              tooltip: widget.tooltip,
              onPressed: widget.onPressed,
              color: WfColors.cream,
              // Spec D §7.2: fondo crema al 12% al passaggio.
              hoverColor: WfColors.cream.withValues(alpha: 0.12),
            ),
          ),
        ),
      ),
    );
  }
}

/// Play/pausa: l'icona cambia con una breve dissolvenza in scala (con le
/// animazioni ridotte solo dissolvenza).
class PlayPauseIcon extends StatelessWidget {
  const PlayPauseIcon({super.key, required this.playing});

  final bool playing;

  /// Scala da cui cresce l'icona nuova.
  static const _fromScale = 0.6;

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return AnimatedSwitcher(
      duration: WfMotion.fast,
      transitionBuilder: (child, animation) => reduced
          ? FadeTransition(opacity: animation, child: child)
          : ScaleTransition(
              scale: Tween<double>(begin: _fromScale, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: WfMotion.emphasized)),
              child: FadeTransition(opacity: animation, child: child),
            ),
      child: Icon(playing ? LucideIcons.pause : LucideIcons.play,
          key: ValueKey(playing)),
    );
  }
}

/// Puntino oro in alto a destra di un'icona (messaggi non letti).
class _WithDot extends StatelessWidget {
  const _WithDot({required this.show, required this.child});

  /// Diametro del puntino.
  static const size = 8.0;

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (show)
            const Positioned(
              key: Key('player-chat-unread'),
              top: -1,
              right: -1,
              child: SizedBox.square(
                dimension: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: WfColors.gold, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      );
}
