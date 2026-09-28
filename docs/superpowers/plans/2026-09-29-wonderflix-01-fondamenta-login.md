# WonderFlix — Piano 1: fondamenta e login

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** app Flutter per Windows con tema Noir & Oro, testi in italiano e inglese e client Jellyfin. L'utente entra con password o Quick Connect (senza inserire l'indirizzo del server), la sessione viene ricordata e si arriva a una Home provvisoria con la barra superiore e il logout.

**Architecture:** quattro strati (spec, sezione 4).
- `lib/core/jellyfin/`: HTTP (dio) con header `MediaBrowser`, mappatura degli errori in `ApiException`, API tipizzate scritte a mano.
- `lib/features/auth/`: servizi Dart puri (`AuthService`, `QuickConnectFlow`), testabili senza Flutter.
- Riverpod collega i servizi e contiene `SessionController`, la macchina a stati della sessione.
- go_router decide la schermata in base allo stato della sessione.

**Tech Stack:** Flutter 3.35.6 / Dart 3.9.2, flutter_riverpod 3, go_router, dio 5, flutter_secure_storage, shared_preferences, window_manager, url_launcher, lucide_icons_flutter, gen-l10n; test con flutter_test, mocktail, fake_async.

**Spec:** `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md`

---

## Roadmap dei piani (Spec A)

| Piano | Contenuto | Risultato verificabile |
|---|---|---|
| **1 — questo** | Progetto, config, tema, l10n, client Jellyfin, login (password + Quick Connect), avvio, server irraggiungibile, barra superiore, logout, finestra, istanza singola, CI | Login reale sul server WonderFlix, sessione ricordata |
| 2 | Home, catalogo Film/Serie, dettaglio film/serie, pagina attore, ricerca, La mia lista, visto/non visto, trailer (link), immagini con blurhash, WebSocket `ServerEvents`, Impostazioni (lingua, logout) | Navigazione completa del catalogo |
| 3 | `VideoEngine` (media_kit), `PlaybackService`, report di avanzamento, player UI, tracce, ritardo sottotitoli, MediaSegments, trickplay, prossimo episodio, trailer locali, SMTC, impostazioni del player | Riproduzione con minutaggi salvati |
| 4 | `UpdateService` + aggiornamenti obbligatori, Inno Setup, `release.yml`, `RELEASING.md`, Discord Rich Presence, log a rotazione + "Copia diagnostica", icona `.ico` | Release installabile e aggiornabile |

Ogni piano viene scritto dopo che il precedente è stato completato, così parte dal codice reale.

## Regole per chi esegue

- **Commit:** fatti con l'identità git già configurata (quella dell'utente). **MAI** aggiungere trailer `Co-Authored-By` o righe "Generated with…".
- Shell: Git Bash su Windows, con percorsi POSIX. Tutti i comandi partono dalla root del repo `D:\Github\wonderflix`.
- Non toccare `wonderflix_logo.png` e `wonderflix_banner.png` nella root: sono file dell'utente, non tracciati.
- Test: `flutter test <file>`. Prima di ogni commit: `flutter analyze` senza errori.

## Mappa dei file

```
pubspec.yaml, l10n.yaml, analysis_options.yaml, .gitignore, README.md
config/wonderflix.example.json
assets/brand/{logo.png,banner.png}         (già presenti, da committare)
assets/fonts/{BebasNeue-Regular,Inter-Regular,Inter-SemiBold,Inter-Bold}.ttf
l10n/{app_it.arb,app_en.arb}
lib/main.dart                               bootstrap: config, prefs, identità, finestra, ProviderScope
lib/config/app_config.dart                  AppConfig da --dart-define-from-file
lib/core/device/device_identity.dart        DeviceId stabile + nome PC
lib/core/jellyfin/client_info.dart          ClientInfo + header Authorization
lib/core/jellyfin/api_exception.dart        eccezioni tipizzate + mappatura DioException
lib/core/jellyfin/jellyfin_http.dart        wrapper dio (token, onUnauthorized, asJsonMap)
lib/core/jellyfin/auth_models.dart          JellyfinUser, AuthResult, QuickConnectState
lib/core/jellyfin/auth_api.dart             endpoint di autenticazione e Quick Connect
lib/core/storage/session_store.dart         token nel Gestore credenziali
lib/features/auth/auth_service.dart         restore/login/logout
lib/features/auth/quick_connect_flow.dart   macchina a stati Quick Connect
lib/features/auth/session_controller.dart   stato di sessione (Riverpod)
lib/features/auth/auth_providers.dart       provider Quick Connect
lib/features/auth/login_screen.dart         schermata di login
lib/features/auth/password_login_form.dart  scheda Password
lib/features/auth/quick_connect_panel.dart  scheda Quick Connect
lib/features/startup/splash_screen.dart     avvio
lib/features/startup/unreachable_screen.dart server irraggiungibile
lib/features/home/home_screen.dart          Home provvisoria (sostituita nel Piano 2)
lib/app/providers.dart                      provider di infrastruttura
lib/app/theme.dart                          token Noir & Oro + ThemeData
lib/app/error_text.dart                     ApiException → messaggio localizzato
lib/app/router.dart                         go_router + redirect in base alla sessione
lib/app/app_shell.dart                      barra superiore + menu utente
lib/app/app.dart                            MaterialApp.router
lib/app/config_error_app.dart               schermata di errore se manca la config
lib/app/window_setup.dart                   dimensione/posizione finestra
windows/runner/main.cpp                     istanza singola, titolo
windows/runner/flutter_window.cpp           finestra mostrata da window_manager
windows/runner/Runner.rc                    nome prodotto
.github/workflows/ci.yml
test/support/{fake_adapter,memory_session_store,fake_session_controller,pump_app,test_data}.dart
test/... (speculari a lib/)
```

---

### Task 1: scaffold del progetto Flutter

**Files:**
- Create: progetto Flutter nella root (`pubspec.yaml`, `lib/main.dart`, `windows/`…)
- Modify: `.gitignore`, `analysis_options.yaml`
- Create: `assets/fonts/*.ttf`

- [ ] **Step 1: crea il progetto**

```bash
flutter create --org it.wonderflix --project-name wonderflix --platforms windows --empty .
```
Expected: `All done!`. I file esistenti (`README.md`, `LICENSE`, `.gitignore`) non vengono sovrascritti.

- [ ] **Step 2: aggiungi le dipendenze**

```bash
flutter pub add flutter_riverpod go_router dio flutter_secure_storage shared_preferences window_manager url_launcher uuid package_info_plus lucide_icons_flutter intl:any
flutter pub add flutter_localizations --sdk=flutter
flutter pub add dev:mocktail dev:fake_async
```
Expected: `Changed N dependencies!`. Pub sceglie automaticamente le versioni compatibili con Dart 3.9.2 (per esempio go_router scende a una major compatibile). Va bene così.

- [ ] **Step 3: scarica i font (TTF statici da Google Fonts, licenza OFL)**

```bash
mkdir -p assets/fonts
curl -sSL -o assets/fonts/BebasNeue-Regular.ttf "https://fonts.gstatic.com/s/bebasneue/v16/JTUSjIg69CK48gW7PXooxW4.ttf"
curl -sSL -o assets/fonts/Inter-Regular.ttf "https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf"
curl -sSL -o assets/fonts/Inter-SemiBold.ttf "https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYMZg.ttf"
curl -sSL -o assets/fonts/Inter-Bold.ttf "https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZg.ttf"
ls -la assets/fonts
```
Expected: 4 file, ognuno sopra i 50 KB. Se un URL restituisce 404, ricava quelli nuovi con `curl -s "https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Inter:wght@400;600;700"` (senza user-agent, Google restituisce URL `.ttf`).

- [ ] **Step 4: sezione `flutter:` di `pubspec.yaml`**

Sostituisci l'intero blocco `flutter:` in fondo a `pubspec.yaml` con:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/brand/
  fonts:
    - family: BebasNeue
      fonts:
        - asset: assets/fonts/BebasNeue-Regular.ttf
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

- [ ] **Step 5: `.gitignore` completo (sovrascrivi)**

```gitignore
# Brainstorming companion
.superpowers/

# Config reale con l'indirizzo del server (nel repo c'è solo l'example)
config/wonderflix.json

# Localizzazioni generate da gen-l10n
lib/l10n/gen/

# Miscellaneous
*.class
*.log
*.pyc
*.swp
.DS_Store
.atom/
.build/
.buildlog/
.history
.svn/
.swiftpm/
migrate_working_dir/

# IntelliJ related
*.iml
*.ipr
*.iws
.idea/

# Flutter/Dart/Pub related
**/doc/api/
.dart_tool/
.flutter-plugins-dependencies
.pub-cache/
.pub/
/build/
/coverage/

# Symbolication / obfuscation
app.*.symbols
app.*.map.json
```

- [ ] **Step 6: `analysis_options.yaml` (sovrascrivi)**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - lib/l10n/gen/**

linter:
  rules:
    prefer_single_quotes: true
    always_declare_return_types: true
    avoid_print: true
```

- [ ] **Step 7: verifica che il progetto compili**

```bash
flutter analyze
flutter build windows --debug
```
Expected: `No issues found!` e `√ Built build\windows\x64\runner\Debug\wonderflix.exe`.

- [ ] **Step 8: commit**

```bash
git add .gitignore analysis_options.yaml pubspec.yaml pubspec.lock lib windows assets/brand assets/fonts .metadata
git commit -m "chore: scaffold Flutter Windows project with dependencies and fonts"
```
(Se `README.md` è stato modificato da `flutter create`, lascialo fuori: verrà riscritto nel Task 17.)

---

### Task 2: AppConfig

**Files:**
- Create: `lib/config/app_config.dart`
- Create: `config/wonderflix.example.json`
- Test: `test/config/app_config_test.dart`

- [ ] **Step 1: scrivi il test (deve fallire)**

`test/config/app_config_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/config/app_config.dart';

AppConfig parse({
  String serverUrl = 'https://media.example.com',
  String supportUrl = 'https://discord.gg/abc',
}) =>
    AppConfig.parse(
      serverUrl: serverUrl,
      githubRepo: ' owner/repo ',
      discordAppId: '123',
      supportUrl: supportUrl,
    );

void main() {
  group('AppConfig.parse', () {
    test('toglie lo slash finale dall\'indirizzo del server', () {
      final config = parse(serverUrl: 'https://media.example.com/');
      expect(config.serverUrl.toString(), 'https://media.example.com');
      expect(config.githubRepo, 'owner/repo');
      expect(config.discordAppId, '123');
      expect(config.supportUrl, Uri.parse('https://discord.gg/abc'));
    });

    test('mantiene un sottopercorso', () {
      final config = parse(serverUrl: 'https://example.com/jellyfin/');
      expect(config.serverUrl.toString(), 'https://example.com/jellyfin');
    });

    test('supportUrl vuoto diventa null', () {
      expect(parse(supportUrl: '  ').supportUrl, isNull);
    });

    test('rifiuta indirizzi non https', () {
      expect(() => parse(serverUrl: 'http://media.example.com'),
          throwsA(isA<AppConfigException>()));
    });

    test('rifiuta indirizzo vuoto', () {
      expect(() => parse(serverUrl: ''), throwsA(isA<AppConfigException>()));
    });
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/config/app_config_test.dart`
Expected: FAIL (`Target of URI doesn't exist: 'package:wonderflix/config/app_config.dart'`).

- [ ] **Step 3: implementa**

`lib/config/app_config.dart`:
```dart
/// Configurazione fissata in fase di build con
/// `--dart-define-from-file=config/wonderflix.json`.
class AppConfig {
  const AppConfig({
    required this.serverUrl,
    required this.githubRepo,
    required this.discordAppId,
    required this.supportUrl,
  });

  /// Indirizzo HTTPS del server Jellyfin, senza slash finale.
  final Uri serverUrl;

  /// Repository GitHub pubblico delle release, formato `owner/repo`.
  final String githubRepo;

  /// Application ID del Discord Developer Portal.
  final String discordAppId;

  /// Link per "Password dimenticata?" (es. invito Discord). Opzionale.
  final Uri? supportUrl;

  static AppConfig fromEnvironment() => AppConfig.parse(
        serverUrl: const String.fromEnvironment('serverUrl'),
        githubRepo: const String.fromEnvironment('githubRepo'),
        discordAppId: const String.fromEnvironment('discordAppId'),
        supportUrl: const String.fromEnvironment('supportUrl'),
      );

  static AppConfig parse({
    required String serverUrl,
    required String githubRepo,
    required String discordAppId,
    required String supportUrl,
  }) {
    final server = Uri.tryParse(serverUrl.trim());
    if (server == null || server.scheme != 'https' || server.host.isEmpty) {
      throw AppConfigException(
          'serverUrl deve essere un indirizzo https valido, ricevuto: "$serverUrl"');
    }
    final normalized =
        server.replace(path: server.path.replaceAll(RegExp(r'/+$'), ''));
    final support = supportUrl.trim();
    return AppConfig(
      serverUrl: normalized,
      githubRepo: githubRepo.trim(),
      discordAppId: discordAppId.trim(),
      supportUrl: support.isEmpty ? null : Uri.tryParse(support),
    );
  }
}

class AppConfigException implements Exception {
  AppConfigException(this.message);
  final String message;

  @override
  String toString() => 'AppConfigException: $message';
}
```

`config/wonderflix.example.json`:
```json
{
  "serverUrl": "https://media.example.com",
  "githubRepo": "davidesidoti/wonderflix",
  "discordAppId": "000000000000000000",
  "supportUrl": "https://discord.gg/INVITO"
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/config/app_config_test.dart`
Expected: PASS (5 test).

- [ ] **Step 5: commit**

```bash
git add lib/config test/config config/wonderflix.example.json
git commit -m "feat: add build-time AppConfig"
```

---

### Task 3: identità del dispositivo e header Authorization

**Files:**
- Create: `lib/core/jellyfin/client_info.dart`
- Create: `lib/core/device/device_identity.dart`
- Test: `test/core/jellyfin/client_info_test.dart`, `test/core/device/device_identity_test.dart`

- [ ] **Step 1: scrivi i test**

`test/core/jellyfin/client_info_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/client_info.dart';

void main() {
  const info = ClientInfo(
    client: 'WonderFlix',
    device: 'PC-MARIO',
    deviceId: 'dev-1',
    version: '1.0.0',
  );

  test('header senza token', () {
    expect(
      buildAuthorizationHeader(info),
      'MediaBrowser Client="WonderFlix", Device="PC-MARIO", '
      'DeviceId="dev-1", Version="1.0.0"',
    );
  });

  test('header con token', () {
    expect(
      buildAuthorizationHeader(info, token: 'tok'),
      endsWith(', Token="tok"'),
    );
  });

  test('ripulisce virgolette, virgole e a capo dal nome dispositivo', () {
    const dirty = ClientInfo(
      client: 'WonderFlix',
      device: 'Mario "PC",\ncasa',
      deviceId: 'dev-1',
      version: '1.0.0',
    );
    expect(buildAuthorizationHeader(dirty), contains('Device="Mario PC casa"'));
  });
}
```

`test/core/device/device_identity_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/core/device/device_identity.dart';

void main() {
  test('genera un DeviceId la prima volta e poi lo riusa', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = await DeviceIdentity.load(prefs,
        hostName: () => 'PC-MARIO', newId: () => 'id-1');
    final second = await DeviceIdentity.load(prefs,
        hostName: () => 'PC-MARIO', newId: () => 'id-2');

    expect(first.deviceId, 'id-1');
    expect(second.deviceId, 'id-1');
    expect(second.deviceName, 'PC-MARIO');
    expect(prefs.getString(DeviceIdentity.prefsKey), 'id-1');
  });
}
```

- [ ] **Step 2: esegui i test**

Run: `flutter test test/core`
Expected: FAIL (file mancanti).

- [ ] **Step 3: implementa**

`lib/core/jellyfin/client_info.dart`:
```dart
/// Identità del client inviata a Jellyfin in ogni richiesta.
class ClientInfo {
  const ClientInfo({
    required this.client,
    required this.device,
    required this.deviceId,
    required this.version,
  });

  final String client;
  final String device;
  final String deviceId;
  final String version;
}

String _clean(String value) => value
    .replaceAll(RegExp(r'[",\r\n]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Header `Authorization` nel formato `MediaBrowser ...` atteso da Jellyfin.
String buildAuthorizationHeader(ClientInfo info, {String? token}) {
  final parts = <String>[
    'Client="${_clean(info.client)}"',
    'Device="${_clean(info.device)}"',
    'DeviceId="${_clean(info.deviceId)}"',
    'Version="${_clean(info.version)}"',
    if (token != null) 'Token="$token"',
  ];
  return 'MediaBrowser ${parts.join(', ')}';
}
```

`lib/core/device/device_identity.dart`:
```dart
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// DeviceId stabile per installazione + nome del PC.
/// Jellyfin lo usa per distinguere le sessioni ("WonderFlix – PC-MARIO").
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  static const prefsKey = 'device_id';

  static Future<DeviceIdentity> load(
    SharedPreferences prefs, {
    String Function()? hostName,
    String Function()? newId,
  }) async {
    var id = prefs.getString(prefsKey);
    if (id == null || id.isEmpty) {
      id = (newId ?? () => const Uuid().v4())();
      await prefs.setString(prefsKey, id);
    }
    final name = (hostName ?? () => Platform.localHostname)();
    return DeviceIdentity(deviceId: id, deviceName: name);
  }
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/core`
Expected: PASS (4 test).

- [ ] **Step 5: commit**

```bash
git add lib/core test/core
git commit -m "feat: add device identity and Jellyfin authorization header"
```

---

### Task 4: `JellyfinHttp` ed eccezioni

**Files:**
- Create: `lib/core/jellyfin/api_exception.dart`
- Create: `lib/core/jellyfin/jellyfin_http.dart`
- Create: `test/support/fake_adapter.dart`, `test/support/test_data.dart`
- Test: `test/core/jellyfin/jellyfin_http_test.dart`

- [ ] **Step 1: supporto ai test**

`test/support/fake_adapter.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class FakeResponse {
  const FakeResponse(this.status, [this.body]);
  final int status;
  final Object? body;
}

typedef FakeHandler = FakeResponse Function(RequestOptions options);

/// Adapter dio che non va in rete: registra le richieste e risponde con [handler].
/// Se [handler] lancia un'eccezione (es. SocketException), dio la riceve come
/// errore di rete.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  FakeHandler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = handler(options);
    // Come un vero 204: nessun corpo e nessun content-type.
    if (response.body == null) {
      return ResponseBody.fromString('', response.status);
    }
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

`test/support/test_data.dart` (versione iniziale, completata nel Task 5):
```dart
import 'package:wonderflix/core/jellyfin/client_info.dart';

const testClientInfo = ClientInfo(
  client: 'WonderFlix',
  device: 'PC-TEST',
  deviceId: 'dev-test',
  version: '0.0.1',
);

final testServerUrl = Uri.parse('https://media.example.com');
```

- [ ] **Step 2: scrivi il test**

`test/core/jellyfin/jellyfin_http_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late JellyfinHttp http;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'ok': true}));
    http = JellyfinHttp(
      baseUrl: Uri.parse('https://media.example.com/jf'),
      clientInfo: testClientInfo,
      adapter: adapter,
    );
  });

  test('unisce indirizzo base e percorso', () async {
    await http.get('/Users/Me');
    expect(adapter.requests.single.uri.toString(),
        'https://media.example.com/jf/Users/Me');
  });

  test('invia l\'header Authorization, con token solo se presente', () async {
    await http.get('/a');
    expect(adapter.requests.last.headers['Authorization'],
        isNot(contains('Token=')));

    http.token = 'tok';
    await http.get('/a');
    expect(adapter.requests.last.headers['Authorization'],
        contains('Token="tok"'));
  });

  test('restituisce il JSON decodificato', () async {
    expect(await http.get('/a'), {'ok': true});
  });

  test('401 diventa UnauthorizedException e chiama onUnauthorized se c\'è un token',
      () async {
    var calls = 0;
    http.onUnauthorized = () => calls++;
    adapter.handler = (_) => const FakeResponse(401);

    await expectLater(http.get('/a'), throwsA(isA<UnauthorizedException>()));
    expect(calls, 0, reason: 'senza token non è una sessione scaduta');

    http.token = 'tok';
    await expectLater(http.get('/a'), throwsA(isA<UnauthorizedException>()));
    expect(calls, 1);
  });

  test('403, 404 e 500 vengono mappati', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(http.get('/a'), throwsA(isA<ForbiddenException>()));
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(http.get('/a'), throwsA(isA<NotFoundException>()));
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(
      http.get('/a'),
      throwsA(isA<ServerErrorException>()
          .having((e) => e.statusCode, 'statusCode', 500)),
    );
  });

  test('errore di rete diventa ServerUnreachableException', () async {
    adapter.handler = (_) => throw const SocketException('down');
    await expectLater(
        http.get('/a'), throwsA(isA<ServerUnreachableException>()));
  });

  test('asJsonMap rifiuta risposte che non sono oggetti', () {
    expect(asJsonMap({'a': 1}), {'a': 1});
    expect(() => asJsonMap(null), throwsA(isA<ServerErrorException>()));
  });
}
```

- [ ] **Step 3: esegui il test**

Run: `flutter test test/core/jellyfin/jellyfin_http_test.dart`
Expected: FAIL (file mancanti).

- [ ] **Step 4: implementa**

`lib/core/jellyfin/api_exception.dart`:
```dart
import 'dart:io';

import 'package:dio/dio.dart';

/// Errori delle chiamate a Jellyfin, già classificati per la UI.
sealed class ApiException implements Exception {
  const ApiException();
}

final class UnauthorizedException extends ApiException {
  const UnauthorizedException();
}

final class ForbiddenException extends ApiException {
  const ForbiddenException();
}

final class NotFoundException extends ApiException {
  const NotFoundException();
}

final class ServerUnreachableException extends ApiException {
  const ServerUnreachableException([this.cause]);
  final Object? cause;

  @override
  String toString() => 'ServerUnreachableException($cause)';
}

final class ServerErrorException extends ApiException {
  const ServerErrorException(this.statusCode);
  final int? statusCode;

  @override
  String toString() => 'ServerErrorException($statusCode)';
}

ApiException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.badResponse:
      return switch (e.response?.statusCode) {
        401 => const UnauthorizedException(),
        403 => const ForbiddenException(),
        404 => const NotFoundException(),
        final code => ServerErrorException(code),
      };
    case DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.connectionError ||
          DioExceptionType.badCertificate:
      return ServerUnreachableException(e.error ?? e.type);
    case DioExceptionType.cancel:
      return const ServerErrorException(null);
    case DioExceptionType.unknown:
      final error = e.error;
      if (error is SocketException ||
          error is TlsException ||
          error is HttpException) {
        return ServerUnreachableException(error);
      }
      return const ServerErrorException(null);
  }
}
```

`lib/core/jellyfin/jellyfin_http.dart`:
```dart
import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'client_info.dart';

/// Accesso HTTP a Jellyfin: aggiunge l'header di autenticazione, converte gli
/// errori in [ApiException] e segnala i 401 di una sessione attiva.
class JellyfinHttp {
  JellyfinHttp({
    required Uri baseUrl,
    required ClientInfo clientInfo,
    HttpClientAdapter? adapter,
  })  : _clientInfo = clientInfo,
        dio = Dio(BaseOptions(
          baseUrl: baseUrl.toString(),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
        )) {
    if (adapter != null) dio.httpClientAdapter = adapter;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.headers['Authorization'] = authorizationHeader;
      handler.next(options);
    }));
  }

  final Dio dio;
  final ClientInfo _clientInfo;

  /// Token della sessione corrente, `null` se non autenticati.
  String? token;

  /// Chiamato quando una richiesta fatta con un token riceve 401.
  void Function()? onUnauthorized;

  String get authorizationHeader =>
      buildAuthorizationHeader(_clientInfo, token: token);

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send(() => dio.post<dynamic>(path, data: body, queryParameters: query));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      if (mapped is UnauthorizedException && token != null) {
        onUnauthorized?.call();
      }
      throw mapped;
    }
  }
}

/// Converte il corpo di una risposta in oggetto JSON, o lancia
/// [ServerErrorException] se la forma non è quella attesa.
Map<String, dynamic> asJsonMap(Object? data) {
  if (data is Map<String, dynamic>) return data;
  throw const ServerErrorException(null);
}
```

- [ ] **Step 5: esegui il test**

Run: `flutter test test/core/jellyfin/jellyfin_http_test.dart`
Expected: PASS (7 test).

- [ ] **Step 6: commit**

```bash
git add lib/core/jellyfin test/core/jellyfin test/support
git commit -m "feat: add JellyfinHttp with typed API exceptions"
```

---

### Task 5: modelli e `AuthApi`

**Files:**
- Create: `lib/core/jellyfin/auth_models.dart`, `lib/core/jellyfin/auth_api.dart`
- Modify: `test/support/test_data.dart`
- Test: `test/core/jellyfin/auth_api_test.dart`

- [ ] **Step 1: completa `test/support/test_data.dart`**

```dart
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/client_info.dart';

const testClientInfo = ClientInfo(
  client: 'WonderFlix',
  device: 'PC-TEST',
  deviceId: 'dev-test',
  version: '0.0.1',
);

final testServerUrl = Uri.parse('https://media.example.com');

const testUser = JellyfinUser(id: 'u1', name: 'Mario');

Map<String, dynamic> authResultJson({String token = 'tok-1'}) => {
      'User': {'Id': 'u1', 'Name': 'Mario', 'PrimaryImageTag': 'img1'},
      'AccessToken': token,
      'ServerId': 'srv',
    };
```

- [ ] **Step 2: scrivi il test**

`test/core/jellyfin/auth_api_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AuthApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = AuthApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('authenticateByName invia Username/Pw e legge token e utente', () async {
    adapter.handler = (_) => FakeResponse(200, authResultJson());

    final result = await api.authenticateByName('mario', 'segreta');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/AuthenticateByName');
    expect(request.data, {'Username': 'mario', 'Pw': 'segreta'});
    expect(result.accessToken, 'tok-1');
    expect(result.user.id, 'u1');
    expect(result.user.name, 'Mario');
    expect(result.user.primaryImageTag, 'img1');
  });

  test('getMe legge l\'utente corrente', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Id': 'u1', 'Name': 'Mario'});
    final user = await api.getMe();
    expect(adapter.requests.single.path, '/Users/Me');
    expect(user.name, 'Mario');
    expect(user.primaryImageTag, isNull);
  });

  test('logout chiama POST /Sessions/Logout', () async {
    await api.logout();
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/Sessions/Logout');
  });

  test('quickConnectEnabled legge il booleano', () async {
    adapter.handler = (_) => const FakeResponse(200, true);
    expect(await api.quickConnectEnabled(), isTrue);
    adapter.handler = (_) => const FakeResponse(200, false);
    expect(await api.quickConnectEnabled(), isFalse);
  });

  test('initiateQuickConnect restituisce codice e segreto', () async {
    adapter.handler = (_) => const FakeResponse(200,
        {'Code': '482913', 'Secret': 's1', 'Authenticated': false});
    final state = await api.initiateQuickConnect();
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/QuickConnect/Initiate');
    expect(state.code, '482913');
    expect(state.secret, 's1');
    expect(state.authenticated, isFalse);
  });

  test('quickConnectState passa il segreto in query', () async {
    adapter.handler = (_) => const FakeResponse(200,
        {'Code': '482913', 'Secret': 's1', 'Authenticated': true});
    final state = await api.quickConnectState('s1');
    expect(adapter.requests.single.path, '/QuickConnect/Connect');
    expect(adapter.requests.single.queryParameters, {'secret': 's1'});
    expect(state.authenticated, isTrue);
  });

  test('authenticateWithQuickConnect invia il segreto', () async {
    adapter.handler = (_) => FakeResponse(200, authResultJson(token: 'tok-qc'));
    final result = await api.authenticateWithQuickConnect('s1');
    expect(adapter.requests.single.path, '/Users/AuthenticateWithQuickConnect');
    expect(adapter.requests.single.data, {'Secret': 's1'});
    expect(result.accessToken, 'tok-qc');
  });
}
```

- [ ] **Step 3: esegui il test**

Run: `flutter test test/core/jellyfin/auth_api_test.dart`
Expected: FAIL (`auth_api.dart` mancante).

- [ ] **Step 4: implementa**

`lib/core/jellyfin/auth_models.dart`:
```dart
class JellyfinUser {
  const JellyfinUser({required this.id, required this.name, this.primaryImageTag});

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
        id: json['Id'] as String,
        name: json['Name'] as String,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );

  final String id;
  final String name;
  final String? primaryImageTag;
}

class AuthResult {
  const AuthResult({required this.user, required this.accessToken});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        user: JellyfinUser.fromJson(json['User'] as Map<String, dynamic>),
        accessToken: json['AccessToken'] as String,
      );

  final JellyfinUser user;
  final String accessToken;
}

class QuickConnectState {
  const QuickConnectState({
    required this.code,
    required this.secret,
    required this.authenticated,
  });

  factory QuickConnectState.fromJson(Map<String, dynamic> json) =>
      QuickConnectState(
        code: json['Code'] as String,
        secret: json['Secret'] as String,
        authenticated: json['Authenticated'] as bool? ?? false,
      );

  final String code;
  final String secret;
  final bool authenticated;
}
```

`lib/core/jellyfin/auth_api.dart`:
```dart
import 'auth_models.dart';
import 'jellyfin_http.dart';

/// Endpoint di autenticazione e Quick Connect (Jellyfin 10.11).
class AuthApi {
  AuthApi(this._http);

  final JellyfinHttp _http;

  Future<AuthResult> authenticateByName(String username, String password) async {
    final data = await _http.post('/Users/AuthenticateByName',
        body: {'Username': username, 'Pw': password});
    return AuthResult.fromJson(asJsonMap(data));
  }

  Future<JellyfinUser> getMe() async =>
      JellyfinUser.fromJson(asJsonMap(await _http.get('/Users/Me')));

  Future<void> logout() async {
    await _http.post('/Sessions/Logout');
  }

  Future<bool> quickConnectEnabled() async =>
      await _http.get('/QuickConnect/Enabled') == true;

  Future<QuickConnectState> initiateQuickConnect() async =>
      QuickConnectState.fromJson(
          asJsonMap(await _http.post('/QuickConnect/Initiate')));

  Future<QuickConnectState> quickConnectState(String secret) async =>
      QuickConnectState.fromJson(asJsonMap(
          await _http.get('/QuickConnect/Connect', query: {'secret': secret})));

  Future<AuthResult> authenticateWithQuickConnect(String secret) async {
    final data = await _http.post('/Users/AuthenticateWithQuickConnect',
        body: {'Secret': secret});
    return AuthResult.fromJson(asJsonMap(data));
  }
}
```

- [ ] **Step 5: esegui tutti i test**

Run: `flutter test`
Expected: PASS (tutti).

- [ ] **Step 6: commit**

```bash
git add lib/core/jellyfin test/core/jellyfin test/support/test_data.dart
git commit -m "feat: add AuthApi for password and Quick Connect login"
```

---

### Task 6: `SessionStore` (token nel Gestore credenziali)

**Files:**
- Create: `lib/core/storage/session_store.dart`
- Create: `test/support/memory_session_store.dart`
- Test: `test/core/storage/session_store_test.dart`

- [ ] **Step 1: scrivi il test**

`test/core/storage/session_store_test.dart`:
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/storage/session_store.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('scrive, legge e cancella la sessione', () async {
    final store = SecureSessionStore();
    expect(await store.read(), isNull);

    await store.write(const StoredSession(userId: 'u1', accessToken: 'tok'));
    final read = await store.read();
    expect(read?.userId, 'u1');
    expect(read?.accessToken, 'tok');

    await store.clear();
    expect(await store.read(), isNull);
  });

  test('un valore corrotto viene scartato e cancellato', () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureSessionStore.key: 'non-json'});
    final store = SecureSessionStore();
    expect(await store.read(), isNull);
    expect(await const FlutterSecureStorage().read(key: SecureSessionStore.key),
        isNull);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/core/storage/session_store_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/core/storage/session_store.dart`:
```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession({required this.userId, required this.accessToken});

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
        userId: json['userId'] as String,
        accessToken: json['accessToken'] as String,
      );

  final String userId;
  final String accessToken;

  Map<String, dynamic> toJson() => {'userId': userId, 'accessToken': accessToken};
}

abstract interface class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Salva la sessione nel Gestore credenziali di Windows.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'wonderflix.session';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: key);
}
```

`test/support/memory_session_store.dart`:
```dart
import 'package:wonderflix/core/storage/session_store.dart';

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);

  StoredSession? session;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/core/storage/session_store_test.dart`
Expected: PASS (2 test).

- [ ] **Step 5: commit**

```bash
git add lib/core/storage test/core/storage test/support/memory_session_store.dart
git commit -m "feat: persist session token in Windows Credential Manager"
```

---

### Task 7: `AuthService`

**Files:**
- Create: `lib/features/auth/auth_service.dart`
- Test: `test/features/auth/auth_service_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/auth/auth_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/session_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';

import '../../support/memory_session_store.dart';
import '../../support/test_data.dart';

class MockAuthApi extends Mock implements AuthApi {}

void main() {
  late MockAuthApi api;
  late JellyfinHttp http;
  late MemorySessionStore store;
  late AuthService service;

  const stored = StoredSession(userId: 'u1', accessToken: 'tok-old');

  setUp(() {
    api = MockAuthApi();
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    store = MemorySessionStore();
    service = AuthService(http: http, api: api, store: store);
  });

  group('restore', () {
    test('nessuna sessione salvata', () async {
      expect(await service.restore(), isA<NoStoredSession>());
      verifyNever(() => api.getMe());
    });

    test('token valido: imposta il token e restituisce l\'utente', () async {
      store.session = stored;
      when(() => api.getMe()).thenAnswer((_) async => testUser);

      final result = await service.restore();

      expect(result, isA<RestoredSession>());
      expect((result as RestoredSession).user.name, 'Mario');
      expect(http.token, 'tok-old');
    });

    test('401: cancella la sessione', () async {
      store.session = stored;
      when(() => api.getMe()).thenThrow(const UnauthorizedException());

      expect(await service.restore(), isA<StoredSessionExpired>());
      expect(store.session, isNull);
      expect(http.token, isNull);
    });

    test('server irraggiungibile: mantiene la sessione', () async {
      store.session = stored;
      when(() => api.getMe()).thenThrow(const ServerUnreachableException());

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.session, isNotNull);
    });

    test('errore 500: trattato come irraggiungibile, mantiene la sessione',
        () async {
      store.session = stored;
      when(() => api.getMe()).thenThrow(const ServerErrorException(500));

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.session, isNotNull);
    });
  });

  test('loginWithPassword salva la sessione e imposta il token', () async {
    when(() => api.authenticateByName('mario', 'pw')).thenAnswer((_) async =>
        const AuthResult(user: testUser, accessToken: 'tok-new'));

    final user = await service.loginWithPassword('  mario ', 'pw');

    expect(user.id, 'u1');
    expect(http.token, 'tok-new');
    expect(store.session?.accessToken, 'tok-new');
  });

  test('loginWithPassword propaga gli errori senza salvare nulla', () async {
    when(() => api.authenticateByName(any(), any()))
        .thenThrow(const UnauthorizedException());

    await expectLater(service.loginWithPassword('mario', 'x'),
        throwsA(isA<UnauthorizedException>()));
    expect(store.session, isNull);
  });

  test('completeQuickConnect salva la sessione', () async {
    when(() => api.authenticateWithQuickConnect('s1')).thenAnswer((_) async =>
        const AuthResult(user: testUser, accessToken: 'tok-qc'));

    await service.completeQuickConnect('s1');

    expect(http.token, 'tok-qc');
    expect(store.session?.accessToken, 'tok-qc');
  });

  test('logout cancella la sessione anche se il server fallisce', () async {
    store.session = stored;
    http.token = 'tok-old';
    when(() => api.logout()).thenThrow(const ServerUnreachableException());

    await service.logout();

    expect(store.session, isNull);
    expect(http.token, isNull);
  });

  test('clearLocalSession cancella senza chiamare il server', () async {
    store.session = stored;
    http.token = 'tok-old';

    await service.clearLocalSession();

    expect(store.session, isNull);
    expect(http.token, isNull);
    verifyNever(() => api.logout());
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/features/auth/auth_service_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/features/auth/auth_service.dart`:
```dart
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_api.dart';
import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/jellyfin_http.dart';
import '../../core/storage/session_store.dart';

sealed class RestoreResult {
  const RestoreResult();
}

final class RestoredSession extends RestoreResult {
  const RestoredSession(this.user);
  final JellyfinUser user;
}

final class NoStoredSession extends RestoreResult {
  const NoStoredSession();
}

final class StoredSessionExpired extends RestoreResult {
  const StoredSessionExpired();
}

final class RestoreServerUnreachable extends RestoreResult {
  const RestoreServerUnreachable();
}

/// Login, ripristino e logout. Nessuna dipendenza da Flutter.
class AuthService {
  AuthService({
    required JellyfinHttp http,
    required AuthApi api,
    required SessionStore store,
  })  : _http = http,
        _api = api,
        _store = store;

  final JellyfinHttp _http;
  final AuthApi _api;
  final SessionStore _store;

  Future<RestoreResult> restore() async {
    final session = await _store.read();
    if (session == null) return const NoStoredSession();

    _http.token = session.accessToken;
    try {
      return RestoredSession(await _api.getMe());
    } on UnauthorizedException {
      await clearLocalSession();
      return const StoredSessionExpired();
    } on ApiException {
      return const RestoreServerUnreachable();
    }
  }

  Future<JellyfinUser> loginWithPassword(String username, String password) async {
    final result = await _api.authenticateByName(username.trim(), password);
    await _adopt(result);
    return result.user;
  }

  Future<JellyfinUser> completeQuickConnect(String secret) async {
    final result = await _api.authenticateWithQuickConnect(secret);
    await _adopt(result);
    return result.user;
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } on ApiException {
      // Il token viene comunque dimenticato in locale.
    } finally {
      await clearLocalSession();
    }
  }

  Future<void> clearLocalSession() async {
    _http.token = null;
    await _store.clear();
  }

  Future<void> _adopt(AuthResult result) async {
    _http.token = result.accessToken;
    await _store.write(
        StoredSession(userId: result.user.id, accessToken: result.accessToken));
  }
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/features/auth/auth_service_test.dart`
Expected: PASS (10 test).

- [ ] **Step 5: commit**

```bash
git add lib/features/auth test/features/auth
git commit -m "feat: add AuthService with session restore and logout"
```

---

### Task 8: `QuickConnectFlow`

**Files:**
- Create: `lib/features/auth/quick_connect_flow.dart`
- Test: `test/features/auth/quick_connect_flow_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/auth/quick_connect_flow_test.dart`:
```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';

import '../../support/test_data.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthApi api;
  late MockAuthService auth;
  late QuickConnectFlow flow;

  QuickConnectState qc(String code, String secret, {bool ok = false}) =>
      QuickConnectState(code: code, secret: secret, authenticated: ok);

  setUp(() {
    api = MockAuthApi();
    auth = MockAuthService();
    flow = QuickConnectFlow(api: api, auth: auth);
  });

  test('Quick Connect disattivato sul server', () {
    fakeAsync((async) {
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => false);
      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect(states.map((s) => s.runtimeType), [QcLoading, QcDisabled]);
    });
  });

  test('mostra il codice, attende e completa il login', () {
    fakeAsync((async) {
      var polls = 0;
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect())
          .thenAnswer((_) async => qc('482913', 's1'));
      when(() => api.quickConnectState('s1'))
          .thenAnswer((_) async => qc('482913', 's1', ok: ++polls >= 2));
      when(() => auth.completeQuickConnect('s1'))
          .thenAnswer((_) async => testUser);

      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect(states.last,
          isA<QcWaiting>().having((s) => s.code, 'code', '482913'));

      async.elapse(const Duration(seconds: 3));
      expect(states.last, isA<QcWaiting>(), reason: 'primo controllo: non ancora');

      async.elapse(const Duration(seconds: 3));
      expect(states.last,
          isA<QcApproved>().having((s) => s.user.id, 'user', 'u1'));
      verify(() => auth.completeQuickConnect('s1')).called(1);
    });
  });

  test('segreto scaduto: genera un nuovo codice', () {
    fakeAsync((async) {
      var initiations = 0;
      when(() => api.quickConnectEnabled()).thenAnswer((_) async => true);
      when(() => api.initiateQuickConnect()).thenAnswer((_) async {
        initiations++;
        return initiations == 1 ? qc('111111', 's1') : qc('222222', 's2');
      });
      when(() => api.quickConnectState('s1'))
          .thenThrow(const NotFoundException());
      when(() => api.quickConnectState('s2'))
          .thenAnswer((_) async => qc('222222', 's2'));

      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect((states.last as QcWaiting).code, '111111');

      async.elapse(const Duration(seconds: 3));
      expect((states.last as QcWaiting).code, '222222');
    });
  });

  test('server irraggiungibile: stato di errore', () {
    fakeAsync((async) {
      when(() => api.quickConnectEnabled())
          .thenThrow(const ServerUnreachableException());
      final states = <QcState>[];
      flow.run().listen(states.add);
      async.flushMicrotasks();
      expect(states.last, isA<QcError>());
    });
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/features/auth/quick_connect_flow_test.dart`
Expected: FAIL (file mancante).

- [ ] **Step 3: implementa**

`lib/features/auth/quick_connect_flow.dart`:
```dart
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_api.dart';
import '../../core/jellyfin/auth_models.dart';
import 'auth_service.dart';

sealed class QcState {
  const QcState();
}

final class QcLoading extends QcState {
  const QcLoading();
}

final class QcDisabled extends QcState {
  const QcDisabled();
}

final class QcWaiting extends QcState {
  const QcWaiting(this.code);
  final String code;
}

final class QcApproved extends QcState {
  const QcApproved(this.user);
  final JellyfinUser user;
}

final class QcError extends QcState {
  const QcError(this.error);
  final ApiException error;
}

abstract interface class QuickConnectRunner {
  /// Stream degli stati. Termina con [QcDisabled], [QcApproved] o [QcError].
  Stream<QcState> run();
}

class QuickConnectFlow implements QuickConnectRunner {
  QuickConnectFlow({
    required AuthApi api,
    required AuthService auth,
    Duration pollInterval = const Duration(seconds: 3),
  })  : _api = api,
        _auth = auth,
        _pollInterval = pollInterval;

  final AuthApi _api;
  final AuthService _auth;
  final Duration _pollInterval;

  @override
  Stream<QcState> run() async* {
    yield const QcLoading();
    try {
      if (!await _api.quickConnectEnabled()) {
        yield const QcDisabled();
        return;
      }
      while (true) {
        final session = await _api.initiateQuickConnect();
        yield QcWaiting(session.code);

        var expired = false;
        while (!expired) {
          await Future<void>.delayed(_pollInterval);
          try {
            final state = await _api.quickConnectState(session.secret);
            if (state.authenticated) {
              yield QcApproved(await _auth.completeQuickConnect(session.secret));
              return;
            }
          } on NotFoundException {
            expired = true;
          } on UnauthorizedException {
            expired = true;
          }
        }
      }
    } on ApiException catch (e) {
      yield QcError(e);
    }
  }
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/features/auth/quick_connect_flow_test.dart`
Expected: PASS (4 test).

- [ ] **Step 5: commit**

```bash
git add lib/features/auth/quick_connect_flow.dart test/features/auth/quick_connect_flow_test.dart
git commit -m "feat: add Quick Connect flow with code regeneration"
```

---

### Task 9: tema Noir & Oro

**Files:**
- Create: `lib/app/theme.dart`
- Test: `test/app/theme_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/theme_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';

void main() {
  test('il tema usa i token Noir & Oro', () {
    final theme = buildWonderflixTheme();
    expect(theme.colorScheme.primary, WfColors.gold);
    expect(theme.colorScheme.onPrimary, WfColors.bg);
    expect(theme.scaffoldBackgroundColor, WfColors.bg);
    expect(theme.colorScheme.onSurface, WfColors.cream);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(WfText.display(40).fontFamily, 'BebasNeue');
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/app/theme_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/app/theme.dart`:
```dart
import 'package:flutter/material.dart';

/// Token colore Noir & Oro (spec, sezione 6).
abstract final class WfColors {
  static const bg = Color(0xFF0A0A0A);
  static const surface = Color(0xFF121212);
  static const surfaceHigh = Color(0xFF1B1B1B);
  static const border = Color(0xFF262626);
  static const gold = Color(0xFFD4A64A);
  static const cream = Color(0xFFF2EAD3);
  static const creamMuted = Color(0x99F2EAD3);
  static const error = Color(0xFFC8463C);
}

abstract final class WfText {
  static const displayFamily = 'BebasNeue';

  /// Titoli in Bebas Neue, come il logo.
  static TextStyle display(double size, {Color color = WfColors.cream}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        height: 1,
        letterSpacing: 1,
        color: color,
      );
}

ThemeData buildWonderflixTheme() {
  const scheme = ColorScheme.dark(
    primary: WfColors.gold,
    onPrimary: WfColors.bg,
    secondary: WfColors.gold,
    onSecondary: WfColors.bg,
    surface: WfColors.bg,
    onSurface: WfColors.cream,
    surfaceContainer: WfColors.surface,
    surfaceContainerHigh: WfColors.surfaceHigh,
    error: WfColors.error,
    outline: WfColors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WfColors.bg,
    fontFamily: 'Inter',
  );

  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color),
      );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: WfColors.cream,
      displayColor: WfColors.cream,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WfColors.surfaceHigh,
      hintStyle: const TextStyle(color: WfColors.creamMuted),
      border: border(WfColors.border),
      enabledBorder: border(WfColors.border),
      focusedBorder: border(WfColors.gold),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WfColors.gold,
        foregroundColor: WfColors.bg,
        minimumSize: const Size.fromHeight(44),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
            fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WfColors.gold,
        side: const BorderSide(color: WfColors.gold),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: WfColors.gold),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: WfColors.gold,
      unselectedLabelColor: WfColors.creamMuted,
      indicatorColor: WfColors.gold,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: WfColors.surface,
      textStyle: TextStyle(color: WfColors.cream),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: WfColors.gold),
  );
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/app/theme_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/app/theme.dart test/app/theme_test.dart
git commit -m "feat: add Noir & Oro theme"
```

---

### Task 10: localizzazione e messaggi di errore

**Files:**
- Create: `l10n/app_it.arb`, `l10n/app_en.arb`, `l10n.yaml`
- Modify: `pubspec.yaml` (`generate: true`)
- Create: `lib/app/error_text.dart`
- Test: `test/app/error_text_test.dart`

- [ ] **Step 1: file ARB**

`l10n/app_it.arb`:
```json
{
  "@@locale": "it",
  "appTitle": "WonderFlix",
  "loginTabPassword": "Password",
  "loginTabQuickConnect": "Quick Connect",
  "loginUsername": "Nome utente",
  "loginPassword": "Password",
  "loginSubmit": "ACCEDI",
  "loginForgotPassword": "Password dimenticata?",
  "loginContactAdmin": "Scrivi all'admin",
  "sessionExpired": "Sessione scaduta, accedi di nuovo.",
  "errorInvalidCredentials": "Nome utente o password errati.",
  "errorAccountDisabled": "Account disabilitato o accesso non consentito.",
  "errorServerUnreachable": "WonderFlix non è raggiungibile. Controlla la connessione.",
  "errorGeneric": "Qualcosa è andato storto. Riprova.",
  "quickConnectYourCode": "Il tuo codice:",
  "quickConnectWaiting": "In attesa di approvazione…",
  "quickConnectHelp": "Da telefono o browser già collegati a WonderFlix apri Impostazioni → Quick Connect e inserisci il codice.",
  "quickConnectDisabled": "Quick Connect non è attivo su questo server.",
  "retry": "Riprova",
  "unreachableTitle": "WonderFlix non è raggiungibile",
  "unreachableBody": "Nuovo tentativo automatico ogni 15 secondi.",
  "navHome": "Home",
  "menuLogout": "Esci",
  "homeWelcome": "Ciao, {name}",
  "@homeWelcome": {
    "placeholders": {
      "name": {"type": "String"}
    }
  }
}
```

`l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "appTitle": "WonderFlix",
  "loginTabPassword": "Password",
  "loginTabQuickConnect": "Quick Connect",
  "loginUsername": "Username",
  "loginPassword": "Password",
  "loginSubmit": "SIGN IN",
  "loginForgotPassword": "Forgot your password?",
  "loginContactAdmin": "Contact the admin",
  "sessionExpired": "Session expired, please sign in again.",
  "errorInvalidCredentials": "Wrong username or password.",
  "errorAccountDisabled": "Account disabled or access not allowed.",
  "errorServerUnreachable": "WonderFlix can't be reached. Check your connection.",
  "errorGeneric": "Something went wrong. Please try again.",
  "quickConnectYourCode": "Your code:",
  "quickConnectWaiting": "Waiting for approval…",
  "quickConnectHelp": "On a phone or browser already signed in to WonderFlix, open Settings → Quick Connect and enter the code.",
  "quickConnectDisabled": "Quick Connect is not enabled on this server.",
  "retry": "Retry",
  "unreachableTitle": "WonderFlix can't be reached",
  "unreachableBody": "Retrying automatically every 15 seconds.",
  "navHome": "Home",
  "menuLogout": "Sign out",
  "homeWelcome": "Hi, {name}"
}
```

- [ ] **Step 2: configura gen-l10n e genera le classi**

Crea `l10n.yaml` nella root:
```yaml
arb-dir: l10n
template-arb-file: app_it.arb
output-dir: lib/l10n/gen
output-localization-file: app_localizations.dart
nullable-getter: false
```
(Non aggiungere `synthetic-package`: in Flutter 3.35 l'opzione è stata rimossa.)

In `pubspec.yaml`, dentro il blocco `flutter:`, aggiungi `generate: true` subito sotto `uses-material-design: true`.

Run: `flutter gen-l10n`
Expected: nessun errore; creato `lib/l10n/gen/app_localizations.dart` (ignorato da git).

- [ ] **Step 3: scrivi il test**

`test/app/error_text_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/error_text.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('ogni errore ha un messaggio dedicato', () {
    expect(describeError(l, const UnauthorizedException()),
        'Nome utente o password errati.');
    expect(describeError(l, const ForbiddenException()),
        'Account disabilitato o accesso non consentito.');
    expect(describeError(l, const ServerUnreachableException()),
        startsWith('WonderFlix non è raggiungibile'));
    expect(describeError(l, const ServerErrorException(500)),
        'Qualcosa è andato storto. Riprova.');
    expect(describeError(l, StateError('x')),
        'Qualcosa è andato storto. Riprova.');
  });
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/app/error_text_test.dart`
Expected: FAIL (`error_text.dart` mancante).

- [ ] **Step 5: implementa**

`lib/app/error_text.dart`:
```dart
import '../core/jellyfin/api_exception.dart';
import '../l10n/gen/app_localizations.dart';

/// Messaggio per l'utente a partire da un errore qualsiasi.
String describeError(AppLocalizations l, Object error) => switch (error) {
      UnauthorizedException() => l.errorInvalidCredentials,
      ForbiddenException() => l.errorAccountDisabled,
      ServerUnreachableException() => l.errorServerUnreachable,
      _ => l.errorGeneric,
    };
```

- [ ] **Step 6: esegui il test**

Run: `flutter test test/app/error_text_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

```bash
git add l10n l10n.yaml pubspec.yaml lib/app/error_text.dart test/app/error_text_test.dart
git commit -m "feat: add Italian/English localization and error messages"
```

---

### Task 11: provider e `SessionController`

**Files:**
- Create: `lib/app/providers.dart`
- Create: `lib/features/auth/session_controller.dart`
- Create: `lib/features/auth/auth_providers.dart`
- Test: `test/features/auth/session_controller_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/auth/session_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/test_data.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late JellyfinHttp http;
  late ProviderContainer container;

  SessionController controller() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  setUp(() {
    auth = MockAuthService();
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    container = ProviderContainer.test(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        jellyfinHttpProvider.overrideWithValue(http),
      ],
      retry: (_, _) => null,
    );
  });

  test('parte in SessionStarting', () {
    expect(state(), isA<SessionStarting>());
  });

  test('restore: sessione valida → SignedIn', () async {
    when(() => auth.restore())
        .thenAnswer((_) async => const RestoredSession(testUser));
    await controller().restore();
    expect(state(), isA<SessionSignedIn>());
  });

  test('restore: nessuna sessione → SignedOut non scaduta', () async {
    when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
    await controller().restore();
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.expired, 'expired', false));
  });

  test('restore: token scaduto → SignedOut scaduta', () async {
    when(() => auth.restore())
        .thenAnswer((_) async => const StoredSessionExpired());
    await controller().restore();
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.expired, 'expired', true));
  });

  test('restore: server giù → Unreachable', () async {
    when(() => auth.restore())
        .thenAnswer((_) async => const RestoreServerUnreachable());
    await controller().restore();
    expect(state(), isA<SessionUnreachable>());
  });

  test('login riuscito → SignedIn; errore propagato e stato invariato',
      () async {
    when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
    await controller().restore();

    when(() => auth.loginWithPassword('mario', 'bad'))
        .thenThrow(const UnauthorizedException());
    await expectLater(controller().loginWithPassword('mario', 'bad'),
        throwsA(isA<UnauthorizedException>()));
    expect(state(), isA<SessionSignedOut>());

    when(() => auth.loginWithPassword('mario', 'ok'))
        .thenAnswer((_) async => testUser);
    await controller().loginWithPassword('mario', 'ok');
    expect(state(), isA<SessionSignedIn>());
  });

  test('quickConnectApproved → SignedIn', () {
    controller().quickConnectApproved(testUser);
    expect(state(), isA<SessionSignedIn>());
  });

  test('logout → SignedOut', () async {
    when(() => auth.logout()).thenAnswer((_) async {});
    controller().quickConnectApproved(testUser);
    await controller().logout();
    expect(state(), isA<SessionSignedOut>());
    verify(() => auth.logout()).called(1);
  });

  test('un 401 durante la sessione riporta al login come sessione scaduta',
      () async {
    when(() => auth.clearLocalSession()).thenAnswer((_) async {});
    controller().quickConnectApproved(testUser);

    http.onUnauthorized!.call();

    expect(state(),
        isA<SessionSignedOut>().having((s) => s.expired, 'expired', true));
    verify(() => auth.clearLocalSession()).called(1);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/features/auth/session_controller_test.dart`
Expected: FAIL (file mancanti).

- [ ] **Step 3: implementa**

`lib/app/providers.dart`:
```dart
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
```

`lib/features/auth/session_controller.dart`:
```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/auth_models.dart';
import 'auth_service.dart';

sealed class SessionState {
  const SessionState();
}

/// Ripristino della sessione in corso (schermata di avvio).
final class SessionStarting extends SessionState {
  const SessionStarting();
}

final class SessionSignedOut extends SessionState {
  const SessionSignedOut({this.expired = false});

  /// `true` se l'utente è stato disconnesso per un token non più valido.
  final bool expired;
}

final class SessionUnreachable extends SessionState {
  const SessionUnreachable();
}

final class SessionSignedIn extends SessionState {
  const SessionSignedIn(this.user);
  final JellyfinUser user;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final http = ref.watch(jellyfinHttpProvider);
    http.onUnauthorized = _onUnauthorized;
    ref.onDispose(() => http.onUnauthorized = null);
    return const SessionStarting();
  }

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> restore() async {
    final result = await _auth.restore();
    state = switch (result) {
      RestoredSession(:final user) => SessionSignedIn(user),
      NoStoredSession() => const SessionSignedOut(),
      StoredSessionExpired() => const SessionSignedOut(expired: true),
      RestoreServerUnreachable() => const SessionUnreachable(),
    };
  }

  /// Lancia [ApiException] in caso di errore: la UI mostra il messaggio.
  Future<void> loginWithPassword(String username, String password) async {
    final user = await _auth.loginWithPassword(username, password);
    state = SessionSignedIn(user);
  }

  void quickConnectApproved(JellyfinUser user) => state = SessionSignedIn(user);

  Future<void> logout() async {
    await _auth.logout();
    state = const SessionSignedOut();
  }

  void _onUnauthorized() {
    if (state is! SessionSignedIn) return;
    unawaited(_auth.clearLocalSession());
    state = const SessionSignedOut(expired: true);
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
```

`lib/features/auth/auth_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'quick_connect_flow.dart';

/// `true` se il server ha Quick Connect attivo. In caso di errore: `false`
/// (la scheda semplicemente non compare).
final quickConnectEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(authApiProvider).quickConnectEnabled();
  } on Object {
    return false;
  }
});

final quickConnectRunnerProvider = Provider<QuickConnectRunner>(
  (ref) => QuickConnectFlow(
    api: ref.watch(authApiProvider),
    auth: ref.watch(authServiceProvider),
  ),
);
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/features/auth/session_controller_test.dart`
Expected: PASS (9 test).

- [ ] **Step 5: commit**

```bash
git add lib/app/providers.dart lib/features/auth test/features/auth/session_controller_test.dart
git commit -m "feat: add session state controller and providers"
```

---

### Task 12: router e redirect in base alla sessione

**Files:**
- Create: `lib/app/router.dart`
- Create (provvisori, completati nei task successivi): `lib/features/startup/splash_screen.dart`, `lib/features/startup/unreachable_screen.dart`, `lib/features/auth/login_screen.dart`, `lib/features/home/home_screen.dart`, `lib/app/app_shell.dart`
- Test: `test/app/router_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/router_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/router.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../support/test_data.dart';

void main() {
  const signedIn = SessionSignedIn(testUser);

  test('avvio: tutto porta allo splash', () {
    expect(sessionRedirect(const SessionStarting(), '/home'), '/splash');
    expect(sessionRedirect(const SessionStarting(), '/splash'), isNull);
  });

  test('non autenticato: tutto porta al login', () {
    expect(sessionRedirect(const SessionSignedOut(), '/home'), '/login');
    expect(sessionRedirect(const SessionSignedOut(), '/login'), isNull);
  });

  test('server irraggiungibile: schermata dedicata', () {
    expect(sessionRedirect(const SessionUnreachable(), '/splash'),
        '/unreachable');
    expect(sessionRedirect(const SessionUnreachable(), '/unreachable'), isNull);
  });

  test('autenticato: dalle schermate di ingresso alla Home, altrimenti resta',
      () {
    expect(sessionRedirect(signedIn, '/splash'), '/home');
    expect(sessionRedirect(signedIn, '/login'), '/home');
    expect(sessionRedirect(signedIn, '/unreachable'), '/home');
    expect(sessionRedirect(signedIn, '/home'), isNull);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/app/router_test.dart`
Expected: FAIL.

- [ ] **Step 3: crea le schermate provvisorie**

Servono solo a far compilare il router; i task 13–16 le sostituiscono per intero.

`lib/features/startup/splash_screen.dart`:
```dart
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

`lib/features/startup/unreachable_screen.dart`:
```dart
import 'package:flutter/material.dart';

class UnreachableScreen extends StatelessWidget {
  const UnreachableScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

`lib/features/auth/login_screen.dart`:
```dart
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

`lib/features/home/home_screen.dart`:
```dart
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

`lib/app/app_shell.dart`:
```dart
import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}
```

- [ ] **Step 4: implementa il router**

`lib/app/router.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/session_controller.dart';
import '../features/home/home_screen.dart';
import '../features/startup/splash_screen.dart';
import '../features/startup/unreachable_screen.dart';
import 'app_shell.dart';

const _entryRoutes = {'/splash', '/login', '/unreachable'};

/// Dove deve stare l'utente in base allo stato di sessione.
/// `null` = la posizione attuale va bene.
String? sessionRedirect(SessionState session, String location) {
  String? goTo(String target) => location == target ? null : target;
  return switch (session) {
    SessionStarting() => goTo('/splash'),
    SessionSignedOut() => goTo('/login'),
    SessionUnreachable() => goTo('/unreachable'),
    SessionSignedIn() => _entryRoutes.contains(location) ? '/home' : null,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<SessionState>(ref.read(sessionControllerProvider));
  ref.listen(sessionControllerProvider, (_, next) => session.value = next);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) =>
        sessionRedirect(session.value, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
          path: '/unreachable',
          builder: (context, state) => const UnreachableScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    session.dispose();
  });
  return router;
});
```

- [ ] **Step 5: esegui il test**

Run: `flutter test test/app/router_test.dart`
Expected: PASS (4 test).

- [ ] **Step 6: commit**

```bash
git add lib/app/router.dart lib/app/app_shell.dart lib/features test/app/router_test.dart
git commit -m "feat: add session-driven router"
```

---

### Task 13: supporto ai widget test, schermata di avvio e server irraggiungibile

**Files:**
- Create: `test/support/fake_session_controller.dart`, `test/support/pump_app.dart`
- Modify (sostituzione completa): `lib/features/startup/splash_screen.dart`, `lib/features/startup/unreachable_screen.dart`
- Test: `test/features/startup/unreachable_screen_test.dart`

- [ ] **Step 1: supporto ai test**

`test/support/fake_session_controller.dart`:
```dart
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

class FakeSessionController extends SessionController {
  FakeSessionController(this.initial, {this.loginError});

  final SessionState initial;
  final Object? loginError;

  int restoreCalls = 0;
  int logoutCalls = 0;
  final loginAttempts = <(String, String)>[];
  JellyfinUser? approvedUser;

  @override
  SessionState build() => initial;

  @override
  Future<void> restore() async {
    restoreCalls++;
  }

  @override
  Future<void> loginWithPassword(String username, String password) async {
    loginAttempts.add((username, password));
    final error = loginError;
    if (error != null) throw error;
    state = SessionSignedIn(JellyfinUser(id: 'u1', name: username));
  }

  @override
  void quickConnectApproved(JellyfinUser user) {
    approvedUser = user;
    state = SessionSignedIn(user);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const SessionSignedOut();
  }
}
```

`test/support/pump_app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/config/app_config.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

final testAppConfig = AppConfig(
  serverUrl: Uri.parse('https://media.example.com'),
  githubRepo: 'owner/repo',
  discordAppId: '1',
  supportUrl: Uri.parse('https://discord.gg/abc'),
);

/// Monta [child] con tema, localizzazione italiana e provider di test.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [appConfigProvider.overrideWithValue(testAppConfig), ...overrides],
    retry: (_, _) => null,
    child: MaterialApp(
      theme: buildWonderflixTheme(),
      locale: const Locale('it'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  ));
  await tester.pump();
}
```

- [ ] **Step 2: scrivi il test**

`test/features/startup/unreachable_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/startup/unreachable_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('riprova da solo ogni 15 s e con il pulsante', (tester) async {
    final fake = FakeSessionController(const SessionUnreachable());
    await pumpApp(tester, const UnreachableScreen(),
        overrides: [sessionControllerProvider.overrideWith(() => fake)]);

    expect(find.text('WonderFlix non è raggiungibile'), findsOneWidget);
    expect(fake.restoreCalls, 0);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(); // ricostruisce dopo la fine del tentativo
    expect(fake.restoreCalls, 1);

    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(fake.restoreCalls, 2);
  });
}
```

- [ ] **Step 3: esegui il test**

Run: `flutter test test/features/startup/unreachable_screen_test.dart`
Expected: FAIL (la schermata provvisoria non contiene testo).

- [ ] **Step 4: implementa le schermate**

`lib/features/startup/splash_screen.dart`:
```dart
import 'package:flutter/material.dart';

/// Visibile mentre `SessionController.restore()` verifica il token salvato.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/brand/logo.png', width: 220),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
```

`lib/features/startup/unreachable_screen.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';

class UnreachableScreen extends ConsumerStatefulWidget {
  const UnreachableScreen({super.key});

  static const retryInterval = Duration(seconds: 15);

  @override
  ConsumerState<UnreachableScreen> createState() => _UnreachableScreenState();
}

class _UnreachableScreenState extends ConsumerState<UnreachableScreen> {
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        UnreachableScreen.retryInterval, (_) => unawaited(_retry()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionControllerProvider.notifier).restore();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, size: 48, color: WfColors.gold),
            const SizedBox(height: 20),
            Text(l.unreachableTitle, style: WfText.display(36)),
            const SizedBox(height: 8),
            Text(l.unreachableBody,
                style: const TextStyle(color: WfColors.creamMuted)),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: FilledButton(
                onPressed: _busy ? null : _retry,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: WfColors.bg),
                      )
                    : Text(l.retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```
(Se l'import di `lucide_icons_flutter` fallisce, controlla il nome del file nel README del pacchetto, per esempio `package:lucide_icons_flutter/lucide_icons.dart`, e correggilo **ovunque** nel piano.)

- [ ] **Step 5: esegui il test**

Run: `flutter test test/features/startup/unreachable_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add lib/features/startup test/support test/features/startup
git commit -m "feat: add splash and server-unreachable screens"
```

---

### Task 14: login con password

**Files:**
- Create: `lib/features/auth/password_login_form.dart`
- Modify (sostituzione completa): `lib/features/auth/login_screen.dart`
- Test: `test/features/auth/login_screen_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/auth/login_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';

void main() {
  Future<FakeSessionController> pumpLogin(
    WidgetTester tester, {
    SessionState initial = const SessionSignedOut(),
    Object? loginError,
    bool quickConnect = false,
  }) async {
    final fake = FakeSessionController(initial, loginError: loginError);
    await pumpApp(tester, const LoginScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
    ]);
    await tester.pump();
    return fake;
  }

  testWidgets('invia nome utente e password', (tester) async {
    final fake = await pumpLogin(tester);

    await tester.enterText(find.byKey(const Key('login-username')), 'mario');
    await tester.enterText(find.byKey(const Key('login-password')), 'segreta');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(fake.loginAttempts, [('mario', 'segreta')]);
  });

  testWidgets('credenziali errate: mostra il messaggio', (tester) async {
    await pumpLogin(tester, loginError: const UnauthorizedException());

    await tester.enterText(find.byKey(const Key('login-username')), 'mario');
    await tester.enterText(find.byKey(const Key('login-password')), 'x');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Nome utente o password errati.'), findsOneWidget);
  });

  testWidgets('sessione scaduta: mostra l\'avviso', (tester) async {
    await pumpLogin(tester, initial: const SessionSignedOut(expired: true));
    expect(find.text('Sessione scaduta, accedi di nuovo.'), findsOneWidget);
  });

  testWidgets('scheda Quick Connect solo se attivo sul server', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Quick Connect'), findsNothing);
  });

  testWidgets('link di supporto visibile', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Scrivi all\'admin'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/auth/password_login_form.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'session_controller.dart';

class PasswordLoginForm extends ConsumerStatefulWidget {
  const PasswordLoginForm({super.key});

  @override
  ConsumerState<PasswordLoginForm> createState() => _PasswordLoginFormState();
}

class _PasswordLoginFormState extends ConsumerState<PasswordLoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .loginWithPassword(_username.text, _password.text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final supportUrl = ref.watch(appConfigProvider).supportUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('login-username'),
          controller: _username,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(hintText: l.loginUsername),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('login-password'),
          controller: _password,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(hintText: l.loginPassword),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('login-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: WfColors.bg),
                )
              : Text(l.loginSubmit),
        ),
        if (supportUrl != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l.loginForgotPassword,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
              TextButton(
                onPressed: () => unawaited(launchUrl(supportUrl)),
                child: Text(l.loginContactAdmin),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: WfColors.error.withValues(alpha: 0.15),
        border: Border.all(color: WfColors.error.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(message,
          style: const TextStyle(color: Color(0xFFF0B4AD), fontSize: 12.5)),
    );
  }
}
```

`lib/features/auth/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'auth_providers.dart';
import 'password_login_form.dart';
import 'quick_connect_panel.dart';
import 'session_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final quickConnect = ref.watch(quickConnectEnabledProvider).value ?? false;
    final expired = session is SessionSignedOut && session.expired;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/logo.png', width: 280),
              const SizedBox(width: 56),
              Container(
                width: 380,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: WfColors.surface,
                  border: Border.all(color: WfColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (expired) ...[
                      ErrorBanner(l.sessionExpired),
                      const SizedBox(height: 12),
                    ],
                    if (quickConnect)
                      DefaultTabController(
                        length: 2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TabBar(
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              tabs: [
                                Tab(text: l.loginTabPassword),
                                Tab(text: l.loginTabQuickConnect),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const SizedBox(
                              height: 300,
                              child: TabBarView(children: [
                                PasswordLoginForm(),
                                QuickConnectPanel(),
                              ]),
                            ),
                          ],
                        ),
                      )
                    else
                      const PasswordLoginForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`lib/features/auth/quick_connect_panel.dart` (provvisorio, completato nel Task 15):
```dart
import 'package:flutter/material.dart';

class QuickConnectPanel extends StatelessWidget {
  const QuickConnectPanel({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: PASS (5 test).

- [ ] **Step 5: commit**

```bash
git add lib/features/auth test/features/auth/login_screen_test.dart
git commit -m "feat: add login screen with password form"
```

---

### Task 15: scheda Quick Connect

**Files:**
- Modify (sostituzione completa): `lib/features/auth/quick_connect_panel.dart`
- Test: `test/features/auth/quick_connect_panel_test.dart`

- [ ] **Step 1: scrivi il test**

`test/features/auth/quick_connect_panel_test.dart`:
```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/quick_connect_flow.dart';
import 'package:wonderflix/features/auth/quick_connect_panel.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

class FakeRunner implements QuickConnectRunner {
  final controllers = <StreamController<QcState>>[];

  StreamController<QcState> get current => controllers.last;

  @override
  Stream<QcState> run() {
    controllers.add(StreamController<QcState>());
    return current.stream;
  }
}

void main() {
  test('formatta il codice a gruppi di tre', () {
    expect(formatQuickConnectCode('482913'), '482 913');
    expect(formatQuickConnectCode('12345'), '12345');
  });

  testWidgets('mostra il codice e completa il login quando approvato',
      (tester) async {
    final runner = FakeRunner();
    final session = FakeSessionController(const SessionSignedOut());
    await pumpApp(tester, const QuickConnectPanel(), overrides: [
      quickConnectRunnerProvider.overrideWithValue(runner),
      sessionControllerProvider.overrideWith(() => session),
    ]);

    runner.current.add(const QcWaiting('482913'));
    await tester.pump();
    expect(find.text('482 913'), findsOneWidget);
    expect(find.text('In attesa di approvazione…'), findsOneWidget);

    runner.current.add(const QcApproved(testUser));
    await tester.pump();
    expect(session.approvedUser?.id, 'u1');
  });

  testWidgets('errore: pulsante Riprova riavvia il flusso', (tester) async {
    final runner = FakeRunner();
    await pumpApp(tester, const QuickConnectPanel(), overrides: [
      quickConnectRunnerProvider.overrideWithValue(runner),
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(const SessionSignedOut())),
    ]);

    runner.current.add(const QcError(ServerUnreachableException()));
    await tester.pump();
    await tester.tap(find.text('Riprova'));
    await tester.pump();

    expect(runner.controllers.length, 2);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/features/auth/quick_connect_panel_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/features/auth/quick_connect_panel.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'auth_providers.dart';
import 'quick_connect_flow.dart';
import 'session_controller.dart';

String formatQuickConnectCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

class QuickConnectPanel extends ConsumerStatefulWidget {
  const QuickConnectPanel({super.key});

  @override
  ConsumerState<QuickConnectPanel> createState() => _QuickConnectPanelState();
}

class _QuickConnectPanelState extends ConsumerState<QuickConnectPanel> {
  StreamSubscription<QcState>? _subscription;
  QcState _state = const QcLoading();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription =
        ref.read(quickConnectRunnerProvider).run().listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state is QcApproved) {
        ref.read(sessionControllerProvider.notifier).quickConnectApproved(state.user);
      }
    });
  }

  void _restart() {
    setState(() => _state = const QcLoading());
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12.5, height: 1.45);
    const spinner = Center(
      child: SizedBox(
          width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
    );

    return switch (_state) {
      QcLoading() || QcApproved() => spinner,
      QcDisabled() => Text(l.quickConnectDisabled, style: muted),
      QcWaiting(:final code) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.quickConnectYourCode),
            const SizedBox(height: 6),
            Text(
              formatQuickConnectCode(code),
              textAlign: TextAlign.center,
              style: WfText.display(52, color: WfColors.gold)
                  .copyWith(letterSpacing: 10),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(l.quickConnectWaiting),
              ],
            ),
            const SizedBox(height: 14),
            Text(l.quickConnectHelp, style: muted),
          ],
        ),
      QcError(:final error) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(describeError(l, error), style: muted),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _restart, child: Text(l.retry)),
          ],
        ),
    };
  }
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/auth`
Expected: PASS (tutti).

- [ ] **Step 5: commit**

```bash
git add lib/features/auth/quick_connect_panel.dart test/features/auth/quick_connect_panel_test.dart
git commit -m "feat: add Quick Connect login tab"
```

---

### Task 16: barra superiore, menu utente e Home provvisoria

**Files:**
- Modify (sostituzione completa): `lib/app/app_shell.dart`, `lib/features/home/home_screen.dart`
- Test: `test/app/app_shell_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/app_shell_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_screen.dart';

import '../support/fake_session_controller.dart';
import '../support/pump_app.dart';
import '../support/test_data.dart';

void main() {
  testWidgets('mostra utente e Home, e fa il logout dal menu', (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: HomeScreen()),
      overrides: [sessionControllerProvider.overrideWith(() => fake)],
    );

    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ciao, Mario'), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();

    expect(fake.logoutCalls, 1);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/app/app_shell_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa**

`lib/app/app_shell.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/auth_models.dart';
import '../features/auth/session_controller.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';

/// Struttura comune alle schermate autenticate: barra superiore + contenuto.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Image.asset('assets/brand/logo.png', height: 40),
                const SizedBox(width: 32),
                _NavItem(
                  label: l.navHome,
                  active: location.startsWith('/home'),
                  onTap: () => context.go('/home'),
                ),
                const Spacer(),
                if (user != null) _UserMenu(user: user),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: active ? WfColors.gold : Colors.transparent, width: 2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? WfColors.gold : WfColors.cream,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user});

  final JellyfinUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final initial = user.name.isEmpty ? '?' : user.name[0].toUpperCase();
    return PopupMenuButton<String>(
      key: const Key('user-menu'),
      tooltip: user.name,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'logout') {
          unawaited(ref.read(sessionControllerProvider.notifier).logout());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.menuLogout),
            ],
          ),
        ),
      ],
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: WfColors.gold,
            child: Text(initial,
                style: const TextStyle(
                    color: WfColors.bg, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(user.name),
        ],
      ),
    );
  }
}
```

`lib/features/home/home_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';

/// Home provvisoria: il Piano 2 la sostituisce con righe e catalogo.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final name = session is SessionSignedIn ? session.user.name : '';
    return Center(
      child: Text(AppLocalizations.of(context).homeWelcome(name),
          style: WfText.display(56)),
    );
  }
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/app/app_shell_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/app/app_shell.dart lib/features/home test/app/app_shell_test.dart
git commit -m "feat: add top bar with user menu and placeholder home"
```

---

### Task 17: bootstrap, finestra, istanza singola, README

**Files:**
- Create: `lib/app/app.dart`, `lib/app/config_error_app.dart`, `lib/app/window_setup.dart`
- Modify (sostituzione completa): `lib/main.dart`, `README.md`
- Modify: `windows/runner/main.cpp`, `windows/runner/flutter_window.cpp`, `windows/runner/Runner.rc`
- Test: `test/app/window_setup_test.dart`

- [ ] **Step 1: scrivi il test delle funzioni pure della finestra**

`test/app/window_setup_test.dart`:
```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/window_setup.dart';

void main() {
  test('codifica e decodifica i bordi della finestra', () {
    const rect = Rect.fromLTWH(10, 20, 1280, 800);
    expect(parseBounds(encodeBounds(rect)), rect);
  });

  test('valori non validi o troppo piccoli vengono ignorati', () {
    expect(parseBounds(null), isNull);
    expect(parseBounds('a,b,c,d'), isNull);
    expect(parseBounds('0,0,100,100'), isNull);
  });
}
```

- [ ] **Step 2: esegui il test**

Run: `flutter test test/app/window_setup_test.dart`
Expected: FAIL.

- [ ] **Step 3: implementa la gestione della finestra**

`lib/app/window_setup.dart`:
```dart
import 'dart:async';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _boundsKey = 'window_bounds';
const minWindowSize = Size(1024, 640);

String encodeBounds(Rect r) => '${r.left},${r.top},${r.width},${r.height}';

Rect? parseBounds(String? value) {
  final parts = value?.split(',').map(double.tryParse).toList();
  if (parts == null || parts.length != 4 || parts.contains(null)) return null;
  final rect = Rect.fromLTWH(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  if (rect.width < minWindowSize.width || rect.height < minWindowSize.height) {
    return null;
  }
  return rect;
}

/// Titolo, dimensione minima, posizione ricordata. La finestra viene mostrata
/// solo quando è pronta (niente lampo bianco all'avvio).
Future<void> setupWindow(SharedPreferences prefs) async {
  await windowManager.ensureInitialized();
  final saved = parseBounds(prefs.getString(_boundsKey));
  const options = WindowOptions(
    title: 'WonderFlix',
    size: Size(1440, 900),
    minimumSize: minWindowSize,
    center: true,
    backgroundColor: Color(0xFF0A0A0A),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (saved != null) await windowManager.setBounds(saved);
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(_BoundsSaver(prefs));
}

class _BoundsSaver with WindowListener {
  _BoundsSaver(this._prefs);

  final SharedPreferences _prefs;

  Future<void> _save() async {
    if (await windowManager.isMaximized() || await windowManager.isFullScreen()) {
      return;
    }
    await _prefs.setString(_boundsKey, encodeBounds(await windowManager.getBounds()));
  }

  @override
  void onWindowResized() => unawaited(_save());

  @override
  void onWindowMoved() => unawaited(_save());
}
```

- [ ] **Step 4: esegui il test**

Run: `flutter test test/app/window_setup_test.dart`
Expected: PASS.

- [ ] **Step 5: app e bootstrap**

`lib/app/app.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/session_controller.dart';
import '../l10n/gen/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class WonderflixApp extends ConsumerStatefulWidget {
  const WonderflixApp({super.key});

  @override
  ConsumerState<WonderflixApp> createState() => _WonderflixAppState();
}

class _WonderflixAppState extends ConsumerState<WonderflixApp> {
  @override
  void initState() {
    super.initState();
    // Una sola volta all'avvio: verifica il token salvato.
    unawaited(ref.read(sessionControllerProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WonderFlix',
      debugShowCheckedModeBanner: false,
      theme: buildWonderflixTheme(),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Italiano per primo: è la lingua di ripiego se Windows usa altre lingue.
      supportedLocales: const [Locale('it'), Locale('en')],
    );
  }
}
```

`lib/app/config_error_app.dart`:
```dart
import 'package:flutter/material.dart';

import 'theme.dart';

/// Mostrata quando l'app è stata compilata senza `config/wonderflix.json`.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildWonderflixTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Configurazione mancante.\n\n$message\n\n'
              'Avvia con: flutter run -d windows '
              '--dart-define-from-file=config/wonderflix.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
```

`lib/main.dart`:
```dart
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
```

- [ ] **Step 6: runner Windows**

In `windows/runner/main.cpp`, subito dopo la riga di apertura di `wWinMain(...) {`, inserisci:
```cpp
  // Una sola istanza: se WonderFlix è già aperto, porta in primo piano quella finestra.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\WonderFlix.SingleInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"WonderFlix");
    if (existing != nullptr) {
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }
```
Nello stesso file sostituisci `window.Create(L"wonderflix", origin, size)` con `window.Create(L"WonderFlix", origin, size)`.

In `windows/runner/flutter_window.cpp`, dentro `SetNextFrameCallback`, sostituisci la riga `this->Show();` con:
```cpp
    // La finestra la mostra window_manager (waitUntilReadyToShow).
```

In `windows/runner/Runner.rc` sostituisci i valori:
- `VALUE "FileDescription", "wonderflix"` → `VALUE "FileDescription", "WonderFlix"`
- `VALUE "ProductName", "wonderflix"` → `VALUE "ProductName", "WonderFlix"`
- `VALUE "InternalName", "wonderflix"` → `VALUE "InternalName", "WonderFlix"`

- [ ] **Step 7: README (sovrascrivi)**

`README.md`:
````markdown
# WonderFlix

Client desktop Windows per il server Jellyfin WonderFlix.

## Sviluppo

Requisiti: Flutter 3.35.x (stable) con Visual Studio Build Tools (workload "Desktop development with C++").

1. Copia `config/wonderflix.example.json` in `config/wonderflix.json` e inserisci l'indirizzo del server (il file è in `.gitignore`).
2. Avvia:

   ```bash
   flutter run -d windows --dart-define-from-file=config/wonderflix.json
   ```

Test: `flutter test` · Analisi: `flutter analyze` · Localizzazioni: `flutter gen-l10n`

Design: `docs/superpowers/specs/` · Piani: `docs/superpowers/plans/`
````

- [ ] **Step 8: test completi e analisi**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` e `All tests passed!`.

- [ ] **Step 9: verifica manuale sul server reale**

Crea `config/wonderflix.json` con l'indirizzo reale (chiedilo all'utente se non c'è), poi:
```bash
flutter run -d windows --dart-define-from-file=config/wonderflix.json
```
Checklist (tutte da verificare a mano; annota l'esito nel messaggio finale):
1. Appare lo splash e poi la schermata di login, senza richiesta del server.
2. Password errata: messaggio "Nome utente o password errati.".
3. Login corretto: si arriva a "Ciao, <nome>". Nella dashboard Jellyfin → Dispositivi compare "WonderFlix" con il nome del PC.
4. Chiudi e riapri l'app: si entra direttamente senza login.
5. Menu utente → Esci: si torna al login. Riaprendo, viene chiesto di nuovo il login.
6. Quick Connect (se attivo sul server): il codice compare; approvandolo da jellyfin-web (Impostazioni → Quick Connect) si entra.
7. Rete scollegata all'avvio (con la sessione salvata): schermata "WonderFlix non è raggiungibile". Riconnetti: entro 15 s si arriva alla Home.
8. Lancia l'app una seconda volta: non si apre una seconda finestra, torna in primo piano quella esistente.
9. Ridimensiona e sposta la finestra, chiudi e riapri: la posizione viene ricordata.

- [ ] **Step 10: commit**

```bash
git add lib windows README.md test/app/window_setup_test.dart
git commit -m "feat: bootstrap app with window setup and single instance"
```

---

### Task 18: CI su GitHub Actions

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: crea il workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.35.6
          cache: true

      - run: flutter pub get
      - run: flutter gen-l10n
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 2: verifica locale degli stessi comandi**

Run: `flutter pub get && flutter gen-l10n && flutter analyze && flutter test`
Expected: tutto verde.

- [ ] **Step 3: commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run analyze and tests on push and pull requests"
```

(Il push non fa parte del piano: lo decide l'utente.)
