import 'dart:async';
import 'dart:js_interop';

import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'player_window.dart';

final _log = Logger('player');

PlayerWindow createPlayerWindow() => WebPlayerWindow();

/// La "finestra" nel browser: schermo intero con la Fullscreen API, chiusura
/// della scheda con `pagehide`. La scheda non si può trattenere né nascondere.
class WebPlayerWindow implements PlayerWindow {
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
    }
  }

  @override
  Future<bool> isFullScreen() async => web.document.fullscreenElement != null;

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
