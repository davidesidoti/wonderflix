import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/rune_limit.dart';

/// Lunghezza massima del commento, in punti di codice (spec Q §3).
const ratingCommentMax = 200;

/// Altezza dei pulsanti del voto.
const _scoreButtonHeight = 36.0;

/// I numeri da 1 a 10 in fila: il voto scelto è oro.
class RatingScorePicker extends StatelessWidget {
  const RatingScorePicker({
    super.key,
    this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final int? selected;
  final ValueChanged<int> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var n = 1; n <= 10; n++) ...[
          if (n > 1) const SizedBox(width: 4),
          Expanded(
            child: Material(
              key: Key('rating-score-$n'),
              color: n == selected ? WfColors.gold : WfColors.surfaceHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: WfColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? () => onSelect(n) : null,
                child: SizedBox(
                  height: _scoreButtonHeight,
                  child: Center(
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: n == selected ? WfColors.bg : WfColors.cream,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Il commento facoltativo: 200 punti di codice, Invio non va a capo.
class RatingCommentField extends StatelessWidget {
  const RatingCommentField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: ratingCommentMax,
      inputFormatters: [capRunes(ratingCommentMax)],
      minLines: 1,
      maxLines: 3,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted?.call(),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).ratingCommentHint,
        isDense: true,
      ),
    );
  }
}

/// "7,7" in italiano, "7.7" in inglese.
String formatRatingAverage(double value, String localeName) =>
    NumberFormat('0.0', localeName).format(value);

/// Il titolo di un voto: il film per nome, l'episodio come "Serie · Stagione 2"
/// (la stagione 0 è "Speciali").
String ratingTitle(AppLocalizations l, JellyfinItem item) {
  final series = item.seriesName;
  if (item.kind != ItemKind.episode || series == null) return item.name;
  final season = item.parentIndexNumber;
  if (season == null) return series;
  return '$series · ${season == 0 ? l.ratingSpecials : l.ratingSeason(season)}';
}
