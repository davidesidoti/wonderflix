import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'diagnostics.dart';

/// Diagnostica da incollare nelle richieste di aiuto e cartella dei log.
class SupportSection extends ConsumerWidget {
  const SupportSection({super.key});

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final text = await ref.read(collectDiagnosticsProvider)();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.settingsDiagnosticsCopied)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.settingsSupportHint,
            style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            WfButton.secondary(
              label: l.settingsCopyDiagnostics,
              icon: LucideIcons.clipboardCopy,
              onPressed: () => unawaited(_copy(context, ref)),
            ),
            WfButton.secondary(
              label: l.settingsOpenLogs,
              icon: LucideIcons.folderOpen,
              onPressed: () => unawaited(ref.read(openLogsFolderProvider)()),
            ),
          ],
        ),
      ],
    );
  }
}
