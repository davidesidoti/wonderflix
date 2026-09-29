import 'dart:async';

import 'package:window_manager/window_manager.dart';

/// Operazioni sulla finestra usate dal player (sostituibili nei test).
abstract class PlayerWindow {
  Future<void> setFullScreen(bool value);

  /// Con `true` la finestra non si chiude da sola: vengono chiamati gli
  /// ascoltatori di [addCloseListener], che poi devono chiamare [destroy].
  Future<void> setPreventClose(bool value);

  Future<void> destroy();

  void addCloseListener(Future<void> Function() onClose);

  void removeCloseListener(Future<void> Function() onClose);
}

class WindowManagerPlayerWindow implements PlayerWindow {
  final _listeners = <Future<void> Function(), _CloseListener>{};

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<void> setPreventClose(bool value) =>
      windowManager.setPreventClose(value);

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
