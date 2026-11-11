# Ricerche via Prowlarr — design

Data: 2026-11-11. Riguarda il plugin (download automatici, ricerca a mano, Alleggerisci) e, per un pulsante, l'app.

## Perché

Ogni ricerca del plugin oggi è un `GET /release` di Sonarr/Radarr (ricerca interattiva). Sonarr 4.0.20 tiene in memoria
per 30 minuti ogni release trovata con serie ed episodi allegati (`ReleaseController.cs:240`,
`_remoteEpisodeCache.Set(..., TimeSpan.FromMinutes(30))`). Per una serie anime una ricerca di stagione diventa stagione
+ ogni episodio (Slime S02: 25 ricerche da 170–600 release l'una). Con il ciclo automatico che cerca quasi di continuo,
Sonarr (container da 2 GB) va in OutOfMemory: il 2026-11-11 è stato riavviato ~10 volte, e Alleggerisci su Slime S02 è
fallito tre volte con "Unreachable" (riavvio del watchdog a metà ricerca, poi OOM vere).

Prova fatta sul seedbox (Slime S02): Prowlarr diretto con i titoli della serie e i suoi titoli alternativi di stagione,
14 query, 1640 release uniche in 44 s; `GET /parse` di Sonarr su tutte e 1640 in 6 s; una ventina di pack S2 veri
(ItaTorrents 23,6 GB WEB-DL ITA, LostYears 11,8 GB, FLE 25 GB BD, Asakura 45 GB, …); memoria di Sonarr invariata
(1,33 → 1,37 GB). `/parse` non mette niente in cache.

## Obiettivi

- Nessuna ricerca del plugin usa più `GET /release`: ciclo automatico, ricerca a mano ("Cerca adesso", SearchStart/
  SearchStatus, GrabBest), Alleggerisci. Sia Sonarr sia Radarr.
- Nuova strada: **cerca su Prowlarr → `GET /parse` su Sonarr/Radarr per ogni release → regole del plugin di sempre →
  `POST /release/push` della sola release scelta.**
- Ogni release scartata ha un motivo breve (l'utente non vuole il dettaglio, vuole un motivo).
- Quando la ricerca trova poco, il plugin **resta su Prowlarr e lo segnala**; nella ricerca a mano c'è un pulsante
  "Cerca con Sonarr" / "Cerca con Radarr" che rifà quella sola ricerca alla vecchia maniera.

## Non obiettivi

- La UI admin "più simile a Sonarr": progetto separato, dopo questo (includerà anche Radarr).
- Cambiare la configurazione di Sonarr/Radarr/Prowlarr o il watchdog (`~/bin/sonarr-watchdog.sh`, già sistemato a parte).
- Riprodurre tutto il motore di decisione di Sonarr nel plugin.

## Anti-obiettivi (sarebbe un fallimento anche se funziona)

- Trovare sensibilmente meno release di oggi per gli anime o per i titoli italiani (gli indexer italiani usano i titoli
  italiani: "A un passo da te" per "Ao Haru Ride").
- Il ciclo automatico che ripiega da solo sulla ricerca di Sonarr: mai.
- Scaricare release che Sonarr/Radarr oggi avrebbero scartato (blocklist, profilo) senza che nessuno lo veda.
- Chiavi API o query nei log (regola già in `ArrClient`).

## Come funziona (deciso)

### 1. Client Prowlarr
- Un `IProwlarrClient`/`ProwlarrClient` nuovo sul modello di `Home/ArrClient.cs` (stesso HttpClient `WonderFlixArr`,
  stesso trattamento errori e timeout, niente chiave/query nei log).
- Impostazioni nuove `ProwlarrUrl` e `ProwlarrApiKey` in `PluginConfiguration` e nella pagina di configurazione, accanto
  a Sonarr/Radarr. Sul seedbox: `http://149.40.59.140:20790/prowlarr` (nginx; Jellyfin è un container e 127.0.0.1 non
  arriva, i `*.usbx.me` tagliano a 300 s).
- **Prowlarr non configurato → si comporta come oggi** (`GET /release`). Così il rilascio non rompe niente finché la
  chiave non è inserita.
- API: `GET /api/v1/search?query=…&type=search|tvsearch|movie[&season=N][&ep=E]&indexerIds=…&categories=…`.

### 2. Quali indexer
- Verificato il 2026-11-11: tutti gli indexer di Sonarr e Radarr vengono da Prowlarr (Torznab), nessuno ha tag;
  Bangumi Moe e CZTeam hanno la ricerca disattivata.
- Esattamente quelli che il servizio ha da Prowlarr con ricerca interattiva attiva: da `GET /indexer` di Sonarr/Radarr
  (già letto per le priorità in `ReadContextAsync`), l'id Prowlarr è nel `baseUrl` (`…/prowlarr/<id>/…`). Il plugin
  conserva la mappa id Prowlarr → id indexer del servizio: priorità (italiani a 20) e push usano l'id del servizio.
- Categorie: quelle configurate sull'indexer del servizio (campi `categories`, e `animeCategories` per le serie anime).

### 3. Le query (per titolo, mai per ID)
- Prova: con `tvdbid` Nyaa/Knaben ignorano l'ID e restituiscono le ultime uscite (704 risultati, 1 di Slime). Si cerca
  per titolo.
- **Serie, stagione N**: `tvsearch` con il titolo e `season=N`; più `search` con ogni titolo alternativo di Sonarr con
  `sceneSeasonNumber` = N o −1, e quelli con `seasonNumber` −1 (titoli generali, anche italiani come "Vita da Slime").
- **Serie, episodio**: `tvsearch` titolo + `season` + `ep`. Per le serie anime anche le query che fa Sonarr con la
  numerazione assoluta (`absoluteEpisodeNumber`, e la numerazione scene `sceneSeasonNumber`/`sceneEpisodeNumber` con i
  titoli di quella stagione).
- **Film**: `movie` con titolo (+ anno), più i titoli alternativi di Radarr: *(mia scelta)* originale, inglese e
  italiano, deduplicati senza badare a maiuscole.
- *(mia scelta)* Al massimo 8 query per ricerca; per le serie si tengono prima il titolo principale e quelli della
  stagione, poi i generali.
- Release deduplicate per indexer + guid.

### 4. Parse e attribuzione
- Per ogni release `GET /parse?title=` sul servizio, con un parallelismo piccolo (la prova sequenziale fa 1640 in 6 s).
- Si costruisce lo stesso `ArrRelease` di oggi: qualità, `CustomFormatScore`, `FullSeason`, `EpisodeNumbers`/
  `MappedEpisodeNumbers` (dagli `episodes` del parse, solo quelli della stagione cercata), `Seeders`, `Size`, `Title`,
  `Indexer`/`IndexerId` (id del servizio). In più il plugin si tiene `downloadUrl`/`magnetUrl`, `protocol`,
  `publishDate` per il push.
- Così `DownloadRule`, `SeasonPackRule`, `WouldImport` e i DTO dell'app restano quelli di oggi.
- Noto dalla prova: `/parse` a volte prende un episodio per stagione intera ("Slime Datta Ken S2 22", 0,3 GB). La regola
  "troppo piccola" esistente lo scarta; il push resta l'ultimo controllo.

### 5. Motivi di scarto (prima del grab)
Calcolati dal plugin, con dati che il servizio dà senza cercare. Codici `Reason` nuovi accanto a `Arr` e `TooSmall`:
- **`WrongTitle`** — `/parse` la attribuisce a un'altra serie/film, a nessuno (205 su 1640 nella prova), o a un'altra
  stagione.
- **`NotWanted`** — qualità non ammessa nel profilo (stessa logica di posizione di `WouldImport`).
- **`Restricted`** — viola le regole di release del servizio (termini obbligatori/vietati, `GET /releaseprofile`).
- **`Blocklisted`** — in blocklist del servizio (`GET /blocklist`, per titolo/indexer).
- **`TooSmall`** — come oggi.
- *(mia scelta)* Anche, con motivo `NotWanted`: fuori dai limiti di peso della qualità (`GET /qualitydefinition`),
  sotto i seeder minimi dell'indexer (campo `minimumSeeders`, oggi 1 ovunque), sotto il punteggio minimo del profilo
  (`minFormatScore`). Lingua e monitoraggio li lascia al push.
"Not an upgrade", "in coda", "file esistente" oggi sono già ignorati (`IgnoredRejectionPrefixes`): non servono.
`DownloadRule.Summarize` oggi conta come `TooSmall` tutto ciò che non è `Arr`: va aggiornato, o i `WrongTitle`
(205 su 1640 nella prova) gonfiano il conteggio "troppo piccole".

### 6. Grab con push
- `POST /release/push` con titolo, link (`downloadUrl` o, se manca come per Nyaa, `magnetUrl`), `protocol`,
  `publishDate`, `size`, `indexerId` del servizio. Sonarr la valuta come se venisse dall'RSS (`GetRssDecision`) e, se la
  approva, la scarica; la risposta contiene approvata/rifiutata e i motivi.
- Differenza con oggi (verificata in `ReleaseController.DownloadRelease`): il grab per guid di oggi scarica **senza**
  le regole di decisione; il push le applica. Per questo i download **intenzionali** hanno una seconda strada (sotto).
- **Download intenzionali**: Alleggerisci (`GrabRequest.Lighten`), il tappabuchi con `forceImport`
  (`DownloadService.Search.cs` ~361-370), il grab dell'admin che finisce in `ManualImportPending` (`WouldImport` falso,
  `Admin.cs` ~1434), la ricerca su stagioni non monitorate. Se il push li rifiuta **solo** per motivi di file, coda o
  monitoraggio ("Not an upgrade", "Existing file on disk…", "Release in queue", "… not monitored" e simili), il plugin
  manda il torrent **direttamente a qBittorrent** nella categoria del servizio (Sonarr/Radarr), con `QbitClient`
  esteso di un "aggiungi torrent" (`.torrent` dal link di Prowlarr, o magnet), e poi chiude con l'**import manuale che
  esiste già** (quello di "Alleggerisci importato a mano" / `ManualImportPending`, `importMode` copy). Deciso
  dall'utente: questi download non compaiono come grab nella cronologia di Sonarr/Radarr, solo all'import.
  Un download non intenzionale con gli stessi motivi resta rifiutato.
- **Rifiuti di regola del push** (profilo, dimensioni, restrizioni, …) sono distinti dai **rifiuti del client** (il
  torrent non entra in qBittorrent): *(mia scelta)* un rifiuto di regola scarta la release con motivo `Arr` e il
  primo motivo di Sonarr, si prova la candidata successiva (fino a 3 per ricerca), **senza** `GrabRefused`, senza
  notifica "serve te" e senza occupare `RefusedReleases` (tetto 20), che resta per i rifiuti del client come oggi.
  Se tutte e 3 vengono rifiutate per regola, l'esito è come "niente di valido".
- Il push sostituisce il guid con `PUSH-<downloadUrl>`: `RefusedReleases` e `DownloadChoice.Guid` usano l'identità
  della release lato plugin (indexer + guid di Prowlarr); da verificare in implementazione.
- La ricerca a mano non dipende più dalla cache di Sonarr: il grab dopo 10 minuti funziona perché il plugin ha il link.
  Il "risultati scaduti, ricerco" (404/400 su `POST /release`) resta solo per la strada vecchia.

### 7. "Trovato poco" e "Cerca con Sonarr/Radarr"
- Il DTO della ricerca (`DownloadSearchDto`) dice da quale strada viene (Prowlarr o servizio) e se ha trovato poco.
  "Poco" = nessuna candidata valida, oppure, in una ricerca di stagione, nessun pack completo.
- Nella pagina di ricerca a mano dell'app (`download_search_page.dart`): con "trovato poco" un avviso; e un pulsante
  "Cerca con Sonarr"/"Cerca con Radarr" che rilancia **quella** ricerca con `GET /release` (codice di oggi, compreso il
  grab per guid). Il pulsante c'è sempre nella ricerca a mano, l'avviso solo quando serve.
- Il ciclo automatico non usa mai la strada vecchia (se Prowlarr è configurato). *(mia scelta)* "Trovato poco" nel
  ciclo è solo annotato (log e stato di oggi per i risultati vuoti): nessuno stato o codice nuovo, nessuna notifica, e
  una stagione senza pack si divide in episodi come oggi.

### 8. Il resto non cambia
Ciclo (ogni 15 min, ≤10 ricerche una alla volta, pausa 10 s, precedenza alle ricerche a mano), job di ricerca in
background con risultato per 30 min, Alleggerisci (`GrabRequest.Lighten`), Spazio. Per gli anime una ricerca diventa
~6–15 query brevi invece di 25 ricerche lunghe di Sonarr.

## Vincoli
- Plugin net9.0 contro Jellyfin 10.11.0; test contro 10.11.9.
- Timeout: ogni query Prowlarr ha un timeout suo (Prowlarr taglia già gli indexer lenti); la ricerca intera resta dentro
  i tempi attuali dei job.
- Rate limit indexer (oggi Uindex risponde 429): le query di una ricerca partono in fila o con parallelismo basso.
- Versioni: plugin minor (1.29.0, aggiornare `InfoControllerTests`); app minor per il pulsante, con riga nuova nella
  checklist di `docs/RELEASING.md`.

## Lasciato al builder
- Nomi di classi/metodi, struttura dei file, parallelismo e timeout esatti.
- Come leggere blocklist e release profile in modo economico (una volta per ciclo/ricerca, come le priorità).
- La forma esatta delle query anime per episodio, purché la verifica qui sotto passi.
- Testi italiani dell'avviso e del pulsante.

## Rischi aperti da verificare in implementazione
- **Esito reale del push**: un push approvato ma che il client rifiuta (torrent già in qBittorrent → 500 "Download client
  failed to add torrent" sulla strada vecchia). Verificare cosa restituisce il push e trattarlo come rifiutato.
- **Push "temporaneamente rifiutato"** (delay profile → pending in Sonarr): va contato come preso, non come rifiutato.
- **Custom format basati sulla dimensione**: `/parse` li calcola senza dimensione; verificare che i profili di oggi non
  ne abbiano, altrimenti il punteggio va corretto.

## Come si capisce che funziona
- Alleggerisci su "That Time I Got Reincarnated as a Slime" S02 trova i pack e finisce in pochi minuti.
- Una giornata di ciclo automatico senza riavvii del watchdog per OutOfMemory dovuti alle ricerche
  (`~/.local/state/sonarr-watchdog/watchdog.log`).
- Confronto su un campione prima del rilascio: un episodio anime in corso, un pack anime, una serie normale, un film
  italiano. Per ognuno, numero di candidate valide e scelta con la strada nuova contro `GET /release`. La strada nuova
  non deve perdere la release che oggi verrebbe scelta.
