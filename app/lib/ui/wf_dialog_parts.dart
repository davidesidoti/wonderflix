import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';
import 'wf_buttons.dart';
import 'wf_confirm_dialog.dart';

const _muted = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);

/// La testa delle finestre: [leading] (di solito la locandina 36×54) a
/// sinistra, il titolo in Bebas e sotto [subtitle] su una riga.
class WfDialogHeader extends StatelessWidget {
  const WfDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: WfText.display(32)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _muted,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Il piede delle finestre: un filo sopra, a sinistra [note] (un
/// suggerimento o un conteggio), a destra Annulla e il [primary]. Le azioni
/// vanno a capo se non ci stanno. Senza [cancelLabel] niente Annulla; senza
/// [onCancel] Annulla fa `maybePop`, così valgono `WfDiscardGuard` e i
/// `PopScope` della finestra.
class WfDialogFooter extends StatelessWidget {
  const WfDialogFooter({
    super.key,
    this.note,
    this.cancelLabel,
    this.onCancel,
    required this.primary,
  });

  final String? note;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        if (cancelLabel != null)
          WfButton.secondary(
            label: cancelLabel!,
            icon: LucideIcons.x,
            onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
          ),
        primary,
      ],
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WfColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (note != null) ...[
                Expanded(child: Text(note!, style: _muted)),
                const SizedBox(width: 16),
              ] else
                const Spacer(),
              // La nota tiene almeno 120 di larghezza; le azioni il resto.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: note == null
                      ? constraints.maxWidth
                      : math.max(0, constraints.maxWidth - 136),
                ),
                child: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Con [changes] > 0 chiudere la finestra (Esc, clic fuori, ✕, Annulla con
/// `maybePop`) chiede prima di buttare le modifiche. Con 0 non fa niente.
class WfDiscardGuard extends StatelessWidget {
  const WfDiscardGuard({super.key, required this.changes, required this.child});

  final int changes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: changes == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final l = AppLocalizations.of(context);
        final discard = await showWfConfirmDialog(
          context,
          title: l.discardChangesTitle(changes),
          message: l.discardChangesBody,
          confirmLabel: l.discardChangesConfirm,
          cancelLabel: l.discardChangesKeep,
        );
        if (discard && context.mounted) Navigator.of(context).pop(result);
      },
      child: child,
    );
  }
}

/// Lo stato del corpo di una finestra che disegna anche il piede (fisso,
/// fuori dal corpo): ogni `setState` ridisegna [WfHostFooter]. Uno stato che
/// cambia per `ref.watch` fa `footerTick.value++` in un `ref.listen`.
mixin WfFooterHost<W extends StatefulWidget> on State<W> {
  final footerTick = ValueNotifier<int>(0);

  Widget buildFooter(BuildContext context);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    footerTick.value++;
  }

  @override
  void dispose() {
    footerTick.dispose();
    super.dispose();
  }
}

/// Il piede disegnato da [WfFooterHost] di [host]:
/// `showWfDialog(..., builder: (_) => _Body(key: key),
/// footer: (_) => WfHostFooter(host: key))`.
class WfHostFooter extends StatefulWidget {
  const WfHostFooter({super.key, required this.host});

  final GlobalKey host;

  @override
  State<WfHostFooter> createState() => _WfHostFooterState();
}

class _WfHostFooterState extends State<WfHostFooter> {
  @override
  Widget build(BuildContext context) {
    final host = widget.host.currentState;
    if (host is! WfFooterHost) {
      // Il corpo non è ancora montato: riprova al frame dopo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: host.footerTick,
      builder: (context, _) => host.buildFooter(context),
    );
  }
}
