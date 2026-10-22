import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/media_info_models.dart';
import '../../core/reports/reports_api.dart';
import '../../core/subtitles/subtitles_api.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';

/// Le segnalazioni del plugin (spec R §7.1).
final reportsApiProvider =
    Provider<ReportsApi>((ref) => ReportsApi(ref.watch(jellyfinHttpProvider)));

/// Ricerca, scarico, caricamento ed eliminazione dei sottotitoli.
final subtitlesApiProvider = Provider<SubtitlesApi>(
    (ref) => SubtitlesApi(ref.watch(jellyfinHttpProvider)));

/// Le versioni e le tracce di un titolo (spec R §7.4).
final itemMediaInfoProvider = FutureProvider.autoDispose
    .family<ItemMediaInfo, String>((ref, itemId) {
  final api = ref.watch(libraryApiProvider);
  final userId = ref.watch(currentUserIdProvider);
  return api.mediaInfo(userId, itemId);
});

/// Può cercare, caricare e scaricare sottotitoli: il plugin ha le
/// segnalazioni e l'utente è admin o ha il permesso (spec R §7.2). Il server
/// controlla comunque ogni chiamata.
final canManageSubtitlesProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionControllerProvider);
  final reports = ref.watch(socialAvailabilityProvider.select((f) => f.reports));
  if (session is! SessionSignedIn || !reports) return false;
  final user = session.user;
  return user.isAdministrator || user.enableSubtitleManagement;
});
