import 'windows_toasts.dart';

/// Nel sito niente notifiche di Windows.
Toasts createToasts() => const _NoToasts();

class _NoToasts implements Toasts {
  const _NoToasts();

  @override
  void show(String title, String body, void Function() onClick) {}
}
