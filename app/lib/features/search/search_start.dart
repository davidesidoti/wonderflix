import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/poster_card.dart';
import '../../ui/tv_focusable.dart';
import '../catalog/catalog_controller.dart';
import '../catalog/catalog_navigation.dart';
import '../home/home_providers.dart';
import 'recent_searches.dart';

/// Cerca prima di scrivere (spec §8.1): ricerche recenti, generi e titoli
/// aggiunti di recente. Ogni blocco ha i margini laterali [side].
class SearchStart extends ConsumerStatefulWidget {
  const SearchStart({super.key, required this.onRecent, required this.side});

  /// Un tocco su una ricerca recente: lo schermo la scrive nel campo.
  final ValueChanged<String> onRecent;
  final double side;

  @override
  ConsumerState<SearchStart> createState() => _SearchStartState();
}

class _SearchStartState extends ConsumerState<SearchStart>
    with AutomaticKeepAliveClientMixin {
  ItemKind _kind = ItemKind.movie;

  /// Dopo un cambio di tipo il blocco (e le due pastiglie) resta anche
  /// mentre i generi si leggono o se la lettura fallisce.
  bool _switched = false;

  /// Nella lista dei risultati scorsa resta viva: i provider non si
  /// rileggono quando si svuota il campo.
  @override
  bool get wantKeepAlive => true;

  static const _head = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final recent = ref.watch(recentSearchesProvider);
    final filters = ref.watch(catalogFiltersProvider(_kind));
    // Sulla TV niente "Aggiunti di recente" (spec §8.3): due file sole.
    final latest = form.tv ? const <JellyfinItem>[] : _latest();
    final showGenres = filters.hasValue || _switched;
    final blocks = [
      if (recent.isNotEmpty)
        form.tv ? _tvRecent(l, recent) : _recent(l, recent),
      if (showGenres)
        form.tv
            ? _tvGenres(l, filters.value?.genres ?? const [])
            : _genres(l, filters.value?.genres ?? const []),
      if (latest.isNotEmpty) _latestSection(l, form, latest),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.fromLTRB(
                widget.side, i == 0 ? 0 : 32, widget.side, 0),
            child: block,
          ),
      ],
    );
  }

  Widget _recent(AppLocalizations l, List<String> recent) {
    final notifier = ref.read(recentSearchesProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(l.searchRecentTitle,
                  overflow: TextOverflow.ellipsis, style: _head),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.searchRecentDeviceOnly,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: WfColors.creamMuted)),
            ),
            TextButton(
                onPressed: notifier.clear,
                child: Text(l.searchRecentClearAll)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final term in recent)
              InputChip(
                avatar: const Icon(LucideIcons.history, size: 14),
                label: Text(term),
                onPressed: () => widget.onRecent(term),
                onDeleted: () => notifier.remove(term),
                deleteButtonTooltipMessage: l.searchRecentRemove(term),
              ),
          ],
        ),
      ],
    );
  }

  Widget _kindChip(ItemKind kind, String label) => ChoiceChip(
        label: Text(label),
        selected: _kind == kind,
        onSelected: (_) => setState(() {
          _kind = kind;
          _switched = true;
        }),
      );

  Widget _tvPills(List<Widget> pills) => _TvPillRow(pills: pills);

  /// Recenti sulla TV: niente ✕ (non si raggiunge), "Cancella" in fondo.
  Widget _tvRecent(AppLocalizations l, List<String> recent) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.searchRecentTitle, style: _head),
              const SizedBox(width: 10),
              Text(l.searchRecentDeviceOnly,
                  style: const TextStyle(
                      fontSize: 12.5, color: WfColors.creamMuted)),
            ],
          ),
          const SizedBox(height: 8),
          _tvPills([
            for (final term in recent)
              ActionChip(
                avatar: const Icon(LucideIcons.history, size: 14),
                label: Text(term),
                onPressed: () => widget.onRecent(term),
              ),
            ActionChip(
              label: Text(l.searchRecentClearAll),
              onPressed: ref.read(recentSearchesProvider.notifier).clear,
            ),
          ]),
        ],
      );

  /// Generi sulla TV: prima Film e Serie, poi i generi, in una fila.
  Widget _tvGenres(AppLocalizations l, List<String> genres) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.searchGenresTitle, style: _head),
          const SizedBox(height: 8),
          _tvPills([
            _kindChip(ItemKind.movie, l.navMovies),
            _kindChip(ItemKind.series, l.navSeries),
            for (final genre in genres)
              ActionChip(
                label: Text(genre),
                onPressed: () => openCatalog(context, _kind, genre: genre),
              ),
          ]),
        ],
      );

  Widget _genres(AppLocalizations l, List<String> genres) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.searchGenresTitle, style: _head)),
            _kindChip(ItemKind.movie, l.navMovies),
            const SizedBox(width: 8),
            _kindChip(ItemKind.series, l.navSeries),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in genres)
              ActionChip(
                label: Text(genre),
                onPressed: () => openCatalog(context, _kind, genre: genre),
              ),
          ],
        ),
      ],
    );
  }

  /// Film e serie alternati, primo un film; con una lettura fallita, l'altra.
  List<JellyfinItem> _latest() {
    final movies = ref.watch(homeLatestMoviesProvider).value ?? const [];
    final series = ref.watch(homeLatestSeriesProvider).value ?? const [];
    return [
      for (var i = 0; i < movies.length || i < series.length; i++) ...[
        if (i < movies.length) movies[i],
        if (i < series.length) series[i],
      ],
    ];
  }

  Widget _latestSection(
          AppLocalizations l, FormFactor form, List<JellyfinItem> items) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.searchLatestTitle,
              style: WfText.display(form.tv ? 22 : (form.compact ? 26 : 30))),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Sul telefono due file da due; più largo una fila intera.
            final count = !form.tv && MediaQuery.sizeOf(context).width < 600
                ? 4
                : catalogColumnCount(width);
            final shown = items.take(count).toList();
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 24,
                crossAxisSpacing: 16,
                mainAxisExtent:
                    catalogCellExtent(width, MediaQuery.textScalerOf(context)),
              ),
              children: [
                for (final (i, item) in shown.indexed)
                  PosterCard(
                      item: item,
                      heroSource: 'search.latest.$i',
                      catalogStyle: true),
              ],
            );
          }),
        ],
      );
}

/// Sulla TV le pastiglie stanno in una fila che scorre col focus. Il focus
/// che arriva da fuori (Su, Giù) va alla prima: Flutter sceglierebbe la più
/// vicina al centro del campo, magari "Cancella".
class _TvPillRow extends StatefulWidget {
  const _TvPillRow({required this.pills});

  final List<Widget> pills;

  @override
  State<_TvPillRow> createState() => _TvPillRowState();
}

class _TvPillRowState extends State<_TvPillRow> {
  final _row = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  void _enter(bool focused) {
    final first = _row.traversalDescendants.firstOrNull;
    if (!focused || first == null || first.hasPrimaryFocus) return;
    first.requestFocus();
    Scrollable.ensureVisible(first.context!);
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _row,
        onFocusChange: _enter,
        child: SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.pills.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) =>
                Center(child: TvFocusBorder(child: widget.pills[i])),
          ),
        ),
      );
}