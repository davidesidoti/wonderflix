import 'dart:async';

import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/core/space/space_models.dart';

class FakeSpaceApi implements SpaceApi {
  var overviewValue = SpaceOverview.empty;

  /// Chiamate in ordine: `overview`, `keep k t`, `unkeep k`, ...
  final calls = <String>[];

  /// Se non vuota, ogni [overview] aspetta la prima, che toglie.
  final overviewGates = <Completer<SpaceOverview>>[];

  /// Se valorizzato, [overview] fallisce con questo.
  Object? overviewError;

  /// Se valorizzato, la prossima azione fallisce con questo, una volta sola.
  SpaceFailure? nextActionFailure;

  @override
  Future<SpaceOverview> overview() async {
    calls.add('overview');
    if (overviewError case final e?) throw e;
    if (overviewGates.isEmpty) return overviewValue;
    return overviewGates.removeAt(0).future;
  }

  /// Se valorizzato, keep/unkeep/dropPending aspettano questo prima di rispondere.
  Completer<void>? actionGate;

  Future<void> _action(String call) async {
    calls.add(call);
    if (actionGate case final gate?) await gate.future;
    if (nextActionFailure case final f?) {
      nextActionFailure = null;
      throw SpaceException(f);
    }
  }

  /// Se valorizzato, [start] aspetta questo prima di rispondere.
  Completer<void>? startGate;

  /// Risposte di [operation] in ordine (un [SpaceOperation] o un errore da
  /// lanciare); l'ultima si ripete.
  final operationResults = <Object>[];

  /// Come [operationResults], per un id; senza, vale [operationResults].
  final operationResultsById = <String, List<Object>>{};

  /// Gli `start` di queste chiavi falliscono con il valore.
  final startFailures = <String, SpaceFailure>{};

  var _starts = 0;

  /// Dà `op1`, `op2`, ... in ordine.
  @override
  Future<String> start(String kind, String key) async {
    await _action('start $kind $key');
    await startGate?.future;
    if (startFailures[key] case final f?) throw SpaceException(f);
    return 'op${++_starts}';
  }

  @override
  Future<SpaceOperation> operation(String id) async {
    calls.add('operation $id');
    final results = operationResultsById[id] ?? operationResults;
    final r = results.length > 1 ? results.removeAt(0) : results.first;
    if (r is SpaceOperation) return r;
    throw r;
  }

  @override
  Future<void> keep(String key, String title) => _action('keep $key $title');

  @override
  Future<void> unkeep(String key) => _action('unkeep $key');

  /// Se valorizzato, la prossima [importLighten] fallisce con questo.
  SpaceException? nextImportError;

  @override
  Future<void> importLighten(String key) async {
    await _action('import $key');
    if (nextImportError case final e?) {
      nextImportError = null;
      throw e;
    }
  }

  @override
  Future<void> dropPending(String hash) => _action('drop $hash');

  @override
  Future<void> recalculate() => _action('recalculate');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
