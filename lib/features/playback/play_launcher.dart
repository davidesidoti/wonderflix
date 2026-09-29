import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../detail/detail_providers.dart';
import '../detail/primary_action.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';

/// Chiamata di [playItem] in corso: dalla scelta di cosa riprodurre fino
/// all'uscita dal player.
class _Launch {
  /// Il player è stato aperto.
  bool pushed = false;
}

_Launch? _launch;

/// `true` se una chiamata precedente sta ancora preparando la riproduzione
/// o il suo player è aperto. Se il player è stato tolto senza uscirne (es.
/// redirect per la sessione) la sua push non si completa più: conta allora
/// la posizione attuale del router.
bool _launchInProgress(BuildContext context) {
  final launch = _launch;
  if (launch == null) return false;
  if (!launch.pushed) return true;
  return GoRouter.of(context)
      .routeInformationProvider
      .value
      .uri
      .path
      .startsWith('/play/');
}

/// Unico punto d'ingresso della riproduzione.
/// - Per una serie riproduce il prossimo episodio (o il primo).
/// - Riprende dal minutaggio salvato, letto dai dati utente più recenti,
///   salvo [fromStart].
/// - Doppio clic: finché la chiamata precedente è in corso le altre vengono
///   ignorate, così si apre un solo player.
///
/// Si completa quando l'utente esce dal player. Eccezione: se il player
/// passa all'episodio successivo (`pushReplacement`) la push originale non
/// si completa più e la chiamata resta in sospeso. Non è un problema: una
/// volta aperto il player, [_launchInProgress] non guarda più la chiamata ma
/// la posizione del router (`/play/…`), quindi uscendo dal player si può
/// riprodurre di nuovo.
Future<void> playItem(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  bool fromStart = false,
}) async {
  if (_launchInProgress(context)) return;
  final launch = _launch = _Launch();
  try {
    var target = item;
    if (item.kind == ItemKind.series) {
      final l = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final JellyfinItem? next;
      try {
        next = await findNextEpisode(ref.read(libraryApiProvider),
            ref.read(currentUserIdProvider), item.id);
      } on Object catch (error) {
        messenger
            .showSnackBar(SnackBar(content: Text(describeError(l, error))));
        return;
      }
      if (next == null) {
        messenger.showSnackBar(SnackBar(content: Text(l.detailNoEpisodes)));
        return;
      }
      if (!context.mounted) return;
      target = next;
    }
    final userData =
        ref.read(userDataOverridesProvider)[target.id] ?? target.userData;
    final action = primaryActionFor(target, userData);
    final start =
        !fromStart && action is ResumeAction ? action.position : Duration.zero;
    await _open(context, launch, playerRoute(target.id, start: start));
  } finally {
    if (identical(_launch, launch)) _launch = null;
  }
}

/// Apre il player e aspetta che l'utente ne esca.
Future<void> _open(BuildContext context, _Launch launch, String route) async {
  final opened = context.push<void>(route);
  launch.pushed = true;
  await opened;
}

/// Primo trailer remoto con indirizzo web valido (solo `http`/`https`).
Uri? remoteTrailerUri(JellyfinItem item) {
  if (item.remoteTrailers.isEmpty) return null;
  final uri = Uri.tryParse(item.remoteTrailers.first.url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  return uri;
}

/// Trailer di [item]: quello salvato sul server nel player, altrimenti il
/// trailer remoto (YouTube) nel browser.
Future<void> playTrailer(
    BuildContext context, WidgetRef ref, JellyfinItem item) async {
  if (_launchInProgress(context)) return;
  final launch = _launch = _Launch();
  try {
    if (item.localTrailerCount > 0) {
      List<JellyfinItem> trailers;
      try {
        trailers = await ref
            .read(libraryApiProvider)
            .localTrailers(ref.read(currentUserIdProvider), item.id);
      } on Object catch (error) {
        debugPrint('Trailer locali non disponibili: $error');
        trailers = const [];
      }
      if (!context.mounted) return;
      if (trailers.isNotEmpty) {
        await _open(context, launch, playerRoute(trailers.first.id));
        return;
      }
    }
    final remote = remoteTrailerUri(item);
    if (remote != null) {
      await launchUrl(remote, mode: LaunchMode.externalApplication);
    }
  } finally {
    if (identical(_launch, launch)) _launch = null;
  }
}
