import 'package:flutter/material.dart';

import '../app/motion.dart';
import '../app/theme.dart';

/// Pulsante con etichetta e icona. Larghezza adatta al contenuto (il tema
/// globale rende i FilledButton larghi quanto il contenitore, qui no).
class WfButton extends StatelessWidget {
  const WfButton.primary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  }) : primary = true;

  const WfButton.secondary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  }) : primary = false;

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  /// Prende il fuoco appena compare (Invio lo preme).
  final bool autofocus;

  Widget _button() {
    const size = Size(0, 44);
    const padding = EdgeInsets.symmetric(horizontal: 20);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        autofocus: autofocus,
        style: FilledButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      autofocus: autofocus,
      style: OutlinedButton.styleFrom(
        minimumSize: size,
        padding: padding,
        shape: shape,
        foregroundColor: WfColors.cream,
        side: const BorderSide(color: WfColors.border),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) =>
      WfButtonFeedback(enabled: onPressed != null, child: _button());
}

/// Alone oro e scala di [WfButton] al passaggio e al clic, anche per i
/// pulsanti disegnati a mano (es. "Riproduci ora" del player).
class WfButtonFeedback extends StatefulWidget {
  const WfButtonFeedback(
      {super.key, required this.enabled, required this.child});

  /// Pulsante disattivato: nessun effetto.
  final bool enabled;
  final Widget child;

  @override
  State<WfButtonFeedback> createState() => _WfButtonFeedbackState();
}

class _WfButtonFeedbackState extends State<WfButtonFeedback> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final enabled = widget.enabled;
    final hovered = enabled && _hovered;
    // Spec C §11.2: alone oro e scala 1,03 al passaggio, 0,97 al clic; con
    // le animazioni ridotte niente scala.
    final scale = !enabled || motion.isReduced
        ? 1.0
        : _pressed
            ? 0.97
            : hovered
                ? 1.03
                : 1.0;
    return MouseRegion(
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
            key: const Key('wf-button-glow'),
            duration: WfMotion.fast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: hovered
                  ? [
                      BoxShadow(
                          color: WfColors.gold.withValues(alpha: 0.3),
                          blurRadius: 18),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Pulsante tondo con stato attivo (preferito, visto).
class WfIconToggle extends StatefulWidget {
  const WfIconToggle({
    super.key,
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 20,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Lato del pulsante e dell'icona: 44/20 nella scheda, più piccoli
  /// nell'anteprima delle card.
  final double size;
  final double iconSize;

  @override
  State<WfIconToggle> createState() => _WfIconToggleState();
}

class _WfIconToggleState extends State<WfIconToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: WfMotion.medium);

  /// 1 → 1,3 → 1 (spec C §11.2).
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: WfMotion.decelerate)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: WfMotion.bounce)),
        weight: 60),
  ]).animate(_pop);

  @override
  void didUpdateWidget(WfIconToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected &&
        widget.selected &&
        !WfMotion.of(context).isReduced) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        isSelected: selected,
        style: IconButton.styleFrom(
          // Il minimo di Material (40) non deve allargare i pulsanti piccoli.
          minimumSize: Size.square(widget.size),
          fixedSize: Size.square(widget.size),
          // Il cambio di colore del riempimento (Material: 200 ms).
          animationDuration: WfMotion.of(context).duration(WfMotion.fast),
          foregroundColor: selected ? WfColors.gold : WfColors.cream,
          // "Riempimento": fondo oro tenue quando è attivo.
          backgroundColor: selected
              ? WfColors.gold.withValues(alpha: 0.15)
              : Colors.transparent,
          side: BorderSide(color: selected ? WfColors.gold : WfColors.border),
        ),
        icon: Icon(widget.icon, size: widget.iconSize),
      ),
    );
  }
}
