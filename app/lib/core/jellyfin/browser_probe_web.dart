import 'package:web/web.dart' as web;

import '../platform/browser_name.dart';
import 'browser_profile.dart';

/// Chiede al browser cosa sa leggere, con le stringhe di
/// `browserDeviceProfile.js` di jellyfin-web.
BrowserCapabilities probeBrowser() {
  final video = web.document.createElement('video') as web.HTMLVideoElement;
  bool mse(String type) {
    try {
      return web.MediaSource.isTypeSupported(type);
    } catch (_) {
      return false; // Senza MediaSource (es. Safari su iPhone).
    }
  }

  bool can(String type) => video.canPlayType(type).isNotEmpty || mse(type);

  final userAgent = web.window.navigator.userAgent;
  final isFirefox = describeBrowser(userAgent) == 'Firefox';
  final nativeHls = video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;
  final h264 = can('video/mp4; codecs="avc1.640029"');
  return BrowserCapabilities(
    h264: h264,
    // Stringhe complete (profilo, compatibilità, livello, vincoli): Chrome
    // risponde "" alle forme corte come `hvc1.1.L120`.
    hevc: can('video/mp4; codecs="hvc1.1.6.L120.90"') ||
        can('video/mp4; codecs="hev1.1.6.L120.90"'),
    hevcMain10: can('video/mp4; codecs="hvc1.2.4.L153.B0"') ||
        can('video/mp4; codecs="hev1.2.4.L153.B0"'),
    vp9: can('video/webm; codecs="vp9"'),
    av1: can('video/mp4; codecs="av01.0.08M.08"'),
    aac: can('audio/mp4; codecs="mp4a.40.2"'),
    mp3: can('audio/mpeg'),
    opus: can('audio/webm; codecs="opus"'),
    flac: can('audio/mp4; codecs="flac"'),
    ac3: can('audio/mp4; codecs="ac-3"'),
    eac3: can('audio/mp4; codecs="ec-3"'),
    // jellyfin-web spegne l'MKV su Firefox (bug del precaricamento).
    mkv: !isFirefox && (can('video/x-matroska') || can('video/mkv')),
    // Firefox 149 ha un bug sui tfdt dei segmenti fMP4: lì si usa il TS.
    fmp4Hls: (nativeHls || mse('video/mp4; codecs="avc1.640029"')) &&
        !userAgent.contains('Firefox/149.'),
    nativeHls: nativeHls,
    isFirefox: isFirefox,
  );
}
