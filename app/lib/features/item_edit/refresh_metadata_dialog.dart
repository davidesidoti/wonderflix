import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 440.0;

/// Dopo quanto si rilegge la scheda: Jellyfin mette l'aggiornamento in coda e
/// non dice quando finisce.
const refreshReloadDelay = Duration(seconds: 10);

/// "Aggiorna metadati" (spec R §7.10): due scelte e la casella delle immagini.
/// Il bump è un `Timer` sul container dell'app, così scatta anche a finestra
/// chiusa.
Future<void> showRefreshMetadataDialog(
  BuildContext context, {
  required String itemId,
}) => showWfDialog<void>(
  context,
  maxWidth: _dialogWidth,
  semanticLabel: AppLocalizations.of(context).refreshTitle,
  builder: (_) => _RefreshDialog(itemId: itemId),
);

class _RefreshDialog extends ConsumerStatefulWidget {
  const _RefreshDialog({required this.itemId});

  final String itemId;

  @override
  ConsumerState<_RefreshDialog> createState() => _RefreshDialogState();
}

class _RefreshDialogState extends ConsumerState<_RefreshDialog> {
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
        widget.itemId,
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.refreshTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            RadioGroup<bool>(
              groupValue: _replaceAll,
              onChanged: (value) {
                if (!_busy) setState(() => _replaceAll = value ?? false);
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.refreshMissing),
                    value: false,
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.refreshReplaceAll),
                    value: true,
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.refreshAlsoImages),
              value: _replaceAll && _images,
              // Le immagini si sostituiscono solo con "sostituisci tutto".
              onChanged: _busy || !_replaceAll
                  ? null
                  : (value) => setState(() => _images = value ?? false),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!),
            ],
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                WfButton.primary(
                  label: l.refreshStart,
                  icon: LucideIcons.refreshCw,
                  onPressed: _busy ? null : () => unawaited(_start()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
