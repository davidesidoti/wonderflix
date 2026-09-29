import '../../core/jellyfin/playback_models.dart';

enum SkipKind { intro, recap }

/// Segmento che si può saltare con il pulsante.
class SkipTarget {
  const SkipTarget(this.kind, this.segment);

  final SkipKind kind;
  final MediaSegment segment;

  Duration get end => segment.end;
}

/// Intro o riassunto in corso in [position]. Nell'ultimo secondo del
/// segmento non si propone più il salto (si sta già uscendo).
SkipTarget? skipTargetAt(List<MediaSegment> segments, Duration position) {
  for (final segment in segments) {
    final kind = switch (segment.type) {
      MediaSegmentType.intro => SkipKind.intro,
      MediaSegmentType.recap => SkipKind.recap,
      _ => null,
    };
    if (kind == null) continue;
    if (position >= segment.start &&
        position < segment.end - const Duration(seconds: 1)) {
      return SkipTarget(kind, segment);
    }
  }
  return null;
}

/// Da quando mostrare la scheda "Prossimo episodio": inizio dei crediti
/// (Outro), altrimenti gli ultimi 30 secondi. `null` se la durata non è
/// ancora nota.
Duration? nextEpisodeCardFrom(List<MediaSegment> segments, Duration duration) {
  for (final segment in segments) {
    if (segment.type == MediaSegmentType.outro && segment.start > Duration.zero) {
      return segment.start;
    }
  }
  if (duration <= Duration.zero) return null;
  final from = duration - const Duration(seconds: 30);
  return from < Duration.zero ? Duration.zero : from;
}
