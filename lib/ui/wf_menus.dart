import 'package:flutter/widgets.dart';

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
