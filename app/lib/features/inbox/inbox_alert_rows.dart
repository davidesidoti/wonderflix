import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/social/inbox_models.dart';

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
