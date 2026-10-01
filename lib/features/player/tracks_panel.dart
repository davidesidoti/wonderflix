import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/staggered_entrance.dart';
import 'player_commands.dart';
import 'player_settings.dart';

/// Nome di una traccia nei menu: quello preparato dal server, se c'è.
String trackLabel(AppLocalizations l, MediaStreamInfo stream) =>
    stream.displayTitle ??
    stream.title ??
    stream.language ??
    l.playerTrack(stream.index);

/// "+0,3 s", "0,0 s", "-1,2 s".
String formatSubtitleDelay(Duration delay, String decimalSeparator) {
  final tenths = (delay.inMilliseconds / 100).round();
  final sign = tenths > 0 ? '+' : (tenths < 0 ? '-' : '');
  final value = tenths.abs();
  return '$sign${value ~/ 10}$decimalSeparator${value % 10} s';
}

/// Pannello "Audio e sottotitoli" (spec D §14): tracce audio, sottotitoli,
/// ritardo e dimensione, in colonna; le voci entrano scaglionate.
class TracksPanel extends StatelessWidget {
  const TracksPanel({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.subtitleDelay,
    required this.subtitleScale,
    required this.onAudio,
    required this.onSubtitle,
    required this.onDelayStep,
    required this.onSubtitleScale,
    required this.onClose,
  });

  final List<MediaStreamInfo> audio;
  final List<MediaStreamInfo> subtitles;
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;

  /// Uno di `subtitleScaleOptions`.
  final double subtitleScale;
  final ValueChanged<int> onAudio;

  /// `null` = nessun sottotitolo.
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<Duration> onDelayStep;
  final ValueChanged<double> onSubtitleScale;
  final VoidCallback onClose;

  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  static const width = 360.0;
  static const maxWidthFraction = 0.35;

  /// Distanza tra l'entrata di una voce e la successiva.
  static const itemStagger = Duration(milliseconds: 40);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(l.playerAudioAndSubtitles, style: WfText.display(24)),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x),
            tooltip: l.playerClosePanel,
            color: WfColors.cream,
            onPressed: onClose,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _SectionTitle(l.playerAudio),
      for (final stream in audio)
        _TrackTile(
          label: trackLabel(l, stream),
          selected: stream.index == audioIndex,
          onTap: () => onAudio(stream.index),
        ),
      const SizedBox(height: 16),
      _SectionTitle(l.playerSubtitles),
      _TrackTile(
        label: l.playerSubtitlesOff,
        selected: subtitleIndex == null,
        onTap: () => onSubtitle(null),
      ),
      for (final stream in subtitles)
        _TrackTile(
          label: trackLabel(l, stream),
          selected: stream.index == subtitleIndex,
          onTap: () => onSubtitle(stream.index),
        ),
      const SizedBox(height: 12),
      _DelayRow(delay: subtitleDelay, onDelayStep: onDelayStep),
      const SizedBox(height: 16),
      Text(l.playerSubtitleSize,
          style: const TextStyle(color: WfColors.creamMuted)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scale in subtitleScaleOptions)
            _ScaleChip(
              key: ValueKey('subtitle-scale-$scale'),
              label: subtitleScaleLabel(l, scale),
              selected: scale == subtitleScale,
              onTap: () => onSubtitleScale(scale),
            ),
        ],
      ),
    ];
    return Material(
      color: WfColors.surface.withValues(alpha: 0.94),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: WfColors.border)),
        ),
        child: StaggerGroup(
          count: items.length,
          stagger: itemStagger,
          itemDuration: WfMotion.medium,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (var i = 0; i < items.length; i++)
                StaggerItem(index: i, child: items[i]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: WfText.display(20, color: WfColors.gold)),
      );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: selected
                    ? const _PopIn(
                        child: Icon(LucideIcons.check,
                            size: 16, color: WfColors.gold))
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? WfColors.cream : WfColors.creamMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// La spunta compare con un piccolo rimbalzo (con le animazioni ridotte
/// solo sfumando).
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WfMotion.fast,
      curve: reduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => reduced
          ? Opacity(opacity: t.clamp(0.0, 1.0), child: child)
          : Transform.scale(scale: t, child: child),
      child: child,
    );
  }
}

class _DelayRow extends StatelessWidget {
  const _DelayRow({required this.delay, required this.onDelayStep});

  final Duration delay;
  final ValueChanged<Duration> onDelayStep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(l.playerSubtitleDelay,
              style: const TextStyle(color: WfColors.creamMuted)),
        ),
        IconButton(
          icon: const Icon(LucideIcons.minus, size: 18),
          tooltip: l.playerSubtitlesEarlier,
          onPressed: () => onDelayStep(-subtitleDelayStep),
        ),
        SizedBox(
          width: 64,
          child: Text(
            formatSubtitleDelay(delay, l.decimalSeparator),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.plus, size: 18),
          tooltip: l.playerSubtitlesLater,
          onPressed: () => onDelayStep(subtitleDelayStep),
        ),
      ],
    );
  }
}

/// Una delle dimensioni dei sottotitoli: bordo e testo oro se scelta.
class _ScaleChip extends StatelessWidget {
  const _ScaleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: WfMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: selected ? WfColors.gold : WfColors.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? WfColors.gold : WfColors.creamMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
}

/// Il pannello a destra, a tutta altezza, con un velo sul film verso di lui
/// (spec D §14): entra scorrendo (`medium`), esce in `fast`; con le
/// animazioni ridotte solo dissolvenza. Chiuso, non è nell'albero (e le
/// voci rientrano scaglionate alla prossima apertura).
class TracksPanelHost extends StatefulWidget {
  const TracksPanelHost({super.key, required this.open, required this.panel});

  final bool open;
  final Widget panel;

  @override
  State<TracksPanelHost> createState() => _TracksPanelHostState();
}

class _TracksPanelHostState extends State<TracksPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    reverseCurve: WfMotion.accelerate,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void didUpdateWidget(TracksPanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    // La larghezza si misura sullo spazio che l'host ha davvero (nel player
    // è la finestra intera), non su `MediaQuery`.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(TracksPanel.width,
            constraints.maxWidth * TracksPanel.maxWidthFraction);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            if (_controller.isDismissed) return const SizedBox.shrink();
            final t = _progress.value.clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(opacity: t, child: const _PanelVeil()),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width,
                  child: reduced
                      ? Opacity(opacity: t, child: widget.panel)
                      : FractionalTranslation(
                          translation: Offset(1 - t, 0),
                          child: widget.panel,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Il film si scurisce appena verso il pannello.
class _PanelVeil extends StatelessWidget {
  const _PanelVeil();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WfColors.bg.withValues(alpha: 0),
              WfColors.bg.withValues(alpha: 0.45),
            ],
            stops: const [0.4, 1],
          ),
        ),
      );
}
