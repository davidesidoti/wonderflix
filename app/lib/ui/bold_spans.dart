import 'package:flutter/painting.dart';

import '../app/theme.dart';

/// [text] con la prima occorrenza di ogni stringa di [bold] in grassetto e
/// color crema; una stringa vuota o che non c'è si ignora.
TextSpan boldSpans(String text, List<String> bold) {
  final found = <(int, String)>[];
  for (final word in bold) {
    final at = word.isEmpty ? -1 : text.indexOf(word);
    if (at >= 0) found.add((at, word));
  }
  if (found.isEmpty) return TextSpan(text: text);
  found.sort((a, b) => a.$1.compareTo(b.$1));
  final children = <TextSpan>[];
  var from = 0;
  for (final (at, word) in found) {
    if (at < from) continue; // sovrapposta a una già evidenziata
    if (at > from) children.add(TextSpan(text: text.substring(from, at)));
    children.add(
      TextSpan(
        text: word,
        style: const TextStyle(
          color: WfColors.cream,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    from = at + word.length;
  }
  if (from < text.length) children.add(TextSpan(text: text.substring(from)));
  return TextSpan(children: children);
}
