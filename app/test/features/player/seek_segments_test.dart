import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/seek_segments.dart';

void main() {
  const hour = Duration(hours: 1);
  const twoHours = Duration(hours: 2);

  group('seekSegments', () {
    test('senza capitoli: una barra sola', () {
      expect(seekSegments(const [], twoHours, 1000),
          const [SeekSegment(Duration.zero, twoHours)]);
    });

    test('un tratto per capitolo; quello all\'inizio non ne apre un altro',
        () {
      expect(
        seekSegments(const [
          ChapterMark(start: Duration.zero, name: 'Inizio'),
          ChapterMark(start: Duration(minutes: 30), name: 'Arrakis'),
          ChapterMark(start: hour, name: 'Deserto'),
        ], twoHours, 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 30)),
          SeekSegment(Duration(minutes: 30), hour),
          SeekSegment(hour, twoHours),
        ],
      );
    });

    test('tratti più corti di 8 px: uniti al precedente', () {
      // 1000 px per 100 min: 1 min = 10 px, 30 s = 5 px.
      expect(
        seekSegments(const [
          ChapterMark(start: Duration(minutes: 10)),
          ChapterMark(start: Duration(minutes: 40)),
          ChapterMark(start: Duration(minutes: 40, seconds: 30)),
        ], const Duration(minutes: 100), 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 10)),
          SeekSegment(Duration(minutes: 10), Duration(minutes: 40, seconds: 30)),
          SeekSegment(
              Duration(minutes: 40, seconds: 30), Duration(minutes: 100)),
        ],
      );
    });

    test('primo tratto troppo corto: unito al successivo', () {
      expect(
        seekSegments(const [
          ChapterMark(start: Duration(seconds: 20)),
          ChapterMark(start: Duration(minutes: 50)),
        ], const Duration(minutes: 100), 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 50)),
          SeekSegment(Duration(minutes: 50), Duration(minutes: 100)),
        ],
      );
    });

    test('capitoli fuori ordine, doppi o oltre la fine', () {
      expect(
        seekSegments(const [
          ChapterMark(start: hour),
          ChapterMark(start: Duration(minutes: 30)),
          ChapterMark(start: Duration(minutes: 30)),
          ChapterMark(start: Duration(hours: 3)),
        ], twoHours, 1000),
        const [
          SeekSegment(Duration.zero, Duration(minutes: 30)),
          SeekSegment(Duration(minutes: 30), hour),
          SeekSegment(hour, twoHours),
        ],
      );
    });

    test('durata non ancora nota: una barra sola', () {
      expect(
          seekSegments(const [ChapterMark(start: hour)], Duration.zero, 1000),
          const [SeekSegment(Duration.zero, Duration.zero)]);
    });
  });

  group('zone', () {
    const segments = [
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(seconds: 55),
          end: Duration(seconds: 130)),
      MediaSegment(
          type: MediaSegmentType.commercial,
          start: Duration(minutes: 10),
          end: Duration(minutes: 11)),
      MediaSegment(
          type: MediaSegmentType.recap,
          start: Duration.zero,
          end: Duration(seconds: 55)),
      MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(minutes: 44),
          end: Duration(minutes: 46)),
      MediaSegment(
          type: MediaSegmentType.intro,
          start: Duration(minutes: 20),
          end: Duration(minutes: 20)),
    ];

    test('solo riassunto, intro e titoli di coda, non vuote', () {
      expect(seekZones(segments), const [
        SeekZone(SeekZoneKind.intro, Duration(seconds: 55),
            Duration(seconds: 130)),
        SeekZone(SeekZoneKind.recap, Duration.zero, Duration(seconds: 55)),
        SeekZone(SeekZoneKind.outro, Duration(minutes: 44),
            Duration(minutes: 46)),
      ]);
    });

    test('zoneAt: inizio compreso, fine esclusa', () {
      final zones = seekZones(segments);
      expect(zoneAt(zones, Duration.zero)?.kind, SeekZoneKind.recap);
      expect(zoneAt(zones, const Duration(seconds: 55))?.kind,
          SeekZoneKind.intro);
      expect(zoneAt(zones, const Duration(seconds: 130)), isNull);
      expect(zoneAt(zones, const Duration(minutes: 10, seconds: 30)), isNull);
    });
  });
}
