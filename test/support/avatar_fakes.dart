import 'package:wonderflix/core/social/avatars_api.dart';

/// `AvatarsApi` finto: risponde con gli utenti di [users] che corrispondono
/// agli id o ai nomi (senza maiuscole), oppure lancia [error]. Con [hold]
/// la risposta aspetta quel future (una chiamata in viaggio).
class FakeAvatarsApi implements AvatarsApi {
  List<UserAvatarInfo> users = const [];
  Object? error;
  Future<void>? hold;
  final calls = <({List<String> ids, List<String> names})>[];

  @override
  Future<List<UserAvatarInfo>> avatars({
    Iterable<String> ids = const [],
    Iterable<String> names = const [],
  }) async {
    calls.add((ids: ids.toList(), names: names.toList()));
    final wait = hold;
    if (wait != null) await wait;
    final failure = error;
    if (failure != null) throw failure;
    final wantedIds = ids.toSet();
    final wantedNames = {for (final name in names) name.toLowerCase()};
    return [
      for (final user in users)
        if (wantedIds.contains(user.userId) ||
            wantedNames.contains(user.name.toLowerCase()))
          user,
    ];
  }
}
