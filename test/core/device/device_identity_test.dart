import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/core/device/device_identity.dart';

void main() {
  test('genera un DeviceId la prima volta e poi lo riusa', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = await DeviceIdentity.load(prefs,
        hostName: () => 'PC-MARIO', newId: () => 'id-1');
    final second = await DeviceIdentity.load(prefs,
        hostName: () => 'PC-MARIO', newId: () => 'id-2');

    expect(first.deviceId, 'id-1');
    expect(second.deviceId, 'id-1');
    expect(second.deviceName, 'PC-MARIO');
    expect(prefs.getString(DeviceIdentity.prefsKey), 'id-1');
  });
}
