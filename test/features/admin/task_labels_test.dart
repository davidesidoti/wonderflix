import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/features/admin/task_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('stato di un\'attività ferma', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final now = DateTime(2026, 10, 6, 10);
    TaskResult result(TaskStatus status) => TaskResult(
          start: DateTime(2026, 10, 6, 8),
          end: DateTime(2026, 10, 6, 8, 3),
          status: status,
        );

    expect(taskIdleLabel(it, null, now), 'Mai eseguita');
    expect(taskIdleLabel(it, result(TaskStatus.completed), now),
        'Ultima: 1 h fa · Completata in 3 min');
    expect(taskIdleLabel(it, result(TaskStatus.cancelled), now),
        'Ultima: 1 h fa · Annullata');
    expect(taskIdleLabel(it, result(TaskStatus.aborted), now),
        'Ultima: 1 h fa · Interrotta');
    expect(taskIdleLabel(it, result(TaskStatus.failed), now), 'Ultima: 1 h fa',
        reason: '"Non riuscita" è un pulsante a parte');
    expect(
        taskIdleLabel(it, const TaskResult(status: TaskStatus.unknown), now), '');
  });

  test('avanzamento', () {
    expect(taskProgressLabel(37.5), '38%');
    expect(taskProgressLabel(null), '0%');
  });
}
