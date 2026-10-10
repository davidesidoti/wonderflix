# WonderFlix — Spec M: Home su misura

- **Data:** 2026-10-10
- **Stato:** approvata il 2026-10-10; piani da scrivere (19a, 19b, 19c, §15).
- **Ambito:** Spec M. Realizza l'idea 15 di `docs/IDEE.md` ("Home su misura"): porta nella Home di WonderFlix le righe che l'utente ha già su jellyfin-web con il plugin Home Screen Sections e va oltre. L'admin sceglie righe e ordine per tutti; ogni utente le sposta e le nasconde per sé; in più "Continua la saga" e "Cosa guardo stasera?".

## 1. Obiettivo

- **Righe nuove.** "Perché hai visto X", "Le mie richieste" (Seerr), "Continua la saga", "Serie in arrivo" (Sonarr) e "Film in arrivo" (Radarr), accanto a quelle di oggi.
- **L'admin decide per tutti.** Dalla dashboard admin l'admin sceglie quali righe ci sono e in che ordine. Una riga spenta dall'admin non c'è per nessuno.
- **Ritocchi dell'utente.** Ogni utente, da Impostazioni → Home, sposta e nasconde le righe accese dall'admin. La sua Home è salvata sul server, nel suo account Jellyfin: la ritrova su ogni PC. "Ripristina" torna alla Home dell'admin.
- **Cosa guardo stasera?** Un pulsante nella Home apre una finestra che propone un titolo non visto a caso, con filtri per tipo, durata e genere.
- **Nessuna riga blocca le altre.** Ogni riga carica per conto suo: una risposta lenta di Sonarr non ferma la Home.

Nota sul modello: "Perché hai visto X" ricorda Netflix, ma Jellyfin non ha un sistema di consigli. La riga usa i titoli simili del server (`/Items/{id}/Similar`: generi, tag e persone in comune), uguali per tutti gli utenti, filtrati per quello che l'utente non ha visto.

## 2. Situazione di partenza

App 0.12.1, plugin 1.6.0, Jellyfin 10.11.9 su Ultra.cc dietro il proxy.

### 2.1 App

- **Home.** `loadHome` (`lib/features/home/home_data.dart`) fa cinque chiamate in parallelo (`Future.wait`): Continua a guardare (`resume`), Prossimi episodi (`nextUp`, serie guardate negli ultimi 365 giorni), ultimi film, ultime serie, preferiti. Il carosello (`pickFeatured`) prende fino a 5 titoli recenti con uno sfondo, alternando film e serie. `homeProvider` si rilegge quando cambiano la libreria (`libraryRevisionProvider`) o i dati dell'utente (`userDataRevisionProvider`).
- **Schermata.** `HomeScreen` (`lib/features/home/home_screen.dart`) mostra scheletro, errore con "Riprova", "Home vuota" (`homeEmpty`) o le righe. Le righe entrano scaglionate (`StaggerGroup`) una volta per sessione (`homeEntrancePlayedProvider`). Due tipi di riga: locandine (`MediaRow` alta 300, `PosterCard` larga 160) e card orizzontali (`MediaRow` alta 230, `LandscapeCard`). L'ordine è fisso nel codice.
- **Preferenze del profilo.** `ProfilePreferences` (`lib/features/profiles/profile_preferences.dart`) salva sul PC, con il prefisso `profile.<id>.`.
- **Impostazioni.** `SettingsScreen` ha, in quest'ordine: Account, Lingua, Aspetto, Player, Lingue di riproduzione, Discord, Supporto. Non sa scorrere fino a una sezione.
- **Amministrazione.** La scheda WonderFlix (`WonderflixTab`) ha le card Annuncio, Titoli nuovi, Seerr (stato e "Prova collegamento") e Recupero password.
- **Saghe (Spec K).** `collectionsProvider` legge le saghe dal plugin (`Collections`: id, nome, immagine e id dei titoli visibili); `collectionItemsProvider` dà i titoli di una saga in ordine di uscita; `collections_logic.dart` sa già scegliere il titolo da proporre (il primo non visto in ordine di uscita).
- **Richieste (Spec I).** `RequestsApi.list(RequestsFilter.mine, …)` dà le richieste dell'utente; `MediaRequest` ha `createdAt`, `status` e `jellyfinItemId`; `openRequest` apre il dettaglio Jellyfin se il titolo è sul server, altrimenti la pagina Seerr (`tmdbRoute`). `RequestBadge` mostra lo stato; `RequestablePosterCard` mostra locandine TMDB (`TmdbImages`).
- **Libreria.** `LibraryApi` ha `items` (con `ItemQuery`: tipi, generi, visti/non visti, ordinamento), `similar`, `filters` (generi per tipo) e `itemsByIds`.
- **Funzioni del plugin.** `SocialFeatures` (`lib/features/social/social_providers.dart`) ricava da `Info.Features` le funzioni accese.

### 2.2 Plugin 1.6.0

- Funzioni in `Info`: `friends`, `parties`, `inbox`, `queue`, `collections`, `avatars`, `account` (`WatchPartyProtocol.Features`), più `requests` se Seerr è configurato.
- Configurazione in `PluginConfiguration` e `configPage.html` (Seerr, Discord, SMTP, novità, promemoria).
- Seerr ha la prova del collegamento (`POST Requests/Test`), usata dalla card dell'app.

### 2.3 Server

- **jellyfin-web.** La Home è fatta con il plugin **Home Screen Sections**, con `AllowUserOverride` spento. Le righe accese, in ordine: Continua a guardare, Prossimi episodi, Le mie richieste (Seerr), Aggiunti di recente film, Aggiunti di recente serie, Perché hai visto X, Scopri (Seerr), Serie in arrivo (Sonarr), Film in arrivo (Radarr).
- **Sonarr 4.0.20 e Radarr 6.4.4** rispondono a `https://hashvps.proton.usbx.me/sonarr` e `/radarr` (UrlBase `/sonarr` e `/radarr`, autenticazione Forms, chiave API in `~/.apps/{sonarr,radarr}/config.xml`). Home Screen Sections ha ancora il dominio vecchio (`hashvps.vapor.usbx.me`, risponde 404): sul web le righe "In arrivo" probabilmente non funzionano. Le chiavi sono quelle giuste.
- **Episodi futuri.** Jellyfin non ne conosce nessuno (0 episodi con `PremiereDate` futura): le date delle uscite vanno prese da Sonarr.
- **Dati di prova del 2026-10-10.** Il calendario di Sonarr ha 16 episodi nei prossimi 7 giorni; quello di Radarr 11 film nei prossimi 90 giorni, prima dei filtri (§7.4).

## 3. Sonarr, Radarr e Jellyfin: cosa offrono

- **Sonarr** `GET /api/v3/calendar?start=…&end=…&includeSeries=true&unmonitored=false` (intestazione `X-Api-Key`): episodi con `seasonNumber`, `episodeNumber`, `title`, `airDateUtc`, `hasFile`, `monitored` e `series` (`title`, `tvdbId`, `tmdbId`, `imdbId`, `images` con `coverType` e `remoteUrl`: `poster`, `fanart`, `banner`, `clearlogo`).
- **Radarr** `GET /api/v3/calendar?start=…&end=…&unmonitored=false`: film con `title`, `year`, `tmdbId`, `inCinemas`, `digitalRelease`, `physicalRelease`, `hasFile`, `images`. Un film c'è se **una qualsiasi** delle sue date cade nel periodo, anche se è già scaricato (es. "Leviticus": scaricato, uscita fisica a novembre).
- **Stato:** `GET /api/v3/system/status` (nome e versione), per la prova del collegamento.
- **Jellyfin `DisplayPreferences`:** `GET` e `POST /DisplayPreferences/{id}?userId=…&client=…`, con un dizionario `CustomPrefs` di stringhe. Ogni utente ha le sue; il `POST` riscrive tutto l'oggetto, quindi si legge, si cambia `CustomPrefs` e si riscrive.
- **Jellyfin `Items`:** `SortBy=DatePlayed` (con `IsPlayed=true`) per le ultime visioni, `SortBy=Random` per pescare a caso; nessun filtro per durata.

## 4. Decisioni

1. **Scopo:** prima le righe del web, poi oltre.
2. **Chi decide:** l'admin per tutti, con i ritocchi dell'utente. Le righe spente dall'admin non esistono per gli utenti.
3. **Righe nuove:** Perché hai visto X, Le mie richieste, Serie in arrivo, Film in arrivo, Continua la saga. Restano fuori Scopri, le righe per genere e Guarda di nuovo.
4. **In arrivo:** due righe come sul web, serie entro 7 giorni e film (uscita digitale) entro 90 giorni, periodi modificabili dall'admin.
5. **Saghe:** "Continua la saga", solo le saghe iniziate e non finite.
6. **Cosa guardo stasera?:** finestra con filtri, un titolo alla volta, "Un altro".
7. **Dove si sistema:** un elenco in Impostazioni → Home per l'utente e una card nella dashboard admin; niente modifica direttamente sulla Home.
8. **Approccio A:** le righe le calcola l'app; il plugin dà la Home dell'admin e le uscite di Sonarr e Radarr. Niente lettura delle API di Home Screen Sections, niente Home calcolata dal plugin.
9. **Home dell'utente sul server**, nelle `DisplayPreferences` di Jellyfin, non nelle preferenze del profilo sul PC.
10. **Caricamento:** ogni riga per conto suo, un'unica entrata con un tempo massimo di 1,5 s.

## 5. Perimetro

### Incluso

- Righe configurabili (§6) con la Home dell'admin nel plugin e quella dell'utente nelle `DisplayPreferences`.
- Le cinque righe nuove (§8.3).
- Plugin 1.7.0: Home dell'admin, Sonarr e Radarr, `Upcoming`, prova del collegamento (§7).
- Caricamento per riga (§8.2).
- Impostazioni → Home, link dalla Home, `/settings?section=home` (§8.5).
- Card admin "Home per tutti" e "Sonarr e Radarr" (§8.6).
- "Cosa guardo stasera?" (§8.4).

### Escluso

- Scopri (tendenze Seerr), righe per genere, Guarda di nuovo, "Visti dagli amici" (idea 5).
- Modifica della Home direttamente sulla Home.
- Avvisi quando un episodio arriva e calendario completo (idea 16).
- L'ora delle uscite: si mostra solo il giorno.
- Configurare il carosello.
- Correggere gli indirizzi di Home Screen Sections su jellyfin-web (si può fare a parte).

## 6. Righe e layout

### 6.1 Le righe

Ogni riga ha un id stabile, usato per salvarla. Ordine predefinito, uguale al web:

| # | Riga | id | Tipo di card | Fonte |
|---|---|---|---|---|
| 1 | Continua a guardare | `resume` | orizzontale | Jellyfin |
| 2 | Prossimi episodi | `nextUp` | orizzontale | Jellyfin |
| 3 | Le mie richieste | `requests` | locandina | Seerr (plugin) |
| 4 | Aggiunti di recente: film | `latestMovies` | locandina | Jellyfin |
| 5 | Aggiunti di recente: serie | `latestSeries` | locandina | Jellyfin |
| 6 | Perché hai visto X | `becauseYouWatched` | locandina | Jellyfin |
| 7 | Continua la saga | `continueSaga` | orizzontale | plugin (`collections`) + Jellyfin |
| 8 | Serie in arrivo | `upcomingSeries` | orizzontale | Sonarr (plugin) |
| 9 | Film in arrivo | `upcomingMovies` | locandina | Radarr (plugin) |
| 10 | La mia lista | `myList` | locandina | Jellyfin |

Il carosello resta in cima, fuori dall'elenco, con i titoli aggiunti di recente come oggi, anche se l'utente nasconde quelle righe.

### 6.2 La Home dell'admin

- Un elenco ordinato degli id delle righe **accese**, salvato nel plugin (§7.2). `null`: mai impostato, vale l'ordine predefinito con tutte le righe accese.
- Un elenco vuoto è valido: l'admin ha spento tutte le righe.

### 6.3 La Home dell'utente

- Nelle `DisplayPreferences` dell'utente, id `wonderflix-home`, client `wonderflix`, due voci di `CustomPrefs`:
  - `homeRows`: gli id nell'ordine dell'utente, separati da virgole;
  - `homeHidden`: gli id nascosti, separati da virgole.
- "Ripristina" toglie le due voci. Senza voci l'utente vede la Home dell'admin.
- Gli id sconosciuti si ignorano (una versione futura dell'app potrebbe averne di più).

### 6.4 Come si combinano

Dati l'elenco dell'admin `A`, l'ordine dell'utente `U` e le righe nascoste `H`:

1. **Ordine.** Si parte dagli id di `U` che sono in `A`, nell'ordine di `U`. Ogni id di `A` che manca si inserisce subito dopo la riga che lo precede in `A` ed è già nell'elenco; se nessuna lo precede, in testa.
2. **Visibili.** Dall'elenco ordinato si tolgono gli id di `H` e le righe non disponibili (§6.5).

Esempio: `A` = `resume, nextUp, requests, upcomingSeries`; `U` = `nextUp, resume`; `H` = `requests`. Ordine: `nextUp, resume, requests, upcomingSeries` (`requests` dopo `nextUp`, che la precede in `A`; `upcomingSeries` dopo `requests`). Visibili: `nextUp, resume, upcomingSeries`.

L'elenco delle impostazioni (§8.5) mostra l'ordine del punto 1 con gli interruttori di `H`.

### 6.5 Righe non disponibili

| id | Disponibile se |
|---|---|
| `requests` | funzione `requests` del plugin e utente collegato a Seerr (`RequestsMe`) |
| `continueSaga` | funzione `collections` del plugin |
| `upcomingSeries` | funzione `upcomingSeries` del plugin (Sonarr configurato) |
| `upcomingMovies` | funzione `upcomingMovies` del plugin (Radarr configurato) |
| le altre | sempre |

Una riga non disponibile non si vede in Home e non fa chiamate; nell'elenco delle impostazioni compare spenta con il motivo (§10).

### 6.6 Plugin più vecchio

Senza la funzione `home` (plugin < 1.7.0) l'app non chiede la Home dell'admin e usa l'ordine predefinito; le righe "In arrivo" non sono disponibili. La Home dell'utente funziona lo stesso: le `DisplayPreferences` sono di Jellyfin.

## 7. Plugin 1.7.0

### 7.1 Configurazione

Nuova sezione "Sonarr e Radarr" in `configPage.html` e in `PluginConfiguration`:

| Campo | Predefinito | Note |
|---|---|---|
| `SonarrUrl` | vuoto | senza "/" finale, con l'UrlBase (`…/sonarr`) |
| `SonarrApiKey` | vuoto | |
| `RadarrUrl` | vuoto | come Sonarr |
| `RadarrApiKey` | vuoto | |
| `UpcomingSeriesDays` | 7 | da 1 a 60 |
| `UpcomingMoviesDays` | 90 | da 1 a 365 |

Sonarr è "configurato" con indirizzo e chiave; lo stesso per Radarr. Al salvataggio della configurazione la cache di §7.4 si svuota.

### 7.2 Home dell'admin

- In `PluginConfiguration`: `HomeRows`, elenco di id (`null` = mai impostato).
- `GET WonderFlixWatchParty/Home/Layout` (ogni utente collegato): `{ "Rows": ["resume", …] }` oppure `{ "Rows": null }`.
- `POST WonderFlixWatchParty/Home/Layout` (solo admin), corpo `{ "Rows": [...] | null }`: scarta gli id sconosciuti e i doppioni, salva e risponde con la Home salvata. `null` torna all'ordine predefinito.
- Gli id conosciuti sono quelli di §6.1, in una costante del plugin.

### 7.3 `Upcoming`

- **`GET WonderFlixWatchParty/Upcoming/Series`** → `{ "Items": [...], "Error": null | "notConfigured" | "unreachable" | "unauthorized" }`.
  - Chiede a Sonarr gli episodi da **ora − 12 ore** a **ora + `UpcomingSeriesDays`**, solo seguiti (`unmonitored=false`), e tiene quelli con `hasFile = false`. Le 12 ore tengono gli episodi usciti stanotte e non ancora scaricati.
  - Episodi della stessa serie e stagione, con numeri consecutivi e lo stesso `airDateUtc` (le uscite in blocco), diventano una voce sola.
  - Ogni voce: `SeriesName`, `SeasonNumber`, `EpisodeNumber`, `LastEpisodeNumber` (solo per un gruppo), `EpisodeTitle` (solo per un episodio singolo), `AirDateUtc`, `TvdbId`, `TmdbId` (`null` se Sonarr non lo sa o è 0), `PosterUrl`, `BackdropUrl` (`remoteUrl` di `poster` e `fanart`), `JellyfinSeriesId`.
  - `JellyfinSeriesId`: la serie di Jellyfin con lo stesso id TVDB, TMDB o IMDb, **solo se chi chiama la vede**; altrimenti `null`.
  - In ordine di `AirDateUtc`.
- **`GET WonderFlixWatchParty/Upcoming/Movies`** → stessa forma.
  - Chiede a Radarr i film da **oggi** (00:00 UTC) a **oggi + `UpcomingMoviesDays`**, solo seguiti, e tiene quelli con `hasFile = false` e `digitalRelease` nel periodo.
  - Ogni voce: `Title`, `Year`, `TmdbId`, `DigitalRelease`, `PosterUrl`, `BackdropUrl`.
  - In ordine di `DigitalRelease`.
- **Immagini:** solo `remoteUrl` (TMDB, TVDB, Fanart: indirizzi pubblici). Mai l'indirizzo locale di Sonarr (`/MediaCover/…`), che vuole la chiave.

### 7.4 Cache ed errori

- La risposta di Sonarr e quella di Radarr, già filtrate, restano in memoria **15 minuti**, uguali per tutti; l'`JellyfinSeriesId` si aggiunge per ogni utente dopo la cache. Due richieste insieme a cache vuota fanno una sola chiamata.
- Un errore resta in cache **1 minuto**, per non insistere su un servizio fermo.
- Codici: `notConfigured` (manca indirizzo o chiave), `unauthorized` (401/403), `unreachable` (rete, tempo scaduto dopo 10 s, 404, 5xx, risposta non JSON). Con un errore `Items` è vuoto e la risposta è 200, come il resto del plugin. L'errore va nel log del plugin.

### 7.5 Prova del collegamento

`POST WonderFlixWatchParty/Upcoming/Test` (solo admin): chiama `system/status` di Sonarr e di Radarr, senza cache, e risponde `{ "Sonarr": { "Configured", "Ok", "Version", "Error" }, "Radarr": { … } }`. `Error` usa i codici di §7.4.

### 7.6 `Info` e versione

- `home` sempre nella 1.7.0.
- `upcomingSeries` se Sonarr è configurato, `upcomingMovies` se Radarr è configurato (come `requests` con Seerr).
- Versione **1.7.0**; descrizione e overview del manifest con le righe della Home e le uscite di Sonarr e Radarr.

## 8. App

### 8.1 Dati e client

- `HomeRowKind`: i 10 id di §6.1 con l'ordine predefinito.
- Logica pura per §6.4 (ordine e visibili), testabile da sola.
- `DisplayPreferencesApi` (Jellyfin): leggere e scrivere `wonderflix-home` / `wonderflix`, cambiando solo `homeRows` e `homeHidden` e lasciando il resto dell'oggetto com'è.
- Client del plugin: `Home/Layout` (lettura e scrittura), `Upcoming/Series`, `Upcoming/Movies`, `Upcoming/Test`.
- `SocialFeatures`: `home`, `upcomingSeries`, `upcomingMovies`.

### 8.2 Caricamento della Home

1. **Composizione.** La Home legge in parallelo la Home dell'admin (se c'è la funzione `home`) e quella dell'utente, poi le combina (§6.4). Se la prima fallisce vale l'ordine predefinito, se fallisce la seconda vale la Home dell'admin; l'errore va nel log. Intanto si vede lo scheletro di oggi.
2. **Righe.** Ogni riga visibile ha il suo caricamento (un provider per riga). Le righe nascoste o non disponibili non fanno chiamate. Il carosello ha il suo, sui titoli aggiunti di recente (§6.1).
3. **Entrata.** La Home aspetta carosello e righe al massimo **1,5 s**, poi mostra tutto quello che è arrivato con l'entrata scaglionata di oggi (sempre una volta per sessione). Una riga arrivata dopo entra al suo posto con la stessa animazione (se l'entrata della sessione è già stata fatta, compare con la dissolvenza delle righe ricostruite).
4. **Errori.**
   - Una riga in errore non si vede; l'errore va nel log.
   - Errore con "Riprova" solo se **tutte** le righe di Jellyfin visibili (e il carosello) falliscono.
   - Tutte vuote (o nessuna riga accesa): "Home vuota" come oggi.
5. **Aggiornamenti.**
   - Righe di Jellyfin (`resume`, `nextUp`, `latestMovies`, `latestSeries`, `becauseYouWatched`, `continueSaga`, `myList`): come oggi, con `libraryRevisionProvider` e `userDataRevisionProvider`.
   - Righe esterne (`requests`, `upcomingSeries`, `upcomingMovies`) e Home dell'admin: si rileggono quando si torna alla Home, al massimo ogni 5 minuti.
   - Home dell'utente: subito, quando la salva dalle impostazioni.
6. **Fondo della Home:** il collegamento "Personalizza la Home" (§8.5).

Con tutte le righe accese le chiamate passano da 5 a circa 12, in parallelo.

### 8.3 Le righe nuove

Al massimo 20 titoli per riga (10 per Continua la saga); una riga vuota non c'è.

**Perché hai visto X** (locandine)
- Le ultime visioni: `Items` con `IsPlayed=true`, film ed episodi, `SortBy=DatePlayed` decrescente, 10 risultati. Un episodio vale come la sua serie; i doppioni si tolgono.
- Per il primo titolo: `similar` (30 risultati), tenendo i film non visti e le serie non finite, senza il titolo stesso. Se ne restano meno di 4, si prova col titolo successivo, fino a 3 titoli. Se nessuno basta, la riga non c'è.
- Titolo della riga: "Perché hai visto *Dune*" (`homeBecauseYouWatched`).

**Le mie richieste** (locandine con `RequestBadge`)
- `RequestsApi.list(RequestsFilter.mine, skip: 0, take: 50)`, senza le rifiutate e le fallite.
- Prima quelle in corso (in attesa, approvata, in download, parziale), dalla più recente; poi le disponibili create negli ultimi 30 giorni, dalla più recente.
- Locandina TMDB come `RequestablePosterCard`. Clic: `openRequest`.

**Continua la saga** (card orizzontali)
- Le saghe di `collectionsProvider` e i film visti (`Items`, film, `IsPlayed=true`, `SortBy=DatePlayed` decrescente, solo id e data, al massimo 500).
- Una saga entra se ha almeno un film visto e almeno uno non visto, contando solo i suoi titoli visibili.
- Ordine: dalla saga col film visto più di recente. Al massimo 10.
- Per le saghe scelte, `itemsByIds` dei titoli non visti: il prossimo è il primo non visto in ordine di uscita (la regola della pagina della saga).
- Card: sfondo del prossimo film, il suo titolo, sotto "Il Signore degli Anelli · 1 di 3 visti" (`homeSagaProgress`). Clic: pagina della saga.

**Serie in arrivo** (card orizzontali)
- `Upcoming/Series`. Sfondo: quello di Jellyfin se c'è `JellyfinSeriesId`, altrimenti `BackdropUrl` (poi `PosterUrl`, poi il segnaposto delle card).
- Titolo: nome della serie. Sotto: "S02E05 · Oggi", "S01E05–E06 · Domani", "S03E01 · ven 17 ott" (`upcomingEpisode`, `upcomingEpisodes`, `upcomingToday`, `upcomingTomorrow`). La data è nel fuso del PC; una data passata o di oggi è "Oggi".
- Clic: dettaglio Jellyfin con `JellyfinSeriesId`; altrimenti pagina Seerr della serie (`tmdbRoute`) se c'è `TmdbId` e la funzione `requests`; altrimenti la card non si clicca.

**Film in arrivo** (locandine)
- `Upcoming/Movies`. Locandina `PosterUrl`. Sotto: "Digitale · 13 ott" (`upcomingDigital`).
- Clic: pagina Seerr del film se c'è la funzione `requests`; altrimenti la card non si clicca.

**Card con immagini esterne.** `PosterCard` e `LandscapeCard` lavorano su `JellyfinItem`. Per "In arrivo" serve una variante con immagine da indirizzo esterno, titolo, sottotitolo e clic facoltativo, nello stile delle card di oggi (come `RequestablePosterCard` con TMDB). Le date sono nella lingua dell'app.

### 8.4 Cosa guardo stasera?

- **Pulsante** "Cosa guardo stasera?" con l'icona del dado, nell'angolo in basso a destra del carosello, sopra i pallini; senza carosello, in cima alle righe, a destra. Sempre presente.
- **Finestra** (`showWfDialog`):
  - Filtri:
    - Tipo: Film / Serie / Entrambi (predefinito Entrambi).
    - Durata: Qualsiasi / meno di 90 min / meno di 2 h; solo per i film, disattivato con "Serie".
    - Genere: "Tutti" o un genere della libreria (`filters` per i tipi scelti; con Entrambi, l'unione).
    - I filtri si ricordano per profilo (`ProfilePreferences`: `tonight.type`, `tonight.duration`, `tonight.genre`).
  - Il titolo: sfondo grande, titolo, anno · durata o numero di stagioni · generi · voto della community, trama su 4 righe.
  - Tasti: **Guarda** (`playItem`; per una serie parte dal primo episodio), **Dettagli** (chiude e apre la pagina), **Un altro** (con un'animazione del dado che rispetta le animazioni ridotte).
- **Titoli:**
  - Film non visti e serie **mai iniziate** (nessun episodio visto).
  - Una chiamata `Items` con `SortBy=Random`, non visti, tipi e genere, 50 risultati, con i campi per durata, generi, trama e dati utente. Durata e "mai iniziate" si filtrano nell'app.
  - "Un altro" passa al successivo; finiti, si pescano altri 50. Nella stessa sessione un titolo già proposto non torna, finché ce ne sono altri.
  - Cambiare un filtro riparte da capo.
- **Casi:** nessun titolo → "Nessun titolo con questi filtri" e "Togli i filtri"; errore → messaggio e "Riprova" nella finestra.

### 8.5 Impostazioni → Home

- Nuova sezione **Home**, dopo Aspetto.
- **Elenco** (`HomeRowsEditor` in modo utente): le righe accese dall'admin nell'ordine di §6.4. Ogni voce: maniglia per trascinare, nome, fonte in piccolo ("da Seerr", "da Sonarr", "da Radarr"), interruttore mostra/nascondi. Con una voce selezionata, due frecce la spostano su e giù (anche da tastiera).
- **Non disponibili:** spente, con il motivo (§10). Si possono spostare.
- **Salvataggio automatico** sul server 500 ms dopo l'ultima modifica. Se fallisce, l'elenco torna all'ultimo stato salvato e compare "Non salvato, riprova".
- **"Ripristina la Home predefinita":** toglie `homeRows` e `homeHidden`; disattivato se non ci sono.
- Sotto: "Vale per questo account su tutti i PC."
- **`/settings?section=home`** apre le impostazioni e scorre fino alla sezione Home. Il collegamento "Personalizza la Home" in fondo alla Home porta lì.

### 8.6 Amministrazione → WonderFlix

Due card nuove, dopo Titoli nuovi:

- **"Home per tutti"** (`HomeRowsEditor` in modo admin): tutte e 10 le righe, nell'ordine dell'admin con quelle spente in fondo nell'ordine predefinito. L'interruttore accende o spegne la riga per tutti. Le modifiche si salvano con **"Salva"** (disattivato senza modifiche); "Ripristina la Home predefinita" salva `null` dopo una conferma. Le righe non disponibili hanno il motivo, ma si possono accendere (diventano visibili quando la fonte c'è).
- **"Sonarr e Radarr":** per ciascuno configurato o no, e "Prova collegamento" (`Upcoming/Test`) con l'esito: versione, oppure il codice d'errore spiegato.
- Senza la funzione `home` le due card dicono "Serve il plugin 1.7.0".

L'admin ha anche la sua Home personale in Impostazioni → Home, come ogni utente.

## 9. Sicurezza

- Le chiavi di Sonarr e Radarr restano nel plugin: l'app riceve solo dati filtrati e indirizzi pubblici delle immagini.
- `POST Home/Layout` e `POST Upcoming/Test` sono solo per l'admin.
- `JellyfinSeriesId` rispetta i permessi delle librerie di chi chiama.
- Le `DisplayPreferences` sono quelle dell'utente collegato.

## 10. Testi nuovi (ARB, it + en)

| Chiave | Italiano | English |
|---|---|---|
| `homeMyRequests` | Le mie richieste | My requests |
| `homeBecauseYouWatched` | Perché hai visto {title} | Because you watched {title} |
| `homeContinueSaga` | Continua la saga | Continue the saga |
| `homeSagaProgress` | {saga} · {watched} di {total} visti | {saga} · {watched} of {total} watched |
| `homeUpcomingSeries` | Serie in arrivo | Upcoming episodes |
| `homeUpcomingMovies` | Film in arrivo | Upcoming movies |
| `upcomingEpisode` | S{season}E{episode} · {day} | S{season}E{episode} · {day} |
| `upcomingEpisodes` | S{season}E{first}–E{last} · {day} | S{season}E{first}–E{last} · {day} |
| `upcomingToday` | Oggi | Today |
| `upcomingTomorrow` | Domani | Tomorrow |
| `upcomingDigital` | Digitale · {day} | Digital · {day} |
| `homeCustomize` | Personalizza la Home | Customize Home |
| `settingsHome` | Home | Home |
| `homeRowsSourceSeerr` | da Seerr | from Seerr |
| `homeRowsSourceSonarr` | da Sonarr | from Sonarr |
| `homeRowsSourceRadarr` | da Radarr | from Radarr |
| `homeRowsMoveUp` / `homeRowsMoveDown` | Sposta su / Sposta giù | Move up / Move down |
| `homeRowsReset` | Ripristina la Home predefinita | Restore the default Home |
| `homeRowsSaveFailed` | Non salvato, riprova | Not saved, try again |
| `homeRowsAllPcs` | Vale per questo account su tutti i PC. | Applies to this account on every PC. |
| `homeRowUnavailableSeerr` | Collega il tuo account a Seerr | Link your account to Seerr |
| `homeRowUnavailableRequests` | Seerr non è configurato | Seerr is not set up |
| `homeRowUnavailableSagas` | Serve il plugin 1.5.0 | Needs plugin 1.5.0 |
| `homeRowUnavailableSonarr` | Sonarr non è configurato | Sonarr is not set up |
| `homeRowUnavailableRadarr` | Radarr non è configurato | Radarr is not set up |
| `adminHomeTitle` | Home per tutti | Home for everyone |
| `adminHomeSave` | Salva | Save |
| `adminHomeResetConfirm` | Tornare alla Home predefinita per tutti? | Restore the default Home for everyone? |
| `adminNeedsPlugin170` | Serve il plugin 1.7.0 | Needs plugin 1.7.0 |
| `adminArrTitle` | Sonarr e Radarr | Sonarr and Radarr |
| `adminArrNotConfigured` | Non configurato | Not set up |
| `adminArrOk` | Collegato (versione {version}) | Connected (version {version}) |
| `adminArrUnauthorized` | Chiave API rifiutata | API key rejected |
| `adminArrUnreachable` | Non raggiungibile: controlla l'indirizzo | Unreachable: check the address |
| `tonightButton` | Cosa guardo stasera? | What should I watch tonight? |
| `tonightTypeMovies` / `tonightTypeSeries` / `tonightTypeBoth` | Film / Serie / Entrambi | Movies / Series / Both |
| `tonightDurationAny` / `tonightDuration90` / `tonightDuration120` | Qualsiasi / Meno di 90 min / Meno di 2 h | Any / Under 90 min / Under 2 h |
| `tonightGenreAll` | Tutti i generi | All genres |
| `tonightAnother` | Un altro | Another one |
| `tonightEmpty` | Nessun titolo con questi filtri | No titles with these filters |
| `tonightClearFilters` | Togli i filtri | Clear filters |
| `tonightSeasons` | {count, plural, =1{1 stagione} other{{count} stagioni}} | {count, plural, =1{1 season} other{{count} seasons}} |

"Guarda", "Dettagli" e "Riprova" usano i testi che ci sono già (`actionPlay`, `actionDetails`, quello di `ErrorView`).

## 11. Errori e casi limite

- **L'admin spegne tutte le righe:** carosello, "Cosa guardo stasera?" e "Home vuota".
- **Due PC cambiano la Home dello stesso account:** vale l'ultimo salvataggio.
- **`DisplayPreferences`:** id e client nostri, non toccano quelle di jellyfin-web; il resto dell'oggetto si riscrive com'era.
- **Utenti con limiti sulle librerie:** "In arrivo" mostra le uscite a tutti; il clic verso il dettaglio Jellyfin solo se l'utente vede la serie.
- **Serie senza id TMDB o senza Seerr:** la card non si clicca.
- **Immagine esterna che non carica:** il segnaposto delle card.
- **Sonarr o Radarr irraggiungibili:** la riga non c'è; la card admin lo dice alla prova.
- **Date:** UTC dal plugin, mostrate nel fuso del PC; "Oggi" e "Domani" sul giorno locale.
- **Profilo cambiato:** la Home si ricompone con le `DisplayPreferences` del nuovo account.
- **Plugin < 1.7.0 o assente:** ordine predefinito, niente "In arrivo"; senza plugin anche niente richieste e saghe, come oggi.

## 12. Test

### 12.1 Plugin (xUnit)

- `Home/Layout`: `null`, elenco vuoto, id sconosciuti e doppioni scartati, solo admin per il `POST`.
- `Upcoming/Series`: filtro `hasFile`, periodo con le 12 ore, raggruppamento "E05–E06" (stesso `airDateUtc`, numeri consecutivi) e non raggruppamento (date diverse, buchi), immagini dai `remoteUrl`, `TmdbId` 0 → `null`, ordine.
- `JellyfinSeriesId`: trovato per TVDB, TMDB o IMDb; `null` se l'utente non vede la serie.
- `Upcoming/Movies`: tiene solo uscita digitale nel periodo e non scaricati (es. scaricato con uscita fisica nel periodo → fuori).
- Cache: due richieste in 15 minuti → una chiamata; errore tenuto 1 minuto; cache svuotata al salvataggio della configurazione.
- Codici d'errore: mancano dati, 401, 404, tempo scaduto, risposta non JSON.
- `Upcoming/Test` e funzioni di `Info`.

### 12.2 App

- Combinazione (§6.4): predefinito, admin con righe spente, utente con ordine parziale, righe nuove dell'admin, id sconosciuti, tutto nascosto, l'esempio di §6.4.
- `DisplayPreferencesApi`: lettura e scrittura che conservano il resto dell'oggetto; "Ripristina".
- Perché hai visto X: episodio → serie, filtro dei visti, ritorno al titolo precedente, riga assente.
- Le mie richieste: filtro e ordine, finestra dei 30 giorni.
- Continua la saga: scelta delle saghe, ordine, prossimo film, saghe finite o non iniziate escluse, solo titoli visibili.
- Etichette delle date: oggi, domani, giorno della settimana, passato → oggi, gruppo di episodi, italiano e inglese.
- Caricamento della Home (con tempo finto): tutte entro 1,5 s; una riga dopo; una riga in errore; tutte le righe di Jellyfin in errore → "Riprova"; tutte vuote; righe nascoste senza chiamate.
- `HomeRowsEditor`: trascinamento, frecce, interruttore, righe non disponibili; utente con salvataggio dopo 500 ms e ritorno indietro se fallisce; admin con "Salva" e "Ripristina" con conferma.
- "Cosa guardo stasera?": filtri e loro memoria per profilo, durata disattivata con Serie, filtro di durata e "mai iniziate", "Un altro" senza ripetizioni, nuovo gruppo di 50, nessun titolo, errore, Guarda e Dettagli.
- `/settings?section=home` e link dalla Home.
- Card admin: "Serve il plugin 1.7.0", esiti della prova.

### 12.3 Prova a mano sul server

- La Home con un utente normale e con l'admin.
- L'admin spegne una riga e la riaccende; cambia l'ordine; "Ripristina".
- L'utente sposta e nasconde righe, la ritrova uguale con un altro profilo sullo stesso account o su un altro PC; "Ripristina".
- "In arrivo" con i dati veri; clic su una serie del server e su una che non c'è.
- Sonarr irraggiungibile (indirizzo sbagliato apposta): la Home si apre lo stesso, la prova lo dice.
- "Cosa guardo stasera?" con tutti i filtri.

## 13. Preparazione

Installando il plugin 1.7.0 sul server (con l'OK dell'utente) si compilano indirizzi (`https://hashvps.proton.usbx.me/sonarr`, `…/radarr`) e chiavi presi dai `config.xml` di Sonarr e Radarr. Nessuna azione dell'utente oltre all'OK.

## 14. Rischi e punti da verificare

All'inizio del piano dell'app, sul server vero:
- un utente **non admin** legge e scrive le sue `DisplayPreferences` con un id e un client nuovi, e il `POST` conserva il resto dell'oggetto;
- come riconoscere una serie **mai iniziata** dai dati utente (`PlayedPercentage`, `UnplayedItemCount` rispetto al numero di episodi) nella risposta di `Items`;
- `SortBy=DatePlayed` con film ed episodi insieme, e `SortBy=Random` con i filtri di genere e non visti.

Altri rischi:
- l'indirizzo di Sonarr e Radarr è già cambiato una volta (`vapor` → `proton`): la card admin serve a scoprirlo;
- i "simili" di Jellyfin possono essere poco pertinenti per alcuni titoli (anime, documentari): la riga resta com'è, senza correzioni;
- le immagini da TVDB/Fanart potrebbero non caricare: c'è il segnaposto.

## 15. Piani e release

- **Tre piani:**
  - **19a — plugin 1.7.0:**
    - Home dell'admin (`Home/Layout`);
    - Sonarr e Radarr: configurazione, client, `Upcoming/Series`, `Upcoming/Movies`, cache, `Upcoming/Test`;
    - funzioni in `Info`, pagina di configurazione, manifest;
    - installazione sul server come build di prova e configurazione (§13).
  - **19b — app, la Home:**
    - verifiche di §14;
    - `HomeRowKind`, combinazione, `DisplayPreferencesApi`, client del plugin, `SocialFeatures`;
    - caricamento per riga con il tempo massimo;
    - le cinque righe nuove e le card con immagini esterne.
  - **19c — app, configurazione e "Cosa guardo stasera?":**
    - `HomeRowsEditor`, Impostazioni → Home, `/settings?section=home` e il link "Personalizza la Home";
    - card admin "Home per tutti" e "Sonarr e Radarr";
    - "Cosa guardo stasera?";
    - testi it/en rimasti, release.
- **Release:**
  - plugin **1.7.0** dal Catalogo (va bene anche con l'app 0.12);
  - poi app **0.13.0 non obbligatoria**, con le note in italiano nella bozza.
- **Alla fine**, in `docs/IDEE.md`:
  - l'idea 15 esce dalla lista;
  - tra le fatte entra "Spec M — Home su misura (plugin 1.7.0, app 0.13.0)".
