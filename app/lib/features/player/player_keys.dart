import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Riquadro di un tasto, come il `kbd` della bozza del player.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        border: const Border(
          top: BorderSide(color: WfColors.border),
          left: BorderSide(color: WfColors.border),
          right: BorderSide(color: WfColors.border),
          bottom: BorderSide(color: WfColors.border, width: 2),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WfColors.cream,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// Suggerimento di un comando; col [shortcut] mostra anche il suo tasto.
/// Senza tasto (dito, TV) è un `Tooltip` normale.
class KeyTooltip extends StatelessWidget {
  const KeyTooltip({
    super.key,
    required this.message,
    this.shortcut,
    required this.child,
  });

  final String message;
  final String? shortcut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final key = shortcut;
    if (key == null) return Tooltip(message: message, child: child);
    return RawTooltip(
      semanticsTooltip: message,
      ignorePointer: true,
      positionDelegate: (c) => positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: 24,
        preferBelow: true,
      ),
      tooltipBuilder: (context, animation) => FadeTransition(
        opacity: animation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: WfColors.surface,
            border: Border.all(color: WfColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: WfColors.cream,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 10),
              KeyCap(key),
            ],
          ),
        ),
      ),
      child: child,
    );
  }
}
