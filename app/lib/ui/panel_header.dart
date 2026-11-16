import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import 'form_factor.dart';
import 'tv_text_field_frame.dart';

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

/// Il fuoco di partenza di un pannello aperto: sul desktop la ✕, in TV il
/// primo controllo del pannello (mai un campo di testo: aprirebbe la
/// tastiera), nello stretto col dito nessuno. `false` se in TV non c'è
/// ancora nulla da raggiungere (elenco che carica): si riprova.
bool focusPanelStart(BuildContext panel, FocusNode close) {
  final form = FormFactor.of(panel);
  if (form.tv) return _focusFirstControl(panel);
  if (!form.compact) close.requestFocus();
  return true;
}

bool _focusFirstControl(BuildContext panel) {
  for (final node in FocusScope.of(panel).traversalDescendants) {
    final context = node.context;
    if (context == null ||
        context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null ||
        // La cornice di un campo (`TvTextFieldFrame`) non è un controllo.
        context.findAncestorWidgetOfExactType<TvTextFieldFrame>() != null) {
      continue;
    }
    var inside = false;
    context.visitAncestorElements((e) => !(inside = identical(e, panel)));
    if (inside) {
      node.requestFocus();
      return true;
    }
  }
  return false;
}
