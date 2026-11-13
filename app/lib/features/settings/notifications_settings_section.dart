import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/notifications_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../admin/admin_kit.dart';
import 'device_push_tile.dart';
import 'notification_prefs_controller.dart';
import 'settings_kit.dart';

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
      'RestartPending' => l.notifPrefRestartPending,
      _ => type,
    };

/// Impostazioni → Notifiche (spec V §4.2): i tipi che il plugin offre
/// all'utente, a gruppi che si aprono e si accendono insieme. Si monta solo
/// con la funzione `push`.
class NotificationsSettingsSection extends ConsumerStatefulWidget {
  const NotificationsSettingsSection({super.key});

  @override
  ConsumerState<NotificationsSettingsSection> createState() =>
      _NotificationsSettingsSectionState();
}

class _NotificationsSettingsSectionState
    extends ConsumerState<NotificationsSettingsSection> {
  /// I gruppi aperti: lo stato vive solo qui. Nel largo parte aperto "Per te".
  Set<String>? _open;

  /// Un solo avviso per tocco, anche se più tipi non si salvano.
  Future<void> _save(Iterable<(String, bool)> changes) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(notificationPrefsProvider.notifier);
    final results = await Future.wait([
      for (final (type, enabled) in changes) notifier.setEnabled(type, enabled),
    ]);
    if (results.contains(false)) {
      messenger?.showSnackBar(
          SnackBar(content: Text(l.settingsShareActivitySaveError)));
    }
  }

  /// Tutti accesi: li spegne tutti; altrimenti accende quelli spenti.
  Future<void> _setGroup(List<NotificationTypePref> shown) {
    final next = !shown.every((p) => p.enabled);
    return _save([
      for (final p in shown)
        if (p.enabled != next) (p.type, next),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(notificationPrefsProvider);
    final Widget child;
    // Rileggendo (es. dopo un cambio di profilo) il valore tenuto è di un
    // altro utente: non si mostra.
    if (prefs.isLoading) {
      child = const SizedBox.shrink();
    } else if (prefs.hasError && !prefs.hasValue) {
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
      final open =
          _open ??= FormFactor.of(context).compact ? <String>{} : {'forYou'};
      Widget typeRow(NotificationTypePref pref, String label,
              {double indent = 0}) =>
          SettingsSwitchRow(
            key: Key('notification-pref-${pref.type}'),
            label: label,
            indent: indent,
            value: pref.enabled,
            onChanged: (next) => unawaited(_save([(pref.type, next)])),
          );
      // Un gruppo si vede solo se ha tipi; dentro, l'ordine del plugin.
      List<Widget> group(String id, String title, Set<String> members) {
        final shown = [
          for (final pref in types)
            if (members.contains(pref.type)) pref,
        ];
        if (shown.isEmpty) return const [];
        // Un solo tipo: una riga normale, senza freccia. Col nome del gruppo
        // solo per le richieste da approvare (il gruppo è il tipo); un altro
        // gruppo con un tipo solo ha l'etichetta del tipo.
        if (shown.length == 1) {
          return [
            typeRow(shown.first,
                id == 'requests' ? title : _label(l, shown.first.type)),
          ];
        }
        final isOpen = open.contains(id);
        return [
          _GroupHeader(
            switchKey: Key('notification-group-$id'),
            title: title,
            count: l.notifPrefsGroupCount(
                shown.where((p) => p.enabled).length, shown.length),
            open: isOpen,
            allOn: shown.every((p) => p.enabled),
            onToggleOpen: () =>
                setState(() => isOpen ? open.remove(id) : open.add(id)),
            onToggleAll: () => unawaited(_setGroup(shown)),
          ),
          if (isOpen)
            for (final pref in shown)
              typeRow(pref, _label(l, pref.type), indent: 20),
        ];
      }

      final rows = [
        ...group('forYou', l.notifPrefsGroupForYou, _forYou),
        ...group('requests', l.notifPrefsGroupRequests, _requests),
        ...group('admin', l.notifPrefsGroupAdmin, _admin),
      ];
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DevicePushTile(),
          if (rows.isNotEmpty) AdminList(children: rows),
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

/// L'intestazione di un gruppo: toccarla (fuori dall'interruttore) apre o
/// chiude; l'interruttore accende o spegne tutto il gruppo.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.switchKey,
    required this.title,
    required this.count,
    required this.open,
    required this.allOn,
    required this.onToggleOpen,
    required this.onToggleAll,
  });

  final Key switchKey;
  final String title;
  final String count;
  final bool open;
  final bool allOn;
  final VoidCallback onToggleOpen;
  final VoidCallback onToggleAll;

  @override
  @override
  Widget build(BuildContext context) => Material(
        color: WfColors.surface,
        child: Row(
          children: [
            Expanded(
              // Un nodo solo per chi legge lo schermo: nome, conteggio e se è
              // aperto. L'interruttore è un altro nodo, col nome del gruppo.
              child: Semantics(
                container: true,
                button: true,
                expanded: open,
                label: '$title, $count',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onToggleOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 0, 6),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: minTouchTarget - 12),
                      child: Row(
                        children: [
                          Icon(
                            open
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            size: 16,
                            color: WfColors.creamMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                children: [
                                  TextSpan(
                                    text: '  $count',
                                    style: const TextStyle(
                                      color: WfColors.creamMuted,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14),
              child: Semantics(
                container: true,
                label: title,
                child: Switch(
                  key: switchKey,
                  value: allOn,
                  onChanged: (_) => onToggleAll(),
                ),
              ),
            ),
          ],
        ),
      );
}
