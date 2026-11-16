import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import 'form_factor.dart';

/// La testa dei pannelli della shell (Amici, Notifiche, Consiglia, Voto):
/// titolo in Bebas, sotto [subtitle] (una riga o un widget come locandina e
/// titolo), a destra le [actions] e la ✕. Nello stretto e in TV il pannello è
/// una pagina con la sua ←: la ✕ non c'è.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.closeTooltip,
    required this.onClose,
    this.closeFocusNode,
  });

  final String title;
  final Widget? subtitle;
  final List<Widget> actions;
  final String closeTooltip;
  final VoidCallback onClose;

  /// Il fuoco di partenza dei pannelli (sulla ✕, quando c'è).
  final FocusNode? closeFocusNode;

  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WfText.display(30)),
                if (subtitle != null) ...[const SizedBox(height: 4), subtitle!],
              ],
            ),
          ),
          ...actions,
          if (!form.compact && !form.tv)
            IconButton(
              focusNode: closeFocusNode,
              tooltip: closeTooltip,
              icon: const Icon(LucideIcons.x, size: 20),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// Riga sotto la testa di un pannello ("2 online"): `creamMuted` 13.
class PanelSubtitle extends StatelessWidget {
  const PanelSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: WfColors.creamMuted, fontSize: 13),
  );
}
