import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/rune_limit.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/tv_text_field_frame.dart';

/// Lunghezza massima del commento, in punti di codice (spec Q §3).
const ratingCommentMax = 200;

/// Altezza dei pulsanti del voto.
const _scoreButtonHeight = 36.0;

/// La parola sotto il voto: da "Da evitare" (1) a "Imperdibile" (10).
String ratingWord(AppLocalizations l, int score) => switch (score) {
      <= 2 => l.ratingWordAvoid,
      <= 4 => l.ratingWordDisappointing,
      <= 6 => l.ratingWordSoSo,
      7 => l.ratingWordGood,
      8 => l.ratingWordVeryGood,
      9 => l.ratingWordGreat,
      _ => l.ratingWordMustSee,
    };

/// I numeri da 1 a 10 in fila: il voto scelto è oro. Con [large] (pannello
/// del voto) due file da cinque, caselle alte e numeri grandi.
class RatingScorePicker extends StatelessWidget {
  const RatingScorePicker({
    super.key,
    this.selected,
    required this.onSelect,
    this.enabled = true,
    this.large = false,
  });

  final int? selected;
  final ValueChanged<int> onSelect;
  final bool enabled;
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (!large) return _row(context, 1, 10);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, 1, 5),
        const SizedBox(height: 8),
        _row(context, 6, 10),
      ],
    );
  }

  Widget _row(BuildContext context, int from, int to) {
    final tv = FormFactor.of(context).tv;
    final gap = large ? 8.0 : 4.0;
    final radius = BorderRadius.circular(large ? 8 : 6);
    return Row(
      children: [
        for (var n = from; n <= to; n++) ...[
          if (n > from) SizedBox(width: gap),
          Expanded(
            child: TvFocusBorder(
              borderRadius: radius,
              // Il voto scelto è pieno d'oro: il bordo crema.
              color: n == selected ? tvFocusSideOnGold.color : tvFocusColor,
              child: Material(
                key: Key('rating-score-$n'),
                color: n == selected ? WfColors.gold : WfColors.surfaceHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: const BorderSide(color: WfColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled ? () => onSelect(n) : null,
                  child: SizedBox(
                    height: large ? (tv ? 46 : 56) : _scoreButtonHeight,
                    child: Center(
                      child: Text(
                        '$n',
                        style: large
                            ? WfText.display(tv ? 26 : 30,
                                color: n == selected
                                    ? WfColors.bg
                                    : WfColors.cream)
                            : TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: n == selected
                                    ? WfColors.bg
                                    : WfColors.cream,
                              ),
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
class RatingCommentField extends StatefulWidget {
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
  State<RatingCommentField> createState() => _RatingCommentFieldState();
}

class _RatingCommentFieldState extends State<RatingCommentField> {
  /// Il nodo di riserva: la cornice TV ne vuole sempre uno.
  final _own = FocusNode(debugLabel: 'rating-comment');

  FocusNode get _node => widget.focusNode ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvTextFieldFrame(
      focusNode: _node,
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        maxLength: ratingCommentMax,
        inputFormatters: [capRunes(ratingCommentMax)],
        minLines: 1,
        maxLines: 3,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).ratingCommentHint,
          isDense: true,
        ),
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
