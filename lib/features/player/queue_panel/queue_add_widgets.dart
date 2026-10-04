import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/jellyfin/image_urls.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../ui/wf_image.dart';
import '../../watch_party/party_queue_rules.dart';
import '../player_side_panel_host.dart';

/// Il riquadro delle viste del pannello "Coda" (spec H §9.2): fondo al 94 %,
/// bordo sinistro, la rotella che non arriva al volume. Tutto fuori dal
/// focus tranne [field] (il campo della ricerca): i tasti restano al player.
class QueuePanelFrame extends StatelessWidget {
  const QueuePanelFrame({
    super.key,
    required this.header,
    required this.body,
    this.field,
    this.footer,
  });

  final Widget header;
  final Widget? field;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final field = this.field;
    final footer = this.footer;
    return PanelWheelBarrier(
      child: Material(
        color: WfColors.surface.withValues(alpha: 0.94),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: WfColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeFocus(child: header),
              ?field,
              Expanded(child: ExcludeFocus(child: body)),
              if (footer != null) ExcludeFocus(child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intestazione di una vista: ← (se c'è una vista prima), titolo con
/// sottotitolo, altri pulsanti, ✕.
class QueuePanelHeader extends StatelessWidget {
  const QueuePanelHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subtitle = this.subtitle;
    final onBack = this.onBack;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack == null ? 24 : 12, 20, 12, 8),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              tooltip: l.navBack,
              color: WfColors.cream,
              onPressed: onBack,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WfText.display(24)),
                if (subtitle != null)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12)),
              ],
            ),
          ),
          ...actions,
          IconButton(
            icon: const Icon(LucideIcons.x),
            tooltip: l.playerClosePanel,
            color: WfColors.cream,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Una riga delle viste Aggiungi, Serie e Stagione: immagine, titolo, riga
/// secondaria, in fondo [trailing].
class QueueItemRow extends ConsumerWidget {
  const QueueItemRow({
    super.key,
    required this.image,
    required this.title,
    this.details,
    this.trailing,
    this.onTap,
    this.landscape = false,
  });

  final ImageRef? image;
  final String title;
  final String? details;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Immagine 16:9 (episodi); altrimenti locandina 2:3.
  final bool landscape;

  /// Locandina 2:3 delle righe di film, serie e stagioni.
  static const posterWidth = 34.0;
  static const posterHeight = 51.0;

  /// Immagine 16:9 delle righe degli episodi.
  static const thumbWidth = 64.0;
  static const thumbHeight = 36.0;

  static const radius = 6.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = this.details;
    final trailing = this.trailing;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        hoverColor: WfColors.surfaceHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: landscape ? thumbWidth : posterWidth,
                  height: landscape ? thumbHeight : posterHeight,
                  child: WfImage(image: image),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (details != null)
                      Text(details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: WfColors.creamMuted)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// ↳ "Riproduci dopo" e ＋ "Aggiungi in coda" (spec H §9.2). Durante
/// l'attesa il pulsante premuto mostra un indicatore e nessuno dei due si
/// ripreme; già in coda → ✓ "In coda"; coda piena → spenti.
class QueueAddButtons extends StatefulWidget {
  const QueueAddButtons({
    super.key,
    required this.queued,
    required this.full,
    required this.onAdd,
  });

  final bool queued;
  final bool full;
  final Future<void> Function({required bool next}) onAdd;

  /// Lato dell'indicatore dell'attesa.
  static const pendingSize = 16.0;

  @override
  State<QueueAddButtons> createState() => _QueueAddButtonsState();
}

class _QueueAddButtonsState extends State<QueueAddButtons> {
  /// Il pulsante che aspetta (`true` = "Riproduci dopo"); `null` = nessuno.
  bool? _pendingNext;

  Future<void> _run(bool next) async {
    setState(() => _pendingNext = next);
    try {
      await widget.onAdd(next: next);
    } finally {
      if (mounted) setState(() => _pendingNext = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (widget.queued && _pendingNext == null) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.check, size: 14, color: WfColors.creamMuted),
            const SizedBox(width: 4),
            Text(l.partyQueueInQueue,
                style:
                    const TextStyle(fontSize: 11.5, color: WfColors.creamMuted)),
          ],
        ),
      );
    }
    Widget button(bool next) {
      final pending = _pendingNext == next;
      return IconButton(
        icon: pending
            ? const SizedBox.square(
                dimension: QueueAddButtons.pendingSize,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: WfColors.gold),
              )
            : Icon(next ? LucideIcons.listStart : LucideIcons.listPlus,
                size: 18),
        tooltip: widget.full
            ? l.partyQueueFull(partyQueueLimit)
            : next
                ? l.partyQueuePlayNext
                : l.partyQueueAddToEnd,
        color: WfColors.gold,
        visualDensity: VisualDensity.compact,
        onPressed: widget.full || _pendingNext != null ? null : () => _run(next),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [button(true), button(false)],
    );
  }
}

/// Lista vuota o errore, con "Riprova" se c'è [onRetry].
class QueueMessage extends StatelessWidget {
  const QueueMessage({super.key, required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onRetry = this.onRetry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: WfColors.creamMuted)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      ),
    );
  }
}
