import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/downloads/download_models.dart';
import '../../core/downloads/downloads_api.dart';
import '../admin/admin_providers.dart';
import '../social/social_providers.dart';
import 'downloads_providers.dart';

final _log = Logger('downloads');

/// La panoramica dei download automatici (spec T §8), solo per un admin con
/// la funzione `downloads`; per gli altri è vuota.
class DownloadsController extends AsyncNotifier<DownloadsOverview> {
  /// Cresce a ogni lettura: vale solo la risposta dell'ultima.
  int _loads = 0;

  @override
  Future<DownloadsOverview> build() async {
    final admin = ref.watch(isAdminProvider);
    final enabled = ref.watch(
      socialAvailabilityProvider.select((f) => f.downloads),
    );
    final api = ref.watch(downloadsApiProvider);
    if (!admin || !enabled) return DownloadsOverview.empty;
    _loads++;
    return api.overview();
  }

  /// Rilegge. Un errore lascia la panoramica di prima; senza una finisce nello
  /// stato.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(isAdminProvider)) return;
    final api = ref.read(downloadsApiProvider);
    final load = ++_loads;
    try {
      final overview = await api.overview();
      if (!ref.mounted || load != _loads) return;
      state = AsyncData(overview);
    } on Object catch (error, stack) {
      _log.info(
        'download non caricati: '
        '${error is DownloadsException ? error.failure.name : error.runtimeType}',
      );
      if (!ref.mounted || load != _loads || state.hasValue) return;
      state = AsyncError(error, stack);
    }
  }
}

final downloadsControllerProvider =
    AsyncNotifierProvider.autoDispose<DownloadsController, DownloadsOverview>(
      DownloadsController.new,
    );
