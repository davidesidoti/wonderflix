# WonderFlix TV 5: distribuzione dell'APK e aggiornamenti sulla TV — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** l'APK della TV esce con ogni rilascio (firmato con una chiave stabile), si installa con Downloader da un indirizzo fisso e si aggiorna dall'app sulla TV.

**Architecture:** la pipeline `release.yml` costruisce un APK unico (armeabi-v7a + arm64-v8a) firmato con la chiave di rilascio dai Secrets, lo allega alla release con il suo `.sha256` e il job `web` lo copia sul sito come `tv.apk`. Nell'app `features/update` sceglie l'asset giusto per piattaforma; sulla TV scarica l'APK nella cache e lo passa all'installer di sistema con un `FileProvider` (metodo nativo sul canale `wonderflix/device`).

**Tech Stack:** Flutter 3.47.5, Riverpod 3, Kotlin (MainActivity), Gradle Kotlin DSL, GitHub Actions, nginx.

**Spec:** `docs/superpowers/specs/2026-11-07-wonderflix-tv-design.md`, sezione "Installazione e aggiornamenti". Stato di partenza e richieste in `.claude/handoff-tv-prossimi-passi.md` (passo 2) della checkout principale.

## Decisioni (con l'utente, 2026-11-08)

- Indirizzo fisso `https://hashvps.proton.usbx.me/wonderflix/tv.apk`, più un **codice numerico di Downloader** che l'utente crea su aftv.news e che punta lì. Nel codice e nei documenti il codice compare solo come segnaposto `<CODICE>` finché l'utente non lo dà.
- La chiave di firma la genera uno **script che lancia l'utente** (`app/android/create_release_key.sh`): l'agente non vede mai la password.

## Decisioni del controller

- **Un solo APK** per release, `WonderFlix-TV-X.Y.Z.apk` (+ `.sha256`), con entrambe le ABI ARM: niente scelta dell'ABI nell'app né nel sito, niente `x86_64`. Niente più `--split-per-abi`.
- **versionCode** calcolato da `versionName` in Gradle: `major * 1_000_000 + minor * 1_000 + patch` (0.33.0 → 33000). Oggi è 1 per ogni versione.
- **Firma:** `app/android/key.properties` (già in `.gitignore`, come `*.jks`) con `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Se c'è, la build release firma con quella; se manca, firma di debug come oggi (sviluppo). In CI il file si crea dai Secrets e la release **fallisce** se mancano: mai un APK di rilascio con la chiave di debug.
- **Sulla TV niente banner** (focus rubato): l'aggiornamento disponibile compare in **Impostazioni** sotto la riga della versione, con il pulsante "Aggiorna" (focalizzabile). La schermata obbligatoria vale anche sulla TV.
- **Permesso "installa app sconosciute":** se Android non lo concede (`canRequestPackageInstalls() == false`), il nativo apre `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` per il pacchetto e l'app mostra come fare; al ritorno si preme di nuovo "Aggiorna". Se quell'attività non esiste (Fire OS vecchi), si apre `Settings.ACTION_SECURITY_SETTINGS`.

## Global Constraints

- Fuori dalla TV (Windows, web) il comportamento resta identico: stesso asset `WonderFlix-Setup-X.Y.Z.exe`, stesso banner.
- Documenti, testi e commit in italiano; codice in inglese. Testi nuovi in `app/l10n/app_it.arb` e `app_en.arb`.
- Commit solo a nome dell'utente, senza `Co-Authored-By`, senza le parole closes/fixes/resolves; `git commit -F <file>` senza BOM.
- Mai `taskkill /IM` / `pkill`. Build Windows: `flutter build windows --release --dart-define-from-file=config/wonderflix.json` da `app/`.
- Nessun bump di versione in questo branch (si decide al rilascio).
- Niente `dart format` su file vecchi interi.

## Review Focus

1. Firma diversa sul dispositivo (APK di debug installato, arriva quello di rilascio): l'installer di sistema rifiuta; l'app non deve restare su una schermata senza uscita — il messaggio dice di disinstallare e reinstallare da Downloader. (Task 4/5: dopo un avvio dell'installer l'app resta usabile, "Aggiorna" si può ripremere.)
2. Download interrotto o SHA-256 sbagliato sulla TV: come su Windows, il file parziale si cancella e la schermata obbligatoria mostra Riprova focalizzato. (Task 4, test del controller con `tv: true`.)
3. Release senza APK (tutte quelle fino alla 0.33.0): sulla TV `parseRelease` restituisce `null` → nessun aggiornamento, nessun obbligo, mai un blocco. (Task 3.)
4. Utente che nega il permesso o torna indietro dalle impostazioni di Android: stato "permesso necessario", pulsante ancora attivo, nessun loop che riapre le impostazioni da solo. (Task 4.)
5. Release pubblicata mentre il job `android` è fallito: la release Windows è comunque in bozza finché l'utente non pubblica; il job `web` non deve pubblicare un `tv.apk` vecchio o mancante senza accorgersene (dipende da `android`). (Task 2.)

---

### Task 1: build Android firmata e versionCode

**Files:**
- Modify: `app/android/app/build.gradle.kts`
- Create: `app/android/create_release_key.sh`
- Modify: `CLAUDE.md` (riga "TV APK": nuovo comando, `key.properties`)

- [ ] **Step 1:** in `build.gradle.kts` leggi `rootProject.file("key.properties")` con `java.util.Properties`; se esiste, `signingConfigs.create("release")` con i quattro valori e usala in `buildTypes.release`, altrimenti resta `signingConfigs.getByName("debug")`. Commento in italiano sul perché.
- [ ] **Step 2:** `versionCode` da `flutter.versionName` con la formula delle decisioni (parti numeriche prima di un eventuale `-`/`+`); errore di build chiaro se non è `X.Y.Z`.
- [ ] **Step 3:** `create_release_key.sh` (Git Bash): rifiuta di partire se `app/android/key.properties` o `wonderflix-release.jks` esistono già; password casuale con `openssl rand -base64 32` (senza `/+=`), `keytool -genkeypair -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10000 -alias wonderflix -dname "CN=WonderFlix" -keystore app/android/wonderflix-release.jks` (keytool dal JDK `C:/Users/sidot/dev/jdk-17.0.21.0.2+1/bin` se non è nel PATH), scrive `key.properties` (`storeFile=../wonderflix-release.jks`, stessa password per store e chiave), carica `gh secret set WONDERFLIX_ANDROID_KEYSTORE` (base64 del .jks, da stdin) e `WONDERFLIX_ANDROID_KEYSTORE_PASSWORD` (da stdin), **senza mai stampare la password**. Alla fine stampa: "Salva wonderflix-release.jks e key.properties nel gestore di password: senza, ogni utente dovrà reinstallare."
- [ ] **Step 4: Verifica** senza `key.properties`: da `app/` `flutter build apk --release --dart-define-from-file=config/wonderflix.json` produce `build/app/outputs/flutter-apk/app-release.apk`; `C:/Users/sidot/dev/android-sdk/build-tools/<versione>/aapt dump badging` mostra `versionCode='33000'` e `native-code: 'arm64-v8a' 'armeabi-v7a'`; `keytool -printcert -jarfile` mostra il certificato di debug (`CN=Android Debug`). Con un `key.properties` di prova creato in uno scratch fuori dal repo (keystore usa e getta, poi cancellato) la firma cambia. Non lanciare lo script vero.
- [ ] **Step 5:** `CLAUDE.md`: il comando TV diventa `flutter build apk --release --dart-define-from-file=config/wonderflix.json`, installazione di `build/app/outputs/flutter-apk/app-release.apk`; una riga: "le build di prova vanno firmate con la chiave di rilascio (`app/android/key.properties` e `.jks` della checkout principale, da copiare nel worktree), altrimenti il Fire Stick rifiuta l'aggiornamento". Commit `build(tv): firma di rilascio e versionCode dalla versione`.

### Task 2: pipeline e sito

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `app/deploy/wonderflix.conf`
- Modify: `docs/RELEASING.md`

**Interfaces:** asset `WonderFlix-TV-<version>.apk` e `WonderFlix-TV-<version>.apk.sha256` (formato `<hash>  <nome>`, come l'exe) — li usa il Task 3.

- [ ] **Step 1:** nuovo job `android` (`needs: release`, ubuntu, `actions/setup-java@v4` temurin 17, flutter 3.47.5): versione da `pubspec.yaml` come nel job `release` (stesso controllo del tag), configurazione dai Secrets come nel job `web`, `key.properties` + `.jks` dai Secrets `WONDERFLIX_ANDROID_KEYSTORE` / `WONDERFLIX_ANDROID_KEYSTORE_PASSWORD` (errore `::error::` se mancano), `flutter build apk --release --dart-define-from-file=config/wonderflix.json`, rinomina in `dist/WonderFlix-TV-$version.apk`, `.sha256` con `sha256sum` nel formato dell'exe, `actions/upload-artifact@v4` nome `wonderflix-tv`, `gh release upload $GITHUB_REF_NAME <file> --clobber` (la bozza l'ha creata `release`). Cancella `key.properties` e `.jks` alla fine (`if: always()`).
- [ ] **Step 2:** job `web`: `needs: [release, android]`; scarica l'artefatto `wonderflix-tv` e lo copia in `build/web/tv.apk` prima del primo `rsync` (così `--delete` non lo toglie).
- [ ] **Step 3:** `wonderflix.conf`: `location = /wonderflix/tv.apk` con `Cache-Control "no-cache"` e il tipo `application/vnd.android.package-archive` (stesse header COOP/COEP degli altri location, l'`add_header` non si eredita). La conf sul server si copia a mano al rilascio (CLAUDE.md): annotarlo in RELEASING.
- [ ] **Step 4:** `docs/RELEASING.md`: i due Secrets nuovi (creati dallo script del Task 1), il job `android`, `tv.apk` sul sito, la copia a mano di `wonderflix.conf`, e la prova della prima release con APK: una build locale con versione più bassa (es. `0.33.99`, `pubspec` non committato) firmata con la chiave di rilascio, installata via adb, deve vedere la release nuova e aggiornarsi da Impostazioni.
- [ ] **Step 5: Verifica:** rileggi il workflow (indentazione, `needs`, nomi degli artefatti, `working-directory`); se `actionlint` non c'è, `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml'))"`. Commit `ci(tv): APK nella release e tv.apk sul sito`.

### Task 3: l'asset giusto per piattaforma

**Files:**
- Modify: `app/lib/features/update/release_info.dart`, `app/lib/features/update/update_controller.dart`
- Test: `app/test/features/update/release_info_test.dart`, `update_controller_test.dart`

**Interfaces:** `ReleaseInfo? parseRelease(Map<String, dynamic> json, {bool tv = false})`; con `tv` cerca `WonderFlix-TV-$version.apk` e `.apk.sha256`, altrimenti l'exe. I campi `installerName/installerUrl/checksumUrl` restano (sono "il file da installare").

- [ ] **Step 1: test:** `parseRelease(json, tv: true)` con gli asset exe+apk → `installerName == 'WonderFlix-TV-0.34.0.apk'`; con solo l'exe → `null`; `tv: false` invariato (test esistenti verdi).
- [ ] **Step 2:** implementa; nel controller `parseRelease(json, tv: ref.read(androidTvProvider))`; la regex dei file vecchi diventa `^WonderFlix-(?:Setup-(.+)\.exe|TV-(.+)\.apk)(\.part)?$` e `_deleteOtherInstallers` considera anche `WonderFlix-TV-`. Test: un `WonderFlix-TV-0.32.0.apk` nella cartella viene cancellato con la versione attuale 0.33.0.
- [ ] **Step 3:** test verdi, commit `feat(update): sulla TV l'aggiornamento è l'APK`.

### Task 4: installazione sulla TV

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml` (permesso `android.permission.REQUEST_INSTALL_PACKAGES`, `<provider androidx.core.content.FileProvider>` con authority `${applicationId}.updates`, `exported=false`, `grantUriPermissions=true`)
- Create: `app/android/app/src/main/res/xml/update_paths.xml` (`<cache-path name="updates" path="WonderFlix/"/>`: `Directory.systemTemp` su Android è la cache dell'app — verificarlo e adattare il percorso)
- Modify: `app/android/app/src/main/kotlin/it/wonderflix/tv/MainActivity.kt` (metodo `installApk` sul canale `wonderflix/device`; aggiungere `androidx.core:core` alle dipendenze solo se non è già transitiva)
- Modify: `app/lib/features/update/update_controller.dart`
- Test: `app/test/features/update/update_controller_test.dart`

**Interfaces:**
- Nativo: `installApk({path: String}) → "started" | "needsPermission"`. `needsPermission`: apre le impostazioni del permesso (vedi decisioni) e non avvia l'installer. `started`: `Intent.ACTION_VIEW` con l'URI del FileProvider, tipo `application/vnd.android.package-archive`, `FLAG_GRANT_READ_URI_PERMISSION | FLAG_ACTIVITY_NEW_TASK`. Errori → `result.error`.
- Dart: `enum InstallOutcome { started, needsPermission }`; `installUpdateProvider` diventa `Provider<Future<InstallOutcome> Function(File installer)>`: su Windows come oggi (non ritorna, `exit(0)`), sulla TV chiama il canale. `UpdateState` riceve `bool installPermissionNeeded` (default `false`).
- Controller: niente più uscita anticipata per `androidTvProvider` in `build()`. `install()`: `needsPermission` → stato con l'installer pronto e `installPermissionNeeded: true`; `started` → stato invariato (l'installer di sistema sostituisce l'app; se l'utente annulla, l'app resta usabile e "Aggiorna" si ripreme); eccezione → come oggi (si riscarica).

- [ ] **Step 1: test** (con `androidTvProvider` sostituito a `true` e `installUpdateProvider` finto): release con APK → scarica e verifica il `.apk`; `install()` con esito `needsPermission` → `installPermissionNeeded` vero e `ready` vero; un secondo `install()` con `started` → `installPermissionNeeded` falso; con `false` (Windows) i test esistenti invariati.
- [ ] **Step 2:** implementa Dart e nativo. **Step 3: verifica sul Fire Stick** solo del nativo, senza release: con una build di debug che chiama `installApk` su un APK copiato a mano nella cache (`adb push` + `run-as it.wonderflix.tv` se serve) — oppure, se troppo lungo, rimanda alla prova di rilascio del Task 2 e scrivilo nell'esito. Mai OK sui pulsanti Riproduci della TV; nessuna disinstallazione senza chiedere al controller.
- [ ] **Step 4:** test verdi, commit `feat(tv): aggiornamento con l'installer di Android`.

### Task 5: interfaccia sulla TV

**Files:**
- Modify: `app/lib/features/settings/settings_screen.dart` (sulla TV, sotto la riga della versione)
- Create: `app/lib/features/update/tv_update_tile.dart`
- Modify: `app/lib/features/update/mandatory_update_screen.dart`, `update_gate.dart` (se serve)
- Test: `app/test/features/update/tv_update_tile_test.dart`, `update_gate_test.dart`

- [ ] **Step 1: test:** sulla TV con un aggiornamento pronto Impostazioni mostra "WonderFlix X.Y.Z disponibile" e il pulsante "Aggiorna" (focalizzabile, chiama `install()`); in download mostra la percentuale; con `installPermissionNeeded` il testo "Consenti a WonderFlix di installare app (Impostazioni di Android → Installa app sconosciute), poi premi di nuovo Aggiorna."; senza aggiornamento niente. Fuori dalla TV il riquadro non c'è. Schermata obbligatoria sulla TV: il pulsante (Aggiorna o Riprova) ha il focus all'apertura, il testo del permesso compare anche lì, e c'è sempre una riga "Se l'aggiornamento non va, disinstalla WonderFlix e reinstallalo con Downloader (codice <CODICE>)." — il codice da una costante `tvDownloaderCode` in `tv_update_tile.dart`, oggi `null`: senza codice la riga dice l'indirizzo `hashvps.proton.usbx.me/wonderflix/tv.apk`.
- [ ] **Step 2:** implementa (componenti esistenti: `WfButton`, focus TV come nelle altre pagine TV). **Step 3:** test verdi, `flutter gen-l10n`, commit `feat(tv): aggiornamento da Impostazioni e schermata obbligatoria`.

### Task 6: istruzioni e checklist

**Files:**
- Create: `docs/INSTALLAZIONE-TV.md` (per gli utenti: attivare Opzioni sviluppatore/"App da fonti sconosciute" per Downloader sul Fire TV, installare Downloader dallo store Amazon, scrivere il codice `<CODICE>` o l'indirizzo, installare, entrare con Quick Connect da WonderFlix su PC/telefono; aggiornamenti da Impostazioni)
- Modify: `docs/RELEASING.md` (righe di test manuale TV: installazione con Downloader, aggiornamento da Impostazioni con il permesso la prima volta, schermata obbligatoria sulla TV)

- [ ] **Step 1:** scrivi, poi `flutter gen-l10n`, `flutter analyze`, `flutter test` completi da `app/`. Commit `docs(tv): installazione con Downloader e checklist`.

## Prova a mano (controller con l'utente)

1. L'utente lancia `bash app/android/create_release_key.sh` nella checkout principale e salva `.jks` + `key.properties`.
2. Sul Fire Stick: disinstallare l'APK con la chiave di debug (si perde il login), installare la build del branch firmata con la chiave nuova, rientrare con Quick Connect.
3. L'aggiornamento vero si prova al primo rilascio con APK (Task 2, step 4).
