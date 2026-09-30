import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../core/device/dev_profile.dart';
import '../core/jellyfin/auth_api.dart';
import '../core/jellyfin/client_info.dart';
import '../core/jellyfin/jellyfin_http.dart';
import '../core/jellyfin/system_api.dart';
import '../core/storage/session_store.dart';
import '../features/auth/auth_service.dart';

/// Sovrascritti in `main()`.
final appConfigProvider = Provider<AppConfig>(
    (ref) => throw UnimplementedError('appConfigProvider va sovrascritto'));
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) =>
    throw UnimplementedError('sharedPreferencesProvider va sovrascritto'));
final clientInfoProvider = Provider<ClientInfo>(
    (ref) => throw UnimplementedError('clientInfoProvider va sovrascritto'));

final sessionStoreProvider = Provider<SessionStore>(
    (ref) => SecureSessionStore(null, sessionKeyFor(devProfile())));

final jellyfinHttpProvider = Provider<JellyfinHttp>((ref) {
  final http = JellyfinHttp(
    baseUrl: ref.watch(appConfigProvider).serverUrl,
    clientInfo: ref.watch(clientInfoProvider),
  );
  ref.onDispose(() => http.dio.close());
  return http;
});

final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.watch(jellyfinHttpProvider)));

final systemApiProvider =
    Provider<SystemApi>((ref) => SystemApi(ref.watch(jellyfinHttpProvider)));

final authServiceProvider = Provider<AuthService>((ref) => AuthService(
      http: ref.watch(jellyfinHttpProvider),
      api: ref.watch(authApiProvider),
      store: ref.watch(sessionStoreProvider),
    ));
