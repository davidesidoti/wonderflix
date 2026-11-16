import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'form_factor.dart';

/// Colore del bordo dell'elemento col focus sulla TV.
const tvFocusColor = WfColors.gold;

/// Ingrandimento dell'elemento col focus sulla TV.
const tvFocusScale = 1.05;

/// Il tasto OK del telecomando (`select`) vale come Invio, e su/giù escono
/// anche da un campo di testo: senza, dopo la tastiera il fuoco resta nel
/// campo (Flutter usa le frecce per il cursore) e "Accedi" non si raggiunge.
const tvShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp):
      DirectionalFocusIntent(TraversalDirection.up, ignoreTextFields: false),
  SingleActivator(LogicalKeyboardKey.arrowDown):
      DirectionalFocusIntent(TraversalDirection.down, ignoreTextFields: false),
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
    this.focusScale = tvFocusScale,
  });

  final Widget child;
  final VoidCallback? onActivate;

  /// Ingrandimento col focus: più basso per le righe larghe quanto il
  /// pannello, che sennò ne escono.
  final double focusScale;
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
      const duration = Duration(milliseconds: 200);
      Scrollable.ensureVisible(context, alignment: 0.5, duration: duration);
      // Una card che si vede tutta con la pagina in cima tiene la pagina in
      // cima: centrarla taglierebbe l'inizio (il carosello della Home).
      // L'animazione nuova prende il posto di quella di `ensureVisible` solo
      // sulla pagina; la riga resta centrata.
      final page = _verticalScrollable(context);
      final box = context.findRenderObject();
      final pageBox = page?.context.findRenderObject();
      if (page != null && box is RenderBox && pageBox is RenderBox) {
        final position = page.position;
        final bottom =
            box.localToGlobal(Offset(0, box.size.height), ancestor: pageBox).dy +
            position.pixels;
        if (bottom <= position.viewportDimension) {
          position.animateTo(
            position.minScrollExtent,
            duration: duration,
            curve: Curves.ease,
          );
        }
      }
    }
  }

  /// La lista verticale più vicina che contiene l'elemento (la pagina).
  static ScrollableState? _verticalScrollable(BuildContext context) {
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null && scrollable.position.axis != Axis.vertical) {
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return scrollable;
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
        scale: _focused ? widget.focusScale : 1,
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

/// Sulla TV il bordo oro largo 2 attorno a [child] quando il focus è su un
/// suo discendente (menu dei filtri, schede): per i controlli che non hanno
/// un `ButtonStyle` da cui prenderlo. Fuori dalla TV restituisce [child].
/// [color] è crema ([tvFocusSideOnGold]) dove il controllo è pieno d'oro.
class TvFocusBorder extends StatelessWidget {
  const TvFocusBorder({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.color = tvFocusColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!FormFactor.of(context).tv) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (context) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: Focus.of(context).hasFocus ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
