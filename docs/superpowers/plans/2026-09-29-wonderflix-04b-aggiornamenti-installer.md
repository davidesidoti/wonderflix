# WonderFlix — Piano 4b: aggiornamenti, installer e release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** distribuire WonderFlix e tenerlo aggiornato (spec §9, §10, §12):
- **aggiornamenti automatici:**
  - all'avvio e ogni 6 h l'app legge l'ultima release pubblicata su GitHub;
  - se è più nuova, scarica l'installer in `%TEMP%` e verifica lo SHA-256;
  - mostra la barra "Aggiornamento pronto" con le note di rilascio in markdown; *Riavvia ora* installa in silenzio e riapre l'app;
  - mai durante la riproduzione; errori solo nel log;
- **aggiornamenti obbligatori:** marcatore `<!-- wonderflix:min-version=X.Y.Z -->` nelle note; schermata bloccante con avanzamento e *Aggiorna ora* (dopo il video, se si stava guardando);
- **installer Inno Setup:**
  - installazione per utente in `%LocalAppData%\Programs\WonderFlix`, senza UAC;
  - collegamenti su Start e Desktop, programma di disinstallazione;
  - modalità silenziosa che aspetta la chiusura dell'app e la riapre;
- **nome dell'app nel pannello media di Windows** (oggi "Unknown app"): AppUserModelID nell'app e nei collegamenti;
- **`release.yml`:** parte col tag `vX.Y.Z`; config dai Secrets, test, build release, installer, `.sha256`, firma presente ma spenta, GitHub Release in bozza;
- **`docs/RELEASING.md`:** procedura di release (§10) e checklist dei test manuali (§12).

**Architecture:**
- **Aggiornamenti (`lib/features/update/`):**
  - `release_info.dart` (pura): legge la risposta di GitHub, il marcatore `min-version`, il file `.sha256`, calcola lo SHA-256 di un file;
  - `github_releases_api.dart`: un `Dio` separato da quello di Jellyfin, senza token;
  - `update_controller.dart`: `UpdateController` (Notifier) controlla all'avvio e ogni 6 h (solo nelle build release), scarica, verifica, espone `UpdateState`, avvia l'installer;
  - `update_gate.dart`: sta nel `builder` di `MaterialApp.router`, sopra tutte le schermate. Mostra la barra o la schermata bloccante, ma **non mentre il player è aperto**.
- **Player aperto:** `playerActiveProvider` conta le schermate del player aperte (le aggiorna `PlayerScreen` in `initState`/`dispose`).
- **Windows:** `windows/runner/main.cpp` imposta l'AppUserModelID `it.wonderflix.WonderFlix`; l'installer lo mette sui collegamenti.
- **Installer:** `installer/wonderflix.iss`. Il controllo "app aperta" è tutto in `[Code]`: in modalità silenziosa aspetta fino a 30 s che il mutex `Local\WonderFlix.SingleInstance` sparisca (l'app avvia l'installer e poi esce); in modalità normale chiede di chiudere l'app.
- **CI:** `.github/workflows/release.yml` su `windows-latest` (Inno Setup 6 già presente).

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, dio 5, `pub_semver` 2.2.1, `crypto` 3.0.7, `flutter_markdown_plus` 1.0.12, Inno Setup 6, GitHub Actions, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md`, sezioni 9, 10 e 12. **Piano precedente:** `docs/superpowers/plans/2026-09-29-wonderflix-04a-log-discord.md` (log con il pacchetto `logging`, `accessRequestUrl`).

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push. **Non creare tag.**
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/updates`, branch `feat/updates`). Comandi git semplici, non composti con variabili.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca, esegui prima `flutter gen-l10n`.
- **File generati:** `flutter test` e `flutter pub get` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga: se `git diff windows/flutter/` non mostra cambi di contenuto, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione e fine riga:** niente `dart format` su file interi. Modifica i file esistenti con Edit mirati e mantieni i loro fine riga (molti sono CRLF, compresi gli ARB).
- **Import:** se l'analyzer segnala un import superfluo o mancante, correggilo e segnalalo.
- **Lint `use_null_aware_elements`:** nelle mappe `'key': ?value`.
- **Icone:** solo `LucideIcons` (verificate sulla 3.1.20: `download`, `rotateCw`, `refreshCw`), niente emoji.
- **Log:** `final _log = Logger('update');` (pacchetto `logging`), mai `debugPrint`. Nei messaggi niente percorsi completi (contengono il nome utente di Windows).
- **Widget test:**
  - `pumpApp` (`test/support/pump_app.dart`) ha `surfaceSize`; non chiamare `setSurfaceSize` prima;
  - `LinearProgressIndicator` senza valore anima all'infinito: niente `pumpAndSettle` con la schermata bloccante, solo `pump()`;
  - il `builder` di `MaterialApp.router` sta **sopra** il `Navigator`: in `UpdateGate` niente `Tooltip`, dialog o `showDialog` (non c'è `Overlay` né `Navigator`).
- **Fake:** niente mocktail. `FakeAdapter` (`test/support/fake_adapter.dart`) per le risposte JSON; `RawAdapter` (nuovo, Task 3) per testo e byte; `FakeGitHubReleasesApi` e `FakeUpdateController` (nuovi) in `test/support/update_fakes.dart`.
- **App avviata da Claude:** l'app desktop di Claude è un pacchetto MSIX e virtualizza le scritture in `AppData` dei processi che lancia. **Non avviare l'installer né l'app installata** dalla shell: lo fa l'utente da Esplora risorse.

## Note tecniche verificate

- **GitHub API:**
  - `GET https://api.github.com/repos/{owner}/{repo}/releases/latest`: la release più recente **non bozza e non pre-release**. **404** se non ce n'è nessuna;
  - campi usati: `tag_name` (`v0.1.1`), `body` (markdown), `draft`, `prerelease`, `assets[] {name, browser_download_url}`;
  - senza token: 60 richieste all'ora per IP (un controllo ogni 6 h basta). Header consigliati: `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent`;
  - `browser_download_url` risponde con un redirect verso `objects.githubusercontent.com`; dio lo segue da solo.
- **Nomi dei file della release:** `WonderFlix-Setup-X.Y.Z.exe` e `WonderFlix-Setup-X.Y.Z.exe.sha256`. Il `.sha256` contiene `<hash esadecimale minuscolo>  WonderFlix-Setup-X.Y.Z.exe`.
- **`pub_semver`:** `Version.parse('0.1.1')`, operatori `<`, `<=`, `>`; `isPreRelease`; `toString()` restituisce `0.1.1`.
- **`crypto`:** `(await sha256.bind(file.openRead()).first).toString()` → hash esadecimale minuscolo. SHA-256 di `abc` = `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
- **dio:** `downloadUri(url, path, onReceiveProgress: (received, total))` (`total` è -1 se il server non lo dice); `getUri<String>(url, options: Options(responseType: ResponseType.plain))`.
- **`flutter_markdown_plus` 1.0.12** (sostituto ufficiale di `flutter_markdown`): `MarkdownBody(data:, styleSheet: MarkdownStyleSheet.fromTheme(theme), onTapLink: (text, href, title) {})`.
- **Inno Setup 6:**
  - su `windows-latest` è già installato (6.7.1) in `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`;
  - `PrivilegesRequired=lowest` + `{localappdata}\Programs\WonderFlix`: nessun UAC; `{autoprograms}` / `{autodesktop}` sono quelli dell'utente;
  - la direttiva `AppMutex` **non va usata**: in modalità silenziosa il suo messaggio riceve la risposta predefinita *Annulla* e l'installazione si interrompe. Il controllo si fa in `[Code]` con `CheckForMutexes`, `WizardSilent`, `Sleep`, `SuppressibleMsgBox`;
  - `[Run]`: `postinstall skipifsilent` (casella "Avvia" a fine installazione normale) e `nowait skipifnotsilent` (riapertura dopo l'aggiornamento silenzioso);
  - `[Icons] … AppUserModelID: "…"` imposta l'ID sul collegamento;
  - `compiler:Languages\Italian.isl` è incluso nell'installazione di Inno Setup;
  - parametri silenziosi: `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`.
- **AppUserModelID:** `SetCurrentProcessExplicitAppUserModelID` (`<shobjidl.h>`, `shell32.lib`, già tra le librerie predefinite di CMake con MSVC). Windows mostra il nome dell'app nel pannello media solo se esiste un collegamento nel menu Start con lo stesso ID: **in sviluppo resta "Unknown app"**, con l'app installata compare "WonderFlix".
- **Runtime di Visual C++:** le build release di Flutter richiedono `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`. Si copiano accanto all'exe da `C:\Windows\System32` del runner, così l'app parte anche su PC senza il pacchetto ridistribuibile.
- **Versione dell'app:** viene da `pubspec.yaml` (`version: 0.1.0`) ed è quella di `clientInfoProvider.version` (PackageInfo legge le informazioni di versione dell'exe).

## Mappa dei file

```
lib/features/update/release_info.dart        ReleaseInfo, parseRelease, minVersionFrom, releaseNotesForDisplay, parseSha256File, sha256OfFile
lib/features/update/github_releases_api.dart GitHubReleasesApi
lib/features/update/update_controller.dart   UpdateState, UpdateController, updateControllerProvider, githubReleasesApiProvider,
                                             updateChecksEnabledProvider, updateDownloadDirectoryProvider, installUpdateProvider
lib/features/update/release_notes.dart       ReleaseNotes (markdown)
lib/features/update/update_banner.dart       UpdateBanner
lib/features/update/mandatory_update_screen.dart MandatoryUpdateScreen
lib/features/update/update_gate.dart         UpdateGate
lib/features/player/player_active.dart       PlayerActiveController, playerActiveProvider
lib/features/player/player_screen.dart       (+ enter/leave di playerActiveProvider)
lib/app/app.dart                             (+ builder: UpdateGate)
windows/runner/main.cpp                      (+ AppUserModelID)
installer/wonderflix.iss                     installer Inno Setup
.github/workflows/release.yml                pipeline di release
docs/RELEASING.md                            procedura di release e checklist
.gitignore                                   (+ /dist/)
l10n/app_it.arb, l10n/app_en.arb             (nuove stringhe)
pubspec.yaml, pubspec.lock                   (+ pub_semver, crypto, flutter_markdown_plus)
test/support/raw_adapter.dart                RawAdapter
test/support/update_fakes.dart               FakeGitHubReleasesApi, FakeUpdateController, testRelease
```

---

### Task 1: stringhe del Piano 4b

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan4b_test.dart`

- [ ] **Step 1: scrivi il test** `test/app/l10n_plan4b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 4b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.updateReadyTitle('0.2.0'), 'Aggiornamento pronto: WonderFlix 0.2.0');
    expect(en.updateReadyTitle('0.2.0'), 'Update ready: WonderFlix 0.2.0');
    expect(it.updateRestartNow, 'Riavvia ora');
    expect(it.updateWhatsNew, 'Novità');
    expect(it.updateLater, 'Più tardi');
    expect(it.updateRequiredTitle, 'Aggiornamento necessario');
    expect(
        it.updateRequiredBody('0.2.0'),
        'Questa versione di WonderFlix non è più supportata. '
        'Installa la versione 0.2.0 per continuare.');
    expect(it.updateDownloading(42), 'Download in corso… 42%');
    expect(en.updateDownloading(42), 'Downloading… 42%');
    expect(it.updateInstallNow, 'Aggiorna ora');
    expect(en.updateDownloadFailed,
        'Download failed. Check your connection and try again.');
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/app/l10n_plan4b_test.dart`
Expected: FAIL (errore di compilazione: `updateReadyTitle` non esiste).

- [ ] **Step 3: aggiungi le stringhe.** In `l10n/app_it.arb`, dopo l'ultima voce (metti la virgola dopo quella riga), con fine riga CRLF:

```json
  "updateReadyTitle": "Aggiornamento pronto: WonderFlix {version}",
  "@updateReadyTitle": {"placeholders": {"version": {"type": "String"}}},
  "updateRestartNow": "Riavvia ora",
  "updateWhatsNew": "Novità",
  "updateLater": "Più tardi",
  "updateRequiredTitle": "Aggiornamento necessario",
  "updateRequiredBody": "Questa versione di WonderFlix non è più supportata. Installa la versione {version} per continuare.",
  "@updateRequiredBody": {"placeholders": {"version": {"type": "String"}}},
  "updateDownloading": "Download in corso… {percent}%",
  "@updateDownloading": {"placeholders": {"percent": {"type": "int"}}},
  "updateInstallNow": "Aggiorna ora",
  "updateDownloadFailed": "Download non riuscito. Controlla la connessione e riprova."
```

In `l10n/app_en.arb`, alla fine allo stesso modo:

```json
  "updateReadyTitle": "Update ready: WonderFlix {version}",
  "updateRestartNow": "Restart now",
  "updateWhatsNew": "What's new",
  "updateLater": "Later",
  "updateRequiredTitle": "Update required",
  "updateRequiredBody": "This version of WonderFlix is no longer supported. Install version {version} to continue.",
  "updateDownloading": "Downloading… {percent}%",
  "updateInstallNow": "Update now",
  "updateDownloadFailed": "Download failed. Check your connection and try again."
```

"Riprova" esiste già (`retry`).

- [ ] **Step 4: genera e verifica**

Run: `flutter gen-l10n && flutter test test/app/l10n_plan4b_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan4b_test.dart
git commit -m "feat: add strings for app updates"
```

---

### Task 2: dati della release

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Create: `lib/features/update/release_info.dart`
- Test: `test/features/update/release_info_test.dart`

- [ ] **Step 1: dipendenze**

```bash
flutter pub add pub_semver crypto flutter_markdown_plus
grep -E "^  (pub_semver|crypto|flutter_markdown_plus):" -A5 pubspec.lock | grep version
```
Expected: `pub_semver` 2.2.1 e `crypto` 3.0.7 (le stesse di prima, ora dirette), `flutter_markdown_plus` 1.0.12. Se una versione è diversa, segnalalo.

- [ ] **Step 2: scrivi il test** `test/features/update/release_info_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:wonderflix/features/update/release_info.dart';

Map<String, dynamic> releaseJson({
  String tag = 'v0.2.0',
  String body = '## Novità\n- Più veloce',
  bool draft = false,
  bool prerelease = false,
  List<String>? assets,
}) =>
    {
      'tag_name': tag,
      'body': body,
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        for (final name in assets ??
            [
              'WonderFlix-Setup-0.2.0.exe',
              'WonderFlix-Setup-0.2.0.exe.sha256',
            ])
          {
            'name': name,
            'browser_download_url': 'https://github.com/o/r/releases/download/$tag/$name',
          },
      ],
    };

void main() {
  test('parseRelease: versione, note, installer e checksum', () {
    final release = parseRelease(releaseJson())!;
    expect(release.version, Version(0, 2, 0));
    expect(release.notes, '## Novità\n- Più veloce');
    expect(release.minVersion, isNull);
    expect(release.installerName, 'WonderFlix-Setup-0.2.0.exe');
    expect(release.installerUrl.toString(),
        'https://github.com/o/r/releases/download/v0.2.0/WonderFlix-Setup-0.2.0.exe');
    expect(release.checksumUrl.path, endsWith('WonderFlix-Setup-0.2.0.exe.sha256'));
  });

  test('parseRelease: tag senza "v"', () {
    expect(parseRelease(releaseJson(tag: '0.2.0'))!.version, Version(0, 2, 0));
  });

  test('parseRelease: bozze, pre-release e tag non validi vengono ignorati', () {
    expect(parseRelease(releaseJson(draft: true)), isNull);
    expect(parseRelease(releaseJson(prerelease: true)), isNull);
    expect(parseRelease(releaseJson(tag: 'v0.2.0-beta.1')), isNull);
    expect(parseRelease(releaseJson(tag: 'nightly')), isNull);
  });

  test('parseRelease: senza installer o checksum non c\'è aggiornamento', () {
    expect(parseRelease(releaseJson(assets: ['WonderFlix-Setup-0.2.0.exe'])),
        isNull);
    expect(
        parseRelease(releaseJson(assets: ['WonderFlix-Setup-0.2.0.exe.sha256'])),
        isNull);
  });

  test('marcatore min-version: letto e tolto dalle note', () {
    const body = 'Correzione importante.\n\n<!-- wonderflix:min-version=0.2.0 -->';
    final release = parseRelease(releaseJson(body: body))!;
    expect(release.minVersion, Version(0, 2, 0));
    expect(release.notes, 'Correzione importante.');
    expect(minVersionFrom('<!--wonderflix:min-version=1.0.0-->'), Version(1, 0, 0));
    expect(minVersionFrom('<!-- wonderflix:min-version=boh -->'), isNull);
    expect(minVersionFrom('nessun marcatore'), isNull);
  });

  test('parseSha256File: hash in minuscolo, anche con nome e spazi', () {
    const hash =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    expect(parseSha256File('$hash  WonderFlix-Setup-0.2.0.exe\n'), hash);
    expect(parseSha256File(hash.toUpperCase()), hash);
    expect(parseSha256File('non un hash'), isNull);
    expect(parseSha256File(''), isNull);
  });

  test('sha256OfFile', () async {
    final temp = Directory.systemTemp.createTempSync('wf_sha_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}a.txt')
      ..writeAsStringSync('abc');
    expect(await sha256OfFile(file),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
```

- [ ] **Step 3: esegui e verifica che fallisca**

Run: `flutter test test/features/update/release_info_test.dart`
Expected: FAIL (il file `release_info.dart` non esiste).

- [ ] **Step 4: crea** `lib/features/update/release_info.dart`:

```dart
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

/// Una release di WonderFlix pubblicata su GitHub, con l'installer.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.minVersion,
    required this.installerName,
    required this.installerUrl,
    required this.checksumUrl,
  });

  final Version version;

  /// Note di rilascio in markdown, senza il marcatore `min-version`.
  final String notes;

  /// Versione minima ancora accettata; sotto, l'aggiornamento è obbligatorio.
  final Version? minVersion;

  /// `WonderFlix-Setup-X.Y.Z.exe`
  final String installerName;
  final Uri installerUrl;

  /// File `.sha256` dell'installer.
  final Uri checksumUrl;
}

/// Legge la risposta di `releases/latest`. `null` se non è una release
/// utilizzabile: bozza, pre-release, tag non semver o file mancanti.
ReleaseInfo? parseRelease(Map<String, dynamic> json) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final Version version;
  try {
    version = Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
  } on FormatException {
    return null;
  }
  if (version.isPreRelease) return null;

  final installerName = 'WonderFlix-Setup-$version.exe';
  Uri? installerUrl;
  Uri? checksumUrl;
  final assets = json['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (name == installerName) installerUrl = Uri.tryParse(url);
      if (name == '$installerName.sha256') checksumUrl = Uri.tryParse(url);
    }
  }
  if (installerUrl == null || checksumUrl == null) return null;

  final body = json['body'];
  final notes = body is String ? body : '';
  return ReleaseInfo(
    version: version,
    notes: releaseNotesForDisplay(notes),
    minVersion: minVersionFrom(notes),
    installerName: installerName,
    installerUrl: installerUrl,
    checksumUrl: checksumUrl,
  );
}

final _minVersionMarker =
    RegExp(r'<!--\s*wonderflix:min-version=([^\s>]+)\s*-->');

/// Versione del marcatore `<!-- wonderflix:min-version=X.Y.Z -->`.
Version? minVersionFrom(String notes) {
  final match = _minVersionMarker.firstMatch(notes);
  if (match == null) return null;
  try {
    return Version.parse(match[1]!);
  } on FormatException {
    return null;
  }
}

/// Le note da mostrare: senza il marcatore.
String releaseNotesForDisplay(String notes) =>
    notes.replaceAll(_minVersionMarker, '').trim();

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// L'hash di un file `.sha256` (`<hash>  <nome file>`), in minuscolo.
String? parseSha256File(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final hash = trimmed.split(RegExp(r'\s+')).first.toLowerCase();
  return _sha256Hex.hasMatch(hash) ? hash : null;
}

/// SHA-256 esadecimale minuscolo del contenuto di [file].
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
```

- [ ] **Step 5: esegui e verifica che passi**

Run: `flutter test test/features/update/release_info_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/update/release_info.dart test/features/update/release_info_test.dart
git commit -m "feat: read GitHub releases, the min-version marker and checksums"
```

---

### Task 3: API delle release di GitHub

**Files:**
- Create: `lib/features/update/github_releases_api.dart`, `test/support/raw_adapter.dart`
- Test: `test/features/update/github_releases_api_test.dart`

- [ ] **Step 1: crea l'adapter di test** `test/support/raw_adapter.dart`:

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Adapter dio che risponde sempre con gli stessi byte (testo o file).
class RawAdapter implements HttpClientAdapter {
  RawAdapter(this.bytes,
      {this.status = 200, this.contentType = 'application/octet-stream'});

  final List<int> bytes;
  final int status;
  final String contentType;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(bytes, status, headers: {
      Headers.contentTypeHeader: [contentType],
      Headers.contentLengthHeader: ['${bytes.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: scrivi il test** `test/features/update/github_releases_api_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/update/github_releases_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/raw_adapter.dart';

void main() {
  test('latestRelease: indirizzo, header e JSON', () async {
    final adapter =
        FakeAdapter((_) => const FakeResponse(200, {'tag_name': 'v0.2.0'}));
    final api = GitHubReleasesApi(userAgent: 'WonderFlix/0.1.0', adapter: adapter);
    expect(await api.latestRelease('owner/repo'), {'tag_name': 'v0.2.0'});
    final request = adapter.requests.single;
    expect(request.uri.toString(),
        'https://api.github.com/repos/owner/repo/releases/latest');
    expect(request.headers['User-Agent'], 'WonderFlix/0.1.0');
    expect(request.headers['Accept'], 'application/vnd.github+json');
    expect(request.headers.containsKey('Authorization'), isFalse);
  });

  test('latestRelease: nessuna release (404) → null', () async {
    final api = GitHubReleasesApi(
        userAgent: 'x', adapter: FakeAdapter((_) => const FakeResponse(404)));
    expect(await api.latestRelease('owner/repo'), isNull);
  });

  test('latestRelease: altri errori arrivano al chiamante', () async {
    final api = GitHubReleasesApi(
        userAgent: 'x', adapter: FakeAdapter((_) => const FakeResponse(403)));
    await expectLater(
        api.latestRelease('owner/repo'), throwsA(isA<DioException>()));
  });

  test('downloadText', () async {
    final api = GitHubReleasesApi(
        userAgent: 'x',
        adapter: RawAdapter(utf8.encode('abc  file.exe\n'),
            contentType: 'text/plain'));
    expect(await api.downloadText(Uri.parse('https://x/file.exe.sha256')),
        'abc  file.exe\n');
  });

  test('downloadFile: scrive i byte e segnala l\'avanzamento', () async {
    final temp = Directory.systemTemp.createTempSync('wf_dl_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final target = File('${temp.path}${Platform.pathSeparator}setup.exe');
    final api = GitHubReleasesApi(
        userAgent: 'x', adapter: RawAdapter(List.filled(1000, 7)));
    final progress = <double>[];
    await api.downloadFile(Uri.parse('https://x/setup.exe'), target,
        onProgress: progress.add);
    expect(target.lengthSync(), 1000);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
  });
}
```

- [ ] **Step 3: esegui e verifica che fallisca**

Run: `flutter test test/features/update/github_releases_api_test.dart`
Expected: FAIL (il file non esiste).

- [ ] **Step 4: crea** `lib/features/update/github_releases_api.dart`:

```dart
import 'dart:io';

import 'package:dio/dio.dart';

/// Release pubbliche su GitHub, senza token. Un `Dio` separato da quello di
/// Jellyfin: niente header di autenticazione verso GitHub.
class GitHubReleasesApi {
  GitHubReleasesApi({required String userAgent, HttpClientAdapter? adapter})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': userAgent,
          },
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final Dio _dio;

  /// Ultima release pubblicata (esclude bozze e pre-release); `null` se il
  /// repository non ne ha ancora (404).
  Future<Map<String, dynamic>?> latestRelease(String repo) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
          'https://api.github.com/repos/$repo/releases/latest');
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<String> downloadText(Uri url) async {
    final response = await _dio.getUri<String>(url,
        options: Options(responseType: ResponseType.plain));
    return response.data ?? '';
  }

  /// Scarica [url] in [target]; [onProgress] riceve valori da 0 a 1.
  Future<void> downloadFile(Uri url, File target,
      {void Function(double progress)? onProgress}) async {
    await _dio.downloadUri(url, target.path,
        onReceiveProgress: (received, total) {
      if (total > 0) onProgress?.call(received / total);
    });
  }

  void close() => _dio.close();
}
```

- [ ] **Step 5: esegui e verifica che passi**

Run: `flutter test test/features/update/github_releases_api_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add lib/features/update/github_releases_api.dart test/features/update/github_releases_api_test.dart test/support/raw_adapter.dart
git commit -m "feat: fetch releases and installers from GitHub"
```

---

### Task 4: `UpdateController`

**Files:**
- Create: `lib/features/update/update_controller.dart`, `test/support/update_fakes.dart`
- Test: `test/features/update/update_controller_test.dart`

- [ ] **Step 1: crea i fake** `test/support/update_fakes.dart`:

```dart
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:wonderflix/features/update/github_releases_api.dart';
import 'package:wonderflix/features/update/release_info.dart';
import 'package:wonderflix/features/update/update_controller.dart';

/// Una release di prova.
ReleaseInfo testRelease({
  String version = '0.2.0',
  String notes = '## Novità\n- Più veloce',
  String? minVersion,
}) =>
    ReleaseInfo(
      version: Version.parse(version),
      notes: notes,
      minVersion: minVersion == null ? null : Version.parse(minVersion),
      installerName: 'WonderFlix-Setup-$version.exe',
      installerUrl: Uri.parse('https://x/WonderFlix-Setup-$version.exe'),
      checksumUrl: Uri.parse('https://x/WonderFlix-Setup-$version.exe.sha256'),
    );

/// Il JSON di `releases/latest` per [version].
Map<String, dynamic> latestJson(String version, {String body = 'Note'}) => {
      'tag_name': 'v$version',
      'body': body,
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': 'WonderFlix-Setup-$version.exe',
          'browser_download_url': 'https://x/WonderFlix-Setup-$version.exe',
        },
        {
          'name': 'WonderFlix-Setup-$version.exe.sha256',
          'browser_download_url':
              'https://x/WonderFlix-Setup-$version.exe.sha256',
        },
      ],
    };

/// SHA-256 di `[1, 2, 3]`, i byte dell'installer finto.
const fakeInstallerSha256 =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

/// GitHub in memoria.
class FakeGitHubReleasesApi implements GitHubReleasesApi {
  Map<String, dynamic>? latest;
  String checksum = '$fakeInstallerSha256  WonderFlix-Setup.exe';
  List<int> installerBytes = const [1, 2, 3];

  /// Se valorizzato, [latestRelease] lancia questo errore.
  Object? latestError;

  /// Se valorizzato, [downloadFile] lancia questo errore.
  Object? downloadError;
  int latestCalls = 0;
  int downloads = 0;

  @override
  Future<Map<String, dynamic>?> latestRelease(String repo) async {
    latestCalls++;
    final error = latestError;
    if (error != null) throw error;
    return latest;
  }

  @override
  Future<String> downloadText(Uri url) async => checksum;

  @override
  Future<void> downloadFile(Uri url, File target,
      {void Function(double progress)? onProgress}) async {
    downloads++;
    final error = downloadError;
    if (error != null) throw error;
    onProgress?.call(0.5);
    await target.writeAsBytes(installerBytes);
    onProgress?.call(1.0);
  }

  @override
  void close() {}
}

/// Controller con uno stato fisso: registra installazioni e nuovi tentativi.
class FakeUpdateController extends UpdateController {
  FakeUpdateController(this.initial);

  final UpdateState initial;
  int installs = 0;
  int retries = 0;

  @override
  UpdateState build() => initial;

  void emit(UpdateState next) => state = next;

  @override
  Future<void> install() async => installs++;

  @override
  void retry() => retries++;
}
```

- [ ] **Step 2: scrivi il test** `test/features/update/update_controller_test.dart`:

```dart
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/client_info.dart';
import 'package:wonderflix/features/update/update_controller.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  late FakeGitHubReleasesApi api;
  late Directory downloads;
  late List<File> installed;

  setUp(() {
    api = FakeGitHubReleasesApi();
    downloads = Directory.systemTemp.createTempSync('wf_update_');
    installed = [];
  });

  tearDown(() {
    if (downloads.existsSync()) downloads.deleteSync(recursive: true);
  });

  ProviderContainer container({String version = '0.1.0', bool enabled = true}) =>
      ProviderContainer.test(overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        clientInfoProvider.overrideWithValue(ClientInfo(
            client: 'WonderFlix', device: 'PC', deviceId: 'd', version: version)),
        githubReleasesApiProvider.overrideWithValue(api),
        updateChecksEnabledProvider.overrideWithValue(enabled),
        updateDownloadDirectoryProvider.overrideWithValue(downloads),
        installUpdateProvider.overrideWithValue((file) async => installed.add(file)),
      ]);

  Future<UpdateState> checked(ProviderContainer c) async {
    c.read(updateControllerProvider);
    await c.read(updateControllerProvider.notifier).check();
    return c.read(updateControllerProvider);
  }

  test('versione più nuova: scarica, verifica e segnala pronto', () async {
    api.latest = latestJson('0.2.0');
    final state = await checked(container());
    expect(state.release!.version, Version(0, 2, 0));
    expect(state.mandatory, isFalse);
    expect(state.ready, isTrue);
    expect(state.installer!.path, endsWith('WonderFlix-Setup-0.2.0.exe'));
    expect(state.installer!.readAsBytesSync(), [1, 2, 3]);
    expect(File('${state.installer!.path}.part').existsSync(), isFalse);
  });

  test('stessa versione o più vecchia: niente da fare', () async {
    api.latest = latestJson('0.1.0');
    final state = await checked(container());
    expect(state.release, isNull);
    expect(api.downloads, 0);
  });

  test('nessuna release (404): niente da fare', () async {
    api.latest = null;
    expect((await checked(container())).release, isNull);
  });

  test('min-version sopra la versione installata: obbligatorio', () async {
    api.latest = latestJson('0.2.0',
        body: 'Importante <!-- wonderflix:min-version=0.2.0 -->');
    final state = await checked(container());
    expect(state.mandatory, isTrue);
    expect(state.ready, isTrue);
    expect(state.release!.notes, 'Importante');
  });

  test('min-version già soddisfatta: facoltativo', () async {
    api.latest = latestJson('0.2.0',
        body: '<!-- wonderflix:min-version=0.1.0 -->');
    expect((await checked(container())).mandatory, isFalse);
  });

  test('SHA-256 diverso: file eliminato, nessun aggiornamento, avviso nel log',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    api.latest = latestJson('0.2.0');
    api.installerBytes = const [9, 9, 9];
    final state = await checked(container());
    expect(state.release, isNull);
    expect(downloads.listSync(), isEmpty);
    expect(records.where((r) => r.level == Level.WARNING), isNotEmpty);
  });

  test('installer già scaricato e valido: nessun nuovo download', () async {
    api.latest = latestJson('0.2.0');
    File('${downloads.path}${Platform.pathSeparator}WonderFlix-Setup-0.2.0.exe')
        .writeAsBytesSync(const [1, 2, 3]);
    final state = await checked(container());
    expect(state.ready, isTrue);
    expect(api.downloads, 0);
  });

  test('toglie gli installer delle versioni precedenti', () async {
    api.latest = latestJson('0.2.0');
    final old = File(
        '${downloads.path}${Platform.pathSeparator}WonderFlix-Setup-0.1.5.exe')
      ..writeAsBytesSync(const [0]);
    await checked(container());
    expect(old.existsSync(), isFalse);
  });

  test('obbligatorio con download fallito: "failed", poi riprova', () async {
    api.latest = latestJson('0.2.0',
        body: '<!-- wonderflix:min-version=0.2.0 -->');
    api.downloadError = const SocketException('offline');
    final c = container();
    final failed = await checked(c);
    expect(failed.mandatory, isTrue);
    expect(failed.failed, isTrue);
    expect(failed.ready, isFalse);

    api.downloadError = null;
    c.read(updateControllerProvider.notifier).retry();
    expect(c.read(updateControllerProvider).failed, isFalse);
    // Il nuovo tentativo scrive su disco: si aspetta che finisca.
    for (var i = 0; i < 100 && !c.read(updateControllerProvider).ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(c.read(updateControllerProvider).ready, isTrue);
  });

  test('facoltativo con errore di rete: nessun segno per l\'utente', () async {
    api.latestError = const SocketException('offline');
    final state = await checked(container());
    expect(state.release, isNull);
    expect(state.failed, isFalse);
  });

  test('install avvia l\'installer scaricato', () async {
    api.latest = latestJson('0.2.0');
    final c = container();
    final state = await checked(c);
    await c.read(updateControllerProvider.notifier).install();
    expect(installed.single.path, state.installer!.path);
  });

  test('controlli disattivati (build di sviluppo): nessuna chiamata', () async {
    final c = container(enabled: false);
    c.read(updateControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(api.latestCalls, 0);
  });

  test('controllo all\'avvio e poi ogni 6 ore', () {
    fakeAsync((async) {
      final c = container();
      c.read(updateControllerProvider);
      async.flushMicrotasks();
      expect(api.latestCalls, 1);
      async.elapse(const Duration(hours: 6));
      expect(api.latestCalls, 2);
    });
  });
}
```

- [ ] **Step 3: esegui e verifica che fallisca**

Run: `flutter test test/features/update/update_controller_test.dart`
Expected: FAIL (il file `update_controller.dart` non esiste).

- [ ] **Step 4: crea** `lib/features/update/update_controller.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../app/providers.dart';
import 'github_releases_api.dart';
import 'release_info.dart';

final _log = Logger('update');

/// Stato dell'aggiornamento.
class UpdateState {
  const UpdateState({
    this.release,
    this.mandatory = false,
    this.progress,
    this.installer,
    this.failed = false,
  });

  /// Versione più nuova trovata; `null` = nessun aggiornamento.
  final ReleaseInfo? release;

  /// La versione installata è sotto `min-version`: l'app va bloccata.
  final bool mandatory;

  /// Download in corso, da 0 a 1.
  final double? progress;

  /// Installer scaricato e verificato.
  final File? installer;

  /// Download non riuscito (lo si mostra solo se obbligatorio).
  final bool failed;

  bool get ready => installer != null;
}

final githubReleasesApiProvider = Provider<GitHubReleasesApi>((ref) {
  final api = GitHubReleasesApi(
      userAgent: 'WonderFlix/${ref.watch(clientInfoProvider).version}');
  ref.onDispose(api.close);
  return api;
});

/// Solo nelle build release: in sviluppo l'app proporrebbe di installare
/// sopra se stessa. Per provarlo: `--dart-define=wfForceUpdateCheck=true`.
final updateChecksEnabledProvider = Provider<bool>((ref) =>
    kReleaseMode || const bool.fromEnvironment('wfForceUpdateCheck'));

/// `%TEMP%\WonderFlix`
final updateDownloadDirectoryProvider = Provider<Directory>((ref) => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}WonderFlix'));

/// Avvia l'installer in silenzio e chiude l'app. L'installer aspetta che
/// l'app sia chiusa (mutex) e la riapre al termine.
final installUpdateProvider =
    Provider<Future<void> Function(File installer)>((ref) => (installer) async {
          _log.info('avvio dell\'installer e chiusura dell\'app');
          await Process.start(installer.path,
              const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
              mode: ProcessStartMode.detached);
          exit(0);
        });

final _repoPattern = RegExp(r'^[\w.-]+/[\w.-]+$');

/// Controlla gli aggiornamenti all'avvio e ogni [checkInterval]; scarica e
/// verifica l'installer in background. Gli errori finiscono solo nel log e
/// si riprova al controllo successivo.
class UpdateController extends Notifier<UpdateState> {
  static const checkInterval = Duration(hours: 6);

  bool _checking = false;

  @override
  UpdateState build() {
    if (!ref.watch(updateChecksEnabledProvider)) return const UpdateState();
    final timer = Timer.periodic(checkInterval, (_) => unawaited(check()));
    ref.onDispose(timer.cancel);
    scheduleMicrotask(() => unawaited(check()));
    return const UpdateState();
  }

  void _set(UpdateState next) {
    if (ref.mounted) state = next;
  }

  Future<void> check() async {
    if (_checking || !ref.mounted || state.ready) return;
    _checking = true;
    var mandatory = false;
    try {
      final repo = ref.read(appConfigProvider).githubRepo;
      if (!_repoPattern.hasMatch(repo)) return;
      final api = ref.read(githubReleasesApiProvider);
      final json = await api.latestRelease(repo);
      final release = json == null ? null : parseRelease(json);
      if (release == null) return;
      final current = Version.parse(ref.read(clientInfoProvider).version);
      if (release.version <= current) return;
      final minVersion = release.minVersion;
      mandatory = minVersion != null && current < minVersion;
      _set(UpdateState(release: release, mandatory: mandatory, progress: 0));
      final installer = await _download(api, release, mandatory);
      _set(UpdateState(
          release: release, mandatory: mandatory, installer: installer));
      _log.info('aggiornamento ${release.version} pronto'
          '${mandatory ? ' (obbligatorio)' : ''}');
    } on Object catch (error) {
      _log.warning('aggiornamento non riuscito: $error');
      final release = state.release;
      _set(mandatory && release != null
          ? UpdateState(release: release, mandatory: true, failed: true)
          : const UpdateState());
    } finally {
      _checking = false;
    }
  }

  /// Nuovo tentativo dopo un download fallito (schermata bloccante).
  void retry() {
    final release = state.release;
    if (release == null) return;
    _set(UpdateState(release: release, mandatory: state.mandatory, progress: 0));
    unawaited(check());
  }

  Future<void> install() async {
    final installer = state.installer;
    if (installer == null) return;
    await ref.read(installUpdateProvider)(installer);
  }

  Future<File> _download(
      GitHubReleasesApi api, ReleaseInfo release, bool mandatory) async {
    final expected = parseSha256File(await api.downloadText(release.checksumUrl));
    if (expected == null) throw const FormatException('file .sha256 non valido');
    final directory = ref.read(updateDownloadDirectoryProvider);
    await directory.create(recursive: true);
    final target = File(
        '${directory.path}${Platform.pathSeparator}${release.installerName}');
    await _deleteOtherInstallers(directory, target);
    if (await target.exists() && await sha256OfFile(target) == expected) {
      return target;
    }
    final partial = File('${target.path}.part');
    await api.downloadFile(release.installerUrl, partial,
        onProgress: (progress) => _set(UpdateState(
            release: release, mandatory: mandatory, progress: progress)));
    if (await sha256OfFile(partial) != expected) {
      await partial.delete();
      throw StateError('SHA-256 dell\'installer ${release.version} non valido');
    }
    if (await target.exists()) await target.delete();
    return partial.rename(target.path);
  }

  /// Installer di versioni precedenti rimasti in `%TEMP%\WonderFlix`.
  Future<void> _deleteOtherInstallers(Directory directory, File keep) async {
    await for (final entity in directory.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          name.startsWith('WonderFlix-Setup-') &&
          entity.path != keep.path) {
        try {
          await entity.delete();
        } on FileSystemException {
          // In uso o già eliminato: non importa.
        }
      }
    }
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
```

- [ ] **Step 5: esegui e verifica che passi**

Run: `flutter test test/features/update/update_controller_test.dart`
Expected: PASS. Il valore di `fakeInstallerSha256` è lo SHA-256 dei byte `[1, 2, 3]`: se un test fallisce per l'hash, ricalcolalo con `dart -e` o con un test temporaneo e correggi la costante (segnalandolo).

- [ ] **Step 6: commit**

```bash
git add lib/features/update/update_controller.dart test/features/update/update_controller_test.dart test/support/update_fakes.dart
git commit -m "feat: check, download and verify app updates"
```

---

### Task 5: player aperto

**Files:**
- Create: `lib/features/player/player_active.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_active_test.dart`, `test/features/player/player_screen_test.dart` (aggiunta)

- [ ] **Step 1: scrivi i test.** `test/features/player/player_active_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_active.dart';

void main() {
  test('conta le schermate del player aperte', () async {
    final c = ProviderContainer.test();
    final active = c.read(playerActiveProvider.notifier);
    expect(c.read(playerActiveProvider), isFalse);

    active.enter();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerActiveProvider), isTrue);

    // Episodio successivo: la nuova schermata entra prima che la vecchia esca.
    active.enter();
    active.leave();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerActiveProvider), isTrue);

    active.leave();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerActiveProvider), isFalse);
  });
}
```

In fondo al `main()` di `test/features/player/player_screen_test.dart` (import `package:wonderflix/features/player/player_active.dart`):

```dart
  testWidgets('segnala il player aperto finché non si esce', (tester) async {
    await pumpPlayer(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    expect(container.read(playerActiveProvider), isTrue);

    mediaSession.press(MediaButton.stop);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(container.read(playerActiveProvider), isFalse);
    await unmount(tester);
  });
```

- [ ] **Step 2: esegui e verifica che falliscano**

Run: `flutter test test/features/player/player_active_test.dart test/features/player/player_screen_test.dart`
Expected: FAIL (`player_active.dart` non esiste).

- [ ] **Step 3: crea** `lib/features/player/player_active.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` mentre una schermata del player è aperta: gli avvisi di
/// aggiornamento aspettano la fine del video.
class PlayerActiveController extends Notifier<bool> {
  /// Schermate aperte: passando all'episodio successivo, per un attimo due.
  int _open = 0;

  @override
  bool build() => false;

  void enter() {
    _open++;
    _publish();
  }

  void leave() {
    if (_open > 0) _open--;
    _publish();
  }

  /// Le schermate chiamano [enter] e [leave] in `initState`/`dispose`,
  /// mentre l'albero dei widget si sta costruendo: lo stato si aggiorna
  /// subito dopo.
  void _publish() => scheduleMicrotask(() {
        if (ref.mounted) state = _open > 0;
      });
}

final playerActiveProvider =
    NotifierProvider<PlayerActiveController, bool>(PlayerActiveController.new);
```

- [ ] **Step 4: collega la schermata.** In `lib/features/player/player_screen.dart` (import `player_active.dart`):
- nuovo campo dello stato: `late final PlayerActiveController _playerActive;`
- in `initState`, subito dopo `super.initState();`:

```dart
    _playerActive = ref.read(playerActiveProvider.notifier)..enter();
```

- in `dispose`, prima di `super.dispose();`:

```dart
    _playerActive.leave();
```

- [ ] **Step 5: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS.

- [ ] **Step 6: commit**

```bash
git add lib/features/player test/features/player
git commit -m "feat: track whether the player is open"
```

---

### Task 6: barra e schermata dell'aggiornamento

**Files:**
- Create: `lib/features/update/release_notes.dart`, `lib/features/update/update_banner.dart`, `lib/features/update/mandatory_update_screen.dart`, `lib/features/update/update_gate.dart`
- Modify: `lib/app/app.dart`
- Test: `test/features/update/update_gate_test.dart`

- [ ] **Step 1: scrivi il test** `test/features/update/update_gate_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/update/update_controller.dart';
import 'package:wonderflix/features/update/update_gate.dart';

import '../../support/pump_app.dart';
import '../../support/update_fakes.dart';

void main() {
  late FakeUpdateController controller;

  Future<ProviderContainer> pumpGate(WidgetTester tester, UpdateState state) async {
    controller = FakeUpdateController(state);
    await pumpApp(tester, const UpdateGate(child: Text('app')),
        overrides: [updateControllerProvider.overrideWith(() => controller)]);
    return ProviderScope.containerOf(tester.element(find.text('app')));
  }

  final installer = File('setup.exe');

  testWidgets('nessun aggiornamento: solo l\'app', (tester) async {
    await pumpGate(tester, const UpdateState());
    expect(find.text('app'), findsOneWidget);
    expect(find.text('Riavvia ora'), findsNothing);
  });

  testWidgets('download in corso (facoltativo): ancora niente barra',
      (tester) async {
    await pumpGate(tester, UpdateState(release: testRelease(), progress: 0.3));
    expect(find.text('Riavvia ora'), findsNothing);
  });

  testWidgets('pronto: barra con novità, "Riavvia ora" e "Più tardi"',
      (tester) async {
    await pumpGate(
        tester, UpdateState(release: testRelease(), installer: installer));
    expect(find.text('Aggiornamento pronto: WonderFlix 0.2.0'), findsOneWidget);
    expect(find.text('Più veloce'), findsNothing);

    await tester.tap(find.text('Novità'));
    await tester.pump();
    expect(find.text('Più veloce'), findsOneWidget);

    await tester.tap(find.text('Riavvia ora'));
    await tester.pump();
    expect(controller.installs, 1);

    await tester.tap(find.text('Più tardi'));
    await tester.pump();
    expect(find.text('Riavvia ora'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('mai durante la riproduzione: la barra compare alla fine',
      (tester) async {
    final container = await pumpGate(
        tester, UpdateState(release: testRelease(), installer: installer));
    container.read(playerActiveProvider.notifier).enter();
    await tester.pump();
    expect(find.text('Riavvia ora'), findsNothing);

    container.read(playerActiveProvider.notifier).leave();
    await tester.pump();
    expect(find.text('Riavvia ora'), findsOneWidget);
  });

  testWidgets('obbligatorio in download: schermata bloccante con avanzamento',
      (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            progress: 0.4));
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsOneWidget);
    expect(find.text('Download in corso… 40%'), findsOneWidget);
    expect(find.text('Più veloce'), findsOneWidget);
    // FilledButton.icon crea una sottoclasse: find.byType non la trova.
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Aggiorna ora'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button.onPressed, isNull);
    // L'app sotto non riceve clic.
    expect(
        tester.widget<IgnorePointer>(find.ancestor(
            of: find.text('app'), matching: find.byType(IgnorePointer)).first).ignoring,
        isTrue);
  });

  testWidgets('obbligatorio pronto: "Aggiorna ora" installa', (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            installer: installer));
    await tester.tap(find.text('Aggiorna ora'));
    await tester.pump();
    expect(controller.installs, 1);
  });

  testWidgets('obbligatorio fallito: messaggio e "Riprova"', (tester) async {
    await pumpGate(
        tester,
        UpdateState(
            release: testRelease(minVersion: '0.2.0'),
            mandatory: true,
            failed: true));
    expect(find.text('Download non riuscito. Controlla la connessione e riprova.'),
        findsOneWidget);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(controller.retries, 1);
  });

  testWidgets('obbligatorio durante la riproduzione: arriva alla fine del video',
      (tester) async {
    final container = await pumpGate(tester, const UpdateState());
    container.read(playerActiveProvider.notifier).enter();
    await tester.pump();
    controller.emit(UpdateState(
        release: testRelease(minVersion: '0.2.0'),
        mandatory: true,
        installer: installer));
    await tester.pump();
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsNothing);

    container.read(playerActiveProvider.notifier).leave();
    await tester.pump();
    expect(find.text('AGGIORNAMENTO NECESSARIO'), findsOneWidget);
  });
}
```

- [ ] **Step 2: esegui e verifica che fallisca**

Run: `flutter test test/features/update/update_gate_test.dart`
Expected: FAIL (i file non esistono).

- [ ] **Step 3: crea** `lib/features/update/release_notes.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Note di rilascio in markdown. I link si aprono nel browser.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: markdown,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
        onTapLink: (text, href, title) {
          final uri = href == null ? null : Uri.tryParse(href);
          if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
            unawaited(launchUrl(uri));
          }
        },
      );
}
```

- [ ] **Step 4: crea** `lib/features/update/update_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'release_info.dart';
import 'release_notes.dart';

/// Barra "Aggiornamento pronto" in basso, con le note apribili.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({
    super.key,
    required this.release,
    required this.onRestart,
    required this.onLater,
  });

  final ReleaseInfo release;
  final VoidCallback onRestart;
  final VoidCallback onLater;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _notesOpen = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final notes = widget.release.notes;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Material(
        color: WfColors.surfaceHigh,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_notesOpen && notes.isNotEmpty) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                      child: ReleaseNotes(markdown: notes)),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  const Icon(LucideIcons.download, color: WfColors.gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.updateReadyTitle(widget.release.version.toString()),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (notes.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _notesOpen = !_notesOpen),
                      child: Text(l.updateWhatsNew),
                    ),
                  TextButton(
                      onPressed: widget.onLater, child: Text(l.updateLater)),
                  const SizedBox(width: 8),
                  WfButton.primary(
                    label: l.updateRestartNow,
                    icon: LucideIcons.rotateCw,
                    onPressed: widget.onRestart,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: crea** `lib/features/update/mandatory_update_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'release_notes.dart';
import 'update_controller.dart';

/// Schermata bloccante: la versione installata è sotto `min-version`.
class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({
    super.key,
    required this.update,
    required this.onInstall,
    required this.onRetry,
  });

  final UpdateState update;
  final VoidCallback onInstall;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final release = update.release!;
    final progress = update.progress;
    return Material(
      color: WfColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.download, color: WfColors.gold, size: 40),
                const SizedBox(height: 16),
                Text(l.updateRequiredTitle.toUpperCase(),
                    style: WfText.display(36)),
                const SizedBox(height: 8),
                Text(l.updateRequiredBody(release.version.toString()),
                    style: const TextStyle(color: WfColors.creamMuted)),
                if (release.notes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                        child: ReleaseNotes(markdown: release.notes)),
                  ),
                ],
                const SizedBox(height: 24),
                if (update.failed)
                  Text(l.updateDownloadFailed,
                      style: const TextStyle(color: WfColors.error))
                else if (!update.ready) ...[
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(l.updateDownloading(((progress ?? 0) * 100).round())),
                ],
                const SizedBox(height: 16),
                if (update.failed)
                  WfButton.primary(
                      label: l.retry,
                      icon: LucideIcons.refreshCw,
                      onPressed: onRetry)
                else
                  WfButton.primary(
                    label: l.updateInstallNow,
                    icon: LucideIcons.download,
                    onPressed: update.ready ? onInstall : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: crea** `lib/features/update/update_gate.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../player/player_active.dart';
import 'mandatory_update_screen.dart';
import 'update_banner.dart';
import 'update_controller.dart';

/// Sopra tutte le schermate (nel `builder` di `MaterialApp.router`): barra
/// "Aggiornamento pronto" o schermata bloccante, mai mentre il player è
/// aperto. L'app resta montata sotto, così lo stato della navigazione non si
/// perde.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  /// Versione rimandata con "Più tardi" (fino al prossimo avvio).
  Version? _postponed;

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateControllerProvider);
    final playing = ref.watch(playerActiveProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final release = update.release;

    final blocked = release != null && update.mandatory && !playing;
    final showBanner = release != null &&
        update.ready &&
        !update.mandatory &&
        !playing &&
        _postponed != release.version;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: blocked,
          child: ExcludeFocus(excluding: blocked, child: widget.child),
        ),
        if (showBanner)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: Center(
              child: UpdateBanner(
                release: release,
                onRestart: () => unawaited(controller.install()),
                onLater: () => setState(() => _postponed = release.version),
              ),
            ),
          ),
        if (blocked)
          Positioned.fill(
            child: MandatoryUpdateScreen(
              update: update,
              onInstall: () => unawaited(controller.install()),
              onRetry: controller.retry,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 7: collega l'app.** In `lib/app/app.dart` (import `../features/update/update_gate.dart`), in `MaterialApp.router` dopo `routerConfig: …`:

```dart
      // Avvisi di aggiornamento sopra tutte le schermate.
      builder: (context, child) =>
          UpdateGate(child: child ?? const SizedBox.shrink()),
```

- [ ] **Step 8: esegui e verifica che passino**

Run: `flutter analyze && flutter test`
Expected: nessun problema, tutti PASS. Se un test fallisce solo per un overflow dovuto al font dei test, correggi il layout (es. `Flexible`) e segnalalo.

- [ ] **Step 9: commit**

```bash
git add lib/features/update lib/app/app.dart test/features/update/update_gate_test.dart
git commit -m "feat: show the update bar and the mandatory update screen"
```

---

### Task 7: nome dell'app per Windows (AppUserModelID)

**Files:**
- Modify: `windows/runner/main.cpp`

- [ ] **Step 1: modifica** `windows/runner/main.cpp`:
- dopo `#include <windows.h>` aggiungi `#include <shobjidl.h>`;
- dopo il blocco del mutex (dopo la `}` che chiude `if (instance_mutex != nullptr && …)`), aggiungi:

```cpp
  // Identità dell'app per Windows (pannello media, barra delle applicazioni).
  // È la stessa dei collegamenti creati dall'installer (installer/wonderflix.iss):
  // senza collegamento, in sviluppo, il pannello media mostra "Unknown app".
  ::SetCurrentProcessExplicitAppUserModelID(L"it.wonderflix.WonderFlix");
```

- [ ] **Step 2: build**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
taskkill //IM wonderflix.exe //F
flutter build windows --debug
```
Expected: build riuscita (`taskkill` può dire che il processo non esiste: va bene). Se il linker non trova `SetCurrentProcessExplicitAppUserModelID`, aggiungi `Shell32.lib` a `target_link_libraries` in `windows/runner/CMakeLists.txt` e segnalalo.

- [ ] **Step 3: verifica e commit**

Run: `flutter analyze && flutter test` → nessun problema, tutti PASS.

```bash
git add windows/runner/main.cpp
git commit -m "feat: give the app a Windows AppUserModelID"
```

---

### Task 8: installer Inno Setup

**Files:**
- Create: `installer/wonderflix.iss`
- Modify: `.gitignore`

- [ ] **Step 1: crea** `installer/wonderflix.iss`:

```iss
; WonderFlix: installer per utente (nessun UAC).
; Compilazione (dalla root del repository, dopo la build release):
;   ISCC.exe /DAppVersion=X.Y.Z installer\wonderflix.iss
; Risultato: dist\WonderFlix-Setup-X.Y.Z.exe

#ifndef AppVersion
  #error Passa la versione: ISCC.exe /DAppVersion=X.Y.Z installer\wonderflix.iss
#endif

#define AppName "WonderFlix"
#define AppExe "wonderflix.exe"
; Stesso mutex di windows\runner\main.cpp (una sola istanza).
#define AppMutex "Local\WonderFlix.SingleInstance"
; Stesso AppUserModelID di windows\runner\main.cpp.
#define AppUserModelId "it.wonderflix.WonderFlix"

[Setup]
; Non cambiare mai AppId: identifica l'installazione per aggiornamenti e
; disinstallazione.
AppId={{04C266E9-CC09-4851-91D0-CD9EFEC2D109}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=WonderFlix-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; L'attesa della chiusura dell'app è in [Code]. Niente AppMutex: in modalità
; silenziosa il suo messaggio risponderebbe "Annulla".
CloseApplications=no

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
italian.CloseWonderFlix=WonderFlix è aperto. Chiudilo e premi Riprova.
english.CloseWonderFlix=WonderFlix is running. Close it and press Retry.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Aggiornamento: via i file della versione precedente.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelId}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelId}"; Tasks: desktopicon

[Run]
; Installazione normale: casella "Avvia WonderFlix" alla fine.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Aggiornamento dall'app (silenzioso): riapre l'app.
Filename: "{app}\{#AppExe}"; Flags: nowait skipifnotsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  WaitStepMs = 500;
  WaitSteps = 60; { 30 secondi }

function AppRunning(): Boolean;
begin
  Result := CheckForMutexes('{#AppMutex}');
end;

{ Aggiornamento silenzioso: l'app avvia l'installer e poi si chiude, quindi
  si aspetta fino a 30 secondi. Installazione normale: si chiede di chiuderla. }
function InitializeSetup(): Boolean;
var
  I: Integer;
begin
  if WizardSilent() then
  begin
    I := 0;
    while AppRunning() and (I < WaitSteps) do
    begin
      Sleep(WaitStepMs);
      I := I + 1;
    end;
    Result := not AppRunning();
    if not Result then
      Log('WonderFlix è ancora aperto: installazione annullata.');
    Exit;
  end;
  while AppRunning() do
    if MsgBox(CustomMessage('CloseWonderFlix'), mbError, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

function InitializeUninstall(): Boolean;
begin
  while AppRunning() do
    if SuppressibleMsgBox(CustomMessage('CloseWonderFlix'), mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;
```

- [ ] **Step 2: ignora l'output.** In fondo a `.gitignore` aggiungi (con i fine riga del file):

```
# Installer generati (installer/wonderflix.iss)
/dist/
```

- [ ] **Step 3: compilazione locale (se possibile)**

```bash
ls "/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
```
- **Se esiste:**

```bash
flutter build windows --release --dart-define-from-file=config/wonderflix.json
"/c/Program Files (x86)/Inno Setup 6/ISCC.exe" "/DAppVersion=0.1.0" installer/wonderflix.iss
ls dist
```
Expected: `dist/WonderFlix-Setup-0.1.0.exe`. **Non eseguirlo** (vedi "App avviata da Claude" nelle regole).
- **Se non esiste:** non installarlo; scrivi nel resoconto che la verifica avverrà nel Task 11 (in CI, o dopo che l'utente avrà installato Inno Setup).

- [ ] **Step 4: commit**

```bash
git add installer/wonderflix.iss .gitignore
git commit -m "feat: add the per-user Inno Setup installer"
```

---

### Task 9: pipeline di release

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: crea** `.github/workflows/release.yml`:

```yaml
name: Release

# Parte con un tag vX.Y.Z (deve coincidere con la versione di pubspec.yaml).
# La GitHub Release viene creata come bozza: la pubblicazione è manuale
# (docs/RELEASING.md).
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: write

jobs:
  release:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.5
          cache: true

      - uses: dtolnay/rust-toolchain@stable

      - name: Versione
        id: version
        shell: pwsh
        run: |
          $line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
          $version = ($line.Matches[0].Groups[1].Value -split '\+')[0]
          if ($env:GITHUB_REF_NAME -ne "v$version") {
            Write-Error "Il tag $env:GITHUB_REF_NAME non corrisponde alla versione di pubspec.yaml ($version)"
            exit 1
          }
          "version=$version" >> $env:GITHUB_OUTPUT

      - name: Configurazione dai Secrets
        shell: pwsh
        env:
          SERVER_URL: ${{ secrets.WONDERFLIX_SERVER_URL }}
          DISCORD_APP_ID: ${{ secrets.WONDERFLIX_DISCORD_APP_ID }}
          SUPPORT_URL: ${{ secrets.WONDERFLIX_SUPPORT_URL }}
          ACCESS_REQUEST_URL: ${{ secrets.WONDERFLIX_ACCESS_REQUEST_URL }}
        run: |
          if (-not $env:SERVER_URL) {
            Write-Error 'Manca il Secret WONDERFLIX_SERVER_URL (docs/RELEASING.md)'
            exit 1
          }
          [ordered]@{
            serverUrl        = $env:SERVER_URL
            githubRepo       = $env:GITHUB_REPOSITORY
            discordAppId     = "$env:DISCORD_APP_ID"
            supportUrl       = "$env:SUPPORT_URL"
            accessRequestUrl = "$env:ACCESS_REQUEST_URL"
          } | ConvertTo-Json | Set-Content -Encoding utf8NoBOM config/wonderflix.json

      - run: flutter pub get
      - run: flutter gen-l10n
      - run: flutter analyze
      - run: flutter test

      - run: flutter build windows --release --dart-define-from-file=config/wonderflix.json

      - name: Runtime di Visual C++ accanto all'exe
        shell: pwsh
        run: |
          foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
            Copy-Item "$env:WINDIR\System32\$dll" build\windows\x64\runner\Release\
          }

      # Firma del codice: pronta ma spenta finché non c'è un certificato
      # (Secrets WONDERFLIX_SIGNING_CERT in base64 e WONDERFLIX_SIGNING_PASSWORD).
      - name: Firma dell'app (disattivata)
        if: ${{ false }}
        shell: pwsh
        run: |
          [IO.File]::WriteAllBytes('cert.pfx', [Convert]::FromBase64String('${{ secrets.WONDERFLIX_SIGNING_CERT }}'))
          signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f cert.pfx /p '${{ secrets.WONDERFLIX_SIGNING_PASSWORD }}' build\windows\x64\runner\Release\wonderflix.exe

      - name: Installer
        shell: pwsh
        run: |
          & "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DAppVersion=${{ steps.version.outputs.version }}" installer\wonderflix.iss
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

      - name: Firma dell'installer (disattivata)
        if: ${{ false }}
        shell: pwsh
        run: |
          signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f cert.pfx /p '${{ secrets.WONDERFLIX_SIGNING_PASSWORD }}' "dist\WonderFlix-Setup-${{ steps.version.outputs.version }}.exe"

      - name: SHA-256
        shell: pwsh
        run: |
          $name = "WonderFlix-Setup-${{ steps.version.outputs.version }}.exe"
          $hash = (Get-FileHash "dist\$name" -Algorithm SHA256).Hash.ToLower()
          Set-Content -Encoding ascii -NoNewline -Path "dist\$name.sha256" -Value "$hash  $name"

      - uses: actions/upload-artifact@v4
        with:
          name: wonderflix-setup
          path: dist/*

      - name: GitHub Release (bozza)
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create $env:GITHUB_REF_NAME dist/* --draft --title "WonderFlix ${{ steps.version.outputs.version }}" --notes "Scrivi qui le note di rilascio (docs/RELEASING.md)."
```

- [ ] **Step 2: controllo della sintassi**

```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml', encoding='utf-8')); print('ok')"
```
Expected: `ok`. Se `yaml` non è installato per Python, salta questo step e segnalalo.

- [ ] **Step 3: commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: build the installer and a draft release from version tags"
```

---

### Task 10: procedura di release

**Files:**
- Create: `docs/RELEASING.md`

- [ ] **Step 1: crea** `docs/RELEASING.md`:

````markdown
# Pubblicare una versione di WonderFlix

L'app controlla gli aggiornamenti su `https://api.github.com/repos/davidesidoti/wonderflix/releases/latest`: vede solo le release **pubblicate**, mai le bozze né le pre-release.

## Una volta sola: i Secrets

Su GitHub: *Settings → Secrets and variables → Actions → New repository secret*.

| Secret | Valore | Obbligatorio |
|---|---|---|
| `WONDERFLIX_SERVER_URL` | indirizzo https del server Jellyfin | sì |
| `WONDERFLIX_DISCORD_APP_ID` | Application ID dell'app Discord | no (senza, niente Rich Presence) |
| `WONDERFLIX_SUPPORT_URL` | link di "Password dimenticata?" (es. invito Discord) | no |
| `WONDERFLIX_ACCESS_REQUEST_URL` | link del pulsante "Chiedi l'accesso" su Discord (es. `https://discord.com/users/<id>`) | no |

`githubRepo` non serve: la pipeline usa il repository stesso.

Firma del codice (per ora spenta in `release.yml`): `WONDERFLIX_SIGNING_CERT` (certificato `.pfx` in base64) e `WONDERFLIX_SIGNING_PASSWORD`, poi togli `if: ${{ false }}` dai due passaggi di firma.

## Procedura

1. Aggiorna `version:` in `pubspec.yaml` (es. `0.1.1`) e fai commit su `main`.
2. Esegui la **checklist dei test manuali** (sotto) su una build locale.
3. Crea il tag e fai push:
   ```bash
   git tag v0.1.1
   git push origin v0.1.1
   ```
   Il tag deve essere esattamente `v` + la versione di `pubspec.yaml`, altrimenti la pipeline si ferma.
4. Attendi la fine di **Release** in *Actions*: la pipeline crea una GitHub Release in **bozza** con `WonderFlix-Setup-0.1.1.exe` e il suo `.sha256`.
5. Scrivi le note di rilascio nella bozza (markdown: l'app le mostra così).
6. **Solo se l'aggiornamento è obbligatorio** (compatibilità col server, bug gravi): aggiungi alle note la riga
   ```
   <!-- wonderflix:min-version=0.1.1 -->
   ```
   dove `0.1.1` è la versione minima ancora accettata (di solito quella che stai pubblicando). La riga non compare nelle note mostrate nell'app.
7. Pubblica la bozza. Da questo momento le app installate la trovano (all'avvio o entro 6 ore).
8. Per le prove interne pubblica come **pre-release**: le app la ignorano.
9. **Ricorda:** il marcatore si legge **solo nell'ultima release pubblicata**. Se una release successiva deve mantenere il blocco, riporta la stessa riga `min-version` (o una più alta).

## Come si aggiorna l'app

- Controllo all'avvio e ogni 6 ore (solo nelle build release).
- Se c'è una versione più nuova: scarica l'installer in `%TEMP%\WonderFlix`, verifica lo SHA-256, mostra "Aggiornamento pronto" con le note. *Riavvia ora* installa in silenzio e riapre l'app.
- Obbligatorio: schermata bloccante con avanzamento e *Aggiorna ora*.
- Mai durante la riproduzione: la barra o la schermata compaiono alla fine del video.
- Errori (rete, hash non valido): solo nel log (`%LocalAppData%\WonderFlix\logs`), nuovo tentativo al controllo successivo.

## Installazione

- Per utente, senza permessi di amministratore: `%LocalAppData%\Programs\WonderFlix`.
- Collegamenti su Start e Desktop; disinstallazione da *Impostazioni → App*.
- La disinstallazione toglie il programma. Log, preferenze e credenziali restano (log in `%LocalAppData%\WonderFlix`, credenziali nel Gestore credenziali di Windows).

## Checklist dei test manuali

Prima di ogni release, su un utente di prova:

- [ ] MKV con sottotitoli ASS interni, PGS interni e SRT esterni: resa corretta e sincronizzata.
- [ ] Ripresa dal minutaggio; stato "visto" sincronizzato con jellyfin-web.
- [ ] Ripiego sulla transcodifica (forzato: `--dart-define=wfBreakDirectPlay=true`).
- [ ] Salta intro, prossimo episodio, trickplay.
- [ ] Login con password e con Quick Connect; sessione scaduta.
- [ ] Aggiornamento da una versione precedente; aggiornamento obbligatorio.
- [ ] Discord Rich Presence attiva e disattivata.
- [ ] Pannello media di Windows con il nome "WonderFlix" (app installata).
- [ ] "Copia diagnostica" e cartella dei log.
````

- [ ] **Step 2: commit**

```bash
git add docs/RELEASING.md
git commit -m "docs: add the release procedure and manual test checklist"
```

---

### Task 11: verifica completa e prova con release vere

**Files:** nessuna modifica prevista (solo eventuali correzioni emerse e i cambi di versione).

- [ ] **Step 1: controlli automatici**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter analyze
flutter test
flutter build windows --debug
git status --short
```
Expected: nessun problema, tutti PASS, build riuscita. Se `git status` mostra solo `windows/flutter/generated_plugin*` con cambi di fine riga, `git checkout -- windows/flutter/`.

- [ ] **Step 2: prova con l'utente.** Ogni passaggio che pubblica qualcosa (push di branch o tag, pubblicazione di release) si fa **solo dopo l'ok esplicito dell'utente in quel momento**. L'installer e l'app installata li avvia l'utente da Esplora risorse, non la shell di Claude.

**Prerequisiti (utente):**
- i Secrets della tabella in `docs/RELEASING.md` configurati sul repository;
- facoltativo: Inno Setup installato in locale (`winget install JRSoftware.InnoSetup`) per provare l'installer prima della CI.

**A. Prima release (v0.1.0):**
1. Con l'ok dell'utente: `git tag v0.1.0` sull'ultimo commit del branch, poi `git push origin v0.1.0` (il tag porta con sé i commit; il branch non serve su GitHub).
2. Attendi la pipeline **Release** (`gh run watch` o la pagina *Actions*). Deve finire in verde, con una bozza che contiene `WonderFlix-Setup-0.1.0.exe` e `.sha256`.
3. L'utente pubblica la bozza, scarica l'installer e lo avvia. Controlla:
   - nessuna richiesta di amministratore;
   - installazione in `%LocalAppData%\Programs\WonderFlix`;
   - collegamenti su Start e Desktop;
   - l'app parte e funziona (login, un video);
   - il pannello media di Windows mostra "WonderFlix" invece di "Unknown app";
   - Impostazioni → Versione 0.1.0.

**B. Aggiornamento facoltativo (v0.1.1):**
1. Commit `chore: release 0.1.1` con `version: 0.1.1` in `pubspec.yaml`; con l'ok dell'utente tag `v0.1.1` e push del tag.
2. L'utente scrive due righe di note nella bozza e la pubblica.
3. L'utente riapre WonderFlix 0.1.0. Entro qualche secondo compare "Aggiornamento pronto: WonderFlix 0.1.1". *Novità* mostra le note.
4. *Riavvia ora*: l'app si chiude, l'installazione avviene senza finestre, l'app si riapre da sola. Impostazioni → Versione 0.1.1.

**C. Aggiornamento obbligatorio (v0.1.2):**
1. Commit `chore: release 0.1.2`; con l'ok dell'utente tag `v0.1.2` e push del tag.
2. L'utente pubblica la bozza con nelle note la riga `<!-- wonderflix:min-version=0.1.2 -->`.
3. L'utente riapre WonderFlix 0.1.1: compare subito la schermata "AGGIORNAMENTO NECESSARIO" con avanzamento e note (la riga del marcatore non si vede). L'app sotto non risponde ai clic.
4. *Aggiorna ora*: installazione silenziosa e riapertura in 0.1.2, senza blocchi.

"Mai durante la riproduzione" non si può provare dal vivo (il controllo parte all'avvio e poi ogni 6 ore): lo coprono i test di `update_gate_test.dart`.

**D. Disinstallazione:** da *Impostazioni → App*, con WonderFlix aperto: compare "WonderFlix è aperto. Chiudilo e premi Riprova". Chiuso e ripreso: programma e collegamenti rimossi.

- [ ] **Step 3:** le modifiche chieste dall'utente durante la prova si fanno con TDD nello stesso worktree, con un commit ciascuna. Il branch finale contiene i commit di versione (`0.1.2`): con il merge fast-forward, `main` resta allineato all'ultima release.
