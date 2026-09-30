import 'package:flutter/widgets.dart';

import '../app/motion.dart';

/// Come entra un elemento (spec C §8.2).
enum EntranceEffect {
  /// Sale di 20 px in dissolvenza (righe, testi).
  rise,

  /// Arriva da destra (40 px) crescendo da 0,85, con un leggero rimbalzo
  /// (card nelle righe).
  fly,
}

/// Durata totale di un'entrata di [count] elementi.
Duration staggerTotal({
  required int count,
  required Duration delay,
  required Duration stagger,
  required Duration item,
}) =>
    delay + stagger * (count > 0 ? count - 1 : 0) + item;

/// Frazioni della durata totale in cui entra l'elemento [index].
({double begin, double end}) staggerInterval({
  required int index,
  required Duration delay,
  required Duration stagger,
  required Duration item,
  required Duration total,
}) {
  final start = delay + stagger * index;
  final totalMs = total.inMicroseconds;
  return (
    begin: (start.inMicroseconds / totalMs).clamp(0.0, 1.0),
    end: ((start + item).inMicroseconds / totalMs).clamp(0.0, 1.0),
  );
}

/// Gruppo di elementi che entrano uno dopo l'altro, con un solo
/// `AnimationController` e nessun timer. Entrano i primi [count] figli
/// [StaggerItem]; gli altri compaiono subito. Con le animazioni ridotte o
/// [play] spento tutto è subito visibile.
class StaggerGroup extends StatefulWidget {
  const StaggerGroup({
    super.key,
    required this.count,
    required this.child,
    this.delay = Duration.zero,
    this.stagger = WfMotion.stagger,
    this.itemDuration = WfMotion.slow,
    this.play = true,
    this.onPlayed,
  });

  final int count;
  final Widget child;
  final Duration delay;
  final Duration stagger;
  final Duration itemDuration;
  final bool play;

  /// Chiamato una volta quando l'entrata parte (dopo il primo fotogramma).
  final VoidCallback? onPlayed;

  @override
  State<StaggerGroup> createState() => _StaggerGroupState();
}

class _StaggerGroupState extends State<StaggerGroup>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Duration _total;

  /// L'entrata si decide una volta sola: un cambio di livello più tardi
  /// non la fa partire a metà vita.
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _total = staggerTotal(
      count: widget.count,
      delay: widget.delay,
      stagger: widget.stagger,
      item: widget.itemDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Si decide una volta sola, alla prima costruzione.
    if (_decided) return;
    _decided = true;
    if (!widget.play || widget.count == 0) return;
    if (WfMotion.of(context).isReduced) return;
    _controller = AnimationController(vsync: this, duration: _total)..forward();
    final onPlayed = widget.onPlayed;
    if (onPlayed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onPlayed();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StaggerScope(
        controller: _controller,
        group: widget,
        total: _total,
        child: widget.child,
      );
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({
    required this.controller,
    required this.group,
    required this.total,
    required super.child,
  });

  final AnimationController? controller;
  final StaggerGroup group;
  final Duration total;

  @override
  bool updateShouldNotify(_StaggerScope oldWidget) =>
      oldWidget.controller != controller;
}

/// Elemento [index] di uno [StaggerGroup].
class StaggerItem extends StatelessWidget {
  const StaggerItem({
    super.key,
    required this.index,
    this.effect = EntranceEffect.rise,
    required this.child,
  });

  final int index;
  final EntranceEffect effect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_StaggerScope>();
    final controller = scope?.controller;
    if (scope == null || controller == null || index >= scope.group.count) {
      return child;
    }
    final interval = staggerInterval(
      index: index,
      delay: scope.group.delay,
      stagger: scope.group.stagger,
      item: scope.group.itemDuration,
      total: scope.total,
    );
    final curve = effect == EntranceEffect.fly
        ? WfMotion.bounce
        : WfMotion.emphasized;
    final progress = controller.drive(CurveTween(
        curve: Interval(interval.begin, interval.end, curve: curve)));
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = progress.value;
        final opacity = t.clamp(0.0, 1.0);
        final Matrix4 matrix = switch (effect) {
          EntranceEffect.rise => Matrix4.translationValues(0, 20 * (1 - t), 0),
          EntranceEffect.fly => Matrix4.translationValues(40 * (1 - t), 0, 0)
            ..scaleByDouble(0.85 + 0.15 * t, 0.85 + 0.15 * t, 1, 1),
        };
        return Opacity(
          opacity: opacity,
          child: Transform(
            transform: matrix,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }
}
