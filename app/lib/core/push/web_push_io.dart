import 'web_push.dart';

/// Su Windows niente push del browser.
WebPush createWebPush() => const _NoWebPush();

class _NoWebPush implements WebPush {
  const _NoWebPush();

  @override
  String get scope => '/';

  @override
  Future<PushAvailability> availability() async => PushAvailability.unsupported;

  @override
  Future<PushKeys?> subscribe(String vapidPublicKey) async => null;

  @override
  Future<void> unsubscribeBrowser() async {}
}
