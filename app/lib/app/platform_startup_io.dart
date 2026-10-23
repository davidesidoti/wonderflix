import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';

import '../core/logging/app_log.dart';
import '../core/logging/rotating_file_sink.dart';
import '../core/media_session/smtc_media_session.dart';
import '../features/discord/discord_providers.dart';
import '../features/player/player_providers.dart';
import 'window_setup.dart';

final _log = Logger('startup');

/// Restituisce `true` se il pannello media di Windows (SMTC) è pronto.
Future<bool> initPlatform(SharedPreferences prefs) async {
  // Carica libmpv: va fatto prima di creare qualunque Player.
  MediaKit.ensureInitialized();
  await setupWindow(prefs);

  // Pannello media di Windows: se non si avvia, il player funziona lo
  // stesso (senza pannello e con i tasti multimediali gestiti dal player).
  try {
    await SMTCWindows.initialize();
    return true;
  } on Object catch (e) {
    _log.warning('SMTC non disponibile: $e');
    return false;
  }
}

List<Override> platformOverrides({required bool smtcReady}) => [
  if (smtcReady)
    systemMediaSessionProvider.overrideWith((ref) {
      final session = SmtcMediaSession();
      ref.onDispose(() => unawaited(session.dispose()));
      return session;
    }),
  discordSessionProvider.overrideWith(createDiscordPresence),
];

RotatingFileSink? createLogSink() => RotatingFileSink(logsDirectory());

/// Nessun errore di avvio deve lasciare una finestra nascosta in giro.
Future<void> showWindowAfterStartupError() => windowManager.show();

/// Chiama [onFocus] quando la finestra torna in primo piano; restituisce la
/// funzione che smette di ascoltare.
VoidCallback watchWindowFocus(VoidCallback onFocus) {
  final listener = _FocusListener(onFocus);
  windowManager.addListener(listener);
  return () => windowManager.removeListener(listener);
}

class _FocusListener with WindowListener {
  _FocusListener(this._onFocus);

  final VoidCallback _onFocus;

  @override
  void onWindowFocus() => _onFocus();
}
