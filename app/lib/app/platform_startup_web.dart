import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../core/logging/rotating_file_sink.dart';

/// Nel browser niente SMTC né finestra da preparare.
Future<bool> initPlatform(SharedPreferences prefs) async => false;

/// Nessun override: Discord e SMTC restano spenti (`NoopMediaSession`).
List<Override> platformOverrides({required bool smtcReady}) => const [];

/// Nel browser i log restano solo in memoria.
RotatingFileSink? createLogSink() => null;

/// I log nella console del browser, con il livello come gravità: così si
/// leggono anche nella build di rilascio.
void logToConsole(Level level, String text) {
  if (level >= Level.SEVERE) {
    web.console.error(text.toJS);
  } else if (level >= Level.WARNING) {
    web.console.warn(text.toJS);
  } else {
    web.console.log(text.toJS);
  }
}

Future<void> showWindowAfterStartupError() async {}

VoidCallback watchWindowFocus(VoidCallback onFocus) => () {};
