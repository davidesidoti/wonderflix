import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

/// Schermo intero della finestra con il codice nativo di `media_kit_video`.
///
/// `windowManager.setFullScreen` lascia barra del titolo e bordo se la
/// finestra è massimizzata (issue #2); media_kit toglie tutto
/// `WS_OVERLAPPEDWINDOW` e all'uscita rimette la finestra com'era.
class NativeFullScreen {
  bool _active = false;

  /// `true` tra [enter] e [exit].
  bool get active => _active;

  /// Lo stato cambia prima della chiamata nativa: due richieste ravvicinate
  /// non arrivano due volte al codice nativo.
  Future<void> enter() async {
    if (_active) return;
    _active = true;
    await defaultEnterNativeFullscreen();
  }

  Future<void> exit() async {
    if (!_active) return;
    _active = false;
    await defaultExitNativeFullscreen();
  }
}

/// Una sola finestra: lo stato è condiviso dal player e dal salvataggio
/// della posizione (`window_setup.dart`).
final nativeFullScreen = NativeFullScreen();
