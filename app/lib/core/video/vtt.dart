class VttCue {
  const VttCue(this.start, this.end, this.text);

  final Duration start, end;
  final String text;
}

final _timing = RegExp(
  r'^((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})',
);
final _tag = RegExp(r'<[^>]*>');

/// Cue di un WebVTT o di un SRT. I blocchi senza tempi (intestazione,
/// `NOTE`, `STYLE`) si saltano, come gli identificatori prima dei tempi.
List<VttCue> parseVtt(String source) {
  final cues = <VttCue>[];
  final blocks = source
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split(RegExp(r'\n{2,}'));
  for (final block in blocks) {
    final lines = block.split('\n');
    final at = lines.indexWhere((line) => _timing.hasMatch(line.trim()));
    // In un blocco NOTE o STYLE una riga con `-->` non è un cue.
    if (at < 0 || at > 1) continue;
    final match = _timing.firstMatch(lines[at].trim())!;
    final text = lines
        .skip(at + 1)
        .map((line) => line.replaceAll(_tag, ''))
        .join('\n')
        .trim();
    if (text.isEmpty) continue;
    cues.add(VttCue(_time(match[1]!), _time(match[2]!), text));
  }
  return cues;
}

Duration _time(String value) {
  final parts = value.replaceAll(',', '.').split(':');
  final seconds = parts.removeLast().split('.');
  final hours = parts.length == 2 ? int.parse(parts.first) : 0;
  return Duration(
    hours: hours,
    minutes: int.parse(parts.last),
    seconds: int.parse(seconds[0]),
    milliseconds: int.parse(seconds[1].padRight(3, '0')),
  );
}
