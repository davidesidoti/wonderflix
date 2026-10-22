# WonderFlix 27 — WonderFlix nel browser del PC: piano di realizzazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Obiettivo:** compilare tutta l'app Flutter anche per il web e pubblicarla su `https://hashvps.proton.usbx.me/wonderflix/`, con un player web che fa convertire al server il meno possibile. L'app Windows resta com'è.

**Architettura:**
- Il codice solo Windows passa dietro file "di piattaforma" con import condizionali: `export 'x_io.dart' if (dart.library.js_interop) 'x_web.dart';`.
- Nel browser:
  - c'è un `WebVideoEngine` (`<video>` + hls.js) dietro l'interfaccia `VideoEngine` che esiste già;
  - un profilo per il browser costruito dalle prove di `canPlayType`;
  - il token va nell'URL (`ApiKey`) solo dove il browser non può mandare header.
- Il sito è statico nel nginx utente di ultra.cc e si aggiorna da `release.yml` via rsync.

**Tecnologie:** Flutter 3.47.5 (web, wasm con ripiego JS), `package:web` + `dart:js_interop`, hls.js, `@jellyfin/libass-wasm`, `libbitsub`, nginx, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-22-wonderflix-web-pc-design.md`. Va letta prima di ogni task.

## Vincoli globali

- I comandi flutter si lanciano da `app/`. Nel worktree nuovo, `app/config/wonderflix.json` si copia da `C:\Users\sidot\Documents\Github\wonderflix\app\config\wonderflix.json`. È ignorato da git.
- Prima di ogni comando flutter in PowerShell si ricarica il PATH:
  ```powershell
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  ```
- **Build Windows:** `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- **Build web:** `flutter build web --release --wasm --base-href /wonderflix/ --pwa-strategy=none --dart-define-from-file=config/wonderflix.json`.
- **Verifica di ogni task:** `flutter analyze` pulito, `flutter test` tutto verde, e la build web che compila. Dal Task 1 in poi la build web non deve mai rompersi.
- **Processi:** mai `taskkill /IM`, solo per PID.
- **Commit:**
  - solo a nome dell'utente, quello già configurato in git;
  - senza `Co-Authored-By` e senza "Generated with Claude Code";
  - nei messaggi niente parole closes/fixes;
  - niente push, niente merge.
- **Scrittura:** identificatori in inglese, commenti e testi dell'interfaccia in italiano, come nel codice intorno. Testi nuovi dell'interfaccia in `l10n/` (it + en), seguiti da `flutter gen-l10n`.
- **Windows non cambia comportamento.** Il profilo `buildDeviceProfile`, l'URL del direct play senza token, mpv, l'aggiornamento e l'installer restano come sono. Ogni scelta web è dietro `kIsWeb` o dietro un file di piattaforma.
- **Token nell'URL:** solo con il nome `ApiKey`, solo nel browser, solo per video, sottotitoli, mosaici trickplay e WebSocket.
- **Video convertito nel browser:** al massimo 1080p e 20 Mbit/s. Il video copiato non ha tetti.
- **Sottotitoli nel browser:**
  - consegna `External` per srt, subrip, vtt, webvtt, ass, ssa, pgssub e dvdsub;
  - `Encode` per tutti gli altri formati.
- **Librerie JS:** copiate in `app/web/vendor/<nome>-<versione>/` con la licenza, mai da CDN.
- **Server:** il lavoro con `ssh ultra` è autorizzato. Non va toccato niente che non sia nominato nel Task 9.

## Cose da controllare in revisione

Sono input o situazioni che la spec implica ma che nessun test di un task copre da solo. Ognuna ha il suo test nel task indicato.

1. **Traccia audio non predefinita in direct play nel browser.** Sceglierla deve riaprire il video con quella traccia (nuovo `prepare`), non fare niente in silenzio. Task 6.
2. **URL di transcodifica che contiene già `ApiKey`.** Non si duplica e non si sostituisce con un altro token. Task 4.
3. **HEVC 4K su un browser che lo legge.** Resta copiato a 4K, cioè il tetto di 1080p non scatta. Task 5.
4. **Sottotitolo con un'estensione che nessun motore conosce.** `addSubtitle` restituisce `null` e resta il sottotitolo di prima, senza eccezioni. Task 8.
5. **Socket in un browser dopo il cambio di profilo.** Il WebSocket nuovo usa il token e il DeviceId del profilo attivo, non quelli del primo. Task 3.

---

### Task 1: Scheletro web e file di piattaforma (la build web compila e arriva al login)

Una prova di compilazione ha mostrato che senza modifiche la build web si ferma su quattro sorgenti native:
- `lib/core/discord/windows_discord_pipe.dart` (package:ffi);
- `lib/core/system/windows_animation_pref.dart` (ffi);
- `lib/core/video/media_kit_engine.dart` (`NativePlayer`);
- `lib/core/media_session/smtc_media_session.dart` (smtc_windows).

`dart:io` e `dart:isolate` invece compilano, ma lanciano eccezioni a runtime.

**Attenzione a `flutter create --platforms=web .`.** Tocca anche file che non c'entrano: `analysis_options.yaml`, `pubspec.lock`, i registranti in `windows/flutter/` e `.metadata`, da cui toglie la voce `windows`. Aggiunge inoltre `README.md` e `test/widget_test.dart`.
- Dopo il comando si tiene solo la cartella `web/`.
- In `.metadata` si aggiunge la voce `web` senza togliere quella `windows`.
- Si tiene anche la riga `web/**` nelle esclusioni di `analysis_options.yaml`.
- Tutto il resto si riporta com'era con `git checkout` e si cancellano i due file nuovi.

**File:**
- Crea `app/web/` (`index.html` con `<title>WonderFlix</title>` e lingua `it`, `manifest.json` con nome WonderFlix e colori del tema, icone tratte dall'icona dell'app in `windows/runner/resources/`).
- Crea `lib/core/platform/platform_info.dart`, `platform_info_io.dart`, `platform_info_web.dart`.
- Crea `lib/core/platform/browser_name.dart` e il suo test `test/core/platform/browser_name_test.dart`.
- Crea `lib/app/platform_startup.dart`, `platform_startup_io.dart`, `platform_startup_web.dart`.
- Crea `lib/core/system/animation_preference.dart`, con l'interfaccia `AnimationPreference` spostata da `windows_animation_pref.dart`.
- Crea i file di piattaforma per i default:
  - `lib/core/system/default_animation_preference{,_io,_web}.dart`;
  - `lib/core/discord/default_discord_pipe{,_io,_web}.dart`;
  - `lib/core/video/default_video_engine{,_io,_web}.dart`;
  - `lib/features/player/default_player_window{,_io,_web}.dart`.
- Modifica:
  - `lib/main.dart`;
  - `lib/app/app.dart`;
  - `lib/core/device/device_identity.dart` (`:26`);
  - `lib/core/device/dev_profile.dart` (`:10`);
  - `lib/features/settings/appearance_settings.dart` (`:5,42-43`);
  - `lib/features/discord/discord_providers.dart` (`:9,33`);
  - `lib/features/player/player_providers.dart` (`:11,35-42`);
  - `lib/features/settings/diagnostics.dart` (`:162`);
  - le impostazioni che mostrano Discord, la decodifica hardware e "Apri cartella dei log" (`support_section.dart:57` e simili).

**Interfacce:**
- `platform_info.dart` esporta:
  - `String hostName()`: su io `Platform.localHostname`; sul web `describeBrowser(userAgent)`.
  - `Map<String, String> environment()`: su io `Platform.environment`; sul web `{}`.
  - `String systemDescription()`: su io `Platform.operatingSystemVersion`; sul web lo user agent.
- `String describeBrowser(String userAgent)`, in `browser_name.dart`, restituisce `'Edge'`, `'Chrome'`, `'Firefox'`, `'Safari'` o `'Browser'`.
- `platform_startup.dart` esporta:
  - `Future<bool> initPlatform(SharedPreferences prefs)`.
    - Su io: `MediaKit.ensureInitialized()`, `setupWindow(prefs)` e SMTC, come oggi; restituisce `smtcReady`.
    - Sul web restituisce `false`.
  - `List<Override> platformOverrides({required bool smtcReady})`.
    - Su io: l'override SMTC (se pronto) e `discordSessionProvider.overrideWith(createDiscordPresence)`.
    - Sul web: `[]`.
  - `RotatingFileSink? createLogSink()`: su io `RotatingFileSink(logsDirectory())`; sul web `null`.
  - `Future<void> showWindowAfterStartupError()`: su io `windowManager.show()`; sul web non fa niente.
  - `VoidCallback watchWindowFocus(VoidCallback onFocus)`: aggiunge l'ascoltatore e restituisce la funzione che lo toglie. Su io è il `WindowListener` di oggi; sul web un callback vuoto.
- Default:
  - `AnimationPreference createAnimationPreference()`: su io `WindowsAnimationPreference()`; sul web legge `PlatformDispatcher.instance.accessibilityFeatures.disableAnimations` (`animationsEnabled()` restituisce il contrario).
  - `DiscordPipe createDiscordPipe()`: su io `WindowsDiscordPipe()`; sul web lancia `UnsupportedError`. Nel browser non si usa mai, perché manca l'override.
  - `VideoEngine createVideoEngine({required bool hardwareDecoding})`.
    - Su io: `MediaKitEngine(hwdec: hardwareDecoding ? 'auto-safe' : 'no')`.
    - Sul web, in questo task, un motore provvisorio il cui `open` lancia `EngineOpenException('player web non ancora pronto')`. Nel Task 7 diventa `WebVideoEngine`.
  - `PlayerWindow createPlayerWindow()`: su io `WindowManagerPlayerWindow()`; sul web, in questo task, una classe che non fa niente e restituisce `isFullScreen` `false`.
- I provider esistenti mantengono nome e tipo. Cambia solo il default, che chiama la funzione di piattaforma.
- In `app.dart`, sul web (`kIsWeb`) `UpdateGate` non c'è: `builder` restituisce `child` dentro `WfMotionScope`.

- [ ] **Step 1: test di `describeBrowser`** in `test/core/platform/browser_name_test.dart`, con gli user agent reali:

  | Browser | User agent | Atteso |
  |---|---|---|
  | Edge | `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0` | `'Edge'` |
  | Chrome | lo stesso senza ` Edg/…` | `'Chrome'` |
  | Firefox | `Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0` | `'Firefox'` |
  | Safari | `Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15` | `'Safari'` |
  | Vuoto | `''` | `'Browser'` |

- [ ] **Step 2:** `flutter test test/core/platform/browser_name_test.dart` fallisce perché manca la funzione.
- [ ] **Step 3: scrivi `describeBrowser`** e lancia di nuovo il test, che passa.
- [ ] **Step 4: crea `web/`** con `flutter create --platforms=web .` e riporta com'erano gli altri file, come spiegato all'inizio del task.
- [ ] **Step 5: file di piattaforma.** Crea i file di piattaforma e sposta `AnimationPreference`. Aggiorna gli import di `windows_animation_pref.dart` e di `test/features/settings/appearance_settings_test.dart`. Collega `main.dart`, `app.dart` e i provider come descritto in Interfacce.
  - `main.dart` non importa più media_kit, smtc_windows, window_manager né `Platform`.
  - La riga di avvio diventa `'WonderFlix ${package.version} su ${systemDescription()}'`.
- [ ] **Step 6: diagnostica e impostazioni nel browser.**
  - `buildDiagnostics(windowsVersion: systemDescription(), …)`. Il nome del parametro può restare.
  - Sul web non si vedono "Apri cartella dei log", la sezione Discord e la voce "Decodifica hardware".
- [ ] **Step 7: verifica.**
  - `flutter analyze` e `flutter test` passano.
  - La build web finisce senza errori.
  - `flutter run -d chrome --web-port 8642 --dart-define-from-file=config/wonderflix.json` mostra la schermata di accesso, senza eccezioni nella console del browser.
  - Senza fare il login: la schermata di accesso si apre e il DeviceId resta uguale dopo un ricaricamento.
- [ ] **Step 8: verifica Windows.** `flutter build windows --release --dart-define-from-file=config/wonderflix.json` riesce.
- [ ] **Step 9: commit.** `git add` di `web/`, `lib/`, `test/`, `.metadata` e `analysis_options.yaml`, poi `git commit -m "feat(web): build web e file di piattaforma"`.

### Task 2: Avatar senza `dart:io` né isolate

`lib/features/profiles/avatar_image.dart` usa `ZLibCodec` (`:1,198`) per il controllo anti zip-bomb e `Isolate.run` (`:81,402`). Nel browser nessuno dei due funziona.

**File:**
- Modifica `lib/features/profiles/avatar_image.dart`.
- Se serve, `pubspec.yaml` con `archive`, che è già una dipendenza di `image`, come dipendenza diretta.
- I test sono quelli esistenti di `avatar_image`.

**Interfacce:**
- Le funzioni pubbliche (`prepareAvatarImageSync`, `cropAvatarImageSync` e quelle asincrone che le chiamano) mantengono firma e comportamento.
- `Isolate.run` diventa `compute`.
- L'inflate a pezzi con il contatore dei byte diventa un inflate in Dart puro, che si ferma allo stesso limite.

- [ ] **Step 1: test sul limite di oggi.** Aggiungi `test('rifiuta un PNG che si gonfia oltre il limite anche senza dart:io')`. Usa lo stesso PNG zip-bomb dei test esistenti (o costruiscilo con `package:archive`) e controlla la stessa eccezione di oggi. Se un test così c'è già, basta quello.
- [ ] **Step 2: sostituisci** `ZLibCodec` e `Isolate.run`. Il file non importa più `dart:io` né `dart:isolate`.
- [ ] **Step 3: verifica.**
  - `flutter test test/features/profiles/` passa.
  - La build web compila.
  - Nella build web, scegliere un'immagine per l'avatar mostra il ritaglio. Il caricamento vero si prova nel Task 11.
- [ ] **Step 4: commit** con `git commit -m "feat(web): avatar senza dart:io"`.

### Task 3: WebSocket di Jellyfin nel browser

**File:**
- Crea `lib/core/jellyfin/web_event_socket{,_io,_web}.dart`.
- Modifica `lib/core/jellyfin/server_events.dart` e `lib/features/library/server_events_binding.dart` (`:12`).
- Test in `test/core/jellyfin/server_events_test.dart`.
- `pubspec.yaml`: aggiunge `web` (package:web) come dipendenza diretta, se non c'è.

**Interfacce:**
- `Uri browserSocketUri(Uri socketUri, {required String token, required String deviceId})` in `server_events.dart`. Restituisce `socketUri` con le query `ApiKey` e `deviceId`.
- `EventSocketConnector defaultEventSocketConnector({required String Function() token, required String Function() deviceId})`, da `web_event_socket.dart`.
  - Su io restituisce `connectIoSocket`.
  - Sul web restituisce un connettore che ignora gli header, apre `browserSocketUri(uri, token: token(), deviceId: deviceId())` con il `WebSocket` di `package:web` e lo avvolge in un `EventSocket`. Non c'è ping di protocollo: resta il keep-alive di Jellyfin che il client manda già.
- `serverEventsClientProvider` passa `connector: defaultEventSocketConnector(token: () => http.token ?? '', deviceId: () => http.deviceId)`, con `http = ref.read(jellyfinHttpProvider)`. I valori si leggono a ogni connessione.

- [ ] **Step 1: test di `browserSocketUri`.**
  - `browserSocketUri(Uri.parse('wss://h/jellyfin/socket'), token: 'abc', deviceId: 'd1')` è uguale a `Uri.parse('wss://h/jellyfin/socket?ApiKey=abc&deviceId=d1')`.
  - Un token con `&` viene codificato.
- [ ] **Step 2: test sul cambio di profilo** (Cose da controllare 5). Crea un `ServerEventsClient` con un connettore finto costruito da `defaultEventSocketConnector`, con un fake di `token`/`deviceId` che cambia valore tra due connessioni. Controlla che la seconda connessione riceva i valori nuovi. Nella VM si prova il percorso io, che riceve gli header nuovi. Il percorso web è uguale per costruzione: leggere a ogni chiamata.
- [ ] **Step 3:** i test falliscono.
- [ ] **Step 4: scrivi il codice**, poi lancia i test, che passano.
- [ ] **Step 5: verifica.** La build web compila. Con `flutter run -d chrome`, dopo il login (fatto dall'utente, vedi Task 11), nella scheda Network il socket risulta aperto con stato 101. Se il login non c'è ancora, la prova passa al Task 11.
- [ ] **Step 6: commit** con `git commit -m "feat(web): WebSocket di Jellyfin nel browser"`.

### Task 4: Token negli URL dei media (solo nel browser)

**File:**
- Crea `lib/core/jellyfin/media_url.dart`.
- Modifica `lib/features/player/playback_service.dart` (`:52-66`, `:96-133`, `subtitleUrl`) e `lib/features/player/player_providers.dart` (`playbackServiceProvider`, `authImageProvider`).
- Test in `test/core/jellyfin/media_url_test.dart` e `test/features/player/playback_service_test.dart`.

**Interfacce:**
- `String withApiKey(String url, String token)`.
  - Aggiunge `ApiKey=<token>` alla query e lascia uguali gli altri parametri.
  - Se l'URL ha già un parametro `ApiKey`, con qualunque maiuscola (per esempio `apikey`), lo restituisce senza toccarlo. `api_key` è un altro parametro, che Jellyfin 10.11 ignora: in quel caso `ApiKey` si aggiunge.
- `PlaybackService({…, String? Function()? mediaToken})`.
  - Con `mediaToken` `null` (Windows) non cambia niente.
  - Con un valore, `prepare` applica `withApiKey` all'URL del direct play e a quello della transcodifica, e `subtitleUrl` lo applica all'URL del sottotitolo.
  - `VideoSource.headers` resta com'è.
- `playbackServiceProvider` passa `mediaToken: kIsWeb ? () => http.token : null`.
- `authImageProvider` sul web restituisce `CachedNetworkImageProvider(withApiKey(url, http.token ?? ''), cacheManager: wonderflixImageCache)`, senza header. Su Windows resta com'è.
- Il commento "il token viaggia nell'header, non nell'URL" (`playback_service.dart:52-53`) va aggiornato: nel browser va anche nell'URL.

- [ ] **Step 1: test di `withApiKey`.**
  - `withApiKey('https://h/jellyfin/Videos/1/stream?static=true', 't')` contiene `static=true` e `ApiKey=t`.
  - `withApiKey('https://h/x/master.m3u8?ApiKey=old&a=1', 'new')` è uguale all'URL di partenza (Cose da controllare 2).
  - `withApiKey('https://h/x?api_key=old', 'new')` contiene `ApiKey=new`.
- [ ] **Step 2: test del servizio.** In `playback_service_test.dart` aggiungi `prepare con mediaToken mette ApiKey negli URL` (direct play e transcodifica) e `senza mediaToken l'URL non ha token`. Il secondo è lo stesso `prepare` di oggi e controlla che nessun URL contenga `ApiKey`. Più `subtitleUrl con mediaToken`.
- [ ] **Step 3:** i test falliscono.
- [ ] **Step 4: scrivi il codice**, poi lancia i test, che passano.
- [ ] **Step 5: test del redattore.** In `test/core/logging/redact_test.dart` aggiungi un URL con `ApiKey=abc123` e controlla che diventi `ApiKey=***`. Il redattore lo fa già: il test lo fissa.
- [ ] **Step 6: commit** con `git commit -m "feat(web): token ApiKey negli URL dei media nel browser"`.

### Task 5: Profilo per il browser

**File:**
- Crea `lib/core/jellyfin/browser_profile.dart`, che è puro Dart.
- Crea `lib/core/jellyfin/browser_probe{,_io,_web}.dart`.
- Modifica `lib/core/jellyfin/playback_api.dart` (`:6-40`) e `playbackApiProvider` (`player_providers.dart:19-20`).
- Modifica `lib/features/player/playback_service.dart`, per il tetto della conversione.
- Test in `test/core/jellyfin/browser_profile_test.dart`, `test/core/jellyfin/playback_api_test.dart` e `test/features/player/playback_service_test.dart`.

**Interfacce:**
- La classe `BrowserCapabilities`, in `browser_profile.dart`, ha i campi booleani `h264`, `hevc`, `hevcMain10`, `vp9`, `av1`, `aac`, `mp3`, `opus`, `flac`, `ac3`, `eac3`, `mkv`, più `fmp4Hls`, `nativeHls` e `isFirefox`. Ha un costruttore `const` con tutti i campi e nessun default.
- `BrowserCapabilities probeBrowser()`, da `browser_probe.dart`.
  - Sul web prova `canPlayType` e `MediaSource.isTypeSupported` con le stringhe di `browserDeviceProfile.js` di jellyfin-web:
    - `video/mp4; codecs="hvc1.1.L120"` e `hev1.1.L120` per l'HEVC;
    - `hvc1.2.4.L153` per Main10;
    - `audio/mp4; codecs="ac-3"` e `ec-3` per AC3/EAC3;
    - `video/webm; codecs="vp9"` e `video/mp4; codecs="av01.0.08M.08"`;
    - `video/x-matroska` per l'MKV, che su Firefox vale sempre `false`.
  - Su io lancia `UnsupportedError`, perché non si usa.
- `Map<String, dynamic> buildBrowserDeviceProfile(BrowserCapabilities caps, {int maxBitrate = originalQualityBitrate})` produce:
  - **`Name`:** `'WonderFlix (browser)'`.
  - **`DirectPlayProfiles`:**
    - `mp4,m4v` con i codec video letti e l'audio letto;
    - `webm` con vp9/av1 e opus;
    - `mkv` solo se `caps.mkv`.
  - **`TranscodingProfiles`:** HLS, `Container: caps.fmp4Hls ? 'mp4' : 'ts'`, `Protocol: 'hls'`, `Context: 'Streaming'`.
    - `VideoCodec` vale `hevc,h264` se `caps.hevc && caps.fmp4Hls`, altrimenti `h264`.
    - `AudioCodec` è `aac`, più `ac3,eac3` se letti.
    - `MaxAudioChannels: '6'`, `MinSegments: 1`, `BreakOnNonKeyFrames: true`.
  - **`CodecProfiles`:**
    - `{'Type': 'VideoAudio', 'Conditions': [{'Condition': 'Equals', 'Property': 'IsSecondaryAudio', 'Value': 'false', 'IsRequired': false}]}`, come jellyfin-web quando il browser non cambia traccia audio da solo.
    - Un profilo `Video` per `hevc` con `VideoProfile` `main` (più `main 10` se `hevcMain10`). Senza `hevcMain10`, aggiunge la condizione `VideoBitDepth <= 8`.
  - **`SubtitleProfiles`:** `External` per srt, subrip, vtt, webvtt, ass, ssa, pgssub e dvdsub; `Encode` per dvbsub, sub, vobsub, mov_text e tutti gli altri.
  - **Bitrate:** `MaxStreamingBitrate` e `MaxStaticBitrate` valgono `maxBitrate`.
- `typedef DeviceProfileBuilder = Map<String, dynamic> Function(int maxBitrate);`
- `PlaybackApi(JellyfinHttp http, {DeviceProfileBuilder? profile})`.
  - Il default è `(b) => buildDeviceProfile(maxBitrate: b)`.
  - `playbackApiProvider` sul web passa `(b) => buildBrowserDeviceProfile(caps, maxBitrate: b)`, con `caps = probeBrowser()` letto una volta nel provider.
- **Tetto della conversione.** `String capConvertedVideo(String transcodingUrl)`, in `browser_profile.dart`.
  - Se il parametro `TranscodeReasons` dell'URL contiene un motivo che obbliga a convertire il video, imposta `MaxHeight` al minimo tra il valore attuale e `1080`, e `VideoBitrate` al minimo tra il valore attuale e `20000000`.
  - I motivi sono:
    - `VideoCodecNotSupported`, `VideoProfileNotSupported`, `VideoLevelNotSupported`;
    - `VideoBitDepthNotSupported`, `VideoRangeTypeNotSupported`, `VideoCodecTagNotSupported`;
    - `VideoResolutionNotSupported`, `VideoBitrateNotSupported`, `VideoFramerateNotSupported`;
    - `RefFramesNotSupported`, `AnamorphicVideoNotSupported`, `InterlacedVideoNotSupported`;
    - `SubtitleCodecNotSupported`.
  - Altrimenti restituisce l'URL com'è.
  - `PlaybackService({…, bool capConvertedVideo = false})`: con `true`, che si passa solo sul web, applica `capConvertedVideo` all'URL di transcodifica.
  - **Da verificare sul server vero nel Task 11:** che Jellyfin scriva davvero `TranscodeReasons` nel `TranscodingUrl` e che rispetti `MaxHeight`. Se non lo fa, si corregge qui e si annota nel piano.

- [ ] **Step 1: test del profilo** in `browser_profile_test.dart`, con quattro `BrowserCapabilities` fisse.

  | Profilo | Capacità | Controlli |
  |---|---|---|
  | `chromeHevc` | h264, hevc, hevcMain10, vp9, av1, aac, mp3, opus, flac, mkv, fmp4Hls | `VideoCodec` di transcodifica `'hevc,h264'`, `AudioCodec` `'aac'`, mkv nel direct play |
  | `chromeNoHevc` | come sopra, senza hevc e hevcMain10 | `VideoCodec` `'h264'` |
  | `edge` | come chromeHevc, più ac3 ed eac3 | `AudioCodec` `'aac,ac3,eac3'` |
  | `firefox` | `isFirefox: true`, `mkv: false` | nessun profilo `mkv` nel direct play |

  Per tutti e quattro:
  - pgssub e ass sono `External`, dvbsub è `Encode`;
  - c'è la condizione `IsSecondaryAudio`.
- [ ] **Step 2: test di `capConvertedVideo`** (Cose da controllare 3).
  - Un URL con `TranscodeReasons=AudioCodecNotSupported` e `MaxHeight` assente resta uguale: è il 4K HEVC copiato con l'audio convertito.
  - Un URL con `TranscodeReasons=VideoCodecNotSupported%2CAudioCodecNotSupported&VideoBitrate=200000000` ha poi `MaxHeight=1080` e `VideoBitrate=20000000`.
  - Un URL con `MaxHeight=720` e un motivo video tiene `720`.
- [ ] **Step 3: test di `PlaybackApi`.** In `playback_api_test.dart`, `PlaybackApi(http, profile: (b) => {'Name': 'x'})` manda `DeviceProfile` `{'Name': 'x'}`. Senza `profile` manda `buildDeviceProfile`, come oggi.
- [ ] **Step 4:** i test falliscono.
- [ ] **Step 5: scrivi il codice**, poi lancia i test, che passano.
- [ ] **Step 6: verifica.** La build web compila. In Chrome, dalla console, `probeBrowser()` risponde come ci si aspetta: si logga una volta la riga `capacità del browser: …` all'avvio del player.
- [ ] **Step 7: commit** con `git commit -m "feat(web): profilo di riproduzione per il browser"`.

### Task 6: Cambio di traccia audio senza `ff-index` e motivi della conversione nel log

**File:**
- Modifica `lib/core/video/video_engine.dart`, `lib/core/video/media_kit_engine.dart`, `test/support/playback_fakes.dart` (`FakeVideoEngine`, `:221`) e `lib/features/player/player_controller.dart` (`:367-378`, `:524-546`).
- Test in `test/features/player/player_controller_test.dart`, o nel file dei test sulle tracce, se c'è.

**Interfacce:**
- `VideoEngine.selectsEmbeddedTracks`, cioè `bool get selectsEmbeddedTracks`. Vale `true` se il motore sa scegliere le tracce interne del file (mpv), `false` per il browser.
  - `MediaKitEngine` restituisce `true`.
  - `FakeVideoEngine` lo prende dal costruttore, con default `true`.
- **`PlayerController.selectAudio`:** se `!plan.isTranscode && !_engine.selectsEmbeddedTracks`, riapre con `_start(_engine.position, forceTranscode: false, audioIndex: index, subtitleIndex: _view.subtitleIndex ?? -1)`. Il server decide se copiare o convertire grazie alla condizione `IsSecondaryAudio`.
- **`_applyTracks`:** con `selectsEmbeddedTracks` `false` non cerca tracce interne.
- **Log:** quando il piano è una transcodifica, il controller logga una volta `transcodifica: <TranscodeReasons dell'URL>` a livello `info`.

- [ ] **Step 1: test** `selectAudio in direct play con un motore senza tracce interne riapre con la traccia scelta` (Cose da controllare 1).
  - Usa `FakeVideoEngine(selectsEmbeddedTracks: false)` e un piano direct play con due tracce audio.
  - `selectAudio(2)` chiama di nuovo `PlaybackService.prepare` con `audioIndex: 2` e `forceTranscode: false`, e lo stato finale ha `audioIndex == 2`.
- [ ] **Step 2: test** `con mpv selectAudio in direct play non riapre`. È il comportamento di oggi, con un fake con `true`.
- [ ] **Step 3:** i test falliscono.
- [ ] **Step 4: scrivi il codice**, poi lancia `flutter test`, che deve essere tutto verde.
- [ ] **Step 5: commit** con `git commit -m "feat(web): cambio di audio riaprendo il video quando il motore non sceglie le tracce"`.

### Task 7: Player web (`WebVideoEngine`), schermo intero e chiusura della scheda

**File:**
- Crea `lib/core/video/web_video_engine.dart`, importato solo da `default_video_engine_web.dart`.
- Crea `app/web/vendor/hls.js-<versione>/`, con l'ultima 1.x stabile e la licenza, caricato con un tag `<script>` in `web/index.html`.
- Sostituisci il provvisorio di `default_video_engine_web.dart` e di `default_player_window_web.dart`.
- Modifica `lib/core/jellyfin/playback_api.dart` (`reportStopped`) e `lib/core/jellyfin/jellyfin_http.dart`, solo per esporre `serverUrl` e `authorizationHeader` se non sono già pubblici.

**Interfacce:**
- `WebVideoEngine implements VideoEngine`, con `selectsEmbeddedTracks` `false`.
- **Vista:** `buildView()` restituisce un `HtmlElementView` con un `<div>` che contiene `<video>` (`playsinline`, `object-fit: contain`, nero) e, sopra, lo spazio per i canvas dei sottotitoli del Task 8. Un solo platform view per motore.
- **`open(source)`:**
  - imposta la sorgente: hls.js se l'URL contiene `.m3u8` e il browser non ha HLS nativo, altrimenti `src`;
  - con hls.js, `xhrSetup` aggiunge l'header `Authorization` da `source.headers`, così i segmenti hanno il token anche se la playlist non lo ricopia;
  - porta la posizione a `source.start` prima di `loadedmetadata` o subito dopo;
  - si completa quando arriva `loadedmetadata` con una durata finita.
  - Lancia `EngineOpenException` se arriva prima `error` (di `<video>` o un errore fatale di hls.js) oppure se dopo 60 s non è arrivato niente. In quel caso libera la sorgente.
- **Comandi:**
  - `play()` e `pause()` chiamano gli stessi metodi del video. Se il browser rifiuta `play()` perché manca un gesto dell'utente, si logga e si emette `playing` `false`.
  - `seek` imposta `currentTime`.
  - `setVolume(v)` imposta `volume = v / 100`.
  - `setRate(r)` imposta `playbackRate` e `preservesPitch = true`.
- **Stato:**
  - `position` è `currentTime` letto al momento.
  - `duration`, e `buffer` dalla fine dell'intervallo di `buffered` che contiene `currentTime`.
- **Stream** (broadcast):
  - `positionStream` da `timeupdate`;
  - `durationStream` da `durationchange`;
  - `bufferStream` da `progress`;
  - `playingStream` da `play`/`pause`;
  - `bufferingStream`: `true` su `waiting` e `seeking`, `false` su `playing`, `canplay` e `seeked`;
  - `completedStream` da `ended`;
  - `errorStream` da `error` e dagli errori di hls.js.
- **Altro:**
  - `firstFrame` si completa al primo `loadeddata`, una volta per motore.
  - `tracks()` restituisce `[]`. `selectAudio` non fa niente.
  - `dispose()` toglie gli ascoltatori, distrugge hls.js e svuota `src`.
  - Sottotitoli: in questo task `addSubtitle` restituisce `null` e `setSubtitleDelay`/`setSubtitleScale` non fanno niente. Il Task 8 li completa.
- **`WebPlayerWindow implements PlayerWindow`:**
  - `setFullScreen` usa `document.documentElement.requestFullscreen()` ed `exitFullscreen()`;
  - `isFullScreen` vale `document.fullscreenElement != null`;
  - `setPreventClose`, `hide` e `destroy` non fanno niente;
  - `addCloseListener` collega l'ascoltatore all'evento `pagehide` di `window`, e `removeCloseListener` lo toglie.
- **Stop alla chiusura:** sul web `PlaybackApi.reportStopped` manda il POST con `fetch` e `keepalive: true`, con lo stesso corpo e gli stessi header, così la richiesta sopravvive alla chiusura della scheda. Su Windows resta Dio. Si implementa con un file di piattaforma `lib/core/jellyfin/keepalive_post{,_io,_web}.dart`: `Future<void> keepalivePost(Uri url, Map<String, String> headers, String jsonBody)`, che su io lancia `UnsupportedError`.

- [ ] **Step 1:** copia hls.js in `web/vendor/` e aggiungi il `<script>` a `web/index.html`.
- [ ] **Step 2: scrivi** `WebVideoEngine`, `WebPlayerWindow` e `keepalivePost`. Collegali nei file `_web` e in `PlaybackApi.reportStopped` dietro `kIsWeb`.
- [ ] **Step 3: verifica automatica.** `flutter analyze` pulito, `flutter test` verde, la build web compila.
- [ ] **Step 4: verifica manuale in Chrome.** Usa il browser integrato con `flutter run -d chrome --web-port 8642`, oppure la build servita in locale. Il login lo fa l'utente (vedi Task 11): se non c'è ancora, questi controlli passano al Task 11.
  - Un titolo H.264/AAC parte in direct play.
  - Un titolo HEVC con EAC3 parte in HLS e il log mostra i motivi.
  - Si possono usare pausa, salto, volume, velocità, schermo intero e la barra con l'anteprima trickplay.
  - Chiudendo la scheda durante la riproduzione, nella dashboard di Jellyfin la sessione si ferma.
- [ ] **Step 5: commit** con `git commit -m "feat(web): player web con hls.js"`.

### Task 8: Sottotitoli nel browser

**File:**
- Crea `lib/core/video/subtitle_kind.dart` e il suo test `test/core/video/subtitle_kind_test.dart`.
- Crea `lib/core/video/vtt.dart` e il suo test `test/core/video/vtt_test.dart`.
- Crea `lib/core/video/web_subtitles.dart`, usato da `WebVideoEngine`.
- Crea `app/web/vendor/libass-wasm-<versione>/` (`@jellyfin/libass-wasm`, file di distribuzione: js, worker e wasm) e `app/web/vendor/libbitsub-<versione>/`, con le licenze.
- Modifica `lib/core/video/web_video_engine.dart`.

**Interfacce:**
- `enum SubtitleKind { text, ass, pgs, vobsub }`.
- `SubtitleKind? subtitleKindForUrl(String url)`: dipende dall'estensione dell'ultimo segmento del percorso (`Stream.<ext>`), senza la query.

  | Estensione | Tipo |
  |---|---|
  | `vtt`, `webvtt`, `srt`, `subrip` | `text` |
  | `ass`, `ssa` | `ass` |
  | `sup`, `pgs`, `pgssub` | `pgs` |
  | `sub`, `idx`, `mks`, `dvdsub` | `vobsub` |
  | qualunque altra | `null` |

  Il builder controlla nel Task 11 quali estensioni usa davvero Jellyfin nei `DeliveryUrl`, e completa la tabella se serve.
- `class VttCue { final Duration start, end; final String text; }`.
- `List<VttCue> parseVtt(String source)`:
  - legge WebVTT e SRT (virgola o punto nei millisecondi);
  - ignora `NOTE`, `STYLE` e gli identificatori;
  - toglie i tag `<…>` dal testo e tiene gli a capo.
- **`WebVideoEngine.addSubtitle(url, …)`:**
  - **`text`:** scarica con Dio (header `Authorization`), applica `parseVtt` e disegna i cue in un widget Flutter sopra il video, dentro la `Stack` di `buildView()`. La grandezza segue `setSubtitleScale`, con lo stile dei sottotitoli di oggi: bianco con contorno, in basso al centro.
  - **`ass`:** crea `SubtitlesOctopus` di libass-wasm sul `<video>`, con `subUrl` (l'URL ha già `ApiKey`) e `workerUrl` in `vendor/`.
    - Opzioni come in jellyfin-web: `renderMode: 'wasm-blend'`, `libassMemoryLimit: 40`, `prescaleFactor: 0.8`, `maxRenderHeight: 2160`, `renderAhead: 90`.
    - Font: gli allegati del file da `MediaSourceInfo.mediaAttachments`, se il modello li espone (altrimenti nessuno), più `fallbackFont` da `/FallbackFont/Fonts`, come jellyfin-web.
  - **`pgs`/`vobsub`:** `libbitsub.PgsRenderer` o `VobSubRenderer` sul `<video>`, con `subUrl`, `streamingLoad: true` e `rangeRequests: true`.
  - **`null`:** restituisce `null` (Cose da controllare 4).
  - Restituisce un id stabile per quell'URL. `selectSubtitle(id)` mostra quello e nasconde gli altri. `selectSubtitle(null)` li nasconde tutti.
- **`setSubtitleDelay(d)`:**
  - testo: sposta i cue;
  - ASS: `timeOffset` di Octopus;
  - PGS: l'opzione equivalente di libbitsub, se c'è. Se libbitsub non ha un'opzione di ritardo, si annota nel piano e lo si dice all'utente nel Task 11.
- **`setSubtitleScale(s)`:** vale solo per i sottotitoli testuali.

- [ ] **Step 1: test di `subtitleKindForUrl`**, con questi casi:
  - `'https://h/jellyfin/Videos/1/2/Subtitles/3/0/Stream.ass?ApiKey=x'` → `ass`;
  - `…/Stream.vtt` → `text`;
  - `…/Stream.sup` → `pgs`;
  - `…/Stream.xyz` → `null`.
- [ ] **Step 2: test di `parseVtt`.**
  - Un VTT con un'intestazione, una `NOTE`, due cue (`00:00:01.000 --> 00:00:02.500`) e un tag `<i>`: due cue con i tempi esatti e senza il tag.
  - Un SRT con `00:01:02,003 --> 00:01:04,000`: `start == Duration(minutes: 1, seconds: 2, milliseconds: 3)`.
- [ ] **Step 3:** i test falliscono.
- [ ] **Step 4: scrivi** le due funzioni, poi lancia i test, che passano.
- [ ] **Step 5:** copia libass-wasm e libbitsub in `web/vendor/`. Scrivi `web_subtitles.dart` e collegalo a `WebVideoEngine`.
- [ ] **Step 6: verifica.** `flutter analyze` e `flutter test` passano e la build web compila. A mano, nel Task 11: un SRT, un ASS con font propri e un PGS si vedono, cambiano e seguono il ritardo.
- [ ] **Step 7: commit** con `git commit -m "feat(web): sottotitoli testuali, ASS e PGS nel browser"`.

### Task 9: Server — pulizia, nginx, Jellyfin e chiave di deploy

Tutti i comandi passano da `ssh ultra`. Non ci sono file della repo, salvo la conf di nginx salvata in `app/web/deploy/wonderflix.conf` come riferimento per `RELEASING.md`.

**Procedura:**
1. **Vecchia app Next.js.**
   - Lancia `systemctl --user disable --now wonderflix.service`, cancella `~/.config/systemd/user/wonderflix.service` e lancia `systemctl --user daemon-reload`.
   - Togli dal crontab solo la riga `20 4 * * * bash -l /home/hashvps/wonderflix/backup-db.sh …`. Prima e dopo mostra `crontab -l`.
   - Cancella `~/wonderflix` e il vecchio `~/.apps/nginx/proxy.d/wonderflix.conf`.
2. **Cartella del sito.** Crea `~/wonderflix-web/`.
3. **Nuova conf** in `~/.apps/nginx/proxy.d/wonderflix.conf`:
   ```nginx
   location = /wonderflix { return 301 /wonderflix/; }
   location /wonderflix/ {
       alias /home/hashvps/wonderflix-web/;
       index index.html;
       access_log off;   # niente ApiKey nei log; il sito è statico
       location ~* \.wasm$ { default_type application/wasm; add_header Cache-Control "no-cache"; }
       location ~* (index\.html|flutter_bootstrap\.js|main\.dart\.(js|mjs|wasm))$ { add_header Cache-Control "no-cache"; }
   }
   ```
   La forma esatta la sceglie il builder, purché valgano le regole della spec §4.7.
   - Lancia `app-nginx restart`.
   - Controlla che `curl -sI https://hashvps.proton.usbx.me/jellyfin/web/` risponda ancora 200 o 302.
   - Controlla che `/wonderflix/` risponda 403 o 404, perché la cartella è vuota.
4. **Log di nginx per `/jellyfin/`.** Controlla se il log registra la query string (`grep ApiKey ~/.apps/nginx/logs/*` dopo una prova). `proxy.d/jellyfin.conf` è gestito da ultra.cc: se nginx registra la query string, non modificarlo. Annota nel piano e dillo all'utente nel Task 11.
5. **Jellyfin.** In `~/.apps/jellyfin/encoding.xml` metti a `true`:
   - `EnableThrottling`;
   - `EnableSegmentDeletion`;
   - `EnableTonemapping`.

   Si modifica il file e poi si riavvia Jellyfin con il comando di ultra.cc: il builder controlla il nome esatto, per esempio `app-jellyfin restart`. Non si creano chiavi API e non si usano password.

   Prima del riavvio si controlla che nessuno stia guardando. Per esempio, nel log di Jellyfin degli ultimi minuti non ci devono essere processi ffmpeg attivi né sessioni in riproduzione. Se qualcuno sta guardando, si chiede all'utente quando riavviare.
6. **Chiave di deploy.**
   - Genera sul PC una chiave `ssh-keygen -t ed25519 -N "" -C wonderflix-deploy -f <scratchpad>/wonderflix_deploy`.
   - Aggiungi a `~/.ssh/authorized_keys` del server la riga `restrict,command="rrsync /home/hashvps/wonderflix-web" ssh-ed25519 … wonderflix-deploy`. Controlla prima dove si trova `rrsync`: se non è nel PATH, usa il percorso completo, oppure lo script in `/usr/share/doc/rsync/scripts/`.
   - Prova dal PC: `rsync -az -e "ssh -i <chiave> -o IdentitiesOnly=yes" <cartella di prova>/ hashvps@46.232.210.229:` deve copiare in `~/wonderflix-web/`. Un `ssh -i <chiave> hashvps@46.232.210.229 ls` deve essere rifiutato.
   - `ssh-keyscan 46.232.210.229`: confronta l'impronta con quella in `~/.ssh/known_hosts` del PC.
7. **Prima pubblicazione a mano.**
   - Lancia la build web dalla cima di questo branch.
   - Copiala con `rsync` in due passate: prima `--exclude index.html`, poi `index.html`.
   - Apri `https://hashvps.proton.usbx.me/wonderflix/` nel browser integrato: arriva la schermata di accesso. Nella scheda Network i `.wasm` hanno `Content-Type: application/wasm`.
8. **Cache dopo una nuova copia.** Ripubblica con una modifica visibile, per esempio una riga di log con l'ora della build. Ricaricando la pagina normalmente deve arrivare la versione nuova.

- [ ] **Step 1:** esegui i punti 1–5 e mostra i comandi e il loro risultato nel report.
- [ ] **Step 2:** esegui il punto 6. La chiave privata e la riga di `known_hosts` restano nello scratchpad, senza committarle.
- [ ] **Step 3:** esegui i punti 7–8.
- [ ] **Step 4: commit** di `app/web/deploy/wonderflix.conf` con `git commit -m "docs(web): conf nginx del sito"`.

### Task 10: CI, release, documenti e versione 0.21.0

**File:**
- Modifica `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `docs/RELEASING.md`, `app/pubspec.yaml` (`version: 0.21.0`), `docs/IDEE.md` (idea 1b tra le fatte, come per l'1a) e la spec (`Stato: realizzata…`, a fine progetto).

**Interfacce:**
- **`ci.yml`:** dopo `flutter build windows --debug`, aggiunge `flutter build web --wasm --base-href /wonderflix/ --pwa-strategy=none`. Senza config, come la build Windows della CI.
- **`release.yml`:** un job `web` su `ubuntu-latest`, con `defaults.run.working-directory: app` e in parallelo al job Windows.
  - Passi: checkout, flutter 3.47.5, lo stesso controllo del tag e lo stesso `config/wonderflix.json` dai Secrets (riscritto in bash), `flutter pub get`, `flutter gen-l10n`, la build web dei Vincoli globali.
  - Poi la chiave da `secrets.WONDERFLIX_DEPLOY_SSH_KEY` in `~/.ssh/id_deploy` (permessi 600) e `secrets.WONDERFLIX_DEPLOY_KNOWN_HOSTS` in `~/.ssh/known_hosts`.
  - Infine `rsync -az --delete --exclude index.html -e "ssh -i ~/.ssh/id_deploy" build/web/ hashvps@46.232.210.229:` e poi `rsync -az … build/web/index.html hashvps@46.232.210.229:`.
  - Nessuna azione di terze parti per SSH.
  - Il job Windows non cambia.
- **`docs/RELEASING.md`:** una sezione "Sito web", con:
  - cosa succede al tag;
  - i due Secrets nuovi e come si rigenera la chiave, cioè il Task 9 punto 6;
  - come rimettere una versione vecchia (rilanciare il job `web` del tag precedente);
  - la conf di nginx in `app/web/deploy/`.

- [ ] **Step 1:** scrivi le modifiche ai workflow e ai documenti, e porta la versione a 0.21.0.
- [ ] **Step 2: verifica.**
  - `actionlint`, se disponibile, altrimenti una lettura attenta del YAML.
  - `flutter analyze` e `flutter test` passano.
  - `flutter build web` funziona senza config, come nella CI.
- [ ] **Step 3: Secrets.** Chiedi all'utente se aggiunge lui i Secrets o se li aggiunge Claude con `gh secret set WONDERFLIX_DEPLOY_SSH_KEY < <file>` e `gh secret set WONDERFLIX_DEPLOY_KNOWN_HOSTS < <file>`. Claude lo fa solo dopo un sì esplicito.
- [ ] **Step 4: commit** con `git commit -m "ci: build e pubblicazione del sito web"`.

### Task 11: Prova completa con l'utente e correzioni

Questo task lo esegue la sessione principale, non un subagente, perché serve l'utente.

1. **Pubblicazione.** Pubblica sul server la build web della cima del branch (Task 9 punto 7).
2. **Primo momento con l'utente.** Chiedi all'utente di fare il login nel browser integrato su `https://hashvps.proton.usbx.me/wonderflix/`. Il login resta salvato.
3. **Prove nel browser integrato**, che è Chromium:
   - home, schede e ricerca;
   - un titolo H.264 in direct play;
   - un HEVC 10 bit con EAC3: copiato o convertito, con il motivo nel log e la risoluzione;
   - un 4K HDR, che se convertito arriva a ≤1080p e non è slavato;
   - il cambio di audio;
   - SRT, ASS e PGS;
   - il ritardo dei sottotitoli;
   - la chiusura della scheda;
   - una richiesta da admin;
   - il calendario;
   - il ritaglio dell'avatar, senza salvarlo se non lo chiede l'utente;
   - un ricaricamento della pagina sul player.
4. **Secondo momento con l'utente.** Chiedi all'utente di fare il login nella build Windows di prova (`flutter build windows --release …` di questo branch). Poi fai un watch party tra Windows e il browser.
   - Controlla che il browser segua pausa, salto e velocità.
   - Controlla che nel log del `DriftCorrector` lo scarto converga sotto i 150 ms in direct play e in HLS.
5. **Correzioni.** Per ogni problema: test (quando si può), correzione e commit. Annota nel piano le scoperte: le estensioni dei sottotitoli, `ApiKey` nelle playlist, `MaxHeight`, il ritardo dei PGS, i log di nginx.
6. **Revisione finale** di tutto il branch.
7. **Prova dell'utente.** Passa all'utente con un riepilogo: URL, cosa provare (anche da Firefox ed Edge, se li ha) e l'installer Windows della build di questo branch.
8. **Dopo il suo ok.**
   - merge su `main` e push;
   - tag `v0.21.0`;
   - controlla che il job `web` pubblichi;
   - scrivi le note nella bozza della release (memoria `release-notes`).

   Ognuno di questi passi si fa solo dopo un ok esplicito dell'utente.
