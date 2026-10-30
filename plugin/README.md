# WonderFlix Watch Party (plugin di Jellyfin)

Plugin del server Jellyfin per il watch party di WonderFlix (spec E,
`docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`):
dice chi ha agito, porta la chat e le reazioni tra i membri di un gruppo
SyncPlay e tiene la lista amici (spec F,
`docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`)
e la cassetta delle notifiche (spec G,
`docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`). Dalla
1.3.0 dice anche chi ha cambiato la coda del gruppo (spec H,
`docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md`).
Dalla 1.4.0 fa da tramite verso Seerr per chiedere film e serie dall'app
(spec I, `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md`).
Dalla 1.5.0 dà le saghe (le collezioni di Jellyfin) e le immagini degli
altri utenti (spec K,
`docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md`).
Dalla 1.6.0 porta il recupero della password con un codice su Discord o per
email (spec L,
`docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md`).
Dalla 1.7.0 dà la Home dell'admin (quali righe vede ogni utente nella Home
dell'app) e le uscite in arrivo da Sonarr e Radarr (spec M,
`docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md`).
Dalla 1.8.0 tiene i consigli tra amici: un utente consiglia un film o una serie ai suoi amici, che lo trovano nella cassetta e nella riga "Consigliati per te" della Home (spec N, `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md`).
Dalla 1.9.0 mostra agli amici cosa si sta guardando in WonderFlix e i titoli visti negli ultimi 30 giorni, con un interruttore per non mostrarlo (spec O, `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md`).
Dalla 1.10.0 c'è il match del film: gli amici in una sala votano sì o no su una pila di titoli e partono in un party privato con quelli che piacciono a tutti (spec P, `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md`).
Dalla 1.11.0 ci sono i voti degli amici: a fine film nel watch party ognuno vota da 1 a 10, i voti si scoprono tutti insieme, e nella scheda restano la media e i commenti degli amici (spec Q, `docs/superpowers/specs/2026-10-20-wonderflix-voti-amici-design.md`).
Dalla 1.12.0 ci sono le segnalazioni: chi trova un problema su un titolo lo segnala, gli admin ricevono una notifica e la chiudono, e chi ha segnalato riceve l'esito; in più admin e utenti con la spunta sottotitoli di Jellyfin cercano, scaricano e caricano sottotitoli (spec R, `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md`).
Dalla 1.14.0 ci sono i download automatici: il plugin cerca i film e gli episodi che mancano in Radarr e Sonarr e scarica la release migliore con una regola sua, e gli admin vedono e correggono le scelte dalla scheda Download dell'app. Una release rifiutata dal client di download va in "Serve te" e si riprova al ritmo lento (spec T, `docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md`).
Dalla 1.16.0 c'è la sezione Spazio: il plugin incrocia visioni, richieste, voti e torrent per proporre cosa cancellare sul seedbox, e fa il lavoro quando l'admin preme il pulsante (spec U, `docs/superpowers/specs/2026-10-30-wonderflix-spazio-seedbox-design.md`).
Senza il plugin WonderFlix funziona lo stesso, con gli avvisi
anonimi, senza saghe, con le iniziali al posto delle immagini, senza il
recupero della password, con la Home nell'ordine predefinito e senza le
uscite in arrivo.

- Jellyfin **10.11.x** (net9.0, `targetAbi` 10.11.0.0). Per Jellyfin 12 serve
  una build nuova (net10.0).
- Le impostazioni stanno nella pagina del plugin nella Dashboard (menu
  laterale, sotto Plugin): **Notify new titles** (accesa di default), Seerr, il
  recupero della password, Sonarr e Radarr e i download automatici. La stessa pagina manda
  un **annuncio** a tutti e, con **Send now**, il riepilogo dei nuovi titoli in
  attesa. Endpoint sotto `/WonderFlixWatchParty`; gli eventi arrivano ai client
  come `GeneralCommand` `SendString` con la chiave `WonderFlixWatchParty`.
- **Dati:** amicizie e richieste stanno in
  `plugins/configurations/WonderFlixWatchParty/friends.json` (non nella
  cartella del plugin, che cambia a ogni versione). Un file illeggibile
  diventa `friends.json.bad` e il plugin riparte vuoto.
- **Notifiche:** la cassetta di ogni utente (inviti ai watch party, annunci,
  nuovi titoli) sta in `plugins/configurations/WonderFlixWatchParty/inbox.json`:
  30 giorni, al massimo 100 voci per utente. Un file illeggibile diventa
  `inbox.json.bad`. **Nuovi titoli:** i film e gli episodi aggiunti alla
  libreria si raccolgono in un'ondata che si chiude dopo 15 minuti senza novità
  (al massimo 2 ore); ogni utente riceve i film che può vedere e gli episodi
  delle serie che segue (La mia lista, o un episodio visto o iniziato).
  Se un fornitore di metadati continua a fallire, i titoli senza metadati
  tengono ferma l'ondata fino a 2 ore (poi partono con quello che hanno, ma
  solo agli utenti senza limiti sui contenuti, come con **Send now**).
  Prima di spostare una libreria in un altro percorso spegni **Notify new
  titles**: ogni titolo sembrerebbe nuovo. L'impostazione sta in
  `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`.
- **Party:** l'app registra ogni gruppo con la sua modalità (pubblico, solo
  amici, privato con codice) e chiede al plugin l'elenco già filtrato
  (`GET Parties`). I party stanno in RAM e spariscono con i gruppi SyncPlay.
- **Seerr (dalla 1.4.0):** nella pagina del plugin si mettono l'indirizzo di
  Seerr (come lo vede il server Jellyfin) e la sua chiave API; **Test
  connection** li prova. Con indirizzo e chiave `GET Info` annuncia
  `requests` e l'app mostra le richieste. Il plugin agisce in Seerr per
  conto dell'utente (`X-API-User`) e crea l'account Seerr mancante alla
  prima richiesta. Il **webhook** di Seerr (indirizzo, modello JSON con il
  segreto e i tipi "Request Pending Approval" e "Request Available"
  sono nella stessa pagina) porta nella cassetta "Ora disponibile" a chi ha
  chiesto il titolo e "Nuova richiesta" a chi può approvare. Indirizzo,
  chiave e segreto stanno nella configurazione del plugin, leggibile solo
  dagli admin.
- **Saghe (dalla 1.5.0):** `GET Collections` dà le collezioni di Jellyfin che
  l'utente vede, ognuna con i soli film che vede (le sue librerie e il
  controllo parentale, come `GET /Items`); una collezione senza film visibili
  non compare. Non si salva niente: si legge da Jellyfin a ogni chiamata.
- **Immagini degli utenti (dalla 1.5.0):**
  `GET Users/Avatars?ids=<id,…>&names=<nome,…>` dà id, nome e tag
  dell'immagine dei soli utenti chiesti (al massimo 100 voci, gli utenti
  disattivati no); con id e tag l'app legge l'immagine da `/UserImage`. Un
  nome si cerca senza badare alle maiuscole. **Rischio accettato:** una
  ricerca per nome conferma che un account esiste, anche nascosto. È basso:
  `/Users/Public` elenca già gli utenti non nascosti, e la ricerca degli amici
  trova i nomi per sottostringa.
- **Recupero della password (dalla 1.6.0):** ogni utente collega e verifica
  il suo Discord o la sua email (`Account/Contacts`, con la password attuale e
  un codice a 6 cifre mandato lì: chi ha solo una sessione aperta non può
  cambiare i contatti). Chi dimentica la password chiede un codice dal login
  (`Account/Recovery`, senza accesso: la risposta non dice se l'account
  esiste) e sceglie la password nuova; tutte le sue sessioni si chiudono.
  Gli admin non possono usarlo (possono collegare i contatti, per la
  prova). Nella pagina del plugin: token del bot e id
  del server Discord, server SMTP (STARTTLS, di solito 587), mittente, ogni
  quanti giorni il promemoria nella cassetta a chi non ha contatti (0:
  spento) e **Send a test**. Il bot: Discord Developer Portal → l'app →
  Bot (il token, "Server Members Intent" acceso), poi l'invito nel server
  con lo scope `bot`, senza permessi. I contatti stanno in
  `plugins/configurations/WonderFlixWatchParty/contacts.json` (un file
  illeggibile diventa `contacts.json.bad`); i codici solo in memoria (10
  minuti, 5 tentativi). Gli endpoint dell'admin stanno sotto
  `Account/Admin`.
- **Home (dalla 1.7.0):** `GET Home/Layout` dà la Home dell'admin (gli id
  delle righe accese, in ordine; `null` se mai impostata), `POST Home/Layout`
  la cambia (solo admin, dall'app; gli id sconosciuti si scartano). Le uscite
  in arrivo: `GET Upcoming/Series` (episodi entro N giorni dal calendario di
  Sonarr, non ancora scaricati, con la serie di Jellyfin se l'utente la vede)
  e `GET Upcoming/Movies` (film con l'uscita digitale entro N giorni, da
  Radarr); rispondono sempre 200, con `Error` (`NotConfigured`,
  `Unauthorized`, `Unreachable`) se qualcosa non va. Le risposte restano in
  memoria 15 minuti (gli errori 1 minuto). Nella pagina del plugin: indirizzo
  (con l'UrlBase, es. `https://host/sonarr`) e chiave di Sonarr e Radarr, i
  giorni e **Test connection** (`POST Upcoming/Test`, solo admin). Le chiavi
  non lasciano il server; le immagini sono gli indirizzi pubblici di TVDB e TMDB.
- **Calendario (dalla 1.13.0):** `GET Upcoming/Calendar?start=YYYY-MM-DD&end=YYYY-MM-DD`
  (`end` escluso, al massimo 42 giorni, altrimenti 400) dà gli episodi di
  Sonarr e i film di Radarr del periodo, anche già scaricati, con `OnServer`;
  risponde sempre 200, con `SeriesError` e `MoviesError` se qualcosa non va.
  Le richieste hanno in più le date di uscita (`InCinemas`, `DigitalRelease`,
  `NextAiring` e il numero del prossimo episodio) e lo stato `AwaitingRelease`.
- **Download automatici (dalla 1.14.0):** tutti gli endpoint sono solo per
  l'admin. `GET Downloads` dà la panoramica (`Enabled`, `Recent` le scelte
  degli ultimi 90 giorni, `Waiting` i titoli in attesa o in download, tra cui
  quelli che servono all'admin, `Review` l'elenco da ripassare, `SonarrError`
  e `RadarrError`); `GET Downloads/Search?key=` fa la ricerca dal vivo (fino a
  2 minuti) e dà le release in ordine con quelle scartate (dalla 1.15.0 anche
  `EpisodeChoices`: per una stagione senza un pack conveniente il singolo
  migliore di ogni episodio che manca, o, se non ne manca nessuno, di quelli
  monitorati e già usciti con il file sotto l'obiettivo, con `EpisodeNumber`,
  `Release` (null senza un singolo valido), `WouldImport` e `CurrentScore`
  (il punteggio del file dell'episodio, null senza file); altrimenti la lista è vuota); `POST Downloads/Grab`
  `{Key, Guid, IndexerId}` scarica la release scelta (204; 400 per corpo o
  chiave non validi; 409 `{"Reason":"Expired"}` se la release non c'è più,
  `{"Reason":"Busy"}` se un'altra azione è in corso; 503
  `{"Reason":"Unavailable"}` se Radarr o Sonarr non rispondono; 502
  `{"Reason":"Refused"}` se Radarr o Sonarr hanno risposto con un errore, per
  esempio il client di download ha rifiutato il torrent);
  `POST Downloads/Accept` `{Key}` è "va bene così" (204, 400);
  `POST Downloads/SearchNow` `{Key}` ricerca subito (202, 400);
  `GET Downloads/Profiles` dà i profili di qualità di Radarr e Sonarr con le
  soglie per la pagina del plugin. Le chiavi dei titoli sono `movie:{id}`,
  `episode:{id}` e `season:{idSerie}:{numero}`. Lo stato sta in
  `plugins/configurations/WonderFlixWatchParty/downloads.json` (un file
  illeggibile diventa `downloads.json.bad` e si riparte da vuoto). Nella
  pagina del plugin: l'interruttore, i GB all'ora minimi e il punteggio
  minimo e obiettivo di ogni profilo. Funzione `downloads`, presente con
  almeno uno tra Sonarr e Radarr.
  Con l'interruttore spento WonderFlix segue ancora i download già partiti
  (dalla scheda Download o prima di spegnerlo), ma non cerca e non ne avvia
  di nuovi.
  **Attivazione sul server** (a mano, nell'ordine; l'interruttore resta
  spento finché non sono fatti):
  1. Provare la regola con l'interruttore spento (dalla scheda Download
     dell'app, ricerca su qualche titolo).
  2. **Prowlarr → Settings → Apps → Sync Profiles → "Standard"**: spegnere
     "Enable RSS". Lasciare accese la ricerca automatica e quella manuale (la
     ricerca manuale serve a WonderFlix). Dopo la sincronizzazione controllare
     che in Radarr e Sonarr gli indexer risultino senza RSS.
  3. **Radarr e Sonarr → Settings → Download Clients**: spegnere "Redownload
     Failed" e "Redownload Failed from Interactive Search".
  4. **Profili di qualità**: perché Radarr e Sonarr accettino come upgrade un
     file con punteggio più alto ma di qualità più bassa (un WEBRip 150 al
     posto di un Bluray 0), i 1080p del Main Profile vanno messi in un solo
     gruppo (HDTV-1080p, WEB 1080p, Bluray-1080p), e lo stesso per i 720p.
     Così dentro la stessa risoluzione decide il punteggio, come nella regola
     di WonderFlix.
  5. **Seerr**: sul server "Radarr Anime" accendere "prevent search";
     facoltativo, su Sonarr mettere `[Anime] 1080p` come profilo anime.
  6. Accendere "Automatic downloads" nella pagina del plugin.
- **Consigli (dalla 1.8.0):** `GET Recommendations/Targets?itemId=` dà gli
  amici attivi con online e accesso al titolo; `POST Recommendations`
  `{ItemId, To, Message}` consiglia un film o una serie (messaggio fino a 200
  caratteri, fino a 50 amici, 30 destinatari all'ora; chi non è amico o non
  vede il titolo si salta) e crea la voce `Recommendation` nella cassetta;
  `GET Recommendations` dà i consigli ricevuti ancora validi (escono quelli
  visti dopo il consiglio, quelli che l'utente non vede più, quelli di chi
  non è più amico e quelli di più di 60 giorni); `DELETE
  Recommendations/{itemId}` è "Non mi interessa". I dati stanno in
  `recommendations.json`, accanto a `inbox.json`. All'avvio la riga
  `recommended` si accende una volta sola nella Home dell'admin già salvata
  (`HomeRowsSeen`).
- **Cosa guardano gli amici (dalla 1.9.0):** in `GET Friends` ogni amico
  online fuori da un party può avere `NowPlaying` (film o episodio di una
  sessione WonderFlix; mai se chi guarda non può vedere il titolo o l'amico
  è in un party). `GET Friends/{userId}/NowPlaying` dà la posizione per
  "Guarda insieme" (409 se non vale). Il plugin registra le visioni
  WonderFlix oltre 5 minuti (film o serie, 30 giorni, 100 per utente) in
  `activity.json`; `GET Activity/FriendsWatched` dà la riga "Visti dagli
  amici" (titoli degli amici che chi chiama vede e non ha mai visto, al
  massimo 30). `GET`/`PUT Activity/Settings` `{ShareActivity}` è
  "Mostra agli amici cosa guardo" (acceso di default; spento cancella le
  visioni). Gli amici rileggono a inizio e fine di ogni riproduzione. All'avvio
  la riga `friendsWatched` si accende una volta sola nella Home dell'admin già
  salvata (`HomeRowsSeen`).
- **Match del film (dalla 1.10.0):** le sale stanno in memoria, una per
  utente, al massimo 8 membri. `POST Match` apre una sala; chi l'ha aperta
  invita amici (`POST Match/{roomId}/Invites`, avviso `MatchInvite` e voce
  nella cassetta), gli invitati entrano con `POST Match/{roomId}/Join`
  finché è in attesa. `POST Match/{roomId}/Start` `{Type, Duration, Genre,
  Rating}` (`Rating` dalla 1.10.1: `any`, `good` voto 7 o più, `bad` voto 5
  o meno; assente vale `any`) pesca 30 titoli a caso che nessun membro ha visto o iniziato e che tutti
  possono vedere; `POST Match/{roomId}/Votes` `{ItemId, Yes}` vota in ordine;
  un match è un titolo a cui tutti hanno detto sì, i quasi match arrivano a
  fine pila; `POST Match/{roomId}/More` pesca altri 30 titoli.
  `POST Match/{roomId}/Party` `{GroupId}` dà ai membri l'accesso al party
  privato di chi ha aperto e chiude la sala. Lo stato (`GET Match/{roomId}`
  e l'avviso `MatchUpdated`, al più ogni 250 ms) ha i conteggi, mai i voti
  dei singoli. Un membro senza sessioni WonderFlix per 60 s esce; se esce
  chi ha aperto, o dopo un'ora senza voti, la sala si chiude. I 409 hanno
  `{Reason}`.
- **Voti degli amici (dalla 1.11.0):** `ratings.json` (un voto per utente e
  titolo, film o stagione); la votazione di fine party in memoria per gruppo
  (`POST Ratings/Rounds`, `Vote`, `Skip`, `Reveal`; voti scoperti per tutti
  votato, 2 minuti o il creatore; avviso `RatingRoundUpdated`, mai voti altrui
  prima); `GET Ratings?itemId=` solo con i voti degli amici, `PUT`/`DELETE`
  `Ratings/{itemId}`; 60 scritture all'ora; `GET`/`DELETE Ratings/Admin/Comments`
  per l'admin; i 409 hanno `{Reason}`.
- **Segnalazioni e sottotitoli (dalla 1.12.0):** `reports.json`, solo le
  aperte, al massimo 20 per utente; `POST Reports`, `GET Reports/Mine` per
  tutti; `GET Reports` e `POST Reports/{id}/Resolve` solo admin; voci
  `ReportPending`/`ReportResolved`; `Subtitles/{itemId}/Search|Download|Upload`
  per admin e spunta sottotitoli, con 502 `{Reason}` se il download o
  l'upload falliscono (la ricerca risponde 502 senza corpo se Jellyfin o il
  provider falliscono); i 409 hanno `{Reason}`.
- **Spazio (dalla 1.16.0, solo admin):** il plugin calcola in memoria (il primo
  2 minuti dopo l'avvio, poi ogni 24 ore e su `POST Space/Recalculate`) quali
  film, serie e stagioni si possono cancellare (nessuno li guarda più, mai
  aperti, voti bassi), quali sono troppo pesanti (Alleggerisci, per stagione) e
  cosa si può pulire (torrent senza copia in libreria, file orfani, doppioni).
  Le operazioni (`POST Space/Operations`, poi `GET Space/Operations/{id}`)
  girano una alla volta nel plugin; si avviano solo le righe di Cancellare.
  `space.json` tiene i titoli tenuti, i torrent in attesa di fine seed e le
  operazioni degli ultimi 30 giorni. Endpoint: `GET Space`, `POST
  Space/Recalculate`, `POST Space/Operations`, `GET Space/Operations/{id}`,
  `POST`/`DELETE Space/Kept`, `DELETE Space/Pending/{hash}`. Voti sulla scala
  1-10: bassi fino a 4, alti da 8, minimo 2 voti (configurabili).
  Configurazione (sezione Spazio della pagina del plugin):
  - **qBittorrent:** indirizzo (`http://127.0.0.1:17541`), utente e password
    (`SpaceQbitUrl`, `SpaceQbitUser`, `SpaceQbitPassword`). Il WebUI ha
    `LocalHostAuth` acceso, quindi serve il login anche da localhost. La
    password non torna mai nelle risposte né nel registro. Senza qBittorrent
    non ci sono torrent né orfani.
  - **Quota:** nel container di Jellyfin `quota` non c'è. Sul seedbox un cron
    scrive `quota -w` in un file (per esempio ogni 10 minuti
    `quota -w > /home/hashvps/.config/wonderflix-quota.tmp && mv /home/hashvps/.config/wonderflix-quota.tmp /home/hashvps/.config/wonderflix-quota.txt`,
    così il plugin non legge mai un file a metà), e `SpaceQuotaFile` ne dà il
    percorso, assoluto e visibile al container di Jellyfin (non `~`). Se il
    file è vuoto o non c'è, la quota non si mostra (`Errors.Quota` =
    `NotConfigured`).
  - **Cartelle da analizzare** (`SpaceScanFolders`, una per riga):
    `/home/hashvps/downloads` e `/home/hashvps/seedings`. Il plugin cancella
    file dal disco solo lì dentro o nei percorsi di Radarr/Sonarr.
  - **Soglie:** mesi senza aperture (6), giorni di grazia di una richiesta
    (60), voti bassi (4), alti (8), minimo voti (2), GB all'ora "pesante" (4),
    tracker con seed obbligatorio (`itatorrents.xyz,shareisland.org`), ratio
    (10) e giorni (30).
  - **Il cestino di Radarr e Sonarr deve restare spento** (`recycleBin`
    vuoto): altrimenti `deleteFiles=true` sposta i file nel cestino e la
    cancellazione non libera spazio.
  - **Regola in qui da correggere** (a mano, sul seedbox): "Stop old
    ItaTorrents downloaded seedings" ha la condizione sullo stato in OR
    (`STATE ≠ downloading` OR `STATE ≠ stalled_downloading`, sempre vera):
    deve essere AND.
  I torrent di ItaTorrents e ShareIsland si tolgono solo con ratio 10 o 30
  giorni di seed e finiti di scaricare; fino ad allora restano in attesa e il
  plugin li controlla ogni ora. Il collegamento titolo-torrent usa device e
  inode di `stat` (Jellyfin vede gli stessi percorsi del seedbox).
- **Funzioni:** `GET Info` annuncia quello che il plugin sa fare; dalla 1.5.0
  ci sono sempre anche `collections` e `avatars`, dalla 1.6.0 anche
  `account`, dalla 1.7.0 anche `home`, dalla 1.8.0 anche `recommendations`, dalla 1.9.0 anche `friendsActivity`, dalla 1.10.0 anche `match`, dalla 1.11.0 anche `ratings`, dalla 1.12.0 anche `reports`, dalla 1.14.0 anche `downloads` (con almeno uno tra Sonarr e Radarr), dalla 1.16.0 anche `space` (subito dopo `downloads`, con le stesse condizioni); `upcomingSeries` e `upcomingMovies`
  solo con Sonarr e Radarr configurati, e `calendar` con almeno uno dei due. Gli endpoint delle saghe e delle
  immagini sono aperti a ogni utente che ha fatto l'accesso. Quelli di
  `account` dipendono dalla rotta: `Account/Contacts` per ogni utente che ha
  fatto l'accesso (con la password attuale per cambiare i contatti),
  `Account/Recovery` senza accesso, `Account/Admin` solo per gli admin. Quelli
  di `Home` e `Upcoming` sono aperti a ogni utente che ha fatto l'accesso,
  tranne le scritture (`POST Home/Layout`, `POST Upcoming/Test`), solo per gli
  admin. Quelli di `Recommendations` hanno la stessa policy degli amici. Quelli di `Activity` hanno la stessa policy degli amici. Quelli di `Match` hanno la stessa policy degli amici. Quelli di `Ratings` hanno la stessa policy degli amici, tranne `Ratings/Admin`, solo per l'admin. Quelli di `Downloads` e di `Space` sono solo per l'admin.

## Installazione dal repository

1. Dashboard → Plugin → Repository → **+**: nome a piacere, URL
   `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/plugin/manifest.json`.
2. Catalogo → **WonderFlix Watch Party** → Installa.
3. Riavvia Jellyfin.

## Installazione a mano (prove)

1. Dalla root del repository: `bash plugin/pack.sh 1.12.0`.
   Crea `plugin/artifacts/WonderFlix Watch Party_1.12.0.0/`
   con la dll e `meta.json`.
2. Copia la cartella dentro `plugins/` della cartella dati di Jellyfin (su
   Ultra.cc via SFTP).
3. Riavvia Jellyfin. In Dashboard → Plugin compare "WonderFlix Watch Party",
   attivo.

Prima di installare dal Catalogo togli la cartella copiata a mano.

## Sviluppo

- Test: `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests`.
- Versioni di Jellyfin: il plugin è compilato contro Jellyfin 10.11.0 (il
  minimo), i test girano con quella del server (10.11.9). Jellyfin ha tolto
  `IUserManager.Users` in una patch 10.11.x, quindi i membri che sono cambiati
  si cercano a runtime (`Server/UserListing.cs`). Anche
  `IUserManager.ChangePassword` ha cambiato firma (`User` nella 10.11.0,
  `Guid` nella 10.11.9): `Server/PasswordChanging.cs`. Quando si aggiorna il
  server, si alzano i pacchetti `Jellyfin.Controller` e `Jellyfin.Model` del
  progetto di test a quella versione.
- Release: tag `watch-party-plugin-vX.Y.Z` → il workflow
  `watch-party-plugin.yml` pubblica una **pre-release** con lo zip e il suo
  MD5. Mai "latest": l'app legge `releases/latest` per i propri
  aggiornamenti. Poi si aggiunge la versione a `manifest.json`.
