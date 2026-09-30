import 'package:flutter/widgets.dart';

import '../app/motion.dart';

/// Dissolvenza incrociata tra scheletro e contenuto (spec C §10.3). Il
/// [child] deve avere una chiave diversa per ogni stato. Con [expand] il
/// contenuto occupa tutto lo spazio (pagine intere); senza, prende la sua
/// altezza (sezioni dentro una lista).
///
/// Durante la dissolvenza il figlio che esce resta nell'albero: i suoi
/// Hero sono spenti e con [isOutgoing] può lasciare il controller dello
/// scroll a quello che entra.
class WfSwitcher extends StatelessWidget {
  const WfSwitcher({super.key, required this.child, this.expand = false});

  final Widget child;
  final bool expand;

  /// `true` se [context] sta nel figlio che esce dal [WfSwitcher] più
  /// vicino. Un controller di scroll condiviso tra gli stati va dato solo
  /// al figlio che entra: se lo stesso stato torna mentre il vecchio sta
  /// ancora sfumando, due liste starebbero sullo stesso controller.
  static bool isOutgoing(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SwitcherSlot>()?.outgoing ??
      false;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: WfMotion.of(context).duration(WfMotion.medium),
        switchInCurve: WfMotion.standard,
        switchOutCurve: WfMotion.standard,
        layoutBuilder: (current, previous) => Stack(
          fit: expand ? StackFit.expand : StackFit.loose,
          // In alto a sinistra: i testi brevi restano allineati come prima.
          alignment: AlignmentDirectional.topStart,
          children: [
            for (final old in previous) _slot(old, outgoing: true),
            if (current != null) _slot(current, outgoing: false),
          ],
        ),
        child: child,
      );

  // Stessa chiave della transizione: passando da "entra" a "esce" il
  // figlio non si ricrea.
  static Widget _slot(Widget child, {required bool outgoing}) => _SwitcherSlot(
        key: child.key,
        outgoing: outgoing,
        child: HeroMode(enabled: !outgoing, child: child),
      );
}

class _SwitcherSlot extends InheritedWidget {
  const _SwitcherSlot(
      {super.key, required this.outgoing, required super.child});

  final bool outgoing;

  @override
  bool updateShouldNotify(_SwitcherSlot oldWidget) =>
      oldWidget.outgoing != outgoing;
}
