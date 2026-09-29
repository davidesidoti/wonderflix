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

/// Unico punto d'ingresso della riproduzione.
/// - Per una serie riproduce il prossimo episodio (o il primo).
/// - Riprende dal minutaggio salvato, letto dai dati utente più recenti,
///   salvo [fromStart].
///
/// Si completa quando l'utente esce dal player.
Future<void> playItem(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  bool fromStart = false,
}) async {
  var target = item;
  if (item.kind == ItemKind.series) {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final JellyfinItem? next;
    try {
      next = await findNextEpisode(ref.read(libraryApiProvider),
          ref.read(currentUserIdProvider), item.id);
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
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
  await context.push<void>(playerRoute(target.id, start: start));
}
