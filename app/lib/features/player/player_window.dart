import 'dart:async';

import 'package:window_manager/window_manager.dart';

import '../../core/system/native_fullscreen.dart';

/// Operazioni sulla finestra usate dal player (sostituibili nei test).
abstract class PlayerWindow {
  Future<void> setFullScreen(bool value);

  Future<bool> isFullScreen();

  /// `false` dove lo schermo intero non c'è (Safari su iPhone): il player
  /// non mostra il pulsante.
  bool get supportsFullScreen;

  /// Blocca lo schermo in orizzontale (telefono a schermo intero). Se il
  /// browser non lo permette non succede niente.
  Future<void> lockLandscape();

  Future<void> unlockOrientation();

  /// Schermo intero cambiato da fuori (nel browser: Esc o richiesta
  /// rifiutata). Su Windows non emette: lo cambia solo il player.
  Stream<bool> get fullScreenChanges;

  /// Con `true` la finestra non si chiude da sola: vengono chiamati gli
  /// ascoltatori di [addCloseListener], che poi devono chiamare [destroy].
  /// Ogni `true` va bilanciato da un `false`: la chiusura torna libera solo
  /// dopo l'ultimo.
  Future<void> setPreventClose(bool value);

  /// Nasconde la finestra. L'app resta viva finché non si chiama [destroy].
  Future<void> hide();

  Future<void> destroy();

  void addCloseListener(Future<void> Function() onClose);

  void removeCloseListener(Future<void> Function() onClose);
}

class WindowManagerPlayerWindow implements PlayerWindow {
  WindowManagerPlayerWindow({NativeFullScreen? fullScreen})
      : _fullScreen = fullScreen ?? nativeFullScreen;

  /// Schermo intero nativo: quello di `window_manager` a finestra
  /// massimizzata lascia la barra del titolo (issue #2).
  final NativeFullScreen _fullScreen;

  final _listeners = <Future<void> Function(), _CloseListener>{};

  /// Richieste di [setPreventClose] attive. Un nuovo player può montarsi
  /// prima che il precedente venga smontato: la chiusura resta bloccata
  /// finché l'ultimo non la rilascia.
  int _preventCloseRequests = 0;

  @override
  Future<void> setFullScreen(bool value) =>
      value ? _fullScreen.enter() : _fullScreen.exit();

  @override
  Future<bool> isFullScreen() async => _fullScreen.active;

  @override
  Stream<bool> get fullScreenChanges => const Stream.empty();

  @override
  bool get supportsFullScreen => true;

  @override
  Future<void> lockLandscape() async {}

  @override
  Future<void> unlockOrientation() async {}

  @override
  Future<void> setPreventClose(bool value) async {
    if (value) {
      if (_preventCloseRequests++ == 0) {
        await windowManager.setPreventClose(true);
      }
    } else if (_preventCloseRequests > 0) {
      if (--_preventCloseRequests == 0) {
        await windowManager.setPreventClose(false);
      }
    }
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> destroy() => windowManager.destroy();

  @override
  void addCloseListener(Future<void> Function() onClose) {
    final listener = _CloseListener(onClose);
    _listeners[onClose] = listener;
    windowManager.addListener(listener);
  }

  @override
  void removeCloseListener(Future<void> Function() onClose) {
    final listener = _listeners.remove(onClose);
    if (listener != null) windowManager.removeListener(listener);
  }
}

class _CloseListener with WindowListener {
  _CloseListener(this._onClose);

  final Future<void> Function() _onClose;

  @override
  void onWindowClose() => unawaited(_onClose());
}
