import '../../core/jellyfin/maintenance_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'admin_time.dart';

/// Lo stato di un'attività ferma (spec J §9.4): "Ultima: 2 h fa · Completata
/// in 3 min", "Ultima: ieri · Annullata", "Mai eseguita". "Non riuscita"
/// non c'è: è un pulsante a parte, che apre il messaggio d'errore.
String taskIdleLabel(AppLocalizations l, TaskResult? result, DateTime now) {
  if (result == null) return l.adminTaskNeverRun;
  final parts = <String>[];
  final when = result.end ?? result.start;
  if (when != null) parts.add(l.adminTaskLastRun(adminTimeLabel(when, now, l)));
  switch (result.status) {
    case TaskStatus.completed:
      final duration = result.duration;
      if (duration != null) {
        parts.add(l.adminTaskCompletedIn(adminDurationLabel(l, duration)));
      }
    case TaskStatus.cancelled:
      parts.add(l.adminTaskCancelled);
    case TaskStatus.aborted:
      parts.add(l.adminTaskAborted);
    case TaskStatus.failed || TaskStatus.unknown:
      break;
  }
  return parts.join(' · ');
}

/// "38%": l'avanzamento di un'attività in corso.
String taskProgressLabel(double? progress) => '${(progress ?? 0).round()}%';
