import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'detail_backdrop.dart';
import 'detail_header.dart';
import 'detail_providers.dart';
import 'movie_detail_view.dart';
import 'series_detail_view.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen(
      {super.key, required this.itemId, this.seasonId, this.launch});

  final String itemId;

  /// Stagione da mostrare aperta (solo per le serie).
  final String? seasonId;

  /// Dati del volo Hero dalla card cliccata (`extra` di go_router).
  final HeroLaunch? launch;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemProvider(widget.itemId));
    final launch = widget.launch;
    final item = async.value;
    final content = async.when(
      loading: () => launch == null
          ? const LoadingView()
          : ListView(
              controller: _scroll,
              children: const [
                SizedBox(height: detailHeaderHeight),
                Padding(padding: EdgeInsets.all(32), child: LoadingView()),
              ],
            ),
      error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(itemProvider(widget.itemId))),
      data: (item) => item.kind == ItemKind.series
          ? SeriesDetailView(
              series: item,
              initialSeasonId: widget.seasonId,
              controller: _scroll)
          : MovieDetailView(item: item, controller: _scroll),
    );
    if (item == null && launch == null) return content;
    if (async.hasError && item == null) return content;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          child: DetailBackdrop(item: item, launch: launch, controller: _scroll),
        ),
        Positioned.fill(child: content),
      ],
    );
  }
}
