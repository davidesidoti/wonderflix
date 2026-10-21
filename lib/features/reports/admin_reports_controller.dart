import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/reports/report_models.dart';
import '../../core/reports/reports_api.dart';
import '../../core/social/social_models.dart';
import '../admin/admin_providers.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';
import 'reports_providers.dart';

final _log = Logger('reports');

/// Le azioni rapide di una segnalazione nel riquadro admin (il 24c ne
/// aggiunge altre).
enum ReportShortcut { subtitles }

/// "Cerca sottotitoli" per i sottotitoli di un film o di un episodio;
/// altrimenti nessuna (decisione 10 del piano 24b).
ReportShortcut? reportShortcut(ItemReport report) =>
    report.type == ReportType.subtitles &&
            (report.itemType == ReportItemType.movie ||
                report.itemType == ReportItemType.episode)
        ? ReportShortcut.subtitles
        : null;

/// Tutte le segnalazioni aperte, per il riquadro nel dettaglio e per la card
/// della dashboard (solo admin, solo con la funzione `reports`). Si rilegge a
/// ogni `InboxChanged` e a ogni connessione del WebSocket.
class AdminReportsController extends AsyncNotifier<List<ItemReport>> {
  /// Cresce a ogni lettura: vale solo la risposta dell'ultima.
  int _loads = 0;

  @override
  Future<List<ItemReport>> build() async {
    final admin = ref.watch(isAdminProvider);
    final enabled =
        ref.watch(socialAvailabilityProvider.select((f) => f.reports));
    final api = ref.watch(reportsApiProvider);
    if (!admin || !enabled) return const [];
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is InboxChangedEvent) unawaited(reload());
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      if (event is ServerConnected) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    _loads++;
    return api.all();
  }

  /// Rilegge l'elenco. Un errore lascia l'elenco di prima; senza un elenco
  /// finisce nello stato.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(isAdminProvider)) return;
    final api = ref.read(reportsApiProvider);
    final load = ++_loads;
    try {
      final reports = await api.all();
      if (!ref.mounted || load != _loads) return;
      state = AsyncData(reports);
    } on Object catch (error, stack) {
      _log.info('segnalazioni non caricate: '
          '${error is ReportsException ? error.failure.name : error.runtimeType}');
      if (!ref.mounted || load != _loads || state.hasValue) return;
      state = AsyncError(error, stack);
    }
  }

  /// Chiude [report] e rilegge. Con `closed` (un altro admin l'ha già chiusa)
  /// rilegge lo stesso e rilancia l'errore; gli altri errori passano a chi
  /// chiama.
  Future<void> resolve(ItemReport report, ReportOutcome outcome,
      {String? note}) async {
    final api = ref.read(reportsApiProvider);
    try {
      await api.resolve(report.id, outcome, note: note);
    } on ReportsException catch (error) {
      if (error.failure == ReportsFailure.closed) await reload();
      rethrow;
    }
    await reload();
  }
}

final adminReportsProvider =
    AsyncNotifierProvider.autoDispose<AdminReportsController, List<ItemReport>>(
        AdminReportsController.new);
