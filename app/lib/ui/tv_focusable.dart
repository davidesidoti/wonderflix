import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'form_factor.dart';

/// Colore del bordo dell'elemento col focus sulla TV.
const tvFocusColor = WfColors.gold;

/// Ingrandimento dell'elemento col focus sulla TV.
const tvFocusScale = 1.05;

/// Il tasto OK del telecomando (`select`) vale come Invio.
const tvActivateShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
};

/// Rende [child] raggiungibile col telecomando: bordo oro e ingrandimento col
/// focus, [onActivate] con OK, Invio o Spazio, e scorrimento fino a vederlo.
///
/// Fuori dalla TV restituisce [child] così com'è.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onActivate,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.onFocusChange,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
    if (focused) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FormFactor.of(context).tv) return widget.child;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      enabled: widget.onActivate != null,
      onFocusChange: _onFocus,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate?.call();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused ? tvFocusScale : 1,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _focused ? tvFocusColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
