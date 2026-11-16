import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';
import 'tv_focusable.dart';

/// Testo lungo che chiuso sta in [maxLines] righe e, solo se non ci sta,
/// ha sotto "Altro": un tocco lo apre ([expandedMaxLines] righe, `null` =
/// tutte) e non si richiude. Con [tvFocusable] (solo TV) è il testo intero
/// a prendere il focus, e OK lo apre; "Altro" resta come scritta.
class ExpandableText extends StatefulWidget {
  const ExpandableText(
    this.text, {
    super.key,
    required this.maxLines,
    this.expandedMaxLines,
    this.style,
    this.tvFocusable = false,
  });

  final String text;
  final int maxLines;
  final int? expandedMaxLines;
  final TextStyle? style;
  final bool tvFocusable;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _open = false;

  void _expand() => setState(() => _open = true);

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    const moreStyle = TextStyle(
      color: WfColors.gold,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final exceeds =
            !_open &&
            (TextPainter(
              text: TextSpan(text: widget.text, style: style),
              textDirection: direction,
              textScaler: scaler,
              maxLines: widget.maxLines,
            )..layout(maxWidth: constraints.maxWidth)).didExceedMaxLines;
        final more = Text(
          AppLocalizations.of(context).detailShowMore,
          style: moreStyle,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _open ? widget.expandedMaxLines : widget.maxLines,
              overflow: TextOverflow.ellipsis,
            ),
            if (exceeds) ...[
              const SizedBox(height: 4),
              if (widget.tvFocusable)
                more
              else
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _expand,
                    child: Semantics(button: true, child: more),
                  ),
                ),
            ],
          ],
        );
      },
    );
    return widget.tvFocusable
        ? TvFocusable(onActivate: _expand, child: body)
        : body;
  }
}
