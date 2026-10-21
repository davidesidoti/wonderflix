import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/reports/report_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/user_avatar.dart';
import '../reports/admin_reports_controller.dart';
import '../reports/report_labels.dart';
import '../social/social_providers.dart';
import 'admin_action_button.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';

/// Altezza massima dell'elenco dentro la card.
const _reportsMaxHeight = 480.0;

/// "Segnalazioni" (spec R §7.8): le segnalazioni aperte di tutti i titoli,
/// con "Apri" sulla scheda del titolo.
class ReportsCard extends ConsumerWidget {
  const ReportsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    return AdminCard(
      title: l.adminReportsTitle,
      icon: LucideIcons.flag,
      child: !features.known
          ? const SkeletonBox(width: 240, height: 20)
          : !features.reports
              ? Text(l.adminReportsNeedPlugin,
                  style: const TextStyle(color: WfColors.creamMuted))
              : _list(context, ref, l),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final data = ref.watch(adminReportsProvider);
    final reports = data.value;
    if (reports == null) {
      return data.hasError
          ? AdminCardError(
              error: data.error!,
              onRetry: () => ref.invalidate(adminReportsProvider))
          : const SkeletonBox(width: 240, height: 20);
    }
    if (reports.isEmpty) return AdminEmptyText(text: l.adminReportsEmpty);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _reportsMaxHeight),
      child: ListView(
        shrinkWrap: true,
        children: [for (final report in reports) _ReportTile(report: report)],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final ItemReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar.lookup(
              userId: report.userId, name: report.userName, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titoli e nomi sono testo della libreria o dell'utente.
                Text(
                    reportTitleLine(l,
                        title: report.titleName,
                        itemType: report.itemType,
                        season: report.seasonNumber,
                        episode: report.episodeNumber,
                        type: report.type),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    '${report.userName} · '
                    '${adminTimeLabel(report.createdAt, clock.now(), l)}',
                    style: const TextStyle(color: WfColors.creamMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AdminActionButton(
            label: l.adminReportsOpen,
            icon: LucideIcons.externalLink,
            onPressed: () async => openItemById(context, report.titleId),
          ),
        ],
      ),
    );
  }
}
