import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/maintenance_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'admin_action_button.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'maintenance_controller.dart';
import 'task_labels.dart';

/// La scheda Manutenzione (spec J §9.4): librerie e attività pianificate.
class MaintenanceTab extends ConsumerStatefulWidget {
  const MaintenanceTab({super.key});

  @override
  ConsumerState<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends ConsumerState<MaintenanceTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(maintenanceControllerProvider);
    final controller = ref.read(maintenanceControllerProvider.notifier);
    final snapshot = data.value;
    if (snapshot == null) {
      final error = data.error;
      if (error == null) return const LoadingView();
      return ErrorView(
          error: error, onRetry: () => unawaited(controller.refresh()));
    }
    final now = clock.now();
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      children: [
        if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        // Con una chiave: la riga "Dati non aggiornati" in cima, che va e
        // viene, non sposta la testata (e non smonta "Scansiona tutte" mentre
        // la sua azione è in corso).
        _LibrariesHeader(
            key: const ValueKey('libraries-header'),
            scanTask: snapshot.scanTask,
            now: now,
            onScanAll: controller.scanAll),
        for (final library in snapshot.libraries)
          LibraryRow(
            key: ValueKey('library-${library.itemId}'),
            library: library,
            onScan: () => controller.scanLibrary(library.itemId),
          ),
        AdminSectionTitle(title: l.adminTasks),
        for (final group in snapshot.groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(group.category,
                style: const TextStyle(
                    color: WfColors.gold, fontWeight: FontWeight.w600)),
          ),
          for (final task in group.tasks)
            TaskRow(
              key: ValueKey('task-${task.id}'),
              task: task,
              now: now,
              onStart: () => controller.startTask(task.id),
              onStop: () => controller.stopTask(task.id),
            ),
        ],
      ],
    );
  }
}

/// "Librerie", lo stato della "Scansione della libreria" e "Scansiona
/// tutte".
class _LibrariesHeader extends StatelessWidget {
  const _LibrariesHeader({
    super.key,
    required this.scanTask,
    required this.now,
    required this.onScanAll,
  });

  final ScheduledTask? scanTask;
  final DateTime now;
  final Future<void> Function() onScanAll;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final task = scanTask;
    final last = task?.lastResult;
    final when = last?.end ?? last?.start;
    // La percentuale mentre va, "Arresto…" mentre si ferma, altrimenti
    // l'ultima scansione.
    final status = switch (task?.state) {
      TaskState.running => taskProgressLabel(task?.progress),
      TaskState.cancelling => l.adminTaskStopping,
      _ => when == null
          ? null
          : l.adminTaskLastRun(adminTimeLabel(when, now, l)),
    };
    // "Scansiona tutte" avvia quell'attività: senza (o con l'attività già in
    // corso) non c'è niente da avviare.
    final canScan = task != null && task.state == TaskState.idle;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Text(l.adminLibraries,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          // Lo stato prende tutto lo spazio che resta, a destra, e si
          // accorcia se non basta: così il pulsante sta sempre sul bordo
          // destro, come "Scansiona" delle librerie.
          Expanded(
            child: status == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(status,
                        key: const Key('scan-all-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 13)),
                  ),
          ),
          const SizedBox(width: 12),
          AdminActionButton(
            label: l.adminScanAll,
            icon: LucideIcons.refreshCw,
            onPressed: canScan ? onScanAll : null,
          ),
        ],
      ),
    );
  }
}

/// Una libreria: icona, nome, la barra durante la scansione e "Scansiona".
class LibraryRow extends StatelessWidget {
  const LibraryRow({super.key, required this.library, required this.onScan});

  final LibraryFolder library;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final icon = switch (library.kind) {
      LibraryKind.movies => LucideIcons.film,
      LibraryKind.shows => LucideIcons.tv,
      LibraryKind.other => LucideIcons.folder,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: WfColors.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(library.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (library.refreshing) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    key: Key('library-progress-${library.itemId}'),
                    value: (library.refreshProgress ?? 0) / 100,
                    minHeight: 4,
                    color: WfColors.gold,
                    backgroundColor: WfColors.surfaceHigh,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          AdminActionButton(
            label: l.adminScan,
            icon: LucideIcons.scanLine,
            onPressed: library.refreshing ? null : onScan,
          ),
        ],
      ),
    );
  }
}

/// Un'attività: nome, descrizione, stato e Avvia o Ferma. "Non riuscita"
/// apre il messaggio d'errore.
class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.now,
    required this.onStart,
    required this.onStop,
  });

  final ScheduledTask task;
  final DateTime now;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _showError = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final task = widget.task;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    final description = task.description;
    final result = task.lastResult;
    final errorMessage = result?.errorMessage;
    final failed = result?.status == TaskStatus.failed;
    final Widget status = switch (task.state) {
      TaskState.running => Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: (task.progress ?? 0) / 100,
                minHeight: 4,
                color: WfColors.gold,
                backgroundColor: WfColors.surfaceHigh,
              ),
            ),
            const SizedBox(width: 8),
            Text(taskProgressLabel(task.progress), style: muted),
          ],
        ),
      TaskState.cancelling => Text(l.adminTaskStopping, style: muted),
      TaskState.idle => Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (taskIdleLabel(l, result, widget.now) case final label
                when label.isNotEmpty)
              Text(label, style: muted),
            if (failed)
              InkWell(
                onTap: errorMessage == null
                    ? null
                    : () => setState(() => _showError = !_showError),
                child: Text(l.adminTaskFailed,
                    style: const TextStyle(
                        color: WfColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
    };
    final Widget action = switch (task.state) {
      TaskState.idle => AdminActionButton(
          label: l.adminTaskStart,
          icon: LucideIcons.play,
          onPressed: widget.onStart,
        ),
      TaskState.running => AdminActionButton(
          label: l.adminTaskStop,
          icon: LucideIcons.square,
          onPressed: widget.onStop,
        ),
      TaskState.cancelling => const SizedBox.shrink(),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (description != null)
                  Tooltip(
                    message: description,
                    child: Text(description,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ),
                const SizedBox(height: 4),
                status,
                if (_showError && errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(errorMessage,
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          action,
        ],
      ),
    );
  }
}
