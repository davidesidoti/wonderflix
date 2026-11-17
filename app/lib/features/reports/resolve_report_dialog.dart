import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/reports/report_models.dart';
import '../../core/reports/reports_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/dialog_item_poster.dart';
import '../../ui/rune_limit.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../auth/session_controller.dart';
import 'admin_reports_controller.dart';
import 'report_dialog.dart';
import 'report_labels.dart';

/// Da qui il contatore `n/500` è visibile.
const _counterFrom = 450;

/// Come si chiude la finestra: chiusa da noi, o già chiusa da un altro admin.
enum _Result { closed, alreadyClosed }

/// Chiude [report] con [outcome] e una nota facoltativa (spec R §7.7).
/// A segnalazione chiusa compare lo snackbar; se un altro admin l'aveva già
/// chiusa, la finestra si chiude con l'altro snackbar; gli altri errori
/// restano nel piede della finestra.
Future<void> showResolveReportDialog(
  BuildContext context,
  ItemReport report,
  ReportOutcome outcome,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = AppLocalizations.of(context);
  final title = outcome == ReportOutcome.fixed
      ? l.reportResolveFixedTitle
      : l.reportResolveCannotFixTitle;
  final host = GlobalKey();
  final result = await showWfDialog<_Result>(
    context,
    semanticLabel: title,
    compactTitle: title,
    builder: (_) => _ResolveDialog(key: host, report: report, outcome: outcome),
    footer: (_) => WfHostFooter(host: host),
  );
  if (result == null) return;
  messenger?.showSnackBar(SnackBar(
      content: Text(
          result == _Result.closed ? l.reportClosed : l.reportAlreadyClosed)));
}

class _ResolveDialog extends ConsumerStatefulWidget {
  const _ResolveDialog({
    super.key,
    required this.report,
    required this.outcome,
  });

  final ItemReport report;
  final ReportOutcome outcome;

  @override
  ConsumerState<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends ConsumerState<_ResolveDialog>
    with WfFooterHost<_ResolveDialog> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
    // Tiene viva la lista finché la finestra è aperta: se l'ultima voce del
    // titolo sparisce (la chiude un altro admin) il riquadro si smonta, e
    // senza questo il provider autoDispose morirebbe prima della chiusura.
    ref.listenManual(adminReportsProvider, (_, _) {});
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final controller = ref.read(adminReportsProvider.notifier);
    final session = ref.read(sessionControllerProvider.notifier);
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      await controller
          .resolve(widget.report, widget.outcome,
              note: note.isEmpty ? null : note);
      if (mounted) Navigator.of(context).pop(_Result.closed);
    } on ReportsException catch (error) {
      // Il permesso è cambiato: l'utente si rilegge.
      if (error.failure == ReportsFailure.forbidden) {
        unawaited(session.refreshUser());
      }
      if (!mounted) return;
      if (error.failure == ReportsFailure.closed) {
        Navigator.of(context).pop(_Result.alreadyClosed);
        return;
      }
      if (error.failure == ReportsFailure.forbidden) {
        setState(() => _error = l.reportNoPermission);
        return;
      }
      setState(() => _error = describeError(l, error));
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _title {
    final l = AppLocalizations.of(context);
    return widget.outcome == ReportOutcome.fixed
        ? l.reportResolveFixedTitle
        : l.reportResolveCannotFixTitle;
  }

  @override
  Widget buildFooter(BuildContext context) {
    final fixed = widget.outcome == ReportOutcome.fixed;
    return WfDialogFooter(
      // Un errore resta visibile anche con il corpo scorso.
      note: _error,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
      primary: WfButton.primary(
        label: _title,
        icon: fixed ? LucideIcons.check : LucideIcons.x,
        onPressed: _busy ? null : () => unawaited(_confirm()),
      ),
    );
  }

  /// La segnalazione che si chiude: chi, di che tipo, quando, la nota.
  Widget _reportBox(AppLocalizations l) {
    final report = widget.report;
    final note = report.note;
    final date =
        DateFormat('d MMMM', l.localeName).format(report.createdAt.toLocal());
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar.lookup(
                userId: report.userId, name: report.userName, size: 32),
            const SizedBox(width: 12),
            Expanded(
              // Nome e nota sono testo dell'utente: sempre testo semplice.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(report.userName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: WfColors.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          child: Text(reportTypeLabel(l, report.type),
                              style: const TextStyle(
                                  color: WfColors.creamMuted, fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
                  Text(date,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Text(note != null && note.isNotEmpty
                      ? '“$note”'
                      : l.reportNoNote),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final report = widget.report;
    final noteLength = _note.text.runes.length;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WfDialogHeader(
          title: _title,
          subtitle: [
            report.titleName,
            reportSubjectLine(l, report, withType: false),
          ].where((part) => part.isNotEmpty).join(' · '),
          leading: DialogItemPoster(itemId: report.itemId),
        ),
        const SizedBox(height: 20),
        _reportBox(l),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          enabled: !_busy,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          inputFormatters: [capRunes(reportNoteMaxLength)],
          decoration: InputDecoration(
            hintText: l.reportResolveNoteHint,
            counterText: noteLength >= _counterFrom
                ? '$noteLength/$reportNoteMaxLength'
                : '',
          ),
        ),
      ],
    );
    // Esc e il clic fuori non chiudono la finestra durante la chiamata.
    return PopScope(canPop: !_busy, child: content);
  }
}
