import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/config_error_app.dart';
import 'app/providers.dart';
import 'app/window_setup.dart';
import 'config/app_config.dart';
import 'core/device/device_identity.dart';
import 'core/jellyfin/client_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  await setupWindow(prefs);

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
    ],
    // Nessun retry automatico: gli errori li gestiscono le schermate.
    retry: (_, _) => null,
    child: const WonderflixApp(),
  ));
}
