import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_operation_controller.dart';

/// Il riquadro del progresso (decisione 6 del piano 30b): i passi
/// dell'operazione [id], aggiornati ogni secondo. Chiuderlo non la ferma.
Future<void> showSpaceOperation(BuildContext context, String id) =>
    showWfDialog<void>(
      context,
      maxWidth: 520,
      builder: (_) => _OperationBody(id: id),
    );

class _OperationBody extends ConsumerWidget {
  const _OperationBody({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Alla fine dell'operazione la panoramica si rilegge.
    ref.listen(spaceOperationProvider(id), (prev, next) {
      if (prev?.value?.running == true && next.value?.running == false) {
        unawaited(ref.read(spaceControllerProvider.notifier).reload());
      }
    });
    final op = ref.watch(spaceOperationProvider(id));
    final value = op.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value != null) ...[
          Text(
            value.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SpaceOperationSteps(operation: value),
          if (!value.running) ..._summary(l, value),
        ] else if (op.hasError)
          Text(
            (op.error is SpaceException &&
                    (op.error as SpaceException).failure ==
                        SpaceFailure.notFound)
                ? l.spaceOpNotFound
                : l.spaceFailureServer,
          )
        else
          const Center(child: CircularProgressIndicator()),
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

  List<Widget> _summary(AppLocalizations l, SpaceOperation o) {
    final freed = o.freedBytes;
    return [
      const SizedBox(height: 12),
      Text(
        l.spaceOpFreed(spaceGb(l, freed)),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      if (o.pendingBytes > 0)
        Text(l.spaceOpPendingSeed(spaceGb(l, o.pendingBytes))),
    ];
  }
}

/// I passi di un'operazione, uno per riga.
class SpaceOperationSteps extends StatelessWidget {
  const SpaceOperationSteps({super.key, required this.operation});

  final SpaceOperation operation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final step in operation.steps) _StepRow(step: step)],
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final SpaceStep step;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, color) = switch (step.state) {
      'Running' => (LucideIcons.loader, WfColors.cream),
      'Done' => (LucideIcons.check, WfColors.cream),
      'Skipped' => (LucideIcons.minus, WfColors.creamMuted),
      'Failed' => (LucideIcons.x, Theme.of(context).colorScheme.error),
      'NotDone' => (LucideIcons.circleSlash, WfColors.creamMuted),
      _ => (LucideIcons.circle, WfColors.creamMuted),
    };
    final text = step.state == 'NotDone'
        ? l.spaceStepWithDetail(
            spaceStepLabel(l, SpaceStep(name: step.name, state: step.state)),
            l.spaceStepNotDone,
          )
        : spaceStepLabel(l, step);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
