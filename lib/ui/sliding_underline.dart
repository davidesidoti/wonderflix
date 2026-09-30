import 'package:flutter/widgets.dart';

import '../app/motion.dart';
import '../app/theme.dart';

/// Linea oro di 2 px sotto l'elemento [selected] di un gruppo (voci della
/// barra, stagioni); scorre da un elemento all'altro (spec C §9.3, §11.1).
/// Gli elementi hanno le [itemKeys] come chiavi: la linea li misura dopo il
/// layout. Si rimisura se cambia la dimensione del testo o della finestra.
class SlidingUnderline extends StatefulWidget {
  const SlidingUnderline({
    super.key,
    required this.selected,
    required this.itemKeys,
    required this.child,
    this.indicatorKey,
  });

  final Object? selected;
  final Map<Object, GlobalKey> itemKeys;
  final Widget child;
  final Key? indicatorKey;

  @override
  State<SlidingUnderline> createState() => _SlidingUnderlineState();
}

class _SlidingUnderlineState extends State<SlidingUnderline> {
  final _stackKey = GlobalKey();

  /// Posizione dell'elemento scelto; `null` = nessuno.
  Rect? _active;

  /// Ultima posizione nota, per far sparire la linea dov'era.
  Rect? _last;

  void _measure() {
    if (!mounted) return;
    final selected = widget.selected;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = selected == null
        ? null
        : widget.itemKeys[selected]?.currentContext?.findRenderObject()
            as RenderBox?;
    Rect? rect;
    if (stack != null && box != null && box.hasSize) {
      rect = box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
    }
    if (rect != _active) {
      setState(() {
        _active = rect;
        if (rect != null) _last = rect;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    // Dipendenze: un cambio della dimensione del testo cambia le larghezze,
    // uno della finestra può mandare a capo gli elementi (stagioni).
    MediaQuery.maybeTextScalerOf(context);
    MediaQuery.maybeSizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final shown = _active ?? _last;
    return Stack(
      key: _stackKey,
      children: [
        widget.child,
        if (shown != null)
          AnimatedPositioned(
            key: widget.indicatorKey,
            left: shown.left,
            width: shown.width,
            top: shown.bottom - 2,
            height: 2,
            duration: motion.pick(full: WfMotion.medium, reduced: Duration.zero),
            curve: WfMotion.emphasized,
            child: AnimatedOpacity(
              opacity: _active == null ? 0 : 1,
              duration: WfMotion.fast,
              child: const ColoredBox(color: WfColors.gold),
            ),
          ),
      ],
    );
  }
}
