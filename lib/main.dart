import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/config_error_app.dart';
import 'app/providers.dart';
import 'app/window_setup.dart';
import 'config/app_config.dart';
import 'core/device/device_identity.dart';
import 'core/jellyfin/client_info.dart';
import 'core/media_session/smtc_media_session.dart';
import 'features/player/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Carica libmpv: va fatto prima di creare qualunque Player.
  MediaKit.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    await setupWindow(prefs);

    // Pannello media di Windows: se non si avvia, il player funziona lo
    // stesso (senza pannello e con i tasti multimediali gestiti dal player).
    var smtcReady = false;
    try {
      await SMTCWindows.initialize();
      smtcReady = true;
    } on Object catch (e) {
      debugPrint('SMTC non disponibile: $e');
    }

    final AppConfig config;
    try {
      config = AppConfig.fromEnvironment();
    } on AppConfigException catch (e) {
      runApp(ConfigErrorApp(message: e.message));
      return;
    }

    final identity = await DeviceIdentity.load(prefs);
    final package = await PackageInfo.fromPlatform();

    runApp(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        clientInfoProvider.overrideWithValue(ClientInfo(
          client: 'WonderFlix',
          device: identity.deviceName,
          deviceId: identity.deviceId,
          version: package.version,
        )),
        if (smtcReady)
          mediaSessionProvider.overrideWith((ref) {
            final session = SmtcMediaSession();
            ref.onDispose(() => unawaited(session.dispose()));
            return session;
          }),
      ],
      // Nessun retry automatico: gli errori li gestiscono le schermate.
      retry: (_, _) => null,
      child: const WonderflixApp(),
    ));
  } catch (e, st) {
    // Nessun errore di avvio deve lasciare una finestra nascosta in giro:
    // mostrala comunque, con un messaggio, invece di restare invisibile.
    try {
      await windowManager.show();
    } on Object {
      // Ignora: proviamo comunque a mostrare l'errore.
    }
    runApp(ConfigErrorApp(message: 'Errore di avvio: $e'));
    debugPrint('Errore di avvio: $e\n$st');
  }
}
