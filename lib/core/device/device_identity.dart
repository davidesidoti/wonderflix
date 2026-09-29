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

  static Future<DeviceIdentity> load(
    SharedPreferences prefs, {
    String Function()? hostName,
    String Function()? newId,
  }) async {
    var id = prefs.getString(prefsKey);
    if (id == null || id.isEmpty) {
      id = (newId ?? () => const Uuid().v4())();
      await prefs.setString(prefsKey, id);
    }
    final name = (hostName ?? () => Platform.localHostname)();
    return DeviceIdentity(deviceId: id, deviceName: name);
  }
}
