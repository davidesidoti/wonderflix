import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'player_window.dart';

final _log = Logger('player');

PlayerWindow createPlayerWindow() => WebPlayerWindow();

/// La "finestra" nel browser: schermo intero con la Fullscreen API, chiusura
/// della scheda con `pagehide`. La scheda non si può trattenere né nascondere.
class WebPlayerWindow implements PlayerWindow {
  WebPlayerWindow() {
    // La finestra vive quanto l'app: l'ascoltatore non si toglie.
    web.EventStreamProviders.fullscreenChangeEvent
        .forTarget(web.document)
        .listen((_) => _fullScreenChanges.add(_active));
  }

  final _fullScreenChanges = StreamController<bool>.broadcast();
  final _listeners = <Future<void> Function(), StreamSubscription<web.Event>>{};

  @override
  Future<void> setFullScreen(bool value) async {
    try {
      if (value) {
        await web.document.documentElement?.requestFullscreen().toDart;
      } else if (web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      }
    } on Object catch (error) {
      // Il browser lo rifiuta, per esempio senza un gesto dell'utente.
      _log.warning('schermo intero rifiutato: $error');
      _fullScreenChanges.add(_active);
    }
  }

  @override
  Future<bool> isFullScreen() async => _active;

  bool get _active => web.document.fullscreenElement != null;

  @override
  bool get supportsFullScreen {
    // Letto come valore JS: su iPhone l'attributo può mancare (`undefined`),
    // e il getter tipato di `package:web` lancerebbe con wasm.
    try {
      final enabled =
          web.document.getProperty<JSAny?>('fullscreenEnabled'.toJS);
      return enabled.isA<JSBoolean>() && (enabled as JSBoolean).toDart;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> lockLandscape() async {
    try {
      await web.window.screen.orientation.lock('landscape').toDart;
    } on Object catch (error) {
      // Il computer, Safari, o fuori dallo schermo intero: si resta così.
      _log.fine('orientamento non bloccato: $error');
    }
  }

  @override
  Future<void> unlockOrientation() async {
    try {
      web.window.screen.orientation.unlock();
    } on Object catch (error) {
      _log.fine('orientamento non sbloccato: $error');
    }
  }

  @override
  Stream<bool> get fullScreenChanges => _fullScreenChanges.stream;

  @override
  Future<void> setPreventClose(bool value) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> destroy() async {}

  @override
  void addCloseListener(Future<void> Function() onClose) {
    removeCloseListener(onClose);
    _listeners[onClose] = web.EventStreamProviders.pageHideEvent
        .forTarget(web.window)
        .listen((_) => unawaited(onClose()));
  }

  @override
  void removeCloseListener(Future<void> Function() onClose) =>
      unawaited(_listeners.remove(onClose)?.cancel());
}
