# WonderFlix — Spec U: spazio sul seedbox

- **Data:** 2026-10-30
- **Stato:** design, da approvare.
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
- **Raccomandazioni:** sono consigli tra amici, non un punteggio. Il plugin non sa niente di saghe o seguiti, a parte le collezioni (BoxSet) di Jellyfin.
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

- **Nessuno lo guarda più.** Qualcuno l'ha aperto, e nessuno lo apre da almeno *N mesi*, che l'abbia finito o no. La frase dice come stanno le cose: "visto da tutti", "abbandonato da tutti" oppure "visto da Anna, abbandonato da Luca", con la data dell'ultima visione. "Finito" per la serie e la stagione: tutti gli episodi visti (`HasWatched` della Spec dei voti). Chi ha chiesto il titolo e non l'ha mai aperto conta tramite la "richiesta recente" (§4.2).
- **Mai aperto.** Nessuno l'ha mai aperto da *N mesi* dall'aggiunta (`DateCreated` di Jellyfin).
- **Voti bassi.** Media dei voti ≤ 2 su 5, con almeno 2 voti.
- **Serie conclusa.** Sonarr `status = ended` e nessuno la guarda più. **Stagioni vecchie**: in una serie in corso, una stagione che nessuno guarda più.

### 4.2 Segnali "tienilo"

Non tolgono il titolo dalla lista, ma lo spostano in fondo con un'etichetta:

- **Visione in corso.** Qualcuno è a metà (posizione > 0 o serie con episodi visti e non visti) e l'ha aperta negli ultimi *N mesi*.
- **Richiesta recente.** Chi l'ha chiesto non l'ha ancora visto, e la richiesta ha meno di *M giorni*.
- **Voti alti.** Media ≥ 4.
- **Seguito in arrivo.** Il titolo è in una collezione (BoxSet) di Jellyfin con un altro titolo in uscita nel calendario (Spec S). Se il calendario non dà questo legame, il segnale non c'è (§12).

Questi invece **tolgono** il titolo dalle liste:

- **Tenuto.** L'admin ha premuto "Tienilo" (§6.4).
- **Preferito.** È tra i preferiti Jellyfin dell'admin che guarda la lista.

### 4.3 Valori iniziali

Nella configurazione del plugin, nella sezione Spazio:

- *N* (mesi senza aperture per "nessuno lo guarda più", "mai aperto", "stagioni vecchie"): 6;
- *M* (giorni di grazia di una richiesta): 60;
- voti bassi ≤ 2, alti ≥ 4, minimo 2 voti;
- soglia "pesante" per Alleggerire: 4 GB all'ora (le scelte dell'admin nella Spec T vanno da 1 a 3,7);
- tracker con seed obbligatorio: `itatorrents.xyz`, `shareisland.org`; ratio 10; giorni 30.

### 4.4 Etichetta "generi che guardi spesso"

I 3 generi più frequenti tra i titoli che l'admin ha visto o votato ≥ 4. Se un candidato ne ha almeno uno, mostra l'etichetta. Non cambia l'ordine.

## 5. Le liste

### 5.1 Cancellare

Film, serie e stagioni con almeno un segnale "via". Ogni riga mostra locandina, titolo, GB, i segnali in frasi ("visto da tutti, ultima visione 8 mesi fa", "voto medio 2/5") e i segnali "tienilo" come etichette. Due numeri: **GB liberati subito** e **GB liberati dopo il seed** (§6.3), con la data prevista.

Una serie compare una volta sola. Se è candidata tutta intera, la riga è la serie. Altrimenti la riga è la serie con le sole stagioni candidate, che si aprono sotto.

### 5.2 Alleggerire

Film ed episodi il cui file supera la soglia di GB all'ora (§4.3), ordinati per GB in eccesso rispetto alla soglia. Esclusi i titoli già in Cancellare. "Alleggerisci" apre la pagina di ricerca della Spec T (§8.2 della Spec T) su quel titolo. L'admin sceglie una release più leggera, e la Spec T la scarica e la sostituisce (import manuale con sostituzione, §5.3b della Spec T). Il vecchio torrent resta e compare poi in Pulizia.

Il file più leggero ha quasi sempre un punteggio o una qualità più bassi, quindi per la Spec T sarebbe sotto l'obiettivo, e gli upgrade automatici o "Da ripassare" riporterebbero un file pesante. Per evitarlo, un download partito da "Alleggerisci" segna il titolo **"va bene così"** nella Spec T (`downloads.json`), come se l'admin l'avesse premuto in "Da ripassare". Gli upgrade automatici non lo toccano più. La chiamata di download della Spec T riceve per questo un'indicazione in più ("da Spazio").

### 5.3 Pulizia

Spazio che non serve a nessuno, senza decidere sul contenuto:

- **Torrent senza copia in libreria.** Torrent in qBittorrent i cui file non hanno un hardlink in libreria. Si vede dal numero di collegamenti del file (1 = solo il torrent). Per ogni torrent: nome, tracker, GB, ratio, giorni di seed. Ci sono due gruppi: "si possono togliere ora" e "in seed obbligatorio fino al …" (§6.3).
- **File fuori dai torrent e fuori da Radarr/Sonarr.** File video sopra i 100 MB in `downloads` o `seedings` che non appartengono a nessun torrent di qBittorrent.
- **Doppioni.** Lo stesso film o episodio con più file in libreria (Radarr/Sonarr ne conoscono uno, l'altro è in più nella cartella).

C'è anche un pulsante "Togli tutti quelli possibili ora". Riguarda **solo i torrent** che si possono togliere ora, e la conferma dice quanti sono e quanti GB. File orfani e doppioni si cancellano uno alla volta, perché il plugin li toglie direttamente dal disco.

### 5.4 In alto

- Quota: usati, totale, liberi (`quota` del seedbox).
- Divisione: film, serie, anime, solo torrent, altro.
- "Liberabili ora" e "liberabili dopo il seed" per ogni lista.
- I dati hanno l'ora dell'ultimo calcolo e un pulsante "ricalcola" (§7.3).

## 6. Le azioni

### 6.1 Come si vedono

Ogni pulsante apre prima una **conferma** con i passi che verranno fatti e i GB attesi (subito e dopo il seed). Poi apre un **riquadro di progresso** con i passi. Ogni passo ha uno stato: in attesa, in corso, fatto, saltato con il motivo, fallito con il motivo. Al primo passo fallito l'operazione si ferma e i passi dopo restano "non fatti". Alla fine il riquadro mostra i GB liberati davvero (quota prima e dopo) e quelli in attesa del seed.

Le operazioni girano nel plugin. Se l'admin chiude il riquadro o l'app, l'operazione continua. Le ultime operazioni si rivedono in fondo alla scheda (sono conservate per 30 giorni).

### 6.2 I passi

**Film:**
1. trova i torrent del film in qBittorrent (vedi §12);
2. rimuove il film da Radarr con i file (`DELETE movie/{id}?deleteFiles=true`, senza esclusione);
3. per ogni torrent: se si può togliere ora lo toglie con i file, altrimenti lo mette in attesa di fine seed (§6.3);
4. toglie il media da Seerr, così torna richiedibile e le vecchie richieste non contano più;
5. aggiorna la libreria di Jellyfin;
6. legge la quota.

Se Seerr non è configurato, il passo 4 viene saltato con il motivo.

**Serie intera:** come il film, con Sonarr (`DELETE series/{id}?deleteFiles=true`).

**Stagione:**
1. trova i torrent degli episodi della stagione;
2. smette di monitorare la stagione in Sonarr;
3. cancella i file degli episodi della stagione (`DELETE episodefile/bulk`);
4. torrent, libreria e quota come sopra. Su Seerr non si fa niente: la serie resta.

**Torrent (Pulizia):** toglie il torrent con i file, poi legge la quota. Se in quel momento è ancora in seed obbligatorio, il passo viene saltato con il motivo.

**File orfano (Pulizia):** cancella il file e la cartella se resta vuota, poi legge la quota.

**Doppione (Pulizia):** cancella il file che Radarr/Sonarr non conoscono.

### 6.3 Seed obbligatorio

- Un torrent di un tracker della lista (§4.3) si può togliere solo se ha finito di scaricare **e** ha ratio ≥ 10 **oppure** almeno 30 giorni di seed (`seeding_time` di qBittorrent). Tag e categoria non contano. Il tracker si riconosce dal dominio degli annunci del torrent.
- Gli altri torrent si possono togliere subito.
- Un torrent in attesa resta in `space.json` (§7.3). Un servizio in background lo controlla ogni ora e lo toglie con i file quando la regola lo permette. Lo spazio si libera allora. La data prevista mostrata è la data in cui scadono i 30 giorni.
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

- qBittorrent: indirizzo (`http://127.0.0.1:17541`), utente, password. La password non torna mai nelle risposte e non finisce nel registro.
- Le soglie di §4.3.
- Le cartelle da analizzare per Pulizia (`~/downloads`, `~/seedings`).

### 7.2 Client

- `IArrClient` aggiunge: `DELETE movie/{id}`, `DELETE series/{id}`, `PUT series` (monitoraggio della stagione), `DELETE episodefile/bulk`, e se serve la lettura di tutti i `moviefile`/`episodefile` con dimensioni e percorsi.
- `ISeerrClient` aggiunge la rimozione di un media (oggi legge soltanto). Chi costruisce verifica la chiamata sulla versione del server.
- Nuovo `IQbitClient`: login (cookie `SID`, nuovo login se scade), `torrents/info`, `torrents/files`, `torrents/trackers`, `torrents/delete?deleteFiles=true`.
- Lettura della quota e del numero di collegamenti dei file: il plugin gira sul seedbox come l'utente, quindi legge il disco direttamente (§12).

### 7.3 Servizio e dati

- **Calcolo** in background, una volta al giorno e su richiesta ("ricalcola"). Legge Jellyfin (visione di tutti gli utenti, preferiti, `DateCreated`), Radarr, Sonarr, Seerr, i voti, qBittorrent e il disco. Salva il risultato. L'app legge l'ultimo risultato, non aspetta il calcolo.
- **Operazioni:** una alla volta, in coda. Ogni operazione ha un id, i passi e lo stato.
- **Su disco** (`space.json`, come `downloads.json`, file illeggibile spostato in `.bad`): ultimo calcolo, titoli tenuti, torrent in attesa di fine seed, operazioni degli ultimi 30 giorni.

### 7.4 Endpoint (solo admin)

- `GET Space`: quota, divisione, le tre liste, in attesa di fine seed, tenuti, ultime operazioni, ora del calcolo.
- `POST Space/Recalculate`.
- `POST Space/Operations` con tipo (film, serie, stagione, torrent, orfano, doppione, "tutti quelli possibili") e chiave: risponde con l'id dell'operazione. Errori: 409 `Busy`, 503 `Unavailable`.
- `GET Space/Operations/{id}`: passi e stato, per il polling.
- `POST`/`DELETE Space/Kept/{key}` per Tienilo.
- `DELETE Space/Pending/{hash}` per togliere un torrent dall'attesa.

## 8. App: scheda "Spazio"

- Nuova voce `AdminTab.space` accanto a Download. Si nasconde se il plugin non ha la funzione.
- In alto §5.4, poi tre sezioni: Cancellare, Alleggerire, Pulizia. Sotto: In attesa di fine seed, Tenuti, Ultime operazioni. Ogni sezione mostra le prime 20 righe e un "mostra altri".
- Toccando una riga di Cancellare o Alleggerire si apre la scheda del titolo (locandina, trama, generi, trailer, chi l'ha visto e quando, chi l'ha chiesto, voti), con "Elimina", "Tienilo" e, se c'è, "Alleggerisci".
- Conferma: `admin_confirm_dialog.dart` con l'elenco dei passi e i GB.
- Il riquadro di progresso legge `GET Space/Operations/{id}` ogni secondo finché l'operazione non finisce, poi ricarica la scheda.
- Testi in italiano e inglese negli ARB. I pesi sono in GB con due decimali e la virgola, i TB per la quota.

## 9. Attivazione sul server

1. Inserire utente e password di qBittorrent nella configurazione del plugin.
2. Correggere la regola in qui (§6.3, nota).
3. Primo "ricalcola" e controllo delle liste prima di eliminare qualcosa.

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

- **Collegare un titolo ai suoi torrent.** Si può partire dal numero di inode del file in libreria e confrontarlo con i file dei torrent, oppure dalla cronologia di Radarr/Sonarr (`downloadId` = hash del torrent). Verificare quale funziona sui file vecchi.
- **Leggere il numero di collegamenti e l'inode da .NET** (`stat`/`lstat` via P/Invoke o `Mono.Unix`), e la quota (`quota -s` o `/proc`) sul seedbox.
- **Aggiornare Jellyfin dopo una cancellazione:** scansione della cartella o della libreria intera.
- **Seguito in arrivo:** come legare le collezioni di Jellyfin al calendario della Spec S. Se non è affidabile, lasciarlo fuori e dirlo.
- Ritmo esatto dei controlli, timeout, dimensione delle pagine.
