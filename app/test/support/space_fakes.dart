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

  Future<void> _action(String call) async {
    calls.add(call);
    if (nextActionFailure case final f?) {
      nextActionFailure = null;
      throw SpaceException(f);
    }
  }

  @override
  Future<String> start(String kind, String key) async {
    await _action('start $kind $key');
    return 'op1';
  }

  @override
  Future<void> keep(String key, String title) => _action('keep $key $title');

  @override
  Future<void> unkeep(String key) => _action('unkeep $key');

  @override
  Future<void> dropPending(String hash) => _action('drop $hash');

  @override
  Future<void> recalculate() => _action('recalculate');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
