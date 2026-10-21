import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/reports/report_models.dart';
import '../../core/reports/reports_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/rune_limit.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import 'report_labels.dart';
import 'reports_providers.dart';

/// Lunghezza massima della nota, in punti di codice (come il plugin).
const reportNoteMaxLength = 500;

/// Da qui il contatore `n/500` è visibile.
const _counterFrom = 450;

/// Un titolo che si può segnalare: il file, la stagione o la serie.
class ReportTarget {
  const ReportTarget({required this.itemId, required this.label});

  final String itemId;
  final String label;
}

/// I bersagli di una segnalazione partendo da [item]: l'episodio, la sua
/// stagione e la serie; per una stagione, lei e la serie. Film e serie hanno
/// solo se stessi. Le voci senza id si saltano.
List<ReportTarget> reportTargets(AppLocalizations l, JellyfinItem item) {
  final seriesId = item.seriesId;
  final seasonId = item.seasonId;
  final seasonNumber =
      item.kind == ItemKind.season ? item.indexNumber : item.parentIndexNumber;
  ReportTarget season() => ReportTarget(
        itemId: seasonId!,
        label: reportLevelLabel(l, ReportItemType.season, season: seasonNumber),
      );
  const series = ReportItemType.series;
  return switch (item.kind) {
    ItemKind.episode => [
        ReportTarget(itemId: item.id, label: l.reportLevelThisEpisode),
        if (seasonId != null && seasonNumber != null) season(),
        if (seriesId != null)
          ReportTarget(
              itemId: seriesId, label: reportLevelLabel(l, series)),
      ],
    ItemKind.season => [
        ReportTarget(itemId: item.id, label: l.reportLevelThisSeason),
        if (seriesId != null)
          ReportTarget(
              itemId: seriesId, label: reportLevelLabel(l, series)),
      ],
    _ => [ReportTarget(itemId: item.id, label: item.name)],
  };
}

/// "Serie · S1 E2 “Nome”" per un episodio, "Serie · Stagione 2" per una
/// stagione, il nome per gli altri.
String _contentLine(AppLocalizations l, JellyfinItem item) {
  final series = item.seriesName;
  final parts = switch (item.kind) {
    ItemKind.episode => [
        series,
        [
          reportLevelLabel(l, ReportItemType.episode,
              season: item.parentIndexNumber, episode: item.indexNumber),
          '“${item.name}”',
        ].where((part) => part.isNotEmpty).join(' '),
      ],
    ItemKind.season => [
        series,
        reportLevelLabel(l, ReportItemType.season, season: item.indexNumber),
      ],
    _ => [item.name],
  };
  return [
    for (final part in parts)
      if (part != null && part.isNotEmpty) part,
  ].join(' · ');
}

/// "Segnala un problema" su [item] (spec R §7.3). La nota e il tipo vanno
/// agli admin; a segnalazione inviata mostra lo snackbar.
Future<void> showReportDialog(BuildContext context, JellyfinItem item) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = AppLocalizations.of(context);
  final sent = await showWfDialog<bool>(
    context,
    semanticLabel: l.reportDialogTitle,
    builder: (_) => _ReportDialog(item: item),
  );
  if (sent == true) {
    messenger?.showSnackBar(SnackBar(content: Text(l.reportSent)));
  }
}

class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({required this.item});

  final JellyfinItem item;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  final _note = TextEditingController();
  List<ReportTarget>? _targets;
  int _target = 0;
  ReportType? _type;
  bool _busy = false;
  String? _error;

  /// Le segnalazioni già aperte di chi scrive sul bersaglio scelto.
  List<ItemReport> _mine = const [];

  /// Distingue le letture: una risposta di un bersaglio lasciato si scarta.
  int _mineRequest = 0;

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_targets == null) {
      _targets = reportTargets(AppLocalizations.of(context), widget.item);
      unawaited(_loadMine());
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _itemId => _targets![_target].itemId;

  Future<void> _loadMine() async {
    final request = ++_mineRequest;
    final api = ref.read(reportsApiProvider);
    List<ItemReport> mine;
    try {
      mine = await api.mine(_itemId);
    } on Object {
      // Solo un avviso in meno: la segnalazione si può inviare lo stesso.
      mine = const [];
    }
    if (!mounted || request != _mineRequest) return;
    setState(() => _mine = mine);
    _prefillNote();
  }

  ItemReport? get _duplicate {
    final type = _type;
    if (type == null) return null;
    for (final report in _mine) {
      if (report.type == type) return report;
    }
    return null;
  }

  /// Con un doppione e la nota vuota, riparte dalla nota già mandata.
  void _prefillNote() {
    final note = _duplicate?.note;
    if (note != null && note.isNotEmpty && _note.text.isEmpty) {
      _note.text = note;
    }
  }

  void _selectTarget(int index) {
    if (index == _target) return;
    setState(() => _target = index);
    unawaited(_loadMine());
  }

  void _selectType(ReportType type) {
    setState(() => _type = type);
    _prefillNote();
  }

  Future<void> _submit() async {
    final type = _type;
    if (_busy || type == null) return;
    final l = AppLocalizations.of(context);
    final api = ref.read(reportsApiProvider);
    final session = ref.read(sessionControllerProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.create(itemId: _itemId, type: type, note: _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ReportsException catch (error) {
      if (error.failure == ReportsFailure.forbidden) {
        // Il permesso è cambiato: l'utente si rilegge.
        unawaited(session.refreshUser());
      }
      if (!mounted) return;
      setState(() => _error = switch (error.failure) {
            ReportsFailure.limitReached => l.reportLimitReached,
            ReportsFailure.forbidden => l.reportNoPermission,
            _ => describeError(l, error),
          });
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final targets = _targets!;
    final noteLength = _note.text.runes.length;
    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.reportDialogTitle,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_contentLine(l, widget.item),
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 16),
          if (targets.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, target) in targets.indexed)
                  ChoiceChip(
                    label: Text(target.label),
                    selected: i == _target,
                    onSelected: _busy ? null : (_) => _selectTarget(i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in ReportType.values)
                ChoiceChip(
                  label: Text(reportTypeLabel(l, type)),
                  selected: type == _type,
                  onSelected: _busy ? null : (_) => _selectType(type),
                ),
            ],
          ),
          if (_duplicate != null) ...[
            const SizedBox(height: 12),
            Text(l.reportAlreadySent,
                style: const TextStyle(color: WfColors.creamMuted)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            enabled: !_busy,
            minLines: 3,
            maxLines: 6,
            inputFormatters: [capRunes(reportNoteMaxLength)],
            decoration: InputDecoration(
              hintText: l.reportNoteHint,
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
          // Wrap: con i testi lunghi i bottoni vanno a capo, non escono.
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(MaterialLocalizations.of(context)
                    .cancelButtonLabel),
              ),
              WfButton.primary(
                label: l.reportSend,
                icon: LucideIcons.send,
                onPressed: _busy || _type == null
                    ? null
                    : () => unawaited(_submit()),
              ),
            ],
          ),
        ],
      ),
    );
    // Esc e il clic fuori non chiudono la finestra durante l'invio.
    return PopScope(canPop: !_busy, child: content);
  }
}
