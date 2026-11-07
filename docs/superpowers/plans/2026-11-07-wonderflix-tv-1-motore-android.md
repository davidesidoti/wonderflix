# WonderFlix TV — Piano 1: app Android e motore Media3 (fino alla prova)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WonderFlix compila e gira come app Android TV, con un terzo motore video (Media3 + libass) dietro `VideoEngine`, e supera (o no) la prova dei quattro casi sul Fire Stick dell'utente.

**Architecture:** Codice nativo Kotlin dentro `app/android` (nessun pacchetto a parte): un registro di player Media3 pilotato da un `MethodChannel`, eventi su un `EventChannel`, e il video in una `PlayerView` di Media3 mostrata in Flutter come platform view in Hybrid Composition (SurfaceView: niente HDR sbiadito, e l'overlay di libass è una View vera). Lato Dart `Media3Engine implements VideoEngine`; `createVideoEngine` lo sceglie su Android. Un profilo dispositivo Android TV costruito dalle capacità dei decoder dice al server cosa può andare in Direct Play.

**Tech Stack:** Flutter 3.47.5, Kotlin, AndroidX Media3 1.11.1 (`media3-exoplayer`, `media3-exoplayer-hls`, `media3-ui`), `io.github.peerless2012:ass-media` 0.5.1 (modalità `AssRenderType.OVERLAY_OPEN_GL`, la stessa dell'app Jellyfin per Android TV 0.20).

**Spec:** `docs/superpowers/specs/2026-11-07-wonderflix-tv-design.md`

Questo è il primo di più piani. Il design chiede di **fermarsi dopo la prova** (Task 6) e tornare dall'utente: interfaccia TV, Quick Connect su PC/web e distribuzione dell'APK avranno piani propri, scritti dopo l'esito.

## Global Constraints

- Flutter 3.47.5 (fissato in CI); Riverpod 3 (niente nomi Riverpod 2).
- Le build Windows e web non cambiano comportamento: `flutter test`, `flutter build windows --debug` e la build web restano verdi.
- `applicationId` e namespace Android: `it.wonderflix.tv`. Codice Kotlin in `app/android/app/src/main/kotlin/it/wonderflix/tv/`.
- `minSdk = 23` (minimo di Media3 1.11), `targetSdk`/`compileSdk` = quelli di Flutter. ABI: `armeabi-v7a` e `arm64-v8a`.
- Dispositivo di prova: Fire TV Stick AFTMA08C15, Fire OS 8.1.8.5 (Android 11), userland 32 bit, ~1,7 GB RAM, TV 1920×1080 **senza HDR**. ADB: `C:/Users/sidot/dev/android-sdk/platform-tools/adb.exe connect 192.168.1.171:5555`.
- Build di prova (da `app/`, Git Bash con `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`): `flutter build apk --release --split-per-abi --dart-define-from-file=config/wonderflix.json`, poi `adb -s 192.168.1.171:5555 install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`. In questo piano la build release è firmata con la chiave di debug (la chiave di rilascio arriva col piano di distribuzione).
- Docs, commenti e messaggi di commit in italiano; codice in inglese. Commit solo a nome dell'utente, senza `Co-Authored-By`, senza le parole `closes`/`fixes`/`resolves`.
- Subagenti: mai terminare processi per nome d'immagine (`taskkill /IM`, `pkill`). Build Windows completa, se serve: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Worktree: `.claude/worktrees/tv`, branch `feat/tv`. Copiare `app/config/wonderflix.json` dal checkout principale.

## Contratto del canale (usato da Task 2 e Task 3)

`MethodChannel('wonderflix/player')`. Ogni chiamata tranne `create` e `decoderCapabilities` porta `id` (int) negli argomenti (mappa).

| Metodo | Argomenti | Risultato |
|---|---|---|
| `create` | — | `int` id del player |
| `open` | `id`, `url`, `headers` (Map<String,String>), `startMs` (int) | `null`; carica in pausa (`playWhenReady=false`) partendo da `startMs`. L'esito arriva come evento `loaded` o `error` |
| `stop` | `id` | `null`; scarica il file |
| `play` / `pause` | `id` | `null` |
| `seek` | `id`, `ms` | `null` |
| `setVolume` | `id`, `volume` (double 0–1) | `null` |
| `setRate` | `id`, `rate` (double) | `null`; il tono resta invariato |
| `tracks` | `id` | lista di mappe `{id: String, type: 'video'\|'audio'\|'subtitle', formatId: String?, title: String?, language: String?}` |
| `selectAudio` / `selectSubtitle` | `id`, `track` (String? — `null` = nessuna) | `null` |
| `addSubtitle` | `id`, `url`, `title`, `language` | `String?` id della traccia aggiunta e selezionata, `null` se non compare entro 10 s |
| `setSubtitleDelay` | `id`, `ms` (positivo = più tardi) | `null` |
| `setSubtitleScale` | `id`, `scale` (1.0 = normale) | `null` |
| `dispose` | `id` | `null`; rilascia il player |
| `decoderCapabilities` | — | `{video: [{mime, maxWidth, maxHeight, tenBit}], audio: [mime], hdrTypes: ['HDR10', 'HLG', 'DOLBY_VISION', 'HDR10_PLUS']}` (dai decoder hardware di `MediaCodecList` e da `Display.getHdrCapabilities`) |

`EventChannel('wonderflix/player/events')`: un solo flusso per tutti i player, ogni evento è `{id: int, type: String, value: dynamic}`.

| `type` | `value` | Quando |
|---|---|---|
| `loaded` | `null` | primo `STATE_READY` dopo `open` |
| `error` | `String` | errore del player |
| `position` | `int` ms | ogni 250 ms mentre riproduce, e dopo ogni seek |
| `duration` | `int` ms | quando la durata cambia |
| `buffer` | `int` ms | con `position` |
| `playing` | `bool` | cambio di `isPlaying` |
| `buffering` | `bool` | `STATE_BUFFERING` sì/no |
| `completed` | `bool` | `STATE_ENDED` (`true`), nuovo `open` (`false`) |
| `firstFrame` | `null` | `onRenderedFirstFrame` |

Platform view: `viewType` `'wonderflix/player_view'`, `creationParams` `{id: int}`, codec `StandardMessageCodec`.

`formatId` è il `Format.id` di Media3: per MKV è il TrackNumber di Matroska (di solito indice ffprobe + 1). Con sottotitoli aggiunti diventa `"<periodo>:<id>"`: periodo `0` = il file, periodo > 0 = un file esterno.

## Review Focus

1. **Indietro durante il caricamento o con il decoder occupato**: il player si chiude senza bloccare l'app (nella prova con mpv qui è arrivato un ANR). → test in Task 2 (`dispose durante open`) e verifica in Task 6.
2. **File che non si apre** (404, formato rifiutato): `open` lancia `EngineOpenException` e non resta niente caricato, niente attesa infinita. → test in Task 2 (`error prima di loaded`, `timeout`).
3. **Due motori vivi insieme** (passaggio all'episodio successivo: il nuovo si crea prima che il vecchio sia chiuso): ognuno ascolta solo gli eventi del proprio `id`. → test in Task 2.
4. **Tracce dopo un sottotitolo esterno**: gli id `"0:3"` restano tracce del file con l'`ffIndex` giusto, `"1:…"` sono esterne. Una scelta sbagliata mostrerebbe la lingua sbagliata. → test in Task 2 (`parseFormatId`) e verifica con la traccia italiana in Task 6.
5. **TV senza HDR con file HDR10**: colori naturali, non slavati. → verifica in Task 6 (caso "Il cavaliere oscuro").

---

### Task 1: Target Android e avvio senza le parti Windows

**Files:**
- Create: `app/android/` (con `flutter create --platforms=android --org it.wonderflix --project-name wonderflix .` da `app/`, poi namespace/applicationId `it.wonderflix.tv` e `MainActivity` spostata in `kotlin/it/wonderflix/tv/`)
- Modify: `app/android/app/src/main/AndroidManifest.xml`, `app/android/app/build.gradle.kts`
- Modify: `app/lib/app/platform_startup_io.dart`
- Modify: `app/lib/core/logging/app_log.dart` (`logsDirectory`)
- Create: `app/lib/features/player/tv_player_window.dart`
- Modify: `app/lib/features/player/default_player_window_io.dart`
- Modify: `.github/workflows/ci.yml`
- Test: `app/test/features/player/tv_player_window_test.dart`, `app/test/core/logging/app_log_test.dart` (o il file di test esistente di `app_log`)

**Interfaces:**
- Produces: `class TvPlayerWindow implements PlayerWindow`; `bool get isAndroidTv` in `app/lib/core/platform/platform_info_io.dart` (`Platform.isAndroid`) e `false` in `platform_info_web.dart`.

- [ ] **Step 1: Test di `TvPlayerWindow`**: `supportsFullScreen == false`, `isFullScreen()` completa con `true`, `setFullScreen`/`lockLandscape`/`unlockOrientation`/`setPreventClose`/`hide` non lanciano, `fullScreenChanges` non emette. `destroy()` chiama `SystemNavigator.pop` (verificalo intercettando il canale `SystemChannels.platform` con `TestDefaultBinaryMessenger`).
- [ ] **Step 2: Test di `logsDirectory`**: il percorso è costruito con `Platform.pathSeparator` (nessun `\\` fisso) e su una base senza `LOCALAPPDATA` sta sotto `Directory.systemTemp`.
- [ ] **Step 3: Esegui i test e verifica che falliscano** — `flutter test test/features/player/tv_player_window_test.dart test/core/logging` → FAIL (classe mancante, separatore fisso).
- [ ] **Step 4: Implementa** `TvPlayerWindow` (tutto no-op, `addCloseListener`/`removeCloseListener` tengono solo la lista); `createPlayerWindow()` in `default_player_window_io.dart` restituisce `TvPlayerWindow()` se `isAndroidTv`, altrimenti `WindowManagerPlayerWindow()`. `logsDirectory` usa `Platform.pathSeparator`.
- [ ] **Step 5: Avvio Android in `initPlatform`**: se `isAndroidTv` non chiamare `MediaKit.ensureInitialized`, `setupWindow`, `localNotifier.setup`, `SMTCWindows.initialize` e restituire `false`; `platformOverrides` non sovrascrive `discordSessionProvider` su Android. `showWindowAfterStartupError` e il listener di `windowManager` (righe 67–74) non fanno niente su Android.
- [ ] **Step 6: Manifest e Gradle**: `INTERNET`; `<uses-feature android:name="android.software.leanback" android:required="false"/>` e `android.hardware.touchscreen` `required="false"`; categoria `LEANBACK_LAUNCHER` accanto a `LAUNCHER`; `android:banner` (320×180, ricavato dal logo in `app/assets/brand/`); `minSdk = 23`; `ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }`. Etichetta dell'app: `WonderFlix`.
- [ ] **Step 7: CI**: in `ci.yml` aggiungi un job `android` su `ubuntu-latest` con `actions/setup-java@v4` (Temurin 17), stessa `subosito/flutter-action`, `flutter pub get`, `flutter gen-l10n`, `flutter build apk --debug --target-platform android-arm`.
- [ ] **Step 8: Verifica** — `flutter analyze` pulito; `flutter test` tutto verde; `flutter build windows --debug` ok; `flutter build apk --release --split-per-abi --dart-define-from-file=config/wonderflix.json` ok.
- [ ] **Step 9: Verifica sul Fire Stick** — disinstalla la prova vecchia (`adb -s 192.168.1.171:5555 uninstall com.wonderflix.wonderflix`), installa l'APK armeabi-v7a, avvialo (`adb shell am start -n it.wonderflix.tv/.MainActivity`), cattura lo schermo (`adb exec-out screencap -p > shot.png`): compare il login e l'icona/banner c'è tra le app di Fire TV. L'accesso lo fa l'utente (le password non le inserisce l'agente). Se `git status` mostra `app/windows/flutter/generated_plugin*` cambiati solo nei fine riga, `git checkout --` quei file.
- [ ] **Step 10: Commit** — `feat(tv): target Android e avvio senza le parti Windows`

### Task 2: `Media3Engine` in Dart (contro il contratto del canale)

**Files:**
- Create: `app/lib/core/video/media3_engine.dart`
- Modify: `app/lib/core/video/default_video_engine_io.dart`
- Test: `app/test/core/video/media3_engine_test.dart`

**Interfaces:**
- Consumes: il contratto del canale (sopra); `VideoEngine`, `VideoSource`, `EngineTrack`, `EngineOpenException` da `video_engine.dart`.
- Produces: `class Media3Engine implements VideoEngine` con costruttore `Media3Engine({MethodChannel channel = const MethodChannel('wonderflix/player'), Stream<dynamic>? events})` (`events` di default: `EventChannel('wonderflix/player/events').receiveBroadcastStream()`); `static const openTimeout = Duration(seconds: 60)`; funzione pura `({int? ffIndex, bool external}) parseFormatId(String? formatId)`.

- [ ] **Step 1: Test** (canale finto con `TestDefaultBinaryMessenger.setMockMethodCallHandler`, eventi da uno `StreamController` passato come `events`):
  - `open` chiama `create` una sola volta, poi `open` con `url`, `headers`, `startMs: 90000` per `start: Duration(seconds: 90)`; completa solo dopo l'evento `{id, type: 'loaded'}`.
  - `error prima di loaded`: `open` lancia `EngineOpenException(message)` e chiama `stop`.
  - `timeout`: con `fake_async`, nessun evento per 60 s → `EngineOpenException('timeout')` e `stop`.
  - `dispose durante open`: `open` in attesa, `dispose()` → `open` completa con `EngineOpenException`, viene chiamato `dispose` sul canale, nessuno stream emette dopo.
  - `eventi di un altro id` (es. `id + 1`) non cambiano `position`, `playing` né completano `open`.
  - Stream: `position`/`duration`/`buffer` (ms → `Duration`), `playing`, `buffering`, `completed`, `firstFrame` completa al primo `firstFrame`, `errorStream` riceve `error` dopo `loaded`. Getter `position`/`duration`/`buffer`/`playing` = ultimo valore.
  - `tracks()` converte `type` e usa `parseFormatId`; `selectAudio(null)`/`selectSubtitle('2:1')` passano `track`; `setVolume(50)` passa `volume: 0.5`; `setSubtitleDelay(Duration(milliseconds: -1500))` passa `ms: -1500`.
  - `parseFormatId`: `'3'` → `(ffIndex: 2, external: false)`; `'0:3'` → `(2, false)`; `'1:0'` → `(null, true)`; `null`/`'abc'` → `(null, false)`.
  - `selectsEmbeddedTracks == true`; `playBlockedStream` non emette mai.
- [ ] **Step 2: Esegui e verifica che falliscano** — `flutter test test/core/video/media3_engine_test.dart` → FAIL (file mancante).
- [ ] **Step 3: Implementa `Media3Engine`**. L'id nativo è un `Future<int>` creato alla prima chiamata (il costruttore non chiama il canale). `buildView()` restituisce un `PlatformViewLink` con `PlatformViewsService.initExpensiveAndroidView` (Hybrid Composition), `viewType 'wonderflix/player_view'`, `creationParams {id}`; finché l'id non c'è, un `ColoredBox` nero.
- [ ] **Step 4: Scelta del motore** — firma `VideoEngine createVideoEngine({required bool hardwareDecoding, @visibleForTesting bool? androidTv})` in `default_video_engine_io.dart` (`androidTv` di default `isAndroidTv`; la versione web accetta e ignora lo stesso parametro): su Android TV restituisce `Media3Engine()` (ignora `hardwareDecoding`), altrimenti `MediaKitEngine` come oggi. Test: `createVideoEngine(hardwareDecoding: true, androidTv: true)` è un `Media3Engine`.
- [ ] **Step 5: Esegui** — `flutter test test/core/video` → PASS; `flutter test` tutto verde; `flutter analyze` pulito.
- [ ] **Step 6: Commit** — `feat(tv): motore Media3 lato Dart`

### Task 3: Player nativo Media3 (Kotlin) senza libass

**Files:**
- Create: `app/android/app/src/main/kotlin/it/wonderflix/tv/player/PlayerRegistry.kt` (canale, eventi, `decoderCapabilities`)
- Create: `.../player/TvPlayer.kt` (un `ExoPlayer` + listener → eventi)
- Create: `.../player/PlayerViewFactory.kt` (platform view con una `PlayerView` di `media3-ui`)
- Modify: `.../MainActivity.kt` (`configureFlutterEngine`: registra canale, `EventChannel`, factory)
- Modify: `app/android/app/build.gradle.kts` (dipendenze `androidx.media3:media3-exoplayer:1.11.1`, `media3-exoplayer-hls:1.11.1`, `media3-ui:1.11.1`)

**Interfaces:**
- Consumes: il contratto del canale.
- Produces: player nativi che rispettano il contratto; `TvPlayer.attach(view: PlayerView)` usato dalla factory.

- [ ] **Step 1: Implementa** secondo il contratto:
  - `PlayerView` con `useController = false`, `resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT`, fondo nero, superficie `SurfaceView` (default): le proporzioni giuste del formato cinema vengono da qui.
  - `open`: `MediaItem` con l'URL, header via `DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)`, timeout di connessione/lettura 60 s; `HlsMediaSource` se l'URL contiene `.m3u8`, altrimenti `ProgressiveMediaSource`; `setMediaSource(source, startMs)`, `prepare()`, `playWhenReady = false`.
  - `setRate`: `PlaybackParameters(rate)` (tono 1.0).
  - `tracks`: dai `Tracks.groups` correnti; `id` = `"<indice gruppo>:<indice traccia>"`; `formatId` = `Format.id`; `language` = `Format.language`; `title` = `Format.label`.
  - `selectAudio`/`selectSubtitle`: `TrackSelectionOverride` sul gruppo; `null` per i sottotitoli = `setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)`.
  - `addSubtitle`: rifà il `MediaItem` con una `SubtitleConfiguration` (mime da estensione: `.ass/.ssa` → `text/x-ssa`, `.srt` → `application/x-subrip`, `.vtt` → `text/vtt`), riprepara alla posizione corrente mantenendo play/pausa, attende il cambio di tracce (max 10 s) e seleziona la nuova.
  - `setSubtitleScale`: `subtitleView.setFractionalTextSize(SubtitleView.DEFAULT_TEXT_SIZE_FRACTION * scale)`. `setSubtitleDelay`: in questo piano non ha effetto (Media3 non ha un offset dei sottotitoli); scrive un log di avviso. Va segnalato nell'esito della prova.
  - Eventi: `position`/`buffer` ogni 250 ms con un `Handler` sul main looper mentre `isPlaying`, e dopo ogni seek.
  - `dispose`: ferma l'handler, `player.release()`, toglie il player dal registro; chiamate successive con quell'id vengono ignorate.
  - `decoderCapabilities`: solo decoder hardware (`MediaCodecInfo.isHardwareAccelerated`) di `MediaCodecList(REGULAR_CODECS)`; `tenBit` = il decoder HEVC dichiara `HEVCProfileMain10`; `hdrTypes` da `display.hdrCapabilities.supportedHdrTypes`.
- [ ] **Step 2: Verifica di build** — `flutter build apk --release --split-per-abi --dart-define-from-file=config/wonderflix.json` ok.
- [ ] **Step 3: Verifica sul Fire Stick** — installa, l'utente accede, apri "2012" (1080p H.264) da Cerca e avvia. Con `adb exec-out screencap -p` controlla: immagine visibile, controlli Flutter sopra il video, la posizione avanza; pausa e seek funzionano; Indietro torna alla scheda del film senza blocchi (nessuna riga `Input event dispatching timed out` in `adb logcat -d`).
- [ ] **Step 4: Commit** — `feat(tv): player Media3 nativo`

### Task 4: Sottotitoli ASS con libass

**Files:**
- Modify: `.../player/TvPlayer.kt`, `.../player/PlayerViewFactory.kt`
- Modify: `app/android/app/build.gradle.kts` (`io.github.peerless2012:ass-media:0.5.1`)

**Interfaces:**
- Consumes: Task 3.
- Produces: tracce ASS/SSA interne ed esterne disegnate da libass con il loro stile.

- [ ] **Step 1: Implementa** come l'app Jellyfin per Android TV: player costruito con supporto ASS (`AssHandler(AssRenderType.OVERLAY_OPEN_GL, AssHandlerConfig(maxRenderPixels = 1920 * 1080))`, `AssSubtitleParserFactory`, `withAssMkvSupport` sull'`ExtractorsFactory`, `AssRenderersFactory`), `assHandler.init(player)` e `AssSubtitleView` aggiunta dentro `playerView.subtitleView`. Per i sottotitoli esterni ASS usa id ≥ 128 come chiede il README di ass-media. `setSubtitleScale` sugli ASS: se `AssHandler` non espone una scala, resta senza effetto (log di avviso) e va segnalato nell'esito.
- [ ] **Step 2: Verifica ABI** — `unzip -l` dell'APK `armeabi-v7a`: contiene `lib/armeabi-v7a/` con le librerie di libass (`libass*.so` o simili). Se mancano, fermati e segnalalo.
- [ ] **Step 3: Verifica sul Fire Stick** — "A Sign of Affection" S1E1: scegli "Italian - ASS" dal menu tracce; con `screencap` durante un dialogo i sottotitoli italiani si vedono, con lo stile del file. Cambia in "English - ASS": cambia lingua (prova che `ffIndex` mappa la traccia giusta).
- [ ] **Step 4: Commit** — `feat(tv): sottotitoli ASS con libass`

### Task 5: Profilo dispositivo Android TV

**Files:**
- Create: `app/lib/core/jellyfin/android_tv_profile.dart`
- Modify: `app/lib/app/platform_startup_io.dart` (legge le capacità all'avvio su Android)
- Modify: `app/lib/features/player/player_providers.dart` (`playbackApiProvider`)
- Test: `app/test/core/jellyfin/android_tv_profile_test.dart`

**Interfaces:**
- Consumes: `decoderCapabilities` del canale; `textSubtitleFormats`, `imageSubtitleFormats`, `externalSubtitleFormats`, `originalQualityBitrate` da `device_profile.dart`.
- Produces: `class DecoderCaps { final List<VideoDecoderCaps> video; final List<String> audioMimes; final List<String> hdrTypes; factory DecoderCaps.fromMap(Map map); }`, `class VideoDecoderCaps { String mime; int maxWidth; int maxHeight; bool tenBit; }`, `Map<String, dynamic> buildAndroidTvDeviceProfile(DecoderCaps caps, {int maxBitrate = originalQualityBitrate})`, `final decoderCapsProvider = Provider<DecoderCaps?>((ref) => null)` (sovrascritto all'avvio su Android).

- [ ] **Step 1: Test di `buildAndroidTvDeviceProfile`**:
  - `Name == 'WonderFlix (Android TV)'`, `MaxStreamingBitrate == maxBitrate`.
  - Un `DirectPlayProfiles` Video con `Container` `'mkv,webm,mp4,m4v,mov,ts'`; `VideoCodec` dai mime: `video/avc` → `h264`, `video/hevc` → `hevc`, `video/x-vnd.on2.vp9` → `vp9`, `video/av01` → `av1` (solo quelli presenti); `AudioCodec` dai mime: `audio/mp4a-latm` → `aac`, `audio/mpeg` → `mp3`, `audio/ac3` → `ac3`, `audio/eac3` → `eac3`, `audio/vnd.dts` → `dts`, `audio/flac` → `flac`, `audio/opus` → `opus`, `audio/vorbis` → `vorbis`.
  - Con HEVC `tenBit: false`: un `CodecProfiles` per `hevc` con condizione `VideoBitDepth LessThanEqual 8`; con `tenBit: true` nessuna condizione sulla profondità.
  - Per ogni codec video: condizioni `Width LessThanEqual maxWidth` e `Height LessThanEqual maxHeight` dei suoi caps.
  - `TranscodingProfiles` uguale a quello di `buildDeviceProfile` (HLS, `h264`, `aac,mp3,ac3,eac3`).
  - `SubtitleProfiles`: `Embed` per testuali e grafici, `External` per `externalSubtitleFormats` (come `buildDeviceProfile`).
  - Caso del Fire Stick dell'utente: caps con `video/hevc` 4096×2176 `tenBit: true`, `hdrTypes: []` → `hevc` in `VideoCodec` senza condizioni su HDR (il decoder converte in SDR: il design chiede colori naturali anche così).
- [ ] **Step 2: Esegui e verifica che falliscano** — `flutter test test/core/jellyfin/android_tv_profile_test.dart` → FAIL.
- [ ] **Step 3: Implementa** il profilo; su Android `initPlatform` chiama `decoderCapabilities` e `platformOverrides` aggiunge `decoderCapsProvider.overrideWithValue(caps)`; `playbackApiProvider`: se `decoderCapsProvider` ha un valore, `PlaybackApi(http, profile: (b) => buildAndroidTvDeviceProfile(caps, maxBitrate: b))`; web e Windows come oggi. Logga le capacità all'avvio (`_log.info`).
- [ ] **Step 4: Esegui** — `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Verifica sul Fire Stick** — dopo l'avvio, nel log Jellyfin (`ssh ultra`, `~/.apps/jellyfin/log/log_YYYYMMDD.log`) i quattro titoli di Task 6 partono con `play_method = "DirectPlay"`; un file con audio DTS (se il Fire Stick non ha il decoder) parte in conversione audio senza errori.
- [ ] **Step 6: Commit** — `feat(tv): profilo dispositivo Android TV`

### Task 6: La prova dei quattro casi (cancello)

**Files:**
- Modify: questo piano (sezione "Esito della prova" in fondo)

- [ ] **Step 1: Build e installazione** — build release `--split-per-abi`, installa l'APK armeabi-v7a sul Fire Stick, avvia; l'utente accede se serve.
- [ ] **Step 2: I quattro casi**, uno per volta, chiedendo all'utente cosa vede (lo screenshot non giudica la fluidità):

  | Caso | Titolo | Cosa deve succedere |
  |---|---|---|
  | 4K HDR su TV SDR | Il cavaliere oscuro (2008) | fluido, colori naturali (non slavati), proporzioni giuste |
  | 4K ~30 Mbps, formato cinema | Fondazione S3E1 | fluido, niente schiacciamento né banda verde |
  | Anime con ASS | A Sign of Affection S1E1 | fluido, "Italian - ASS" visibile con il suo stile, cambio lingua corretto |
  | 1080p semplice | 2012 (2009) | fluido |

  Per ciascuno: Indietro esce dal player senza blocchi (`adb logcat -d | grep "Input event dispatching timed out"` vuoto) e il server fa Direct Play.
- [ ] **Step 3: Rimetti a posto l'account** — controlla con lo script Python in sola lettura su `jellyfin.db` (`UserData` di `davide.sidoti`) che "Il cavaliere oscuro" e Fondazione S3E1 siano ancora visti; se la prova li ha cambiati, rimettili dall'app (pulsante "visto"). Non segnare come vista l'intera serie "A Sign of Affection": avviserebbe gli amici.
- [ ] **Step 4: Scrivi l'esito** — per ogni caso: passato/non passato, cosa ha visto l'utente, CPU e memoria (`adb shell top -b -n 1 -o %CPU,RES,ARGS | grep wonderflix`), più gli effetti non coperti: ritardo dei sottotitoli e scala degli ASS (Task 3–4). Commit — `docs(tv): esito della prova del motore Media3`.
- [ ] **Step 5: Fermati** — riporta l'esito all'utente. Se anche un solo caso non passa, non si prosegue: si decide con l'utente. Se passano tutti, il passo successivo è il piano 2 (interfaccia TV), da scrivere con lui.

## Esito della prova

_Da compilare in Task 6._
