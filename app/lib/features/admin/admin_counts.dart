import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/download_models.dart';
import '../../core/jellyfin/maintenance_models.dart';
import '../downloads/downloads_controller.dart';
import '../downloads/downloads_providers.dart';
import '../reports/admin_reports_controller.dart';
import '../social/social_providers.dart';
import 'admin_navigation.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';
import 'maintenance_controller.dart';
import 'sessions_controller.dart';

/// Quanto richiede attenzione, per scheda: chi guarda, le attività in corso,
/// i download che aspettano una decisione. `null` = non letto.
class AdminCounts {
  const AdminCounts({this.playing, this.running, this.needsYou});

  final int? playing, running, needsYou;
}

/// I numeri sui pallini delle schede, riletti ogni minuto. Servono alle
/// schede che non sono aperte: quella aperta ha il suo controller.
class AdminCountsController extends AdminTabController<AdminCounts> {
  static const every = Duration(seconds: 60);

  @override
  Duration get interval => every;

  /// Una lettura che fallisce lascia il valore di prima di quel campo, senza
  /// far fallire le altre.
  @override
  Future<AdminCounts> fetch() async {
    final api = ref.read(adminApiProvider);
    final downloads = ref.read(downloadsApiProvider);
    final withDownloads = ref.read(socialAvailabilityProvider).downloads;
    final previous = state.value;

    Future<int?> read(Future<int> Function() count, int? before) async {
      try {
        return await count();
      } on Object {
        return before;
      }
    }

    final results = await Future.wait([
      read(() async {
        final sessions = await api.sessions();
        return sessions.where((s) => s.nowPlaying != null).length;
      }, previous?.playing),
      read(() async {
        final tasks = await api.tasks();
        return tasks.where((t) => t.state != TaskState.idle).length;
      }, previous?.running),
      if (withDownloads)
        read(() async => _needsYou(await downloads.overview()),
            previous?.needsYou),
    ]);
    return AdminCounts(
      playing: results[0],
      running: results[1],
      needsYou: withDownloads ? results[2] : null,
    );
  }
}

int _needsYou(DownloadsOverview overview) =>
    overview.waiting.where((i) => i.state == DownloadState.needsYou).length;

final adminCountsProvider =
    NotifierProvider.autoDispose<AdminCountsController, AdminData<AdminCounts>>(
        AdminCountsController.new);

/// Il numero sul pallino di [tab], `null` = nessun pallino (anche 0). Per la
/// scheda aperta ([current]) conta il controller della scheda, già vivo e
/// più fresco; per le altre [adminCountsProvider]. Il controller della scheda
/// aperta riparte vuoto a ogni cambio di scheda (è autoDispose): finché non ha
/// un valore vale [adminCountsProvider], così il pallino non lampeggia.
/// WonderFlix conta sempre le segnalazioni, che si aggiornano da sole con gli
/// eventi.
int? adminTabCount(WidgetRef ref, AdminTab tab, {required AdminTab current}) {
  final open = tab == current;
  final int? count = switch (tab) {
    AdminTab.sessions =>
      (open
              ? ref.watch(sessionsControllerProvider).value?.playing.length
              : null) ??
          ref.watch(adminCountsProvider).value?.playing,
    AdminTab.maintenance =>
      (open
              ? ref
                  .watch(maintenanceControllerProvider)
                  .value
                  ?.groups
                  .expand((g) => g.tasks)
                  .where((t) => t.state != TaskState.idle)
                  .length
              : null) ??
          ref.watch(adminCountsProvider).value?.running,
    AdminTab.downloads =>
      (open
              ? _needsYouOf(ref.watch(downloadsControllerProvider).value)
              : null) ??
          ref.watch(adminCountsProvider).value?.needsYou,
    AdminTab.wonderflix => ref.watch(adminReportsProvider).value?.length,
    AdminTab.users || AdminTab.activity || AdminTab.space => null,
  };
  return count == null || count == 0 ? null : count;
}

int? _needsYouOf(DownloadsOverview? overview) =>
    overview == null ? null : _needsYou(overview);
