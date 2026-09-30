import 'dart:async';

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
    unawaited(animateTo(target,
        duration: wheelScrollDuration, curve: Curves.easeOutCubic));
    _wheelActivity = activity;
  }
}
