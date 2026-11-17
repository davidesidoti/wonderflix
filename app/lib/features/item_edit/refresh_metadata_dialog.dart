import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/dialog_item_poster.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_choice_tile.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 440.0;

/// Dopo quanto si rilegge la scheda: Jellyfin mette l'aggiornamento in coda e
/// non dice quando finisce.
const refreshReloadDelay = Duration(seconds: 10);

/// "Aggiorna metadati" (spec §6.6): due riquadri e l'interruttore delle
/// immagini. Il bump è un `Timer` sul container dell'app, così scatta anche a
/// finestra chiusa.
Future<void> showRefreshMetadataDialog(
  BuildContext context, {
  required JellyfinItem item,
}) {
  final l = AppLocalizations.of(context);
  final host = GlobalKey();
  return showWfDialog<void>(
    context,
    maxWidth: _dialogWidth,
    semanticLabel: l.refreshTitle,
    compactTitle: l.refreshTitle,
    builder: (_) => _RefreshDialog(key: host, item: item),
    footer: (_) => WfHostFooter(host: host),
  );
}

class _RefreshDialog extends ConsumerStatefulWidget {
  const _RefreshDialog({super.key, required this.item});

  final JellyfinItem item;

  @override
  ConsumerState<_RefreshDialog> createState() => _RefreshDialogState();
}

class _RefreshDialogState extends ConsumerState<_RefreshDialog>
    with WfFooterHost<_RefreshDialog> {
  bool _replaceAll = false;
  bool _images = false;
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    if (_busy) return;
    final api = ref.read(itemEditApiProvider);
    // Letti prima delle attese: la finestra si chiude prima del bump.
    final session = ref.read(sessionControllerProvider.notifier);
    final revision = ref.read(libraryRevisionProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.refresh(
        widget.item.id,
        replaceAllMetadata: _replaceAll,
        replaceAllImages: _replaceAll && _images,
      );
      // Non dipende dalla finestra: il notifier è del container dell'app.
      Timer(refreshReloadDelay, revision.bump);
      messenger?.showSnackBar(SnackBar(content: Text(l.refreshStarted)));
      if (mounted) navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is ForbiddenException) {
          // Il permesso è cambiato: l'utente si rilegge.
          unawaited(session.refreshUser());
          _error = l.editNoPermission;
        } else {
          _error = describeError(l, error);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Vale anche per le sue 2 stagioni e 16 episodi", o la frase senza numeri.
  String _seriesNote(AppLocalizations l) {
    final seasons = widget.item.childCount;
    final episodes = widget.item.recursiveItemCount;
    return seasons == null || episodes == null
        ? l.refreshSeriesNoteUnknown
        : l.refreshSeriesNote(seasons, episodes);
  }

  @override
  Widget buildFooter(BuildContext context) {
    final l = AppLocalizations.of(context);
    return WfDialogFooter(
      note: _error,
      noteIsError: _error != null,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
      primary: WfButton.primary(
        label: _replaceAll ? l.refreshReplaceAll : l.refreshMissing,
        icon: LucideIcons.refreshCw,
        iconWidget: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onPressed: _busy ? null : () => unawaited(_start()),
      ),
    );
  }

  Widget _seriesBox(AppLocalizations l) => DecoratedBox(
    decoration: BoxDecoration(
      color: WfColors.gold.withValues(alpha: 0.08),
      border: Border.all(color: WfColors.gold.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 16, color: WfColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_seriesNote(l), style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget tile(String title, String hint, bool replace) => WfChoiceTile(
      title: title,
      description: hint,
      selected: _replaceAll == replace,
      onTap: _busy ? null : () => setState(() => _replaceAll = replace),
    );
    return PopScope(
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WfDialogHeader(
            title: l.refreshTitle,
            subtitle: itemContextLine(l, widget.item),
            leading: DialogItemPoster(itemId: widget.item.id),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.refreshAsk,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          tile(l.refreshMissing, l.refreshMissingHint, false),
          const SizedBox(height: 8),
          tile(l.refreshReplaceAll, l.refreshReplaceAllHint, true),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.refreshAlsoImages),
            subtitle: Text(l.refreshAlsoImagesHint),
            value: _replaceAll && _images,
            // Le immagini si sostituiscono solo con "Riscrivi tutto".
            onChanged: _busy || !_replaceAll
                ? null
                : (value) => setState(() => _images = value),
          ),
          if (widget.item.kind == ItemKind.series) ...[
            const SizedBox(height: 8),
            _seriesBox(l),
          ],
        ],
      ),
    );
  }
}
