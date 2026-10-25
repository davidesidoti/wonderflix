# WonderFlix — Progetto 1b: WonderFlix nel browser del PC

- **Data:** 2026-10-22
- **Stato:** approvata il 2026-10-22; **realizzata** il 2026-10-25 con il piano 27 (`docs/superpowers/plans/2026-10-22-wonderflix-27-web-pc.md`), provata dall'utente, sito pubblicato su `https://hashvps.proton.usbx.me/wonderflix/`.
- **Ambito:** progetto 1b dell'idea 1 di `docs/IDEE.md` ("Versione web"). Viene dopo il progetto 1a (repo per componente, su `main`) e prima del progetto 1c (telefono e touch).
- **Ricerche:** le fonti di questa spec sono in due note di sessione, l'inventario del codice e la ricerca sul video nel browser. Le cose che servono sono riportate qui sotto.

I percorsi `lib/…`, `test/…`, `web/…` sono dentro `app/`.

## 1. Perché e per chi

L'utente vuole usare WonderFlix fuori casa senza installare niente, per esempio dal PC di un parente. Le due cose che deve poter fare sono:
- guardare un film o una puntata;
- gestire le richieste degli utenti, cioè le azioni da admin.

Lo usano tutti gli utenti del server, ognuno con il suo account Jellyfin, non solo l'admin.

Il sito è la stessa app Flutter compilata per il web, servita da `https://hashvps.proton.usbx.me/wonderflix/`. È la stessa origine di Jellyfin (`/jellyfin/`), quindi non c'è CORS.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Tutta l'app funziona dal browser del PC: login, profili, home, ricerca, schede, player, watch party, richieste, calendario, voti, amici, segnalazioni e strumenti admin.
- Il login resta salvato nel browser, con i profili come sull'app Windows (decisione dell'utente).
- Il video si comporta come in jellyfin-web (decisione dell'utente): l'app chiede al browser cosa sa leggere e il server converte solo quello che manca.
  - Se il browser non legge l'HEVC, il server converte il video in ogni caso.
  - Non c'è nessun limite al numero di conversioni contemporanee.
  - Il video convertito arriva al massimo a 1080p, con i colori dei titoli HDR corretti dal tone-mapping del server (decisione dell'utente). Il video solo copiato resta alla qualità originale.
- I sottotitoli ASS e PGS li disegna il browser. Il video si converte per i sottotitoli solo quando non c'è altro modo (decisione dell'utente).
- Un watch party può mischiare chi guarda dall'app Windows e chi guarda dal browser, e tutti restano allineati (decisione dell'utente).
- A ogni release, cioè a ogni tag `vX.Y.Z`, il sito si aggiorna da solo.
- L'installer e l'app Windows restano come sono.

**Non obiettivi**
- Telefono, schermi stretti e touch: sono il progetto 1c. Il sito si usa con mouse e tastiera su una finestra larga almeno quanto la minima dell'app (1024×640). Sotto quella misura può essere scomodo.
- Safari: se capita si prova, ma non è garantito. I browser garantiti sono Chrome, Edge e Firefox recenti su Windows.
- Le parti solo Windows non hanno un sostituto nel browser (§5): non ci sono Discord Rich Presence, controlli multimediali del sistema né aggiornamento automatico. Anche i tasti multimediali della tastiera nel browser non sono previsti (scelta di Claude).
- Un tetto alle conversioni contemporanee (scelta dell'utente).
- Nessuna modifica al plugin, salvo che lo richieda un problema trovato durante il lavoro.

**Anti-obiettivi** (sarebbe un fallimento anche se "funziona")
- L'app Windows cambia comportamento: player, sottotitoli, profilo inviato a Jellyfin, token solo nell'header, aggiornamento o installer.
- Nel browser il server converte il video quando basterebbe copiarlo, per esempio perché il profilo non dichiara l'HEVC che il browser legge, o perché brucia un PGS che si poteva disegnare.
- Il token finisce in chiaro nei log dell'app o in quelli di nginx.
- Dopo una release il browser continua a usare la versione vecchia del sito finché qualcuno non svuota la cache.

## 3. Vincoli

- Flutter 3.47.5, Jellyfin 10.11.9, plugin 1.13.0. L'app passa da 0.20.0 a 0.21.0 con questo progetto.
- Il server è un EPYC condiviso senza accelerazione hardware (`HardwareAccelerationType: none`).
- La libreria:
  - 5.354 video, di cui 3.673 HEVC (1.920 a 10 bit, 116 in 4K);
  - audio quasi tutto EAC3/AC3;
  - circa 1.000 tracce PGS/DVD, più ASS e SRT.
- Supporto dei browser su Windows:

  | Browser | HEVC | AC3/EAC3 |
  |---|---|---|
  | Chrome | Solo con una GPU adatta, senza estensioni | No |
  | Edge | Solo con le HEVC Video Extensions | Sì |
  | Firefox | Solo con GPU ed estensione; spesso non funziona | No |

- ultra.cc:
  - Il nginx utente è in `~/.apps/nginx/`, con un file per app in `proxy.d/`, e si riavvia con `app-nginx restart`.
  - `conf/mime.types` non ha `wasm`.
  - Il sito può stare solo in un percorso, non in un sottodominio.
  - `rsync` c'è.
  - Il ToS ammette l'uso privato con login.
- Jellyfin 10.11 accetta il token nell'URL solo come `ApiKey`. `api_key` vale solo con l'autorizzazione legacy, che in 10.12 è spenta.
- Regole del progetto:
  - ogni build Windows è `flutter build windows --release --dart-define-from-file=config/wonderflix.json`, lanciata da `app/`;
  - i commit sono solo a nome dell'utente;
  - merge su `main` e push solo dopo il suo ok.

## 4. Come funziona nel browser (deciso)

Le scelte tecniche le ha lasciate tutte a Claude, che le ha spiegate all'utente prima della spec. Dove una scelta è solo di Claude e non è stata spiegata, è segnata come "scelta di Claude".

### 4.1 Separare il codice per piattaforma

- Il codice solo Windows passa dietro import condizionali: `dart:ffi`, `dart:isolate`, `smtc_windows`, `window_manager`, `screen_retriever` e media_kit. Così la build web compila senza quel codice, e su Windows tutto resta com'è.
- Dove c'è già un'interfaccia si aggiunge un'implementazione web o si usa quella che non fa niente: `VideoEngine`, `PlayerWindow`, `MediaSession`, `DiscordPipe`, `AnimationPreference` ed `EventSocketConnector`.
- Le chiamate a `Platform.*` che bloccano l'avvio hanno un ripiego quando gira nel browser (`kIsWeb`):
  - in `main.dart`, il nome del dispositivo, il profilo di sviluppo e la versione del sistema;
  - il log su file.
- Nel browser i log restano solo in memoria.
- Su Windows resta mpv. La build Windows e i suoi test non cambiano comportamento.

### 4.2 Player web

È un `VideoEngine` nuovo, che usa l'elemento `<video>` del browser dentro un `HtmlElementView`, con hls.js per l'HLS. Non si usa media_kit nel browser: non sa cambiare la traccia audio e porta con sé un hls.js vecchio.

- Tutto il codice JS passa da `package:web` e `dart:js_interop`, così la build funziona anche in wasm.
- hls.js (1.6 o successivo), libass-wasm e libbitsub sono copiati dentro `web/` con la versione fissata. Il sito non carica niente da CDN esterni (scelta di Claude).
- La vista è un solo platform view: un contenitore con il `<video>` e sopra i canvas dei sottotitoli. I controlli Flutter stanno sopra.
- `position` legge `currentTime` quando serve, senza aspettare `timeupdate`. `setRate` usa `playbackRate`, che di serie conserva l'intonazione.
- Il buffering viene dagli eventi `waiting`/`playing` e la fine da `ended`.
- Gli errori del media diventano `errorStream`, e quindi lo stesso ripiego di oggi: se il direct play fallisce, si riprova con la transcodifica.
- **Tracce.** Le tracce si prendono dal `MediaSourceInfo` di Jellyfin, non da mpv, perché nel browser non c'è `ff-index`.
  - Cambiare traccia audio richiede sempre un nuovo `prepare` con `AudioStreamIndex`, dalla posizione attuale. Questo meccanismo esiste già per la transcodifica.
- **Sottotitoli.** Chiede la consegna `External` e li disegna nel browser:
  - SRT e VTT: testo, disegnato dal widget dei sottotitoli di Flutter o da `<track>`, a scelta del builder;
  - ASS e SSA: `@jellyfin/libass-wasm`, con i font del file e quelli di ripiego del server, come in jellyfin-web;
  - PGS e DVD: `libbitsub`.
  - Il ritardo dei sottotitoli vale per tutti i formati. La grandezza vale solo per i sottotitoli testuali (scelta di Claude).
  - Solo i formati che nessuno dei due motori sa disegnare, per esempio i DVB, si bruciano nel video.
- **Schermo intero.** `PlayerWindow` per il web usa la Fullscreen API del browser.
- **Chiusura della scheda.** Il segnale di stop a Jellyfin parte da `pagehide`, con una richiesta `keepalive`. Si accetta che a volte vada perso. Jellyfin chiude comunque la sessione da solo.

### 4.3 Profilo per il browser

È un secondo profilo, separato da quello di mpv. Il profilo di Windows non cambia. Si costruisce a ogni avvio della riproduzione, chiedendo al browser cosa sa leggere (`canPlayType`, `MediaSource.isTypeSupported`), e segue le regole di `browserDeviceProfile.js` di jellyfin-web.

- **Direct play.** Solo con contenitori e codec che il browser dichiara di leggere:
  - HEVC 8 e 10 bit se le prove lo dicono;
  - AC3/EAC3 se le prove lo dicono, cioè su Edge;
  - su Firefox niente MKV in direct play, come fa jellyfin-web.
- **Transcodifica.** HLS con segmenti fMP4:
  - video copiato quando il browser lo legge, HEVC compreso, altrimenti convertito in H.264;
  - il video convertito ha un tetto di 1080p (decisione dell'utente). Il tetto non deve mai far convertire un video che si poteva copiare. Per esempio, un 4K HEVC su Chrome con la GPU adatta resta 4K copiato. Il builder sceglie come applicarlo. Una possibilità è chiedere `PlaybackInfo` senza tetto e, solo se il server converte il video, richiederlo con l'altezza massima a 1080;
  - audio in AAC, oppure AC3/EAC3 copiato dove il browser li legge.
  - Su Firefox l'fMP4 è spento solo nelle versioni con il bug noto, come in jellyfin-web.
- **Sottotitoli.** `External` per srt, subrip, vtt, webvtt, ass, ssa, pgssub e dvdsub. `Encode` per tutti gli altri.
- La parte del profilo che dipende dalle prove è una funzione pura di Dart, con i risultati delle prove in ingresso. Così è testabile con `flutter test`.
- I `TranscodeReasons` restituiti dal server finiscono nel log, per capire perché un titolo viene convertito.

### 4.4 Token e login

- I profili e i token restano in `flutter_secure_storage`, che nel browser usa localStorage cifrato con WebCrypto. È lo stesso posto dove jellyfin-web tiene il token, e il login resta salvato. Il flusso di login e i profili non cambiano.
- Nel browser il token va nell'URL come `ApiKey` dovunque l'elemento non può mandare header:
  - il video, cioè il direct play e l'HLS;
  - i file dei sottotitoli;
  - le immagini delle anteprime sulla barra (trickplay);
  - il WebSocket di Jellyfin (`/socket?ApiKey=…&deviceId=…`).
- Le chiamate HTTP normali continuano a usare l'header `Authorization`.
- Su Windows resta la regola di oggi, "il token mai nell'URL".
- Il builder deve verificare se Jellyfin ricopia `ApiKey` negli URL dei segmenti delle playlist HLS. Se non lo fa, hls.js aggiunge l'header `Authorization` alle sue richieste.
- **Log.** Il redattore dei log dell'app toglie `ApiKey` dagli URL. Il `proxy.d/wonderflix.conf` non registra la query string di `/wonderflix/`. Per `/jellyfin/` il builder controlla se il log di nginx la registra e, se è possibile senza toccare la conf di Jellyfin gestita da ultra.cc, la toglie. Altrimenti lo segnala.
- **WebSocket.** Il WebSocket web passa da un nuovo `EventSocketConnector`. Il punto in cui si crea il socket, `server_events_binding.dart`, sceglie il connettore in base alla piattaforma. Gli eventi del watch party passano dallo stesso socket.

### 4.5 Watch party

- La sincronizzazione (`lib/core/syncplay/`, `GroupPlaybackDriver`, `DriftCorrector`) resta com'è e va su `VideoEngine`. Non ci sono soglie diverse per il web.
- Party misti tra app e browser: nessuna differenza nel protocollo, perché tutti parlano con Jellyfin SyncPlay e con il plugin.
- Il builder verifica con una prova reale che nel browser il `DriftCorrector` converga. Le soglie sono: zona morta 150 ms, assestamento 40 ms, velocità 0,95/1,05, salto oltre 3 s. Va provato anche in transcodifica, dove un salto può finire su un confine di segmento.
- Se in transcodifica i salti non arrivano mai entro la tolleranza e il correttore entra in un ciclo, si corregge nel driver del web, senza toccare il comportamento di Windows.

### 4.6 Cosa si spegne nel browser

| Parte | Nel browser |
|---|---|
| Discord Rich Presence | Spenta: non si aggiunge l'override |
| Controlli multimediali di Windows (SMTC) | Spenti: resta `NoopMediaSession` |
| Aggiornamento automatico | Spento. `UpdateGate`, il banner e la schermata di aggiornamento obbligatorio non ci sono: il sito è sempre all'ultima versione |
| Finestra (dimensioni salvate, chiusura controllata) | Spenta, tranne lo schermo intero (§4.2) |
| Preferenza "animazioni" di Windows | Viene da `MediaQuery.disableAnimations` |
| Log su file e "apri cartella dei log" | Log solo in memoria; il pulsante non c'è |
| Versione di Windows nella diagnostica | Al suo posto il browser (user agent) |

**Avatar.** Il controllo anti zip-bomb usa `ZLibCodec` e `Isolate.run`, che nel browser non esistono. Si passa a `compute` e a un inflate in Dart puro che funzioni su tutte e due le piattaforme. Il comportamento resta uguale.

**Navigazione.** L'app usa l'URL con il `#`, che è quello predefinito di Flutter web. Così nginx non deve rimandare ogni percorso a `index.html` (scelta di Claude). Se si ricarica la pagina su una schermata che aveva bisogno di dati passati in memoria (`state.extra`, per esempio il player), l'app torna alla home senza errori.

### 4.7 Build e pubblicazione

- **Build:**
  ```
  flutter build web --release --wasm --base-href /wonderflix/ --pwa-strategy=none --dart-define-from-file=config/wonderflix.json
  ```
  lanciata da `app/`.
  - Il wasm gira in Chrome e in Edge; Firefox ricade da solo sulla versione JS.
  - Header COOP `same-origin` e COEP `credentialless`, così il wasm usa più thread. Con un solo thread l'interfaccia scattava sul portatile dell'utente; immagini TMDB, video e worker dei sottotitoli funzionano anche così (scelta di Claude, rivista il 2026-10-23).
- **Server:**
  - I file stanno in `~/wonderflix-web/`. La cartella e il nome sono una scelta di Claude.
  - Il nuovo `~/.apps/nginx/proxy.d/wonderflix.conf` fa un `alias` su quella cartella, con `default_type application/wasm` per i `.wasm` e senza la query string nei log.
  - `Cache-Control: no-cache` su `index.html`, `flutter_bootstrap.js`, `main.dart.*` e `*.wasm`/`*.mjs`. Gli altri file si riconvalidano con l'ETag.
  - Il builder controlla che dopo una release il browser carichi davvero la versione nuova.
- **Release:**
  - `release.yml` ha un secondo job su `ubuntu-latest`. Ripete il controllo del tag, crea `config/wonderflix.json` dagli stessi Secrets, lancia analisi e build web, poi copia la build sul server con `rsync`.
  - Il job Windows e l'installer non cambiano.
  - La copia avviene in due passate, prima tutto tranne `index.html` e poi `index.html`, così chi apre il sito durante la copia non prende una versione a metà.
  - Il sito si aggiorna al push del tag, prima che l'utente pubblichi la bozza della release (scelta di Claude).
- **Chiave di deploy.**
  - È una chiave ed25519 dedicata, generata da Claude. Sul server sta in `authorized_keys`, limitata da `rrsync` alla sola `~/wonderflix-web/`.
  - La chiave privata e l'impronta del server, verificata a mano, vanno nei Secrets della repo: `WONDERFLIX_DEPLOY_SSH_KEY` e `WONDERFLIX_DEPLOY_KNOWN_HOSTS`. I dati di collegamento possono andare in un terzo Secret o direttamente nel workflow.
  - I Secrets li aggiunge l'utente, oppure Claude con `gh secret set` dopo un suo sì esplicito.
- **CI:** `ci.yml` aggiunge una build web, oltre a quella Windows, così chi rompe la compilazione per il web se ne accorge subito.
- `docs/RELEASING.md` spiega la pubblicazione del sito, i Secrets nuovi e come rimettere una versione vecchia, cioè rilanciare il job su un tag precedente.

### 4.8 Server: pulizia e impostazioni (lavoro di Claude, autorizzato)

1. **Vecchia app Next.js.** Va tolta prima di pubblicare il sito, perché occupa `/wonderflix`. L'utente ha confermato che si può cancellare.
   - Fermare e disabilitare `wonderflix.service` e cancellarne il file di unità.
   - Togliere dal crontab la riga che lancia `~/wonderflix/backup-db.sh` ogni notte alle 4:20.
   - Cancellare `~/wonderflix` (546 MB) e il vecchio `proxy.d/wonderflix.conf`.
2. **Jellyfin.** Attivare:
   - `EnableThrottling`, che rallenta ffmpeg quando il buffer è avanti;
   - `EnableSegmentDeletion`, che cancella i segmenti già visti;
   - `EnableTonemapping`, che corregge i colori degli HDR convertiti. Costa più CPU, scelta dell'utente.

   Il tone-mapping vale anche per le rare conversioni dell'app Windows. Il numero di thread per conversione e i limiti per utente restano come sono.
3. **nginx.** Mettere la nuova conf, lanciare `app-nginx restart` e controllare che `/jellyfin/` funzioni ancora.

## 5. Prove

- **Test automatici** (`flutter test`, nella VM come oggi):
  - il profilo del browser a partire dai risultati delle prove (Chrome con e senza HEVC, Edge con AC3, Firefox);
  - l'aggiunta di `ApiKey` agli URL nel browser, e la sua assenza su Windows;
  - il redattore dei log che toglie `ApiKey`;
  - la scelta dei sottotitoli da disegnare o da bruciare;
  - il cambio di traccia audio con un nuovo `prepare`.
- Il codice che parla con il browser (js_interop) non si prova nella VM. Si prova a mano.
- **Prova manuale di Claude**, prima di passare all'utente: build web servita in locale e poi sul server.
  - Claude non scrive le password del server vero. Nei due momenti in cui serve, l'utente fa il login nel browser integrato di Claude e nell'app Windows di prova (decisione dell'utente). Il login resta salvato e Claude prosegue da solo.
  - Le prove, con il browser integrato:
  - login;
  - un titolo HEVC con audio EAC3, per vedere copia o conversione e il motivo nel log;
  - cambio di audio;
  - un sottotitolo SRT, uno ASS e uno PGS;
  - una richiesta da admin;
  - un watch party tra la build Windows e il browser.
  - Il plugin riconosce i client del watch party dal nome `WonderFlix` della sessione, quindi la build web deve mandare lo stesso nome.
- **Prova dell'utente:** dal browser del suo PC su `https://hashvps.proton.usbx.me/wonderflix/`, più l'installer Windows della stessa versione.

## 6. Fatto quando

- Tutta l'app funziona dal browser del PC su `https://hashvps.proton.usbx.me/wonderflix/`, con il login di Jellyfin.
- L'installer Windows continua a funzionare com'è.
- L'utente l'ha provata e ha dato l'ok.
- La vecchia app Next.js non c'è più sul server.
- La release 0.21.0 ha pubblicato il sito da sola.

## 7. Lasciato al builder

- Come dividere i file con gli import condizionali, e i nomi delle classi nuove.
- Come caricare hls.js, libass-wasm e libbitsub, cioè con un tag `<script>` in `index.html` o caricati quando servono.
- Come disegnare i sottotitoli testuali: widget Flutter o `<track>`.
- Il nome della cartella delle build sul server e la forma esatta della conf di nginx, purché rispetti §4.7.
- L'ordine dei passi nel piano, purché la pulizia del server venga prima della prima pubblicazione.
