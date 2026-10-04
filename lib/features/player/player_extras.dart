import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

/// "Riproduci ora" del post-play e della scheda (spec D §12): con
/// [countdown] il fondo si riempie d'oro in [countdownFrom] secondi e
/// l'etichetta conta; con [paused] il conto si ferma; a zero chiama
/// [onPressed]. Un timer al secondo, e a ogni secondo un passo del fondo
/// fino allo scatto successivo: fermo non chiede fotogrammi.
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

  /// Altezza con la densità standard, come `WfButton`: la densità del tema
  /// la cambia come nei pulsanti Material (compatta su Windows: 36).
  static const height = 44.0;

  @override
  State<PlayNowButton> createState() => _PlayNowButtonState();
}

class _PlayNowButtonState extends State<PlayNowButton> {
  /// Oro tenue della parte non ancora riempita.
  static const _trackAlpha = 0.35;

  /// Velo scuro sopra il pulsante, come nei `FilledButton` di Material 3
  /// (`onPrimary` all'8% al passaggio, al 10% al clic e con il fuoco).
  static const _hoverVeil = 0.08;
  static const _pressVeil = 0.1;

  static final _veil = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused)) {
      return WfColors.bg.withValues(alpha: _pressVeil);
    }
    if (states.contains(WidgetState.hovered)) {
      return WfColors.bg.withValues(alpha: _hoverVeil);
    }
    return null;
  });

  static const _labelStyle = TextStyle(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      // Cifre della stessa larghezza: il pulsante non balla a ogni secondo.
      fontFeatures: [FontFeature.tabularFigures()]);

  int _left = PlayNowButton.countdownFrom;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.countdown) _start();
  }

  @override
  void didUpdateWidget(PlayNowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.countdown != oldWidget.countdown) {
      _timer?.cancel();
      _timer = null;
      // Il conto può arrivare dopo (es. il server toglie dal gruppo durante
      // il post-play): riparte da capo.
      if (widget.countdown) {
        _left = PlayNowButton.countdownFrom;
        _start();
      }
    } else if (widget.countdown &&
        _left > 0 &&
        oldWidget.paused &&
        !widget.paused) {
      // Ripresa: il secondo lasciato a metà dalla pausa non conta (il fondo
      // è tornato sull'ultimo secondo compiuto). Il timer riparte da qui, e
      // lo scatto arriva quando finisce il passo del fondo che parte ora.
      _timer?.cancel();
      _start();
    }
  }

  void _start() {
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Larghezza dell'etichetta più lunga ("· 10"), riservata durante il
  /// conto: il pulsante non si stringe quando resta una cifra sola.
  double _widestLabel(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: AppLocalizations.of(context)
            .playerPlayNowIn(PlayNowButton.countdownFrom),
        // Lo stile che `Text` userà davvero.
        style: DefaultTextStyle.of(context).style.merge(_labelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reduced = WfMotion.of(context).isReduced;
    final countdown = widget.countdown;
    final counting = countdown && _left > 0;
    final done = PlayNowButton.countdownFrom - _left;
    // Con le animazioni complete ogni passo punta al secondo che sta per
    // scattare e finisce con lui: allo scatto il fondo è pieno. In pausa
    // resta sull'ultimo secondo compiuto; con quelle ridotte scatta lì.
    final step = counting && !widget.paused && !reduced ? done + 1 : done;
    final progress = step / PlayNowButton.countdownFrom;
    final height = Theme.of(context)
        .visualDensity
        .effectiveConstraints(
            const BoxConstraints(minHeight: PlayNowButton.height))
        .minHeight;
    // Come `WfButton.primary` (angoli 6, margini 20, icona 18). Scura
    // sull'oro; durante il conto la ricolora la maschera qui sotto.
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.play, size: 18, color: WfColors.bg),
            const SizedBox(width: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: countdown ? _widestLabel(context) : 0),
                child: Text(
                  counting ? l.playerPlayNowIn(_left) : l.playerPlayNow,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle.copyWith(color: WfColors.bg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final content = !countdown
        ? label
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            // In pausa il fondo torna in fretta sull'ultimo secondo
            // compiuto, senza scivolare indietro per un secondo intero.
            duration: reduced
                ? Duration.zero
                : widget.paused
                    ? WfMotion.fast
                    : PlayNowButton.fillStep,
            curve: PlayNowButton.fillCurve,
            builder: (context, t, label) => Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const Key('play-now-fill'),
                      widthFactor: t,
                      heightFactor: 1,
                      child: const ColoredBox(color: WfColors.gold),
                    ),
                  ),
                ),
                // Etichetta in due toni, divisa dove arriva il fondo: scura
                // sull'oro, crema sull'oro tenue (leggibile per tutto il
                // conto). La maschera copre tutto il pulsante, come il fondo.
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: const [
                      WfColors.bg,
                      WfColors.bg,
                      WfColors.cream,
                      WfColors.cream,
                    ],
                    stops: [0, t, t, 1],
                  ).createShader(bounds),
                  child: label,
                ),
              ],
            ),
            child: label,
          );
    return Semantics(
      container: true,
      button: true,
      // Come `ButtonStyleButton`: un pulsante attivo lo dichiara.
      enabled: true,
      child: WfButtonFeedback(
        enabled: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
            color: countdown
                ? WfColors.gold.withValues(alpha: _trackAlpha)
                : WfColors.gold,
            child: Stack(
              children: [
                content,
                // Velo del passaggio e onda del clic sopra il riempimento:
                // su un `Material` sotto, il fondo oro li coprirebbe.
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child:
                        InkWell(onTap: widget.onPressed, overlayColor: _veil),
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
    this.label,
  });

  final JellyfinItem episode;

  /// Occhiello; di default "Prossimo episodio" (nel watch party può essere
  /// "Prossimo nella coda", spec H §9.1).
  final String? label;

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
                Text((label ?? l.playerNextEpisodeTitle).toUpperCase(),
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
                        // Un episodio: "S1:E5 · Titolo". Nel gruppo il
                        // prossimo può essere un film: ci vuole il titolo,
                        // non solo l'anno.
                        episode.kind == ItemKind.episode
                            ? cardSubtitle(episode) ?? episode.name
                            : episode.name,
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
