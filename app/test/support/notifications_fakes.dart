import 'dart:async';

import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/push/web_push.dart';
import 'package:wonderflix/core/social/notifications_api.dart';
import 'package:wonderflix/core/social/notifications_models.dart';

/// `NotificationsApi` senza rete: registra le chiamate e risponde con
/// [types]. [failure] fa lanciare tutte le chiamate.
class FakeNotificationsApi implements NotificationsApi {
  FakeNotificationsApi({List<NotificationTypePref>? types})
      : types = types ?? const [];

  List<NotificationTypePref> types;
  ApiException? failure;
  final calls = <String>[];

  /// Se c'è, [get] / [setEnabled] aspettano che si completi (la chiamata
  /// resta in volo), dopo aver registrato la chiamata.
  Completer<void>? getGate;
  Completer<void>? setGate;

  @override
  Future<NotificationsInfo> get() async {
    calls.add('get');
    if (getGate case final gate?) await gate.future;
    if (failure case final error?) throw error;
    return NotificationsInfo(vapidPublicKey: 'BKey', types: types);
  }

  @override
  Future<void> setEnabled(String type, bool enabled) async {
    calls.add('setEnabled $type $enabled');
    if (setGate case final gate?) await gate.future;
    if (failure case final error?) throw error;
  }

  @override
  Future<void> subscribe({
    required String endpoint,
    required String p256dh,
    required String auth,
    required String language,
  }) async {
    calls.add('subscribe $endpoint $language');
    if (failure case final error?) throw error;
  }

  @override
  Future<void> unsubscribe(String endpoint) async {
    calls.add('unsubscribe $endpoint');
    if (failure case final error?) throw error;
  }
}

/// `WebPush` senza browser: risponde con [state] e [keys] (`null`: permesso
/// negato).
class FakeWebPush implements WebPush {
  FakeWebPush({this.state = PushAvailability.ready, this.keys = testPushKeys});

  PushAvailability state;
  PushKeys? keys;
  final subscribeKeys = <String>[];
  int unsubscribeCalls = 0;

  @override
  Future<PushAvailability> availability() async => state;

  @override
  Future<PushKeys?> subscribe(String vapidPublicKey) async {
    subscribeKeys.add(vapidPublicKey);
    final result = keys;
    if (result != null) state = PushAvailability.active;
    return result;
  }

  @override
  Future<void> unsubscribeBrowser() async {
    unsubscribeCalls++;
    state = PushAvailability.ready;
  }
}

const testPushKeys = PushKeys(
  endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
  p256dh: 'p256',
  auth: 'secret',
);
