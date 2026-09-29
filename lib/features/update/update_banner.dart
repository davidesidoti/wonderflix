import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'release_info.dart';
import 'release_notes.dart';

/// Barra "Aggiornamento pronto" in basso, con le note apribili.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({
    super.key,
    required this.release,
    required this.onRestart,
    required this.onLater,
  });

  final ReleaseInfo release;
  final VoidCallback onRestart;
  final VoidCallback onLater;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _notesOpen = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final notes = widget.release.notes;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Material(
        color: WfColors.surfaceHigh,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_notesOpen && notes.isNotEmpty) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                      child: ReleaseNotes(markdown: notes)),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  const Icon(LucideIcons.download, color: WfColors.gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.updateReadyTitle(widget.release.version.toString()),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (notes.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _notesOpen = !_notesOpen),
                      child: Text(l.updateWhatsNew),
                    ),
                  TextButton(
                      onPressed: widget.onLater, child: Text(l.updateLater)),
                  const SizedBox(width: 8),
                  WfButton.primary(
                    label: l.updateRestartNow,
                    icon: LucideIcons.rotateCw,
                    onPressed: widget.onRestart,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
