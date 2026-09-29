import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
import '../playback/play_launcher.dart';
import 'hero_carousel.dart';
import 'home_data.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final home = ref.watch(homeProvider);
    return home.when(
      loading: () => const _HomeSkeleton(),
      error: (error, _) =>
          ErrorView(error: error, onRetry: () => ref.invalidate(homeProvider)),
      data: (data) {
        if (data.isEmpty) {
          return Center(
            child: Text(l.homeEmpty,
                style: const TextStyle(color: WfColors.creamMuted)),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            if (data.featured.isNotEmpty) HeroCarousel(items: data.featured),
            if (data.resume.isNotEmpty)
              _landscapeRow(ref, l.homeContinueWatching, data.resume),
            if (data.nextUp.isNotEmpty) _landscapeRow(ref, l.homeNextUp, data.nextUp),
            if (data.latestMovies.isNotEmpty)
              _posterRow(ref, l.homeLatestMovies, data.latestMovies),
            if (data.latestSeries.isNotEmpty)
              _posterRow(ref, l.homeLatestSeries, data.latestSeries),
            if (data.favorites.isNotEmpty) _posterRow(ref, l.navMyList, data.favorites),
          ],
        );
      },
    );
  }

  Widget _posterRow(WidgetRef ref, String title, List<JellyfinItem> items) => MediaRow(
        title: title,
        height: 300,
        itemCount: items.length,
        itemBuilder: (context, i) => PosterCard(
          item: items[i],
          width: 160,
          onTap: () => openItem(context, items[i]),
          onPlay: () => unawaited(playItem(context, ref, items[i])),
        ),
      );

  Widget _landscapeRow(WidgetRef ref, String title, List<JellyfinItem> items) => MediaRow(
        title: title,
        height: 230,
        itemCount: items.length,
        itemBuilder: (context, i) => LandscapeCard(
          item: items[i],
          onTap: () => openItem(context, items[i]),
          onPlay: () => unawaited(playItem(context, ref, items[i])),
        ),
      );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SkeletonBox(height: 380),
        const SizedBox(height: 32),
        for (var row = 0; row < 2; row++) ...[
          const SkeletonBox(width: 240, height: 22),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  const SkeletonBox(width: 160, height: 240),
                  const SizedBox(width: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
