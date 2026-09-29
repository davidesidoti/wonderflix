# WonderFlix — passaggio di consegne verso il Piano 3 (player)

Documento per riprendere il lavoro in una nuova sessione. Tutto quello che segue è già su `main` ed è pushato su `origin`.

## Stato al 2026-09-29

| Piano | Stato | Documento |
|---|---|---|
| Spec A (client core) | approvato | `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md` |
| 1 — fondamenta e login | completato, provato sul server, su `main` | `docs/superpowers/plans/2026-09-29-wonderflix-01-fondamenta-login.md` |
| 2 — Home e catalogo | completato, provato sul server, su `main` (ultimo commit `746d7ee`) | `docs/superpowers/plans/2026-09-29-wonderflix-02-home-catalogo.md` |
| **3 — player** | **da scrivere** | — |
| 4 — aggiornamenti, installer, Discord, log | da scrivere | — |
| Spec B — watch party | dopo lo Spec A | — |

**Cosa fa oggi l'app** (verificato dall'utente sul server reale):
- login con password o Quick Connect, sessione ricordata, schermata "server irraggiungibile";
- Home (carosello + righe), catalogo Film/Serie con filtri;
- schede film/serie (stagioni, episodi, prossimo episodio, cast, simili, trailer remoto nel browser; locandina sfocata se manca lo sfondo);
- pagina attore, ricerca, La mia lista, Impostazioni (lingua);
- aggiornamenti in tempo reale via WebSocket, freccia/Esc/Alt+←/tasto mouse per tornare indietro.

**"Riproduci" oggi** chiama `playItem` (`lib/features/playback/play_launcher.dart`), che mostra solo un avviso. Il Piano 3 lo sostituisce.

176 test verdi, `flutter analyze` pulito, CI con analyze, test e build Windows (`.github/workflows/ci.yml`).

## Regole di lavoro concordate con l'utente

- **Lingua:** conversazione in italiano. Documenti in italiano, codice e identificatori in inglese, testi UI nei file ARB (it + en).
- **Commit:** con l'identità git dell'utente, **mai** `Co-Authored-By` o "Generated with…". Vale anche per i subagent.
- **Processo per ogni piano:**
  1. `superpowers:writing-plans` → piano in `docs/superpowers/plans/`, commit su `main`.
  2. Worktree dedicato in `.claude/worktrees/<nome>` su un branch `feat/<nome>` (creato con `git worktree add` partendo da `main`, poi `EnterWorktree` con `path`).
  3. `superpowers:subagent-driven-development`: un subagent per task (o per 2–3 task piccoli), controllo dei risultati, a fine piano una revisione finale del branch con un subagent reviewer e una correzione dei problemi trovati.
  4. Prova manuale insieme all'utente sul server reale (`flutter run -d windows --dart-define-from-file=config/wonderflix.json`).
  5. Solo dopo l'ok dell'utente: merge fast-forward su `main`, push, rimozione del worktree e del branch.
- **UI:** icone solo `LucideIcons`, nessuna emoji. Tema Noir & Oro (`lib/app/theme.dart`).

## Ambiente (particolarità importanti)

- **Flutter 3.47.5**, non 3.35.6 come dicono spec e Piano 1: è stato aggiornato perché la 3.35 non riconosce i Visual Studio Build Tools 2026.
- **Build Tools 2026 con il componente ATL** installato (serve a `flutter_secure_storage`).
- **`config/wonderflix.json`** esiste solo in locale (è in `.gitignore`): server `https://hashvps.proton.usbx.me/jellyfin`. Va copiato nel worktree nuovo (`cp config/wonderflix.json .claude/worktrees/<nome>/config/`).
- **File generati con modifiche false:** `flutter pub get` / `flutter test` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga. Se `git diff` non mostra cambi di contenuto: `git checkout -- windows/flutter/`, senza committarli. Se un nuovo plugin nativo cambia davvero il contenuto, vanno committati.
- **App aperta durante il riavvio:** fermare un `flutter run` in background non chiude la finestra, e una build successiva fallisce con `LNK1168` (exe bloccato). Soluzione: `taskkill //IM wonderflix.exe //F` prima di rilanciare.
- **Shell nei worktree:** i comandi git vanno eseguiti dal worktree. Non lanciare `git worktree remove` stando dentro la cartella da rimuovere.

## Lezioni dai test (da dare ai subagent del Piano 3)

- **Material mancante:** `pumpApp` (`test/support/pump_app.dart`) non mette un `Scaffold`. Widget come DropdownButton, TextField, IconButton, InkWell e SnackBar richiedono `Scaffold(body: Schermata())` nel test.
- **Liste lazy:** le schermate usano ListView/CustomScrollView lazy. Se una sezione in basso non viene costruita, alzare la superficie del test con `tester.binding.setSurfaceSize(Size(1440, 1600))`.
- **Lint `use_null_aware_elements`:** scrivere `'key': ?value` invece di `if (value != null) 'key': value`.
- **Double per `LibraryApi`:** si usa `FakeLibraryApi` (`test/support/library_fakes.dart`), non mocktail. Chi lo estende con nuovi metodi deve aggiornare il fake.
- **Microtask di Riverpod:** i provider che partono con un microtask vanno letti o ascoltati *dopo* aver configurato i fake (vedi `catalog_controller_test.dart`).
- **`fake_async` e `await`:** attendere un future del root zone dentro `fake_async` non avanza. Avviare in parallelo le operazioni da attendere (vedi `ServerEventsClient.stop`).
- **Conflitto di nomi:** `SearchController` esiste anche in material. Usare `hide SearchController` (vedi `search_screen.dart`).

## Punti rimandati al Piano 3 (dalla revisione finale del Piano 2)

1. **Nuovo punto d'ingresso della riproduzione.** `playItem(context, item)` è troppo povero. Serve un launcher con accesso a `ref` che:
   - riceva la destinazione giusta: per una serie il prossimo episodio (`seriesNextEpisodeProvider`); per il resto l'elemento con i dati utente aggiornati (`watchUserData` / `userDataOverridesProvider`), non `item.userData` che può essere vecchio;
   - sappia se riprendere o ricominciare (`PrimaryAction` in `lib/features/detail/primary_action.dart`: `ResumeAction.position`, `fromStart`);
   - restituisca un `Future`.

   I chiamanti attuali sono `hero_carousel.dart` (passa anche delle **serie**), `detail_header.dart` (Riproduci/Ricomincia) ed `EpisodeTile` in `series_detail_view.dart`.
2. **Route del player fuori dalla `ShellRoute`.** Per esempio `/play/:id` sul navigatore radice, senza barra superiore.
   - `BackNavigationHandler` (`lib/app/back_navigation.dart`) usa un handler globale di `HardwareKeyboard`. Ignora gli eventi quando la pagina della shell non è in cima (`ModalRoute.isCurrent`), quindi con il player sulla radice non interferisce.
   - Il player gestisce da sé Esc (esce dallo schermo intero, poi dal player), frecce, spazio e le altre scorciatoie della spec §7.
3. **Aggiornamento locale del minutaggio.** `UserItemData.copyWith` accetta solo `played`/`isFavorite`: va esteso con `playbackPositionTicks` e `playedPercentage`. Dopo `Sessions/Playing/Stopped` vanno aggiornati gli override e fatto `bump()` di `userDataRevisionProvider`, così Home e prossimo episodio si aggiornano subito, senza aspettare il WebSocket.
4. **Trailer locali.** Aggiungere `LibraryApi.localTrailers` (`GET /Items/{itemId}/LocalTrailers`, presente nell'OpenAPI). Il pulsante Trailer, quando `localTrailerCount > 0`, deve riprodurli nel player tramite il nuovo launcher; resta il ripiego al trailer remoto nel browser.
5. (Opzionale) Nella riga "Prossimi episodi" della Home, passare `nextUpDateCutoff` come fa jellyfin-web.

## Ricerca già fatta per il Piano 3

**Pacchetti** (versioni risolte in un progetto di prova, compatibili con Flutter 3.47.5):
- `media_kit` 1.2.6, `media_kit_video` 2.0.1, `media_kit_libs_windows_video` 1.0.11:
  - `Player` con `open(Media(...))`, `play/pause/seek/setVolume/setRate`, `setAudioTrack/setSubtitleTrack/setVideoTrack`, `stream.*` / `state.*`;
  - `NativePlayer.setProperty` per le proprietà mpv (`http-header-fields`, `sub-delay`, `hwdec`, `start`…);
  - `SubtitleTrack.uri(...)` per i sottotitoli esterni.
  - **Da verificare nella pub cache prima di scrivere il piano:** i parametri di `Media` (`httpHeaders`, `start`, `extras`) nel file `lib/src/models/media/media_native.dart`, e come leggere `track-list/N/ff-index` (`NativePlayer.getProperty`).
- `wakelock_plus` 1.8.0: blocca salvaschermo e sospensione.
- `smtc_windows` 1.1.0: pannello media di Windows. **Da verificare:** usa flutter_rust_bridge/cargokit e potrebbe richiedere Rust per compilare. Se è così, valutare di rimandarlo al Piano 4 o gestire i tasti multimediali solo con l'app in primo piano.

**Endpoint Jellyfin 10.11.9** (riferimento: `docs/reference/jellyfin-openapi-10.11.9.json`):
- **Informazioni di riproduzione:** `POST /Items/{itemId}/PlaybackInfo` con `PlaybackInfoDto`:
  - campi della richiesta: `UserId`, `MaxStreamingBitrate`, `StartTimeTicks`, `AudioStreamIndex`, `SubtitleStreamIndex`, `MediaSourceId`, `DeviceProfile`, `EnableDirectPlay`, `EnableDirectStream`, `EnableTranscoding`;
  - la risposta ha `MediaSources[]` (con `SupportsDirectPlay`, `TranscodingUrl`, `MediaStreams`, `DefaultAudioStreamIndex`, `DefaultSubtitleStreamIndex`) e `PlaySessionId`;
  - le preferenze di lingua dell'utente le applica il server tramite i default.
- **URL di riproduzione:**
  - direct play: `/Videos/{itemId}/stream?static=true&mediaSourceId=…&playSessionId=…`, con il token nell'header;
  - sottotitoli esterni: `MediaStream.DeliveryUrl` (quando `DeliveryMethod == External`).
- **Report dell'avanzamento:** `POST /Sessions/Playing`, `/Sessions/Playing/Progress`, `/Sessions/Playing/Stopped` (campi `ItemId`, `MediaSourceId`, `PlaySessionId`, `PositionTicks`, `IsPaused`, `AudioStreamIndex`, `SubtitleStreamIndex`, `PlayMethod`, `CanSeek`).
- **Intro e crediti:** `GET /MediaSegments/{itemId}` → `Items[]` con `Type` (`Intro`, `Outro`, `Recap`, `Preview`, `Commercial`, `Unknown`), `StartTicks`, `EndTicks`.
- **Anteprime trickplay:**
  - le info stanno nel campo `Trickplay` dell'elemento (per ogni media source e larghezza: `Width`, `Height`, `TileWidth`, `TileHeight`, `ThumbnailCount`, `Interval`);
  - i mosaici sono `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg` e **richiedono autenticazione**: serve l'header, per esempio con `CachedNetworkImage(httpHeaders: …)`.
- **Episodio successivo:** `GET /Shows/{seriesId}/Episodes?startItemId={id}&limit=2`, oppure `adjacentTo`.
- **Preferenze audio/sottotitoli dell'utente:** `GET /Users/Me` → `Configuration` (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`, `PlayDefaultAudioTrack`); per salvarle, `POST /Users/Configuration?userId=…`.

**Proposta di scomposizione** (da confermare con l'utente in fase di piano). La spec §7 è ampia, quindi conviene dividerla in due piani, ognuno provabile:
- **3a — riproduzione di base:**
  - `VideoEngine` sopra media_kit, PlaybackInfo e scelta tra direct play e transcodifica, report dell'avanzamento;
  - route `/play/:id`, overlay dei controlli, schermo intero, tastiera;
  - tracce audio e sottotitoli, ritardo dei sottotitoli, ripiego sulla transcodifica, errori, wakelock;
  - nuovo launcher (punti rimandati 1–3).
- **3b — funzioni extra:** MediaSegments (salta intro/crediti), trickplay, prossimo episodio, trailer locali (punto 4), capitoli, impostazioni del player (qualità, decodifica hardware, dimensione dei sottotitoli, lingue su server), SMTC se fattibile.
