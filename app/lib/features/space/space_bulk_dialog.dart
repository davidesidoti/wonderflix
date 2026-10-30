import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_operation_controller.dart';
import 'space_operation_dialog.dart';
import 'space_rows.dart';

/// Un titolo dell'eliminazione in blocco: avviato ([operationId]) o no
/// ([failure]).
class SpaceBulkItem {
  const SpaceBulkItem({
    required this.title,
    required this.kind,
    this.operationId,
    this.failure,
  });

  final String title;
  final String kind;
  final String? operationId;
  final SpaceFailure? failure;
}

/// I passi di tutti i titoli, uno sotto l'altro (decisione 3). Chiuderla non
/// ferma niente; la panoramica si rilegge una volta, quando tutte le
/// operazioni avviate sono finite.
Future<void> showSpaceBulkProgress(
  BuildContext context,
  List<SpaceBulkItem> items,
) => showWfDialog<void>(
  context,
  maxWidth: 560,
  builder: (_) => _BulkBody(items: items),
);

class _BulkBody extends ConsumerStatefulWidget {
  const _BulkBody({required this.items});

  final List<SpaceBulkItem> items;

  @override
  ConsumerState<_BulkBody> createState() => _BulkBodyState();
}

class _BulkBodyState extends ConsumerState<_BulkBody> {
  var _reloaded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ops = {
      for (final id in [for (final i in widget.items) ?i.operationId])
        id: ref.watch(spaceOperationProvider(id)),
    };
    // Finita: con lo stato finale, o sparita (`notFound`).
    final finished =
        ops.isNotEmpty &&
        ops.values.every((o) => o.hasError || o.value?.running == false);
    if (finished && !_reloaded) {
      _reloaded = true;
      unawaited(ref.read(spaceControllerProvider.notifier).reload());
    }
    final done = [for (final o in ops.values) ?o.value];
    final freed = done.fold(0, (s, o) => s + o.freedBytes);
    final pending = done.fold(0, (s, o) => s + o.pendingBytes);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.spaceTitles(widget.items.length),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in widget.items)
                  _item(l, i, ops[i.operationId]),
                if (finished) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.spaceOpFreed(spaceGb(l, freed)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (pending > 0)
                    Text(l.spaceOpPendingSeed(spaceGb(l, pending))),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.friendsClose),
          ),
        ),
      ],
    );
  }

  Widget _item(
    AppLocalizations l,
    SpaceBulkItem item,
    AsyncValue<SpaceOperation>? op,
  ) {
    final value = op?.value;
    final failure = item.failure;
    final state = failure != null
        ? l.spaceNotStarted(spaceFailureLabel(l, failure))
        : value != null
        ? spaceOperationState(l, value.state)
        : op?.hasError == true
        ? l.spaceOpNotFound
        : l.spaceOpQueued;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            state,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 13),
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: SpaceOperationSteps(operation: value),
            ),
        ],
      ),
    );
  }
}
