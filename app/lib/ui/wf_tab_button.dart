import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'form_factor.dart';

/// Il pulsante di una scheda (pagine Richieste e Amministrazione, vista
/// Film|Saghe del catalogo): testo, con la riga oro sotto quella scelta.
class WfTabButton extends StatelessWidget {
  const WfTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Nel layout stretto si tocca con il dito: almeno 44 di altezza.
    final compact = FormFactor.of(context).compact;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints:
            BoxConstraints(minHeight: compact ? minTouchTarget : 0),
        alignment: compact ? Alignment.center : null,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: selected ? WfColors.gold : Colors.transparent, width: 2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? WfColors.cream : WfColors.creamMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
