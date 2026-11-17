import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tv_provider.dart';

/// Il dispositivo come lo nominano i testi ("da questo PC", "su questa TV").
/// Nei messaggi ICU va il `name` (`select`).
enum DeviceKind { pc, browser, phone, tv }

DeviceKind deviceKindFor(
        {required bool tv, required bool web, required TargetPlatform platform}) =>
    tv
        ? DeviceKind.tv
        : web
            ? DeviceKind.browser
            : platform == TargetPlatform.android
                ? DeviceKind.phone
                : DeviceKind.pc;

/// Il dispositivo di questa app. Nei test lo fissa `pumpApp`.
final deviceKindProvider = Provider<DeviceKind>((ref) => deviceKindFor(
    tv: ref.watch(androidTvProvider),
    web: kIsWeb,
    platform: defaultTargetPlatform));
