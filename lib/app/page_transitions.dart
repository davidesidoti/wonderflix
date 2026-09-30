import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import 'motion.dart';

/// Durata del "fade through" tra le voci della barra: 90 ms di uscita e
/// 210 ms di entrata (spec C §6.1).
const shellTransitionDuration = Duration(milliseconds: 300);

/// Dissolvenza incrociata "fade through": la pagina entra dopo il primo 30%,
/// con una leggera scala; esce nel primo 30% quando un'altra le entra sopra.
/// Con le animazioni ridotte: sola dissolvenza.
Widget pageTransition(WfMotion motion, Animation<double> animation,
    Animation<double> secondaryAnimation, Widget child) {
  if (motion.isReduced) return FadeTransition(opacity: animation, child: child);
  final incoming = CurvedAnimation(
      parent: animation, curve: const Interval(0.3, 1, curve: Curves.easeOut));
  final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.3, curve: Curves.easeIn));
  return FadeTransition(
    opacity: ReverseAnimation(outgoing),
    child: FadeTransition(
      opacity: incoming,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(incoming),
        child: child,
      ),
    ),
  );
}

/// [underBar]: la pagina inizia sotto la barra in alto; altrimenti arriva
/// fino al bordo della finestra (Home e scheda, spec C §11.1). Il margine sta
/// dentro la pagina, non nella shell: così nel fotogramma del push/pop la
/// pagina che esce non salta.
CustomTransitionPage<void> _page(BuildContext context, GoRouterState state,
    Widget child, Duration fullDuration, bool underBar) {
  final motion = WfMotion.of(context);
  final duration = motion.duration(fullDuration);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: Padding(
      padding: EdgeInsets.only(top: underBar ? shellBarHeight : 0),
      child: child,
    ),
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        pageTransition(motion, animation, secondaryAnimation, child),
  );
}

/// Pagina di una voce della barra (Home, Film, Serie, …).
Page<void> shellPage(BuildContext context, GoRouterState state, Widget child,
        {required bool underBar}) =>
    _page(context, state, child, shellTransitionDuration, underBar);

/// Scheda del titolo e pagina della persona: dura quanto il volo Hero.
Page<void> detailPage(BuildContext context, GoRouterState state, Widget child,
        {required bool underBar}) =>
    _page(context, state, child, WfMotion.hero, underBar);
