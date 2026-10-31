import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_push.dart';

/// Nel browser: la Push API con `push_sw.js`, l'unico service worker del
/// sito (scope: la cartella del sito).
WebPush createWebPush() => const _BrowserPush();

class _BrowserPush implements WebPush {
  const _BrowserPush();

  web.Navigator get _navigator => web.window.navigator;

  /// Dal `<base href>`, come lo scope di `push_sw.js`.
  @override
  String get scope => Uri.parse(web.document.baseURI).path;

  /// iPhone/iPad: `navigator.standalone` c'è solo su iOS (un Mac non ha
  /// tocco).
  bool get _isIos =>
      _navigator.has('standalone') && _navigator.maxTouchPoints > 0;

  bool get _hasPush =>
      web.window.has('PushManager') &&
      web.window.has('Notification') &&
      _navigator.has('serviceWorker');

  /// La registrazione dello scope della pagina, se c'è.
  Future<web.ServiceWorkerRegistration?> _registration() async =>
      _hasPush ? await _navigator.serviceWorker.getRegistration().toDart : null;

  @override
  Future<PushAvailability> availability() async {
    final ios = _isIos;
    if (ios && _navigator.getProperty<JSBoolean?>('standalone'.toJS)?.toDart != true) {
      return PushAvailability.needsHomeScreen;
    }
    if (!_hasPush) {
      return ios ? PushAvailability.needsHomeScreen : PushAvailability.unsupported;
    }
    if (web.Notification.permission == 'denied') return PushAvailability.denied;
    final registration = await _registration();
    final subscription =
        await registration?.pushManager.getSubscription().toDart;
    return subscription == null ? PushAvailability.ready : PushAvailability.active;
  }

  @override
  Future<PushKeys?> subscribe(String vapidPublicKey) async {
    // Prima di ogni await: su iOS il permesso si chiede solo dentro il tocco.
    final permission = web.Notification.requestPermission();
    if ((await permission.toDart).toDart != 'granted') return null;
    final container = _navigator.serviceWorker;
    // Relativo al <base href>: lo scope è la cartella del sito.
    await container.register('push_sw.js'.toJS).toDart;
    final registration = await container.ready.toDart;
    final key = base64Url.decode(base64Url.normalize(vapidPublicKey));
    final subscription = await registration.pushManager
        .subscribe(web.PushSubscriptionOptionsInit(
          userVisibleOnly: true,
          applicationServerKey: key.toJS,
        ))
        .toDart;
    return PushKeys(
      endpoint: subscription.endpoint,
      p256dh: _key(subscription, 'p256dh'),
      auth: _key(subscription, 'auth'),
    );
  }

  /// In base64url senza `=`, come `PushSubscription.toJSON()`.
  static String _key(web.PushSubscription subscription, String name) {
    final buffer = subscription.getKey(name);
    if (buffer == null) throw StateError('chiave $name mancante');
    return base64Url.encode(buffer.toDart.asUint8List()).replaceAll('=', '');
  }

  @override
  Future<void> unsubscribeBrowser() async {
    final registration = await _registration();
    final subscription =
        await registration?.pushManager.getSubscription().toDart;
    await subscription?.unsubscribe().toDart;
  }
}
