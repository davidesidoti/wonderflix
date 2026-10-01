import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

/// Ricostruisce [builder] solo quando cambia il valore che [select] ricava
/// dalla posizione del video (la posizione cambia molte volte al secondo).
class PositionSelector<T> extends StatefulWidget {
  const PositionSelector({
    super.key,
    required this.engine,
    required this.select,
    required this.builder,
  });

  final VideoEngine engine;
  final T Function(Duration position) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<PositionSelector<T>> createState() => _PositionSelectorState<T>();
}

class _PositionSelectorState<T> extends State<PositionSelector<T>> {
  late T _value;
  StreamSubscription<Duration>? _subscription;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.engine.position);
    _subscription = widget.engine.positionStream.listen((position) {
      final value = widget.select(position);
      if (value != _value) setState(() => _value = value);
    });
  }

  @override
  void didUpdateWidget(PositionSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [select] può dipendere da dati arrivati dopo (es. i segmenti).
    _value = widget.select(widget.engine.position);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// "Riproduci ora" del post-play e della scheda (spec D §12): con
/// [countdown] il fondo si riempie d'oro in [countdownFrom] secondi e
/// l'etichetta conta; con [paused] il conto si ferma; a zero chiama
/// [onPressed]. Un timer al secondo, non un'animazione continua: fermo non
/// chiede fotogrammi.
class PlayNowButton extends StatefulWidget {
  const PlayNowButton({
    super.key,
    required this.countdown,
    required this.onPressed,
    this.paused = false,
  });

  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPressed;

  static const countdownFrom = 10;

  /// Ogni secondo il riempimento avanza di un passo, a velocità costante.
  static const fillStep = Duration(seconds: 1);
  static const fillCurve = Curves.linear;

  @override
  State<PlayNowButton> createState() => _PlayNowButtonState();
}

class _PlayNowButtonState extends State<PlayNowButton> {
  int _left = PlayNowButton.countdownFrom;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.countdown) {
      // Un solo timer: i secondi in pausa non contano.
      _timer = Timer.periodic(PlayNowButton.fillStep, (timer) {
        if (widget.paused) return;
        if (_left <= 1) {
          timer.cancel();
          setState(() => _left = 0);
          widget.onPressed();
        } else {
          setState(() => _left--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reduced = WfMotion.of(context).isReduced;
    final counting = widget.countdown && _left > 0;
    final progress = widget.countdown
        ? (PlayNowButton.countdownFrom - _left) / PlayNowButton.countdownFrom
        : 1.0;
    // Come `WfButton.primary` (altezza 44, angoli 6, testo del tema), con il
    // riempimento oro sotto l'etichetta.
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Material(
        color: widget.countdown
            ? WfColors.gold.withValues(alpha: 0.35)
            : WfColors.gold,
        child: InkWell(
          onTap: widget.onPressed,
          child: Stack(
            children: [
              if (widget.countdown)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      widthFactor: progress,
                      heightFactor: 1,
                      duration:
                          reduced ? Duration.zero : PlayNowButton.fillStep,
                      curve: PlayNowButton.fillCurve,
                      child: const ColoredBox(color: WfColors.gold),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.play,
                          size: 18, color: WfColors.bg),
                      const SizedBox(width: 8),
                      Text(
                        counting ? l.playerPlayNowIn(_left) : l.playerPlayNow,
                        style: const TextStyle(
                            color: WfColors.bg,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            // Cifre della stessa larghezza: il pulsante non
                            // balla a ogni secondo.
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scheda "Prossimo episodio" negli ultimi 30 s, quando Jellyfin non
/// conosce i titoli di coda (spec D §12.2): entra da destra con un piccolo
/// rimbalzo; il film resta a tutto schermo.
class NextEpisodeCard extends ConsumerWidget {
  const NextEpisodeCard({
    super.key,
    required this.episode,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
    this.paused = false,
  });

  final JellyfinItem episode;
  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  /// Di quanto arriva da destra entrando.
  static const enterShift = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.duration(WfMotion.medium),
      curve: motion.isReduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(motion.isReduced ? 0 : (1 - t) * enterShift, 0),
          child: child,
        ),
      ),
      child: Material(
        color: WfColors.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.playerNextEpisodeTitle.toUpperCase(),
                    style: WfText.display(20, color: WfColors.gold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: WfImage(
                              image: ref
                                  .watch(imageUrlsProvider)
                                  .landscape(episode)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cardSubtitle(episode) ?? episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PlayNowButton(
                        countdown: countdown, paused: paused, onPressed: onPlay),
                    WfButton.secondary(
                        label: l.playerCancel,
                        icon: LucideIcons.x,
                        onPressed: onCancel),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
