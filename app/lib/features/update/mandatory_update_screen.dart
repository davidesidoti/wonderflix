import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'release_notes.dart';
import 'update_controller.dart';

/// Schermata bloccante: la versione installata è sotto `min-version`.
class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({
    super.key,
    required this.update,
    required this.onInstall,
    required this.onRetry,
  });

  final UpdateState update;
  final VoidCallback onInstall;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final release = update.release!;
    final progress = update.progress;
    return Material(
      color: WfColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.download, color: WfColors.gold, size: 40),
                const SizedBox(height: 16),
                Text(l.updateRequiredTitle.toUpperCase(),
                    style: WfText.display(36)),
                const SizedBox(height: 8),
                Text(l.updateRequiredBody(release.version.toString()),
                    style: const TextStyle(color: WfColors.creamMuted)),
                if (release.notes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                        child: ReleaseNotes(markdown: release.notes)),
                  ),
                ],
                const SizedBox(height: 24),
                if (update.failed)
                  Text(l.updateDownloadFailed,
                      style: const TextStyle(color: WfColors.error))
                else if (!update.ready) ...[
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(l.updateDownloading(((progress ?? 0) * 100).round())),
                ],
                const SizedBox(height: 16),
                // Chiavi diverse: il pulsante si ricrea quando diventa
                // attivo e l'autofocus scatta di nuovo (Invio lo preme).
                if (update.failed)
                  WfButton.primary(
                      key: const ValueKey('retry'),
                      label: l.retry,
                      icon: LucideIcons.refreshCw,
                      autofocus: true,
                      onPressed: onRetry)
                else
                  WfButton.primary(
                    key: ValueKey('install-${update.ready}'),
                    label: l.updateInstallNow,
                    icon: LucideIcons.download,
                    autofocus: true,
                    onPressed: update.ready ? onInstall : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
