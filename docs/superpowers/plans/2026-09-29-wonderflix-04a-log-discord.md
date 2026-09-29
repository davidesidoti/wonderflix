# WonderFlix — Piano 4a: log, diagnostica e Discord

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte "in app" del Piano 4, che non dipende da release e installer:
- **log su file** a rotazione in `%LocalAppData%\WonderFlix\logs` (5 file da 2 MB), senza token, password né header `Authorization` (spec §11);
- **tutti i `debugPrint`** diventano messaggi di log; anche gli errori non gestiti e le richieste HTTP fallite finiscono nel log;
- **"Copia diagnostica"** nelle Impostazioni: versione dell'app, di Windows e del server, impostazioni del player e di Discord, ultimi 50 errori; più **"Apri la cartella dei log"**;
- **Discord Rich Presence** (spec §8): attività *Watching* con titolo, "S1:E4 · titolo" o anno, tempo trascorso e rimanente, locandina o logo, pulsante verso `supportUrl`; "In pausa" senza tempi; cancellata fuori dal player; nuovo tentativo ogni 30 s se Discord è chiuso; impostazioni *mostra attività*, *mostra titolo*, *mostra locandina*.

**Architecture:**
- **Log (`lib/core/logging/`):**
  - `redactSecrets` toglie i segreti da ogni riga;
  - `RotatingFileSink` scrive e ruota i file;
  - `AppLog` ascolta `Logger.root` (pacchetto `logging`), scrive nel file e tiene in memoria gli ultimi 50 avvisi ed errori;
  - `main` lo attiva per primo e ci manda anche `FlutterError.onError` e gli errori non gestiti.
- **Discord, protocollo (`lib/core/discord/`):**
  - `discord_ipc.dart`: frame (8 byte di intestazione little-endian + JSON), `DiscordPipe` (interfaccia), `DiscordIpcClient` (handshake, attesa di `READY`, `SET_ACTIVITY`);
  - `windows_discord_pipe.dart`: la named pipe `\\.\pipe\discord-ipc-0..9` con FFI diretto su `kernel32.dll` (nessun pacchetto Discord: quelli esistenti bloccano l'app, sono in conflitto con `win32` 6 o usano `flutter_rust_bridge`, fissato per SMTC).
- **Discord, logica (`lib/features/discord/`):**
  - `buildDiscordActivity` (pura) costruisce l'attività da stato e impostazioni;
  - `DiscordPresence` **implementa `MediaSession`**: il player la aggiorna esattamente come il pannello SMTC, quindi `player_screen.dart` non cambia;
  - si collega solo quando c'è qualcosa da mostrare, invia al massimo un aggiornamento ogni 5 s (limite di Discord: 5 ogni 20 s), riprova ogni 30 s.
- **Sessione media combinata:** `MirroredMediaSession` inoltra gli aggiornamenti al pannello di sistema (che gestisce anche i tasti) e a Discord. `mediaSessionProvider` la costruisce da `systemMediaSessionProvider` (SMTC in `main`) e `discordSessionProvider` (Discord in `main`).
- **Impostazioni:** nuove sezioni "Discord" e "Supporto".

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, `logging` 1.3.0, `ffi` 2.2.0 (`dart:ffi` su `kernel32.dll`), `clock` 1.1.3 (orologio sostituibile nei test con fake_async), shared_preferences, url_launcher.

**Spec:** `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md`, sezioni 8 e 11. **Passaggio di consegne:** `docs/superpowers/handoff/2026-09-29-handoff-piano-4.md`. Il resto del Piano 4 (aggiornamenti, installer, release) è il **Piano 4b**.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/logs-discord`, branch `feat/logs-discord`). Comandi git semplici, non composti con variabili.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca, esegui prima `flutter gen-l10n`.
- **File generati:** `flutter test` e `flutter pub get` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga. Se `git diff windows/flutter/` non mostra cambi di contenuto, esegui `git checkout -- windows/flutter/` prima del commit. In questo piano non si aggiungono plugin nativi.
- **Formattazione:** non eseguire `dart format` su file interi (il progetto non è nello stile "tall" e verrebbe riscritto tutto).
- **Import:** se l'analyzer segnala un import superfluo (`unnecessary_import`, `unused_import`) o mancante, correggilo e segnalalo. `debugPrint` e `kDebugMode` possono arrivare già da `material.dart`.
- **Lint `use_null_aware_elements`:** nelle mappe scrivi `'key': ?value`.
- **Icone:** solo `LucideIcons` (verificate sulla 3.1.20: `clipboardCopy`, `folderOpen`), niente emoji.
- **Widget test:**
  - `pumpApp` (`test/support/pump_app.dart`) ha il parametro `surfaceSize`; non chiamare `setSurfaceSize` prima.
  - `pumpApp` non mette uno `Scaffold`: SnackBar e Switch lo richiedono (`Scaffold(body: …)`).
  - Nelle Impostazioni (una `SingleChildScrollView`) usa `await tester.ensureVisible(finder)` prima di `tap`.
- **Log nei test:** nei test nessuno ascolta `Logger.root`, quindi i messaggi non compaiono. I test che li verificano si iscrivono a `Logger.root.onRecord` e cancellano l'iscrizione con `addTearDown`.
- **Fake:** niente mocktail. `FakeMediaSession` è in `test/support/playback_fakes.dart`; `FakeDiscordPipe` (nuovo, Task 6) in `test/support/discord_fakes.dart`; `FakeSystemApi` (nuovo, Task 11) in `test/support/settings_fakes.dart`.

## Note tecniche verificate

- **Pacchetti:** `logging` 1.3.0, `ffi` 2.2.0 e `clock` 1.1.3 sono già nel `pubspec.lock` come dipendenze indirette: il Task 2 li rende diretti con `flutter pub add`, senza cambiare versione.
- **`logging`:**
  - `Logger('nome')`, `Logger.root.level = Level.ALL`, `Logger.root.onRecord` (stream di `LogRecord`: `level`, `message`, `loggerName`, `time`, `error`, `stackTrace`);
  - i livelli si confrontano con `>=`;
  - costruttore `LogRecord(level, message, loggerName, [error, stackTrace])`.
- **Discord IPC** (stesso protocollo della libreria ufficiale `discord-rpc`):
  - pipe `\\.\pipe\discord-ipc-N` con N da 0 a 9: si usa la prima che si apre;
  - ogni frame: opcode (uint32 little-endian), lunghezza del JSON (uint32 little-endian), JSON UTF-8. Opcode: 0 handshake, 1 frame, 2 close, 3 ping, 4 pong;
  - handshake: opcode 0 con `{"v": 1, "client_id": "<Application ID>"}`. Risposta: opcode 1 con `"evt": "READY"`. Con un ID non valido Discord risponde opcode 2 (`{"code": 4000, "message": "Invalid Client ID"}`) e chiude;
  - attività: opcode 1 con `{"cmd": "SET_ACTIVITY", "args": {"pid": <pid>, "activity": {…}}, "nonce": "<unico>"}`. Senza `activity` l'attività si cancella;
  - ai ping (opcode 3) si risponde con un pong (opcode 4) con lo stesso JSON.
- **Attività:**
  - `type` 3 = *Watching* (con `SET_ACTIVITY` sono ammessi solo 0, 2, 3, 5);
  - `details` e `state`: da 2 a 128 caratteri;
  - `timestamps.start` / `timestamps.end` in millisecondi Unix: Discord mostra la barra di avanzamento;
  - `assets.large_image`: nome di un asset dell'app sul Developer Portal (qui `logo`) oppure un URL https esterno. Le immagini di Jellyfin (`/Items/{id}/Images/Primary`) non richiedono il token;
  - `buttons`: al massimo 2, `{label (max 32 caratteri), url}`. **Chi li ha impostati non li vede**: li vedono gli altri utenti;
  - limite: 5 aggiornamenti ogni 20 s. Il piano ne invia al massimo uno ogni 5 s.
- **FFI su `kernel32.dll`:** `CreateFileW` (`GENERIC_READ | GENERIC_WRITE` = `0xC0000000`, `OPEN_EXISTING` = 3) restituisce `INVALID_HANDLE_VALUE` (indirizzo -1) se la pipe non esiste o è occupata. `PeekNamedPipe` dice quanti byte si possono leggere senza bloccare; `ReadFile`/`WriteFile` sincroni; `CloseHandle`. `toNativeUtf16()` alloca con `malloc`: si libera con `malloc.free`.
- **Versione del server:** `GET /System/Info/Public` (senza autenticazione) → `{"Version": "10.11.9", …}`.
- **Versione di Windows:** `Platform.operatingSystemVersion` (es. `"Windows 11 Pro" 10.0 (Build 26200)`).
- **Cartella dei log:** `Platform.environment['LOCALAPPDATA']` + `\WonderFlix\logs`; si apre in Esplora risorse con `launchUrl(Uri.file(percorso, windows: true))`.
- **fake_async e `clock`:** dentro `fakeAsync` il `clock.now()` del pacchetto `clock` segue il tempo finto. `DiscordPresence` usa `clock.now()`.

## Mappa dei file

```
lib/core/logging/redact.dart                  redactSecrets
lib/core/logging/rotating_file_sink.dart      RotatingFileSink
lib/core/logging/app_log.dart                 AppLog, formatLogRecord, logsDirectory, appLogProvider, logsDirectoryProvider
lib/core/discord/discord_ipc.dart             DiscordOpcode, DiscordFrame, encodeDiscordFrame, DiscordFrameReader, DiscordPipe, DiscordPipeException, DiscordIpcClient
lib/core/discord/windows_discord_pipe.dart    WindowsDiscordPipe (FFI)
lib/core/media_session/mirrored_media_session.dart MirroredMediaSession
lib/core/jellyfin/jellyfin_http.dart          (+ log delle richieste fallite)
lib/core/jellyfin/system_api.dart             SystemApi.serverVersion
lib/features/discord/discord_settings.dart    DiscordSettings, DiscordSettingsController, discordSettingsProvider
lib/features/discord/discord_activity.dart    DiscordLabels, buildDiscordActivity, discordText
lib/features/discord/discord_presence.dart    DiscordPresence (MediaSession)
lib/features/discord/discord_providers.dart   discordLabelsProvider, discordPipeFactoryProvider, discordSessionProvider, createDiscordPresence
lib/features/player/player_providers.dart     (+ systemMediaSessionProvider; mediaSessionProvider combinata)
lib/features/settings/diagnostics.dart        buildDiagnostics, collectDiagnosticsProvider, openLogsFolderProvider
lib/features/settings/discord_settings_section.dart DiscordSettingsSection
lib/features/settings/support_section.dart    SupportSection
lib/features/settings/settings_screen.dart    (+ sezioni Discord e Supporto)
lib/app/providers.dart                        (+ systemApiProvider)
lib/main.dart                                 (+ log, errori non gestiti, sessioni media)
debugPrint sostituiti: lib/core/media_session/smtc_media_session.dart, lib/core/video/media_kit_engine.dart,
  lib/features/playback/play_launcher.dart, lib/features/player/player_controller.dart, lib/features/player/progress_reporter.dart
l10n/app_it.arb, l10n/app_en.arb             (nuove stringhe)
pubspec.yaml, pubspec.lock                    (+ logging, ffi, clock)
test/support/discord_fakes.dart               FakeDiscordPipe
test/support/settings_fakes.dart              (+ FakeSystemApi)
```

---

### Task 1: stringhe del Piano 4a

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan4a_test.dart`

- [ ] **Step 1: scrivi il test** `test/app/l10n_plan4a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 4a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.discordPaused, 'In pausa');
    expect(en.discordPaused, 'Paused');
    expect(it.discordJoinButton, 'Entra in WonderFlix');
    expect(en.discordJoinButton, 'Join WonderFlix');
    // Limite di Discord per le etichette dei pulsanti.
    expect(it.discordJoinButton.length, lessThanOrEqualTo(32));
    expect(en.discordJoinButton.length, lessThanOrEqualTo(32));
    expect(it.settingsDiscordEnabled, 'Mostra su Discord cosa sto guardando');
    expect(it.settingsCopyDiagnostics, 'Copia diagnostica');
    expect(en.settingsCopyDiagnostics, 'Copy diagnostics');
    expect(it.settingsDiagnosticsCopied, 'Diagnostica copiata negli appunti');
    expect(en.settingsOpenLogs, 'Open the log folder');
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/app/l10n_plan4a_test.dart`
Expected: FAIL (errore di compilazione: `discordPaused` non esiste).

- [ ] **Step 3: aggiungi le stringhe.** In `l10n/app_it.arb`, dopo `"settingsSaveError": "Impossibile salvare. Riprova."` (metti la virgola dopo quella riga):

```json
  "discordPaused": "In pausa",
  "discordJoinButton": "Entra in WonderFlix",
  "settingsDiscord": "Discord",
  "settingsDiscordEnabled": "Mostra su Discord cosa sto guardando",
  "settingsDiscordShowTitle": "Mostra il titolo",
  "settingsDiscordShowPoster": "Mostra la locandina",
  "settingsDiscordPosterHint": "La locandina rende visibile agli amici su Discord l'indirizzo del server.",
  "settingsSupport": "Supporto",
  "settingsSupportHint": "Per chiedere aiuto, copia la diagnostica e incollala nel messaggio.",
  "settingsCopyDiagnostics": "Copia diagnostica",
  "settingsDiagnosticsCopied": "Diagnostica copiata negli appunti",
  "settingsOpenLogs": "Apri la cartella dei log"
```

In `l10n/app_en.arb`, alla fine allo stesso modo:

```json
  "discordPaused": "Paused",
  "discordJoinButton": "Join WonderFlix",
  "settingsDiscord": "Discord",
  "settingsDiscordEnabled": "Show what I'm watching on Discord",
  "settingsDiscordShowTitle": "Show the title",
  "settingsDiscordShowPoster": "Show the poster",
  "settingsDiscordPosterHint": "The poster lets your Discord friends see the server address.",
  "settingsSupport": "Support",
  "settingsSupportHint": "To ask for help, copy the diagnostics and paste them into your message.",
  "settingsCopyDiagnostics": "Copy diagnostics",
  "settingsDiagnosticsCopied": "Diagnostics copied to the clipboard",
  "settingsOpenLogs": "Open the log folder"
```

- [ ] **Step 4: genera e verifica**

Run: `flutter gen-l10n && flutter test test/app/l10n_plan4a_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan4a_test.dart
git commit -m "feat: add strings for logs, diagnostics and Discord"
```

---

### Task 2: mascheramento dei segreti

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Create: `lib/core/logging/redact.dart`
- Test: `test/core/logging/redact_test.dart`

- [ ] **Step 1: dipendenze**

```bash
flutter pub add logging ffi clock
grep -E "^  (logging|ffi|clock):" -A5 pubspec.lock | grep version
```
Expected: `logging` 1.3.0, `ffi` 2.2.0, `clock` 1.1.3 (le stesse versioni di prima, ora dirette). Se una versione è diversa, segnalalo.

- [ ] **Step 2: scrivi il test** `test/core/logging/redact_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/logging/redact.dart';

void main() {
  test('header MediaBrowser: via il token', () {
    expect(
        redactSecrets('MediaBrowser Client="WonderFlix", Token="abc123"'),
        'MediaBrowser Client="WonderFlix", Token="***"');
  });

  test('parametri dell\'indirizzo', () {
    expect(redactSecrets('GET /Videos/1/stream?api_key=abc&static=true'),
        'GET /Videos/1/stream?api_key=***&static=true');
    expect(redactSecrets('https://x/a?ApiKey=zz'), 'https://x/a?ApiKey=***');
  });

  test('JSON con password e token', () {
    expect(
        redactSecrets(
            '{"Username":"mario","Pw":"segreta","AccessToken": "t0k"}'),
        '{"Username":"mario","Pw":"***","AccessToken":"***"}');
  });

  test('header Authorization scritto per intero', () {
    expect(
        redactSecrets(
            'headers: {Authorization: MediaBrowser Client="W", Token="x"}'),
        'headers: {Authorization: ***');
  });

  test('testo senza segreti: invariato', () {
    const text = 'direct play non riuscito: provo la transcodifica';
    expect(redactSecrets(text), text);
  });
}
```

- [ ] **Step 3: esegui e verifica che fallisca**

Run: `flutter test test/core/logging/redact_test.dart`
Expected: FAIL (il file `redact.dart` non esiste).

- [ ] **Step 4: crea** `lib/core/logging/redact.dart`:

```dart
/// Toglie da un testo di log token, password e header di autenticazione.
/// Meglio togliere troppo che troppo poco: il log si allega alle richieste
/// di aiuto.
String redactSecrets(String text) {
  var result = text;
  for (final (pattern, replace) in _rules) {
    result = result.replaceAllMapped(pattern, replace);
  }
  return result;
}

final _rules = <(RegExp, String Function(Match))>[
  // Header MediaBrowser: Token="…"
  (RegExp(r'Token="[^"]*"'), (_) => 'Token="***"'),
  // Parametri dell'indirizzo: api_key=…, ApiKey=…, access_token=…
  (
    RegExp(r'\b(api_key|ApiKey|access_token|X-Emby-Token|X-MediaBrowser-Token)=[^&\s"]+',
        caseSensitive: false),
    (m) => '${m[1]}=***',
  ),
  // JSON: "AccessToken": "…", "Pw": "…", "Password": "…", "Token": "…"
  (
    RegExp(r'"(AccessToken|Pw|Password|Token)"\s*:\s*"[^"]*"',
        caseSensitive: false),
    (m) => '"${m[1]}":"***"',
  ),
  // Header scritto per intero: tutto fino a fine riga.
  (
    RegExp(r'(Authorization["\x27]?\s*[:=]\s*)[^\n]*', caseSensitive: false),
    (m) => '${m[1]}***',
  ),
];
```

- [ ] **Step 5: esegui e verifica che passi**

Run: `flutter test test/core/logging/redact_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/logging/redact.dart test/core/logging/redact_test.dart
git commit -m "feat: strip tokens and passwords from log lines"
```

---

### Task 3: file di log a rotazione

**Files:**
- Create: `lib/core/logging/rotating_file_sink.dart`
- Test: `test/core/logging/rotating_file_sink_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/logging/rotating_file_sink_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/logging/rotating_file_sink.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wf_logs_');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  String read(String name) =>
      File('${temp.path}${Platform.pathSeparator}$name').readAsStringSync();
  bool exists(String name) =>
      File('${temp.path}${Platform.pathSeparator}$name').existsSync();

  test('crea la cartella e aggiunge in coda', () {
    final dir = Directory('${temp.path}${Platform.pathSeparator}logs');
    final sink = RotatingFileSink(dir);
    sink.write('uno\n');
    sink.write('due\n');
    expect(sink.current.readAsStringSync(), 'uno\ndue\n');
    expect(sink.current.path, endsWith('wonderflix.log'));
  });

  test('ruota oltre la dimensione massima e tiene al massimo maxFiles file',
      () {
    final sink = RotatingFileSink(temp, maxBytes: 10, maxFiles: 3);
    sink.write('aaaaaaaa\n');
    sink.write('bbbbbbbb\n');
    sink.write('cccccccc\n');
    sink.write('dddddddd\n');
    expect(read('wonderflix.log'), 'dddddddd\n');
    expect(read('wonderflix.1.log'), 'cccccccc\n');
    expect(read('wonderflix.2.log'), 'bbbbbbbb\n');
    expect(exists('wonderflix.3.log'), isFalse);
  });

  test('una riga più lunga del massimo si scrive comunque', () {
    final sink = RotatingFileSink(temp, maxBytes: 4);
    sink.write('riga lunga\n');
    expect(read('wonderflix.log'), 'riga lunga\n');
  });

  test('non lancia se la cartella non si può creare', () {
    final blocker = File('${temp.path}${Platform.pathSeparator}blocco')
      ..writeAsStringSync('x');
    final sink = RotatingFileSink(Directory(blocker.path));
    expect(() => sink.write('ciao\n'), returnsNormally);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/logging/rotating_file_sink_test.dart`
Expected: FAIL (il file non esiste).

- [ ] **Step 3: crea** `lib/core/logging/rotating_file_sink.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// File di log a rotazione: `wonderflix.log` più fino a [maxFiles] - 1 file
/// precedenti (`wonderflix.1.log` è il più recente). Scrittura sincrona,
/// così le ultime righe prima di un crash restano sul disco.
///
/// Non lancia mai: un problema col disco non deve fermare l'app.
class RotatingFileSink {
  RotatingFileSink(
    this.directory, {
    this.baseName = 'wonderflix',
    this.maxBytes = 2 * 1024 * 1024,
    this.maxFiles = 5,
  });

  final Directory directory;
  final String baseName;
  final int maxBytes;
  final int maxFiles;

  /// Il file su cui si sta scrivendo.
  File get current => _file(0);

  File _file(int index) => File('${directory.path}${Platform.pathSeparator}'
      '${index == 0 ? '$baseName.log' : '$baseName.$index.log'}');

  void write(String text) {
    try {
      final bytes = utf8.encode(text);
      directory.createSync(recursive: true);
      final file = current;
      final size = file.existsSync() ? file.lengthSync() : 0;
      if (size > 0 && size + bytes.length > maxBytes) _rotate();
      current.writeAsBytesSync(bytes, mode: FileMode.append);
    } on FileSystemException {
      // Riga persa: meglio che un errore mentre si registra un errore.
    }
  }

  void _rotate() {
    final oldest = _file(maxFiles - 1);
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = maxFiles - 2; i >= 0; i--) {
      final file = _file(i);
      if (file.existsSync()) file.renameSync(_file(i + 1).path);
    }
  }
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/core/logging/rotating_file_sink_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/logging/rotating_file_sink.dart test/core/logging/rotating_file_sink_test.dart
git commit -m "feat: add a rotating log file"
```

---

### Task 4: registro dell'app (`AppLog`)

**Files:**
- Create: `lib/core/logging/app_log.dart`
- Test: `test/core/logging/app_log_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/logging/app_log_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/logging/app_log.dart';
import 'package:wonderflix/core/logging/rotating_file_sink.dart';

void main() {
  test('formato: data, livello, nome, messaggio, errore', () {
    final text = formatLogRecord(
        LogRecord(Level.WARNING, 'ciao', 'player', StateError('boom')));
    expect(
        text,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} '
            r'WARNING \[player\] ciao\n  Bad state: boom$')));
  });

  test('scrive nel file senza segreti', () {
    final temp = Directory.systemTemp.createTempSync('wf_applog_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final log = AppLog(sink: RotatingFileSink(temp));
    log.add(LogRecord(Level.INFO, 'header Token="segreto"', 'http'));
    final written = File('${temp.path}${Platform.pathSeparator}wonderflix.log')
        .readAsStringSync();
    expect(written, contains('Token="***"'));
    expect(written, isNot(contains('segreto')));
    expect(written, endsWith('\n'));
  });

  test('ultimi errori: solo avvisi ed errori, al massimo maxRecentErrors', () {
    final log = AppLog(maxRecentErrors: 2);
    log.add(LogRecord(Level.INFO, 'info', 'a'));
    log.add(LogRecord(Level.WARNING, 'primo', 'a'));
    log.add(LogRecord(Level.SEVERE, 'secondo', 'a'));
    log.add(LogRecord(Level.WARNING, 'terzo', 'a'));
    expect(log.recentErrors, hasLength(2));
    expect(log.recentErrors.first, contains('secondo'));
    expect(log.recentErrors.last, contains('terzo'));
  });

  test('attach riceve i messaggi di tutti i Logger', () async {
    final log = AppLog()..attach();
    addTearDown(log.detach);
    Logger('discord').severe('non collegato');
    await Future<void>.delayed(Duration.zero);
    expect(log.recentErrors.single, contains('[discord] non collegato'));
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/logging/app_log_test.dart`
Expected: FAIL (il file non esiste).

- [ ] **Step 3: crea** `lib/core/logging/app_log.dart`:

```dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'redact.dart';
import 'rotating_file_sink.dart';

/// Registro dell'app: riceve i messaggi di tutti i `Logger`, li scrive nel
/// file a rotazione (senza segreti) e tiene in memoria gli ultimi avvisi ed
/// errori per la diagnostica.
class AppLog {
  AppLog({this.sink, this.echo = false, this.maxRecentErrors = 50});

  final RotatingFileSink? sink;

  /// Ripete i messaggi nella console (in debug).
  final bool echo;
  final int maxRecentErrors;

  final _recentErrors = ListQueue<String>();
  StreamSubscription<LogRecord>? _subscription;

  /// Ultimi avvisi ed errori, dal più vecchio, già senza segreti.
  List<String> get recentErrors => List.unmodifiable(_recentErrors);

  /// Inizia ad ascoltare `Logger.root` (tutti i livelli).
  void attach() {
    Logger.root.level = Level.ALL;
    _subscription ??= Logger.root.onRecord.listen(add);
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void add(LogRecord record) {
    final text = redactSecrets(formatLogRecord(record));
    sink?.write('$text\n');
    if (echo) debugPrint(text);
    if (record.level >= Level.WARNING) {
      _recentErrors.addLast(text);
      while (_recentErrors.length > maxRecentErrors) {
        _recentErrors.removeFirst();
      }
    }
  }
}

/// `2026-09-29 21:15:03.042 WARNING [player] messaggio`, con errore e stack
/// trace sulle righe seguenti.
String formatLogRecord(LogRecord record) {
  final t = record.time;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
  final buffer = StringBuffer(
      '$time ${record.level.name} [${record.loggerName}] ${record.message}');
  if (record.error != null) buffer.write('\n  ${record.error}');
  if (record.stackTrace != null) buffer.write('\n${record.stackTrace}');
  return buffer.toString();
}

/// `%LocalAppData%\WonderFlix\logs` (la cartella temporanea, se la variabile
/// manca).
Directory logsDirectory() {
  final base = Platform.environment['LOCALAPPDATA'];
  final root = base == null || base.isEmpty ? Directory.systemTemp.path : base;
  return Directory('$root\\WonderFlix\\logs');
}

/// Sovrascritto in `main()` con il registro collegato al file. Di default
/// (test) tiene solo gli errori in memoria.
final appLogProvider = Provider<AppLog>((ref) => AppLog());

final logsDirectoryProvider = Provider<Directory>((ref) => logsDirectory());
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/core/logging/app_log_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/logging/app_log.dart test/core/logging/app_log_test.dart
git commit -m "feat: collect app logs into the file and keep recent errors"
```

---

### Task 5: collegamento dei log (avvio, HTTP, `debugPrint`)

**Files:**
- Modify: `lib/main.dart`, `lib/core/jellyfin/jellyfin_http.dart`, `lib/core/media_session/smtc_media_session.dart`, `lib/core/video/media_kit_engine.dart`, `lib/features/playback/play_launcher.dart`, `lib/features/player/player_controller.dart`, `lib/features/player/progress_reporter.dart`
- Test: `test/core/jellyfin/jellyfin_http_test.dart` (aggiunta)

- [ ] **Step 1: aggiungi il test** in fondo al `main()` di `test/core/jellyfin/jellyfin_http_test.dart` (import `package:logging/logging.dart`):

```dart
  test('registra le richieste fallite, senza query né header', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    http.token = 'tok';
    adapter.handler = (_) => const FakeResponse(500);

    await expectLater(http.get('/Items/x', query: {'api_key': 'k'}),
        throwsA(isA<ApiException>()));

    expect(records.single.loggerName, 'http');
    expect(records.single.level, Level.WARNING);
    expect(records.single.message, 'GET /Items/x: 500');
  });
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/jellyfin_http_test.dart`
Expected: FAIL (`records` vuoto).

- [ ] **Step 3: log in `JellyfinHttp`.** In `lib/core/jellyfin/jellyfin_http.dart`:
- import `package:logging/logging.dart`;
- sotto gli import: `final _log = Logger('http');`
- in `_send`, all'inizio del blocco `on DioException catch (e) {`:

```dart
      // Solo metodo, percorso ed esito: query e header possono contenere
      // token. Le richieste annullate non sono errori.
      if (e.type != DioExceptionType.cancel) {
        _log.warning('${e.requestOptions.method} ${e.requestOptions.path}: '
            '${e.response?.statusCode ?? e.type.name}');
      }
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/core/jellyfin/jellyfin_http_test.dart`
Expected: PASS.

- [ ] **Step 5: sostituisci i `debugPrint`.** In ogni file aggiungi `import 'package:logging/logging.dart';` e, sotto gli import, il logger indicato. Poi sostituisci ogni chiamata come nella tabella. Il testo resta lo stesso, **senza il prefisso `[player]`** (ora è il nome del logger).

| File | Logger | Chiamata attuale | Diventa |
|---|---|---|---|
| `lib/core/media_session/smtc_media_session.dart` | `final _log = Logger('smtc');` | `debugPrint('SMTC: $e')` (in `_run`) | `_log.warning('pannello media: $e')` |
| idem | idem | `.handleError((Object error) => debugPrint('SMTC: $error'))` | `.handleError((Object error) => _log.fine('pulsante non gestito: $error'))` |
| `lib/core/video/media_kit_engine.dart` | `final _log = Logger('player');` | `debugPrint('[player] stop dopo apertura non riuscita: $error')` | `_log.warning('stop dopo apertura non riuscita: $error')` |
| `lib/features/playback/play_launcher.dart` | `final _log = Logger('trailer');` | `debugPrint('Trailer locali non disponibili: $error')` | `_log.warning('trailer locali non disponibili: $error')` |
| `lib/features/player/progress_reporter.dart` | `final _log = Logger('player');` | `debugPrint('[player] report non inviato: $error')` | `_log.warning('report non inviato: $error')` |
| `lib/features/player/player_controller.dart` | `final _log = Logger('player');` | `debugPrint('[player] motore: $message')` | `_log.warning('motore: $message')` |
| idem | | `debugPrint('[player] direct play non riuscito ($error): provo la transcodifica')` | `_log.info('direct play non riuscito ($error): provo la transcodifica')` |
| idem | | `debugPrint('[player] errore: $error')` (in `_fail`) | `_log.severe('errore: $error')` |
| idem | | `debugPrint('[player] sottotitolo $index non caricato')` | `_log.warning('sottotitolo $index non caricato')` |
| idem | | `debugPrint('[player] tracce: $error')` | `_log.warning('tracce: $error')` |
| idem | | `debugPrint('[player] sottotitolo $index non caricato: resta il ' 'precedente')` | `_log.warning('sottotitolo $index non caricato: resta il precedente')` |
| idem | | `debugPrint('[player] $what non disponibili: $error')` | `_log.warning('$what non disponibili: $error')` |
| idem | | `debugPrint('[player] chiusura del motore: $error')` | `_log.warning('chiusura del motore: $error')` |
| idem | | `debugPrint('[player] "visto" non salvato: $error')` | `_log.warning('"visto" non salvato: $error')` |
| idem | | `debugPrint('[player] dati utente non aggiornati dal server: $error')` | `_log.info('dati utente non aggiornati dal server: $error')` |
| idem | | `debugPrint('[player] dati utente non aggiornati: $error')` | `_log.info('dati utente non aggiornati: $error')` |

Se dopo la sostituzione `package:flutter/foundation.dart` risulta inutilizzato (`unused_import`), toglilo.

- [ ] **Step 6: avvio.** Sostituisci `lib/main.dart` con:

```dart
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
import 'core/device/device_identity.dart';
import 'core/jellyfin/client_info.dart';
import 'core/logging/app_log.dart';
import 'core/logging/rotating_file_sink.dart';
import 'core/media_session/smtc_media_session.dart';
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

    final identity = await DeviceIdentity.load(prefs);
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
```

- [ ] **Step 7: nessun `debugPrint` rimasto**

```bash
grep -rn "debugPrint" lib
```
Expected: una sola riga, in `lib/core/logging/app_log.dart` (l'eco in console).

- [ ] **Step 8: verifica**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 9: commit**

```bash
git add lib test
git commit -m "feat: send all diagnostics and failed requests to the log file"
```

---

### Task 6: protocollo IPC di Discord

**Files:**
- Create: `lib/core/discord/discord_ipc.dart`, `test/support/discord_fakes.dart`
- Test: `test/core/discord/discord_ipc_test.dart`

- [ ] **Step 1: crea il fake** `test/support/discord_fakes.dart`:

```dart
import 'dart:typed_data';

import 'package:wonderflix/core/discord/discord_ipc.dart';

/// Pipe di Discord in memoria: registra i frame scritti e risponde
/// all'handshake come Discord.
class FakeDiscordPipe implements DiscordPipe {
  /// Discord aperto: [open] riesce.
  bool available = true;

  /// Pipe interrotta (Discord chiuso a connessione aperta): lettura e
  /// scrittura lanciano.
  bool broken = false;

  /// Risposta all'handshake; `null` = nessuna risposta.
  ({DiscordOpcode opcode, Map<String, Object?> json})? handshakeReply = (
    opcode: DiscordOpcode.frame,
    json: {'cmd': 'DISPATCH', 'evt': 'READY'},
  );

  int opens = 0;
  bool closed = false;
  final written = <DiscordFrame>[];
  final _incoming = <int>[];

  /// Simula un frame in arrivo da Discord.
  void push(DiscordOpcode opcode, Map<String, Object?> json) =>
      _incoming.addAll(encodeDiscordFrame(opcode, json));

  List<Map<String, dynamic>> get handshakes => [
        for (final frame in written)
          if (frame.opcode == DiscordOpcode.handshake) frame.json,
      ];

  List<Map<String, dynamic>> get commands => [
        for (final frame in written)
          if (frame.opcode == DiscordOpcode.frame) frame.json,
      ];

  /// Attività inviate con SET_ACTIVITY, in ordine; `null` = cancellata.
  List<Map<String, dynamic>?> get activities => [
        for (final command in commands)
          if (command['cmd'] == 'SET_ACTIVITY')
            (command['args'] as Map<String, dynamic>)['activity']
                as Map<String, dynamic>?,
      ];

  List<int> get pids => [
        for (final command in commands)
          if (command['cmd'] == 'SET_ACTIVITY')
            (command['args'] as Map<String, dynamic>)['pid'] as int,
      ];

  @override
  bool open() {
    opens++;
    if (!available) return false;
    closed = false;
    return true;
  }

  @override
  void write(Uint8List bytes) {
    if (broken) throw const DiscordPipeException('pipe interrotta');
    final frames = (DiscordFrameReader()..add(bytes)).takeFrames();
    written.addAll(frames);
    final reply = handshakeReply;
    if (reply != null &&
        frames.any((frame) => frame.opcode == DiscordOpcode.handshake)) {
      push(reply.opcode, reply.json);
    }
  }

  @override
  Uint8List read() {
    if (broken) throw const DiscordPipeException('pipe interrotta');
    final data = Uint8List.fromList(_incoming);
    _incoming.clear();
    return data;
  }

  @override
  void close() {
    closed = true;
  }
}
```

- [ ] **Step 2: scrivi il test** `test/core/discord/discord_ipc_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/discord/discord_ipc.dart';

import '../../support/discord_fakes.dart';

void main() {
  group('frame', () {
    test('intestazione little-endian con opcode e lunghezza', () {
      final bytes = encodeDiscordFrame(DiscordOpcode.frame, {'a': 1});
      final header = ByteData.sublistView(bytes, 0, 8);
      expect(header.getUint32(0, Endian.little), 1);
      expect(header.getUint32(4, Endian.little), utf8.encode('{"a":1}').length);
      expect(utf8.decode(bytes.sublist(8)), '{"a":1}');
    });

    test('il lettore ricompone frame arrivati a pezzi', () {
      final bytes = [
        ...encodeDiscordFrame(DiscordOpcode.frame, {'evt': 'READY'}),
        ...encodeDiscordFrame(DiscordOpcode.ping, {'n': 2}),
      ];
      final reader = DiscordFrameReader();
      reader.add(bytes.sublist(0, 5));
      expect(reader.takeFrames(), isEmpty);
      reader.add(bytes.sublist(5));
      final frames = reader.takeFrames();
      expect(frames.map((f) => f.opcode),
          [DiscordOpcode.frame, DiscordOpcode.ping]);
      expect(frames.first.json, {'evt': 'READY'});
      expect(reader.takeFrames(), isEmpty);
    });

    test('opcode sconosciuti e JSON non valido vengono saltati', () {
      final bad = Uint8List(8 + 3);
      ByteData.sublistView(bad)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 3, Endian.little);
      bad.setAll(8, utf8.encode('{{{'));
      final unknown = Uint8List.fromList(
          encodeDiscordFrame(DiscordOpcode.frame, {'x': 1}));
      ByteData.sublistView(unknown).setUint32(0, 9, Endian.little);
      final reader = DiscordFrameReader()
        ..add(bad)
        ..add(unknown)
        ..add(encodeDiscordFrame(DiscordOpcode.frame, {'ok': true}));
      expect(reader.takeFrames().single.json, {'ok': true});
    });
  });

  group('client', () {
    late FakeDiscordPipe pipe;
    late DiscordIpcClient client;

    setUp(() {
      pipe = FakeDiscordPipe();
      client = DiscordIpcClient(pipe,
          clientId: '123',
          pollInterval: const Duration(milliseconds: 1),
          readyTimeout: const Duration(milliseconds: 30));
    });

    test('handshake con client_id e attesa di READY', () async {
      expect(await client.connect(), isTrue);
      expect(client.connected, isTrue);
      expect(pipe.handshakes, [
        {'v': 1, 'client_id': '123'},
      ]);
    });

    test('Discord chiuso: nessuna connessione, nessuna scrittura', () async {
      pipe.available = false;
      expect(await client.connect(), isFalse);
      expect(client.connected, isFalse);
      expect(pipe.written, isEmpty);
    });

    test('ID rifiutato da Discord: chiude la pipe', () async {
      pipe.handshakeReply = (
        opcode: DiscordOpcode.close,
        json: {'code': 4000, 'message': 'Invalid Client ID'},
      );
      expect(await client.connect(), isFalse);
      expect(pipe.closed, isTrue);
    });

    test('nessuna risposta: rinuncia dopo readyTimeout', () async {
      pipe.handshakeReply = null;
      expect(await client.connect(), isFalse);
      expect(pipe.closed, isTrue);
    });

    test('SET_ACTIVITY con pid e nonce diversi; null cancella', () async {
      await client.connect();
      expect(client.setActivity({'type': 3}, pid: 42), isTrue);
      expect(client.setActivity(null, pid: 42), isTrue);
      final commands = pipe.commands;
      expect(commands[0]['cmd'], 'SET_ACTIVITY');
      expect(commands[0]['args'], {
        'pid': 42,
        'activity': {'type': 3},
      });
      expect(commands[1]['args'], {'pid': 42});
      expect(commands[0]['nonce'], isNot(commands[1]['nonce']));
    });

    test('risponde ai ping con un pong', () async {
      await client.connect();
      pipe.push(DiscordOpcode.ping, {'n': 7});
      client.setActivity(null, pid: 1);
      final pong = pipe.written
          .firstWhere((frame) => frame.opcode == DiscordOpcode.pong);
      expect(pong.json, {'n': 7});
    });

    test('Discord chiude la connessione: setActivity restituisce false',
        () async {
      await client.connect();
      pipe.push(DiscordOpcode.close, {'code': 1000});
      expect(client.setActivity({'type': 3}, pid: 1), isFalse);
      expect(client.connected, isFalse);
    });

    test('pipe interrotta: setActivity restituisce false', () async {
      await client.connect();
      pipe.broken = true;
      expect(client.setActivity({'type': 3}, pid: 1), isFalse);
      expect(client.connected, isFalse);
      expect(pipe.closed, isTrue);
    });
  });
}
```

- [ ] **Step 3: esegui e verifica che fallisca**

Run: `flutter test test/core/discord/discord_ipc_test.dart`
Expected: FAIL (il file `discord_ipc.dart` non esiste).

- [ ] **Step 4: crea** `lib/core/discord/discord_ipc.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger('discord');

/// Tipi di frame del protocollo IPC di Discord. L'indice è il valore
/// sul protocollo.
enum DiscordOpcode { handshake, frame, close, ping, pong }

/// Un messaggio ricevuto o inviato sulla pipe.
class DiscordFrame {
  const DiscordFrame(this.opcode, this.json);

  final DiscordOpcode opcode;
  final Map<String, dynamic> json;
}

/// 8 byte di intestazione (opcode e lunghezza, little-endian) più il JSON.
Uint8List encodeDiscordFrame(DiscordOpcode opcode, Map<String, Object?> json) {
  final payload = utf8.encode(jsonEncode(json));
  final bytes = Uint8List(8 + payload.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, opcode.index, Endian.little)
    ..setUint32(4, payload.length, Endian.little);
  bytes.setAll(8, payload);
  return bytes;
}

/// Ricompone i frame da byte che possono arrivare a pezzi. I frame con
/// opcode sconosciuto o JSON non valido vengono saltati.
class DiscordFrameReader {
  final _pending = <int>[];

  void add(List<int> bytes) => _pending.addAll(bytes);

  List<DiscordFrame> takeFrames() {
    final frames = <DiscordFrame>[];
    while (_pending.length >= 8) {
      final header =
          ByteData.sublistView(Uint8List.fromList(_pending.sublist(0, 8)));
      final opcode = header.getUint32(0, Endian.little);
      final length = header.getUint32(4, Endian.little);
      if (_pending.length < 8 + length) break;
      final payload = _pending.sublist(8, 8 + length);
      _pending.removeRange(0, 8 + length);
      if (opcode >= DiscordOpcode.values.length) continue;
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(payload));
      } on FormatException {
        continue;
      }
      frames.add(DiscordFrame(DiscordOpcode.values[opcode],
          json is Map<String, dynamic> ? json : const {}));
    }
    return frames;
  }
}

/// La pipe locale di Discord. Tutte le operazioni sono sincrone e non
/// bloccano: [read] restituisce solo i byte già arrivati.
abstract class DiscordPipe {
  /// Apre `\\.\pipe\discord-ipc-0..9`; `false` se Discord non è aperto.
  bool open();

  /// Lancia [DiscordPipeException] se la pipe è chiusa.
  void write(Uint8List bytes);

  /// Byte già arrivati (vuoto se nessuno). Lancia [DiscordPipeException] se
  /// la pipe è chiusa.
  Uint8List read();

  void close();
}

class DiscordPipeException implements Exception {
  const DiscordPipeException(this.message);
  final String message;

  @override
  String toString() => 'DiscordPipeException: $message';
}

/// Connessione a Discord per la Rich Presence: handshake, attesa di
/// `READY`, invio dell'attività.
class DiscordIpcClient {
  DiscordIpcClient(
    this._pipe, {
    required this.clientId,
    this.pollInterval = const Duration(milliseconds: 100),
    this.readyTimeout = const Duration(seconds: 5),
  }) : assert(pollInterval > Duration.zero);

  final DiscordPipe _pipe;

  /// Application ID del Discord Developer Portal.
  final String clientId;
  final Duration pollInterval;
  final Duration readyTimeout;

  final _reader = DiscordFrameReader();
  bool _connected = false;
  int _nonce = 0;

  bool get connected => _connected;

  /// `true` quando Discord ha risposto `READY`; `false` se non è aperto,
  /// rifiuta l'Application ID o non risponde entro [readyTimeout].
  Future<bool> connect() async {
    if (!_pipe.open()) return false;
    try {
      _pipe.write(encodeDiscordFrame(
          DiscordOpcode.handshake, {'v': 1, 'client_id': clientId}));
      var waited = Duration.zero;
      while (waited < readyTimeout) {
        _reader.add(_pipe.read());
        for (final frame in _reader.takeFrames()) {
          if (frame.opcode == DiscordOpcode.frame &&
              frame.json['evt'] == 'READY') {
            _connected = true;
            return true;
          }
          if (frame.opcode == DiscordOpcode.close) {
            _log.warning('Discord ha rifiutato la connessione: '
                '${frame.json['message']}');
            _pipe.close();
            return false;
          }
        }
        await Future<void>.delayed(pollInterval);
        waited += pollInterval;
      }
      _log.info('Discord non ha risposto all\'handshake');
    } on DiscordPipeException catch (e) {
      _log.fine('pipe di Discord: $e');
    }
    _pipe.close();
    return false;
  }

  /// Imposta l'attività, o la cancella con `null`. `false` se la
  /// connessione è caduta: il client va ricreato.
  bool setActivity(Map<String, Object?>? activity, {required int pid}) {
    if (!_connected) return false;
    try {
      _drain();
      if (!_connected) return false;
      _pipe.write(encodeDiscordFrame(DiscordOpcode.frame, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': ?activity},
        'nonce': '${++_nonce}',
      }));
      return true;
    } on DiscordPipeException catch (e) {
      _log.fine('pipe di Discord: $e');
      close();
      return false;
    }
  }

  void close() {
    _connected = false;
    _pipe.close();
  }

  /// Legge quello che Discord ha mandato nel frattempo: ping, chiusura,
  /// errori sui comandi.
  void _drain() {
    _reader.add(_pipe.read());
    for (final frame in _reader.takeFrames()) {
      switch (frame.opcode) {
        case DiscordOpcode.ping:
          _pipe.write(encodeDiscordFrame(DiscordOpcode.pong, frame.json));
        case DiscordOpcode.close:
          _log.info('Discord ha chiuso la connessione: ${frame.json}');
          close();
          return;
        case DiscordOpcode.frame:
          if (frame.json['evt'] == 'ERROR') {
            _log.warning('Discord: ${frame.json['data']}');
          }
        case DiscordOpcode.handshake:
        case DiscordOpcode.pong:
          break;
      }
    }
  }
}
```

- [ ] **Step 5: esegui e verifica che passi**

Run: `flutter test test/core/discord/discord_ipc_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add lib/core/discord/discord_ipc.dart test/core/discord/discord_ipc_test.dart test/support/discord_fakes.dart
git commit -m "feat: speak the Discord IPC protocol"
```

---

### Task 7: pipe di Windows (FFI)

**Files:**
- Create: `lib/core/discord/windows_discord_pipe.dart`

Nessun test automatico: è un sottile strato su `kernel32.dll` e il suo comportamento dipende da Discord aperto o no sul PC. Si prova a mano nel Task 14. Tutta la logica sopra è testata con `FakeDiscordPipe`.

- [ ] **Step 1: crea** `lib/core/discord/windows_discord_pipe.dart`:

```dart
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'discord_ipc.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createFile = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>,
        Uint32, Uint32, Pointer<Void>),
    Pointer<Void> Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
        Pointer<Void>)>('CreateFileW');

final _peekNamedPipe = _kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Pointer<Uint32>,
        Pointer<Uint32>, Pointer<Uint32>),
    int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>,
        Pointer<Uint32>, Pointer<Uint32>)>('PeekNamedPipe');

final _readFile = _kernel32.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Void>)>('ReadFile');

final _writeFile = _kernel32.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Void>)>('WriteFile');

final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CloseHandle');

const _genericReadWrite = 0x80000000 | 0x40000000;
const _openExisting = 3;
const _invalidHandle = -1;

/// [DiscordPipe] sulla named pipe di Windows `\\.\pipe\discord-ipc-N`.
class WindowsDiscordPipe implements DiscordPipe {
  Pointer<Void>? _handle;

  @override
  bool open() {
    close();
    for (var i = 0; i < 10; i++) {
      final path = '\\\\.\\pipe\\discord-ipc-$i'.toNativeUtf16();
      try {
        final handle = _createFile(path, _genericReadWrite, 0, nullptr,
            _openExisting, 0, nullptr);
        if (handle.address != _invalidHandle && handle.address != 0) {
          _handle = handle;
          return true;
        }
      } finally {
        malloc.free(path);
      }
    }
    return false;
  }

  Pointer<Void> _requireHandle() =>
      _handle ?? (throw const DiscordPipeException('pipe non aperta'));

  @override
  void write(Uint8List bytes) {
    final handle = _requireHandle();
    final buffer = malloc<Uint8>(bytes.length);
    final written = malloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final ok = _writeFile(handle, buffer, bytes.length, written, nullptr);
      if (ok == 0 || written.value != bytes.length) {
        throw const DiscordPipeException('scrittura non riuscita');
      }
    } finally {
      malloc.free(buffer);
      malloc.free(written);
    }
  }

  @override
  Uint8List read() {
    final handle = _requireHandle();
    final available = malloc<Uint32>();
    try {
      final ok =
          _peekNamedPipe(handle, nullptr, 0, nullptr, available, nullptr);
      if (ok == 0) throw const DiscordPipeException('pipe chiusa');
      final count = available.value;
      if (count == 0) return Uint8List(0);
      final buffer = malloc<Uint8>(count);
      final read = malloc<Uint32>();
      try {
        if (_readFile(handle, buffer, count, read, nullptr) == 0) {
          throw const DiscordPipeException('lettura non riuscita');
        }
        return Uint8List.fromList(buffer.asTypedList(read.value));
      } finally {
        malloc.free(buffer);
        malloc.free(read);
      }
    } finally {
      malloc.free(available);
    }
  }

  @override
  void close() {
    final handle = _handle;
    _handle = null;
    if (handle != null) _closeHandle(handle);
  }
}
```

- [ ] **Step 2: verifica**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 3: commit**

```bash
git add lib/core/discord/windows_discord_pipe.dart
git commit -m "feat: open the Discord named pipe on Windows"
```

---

### Task 8: impostazioni, testi e attività di Discord

**Files:**
- Create: `lib/features/discord/discord_settings.dart`, `lib/features/discord/discord_activity.dart`, `lib/features/discord/discord_providers.dart`
- Test: `test/features/discord/discord_settings_test.dart`, `test/features/discord/discord_activity_test.dart`

- [ ] **Step 1: scrivi i test.** `test/features/discord/discord_settings_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/discord/discord_providers.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';

void main() {
  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  }

  test('impostazioni: tutte attive di default, salvate e rilette', () async {
    final first = await container();
    const defaults = DiscordSettings();
    expect(first.read(discordSettingsProvider).enabled, isTrue);
    expect(first.read(discordSettingsProvider).showTitle, isTrue);
    expect(first.read(discordSettingsProvider).showPoster, isTrue);

    await first.read(discordSettingsProvider.notifier).update(defaults.copyWith(
        enabled: false, showTitle: false, showPoster: false));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('discord.enabled'), isFalse);

    final again = ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final settings = again.read(discordSettingsProvider);
    expect(settings.enabled, isFalse);
    expect(settings.showTitle, isFalse);
    expect(settings.showPoster, isFalse);
  });

  test('testi per Discord nella lingua scelta', () async {
    final c = await container();
    await c.read(localeProvider.notifier).set(const Locale('en'));
    expect(c.read(discordLabelsProvider).paused, 'Paused');
    await c.read(localeProvider.notifier).set(const Locale('it'));
    expect(c.read(discordLabelsProvider).paused, 'In pausa');
    expect(c.read(discordLabelsProvider).button, 'Entra in WonderFlix');
  });
}
```

`test/features/discord/discord_activity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/discord/discord_activity.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';

void main() {
  const labels = DiscordLabels(paused: 'In pausa', button: 'Entra in WonderFlix');
  final support = Uri.parse('https://discord.gg/abc');
  final start = DateTime.utc(2026, 9, 29, 21);

  Map<String, Object?> build({
    String? subtitle = 'S1:E4 · Pilot',
    String? poster = 'https://media.example.com/p.jpg',
    bool playing = true,
    DateTime? begin,
    Duration? duration,
    DiscordSettings settings = const DiscordSettings(),
    Uri? supportUrl,
  }) =>
      buildDiscordActivity(
        title: 'Breaking Bad',
        subtitle: subtitle,
        posterUrl: poster,
        playing: playing,
        start: begin,
        duration: duration,
        settings: settings,
        labels: labels,
        supportUrl: supportUrl,
      );

  test('in riproduzione: titolo, episodio, tempi, locandina, pulsante', () {
    expect(
        build(
            begin: start,
            duration: const Duration(minutes: 47),
            supportUrl: support),
        {
          'type': 3,
          'details': 'Breaking Bad',
          'state': 'S1:E4 · Pilot',
          'timestamps': {
            'start': start.millisecondsSinceEpoch,
            'end': start.add(const Duration(minutes: 47)).millisecondsSinceEpoch,
          },
          'assets': {
            'large_image': 'https://media.example.com/p.jpg',
            'large_text': 'Breaking Bad',
          },
          'buttons': [
            {'label': 'Entra in WonderFlix', 'url': 'https://discord.gg/abc'},
          ],
        });
  });

  test('in pausa: "In pausa" e nessun tempo', () {
    final activity = build(playing: false, begin: start);
    expect(activity['state'], 'In pausa');
    expect(activity.containsKey('timestamps'), isFalse);
  });

  test('senza durata: solo il tempo trascorso', () {
    expect(build(begin: start)['timestamps'],
        {'start': start.millisecondsSinceEpoch});
  });

  test('senza locandina, o con "mostra locandina" spento: il logo', () {
    expect((build(poster: null)['assets'] as Map)['large_image'], 'logo');
    expect(
        (build(settings: const DiscordSettings(showPoster: false))['assets']
            as Map)['large_image'],
        'logo');
  });

  test('"mostra titolo" spento: niente titolo, episodio né locandina', () {
    final activity = build(settings: const DiscordSettings(showTitle: false));
    expect(activity.containsKey('details'), isFalse);
    expect(activity.containsKey('state'), isFalse);
    expect(activity['assets'],
        {'large_image': 'logo', 'large_text': 'WonderFlix'});
  });

  test('senza supportUrl: nessun pulsante', () {
    expect(build().containsKey('buttons'), isFalse);
  });

  test('discordText: da 2 a 128 caratteri', () {
    expect(discordText('Up'), 'Up');
    expect(discordText('X'), hasLength(2));
    expect(discordText('  M  '), hasLength(2));
    final long = discordText('a' * 200);
    expect(long, hasLength(128));
    expect(long, endsWith('…'));
  });
}
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/discord`
Expected: FAIL (i file non esistono).

- [ ] **Step 3: crea** `lib/features/discord/discord_settings.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Preferenze della Rich Presence di Discord, salvate su questo PC.
class DiscordSettings {
  const DiscordSettings({
    this.enabled = true,
    this.showTitle = true,
    this.showPoster = true,
  });

  /// Mostra l'attività su Discord.
  final bool enabled;

  /// Mostra titolo ed episodio (spento: solo "WonderFlix" e i tempi).
  final bool showTitle;

  /// Usa la locandina dal server invece del logo. Rende visibile l'indirizzo
  /// del server agli amici su Discord.
  final bool showPoster;

  DiscordSettings copyWith({bool? enabled, bool? showTitle, bool? showPoster}) =>
      DiscordSettings(
        enabled: enabled ?? this.enabled,
        showTitle: showTitle ?? this.showTitle,
        showPoster: showPoster ?? this.showPoster,
      );
}

class DiscordSettingsController extends Notifier<DiscordSettings> {
  static const _enabled = 'discord.enabled';
  static const _showTitle = 'discord.showTitle';
  static const _showPoster = 'discord.showPoster';

  @override
  DiscordSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    const defaults = DiscordSettings();
    return DiscordSettings(
      enabled: prefs.getBool(_enabled) ?? defaults.enabled,
      showTitle: prefs.getBool(_showTitle) ?? defaults.showTitle,
      showPoster: prefs.getBool(_showPoster) ?? defaults.showPoster,
    );
  }

  Future<void> update(DiscordSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setBool(_enabled, next.enabled),
      prefs.setBool(_showTitle, next.showTitle),
      prefs.setBool(_showPoster, next.showPoster),
    ]);
  }
}

final discordSettingsProvider =
    NotifierProvider<DiscordSettingsController, DiscordSettings>(
        DiscordSettingsController.new);
```

- [ ] **Step 4: crea** `lib/features/discord/discord_activity.dart`:

```dart
import 'discord_settings.dart';

/// Tipo di attività "Watching" di Discord.
const watchingActivityType = 3;

/// Asset caricato sul Discord Developer Portal.
const discordLogoAsset = 'logo';

/// Testi dell'attività, nella lingua dell'app (li vedono gli amici).
class DiscordLabels {
  const DiscordLabels({required this.paused, required this.button});

  final String paused;

  /// Etichetta del pulsante verso `supportUrl` (max 32 caratteri).
  final String button;
}

/// Attività di Discord per quello che si sta guardando.
///
/// [start] è l'istante in cui il video sarebbe partito da zero (adesso meno
/// la posizione): con [duration] Discord mostra tempo trascorso e
/// rimanente. In pausa i tempi non si mostrano.
Map<String, Object?> buildDiscordActivity({
  required String title,
  String? subtitle,
  String? posterUrl,
  required bool playing,
  DateTime? start,
  Duration? duration,
  required DiscordSettings settings,
  required DiscordLabels labels,
  Uri? supportUrl,
}) {
  final showTitle = settings.showTitle;
  // La locandina svela il titolo: senza titolo, sempre il logo.
  final poster = settings.showPoster && showTitle ? posterUrl : null;
  final state = playing ? (showTitle ? subtitle : null) : labels.paused;
  final begin = playing ? start : null;
  final end = begin != null && duration != null && duration > Duration.zero
      ? begin.add(duration)
      : null;
  return {
    'type': watchingActivityType,
    if (showTitle) 'details': discordText(title),
    if (state != null && state.trim().isNotEmpty) 'state': discordText(state),
    if (begin != null)
      'timestamps': {
        'start': begin.millisecondsSinceEpoch,
        'end': ?end?.millisecondsSinceEpoch,
      },
    'assets': {
      'large_image': poster ?? discordLogoAsset,
      'large_text': showTitle ? discordText(title) : 'WonderFlix',
    },
    if (supportUrl != null)
      'buttons': [
        {'label': labels.button, 'url': supportUrl.toString()},
      ],
  };
}

/// Discord accetta testi da 2 a 128 caratteri.
String discordText(String text) {
  final trimmed = text.trim();
  if (trimmed.length > 128) return '${trimmed.substring(0, 127)}…';
  // Spazio vuoto braille: Discord non lo toglie come uno spazio normale.
  return trimmed.padRight(2, '⠀');
}
```

- [ ] **Step 5: crea** `lib/features/discord/discord_providers.dart`:

```dart
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../settings/locale_controller.dart';
import 'discord_activity.dart';

/// Testi dell'attività nella lingua dell'app (quella scelta, o quella di
/// Windows risolta come fa `MaterialApp`).
final discordLabelsProvider = Provider<DiscordLabels>((ref) {
  final locale = ref.watch(localeProvider) ??
      basicLocaleListResolution(PlatformDispatcher.instance.locales,
          AppLocalizations.supportedLocales);
  final l = lookupAppLocalizations(locale);
  return DiscordLabels(paused: l.discordPaused, button: l.discordJoinButton);
});
```

- [ ] **Step 6: esegui e verifica che passino**

Run: `flutter test test/features/discord`
Expected: PASS.

- [ ] **Step 7: commit**

```bash
git add lib/features/discord test/features/discord
git commit -m "feat: build the Discord activity from settings and playback"
```

---

### Task 9: `DiscordPresence`

**Files:**
- Create: `lib/features/discord/discord_presence.dart`
- Test: `test/features/discord/discord_presence_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/discord/discord_presence_test.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/discord/discord_ipc.dart';
import 'package:wonderflix/features/discord/discord_activity.dart';
import 'package:wonderflix/features/discord/discord_presence.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';

import '../../support/discord_fakes.dart';

void main() {
  late FakeDiscordPipe pipe;
  late DiscordSettings settings;
  const labels = DiscordLabels(paused: 'In pausa', button: 'Entra in WonderFlix');
  const poster = 'https://media.example.com/p.jpg';

  setUp(() {
    pipe = FakeDiscordPipe();
    settings = const DiscordSettings();
  });

  DiscordPresence presence() => DiscordPresence(
        createClient: () => DiscordIpcClient(pipe,
            clientId: '123', pollInterval: const Duration(milliseconds: 10)),
        settings: () => settings,
        labels: () => labels,
        supportUrl: Uri.parse('https://discord.gg/abc'),
        processId: 42,
      );

  /// Avvia un episodio e aspetta il primo invio.
  DiscordPresence started(FakeAsync async) {
    final p = presence();
    unawaited(p.setMetadata(
        title: 'Breaking Bad', subtitle: 'S1:E4 · Pilot', thumbnailUrl: poster));
    async.flushMicrotasks();
    return p;
  }

  test('all\'avvio: titolo, episodio, locandina e pulsante', () {
    fakeAsync((async) {
      started(async);
      expect(pipe.handshakes, [
        {'v': 1, 'client_id': '123'},
      ]);
      expect(pipe.activities.single, {
        'type': 3,
        'details': 'Breaking Bad',
        'state': 'S1:E4 · Pilot',
        'assets': {'large_image': poster, 'large_text': 'Breaking Bad'},
        'buttons': [
          {'label': 'Entra in WonderFlix', 'url': 'https://discord.gg/abc'},
        ],
      });
      expect(pipe.pids.single, 42);
    });
  });

  test('tempi dalla posizione, al massimo un invio ogni 5 s', () {
    fakeAsync((async) {
      final t0 = clock.now();
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 47)));
      async.flushMicrotasks();
      expect(pipe.activities, hasLength(1));

      async.elapse(const Duration(seconds: 5));
      final begin = t0.subtract(const Duration(minutes: 10));
      expect(pipe.activities, hasLength(2));
      expect(pipe.activities.last!['timestamps'], {
        'start': begin.millisecondsSinceEpoch,
        'end': begin.add(const Duration(minutes: 47)).millisecondsSinceEpoch,
      });
    });
  });

  test('piccoli scarti di posizione non si inviano, i salti sì', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 10));
      expect(pipe.activities, hasLength(2));

      // 10 s dopo la posizione è avanzata di 11 s: scarto di 1 s.
      unawaited(p.setTimeline(
          position: const Duration(minutes: 10, seconds: 11),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities, hasLength(2));

      // Salto in avanti di 20 minuti.
      unawaited(p.setTimeline(
          position: const Duration(minutes: 30, seconds: 15),
          duration: const Duration(minutes: 47)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities, hasLength(3));
    });
  });

  test('in pausa: "In pausa" senza tempi', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.setTimeline(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 47)));
      unawaited(p.setPlaying(false));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last!['state'], 'In pausa');
      expect(pipe.activities.last!.containsKey('timestamps'), isFalse);
    });
  });

  test('uscita dal player: attività cancellata', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.clear());
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last, isNull);
    });
  });

  test('Discord chiuso: riprova ogni 30 s, poi mostra l\'attività', () {
    fakeAsync((async) {
      pipe.available = false;
      final p = started(async);
      unawaited(p.setPlaying(false));
      async.flushMicrotasks();
      expect(pipe.opens, 1);
      expect(pipe.activities, isEmpty);

      async.elapse(const Duration(seconds: 29));
      expect(pipe.opens, 1);
      async.elapse(const Duration(seconds: 1));
      expect(pipe.opens, 2);

      pipe.available = true;
      async.elapse(const Duration(seconds: 30));
      expect(pipe.opens, 3);
      expect(pipe.activities.single!['state'], 'In pausa');
    });
  });

  test('connessione persa: riprova dopo 30 s e rimanda lo stato', () {
    fakeAsync((async) {
      final p = started(async);
      async.elapse(const Duration(seconds: 5));
      pipe.broken = true;
      unawaited(p.setPlaying(false));
      async.flushMicrotasks();
      expect(pipe.activities, hasLength(1));

      pipe.broken = false;
      async.elapse(const Duration(seconds: 30));
      expect(pipe.opens, 2);
      expect(pipe.activities.last!['state'], 'In pausa');
    });
  });

  test('niente da mostrare: non si collega', () {
    fakeAsync((async) {
      final p = presence();
      unawaited(p.setPlaying(true));
      unawaited(p.clear());
      async.elapse(const Duration(minutes: 1));
      expect(pipe.opens, 0);
    });
  });

  test('impostazioni: spenta cancella, senza locandina usa il logo', () {
    fakeAsync((async) {
      final p = started(async);
      settings = const DiscordSettings(showPoster: false);
      p.refresh();
      async.elapse(const Duration(seconds: 5));
      expect((pipe.activities.last!['assets'] as Map)['large_image'], 'logo');

      settings = const DiscordSettings(enabled: false);
      p.refresh();
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last, isNull);
    });
  });

  test('dispose: cancella l\'attività e chiude la pipe', () {
    fakeAsync((async) {
      final p = started(async);
      unawaited(p.dispose());
      async.flushMicrotasks();
      expect(pipe.activities.last, isNull);
      expect(pipe.closed, isTrue);
    });
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/discord/discord_presence_test.dart`
Expected: FAIL (il file non esiste).

- [ ] **Step 3: crea** `lib/features/discord/discord_presence.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io show pid;

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

import '../../core/discord/discord_ipc.dart';
import '../../core/media_session/media_session.dart';
import 'discord_activity.dart';
import 'discord_settings.dart';

final _log = Logger('discord');

/// Attività "Watching" su Discord (Rich Presence). Il player la aggiorna
/// come il pannello media di sistema, attraverso [MediaSession].
///
/// - Si collega a Discord solo quando c'è qualcosa da mostrare; se Discord
///   non è aperto (o si chiude) riprova ogni [retryInterval].
/// - Invia al massimo un aggiornamento ogni [minSendInterval] (limite di
///   Discord: 5 ogni 20 s), sempre con lo stato più recente.
/// - Non invia di nuovo un'attività uguale all'ultima; l'inizio del video
///   (adesso meno la posizione) si considera uguale entro [startTolerance].
class DiscordPresence implements MediaSession {
  DiscordPresence({
    required DiscordIpcClient Function() createClient,
    required DiscordSettings Function() settings,
    required DiscordLabels Function() labels,
    required Uri? supportUrl,
    int? processId,
    this.retryInterval = const Duration(seconds: 30),
    this.minSendInterval = const Duration(seconds: 5),
  })  : _createClient = createClient,
        _settings = settings,
        _labels = labels,
        _supportUrl = supportUrl,
        _pid = processId ?? io.pid;

  final DiscordIpcClient Function() _createClient;
  final DiscordSettings Function() _settings;
  final DiscordLabels Function() _labels;
  final Uri? _supportUrl;
  final int _pid;
  final Duration retryInterval;
  final Duration minSendInterval;

  static const startTolerance = Duration(seconds: 2);

  DiscordIpcClient? _client;
  bool _connecting = false;
  bool _disposed = false;
  Timer? _retryTimer;
  Timer? _sendTimer;
  DateTime? _lastSendAt;

  /// Ultima attività inviata, in JSON (`null` = nessuna) e il suo inizio.
  String? _sentJson;
  DateTime? _sentStart;

  // Cosa si sta guardando.
  bool _active = false;
  String _title = '';
  String? _subtitle;
  String? _posterUrl;
  bool _playing = true;
  DateTime? _start;
  Duration? _duration;

  @override
  bool get handlesMediaKeys => false;

  @override
  Stream<MediaButton> get buttons => const Stream.empty();

  @override
  Future<void> setMetadata(
      {required String title, String? subtitle, String? thumbnailUrl}) async {
    _active = true;
    _title = title;
    _subtitle = subtitle;
    _posterUrl = thumbnailUrl;
    // Nuovo video: parte in riproduzione, i tempi arrivano con la timeline.
    _playing = true;
    _start = null;
    _duration = null;
    _sync();
  }

  @override
  Future<void> setPlaying(bool playing) async {
    _playing = playing;
    _sync();
  }

  @override
  Future<void> setTimeline(
      {required Duration position, required Duration duration}) async {
    _start = clock.now().subtract(position);
    _duration = duration;
    _sync();
  }

  @override
  Future<void> setNextEnabled(bool enabled) async {}

  @override
  Future<void> clear() async {
    _active = false;
    _start = null;
    _duration = null;
    _sync();
  }

  /// Impostazioni o lingua cambiate.
  void refresh() => _sync();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _sendTimer?.cancel();
    final client = _client;
    _client = null;
    if (client != null && client.connected) {
      client.setActivity(null, pid: _pid);
      client.close();
    }
  }

  ({Map<String, Object?> activity, DateTime? start})? _desired() {
    if (!_active || !_settings().enabled) return null;
    var start = _playing ? _start : null;
    final sentStart = _sentStart;
    if (start != null &&
        sentStart != null &&
        start.difference(sentStart).abs() <= startTolerance) {
      start = sentStart;
    }
    return (
      activity: buildDiscordActivity(
        title: _title,
        subtitle: _subtitle,
        posterUrl: _posterUrl,
        playing: _playing,
        start: start,
        duration: _duration,
        settings: _settings(),
        labels: _labels(),
        supportUrl: _supportUrl,
      ),
      start: start,
    );
  }

  void _sync() {
    if (_disposed) return;
    final desired = _desired();
    final json = desired == null ? null : jsonEncode(desired.activity);
    if (json == _sentJson) return;
    final client = _client;
    if (client == null || !client.connected) {
      if (desired != null) unawaited(_connect());
      return;
    }
    final last = _lastSendAt;
    if (last != null) {
      final wait = minSendInterval - clock.now().difference(last);
      if (wait > Duration.zero) {
        _sendTimer ??= Timer(wait, () {
          _sendTimer = null;
          _sync();
        });
        return;
      }
    }
    _lastSendAt = clock.now();
    if (client.setActivity(desired?.activity, pid: _pid)) {
      _sentJson = json;
      _sentStart = desired?.start;
    } else {
      _log.info('connessione a Discord interrotta');
      _client = null;
      _sentJson = null;
      _sentStart = null;
      _scheduleRetry();
    }
  }

  Future<void> _connect() async {
    if (_connecting || _retryTimer != null) return;
    _connecting = true;
    final client = _createClient();
    final ok = await client.connect();
    _connecting = false;
    if (_disposed) {
      client.close();
      return;
    }
    if (!ok) {
      _log.fine('Discord non raggiungibile: nuovo tentativo tra '
          '${retryInterval.inSeconds} s');
      client.close();
      _scheduleRetry();
      return;
    }
    _log.info('collegato a Discord');
    _client = client;
    // Connessione nuova: Discord non ha ancora nessuna nostra attività.
    _sentJson = null;
    _sentStart = null;
    _sync();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(retryInterval, () {
      _retryTimer = null;
      _sync();
    });
  }
}
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/discord/discord_presence_test.dart`
Expected: PASS. Se un test di tempi fallisce di pochi millisecondi, controlla che `setTimeline` e il confronto usino `clock.now()` (non `DateTime.now()`).

- [ ] **Step 5: commit**

```bash
git add lib/features/discord/discord_presence.dart test/features/discord/discord_presence_test.dart
git commit -m "feat: show what is playing as Discord Rich Presence"
```

---

### Task 10: sessione media combinata e avvio

**Files:**
- Create: `lib/core/media_session/mirrored_media_session.dart`
- Modify: `lib/features/discord/discord_providers.dart`, `lib/features/player/player_providers.dart`, `lib/main.dart`
- Test: `test/core/media_session/mirrored_media_session_test.dart`, `test/features/discord/discord_providers_test.dart`

- [ ] **Step 1: scrivi i test.** `test/core/media_session/mirrored_media_session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/core/media_session/mirrored_media_session.dart';

import '../../support/playback_fakes.dart';

class _BrokenSession extends NoopMediaSession {
  @override
  Future<void> setMetadata(
          {required String title, String? subtitle, String? thumbnailUrl}) =>
      Future.error(StateError('rotta'));
}

void main() {
  test('aggiorna tutte le sessioni; tasti solo dalla principale', () async {
    final primary = FakeMediaSession()..handlesMediaKeys = true;
    final mirror = FakeMediaSession();
    final session = MirroredMediaSession(primary: primary, mirrors: [mirror]);

    await session.setMetadata(title: 'Heat', subtitle: '1995');
    await session.setPlaying(false);
    await session.setTimeline(
        position: const Duration(seconds: 3),
        duration: const Duration(hours: 2));
    await session.setNextEnabled(true);
    await session.clear();

    for (final s in [primary, mirror]) {
      expect(s.metadata.single.title, 'Heat');
      expect(s.playingStates, [false]);
      expect(s.timelines, [const Duration(seconds: 3)]);
      expect(s.nextEnabled, [true]);
      expect(s.cleared, 1);
    }
    expect(session.handlesMediaKeys, isTrue);

    final pressed = <MediaButton>[];
    final sub = session.buttons.listen(pressed.add);
    primary.press(MediaButton.pause);
    await Future<void>.delayed(Duration.zero);
    expect(pressed, [MediaButton.pause]);
    await sub.cancel();
  });

  test('l\'errore di una sessione non ferma le altre', () async {
    final mirror = FakeMediaSession();
    final session =
        MirroredMediaSession(primary: _BrokenSession(), mirrors: [mirror]);
    await session.setMetadata(title: 'Heat');
    expect(mirror.metadata.single.title, 'Heat');
  });

  test('dispose non chiude le sessioni (sono dei loro provider)', () async {
    final primary = FakeMediaSession();
    await MirroredMediaSession(primary: primary).dispose();
    expect(primary.disposed, isFalse);
  });
}
```

`test/features/discord/discord_providers_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/config/app_config.dart';
import 'package:wonderflix/core/media_session/media_session.dart';
import 'package:wonderflix/features/discord/discord_providers.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/player/player_providers.dart';

import '../../support/discord_fakes.dart';
import '../../support/test_data.dart';

void main() {
  AppConfig config(String discordAppId) => AppConfig(
        serverUrl: testServerUrl,
        githubRepo: 'owner/repo',
        discordAppId: discordAppId,
        supportUrl: null,
      );

  test('Application ID valido: il player aggiorna Discord, che segue le '
      'impostazioni', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final pipe = FakeDiscordPipe();
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(config('123456789012345678')),
        sharedPreferencesProvider.overrideWithValue(prefs),
        discordPipeFactoryProvider.overrideWithValue(() => pipe),
        discordSessionProvider.overrideWith(createDiscordPresence),
      ]);
      final session = container.read(mediaSessionProvider);
      unawaited(session.setMetadata(title: 'Heat', subtitle: '1995'));
      async.flushMicrotasks();
      expect(pipe.activities.single!['details'], 'Heat');

      unawaited(container
          .read(discordSettingsProvider.notifier)
          .update(const DiscordSettings(enabled: false)));
      async.elapse(const Duration(seconds: 5));
      expect(pipe.activities.last, isNull);

      container.dispose();
      async.flushMicrotasks();
    });
  });

  test('Application ID d\'esempio o vuoto: nessuna connessione', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    for (final id in ['000000000000000000', '', '1']) {
      final pipe = FakeDiscordPipe();
      final container = ProviderContainer.test(overrides: [
        appConfigProvider.overrideWithValue(config(id)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        discordPipeFactoryProvider.overrideWithValue(() => pipe),
        discordSessionProvider.overrideWith(createDiscordPresence),
      ]);
      expect(container.read(discordSessionProvider), isA<NoopMediaSession>());
    }
  });
}
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/core/media_session test/features/discord/discord_providers_test.dart`
Expected: FAIL (file e provider non esistono).

- [ ] **Step 3: crea** `lib/core/media_session/mirrored_media_session.dart`:

```dart
import 'package:logging/logging.dart';

import 'media_session.dart';

final _log = Logger('media');

/// Inoltra gli aggiornamenti a più sessioni. [primary] (il pannello di
/// sistema) riceve anche i tasti; le [mirrors] (es. Discord) solo lo stato.
/// L'errore di una sessione non ferma le altre.
///
/// Non chiude le sessioni: le chiude il provider che le ha create.
class MirroredMediaSession implements MediaSession {
  MirroredMediaSession({required this.primary, this.mirrors = const []});

  final MediaSession primary;
  final List<MediaSession> mirrors;

  Future<void> _all(Future<void> Function(MediaSession session) action) =>
      Future.wait([
        for (final session in [primary, ...mirrors])
          () async {
            try {
              await action(session);
            } on Object catch (error) {
              _log.warning('sessione media: $error');
            }
          }(),
      ]);

  @override
  bool get handlesMediaKeys => primary.handlesMediaKeys;

  @override
  Stream<MediaButton> get buttons => primary.buttons;

  @override
  Future<void> setMetadata(
          {required String title, String? subtitle, String? thumbnailUrl}) =>
      _all((s) => s.setMetadata(
          title: title, subtitle: subtitle, thumbnailUrl: thumbnailUrl));

  @override
  Future<void> setPlaying(bool playing) => _all((s) => s.setPlaying(playing));

  @override
  Future<void> setTimeline(
          {required Duration position, required Duration duration}) =>
      _all((s) => s.setTimeline(position: position, duration: duration));

  @override
  Future<void> setNextEnabled(bool enabled) =>
      _all((s) => s.setNextEnabled(enabled));

  @override
  Future<void> clear() => _all((s) => s.clear());

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 4: provider di Discord.** In `lib/features/discord/discord_providers.dart`:
- nuovi import: `dart:async`, `../../app/providers.dart`, `../../core/discord/discord_ipc.dart`, `../../core/discord/windows_discord_pipe.dart`, `../../core/media_session/media_session.dart`, `discord_presence.dart`, `discord_settings.dart`;
- in fondo al file:

```dart
/// Crea la pipe verso Discord; nei test si usa una pipe finta.
final discordPipeFactoryProvider =
    Provider<DiscordPipe Function()>((ref) => WindowsDiscordPipe.new);

/// Attività su Discord. Di default non fa nulla; `main` la sostituisce con
/// [createDiscordPresence].
final discordSessionProvider = Provider<MediaSession>((ref) {
  final session = NoopMediaSession();
  ref.onDispose(() => unawaited(session.dispose()));
  return session;
});

/// Snowflake di Discord: 17–20 cifre, non il valore d'esempio tutto zeri.
final _applicationId = RegExp(r'^[1-9]\d{16,19}$');

/// La Rich Presence vera, se `discordAppId` è un Application ID valido.
MediaSession createDiscordPresence(Ref ref) {
  final config = ref.watch(appConfigProvider);
  final appId = config.discordAppId;
  if (!_applicationId.hasMatch(appId)) return NoopMediaSession();
  final createPipe = ref.watch(discordPipeFactoryProvider);
  final presence = DiscordPresence(
    createClient: () => DiscordIpcClient(createPipe(), clientId: appId),
    settings: () => ref.read(discordSettingsProvider),
    labels: () => ref.read(discordLabelsProvider),
    supportUrl: config.supportUrl,
  );
  ref.listen(discordSettingsProvider, (_, _) => presence.refresh());
  ref.listen(discordLabelsProvider, (_, _) => presence.refresh());
  ref.onDispose(() => unawaited(presence.dispose()));
  return presence;
}
```

- [ ] **Step 5: sessione del player.** In `lib/features/player/player_providers.dart`:
- nuovi import: `../../core/media_session/mirrored_media_session.dart`, `../discord/discord_providers.dart`;
- sostituisci il `mediaSessionProvider` attuale (con il suo commento) con:

```dart
/// Pannello media di sistema. Di default non fa nulla; `main` lo sostituisce
/// con SMTC se è disponibile.
final systemMediaSessionProvider = Provider<MediaSession>((ref) {
  final session = NoopMediaSession();
  ref.onDispose(() => unawaited(session.dispose()));
  return session;
});

/// Sessione media condivisa da tutta l'app (una sola, anche passando da un
/// episodio all'altro): il pannello di sistema, che gestisce anche i tasti,
/// più l'attività su Discord.
final mediaSessionProvider = Provider<MediaSession>((ref) =>
    MirroredMediaSession(
      primary: ref.watch(systemMediaSessionProvider),
      mirrors: [ref.watch(discordSessionProvider)],
    ));
```

- [ ] **Step 6: avvio.** In `lib/main.dart`:
- nuovo import: `features/discord/discord_providers.dart`;
- nella lista `overrides`, sostituisci il blocco `if (smtcReady) mediaSessionProvider.overrideWith(…)` con:

```dart
        if (smtcReady)
          systemMediaSessionProvider.overrideWith((ref) {
            final session = SmtcMediaSession();
            ref.onDispose(() => unawaited(session.dispose()));
            return session;
          }),
        discordSessionProvider.overrideWith(createDiscordPresence),
```

- [ ] **Step 7: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS. `test/features/player/player_screen_test.dart` sovrascrive `mediaSessionProvider` e non cambia.

- [ ] **Step 8: commit**

```bash
git add lib test
git commit -m "feat: mirror playback to Discord alongside the Windows media controls"
```

---

### Task 11: versione del server

**Files:**
- Create: `lib/core/jellyfin/system_api.dart`
- Modify: `lib/app/providers.dart`, `test/support/settings_fakes.dart`
- Test: `test/core/jellyfin/system_api_test.dart`

- [ ] **Step 1: scrivi il test** `test/core/jellyfin/system_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/system_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SystemApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {
          'Version': '10.11.9',
          'ServerName': 'casa',
        }));
    api = SystemApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('serverVersion legge /System/Info/Public', () async {
    expect(await api.serverVersion(), '10.11.9');
    expect(adapter.requests.single.path, '/System/Info/Public');
  });

  test('risposta senza versione: errore del server', () async {
    adapter.handler = (_) => const FakeResponse(200, {'ServerName': 'casa'});
    await expectLater(
        api.serverVersion(), throwsA(isA<ServerErrorException>()));
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/core/jellyfin/system_api_test.dart`
Expected: FAIL (il file non esiste).

- [ ] **Step 3: crea** `lib/core/jellyfin/system_api.dart`:

```dart
import 'api_exception.dart';
import 'jellyfin_http.dart';

/// Informazioni sul server.
class SystemApi {
  SystemApi(this._http);

  final JellyfinHttp _http;

  /// Versione di Jellyfin (`GET /System/Info/Public`, senza autenticazione).
  Future<String> serverVersion() async {
    final json = asJsonMap(await _http.get('/System/Info/Public'));
    final version = json['Version'];
    if (version is! String) throw const ServerErrorException(null);
    return version;
  }
}
```

- [ ] **Step 4: provider.** In `lib/app/providers.dart` (import `../core/jellyfin/system_api.dart`), dopo `authApiProvider`:

```dart
final systemApiProvider =
    Provider<SystemApi>((ref) => SystemApi(ref.watch(jellyfinHttpProvider)));
```

- [ ] **Step 5: fake.** In fondo a `test/support/settings_fakes.dart` (import `package:wonderflix/core/jellyfin/system_api.dart`):

```dart
/// `SystemApi` in memoria; con [version] `null` il server non risponde.
class FakeSystemApi implements SystemApi {
  String? version = '10.11.9';

  @override
  Future<String> serverVersion() async {
    final current = version;
    if (current == null) throw StateError('server non raggiungibile');
    return current;
  }
}
```

- [ ] **Step 6: esegui e verifica che passi**

Run: `flutter analyze && flutter test test/core/jellyfin/system_api_test.dart`
Expected: nessun problema, PASS.

- [ ] **Step 7: commit**

```bash
git add lib/core/jellyfin/system_api.dart lib/app/providers.dart test/core/jellyfin/system_api_test.dart test/support/settings_fakes.dart
git commit -m "feat: read the server version"
```

---

### Task 12: diagnostica

**Files:**
- Create: `lib/features/settings/diagnostics.dart`
- Test: `test/features/settings/diagnostics_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/settings/diagnostics_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/logging/app_log.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/settings/diagnostics.dart';

import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

void main() {
  test('buildDiagnostics: testo completo', () {
    expect(
        buildDiagnostics(
          appVersion: '0.1.0',
          windowsVersion: '"Windows 11 Pro" 10.0 (Build 26200)',
          serverVersion: '10.11.9',
          player: const PlayerSettings(),
          discord: const DiscordSettings(showPoster: false),
          recentErrors: ['riga 1', 'riga 2'],
        ),
        'WonderFlix 0.1.0\n'
        'Windows: "Windows 11 Pro" 10.0 (Build 26200)\n'
        'Jellyfin: 10.11.9\n'
        'Player: quality=original, hardwareDecoding=true, subtitleScale=1.0, '
        'autoSkipIntro=false, autoplayNext=true\n'
        'Discord: enabled=true, showTitle=true, showPoster=false\n'
        '\n'
        'Ultimi errori (2):\n'
        'riga 1\n'
        'riga 2\n');
  });

  test('buildDiagnostics: server irraggiungibile, nessun errore', () {
    final text = buildDiagnostics(
      appVersion: '0.1.0',
      windowsVersion: 'w',
      serverVersion: null,
      player: const PlayerSettings(),
      discord: const DiscordSettings(),
      recentErrors: const [],
    );
    expect(text, contains('Jellyfin: non raggiungibile\n'));
    expect(text, endsWith('Ultimi errori (0):\nnessuno\n'));
  });

  Future<ProviderContainer> container(FakeSystemApi system) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final log = AppLog()..add(LogRecord(Level.SEVERE, 'boom', 'player'));
    return ProviderContainer.test(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      systemApiProvider.overrideWithValue(system),
      appLogProvider.overrideWithValue(log),
    ]);
  }

  test('collectDiagnostics: versioni, impostazioni ed errori dell\'app',
      () async {
    final c = await container(FakeSystemApi());
    final text = await c.read(collectDiagnosticsProvider)();
    expect(text, startsWith('WonderFlix 0.0.1\nWindows: '));
    expect(text, contains('Jellyfin: 10.11.9\n'));
    expect(text, contains('Player: quality=original'));
    expect(text, contains('Discord: enabled=true'));
    expect(text, contains('[player] boom'));
  });

  test('collectDiagnostics: server offline', () async {
    final c = await container(FakeSystemApi()..version = null);
    final text = await c.read(collectDiagnosticsProvider)();
    expect(text, contains('Jellyfin: non raggiungibile\n'));
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/settings/diagnostics_test.dart`
Expected: FAIL (il file non esiste).

- [ ] **Step 3: crea** `lib/features/settings/diagnostics.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/logging/app_log.dart';
import '../discord/discord_settings.dart';
import '../player/player_settings.dart';

final _log = Logger('diagnostics');

/// Testo da incollare nelle richieste di aiuto. Non contiene l'indirizzo del
/// server né dati dell'account; gli errori sono già senza segreti.
String buildDiagnostics({
  required String appVersion,
  required String windowsVersion,
  required String? serverVersion,
  required PlayerSettings player,
  required DiscordSettings discord,
  required List<String> recentErrors,
}) {
  final buffer = StringBuffer()
    ..writeln('WonderFlix $appVersion')
    ..writeln('Windows: $windowsVersion')
    ..writeln('Jellyfin: ${serverVersion ?? 'non raggiungibile'}')
    ..writeln('Player: quality=${player.quality.name}, '
        'hardwareDecoding=${player.hardwareDecoding}, '
        'subtitleScale=${player.subtitleScale}, '
        'autoSkipIntro=${player.autoSkipIntro}, '
        'autoplayNext=${player.autoplayNext}')
    ..writeln('Discord: enabled=${discord.enabled}, '
        'showTitle=${discord.showTitle}, showPoster=${discord.showPoster}')
    ..writeln()
    ..writeln('Ultimi errori (${recentErrors.length}):');
  if (recentErrors.isEmpty) buffer.writeln('nessuno');
  for (final error in recentErrors) {
    buffer.writeln(error);
  }
  return buffer.toString();
}

/// Raccoglie la diagnostica (la versione del server con un tentativo di al
/// massimo 5 s).
final collectDiagnosticsProvider =
    Provider<Future<String> Function()>((ref) => () async {
          String? server;
          try {
            server = await ref
                .read(systemApiProvider)
                .serverVersion()
                .timeout(const Duration(seconds: 5));
          } on Object catch (error) {
            _log.info('versione del server non disponibile: $error');
          }
          return buildDiagnostics(
            appVersion: ref.read(clientInfoProvider).version,
            windowsVersion: Platform.operatingSystemVersion,
            serverVersion: server,
            player: ref.read(playerSettingsProvider),
            discord: ref.read(discordSettingsProvider),
            recentErrors: ref.read(appLogProvider).recentErrors,
          );
        });

/// Apre la cartella dei log in Esplora risorse.
final openLogsFolderProvider =
    Provider<Future<void> Function()>((ref) => () async {
          final directory = ref.read(logsDirectoryProvider);
          try {
            directory.createSync(recursive: true);
            await launchUrl(Uri.file(directory.path, windows: true));
          } on Object catch (error) {
            _log.warning('cartella dei log non aperta: $error');
          }
        });
```

- [ ] **Step 4: esegui e verifica che passi**

Run: `flutter test test/features/settings/diagnostics_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/features/settings/diagnostics.dart test/features/settings/diagnostics_test.dart
git commit -m "feat: collect diagnostics for support requests"
```

---

### Task 13: Impostazioni — sezioni Discord e Supporto

**Files:**
- Create: `lib/features/settings/discord_settings_section.dart`, `lib/features/settings/support_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/settings_test.dart` (aggiunte)

- [ ] **Step 1: aggiungi i test** in fondo al `main()` di `test/features/settings/settings_test.dart`. Nuovi import: `package:flutter/services.dart`, `package:wonderflix/features/settings/diagnostics.dart`.

```dart
  testWidgets('sezione Discord: interruttori salvati e collegati tra loro',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 2400),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
    ]);

    final enabled = find.byKey(const Key('discord-enabled'));
    final showTitle = find.byKey(const Key('discord-show-title'));
    final showPoster = find.byKey(const Key('discord-show-poster'));
    expect(find.text('Mostra su Discord cosa sto guardando'), findsOneWidget);

    await tester.ensureVisible(showPoster);
    await tester.tap(showPoster);
    await tester.pump();
    expect(prefs.getBool('discord.showPoster'), isFalse);

    await tester.tap(showTitle);
    await tester.pump();
    expect(prefs.getBool('discord.showTitle'), isFalse);
    // Senza titolo la locandina non si può attivare.
    expect(tester.widget<SwitchListTile>(showPoster).onChanged, isNull);

    await tester.tap(enabled);
    await tester.pump();
    expect(prefs.getBool('discord.enabled'), isFalse);
    expect(tester.widget<SwitchListTile>(showTitle).onChanged, isNull);
  });

  testWidgets('sezione Supporto: copia la diagnostica e apre i log',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    var opened = 0;

    await pumpApp(tester, const Scaffold(body: SettingsScreen()),
        surfaceSize: const Size(1440, 2400),
        overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      collectDiagnosticsProvider.overrideWithValue(() async => 'DIAGNOSTICA'),
      openLogsFolderProvider.overrideWithValue(() async => opened++),
    ]);

    final copy = find.text('Copia diagnostica');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    await tester.pump();
    expect(copied, ['DIAGNOSTICA']);
    expect(find.text('Diagnostica copiata negli appunti'), findsOneWidget);

    await tester.tap(find.text('Apri la cartella dei log'));
    await tester.pump();
    expect(opened, 1);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/settings/settings_test.dart`
Expected: FAIL (le sezioni non ci sono).

- [ ] **Step 3: crea** `lib/features/settings/discord_settings_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../discord/discord_settings.dart';

/// Rich Presence di Discord: cosa mostrare agli amici.
class DiscordSettingsSection extends ConsumerWidget {
  const DiscordSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(discordSettingsProvider);
    void save(DiscordSettings next) =>
        unawaited(ref.read(discordSettingsProvider.notifier).update(next));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('discord-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsDiscordEnabled),
            value: settings.enabled,
            onChanged: (value) => save(settings.copyWith(enabled: value)),
          ),
          SwitchListTile(
            key: const Key('discord-show-title'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsDiscordShowTitle),
            value: settings.showTitle,
            onChanged: settings.enabled
                ? (value) => save(settings.copyWith(showTitle: value))
                : null,
          ),
          SwitchListTile(
            key: const Key('discord-show-poster'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsDiscordShowPoster),
            subtitle: Text(l.settingsDiscordPosterHint),
            value: settings.showPoster,
            onChanged: settings.enabled && settings.showTitle
                ? (value) => save(settings.copyWith(showPoster: value))
                : null,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: crea** `lib/features/settings/support_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'diagnostics.dart';

/// Diagnostica da incollare nelle richieste di aiuto e cartella dei log.
class SupportSection extends ConsumerWidget {
  const SupportSection({super.key});

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final text = await ref.read(collectDiagnosticsProvider)();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.settingsDiagnosticsCopied)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.settingsSupportHint,
            style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            WfButton.secondary(
              label: l.settingsCopyDiagnostics,
              icon: LucideIcons.clipboardCopy,
              onPressed: () => unawaited(_copy(context, ref)),
            ),
            WfButton.secondary(
              label: l.settingsOpenLogs,
              icon: LucideIcons.folderOpen,
              onPressed: () => unawaited(ref.read(openLogsFolderProvider)()),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: aggiungi le sezioni.** In `lib/features/settings/settings_screen.dart`:
- import `discord_settings_section.dart` e `support_section.dart`;
- dopo `const LanguageSettingsSection(),` inserisci:

```dart
          section(l.settingsDiscord),
          const DiscordSettingsSection(),
```

- dopo il blocco `Align(… WfButton.secondary(label: l.menuLogout …))` e prima di `const SizedBox(height: 40),` inserisci:

```dart
          section(l.settingsSupport),
          const SupportSection(),
```

- [ ] **Step 6: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 7: commit**

```bash
git add lib/features/settings test/features/settings
git commit -m "feat: add Discord and support sections to settings"
```

---

### Task 14: verifica completa e prova manuale

**Files:** nessuna modifica prevista (solo eventuali correzioni emerse).

- [ ] **Step 1: controlli automatici**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter analyze
flutter test
flutter build windows --debug
git status --short
```
Expected: nessun problema, tutti PASS, build riuscita. Se `git status` mostra solo `windows/flutter/generated_plugin*` con cambi di fine riga, esegui `git checkout -- windows/flutter/`.

- [ ] **Step 2: prova manuale con l'utente sul server reale.** Prerequisiti:
- `config/wonderflix.json` copiato nel worktree, con `discordAppId` valorizzato;
- l'app Discord sul Developer Portal ha l'asset **`logo`** (Rich Presence → Art Assets);
- Discord desktop aperto.

Avvio: `taskkill //IM wonderflix.exe //F` se l'app è già aperta, poi `flutter run -d windows --dart-define-from-file=config/wonderflix.json`.

Checklist:
1. **Log:** esiste `%LocalAppData%\WonderFlix\logs\wonderflix.log` con la riga `[startup] WonderFlix … su "Windows …"`. Dopo aver usato l'app, il file non contiene token: `grep -c 'Token="[^*]' "$LOCALAPPDATA/WonderFlix/logs/wonderflix.log"` deve dare `0`.
2. **Copia diagnostica:** incollata nel Blocco note, contiene versioni di app, Windows e Jellyfin, impostazioni del player e di Discord, "Ultimi errori". Nessun indirizzo del server, nessun token.
3. **Apri la cartella dei log:** si apre Esplora risorse sulla cartella.
4. **Film:** sul profilo Discord compare "Guarda WonderFlix" con titolo, anno, locandina e tempo trascorso/rimanente (entro ~5 s dall'avvio).
5. **Pausa:** "In pausa", senza tempi. Ripresa: tempi di nuovo corretti.
6. **Salto** avanti di qualche minuto: la barra di Discord si aggiorna entro ~5 s.
7. **Episodio:** titolo della serie e "S1:E4 · titolo". Passando all'episodio successivo l'attività si aggiorna.
8. **Uscita dal player:** l'attività sparisce.
9. **Pulsante "Entra in WonderFlix":** lo vede un altro utente (un amico o un secondo account), non chi guarda.
10. **Impostazioni:** *mostra locandina* spento → logo; *mostra titolo* spento → solo "WonderFlix" e i tempi; *mostra attività* spento → nessuna attività. Le modifiche valgono subito, anche durante la visione.
11. **Discord chiuso** durante la visione, poi riaperto: l'attività ricompare entro ~30 s.
12. **Pannello media di Windows:** funziona ancora come prima (titolo, play/pausa, successivo).

- [ ] **Step 3:** le modifiche chieste dall'utente durante la prova si fanno con TDD nello stesso worktree, con un commit ciascuna.
