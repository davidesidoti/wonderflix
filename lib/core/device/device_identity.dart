import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// DeviceId stabile per installazione + nome del PC.
/// Jellyfin lo usa per distinguere le sessioni ("WonderFlix – PC-MARIO").
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  static const prefsKey = 'device_id';

  /// Con un profilo di sviluppo ([profile], vedi `devProfile`) il DeviceId
  /// non sta nelle preferenze: le due istanze condividono lo stesso file e si
  /// sovrascriverebbero a vicenda. Si ricava dal nome del PC e dal profilo,
  /// quindi resta lo stesso a ogni avvio.
  static Future<DeviceIdentity> load(
    SharedPreferences prefs, {
    String? profile,
    String Function()? hostName,
    String Function()? newId,
  }) async {
    final name = (hostName ?? () => Platform.localHostname)();
    if (profile != null) {
      final id = const Uuid()
          .v5(Namespace.url.value, 'wonderflix-dev:$name:$profile');
      return DeviceIdentity(deviceId: id, deviceName: name);
    }
    var id = prefs.getString(prefsKey);
    if (id == null || id.isEmpty) {
      id = (newId ?? () => const Uuid().v4())();
      await prefs.setString(prefsKey, id);
    }
    return DeviceIdentity(deviceId: id, deviceName: name);
  }
}
