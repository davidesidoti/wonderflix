import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
/// Si completa quando l'utente esce dal player.
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
    final opened = context.push<void>(playerRoute(target.id, start: start));
    launch.pushed = true;
    await opened;
  } finally {
    if (identical(_launch, launch)) _launch = null;
  }
}
