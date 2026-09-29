/// Pulsanti del pannello media di sistema e dei tasti multimediali.
enum MediaButton { play, pause, next, stop }

/// Pannello media di sistema (su Windows: SMTC): titolo, immagine, stato
/// e tasti multimediali, attivi anche con l'app in secondo piano.
abstract class MediaSession {
  Future<void> setMetadata({
    required String title,
    String? subtitle,
    String? thumbnailUrl,
  });

  Future<void> setPlaying(bool playing);

  Future<void> setTimeline({
    required Duration position,
    required Duration duration,
  });

  Future<void> setNextEnabled(bool enabled);

  Stream<MediaButton> get buttons;

  Future<void> dispose();
}

/// Nessun pannello (test, o SMTC non disponibile).
class NoopMediaSession implements MediaSession {
  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {}

  @override
  Future<void> setPlaying(bool playing) async {}

  @override
  Future<void> setTimeline(
      {required Duration position, required Duration duration}) async {}

  @override
  Future<void> setNextEnabled(bool enabled) async {}

  @override
  Stream<MediaButton> get buttons => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
