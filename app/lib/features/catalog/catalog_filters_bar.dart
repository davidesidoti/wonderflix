import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';

/// Altezza di una riga di menu della barra dei filtri.
const filtersBarHeight = 40.0;

/// Un menu della barra dei filtri (catalogo, La mia lista, vista "Saghe").
class FilterPicker<T> extends StatelessWidget {
  const FilterPicker(
      {super.key,
      required this.value,
      required this.items,
      required this.onChanged,
      this.autofocus = false});

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBorder(
      child: Container(
        height: filtersBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: WfColors.surfaceHigh,
          border: Border.all(color: WfColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            autofocus: autofocus,
            // Nello stretto riempie la riga: col testo lungo non sfora. Sulla
            // TV (larga 960) no: i filtri stanno in una riga sopra la griglia.
            isExpanded:
                FormFactor.of(context).compact && !FormFactor.of(context).tv,
            value: items.containsKey(value) ? value : null,
            dropdownColor: WfColors.surface,
            style: const TextStyle(color: WfColors.cream, fontSize: 13.5),
            items: [
              for (final entry in items.entries)
                DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) {
              // DropdownButton avvisa anche se si riscegli la stessa voce.
              if (v != value) onChanged(v as T);
            },
          ),
        ),
      ),
    );
  }
}
