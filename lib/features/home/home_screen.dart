import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../playback/play_launcher.dart';
import 'hero_carousel.dart';
import 'home_data.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          controller: _scroll,
          // Il carosello parte dal bordo della finestra, sotto la barra;
          // senza carosello la prima riga inizia sotto la barra.
          padding: EdgeInsets.only(
              top: data.featured.isEmpty ? shellBarHeight : 0, bottom: 40),
          children: [
            if (data.featured.isNotEmpty) HeroCarousel(items: data.featured),
            if (data.resume.isNotEmpty)
              _landscapeRow(l.homeContinueWatching, data.resume, 'home.resume'),
            if (data.nextUp.isNotEmpty)
              _landscapeRow(l.homeNextUp, data.nextUp, 'home.nextUp'),
            if (data.latestMovies.isNotEmpty)
              _posterRow(l.homeLatestMovies, data.latestMovies, 'home.latestMovies'),
            if (data.latestSeries.isNotEmpty)
              _posterRow(l.homeLatestSeries, data.latestSeries, 'home.latestSeries'),
            if (data.favorites.isNotEmpty)
              _posterRow(l.navMyList, data.favorites, 'home.favorites'),
          ],
        );
      },
    );
  }

  Widget _posterRow(String title, List<JellyfinItem> items, String source) =>
      MediaRow(
        title: title,
        height: 300,
        itemCount: items.length,
        itemBuilder: (context, i) => PosterCard(
          item: items[i],
          width: 160,
          heroSource: '$source.$i',
          onPlay: () => unawaited(playItem(context, ref, items[i])),
        ),
      );

  Widget _landscapeRow(String title, List<JellyfinItem> items, String source) =>
      MediaRow(
        title: title,
        height: 230,
        itemCount: items.length,
        itemBuilder: (context, i) => LandscapeCard(
          item: items[i],
          heroSource: '$source.$i',
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
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
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
