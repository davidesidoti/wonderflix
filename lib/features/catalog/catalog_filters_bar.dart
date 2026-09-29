import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import 'catalog_controller.dart';

/// Ordinamento, genere, anno e visto/non visto.
class CatalogFiltersBar extends ConsumerWidget {
  const CatalogFiltersBar({
    super.key,
    required this.kind,
    required this.query,
    required this.onChanged,
  });

  final ItemKind kind;
  final ItemQuery query;
  final ValueChanged<ItemQuery> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filters =
        ref.watch(catalogFiltersProvider(kind)).value ?? const LibraryFilters();
    final genre = query.genres.isEmpty ? null : query.genres.first;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Picker<CatalogSort>(
          value: query.sort,
          items: {
            CatalogSort.title: '${l.catalogSortLabel}: ${l.catalogSortTitle}',
            CatalogSort.dateAdded: '${l.catalogSortLabel}: ${l.catalogSortDateAdded}',
            CatalogSort.year: '${l.catalogSortLabel}: ${l.catalogSortYear}',
            CatalogSort.rating: '${l.catalogSortLabel}: ${l.catalogSortRating}',
          },
          onChanged: (sort) => onChanged(query.copyWith(sort: sort)),
        ),
        _Picker<String?>(
          value: genre,
          items: {
            null: l.catalogAllGenres,
            for (final g in filters.genres) g: g,
          },
          onChanged: (g) =>
              onChanged(query.copyWith(genres: g == null ? const {} : {g})),
        ),
        _Picker<int?>(
          value: query.year,
          items: {
            null: l.catalogAllYears,
            for (final y in filters.years) y: '$y',
          },
          onChanged: (y) => onChanged(query.copyWith(year: y)),
        ),
        SegmentedButton<WatchedFilter>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: WatchedFilter.all, label: Text(l.catalogWatchedAll)),
            ButtonSegment(
                value: WatchedFilter.unwatched,
                label: Text(l.catalogWatchedUnwatched)),
            ButtonSegment(
                value: WatchedFilter.watched, label: Text(l.catalogWatchedWatched)),
          ],
          selected: {query.watched},
          onSelectionChanged: (s) => onChanged(query.copyWith(watched: s.first)),
        ),
        if (query.hasFilters)
          TextButton(
            onPressed: () => onChanged(ItemQuery(kinds: query.kinds, sort: query.sort)),
            child: Text(l.catalogClearFilters),
          ),
      ],
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({required this.value, required this.items, required this.onChanged});

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : null,
          dropdownColor: WfColors.surface,
          style: const TextStyle(color: WfColors.cream, fontSize: 13.5),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => onChanged(v as T),
        ),
      ),
    );
  }
}
