import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/syncplay/syncplay_api.dart';
import '../library/server_events_binding.dart';

final syncPlayApiProvider =
    Provider<SyncPlayApi>((ref) => SyncPlayApi(ref.watch(jellyfinHttpProvider)));

/// Eventi del WebSocket per il watch party. Tiene aperto il WebSocket anche
/// se la barra superiore non è montata.
final watchPartyEventsProvider = Provider<Stream<ServerEvent>>((ref) {
  ref.watch(serverEventsBindingProvider);
  return ref.watch(serverEventsClientProvider).events;
});
