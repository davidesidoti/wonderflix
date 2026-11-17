import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/platform/device_kind.dart';

void main() {
  test('il dispositivo dalla piattaforma', () {
    expect(deviceKindFor(tv: true, web: false, platform: TargetPlatform.android),
        DeviceKind.tv);
    expect(deviceKindFor(tv: false, web: true, platform: TargetPlatform.iOS),
        DeviceKind.browser);
    expect(
        deviceKindFor(tv: false, web: false, platform: TargetPlatform.android),
        DeviceKind.phone);
    expect(
        deviceKindFor(tv: false, web: false, platform: TargetPlatform.windows),
        DeviceKind.pc);
  });
}
