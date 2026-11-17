import 'package:flutter/painting.dart';

import '../app/theme.dart';

/// [text] con un'occorrenza di ogni stringa di [bold] in grassetto e color
/// crema: la prima che non si sovrappone a una già evidenziata (a parità di
/// posizione vince la più lunga). Una stringa ripetuta prende l'occorrenza
/// dopo; una vuota o che non c'è si ignora.
TextSpan boldSpans(String text, List<String> bold) {
  final words = [...bold]..removeWhere((w) => w.isEmpty);
  final children = <TextSpan>[];
  var from = 0;
  while (words.isNotEmpty) {
    String? next;
    var nextAt = -1;
    for (final word in words) {
      final at = text.indexOf(word, from);
      if (at < 0) continue;
      if (next == null ||
          at < nextAt ||
          (at == nextAt && word.length > next.length)) {
        next = word;
        nextAt = at;
      }
    }
    if (next == null) break;
    words.remove(next);
    if (nextAt > from) {
      children.add(TextSpan(text: text.substring(from, nextAt)));
    }
    children.add(
      TextSpan(
        text: next,
        style: const TextStyle(
          color: WfColors.cream,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    from = nextAt + next.length;
  }
  if (children.isEmpty) return TextSpan(text: text);
  if (from < text.length) children.add(TextSpan(text: text.substring(from)));
  return TextSpan(children: children);
}
