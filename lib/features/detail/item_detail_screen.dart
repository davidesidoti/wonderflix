import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/states.dart';
import 'detail_providers.dart';
import 'movie_detail_view.dart';
import 'series_detail_view.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen(
      {super.key, required this.itemId, this.seasonId, this.launch});

  final String itemId;

  /// Stagione da mostrare aperta (solo per le serie).
  final String? seasonId;

  /// Dati del volo Hero dalla card cliccata (`extra` di go_router).
  final HeroLaunch? launch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(itemProvider(itemId)).when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(
              error: error, onRetry: () => ref.invalidate(itemProvider(itemId))),
          data: (item) => item.kind == ItemKind.series
              ? SeriesDetailView(series: item, initialSeasonId: seasonId)
              : MovieDetailView(item: item),
        );
  }
}
