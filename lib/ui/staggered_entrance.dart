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
    this.nested = false,
    this.onPlayed,
  });

  final int count;
  final Widget child;
  final Duration delay;
  final Duration stagger;
  final Duration itemDuration;
  final bool play;

  /// Gruppo dentro uno [StaggerItem] di un altro gruppo (le card di una
  /// riga): entra solo insieme a quell'elemento, cioè se il suo gruppo sta
  /// ancora animando e l'elemento non ha finito di entrare; parte quando
  /// parte l'elemento (più [delay]). Altrimenti — elemento già entrato
  /// (riga ricostruita scorrendo, dati aggiornati), gruppo esterno fermo o
  /// assente — niente entrata: la riga c'è già, le card non volano.
  final bool nested;

  /// Chiamato una volta quando l'entrata parte (dopo il primo fotogramma).
  final VoidCallback? onPlayed;

  @override
  State<StaggerGroup> createState() => _StaggerGroupState();
}

class _StaggerGroupState extends State<StaggerGroup>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// Ritardo effettivo: [StaggerGroup.delay] più, se annidato, l'attesa
  /// dell'elemento che lo contiene.
  late Duration _delay = widget.delay;
  late Duration _total;

  /// L'entrata si decide una volta sola: un cambio di livello più tardi
  /// non la fa partire a metà vita.
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _computeTotal();
  }

  void _computeTotal() => _total = staggerTotal(
        count: widget.count,
        delay: _delay,
        stagger: widget.stagger,
        item: widget.itemDuration,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Si decide una volta sola, alla prima costruzione.
    if (_decided) return;
    _decided = true;
    if (!widget.play || widget.count == 0) return;
    if (WfMotion.of(context).isReduced) return;
    if (widget.nested) {
      final wait = context
          .getInheritedWidgetOfExactType<_StaggerItemScope>()
          ?.waitForEntrance();
      if (wait == null) return;
      _delay = widget.delay + wait;
      _computeTotal();
    }
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
        delay: _delay,
        total: _total,
        child: widget.child,
      );
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({
    required this.controller,
    required this.group,
    required this.delay,
    required this.total,
    required super.child,
  });

  final AnimationController? controller;
  final StaggerGroup group;
  final Duration delay;
  final Duration total;

  @override
  bool updateShouldNotify(_StaggerScope oldWidget) =>
      oldWidget.controller != controller;
}

/// Entrata di uno [StaggerItem], per un gruppo annidato sotto di lui.
class _StaggerItemScope extends InheritedWidget {
  const _StaggerItemScope({
    required this.controller,
    required this.start,
    required this.end,
    required this.total,
    required super.child,
  });

  /// Controller del gruppo dell'elemento; `null` = l'elemento non entra.
  final AnimationController? controller;

  /// Inizio e fine dell'entrata dell'elemento nel tempo del suo gruppo.
  final Duration start;
  final Duration end;
  final Duration total;

  /// Attesa prima che l'elemento inizi a entrare (zero se sta entrando);
  /// `null` se non entra o ha già finito.
  Duration? waitForEntrance() {
    final controller = this.controller;
    if (controller == null || controller.isCompleted) return null;
    final elapsed = total * controller.value;
    if (elapsed >= end) return null;
    return elapsed < start ? start - elapsed : Duration.zero;
  }

  // Si legge una volta sola, alla nascita del gruppo annidato.
  @override
  bool updateShouldNotify(_StaggerItemScope oldWidget) => false;
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
      // Anche senza entrata: un gruppo annidato qui sotto non deve trovare
      // l'elemento di un gruppo più esterno.
      return _StaggerItemScope(
        controller: null,
        start: Duration.zero,
        end: Duration.zero,
        total: Duration.zero,
        child: child,
      );
    }
    final start = scope.delay + scope.group.stagger * index;
    final interval = staggerInterval(
      index: index,
      delay: scope.delay,
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
      child: _StaggerItemScope(
        controller: controller,
        start: start,
        end: start + scope.group.itemDuration,
        total: scope.total,
        child: child,
      ),
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
