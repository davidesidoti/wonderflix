import 'package:flutter/widgets.dart';

import '../app/motion.dart';
import '../app/theme.dart';

/// Giro completo dell'onda sugli scheletri (spec C §10.1).
const shimmerPeriod = Duration(milliseconds: 1800);

/// Chiave del pittore dell'onda (per i test).
const shimmerPaintKey = ValueKey<String>('wf-shimmer-paint');

/// Rettangolo del gradiente per un blocco a [offset] dentro un'onda grande
/// [shimmerSize]: lo stesso gradiente per tutti, spostato, così si vede
/// un'unica onda.
Rect shimmerShaderRect(Size shimmerSize, Offset offset) => Rect.fromLTWH(
    -offset.dx, -offset.dy, shimmerSize.width, shimmerSize.height);

/// Spostamento dell'onda, in larghezze dell'area, al punto [t] del giro:
/// da -1 (tutta a sinistra) a 1 (tutta a destra), con `easeInOut`
/// (spec C §10.1).
double shimmerShift(double t) => WfMotion.standard.transform(t) * 2 - 1;

/// Onda oro-crema diagonale che attraversa tutti gli [SkeletonBox] sotto di
/// sé (spec C §10.1). Un solo controller per pagina; con le animazioni
/// ridotte nessun controller e blocchi fermi.
class WfShimmer extends StatefulWidget {
  const WfShimmer({super.key, required this.child});

  final Widget child;

  /// Onda più vicina a [context], se c'è e si muove.
  static WfShimmerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WfShimmerScope>();

  @override
  State<WfShimmer> createState() => _WfShimmerState();
}

// TickerProviderStateMixin (non Single...): passando da ridotte a complete
// più volte si crea un controller nuovo ogni volta.
class _WfShimmerState extends State<WfShimmer> with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = WfMotion.of(context).isReduced;
    if (!reduced && _controller == null) {
      _controller = AnimationController(vsync: this, duration: shimmerPeriod)
        ..repeat();
    } else if (reduced && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  RenderBox? _box() => mounted ? context.findRenderObject() as RenderBox? : null;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // RepaintBoundary: l'onda ridipinge solo lo scheletro.
    final child = RepaintBoundary(child: widget.child);
    if (controller == null) return child;
    return WfShimmerScope(animation: controller, box: _box, child: child);
  }
}

class WfShimmerScope extends InheritedWidget {
  const WfShimmerScope(
      {super.key, required this.animation, required this.box, required super.child});

  final Animation<double> animation;

  /// Area dell'onda (per la posizione dei blocchi).
  final RenderBox? Function() box;

  @override
  bool updateShouldNotify(WfShimmerScope oldWidget) =>
      oldWidget.animation != animation;
}

/// Dipinge un blocco dello scheletro con l'onda.
class ShimmerBlockPainter extends CustomPainter {
  ShimmerBlockPainter({
    required this.animation,
    required this.shimmerBox,
    required this.selfBox,
    required this.radius,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final RenderBox? Function() shimmerBox;
  final RenderBox? Function() selfBox;
  final double radius;

  static final _colors = [
    WfColors.gold.withValues(alpha: 0),
    WfColors.gold.withValues(alpha: 0.10),
    WfColors.cream.withValues(alpha: 0.10),
    WfColors.gold.withValues(alpha: 0.10),
    WfColors.gold.withValues(alpha: 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = WfColors.surfaceHigh);
    final area = shimmerBox();
    final self = selfBox();
    // Blocco o onda non ancora pronti: solo il fondo fermo.
    if (area == null ||
        self == null ||
        !area.attached ||
        !self.attached ||
        !area.hasSize ||
        area.size.isEmpty) {
      return;
    }
    final offset = self.localToGlobal(Offset.zero, ancestor: area);
    final gradient = LinearGradient(
      begin: const Alignment(-1, -0.3),
      end: const Alignment(1, 0.3),
      colors: _colors,
      stops: const [0.35, 0.47, 0.5, 0.53, 0.65],
      transform: _Slide(animation.value),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader =
            gradient.createShader(shimmerShaderRect(area.size, offset)),
    );
  }

  @override
  bool shouldRepaint(ShimmerBlockPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.animation != animation;
}

/// Sposta il gradiente da una larghezza a sinistra a una a destra.
class _Slide extends GradientTransform {
  const _Slide(this.value);

  /// Punto del giro (0–1), lineare: la curva la applica [shimmerShift].
  final double value;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * shimmerShift(value), 0, 0);
}
