import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Moltiplicatore dello scatto della rotella: Windows dà circa 60 px
/// (3 righe × 20 px), i browser circa 100. Da ritoccare nella prova.
const wheelScrollMultiplier = 1.6;

/// Durata dell'animazione di uno scatto.
const wheelScrollDuration = Duration(milliseconds: 200);

/// `ScrollController` con la rotella del mouse animata (spec C §5). Il
/// touchpad di precisione (PanZoom) e il trascinamento restano quelli di
/// Flutter.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      SmoothScrollPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double? _target;
  ScrollActivity? _wheelActivity;

  /// Destinazione della rotella ancora in corso. Un trascinamento, un
  /// `jumpTo` o un `animateTo` esterno cambiano l'attività e la annullano.
  double? get _pendingTarget =>
      identical(activity, _wheelActivity) ? _target : null;

  /// Solo per la rotella: Flutter la chiama per `PointerScrollEvent`.
  /// Come `animateTo`, ma con [_WheelScrollActivity]: la pagina continua a
  /// ricevere il mouse mentre scorre.
  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      super.pointerScroll(delta);
      return;
    }
    final from = _pendingTarget ?? pixels;
    final target = (from + delta * wheelScrollMultiplier)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    if (target == from) return;
    _target = target;
    updateUserScrollDirection(
        delta > 0.0 ? ScrollDirection.reverse : ScrollDirection.forward);
    if (nearEqual(target, pixels, physics.toleranceFor(this).distance)) {
      // Già lì (come `animateTo`): niente animazione.
      jumpTo(target);
      return;
    }
    final activity = _WheelScrollActivity(
      this,
      from: pixels,
      to: target,
      duration: wheelScrollDuration,
      curve: Curves.easeOutCubic,
      vsync: context.vsync,
    );
    beginActivity(activity);
    _wheelActivity = activity;
  }
}

/// Animazione di uno scatto della rotella. `DrivenScrollActivity` mette la
/// pagina sotto `IgnorePointer` finché dura (pensata per `animateTo` da
/// codice): con la rotella si perderebbero i clic e i passaggi del mouse
/// sulle card. Qui il mouse passa; un clic ferma lo scorrimento come un
/// trascinamento.
class _WheelScrollActivity extends DrivenScrollActivity {
  _WheelScrollActivity(
    super.delegate, {
    required super.from,
    required super.to,
    required super.duration,
    required super.curve,
    required super.vsync,
  });

  @override
  bool get shouldIgnorePointer => false;
}
