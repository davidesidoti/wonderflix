import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';
import 'tv_focusable.dart';

/// Testo lungo che chiuso sta in [maxLines] righe e, solo se non ci sta,
/// ha sotto "Altro": un tocco lo apre e non si richiude. Aperto è alto al
/// più [expandedMaxLines] righe e scorre dentro (`null` = tutto il testo). Con [tvFocusable] (solo TV) è il testo intero
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
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: widget.maxLines,
        )..layout(maxWidth: constraints.maxWidth);
        final exceeds = !_open && painter.didExceedMaxLines;
        painter.dispose();
        final more = Text(
          AppLocalizations.of(context).detailShowMore,
          style: moreStyle,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_open)
              Text(
                widget.text,
                style: widget.style,
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
              )
            else if (widget.expandedMaxLines case final lines?)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      lines *
                      scaler.scale(style.fontSize ?? 14) *
                      (style.height ?? 1.2),
                ),
                child: SingleChildScrollView(
                  child: Text(widget.text, style: widget.style),
                ),
              )
            else
              Text(widget.text, style: widget.style),
            if (exceeds)
              if (widget.tvFocusable)
                Padding(padding: const EdgeInsets.only(top: 4), child: more)
              else
                // Con la tastiera: Tab porta qui, Invio apre.
                InkWell(
                  onTap: _expand,
                  focusColor: WfColors.gold.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: more,
                  ),
                ),
          ],
        );
      },
    );
    return widget.tvFocusable
        ? TvFocusable(onActivate: _expand, child: body)
        : body;
  }
}
