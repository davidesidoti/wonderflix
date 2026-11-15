import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import 'catalog_filters_bar.dart';
import 'catalog_genres.dart';

/// Attesa tra un tasto e l'altro prima di cercare.
const _searchDelay = Duration(milliseconds: 300);

/// Gli attrezzi della sala: ordina, verso, decennio, stato delle serie,
/// "Nascondi i visti", "Azzera filtri" e la ricerca. Stretto (telefono) la
/// riga si accorcia; sulla TV non c'è la ricerca (c'è Cerca nella barra).
class CatalogTools extends StatefulWidget {
  const CatalogTools({
    super.key,
    required this.kind,
    required this.query,
    required this.onChanged,
    this.totals,
  });

  final ItemKind kind;
  final ItemQuery query;
  final ValueChanged<ItemQuery> onChanged;

  /// Per i numeri di "In corso" e "Concluse"; senza, i pulsanti non li hanno.
  final CatalogTotals? totals;

  @override
  State<CatalogTools> createState() => _CatalogToolsState();
}

class _CatalogToolsState extends State<CatalogTools> {
  late final _controller = TextEditingController(
    text: widget.query.searchTerm ?? '',
  );
  Timer? _timer;
  bool _searchOpen = false;

  bool get _series => widget.kind == ItemKind.series;

  @override
  void didUpdateWidget(CatalogTools old) {
    super.didUpdateWidget(old);
    // "Azzera filtri" (o chi sta sopra) cambia la ricerca da fuori.
    final term = widget.query.searchTerm ?? '';
    if (term != (old.query.searchTerm ?? '') && term != _controller.text) {
      _timer?.cancel();
      _controller.text = term;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _change(ItemQuery Function(ItemQuery q) edit) =>
      widget.onChanged(edit(widget.query));

  void _typed(String text) {
    _timer?.cancel();
    _timer = Timer(
      _searchDelay,
      () => _change((q) => q.copyWith(searchTerm: text)),
    );
  }

  void _closeSearch() {
    _timer?.cancel();
    final had = (widget.query.searchTerm ?? '').isNotEmpty;
    _controller.clear();
    setState(() => _searchOpen = false);
    if (had) _change((q) => q.copyWith(searchTerm: null));
  }

  String _sortName(AppLocalizations l, CatalogSort sort) => switch (sort) {
    CatalogSort.title => l.catalogSortTitle,
    CatalogSort.dateAdded =>
      _series ? l.catalogSortNewEpisodes : l.catalogSortAdded,
    CatalogSort.year => l.catalogSortYear,
    CatalogSort.rating => l.catalogSortRating,
  };

  Widget _sortPicker(AppLocalizations l, {required bool prefix}) =>
      FilterPicker<CatalogSort>(
        value: widget.query.sort,
        items: {
          for (final s in CatalogSort.values)
            s: prefix
                ? '${l.catalogSortShort}: ${_sortName(l, s)}'
                : _sortName(l, s),
        },
        // Cambiare ordine riparte dal verso naturale.
        onChanged: (s) => _change((q) => q.copyWith(sort: s, reversed: false)),
      );

  /// [prefix]: "Decennio: 2010"; senza, il menu stretto mostra solo "2010" e,
  /// a riposo, "Decennio".
  Widget _decadePicker(
    AppLocalizations l,
    ItemQuery query,
    ValueChanged<int?> onPick, {
    required bool prefix,
  }) {
    String name(int d) =>
        d == ItemQuery.olderDecades ? l.catalogDecadeOlder : '$d';
    String label(String s) => prefix ? '${l.catalogDecade}: $s' : s;
    return FilterPicker<int?>(
      value: query.decade,
      items: {
        null: prefix ? label(l.catalogAll) : l.catalogDecade,
        for (final d in const [2020, 2010, 2000, 1990, ItemQuery.olderDecades])
          d: label(name(d)),
      },
      onChanged: onPick,
    );
  }

  Widget _statusButtons(
    AppLocalizations l,
    ItemQuery query,
    ValueChanged<SeriesStatusFilter> onPick,
  ) {
    final t = widget.totals;
    String named(String s, int? n) => n == null ? s : '$s $n';
    return SegmentedButton<SeriesStatusFilter>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: SeriesStatusFilter.all,
          label: Text(l.catalogAllFeminine),
        ),
        ButtonSegment(
          value: SeriesStatusFilter.continuing,
          label: Text(named(l.catalogStatusContinuing, t?.secondary)),
        ),
        ButtonSegment(
          value: SeriesStatusFilter.ended,
          label: Text(
            named(
              l.catalogStatusEnded,
              t == null ? null : t.total - t.secondary,
            ),
          ),
        ),
      ],
      selected: {query.seriesStatus},
      onSelectionChanged: (s) => onPick(s.first),
    );
  }

  Widget _reverse(AppLocalizations l) => CatalogReverseButton(
    reversed: widget.query.reversed,
    onPressed: () => _change((q) => q.copyWith(reversed: !q.reversed)),
  );

  void _toggleHidden() => _change(
    (q) => q.copyWith(
      watched: q.watched == WatchedFilter.unwatched
          ? WatchedFilter.all
          : WatchedFilter.unwatched,
    ),
  );

  String _hideLabel(AppLocalizations l) =>
      _series ? l.catalogHideWatchedSeries : l.catalogHideWatched;

  Widget _hideSwitch(AppLocalizations l) => CatalogSwitch(
    on: widget.query.watched == WatchedFilter.unwatched,
    label: _hideLabel(l),
    onToggle: _toggleHidden,
  );

  Widget _searchField(AppLocalizations l, {bool autofocus = false}) => SizedBox(
    height: 36,
    child: TextField(
      controller: _controller,
      autofocus: autofocus,
      onChanged: _typed,
      style: const TextStyle(fontSize: 13, color: WfColors.cream),
      decoration: InputDecoration(
        isDense: true,
        hintText: _series ? l.catalogSearchSeries : l.catalogSearchMovies,
        prefixIcon: const Icon(
          LucideIcons.search,
          size: 16,
          color: WfColors.creamMuted,
        ),
      ),
    ),
  );

  Widget _clear(AppLocalizations l) => TextButton(
    onPressed: () => _change((q) => q.clearRefinements()),
    child: Text(l.catalogClearFilters),
  );

  /// "Filtri" del telefono con le serie: decennio e stato in un foglio. Il
  /// foglio tiene la sua copia della query, perché non si ricostruisce con la
  /// pagina.
  void _openFilters() {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WfColors.surface,
      builder: (context) {
        var q = widget.query;
        return StatefulBuilder(
          builder: (context, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  _decadePicker(l, q, (d) {
                    setSheet(() => q = q.copyWith(decade: d));
                    _change((_) => q);
                  }, prefix: true),
                  _statusButtons(l, q, (s) {
                    setSheet(() => q = q.copyWith(seriesStatus: s));
                    _change((_) => q);
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _compact(AppLocalizations l) {
    if (_searchOpen) {
      return Row(
        spacing: 8,
        children: [
          Expanded(child: _searchField(l, autofocus: true)),
          TextButton(
            onPressed: _closeSearch,
            child: Text(l.catalogSearchClose),
          ),
        ],
      );
    }
    final hidden = widget.query.watched == WatchedFilter.unwatched;
    return Row(
      spacing: 8,
      children: [
        Expanded(child: _sortPicker(l, prefix: false)),
        _reverse(l),
        Expanded(
          child: _series
              ? OutlinedButton(
                  onPressed: _openFilters,
                  child: Text(l.catalogFilters),
                )
              : _decadePicker(
                  l,
                  widget.query,
                  (d) => _change((q) => q.copyWith(decade: d)),
                  prefix: false,
                ),
        ),
        IconButton(
          tooltip: _hideLabel(l),
          isSelected: hidden,
          onPressed: _toggleHidden,
          icon: const Icon(LucideIcons.eye, size: 18),
          selectedIcon: const Icon(
            LucideIcons.eyeOff,
            size: 18,
            color: WfColors.gold,
          ),
        ),
        IconButton(
          tooltip: _series ? l.catalogSearchSeries : l.catalogSearchMovies,
          onPressed: () => setState(() => _searchOpen = true),
          icon: const Icon(LucideIcons.search, size: 18),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final controls = <Widget>[
      _sortPicker(l, prefix: true),
      _reverse(l),
      _decadePicker(
        l,
        widget.query,
        (d) => _change((q) => q.copyWith(decade: d)),
        prefix: true,
      ),
      if (_series)
        _statusButtons(l, widget.query, (s) {
          _change((q) => q.copyWith(seriesStatus: s));
        }),
      _hideSwitch(l),
      if (widget.query.hasRefinements) _clear(l),
    ];
    final Widget row;
    if (form.tv) {
      // Una riga che scorre di lato: la griglia sotto resta alta.
      row = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 12, children: controls),
      );
    } else if (form.compact) {
      row = _compact(l);
    } else {
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: controls,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 260, child: _searchField(l)),
        ],
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(vertical: form.tv ? 6 : 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WfColors.surface)),
      ),
      child: row,
    );
  }
}

/// Il pulsante del verso dell'ordine: freccia in giù col verso di default,
/// in su con quello inverso.
class CatalogReverseButton extends StatelessWidget {
  const CatalogReverseButton({
    super.key,
    required this.reversed,
    required this.onPressed,
  });

  final bool reversed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).catalogReverse,
    onPressed: onPressed,
    icon: Icon(
      reversed ? LucideIcons.arrowUp : LucideIcons.arrowDown,
      size: 18,
    ),
  );
}

/// Interruttore degli attrezzi ("Nascondi i visti", "Nascondi le saghe
/// finite"): levetta oro quando è acceso, e il nome.
class CatalogSwitch extends StatelessWidget {
  const CatalogSwitch({
    super.key,
    required this.on,
    required this.label,
    required this.onToggle,
  });

  final bool on;
  final String label;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tv = FormFactor.of(context).tv;
    return TvFocusable(
      onActivate: onToggle,
      child: Semantics(
        toggled: on,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            canRequestFocus: !tv,
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Container(
                  width: 30,
                  height: 18,
                  padding: const EdgeInsets.all(2),
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: on ? WfColors.gold : WfColors.border,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? WfColors.bg : WfColors.cream,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: on ? WfColors.cream : WfColors.creamMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
