import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../core/jellyfin/auth_api.dart';
import '../core/jellyfin/client_info.dart';
import '../core/jellyfin/jellyfin_http.dart';
import '../core/storage/session_store.dart';
import '../features/auth/auth_service.dart';

/// Sovrascritti in `main()`.
final appConfigProvider = Provider<AppConfig>(
    (ref) => throw UnimplementedError('appConfigProvider va sovrascritto'));
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) =>
    throw UnimplementedError('sharedPreferencesProvider va sovrascritto'));
final clientInfoProvider = Provider<ClientInfo>(
    (ref) => throw UnimplementedError('clientInfoProvider va sovrascritto'));

final sessionStoreProvider =
    Provider<SessionStore>((ref) => SecureSessionStore());

final jellyfinHttpProvider = Provider<JellyfinHttp>((ref) => JellyfinHttp(
      baseUrl: ref.watch(appConfigProvider).serverUrl,
      clientInfo: ref.watch(clientInfoProvider),
    ));

final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.watch(jellyfinHttpProvider)));

final authServiceProvider = Provider<AuthService>((ref) => AuthService(
      http: ref.watch(jellyfinHttpProvider),
      api: ref.watch(authApiProvider),
      store: ref.watch(sessionStoreProvider),
    ));
