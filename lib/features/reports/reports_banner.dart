import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/reports/report_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../subtitles/subtitles_dialog.dart';
import 'admin_reports_controller.dart';
import 'report_labels.dart';
import 'resolve_report_dialog.dart';

/// Il riquadro delle segnalazioni aperte di un titolo, nel dettaglio di un
/// film o di una serie (spec R §7.7). Solo per gli admin: per gli altri, e
/// durante il caricamento, non c'è. Comprende anche le segnalazioni delle
/// stagioni e degli episodi di una serie.
class ReportsBanner extends ConsumerWidget {
  const ReportsBanner({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = jellyfinIdKey(titleId);
    final reports = [
      for (final report in ref.watch(adminReportsProvider).value ?? const [])
        if (jellyfinIdKey(report.titleId) == key) report,
    ];
    if (key.isEmpty || reports.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.gold),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.reportsBannerTitle(reports.length),
              style: const TextStyle(
                  color: WfColors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          for (final report in reports) _ReportRow(report: report),
        ],
      ),
    );
  }
}

class _ReportRow extends ConsumerWidget {
  const _ReportRow({required this.report});

  final ItemReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final note = report.note;
    final shortcut = reportShortcut(report);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
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
                // Nome e nota sono testo dell'utente: sempre testo semplice.
                Text(report.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    reportTitleLine(l,
                        title: '',
                        itemType: report.itemType,
                        season: report.seasonNumber,
                        episode: report.episodeNumber,
                        type: report.type),
                    style: const TextStyle(color: WfColors.creamMuted)),
                const SizedBox(height: 4),
                Text(note != null && note.isNotEmpty ? note : l.reportNoNote,
                    style: note != null && note.isNotEmpty
                        ? null
                        : const TextStyle(color: WfColors.creamMuted)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WfButton.primary(
                      label: l.reportFixed,
                      icon: LucideIcons.check,
                      onPressed: () => unawaited(showResolveReportDialog(
                          context, ref, report, ReportOutcome.fixed)),
                    ),
                    WfButton.secondary(
                      label: l.reportCannotFix,
                      icon: LucideIcons.x,
                      onPressed: () => unawaited(showResolveReportDialog(
                          context, ref, report, ReportOutcome.cannotFix)),
                    ),
                    if (shortcut == ReportShortcut.subtitles)
                      WfButton.secondary(
                        label: l.reportShortcutSubtitles,
                        icon: LucideIcons.captions,
                        onPressed: () => unawaited(showSubtitlesDialog(
                          context,
                          itemId: report.itemId,
                          title: reportTitleLine(l,
                              title: report.titleName,
                              itemType: report.itemType,
                              season: report.seasonNumber,
                              episode: report.episodeNumber),
                        )),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
