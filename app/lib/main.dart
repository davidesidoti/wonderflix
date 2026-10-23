import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/config_error_app.dart';
import 'app/platform_startup.dart';
import 'app/providers.dart';
import 'config/app_config.dart';
import 'core/device/dev_profile.dart';
import 'core/device/device_identity.dart';
import 'core/jellyfin/client_info.dart';
import 'core/logging/app_log.dart';
import 'core/platform/platform_info.dart';

final _log = Logger('startup');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Per primo: da qui in poi ogni messaggio finisce anche nel file di log.
  final appLog = AppLog(sink: createLogSink(), echo: kDebugMode)..attach();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger('flutter')
        .severe(details.exceptionAsString(), details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Logger('app').severe('errore non gestito', error, stack);
    return true;
  };
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
    // Su Windows: libmpv, finestra e pannello media (SMTC).
    final smtcReady = await initPlatform(prefs);

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
    _log.info('WonderFlix ${package.version} su ${systemDescription()}');

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
        ...platformOverrides(smtcReady: smtcReady),
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
      await showWindowAfterStartupError();
    } on Object {
      // Ignora: proviamo comunque a mostrare l'errore.
    }
    runApp(ConfigErrorApp(message: 'Errore di avvio: $e'));
  }
}
