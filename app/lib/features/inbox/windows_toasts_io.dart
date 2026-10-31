import 'dart:async';

import 'package:local_notifier/local_notifier.dart';
import 'package:logging/logging.dart';

import 'windows_toasts.dart';

final _log = Logger('social');

Toasts createToasts() => const _WindowsToasts();

class _WindowsToasts implements Toasts {
  const _WindowsToasts();

  @override
  void show(String title, String body, void Function() onClick) {
    final toast = LocalNotification(title: title, body: body);
    // `local_notifier` tiene ogni notifica tra i suoi ascoltatori finché non
    // la si toglie. Scaduta resta: dal centro notifiche si può ancora toccare.
    toast.onClick = () {
      localNotifier.removeListener(toast);
      onClick();
    };
    toast.onClose = (reason) {
      if (reason == LocalNotificationCloseReason.userCanceled) {
        localNotifier.removeListener(toast);
      }
    };
    // Una notifica che non parte non deve fermare l'app.
    unawaited(toast.show().catchError((Object error) {
      _log.info('notifica di Windows non mostrata: ${error.runtimeType}');
    }));
  }
}
