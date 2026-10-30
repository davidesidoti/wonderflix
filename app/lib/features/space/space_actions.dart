import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/space/space_api.dart';
import '../../core/space/space_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../admin/admin_confirm_dialog.dart';
import 'space_controller.dart';
import 'space_labels.dart';
import 'space_providers.dart';
import 'space_rows.dart';

/// Conferma (passi in parole, GB subito e dopo il seed, nota del pack), poi
/// avvia l'operazione (spec U §6.1). `true` se è partita. [candidate] dà i GB
/// di un titolo; senza, vale [sizeBytes] (torrent e file: tutto subito).
/// Il Task 5 sostituisce l'avviso con il riquadro del progresso.
Future<bool> startSpaceOperation(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  required String key,
  required String title,
  SpaceCandidate? candidate,
  int? sizeBytes,
}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final c = candidate;
  final now = c?.freeNowBytes ?? sizeBytes ?? 0;
  final later = c?.freeLaterBytes ?? 0;
  final laterAt = c?.freeLaterAt;
  final pack = c?.inPackBytes ?? 0;
  final message = [
    l.spaceConfirmSteps(
      [for (final s in spacePlannedSteps(l, kind)) '• $s'].join('\n'),
    ),
    l.spaceConfirmFreeNow(spaceGb(l, now)),
    if (later > 0)
      laterAt == null
          ? l.spaceConfirmFreeLaterNoDate(spaceGb(l, later))
          : l.spaceConfirmFreeLater(spaceGb(l, later), spaceDate(l, laterAt)),
    if (pack > 0) l.spaceConfirmPack(spaceGb(l, pack)),
  ].join('\n\n');
  final ok = await showAdminConfirmDialog(
    context,
    title: l.spaceConfirmTitle(title),
    message: message,
    confirmLabel: l.spaceConfirmAction,
  );
  if (!ok || !context.mounted) return false;
  try {
    final id = await ref.read(spaceApiProvider).start(kind, key);
    messenger.showSnackBar(SnackBar(content: Text(l.spaceStarted(id))));
  } on SpaceException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(spaceFailureLabel(l, e.failure))),
    );
    return false;
  } finally {
    if (context.mounted) {
      await ref.read(spaceControllerProvider.notifier).reload();
    }
  }
  return true;
}
