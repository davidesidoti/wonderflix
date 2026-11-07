import 'dart:async';

import 'package:flutter/services.dart';

import 'player_window.dart';

/// Finestra del player su Android TV: l'app è già a tutto schermo e non ha
/// finestra da nascondere o chiudere, quindi quasi tutto è un no-op.
class TvPlayerWindow implements PlayerWindow {
  final _listeners = <Future<void> Function()>[];

  @override
  bool get supportsFullScreen => false;

  @override
  Future<bool> isFullScreen() async => true;

  @override
  Future<void> setFullScreen(bool value) async {}

  @override
  Stream<bool> get fullScreenChanges => const Stream.empty();

  @override
  Future<void> lockLandscape() async {}

  @override
  Future<void> unlockOrientation() async {}

  @override
  Future<void> setPreventClose(bool value) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> destroy() => SystemNavigator.pop();

  @override
  void addCloseListener(Future<void> Function() onClose) =>
      _listeners.add(onClose);

  @override
  void removeCloseListener(Future<void> Function() onClose) =>
      _listeners.remove(onClose);
}
