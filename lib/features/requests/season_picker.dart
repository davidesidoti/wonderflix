import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// L'etichetta dello stato di una stagione (spec I §9.2).
String seasonStatusLabel(AppLocalizations l, TitleStatus status) =>
    switch (status) {
      TitleStatus.none => l.requestsStatusToRequest,
      TitleStatus.pending => l.requestsStatusPending,
      TitleStatus.processing => l.requestsBadgeComing,
      TitleStatus.partial => l.requestsBadgePartial,
      TitleStatus.available => l.requestsStatusAvailable,
    };

/// Le stagioni con le caselle (spec I §9.2): "Tutte" in cima se ce n'è più
/// di una da chiedere; quelle già presenti o già chieste sono segnate e
/// bloccate, con il loro stato a destra.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
    this.enabled = true,
  });

  final List<SeasonInfo> seasons;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final VoidCallback onToggleAll;

  /// Spento durante l'invio, o se l'utente non può chiedere.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final requestable = [
      for (final season in seasons)
        if (season.status.isRequestable) season.seasonNumber,
    ];
    final chosen = requestable.where(selected.contains).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (requestable.length > 1)
          _SeasonRow(
            key: const ValueKey('season-all'),
            value: chosen == 0
                ? false
                : chosen == requestable.length
                    ? true
                    : null,
            label: l.requestsAllSeasons,
            onTap: enabled ? onToggleAll : null,
          ),
        for (final season in seasons)
          _SeasonRow(
            key: ValueKey('season-${season.seasonNumber}'),
            value: season.status.isRequestable
                ? selected.contains(season.seasonNumber)
                : true,
            label: l.requestsSeasonLine(season.seasonNumber, season.episodeCount),
            status: seasonStatusLabel(l, season.status),
            onTap: enabled && season.status.isRequestable
                ? () => onToggle(season.seasonNumber)
                : null,
          ),
      ],
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({
    super.key,
    required this.value,
    required this.label,
    required this.onTap,
    this.status,
  });

  /// `null`: in parte (solo "Tutte").
  final bool? value;
  final String label;
  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final status = this.status;
    return InkWell(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WfColors.border)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              tristate: value == null,
              onChanged: tap == null ? null : (_) => tap(),
              activeColor: WfColors.gold,
              checkColor: WfColors.bg,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: tap == null ? WfColors.creamMuted : WfColors.cream)),
            ),
            if (status != null)
              Text(status,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
