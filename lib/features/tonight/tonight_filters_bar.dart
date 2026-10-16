import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../catalog/catalog_filters_bar.dart';
import 'tonight_controller.dart';
import 'tonight_logic.dart';

/// I filtri di "Cosa guardo stasera?" (spec M §8.4): tipo, durata (solo per
/// i film) e genere. Li usa anche la sala del match (spec P §7.3).
class TonightFiltersBar extends ConsumerWidget {
  const TonightFiltersBar(
      {super.key, required this.filters, required this.onChanged});

  final TonightFilters filters;
  final ValueChanged<TonightFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final genres = ref.watch(tonightGenresProvider(filters.type)).value ??
        const <String>[];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<TonightType>(
          key: const Key('tonight-type'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: TonightType.movies, label: Text(l.tonightTypeMovies)),
            ButtonSegment(
                value: TonightType.series, label: Text(l.tonightTypeSeries)),
            ButtonSegment(
                value: TonightType.both, label: Text(l.tonightTypeBoth)),
          ],
          selected: {filters.type},
          onSelectionChanged: (selection) =>
              onChanged(filters.copyWith(type: selection.first)),
        ),
        SegmentedButton<TonightDuration>(
          key: const Key('tonight-duration'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: TonightDuration.any, label: Text(l.tonightDurationAny)),
            ButtonSegment(
                value: TonightDuration.under90,
                label: Text(l.tonightDuration90)),
            ButtonSegment(
                value: TonightDuration.under120,
                label: Text(l.tonightDuration120)),
          ],
          selected: {filters.duration},
          // La durata vale solo per i film (spec M §8.4).
          onSelectionChanged: filters.type == TonightType.series
              ? null
              : (selection) =>
                  onChanged(filters.copyWith(duration: selection.first)),
        ),
        FilterPicker<String?>(
          value: filters.genre,
          items: {
            null: l.catalogAllGenres,
            for (final genre in genres) genre: genre,
          },
          onChanged: (genre) => onChanged(filters.copyWith(genre: genre)),
        ),
      ],
    );
  }
}
