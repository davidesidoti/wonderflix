/// Come il browser disegna un sottotitolo esterno.
enum SubtitleKind { text, ass, pgs, vobsub }

/// Tipo dall'estensione dell'ultimo segmento del percorso (`Stream.<ext>`);
/// `null` se il browser non lo sa disegnare.
SubtitleKind? subtitleKindForUrl(String url) {
  final segments = Uri.tryParse(url)?.pathSegments ?? const [];
  final name = segments.isEmpty ? '' : segments.last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'vtt' || 'webvtt' || 'srt' || 'subrip' => SubtitleKind.text,
    'ass' || 'ssa' => SubtitleKind.ass,
    'sup' || 'pgs' || 'pgssub' => SubtitleKind.pgs,
    'sub' || 'idx' || 'mks' || 'dvdsub' => SubtitleKind.vobsub,
    _ => null,
  };
}
