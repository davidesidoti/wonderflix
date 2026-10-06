import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';

/// L'utente collegato è amministratore di Jellyfin (spec J §7): vede la voce
/// "Amministrazione" e la pagina.
final isAdminProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session is SessionSignedIn && session.user.isAdministrator;
});
