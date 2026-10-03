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

/// Posizione di un menu aperto sotto [anchor], come quella di
/// `PopupMenuButton`; se sotto non c'è spazio `showMenu` lo apre sopra.
RelativeRect menuPositionBelow(BuildContext anchor) {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(button.size.bottomLeft(Offset.zero),
          ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(Offset.zero),
          ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );
}
