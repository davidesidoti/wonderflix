import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:local_notifier/local_notifier.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';

import '../core/jellyfin/android_tv_profile.dart';
import '../core/logging/app_log.dart';
import '../core/logging/rotating_file_sink.dart';
import '../core/media_session/smtc_media_session.dart';
import '../core/platform/platform_info.dart';
import '../features/discord/discord_providers.dart';
import '../features/player/player_providers.dart';
import 'window_setup.dart';

final _log = Logger('startup');

/// Letti all'avvio su Android; `platformOverrides` li passa al provider.
DecoderCaps? _decoderCaps;

/// Nome del dispositivo scelto sulla TV; `null` altrove o se non leggibile.
String? _tvDeviceName;

String? get tvDeviceName => _tvDeviceName;

/// Il nome dato dall'utente al Fire TV, se c'è, altrimenti il modello.
String tvDeviceNameFrom(String? settingsName, String model) {
  final name = settingsName?.trim();
  return name == null || name.isEmpty ? model : name;
}

/// Restituisce `true` se il pannello media di Windows (SMTC) è pronto.
Future<bool> initPlatform(SharedPreferences prefs) async {
  // Android TV: niente libmpv, finestra, notifiche né SMTC (il player usa
  // Media3); si leggono i decoder per il profilo del dispositivo.
  if (isAndroidTv) {
    try {
      final map = await const MethodChannel(
        'wonderflix/player',
      ).invokeMapMethod<String, dynamic>('decoderCapabilities');
      _decoderCaps = DecoderCaps.fromMap(map ?? const {});
    } on Object catch (e) {
      // Senza decoder noti il profilo non ha direct play: tutto si transcodifica.
      _log.warning('decoder non leggibili: $e');
      _decoderCaps = DecoderCaps.fromMap(const {});
    }
    _log.info('capacità dei decoder: $_decoderCaps');
    try {
      final map = await const MethodChannel(
        'wonderflix/device',
      ).invokeMapMethod<String, String?>('name');
      _tvDeviceName = tvDeviceNameFrom(
        map?['settingsName'],
        map?['model'] ?? '',
      );
    } on Object catch (e) {
      // Si resta sul nome di rete (`hostName()`).
      _log.warning('nome del dispositivo non leggibile: $e');
    }
    return false;
  }
  // Carica libmpv: va fatto prima di creare qualunque Player.
  MediaKit.ensureInitialized();
  await setupWindow(prefs);

  // Notifiche di Windows con l'identità del processo e dei collegamenti
  // dell'installer (windows/runner/main.cpp, installer/wonderflix.iss):
  // `local_notifier` usa appName come AppUserModelID. `ignore` perché il
  // collegamento nel menu Start lo crea l'installer: con `requireCreate`
  // la libreria riscriverebbe il suo AppUserModelID.
  try {
    await localNotifier.setup(
        appName: 'it.wonderflix.WonderFlix',
        shortcutPolicy: ShortcutPolicy.ignore);
  } on Object catch (e) {
    _log.warning('notifiche di Windows non disponibili: $e');
  }

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
  if (_decoderCaps != null) decoderCapsProvider.overrideWithValue(_decoderCaps),
  if (smtcReady)
    systemMediaSessionProvider.overrideWith((ref) {
      final session = SmtcMediaSession();
      ref.onDispose(() => unawaited(session.dispose()));
      return session;
    }),
  if (!isAndroidTv) discordSessionProvider.overrideWith(createDiscordPresence),
];

RotatingFileSink? createLogSink() => RotatingFileSink(logsDirectory());

/// Su Windows i log vanno solo nel file (e, in debug, nella console). Su
/// Android TV anche in logcat (`adb logcat | grep flutter`): nel file, nella
/// cache dell'app, non si arriva senza root.
final void Function(Level, String)? logToConsole =
    isAndroidTv ? (level, text) => debugPrint(text) : null;

/// Nessun errore di avvio deve lasciare una finestra nascosta in giro.
Future<void> showWindowAfterStartupError() async {
  if (!isAndroidTv) await windowManager.show();
}

/// Chiama [onFocus] quando la finestra torna in primo piano; restituisce la
/// funzione che smette di ascoltare.
VoidCallback watchWindowFocus(VoidCallback onFocus) {
  if (isAndroidTv) return () {};
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
