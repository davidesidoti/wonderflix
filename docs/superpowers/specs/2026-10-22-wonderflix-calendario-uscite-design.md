# WonderFlix — Spec S: calendario delle uscite

- **Data:** 2026-10-22
- **Stato:** approvata il 2026-10-22; piano 25a realizzato (`docs/superpowers/plans/2026-10-22-wonderflix-25a-calendario-plugin.md`), build di prova sul server; piano 25b realizzato (`docs/superpowers/plans/2026-10-22-wonderflix-25b-calendario-app.md`), provato con l'utente il 2026-10-22. **Realizzata:** plugin 1.13.0 (tag `watch-party-plugin-v1.13.0`) e app 0.20.0 (tag `v0.20.0`). Bozza della griglia: `.superpowers/brainstorm/1632-1792678780/content/calendario-layout.html` (opzione B, non nel repo).
- **Ambito:** Spec S. Realizza l'idea 16 di `docs/IDEE.md` ("Calendario delle uscite"). Si appoggia alla Spec I (richieste con Seerr: `2026-10-05-wonderflix-seerr-design.md`), alla Spec M (Sonarr e Radarr nel plugin: `2026-10-10-wonderflix-home-su-misura-design.md`, §7) e alla Spec G (cassetta: `2026-10-03-wonderflix-notifiche-design.md`).

## 1. Obiettivo

Gli utenti scrivono spesso all'admin: "ho chiesto questo film ma ancora non c'è". Di solito è un film uscito da poco al cinema, che in digitale arriva settimane dopo. Radarr non può scaricarlo prima. Gli utenti devono poterlo vedere da soli.

Con lo spec S:

- **nella pagina Richieste**, ogni richiesta ha la sua data:
  - per un film, quando esce al cinema e quando esce in digitale;
  - per una serie, il prossimo episodio atteso.

  Un film non ancora uscito in digitale ha lo stato **"In attesa dell'uscita"**, non "Approvata" né "In arrivo". La pagina Richieste fa da calendario personale.
- **un calendario a muro**, nuova pagina "Calendario": la griglia del mese con tutte le prossime uscite del server, **uguale per tutti**, "giusto per esserne a conoscenza";
- **avvisi:** restano quelli di oggi ("Ora disponibile" da Seerr, "Nuovi titoli"). Non serve niente di nuovo: vedi §2, Seerr.

**Nota sul modello:** il calendario non è un calendario di tutte le uscite del mondo, come quello di TMDB o di un sito di cinema. Mostra solo quello che **Sonarr e Radarr seguono**, cioè le serie e i film già aggiunti al server o chiesti con Seerr e approvati. Un film che nessuno ha chiesto non c'è. Anche un film chiesto ma **non ancora approvato** non c'è, perché è in Seerr e non ancora in Radarr: la sua data si vede solo nella pagina Richieste (§6.2).

## 2. Situazione di partenza

App 0.19.0, plugin 1.12.0, Jellyfin 10.11.9 su Ultra.cc, Sonarr 4.0.20 e Radarr 6.4.4 (Spec M §2).

### Plugin

- `Home/ArrClient.cs` (`IArrClient`) legge il calendario di Sonarr (`GetEpisodesAsync`) e quello di Radarr (`GetMoviesAsync`), più `system/status`. I modelli sono in `Home/ArrJson.cs`. `RadarrMovie` ha solo `DigitalRelease` e `HasFile` tra le date e lo stato.
- `Home/UpcomingService.cs` dà `GET Upcoming/Series` (7 giorni) e `GET Upcoming/Movies` (90 giorni, solo `hasFile = false` con `digitalRelease` nel periodo), con una cache di 15 minuti (1 minuto per un errore) legata alle impostazioni. Raggruppa le uscite in blocco (`UpcomingBuilder`) e collega le serie di Jellyfin per utente (`ISeriesIndex`, `JellyfinSeriesId`).
- `Hub/RequestsService.cs` dà le richieste di Seerr (`MediaRequestDto`) con lo stato calcolato come in Spec I §7.3: `Pending`, `Approved`, `Downloading`, `Partial`, `Available`, `Declined`, `Failed`.
- `Hub/RequestWebhookHandler.cs` trasforma `MEDIA_AVAILABLE` di Seerr in "Ora disponibile" nella cassetta.
- `NewTitlesHostedService` e `Hub/NewTitlesCollector.cs` ascoltano `ItemAdded` di Jellyfin e mandano "Nuovi titoli" a ondate, quasi subito.

### Seerr (controllato sul server il 2026-10-22)

- La sincronizzazione "aggiunti di recente" di Jellyfin, rotta ai tempi della Spec I (§3, §11), **ora funziona**: "Recently Added Scan Complete" ogni 5 minuti (199 volte il 2026-10-22). Un titolo arrivato diventa disponibile in Seerr entro pochi minuti: "Ora disponibile" parte e lo stato della richiesta passa a `Available`.
- Resta un errore a parte, a ogni giro, su un solo titolo ("Neon Genesis Evangelion", `UNIQUE constraint failed: media.tvdbId`): non tocca questo spec.

### Radarr e Sonarr (controllati sul server il 2026-10-22)

- `GET /api/v3/movie` di Radarr: 814 film, **5,4 MB**, 0,35 s. Ogni film ha `inCinemas`, `digitalRelease`, `physicalRelease`, `hasFile`.
- `GET /api/v3/movie?tmdbId=` di Radarr: un elenco con solo quel film (7 kB, 0,06 s).
- `GET /api/v3/movie/lookup/tmdb?tmdbId=` di Radarr risponde anche per un film **non** in libreria (`id` null), con `inCinemas`, `digitalRelease`, `physicalRelease` (provato con "Avatar: Fuoco e cenere").
- `GET /api/v3/series` di Sonarr: 174 serie, 0,66 MB; ognuna ha `tvdbId`, `tmdbId`, `nextAiring` (14 con un prossimo episodio).
- `Info.Features` ha `upcomingSeries` (Sonarr configurato) e `upcomingMovies` (Radarr configurato).

### App

- Pagina Richieste: `lib/features/requests/requests_screen.dart`, la riga è `request_row.dart`, le etichette sono in `request_labels.dart`.
- Righe "Serie in arrivo" e "Film in arrivo" della Home: `lib/features/home/` e `lib/core/social/home_api.dart`.
- Barra in alto: `lib/app/shell_header.dart`, indirizzi in `lib/app/router.dart`.

## 3. Decisioni

| Tema | Decisione | Di chi |
|---|---|---|
| Due pezzi | date accanto alle richieste (personale) **e** calendario (per tutti) | utente |
| Forma del calendario | griglia del mese | utente |
| Data di un film | solo l'uscita **digitale**, nel calendario; nella pagina Richieste anche il cinema | utente (cinema in Richieste: dalla bozza approvata) |
| Contenuto del calendario | tutte le uscite seguite da Sonarr e Radarr, uguali per tutti; le cose proprie si vedono nella pagina Richieste | utente |
| Navigazione | frecce mese prima / mese dopo, "Oggi", giorno di oggi evidenziato | mia, approvata |
| Giorni affollati | episodi della stessa serie nello stesso giorno = una voce ("Andor ×3"); oltre il limite "+N", che apre l'elenco del giorno | mia, approvata |
| Clic su un titolo | serie della libreria → sua pagina; film non sul server → scheda da richiedere | mia, approvata |
| Già arrivato | segno verde sulle uscite già sul server | mia, approvata |
| Serie nella pagina Richieste | prossimo episodio atteso | mia, approvata |
| Stato nuovo | "In attesa dell'uscita" per i film approvati non ancora usciti in digitale | mia, approvata |
| Avvisi | nessun avviso nuovo (niente "domani esce…"); "Ora disponibile" di Seerr arriva già entro pochi minuti (§2) | utente; il controllo su Seerr è mio |
| Voce nella barra | "Calendario", tra "Richieste" e "Cerca" | mia |
| Film già scaricato | `hasFile` di Radarr blocca "In attesa dell'uscita" | mia (§6.2) |
| Film senza data digitale | "In attesa dell'uscita" solo se il film è recente; un film vecchio senza data resta "Approvata" | mia (§6.2) |

## 4. Perimetro

### Incluso

- **Plugin 1.13.0:** `GET Upcoming/Calendar` (§6.1), le date nelle richieste e lo stato `AwaitingRelease` (§6.2), la funzione `calendar` in `Info.Features` (§6.4).
- **App 0.20.0:** pagina Calendario (§7.1–7.4), date e stato nuovo nella pagina Richieste (§7.5), voce nella barra (§7.1).

### Escluso

- Uscite al cinema e su disco nel calendario.
- Avvisi nuovi: prima dell'uscita ("domani esce…"), promemoria, un "Ora disponibile" mandato dal plugin.
- Un calendario personale (solo le cose mie, solo le serie che seguo): per le cose proprie c'è la pagina Richieste.
- Uscite che Sonarr e Radarr non seguono (titoli mai chiesti, richieste non ancora approvate).
- Esportare il calendario (iCal, Google Calendar).
- Vista a settimana o elenco: c'è solo il mese.
- Modifiche alle righe "Serie in arrivo" e "Film in arrivo" della Home.

## 5. Architettura

Il plugin resta l'unico che parla con Sonarr, Radarr e Seerr: le chiavi non arrivano mai all'app. Il calendario è una lettura in più dello stesso `IArrClient`, con la stessa cache e gli stessi codici d'errore dello spec M §7.4. Le date delle richieste le aggiunge `RequestsService` tramite `ReleaseDatesService`: i film si chiedono a Radarr uno per uno, per id TMDB; per le serie si legge la libreria di Sonarr (una volta ogni 15 minuti per tutti). Le letture di tutti e due passano da `ArrReadCache<T>`, una cache a chiavi condivisa (15 minuti, 1 minuto per un errore).

## 6. Plugin 1.13.0

### 6.1 `GET WonderFlixWatchParty/Upcoming/Calendar?start=YYYY-MM-DD&end=YYYY-MM-DD`

- Per tutti gli utenti autenticati. `end` è escluso. Al massimo **42 giorni** (sei settimane: la griglia del mese con i giorni dei mesi vicini); un periodo più lungo, date non valide (solo `YYYY-MM-DD`, anche se mancano) o `end ≤ start` → 400 **senza corpo**, come gli altri controller del plugin.
- Le date sono giorni di calendario. Il plugin chiede a Sonarr e Radarr da `start` 00:00 a `end` 00:00 **allargati di un giorno per parte** (14 ore bastano per i fusi, un giorno è più semplice). L'app mette ogni episodio nel giorno **locale** dell'utente, ogni film nel giorno della sua data (§10), e scarta quelle fuori dalla griglia.
- Chiama Sonarr e Radarr **in parallelo**; se uno dei due non è configurato o va in errore, l'altro risponde lo stesso.
- Risposta (sempre 200):

  ```json
  {
    "Episodes": [ { "SeriesName", "SeasonNumber", "EpisodeNumber", "LastEpisodeNumber", "EpisodeTitle",
                    "AirDateUtc", "TvdbId", "TmdbId", "PosterUrl", "BackdropUrl", "JellyfinSeriesId",
                    "OnServer" } ],
    "Movies":   [ { "Title", "Year", "TmdbId", "DigitalRelease", "PosterUrl", "BackdropUrl",
                    "JellyfinItemId", "OnServer" } ],
    "SeriesError": null,
    "MoviesError": null
  }
  ```

  - Le voci sono quelle di `Upcoming/Series` e `Upcoming/Movies` (Spec M §7.3), con le stesse regole per immagini, gruppi in blocco, `JellyfinSeriesId` per utente e ordine.
  - **Campi null:** il plugin non mette `WhenWritingNull`, ma Jellyfin non scrive i null nelle sue risposte (provato sul server il 2026-10-22: senza errori mancano `SeriesError` e `MoviesError`, e nelle voci mancano i campi null). Come per `Upcoming/*` (Spec M), l'app legge un campo mancante come null.
  - **Differenze da `Upcoming/*`:** il periodo lo sceglie l'app; si tengono **anche** le uscite già scaricate (`hasFile = true`), con `OnServer = true`; senza `SeriesLookBack`.
  - Un gruppo in blocco è `OnServer` solo se tutti i suoi episodi lo sono.
  - Film: solo quelli con `digitalRelease` nel periodo (allargato). Un film con solo `inCinemas` nel periodo non c'è.
  - `JellyfinItemId` di un film (nuovo): il film di Jellyfin con lo stesso id TMDB, **solo se chi chiama lo vede**; altrimenti `null`. Come `JellyfinSeriesId`, con le stesse regole di scelta e ordine.
  - `SeriesError` e `MoviesError` usano i codici di Spec M §7.4 (`NotConfigured`, `Unauthorized`, `Unreachable`).
- **Cache:** `ArrReadCache<T>` (§5), 15 minuti (1 minuto per un errore), legata a indirizzo, chiave e **periodo**. Tiene **6 periodi per servizio** (`CalendarService.MaxCachedPeriods`; Sonarr e Radarr hanno ognuno la sua cache): chi sfoglia i mesi non deve far crescere la memoria senza limite. Il limite vale per le letture finite; quelle in corso si aggiungono sempre, e quando serve posto esce la più vecchia.
  - Nella cache ci sono le voci già costruite, compresi gli id dei titoli di Jellyfin che le corrispondono (uguali per tutti). Solo la scelta di quello che l'utente vede si fa per utente, **dopo** la cache.
- Le richieste allo stesso periodo in contemporanea fanno una sola lettura. La lettura non si ferma se chi l'ha chiesta se ne va (il suo risultato serve alla prossima richiesta); chi chiede smette solo di aspettarla.

### 6.2 Date nelle richieste

Ogni `MediaRequestDto` riceve tre campi nuovi, che possono mancare (null):

| Campo | Film | Serie |
|---|---|---|
| `InCinemas` | `inCinemas` di Radarr | — |
| `DigitalRelease` | `digitalRelease` di Radarr | — |
| `NextAiring` | — | prossimo episodio atteso: `nextAiring` di Sonarr, con stagione ed episodio (`NextSeasonNumber`, `NextEpisodeNumber`) |

- **Da dove:**
  - film: Radarr **per `tmdbId`**, mai la libreria intera (5,4 MB, §2): prima `movie?tmdbId=`, poi, se l'elenco è vuoto, `movie/lookup/tmdb?tmdbId=`. Una voce in cache per film (15 minuti, 1 minuto con un errore), legata a indirizzo e chiave come §6.1, al massimo 500 film (`ReleaseDatesService.MaxCachedMovies`);
  - **solo dove servono:** una richiesta `Available`, `Declined` o `Failed` non chiede niente a Radarr e i suoi campi restano null (l'app non li mostra, §7.5). Le altre, `Pending` compresa, sì;
  - serie: la libreria di Sonarr (`series`, 0,66 MB), letta tutta insieme con la stessa cache (una sola voce); si abbina per **`tvdbId` del media di Seerr** (campo nuovo `SeerrRequestMedia.TvdbId`, null per i film), poi per `tmdbId`. Le serie le chiedono sempre, qualunque sia lo stato;
  - il numero del prossimo episodio non è in `series`: si legge `episode?seriesId=` solo per una serie con `nextAiring`, e si prende l'episodio con quell'ora (a parità la stagione normale prima della 0, poi il numero più basso). Una voce in cache per serie, al massimo 200 (`ReleaseDatesService.MaxCachedSeriesEpisodes`). Se quella lettura fallisce o non trova l'episodio, `NextAiring` resta e `NextSeasonNumber` e `NextEpisodeNumber` sono null.
  - I campi nuovi null non arrivano all'app (Jellyfin non scrive i null, §6.1): l'app legge un campo mancante come null.
- **Richiesta non ancora in Radarr** (in attesa di approvazione, o approvata ma Radarr non l'ha ancora aggiunta): le date vengono da `movie/lookup/tmdb` (le date di TMDB, come le vedrebbe Radarr). Se anche questo fallisce, i campi restano null.
- Sonarr o Radarr non configurati o in errore: i campi restano null, la pagina Richieste funziona come oggi. Un errore di Sonarr o Radarr **non** fa fallire l'elenco delle richieste (`ReleaseDatesService` non lancia mai, tranne l'annullamento di chi chiede; nel log solo l'id, mai titoli o indirizzi).
- **Stato nuovo `AwaitingRelease`**, tra 6 e 8 della Spec I §7.3: una richiesta di **film** approvata, non disponibile, senza download in corso, con Radarr che **non** ha il file (`hasFile` falso o film non in Radarr), e **non ancora uscito** → `AwaitingRelease` invece di `Approved`. "Non ancora uscito" vuol dire:
  - `DigitalRelease` nel futuro (dopo l'ora attuale); oppure
  - `DigitalRelease` null, `PhysicalRelease` null o nel futuro, e `InCinemas` null, nel futuro o negli **ultimi 12 mesi**.

  Un film vecchio senza data digitale (molti film vecchi o stranieri su TMDB) resta `Approved`: lì il problema non è l'uscita ma che Radarr non lo trova, e la pagina non deve dare la colpa alla data.
  - Con `DigitalRelease` passato resta `Approved`: il film è uscito e Radarr lo sta cercando.
  - Con `hasFile` vero resta `Approved` (o `Downloading`): il film è sul server o ci sta arrivando, e Seerr lo segna `Available` entro pochi minuti (§2).
  - `PhysicalRelease` serve solo per questa regola: non va nel DTO.
  - **Senza le date non si sa:** con Radarr non configurato o in errore (campi null) la richiesta resta `Approved`, non diventa `AwaitingRelease`.
  - `Pending` resta `Pending` anche se il film non è uscito: l'admin deve ancora approvarla.
  - Un'app vecchia mostra `AwaitingRelease` come "Approvata": `RequestStatus.parse` (`lib/core/requests/requests_models.dart`) legge ogni stato sconosciuto come `approved`. Nessun cambio di forma serve.

### 6.3 Pagina del plugin

Niente di nuovo: il calendario usa la configurazione di Sonarr e Radarr che c'è già (Spec M §7.1).

### 6.4 `Info` e versione

- `calendar` in `Features` se Sonarr **o** Radarr è configurato. Lo calcola `WatchPartyProtocol.FeaturesWith` (la firma non cambia) e lo mette subito dopo `upcomingSeries` e `upcomingMovies`: con tutti e due `…, "upcomingSeries", "upcomingMovies", "calendar"`, con solo Sonarr `…, "upcomingSeries", "calendar"`.
- Versione **1.13.0**; descrizione e overview del manifest con il calendario.

## 7. App 0.20.0

### 7.1 Voce e indirizzo

- Voce **"Calendario"** nella barra in alto, tra "Richieste" e "Cerca", solo con la funzione `calendar`.
- Indirizzo `/calendar?month=YYYY-MM`; senza `month` il mese di oggi. Le frecce cambiano l'indirizzo, come le schede della pagina Richieste.
- La pagina si rifà a ogni mese (la chiave è l'indirizzo, come la pagina Richieste): dopo un cambio di mese il fuoco della tastiera ricomincia da capo.

### 7.2 Griglia del mese

- Titolo "Calendario", poi il mese ("Ottobre 2026") con **‹** e **›** ai lati e il pulsante **"Oggi"** (spento sul mese di oggi).
- Sette colonne da **lunedì** a domenica, intestazioni corte ("L M M G V S D" o "lun mar …", scelta del costruttore); sei righe sempre, con i giorni dei mesi vicini più spenti.
- Il giorno di oggi ha il bordo oro.
- Ogni casella: il numero del giorno e le voci di quel giorno (episodi nel giorno **locale** del PC, film nel giorno della data, §10):
  - film in oro scuro (`WfColors.calendarMovie`), serie in blu scuro (`WfColors.calendarSeries`), presi dalla bozza `.superpowers/brainstorm/…/calendario-layout.html`, opzione B; il colore non è l'unico segno: una piccola icona (film / serie) e il testo per gli screen reader;
  - serie: "{SeriesName}" per un episodio, "{SeriesName} ×{n}" per un gruppo in blocco o per più episodi della stessa serie nello stesso giorno. Gli episodi della stessa serie nello stesso giorno locale sono **una** voce (stesso `tvdbId`, altrimenti `tmdbId`, altrimenti il nome senza badare alle maiuscole); `n` è il numero degli episodi (un blocco "E01–E03" vale 3); la voce è `OnServer` solo se lo sono tutti gli episodi;
  - una voce già sul server (`OnServer`) ha il segno verde (un puntino o una spunta `online`);
  - in ordine: prima i film, poi le serie, ognuno per nome.
- **Troppe voci:** la casella ne mostra quante ci stanno secondo l'altezza, **almeno 1** (`CalendarMonthGrid.minEntries`; la riga del numero è alta 22 px, una voce 20 px). Se le voci sono più di quelle che ci stanno, l'ultima riga diventa **"+{n}"**. Alla finestra minima (1024×640) una casella ha posto per una sola riga: con più di una voce quella riga diventa "+{n}". Il minimo è 1 e non 2 perché a quell'altezza due righe non ci stanno.
- **Clic sulla casella** (o su "+{n}"): si apre l'**elenco del giorno** (§7.3).
- **Clic su una voce:** come §7.4. Una voce che non si può aprire ("niente clic") non ha clic, cursore né azione per lo screen reader, né nella griglia né nell'elenco del giorno: il clic passa alla casella del giorno, che apre l'elenco.
- Senza uscite nel mese: la griglia vuota e sotto "Nessuna uscita in questo mese".
- **Tastiera:** frecce (±1 giorno a sinistra e destra, ±7 giorni in su e in giù) e Invio, dentro i 42 giorni della griglia, a partire dal giorno di oggi (o dal primo del mese, se oggi non c'è nella griglia). Invio apre l'elenco del giorno. La Home non ha una tastiera da imitare: la griglia ha la sua. **Niente PagSu e PagGiù**: i mesi si cambiano con le frecce in alto.
- La griglia si adatta alla larghezza della finestra. Sotto i 96 px di larghezza per casella (`CalendarMonthGrid.compactCellWidth`) la casella mostra solo il numero e un puntino per voce (al massimo 4); il clic apre l'elenco del giorno. È solo una protezione: con la finestra minima di 1024 px le caselle sono larghe circa 133 px, quindi nell'app vera non compare mai. I puntini sono oro per i film e crema per le serie (i colori scuri delle voci a 6 px non si vedrebbero).
- **Semantica (screen reader):** le caselle con voci sono pulsanti con l'azione di tocco; i giorni vuoti non sono pulsanti. Le righe della finestra del giorno sono protette da un doppio tocco.

### 7.3 Elenco del giorno

- Una finestra (`showWfDialog`) con il titolo "Mercoledì 22 ottobre" e l'elenco completo:
  - locandina piccola, nome, "Film · in digitale" oppure "S03E04 · {EpisodeTitle}" / "S03E01–E03", ora locale per gli episodi;
  - "Sul server" in verde per `OnServer`.
- Clic su una riga: come §7.4 (la finestra si chiude). Una riga che non porta da nessuna parte non ha clic.

### 7.4 Dove porta un titolo

| Voce | Destinazione |
|---|---|
| Serie con `JellyfinSeriesId` | la pagina della serie in WonderFlix |
| Serie senza `JellyfinSeriesId`, con `TmdbId` e Seerr disponibile | la scheda da richiedere `/tmdb/tv/{tmdbId}` |
| Film con `JellyfinItemId` | la scheda del film in WonderFlix |
| Film senza `JellyfinItemId`, Seerr disponibile | la scheda da richiedere `/tmdb/movie/{tmdbId}` |
| Altrimenti | niente clic; la voce si vede lo stesso |

### 7.5 Pagina Richieste

- **Riga** (`request_row.dart`): sotto la riga di oggi, una riga in più con le date, solo se ce n'è almeno una:
  - film: "Al cinema dal {data}" · "in digitale previsto il {data}" (futuro) / "uscito in digitale il {data}" (passato) / "in digitale: data non ancora nota" (null, solo se la richiesta non è disponibile);
  - serie: "Prossimo episodio: S{n}E{m} il {data}" (senza numero: "Prossimo episodio il {data}");
  - la data futura in oro, come nella bozza; per la serie la data del prossimo episodio è in oro solo se è futura; formato "12 novembre" (con l'anno solo se non è quest'anno);
  - la prima parte della riga comincia con la maiuscola ("In digitale previsto il…" se manca il cinema);
  - un film senza **nessuna** data (né cinema né digitale) non ha la riga: vuol dire Radarr non configurato o plugin vecchio, e "data non ancora nota" sarebbe falso.
  - Per 1-2 ore dopo la mezzanotte locale (Italia) un film può mostrare "In attesa dell'uscita" accanto a "uscito in digitale il …": il plugin confronta l'istante, l'app il giorno locale. Accettato.
  - Su una richiesta `Available`, `Declined` o `Failed` le date di un film non si mostrano (non servono più); quelle di una serie sì.
- **Stato nuovo:** `awaitingRelease` → etichetta **"In attesa dell'uscita"**, oro. Va anche nel filtro e nei conteggi come `approved`.
- Nessuna chiamata nuova: le date arrivano con le richieste.

### 7.6 Senza plugin ed errori

- Plugin < 1.13.0: niente voce "Calendario", righe delle richieste senza date (i campi mancano).
- `SeriesError` o `MoviesError` nella risposta: la griglia mostra quello che c'è e una riga sopra: "Le serie non si possono caricare ora" / "I film non si possono caricare ora".
  - **`NotConfigured` non è un errore da mostrare:** con solo Sonarr configurato, `MoviesError` è `NotConfigured` e la pagina non dice niente dei film. La riga c'è solo per `Unauthorized` e `Unreachable`.
  - **Il motivo per l'admin** (come le card di Spec M §8.6) è il testo di `arrTestLabel` dopo un " · ": "Le serie non si possono caricare ora · Chiave rifiutata". Gli altri vedono solo la prima parte.
  - **Errore a pagina intera con "Riprova"** solo se **ogni** servizio configurato è in errore.
  - "Nessuna uscita in questo mese" non si mostra se un servizio è in errore (il mese potrebbe non essere vuoto).
  - **Campi mancanti:** Jellyfin non scrive i null (§6.1), quindi `SeriesError`, `MoviesError`, `JellyfinSeriesId`, `JellyfinItemId` e le date delle richieste di solito mancano; l'app li legge come null (`OnServer` mancante = falso). Il calendario riusa `UpcomingEpisode` e `UpcomingMovie` con i campi nuovi facoltativi, senza modelli nuovi; la Home li ignora.
- Errore di rete o di Jellyfin → errore con "Riprova", come le altre pagine.
- Il mese si rilegge quando la pagina si riapre o si cambia mese; nessun aggiornamento automatico.

## 8. Testi nuovi (ARB, it + en)

| Dove | Testi |
|---|---|
| Barra | "Calendario" |
| Calendario | "Oggi", "Mese precedente", "Mese successivo", "Nessuna uscita in questo mese", "+{n}", "{name} ×{n}", "Film · in digitale", "Sul server", "Le serie non si possono caricare ora", "I film non si possono caricare ora" |
| Richieste | "In attesa dell'uscita", "Al cinema dal {date}", "in digitale previsto il {date}", "uscito in digitale il {date}", "in digitale: data non ancora nota", "Prossimo episodio: S{season}E{episode} il {date}", "Prossimo episodio il {date}" |
| Screen reader | "{date}: {n} uscite", "Film", "Serie", "già sul server" |

## 9. Test

### 9.1 Plugin (xUnit)

- `Upcoming/Calendar`: periodo valido, troppo lungo, date non valide, `end ≤ start` (400); Sonarr in errore e Radarr no (e il contrario); `OnServer` per episodi, gruppi e film; film con solo `inCinemas` escluso; `JellyfinItemId` solo per chi vede il film; cache per periodo, limite dei periodi tenuti, cache legata alle impostazioni.
- Date nelle richieste: abbinamento per `tmdbId` e `tvdbId`; film non in Radarr con `lookup`; Sonarr o Radarr in errore → campi null ed elenco intatto.
- `AwaitingRelease`: digitale futuro, passato; digitale null con cinema futuro, recente (dentro i 12 mesi) e vecchio; uscita fisica passata; `hasFile` vero; film non in Radarr; `Pending` non cambia; download in corso vince; serie mai `AwaitingRelease`.
- `Info.Features.calendar`.

### 9.2 App

- Costruzione della griglia (il giorno di un film è la data UTC di `DigitalRelease`, mai spostata dal fuso): mese che parte di domenica, febbraio, cambio dell'ora legale (le uscite non saltano di giorno), giorno locale da `AirDateUtc`.
- Raggruppamento per serie e giorno, ordine, "+{n}".
- Destinazioni del clic (§7.4).
- Righe delle date nella pagina Richieste e l'etichetta "In attesa dell'uscita".
- Errori parziali e totali.

### 9.3 Prova a mano

- Sul server vero: il mese di oggi e quello dopo, con le serie di Sonarr e i film di Radarr; un film già scaricato segnato in verde; clic su una serie della libreria e su un film da richiedere.
- Pagina Richieste: un film approvato non ancora uscito in digitale ("In attesa dell'uscita" con le date), una serie con il prossimo episodio.

## 10. Da verificare sul server

- Il calendario di Radarr con `unmonitored=false` include i film già scaricati con `digitalRelease` nel periodo (Spec M §3 dice di sì: "Leviticus").
- Le date dei film di Radarr sono a mezzanotte UTC (`2026-03-31T00:00:00Z`): l'app le mostra come **giorno** (la data UTC), senza spostarle al giorno prima con il fuso. Gli episodi invece hanno un'ora vera (`AirDateUtc`) e vanno nel giorno locale (§6.1, §7.2).

## 11. Piani e release

- **Piano 25a — plugin 1.13.0:** §6, test §9.1, build di prova installata a mano sul server. Realizzato.
- **Piano 25b — app 0.20.0:** §7 e §8, test §9.2, poi la prova a mano §9.3 con l'utente.
- Release insieme alla fine di 25b: tag del plugin `watch-party-plugin-v1.13.0` con manifest e Catalog, app `v0.20.0` (non obbligatoria) con le note in italiano nella bozza.
