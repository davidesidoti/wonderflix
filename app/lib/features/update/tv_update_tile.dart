import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import 'update_controller.dart';

/// Codice di Downloader (aftv.news) che porta a [tvApkAddress]; `null` finché
/// l'utente non lo crea.
const String? tvDownloaderCode = null;

/// Da dove si reinstalla l'APK della TV.
const tvApkAddress = 'hashvps.proton.usbx.me/wonderflix/tv.apk';

/// "Se l'aggiornamento non va, disinstalla e reinstalla con Downloader".
String tvReinstallHint(AppLocalizations l) {
  const code = tvDownloaderCode;
  return code == null
      ? l.tvUpdateReinstallUrl(tvApkAddress)
      : l.tvUpdateReinstallCode(code);
}

/// Sulla TV, in Impostazioni sotto la versione: l'aggiornamento disponibile
/// e "Aggiorna" (niente banner, ruberebbe il focus). Fuori dalla TV niente.
class TvUpdateTile extends ConsumerWidget {
  const TvUpdateTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateControllerProvider);
    final release = update.release;
    if (!FormFactor.of(context).tv || release == null) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tvUpdateAvailable(release.version.toString()),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (update.ready)
            WfButton.primary(
              label: l.tvUpdateInstall,
              icon: LucideIcons.download,
              onPressed: () => unawaited(
                  ref.read(updateControllerProvider.notifier).install()),
            )
          else
            Text(l.updateDownloading(((update.progress ?? 0) * 100).round()),
                style: muted),
          if (update.installPermissionNeeded) ...[
            const SizedBox(height: 12),
            Text(l.tvUpdatePermission, style: muted),
          ],
        ],
      ),
    );
  }
}
