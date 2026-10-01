import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'player_overlay.dart';

/// Periodo della linea oro del caricamento (spec D §10.1).
const loadingLinePeriod = Duration(milliseconds: 1200);

/// Un buffering più breve di così non mostra lo spinner (spec D §10.2).
const bufferingSpinnerDelay = Duration(milliseconds: 300);

/// Sfondo del titolo con un velo scuro (caricamento ed errore). Stesso URL
/// della testata della scheda: l'immagine è già in cache.
class _DimmedBackdrop extends ConsumerWidget {
  const _DimmedBackdrop({super.key, required this.item, required this.dim});

  final JellyfinItem item;

  /// Opacità del velo, 0–1.
  final double dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropImage(
            backdrop: urls.backdrop(item), fallback: urls.poster(item)),
        ColoredBox(color: WfColors.bg.withValues(alpha: dim)),
      ],
    );
  }
}

/// Caricamento del player (spec D §10.1): sfondo del titolo scurito, logo
/// (o titolo) al centro e una linea oro che scorre; in alto a sinistra la
/// freccia per uscire. Nascosto sfuma e poi esce dall'albero (la linea non
/// gira più).
class PlayerLoadingLayer extends ConsumerStatefulWidget {
  const PlayerLoadingLayer({
    super.key,
    required this.item,
    required this.visible,
    required this.onBack,
  });

  /// `null` finché l'elemento non è arrivato: solo il nero e la linea.
  final JellyfinItem? item;
  final bool visible;
  final VoidCallback onBack;

  /// Velo sullo sfondo.
  static const dim = 0.55;

  /// Il logo: al massimo così alto e largo questa parte della finestra.
  static const logoMaxHeight = 160.0;
  static const logoWidthFraction = 0.4;

  /// Senza logo, il titolo: largo al massimo questa parte della finestra.
  static const titleWidthFraction = 0.6;

  /// Spazio tra il logo e la linea.
  static const logoGap = 28.0;

  @override
  ConsumerState<PlayerLoadingLayer> createState() =>
      _PlayerLoadingLayerState();
}

class _PlayerLoadingLayerState extends ConsumerState<PlayerLoadingLayer> {
  /// Sfumato via: lo strato non è più nell'albero. Montato già nascosto (per
  /// esempio dopo "Riprova", con il primo fotogramma già arrivato) non
  /// entra proprio: non avrebbe nessuna dissolvenza, quindi nessun `onEnd`,
  /// e la linea girerebbe per sempre.
  late bool _gone = !widget.visible;

  /// Lo strato rientra dopo essere uscito dall'albero ("Riprova", un nuovo
  /// caricamento): sfuma in entrata invece di comparire di colpo. La prima
  /// volta no, deve coprire il film da subito.
  bool _fadeIn = false;

  @override
  void didUpdateWidget(PlayerLoadingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      if (_gone) _fadeIn = true;
      _gone = false;
    }
  }

  /// Logo o titolo in basso al centro del loro spazio, anche mentre uno
  /// prende il posto dell'altro.
  static Widget _bottomLayout(Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, ?current],
      );

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final item = widget.item;
    final logo = item == null ? null : urls.logo(item);
    final width = MediaQuery.sizeOf(context).width;
    return IgnorePointer(
      ignoring: !widget.visible,
      child: TweenAnimationBuilder<double>(
        key: const Key('player-loading'),
        // `begin` conta solo alla nascita: 0 se rientra, 1 la prima volta.
        tween: Tween(begin: _fadeIn ? 0 : 1, end: widget.visible ? 1 : 0),
        duration:
            widget.visible ? WfMotion.fast : motion.duration(WfMotion.slow),
        curve: WfMotion.standard,
        onEnd: () {
          if (!widget.visible && mounted) setState(() => _gone = true);
        },
        builder: (context, t, child) =>
            Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        child: ColoredBox(
          color: WfColors.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: WfMotion.fast,
                child: item == null
                    ? const SizedBox.expand()
                    : _DimmedBackdrop(
                        key: ValueKey(item.id),
                        item: item,
                        dim: PlayerLoadingLayer.dim),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Il posto del logo c'è fin dall'inizio, anche senza
                    // l'elemento: quando arriva, la linea non si sposta.
                    SizedBox(
                      height: PlayerLoadingLayer.logoMaxHeight +
                          PlayerLoadingLayer.logoGap,
                      child: AnimatedSwitcher(
                        duration: WfMotion.fast,
                        layoutBuilder: _bottomLayout,
                        child: item == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey(item.id),
                                padding: const EdgeInsets.only(
                                    bottom: PlayerLoadingLayer.logoGap),
                                child: logo != null
                                    ? SizedBox(
                                        width: width *
                                            PlayerLoadingLayer
                                                .logoWidthFraction,
                                        height:
                                            PlayerLoadingLayer.logoMaxHeight,
                                        child: WfImage(
                                            image: logo,
                                            fit: BoxFit.contain,
                                            fallbackIcon: null),
                                      )
                                    : ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: width *
                                                PlayerLoadingLayer
                                                    .titleWidthFraction),
                                        child: Text(
                                          cardTitle(item).toUpperCase(),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: WfText.display(64),
                                        ),
                                      ),
                              ),
                      ),
                    ),
                    const LoadingLine(),
                  ],
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: PlayerIconButton(
                  icon: const Icon(LucideIcons.arrowLeft),
                  tooltip: l.navBack,
                  onPressed: widget.onBack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linea oro che scorre: c'è un'attesa (spec D §10.1). Gira anche con le
/// animazioni ridotte, come uno spinner.
class LoadingLine extends StatefulWidget {
  const LoadingLine({super.key});

  static const width = 200.0;
  static const height = 3.0;

  /// Parte oro della linea, rispetto alla sua lunghezza.
  static const segment = 0.35;

  @override
  State<LoadingLine> createState() => _LoadingLineState();
}

class _LoadingLineState extends State<LoadingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: loadingLinePeriod)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const segment = LoadingLine.width * LoadingLine.segment;
    // Strato di disegno proprio: a 60 fps si ridisegna solo la linea, non
    // tutta la pagina (spec D §6.4).
    return RepaintBoundary(
      child: SizedBox(
        width: LoadingLine.width,
        height: LoadingLine.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LoadingLine.height),
          child: ColoredBox(
            color: WfColors.cream.withValues(alpha: 0.15),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = WfMotion.standard.transform(_controller.value);
                return Stack(
                  children: [
                    Positioned(
                      left: -segment + t * (LoadingLine.width + segment),
                      top: 0,
                      bottom: 0,
                      width: segment,
                      child: const ColoredBox(color: WfColors.gold),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Spinner oro del buffering (spec D §10.2): compare solo se l'attesa dura
/// più di [bufferingSpinnerDelay] e sfuma in entrata e in uscita. Sparito,
/// non è nell'albero.
class BufferingSpinner extends StatefulWidget {
  const BufferingSpinner({super.key, required this.buffering});

  final bool buffering;

  @override
  State<BufferingSpinner> createState() => _BufferingSpinnerState();
}

class _BufferingSpinnerState extends State<BufferingSpinner> {
  Timer? _timer;
  bool _shown = false;

  /// Nell'albero: mostrato o mentre sfuma via.
  bool _present = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BufferingSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buffering != widget.buffering) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.buffering) {
      _shown = false;
      return;
    }
    _timer = Timer(bufferingSpinnerDelay, () {
      if (mounted) {
        setState(() {
          _shown = true;
          _present = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: const Key('buffering-spinner'),
        tween: Tween(begin: 0, end: _shown ? 1 : 0),
        duration: WfMotion.fast,
        onEnd: () {
          if (!_shown && mounted) setState(() => _present = false);
        },
        builder: (context, t, child) =>
            Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        child: const Center(
            child: CircularProgressIndicator(color: WfColors.gold)),
      ),
    );
  }
}

/// Errore di riproduzione (spec D §10.3): sullo sfondo del titolo molto
/// scurito (o sul nero) icona, titolo, testo e pulsanti entrano
/// scaglionati.
class PlayerErrorLayer extends StatelessWidget {
  const PlayerErrorLayer({
    super.key,
    required this.item,
    required this.error,
    required this.onRetry,
    required this.onBack,
    required this.backLabel,
  });

  final JellyfinItem? item;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final String backLabel;

  /// Velo sullo sfondo.
  static const dim = 0.75;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final failure = error;
    final current = item;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (current != null)
          _DimmedBackdrop(item: current, dim: dim)
        else
          const ColoredBox(color: WfColors.bg),
        Center(
          child: StaggerGroup(
            count: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StaggerItem(
                  index: 0,
                  child: Icon(LucideIcons.circleAlert,
                      size: 44, color: WfColors.error),
                ),
                const SizedBox(height: 16),
                StaggerItem(
                  index: 1,
                  child:
                      Text(l.playerErrorTitle, style: WfText.display(34)),
                ),
                const SizedBox(height: 8),
                StaggerItem(
                  index: 2,
                  child: Text(
                    failure == null
                        ? l.errorGeneric
                        : describeError(l, failure),
                    style: const TextStyle(color: WfColors.creamMuted),
                  ),
                ),
                const SizedBox(height: 24),
                StaggerItem(
                  index: 3,
                  child: Wrap(
                    spacing: 12,
                    children: [
                      WfButton.primary(
                          label: l.retry,
                          icon: LucideIcons.rotateCcw,
                          onPressed: onRetry),
                      WfButton.secondary(
                          label: backLabel,
                          icon: LucideIcons.arrowLeft,
                          onPressed: onBack),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
