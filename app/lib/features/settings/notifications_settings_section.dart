import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'notification_prefs_controller.dart';

/// Larghezza massima della sezione, come le altre impostazioni.
const _notificationsMaxWidth = 640.0;

/// I tipi per gruppo, come le destinazioni del plugin: i 10 per tutti, le
/// richieste da approvare e i 9 solo per gli admin. Un tipo che l'app non
/// conosce non ha etichetta e non si mostra.
const _forYou = {
  'Invite',
  'Announcement',
  'NewTitles',
  'RequestAvailable',
  'RequestApproved',
  'RequestDeclined',
  'ContactReminder',
  'Recommendation',
  'MatchInvite',
  'ReportResolved',
};
const _requests = {'RequestPending'};
const _admin = {
  'ReportPending',
  'DownloadNeedsYou',
  'DownloadStalled',
  'LightenBlocked',
  'SpaceOperationFailed',
  'DiskAlmostFull',
  'RecoveryStarted',
  'RecoveryBlocked',
  'RestartPending',
};

String _label(AppLocalizations l, String type) => switch (type) {
      'Invite' => l.notifPrefInvite,
      'Announcement' => l.notifPrefAnnouncement,
      'NewTitles' => l.notifPrefNewTitles,
      'RequestAvailable' => l.notifPrefRequestAvailable,
      'RequestApproved' => l.notifPrefRequestApproved,
      'RequestDeclined' => l.notifPrefRequestDeclined,
      'ContactReminder' => l.notifPrefContactReminder,
      'Recommendation' => l.notifPrefRecommendation,
      'MatchInvite' => l.notifPrefMatchInvite,
      'ReportResolved' => l.notifPrefReportResolved,
      'RequestPending' => l.notifPrefRequestPending,
      'ReportPending' => l.notifPrefReportPending,
      'DownloadNeedsYou' => l.notifPrefDownloadNeedsYou,
      'DownloadStalled' => l.notifPrefDownloadStalled,
      'LightenBlocked' => l.notifPrefLightenBlocked,
      'SpaceOperationFailed' => l.notifPrefSpaceOperationFailed,
      'DiskAlmostFull' => l.notifPrefDiskAlmostFull,
      'RecoveryStarted' => l.notifPrefRecoveryStarted,
      'RecoveryBlocked' => l.notifPrefRecoveryBlocked,
      _ => l.notifPrefRestartPending,
    };

/// Impostazioni → Notifiche (spec V §4.2): un interruttore per ogni tipo che
/// il plugin offre all'utente. Si monta solo con la funzione `push`.
class NotificationsSettingsSection extends ConsumerWidget {
  const NotificationsSettingsSection({super.key});

  Future<void> _set(
      BuildContext context, WidgetRef ref, String type, bool enabled) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await ref
        .read(notificationPrefsProvider.notifier)
        .setEnabled(type, enabled)) {
      messenger?.showSnackBar(
          SnackBar(content: Text(l.settingsShareActivitySaveError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(notificationPrefsProvider);
    final Widget child;
    if (prefs.hasError && !prefs.hasValue) {
      child = Row(
        children: [
          Expanded(
            child: Text(l.settingsShareActivityLoadError,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
          TextButton(
            key: const Key('notification-prefs-retry'),
            onPressed: () => ref.invalidate(notificationPrefsProvider),
            child: Text(l.retry),
          ),
        ],
      );
    } else {
      final types = prefs.value?.types ?? const [];
      // Un gruppo si vede solo se ha tipi; dentro, l'ordine del plugin.
      Widget group(String title, Set<String> members) {
        final shown = [
          for (final pref in types)
            if (members.contains(pref.type)) pref,
        ];
        if (shown.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(title,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontWeight: FontWeight.w600)),
            ),
            for (final pref in shown)
              SwitchListTile(
                key: Key('notification-pref-${pref.type}'),
                contentPadding: EdgeInsets.zero,
                title: Text(_label(l, pref.type)),
                value: pref.enabled,
                onChanged: (next) =>
                    unawaited(_set(context, ref, pref.type, next)),
              ),
          ],
        );
      }

      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          group(l.notifPrefsGroupForYou, _forYou),
          group(l.notifPrefsGroupRequests, _requests),
          group(l.notifPrefsGroupAdmin, _admin),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _notificationsMaxWidth),
        child: child,
      ),
    );
  }
}
