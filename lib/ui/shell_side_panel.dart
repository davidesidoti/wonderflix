import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/motion.dart';

/// Pannello laterale sopra la shell e la barra (spec F §8.3, spec G §7.5):
/// entra da destra (con le animazioni ridotte solo in dissolvenza), il resto
/// della finestra si scurisce. Esc e un clic sullo scuro lo chiudono; con un
/// menu aperto sopra la pagina Esc è del menu.
class ShellSidePanel extends StatefulWidget {
  const ShellSidePanel({
    super.key,
    required this.open,
    required this.onClose,
    required this.scrimKey,
    required this.child,
    this.onEscape,
  });

  /// Larghezza, e quota massima della finestra.
  static const width = 360.0;
  static const maxWidthFraction = 0.9;

  /// Opacità del nero sul resto della finestra a pannello aperto (come lo
  /// scrim dei dialog di Material).
  static const scrimOpacity = 0.54;

  final bool open;
  final VoidCallback onClose;

  /// Chiave dello scuro (la cercano i test).
  final Key scrimKey;
  final Widget child;

  /// Esc a pannello aperto: `true` se l'ha usato il contenuto (es. chiude un
  /// campo); altrimenti il pannello si chiude.
  final bool Function()? onEscape;

  @override
  State<ShellSidePanel> createState() => _ShellSidePanelState();
}

class _ShellSidePanelState extends State<ShellSidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: widget.open ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    reverseCurve: WfMotion.accelerateReverse,
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void didUpdateWidget(ShellSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Prima la curva (si stacca dal controller), poi il controller.
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Esc chiude il pannello; `BackNavigationHandler` intanto non torna
  /// indietro di pagina. Con un menu aperto la route della pagina non è
  /// quella corrente: Esc lo gestisce il menu.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        !widget.open ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    if (widget.onEscape?.call() ?? false) return true;
    widget.onClose();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(ShellSidePanel.width,
            constraints.maxWidth * ShellSidePanel.maxWidthFraction);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            if (_controller.isDismissed) return const SizedBox.shrink();
            final t = _progress.value.clamp(0.0, 1.0);
            final closing = _controller.status == AnimationStatus.reverse;
            return Stack(
              children: [
                Positioned.fill(
                  // In uscita lo scuro non prende i clic: un clic lì non
                  // deve chiudere un altro pannello che intanto si apre.
                  child: IgnorePointer(
                    ignoring: closing,
                    child: GestureDetector(
                      key: widget.scrimKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onClose,
                      child: ColoredBox(
                          color: Colors.black.withValues(
                              alpha: ShellSidePanel.scrimOpacity * t)),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width,
                  child: IgnorePointer(
                    ignoring: closing,
                    child: reduced
                        ? Opacity(opacity: t, child: widget.child)
                        : FractionalTranslation(
                            translation: Offset(1 - t, 0),
                            child: widget.child,
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
