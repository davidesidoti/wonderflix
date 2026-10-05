import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// Un pannello a destra del player, a tutta altezza sopra i controlli, con
/// un velo sul film verso di lui (spec D §14): entra scorrendo (`medium`),
/// esce in `fast`; con le animazioni ridotte solo dissolvenza. Chiuso, non è
/// nell'albero (e le voci rientrano scaglionate alla prossima apertura). Lo
/// usano "Audio e sottotitoli" e la coda del watch party (spec H §9.1).
class PlayerSidePanelHost extends StatefulWidget {
  const PlayerSidePanelHost({
    super.key,
    required this.open,
    required this.panel,
    this.width = defaultWidth,
    this.maxWidthFraction = defaultMaxWidthFraction,
  });

  final bool open;
  final Widget panel;

  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  final double width;
  final double maxWidthFraction;

  static const defaultWidth = 360.0;
  static const defaultMaxWidthFraction = 0.35;

  /// Larghezza del pannello in uno spazio largo [available]. La usa l'host,
  /// e chi deve lasciargli posto (la pillola del player): i due conti non
  /// possono divergere.
  static double widthFor(double available,
          {double width = defaultWidth,
          double maxWidthFraction = defaultMaxWidthFraction}) =>
      math.min(width, available * maxWidthFraction);

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

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    // La larghezza si misura sullo spazio che l'host ha davvero (nel player
    // è la finestra intera), non su `MediaQuery`.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = PlayerSidePanelHost.widthFor(constraints.maxWidth,
            width: widget.width, maxWidthFraction: widget.maxWidthFraction);
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
