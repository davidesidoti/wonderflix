// Le notifiche push del browser (spec V §4.3): nel sito la Push API, su
// Windows niente (`unsupported`).
export 'web_push_io.dart' if (dart.library.js_interop) 'web_push_web.dart';

/// Cosa può fare questo dispositivo con le notifiche push.
enum PushAvailability {
  /// Il browser non ha la Push API (o è l'app Windows).
  unsupported,

  /// iPhone/iPad: le push arrivano solo al sito aggiunto alla schermata Home.
  needsHomeScreen,

  /// Il permesso è stato negato.
  denied,

  /// Si possono attivare.
  ready,

  /// Attive per il profilo aperto.
  active,
}

/// Le chiavi di un `PushSubscription`, in base64url come le vuole il plugin.
class PushKeys {
  const PushKeys({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}

abstract interface class WebPush {
  /// Il percorso del service worker (la cartella del sito, es.
  /// `/wonderflix/`): il sito pubblico e quello di prova hanno la stessa
  /// origine ma iscrizioni diverse.
  String get scope;

  /// `active` se il browser ha già un'iscrizione (di qualunque profilo).
  Future<PushAvailability> availability();

  /// Chiede il permesso (come prima cosa: su iOS solo dentro il tocco),
  /// registra `push_sw.js` e iscrive il browser. `null` senza permesso.
  Future<PushKeys?> subscribe(String vapidPublicKey);

  /// Toglie l'iscrizione del browser.
  Future<void> unsubscribeBrowser();
}
