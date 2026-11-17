import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// La riga comune di ogni notifica (spec §7): pallino delle non lette,
/// avatar, frase, riga dell'ora con l'azione a destra, e la ✕.
class InboxRow extends StatefulWidget {
  const InboxRow({
    super.key,
    required this.highlighted,
    required this.leading,
    required this.sentence,
    this.below,
    required this.meta,
    this.action,
    this.onOpen,
    this.openKey,
    required this.onRemove,
  });

  final bool highlighted;
  final Widget leading;
  final InlineSpan sentence;
  final Widget? below;
  final String meta;
  final Widget? action;
  final VoidCallback? onOpen;
  final Key? openKey;
  final VoidCallback onRemove;

  static const dotSize = 8.0;

  @override
  State<InboxRow> createState() => _InboxRowState();
}

class _InboxRowState extends State<InboxRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final below = widget.below;
    final action = widget.action;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ColoredBox(
        color: widget.highlighted
            ? WfColors.surfaceHigh.withValues(alpha: 0.5)
            : Colors.transparent,
        // Il fondo sta sotto il Material, così l'inchiostro del tocco si vede.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: widget.openKey,
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: InboxRow.dotSize,
                    child: widget.highlighted
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Container(
                              key: const Key('inbox-unread'),
                              width: InboxRow.dotSize,
                              height: InboxRow.dotSize,
                              decoration: const BoxDecoration(
                                  color: WfColors.gold, shape: BoxShape.circle),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // La locandina dell'avatar sporge di 4 in basso a destra:
                  // lo spazio dopo e il margine sotto la tengono libera.
                  widget.leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          widget.sentence,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: WfColors.cream, fontSize: 14),
                        ),
                        if (below != null) ...[
                          const SizedBox(height: 4),
                          below,
                        ],
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: WfColors.creamMuted,
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            if (action != null) Flexible(child: action),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (focused) =>
                        setState(() => _focused = focused),
                    child: Opacity(
                      opacity: _hovered || _focused ? 1 : 0.4,
                      child: IconButton(
                        tooltip: l.inboxRemove,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(LucideIcons.x,
                            size: 16, color: WfColors.creamMuted),
                        onPressed: widget.onRemove,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
