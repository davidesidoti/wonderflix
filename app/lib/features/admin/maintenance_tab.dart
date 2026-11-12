import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/maintenance_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'admin_action_button.dart';
import 'admin_kit.dart';
import 'admin_widgets.dart';
import 'maintenance_controller.dart';
import 'task_labels.dart';

/// La scheda Manutenzione (spec J §9.4): librerie e attività pianificate.
class MaintenanceTab extends ConsumerStatefulWidget {
  const MaintenanceTab({super.key, this.header});

  /// La striscia del server, nel layout stretto: scorre con l'elenco.
  final Widget? header;

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
      if (error == null) {
        return adminTabState(context, widget.header, const LoadingView());
      }
      return adminTabState(
        context,
        widget.header,
        ErrorView(error: error, onRetry: () => unawaited(controller.refresh())),
      );
    }
    final now = clock.now();
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          adminSideMargin(context), 0, adminSideMargin(context), 40),
      children: [
        if (widget.header case final header?)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: header),
        if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        AdminTabTitle(title: l.adminTabMaintenance),
        // Con una chiave: la riga "Dati non aggiornati" in cima, che va e
        // viene, non sposta le librerie (e non smonta "Scansiona tutte"
        // mentre la sua azione è in corso).
        AdminSectionTitle(
          key: const ValueKey('libraries-header'),
          title: l.adminLibraries,
          action: AdminActionButton(
            label: l.adminScanAll,
            icon: LucideIcons.refreshCw,
            // Avvia l'attività "Scansione della libreria": senza (o già in
            // corso) non c'è niente da avviare.
            onPressed: snapshot.scanTask?.state == TaskState.idle
                ? controller.scanAll
                : null,
          ),
        ),
        // Largo: tre tessere per riga; stretto: una.
        LayoutBuilder(builder: (context, constraints) {
          final width = FormFactor.of(context).compact
              ? constraints.maxWidth
              : (constraints.maxWidth - 28) / 3;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final library in snapshot.libraries)
                SizedBox(
                  width: width,
                  child: LibraryTile(
                    key: ValueKey('library-${library.itemId}'),
                    library: library,
                    onScan: () => controller.scanLibrary(library.itemId),
                  ),
                ),
            ],
          );
        }),
        AdminSectionTitle(title: l.adminTasks),
        for (final group in snapshot.groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(group.category,
                style: const TextStyle(
                    color: WfColors.creamMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          AdminList(children: [
            for (final task in group.tasks)
              TaskRow(
                key: ValueKey('task-${task.id}'),
                task: task,
                now: now,
                onStart: () => controller.startTask(task.id),
                onStop: () => controller.stopTask(task.id),
              ),
          ]),
        ],
      ],
    );
  }
}

/// Una libreria: nome, tipo e "Scansiona"; durante la scansione il bordo
/// oro, la percentuale e la barra.
class LibraryTile extends StatelessWidget {
  const LibraryTile({super.key, required this.library, required this.onScan});

  final LibraryFolder library;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kind = switch (library.kind) {
      LibraryKind.movies => l.navMovies,
      LibraryKind.shows => l.navSeries,
      LibraryKind.other => null,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: library.refreshing
                ? WfColors.gold.withValues(alpha: 0.5)
                : WfColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(library.name, style: WfText.display(20)),
          const SizedBox(height: 8),
          Row(
            children: [
              // Il testo cede spazio al pulsante (col dito è più largo).
              Expanded(
                child: library.refreshing
                    ? Row(children: [
                        Flexible(
                          child: Text(l.adminLibraryScanning,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: WfColors.gold, fontSize: 13)),
                        ),
                        const SizedBox(width: 4),
                        Text(taskProgressLabel(library.refreshProgress),
                            style: const TextStyle(
                                color: WfColors.gold, fontSize: 13)),
                      ])
                    : kind == null
                        ? const SizedBox.shrink()
                        : Text(kind,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: WfColors.creamMuted, fontSize: 13)),
              ),
              AdminActionButton(
                label: l.adminScan,
                icon: LucideIcons.scanLine,
                onPressed: library.refreshing ? null : onScan,
              ),
            ],
          ),
          if (library.refreshing) ...[
            const SizedBox(height: 8),
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
    // Spia (spec "Manutenzione"): oro in corso, verde completata, rossa
    // non riuscita, interrotta o annullata, spenta mai eseguita.
    final lamp = switch (task.state) {
      TaskState.running || TaskState.cancelling => LampState.attention,
      TaskState.idle => switch (result?.status) {
          TaskStatus.completed => LampState.ok,
          TaskStatus.failed ||
          TaskStatus.aborted ||
          TaskStatus.cancelled =>
            LampState.broken,
          _ => LampState.off,
        },
    };
    final idleLabel = taskIdleLabel(l, result, widget.now);
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
            if (idleLabel.isNotEmpty)
              Text(idleLabel,
                  style: lamp == LampState.broken
                      ? muted.copyWith(color: WfColors.error)
                      : muted),
            if (failed)
              InkWell(
                onTap: errorMessage == null
                    ? null
                    : () => setState(() => _showError = !_showError),
                child: ConstrainedBox(
                  // Col dito si tocca su almeno 44 di altezza.
                  constraints: BoxConstraints(
                      minHeight:
                          FormFactor.of(context).compact ? minTouchTarget : 0),
                  child: Align(
                    widthFactor: 1,
                    child: Text(l.adminTaskFailed,
                        style: const TextStyle(
                            color: WfColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          WfLamp(
            key: ValueKey('task-lamp-${task.id}'),
            state: lamp,
            label: task.state == TaskState.idle
                ? idleLabel
                : taskProgressLabel(task.progress),
          ),
          const SizedBox(width: 14),
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
