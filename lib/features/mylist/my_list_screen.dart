import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';

final favoritesProvider = FutureProvider.autoDispose<List<JellyfinItem>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final page = await ref.watch(libraryApiProvider).items(
        const ItemQuery(
          kinds: {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.dateAdded,
          favoritesOnly: true,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: 500,
      );
  return page.items;
});

class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final overrides = ref.watch(userDataOverridesProvider);
    return WfSwitcher(
      expand: true,
      child: ref.watch(favoritesProvider).when(
          // Lo spazio del titolo resta libero: la griglia è dove sarà.
          loading: () => const Padding(
            key: ValueKey('loading'),
            padding: EdgeInsets.only(top: 32 + 40 + 20),
            child: PosterGridSkeleton(),
          ),
          error: (error, _) => ErrorView(
              key: const ValueKey('error'),
              error: error,
              onRetry: () => ref.invalidate(favoritesProvider)),
          data: (items) {
            // Tolti dal cuore in questa sessione: spariscono subito.
            final visible = items
                .where((i) => (overrides[i.id] ?? i.userData).isFavorite)
                .toList();
            return CustomScrollView(
              key: const ValueKey('data'),
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 20),
                  sliver: SliverToBoxAdapter(
                    child: Text(l.navMyList.toUpperCase(), style: WfText.display(40)),
                  ),
                ),
                if (visible.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    sliver: SliverToBoxAdapter(
                      child: Text(l.myListEmpty,
                          style: const TextStyle(color: WfColors.creamMuted)),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 24,
              crossAxisSpacing: 16,
              childAspectRatio: 0.55,
            ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => PosterCard(
                          item: visible[i],
                          heroSource: 'mylist.$i',
                        ),
                        childCount: visible.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
    );
  }
}
