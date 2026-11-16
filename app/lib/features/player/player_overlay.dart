import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_menus.dart';
import '../library/item_labels.dart';
import 'player_commands.dart';
import 'player_controller.dart';
import 'player_keys.dart';
import 'playback_rate.dart';
import 'player_time.dart';
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
    required this.backLabel,
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
    this.previewAt,
    this.partyBadge,
    this.onWatchTogether,
    this.onToggleChat,
    this.chatUnread = false,
    this.onToggleReactions,
    this.reactionsLink,
    this.onToggleQueue,
    this.playFocusNode,
    this.rate = 1,
    this.onRate,
  });

  final PlayerViewState view;
  final VideoEngine engine;
  final bool fullscreen;
  final VoidCallback onBack;

  /// Suggerimento della ←: dice dove si torna.
  final String backLabel;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleTracks;
  /// `null` dove lo schermo intero non c'è (Safari su iPhone).
  final VoidCallback? onToggleFullscreen;

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

  /// Anteprima mostrata senza mouse, a questa posizione (salto da
  /// telecomando); vedi [SeekBar.previewAt].
  final Duration? previewAt;

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

  /// Pannello "Coda" del watch party (spec H §9.1): solo nel gruppo; `null`
  /// = nessun pulsante.
  final VoidCallback? onToggleQueue;

  /// Nodo del pulsante play/pausa: sulla TV Giù ci porta il focus.
  final FocusNode? playFocusNode;

  /// Velocità di riproduzione attuale.
  final double rate;

  /// Velocità scelta dal menu; `null` = niente Velocità (nel watch party
  /// resta 1×).
  final ValueChanged<double>? onRate;

  /// Di quanto la parte alta sale e la bassa scende a controlli nascosti.
  static const hiddenShift = 24.0;

  /// [child] agganciato a [link] (se c'è), per un livello che lo segue.
  static Widget _anchored(LayerLink? link, Widget child) => link == null
      ? child
      : CompositedTransformTarget(link: link, child: child);

  /// Parte alta o bassa: sfuma e scivola verso il suo bordo (quella al
  /// centro, [top] `null`, sfuma e basta). Entrata `medium`, uscita `fast`;
  /// con le animazioni ridotte solo dissolvenza.
  Widget _part(BuildContext context,
      {required Key key, required bool? top, required Widget child}) {
    final motion = WfMotion.of(context);
    final duration =
        visible ? motion.duration(WfMotion.medium) : WfMotion.fast;
    final curve = visible ? WfMotion.emphasized : WfMotion.accelerate;
    final shift = visible || motion.isReduced || top == null
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
    // Layout stretto (spec §4.4): -10/play/+10 al centro, in basso la barra
    // e i pulsanti con la parola, il resto in "Altro".
    // Sulla TV la fila larga anche su uno schermo stretto, senza volume,
    // schermo intero, guarda insieme e indietro (c'è il tasto Indietro).
    final tv = FormFactor.of(context).tv;
    final compact = FormFactor.of(context).compact && !tv;
    final rewind = PlayerIconButton(
      icon: const Icon(LucideIcons.rewind),
      tooltip: l.playerRewind,
      shortcut: '←',
      size: compact ? centerSeekSize : null,
      onPressed: () => onSeekBy(-seekStep),
    );
    final playPause = PlayerIconButton(
      iconSize: tv ? 32 : (compact ? 40 : 34),
      icon: PlayPauseIcon(playing: view.playing),
      tooltip: view.playing ? l.playerPause : l.actionPlay,
      shortcut: l.playerKeySpace,
      size: compact ? centerPlaySize : null,
      focusNode: playFocusNode,
      onPressed: onTogglePlay,
    );
    final forward = PlayerIconButton(
      icon: const Icon(LucideIcons.fastForward),
      tooltip: l.playerForward,
      shortcut: '→',
      size: compact ? centerSeekSize : null,
      onPressed: () => onSeekBy(seekStep),
    );
    final mute = PlayerIconButton(
      icon: Icon(volume == 0 ? LucideIcons.volumeX : LucideIcons.volume2),
      tooltip: view.muted ? l.playerUnmute : l.playerMute,
      shortcut: 'M',
      onPressed: onToggleMute,
    );
    final next = onNextEpisode == null
        ? null
        : PlayerIconButton(
            icon: const Icon(LucideIcons.skipForward),
            tooltip: partyQueue ? l.playerNextInQueue : l.playerNextEpisode,
            shortcut: 'N',
            onPressed: onNextEpisode,
          );
    // Col dito il volume è quello del telefono (su iOS il video non lo
    // cambia): resta il muto.
    final slider = FormFactor.of(context).touch || tv
        ? null
        : SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: WfColors.gold,
              inactiveTrackColor: WfColors.cream.withValues(alpha: 0.25),
              thumbColor: WfColors.gold,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: KeyTooltip(
              message: l.playerVolume,
              shortcut: '↑/↓',
              child: Slider(
                key: const Key('volume-slider'),
                value: volume,
                max: 100,
                onChanged: onVolume,
              ),
            ),
          );

    final seekBar = SeekBar(
      engine: engine,
      onSeek: onSeekTo,
      chapters: chapters,
      zones: seekZones(view.segments),
      preview: preview,
      previewAt: previewAt,
      // Col dito sul telefono l'area tattile è alta quanto un pulsante.
      height: compact && FormFactor.of(context).touch
          ? minTouchTarget
          : SeekBar.defaultHeight,
    );
    final chat = onToggleChat == null
        ? null
        : PlayerIconButton(
            key: const Key('player-chat-button'),
            icon: _WithDot(
              show: chatUnread,
              child: const Icon(LucideIcons.messageCircle),
            ),
            tooltip: l.partyChatOpen,
            shortcut: l.playerKeyEnter,
            onPressed: onToggleChat,
          );
    final reactions = onToggleReactions == null
        ? null
        : _anchored(
            reactionsLink,
            PlayerIconButton(
              key: const Key('player-reactions-button'),
              icon: const Icon(LucideIcons.smilePlus),
              tooltip: l.partyReactionsOpen,
              shortcut: '1–6',
              onPressed: onToggleReactions,
            ),
          );
    final queue = onToggleQueue == null
        ? null
        : PlayerIconButton(
            key: const Key('player-queue-button'),
            icon: const Icon(LucideIcons.listVideo),
            tooltip: l.partyQueueOpen,
            onPressed: onToggleQueue,
          );
    final tracks = PlayerIconButton(
      icon: const Icon(LucideIcons.captions),
      tooltip: l.playerAudioAndSubtitles,
      onPressed: onToggleTracks,
    );

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
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(8, 8, 12, 24)
                      : const EdgeInsets.fromLTRB(16, 16, 24, 48),
                  child: Row(
                    children: [
                      if (!tv)
                        PlayerIconButton(
                          icon: const Icon(LucideIcons.arrowLeft),
                          tooltip: backLabel,
                          size: compact ? minTouchTarget : null,
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
                                  style: WfText.display(compact ? 26 : 28)),
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
          ),
          if (compact)
            Positioned.fill(
              child: _part(
                context,
                key: const Key('player-controls-center'),
                top: null,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      rewind,
                      const SizedBox(width: 24),
                      playPause,
                      const SizedBox(width: 24),
                      forward,
                    ],
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
                child: SafeArea(
                  top: false,
                  child: Padding(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(12, 24, 12, 8)
                      // Sulla TV sotto la fila c'è il nome del pulsante.
                      : EdgeInsets.fromLTRB(24, 48, 24, tv ? 40 : 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (compact) ...[
                        seekBar,
                        RepaintBoundary(
                          child: Row(
                            children: [
                              PositionLabel(engine: engine),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: RemainingLabel(
                                      engine: engine, rate: rate),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _compactCommands(context, l),
                      ] else ...[
                        Row(
                          children: [
                            RepaintBoundary(
                                child: PositionLabel(engine: engine)),
                            const SizedBox(width: _timeGap),
                            Expanded(child: seekBar),
                            const SizedBox(width: _timeGap),
                            RepaintBoundary(
                                child:
                                    RemainingLabel(engine: engine, rate: rate)),
                          ],
                        ),
                        if (tv)
                          // Sulla TV come nella bozza: pausa, −10 s, +10 s.
                          Row(
                            children: [
                              playPause,
                              rewind,
                              forward,
                              const Spacer(),
                              ?chat,
                              ?reactions,
                              ?queue,
                              tracks,
                              // Sulla TV come nella bozza: dopo le tracce.
                              ?next,
                            ],
                          )
                        else
                          Row(
                            children: _grouped([
                              [
                                rewind,
                                playPause,
                                forward,
                                mute,
                                if (slider != null)
                                  SizedBox(width: 120, child: slider),
                              ],
                              [
                                if (onPrevious != null)
                                  PlayerIconButton(
                                    icon: const Icon(LucideIcons.skipBack),
                                    tooltip: partyQueue
                                        ? l.playerPreviousInQueue
                                        : l.playerPreviousEpisode,
                                    shortcut: 'P',
                                    onPressed: onPrevious,
                                  ),
                                ?next,
                              ],
                              [
                                if (onWatchTogether != null)
                                  Builder(
                                    builder: (buttonContext) =>
                                        PlayerIconButton(
                                      icon: const Icon(LucideIcons.users),
                                      tooltip: l.watchPartyWatchTogether,
                                      onPressed: () =>
                                          onWatchTogether!(buttonContext),
                                    ),
                                  ),
                                ?chat,
                                ?reactions,
                              ],
                              [
                                ?queue,
                                tracks,
                                if (onRate case final onRate?)
                                  Builder(
                                    builder: (buttonContext) =>
                                        PlayerIconButton(
                                      icon: const Icon(LucideIcons.gauge),
                                      tooltip: l.playerSpeed,
                                      onPressed: () => unawaited(showSpeedMenu(
                                          buttonContext,
                                          rate: rate,
                                          onSelected: onRate)),
                                    ),
                                  ),
                                if (onToggleFullscreen case final toggle?)
                                  PlayerIconButton(
                                    icon: Icon(fullscreen
                                        ? LucideIcons.minimize
                                        : LucideIcons.maximize),
                                    tooltip: fullscreen
                                        ? l.playerExitFullscreen
                                        : l.playerFullscreen,
                                    shortcut: 'F',
                                    onPressed: toggle,
                                  ),
                              ],
                            ]),
                          ),
                      ],
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Spazio tra i tempi e la barra di avanzamento.
  static const _timeGap = 14.0;

  /// I gruppi di comandi della riga larga, separati da un filo (un gruppo
  /// vuoto non ne lascia due di fila); l'ultimo sta a destra.
  static List<Widget> _grouped(List<List<Widget>> groups) {
    final full = [
      for (final group in groups)
        if (group.isNotEmpty) group,
    ];
    return [
      for (final (i, group) in full.indexed) ...[
        if (i > 0 && i == full.length - 1) const Spacer(),
        if (i > 0) _groupDivider,
        ...group,
      ],
    ];
  }

  static const _groupDivider = Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    // La chiave sta dentro: fra fratelli due chiavi uguali non si può.
    child: SizedBox(
      key: Key('player-group-divider'),
      width: 1,
      height: 20,
      child: ColoredBox(color: WfColors.border),
    ),
  );

  /// Lati dei pulsanti al centro nel layout stretto.
  static const centerPlaySize = 68.0;
  static const centerSeekSize = 52.0;

  /// Spazio tra i pulsanti con la parola del layout stretto.
  static const _compactGap = 10.0;

  /// Da questa larghezza (telefono in orizzontale) i pulsanti stanno in una
  /// riga sola: in due righe arriverebbero al play al centro.
  static const _compactOneRowWidth = 600.0;

  /// I pulsanti con la parola del layout stretto (spec §4.4): Audio e
  /// sottotitoli, Episodio successivo, Guarda insieme e "Altro" per ultimo,
  /// che tiene gli altri comandi (nessuno si perde).
  Widget _compactCommands(BuildContext context, AppLocalizations l) {
    final more = <_Command>[
      if (onToggleChat case final chat?)
        _Command(LucideIcons.messageCircle, l.partyChatOpen, (_) => chat()),
      if (onToggleReactions case final reactions?)
        _Command(LucideIcons.smilePlus, l.partyReactionsOpen,
            (_) => reactions()),
      if (onToggleQueue case final queue?)
        _Command(LucideIcons.listVideo, l.partyQueueOpen, (_) => queue()),
      if (onPrevious case final previous?)
        _Command(LucideIcons.skipBack,
            partyQueue ? l.playerPreviousInQueue : l.playerPreviousEpisode,
            (_) => previous()),
      // Nel watch party la velocità resta 1× (`onRate` null).
      if (onRate case final onRate?)
        _Command(
            LucideIcons.gauge,
            l.playerSpeed,
            (anchor) => unawaited(
                showSpeedMenu(anchor, rate: rate, onSelected: onRate))),
      if (onToggleFullscreen case final toggle?)
        _Command(fullscreen ? LucideIcons.minimize : LucideIcons.maximize,
            fullscreen ? l.playerExitFullscreen : l.playerFullscreen,
            (_) => toggle()),
      _Command(view.muted ? LucideIcons.volumeX : LucideIcons.volume2,
          view.muted ? l.playerUnmute : l.playerMute, (_) => onToggleMute()),
    ];
    const align = AlignmentDirectional.centerStart;
    final buttons = <Widget>[
      WfButton.secondary(
        label: l.playerAudioAndSubtitles,
        icon: LucideIcons.captions,
        alignment: align,
        onPressed: onToggleTracks,
      ),
      if (onNextEpisode case final next?)
        WfButton.secondary(
          label: partyQueue ? l.playerNextInQueue : l.playerNextEpisode,
          icon: LucideIcons.skipForward,
          alignment: align,
          onPressed: next,
        ),
      if (onWatchTogether case final together?)
        Builder(
          // Il menu delle modalità si ancora al pulsante.
          builder: (buttonContext) => WfButton.secondary(
            label: l.watchPartyWatchTogether,
            icon: LucideIcons.users,
            alignment: align,
            onPressed: () => together(buttonContext),
          ),
        ),
      // La barretta delle reazioni si aggancia ad "Altro", che le tiene.
      _anchored(
        onToggleReactions == null ? null : reactionsLink,
        Builder(
          builder: (buttonContext) => WfButton.secondary(
            key: const Key('player-more-controls'),
            label: l.playerMore,
            icon: LucideIcons.ellipsis,
            iconWidget: _WithDot(
              show: chatUnread && onToggleChat != null,
              child: const Icon(LucideIcons.ellipsis, size: 18),
            ),
            alignment: align,
            onPressed: () => unawaited(_showMore(buttonContext, more)),
          ),
        ),
      ),
    ];
    final columns =
        MediaQuery.sizeOf(context).width >= _compactOneRowWidth ? 4 : 2;
    return Column(
      children: [
        for (var row = 0; row < buttons.length; row += columns) ...[
          if (row > 0) const SizedBox(height: _compactGap),
          Row(
            children: [
              for (var i = row; i < row + columns; i++) ...[
                if (i > row) const SizedBox(width: _compactGap),
                Expanded(
                    child: i < buttons.length ? buttons[i] : const SizedBox()),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// Il menu di "Altro", ancorato ad [anchor].
  static Future<void> _showMore(
      BuildContext anchor, List<_Command> commands) async {
    final picked = await showMenu<_Command>(
      context: anchor,
      position: menuPositionBelow(anchor,
          estimatedHeight: commands.length * kMinInteractiveDimension),
      popUpAnimationStyle: wfPopUpAnimation(anchor),
      items: [
        for (final command in commands)
          PopupMenuItem(
            value: command,
            child: Row(
              children: [
                Icon(command.icon),
                const SizedBox(width: 12),
                Flexible(child: Text(command.label)),
              ],
            ),
          ),
      ],
    );
    if (picked != null && anchor.mounted) picked.run(anchor);
  }
}

/// Una voce di "Altro" nel layout stretto. [run] riceve il contesto di
/// "Altro" (vi si ancorano i menu che apre).
class _Command {
  const _Command(this.icon, this.label, this.run);

  final IconData icon;
  final String label;
  final ValueChanged<BuildContext> run;
}

/// Pulsante quadrato di lato [size], senza margini aggiunti dal tema.
ButtonStyle _sizedStyle(double size) => IconButton.styleFrom(
      fixedSize: Size.square(size),
      minimumSize: Size.square(size),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );

/// Icona dei controlli del player con il linguaggio di `WfButton` (spec D
/// §7.2): al passaggio fondo crema tenue, alone oro e scala 1,08; premuta,
/// 0,97. Con le animazioni ridotte niente scala.
class PlayerIconButton extends StatefulWidget {
  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.shortcut,
    this.iconSize,
    this.size,
    this.focusNode,
  });

  /// Di solito un `Icon`; play/pausa passa un [PlayPauseIcon].
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Tasto che fa lo stesso: si mostra nel suggerimento solo con tastiera
  /// (né dito né TV).
  final String? shortcut;
  /// `null` = 24 (30 sulla TV).
  final double? iconSize;

  /// Lato fisso del pulsante (layout stretto); `null` = misura del tema.
  final double? size;
  final FocusNode? focusNode;

  /// Sulla TV il bordo oro del focus.
  static final _tvFocusSide = WidgetStateBorderSide.resolveWith(
      (states) => states.contains(WidgetState.focused) ? tvFocusSide : null);

  /// Sulla TV il cerchio del pulsante e la distanza del suo nome.
  static const _tvSize = 56.0;
  static const _tvLabelGap = 12.0;

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<PlayerIconButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final enabled = widget.onPressed != null;
    final hovered = enabled && _hovered;
    final formFactor = FormFactor.of(context);
    final tv = formFactor.tv;
    final scale = tv
        ? (_focused ? tvFocusScale : 1.0)
        : !enabled || motion.isReduced
        ? 1.0
        : _pressed
            ? 0.97
            : hovered
                ? 1.08
                : 1.0;
    final button = MouseRegion(
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
            child: KeyTooltip(
              message: widget.tooltip,
              shortcut: formFactor.tv || formFactor.touch
                  ? null
                  : widget.shortcut,
              child: IconButton(
                icon: widget.icon,
                iconSize: widget.iconSize ?? (tv ? 30 : 24),
                onPressed: widget.onPressed,
                focusNode: widget.focusNode,
                style: !tv
                    ? (widget.size == null ? null : _sizedStyle(widget.size!))
                    : _sizedStyle(widget.size ?? PlayerIconButton._tvSize)
                        .copyWith(
                        backgroundColor: WidgetStatePropertyAll(
                            WfColors.bg.withValues(alpha: 0.35)),
                        side: PlayerIconButton._tvFocusSide,
                      ),
                color: WfColors.cream,
                // Spec D §7.2: fondo crema al 12% al passaggio.
                hoverColor: WfColors.cream.withValues(alpha: 0.12),
              ),
            ),
          ),
        ),
      ),
    );
    if (!tv) return button;
    // Il nome sta sotto il cerchio col focus, fuori dal layout: la fila non
    // si muove.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (_focused)
            Positioned(
              top: (widget.size ?? PlayerIconButton._tvSize) +
                  PlayerIconButton._tvLabelGap,
              left: (widget.size ?? PlayerIconButton._tvSize) / 2,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: Text(
                  widget.tooltip,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                      color: WfColors.cream,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
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
