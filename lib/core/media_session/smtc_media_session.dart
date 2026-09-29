import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'media_session.dart';

/// [MediaSession] sul pannello media di Windows (System Media Transport
/// Controls). Richiede `SMTCWindows.initialize()` all'avvio.
///
/// Il pannello parte disattivato: lo accende il primo [setMetadata] e lo
/// spegne [clear].
class SmtcMediaSession implements MediaSession {
  SmtcMediaSession()
      : _smtc = SMTCWindows(
          enabled: false,
          config: const SMTCConfig(
            playEnabled: true,
            pauseEnabled: true,
            stopEnabled: true,
            nextEnabled: false,
            prevEnabled: false,
            fastForwardEnabled: false,
            rewindEnabled: false,
          ),
        );

  final SMTCWindows _smtc;
  bool _enabled = false;

  /// Le chiamate al pannello vanno in ordine: un [clear] seguito subito da
  /// un [setMetadata] (uscita e rientro nel player) non deve lasciarlo spento.
  Future<void> _queue = Future.value();

  Future<void> _run(Future<void> Function() action) {
    final next = _queue.then((_) async {
      try {
        await action();
      } on Object catch (e) {
        // Il pannello è accessorio: un suo errore non deve fermare il player.
        debugPrint('SMTC: $e');
      }
    });
    _queue = next;
    return next;
  }

  @override
  bool get handlesMediaKeys => true;

  @override
  Future<void> setMetadata(
          {required String title, String? subtitle, String? thumbnailUrl}) =>
      _run(() async {
        if (!_enabled) {
          await _smtc.enableSmtc();
          _enabled = true;
        }
        await _smtc.updateMetadata(MusicMetadata(
            title: title, artist: subtitle, thumbnail: thumbnailUrl));
      });

  @override
  Future<void> setPlaying(bool playing) => _run(() => _smtc.setPlaybackStatus(
      playing ? PlaybackStatus.playing : PlaybackStatus.paused));

  @override
  Future<void> setTimeline(
          {required Duration position, required Duration duration}) =>
      _run(() => _smtc.updateTimeline(PlaybackTimeline(
            startTimeMs: 0,
            endTimeMs: duration.inMilliseconds,
            positionMs: position.inMilliseconds,
            minSeekTimeMs: 0,
            maxSeekTimeMs: duration.inMilliseconds,
          )));

  @override
  Future<void> setNextEnabled(bool enabled) =>
      _run(() => _smtc.setIsNextEnabled(enabled));

  /// Broadcast come quello di smtc_windows: durante il passaggio
  /// all'episodio successivo ascoltano due schermate.
  @override
  Stream<MediaButton> get buttons => _smtc.buttonPressStream
      // Pulsanti che smtc_windows non conosce: ignorati.
      .handleError((Object error) => debugPrint('SMTC: $error'))
      .map(_button)
      .where((button) => button != null)
      .cast<MediaButton>();

  static MediaButton? _button(PressedButton button) => switch (button) {
        PressedButton.play => MediaButton.play,
        PressedButton.pause => MediaButton.pause,
        PressedButton.next => MediaButton.next,
        PressedButton.stop => MediaButton.stop,
        _ => null,
      };

  @override
  Future<void> clear() => _run(() async {
        await _smtc.clearMetadata();
        await _smtc.setPlaybackStatus(PlaybackStatus.stopped);
        await _smtc.disableSmtc();
        _enabled = false;
      });

  @override
  Future<void> dispose() => _run(() async {
        await _smtc.disableSmtc();
        _enabled = false;
        await _smtc.dispose();
      });
}
