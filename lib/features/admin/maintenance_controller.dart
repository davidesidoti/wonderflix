import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/maintenance_models.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Le attività di una categoria.
class TaskGroup {
  const TaskGroup({required this.category, required this.tasks});

  final String category;
  final List<ScheduledTask> tasks;
}

/// Il contenuto della scheda Manutenzione (spec J §9.4).
class MaintenanceSnapshot {
  const MaintenanceSnapshot({
    this.libraries = const [],
    this.groups = const [],
    this.scanTask,
  });

  /// Attività per categoria e poi per nome, senza badare alle maiuscole,
  /// come la Dashboard web (decisione 2 del piano 16b).
  factory MaintenanceSnapshot.from(
      List<LibraryFolder> libraries, List<ScheduledTask> tasks) {
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final sorted = [...tasks]..sort((a, b) {
        final byCategory = byText(a.category ?? '', b.category ?? '');
        return byCategory != 0 ? byCategory : byText(a.name, b.name);
      });
    final groups = <TaskGroup>[];
    for (final task in sorted) {
      final category = task.category ?? '';
      if (groups.isNotEmpty && groups.last.category == category) {
        groups.last.tasks.add(task);
      } else {
        groups.add(TaskGroup(category: category, tasks: [task]));
      }
    }
    ScheduledTask? scanTask;
    for (final task in tasks) {
      if (task.key == ScheduledTask.refreshLibraryKey) scanTask = task;
    }
    return MaintenanceSnapshot(
        libraries: libraries, groups: groups, scanTask: scanTask);
  }

  final List<LibraryFolder> libraries;
  final List<TaskGroup> groups;

  /// "Scansione della libreria": il suo stato sta accanto a "Scansiona
  /// tutte".
  final ScheduledTask? scanTask;

  /// Una scansione o un'attività è in corso (o in arresto): la scheda si
  /// rilegge più spesso.
  bool get busy =>
      libraries.any((library) => library.refreshing) ||
      groups.any((group) =>
          group.tasks.any((task) => task.state != TaskState.idle));
}

/// Librerie e attività, rilette ogni 15 s, o ogni 2 s quando qualcosa è in
/// corso (spec J §9.4).
class MaintenanceController extends AdminTabController<MaintenanceSnapshot> {
  static const idleEvery = Duration(seconds: 15);
  static const busyEvery = Duration(seconds: 2);

  @override
  Duration get interval => idleEvery;

  @override
  Future<MaintenanceSnapshot> fetch() async {
    final api = ref.read(adminApiProvider);
    final results = await Future.wait<Object>(
      [api.libraries(), api.tasks()],
      eagerError: true,
    );
    final snapshot = MaintenanceSnapshot.from(
      results[0] as List<LibraryFolder>,
      results[1] as List<ScheduledTask>,
    );
    // Vale dal prossimo turno: questa lettura è ancora in corso.
    setInterval(snapshot.busy ? busyEvery : idleEvery);
    return snapshot;
  }

  /// "Scansiona tutte": come la Dashboard web 10.11, avvia l'attività
  /// "Scansione della libreria" (la sua chiave è `RefreshLibrary`), così se ne
  /// vede l'avanzamento. `POST /Library/Refresh` non risponde finché la
  /// scansione non è finita. Senza quell'attività (il pulsante è spento) è un
  /// errore chiaro, non una scansione che non parte.
  Future<void> scanAll() async {
    final scanTask = state.value?.scanTask;
    if (scanTask == null) {
      throw StateError('manca l\'attività "${ScheduledTask.refreshLibraryKey}"');
    }
    await startTask(scanTask.id);
  }

  Future<void> scanLibrary(String itemId) =>
      act(() => ref.read(adminApiProvider).scanLibrary(itemId));

  Future<void> startTask(String id) =>
      act(() => ref.read(adminApiProvider).startTask(id));

  Future<void> stopTask(String id) =>
      act(() => ref.read(adminApiProvider).stopTask(id));
}

final maintenanceControllerProvider = NotifierProvider.autoDispose<
    MaintenanceController,
    AdminData<MaintenanceSnapshot>>(MaintenanceController.new);
