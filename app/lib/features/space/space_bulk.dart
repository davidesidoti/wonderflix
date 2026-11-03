import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../downloads/download_rows.dart';
import 'space_bulk_dialog.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_providers.dart';
import 'space_rows.dart';

/// Le chiavi scelte in "Cancellare" (decisione 1). Una chiave che sparisce
/// dalla panoramica esce dalla selezione.
class SpaceSelection extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen(spaceControllerProvider, (_, next) {
      final o = next.value;
      if (o == null) return;
      final keys = {for (final c in o.delete) c.key};
      if (!keys.containsAll(state)) state = state.intersection(keys);
    });
    return const {};
  }

  /// Sceglie tutte [keys], o le toglie se lo sono già tutte.
  void toggle(Iterable<String> keys) => state = state.containsAll(keys)
      ? state.difference(keys.toSet())
      : {...state, ...keys};

  void clear() => state = const {};
}

final spaceSelectionProvider =
    NotifierProvider.autoDispose<SpaceSelection, Set<String>>(
      SpaceSelection.new,
    );

/// Panoramica dei [selected] e conferma (decisione 2), poi un `start` alla
/// volta; uno che fallisce resta "non avviato" e si passa al successivo. Poi
/// la finestra dei passi di tutti (decisione 3).
Future<void> startSpaceBulk(
  BuildContext context,
  WidgetRef ref,
  List<SpaceCandidate> selected,
) async {
  final list = dedupeSpaceSelection(selected);
  final ok = await showWfDialog<bool>(
    context,
    maxWidth: 560,
    fullPageWhenCompact: false,
    builder: (_) => _Summary(list: list),
  );
  if (ok != true || !context.mounted) return;
  final l = AppLocalizations.of(context);
  await _startAll(context, ref, [
    for (final c in list)
      (c.kind, c.key, spaceTitleOf(l, c.title, c.seasonNumber)),
  ], onStarted: ref.read(spaceSelectionProvider.notifier).clear);
}

/// Conferma con l'elenco dei file, poi come [startSpaceBulk]. [onStarted]:
/// avviati tutti, prima della finestra dei passi.
Future<void> startSpaceOrphans(
  BuildContext context,
  WidgetRef ref,
  List<SpaceFile> files, {
  required VoidCallback onStarted,
}) async {
  final ok = await showWfDialog<bool>(
    context,
    maxWidth: 560,
    fullPageWhenCompact: false,
    builder: (_) => _OrphanSummary(files: files),
  );
  if (ok != true || !context.mounted) return;
  await _startAll(context, ref, [
    for (final f in files) ('Orphan', f.key, f.path),
  ], onStarted: onStarted);
}

/// Un `start` alla volta; uno che fallisce resta "non avviato" e si passa al
/// successivo. Poi la finestra dei passi di tutti.
Future<void> _startAll(
  BuildContext context,
  WidgetRef ref,
  List<(String kind, String key, String title)> targets, {
  required VoidCallback onStarted,
}) async {
  final api = ref.read(spaceApiProvider);
  final items = <SpaceBulkItem>[];
  for (final (kind, key, title) in targets) {
    try {
      final id = await api.start(kind, key);
      items.add(SpaceBulkItem(title: title, kind: kind, operationId: id));
    } on SpaceException catch (e) {
      items.add(SpaceBulkItem(title: title, kind: kind, failure: e.failure));
    }
  }
  if (!context.mounted) return;
  onStarted();
  await showSpaceBulkProgress(context, items);
  // Chiusa la finestra, la panoramica si rilegge una volta, come in startSpaceOperation.
  if (context.mounted) {
    unawaited(ref.read(spaceControllerProvider.notifier).reload());
  }
}

/// Una stagione di una serie scelta intera è già dentro l'operazione della serie.
List<SpaceCandidate> dedupeSpaceSelection(List<SpaceCandidate> selected) {
  final series = {
    for (final c in selected)
      if (c.kind == 'Series') c.key,
  };
  return [
    for (final c in selected)
      if (c.kind == 'Series' || !series.contains(c.seriesKey)) c,
  ];
}

class _Summary extends StatelessWidget {
  const _Summary({required this.list});

  final List<SpaceCandidate> list;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    int sum(int Function(SpaceCandidate c) bytes) =>
        list.fold(0, (s, c) => s + bytes(c));
    final now = sum((c) => c.freeNowBytes);
    final later = sum((c) => c.freeLaterBytes);
    final pack = sum((c) => c.inPackBytes);
    final kinds = {for (final c in list) c.kind};
    return _confirmBody(context, l, l.spaceTitles(list.length), [
      for (final c in list)
        RowShell(
          posterUrl: c.posterUrl,
          lines: [
            Text(
              spaceTitleOf(l, c.title, c.seasonNumber),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _bold,
            ),
            Text(
              l.spaceTotalsDelete(
                spaceGb(l, c.freeNowBytes),
                spaceGb(l, c.freeLaterBytes),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
          actions: const [],
        ),
      const SizedBox(height: 8),
      Text(l.spaceConfirmFreeNow(spaceGb(l, now)), style: _bold),
      if (later > 0) Text(l.spaceConfirmFreeLaterNoDate(spaceGb(l, later))),
      if (pack > 0) Text(l.spaceConfirmPack(spaceGb(l, pack))),
      for (final kind in kinds) ...[
        const SizedBox(height: 12),
        Text(l.spaceStepsFor(kind), style: _bold),
        Text([for (final s in spacePlannedSteps(l, kind)) '• $s'].join('\n')),
      ],
    ]);
  }
}

class _OrphanSummary extends StatelessWidget {
  const _OrphanSummary({required this.files});

  final List<SpaceFile> files;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final total = files.fold(0, (s, f) => s + f.sizeBytes);
    return _confirmBody(context, l, l.spaceFiles(files.length), [
      for (final f in files)
        RowShell(
          posterUrl: null,
          // Il percorso intero: è quello che sparisce dal disco.
          lines: [
            Text(f.path, style: _bold),
            Text(spaceGb(l, f.sizeBytes), style: const TextStyle(fontSize: 13)),
          ],
          actions: const [],
        ),
      const SizedBox(height: 8),
      Text(l.spaceConfirmFreeNow(spaceGb(l, total)), style: _bold),
      Text(l.spaceFilesDeleteNote),
    ]);
  }
}

const _bold = TextStyle(fontWeight: FontWeight.w600);

/// "Eliminare [what]?", [body] che scorre, e i due pulsanti.
Widget _confirmBody(
  BuildContext context,
  AppLocalizations l,
  String what,
  List<Widget> body,
) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      l.spaceConfirmTitle(what),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 16),
    Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    ),
    const SizedBox(height: 24),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.adminCancel),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.spaceConfirmAction),
          ),
        ),
      ],
    ),
  ],
);
