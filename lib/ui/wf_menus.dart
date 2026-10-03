import 'package:flutter/material.dart';

import '../app/motion.dart';

/// Animazione dei menu a comparsa dai token (spec C §11.4). Va passata a
/// ogni `PopupMenuButton` (non esiste nel tema).
AnimationStyle wfPopUpAnimation(BuildContext context) {
  final motion = WfMotion.of(context);
  return AnimationStyle(
    duration: motion.duration(WfMotion.medium),
    curve: WfMotion.emphasized,
    reverseDuration: WfMotion.fast,
  );
}

/// Distanza minima tra un menu e il bordo della finestra (come in
/// `showMenu`).
const menuScreenMargin = 8.0;

/// Posizione di un menu ancorato ad [anchor]: sotto, come quella di
/// `PopupMenuButton`. `showMenu` non rovescia un menu che sotto non ci sta:
/// lo spinge in su quanto basta, e il menu copre il pulsante (es. nella
/// barra in basso del player). Con [estimatedHeight], l'altezza prevista del
/// menu, se sotto non c'è posto il menu si apre sopra il pulsante.
RelativeRect menuPositionBelow(BuildContext anchor, {double? estimatedHeight}) {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay);
  final height = estimatedHeight;
  final above = height != null &&
      overlay.size.height - bottomRight.dy < height + menuScreenMargin;
  // `showMenu` mette il bordo alto del menu sul bordo alto del rettangolo.
  final top = above ? topLeft.dy - height : bottomRight.dy;
  return RelativeRect.fromRect(
    Rect.fromLTRB(topLeft.dx, top, bottomRight.dx, top),
    Offset.zero & overlay.size,
  );
}
