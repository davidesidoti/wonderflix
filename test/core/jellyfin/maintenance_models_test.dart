import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';

import '../../support/admin_json.dart';

void main() {
  test('librerie: genere, scansione in corso, voci senza id saltate', () {
    final libraries = parseLibraries([
      ...librariesJson,
      {'Name': 'senza id'},
    ]);

    expect(libraries.map((l) => l.name),
        ['Movies', 'Collezioni2', 'Anime', 'Shows']);
    expect(libraries.map((l) => l.kind), [
      LibraryKind.movies,
      LibraryKind.other,
      LibraryKind.other,
      LibraryKind.shows,
    ]);
    expect(libraries[0].itemId, 'f137a2dd21bbc1b99aa5c0f6bf02a805');
    expect(libraries[0].refreshing, isTrue);
    expect(libraries[0].refreshProgress, 42.5);
    expect(libraries[1].refreshing, isFalse);
    expect(libraries[1].refreshProgress, isNull);
    expect(() => parseLibraries({'x': 1}), throwsA(isA<ServerErrorException>()));
  });

  test('libreria in coda: vale come scansione in corso', () {
    LibraryFolder library(Object? status) => parseLibraries([
          {
            'ItemId': 'l1',
            'Name': 'Movies',
            if (status != 'missing') 'RefreshStatus': status,
          },
        ]).single;

    // Jellyfin dice "Queued" per una libreria che aspetta dietro un'altra.
    final queued = library('Queued');
    expect(queued.refreshing, isTrue);
    expect(queued.refreshProgress, isNull);
    expect(library('Active').refreshing, isTrue);
    expect(library('Idle').refreshing, isFalse);
    expect(library('missing').refreshing, isFalse);
    expect(library('').refreshing, isFalse);
    expect(library(null).refreshing, isFalse);
    expect(library(1).refreshing, isFalse, reason: 'non è una stringa');
  });

  test('attività: stato, avanzamento, ultimo risultato', () {
    final tasks = {for (final task in parseTasks(tasksJson)) task.id: task};

    expect(tasks, hasLength(8));
    final plugins = tasks['t-plugins']!;
    expect(plugins.name, 'Aggiorna i plugin');
    expect(plugins.key, 'PluginUpdates');
    expect(plugins.category, 'Applicazione');
    expect(plugins.description, 'Scarica e installa gli aggiornamenti dei plugin.');
    expect(plugins.state, TaskState.idle);
    expect(plugins.lastResult!.status, TaskStatus.completed);
    expect(plugins.lastResult!.end,
        DateTime.parse('2026-10-05T22:23:46.508378Z'));

    expect(tasks['t-autocol']!.state, TaskState.running);
    expect(tasks['t-autocol']!.progress, 37.5);
    expect(tasks['t-autocol']!.lastResult, isNull);
    expect(tasks['t-webhook']!.state, TaskState.cancelling);
    expect(tasks['t-keyframe']!.lastResult!.status, TaskStatus.cancelled);
    expect(tasks['t-trakt']!.lastResult!.status, TaskStatus.failed);
    expect(tasks['t-trakt']!.lastResult!.errorMessage, contains('401'));
    expect(tasks['t-optimize']!.lastResult!.duration!.inMinutes, 3);
    expect(tasks['t-skipme']!.lastResult, isNull);
    expect(tasks['t-scan']!.key, ScheduledTask.refreshLibraryKey);
  });

  test('attività strane: senza id saltate, valori sconosciuti', () {
    final tasks = parseTasks([
      {'Name': 'senza id'},
      {
        'Id': 'x',
        'State': 'Boh',
        'LastExecutionResult': {'Status': 'Boh'},
      },
    ]);

    final task = tasks.single;
    expect(task.name, '');
    expect(task.state, TaskState.idle);
    expect(task.lastResult!.status, TaskStatus.unknown);
    expect(task.lastResult!.duration, isNull);
  });
}
