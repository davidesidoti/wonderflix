# Trailer dentro l'app — design

Data: 2026-11-10. Stato: bozza da approvare.

## Perché

Un amico consiglia un film ("Colony"). L'utente apre la scheda, legge la
trama e vorrebbe vedere il trailer. Oggi:

- il pulsante "Trailer" compare solo se Jellyfin conosce un trailer
  (`RemoteTrailers` o `LocalTrailerCount`). Colony, aggiunto il
  2026-11-07, non ne ha, quindi il pulsante mancava;
- quando c'è, il trailer remoto (YouTube) si apre **nel browser**
  (`playTrailer` in `app/lib/features/playback/play_launcher.dart`);
- sulla TV il pulsante è nascosto (`trailer != null && !tv` in
  `detail_header.dart`), proprio perché aprirebbe il browser.

L'utente vuole un pulsante che fa partire il trailer **restando dentro
l'app**, su Windows, web (anche iPhone) e Fire TV.

## Obiettivi

1. Il trailer si guarda dentro WonderFlix, su tutte le piattaforme, senza
   aprire browser, schede o l'app di YouTube.
2. Il pulsante compare anche per i titoli che Jellyfin non conosce ancora
   come "con trailer" ma che su TMDB ce l'hanno (Colony).
3. I file dei trailer restano poco sul server: niente accumulo.

## Non obiettivi

- Trailer per episodi o stagioni: solo film e serie.
- Scaricare in anticipo i trailer di tutta la libreria.
- Watch party sul trailer, resume, segnare come visto, sottotitoli, scelta
  della qualità.
- Trailer salvati nella libreria (accanto ai file dei film).

## Anti-obiettivi (sarebbe un fallimento anche se "funziona")

- Si apre il browser o l'app di YouTube, anche come ripiego.
- Il seedbox si riempie di trailer.
- Un utente può far scaricare al server un video YouTube qualsiasi.

## Cosa abbiamo verificato (2026-11-10)

- **Dati sul server:** 644 film su 795 e 88 serie su 186 hanno link
  YouTube in `RemoteTrailers` (già in italiano, es. "Trailer Ufficiale
  Italiano"). Nessun trailer locale.
- **Colony:** `RemoteTrailers` vuoto; Seerr (`GET /api/v1/movie/1375646`)
  dà `relatedVideos` con "COLONY (2026) | Trailer italiano…"
  (`https://www.youtube.com/watch?v=25WcssMq1VM`).
- **YouTube incorporato scartato:** il sito web manda
  `Cross-Origin-Embedder-Policy: require-corp` (serve a skwasm). Con questa
  intestazione l'iframe di YouTube è bloccato; parte solo con l'attributo
  `credentialless`, che Safari non supporta, quindi su iPhone non va. Sulla
  Fire TV la WebView è spesso vecchia e il telecomando non entra
  nell'iframe. Alcuni video vietano anche l'incorporamento.
- **yt-dlp sul seedbox:** `yt-dlp 2026.10.26` (venv sull'host) scarica
  `AmsN8z7tl48` con
  `-f "bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/b[height<=720]" --merge-output-format mp4`
  in 7 s: 27,7 MB, h264 1280x720 + aac, 155 s. Avviso: senza un motore
  JavaScript YouTube "potrebbe togliere formati" (oggi funziona).
- **Container Jellyfin:** Ubuntu 26.04 (linuxserver, s6), **senza
  python3**; ffmpeg in `/usr/lib/jellyfin-ffmpeg/ffmpeg`; `/config` è
  `~/.apps/jellyfin` sull'host; `/tmp` scrivibile, non montato a parte.
  L'IP d'uscita dell'host è 149.40.59.140.
- **Non verificato:** che il binario autonomo `yt-dlp_linux` parta dentro
  il container (non c'è modo di eseguire comandi lì dentro senza il
  plugin).

## Come funziona (deciso con l'utente)

- Il trailer passa dal seedbox: il plugin lo scarica con yt-dlp quando
  qualcuno preme "Trailer" e l'app lo riproduce nel proprio player.
  L'utente accetta che sia contro i termini di YouTube (uso privato).
- **Durata dei file:** ognuno si cancella **un'ora dopo l'ultima
  visione**.
- **Anche fuori libreria:** il trailer in app vale anche nella scheda TMDB
  delle richieste. Ogni utente autenticato può quindi far scaricare il
  trailer di qualunque titolo TMDB (limitato da durata di un'ora e tetto
  di 1 GB).

## Come funziona (scelte mie, da controllare)

### Plugin

**Da dove viene il trailer.** Il plugin risolve il link da solo, a
partire da un elemento della libreria o da un id TMDB; l'app non manda mai
un URL YouTube.

1. Elemento della libreria (film o serie): primo `RemoteTrailers` di
   Jellyfin con un id YouTube valido.
2. Altrimenti, se l'elemento ha l'id TMDB e Seerr è configurato:
   `SeerrClient.GetMovieAsync` / `GetTvAsync` con la lingua `it`, poi la
   regola già usata da `SeerrMapping.TrailerUrl` (primo "Trailer"
   YouTube, altrimenti il primo "Teaser").
3. Titolo fuori libreria (scheda TMDB delle richieste,
   `tmdb_title_screen.dart`): `(mediaType, tmdbId)` → passo 2.

Il risultato della ricerca (anche "nessun trailer") resta in memoria
24 ore per chiave, così aprire una scheda non chiama Seerr ogni volta.

**yt-dlp.** Binario autonomo `yt-dlp_linux` (Python incluso) dall'ultima
release ufficiale su GitHub, controllato con lo SHA-256 del file
`SHA2-256SUMS` della stessa release, salvato in
`<cartella dati del plugin>/trailers/bin/` ed eseguibile (`chmod +x`).
Viene scaricato al primo uso e riscaricato se ha più di 7 giorni o se un
download fallisce con un errore di estrazione (una volta, poi si arrende).
Comando:

```
yt-dlp_linux --no-playlist --no-progress \
  --ffmpeg-location /usr/lib/jellyfin-ffmpeg/ffmpeg \
  -f "bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/b[height<=720][ext=mp4]" \
  --merge-output-format mp4 \
  --match-filter "duration<=600" --max-filesize 200M \
  -o "<cartella>/<videoId>.part.%(ext)s" https://www.youtube.com/watch?v=<videoId>
```

poi rinomina il file finito in `<videoId>.mp4`. Il percorso di ffmpeg
viene dal percorso che Jellyfin usa già (`IMediaEncoder.EncoderPath` o
equivalente in 10.11), non scritto a mano. Timeout 3 minuti; i processi
vengono uccisi per PID se scade o se Jellyfin si ferma.

**Cache.** Cartella `<cartella dati del plugin>/trailers/cache/`, un file
per id YouTube (due utenti sullo stesso trailer condividono il file e il
download). Regole:

- ogni richiesta di stato o di stream aggiorna "ultima visione";
- un servizio in background ogni 5 minuti cancella i file non visti da
  più di 60 minuti e i `.part` orfani;
- all'avvio del plugin la cartella cache si svuota;
- tetto 1 GB: prima di un nuovo download, se si supererebbe, si cancellano
  i file visti meno di recente;
- non si cancella un file mentre è in riproduzione (stream aperto).

**API** (in un nuovo `TrailersController`, rotta `WonderFlixWatchParty`,
utenti autenticati; schema a job come `SearchStart`/`SearchStatus`, perché
il download dura più del timeout di nginx):

- `GET Trailers/Info?itemId=` oppure `?tmdbId=&type=movie|tv` →
  `{ Available: bool, Name: string? }`. Solo ricerca, niente download.
- `POST Trailers/Start` con lo stesso corpo → `{ Key, State, Error? }`,
  con `State` tra `Downloading`, `Ready`, `Failed`, `None` (nessun
  trailer). Avvia il download se il file non c'è.
- `GET Trailers/Status?key=` → stesso oggetto.
- `GET Trailers/{key}/Stream` → l'mp4 con supporto `Range`
  (`PhysicalFile(..., enableRangeProcessing: true)`), `video/mp4`.

`Key` è l'id YouTube. Il plugin accetta solo id usciti dalla propria
risoluzione: un id che non ha risolto lui risponde 404.

### App

- **Quando compare il pulsante:** per film e serie, se Jellyfin conosce un
  trailer (come oggi) **oppure** se `Trailers/Info` risponde
  `Available: true` (chiamata all'apertura della scheda, solo se Jellyfin
  non ne conosce già uno). Con un plugin troppo vecchio (404) il pulsante
  non compare per i trailer remoti: niente browser come ripiego. I trailer
  locali di Jellyfin continuano ad aprirsi nel player di sempre.
- **Sulla TV** il pulsante si vede (togliere `!tv` dal ramo largo di
  `detail_header.dart`) ed è raggiungibile con il telecomando.
- **Premuto:** si apre subito una schermata trailer a tutto schermo con
  sfondo nero, il backdrop del titolo e "Preparo il trailer…"; l'app manda
  `Start` e poi interroga `Status` ogni secondo fino a `Ready`, con un
  limite di 3 minuti. Con `Ready` apre lo stream e parte. Con `Failed` o
  `None`: messaggio "Trailer non disponibile" e un pulsante per chiudere.
- **Schermata trailer:** nuova e semplice, non `PlayerScreen` (che è
  legato a PlaybackInfo, resume, watched, watch party). Usa il
  `VideoEngine` di piattaforma (`default_video_engine`: media_kit su
  Windows, `WebVideoEngine` sul web, `Media3Engine` sulla TV) con
  `VideoSource(url, headers: autorizzazione come per il resto delle
  chiamate)`. Controlli: play/pausa, barra con posizione, chiudi. Si
  chiude da sola alla fine del video. TV: OK = play/pausa,
  sinistra/destra = ±10 s, Indietro = chiudi (ignorare `goBack` nei key
  handler, come da nota TV). iPhone: se `playBlockedStream` scatta, un
  grande pulsante play da toccare.
- **Dove si usa:** `playTrailer` (scheda dettagli e
  `space_title_dialog.dart`) e la scheda TMDB delle richieste
  (`tmdb_title_screen.dart`, che oggi fa `launchUrl` del `TrailerUrl`).
  In nessuno dei tre resta `launchUrl` per i trailer.
- Testi nuovi in `app/l10n` (it/en).

## Vincoli

- Plugin compilato su Jellyfin 10.11.0, test su 10.11.9: non dare per
  scontate firme di patch release.
- Richieste lunghe solo come job interrogato (nginx `/jellyfin/` taglia a
  180 s).
- Dio: `receiveTimeout` normale va bene, perché ogni chiamata è breve.
- Web: COEP `require-corp`; lo stream arriva dallo stesso host
  (`/jellyfin/...`), quindi non è bloccato. `WebVideoEngine` mette l'mp4
  in `_video.src` e ignora gli header: l'URL dello stream passa da
  `withApiKey(...)` (`core/jellyfin/media_url.dart`), come le altre
  riproduzioni dirette. Verificare che l'`[Authorize]` del plugin accetti
  la chiave nella query.
- Off-TV il comportamento della scheda resta identico, a parte il
  pulsante che ora apre la schermata trailer invece del browser.

## Ordine di lavoro consigliato

1. **Spike nel container (prima di tutto):** build del plugin con il solo
   download di yt-dlp + `--version` + un download di prova, deploy sul
   seedbox, controllo nei log. Se il binario non parte nel container, ci
   si ferma e si torna dall'utente (ripiego: un piccolo servizio utente
   sul seedbox fuori dal container).
2. Plugin: risoluzione, cache, job, API, test.
3. App: pulsante, schermata trailer, TV, scheda TMDB, test.
4. Riga nuova nella checklist manuale di `docs/RELEASING.md`; versioni
   plugin 1.27.0 e app 0.38.0.

## Test

- Plugin: risoluzione (Jellyfin prima di Seerr, Seerr assente, nessun
  trailer), id non risolto → 404, pulizia dopo 60 minuti con un orologio
  finto, tetto 1 GB, svuotamento all'avvio, download condiviso tra due
  richieste, `.part` mai servito. Il processo yt-dlp dietro
  un'interfaccia, così i test non scaricano niente.
- App: pulsante visibile con `Available: true` e nascosto con 404,
  schermata trailer da `Downloading` a `Ready` e da `Failed` a messaggio
  con un motore finto, tasti TV.
- A mano: Colony da Windows, da iPhone (web) e dal Fire Stick; un titolo
  con trailer Jellyfin; un titolo senza trailer; dopo un'ora il file è
  sparito dal seedbox.

## Lasciato a chi implementa

- Nomi di classi, DTO e provider; dove sta esattamente la cartella dati.
- Aspetto della schermata trailer, entro lo stile dell'app.
- Il motore JavaScript per yt-dlp: non serve oggi; se YouTube toglie i
  formati, aggiungere un runtime piccolo (`--js-runtimes`), da decidere
  allora.
