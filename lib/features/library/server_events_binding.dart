import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/server_events.dart';
import '../auth/session_controller.dart';
import 'library_providers.dart';
import 'user_data.dart';

final serverEventsClientProvider = Provider<ServerEventsClient>((ref) {
  final client = ServerEventsClient(
    serverUrl: ref.watch(appConfigProvider).serverUrl,
    authorizationHeader: () => ref.read(jellyfinHttpProvider).authorizationHeader,
  );
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

const _libraryDebounce = Duration(seconds: 5);
const _userDataDebounce = Duration(seconds: 2);

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Tiene aperto il WebSocket finché l'utente è autenticato e ne applica gli
/// eventi allo stato. La barra superiore (`AppShell`) lo osserva.
final serverEventsBindingProvider = Provider<void>((ref) {
  final userId = ref.watch(sessionControllerProvider
      .select((s) => s is SessionSignedIn ? s.user.id : null));
  if (userId == null) return;

  final client = ref.watch(serverEventsClientProvider);
  Timer? libraryTimer;
  Timer? userDataTimer;
  final subscription = client.events.listen((event) {
    switch (event) {
      case UserDataChanged(userId: final changedUser, :final changes)
          when changedUser.isEmpty ||
              _normalizeId(changedUser) == _normalizeId(userId):
        ref.read(userDataOverridesProvider.notifier).applyAll(changes);
        // Le righe "Continua a guardare" e simili si ricaricano con calma.
        userDataTimer?.cancel();
        userDataTimer = Timer(_userDataDebounce, () {
          if (ref.mounted) ref.read(userDataRevisionProvider.notifier).bump();
        });
      case LibraryChanged():
        // Le scansioni della libreria mandano raffiche di eventi.
        libraryTimer?.cancel();
        libraryTimer = Timer(_libraryDebounce, () {
          if (ref.mounted) ref.read(libraryRevisionProvider.notifier).bump();
        });
      case ServerConnected(isReconnect: true):
        // Durante la disconnessione potremmo aver perso degli eventi.
        ref.read(userDataOverridesProvider.notifier).clear();
        ref.read(libraryRevisionProvider.notifier).bump();
      default:
        break;
    }
  });
  client.start();
  ref.onDispose(() {
    libraryTimer?.cancel();
    userDataTimer?.cancel();
    unawaited(subscription.cancel());
    unawaited(client.stop());
  });
});
