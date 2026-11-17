import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'form_factor.dart';
import 'tv_focusable.dart';

/// Un riquadro da scegliere fra pochi (il motivo di Segnala, ...): scelto
/// ha bordo, icona e titolo oro.
class WfChoiceTile extends StatelessWidget {
  const WfChoiceTile({
    super.key,
    required this.title,
    this.description,
    this.icon,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tv = FormFactor.of(context).tv;
    final accent = selected ? WfColors.gold : WfColors.cream;
    const radius = BorderRadius.all(Radius.circular(8));
    final tile = Material(
      color: selected
          ? Color.alphaBlend(
              WfColors.gold.withValues(alpha: 0.1),
              WfColors.surfaceHigh,
            )
          : WfColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: selected ? WfColors.gold : WfColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus && !tv,
        canRequestFocus: !tv,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: accent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WfColors.creamMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: tv
          ? TvFocusable(
              onActivate: onTap,
              autofocus: autofocus,
              borderRadius: radius,
              color: selected ? tvFocusSideOnGold.color : tvFocusColor,
              child: tile,
            )
          : tile,
    );
  }
}
