import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/reports/report_models.dart';
import '../../core/reports/reports_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/dialog_item_poster.dart';
import '../../ui/form_factor.dart';
import '../../ui/rune_limit.dart';
import '../../ui/tv_text_field_frame.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_choice_tile.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
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

/// "Segnala un problema" su [item] (spec R §7.3). La nota e il tipo vanno
/// agli admin; a segnalazione inviata mostra lo snackbar.
Future<void> showReportDialog(BuildContext context, JellyfinItem item) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = AppLocalizations.of(context);
  final host = GlobalKey();
  final sent = await showWfDialog<bool>(
    context,
    semanticLabel: l.reportDialogTitle,
    compactTitle: l.reportDialogTitle,
    // In TV la finestra resta una finestra: una pagina intera non serve.
    fullPageWhenCompact: !FormFactor.of(context).tv,
    builder: (_) => _ReportDialog(key: host, item: item),
    footer: (_) => WfHostFooter(host: host),
  );
  if (sent == true) {
    messenger?.showSnackBar(SnackBar(content: Text(l.reportSent)));
  }
}

class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({super.key, required this.item});

  final JellyfinItem item;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog>
    with WfFooterHost<_ReportDialog> {
  final _note = TextEditingController();
  final _noteFocus = FocusNode(debugLabel: 'report-note');
  List<ReportTarget>? _targets;
  int _target = 0;
  ReportType? _type;
  bool _busy = false;
  String? _error;

  /// Le segnalazioni già aperte di chi scrive sul bersaglio scelto.
  List<ItemReport> _mine = const [];

  /// Distingue le letture: una risposta di un bersaglio lasciato si scarta.
  int _mineRequest = 0;

  /// La nota precompilata dal doppione, se l'utente non l'ha modificata.
  String? _prefilled;

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
    _noteFocus.dispose();
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
      _prefilled = note;
    }
  }

  void _selectTarget(int index) {
    if (index == _target) return;
    setState(() {
      _target = index;
      // Né l'avviso né la nota precompilata valgono per il nuovo bersaglio.
      _mine = const [];
      if (_note.text == _prefilled) _note.clear();
      _prefilled = null;
    });
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

  /// Una modifica tua: la nota scritta o cambiata, non quella precompilata.
  int get _changes {
    if (_busy) return 0;
    final note = _note.text.trim();
    return note.isNotEmpty && note != _prefilled?.trim() ? 1 : 0;
  }

  @override
  Widget buildFooter(BuildContext context) {
    final l = AppLocalizations.of(context);
    return WfDialogFooter(
      note: _type == null ? l.reportPickType : null,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
      primary: WfButton.primary(
        label: _duplicate != null ? l.reportUpdate : l.reportSend,
        icon: LucideIcons.send,
        onPressed: _busy || _type == null ? null : () => unawaited(_submit()),
      ),
    );
  }

  Widget _question(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _typeTiles(AppLocalizations l, bool oneColumn) {
    Widget tile(ReportType type) => WfChoiceTile(
          title: reportTypeLabel(l, type),
          description: reportTypeExample(l, type),
          icon: reportTypeIcon(type),
          selected: type == _type,
          onTap: _busy ? null : () => _selectType(type),
        );
    const types = ReportType.values;
    if (oneColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final type in types) ...[
            tile(type),
            if (type != types.last) const SizedBox(height: 8),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < types.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(types[i])),
                const SizedBox(width: 8),
                Expanded(
                    child: i + 1 < types.length
                        ? tile(types[i + 1])
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _duplicateBox(AppLocalizations l, ItemReport report) {
    final date = DateFormat('d MMMM', l.localeName).format(
      report.createdAt.toLocal(),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WfColors.gold.withValues(alpha: 0.08),
        border: Border.all(color: WfColors.gold.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.info, size: 16, color: WfColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.reportAlreadySent(date),
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final targets = _targets!;
    final noteLength = _note.text.runes.length;
    final duplicate = _duplicate;
    final form = FormFactor.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WfDialogHeader(
          title: l.reportDialogTitle,
          subtitle: itemContextLine(l, widget.item),
          leading: DialogItemPoster(itemId: widget.item.id),
        ),
        const SizedBox(height: 20),
        if (targets.length > 1) ...[
          _question(l.reportAskTarget),
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
        _question(l.reportAskType),
        _typeTiles(l, form.compact && !form.tv),
        if (duplicate != null) ...[
          const SizedBox(height: 12),
          _duplicateBox(l, duplicate),
        ],
        const SizedBox(height: 16),
        TvTextFieldFrame(
          focusNode: _noteFocus,
          child: TextField(
            controller: _note,
            focusNode: _noteFocus,
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
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(_error!),
        ],
      ],
    );
    // Esc e il clic fuori non chiudono la finestra durante l'invio.
    return WfDiscardGuard(
      changes: _changes,
      child: PopScope(canPop: !_busy, child: content),
    );
  }
}
