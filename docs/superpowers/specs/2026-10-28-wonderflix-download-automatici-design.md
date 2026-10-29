# WonderFlix — Spec T: download automatici con le regole dell'admin

- **Data:** 2026-10-28
- **Stato:** piani 29a e 29b realizzati (plugin 1.14.0, app 0.23.0, branch `feat/download-automatici`, non ancora rilasciato). Bozza delle schermate: `.superpowers/brainstorm/1831-1793204853/content/download-tab-v2.html` (non nel repo).
- **Ambito:** Spec T. Si appoggia alla Spec M (Sonarr e Radarr nel plugin: `2026-10-10-wonderflix-home-su-misura-design.md`, §7), alla Spec I (richieste con Seerr: `2026-10-05-wonderflix-seerr-design.md`), alla Spec S (calendario: `2026-10-22-wonderflix-calendario-uscite-design.md`) e alla dashboard admin (`2026-10-06-wonderflix-dashboard-admin-design.md`).

## 1. Obiettivo

Oggi l'admin non lascia scaricare Radarr e Sonarr da soli. Per ogni titolo apre la ricerca manuale e sceglie a mano. Ha paura che la ricerca automatica prenda file molto più grandi, o file che lui non avrebbe scelto. Lo fa per tutti i film, e non ricontrolla gli episodi settimanali solo perché non ha tempo.

Con la Spec T **WonderFlix sceglie e scarica al posto suo, con le sue regole**. L'admin non deve più fare niente: vede soltanto cosa è stato scelto e può cambiarlo. È una funzione solo per gli admin; gli utenti non vedono niente di nuovo.

**Nota sul modello.** Non è la ricerca automatica di Radarr e Sonarr con impostazioni diverse. WonderFlix usa la stessa API della **ricerca manuale** (interactive search): chiede a Radarr o Sonarr l'elenco delle release, applica la regola dell'admin (§4) e manda a scaricare quella scelta, esattamente come se l'admin avesse premuto il pulsante di download nella ricerca manuale. Radarr e Sonarr restano chi parla con gli indexer, chi manda a qBittorrent, chi importa e rinomina. Cambia solo **chi sceglie**.

### Perché la ricerca automatica di Radarr non va bene

Controllato il 2026-10-28 rifacendo la ricerca manuale su 5 film che l'admin aveva scelto a mano. Il primo risultato di Radarr è quello che la ricerca automatica prenderebbe:

| Film | Radarr prenderebbe | L'admin ha preso |
|---|---|---|
| Amistad (1997) | 9,47 GB Bluray ITA-ENG, punteggio 150 | lo stesso |
| In the Grey (2026) | 9,71 GB Bluray, 150 | 1,88 GB WEBRip x265, 150 (36° in lista) |
| Firebreak (2026) | 6,93 GB WEB-DL, 150 | 2,46 GB WEBRip x265, 150 (2°) |
| The Breadwinner (2026) | 11 GB Bluray, **punteggio 0** | 1,61 GB WEBRip x265 ITA-ENG, 150 (16°) |
| Animals (2026) | 4,83 GB HEVC HDR, 150 | 2,9 GB x264, 150 (2°); avrebbe preso il WEBRip x265 da 1,89 GB se fosse già uscito |

Radarr ordina prima per **qualità** (nel profilo Bluray-1080p sta sopra il gruppo "WEB 1080p"), poi per punteggio dei custom format; la dimensione quasi non conta. L'admin ordina per **punteggio**, poi per **peso**.

## 2. Situazione di partenza

App 0.22.0, plugin 1.13.0, Sonarr 4.0.20, Radarr 6.4.4, Prowlarr, Seerr. Tutto controllato via API sul server il 2026-10-28.

### Radarr e Sonarr

- **Indirizzi interni** (visti dal server, già configurati nel plugin): Sonarr `127.0.0.1:17526/sonarr`, Radarr `127.0.0.1:17527/radarr`, Prowlarr `127.0.0.1:17524/prowlarr`. Le porte di `config.xml` (8989, 7878) non sono quelle vere: Ultra.cc le cambia. Le voci nginx `sonarr2` e `radarr2` puntano a istanze che non esistono più: da ignorare.
- **Profili di qualità.**
  - Radarr `Main Profile` (id 8): ammessi HDTV-720p, WEB 720p, Bluray-720p, HDTV-1080p, WEB 1080p (WEBDL+WEBRip), Bluray-1080p; cutoff "WEB 1080p"; punteggio minimo −9999, cutoff punteggio 100000 (irraggiungibile), upgrade dal +1.
  - Radarr `Anime Main Profile` (id 7): WEB 720p, WEB 1080p (con HDTV-1080p), Bluray-1080p; tier anime TRaSH.
  - Sonarr `Main Profile` (id 7): HDTV-1080p, WEB 1080p, Bluray-1080p.
  - Sonarr `[Anime] 1080p` (id 8): WEB 720p, WEB 1080p, Bluray-1080p; tier anime TRaSH.
- **Custom format con punteggio.**
  - Main (film e serie): `Language: Italian + English (Dual)` +100, `Language: Prefer Italian` +50, `Language: Not Original or Italian` −10000. Nel Sonarr Main anche `Season Pack` +20, `BR-DISK` e `Sample` −10000. Un file ITA-ENG fa 150, solo ITA 50.
  - Anime: tier BD da 700 a 1400, tier Web da 100 a 600, Remux 925-975, `Anime Dual Audio` +10, versioni v0-v4, streaming (CR, NF, AMZN…) pochi punti, `AV1`, `Dubs Only`, `Anime Raws`, `Anime LQ Groups` −10000.
- **Indexer:** 10 torrent da Prowlarr (Bangumi Moe, CZTeam, ItaTorrents, Knaben, LimeTorrents solo Sonarr, Milkie, Nyaa.si, Shareisland, The Pirate Bay, Uindex). ItaTorrents e Shareisland hanno priorità 20, gli altri 25. RSS, ricerca automatica e ricerca manuale accesi su tutti. Prowlarr sincronizza in `fullSync` con l'app profile "Standard" (RSS acceso): spegnere l'RSS direttamente in Radarr/Sonarr non dura, va spento in Prowlarr. In Prowlarr non ci sono limiti di query impostati.
- **Download client:** qBittorrent (due per app: uno normale e uno per serie o anime). `autoRedownloadFailed` acceso in entrambe le app: quando un download fallisce, Radarr e Sonarr rifanno da soli una ricerca automatica, cioè con la loro logica.
- **Cronologia** (ultimi 300 grab Sonarr, tutti i 265 di Radarr): Radarr 133 da ricerca manuale, 94 da RSS, 38 da ricerca automatica; Sonarr 165 manuali, 135 da RSS. L'RSS oggi scarica già da solo circa il 40%.
- **Libreria:** 824 film (796 con file, circa 3,4 TB, 28 monitorati senza file); 180 serie, 65 in corso, 110 monitorate, 155 episodi monitorati mancanti.
- **API utili, provate:**
  - `GET /api/v3/release?movieId=` (Radarr) e `?episodeId=` / `?seriesId=&seasonNumber=` (Sonarr) fanno la ricerca manuale su tutti gli indexer. Durano da pochi secondi a circa un minuto. Ogni release ha `guid`, `indexerId`, `indexer`, `title`, `size`, `seeders`, `quality`, `customFormatScore`, `customFormats`, `languages`, `rejected`, `rejections` (solo testo), `temporarilyRejected`, `downloadAllowed`, `releaseGroup`, `protocol`.
  - `POST /api/v3/release` con `guid` e `indexerId` manda a scaricare una release dell'ultima ricerca, anche se rifiutata, come il pulsante della ricerca manuale.
  - `GET /api/v3/moviefile?movieId=` e `GET /api/v3/episodefile?seriesId=` danno `customFormatScore`, `size`, `quality` e `languages` del file già scaricato. In `GET /movie` il punteggio del file manca.
  - `GET /api/v3/history?eventType=` per grab e download falliti.
- **Motivi di scarto** più frequenti nelle ricerche fatte: `Existing file on disk has a equal or higher Custom Format score`, `Existing file on disk meets quality cutoff`, `Existing file on disk is of equal or higher preference`, `Not enough seeders`, `<qualità> is not wanted in profile`, `Unable to parse release`, `Unable to match to correct movie`.

### Seerr

- Server `Radarr` (predefinito, Main Profile): `preventSearch: true`. Server `Radarr Anime` (Anime Main Profile, cartella anime): **`preventSearch: false`**, quindi i film anime approvati vengono già cercati e scaricati da Radarr da solo.
- Server `Sonarr`: `preventSearch: true`, ma `activeAnimeProfileName` è "Main Profile": le serie anime chieste da Seerr non ricevono il profilo `[Anime] 1080p`.

### Plugin

- `Home/ArrClient.cs` (`IArrClient`): solo GET, con `X-Api-Key`, timeout di 10 s, errori come `ArrException`. Modelli in `Home/ArrJson.cs`. Impostazioni in `Server/PluginArrSettings.cs` (`IArrSettings`).
- Servizi in background come `ReportsHostedService`, `RatingsHostedService`; dati su disco come `Hub/ReportStore.cs` (`reports.json` nelle configurazioni dei plugin, file illeggibile spostato in `.bad`).
- Le richieste passano ancora da Seerr (`Hub/RequestsService.cs`): quando l'admin approva in WonderFlix, è Seerr ad aggiungere il titolo a Radarr o Sonarr.

### App

- Dashboard admin: `lib/features/admin/`, schede in `admin_navigation.dart` (`AdminTab`: sessions, users, maintenance, activity, wonderflix), pagina `admin_screen.dart`.

## 3. Decisioni

| Tema | Decisione | Di chi |
|---|---|---|
| Chi sceglie | WonderFlix, sempre: prima scelta, attesa, upgrade, episodi settimanali | utente |
| Conferma | nessuna: scarica da solo; l'admin vede le scelte e può cambiarle | utente |
| Regola | punteggio più alto, poi il file più leggero sopra una soglia minima | utente |
| 1080p o 720p | a parità di punteggio vince il 1080p anche se pesa di più; il 720p solo se manca il 1080p | dalle scelte dell'admin (Amistad), confermato con la bozza |
| x265 / gruppo / codec | nessuna preferenza: decide il peso | utente (Animals) |
| Anime | stessa regola, nessun ordine per tier | utente |
| Upgrade | sì: si sostituisce quando esce un file con punteggio più alto | utente |
| Libreria già scaricata | un elenco "Da ripassare"; l'admin la sistema a mano, con calma | utente |
| Schermate | scheda "Download" nella dashboard admin, come la bozza | utente (bozza approvata) |
| Dove gira la logica | nel plugin, in background, anche ad app chiusa | mia |
| RSS di Radarr e Sonarr | spento, perché scarichi solo WonderFlix | mia, conseguenza della prima riga |
| A parità di punteggio, un file più leggero non è un upgrade | così non si scarica di continuo | mia |
| Profili Main | qualità della stessa risoluzione in un solo gruppo, a mano | utente (§12) |
| Download in corso, fermi, "cambia", serie in "Da ripassare" | §5.3a, §5.3b, §8.2, §6 | mie, dopo la revisione |

## 4. La regola di scelta

Si applica a ogni ricerca, di film o di episodio, in tutti i profili, anime compresi.

1. **Candidati.** Le release della ricerca manuale. Si scartano quelle che Radarr o Sonarr rifiutano, **tranne** i rifiuti che confrontano la release con il file già scaricato (`Existing file on disk …`) o con la coda: degli upgrade decide WonderFlix (§5.3). Tutti gli altri rifiuti valgono: qualità non ammessa nel profilo (quindi niente 2160p), seeders sotto il minimo dell'indexer, release non riconosciuta o di un altro titolo, blocklist, punteggio sotto il minimo del profilo (la lingua sbagliata fa −10000).
2. **Peso minimo.** Si scartano le release sotto **0,8 GB all'ora** di durata (durata del film da Radarr, `runtime`; dell'episodio dalla serie di Sonarr). Le scelte dell'admin vanno da circa 1 a 3,7 GB all'ora. Se la durata manca: 100 minuti per un film, 40 per un episodio.
3. **Punteggio minimo per scaricare da solo.** Per profilo, nella configurazione (§7.1). Valori iniziali: 50 nei Main Profile (almeno l'italiano riconosciuto), 1 negli anime. Se il miglior candidato è sotto, WonderFlix non scarica e il titolo va in "Serve te" (§5.5).
4. **Ordine:**
   1. punteggio (`customFormatScore`), dal più alto;
   2. risoluzione: 1080p prima di 720p;
   3. peso, dal più leggero;
   4. a parità di file (la stessa release su più indexer): più seeders, poi priorità dell'indexer.
5. Il primo è la scelta.

La regola è una funzione pura, con i suoi test: dato l'elenco delle release, la durata e le soglie, restituisce la scelta, gli scartati con il motivo e il motivo per cui la scelta ha vinto.

## 5. Il ciclo

### 5.1 Cosa cerca

Ogni giro WonderFlix legge:

- i film **monitorati senza file** di Radarr che sono già disponibili (`isAvailable`: rispetta la "minimum availability" di Radarr, quindi nessuna ricerca prima dell'uscita);
- gli episodi **monitorati mancanti** di Sonarr già andati in onda;
- i titoli scaricati da WonderFlix che stanno ancora aspettando un upgrade (§5.3).

Così si prende tutto quello che entra in Radarr e Sonarr, comunque sia entrato: da una richiesta approvata in WonderFlix, da Seerr, a mano. Quando l'admin approva una richiesta in WonderFlix, la ricerca di quel titolo parte subito, senza aspettare il giro.

### 5.2 Quando ricerca

Per un titolo senza un file valido, contando da quando è disponibile (film) o da quando è andato in onda (episodio):

- primi 7 giorni: ogni 6 ore;
- fino a 30 giorni: una volta al giorno;
- dopo: una volta alla settimana.

Le ricerche sono una alla volta, con una pausa tra l'una e l'altra, per non pesare sugli indexer.

### 5.3 Upgrade

- Dopo un download di WonderFlix, se il file ha un punteggio sotto l'**obiettivo** del profilo, il titolo resta tra quelli da ricercare per 30 giorni con lo stesso ritmo di §5.2.
- Obiettivo iniziale: 150 nei Main Profile (ITA-ENG). Negli anime non c'è un massimo sensato: l'obiettivo resta vuoto e si ricerca per 30 giorni.
- Si scarica un upgrade solo se la nuova scelta ha un **punteggio più alto** del file presente. Un file più leggero con lo stesso punteggio non basta.
- Dopo un import normale (non un upgrade) il punteggio del file è quello della release scaricata, già noto: per questa decisione il file non si rilegge (la lista "Da ripassare" invece legge i file, §6).
- Un upgrade finito si conferma leggendo il file (`moviefile`/`episodefile`): se non è più quello di prima (stesso punteggio e stessa qualità), è importato e il suo punteggio diventa quello attuale. Se è ancora quello di prima, l'upgrade è fallito e il titolo torna a guardare gli upgrade, con la finestra di 30 giorni che aveva.
- Dopo i 30 giorni, un titolo ancora sotto l'obiettivo passa in "Da ripassare" (§6).
- Radarr e Sonarr importano il nuovo file solo se lo considerano un upgrade. Con i profili di oggi un WEBRip 150 non sostituisce un Bluray 0, perché il Bluray sta più in alto in qualità. Vedi §9, punto 4.

### 5.3a Mentre scarica (mia scelta)

- Un titolo con un download nella coda di Radarr/Sonarr (`GET /api/v3/queue`), chiunque l'abbia fatto partire (WonderFlix, l'admin, l'RSS prima di spegnerlo), **non si ricerca**: si aspetta l'import.
- Un download fermo conta come fallito. È fermo solo se la coda dice "downloading" e `sizeleft` non cambia da 24 ore: un torrent lento ma vivo no, e nemmeno uno in coda, in pausa o con il client irraggiungibile (il tempo riparte). I seeders non si leggono. WonderFlix lo toglie dalla coda e da qBittorrent con la blocklist (`DELETE /api/v3/queue/{id}?removeFromClient=true&blocklist=true`) e al giro dopo passa alla scelta successiva.
- Un download che sparisce dalla coda senza che Radarr/Sonarr abbiano il file conta come fallito, e si riparte allo stesso modo: Radarr e Sonarr mettono già in blocklist la release fallita, quindi non si legge la cronologia. Un upgrade fermo o fallito torna a guardare gli upgrade (§5.3), non in attesa.
- Un download finito che Radarr/Sonarr non importano (per esempio "non è un upgrade") non si riscarica: il titolo va in "Serve te" con il motivo.

### 5.3b Upgrade che Radarr e Sonarr non importerebbero (mia scelta)

- WonderFlix scarica **da solo** un upgrade solo se Radarr/Sonarr lo importerebbero: punteggio più alto **e** qualità non più bassa nell'ordine del profilo. Con i profili di oggi un WEBRip 150 non sostituisce un Bluray 0, e un 720p 150 non sostituisce un 1080p 50. Questi casi non si scaricano da soli: vanno in "Da ripassare", dove decide l'admin.
- Quando invece è l'admin a scegliere un file che Radarr/Sonarr non importerebbero, la conferma lo dice. Dopo il download WonderFlix fa l'import manuale con sostituzione (`manualimport`), come si fa a mano nella schermata di import di Radarr. Chi costruisce verifica che l'API lo permetta sulle versioni del server; se non lo permette, il pulsante resta solo per i file che Radarr/Sonarr importano.
- Con i profili uniti per risoluzione (§12) restano fuori quasi solo i passaggi da 1080p a 720p.
- "Lo importerebbero?" si decide con la posizione della qualità nel profilo (gli `items` ammessi, dal più basso al più alto; un gruppo è una posizione sola): importano se la posizione nuova è più alta, o uguale con punteggio più alto.
- Se l'import manuale con sostituzione fallisce, il titolo va in "Serve te" con il motivo `ImportBlocked`.

### 5.4 Stagioni intere

Se mancano tutti gli episodi andati in onda di una stagione finita, WonderFlix fa prima la ricerca della stagione. Prende il pack se vince con la regola e se pesa al massimo il 20% in più della somma dei migliori episodi singoli; altrimenti scarica gli episodi uno per uno. Per le serie in corso cerca episodio per episodio.

Come è fatto:

- Pack e singoli vengono dalla stessa ricerca di stagione di Sonarr, senza ricerche in più. I singoli si raggruppano per episodio e di ognuno si tiene il migliore con la regola. La somma si confronta con il pack solo se ogni episodio mancante ha un singolo.
- Se la ricerca di stagione non dà nessun pack valido, o il pack non conviene, la voce di stagione si divide per sempre in voci di episodio, da cercare subito.
- Una stagione con qualcosa in coda, o con una scelta di WonderFlix negli ultimi 90 giorni, non si raggruppa: si cerca episodio per episodio.

### 5.5 Quando non trova niente o qualcosa va storto

- Nessun candidato valido: il titolo resta "In attesa" con la prossima ricerca. Dopo 7 giorni dalla disponibilità senza niente, o se ci sono risultati ma tutti sotto il punteggio minimo, compare anche in **"Serve te"**.
- Una ricerca o un download che falliscono per rete o timeout (indexer o servizio in errore): il titolo mostra il motivo `SearchFailed` ("ricerca non riuscita") e si riprova dopo 15 minuti, così non occupa sempre i primi posti del giro.
- Il client di download rifiuta la release scelta (Radarr/Sonarr rispondono con un errore 5xx al grab, per esempio il torrent è già in qBittorrent): il titolo va in **"Serve te"** con il motivo `GrabRefused` (un upgrade resta in `UpgradeWatch`, con lo stesso motivo) e si riprova al ritmo lento di §3, non ogni 15 minuti. Dall'app si risolve con "Guarda" (per esempio scegliendo un'altra release).
- Download fallito (sparito dalla coda senza file, §5.3a): la release è in blocklist e WonderFlix riprende dalla scelta successiva al prossimo giro. Il "riscarica i falliti" di Radarr e Sonarr va spento (§9), altrimenti scelgono loro.
- Radarr, Sonarr o un indexer non rispondono: il giro salta quel titolo e riprova al successivo; la scheda Download lo mostra.
- Un titolo eliminato o smesso di monitorare in Radarr/Sonarr esce dal ciclo.

### 5.6 Interruttore

Nella configurazione c'è "Download automatici" (spento all'installazione). Spento, WonderFlix non scarica niente da solo, ma la scheda Download funziona: ricerca manuale con la regola e "Da ripassare". Così l'admin può provare la regola prima di accenderla e di spegnere l'RSS.

## 6. Da ripassare

- Un elenco dei film e degli episodi già scaricati con punteggio **sotto l'obiettivo** del profilo (`moviefile`/`episodefile`), più quelli usciti dagli upgrade automatici dopo 30 giorni. Prima i punteggi più bassi, poi i file più grandi. I profili anime non hanno un obiettivo, quindi i loro titoli non compaiono mai in "Da ripassare", nemmeno a fine finestra degli upgrade.
- WonderFlix non ricerca da solo questi titoli. L'admin apre un titolo, vede la ricerca con la regola (§8.3) e decide. Un titolo sistemato, o che l'admin segna "va bene così", esce dall'elenco.
- L'elenco si ricalcola una volta al giorno, non a ogni apertura (796 film e migliaia di episodi).
- Le serie (mia scelta): una riga per serie, che si apre nelle stagioni. Ricerca, "scarica" e "va bene così" lavorano per stagione (ricerca della stagione, poi episodi singoli come in §5.4). Il punteggio della stagione è quello del suo episodio peggiore.

## 7. Plugin

### 7.1 Configurazione

Nella pagina di configurazione del plugin, accanto a Sonarr e Radarr:

- "Download automatici" acceso/spento (spento);
- peso minimo in GB all'ora (0,8);
- per ogni profilo di qualità di Radarr e Sonarr (letti dalle API): punteggio minimo per scaricare da solo e obiettivo per gli upgrade, con i valori di §4 e §5.3.
- Si salva una regola solo per i profili che l'admin ha cambiato (o che ne avevano già una). Gli altri restano senza riga e valgono i valori predefiniti: profilo con "anime" nel nome, minimo 1 e nessun obiettivo; altrimenti minimo 50 e obiettivo 150. Le regole dei profili non mostrati (servizio giù) restano.

### 7.2 Client

`IArrClient` aggiunge la ricerca manuale (`GET release`), il download di una release (`POST release`), i film disponibili senza file, gli episodi mancanti, i file con il loro punteggio (`moviefile`, `episodefile`), i profili di qualità, l'episodio (`episode/{id}`), la coda (`GET queue`, `DELETE queue/{id}`) e l'import manuale (`manualimport`). La cronologia (`history`) non si usa (§5.3a). La ricerca ha un timeout suo, più lungo dei 10 s di oggi.

### 7.3 Servizio e dati

- Un servizio in background fa il ciclo di §5, un titolo alla volta.
- Su disco (`downloads.json`, come `reports.json`): per ogni titolo seguito lo stato (in attesa, scaricato, in upgrade, serve te, va bene così), le ultime ricerche, la scelta, le stagioni divise in episodi. Le alternative e gli scarti con il motivo non si salvano: vengono dalla ricerca dal vivo. La storia delle scelte si tiene per 90 giorni.

### 7.4 Endpoint (solo admin)

- elenco "Scelte automatiche", "In attesa", "Serve te", "Da ripassare";
- ricerca di un titolo con la regola applicata (risultato ordinato con i motivi);
- scarica una release scelta dall'admin ("cambia" o ricerca a mano). Oltre a 409 `Expired` (la release non c'è più), risponde 409 `Busy` (un altro download dello stesso titolo è in corso, dal giro o da un altro admin) e 503 `Unavailable` (Radarr o Sonarr non rispondono), più 502 `Refused` (Radarr o Sonarr hanno risposto con un errore, per esempio il client di download rifiuta il torrent);
- segna "va bene così";
- forza una ricerca subito.

Come gli altri endpoint della dashboard: solo gli admin di Jellyfin; mai le chiavi API nelle risposte o nel registro.

## 8. App: scheda "Download"

Nuova voce `AdminTab.downloads` nella dashboard admin, tra Attività e WonderFlix. Le schermate seguono la bozza approvata.

### 8.1 Panoramica

Tre sezioni, più "Serve te" in evidenza quando non è vuota:

- **Scelte automatiche** (ultimi 7 giorni, poi "mostra altri"): titolo, release scelta, peso, punteggio, indexer, quando; un segno "upgrade" con il prima e dopo. Pulsante "cambia".
- **In attesa:** titolo, quando esce o da quanto si cerca, prossima ricerca e il motivo, se c'è. Quelli in "Serve te" hanno il pulsante "guarda".
- **Da ripassare:** titolo, punteggio e peso del file attuale; pulsante "apri".

Ogni sezione mostra le prime righe; "mostra altri" estende. Scelte automatiche: 7 giorni, poi tutte quelle che il plugin conserva (90 giorni). Da ripassare: 50 righe, poi altre 50. La panoramica si ricarica ogni 60 s con la scheda aperta e subito dopo ogni azione. Gli errori di Sonarr e Radarr compaiono come nota in cima alla scheda, senza nascondere il resto.

### 8.2 Ricerca di un titolo

Si apre da "cambia", "guarda" o "apri". È una schermata a tutto schermo sopra la dashboard, non una route, e si apre solo dalle righe della scheda. Il perché della scelta lo compone l'app dai dati (il plugin non manda testi).

- In alto: titolo, durata, file attuale (peso e punteggio), quanti risultati validi, "ricerca di nuovo".
- L'elenco ordinato con la regola, con la scelta di WonderFlix evidenziata e il perché ("più leggero dei 150 in 1080p"). Ogni riga ha release, punteggio, peso, seeders, indexer e "scarica".
- Sotto, in grigio, gli scartati con il motivo ("non in italiano", "0,6 GB/ora, sotto la soglia", "qualità non ammessa").
- Per i titoli in "Da ripassare", anche "va bene così".
- Scaricare un file con punteggio più basso o uguale a quello presente chiede conferma; lo stesso se Radarr o Sonarr non importerebbero la release. Il testo dice quale dei due casi è.
- **"cambia"** (mia scelta): se la scelta precedente è ancora in coda, WonderFlix la toglie dalla coda e da qBittorrent (senza blocklist) e scarica la nuova, così non arrivano due copie. Se è già importata, la nuova è un upgrade scelto dall'admin (§5.3b).

### 8.3 Testi

Italiano e inglese negli ARB, come il resto della dashboard. I pesi sono in GB con due decimali e la virgola, come nel dettaglio media.

## 9. Attivazione sul server

Da fare a mano, nell'ordine, quando l'admin decide di accendere i download automatici. Vanno nel README del plugin.

1. Provare la regola con l'interruttore spento (§5.6) su qualche titolo.
2. **Prowlarr → Settings → Apps → Sync Profiles → "Standard"**: spegnere "Enable RSS". Lasciare accese ricerca automatica e manuale (la ricerca manuale serve a WonderFlix). Controllare che in Radarr e Sonarr gli indexer risultino senza RSS dopo la sincronizzazione.
3. **Radarr e Sonarr → Settings → Download Clients**: spegnere "Redownload Failed" e "Redownload Failed from Interactive Search".
4. **Profili di qualità** (decisione dell'utente, §12): perché Radarr e Sonarr accettino come upgrade un file con punteggio più alto ma di qualità più bassa (WEBRip 150 al posto di Bluray 0), i 1080p del Main Profile vanno messi in un solo gruppo (HDTV-1080p, WEB 1080p, Bluray-1080p), lo stesso per i 720p. Così dentro la stessa risoluzione decide il punteggio, come nella regola di WonderFlix.
5. **Seerr**: sul server "Radarr Anime" accendere "prevent search"; facoltativo, su Sonarr mettere `[Anime] 1080p` come profilo anime.
6. Accendere "Download automatici".

## 10. Perimetro

### Incluso

Regola di §4, ciclo di §5, "Da ripassare", configurazione, scheda Download (PC e web, come il resto della dashboard), istruzioni di §9.

### Escluso

- Cambiare da WonderFlix le impostazioni di Radarr, Sonarr, Prowlarr o Seerr: si fanno a mano (§9).
- Usenet, 4K, istanze in più di Radarr/Sonarr.
- Notifiche push o Discord per le scelte: le scelte si guardano nella scheda Download. "Serve te" si vede solo lì.
- Ricerche automatiche sulla libreria già scaricata.
- Togliere Seerr dal flusso delle richieste.

## 11. Casi limite

- Lo stesso film in più versioni sul tracker con nomi diversi: conta il file, non il nome; a parità di peso vince chi ha più seeders.
- Un titolo con release solo in 2160p o solo in inglese: nessun candidato valido, quindi "In attesa" e poi "Serve te".
- Una serie in corso con un pack parziale della stagione: non si prende, per le serie in corso si cercano solo episodi singoli (§5.4).
- L'admin scarica a mano da Radarr o Sonarr: WonderFlix vede il file al giro dopo e tratta il titolo come gli altri (upgrade compresi solo se l'ha scaricato WonderFlix; altrimenti finisce in "Da ripassare" se è sotto l'obiettivo).
- I risultati di una ricerca in Radarr/Sonarr scadono dopo circa 30 minuti: se "scarica" arriva più tardi, WonderFlix rifà la ricerca e scarica la stessa release, se c'è ancora.
- L'interruttore spento a metà di un ciclo: il giro finisce il titolo in corso e si ferma.

## 12. Profili di qualità

Deciso dall'utente il 2026-10-28: nei Main Profile di Radarr e Sonarr le qualità della stessa risoluzione si uniscono in un solo gruppo (§9 punto 4), a mano, all'attivazione. Dopo la modifica, dentro la stessa risoluzione Radarr e Sonarr importano ogni file con punteggio più alto, quindi gli upgrade automatici di §5.3b coprono quasi tutti i casi. Restano fuori solo i passaggi da 1080p a 720p, che vanno in "Da ripassare". Il controllo di §5.3b ("lo importerebbero?") resta comunque, per i profili anime e per il caso in cui la modifica non sia ancora fatta.

## 13. Lasciato a chi costruisce

- Come riconoscere i rifiuti "file già presente" e "in coda" (solo testo nelle API): l'elenco del §2 è il punto di partenza; verificarlo sulle versioni del server.
- Come ottenere la somma dei migliori episodi singoli per il confronto con il pack (§5.4).
- Il ritmo esatto del giro, la pausa tra le ricerche, il timeout della ricerca.
- Versioni di plugin e app, divisione in piani (plugin poi app, come nelle spec precedenti).
