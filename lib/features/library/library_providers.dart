import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/library_api.dart';
import '../auth/session_controller.dart';

/// Id dell'utente autenticato. Da usare solo dentro provider asincroni:
/// senza sessione lancia, e l'errore finisce nell'`AsyncValue`.
final currentUserIdProvider = Provider<String>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is SessionSignedIn) return session.user.id;
  throw StateError('Nessun utente autenticato');
});

final libraryApiProvider =
    Provider<LibraryApi>((ref) => LibraryApi(ref.watch(jellyfinHttpProvider)));

final imageUrlsProvider =
    Provider<ImageUrls>((ref) => ImageUrls(ref.watch(appConfigProvider).serverUrl));

/// Aumenta quando il server segnala modifiche alla libreria: i provider che
/// lo osservano ricaricano i dati.
class LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final libraryRevisionProvider =
    NotifierProvider<LibraryRevision, int>(LibraryRevision.new);
