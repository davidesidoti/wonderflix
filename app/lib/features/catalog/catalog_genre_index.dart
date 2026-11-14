import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import 'catalog_genres.dart';

/// La riga dei generi della sala: "Tutti 801", "Azione 330", ... Scorre di
/// lato, con una sfumatura a destra che dice che continua.
///
/// Finché i conteggi non ci sono (o se la lettura è fallita) mostra solo
/// "Tutti": la soglia dei 5 titoli ha bisogno dei conteggi.
class CatalogGenreIndex extends StatelessWidget {
  const CatalogGenreIndex({
    super.key,
    required this.kind,
    required this.genres,
    required this.total,
    required this.selected,
    required this.onSelected,
  });

  final ItemKind kind;
  final AsyncValue<List<GenreCount>> genres;

  /// Titoli senza filtri; senza, "Tutti" non ha il numero.
  final int? total;

  /// Etichetta del genere scelto, `null` per "Tutti".
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tv = FormFactor.of(context).tv;
    final list = switch (genres) {
      AsyncData(:final value) => value,
      _ => const <GenreCount>[],
    };
    final entries = <({String? genre, String label, int? count})>[
      (
        genre: null,
        label: kind == ItemKind.series ? l.catalogAllFeminine : l.catalogAll,
        count: total,
      ),
      for (final g in list) (genre: g.label, label: g.label, count: g.count),
    ];
    return Stack(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(0, tv ? 6 : 10, 48, tv ? 4 : 6),
          child: Row(
            spacing: 22,
            children: [
              for (final e in entries)
                _GenreItem(
                  label: e.label,
                  count: e.count,
                  selected: e.genre == selected,
                  onTap: () => onSelected(e.genre),
                ),
            ],
          ),
        ),
        // Sfuma verso il fondo della pagina, non prende i tocchi.
        Positioned(
          top: 0,
          bottom: 6,
          right: 0,
          width: 56,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [WfColors.bg.withValues(alpha: 0), WfColors.bg],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GenreItem extends StatelessWidget {
  const _GenreItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tv = FormFactor.of(context).tv;
    final color = selected ? WfColors.gold : WfColors.creamMuted;
    return TvFocusable(
      autofocus: selected,
      onActivate: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            // Sulla TV il focus è di TvFocusable.
            canRequestFocus: !tv,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? WfColors.gold : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (count != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: selected
                              ? WfColors.gold
                              : WfColors.cream.withValues(alpha: 0.32),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
