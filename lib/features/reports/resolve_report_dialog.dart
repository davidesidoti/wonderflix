import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../core/reports/report_models.dart';
import '../../core/reports/reports_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/rune_limit.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import 'admin_reports_controller.dart';
import 'report_dialog.dart';

/// Da qui il contatore `n/500` è visibile.
const _counterFrom = 450;

/// Chiude [report] con [outcome] e una nota facoltativa (spec R §7.7).
/// Se un altro admin l'aveva già chiusa, la finestra si chiude e compare lo
/// snackbar; gli altri errori restano nella finestra.
Future<void> showResolveReportDialog(
  BuildContext context,
  WidgetRef ref,
  ItemReport report,
  ReportOutcome outcome,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = AppLocalizations.of(context);
  // La finestra può restare aperta dopo che il riquadro che l'ha aperta è
  // sparito (l'ultima voce chiusa): il controller si prende ora.
  final controller = ref.read(adminReportsProvider.notifier);
  final closed = await showWfDialog<bool>(
    context,
    semanticLabel: outcome == ReportOutcome.fixed
        ? l.reportResolveFixedTitle
        : l.reportResolveCannotFixTitle,
    builder: (_) => _ResolveDialog(
      controller: controller,
      report: report,
      outcome: outcome,
    ),
  );
  if (closed == true) {
    messenger?.showSnackBar(SnackBar(content: Text(l.reportAlreadyClosed)));
  }
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({
    required this.controller,
    required this.report,
    required this.outcome,
  });

  final AdminReportsController controller;
  final ItemReport report;
  final ReportOutcome outcome;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      await widget.controller
          .resolve(widget.report, widget.outcome,
              note: note.isEmpty ? null : note);
      if (mounted) Navigator.of(context).pop(false);
    } on ReportsException catch (error) {
      if (!mounted) return;
      if (error.failure == ReportsFailure.closed) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = describeError(l, error));
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final noteLength = _note.text.runes.length;
    final fixed = widget.outcome == ReportOutcome.fixed;
    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fixed ? l.reportResolveFixedTitle : l.reportResolveCannotFixTitle,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
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
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(_error!),
          ],
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel),
              ),
              WfButton.primary(
                label: l.reportResolveConfirm,
                icon: fixed ? LucideIcons.check : LucideIcons.x,
                onPressed: _busy ? null : () => unawaited(_confirm()),
              ),
            ],
          ),
        ],
      ),
    );
    // Esc e il clic fuori non chiudono la finestra durante la chiamata.
    return PopScope(canPop: !_busy, child: content);
  }
}
