import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/party_channel/party_channel_api.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../auth/session_controller.dart';
import '../library/server_events_binding.dart';

final syncPlayApiProvider =
    Provider<SyncPlayApi>((ref) => SyncPlayApi(ref.watch(jellyfinHttpProvider)));

final partyChannelApiProvider = Provider<PartyChannelApi>(
    (ref) => PartyChannelApi(ref.watch(jellyfinHttpProvider)));

/// Eventi del WebSocket per il watch party. Tiene aperto il WebSocket anche
/// se la barra superiore non è montata.
final watchPartyEventsProvider = Provider<Stream<ServerEvent>>((ref) {
  ref.watch(serverEventsBindingProvider);
  return ref.watch(serverEventsClientProvider).events;
});

/// Permessi del watch party dell'utente collegato; nessuno senza sessione.
final syncPlayAccessProvider = Provider<SyncPlayAccess>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session is SessionSignedIn
      ? session.user.syncPlayAccess
      : SyncPlayAccess.none;
});
