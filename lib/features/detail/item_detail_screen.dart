import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/shimmer.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
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
    final (state, content) = async.when(
      loading: () => (
        'loading',
        launch == null
            ? const DetailSkeleton(headerHeight: detailHeaderHeight)
            // Senza `_scroll`: durante la dissolvenza verso i dati il
            // controller sta solo sulla lista dei dati.
            : ListView(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: detailHeaderHeight),
                  WfShimmer(child: DetailRowsSkeleton()),
                ],
              ),
      ),
      error: (error, _) => (
        'error',
        ErrorView(
            error: error,
            onRetry: () => ref.invalidate(itemProvider(widget.itemId))),
      ),
      data: (item) => (
        'data',
        item.kind == ItemKind.series
            ? SeriesDetailView(
                series: item,
                initialSeasonId: widget.seasonId,
                controller: _scroll)
            : MovieDetailView(item: item, controller: _scroll),
      ),
    );
    // Sfondo solo con i dati o con un volo in arrivo. L'albero resta lo
    // stesso in ogni stato, così la dissolvenza verso i dati c'è sempre.
    final showBackdrop = item != null || (launch != null && !async.hasError);
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          child: showBackdrop
              ? DetailBackdrop(item: item, launch: launch, controller: _scroll)
              : const SizedBox.shrink(),
        ),
        Positioned.fill(
          child: WfSwitcher(
            expand: true,
            child: KeyedSubtree(key: ValueKey(state), child: content),
          ),
        ),
      ],
    );
  }
}
