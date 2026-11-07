# WonderFlix sulla TV (Fire TV e Android TV) — design

Data: 2026-11-07. Stato: da approvare dall'utente.

## Perché

Gli utenti di WonderFlix guardano già molto dalla TV, ma con l'app Jellyfin per
Android TV (o Moonfin), quindi senza le funzioni di WonderFlix. Dal plugin
Playback Reporting (7 agosto – 7 novembre 2026), le riproduzioni da TV sono:

| Piattaforma | Dispositivi | Riproduzioni |
|---|---|---|
| Fire TV (Jellyfin Android TV) | 6 stick (viviroby ×2, davide ×2, Italy86, Sara) | 349 |
| Android TV | Panasonic di sronweb (Moonfin), "TV" di Jeiden | 155 |
| LG webOS | Fano00 (Jellyfin for WebOS), sronweb (Moonfin) | 25 |

Fire TV e Android TV fanno il 94% delle visioni da TV. Un'app Android per TV
copre quasi tutti.

L'utente (Davide) vuole che sulla TV ci siano le stesse migliorie che
WonderFlix ha dato al client Jellyfin su PC e telefono: sono quelle a
convincere gli utenti a cambiare.

**Successo:** chi oggi guarda con Jellyfin su Fire TV passa a WonderFlix e non
torna indietro.
**Fallimento da evitare (anti-obiettivo):** un'app più lenta o più scomoda di
Jellyfin per Android TV, o che non riproduce file che Jellyfin legge.

## Obiettivi

- App WonderFlix per **Fire TV e Android TV**, usabile solo col telecomando.
- Sulla TV **si guarda e basta**: nessuna parte admin.
- Parità con il PC per tutto ciò che serve a scegliere e guardare (elenco sotto).
- Riproduzione affidabile della libreria reale: 4K HEVC 10 bit HDR fino a
  ~30 Mbps, anime HEVC 10 bit con sottotitoli ASS.
- Installazione a mano con Downloader e aggiornamenti dall'app, senza store.

## Non obiettivi (per ora)

- **Watch party, amici e chat**: fuori. Il player e la navigazione però non
  devono impedire di aggiungerle dopo (vedi "Porte aperte").
- **Notifiche e calendario delle uscite**: fuori.
- **Match**: fuori (si gioca in due, ha più senso sul telefono).
- **Admin, Spazio, Download, modifica metadati, Discord**: fuori.
- **Telefoni Android**: l'APK è solo per TV. Sui telefoni resta la versione web.
- **TV LG (webOS)**: fase separata, dopo (vedi "Fase LG").
- **Pubblicazione su Amazon Appstore o Google Play**: esclusa per scelta
  dell'utente.

## Cosa c'è sulla TV

Decisi con l'utente:

- **Home** con carosello e righe personalizzate, come su PC.
- **Catalogo** Film e Serie con filtri, **saghe e collezioni**.
- **Pagina del titolo** (film, serie con stagioni ed episodi) e **pagina della
  persona**.
- **Cerca** e **La mia lista**.
- **Player** con le funzioni del PC (sezione dedicata).
- **Valutazioni** (Vota) e **Consiglia a un amico**: dentro.
- **Stasera** ("Cosa guardo stasera?"): dentro.
- **Richieste**: dentro. Si richiede **dalla ricerca**: chi cerca un titolo
  che non c'è lo trova nella sezione "da richiedere" sotto i risultati (come fa
  già `search_screen.dart` con `RequestablesSection`), lo apre e preme
  "Richiedi" (per le serie sceglie le stagioni). In più c'è una scheda
  **Richieste** nella barra laterale con le proprie richieste e il loro stato.
  Le azioni da admin sulle richieste (approva/rifiuta) restano fuori.

## Navigazione e aspetto

Deciso con l'utente, dalle bozze approvate (`.superpowers/brainstorm/`, file
`tv-home-nav.html` e `tv-detail-player.html`):

- **Barra laterale a icone** a sinistra (variante B). Premendo Sinistra da
  qualsiasi punto si allarga e mostra i nomi. Voci, dall'alto: Cerca, Home,
  Film, Serie, Stasera, La mia lista, Richieste. In fondo l'**avatar** per
  cambiare account.
- **Home**: carosello in alto con "Riproduci/Riprendi", sotto le righe
  ("Continua a guardare", "Nuovi arrivi", …), come su PC.
- **Pagina di una serie**: a sinistra logo/titolo, dati, trama; il pulsante
  principale (Riproduci / Riprendi SxEy · posizione) ha il focus all'apertura.
  Accanto: La mia lista, Vota, Consiglia, Segna come visto, Altro (info
  tecniche, segnala un problema). Giù: schede delle stagioni con gli episodi in
  fila (con barra d'avanzamento), poi cast e titoli simili. Per un film, cast e
  simili al posto delle stagioni.
- **Elemento con il focus** sempre ben visibile (riquadro oro/crema e leggero
  ingrandimento), testi leggibili da tre metri. Colori, font (Bebas Neue,
  Inter) e stile sono quelli di WonderFlix (`app/lib/app/theme.dart`).
- **Tasto Indietro** coerente ovunque: chiude pannelli e menu, poi torna alla
  pagina precedente; dalla home non esce dall'app senza conferma (scelta del
  builder su come: conferma o doppio Indietro).

## Accesso e account

Deciso con l'utente: **riparte dall'ultimo account usato**; si cambia
dall'avatar in fondo alla barra laterale. Su Jellyfin ogni "profilo" è un
account vero con la sua password (non un profilo Netflix); l'app li ricorda
già sul dispositivo (`features/profiles`, `features/auth`).

Proposte mie, non obiettate:

- Indirizzo del server già nell'app (come su PC, `config/wonderflix.json`).
- Per aggiungere un account: **Quick Connect** (la TV mostra un codice, lo si
  conferma da WonderFlix sul telefono o sul PC). Nome utente e password con
  la tastiera a schermo restano come alternativa.
- **Conferma dei codici su PC e web** (deciso con l'utente): oggi l'app sa
  solo usare Quick Connect (`core/jellyfin/auth_api.dart`: `Initiate`,
  `Connect`, `Enabled`), non confermare i codici. Si aggiunge a WonderFlix su
  PC e web una schermata "Autorizza un dispositivo" per l'utente già entrato:
  scrive il codice mostrato dalla TV e lo conferma (endpoint Jellyfin
  `POST /QuickConnect/Authorize?code=…`). Dove metterla (impostazioni
  dell'account, menu dell'avatar) è scelta del builder. È l'unica aggiunta
  visibile su PC e web di questo progetto.
- Dall'avatar: passa a un altro account salvato, aggiungi account,
  **Impostazioni**, esci.
- **Impostazioni sulla TV** (decisione mia): solo quelle del player e della
  lingua che oggi stanno sul dispositivo (qualità dello streaming, lingue
  predefinite di audio e sottotitoli, stile dei sottotitoli quando arriva,
  lingua dell'app). Restano per dispositivo, come su PC. Niente impostazioni
  admin, home o notifiche.

## Il player

### Motore: ExoPlayer (Media3) con libass — deciso con l'utente

La prova sul Fire Stick dell'utente (sotto) ha escluso media_kit/mpv così
com'è. Sulla TV il video va riprodotto con il **player nativo di Android
(Media3/ExoPlayer)**, con **libass** per i sottotitoli ASS/SSA (la combinazione
usata dall'app Jellyfin per Android TV). Si aggiunge come **terzo motore**
dietro l'interfaccia esistente `VideoEngine`
(`app/lib/core/video/video_engine.dart`), accanto a `MediaKitEngine`
(Windows) e `WebVideoEngine` (web). `createVideoEngine` sceglie il motore per
piattaforma. Il resto del player (`features/player`) resta comune.

Il motore deve coprire l'interfaccia attuale: open in pausa con posizione di
partenza e header HTTP, play/pausa/seek, volume, **velocità** (serve al watch
party in futuro), tracce interne audio/sottotitoli, sottotitoli esterni,
ritardo e dimensione dei sottotitoli, stream di posizione/durata/buffer/stato,
primo fotogramma, `buildView()`.

Stile dei sottotitoli (decisione mia): la funzione "stile sottotitoli" è
ancora nel branch non unito `worktree-stile-sottotitoli` (aggiunge un metodo a
`VideoEngine` e salva lo stile in `ProfilePreferences`, cioè sul dispositivo).
Il lavoro TV parte da `main`; se quel branch viene unito prima, il motore TV
implementa anche il nuovo metodo. Lo stile resta **per dispositivo** (niente
sincronizzazione col server): sulla TV si sceglie dalle impostazioni della TV
(sotto). Per gli ASS vale lo stile del file, come su PC.

Come integrare Media3 e libass in Flutter (plugin esistente, plugin scritto
da noi con platform channel/Pigeon, quale libreria libass per Android) è
lasciato al builder. **Primo passo del piano: una prova sul Fire Stick** che
confermi i quattro casi della tabella sotto con il nuovo motore, prima di
costruire il resto. **Se anche un solo caso non passa** (per esempio gli ASS
scattano o perdono lo stile), ci si ferma e si torna dall'utente con i
risultati prima di proseguire (decisione mia). Bruciare i sottotitoli sul
server non è un'alternativa: il seedbox non ha GPU.

### Cosa deve riprodurre (casi di prova reali sul server)

| Caso | Titolo | Formato |
|---|---|---|
| 4K HDR | Il cavaliere oscuro (2008) | HEVC 10 bit, HDR10, 3840×2160, ~6.7 Mbps |
| 4K alto bitrate, formato cinema | Fondazione S3E1 "Una canzone per la fine di tutto" | HEVC 4K 3840×1600, ~25–31 Mbps |
| Anime con ASS | A Sign of Affection S1E1 "Yuki no Sekai" | HEVC 10 bit 1080p, sottotitoli ASS italiani interni |
| 1080p semplice | 2012 (2009) | H.264 8 bit 1080p |

Criterio: immagine fluida, proporzioni giuste (niente schiacciamento o bande
verdi), **colori naturali, non slavati** (la TV dell'utente non è HDR, sotto),
sottotitoli ASS italiani visibili con il loro stile, Indietro che esce dal
player senza blocchi.

### Profilo di riproduzione

L'app dice già al server cosa sa leggere (`core/jellyfin/device_profile.dart`,
`browser_profile.dart`). Serve un profilo per Android TV che rifletta ciò che
il dispositivo decodifica davvero (HEVC 10 bit, HDR, codec audio), così il
server fa Direct Play quando può e converte solo il resto. Ricavarlo dalle
capacità del dispositivo (MediaCodec) o fissarlo è scelta del builder. Durante
la prova il server ha fatto Direct Play di tutti e quattro i casi.

Proposte mie: **HDR passato alla TV solo se lo schermo lo supporta**
(`Display.getHdrCapabilities`); **audio Dolby/DTS in passthrough** verso la
soundbar quando il dispositivo lo supporta; altrimenti decodifica o
conversione lato server come oggi.

La TV dell'utente **non è HDR**: il Fire Stick riporta
`mSupportedHdrTypes=[]`, uscita 1920×1080. Su questa TV un titolo HDR10 deve
comunque avere colori naturali: nella prova con mpv in modalità diretta
"Il cavaliere oscuro" si vedeva bene, segno che il decoder del Fire Stick
converte in SDR. Se con ExoPlayer i colori risultano slavati, è un caso che non
passa. Lo schermo supporta anche 23.976/24/50 Hz: adattare la frequenza dello
schermo a quella del video è un'aggiunta gradita, non obbligatoria.

### Controlli col telecomando (bozza approvata)

- **OK**: pausa/play e mostra i controlli.
- **Sinistra/Destra**: ±10 s, con l'anteprima trickplay sulla barra.
- **Su/Giù**: mostrano i controlli; dentro ci si sposta tra barra e pulsanti
  (pausa, ±10 s, Audio e sottotitoli, Episodio successivo).
- **Indietro**: prima chiude i controlli, poi esce dal player.
- **Tasti media del telecomando** (play/pausa, avanti, indietro): fanno ciò
  che dicono.
- **Salta intro / riassunto** compare da solo come su PC e prende il focus
  finché è visibile. Post-play ed episodio successivo come su PC.

## Installazione e aggiornamenti

Deciso con l'utente: **niente store**, si installa a mano con l'app
**Downloader**.

Proposte mie:

- La pipeline dei rilasci (`.github/workflows/release.yml`) produce anche
  l'APK, con la **stessa versione** dell'app PC, e lo allega alla release
  GitHub. Il sito pubblica l'ultimo APK a un indirizzo fisso e corto
  (es. `https://<sito>/wonderflix/tv.apk`) da scrivere in Downloader (o un
  codice numerico di Downloader che punti lì).
- L'APK è firmato con una **chiave di rilascio stabile** (segreto in CI): se
  la firma cambia, Android rifiuta l'aggiornamento e bisogna disinstallare.
- **Aggiornamenti dall'app**: il controllo esistente (`features/update`, che
  legge `releases/latest` da GitHub) trova la versione nuova; sulla TV scarica
  l'APK e apre l'installer di sistema. La prima volta Android chiede il
  permesso "installa app sconosciute" per WonderFlix. L'aggiornamento
  obbligatorio (`mandatory_update_screen.dart`) vale anche qui.
- Istruzioni d'installazione per gli utenti (passi con Downloader) in
  `docs/` o sul sito; i passi di rilascio in `docs/RELEASING.md`, con le righe
  di test manuale per la TV.
- Durante lo sviluppo le build di prova si installano sul Fire Stick
  dell'utente via ADB (`192.168.1.171:5555`, debug ADB attivo).

## Porte aperte per dopo

- **Watch party**: il motore espone già velocità e seek; la barra laterale e
  il player devono poter accogliere in seguito un pulsante "Guarda insieme" e
  la chat senza essere rifatti.
- **Fase LG**: la parte di interfaccia "da TV" (focus, barra laterale,
  pagine) va scritta in Flutter comune, non legata ad Android, così da poterla
  riusare sulla versione web dentro un guscio webOS.

## Fase LG (lavoro futuro, non in questo progetto)

Da riprendere quando ci sarà una TV LG di un utente su cui provare (Fano00 o
sronweb). Quanto emerso oggi:

- webOS fa girare app web in un browser integrato: Chromium 79 (2021),
  87 (2022), 94 (2023), 108 (2024), 120 (2025), 132 (2026).
- La build web di WonderFlix su LG userebbe il ripiego JS + CanvasKit (non
  WebAssembly). Un report sul forum LG descrive con CanvasKit: blocco sulla
  schermata iniziale su webOS ≤5.5, lentezza e chiusure per memoria sulle
  recenti. Realisticamente solo dalle LG 2023 in su.
- L'app Jellyfin per LG è un guscio che carica il client web del server in un
  iframe: è il modello da seguire (guscio che carica `/wonderflix/`).
- Tasti: frecce 37–40, OK 13, Indietro 461, play/pausa 415/19.
- LG ha pubblicato un Flutter nativo per webOS, ma solo per TV 2026 aggiornate.

## Vincoli

- Dispositivo di prova: Fire TV Stick dell'utente, modello AFTMA08C15
  ("karat"), Fire OS 8.1.8.5 (Android 11, API 30), **userland a 32 bit
  (armeabi-v7a)**, ~1,7 GB di RAM, uscita 1080p. L'APK deve includere
  armeabi-v7a (e arm64-v8a per gli altri dispositivi).
- Solo questo dispositivo è disponibile per i test.
- Su questo Fire Stick la densità fa risultare lo schermo 960×540 dp: oggi
  l'app sceglie il layout da telefono. La TV ha un suo layout, non quello da
  telefono.
- Toolchain Android installata sul PC: Java 17
  (`C:\Users\sidot\dev\jdk-17.0.21.0.2+1`), SDK in
  `C:\Users\sidot\dev\android-sdk` (piattaforma 36, build-tools 36.1, NDK
  28.2), già configurati in Flutter (`flutter config`). ADB nella cartella
  `platform-tools` dell'SDK.
- Flutter 3.47.5 fissato in CI; Riverpod 3.
- Le build Windows e web non devono cambiare comportamento, a parte
  l'aggiunta della schermata "Autorizza un dispositivo" (Quick Connect).

## La prova del 2026-11-07 (spike, da buttare)

Branch `spike/tv-android` (worktree `.claude/worktrees/spike-tv`): l'app
attuale compilata per Android senza cambi di interfaccia, avvio senza le parti
Windows (finestra, SMTC, Discord). Risultati sul Fire Stick:

- L'app parte: login, home, ricerca, pagine, menu tracce, "Salta intro"
  funzionano.
- mpv (media_kit) in modalità normale (`hwdec auto-safe`, copia nella texture
  di Flutter): 1080p H.264 ok; **HEVC 10 bit (4K HDR e anime 1080p) immagine
  nera o ferma con audio**, avvisi del decoder MediaTek
  ("PrepareAvaliableColorConvertBuffer"), poi l'app si blocca (ANR).
- mpv in modalità diretta (`hwdec mediacodec`, `vo mediacodec_embed`): fluido
  anche a 30 Mbps, ma **niente sottotitoli** e il formato cinema esce
  schiacciato con una banda verde.
- Da qui la scelta di ExoPlayer + libass.
- Effetti sull'account di prova: ripristinati, tranne il punto di ripresa di
  "A Sign of Affection" S1E1 a 3:35.

## Lasciato al builder

- Come integrare Media3 e libass in Flutter.
- Come la TV viene riconosciuta (flavor/target di build dedicato, controllo
  di `android.software.leanback` all'avvio, …) e come si separa il layout TV
  da quello PC/telefono.
- Gestione del focus (widget `Focus`/`FocusTraversalGroup` di Flutter o un
  pacchetto), animazioni del focus.
- Dettagli di Stasera, Vota, Consiglia e Richieste col telecomando, partendo
  dai pannelli del PC.
- Banner della TV nel launcher di Fire TV / Android TV e icona.
- Ordine dei lavori dopo la prova del motore.
