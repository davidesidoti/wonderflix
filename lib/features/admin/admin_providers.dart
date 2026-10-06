import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/admin_api.dart';
import '../auth/session_controller.dart';

final adminApiProvider =
    Provider<AdminApi>((ref) => AdminApi(ref.watch(jellyfinHttpProvider)));

/// L'utente collegato è amministratore di Jellyfin (spec J §7): vede la voce
/// "Amministrazione" e la pagina.
final isAdminProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session is SessionSignedIn && session.user.isAdministrator;
});

/// La finestra è in vista (spec J §10): falso quando è nascosta, per
/// esempio ridotta a icona. Le riletture della pagina si fermano finché è
/// falso. Vive finché la pagina la usa.
class AdminForeground extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onHide: () => state = false,
      onShow: () => state = true,
    );
    ref.onDispose(listener.dispose);
    // Se la finestra è già nascosta quando la pagina si apre, il listener non
    // ha visto nessun cambio: si parte dallo stato di adesso.
    return switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.hidden || AppLifecycleState.paused => false,
      _ => true,
    };
  }
}

final adminForegroundProvider =
    NotifierProvider.autoDispose<AdminForeground, bool>(AdminForeground.new);

/// Cresce quando Jellyfin torna dopo un riavvio: la striscia e le schede
/// rileggono subito (spec J §9.2).
class AdminEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final adminEpochProvider = NotifierProvider<AdminEpoch, int>(AdminEpoch.new);
