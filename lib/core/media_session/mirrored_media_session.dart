import 'package:logging/logging.dart';

import 'media_session.dart';

final _log = Logger('media');

/// Inoltra gli aggiornamenti a più sessioni. [primary] (il pannello di
/// sistema) riceve anche i tasti; le [mirrors] (es. Discord) solo lo stato.
/// L'errore di una sessione non ferma le altre.
///
/// Non chiude le sessioni: le chiude il provider che le ha create.
class MirroredMediaSession implements MediaSession {
  MirroredMediaSession({required this.primary, this.mirrors = const []});

  final MediaSession primary;
  final List<MediaSession> mirrors;

  Future<void> _all(Future<void> Function(MediaSession session) action) =>
      Future.wait([
        for (final session in [primary, ...mirrors])
          () async {
            try {
              await action(session);
            } on Object catch (error) {
              _log.warning('sessione media: $error');
            }
          }(),
      ]);

  @override
  bool get handlesMediaKeys => primary.handlesMediaKeys;

  @override
  Stream<MediaButton> get buttons => primary.buttons;

  @override
  Future<void> setMetadata(
          {required String title, String? subtitle, String? thumbnailUrl}) =>
      _all((s) => s.setMetadata(
          title: title, subtitle: subtitle, thumbnailUrl: thumbnailUrl));

  @override
  Future<void> setPlaying(bool playing) => _all((s) => s.setPlaying(playing));

  @override
  Future<void> setTimeline(
          {required Duration position, required Duration duration}) =>
      _all((s) => s.setTimeline(position: position, duration: duration));

  @override
  Future<void> setNextEnabled(bool enabled) =>
      _all((s) => s.setNextEnabled(enabled));

  @override
  Future<void> setParty(int? members) => _all((s) => s.setParty(members));

  @override
  Future<void> clear() => _all((s) => s.clear());

  @override
  Future<void> dispose() async {}
}
