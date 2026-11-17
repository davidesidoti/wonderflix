import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/reports/report_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../admin/admin_kit.dart';
import '../admin/admin_time.dart';
import '../item_edit/edit_metadata_dialog.dart';
import '../item_edit/identify_dialog.dart';
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
    final side = FormFactor.of(context).compact ? 16.0 : 32.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 0, side, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionTitle(title: l.reportsOpenTitle, count: reports.length),
          AdminList(children: [
            for (final report in reports) _ReportRow(report: report),
          ]),
        ],
      ),
    );
  }
}

/// Il tipo della voce segnalata (c'è sempre quando c'è una scorciatoia).
ItemKind _kindOf(ReportItemType? type) => switch (type) {
      ReportItemType.movie => ItemKind.movie,
      ReportItemType.series => ItemKind.series,
      ReportItemType.season => ItemKind.season,
      ReportItemType.episode => ItemKind.episode,
      null => ItemKind.other,
    };

class _ReportRow extends ConsumerWidget {
  const _ReportRow({required this.report});

  final ItemReport report;

  Widget? _shortcut(BuildContext context, AppLocalizations l) {
    Widget button(String label, IconData icon, Future<void> Function() open) =>
        TextButton.icon(
          onPressed: () => unawaited(open()),
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    return switch (reportShortcut(report)) {
      ReportShortcut.identify => button(
          l.reportShortcutIdentify,
          LucideIcons.search,
          () => showIdentifyDialog(
            context,
            itemId: report.itemId,
            kind: _kindOf(report.itemType),
          ),
        ),
      ReportShortcut.editMetadata => button(
          l.reportShortcutEdit,
          LucideIcons.pencil,
          () => showEditMetadataDialog(
            context,
            itemId: report.itemId,
            kind: _kindOf(report.itemType),
          ),
        ),
      ReportShortcut.subtitles => button(
          l.reportShortcutSubtitles,
          LucideIcons.captions,
          () => showSubtitlesDialog(
            context,
            itemId: report.itemId,
            title: reportContextLine(l, report),
          ),
        ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final compact = FormFactor.of(context).compact;
    final note = report.note;
    final hasNote = note != null && note.isNotEmpty;
    final info = Row(
      children: [
        WfLamp(state: LampState.attention, label: l.reportOpen),
        const SizedBox(width: 12),
        UserAvatar.lookup(
            userId: report.userId, name: report.userName, size: 32),
        const SizedBox(width: 12),
        // Nome, note e nomi sono testo dell'utente o della libreria.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${report.userName} · '
                  '${adminTimeLabel(report.createdAt, clock.now(), l)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(reportSubjectLine(l, report),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(hasNote ? '“$note”' : l.reportNoNote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
    final actions = [
      ?_shortcut(context, l),
      WfButton.secondary(
        label: l.reportFixedAction,
        icon: LucideIcons.check,
        onPressed: () => unawaited(
            showResolveReportDialog(context, report, ReportOutcome.fixed)),
      ),
      PopupMenuButton<ReportOutcome>(
        tooltip: l.itemActionsMenu,
        icon: const Icon(LucideIcons.ellipsis, color: WfColors.cream),
        onSelected: (outcome) =>
            unawaited(showResolveReportDialog(context, report, outcome)),
        itemBuilder: (_) => [
          PopupMenuItem(
              value: ReportOutcome.cannotFix,
              child: Text(l.reportCannotFixAction)),
        ],
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  action,
                ],
              ],
            ),
    );
  }
}
