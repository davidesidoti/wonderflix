import '../../core/social/inbox_models.dart';

/// Se la voce va nella vista "Server" (solo admin): download, spazio,
/// riavvio, recupero, richieste e segnalazioni da gestire. Il resto è "Per
/// te". Lo `switch` è esaustivo: un tipo nuovo non compila finché non si
/// sceglie.
bool isServerEntry(InboxEntry entry) => switch (entry) {
  DownloadNeedsYouEntry() ||
  DownloadStalledEntry() ||
  LightenBlockedEntry() ||
  SpaceOperationFailedEntry() ||
  DiskAlmostFullEntry() ||
  RestartPendingEntry() ||
  RecoveryStartedEntry() ||
  RecoveryBlockedEntry() ||
  RequestPendingEntry() ||
  ReportPendingEntry() => true,
  InviteEntry() ||
  MatchInviteEntry() ||
  RecommendationEntry() ||
  AnnouncementEntry() ||
  NewTitlesEntry() ||
  RequestAvailableEntry() ||
  RequestApprovedEntry() ||
  RequestDeclinedEntry() ||
  ContactReminderEntry() ||
  ReportResolvedEntry() => false,
};
