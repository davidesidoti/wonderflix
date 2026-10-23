import 'player_window.dart';

PlayerWindow createPlayerWindow() => _BrowserPlayerWindow();

/// Provvisorio: nel browser non c'è una finestra da gestire. Lo schermo
/// intero arriva con il player web (piano 27).
class _BrowserPlayerWindow implements PlayerWindow {
  @override
  Future<void> setFullScreen(bool value) async {}

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<void> setPreventClose(bool value) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> destroy() async {}

  @override
  void addCloseListener(Future<void> Function() onClose) {}

  @override
  void removeCloseListener(Future<void> Function() onClose) {}
}
