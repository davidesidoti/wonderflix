import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/states.dart';
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

class MyListScreen extends ConsumerWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final overrides = ref.watch(userDataOverridesProvider);
    return ref.watch(favoritesProvider).when(
          loading: () => const LoadingView(),
          error: (error, _) =>
              ErrorView(error: error, onRetry: () => ref.invalidate(favoritesProvider)),
          data: (items) {
            // Tolti dal cuore in questa sessione: spariscono subito.
            final visible = items
                .where((i) => (overrides[i.id] ?? i.userData).isFavorite)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(32),
              children: [
                Text(l.navMyList.toUpperCase(), style: WfText.display(40)),
                const SizedBox(height: 20),
                if (visible.isEmpty)
                  Text(l.myListEmpty, style: const TextStyle(color: WfColors.creamMuted))
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 24,
                    children: [
                      for (final item in visible)
                        PosterCard(
                          item: item,
                          width: 160,
                          onTap: () => openItem(context, item),
                        ),
                    ],
                  ),
              ],
            );
          },
        );
  }
}
