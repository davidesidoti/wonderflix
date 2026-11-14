# WonderFlix — Richieste, nuova UI

Data: 2026-11-14. Bozza approvata: [`2026-11-14-richieste-bozze/richieste.html`](2026-11-14-richieste-bozze/richieste.html) (richieste vere del server; nomi di chi chiede, percentuali, alcune date e le richieste "Da approvare" sono inventati). Spec di partenza: spec I (richieste con Seerr, piani 15a/15b) e piano 25b (date nelle richieste). Dove questa spec non dice nulla valgono quelle.

## 1. Perché

La pagina Richieste (app 0.9.0, poi 0.20.0 per le date) è un unico elenco a pagine, dalla richiesta più recente, con una pillola di stato a destra. Sul server, il 14 novembre:

- 493 richieste; delle ultime 200, 161 sono "Disponibile". Le poche ancora aperte (22 tra in arrivo e in parte) si perdono tra quelle finite;
- la pillola dice uno stato ma non a che punto del percorso si è né cosa manca; "In arrivo · 42%" non ha una barra;
- le date (cinema, digitale, prossimo episodio) sono una terza riga grigia uguale per tutti;
- le rifiutate stanno in mezzo alle altre;
- 83 richieste "completate" riguardano titoli poi tolti dal server (stato media "eliminato", aggiornato da Seerr tra il 12 e il 15 settembre; non da Spazio, che cancella il media in Seerr e con lui le richieste): l'app le mostra "Disponibile", e non è vero;
- la pagina vuota è una riga di testo, senza un modo per richiedere.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Tre gruppi: **In corso** in cima, **Arrivate** come scaffale di locandine, **Chiuse** in fondo, chiuse.
- Ogni richiesta in corso mostra un **percorso in quattro tappe** (Chiesta → Approvata → In arrivo → Su WonderFlix); durante il download la linea si riempie con la percentuale.
- Sotto il percorso, una riga con cosa manca (date in oro se future, percentuale, attesa di approvazione).
- I titoli tolti dal server smettono di sembrare disponibili: stato nuovo "Tolta dal server", nel gruppo Chiuse.
- Le richieste approvate da più di 30 giorni e mai arrivate vanno in Chiuse come "Non trovata" (decisione dell'utente).
- "Richiedi un titolo" in alto e nella pagina vuota porta a Cerca.

**Non obiettivi**
- Niente avviso per le richieste doppie (Slime S4 chiesta due volte).
- Niente dettaglio di quali stagioni sono arrivate in "In parte": il plugin non lo passa.
- Niente filtri, ordinamenti o ricerca dentro la pagina.
- La finestra "Approva" (server, profilo, cartella) e il Rifiuta a due tempi non cambiano.
- La scheda da richiedere (`tmdb_title_screen.dart`) e la sezione "Da richiedere" di Cerca non cambiano.

**Anti-obiettivi**
- Lo stile non cambia: Noir & Oro, Bebas Neue per i titoli, Inter per il resto. Nessun colore nuovo.
- Un'app 0.41 con il plugin nuovo deve continuare a funzionare come oggi (stessi stati, stesso elenco).
- La pagina non deve diventare lenta: niente letture di titolo e date per richieste che non si mostrano.

## 3. Strade considerate

| Strada | Pro | Contro | Scelta |
|---|---|---|---|
| **A. Il plugin divide.** L'app chiede un gruppo alla volta; il plugin legge da Seerr l'elenco completo (grezzo, senza titoli né date), lo divide con le regole di stato che usa già, e completa solo le righe della pagina. Elenco grezzo tenuto pochi secondi | gruppi sempre uguali agli stati mostrati, casi strani compresi; regole in un posto solo | ogni lettura scarica tutte le richieste (oggi ~500, veloce; cresce col tempo) | **scelta** (dall'utente) |
| B. Filtri di Seerr (`unavailable`, `completed`, `failed`), Seerr fa le pagine | meno codice nel plugin | Seerr non ha un filtro per le rifiutate (11); `completed` include gli 83 titoli tolti; una richiesta approvata e già arrivata (Shield Hero) non è in nessun gruppo | scartata |
| C. L'app carica tutte le pagine e divide | nessuna modifica al plugin | ~500 letture di titolo e date per aprire la pagina | scartata |

Verifica fatta sul server (letture con la chiave di Seerr dal file di configurazione del plugin), coppie (stato richiesta, stato media) su 493: `(2,1)` 13, `(2,3)` 23, `(2,4)` 8, `(2,5)` 1, `(2,7)` 4, `(3,1)` 11, `(5,1)` 1, `(5,4)` 6, `(5,5)` 343, `(5,7)` 83. Il filtro `pending` di Seerr oggi dà 0.

## 4. Plugin

Il plugin resta alla versione **1.31.0**, non ancora rilasciata: questo lavoro esce nella stessa release (decisione mia: l'utente vuole una release unica; niente bump, `InfoControllerTests` invariato).

### 4.1 Endpoint

`GET WonderFlixWatchParty/Requests?filter=mine|pending|all&group=open|done|closed&skip&take&language`

- `group` è facoltativo. **Senza `group` la risposta è identica a oggi**, anche negli stati (nessun `Removed`): le app 0.41 non cambiano.
- `group` con `filter=pending` → 400 (pending è già un gruppo). Un `group` sconosciuto → 400.
- I permessi restano quelli di oggi: `mine` per tutti, `all` solo per chi può approvare.
- Con `group` la risposta ha in più `Total` (intero): quante richieste ha il gruppo, per i conteggi nei titoli dei gruppi. Senza `group` il campo non c'è.
- Ordine dentro ogni gruppo: dalla più recente (`createdAt` decrescente), come oggi.

### 4.2 I gruppi

Lo stato di una richiesta è quello di `SeerrMapping.RequestStatus` di oggi, più uno nuovo:

- **`Removed`** ("Tolta dal server"): stato media `MediaDeleted` (7) e nessun download in corso (`Media.DownloadStatus` vuoto), con la richiesta completata o approvata. Coppie `(5,7)` e `(2,7)` del §3. Rifiutate e non riuscite restano tali anche con il media tolto. (Mia scelta per `(2,7)`: approvata ma il titolo non c'è più e non scarica niente; con un download in corso resta "In arrivo".)
- `Removed` si manda all'app **solo con `group`**; senza, quelle richieste restano `Available` (o lo stato di oggi) come adesso.
- Con `Removed` il plugin manda `JellyfinItemId` nullo, anche se Seerr ha ancora il vecchio id: così `openRequest` porta alla scheda da cui si richiede di nuovo e non a un elemento che non c'è più (mia scelta: lo stato lo decide il plugin, la correzione sta lì).
- Stato media sconosciuto (1) non è `Removed`. Verificato sul server: le 13 `(2,1)` sono richieste approvate, mandate a Radarr/Sonarr (hanno `externalServiceId`) e mai arrivate (titoli poco noti come "Fear PHarm", "Night Shot", "The Tonight Show"), create tra maggio e ottobre; la `(5,1)` ("Away") è in Jellyfin.
- **`NotFound`** ("Non trovata", decisione dell'utente): richiesta con stato di base `Approved` (non Downloading, non Partial), chiesta da **più di 30 giorni** (`createdAt`, costante `NotFoundAfter`), senza download in corso e senza niente sul server (stato media sconosciuto, in attesa o in lavorazione). Per un film, se è `AwaitingRelease` (non ancora uscito) resta in corso: per queste richieste il plugin legge le date del film anche solo per decidere il gruppo (poche: oggi 13 in tutto). Per una serie conta solo il tempo (una serie che va in onda ogni settimana e non si trova è proprio il caso da chiudere). Se il titolo poi arriva, lo stato torna `Available` da solo e la richiesta passa ad Arrivate.
- Come `Removed`, `NotFound` si manda solo con `group`; senza resta `Approved`.

Assegnazione:

| Gruppo | Stati |
|---|---|
| `open` | Pending, Approved, Downloading, Partial, AwaitingRelease |
| `done` | Available |
| `closed` | Declined, Failed, Removed, NotFound |

`AwaitingRelease` dipende dalle date del film, che si leggono solo per le righe completate: per decidere il gruppo basta che lo stato di base sia `Approved` (resta in `open` in tutti e due i casi).

### 4.3 Lettura e cache

- Un servizio (per esempio `SeerrRequestList`) legge da Seerr tutte le richieste di un ambito: tutte (`all`) o di un utente Seerr (`mine`, con `requestedBy`). `SpaceService.Scan.cs` fa già lo stesso giro (`GetRequestsAsync(..., "all", 100, skip, ...)`, decisione 9 di Spazio): si riusa o si estrae quel ciclo. Lo `skip` avanza del numero di risultati ricevuti, non di quelli chiesti (Seerr può tagliare `take`), finché `pageInfo.results` non è raggiunto.
- L'elenco grezzo si tiene **30 secondi** per ambito (`TimeProvider`, come `SeerrTitleCache`), così i tre gruppi aperti insieme e le pagine successive costano una lettura sola. Due richieste contemporanee per lo stesso ambito condividono la stessa lettura.
- Approva, Rifiuta e una richiesta nuova creata dal plugin **svuotano la cache** (tutti gli ambiti): l'aggiornamento dopo un'azione deve vedere lo stato nuovo. Anche il webhook di Seerr la svuota, in `RequestWebhookHandler.HandleAsync` e **prima** dell'avviso nella cassetta (l'app rilegge appena lo riceve).
- Dopo la divisione si prende la fetta `skip`/`take` e solo quelle righe passano da `ToDtoAsync` (titolo da `SeerrTitleCache`, date da `ReleaseDatesService`), come oggi.
- Errori di Seerr: come oggi (503/"Seerr non risponde" nell'app).

### 4.4 Funzione

Nuova funzione `requestsGroups` in GET Info, presente quando c'è `requests` (Seerr configurato). L'app la usa per scegliere la pagina nuova o il ripiego (§5.8).

### 4.5 Test

In `RequestsServiceTests` (o un file nuovo accanto): divisione per gruppo di ogni coppia del §3; `Removed` e `NotFound` solo con `group`; `NotFound` a 29 e 31 giorni, film non ancora uscito che resta in corso, serie, titolo poi arrivato; `(2,7)` con download resta Downloading; `Total`; pagine dentro un gruppo; 400 per `pending`+`group` e gruppo sconosciuto; permessi di `all`; cache (una sola lettura per due gruppi, nuova lettura dopo 30 s, svuotata da Approva/Rifiuta/creazione/webhook); `requestsGroups` in Info.

## 5. App

Versione: resta **0.42.0** (non rilasciata), riga nuova nella checklist di `docs/RELEASING.md` e in `.claude/release-notes-draft.md` (checkout principale).

### 5.1 Modelli e API

- `RequestStatus.removed` (`'Removed'`), etichetta "Tolta dal server", e `RequestStatus.notFound` (`'NotFound'`), etichetta "Non trovata": tutte e due colore `creamMuted`.
- `RequestsApi.list` prende `group` facoltativo (`RequestsGroup.open|done|closed`); `RequestPage` prende `total` (`int?`).
- `PluginFeatures.requestsGroups`.

### 5.2 Struttura della pagina

```
RICHIESTE                                         [⌕ Richiedi un titolo]
Le mie   Da approvare (2)   Tutte                (schede solo per chi approva)

IN CORSO  5
[locandina] Titolo (anno)                         ●───●───◎────○
            Film · chiesta da (L) Luca · 14 ore fa  Chiesta Approvata In arrivo Su WonderFlix
                                                  42% scaricato
...
ARRIVATE  61
[loc][loc][loc][loc][loc][loc][loc][loc]
[loc][loc] ...
Mostra altre

CHIUSE  1  ▾                                       (chiuso; si apre al clic)
```

- Titolo "RICHIESTE", schede, scheda nell'indirizzo (`?tab=`), scelta automatica della scheda e uscita verso la Home quando Seerr sparisce: **come oggi** (`requests_screen.dart`).
- "Richiedi un titolo": pulsante con il bordo oro (stile `WfButton` esistente con icona di ricerca), a destra del titolo; apre Cerca (`/search`). C'è anche sulla TV, dove Cerca esiste.
- Le schede "Le mie" e "Tutte" mostrano i tre gruppi; "Da approvare" mostra solo le righe con Approva e Rifiuta (§5.6).
- Titolo di gruppo: Bebas 24 in crema, conteggio (`total`) in Inter 13 `creamMuted` accanto. Un gruppo senza richieste non si mostra.
- Tutta la pagina scorre in un solo `CustomScrollView` (gruppi come slivers), larghezza del contenuto come Impostazioni (1040 px più i margini, allineato a sinistra).

### 5.3 Riga "In corso"

- Locandina 56×84 (40×60 nello stretto), raggio 4.
- Titolo "(anno)" Inter 15 semibold; riga sotto in 13 `creamMuted`: tipo o stagioni (`formatSeasonList`, come oggi), "chiesta da" con avatar piccolo (18 px) e nome solo in "Tutte", ora relativa (`inboxTimeLabel`). Il richiedente "tu" quando `isMe`.
- A destra (fuori dallo stretto) una colonna di 400 px: il percorso e, sotto, la riga del dettaglio.
- Nello stretto il percorso va sotto, largo quanto la riga, **senza etichette**; la riga del dettaglio comincia con la tappa attuale in crema semibold ("In arrivo · 42% scaricato").
- Clic sulla riga: `openRequest` come oggi. Hover: fondo `surfaceHigh`. Righe separate da una linea `surface` di 1 px, nessuna card.
- Avatar: `UserAvatar.lookup(name:)` se trova l'utente, altrimenti l'iniziale in un cerchio `surfaceHigh` (scelta del costruttore, purché ci sia sempre qualcosa).

### 5.4 Il percorso

Widget nuovo (per esempio `RequestTrack`) con funzione pura che dà, per uno stato, la tappa attuale, le etichette e quanto della linea è oro.

| Stato | Tappa attuale | Etichetta della tappa | Linea oro fino a | Riga del dettaglio |
|---|---|---|---|---|
| pending | 2 | "Da approvare" | tappa 2 | "Aspetta l'ok di chi gestisce le richieste" |
| approved | 3 | "In arrivo" | tappa 3 | "Approvata: si cerca una versione da scaricare" |
| awaitingRelease | 3 | "Non ancora uscito" | tappa 3 | le date del film (`requestDateParts`, oro se future) |
| downloading | 3 | "In arrivo" | tappa 3 + progresso verso la 4 | "42% scaricato" (senza progresso: "Download in corso") |
| partial | 4 (mezzo pieno) | "In parte" | tappa 4 | il prossimo episodio (`requestDateParts`), altrimenti "Una parte è già su WonderFlix" |

- Punti: fatti 12 px oro pieno; attuale anello oro 2 px con alone oro al 18%; "In parte" metà oro e metà fondo; da fare grigio `#333`. Linea 2 px, base `border`, parte fatta oro.
- Etichette 11,5 px sotto i punti: prima allineata a sinistra, ultima a destra, le altre centrate; fatte `creamMuted`, attuale crema semibold, da fare crema al 42%.
- Semantica: una sola etichetta per lo screen reader, per esempio "Fatte: Chiesta, Approvata. Ora: In arrivo, 42%".
- Nessuna animazione continua. La linea può allungarsi con una transizione breve (`WfMotion`) quando il progresso cambia, ferma con le animazioni ridotte.
- Le date dei film per gli stati chiusi o arrivati non si mostrano (com'è oggi).

### 5.5 Arrivate e Chiuse

- **Arrivate**: griglia di locandine 112×168 (fuori dallo stretto), 3 per riga nello stretto; sotto il titolo (2 righe al massimo) e "Film"/"Serie" in `creamMuted`. Clic: `openRequest` (scheda della libreria se c'è il titolo). Hover: bordo `creamMuted`. Sulla TV `TvFocusable`. Si può riusare l'aspetto di `RequestablePosterCard`/`PosterCard`, senza etichetta sulla locandina.
- Si caricano 20 richieste per volta; sotto la griglia **"Mostra altre"** (pulsante di testo oro) carica la pagina dopo, finché ce ne sono. (Mia scelta, diversa dalla bozza che diceva "Mostra tutte": caricare tutte le 412 di "Tutte" vorrebbe dire 412 letture di titolo. Niente scorrimento infinito, così si arriva sempre al gruppo Chiuse.)
- **Chiuse**: titolo "Chiuse" con conteggio e una freccia; chiuso all'apertura della pagina, si apre al clic (o con OK sulla TV). Righe come quelle in corso ma senza percorso: a destra l'etichetta "Rifiutata"/"Non riuscita" in `error`, "Tolta dal server"/"Non trovata" in `creamMuted`. Clic: `openRequest` (per un titolo tolto porta alla scheda da cui si richiede di nuovo). "Mostra altre" anche qui.

### 5.6 Da approvare

- Righe come in §5.3 con "chiesta da" sempre visibile, Rifiuta (a due tempi) e Approva a destra (sotto, a destra, nello stretto): `PendingRequestActions` com'è.
- Nessun percorso (sono tutte alla tappa 2).
- Elenco a pagine come oggi (`filter=pending`, senza `group`); conteggio nella scheda come oggi.

### 5.7 Caricamento, aggiornamenti, vuoto

- All'apertura di "Le mie" o "Tutte" partono le prime pagine dei tre gruppi (una lettura su Seerr grazie alla cache del plugin). **In corso** carica da solo le pagine successive finché `hasMore` (oggi 44 in "Tutte": tre pagine); Arrivate e Chiuse solo con "Mostra altre".
- **Percentuale che sale**: oggi l'elenco si rilegge solo sugli avvisi della cassetta, quindi la percentuale resta ferma. Il gruppo In corso si aggiorna da solo (`refresh`) ogni **30 secondi**, solo mentre ha almeno una riga in download e la pagina è aperta (mia scelta: 30 s come la cache del plugin; nessun aggiornamento a vuoto quando niente scarica). Il timer si ferma con il controller.
- Ogni gruppo ha il suo controller con la logica di `RequestsListController` di oggi (generazioni, niente doppioni, aggiornamento sui `InboxChangedEvent`): la chiave si allarga con il gruppo (`({filter, group, language})`). Una richiesta che cambia gruppo (arriva, viene tolta) compare nel gruppo giusto al successivo aggiornamento di tutti e tre.
- Dopo Approva o Rifiuta: come oggi (conteggio invalidato, riga tolta da "Da approvare"); al posto dell'elenco "Tutte" si aggiornano i gruppi di "Tutte" che esistono.
- Errore di un gruppo: il gruppo mostra "Riprova" al suo posto, gli altri restano. Errore di tutti all'apertura: `ErrorView` come oggi.
- Caricamento iniziale: `LoadingView` come oggi finché i tre gruppi non hanno la prima risposta.
- **Pagina vuota** (nessun gruppo con righe):
  - "Le mie": titolo Bebas "Non hai ancora chiesto niente", sotto "Se un film o una serie non è su WonderFlix, cercalo e premi Richiedi. Lo trovi qui mentre arriva." e il pulsante "Richiedi un titolo".
  - "Tutte": "Nessuna richiesta" (com'è).
  - "Da approvare": "Niente da approvare" (com'è).

### 5.8 Ripiego (plugin senza `requestsGroups`)

Senza la funzione la pagina resta l'elenco unico a pagine di oggi, con le righe nuove (§5.3, percorso compreso; righe arrivate e chiuse con l'etichetta a destra al posto del percorso). Niente gruppi, niente scaffale.

### 5.9 TV

- Come oggi solo "Le mie", niente approvazioni.
- Righe, locandine dello scaffale, "Mostra altre", "Chiuse" e "Richiedi un titolo" sono tappe del telecomando (`TvFocusable`); la pagina scorre spostando il fuoco (vedi CLAUDE.md sul fuoco TV e `SingleChildScrollView` nei test).
- Il percorso sulla TV ha le etichette (schermo largo).

### 5.10 Testi nuovi (it, e en dove c'è)

"Richiedi un titolo", "In corso", "Arrivate", "Chiuse", "Mostra altre", "Da approvare" (tappa), "Non ancora uscito", "In parte", "Chiesta", "Approvata", "In arrivo", "Su WonderFlix", "Tolta dal server", "Non trovata", "Aspetta l'ok di chi gestisce le richieste", "Approvata: si cerca una versione da scaricare", "{percent}% scaricato", "Download in corso", "Una parte è già su WonderFlix", "Non hai ancora chiesto niente", testo della pagina vuota, "chiesta da {name}" (oggi "chiesto da": cambia il genere perché il soggetto è la richiesta), etichetta per lo screen reader del percorso. Le stringhe che non servono più si tolgono.

### 5.11 Test

- Funzione pura del percorso: ogni riga della tabella del §5.4.
- `RequestRow`/riga nuova: largo e stretto, "Tutte" con avatar, "tu".
- Pagina: tre gruppi con conteggi; gruppo vuoto nascosto; "Mostra altre"; Chiuse chiuso e poi aperto; errore di un gruppo; pagina vuota con il pulsante; ripiego senza `requestsGroups`; "Richiedi un titolo" apre `/search`; schede e indirizzo come oggi (i test di oggi restano o si adattano).
- TV: fuoco su righe, scaffale, Chiuse.
- Controller per gruppo: chiave con il gruppo, `total`, caricamento automatico di In corso.

## 6. Cosa lascio al costruttore

- I nomi di classi e file, purché in `features/requests/` (e `core/requests/` per API e modelli).
- Come disegnare il percorso (Row/Stack o `CustomPainter`), purché uguale alla bozza.
- Il componente della locandina dello scaffale (riuso o widget piccolo nuovo).
- Il dettaglio della condivisione della lettura in corso nella cache del plugin.

## 7. Prova a mano

Windows: le tre schede da admin; un film in download (percentuale che sale), uno in attesa d'uscita, una serie in parte con il prossimo episodio; "Mostra altre" in Arrivate; Chiuse con una rifiutata (The Thundermans) e un titolo tolto, per esempio "Fargo" (apre la scheda da richiedere; ce ne sono già 83, non serve toglierne uno); Approva e Rifiuta da "Da approvare" e la riga che compare in In corso di "Tutte"; finestra stretta sotto 1024 px. Web sul telefono se possibile. TV: "Le mie" col telecomando.
