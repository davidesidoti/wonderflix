import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Pulsante con etichetta e icona. Larghezza adatta al contenuto (il tema
/// globale rende i FilledButton larghi quanto il contenitore, qui no).
class WfButton extends StatelessWidget {
  const WfButton.primary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  }) : primary = true;

  const WfButton.secondary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  }) : primary = false;

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    const size = Size(0, 44);
    const padding = EdgeInsets.symmetric(horizontal: 20);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: size,
        padding: padding,
        shape: shape,
        foregroundColor: WfColors.cream,
        side: const BorderSide(color: WfColors.border),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Pulsante tondo con stato attivo (preferito, visto).
class WfIconToggle extends StatelessWidget {
  const WfIconToggle({
    super.key,
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        foregroundColor: selected ? WfColors.gold : WfColors.cream,
        side: BorderSide(color: selected ? WfColors.gold : WfColors.border),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}
