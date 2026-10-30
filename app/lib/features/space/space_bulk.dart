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
  // Una stagione di una serie scelta intera è già dentro l'operazione della serie.
  final series = {
    for (final c in selected)
      if (c.kind == 'Series') c.key,
  };
  final list = [
    for (final c in selected)
      if (c.kind == 'Series' || !series.contains(c.seriesKey)) c,
  ];
  final ok = await showWfDialog<bool>(
    context,
    maxWidth: 560,
    fullPageWhenCompact: false,
    builder: (_) => _Summary(list: list),
  );
  if (ok != true || !context.mounted) return;
  final l = AppLocalizations.of(context);
  final api = ref.read(spaceApiProvider);
  final items = <SpaceBulkItem>[];
  for (final c in list) {
    final title = spaceTitleOf(l, c.title, c.seasonNumber);
    try {
      final id = await api.start(c.kind, c.key);
      items.add(SpaceBulkItem(title: title, kind: c.kind, operationId: id));
    } on SpaceException catch (e) {
      items.add(SpaceBulkItem(title: title, kind: c.kind, failure: e.failure));
    }
  }
  if (!context.mounted) return;
  ref.read(spaceSelectionProvider.notifier).clear();
  await showSpaceBulkProgress(context, items);
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
    const bold = TextStyle(fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.spaceConfirmTitle(l.spaceTitles(list.length)),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in list)
                  RowShell(
                    posterUrl: c.posterUrl,
                    lines: [
                      Text(
                        spaceTitleOf(l, c.title, c.seasonNumber),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bold,
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
                Text(l.spaceConfirmFreeNow(spaceGb(l, now)), style: bold),
                if (later > 0)
                  Text(l.spaceConfirmFreeLaterNoDate(spaceGb(l, later))),
                if (pack > 0) Text(l.spaceConfirmPack(spaceGb(l, pack))),
                for (final kind in kinds) ...[
                  const SizedBox(height: 12),
                  Text(l.spaceStepsFor(kind), style: bold),
                  Text(
                    [
                      for (final s in spacePlannedSteps(l, kind)) '• $s',
                    ].join('\n'),
                  ),
                ],
              ],
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
  }
}
