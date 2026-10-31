import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import '../../core/social/inbox_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/locale_controller.dart';
import '../settings/notification_prefs_controller.dart';
import 'inbox_controller.dart';
import 'notification_text.dart';
import 'windows_toasts.dart';

final _log = Logger('social');

final toastsProvider = Provider<Toasts>((ref) => createToasts());

/// Le voci che arrivano con l'app aperta diventano notifiche di Windows,
/// solo per i tipi che l'utente vuole. Toccata, la notifica riporta davanti
/// la finestra e apre la rotta della voce. La avvia la shell.
final inboxToasterProvider = Provider<void>((ref) {
  final toasts = ref.watch(toastsProvider);
  // Le preferenze si caricano subito: finché mancano, ogni tipo vale.
  ref.listen(notificationPrefsProvider, (_, _) {});
  final arrivals = ref.watch(inboxControllerProvider.notifier).arrivals.listen((
    entry,
  ) {
    // Una notifica che non si può comporre non deve rompere l'app.
    try {
      _toast(ref, toasts, entry);
    } on Object catch (error) {
      _log.info('notifica di Windows non composta: ${error.runtimeType}');
    }
  });
  ref.onDispose(() => unawaited(arrivals.cancel()));
});

void _toast(Ref ref, Toasts toasts, InboxEntry entry) {
  if (!ref
      .read(notificationPrefsProvider.notifier)
      .isEnabled(inboxTypeOf(entry))) {
    return;
  }
  final locale =
      ref.read(localeProvider) ??
      basicLocaleListResolution(
        PlatformDispatcher.instance.locales,
        AppLocalizations.supportedLocales,
      );
  final text = notificationTextOf(entry, lookupAppLocalizations(locale));
  toasts.show(text.title, text.body, () async {
    await windowManager.show();
    await windowManager.focus();
    if (ref.mounted) ref.read(routerProvider).go(text.route);
  });
}

/// Il tipo della voce come lo chiama il plugin (`Type`).
String inboxTypeOf(InboxEntry entry) => switch (entry) {
  InviteEntry() => 'Invite',
  AnnouncementEntry() => 'Announcement',
  NewTitlesEntry() => 'NewTitles',
  RequestAvailableEntry() => 'RequestAvailable',
  RequestPendingEntry() => 'RequestPending',
  ContactReminderEntry() => 'ContactReminder',
  RecommendationEntry() => 'Recommendation',
  MatchInviteEntry() => 'MatchInvite',
  ReportPendingEntry() => 'ReportPending',
  ReportResolvedEntry() => 'ReportResolved',
  RequestApprovedEntry() => 'RequestApproved',
  RequestDeclinedEntry() => 'RequestDeclined',
  DownloadNeedsYouEntry() => 'DownloadNeedsYou',
  DownloadStalledEntry() => 'DownloadStalled',
  LightenBlockedEntry() => 'LightenBlocked',
  SpaceOperationFailedEntry() => 'SpaceOperationFailed',
  DiskAlmostFullEntry() => 'DiskAlmostFull',
  RecoveryStartedEntry() => 'RecoveryStarted',
  RecoveryBlockedEntry() => 'RecoveryBlocked',
  RestartPendingEntry() => 'RestartPending',
};
