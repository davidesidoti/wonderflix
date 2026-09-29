import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'primary_action.dart';

/// Parte alta di una scheda: sfondo, logo o titolo, dati, trama, azioni.
class DetailHeader extends ConsumerWidget {
  const DetailHeader({super.key, required this.item, required this.primary});

  final JellyfinItem item;

  /// `null` finché non si sa cosa riprodurre (serie ancora in caricamento).
  final PrimaryAction? primary;

  Future<void> _toggle(BuildContext context, Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final userData = watchUserData(ref, item);
    final overrides = ref.read(userDataOverridesProvider.notifier);
    final logo = urls.logo(item);
    final action = primary;
    final overview = item.overview;
    final hasTrailer =
        item.localTrailerCount > 0 || remoteTrailerUri(item) != null;

    return SizedBox(
      height: 560,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropImage(backdrop: urls.backdrop(item), fallback: urls.poster(item)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [WfColors.bg, Color(0xD90A0A0A), Colors.transparent],
                stops: [0, 0.4, 0.8],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [WfColors.bg, Colors.transparent],
                stops: [0, 0.5],
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  SizedBox(
                    height: 120,
                    width: 460,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: WfImage(image: logo, fit: BoxFit.contain),
                    ),
                  )
                else
                  Text(item.name.toUpperCase(),
                      maxLines: 2, style: WfText.display(56)),
                const SizedBox(height: 12),
                MetaLine(item: item),
                if (item.genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item.genres.join(' · '),
                      style: const TextStyle(color: WfColors.creamMuted)),
                ],
                if (overview != null) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Text(overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45)),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (action != null)
                      WfButton.primary(
                        label: primaryActionLabel(l, action),
                        icon: LucideIcons.play,
                        onPressed: () =>
                            unawaited(playItem(context, ref, action.target)),
                      ),
                    if (action is ResumeAction)
                      WfButton.secondary(
                        label: l.actionRestart,
                        icon: LucideIcons.rotateCcw,
                        onPressed: () => unawaited(playItem(
                            context, ref, action.target,
                            fromStart: true)),
                      ),
                    if (hasTrailer)
                      WfButton.secondary(
                        label: l.actionTrailer,
                        icon: LucideIcons.clapperboard,
                        onPressed: () =>
                            unawaited(playTrailer(context, ref, item)),
                      ),
                    WfIconToggle(
                      icon: LucideIcons.heart,
                      selected: userData.isFavorite,
                      tooltip: userData.isFavorite
                          ? l.actionRemoveFromList
                          : l.actionAddToList,
                      onPressed: () => unawaited(
                          _toggle(context, () => overrides.toggleFavorite(item))),
                    ),
                    WfIconToggle(
                      icon: LucideIcons.check,
                      selected: userData.played,
                      tooltip: userData.played
                          ? l.actionMarkUnwatched
                          : l.actionMarkWatched,
                      onPressed: () => unawaited(
                          _toggle(context, () => overrides.togglePlayed(item))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "2024 · 2h 46m · ★ 8.4 · [PG-13]".
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final runtime = item.runtime;
    final seasons = item.childCount;
    final rating = item.communityRating;
    final official = item.officialRating;
    const muted = TextStyle(color: WfColors.creamMuted);
    final parts = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.kind != ItemKind.series && runtime != null) formatRuntime(runtime),
      if (item.kind == ItemKind.series && seasons != null) l.detailSeasons(seasons),
    ];
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (parts.isNotEmpty) Text(parts.join(' · '), style: muted),
        if (rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
              const SizedBox(width: 4),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(
                      color: WfColors.gold, fontWeight: FontWeight.w600)),
            ],
          ),
        if (official != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: WfColors.creamMuted),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(official, style: muted.copyWith(fontSize: 12)),
          ),
      ],
    );
  }
}
