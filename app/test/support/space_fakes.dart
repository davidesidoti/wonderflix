import 'package:wonderflix/core/space/space_api.dart';
import 'package:wonderflix/core/space/space_models.dart';

class FakeSpaceApi implements SpaceApi {
  var overviewValue = SpaceOverview.empty;

  /// Chiamate in ordine: `overview`, `keep k t`, `unkeep k`, ...
  final calls = <String>[];

  @override
  Future<SpaceOverview> overview() async {
    calls.add('overview');
    return overviewValue;
  }

  @override
  Future<void> keep(String key, String title) async =>
      calls.add('keep $key $title');

  @override
  Future<void> unkeep(String key) async => calls.add('unkeep $key');

  @override
  Future<void> dropPending(String hash) async => calls.add('drop $hash');

  @override
  Future<void> recalculate() async => calls.add('recalculate');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
