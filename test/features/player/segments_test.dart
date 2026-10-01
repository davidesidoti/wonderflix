import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/playback_models.dart';
import 'package:wonderflix/features/player/segments.dart';

void main() {
  const recap = MediaSegment(
      type: MediaSegmentType.recap,
      start: Duration.zero,
      end: Duration(seconds: 8));
  const intro = MediaSegment(
      type: MediaSegmentType.intro,
      start: Duration(seconds: 10),
      end: Duration(seconds: 90));
  const outro = MediaSegment(
      type: MediaSegmentType.outro,
      start: Duration(minutes: 40),
      end: Duration(minutes: 42));
  const all = [recap, intro, outro];

  test('pulsante durante riassunto e intro', () {
    expect(skipTargetAt(all, const Duration(seconds: 3))?.kind, SkipKind.recap);
    final target = skipTargetAt(all, const Duration(seconds: 20));
    expect(target?.kind, SkipKind.intro);
    expect(target?.end, const Duration(seconds: 90));
    expect(skipTargetAt(all, const Duration(seconds: 89, milliseconds: 500)),
        isNull,
        reason: 'nell\'ultimo secondo il pulsante non serve');
    expect(skipTargetAt(all, const Duration(minutes: 41)), isNull,
        reason: 'i crediti portano alla scheda, non al pulsante');
    expect(skipTargetAt(const [], Duration.zero), isNull);
  });

  test('scheda del prossimo episodio: crediti o ultimi 30 s', () {
    expect(nextEpisodeCardFrom([intro, outro], const Duration(minutes: 42)),
        const Duration(minutes: 40));
    expect(nextEpisodeCardFrom([intro], const Duration(minutes: 42)),
        const Duration(minutes: 41, seconds: 30));
    expect(nextEpisodeCardFrom(const [], const Duration(seconds: 20)),
        Duration.zero);
    expect(nextEpisodeCardFrom(const [], Duration.zero), isNull,
        reason: 'durata non ancora nota');
  });

  group('fine episodio', () {
    const outro = MediaSegment(
        type: MediaSegmentType.outro,
        start: Duration(minutes: 40),
        end: Duration(minutes: 42));
    const duration = Duration(minutes: 42);

    test('outroStart: solo un Outro che non parte da 0', () {
      expect(outroStart(const [outro]), const Duration(minutes: 40));
      expect(outroStart(const []), isNull);
      expect(
          outroStart(const [
            MediaSegment(
                type: MediaSegmentType.outro,
                start: Duration.zero,
                end: Duration(minutes: 1)),
          ]),
          isNull);
    });

    test('con i titoli noti: zona dei titoli dall\'inizio dell\'Outro', () {
      expect(endZoneAt(const [outro], duration, const Duration(minutes: 39)),
          EndZone.none);
      expect(endZoneAt(const [outro], duration, const Duration(minutes: 40)),
          EndZone.credits);
      expect(
          endZoneAt(const [outro], duration,
              const Duration(minutes: 41, seconds: 45)),
          EndZone.credits,
          reason: 'anche negli ultimi 30 s: post-play, non la scheda');
    });

    test('senza titoli noti: ultimi 30 s', () {
      expect(
          endZoneAt(
              const [], duration, const Duration(minutes: 41, seconds: 29)),
          EndZone.none);
      expect(
          endZoneAt(
              const [], duration, const Duration(minutes: 41, seconds: 30)),
          EndZone.lastSeconds);
      expect(endZoneAt(const [], Duration.zero, const Duration(minutes: 1)),
          EndZone.none,
          reason: 'durata ancora ignota');
    });

    test('un Outro che parte da 0 non vale: ultimi 30 s', () {
      const fromZero = MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration.zero,
          end: Duration(minutes: 42));
      expect(
          endZoneAt(const [fromZero], duration,
              const Duration(minutes: 41, seconds: 30)),
          EndZone.lastSeconds);
    });

    test('con i titoli noti la durata non serve', () {
      expect(endZoneAt(const [outro], Duration.zero, const Duration(minutes: 40)),
          EndZone.credits);
    });

    test('più Outro: vale il primo valido', () {
      const fromZero = MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration.zero,
          end: Duration(minutes: 1));
      const later = MediaSegment(
          type: MediaSegmentType.outro,
          start: Duration(minutes: 41),
          end: Duration(minutes: 42));
      expect(
          endZoneAt(const [outro, later], duration,
              const Duration(minutes: 40, seconds: 30)),
          EndZone.credits,
          reason: 'il primo, alle 40:00');
      expect(
          endZoneAt(const [later, outro], duration,
              const Duration(minutes: 40, seconds: 30)),
          EndZone.none,
          reason: 'il primo nella lista, alle 41:00');
      expect(
          endZoneAt(const [fromZero, outro], duration,
              const Duration(minutes: 40)),
          EndZone.credits,
          reason: 'quello da 0 non conta');
    });
  });
}
