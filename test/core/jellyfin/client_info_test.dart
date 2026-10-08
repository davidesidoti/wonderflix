import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/client_info.dart';

void main() {
  const info = ClientInfo(
    client: 'WonderFlix',
    device: 'PC-MARIO',
    deviceId: 'dev-1',
    version: '1.0.0',
  );

  test('header senza token', () {
    expect(
      buildAuthorizationHeader(info),
      'MediaBrowser Client="WonderFlix", Device="PC-MARIO", '
      'DeviceId="dev-1", Version="1.0.0"',
    );
  });

  test('header con token', () {
    expect(
      buildAuthorizationHeader(info, token: 'tok'),
      endsWith(', Token="tok"'),
    );
  });

  test('ripulisce virgolette, virgole e a capo dal nome dispositivo', () {
    const dirty = ClientInfo(
      client: 'WonderFlix',
      device: 'Mario "PC",\ncasa',
      deviceId: 'dev-1',
      version: '1.0.0',
    );
    expect(buildAuthorizationHeader(dirty), contains('Device="Mario PC casa"'));
  });

  test('copyWith cambia solo il DeviceId', () {
    final copy = info.copyWith(deviceId: 'dev-2');
    expect(copy.deviceId, 'dev-2');
    expect(copy.client, info.client);
    expect(copy.device, info.device);
    expect(copy.version, info.version);
    expect(info.copyWith().deviceId, 'dev-1');
  });
}
