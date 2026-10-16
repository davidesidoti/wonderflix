import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

/// Il posto della carta d'invito in alto a destra (spec C §11.4): entra da
/// destra e se ne va in dissolvenza; quella che esce non riceve più clic.
/// [card] `null` = nessun invito; [id] distingue un invito dall'altro.
class InviteCardSlot extends StatelessWidget {
  const InviteCardSlot({super.key, required this.id, required this.card});

  final Object? id;
  final Widget? card;

  @override
  Widget build(BuildContext context) {
    final current = card == null
        ? const SizedBox.shrink(key: ValueKey('no-invite'))
        : KeyedSubtree(key: ValueKey(id), child: card!);
    return AnimatedSwitcher(
      duration: WfMotion.of(context).duration(WfMotion.medium),
      transitionBuilder: (child, animation) => IgnorePointer(
        // L'invito che se ne va non accetta più "Unisciti".
        ignoring: child.key != current.key,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.3, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation, curve: WfMotion.emphasized)),
            child: child,
          ),
        ),
      ),
      child: current,
    );
  }
}

/// La carta d'invito (watch party e match, spec P §7.2): icona, titolo,
/// sottotitolo, X e "Unisciti".
class InviteCardFrame extends StatelessWidget {
  const InviteCardFrame({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onDismiss,
    required this.onJoin,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onDismiss;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subtitle = this.subtitle;
    return Material(
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: WfColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: l.watchPartyDismiss,
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 26, right: 8),
                  child: Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: WfButton.primary(
                  label: l.watchPartyJoin,
                  icon: LucideIcons.play,
                  onPressed: onJoin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
