import 'package:flutter/foundation.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/playback_models.dart';

/// Spazio tra due tratti della barra (spec D §8.1).
const seekSegmentGap = 3.0;

/// Un tratto più corto di così, sullo schermo, si unisce al precedente.
const seekSegmentMinWidth = 8.0;

/// Un tratto della barra: un capitolo (o più, uniti) o tutta la barra.
@immutable
class SeekSegment {
  const SeekSegment(this.start, this.end);

  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is SeekSegment && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SeekSegment($start, $end)';
}

/// Tratti della barra per [chapters] su una traccia larga [trackWidth] px
/// (spec D §8.1): un tratto per capitolo; i tratti più corti di
/// [seekSegmentMinWidth] si uniscono al precedente (il primo al
/// successivo). Senza durata o capitoli: un tratto solo.
List<SeekSegment> seekSegments(
    List<ChapterMark> chapters, Duration duration, double trackWidth) {
  if (duration <= Duration.zero) return [SeekSegment(Duration.zero, duration)];
  final starts = {
    for (final chapter in chapters)
      if (chapter.start > Duration.zero && chapter.start < duration)
        chapter.start,
  }.toList()
    ..sort();
  final bounds = [Duration.zero, ...starts, duration];
  double width(SeekSegment segment) =>
      (segment.end - segment.start).inMicroseconds /
      duration.inMicroseconds *
      trackWidth;
  final merged = <SeekSegment>[];
  for (var i = 0; i + 1 < bounds.length; i++) {
    final segment = SeekSegment(bounds[i], bounds[i + 1]);
    if (merged.isNotEmpty && width(segment) < seekSegmentMinWidth) {
      merged.last = SeekSegment(merged.last.start, segment.end);
    } else {
      merged.add(segment);
    }
  }
  // Il primo non ha un precedente: se è troppo corto va con il successivo.
  if (merged.length > 1 && width(merged.first) < seekSegmentMinWidth) {
    merged.replaceRange(
        0, 2, [SeekSegment(merged[0].start, merged[1].end)]);
  }
  return merged;
}

/// Parti che Jellyfin conosce e che la barra mostra rigate (spec D §8.3).
enum SeekZoneKind { recap, intro, outro }

@immutable
class SeekZone {
  const SeekZone(this.kind, this.start, this.end);

  final SeekZoneKind kind;
  final Duration start;
  final Duration end;

  /// Inizio compreso, fine esclusa.
  bool contains(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is SeekZone &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'SeekZone($kind, $start, $end)';
}

/// Zone della barra dai segmenti di Jellyfin: solo `Recap`, `Intro` e
/// `Outro`, e solo se non vuote.
List<SeekZone> seekZones(List<MediaSegment> segments) {
  final zones = <SeekZone>[];
  for (final segment in segments) {
    final kind = switch (segment.type) {
      MediaSegmentType.recap => SeekZoneKind.recap,
      MediaSegmentType.intro => SeekZoneKind.intro,
      MediaSegmentType.outro => SeekZoneKind.outro,
      _ => null,
    };
    if (kind != null && segment.end > segment.start) {
      zones.add(SeekZone(kind, segment.start, segment.end));
    }
  }
  return zones;
}

/// Zona in cui cade [position]; `null` = nessuna.
SeekZone? zoneAt(List<SeekZone> zones, Duration position) {
  for (final zone in zones) {
    if (zone.contains(position)) return zone;
  }
  return null;
}
