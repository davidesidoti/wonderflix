import '../../core/jellyfin/playback_models.dart';

enum SkipKind { intro, recap }

/// Segmento che si può saltare con il pulsante.
class SkipTarget {
  const SkipTarget(this.kind, this.segment);

  final SkipKind kind;
  final MediaSegment segment;

  Duration get end => segment.end;
}

/// Ultimo tratto di un intro o di un riassunto in cui il salto non si
/// propone più (si sta già uscendo): il pulsante sparisce questo tempo prima
/// della fine del segmento, e la sua linea arriva a zero proprio allora.
const skipOfferTail = Duration(seconds: 1);

/// Intro o riassunto in corso in [position]. Nell'ultimo [skipOfferTail]
/// del segmento non si propone più il salto.
SkipTarget? skipTargetAt(List<MediaSegment> segments, Duration position) {
  for (final segment in segments) {
    final kind = switch (segment.type) {
      MediaSegmentType.intro => SkipKind.intro,
      MediaSegmentType.recap => SkipKind.recap,
      _ => null,
    };
    if (kind == null) continue;
    if (position >= segment.start && position < segment.end - skipOfferTail) {
      return SkipTarget(kind, segment);
    }
  }
  return null;
}

/// Inizio dei titoli di coda (`Outro`) se Jellyfin li conosce; `null`
/// altrimenti (spec D §12).
Duration? outroStart(List<MediaSegment> segments) {
  for (final segment in segments) {
    if (segment.type == MediaSegmentType.outro &&
        segment.start > Duration.zero) {
      return segment.start;
    }
  }
  return null;
}

/// Da quando si propone il prossimo episodio (e l'episodio lasciato conta
/// come visto): inizio dei titoli di coda, altrimenti gli ultimi 30 s.
/// `null` se la durata non è ancora nota.
Duration? nextEpisodeCardFrom(List<MediaSegment> segments, Duration duration) {
  final outro = outroStart(segments);
  if (outro != null) return outro;
  if (duration <= Duration.zero) return null;
  final from = duration - const Duration(seconds: 30);
  return from < Duration.zero ? Duration.zero : from;
}

/// Dove si è rispetto alla fine dell'episodio (spec D §12).
enum EndZone {
  /// Prima della fine.
  none,

  /// Nei titoli di coda noti (`Outro`): post-play.
  credits,

  /// Negli ultimi 30 s, senza titoli noti: scheda piccola.
  lastSeconds,
}

/// Zona di fine in [position]. Con un `Outro` noto la durata non conta: i
/// titoli vincono anche negli ultimi 30 s (e senza durata). Un `Outro` che
/// parte da 0 non vale ([outroStart]): si usano gli ultimi 30 s.
EndZone endZoneAt(
    List<MediaSegment> segments, Duration duration, Duration position) {
  final outro = outroStart(segments);
  if (outro != null) {
    return position >= outro ? EndZone.credits : EndZone.none;
  }
  final from = nextEpisodeCardFrom(segments, duration);
  return from != null && position >= from
      ? EndZone.lastSeconds
      : EndZone.none;
}
