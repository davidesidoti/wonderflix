import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/rotating_file_sink.dart';

/// Nel browser niente SMTC né finestra da preparare.
Future<bool> initPlatform(SharedPreferences prefs) async => false;

/// Nessun override: Discord e SMTC restano spenti (`NoopMediaSession`).
List<Override> platformOverrides({required bool smtcReady}) => const [];

/// Nel browser i log restano solo in memoria.
RotatingFileSink? createLogSink() => null;

Future<void> showWindowAfterStartupError() async {}

VoidCallback watchWindowFocus(VoidCallback onFocus) => () {};
