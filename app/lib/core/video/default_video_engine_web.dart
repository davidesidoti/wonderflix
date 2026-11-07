import 'package:flutter/foundation.dart';

import 'video_engine.dart';
import 'web_video_engine.dart';

// Nel browser la decodifica la sceglie lui: [hardwareDecoding] non serve, e
// [androidTv] c'è solo per tenere la stessa firma dell'altra versione.
VideoEngine createVideoEngine({
  required bool hardwareDecoding,
  @visibleForTesting bool? androidTv,
}) => WebVideoEngine();
