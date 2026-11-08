import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'tv_focusable.dart';

/// Sotto questa larghezza la finestra usa il layout stretto.
const compactLayoutWidth = 1024.0;

/// Telefono: modo tocco e lato corto sotto questa misura.
const phoneShortestSide = 600.0;

/// Lato minimo di ogni elemento toccabile nel layout stretto e nel modo tocco.
const minTouchTarget = 44.0;

/// Come va disegnata l'interfaccia: larghezza, dito o mouse, telefono.
///
/// Viene da `MediaQuery` e dal tipo di puntatore, mai da `kIsWeb`, dallo user
/// agent o da `Platform`. Fa eccezione [tv]: lo decide `app.dart` (con
/// `isAndroidTv`) e lo passa a [FormFactorScope].
@immutable
class FormFactor {
  const FormFactor({
    required this.compact,
    required this.touch,
    required this.phone,
    required this.tv,
  });

  /// Finestra più stretta di [compactLayoutWidth].
  final bool compact;

  /// L'ultimo puntatore è un dito o una penna.
  final bool touch;

  /// [touch] e lato corto sotto [phoneShortestSide].
  final bool phone;

  /// Android TV con il telecomando: [touch] e [phone] sono sempre falsi.
  final bool tv;

  /// Senza [FormFactorScope] il modo tocco è spento.
  static FormFactor of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scope = context.dependOnInheritedWidgetOfExactType<_FormFactorTouch>();
    final touch = scope?.touch ?? false;
    return FormFactor(
      compact: size.width < compactLayoutWidth,
      touch: touch,
      phone: touch && size.shortestSide < phoneShortestSide,
      tv: scope?.tv ?? false,
    );
  }
}

/// Segue l'ultimo puntatore e lo pubblica per [FormFactor.of].
///
/// Parte in modo tocco su Android e iOS. Con [touchOverride] il modo tocco è
/// fisso (nei test, dove `tester.tap` è sempre un tocco). Con [tv] il modo
/// tocco è spento e i puntatori sono ignorati, e ogni elemento che prende il
/// focus scorre fino a vedersi.
class FormFactorScope extends StatefulWidget {
  const FormFactorScope({
    super.key,
    required this.child,
    this.touchOverride,
    this.tv = false,
  });

  final Widget child;
  final bool? touchOverride;
  final bool tv;

  @override
  State<FormFactorScope> createState() => _FormFactorScopeState();
}

class _FormFactorScopeState extends State<FormFactorScope> {
  bool _touch =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (widget.tv) FocusManager.instance.addListener(_revealFocus);
  }

  @override
  void didUpdateWidget(FormFactorScope old) {
    super.didUpdateWidget(old);
    if (old.tv == widget.tv) return;
    if (widget.tv) {
      FocusManager.instance.addListener(_revealFocus);
    } else {
      FocusManager.instance.removeListener(_revealFocus);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_revealFocus);
    super.dispose();
  }

  /// Sulla TV l'elemento col focus (anche `autofocus` o `requestFocus`, che
  /// non passano dalla ricerca del focus) scorre quanto basta per vedersi.
  /// Le card (`TvFocusable`) si centrano da sole.
  void _revealFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null ||
        FocusManager.instance.primaryFocus is FocusScopeNode ||
        context.findAncestorWidgetOfExactType<TvFocusable>() != null) {
      return;
    }
    // Il focus cambia a fine microtask: il layout del fotogramma serve per
    // sapere dove sta.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) async {
        if (!context.mounted) return;
        const duration = Duration(milliseconds: 200);
        await Scrollable.ensureVisible(
          context,
          duration: duration,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        if (!context.mounted) return;
        await Scrollable.ensureVisible(
          context,
          duration: duration,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      })
      ..scheduleFrame();
  }

  void _onPointer(PointerEvent event) {
    if (widget.tv) return;
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
      touch: !widget.tv && (widget.touchOverride ?? _touch),
      tv: widget.tv,
      child: widget.child,
    ),
  );
}

class _FormFactorTouch extends InheritedWidget {
  const _FormFactorTouch({
    required this.touch,
    required this.tv,
    required super.child,
  });

  final bool touch;
  final bool tv;

  @override
  bool updateShouldNotify(_FormFactorTouch old) =>
      touch != old.touch || tv != old.tv;
}
