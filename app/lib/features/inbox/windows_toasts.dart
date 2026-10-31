// Le notifiche di Windows: su Windows `local_notifier`, nel sito niente
// (lì ci sono le push del browser).
export 'windows_toasts_io.dart' if (dart.library.js_interop) 'windows_toasts_web.dart';

abstract interface class Toasts {
  /// Mostra una notifica; [onClick] quando la si tocca.
  void show(String title, String body, void Function() onClick);
}
