import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/core/media_session/mirrored_media_session.dart';

import '../../support/playback_fakes.dart';

class _BrokenSession extends NoopMediaSession {
  @override
  Future<void> setMetadata(
          {required String title, String? subtitle, String? thumbnailUrl}) =>
      Future.error(StateError('rotta'));
}

void main() {
  test('aggiorna tutte le sessioni; tasti solo dalla principale', () async {
    final primary = FakeMediaSession()..handlesMediaKeys = true;
    final mirror = FakeMediaSession();
    final session = MirroredMediaSession(primary: primary, mirrors: [mirror]);

    await session.setMetadata(title: 'Heat', subtitle: '1995');
    await session.setPlaying(false);
    await session.setTimeline(
        position: const Duration(seconds: 3),
        duration: const Duration(hours: 2));
    await session.setNextEnabled(true);
    await session.setPreviousEnabled(false);
    await session.setParty(2);
    await session.clear();

    for (final s in [primary, mirror]) {
      expect(s.metadata.single.title, 'Heat');
      expect(s.playingStates, [false]);
      expect(s.timelines, [const Duration(seconds: 3)]);
      expect(s.nextEnabled, [true]);
      expect(s.previousEnabled, [false]);
      expect(s.parties, [2]);
      expect(s.cleared, 1);
    }
    expect(session.handlesMediaKeys, isTrue);

    final pressed = <MediaButton>[];
    final sub = session.buttons.listen(pressed.add);
    primary.press(MediaButton.pause);
    await Future<void>.delayed(Duration.zero);
    expect(pressed, [MediaButton.pause]);
    await sub.cancel();
  });

  test('l\'errore di una sessione non ferma le altre', () async {
    final mirror = FakeMediaSession();
    final session =
        MirroredMediaSession(primary: _BrokenSession(), mirrors: [mirror]);
    await session.setMetadata(title: 'Heat');
    expect(mirror.metadata.single.title, 'Heat');
  });

  test('dispose non chiude le sessioni (sono dei loro provider)', () async {
    final primary = FakeMediaSession();
    await MirroredMediaSession(primary: primary).dispose();
    expect(primary.disposed, isFalse);
  });
}
