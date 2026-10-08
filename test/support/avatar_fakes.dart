import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/ui/wf_image.dart';

/// Sostituisce il disegno delle immagini e ne registra gli indirizzi.
Override captureImageUrls(List<String> urls) =>
    imageBuilderProvider.overrideWithValue((image, fit) {
      urls.add(image.url);
      return const SizedBox.expand();
    });

/// Una cache degli avatar che conosce [users] (come con un profilo aperto e
/// la funzione `avatars`). Come il provider vero si chiude con lo scope: una
/// richiesta partita alla fine del test lascerebbe il suo timer in sospeso.
Override avatarsFor(List<UserAvatarInfo> users) =>
    avatarDirectoryProvider.overrideWith((ref) {
      final directory = AvatarDirectory(FakeAvatarsApi()..users = users);
      ref.onDispose(directory.dispose);
      return directory;
    });

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
