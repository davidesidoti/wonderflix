# WonderFlix — Spec U: spazio sul seedbox

- **Data:** 2026-10-30
- **Stato:** piani 30a e 30b realizzati (plugin 1.16.0, app 0.25.0, branch `feat/spazio-seedbox`, non ancora rilasciato).
- **Ambito:** Spec U. Si appoggia alla Spec T (download automatici: `2026-10-28-wonderflix-download-automatici-design.md`), alla Spec M (Sonarr e Radarr nel plugin), alla Spec I (richieste con Seerr) e alla dashboard admin.

## 1. Obiettivo

Oggi l'admin libera spazio a mano. Guarda quanto pesa un titolo, si chiede se qualcuno lo vuole vedere o l'ha chiesto, controlla se è già stato visto e poi abbandonato, e cancella da Radarr, Sonarr e qBittorrent uno per uno.

Con la Spec U **WonderFlix fa l'incrocio al posto suo**. Gli mostra cosa occupa spazio, propone i candidati con il perché e, quando l'admin preme un pulsante, fa tutto il lavoro. Durante l'operazione mostra i singoli passi. È una funzione solo per gli admin.

**Nota sul modello.** WonderFlix non cancella mai da solo. Propone, e l'admin decide titolo per titolo. Per questo non servono protezioni extra: la decisione è sempre dell'admin (dell'utente, §3). L'unica cosa automatica è la rimozione di un torrent che l'admin ha già deciso di eliminare, quando finisce il seed obbligatorio (§6.3).

**Differenza da Maintainerr.** Sul seedbox c'è una cartella `~/maintainerr`, ma l'app non è in esecuzione. Maintainerr cancella da solo, con delle regole, dopo un periodo in una collezione "in uscita". Qui invece decide sempre l'admin, e WonderFlix conosce anche le regole di seed dei tracker.

## 2. Situazione di partenza

Controllato via SSH il 2026-10-30, solo in lettura.

### Seedbox

- **Quota:** 11.088 GB usati su 11.176 GB (`quota -s`), restano circa 90 GB. Il disco mostrato da `df` (26 TB) è condiviso e non conta.
- **Cartelle:** `media/series` 6,3 TB, `media/movies` 3,1 TB, `media/anime` 262 GB. Poi `downloads/qbittorrent` (categorie `movies`, `series`, `anime_tv`, `anime_film`, più alcune cartelle di stagione) e `seedings`. `media/Movies` e `media/TV Shows` sono vuote.
- **Hardlink** (file sopra i 100 MB):
  - in `downloads` e `seedings`, collegati alla libreria: 3.210 file, 5,9 TB, che non occupano spazio in più;
  - **solo torrent**, senza copia in libreria: **940 file, 1,34 TB**;
  - in libreria senza torrent: 2.902 file, 5,0 TB;
  - copie doppie vere (stessa dimensione, non collegate): 2 file, 8,8 GB. Gli hardlink funzionano, i doppioni non sono un problema.
- **qBittorrent:** WebUI su `127.0.0.1:17541`, `WebUI\LocalHostAuth=true`, quindi serve il login anche da localhost. Ci sono anche qui (regole automatiche su qBittorrent), Jellystat, Seerr e Bazarr.
- **Cestino di Radarr e Sonarr:** spento (`recycleBin` vuoto in entrambi). `deleteFiles=true` libera lo spazio subito.

### Plugin

- `Home/ArrClient.cs` (`IArrClient`) legge da Radarr e Sonarr film, serie, episodi, `moviefile` e `episodefile` (con `Size`), profili qualità, coda, release. Non scrive: niente cancellazioni, niente cambio di `monitored`. L'unica cancellazione è `DELETE queue/{id}` (Spec T). I modelli in `Home/ArrJson.cs` leggono già `Monitored` e `QualityProfileId`; `RadarrMovie` e `SonarrSeries` non hanno `SizeOnDisk`.
- **qBittorrent:** nessun client.
- **Richieste:** arrivano da Seerr (`Hub/RequestsService.cs`, `MediaRequestDto`: `RequestedBy`, `CreatedAt`, `Status`, `JellyfinItemId`, `TmdbId`, `Seasons`).
- **Voti:** `Hub/RatingBook.cs` (`ratings.json`), per film e per stagione, per utente.
- **Visione:** nessun aiuto generale. Si usa `IUserDataManager.GetUserData` direttamente (`Played`, `PlaybackPositionTicks`, `LastPlayedDate`). Esempi in `Server/JellyfinRatingLibrary.cs` (`HasWatched`) e `Server/JellyfinRecommendationLibrary.cs` (`LastWatched`).
- **Raccomandazioni:** sono consigli tra amici, non un punteggio. Il plugin non sa niente di saghe o seguiti, a parte le collezioni (BoxSet) di Jellyfin. Per "seguito in arrivo" la Spec U usa invece le collezioni di Radarr (§4.2).
- **Admin:** `[Authorize(Policy = Policies.RequiresElevation)]`, come `DownloadsController`.
- **Progresso:** nessun push dei progressi. La scheda Download ricarica ogni 60 s (`AdminPoller`).

### App

Dashboard admin in `lib/features/admin/`, schede `AdminTab` (sessions, users, maintenance, activity, downloads, wonderflix). Pezzi riusabili: `admin_confirm_dialog.dart`, `admin_action_button.dart`, `admin_widgets.dart`, `AdminPoller`, la pagina di ricerca della Spec T (`lib/features/downloads/`).

## 3. Decisioni

| Tema | Decisione | Di chi |
|---|---|---|
| Chi decide | sempre l'admin, con un pulsante per titolo; WonderFlix propone | utente |
| Protezioni | nessuna in più: prima di agire una conferma dice cosa succederà | utente ("è un'azione che faccio partire io") |
| Progresso | ogni azione mostra i passi dal vivo, con il passo fallito e il motivo | utente |
| Segnali | tutti quelli di §4 | utente ("tutti molto utili") |
| "Ti potrebbe piacere" | niente punteggio: scheda con trama, generi e trailer, pulsante "Tienilo", preferiti Jellyfin = tienilo, un'etichetta leggera sui generi | utente (proposta approvata) |
| Torrent ItaTorrents e ShareIsland | si eliminano solo con ratio ≥ 10 oppure ≥ 30 giorni di seed, finiti di scaricare; qualsiasi tag e categoria | utente |
| Torrent di altri tracker | si eliminano subito | utente |
| Tre liste: Cancellare, Alleggerire, Pulizia | §5 | mia, approvata nella conversazione |
| Film e serie intere: rimossi da Radarr/Sonarr con i file, senza esclusione | così si possono richiedere di nuovo | mia |
| Stagioni: smettere di monitorare la stagione e cancellarne i file | la serie resta in Sonarr | mia |
| Progresso via polling ogni 1 s mentre il riquadro è aperto | niente WebSocket nuovo | mia |
| Torrent in seed obbligatorio | il file in libreria sparisce subito; il torrent si toglie da solo a fine obbligo | mia |
| Alleggerire | riusa la ricerca della Spec T; il vecchio torrent finisce poi in Pulizia | mia |
| Soglie | nella configurazione del plugin, valori iniziali in §4.3 | mia |
| Visto da alcuni, abbandonato da altri | un solo segnale "nessuno lo guarda più" (§4.1) | mia, dopo la revisione |
| Un titolo alleggerito non torna pesante | la Spec T lo segna "va bene così" | mia, dopo la revisione |
| Seerr | la cancellazione toglie anche il media da Seerr, così si può richiedere di nuovo | mia, dopo la revisione |
| "Togli tutti quelli possibili ora" | solo torrent; file orfani e doppioni uno alla volta | mia, dopo la revisione |

## 4. Segnali

Il plugin calcola i segnali per ogni film, serie e stagione. L'app li mostra come frasi brevi. La classifica non è un punteggio unico: ogni candidato entra in una lista per un motivo (§5), e la lista è ordinata per **GB liberabili subito**, dal più alto.

### 4.1 Segnali "via"

- **Nessuno lo guarda più.** Qualcuno l'ha aperto, e nessuno lo apre da almeno *N mesi*, che l'abbia finito o no. Gli speciali (stagione 0) non contano per "finito" di una serie intera. La frase dice come stanno le cose: "visto da tutti", "abbandonato da tutti" oppure "visto da Anna, abbandonato da Luca", con la data dell'ultima visione. "Finito" per la serie e la stagione: tutti gli episodi visti (`HasWatched` della Spec dei voti). Chi ha chiesto il titolo e non l'ha mai aperto conta tramite la "richiesta recente" (§4.2).
- **Mai aperto.** Nessuno l'ha mai aperto da *N mesi* dall'aggiunta (`DateCreated` di Jellyfin).
- **Voti bassi.** Media dei voti ≤ 4 (scala 1–10, quella che vedono gli utenti, Spec Q), con almeno 2 voti. Per una serie è la media dei voti delle sue stagioni.
- **Serie conclusa.** Sonarr `status = ended` e nessuno la guarda più: può essere candidata intera. **Stagioni vecchie**: in una serie in corso, una stagione che nessuno guarda più. Di una serie in corso sono candidate solo le stagioni, mai l'ultima (il numero più alto con file) e mai la stagione 0.

### 4.2 Segnali "tienilo"

Non tolgono il titolo dalla lista, ma lo spostano in fondo con un'etichetta:

- **Visione in corso.** Qualcuno è a metà (posizione > 0 o serie con episodi visti e non visti) e l'ha aperta negli ultimi *N mesi*.
- **Richiesta recente.** Chi l'ha chiesto non l'ha ancora visto, e la richiesta ha meno di *M giorni*.
- **Voti alti.** Media ≥ 8 (scala 1–10), con almeno 2 voti.
- **Seguito in arrivo.** Solo per i film: un altro film di Radarr nella stessa collezione (`collection.tmdbId`), senza file e con `status` diverso da `released`. Radarr ha la collezione per 420 film su 825. Le serie non hanno questo segnale.

Questi invece **tolgono** il titolo dalle liste:

- **Tenuto.** L'admin ha premuto "Tienilo" (§6.4).
- **Preferito.** È tra i preferiti Jellyfin dell'admin che guarda la lista.

### 4.3 Valori iniziali

Nella configurazione del plugin, nella sezione Spazio:

- *N* (mesi senza aperture per "nessuno lo guarda più", "mai aperto", "stagioni vecchie"): 6;
- *M* (giorni di grazia di una richiesta): 60;
- voti bassi ≤ 4, alti ≥ 8, minimo 2 voti (scala 1–10, intervallo configurabile 1–10);
- soglia "pesante" per Alleggerire: 4 GB all'ora (le scelte dell'admin nella Spec T vanno da 1 a 3,7);
- tracker con seed obbligatorio: `itatorrents.xyz`, `shareisland.org`; ratio 10; giorni 30.

### 4.4 Etichetta "generi che guardi spesso"

I 3 generi più frequenti tra i titoli che chi chiama ha visto o votato almeno quanto la soglia dei voti alti (8) (calcolati a ogni `GET Space` per chi chiama). Se un candidato ne ha almeno uno, mostra l'etichetta. Non cambia l'ordine.

## 5. Le liste

### 5.1 Cancellare

Film, serie e stagioni con almeno un segnale "via". Ogni riga mostra locandina, titolo, GB, i segnali in frasi ("visto da tutti, ultima visione 8 mesi fa", "voto medio 3/10") e i segnali "tienilo" come etichette. Solo le righe di Cancellare si possono avviare come operazioni, i titoli tenuti no. Due numeri: **GB liberati subito** e **GB liberati dopo il seed** (§6.3), con la data prevista (senza data se un torrent che trattiene i file è ancora in download).

Una serie compare una volta sola. Se è candidata tutta intera, la riga è la serie. Altrimenti la riga è la serie con le sole stagioni candidate, che si aprono sotto.

### 5.2 Alleggerire

Film e stagioni (non episodi singoli) il cui file supera la soglia di GB all'ora (§4.3), ordinati per GB in eccesso rispetto alla soglia. Esclusi i titoli già in Cancellare. Alleggerire lavora **per stagione** (chiave `season:{idSerie}:{n}`). "Alleggerisci" apre la ricerca della stagione della Spec T (§8.2 della Spec T) su quel titolo. L'admin sceglie una release più leggera, e la Spec T la scarica e la sostituisce (import manuale con sostituzione, §5.3b della Spec T). Il vecchio torrent resta e compare poi in Pulizia.

Il file più leggero ha quasi sempre un punteggio o una qualità più bassi, quindi per la Spec T sarebbe sotto l'obiettivo, e gli upgrade automatici o "Da ripassare" riporterebbero un file pesante. Per evitarlo, un download partito da "Alleggerisci" segna il titolo **"va bene così"** nella Spec T (`downloads.json`), come se l'admin l'avesse premuto in "Da ripassare". Gli upgrade automatici non lo toccano più. La chiamata `Downloads/Grab` della Spec T riceve per questo un campo in più, `Lighten` (bool, facoltativo, `false` se manca). Se la ricerca era di una stagione e la release scelta è di un episodio, si accettano tutte le chiavi coinvolte.

### 5.3 Pulizia

Spazio che non serve a nessuno, senza decidere sul contenuto:

- **Torrent senza copia in libreria.** Torrent in qBittorrent i cui file non hanno un hardlink in libreria. Si vede dal numero di collegamenti del file (1 = solo il torrent). Un torrent che condivide un percorso con un torrent che deve restare non si toglie mai insieme al titolo. Per ogni torrent: nome, tracker, GB, ratio, giorni di seed. Ci sono due gruppi: "si possono togliere ora" e "in seed obbligatorio fino al …" (§6.3). Un torrent il cui hash è un `downloadId` nella coda di Radarr o Sonarr (non ancora importato, anche un'alternativa leggera che aspetta l'import a mano) non è mai in Pulizia; se una coda non si legge, nessun torrent è in Pulizia e l'errore resta in `Errors`.
- **File fuori dai torrent e fuori da Radarr/Sonarr.** File video sopra i 100 MB in `downloads` o `seedings` che non appartengono a nessun torrent di qBittorrent. Non sono mai orfani né doppioni i file noti a Radarr/Sonarr (per percorso o inode), i file di un torrent (per percorso o inode) e quelli sotto i download incompleti. Senza i dati di qBittorrent non si mostra nessun orfano, e nemmeno se un torrent finito non ha nessun file visibile su disco (il percorso di qBittorrent non è quello che vede Jellyfin): in quel caso il registro ha un avviso con i soli conteggi.
- **Doppioni.** Lo stesso film o episodio con più file in libreria (Radarr/Sonarr ne conoscono uno, l'altro è in più nella cartella). Di una serie è doppione solo un video con lo stesso `SxxEyy` di un episodio che Sonarr conosce; di un film non lo sono i video nelle cartelle degli extra di Jellyfin (`extras`, `featurettes`, `behind the scenes`, `deleted scenes`, `interviews`, `scenes`, `shorts`, `trailers`, `other`, `samples`).

C'è anche un pulsante "Togli tutti quelli possibili ora". Riguarda **solo i torrent** che si possono togliere ora, e la conferma dice quanti sono e quanti GB. File orfani e doppioni si cancellano uno alla volta, perché il plugin li toglie direttamente dal disco.

### 5.4 In alto

- Quota: usati, totale, liberi. Nel container di Jellyfin `quota` non c'è: un cron sul seedbox scrive l'output di `quota -w` in un file, che il plugin legge (`SpaceQuotaFile`, §9). Se il file è vuoto o non c'è, la quota non c'è e `Errors.Quota` = `NotConfigured`.
- Divisione: film, serie, anime, solo torrent, altro.
- "Liberabili ora" e "liberabili dopo il seed" per ogni lista.
- I dati hanno l'ora dell'ultimo calcolo e un pulsante "ricalcola" (§7.3).

## 6. Le azioni

### 6.1 Come si vedono

Ogni pulsante apre prima una **conferma** con i passi che verranno fatti e i GB attesi (subito e dopo il seed). Poi apre un **riquadro di progresso** con i passi. Ogni passo ha uno stato: in attesa, in corso, fatto, saltato con il motivo, fallito con il motivo. Al primo passo fallito l'operazione si ferma e i passi dopo restano "non fatti". Alla fine il riquadro mostra i GB liberati davvero (quota prima e dopo) e quelli in attesa del seed. Il file della quota lo riscrive un cron ogni 10 minuti: se non è stato riscritto dopo l'inizio dell'operazione, la quota "dopo" resta vuota e l'app mostra la stima. I GB liberati non sono mai negativi. Fino al calcolo dopo, le righe di un'operazione finita (il titolo, i torrent tolti, il file) non si vedono più nelle liste.

Le operazioni girano nel plugin. Se l'admin chiude il riquadro o l'app, l'operazione continua. Le ultime operazioni si rivedono in fondo alla scheda (sono conservate per 30 giorni).

### 6.2 I passi

**Film:**
1. trova i torrent del film in qBittorrent (vedi §12);
2. toglie dalla coda di Radarr/Sonarr i download del titolo, senza blocklist: le voci già complete si tolgono dalla coda senza toccarle in qBittorrent (decide la regola del seed), quelle ancora in download si tolgono anche dal client. Una voce già sparita (404) si salta e le altre continuano;
3. rimuove il film da Radarr con i file (`DELETE movie/{id}?deleteFiles=true`, senza esclusione);
4. per ogni torrent: se si può togliere ora lo toglie con i file, altrimenti lo mette in attesa di fine seed (§6.3). Un torrent che condivide un percorso con un torrent che resta (cross-seed, anche quello in attesa) va via **senza** file: i dati spariscono con l'ultimo torrent su quel percorso, e i loro GB contano solo "dopo il seed";
5. toglie il media da Seerr, così torna richiedibile e le vecchie richieste non contano più;
6. aggiorna la libreria di Jellyfin;
7. legge la quota.

Se Seerr non è configurato, il passo 5 viene saltato con il motivo.

**Serie intera:** come il film, con Sonarr (`DELETE series/{id}?deleteFiles=true`). Se una sua stagione è tenuta, la serie intera non è nelle liste e non si può avviare.

**Stagione:**
1. trova i torrent degli episodi della stagione;
2. toglie dalla coda di Sonarr i download della stagione (come sopra);
3. smette di monitorare la stagione in Sonarr;
4. cancella i file degli episodi della stagione (`DELETE episodefile/bulk`);
5. torrent, libreria e quota come sopra. Su Seerr non si fa niente: la serie resta.

**Torrent (Pulizia):** toglie il torrent con i file, poi legge la quota. Se in quel momento è ancora in seed obbligatorio, il passo viene saltato con il motivo. Dal vivo si ricontrollano le code di Radarr/Sonarr, e un torrent che condivide un percorso con uno che resta va via senza file (vale anche per "togli tutti").

**File orfano (Pulizia):** cancella il file e la cartella se resta vuota, poi legge la quota. Si rifiuta se il file ora ha più di un collegamento o una dimensione diversa da quella del calcolo.

**Doppione (Pulizia):** cancella il file che Radarr/Sonarr non conoscono. La radice consentita è la cartella del film o della serie, letta in quel momento da Radarr/Sonarr.

### 6.3 Seed obbligatorio

- Un torrent di un tracker della lista (§4.3) si può togliere solo se ha finito di scaricare **e** ha ratio ≥ 10 **oppure** almeno 30 giorni di seed (`seeding_time` di qBittorrent). Tag e categoria non contano. Il tracker si riconosce dal dominio degli annunci del torrent.
- Gli altri torrent si possono togliere subito. Il tracker è il campo `tracker` di `torrents/info`; solo se è vuoto si chiama `torrents/trackers`. Il dominio è protetto se l'host coincide con uno della lista o ne è un sottodominio.
- Un torrent in attesa resta in `space.json` (§7.3). Un servizio in background lo controlla ogni ora e lo toglie con i file quando la regola lo permette (senza file se, dal vivo, un altro torrent è sullo stesso percorso). Lo spazio si libera allora. La data prevista mostrata è la data in cui scadono i 30 giorni; se un torrent che trattiene i file è ancora in download la data non c'è, e l'app mostra "dopo il seed" senza data.
- Nella scheda c'è un elenco "In attesa di fine seed", e ogni torrent può essere tolto dall'attesa (lo lascia in qBittorrent).
- Se un torrent in attesa sparisce da qBittorrent per altri motivi, esce dall'elenco.

**Nota per l'admin (fuori dall'app):** la regola "Stop old ItaTorrents downloaded seedings" in qui ha la condizione sullo stato in OR. `STATE ≠ downloading` OR `STATE ≠ stalled_downloading` è sempre vera, quindi deve essere AND. Va corretta a mano in qui.

### 6.4 Tienilo

"Tienilo" su un film, una serie o una stagione lo toglie da Cancellare e Alleggerire. Resta in un elenco "Tenuti" in fondo alla scheda, da cui si può togliere. Vale per tutti gli admin.

### 6.5 Errori

- Radarr, Sonarr o qBittorrent non rispondono: il passo fallisce con "non risponde" e l'operazione si ferma. I passi già fatti restano fatti. Il riquadro dice cosa è rimasto da fare, e il pulsante si può ripremere: i passi già fatti vengono saltati.
- Un titolo già sparito (cancellato a mano nel frattempo): il passo viene saltato con il motivo e si va avanti.
- Due operazioni sullo stesso titolo: la seconda risponde 409 `Busy`.

## 7. Plugin

### 7.1 Configurazione

Sezione "Spazio" nella pagina di configurazione:

- qBittorrent: indirizzo, utente, password. L'indirizzo deve essere raggiungibile dal container di Jellyfin: sul seedbox è quello pubblico, `https://<tuo-host>/qbittorrent`, perché dal container `127.0.0.1:17541` è rifiutato. La password non torna mai nelle risposte e non finisce nel registro.
- Le soglie di §4.3.
- Le cartelle da analizzare per Pulizia (`/home/hashvps/downloads`, `/home/hashvps/seedings`, una per riga: `SpaceScanFolders`).
- Il file della quota (`SpaceQuotaFile`).
- Il cestino di Radarr e Sonarr deve restare spento, altrimenti la cancellazione non libera spazio.

### 7.2 Client

- `IArrClient` aggiunge: `DELETE movie/{id}`, `DELETE series/{id}`, `PUT series` (monitoraggio della stagione), `DELETE episodefile/bulk`, e se serve la lettura di tutti i `moviefile`/`episodefile` con dimensioni e percorsi.
- `ISeerrClient` aggiunge la rimozione di un media (oggi legge soltanto). Chi costruisce verifica la chiamata sulla versione del server.
- Nuovo `IQbitClient`: login (cookie `SID`, nuovo login se scade), `torrents/info`, `torrents/files`, `torrents/trackers`, `torrents/delete?deleteFiles=true`.
- Numero di collegamenti e inode dei file: il plugin li legge dal disco con `stat` (§12). La quota viene invece dal file del cron (§5.4).

### 7.3 Servizio e dati

- **Calcolo** in background: il primo 2 minuti dopo l'avvio, poi ogni 24 ore e su richiesta ("ricalcola"). Legge Jellyfin (visione di tutti gli utenti, preferiti, `DateCreated`), Radarr, Sonarr, Seerr, i voti, qBittorrent e il disco. **Il risultato resta in memoria**, non su disco. L'app legge l'ultimo risultato, non aspetta il calcolo. Fino al primo risultato `ScannedAt` è null e `Scanning` è vero; se il primo calcolo fallisce `ScannedAt` resta null e `Scanning` torna falso (l'app mostra "calcolo non riuscito"). Le dimensioni vengono da Radarr (`sizeOnDisk`) e da Sonarr (`statistics.sizeOnDisk`, per stagione `seasons[].statistics.sizeOnDisk`), i percorsi da `movieFile.path` e `episodefile.path`.
- **Chi è "interessato":** gli utenti Jellyfin attivi che hanno aperto il titolo, più chi l'ha chiesto in Seerr (`GetRequestsAsync`, tutte le pagine; il richiedente si riconosce da `RequestedBy.JellyfinUserId`). "Aperto" vuol dire `Played` o `PlaybackPositionTicks > 0` sul film o su almeno un episodio; "finito" vuol dire `Played` sul film, o tutti gli episodi con file visti.
- **Stima:** un torrent che condivide un percorso con un torrent che deve restare non si toglie mai insieme al titolo; quei byte contano come "restano nel pack" (`InPackBytes`).
- **Operazioni:** una alla volta, in coda. Ogni operazione ha un id, i passi e lo stato.
- **Su disco** (`space.json`, come `downloads.json`, file illeggibile spostato in `.bad`): titoli tenuti, torrent in attesa di fine seed, operazioni degli ultimi 30 giorni. Chiavi: `movie:{idRadarr}`, `series:{idSonarr}`, `season:{idSonarr}:{n}`, `torrent:{hash}`, `file:{h}` (16 caratteri esadecimali dello SHA-256 del percorso, per orfani e doppioni), `all-torrents`.
- **Rifare un'operazione** riparte da capo; un 404 di Radarr, Sonarr, qBittorrent o Seerr è "saltato" con `Gone`.

### 7.4 Endpoint (solo admin)

- `GET Space`: quota, divisione, le tre liste, in attesa di fine seed, tenuti, le ultime 20 operazioni, generi, errori per servizio, ora del calcolo.
- `POST Space/Recalculate`: 202.
- `POST Space/Operations` con `{"Kind","Key"}` (film, serie, stagione, torrent, orfano, doppione, "tutti quelli possibili"): 202 con `{"Id"}`. Errori: 400 per corpo o chiave non validi; 404 `Unknown` per una chiave che non è nell'ultimo calcolo; 409 `Busy` se un'operazione sulla stessa chiave è in coda o in corso; 409 `NotReady` prima del primo calcolo.
- `GET Space/Operations/{id}`: passi e stato, per il polling; 404 se non c'è.
- `POST Space/Kept` con `{"Key","Title"}` e `DELETE Space/Kept?key=` per Tienilo (204).
- `DELETE Space/Pending/{hash}` per togliere un torrent dall'attesa (204, 404 se non c'è).
- La funzione `space` compare in `GET Info` subito dopo `downloads`, quando c'è almeno Sonarr o Radarr.

## 8. App: scheda "Spazio"

- Nuova voce `AdminTab.space` accanto a Download. Si nasconde se il plugin non ha la funzione.
- In alto §5.4, poi tre sezioni: Cancellare, Alleggerire, Pulizia. Sotto: In attesa di fine seed, Tenuti, Ultime operazioni. Ogni sezione mostra le prime 20 righe e un "mostra altri".
- Toccando una riga di Cancellare o Alleggerire si apre la scheda del titolo (locandina, trama, generi, trailer, chi l'ha visto e quando, chi l'ha chiesto, voti), con "Elimina", "Tienilo" e, se c'è, "Alleggerisci".
- Conferma: `admin_confirm_dialog.dart` con l'elenco dei passi e i GB.
- Il riquadro di progresso legge `GET Space/Operations/{id}` ogni secondo finché l'operazione non finisce, poi ricarica la scheda.
- Testi in italiano e inglese negli ARB. I pesi sono in GB con due decimali e la virgola, i TB per la quota.

## 9. Attivazione sul server

1. Inserire indirizzo (`https://<tuo-host>/qbittorrent`, raggiungibile dal container di Jellyfin), utente e password di qBittorrent nella configurazione del plugin.
2. Correggere la regola in qui (§6.3, nota).
3. Sul seedbox, un cron che scrive `quota -w` nel file indicato in `SpaceQuotaFile`.
4. Tenere spento il cestino di Radarr e Sonarr.
5. Primo "ricalcola" e controllo delle liste prima di eliminare qualcosa.

## 10. Perimetro

### Incluso

Segnali, tre liste, azioni con progresso, seed obbligatorio con rimozione automatica a fine obbligo, Tienilo, configurazione, scheda Spazio (PC e web).

### Escluso

- Cancellazioni automatiche senza un pulsante premuto dall'admin.
- Una riga "In uscita" o avvisi agli utenti prima di cancellare.
- Un punteggio "ti potrebbe piacere".
- Alleggerire in blocco: si fa titolo per titolo con la ricerca della Spec T.
- Gestire le regole di qui da WonderFlix.
- Anime come categoria a parte: valgono le stesse regole dei film e delle serie.

## 11. Casi limite

- Un torrent con più film o una stagione intera (pack) mentre si cancella solo un episodio o un film: il torrent si toglie solo quando nessuno dei suoi file ha più un hardlink in libreria. Altrimenti resta, e la conferma lo dice ("il pack resta: contiene altri episodi in libreria").
- Lo stesso file in due torrent (cross-seed): sono due torrent con gli stessi file, e lo spazio si libera solo togliendoli entrambi.
- Un titolo che la Spec T sta scaricando o aggiornando (in coda): "Elimina" chiede conferma, e prima toglie il download dalla coda.
- Un utente che ricomincia a guardare un titolo dopo il calcolo: lo si vede al calcolo successivo. La conferma usa i dati del calcolo, con la sua ora.
- Utenti Jellyfin disattivati: non contano negli "interessati".

## 12. Lasciato a chi costruisce

- **Collegare un titolo ai suoi torrent** (fatto): con il numero di device e di inode (`stat --printf "%d\t%i\t%h\t%s\t%n\n"`, a gruppi di 500 percorsi). Jellyfin gira in un container Ubuntu 24.04 che vede `/home/hashvps/{media,downloads,seedings}` con gli stessi percorsi e ha `/usr/bin/stat`; controllato il 2026-10-30, lo stesso file dà gli stessi device e inode da dentro e da fuori.
- **Quota** (fatto): dal file del cron (§5.4, §9), non da `quota` né da `/proc`.
- **Aggiornare Jellyfin dopo una cancellazione** (fatto): `ILibraryManager.QueueLibraryScan()`.
- **Seguito in arrivo** (fatto): la collezione di Radarr, solo film (§4.2), non le collezioni di Jellyfin né il calendario della Spec S.
- Ritmo dei controlli: torrent in attesa ogni ora, operazioni conservate 30 giorni.
