import 'json_fields.dart';

/// Il genere di una libreria, per l'icona (`CollectionType`).
enum LibraryKind { movies, shows, other }

/// Una libreria del server (`VirtualFolderInfo`, spec J §8.2).
class LibraryFolder {
  const LibraryFolder({
    required this.itemId,
    required this.name,
    this.kind = LibraryKind.other,
    this.refreshing = false,
    this.refreshProgress,
  });

  /// `null` senza `ItemId`: non si potrebbe scansionare.
  static LibraryFolder? fromJson(Map<String, dynamic> json) {
    final itemId = jsonString(json, 'ItemId');
    if (itemId == null) return null;
    return LibraryFolder(
      itemId: itemId,
      name: jsonString(json, 'Name') ?? '',
      kind: switch (json['CollectionType']) {
        'movies' => LibraryKind.movies,
        'tvshows' => LibraryKind.shows,
        _ => LibraryKind.other,
      },
      refreshing: switch (jsonString(json, 'RefreshStatus')) {
        null || 'Idle' => false,
        _ => true,
      },
      refreshProgress: jsonDouble(json, 'RefreshProgress'),
    );
  }

  final String itemId;
  final String name;
  final LibraryKind kind;

  /// Una scansione è in corso o in coda: `RefreshStatus` è una stringa che
  /// non è "Idle" (Jellyfin dice "Active", e "Queued" per una libreria che
  /// aspetta dietro un'altra).
  final bool refreshing;

  /// Da 0 a 100, se Jellyfin lo dice.
  final double? refreshProgress;
}

List<LibraryFolder> parseLibraries(Object? data) =>
    jsonList(data, LibraryFolder.fromJson);

/// Stato di un'attività pianificata; uno sconosciuto vale come ferma.
enum TaskState { idle, running, cancelling }

/// Com'è finita l'ultima esecuzione (`TaskCompletionStatus`).
enum TaskStatus { completed, failed, cancelled, aborted, unknown }

/// L'ultima esecuzione di un'attività (`LastExecutionResult`).
class TaskResult {
  const TaskResult({
    this.start,
    this.end,
    this.status = TaskStatus.unknown,
    this.errorMessage,
  });

  factory TaskResult.fromJson(Map<String, dynamic> json) => TaskResult(
        start: jsonDate(json, 'StartTimeUtc'),
        end: jsonDate(json, 'EndTimeUtc'),
        status: switch (json['Status']) {
          'Completed' => TaskStatus.completed,
          'Failed' => TaskStatus.failed,
          'Cancelled' => TaskStatus.cancelled,
          'Aborted' => TaskStatus.aborted,
          _ => TaskStatus.unknown,
        },
        errorMessage: jsonString(json, 'ErrorMessage'),
      );

  final DateTime? start;
  final DateTime? end;
  final TaskStatus status;
  final String? errorMessage;

  /// Quanto è durata, se si sanno inizio e fine.
  Duration? get duration {
    final start = this.start;
    final end = this.end;
    return start == null || end == null ? null : end.difference(start);
  }
}

/// Un'attività pianificata (`TaskInfo`, spec J §8.2).
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.name,
    this.key,
    this.description,
    this.category,
    this.state = TaskState.idle,
    this.progress,
    this.lastResult,
  });

  /// La "Scansione della libreria" di Jellyfin: il suo stato sta accanto a
  /// "Scansiona tutte" (spec J §9.4).
  static const refreshLibraryKey = 'RefreshLibrary';

  /// `null` senza `Id`: non si potrebbe avviare.
  static ScheduledTask? fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'Id');
    if (id == null) return null;
    final last = jsonMap(json['LastExecutionResult']);
    return ScheduledTask(
      id: id,
      name: jsonString(json, 'Name') ?? '',
      key: jsonString(json, 'Key'),
      description: jsonString(json, 'Description'),
      category: jsonString(json, 'Category'),
      state: switch (json['State']) {
        'Running' => TaskState.running,
        'Cancelling' => TaskState.cancelling,
        _ => TaskState.idle,
      },
      progress: jsonDouble(json, 'CurrentProgressPercentage'),
      lastResult: last == null ? null : TaskResult.fromJson(last),
    );
  }

  final String id;
  final String name;
  final String? key;
  final String? description;
  final String? category;
  final TaskState state;

  /// Da 0 a 100, mentre è in corso.
  final double? progress;
  final TaskResult? lastResult;
}

List<ScheduledTask> parseTasks(Object? data) =>
    jsonList(data, ScheduledTask.fromJson);
