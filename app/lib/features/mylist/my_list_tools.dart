import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../catalog/catalog_filters_bar.dart';
import '../catalog/catalog_genre_index.dart';
import '../catalog/catalog_tools.dart';
import 'my_list_view.dart';

/// Gli attrezzi di La mia lista (spec §7): Ordina e verso; con più di 24
/// titoli, sopra, la riga dei generi (non sulla TV) e, a destra, "Cerca
/// nella lista" (né stretto né sulla TV), che filtra a ogni tasto.
class MyListTools extends StatefulWidget {
  const MyListTools({
    super.key,
    required this.view,
    required this.filters,
    required this.onChanged,
  });

  final MyListView view;
  final MyListFilters filters;
  final ValueChanged<MyListFilters> onChanged;

  @override
  State<MyListTools> createState() => _MyListToolsState();
}

class _MyListToolsState extends State<MyListTools> {
  late final _search = TextEditingController(text: widget.filters.search);

  @override
  void didUpdateWidget(MyListTools old) {
    super.didUpdateWidget(old);
    // "Azzera filtri" e il cambio di scheda svuotano la ricerca da fuori.
    if (widget.filters.search != _search.text) {
      _search.text = widget.filters.search;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final filters = widget.filters;
    final narrow = form.compact && !form.tv;
    final refine = widget.view.showRefinements;
    String label(String name) => narrow ? name : '${l.catalogSortShort}: $name';
    final sort = FilterPicker<CatalogSort>(
      value: filters.sort,
      items: {
        CatalogSort.dateAdded: label(l.myListSortAdded),
        CatalogSort.title: label(l.catalogSortTitle),
        CatalogSort.year: label(l.catalogSortYear),
        CatalogSort.rating: label(l.catalogSortRating),
      },
      // Cambiare ordine riparte dal verso di default.
      onChanged: (s) =>
          widget.onChanged(filters.copyWith(sort: s, reversed: false)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refine && !form.tv)
          CatalogGenreIndex(
            kind: ItemKind.movie,
            genres: AsyncData(widget.view.genres),
            total: widget.view.tabCount,
            selected: filters.genre,
            onSelected: (g) => widget.onChanged(filters.copyWith(genre: g)),
          ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: form.tv ? 6 : 10),
          child: Row(
            spacing: 8,
            children: [
              if (narrow) Expanded(child: sort) else sort,
              CatalogReverseButton(
                reversed: filters.reversed,
                onPressed: () => widget.onChanged(
                  filters.copyWith(reversed: !filters.reversed),
                ),
              ),
              if (refine && !form.compact && !form.tv) ...[
                const Spacer(),
                SizedBox(
                  width: 260,
                  height: 36,
                  child: TextField(
                    controller: _search,
                    onChanged: (text) =>
                        widget.onChanged(widget.filters.copyWith(search: text)),
                    style: const TextStyle(fontSize: 13, color: WfColors.cream),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l.myListSearch,
                      prefixIcon: const Icon(
                        LucideIcons.search,
                        size: 16,
                        color: WfColors.creamMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
