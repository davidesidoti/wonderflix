import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/trailers/trailers_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../detail/detail_providers.dart';
import '../detail/primary_action.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';

final _log = Logger('trailer');

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
  // La pagina in cima: l'indirizzo del `routeInformationProvider`, dopo una
  // push, torna quello della pagina di base.
  final path = GoRouter.of(context).state.uri.path;
  return path.startsWith('/play/') || path.startsWith('/trailer/');
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

/// Id del video YouTube di [url] (11 caratteri), come `YouTubeId.FromUrl`
/// del plugin: watch?v=, youtu.be/, /embed/; `null` per il resto.
String? youTubeIdOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  final id = switch (host) {
    'youtu.be' => segments.firstOrNull,
    'youtube.com' ||
    'www.youtube.com' ||
    'm.youtube.com' ||
    'youtube-nocookie.com' ||
    'www.youtube-nocookie.com' =>
      segments.length > 1 && segments.first == 'embed'
          ? segments[1]
          : uri.path == '/watch'
          ? uri.queryParameters['v']
          : null,
    _ => null,
  };
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}

/// Il titolo ha un trailer: locale, YouTube conosciuto da Jellyfin o, per
/// film e serie, uno che il plugin sa trovare (chiede `Info` solo se
/// Jellyfin non ne conosce già uno).
bool hasTrailerOf(WidgetRef ref, JellyfinItem item) {
  if (item.localTrailerCount > 0 ||
      item.remoteTrailers.any((t) => youTubeIdOf(t.url) != null)) {
    return true;
  }
  if (item.kind != ItemKind.movie && item.kind != ItemKind.series) {
    return false;
  }
  return ref.watch(trailerAvailableProvider(LibraryTrailer(item.id))).value ??
      false;
}

/// Trailer di [item]: quello salvato sul server nel player, altrimenti la
/// schermata del trailer, che lo fa scaricare al plugin.
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
        _log.warning('trailer locali non disponibili: $error');
        trailers = const [];
      }
      if (!context.mounted) return;
      if (trailers.isNotEmpty) {
        await _open(context, launch, playerRoute(trailers.first.id));
        return;
      }
    }
    await _open(
      context,
      launch,
      trailerRoute(
        LibraryTrailer(item.id),
        title: item.name,
        backdropItemId: item.id,
      ),
    );
  } finally {
    if (identical(_launch, launch)) _launch = null;
  }
}
