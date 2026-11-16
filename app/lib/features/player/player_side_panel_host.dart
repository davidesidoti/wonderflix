import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../ui/form_factor.dart';

/// Un pannello a destra del player, a tutta altezza sopra i controlli, con
/// un velo sul film verso di lui (spec D §14): entra scorrendo (`medium`),
/// esce in `fast`; con le animazioni ridotte solo dissolvenza. Chiuso, non è
/// nell'albero (e le voci rientrano scaglionate alla prossima apertura). Lo
/// usano "Audio e sottotitoli" e la coda del watch party (spec H §9.1).
/// Nel layout stretto (spec §4.4) è un foglio dal basso, a tutta larghezza:
/// maniglia, angoli tondi in alto; trascinato giù chiama [onClose].
class PlayerSidePanelHost extends StatefulWidget {
  const PlayerSidePanelHost({
    super.key,
    required this.open,
    required this.panel,
    this.width = defaultWidth,
    this.maxWidthFraction = defaultMaxWidthFraction,
    this.onClose,
  });

  final bool open;
  final Widget panel;

  /// Il foglio dal basso trascinato giù.
  final VoidCallback? onClose;

  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  final double width;
  final double maxWidthFraction;

  static const defaultWidth = 380.0;
  static const defaultMaxWidthFraction = 0.4;

  /// Larghezza sulla TV (spec §4.5): fissa, a 960 la frazione darebbe 336.
  static const tvWidth = 380.0;

  /// Nel layout stretto: la parte della finestra che può occupare in altezza.
  static const compactHeightFraction = 0.7;

  /// Il foglio si chiude trascinato giù di più, o più veloce (px/s).
  static const closeDragDistance = 80.0;
  static const closeDragVelocity = 700.0;

  /// Larghezza del pannello in uno spazio largo [available]. La usa l'host,
  /// e chi deve lasciargli posto (la pillola del player): i due conti non
  /// possono divergere.
  static double widthFor(double available,
          {double width = defaultWidth,
          double maxWidthFraction = defaultMaxWidthFraction,
          bool tv = false}) =>
      tv ? tvWidth : math.min(width, available * maxWidthFraction);

  @override
  State<PlayerSidePanelHost> createState() => _PlayerSidePanelHostState();
}

class _PlayerSidePanelHostState extends State<PlayerSidePanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: widget.open ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    // Chiudendo il controller torna da 1 a 0: la curva girata accelera.
    reverseCurve: WfMotion.accelerateReverse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void didUpdateWidget(PlayerSidePanelHost oldWidget) {
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
    // Prima la curva (si stacca dal controller), poi il controller.
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  double _drag = 0;

  /// Altezza dell'area tattile della maniglia (la barretta è 36×4 al centro).
  static const _handleHeight = 44.0;

  /// Il pannello nel foglio dal basso, con la maniglia che lo chiude. La
  /// SafeArea sta dentro il foglio: il fondo copre l'indicatore home.
  Widget _sheet() => ClipRRect(
        key: const Key('panel-sheet'),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ColoredBox(
          color: WfColors.surface,
          child: SafeArea(
            top: false,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _drag = 0,
                onVerticalDragUpdate: (details) => _drag += details.delta.dy,
                onVerticalDragEnd: (details) {
                  if (_drag > PlayerSidePanelHost.closeDragDistance ||
                      (details.primaryVelocity ?? 0) >
                          PlayerSidePanelHost.closeDragVelocity) {
                    widget.onClose?.call();
                  }
                },
                child: SizedBox(
                  height: _handleHeight,
                  child: Center(
                    child: SizedBox(
                      key: const Key('panel-sheet-handle'),
                      width: 36,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: WfColors.cream.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: widget.panel),
            ],
          ),
        ),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    final form = FormFactor.of(context);
    // La TV è stretta (960) ma il pannello resta laterale (spec §3.5).
    final compact = form.compact && !form.tv;
    // La larghezza si misura sullo spazio che l'host ha davvero (nel player
    // è la finestra intera), non su `MediaQuery`.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = PlayerSidePanelHost.widthFor(constraints.maxWidth,
            width: widget.width,
            maxWidthFraction: widget.maxWidthFraction,
            tv: form.tv);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            if (_controller.isDismissed) return const SizedBox.shrink();
            final t = _progress.value.clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                        opacity: t, child: _PanelVeil(fromBottom: compact)),
                  ),
                ),
                if (compact)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: constraints.maxHeight *
                        PlayerSidePanelHost.compactHeightFraction,
                    child: reduced
                        ? Opacity(opacity: t, child: _sheet())
                        : FractionalTranslation(
                            translation: Offset(0, 1 - t),
                            child: _sheet(),
                          ),
                  )
                else
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

/// Il film si scurisce appena verso il pannello (a destra, o in basso).
class _PanelVeil extends StatelessWidget {
  const _PanelVeil({required this.fromBottom});

  final bool fromBottom;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromBottom ? Alignment.topCenter : Alignment.centerLeft,
            end: fromBottom ? Alignment.bottomCenter : Alignment.centerRight,
            colors: [
              WfColors.bg.withValues(alpha: 0),
              WfColors.bg.withValues(alpha: 0.45),
            ],
            stops: const [0.4, 1],
          ),
        ),
      );
}

/// La rotella su un pannello del player non arriva mai al volume (issue
/// #4). Vince chi registra per primo, cioè il widget più interno: se la
/// lista può scorrere registra lei; se no (in cima, in fondo, lista corta)
/// vince questa azione vuota.
class PanelWheelBarrier extends StatelessWidget {
  const PanelWheelBarrier({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver
                .register(event, (_) {});
          }
        },
        child: child,
      );
}
