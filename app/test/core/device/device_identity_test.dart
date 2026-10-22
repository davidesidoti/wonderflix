import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
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

  test('profilo di sviluppo: DeviceId stabile dal PC e dal profilo, senza '
      'toccare le preferenze', () async {
    // Le due istanze condividono il file delle preferenze.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DeviceIdentity.prefsKey, 'id-principale');

    final first = await DeviceIdentity.load(prefs,
        profile: 'dev', hostName: () => 'PC-MARIO', newId: () => 'id-1');
    final second = await DeviceIdentity.load(prefs,
        profile: 'dev', hostName: () => 'PC-MARIO', newId: () => 'id-2');
    final other = await DeviceIdentity.load(prefs,
        profile: 'prova', hostName: () => 'PC-MARIO');
    final otherPc = await DeviceIdentity.load(prefs,
        profile: 'dev', hostName: () => 'PC-LUIGI');

    expect(first.deviceId,
        const Uuid().v5(Namespace.url.value, 'wonderflix-dev:PC-MARIO:dev'));
    expect(second.deviceId, first.deviceId);
    expect(other.deviceId, isNot(first.deviceId));
    expect(otherPc.deviceId, isNot(first.deviceId));
    expect(first.deviceId, isNot('id-principale'));
    expect(first.deviceName, 'PC-MARIO');
    expect(prefs.getString(DeviceIdentity.prefsKey), 'id-principale');
  });
}
