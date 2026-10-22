import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
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
import 'core/device/dev_profile.dart';
import 'core/device/device_identity.dart';
import 'core/jellyfin/client_info.dart';
import 'core/logging/app_log.dart';
import 'core/logging/rotating_file_sink.dart';
import 'core/media_session/smtc_media_session.dart';
import 'features/discord/discord_providers.dart';
import 'features/player/player_providers.dart';

final _log = Logger('startup');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Per primo: da qui in poi ogni messaggio finisce anche nel file di log.
  final appLog =
      AppLog(sink: RotatingFileSink(logsDirectory()), echo: kDebugMode)
        ..attach();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger('flutter')
        .severe(details.exceptionAsString(), details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Logger('app').severe('errore non gestito', error, stack);
    return true;
  };
  // Carica libmpv: va fatto prima di creare qualunque Player.
  MediaKit.ensureInitialized();

  try {
    // Sviluppo: seconda istanza con dati separati (WONDERFLIX_PROFILE).
    final profile = devProfile();
    if (profile != null) {
      // Il prefisso separa le chiavi, ma il file delle preferenze resta uno
      // solo per le due istanze: posizione della finestra e impostazioni
      // possono ancora mescolarsi (accettabile per uno strumento di
      // sviluppo). Per questo il DeviceId del profilo non si salva qui.
      SharedPreferences.setPrefix(prefsPrefixFor(profile));
      _log.info('profilo di sviluppo: $profile');
    }
    final prefs = await SharedPreferences.getInstance();
    await setupWindow(prefs);

    // Pannello media di Windows: se non si avvia, il player funziona lo
    // stesso (senza pannello e con i tasti multimediali gestiti dal player).
    var smtcReady = false;
    try {
      await SMTCWindows.initialize();
      smtcReady = true;
    } on Object catch (e) {
      _log.warning('SMTC non disponibile: $e');
    }

    final AppConfig config;
    try {
      config = AppConfig.fromEnvironment();
    } on AppConfigException catch (e) {
      _log.severe('configurazione non valida: ${e.message}');
      runApp(ConfigErrorApp(message: e.message));
      return;
    }

    final identity = await DeviceIdentity.load(prefs, profile: profile);
    final package = await PackageInfo.fromPlatform();
    _log.info('WonderFlix ${package.version} su '
        '${Platform.operatingSystemVersion}');

    runApp(ProviderScope(
      overrides: [
        appLogProvider.overrideWithValue(appLog),
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        clientInfoProvider.overrideWithValue(ClientInfo(
          client: 'WonderFlix',
          device: identity.deviceName,
          deviceId: identity.deviceId,
          version: package.version,
        )),
        if (smtcReady)
          systemMediaSessionProvider.overrideWith((ref) {
            final session = SmtcMediaSession();
            ref.onDispose(() => unawaited(session.dispose()));
            return session;
          }),
        discordSessionProvider.overrideWith(createDiscordPresence),
      ],
      // Nessun retry automatico: gli errori li gestiscono le schermate.
      retry: (_, _) => null,
      child: const WonderflixApp(),
    ));
  } catch (e, st) {
    _log.severe('errore di avvio', e, st);
    // Nessun errore di avvio deve lasciare una finestra nascosta in giro:
    // mostrala comunque, con un messaggio, invece di restare invisibile.
    try {
      await windowManager.show();
    } on Object {
      // Ignora: proviamo comunque a mostrare l'errore.
    }
    runApp(ConfigErrorApp(message: 'Errore di avvio: $e'));
  }
}
