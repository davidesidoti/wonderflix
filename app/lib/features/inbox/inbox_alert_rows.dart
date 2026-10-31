import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/inbox_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'notification_text.dart';

/// L'icona di una voce di spec V (admin e richieste accettate o rifiutate).
IconData alertIconOf(AlertedEntry entry) => switch (entry) {
      RequestApprovedEntry() => LucideIcons.clapperboard,
      RequestDeclinedEntry() => LucideIcons.circleX,
      DownloadNeedsYouEntry() ||
      DownloadStalledEntry() =>
        LucideIcons.download,
      LightenBlockedEntry() ||
      SpaceOperationFailedEntry() ||
      DiskAlmostFullEntry() =>
        LucideIcons.hardDrive,
      RecoveryStartedEntry() || RecoveryBlockedEntry() => LucideIcons.shieldAlert,
      RestartPendingEntry() => LucideIcons.rotateCw,
    };

/// Il testo di una voce di spec V: titolo e testo come la push (stesso
/// `notificationTextOf`), l'ora; il clic chiude il pannello e va alla sua
/// rotta.
class InboxAlertContent extends ConsumerWidget {
  const InboxAlertContent({super.key, required this.entry, required this.time});

  final AlertedEntry entry;
  final String time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = notificationTextOf(entry, AppLocalizations.of(context));
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: () {
          ref.read(shellPanelProvider.notifier).close();
          context.go(text.route);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: WfColors.cream, fontWeight: FontWeight.w600)),
              if (text.body.isNotEmpty)
                Text(text.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 13)),
              const SizedBox(height: 4),
              Text(time,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
