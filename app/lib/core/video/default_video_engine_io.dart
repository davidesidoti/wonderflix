import 'package:flutter/foundation.dart';

import '../platform/platform_info.dart';
import 'media3_engine.dart';
import 'media_kit_engine.dart';
import 'video_engine.dart';

/// Su Android TV il motore è Media3 (decodifica hardware sempre, quindi
/// [hardwareDecoding] non serve); altrove media_kit.
VideoEngine createVideoEngine({
  required bool hardwareDecoding,
  @visibleForTesting bool? androidTv,
}) => (androidTv ?? isAndroidTv)
    ? Media3Engine()
    : MediaKitEngine(hwdec: hardwareDecoding ? 'auto-safe' : 'no');
