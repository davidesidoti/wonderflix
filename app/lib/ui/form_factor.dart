import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Sotto questa larghezza la finestra usa il layout stretto.
const compactLayoutWidth = 1024.0;

/// Telefono: modo tocco e lato corto sotto questa misura.
const phoneShortestSide = 600.0;

/// Lato minimo di ogni elemento toccabile nel layout stretto e nel modo tocco.
const minTouchTarget = 44.0;

/// Come va disegnata l'interfaccia: larghezza, dito o mouse, telefono.
///
/// Viene solo da `MediaQuery` e dal tipo di puntatore, mai da `kIsWeb`,
/// dallo user agent o da `Platform`.
@immutable
class FormFactor {
  const FormFactor({
    required this.compact,
    required this.touch,
    required this.phone,
  });

  /// Finestra più stretta di [compactLayoutWidth].
  final bool compact;

  /// L'ultimo puntatore è un dito o una penna.
  final bool touch;

  /// [touch] e lato corto sotto [phoneShortestSide].
  final bool phone;

  /// Senza [FormFactorScope] il modo tocco è spento.
  static FormFactor of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final touch =
        context.dependOnInheritedWidgetOfExactType<_FormFactorTouch>()?.touch ??
        false;
    return FormFactor(
      compact: size.width < compactLayoutWidth,
      touch: touch,
      phone: touch && size.shortestSide < phoneShortestSide,
    );
  }
}

/// Segue l'ultimo puntatore e lo pubblica per [FormFactor.of].
///
/// Parte in modo tocco su Android e iOS. Con [touchOverride] il modo tocco è
/// fisso (nei test, dove `tester.tap` è sempre un tocco).
class FormFactorScope extends StatefulWidget {
  const FormFactorScope({super.key, required this.child, this.touchOverride});

  final Widget child;
  final bool? touchOverride;

  @override
  State<FormFactorScope> createState() => _FormFactorScopeState();
}

class _FormFactorScopeState extends State<FormFactorScope> {
  bool _touch =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _onPointer(PointerEvent event) {
    final touch =
        event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (touch != _touch) setState(() => _touch = touch);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointer,
    onPointerHover: _onPointer,
    child: _FormFactorTouch(
      touch: widget.touchOverride ?? _touch,
      child: widget.child,
    ),
  );
}

class _FormFactorTouch extends InheritedWidget {
  const _FormFactorTouch({required this.touch, required super.child});

  final bool touch;

  @override
  bool updateShouldNotify(_FormFactorTouch old) => touch != old.touch;
}
