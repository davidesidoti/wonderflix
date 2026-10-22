# WonderFlix — Piano 25a: calendario delle uscite, plugin 1.13.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec S nel plugin 1.13.0:
- `GET Upcoming/Calendar?start=&end=`: le uscite di Sonarr e Radarr di un periodo (al massimo 42 giorni), anche quelle già sul server (`OnServer`), con la serie o il film di Jellyfin per chi chiama;
- le date nelle richieste (`InCinemas`, `DigitalRelease`, `NextAiring`, `NextSeasonNumber`, `NextEpisodeNumber`) e lo stato nuovo `AwaitingRelease`;
- la funzione `calendar` in `Info`, la versione 1.13.0 e una build di prova sul server.

L'app arriva nel piano 25b: si appoggia ai JSON di "Global Constraints", quindi **i nomi delle proprietà JSON non si cambiano**.

**Architecture:**
- `IArrClient` impara quattro letture nuove (film per id TMDB, lookup TMDB, serie di Sonarr, episodi di una serie).
- `ArrReadCache<T>` è una cache con chiave, scadenza (15 min, 1 min per un errore), una lettura sola per chiave e un numero massimo di voci. La usano il calendario e le date. Le cache di `UpcomingService` restano come sono.
- `UpcomingBuilder` impara `OnServer`, l'opzione per tenere le uscite già scaricate e il collegamento dei film (`MatchMovies`). `ISeriesIndex` impara `GetMovies()`.
- `CalendarService` dà il calendario. `UpcomingController` espone `GET Upcoming/Calendar`.
- `ReleaseDatesService` dà le date di un film o di una serie e non lancia mai. `ReleaseRules.IsAwaitingRelease` è la regola dello stato nuovo. `RequestsService` li usa in `ToDtoAsync`.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-22-wonderflix-calendario-uscite-design.md` (§2, §3, §5, §6, §9.1, §10, §11).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 8):
1. **400 senza corpo** per un periodo non valido, come gli altri controller del plugin (`return BadRequest();`).
2. **Date dei film per id TMDB**, non la libreria intera di Radarr (5,4 MB, spec §2): prima `movie?tmdbId=`, poi, se l'elenco è vuoto, `movie/lookup/tmdb?tmdbId=`.
3. **Date dei film solo dove servono:** un film con stato `Available`, `Declined` o `Failed` non chiede niente a Radarr, e i suoi campi restano null (l'app non li mostra: spec §7.5). Le serie le chiedono sempre.
4. **Numero del prossimo episodio** con `episode?seriesId=`, solo per una serie con `nextAiring`. Se quella lettura fallisce, `NextAiring` resta e i numeri sono null.
5. **Abbinamento delle serie:** `tvdbId` del media di Seerr (campo nuovo `SeerrRequestMedia.TvdbId`), poi `tmdbId`.
6. **`calendar`** si calcola dentro `WatchPartyProtocol.FeaturesWith`, senza cambiarne la firma: c'è quando c'è almeno una tra `upcomingSeries` e `upcomingMovies`, e viene subito dopo di loro.
7. **I campi nuovi delle richieste si scrivono anche null**, come `Year` e `PosterPath` di `MediaRequestDto`. Anche quelli del calendario.
8. **Le date null in Radarr:** `ReleaseRules` con `MovieDates` null (Radarr non configurato o in errore) → **non** `AwaitingRelease`: senza le date non si sa.

## Global Constraints

- Plugin **1.13.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9.
- **Endpoint** sotto `/WonderFlixWatchParty`:
  - `GET Upcoming/Calendar?start=YYYY-MM-DD&end=YYYY-MM-DD` in `UpcomingController` (`[Authorize]` sulla classe, già c'è). `end` escluso; `1 ≤ end − start ≤ 42` giorni; date con `DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _)`; altrimenti 400. Sempre 200 con una risposta, anche con Sonarr o Radarr in errore.
  - Le richieste non cambiano endpoint: cambiano solo i campi di `MediaRequestDto` e uno stato.
- **JSON** (PascalCase, come il resto del plugin; tutti i campi scritti anche se null, decisione 7):
  - `CalendarResponse`: `{"Episodes":[CalendarEpisodeDto…],"Movies":[CalendarMovieDto…],"SeriesError":…,"MoviesError":…}`;
  - `CalendarEpisodeDto`: `SeriesName`, `SeasonNumber`, `EpisodeNumber`, `LastEpisodeNumber`, `EpisodeTitle`, `AirDateUtc`, `TvdbId`, `TmdbId`, `PosterUrl`, `BackdropUrl`, `JellyfinSeriesId`, `OnServer`;
  - `CalendarMovieDto`: `Title`, `Year`, `TmdbId`, `DigitalRelease`, `PosterUrl`, `BackdropUrl`, `JellyfinItemId`, `OnServer`;
  - `MediaRequestDto`, in fondo: `InCinemas`, `DigitalRelease`, `NextAiring` (`DateTimeOffset?`), `NextSeasonNumber`, `NextEpisodeNumber` (`int?`);
  - `RequestStatuses.AwaitingRelease = "AwaitingRelease"`;
  - errori del calendario: i codici di `UpcomingErrors` (`NotConfigured`, `Unauthorized`, `Unreachable`).
- **Valori:**
  - `CalendarService.MaxDays = 42`; `CalendarService.MaxCachedPeriods = 6` (per servizio);
  - periodo chiesto a Sonarr e Radarr: da `start` 00:00 UTC − 1 giorno a `end` 00:00 UTC + 1 giorno (`CalendarService.Margin = TimeSpan.FromDays(1)`);
  - `ArrReadCache`: `CacheFor = 15 min`, `ErrorCacheFor = 1 min` (gli stessi valori di `UpcomingService`, riusati con `UpcomingService.CacheFor`/`ErrorCacheFor`);
  - `ReleaseDatesService.MaxCachedMovies = 500`, `MaxCachedSeriesEpisodes = 200`;
  - `ReleaseRules.RecentCinemaWindow = TimeSpan.FromDays(365)` (spec: "ultimi 12 mesi").
- **`Info`:** `Version` "1.13.0", `Protocol` 1, `Features` con `"calendar"` dopo `"upcomingMovies"` (o dopo `"upcomingSeries"` se c'è solo Sonarr).
- **Id e date:** id di Jellyfin in formato `"N"`; `TimeProvider`, mai `DateTimeOffset.UtcNow`.
- **Log:** **mai titoli, chiavi, indirizzi o query**, solo servizio, percorso senza query, id e codici d'errore. `Warning` per Sonarr o Radarr che non rispondono (come `UpcomingService`).
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.

## Review Focus

1. **Sonarr fermo e Radarr no (e il contrario):** il calendario risponde 200 con i film e `SeriesError`, non un errore generale; e l'elenco delle richieste non fallisce mai per Sonarr o Radarr. Test: Task 4 (`OneServiceFailingKeepsTheOther`), Task 6 (`ArrFailuresNeverBreakTheRequestList`).
2. **Chi sfoglia molti mesi:** la cache del calendario non supera 6 periodi per servizio; il settimo toglie il più vecchio. Test: Task 2 (`TheOldestEntryGoesWhenFull`), Task 4 (`PeriodsAreCachedSeparately`).
3. **Un film vecchio senza data digitale** resta `Approved`; un film uscito al cinema 3 mesi fa senza data digitale è `AwaitingRelease`; uno già scaricato mai. Test: Task 5 (`AwaitingReleaseRules`).
4. **Un blocco di episodi in parte scaricato:** è `OnServer` solo se lo sono tutti. Test: Task 3 (`ABlockIsOnServerOnlyWhenAllItsEpisodesAre`).
5. **Più richieste dello stesso film nella pagina** (o 50 righe insieme): una lettura sola a Radarr per film. Test: Task 5 (`OneReadPerMovieEvenWhenAskedTogether`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
  - Messaggi su una riga sola e senza virgolette interne: `git commit -m "feat(plugin): …"`.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `dotnet` o `git`, prima rinfresca il PATH:
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-25a`): fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.13.0`.
- **Test:**
  - un gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj ha `TreatWarningsAsErrors`), poi `dotnet build-server shutdown`;
  - la base di partenza è di **1111** test verdi alla fine del piano 24a; i piani 24b e 24c non hanno toccato il plugin. Il primo implementatore controlla il numero e lo scrive nel registro.
- **Formattazione:** ogni file tiene le sue terminazioni di riga (working copy CRLF, indice LF; i file nuovi vanno bene con LF). UTF-8 con gli strumenti di modifica dei file, mai `Set-Content`/`Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese; ogni tipo nuovo ha il suo `/// <summary>` con il riferimento alla spec ("spec S §6.1");
  - durate e limiti come costanti nominate e commentate; `TimeProvider`;
  - DTO `record` con `[property: JsonPropertyName("…")]`; modelli di Sonarr/Radarr come classi con proprietà `{ get; set; }` in `Home/ArrJson.cs`;
  - `Lock` di .NET 9; id `"N"`.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo; preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-22 sul codice di `main` (`d6a2959`) e sul server.

- **`ArrClient.GetAsync<T>(kind, path, ct)`** (privato) fa già tutto: chiave, tempo massimo di 10 s, errori come `ArrException` (`NotConfigured`, `Unauthorized`, `Unreachable`), log senza query. Le letture nuove sono una riga ciascuna, come `GetMoviesAsync`.
- **`UpcomingService`:** `Fetched<T>(Items, Error)`, `UpcomingErrors.Code(ArrError)`, la cache a slot, `ReadLibrarySeries()` e `CanSee` con il `try/catch` che toglie solo il collegamento. `CalendarService` copia questi due aiutanti (sono privati).
- **`UpcomingBuilder.Episodes`/`Movies`** oggi scartano `HasFile = true`; `Episodes` unisce i blocchi (stessa serie, stagione e `AirDateUtc`, numeri consecutivi).
- **`ISeriesIndex`** ha solo `GetSeries()`; `JellyfinSeriesIndex` fa una query `InternalItemsQuery` senza utente, in ordine di id. `FakeSeriesIndex` (`Series`, `Fails`).
- **`FakeArrClient`** (`Episodes`, `Movies`, `Status`, liste di chiamate) e **`FakeArrSettings`** (`Sonarr`, `Radarr`, `SeriesDays`, `MovieDays`; `ArrEndpoint.None`). `ArrClientTests` usa `FakeSeerrHttp` e indirizzi `https://arr.example/sonarr` e `/radarr` con chiavi `sonarr-key`/`radarr-key`.
- **`RequestsService(ISeerrClient, SeerrUserMap, SeerrTitleCache)`** si costruisce in `RequestsServiceTests.cs` (righe 24 e 58) e in `RequestsControllerTests.cs` (riga 35). `ToDtoAsync` costruisce `MediaRequestDto`; `ListAsync` fa `Task.WhenAll` sulle righe.
- **`SeerrMapping.RequestStatus(SeerrRequest)`** è lo switch della Spec I §7.3; `Approved` è l'ultimo caso.
- **`SeerrRequestMedia`** (`TmdbId`, `MediaType`, `Status`, `JellyfinMediaId`, `DownloadStatus`): Seerr manda anche `tvdbId` (null per i film).
- **`WatchPartyProtocol.FeaturesWith(bool requests, bool upcomingSeries, bool upcomingMovies)`**; `InfoControllerTests` controlla `"1.12.0"` e le funzioni.
- **DI:** `PluginServiceRegistrator` registra `ISeriesIndex`, `UpcomingService`, `RequestsService` come singleton; `ServiceRegistrationTests` conta 8 servizi in background (non cambiano).
- **Server** (spec §2): `movie?tmdbId=` dà un elenco con quel film solo; `movie/lookup/tmdb?tmdbId=` risponde per un film non in libreria, con `inCinemas`, `digitalRelease`, `physicalRelease`; `series` ha `id`, `tvdbId`, `tmdbId`, `nextAiring`. Le date dei film sono a mezzanotte UTC.

## File

| File | Responsabilità |
|---|---|
| `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs` | le quattro letture nuove e i campi nuovi dei modelli |
| `Home/ArrReadCache.cs` | cache con chiave, scadenza, lettura sola, limite di voci |
| `Home/UpcomingBuilder.cs`, `Home/ISeriesIndex.cs`, `Server/JellyfinSeriesIndex.cs` | `OnServer`, uscite già scaricate, film della libreria |
| `Home/CalendarService.cs`, `Protocol/CalendarDtos.cs`, `Api/UpcomingController.cs` | il calendario |
| `Home/ReleaseRules.cs`, `Home/ReleaseDatesService.cs` | date di film e serie, regola di `AwaitingRelease` |
| `Protocol/RequestsDtos.cs`, `Seerr/SeerrJson.cs`, `Hub/RequestsService.cs` | campi nuovi delle richieste e stato nuovo |
| `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `Plugin.cs`, `Api/InfoController.cs`, `../meta.template.json`, `../README.md` | montaggio, `Info`, versione, documentazione |

I percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test, scritti `Tests/…`), se non è detto altro.

---

### Task 1: letture nuove di Sonarr e Radarr

**Files:**
- Modify: `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs`, `Seerr/SeerrJson.cs` (`SeerrRequestMedia.TvdbId`)
- Modify (test): `Tests/FakeArrClient.cs`
- Test: `Tests/ArrClientTests.cs`

**Interfaces:**
- Produces:
  - `RadarrMovie` in più: `DateTimeOffset? InCinemas`, `DateTimeOffset? PhysicalRelease`.
  - `SonarrSeries` in più: `int Id`, `DateTimeOffset? NextAiring`.
  - `SeerrRequestMedia` in più: `int? TvdbId`.
  - `IArrClient` in più:
    - `Task<IReadOnlyList<RadarrMovie?>> FindMoviesAsync(int tmdbId, CancellationToken cancellationToken)` → Radarr `movie?tmdbId={tmdbId}`;
    - `Task<RadarrMovie> LookupMovieAsync(int tmdbId, CancellationToken cancellationToken)` → Radarr `movie/lookup/tmdb?tmdbId={tmdbId}`;
    - `Task<IReadOnlyList<SonarrSeries?>> GetSeriesAsync(CancellationToken cancellationToken)` → Sonarr `series`;
    - `Task<IReadOnlyList<SonarrEpisode?>> GetSeriesEpisodesAsync(int seriesId, CancellationToken cancellationToken)` → Sonarr `episode?seriesId={seriesId}`.
    Gli id vanno nella query con `CultureInfo.InvariantCulture`.
  - `FakeArrClient` in più: gestori `FindMovies` (`Func<int, Task<IReadOnlyList<RadarrMovie?>>>`, predefinito elenco vuoto), `Lookup` (`Func<int, Task<RadarrMovie>>`, predefinito `ArrException(ArrError.Unreachable)`), `Series` (`Func<Task<IReadOnlyList<SonarrSeries?>>>`, predefinito vuoto), `SeriesEpisodes` (`Func<int, Task<IReadOnlyList<SonarrEpisode?>>>`, predefinito vuoto); liste `FindMovieCalls`, `LookupCalls`, `SeriesCalls` (contatore `int`), `SeriesEpisodeCalls`, sotto `_lock` come le altre.

- [ ] **Step 1: test che falliscono** in `Tests/ArrClientTests.cs`, con le risposte del server accorciate come le costanti che ci sono:
  - `FindingAMovieAsksRadarrByTmdbId`: risposta `[{"title":"Coco","tmdbId":354912,"inCinemas":"2017-10-27T00:00:00Z","digitalRelease":"2017-11-30T00:00:00Z","physicalRelease":"2018-02-27T00:00:00Z","hasFile":true,"id":1}]`. Indirizzo `https://arr.example/radarr/api/v3/movie?tmdbId=354912`, chiave `radarr-key`; il film ha le tre date e `HasFile` vero.
  - `TheLookupAsksRadarrForAMovieNotInTheLibrary`: risposta `{"title":"Avatar: Fuoco e cenere","tmdbId":83533,"inCinemas":"2025-12-17T00:00:00Z","digitalRelease":"2026-03-31T00:00:00Z","physicalRelease":"2026-05-19T00:00:00Z"}`. Indirizzo `…/radarr/api/v3/movie/lookup/tmdb?tmdbId=83533`; tre date, `HasFile` falso.
  - `TheSeriesListHasTheNextAiring`: risposta `[{"title":"Dexter: Resurrection","tvdbId":452595,"tmdbId":259909,"nextAiring":"2026-11-02T01:00:00Z","id":40}]`. Indirizzo `https://arr.example/sonarr/api/v3/series`; `Id` 40, `NextAiring` 2026-11-02 01:00 UTC.
  - `TheEpisodesOfASeriesAreAskedBySeriesId`: indirizzo `…/sonarr/api/v3/episode?seriesId=40`; risposta con un episodio `{"seriesId":40,"seasonNumber":1,"episodeNumber":4,"airDateUtc":"2026-11-02T01:00:00Z","hasFile":false}`.
  - Aggiungi le quattro letture al test del log esistente (`TheLogHasThePathButNeverTheKeyOrTheQuery`): nel registro `movie`, `movie/lookup/tmdb`, `series`, `episode`, mai `tmdbId=` né `seriesId=`.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~ArrClientTests"`): FAIL, metodi mancanti.
- [ ] **Step 3: il codice** con le firme sopra, più `FakeArrClient`.
- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): read movies, lookups, series and episodes from Radarr and Sonarr"`

### Task 2: `ArrReadCache<T>`

**Files:**
- Create: `Home/ArrReadCache.cs`
- Test: `Tests/ArrReadCacheTests.cs`

**Interfaces:**
- Produces:
  - `public sealed record ArrRead<T>(T? Value, string? Error)`: una lettura riuscita (`Error` null) o un codice di `UpcomingErrors`.
  - `public sealed class ArrReadCache<T>(TimeProvider time, int maxEntries, ILogger logger)`:
    - `Task<ArrRead<T>> GetAsync(string key, Func<Task<T>> read)`.
    - Regole, come le slot di `UpcomingService` ma per più chiavi:
      - una voce in corso vale sempre; una finita vale fino alla scadenza: `UpcomingService.CacheFor` se riuscita, `UpcomingService.ErrorCacheFor` se in errore;
      - `ArrException` → `ArrRead(default, UpcomingErrors.Code(ex.Error))`; qualunque altra eccezione → `Warning` nel log (senza la chiave della cache, che contiene la chiave API) e `UpcomingErrors.Unreachable`; `GetAsync` non lancia mai;
      - la lettura parte con `Task.Run`, senza il token di chi chiama, come `UpcomingService.Cached`;
      - con `maxEntries` voci, una chiave nuova toglie la voce **finita** inserita per prima; se sono tutte in corso, si aggiunge lo stesso (il limite vale per le voci finite).
    - Le chiavi le compone chi chiama, con indirizzo e chiave del servizio dentro (così un cambio d'impostazioni non usa la vecchia voce, come `UpcomingService.Key`).

- [ ] **Step 1: test che falliscono** in `Tests/ArrReadCacheTests.cs` (con `FakeTimeProvider`, `RecordingLogger<…>`):
  - `AReadIsKeptForFifteenMinutes`: due `GetAsync("a", …)` → una lettura; dopo `Advance(15 min)` → due.
  - `AnErrorIsKeptForAMinute`: `ArrException(ArrError.Unauthorized)` → `Error == "Unauthorized"`; dopo 59 s ancora una lettura, dopo 1 min due.
  - `AnUnexpectedFailureIsUnreachableAndLogged`: `InvalidOperationException` → `"Unreachable"`, un `Warning` nel registro, nessuna eccezione.
  - `CallersAskingTogetherShareOneRead`: la lettura aspetta un `TaskCompletionSource`; due chiamate prima che finisca → una sola lettura, stessa risposta.
  - `KeysAreSeparate`: `"a"` e `"b"` → due letture.
  - `TheOldestEntryGoesWhenFull`: `maxEntries` 2; `"a"`, `"b"`, `"c"` → `"a"` si rilegge, `"c"` no.
- [ ] **Step 2: i test falliscono** (`ArrReadCacheTests`).
- [ ] **Step 3: il codice.** Un `Dictionary<string, Entry>` e una `LinkedList<string>` dell'ordine d'inserimento, sotto un `Lock`.
- [ ] **Step 4: i test passano** (poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): keyed cache for Sonarr and Radarr reads"`

### Task 3: uscite già sul server e film della libreria

**Files:**
- Modify: `Home/UpcomingBuilder.cs`, `Home/ISeriesIndex.cs`, `Server/JellyfinSeriesIndex.cs`
- Modify (test): `Tests/FakeSeriesIndex.cs`
- Test: `Tests/UpcomingBuilderTests.cs`

**Interfaces:**
- Produces:
  - `UpcomingEpisodeGroup` e `UpcomingMovie` in più: `public bool OnServer { get; init; }`. `UpcomingMovie` anche `public IReadOnlyList<Guid> LibraryItemIds { get; init; } = [];`.
  - `UpcomingBuilder.Episodes(IEnumerable<SonarrEpisode?> episodes, DateTimeOffset from, DateTimeOffset to, bool includeDownloaded = false)`: con `includeDownloaded` tiene anche `HasFile = true`; `OnServer` = `HasFile`; un blocco unito è `OnServer` solo se tutti i suoi episodi lo sono. Senza `includeDownloaded` tutto come oggi.
  - `UpcomingBuilder.Movies(IEnumerable<RadarrMovie?> movies, DateTimeOffset from, DateTimeOffset to, bool includeDownloaded = false)`: lo stesso per i film.
  - `UpcomingBuilder.MatchMovies(IReadOnlyList<UpcomingMovie> movies, IEnumerable<LibraryMovie> library)`: `LibraryItemIds` = i film di Jellyfin con lo stesso id TMDB (senza badare a spazi e maiuscole, come `Same`), senza doppioni, nell'ordine della libreria.
  - `public sealed record LibraryMovie(Guid Id, string? TmdbId);` in `Home/ISeriesIndex.cs`; `ISeriesIndex.GetMovies()` → `IReadOnlyList<LibraryMovie>` (commento: "Tutti i film, di tutte le librerie, senza guardare l'utente"). `JellyfinSeriesIndex.GetMovies()`: la stessa query di `GetSeries()` con `BaseItemKind.Movie`, solo l'id TMDB, in ordine di id.
  - `FakeSeriesIndex` in più: `List<LibraryMovie> Movies`; `GetMovies()` lancia con `Fails` come `GetSeries()`.

- [ ] **Step 1: test che falliscono** in `Tests/UpcomingBuilderTests.cs`:
  - `DownloadedEpisodesStayOnlyWhenAsked`: un episodio scaricato e uno no; senza l'opzione uno solo, con l'opzione due, con `OnServer` vero solo per quello scaricato.
  - `ABlockIsOnServerOnlyWhenAllItsEpisodesAre`: tre episodi in blocco (stesso `AirDateUtc`, 1–3), il secondo non scaricato → una voce 1–3 con `OnServer` falso; tutti scaricati → vero.
  - `DownloadedMoviesStayOnlyWhenAsked`: come il primo, per i film.
  - `MoviesAreMatchedByTmdbId`: libreria con due film con `" 1058424 "` e `"1058424"` e uno diverso → `LibraryItemIds` con i due, nell'ordine dato.
  - I test di oggi restano verdi senza modifiche.
- [ ] **Step 2: i test falliscono** (`UpcomingBuilderTests`).
- [ ] **Step 3: il codice.** Nel ciclo di `Episodes`, l'unione di un blocco fa `OnServer = current.OnServer && episode.HasFile`.
- [ ] **Step 4: i test passano** (poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): downloaded releases and library movies for the calendar"`

### Task 4: `CalendarService` e `GET Upcoming/Calendar`

**Files:**
- Create: `Home/CalendarService.cs`, `Protocol/CalendarDtos.cs`
- Modify: `Api/UpcomingController.cs`, `PluginServiceRegistrator.cs` (`AddSingleton<CalendarService>()`, accanto a `UpcomingService`)
- Test: `Tests/CalendarServiceTests.cs`, `Tests/UpcomingControllerTests.cs`

**Interfaces:**
- Consumes: Task 2 (`ArrReadCache<T>`, `ArrRead<T>`), Task 3 (`includeDownloaded`, `OnServer`, `MatchMovies`, `GetMovies`).
- Produces:
  - `Protocol/CalendarDtos.cs`: `CalendarEpisodeDto`, `CalendarMovieDto`, `CalendarResponse(IReadOnlyList<CalendarEpisodeDto> Episodes, IReadOnlyList<CalendarMovieDto> Movies, string? SeriesError, string? MoviesError)`, con i campi di "Global Constraints".
  - `public sealed class CalendarService(IArrClient client, IArrSettings settings, ISeriesIndex index, ILibraryAccess library, TimeProvider time, ILogger<CalendarService> logger)`:
    - costanti `MaxDays = 42`, `MaxCachedPeriods = 6`, `Margin = TimeSpan.FromDays(1)`;
    - `public static bool IsValidPeriod(DateOnly start, DateOnly end)`: `end > start` e `end.DayNumber - start.DayNumber <= MaxDays`;
    - `Task<CalendarResponse> GetAsync(Guid userId, DateOnly start, DateOnly end, CancellationToken cancellationToken)` (chiamato solo con un periodo valido).
  - Regole di `GetAsync`:
    - `from` = `start` a 00:00 UTC − `Margin`, `to` = `end` a 00:00 UTC + `Margin`;
    - Sonarr e Radarr in parallelo, ognuno con la sua `ArrReadCache<…>` (`MaxCachedPeriods` voci), chiave `"{url}\n{apiKey}\n{start:yyyy-MM-dd}\n{end:yyyy-MM-dd}"`;
    - un servizio non configurato → lista vuota ed errore `NotConfigured`, senza chiamarlo;
    - in cache vanno le voci già costruite: `UpcomingBuilder.Episodes(…, includeDownloaded: true)` con `MatchSeries`, `UpcomingBuilder.Movies(…, includeDownloaded: true)` con `MatchMovies`. La libreria si legge dentro la lettura, con un `try/catch` come `UpcomingService.ReadLibrarySeries` (anche per i film);
    - dopo la cache, per l'utente: il primo id della libreria che vede (`library.CanSee`, con il `try/catch` di `UpcomingService.CanSee`) diventa `JellyfinSeriesId` / `JellyfinItemId` in formato `"N"`, altrimenti null;
    - `GetAsync` aspetta le due letture con `.WaitAsync(cancellationToken)`.
  - `UpcomingController` in più:

    ```csharp
    [HttpGet("Calendar")]
    public async Task<ActionResult<CalendarResponse>> GetCalendar([FromQuery] string? start, [FromQuery] string? end)
    ```

    Date non valide o periodo non valido → `BadRequest()`. Il controller prende `CalendarService` nel costruttore, dopo `UpcomingService`.

- [ ] **Step 1: test che falliscono.**
  `Tests/CalendarServiceTests.cs` (con `Now` = 2026-10-22 14:00 UTC, `FakeArrClient`, `FakeArrSettings`, `FakeSeriesIndex`, `FakeServer` come `UpcomingServiceTests`):
  - `IsValidPeriodChecksOrderAndLength`: `(1 ott, 1 ott)` falso, `(1 ott, 2 ott)` vero, `(28 set, 9 nov)` (42 giorni) vero, `(28 set, 10 nov)` falso.
  - `TheServicesAreAskedWithADayOfMarginEachSide`: periodo 28 set – 9 nov → Sonarr e Radarr chiamati con 27 set 00:00 UTC e 10 nov 00:00 UTC.
  - `DownloadedReleasesAreOnServer`: un episodio e un film scaricati, uno e uno no → quattro voci, `OnServer` giusto.
  - `EachUserGetsTheLibraryIdsOnlyWhenTheySeeThem`: una serie e un film della libreria visibili a Mario e non a Luigi → Mario ha `JellyfinSeriesId` e `JellyfinItemId` in `"N"`, Luigi null.
  - `OneServiceFailingKeepsTheOther`: Sonarr lancia `ArrException(ArrError.Unreachable)`, Radarr risponde → `SeriesError == "Unreachable"`, `Episodes` vuoto, `Movies` con il film, `MoviesError` null.
  - `NotConfiguredServicesAreNotCalled`: Sonarr `ArrEndpoint.None` → `SeriesError == "NotConfigured"`, nessuna chiamata a Sonarr.
  - `PeriodsAreCachedSeparately`: lo stesso periodo due volte → una lettura per servizio; sette periodi diversi, poi il primo di nuovo → si rilegge.
  - `TheLibraryFailingKeepsTheReleases`: `FakeSeriesIndex.Fails` → le voci ci sono, senza id della libreria.
  `Tests/UpcomingControllerTests.cs`:
  - `TheCalendarIsReadForTheCaller`: `?start=2026-10-01&end=2026-11-01` → 200 con le voci, `JellyfinSeriesId` per chi chiama.
  - `ABadPeriodIsABadRequest` (`[Theory]`): `start` mancante, `"2026-10-1"`, `"01/10/2026"`, `end` uguale a `start`, 43 giorni → `BadRequestResult`.
- [ ] **Step 2: i test falliscono** (`CalendarServiceTests|UpcomingControllerTests`).
- [ ] **Step 3: il codice** con le firme sopra. I DTO si fanno da `UpcomingEpisodeGroup` e `UpcomingMovie` come `UpcomingService.ToDto`.
- [ ] **Step 4: i test passano** (poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): monthly release calendar endpoint"`

### Task 5: date delle uscite e regola di `AwaitingRelease`

**Files:**
- Create: `Home/ReleaseRules.cs`, `Home/ReleaseDatesService.cs`
- Test: `Tests/ReleaseRulesTests.cs`, `Tests/ReleaseDatesServiceTests.cs`

**Interfaces:**
- Consumes: Task 1 (letture nuove), Task 2 (`ArrReadCache<T>`).
- Produces:
  - `public sealed record MovieDates(DateTimeOffset? InCinemas, DateTimeOffset? DigitalRelease, DateTimeOffset? PhysicalRelease, bool HasFile);`
  - `public sealed record SeriesNext(DateTimeOffset NextAiring, int? SeasonNumber, int? EpisodeNumber);`
  - `public static class ReleaseRules` con `RecentCinemaWindow` e `public static bool IsAwaitingRelease(MovieDates? dates, DateTimeOffset now)`:
    - `dates` null o `HasFile` → falso;
    - `DigitalRelease` non null → `DigitalRelease > now`;
    - altrimenti vero solo se `PhysicalRelease` è null o `> now`, **e** `InCinemas` è null o `> now - RecentCinemaWindow`.
  - `public sealed class ReleaseDatesService(IArrClient client, IArrSettings settings, TimeProvider time, ILogger<ReleaseDatesService> logger)`, costanti `MaxCachedMovies = 500`, `MaxCachedSeriesEpisodes = 200`:
    - `Task<MovieDates?> GetMovieAsync(int tmdbId, CancellationToken cancellationToken)`: Radarr non configurato o `tmdbId <= 0` → null senza chiamate. Altrimenti, in una `ArrReadCache<MovieDates>` (chiave con indirizzo, chiave API e `tmdbId`): il primo film non null di `FindMoviesAsync` (con `HasFile`), altrimenti `LookupMovieAsync` (con `HasFile` falso). Un errore → null.
    - `Task<SeriesNext?> GetSeriesAsync(int? tvdbId, int tmdbId, CancellationToken cancellationToken)`: Sonarr non configurato → null. La libreria di Sonarr (`GetSeriesAsync`) in una `ArrReadCache<IReadOnlyList<SonarrSeries?>>` da 1 voce; la serie con lo stesso `TvdbId` (se `tvdbId` > 0), altrimenti con lo stesso `TmdbId` (se > 0). Senza serie o senza `NextAiring` → null. Poi gli episodi di quella serie (`GetSeriesEpisodesAsync`) in una `ArrReadCache<IReadOnlyList<SonarrEpisode?>>` (`MaxCachedSeriesEpisodes`, chiave con l'id della serie): l'episodio con `AirDateUtc == NextAiring`, preferendo stagione > 0, poi stagione ed episodio più bassi. Episodi in errore o nessun episodio con quella data → `SeriesNext(NextAiring, null, null)`.
    - Non lancia mai, tranne `OperationCanceledException` per chi chiama: le letture passano dalla cache, che non lancia; il resto è in un `try/catch` con un `Warning` (solo id).
    - Le date si leggono con `.WaitAsync(cancellationToken)`.

- [ ] **Step 1: test che falliscono.**
  `Tests/ReleaseRulesTests.cs` (`Now` = 2026-10-22 12:00 UTC), un `[Fact]` per riga o un `[Theory]` con i casi (nome `AwaitingReleaseRules`):

  | Date | Atteso |
  |---|---|
  | null | falso |
  | digitale 12 nov 2026 | vero |
  | digitale 20 ott 2026 | falso |
  | digitale 12 nov 2026, `HasFile` | falso |
  | digitale null, cinema 25 set 2026 | vero |
  | digitale null, cinema 18 dic 2026 | vero |
  | digitale null, cinema 1 ott 2024 | falso |
  | digitale null, cinema null, fisico null | vero |
  | digitale null, cinema 25 set 2026, fisico 1 ott 2026 | falso |

  `Tests/ReleaseDatesServiceTests.cs`:
  - `AMovieInRadarrGivesItsDates`: `FindMovies` con il film (tre date, `HasFile` falso) → `MovieDates` con le tre date; nessun lookup.
  - `AMovieNotInRadarrUsesTheLookup`: `FindMovies` vuoto, `Lookup` con le date → le date, `HasFile` falso.
  - `RadarrFailingGivesNoDates`: `FindMovies` lancia `ArrException` → null, e nessuna eccezione.
  - `OneReadPerMovieEvenWhenAskedTogether`: dieci `GetMovieAsync(83533)` in parallelo → una chiamata a `FindMovies`.
  - `NotConfiguredAsksNothing`: Radarr e Sonarr `ArrEndpoint.None` → null e null, nessuna chiamata.
  - `TheSeriesIsFoundByTvdbThenTmdb`: due serie in Sonarr; `GetSeriesAsync(452595, 0)` trova la prima per TVDB; `GetSeriesAsync(null, 259909)` la trova per TMDB; una sola lettura di `series`.
  - `TheNextEpisodeHasItsNumbers`: serie 40 con `NextAiring` 2 nov 01:00; episodi S00E01 e S01E04 con quella data → `SeriesNext(2 nov, 1, 4)`.
  - `EpisodesFailingKeepTheDate`: `SeriesEpisodes` lancia → `SeriesNext(2 nov, null, null)`.
  - `ASeriesWithoutNextAiringHasNoNext`: → null, nessuna lettura degli episodi.
- [ ] **Step 2: i test falliscono** (`ReleaseRulesTests|ReleaseDatesServiceTests`).
- [ ] **Step 3: il codice** con le firme sopra.
- [ ] **Step 4: i test passano** (poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): release dates for requested movies and series"`

### Task 6: date e `AwaitingRelease` nelle richieste

**Files:**
- Modify: `Protocol/RequestsDtos.cs`, `Hub/RequestsService.cs`, `PluginServiceRegistrator.cs` (solo `AddSingleton<ReleaseDatesService>()`, accanto a `UpcomingService`)
- Modify (test): `Tests/RequestsServiceTests.cs` (righe 24 e 58), `Tests/RequestsControllerTests.cs` (riga 35)
- Test: `Tests/RequestsServiceTests.cs`

**Interfaces:**
- Consumes: Task 1 (`SeerrRequestMedia.TvdbId`), Task 5 (`ReleaseDatesService`, `ReleaseRules`, `MovieDates`, `SeriesNext`).
- Produces:
  - `RequestStatuses.AwaitingRelease = "AwaitingRelease"`.
  - `MediaRequestDto` con cinque parametri nuovi **in fondo**: `DateTimeOffset? InCinemas`, `DateTimeOffset? DigitalRelease`, `DateTimeOffset? NextAiring`, `int? NextSeasonNumber`, `int? NextEpisodeNumber` (nomi JSON uguali).
  - `RequestsService(ISeerrClient seerr, SeerrUserMap users, SeerrTitleCache titles, ReleaseDatesService dates, TimeProvider time)`.
  - In `ToDtoAsync`:
    - stato da `SeerrMapping.RequestStatus(request)`, come oggi;
    - **film** con stato diverso da `Available`, `Declined`, `Failed` (decisione 3): `dates.GetMovieAsync(tmdbId)`; se lo stato è `Approved` e `ReleaseRules.IsAwaitingRelease(movieDates, time.GetUtcNow())` → `AwaitingRelease`; `InCinemas` e `DigitalRelease` dalle date;
    - **serie**: `dates.GetSeriesAsync(request.Media?.TvdbId, tmdbId)` → `NextAiring`, `NextSeasonNumber`, `NextEpisodeNumber`;
    - le date si chiedono insieme al titolo (`Task.WhenAll` o due `await` dopo aver fatto partire entrambi), non una dopo l'altra.
  - `CreatedRequestDto` non cambia.

- [ ] **Step 1: test che falliscono** in `Tests/RequestsServiceTests.cs`. Il costruttore dei test esistenti prende un `ReleaseDatesService` con `FakeArrSettings` non configurato (`ArrEndpoint.None` per entrambi), così i test di oggi non cambiano risultato. Test nuovi, con un `FakeArrClient` e Radarr/Sonarr configurati:
  - `AnApprovedMovieNotYetOutDigitallyIsAwaitingRelease`: richiesta approvata (`SeerrCodes.RequestApproved`, nessun download), Radarr con digitale 12 nov 2026 e cinema 25 set 2026 → `Status == "AwaitingRelease"`, `InCinemas` e `DigitalRelease` giusti.
  - `AnApprovedMovieAlreadyOutStaysApproved`: digitale 20 ott 2026 → `"Approved"`, con le date.
  - `PendingAndDownloadingDoNotChange`: una in attesa con digitale futuro → `"Pending"` con le date; una approvata con un download → `"Downloading"`.
  - `AvailableMoviesAskRadarrNothing`: richiesta completata → `"Available"`, date null, nessuna chiamata a `FindMovies`.
  - `ASeriesGetsItsNextEpisode`: richiesta di serie con `Media.TvdbId` 452595 → `NextAiring`, `NextSeasonNumber` 1, `NextEpisodeNumber` 4.
  - `ArrFailuresNeverBreakTheRequestList`: `FindMovies` e `Series` lanciano `ArrException` → `ListAsync` dà le righe con i campi null e lo stato di Seerr (`"Approved"`).
  - JSON: in un test di serializzazione (`ProtocolJsonTests` o qui) una `MediaRequestDto` con i campi nuovi null li scrive come `null`, con i nomi `InCinemas`, `DigitalRelease`, `NextAiring`, `NextSeasonNumber`, `NextEpisodeNumber`.
- [ ] **Step 2: i test falliscono** (`RequestsServiceTests|RequestsControllerTests|ProtocolJsonTests`).
- [ ] **Step 3: il codice** con le firme sopra, più le tre costruzioni nei test e la registrazione nel DI.
- [ ] **Step 4: i test passano** (poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): release dates and awaiting release status on requests"`

### Task 7: montaggio, `Info` e plugin 1.13.0

**Files:**
- Modify: `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs` (solo il commento), `Jellyfin.Plugin.WonderFlixWatchParty.csproj` (`<Version>1.13.0</Version>`), `Plugin.cs` (commento: "e, dalla 1.13.0, il calendario delle uscite e le date delle richieste (spec S)"), `../meta.template.json` (descrizione e overview), `../README.md`
- Test: `Tests/ServiceRegistrationTests.cs`, `Tests/InfoControllerTests.cs`

**Interfaces:**
- Produces: `WatchPartyProtocol.CalendarFeature = "calendar"` (commento "Il calendario delle uscite (spec S §6.4): con Sonarr o Radarr configurato"); `FeaturesWith` lo aggiunge dopo `upcomingMovies` se `upcomingSeries || upcomingMovies` (decisione 6).

- [ ] **Step 1: test che falliscono:**
  - `InfoControllerTests`: versione `"1.13.0"`; con Sonarr e Radarr le funzioni finiscono con `"upcomingSeries", "upcomingMovies", "calendar"`; con solo Sonarr `"upcomingSeries", "calendar"`; senza nessuno dei due niente `"calendar"`.
  - `ServiceRegistrationTests`: `CalendarService` e `ReleaseDatesService` si risolvono dal DI (registrati nei Task 4 e 6); i servizi in background restano 8.
- [ ] **Step 2: i test falliscono** (`InfoControllerTests|ServiceRegistrationTests`).
- [ ] **Step 3: il codice.**
  - `meta.template.json`: alla fine della descrizione `…the upcoming episodes and movies from Sonarr and Radarr, with a monthly release calendar and the release dates of requested titles.`; overview `…, upcoming from Sonarr and Radarr, release calendar`.
  - `README.md`: una riga sul calendario (`GET Upcoming/Calendar`) e sulle date delle richieste, dove il README elenca le funzioni di Sonarr e Radarr.
  - Il `manifest.json` **non** si tocca: si aggiorna alla release, alla fine del 25b.
- [ ] **Step 4: i test passano** (poi la suite intera; scrivi nel registro il numero di test).
- [ ] **Step 5: commit** `git commit -m "chore(plugin): calendar feature and version 1.13.0"`

### Task 8: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-22-wonderflix-calendario-uscite-design.md`

- [ ] **Step 1: la spec**, controllando ogni frase sul codice:
  - **Stato:** "approvata il 2026-10-22; piano 25a realizzato (`docs/superpowers/plans/2026-10-22-wonderflix-25a-calendario-plugin.md`), build di prova sul server; piano 25b da realizzare".
  - **§6.1:** 400 senza corpo (decisione 1); la cache con 6 periodi per servizio; i campi null scritti (decisione 7).
  - **§6.2:** le date dei film per id TMDB e solo dove servono (decisioni 2, 3); il numero del prossimo episodio (decisione 4); l'abbinamento delle serie (decisione 5); date mancanti = niente `AwaitingRelease` (decisione 8).
  - **§6.4:** `calendar` dopo `upcomingMovies` (decisione 6).
  - Ogni altra differenza venuta fuori durante i task, con il motivo.
- [ ] **Step 2: commit** (suite intera verde) `git commit -m "docs: align the calendar spec with plan 25a"`

### Task 9: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent si ferma dopo il Task 8. L'orchestratore fa la review finale del branch e i ritocchi, poi esegue questi passi, con un solo riavvio di Jellyfin e **dopo l'OK dell'utente al riavvio**.

Regole per il server:
- il server lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando;
- gli script vanno in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`);
- **nessuno script stampa chiavi o token.**

1. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.13.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.13.0.0/`.
2. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix": base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - salvataggi: `mkdir -p ~/wfwp-backup`; sposta la cartella `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.12.0.0` in `~/wfwp-backup/1.12.0.0-segnalazioni` (con un suffisso se c'è già); copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.12.0-prima-25a.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.13.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log di oggi (`~/.apps/jellyfin/log/`) `Loaded plugin: "WonderFlix Watch Party" "1.13.0.0"` e nessun errore del plugin. L'avvio dura circa 7 minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.13.0.0, rimetti `~/wfwp-backup/1.12.0.0-segnalazioni` e la configurazione salvata, riavvia, e segnalalo.
3. **Controlli** (stessa base e intestazione; risposte riassunte con `python3`, mai stampate intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.13.0`; funzioni con `upcomingSeries`, `upcomingMovies`, `calendar`, e ancora `reports`, `ratings`, `requests`;
   - `GET /WonderFlixWatchParty/Upcoming/Calendar?start=2026-10-27&end=2026-12-08`: 200, numero di episodi e film, quanti `OnServer`, `SeriesError` e `MoviesError` null;
   - `…?start=2026-10-01&end=2026-12-01` (61 giorni): 400, **non 404**;
   - `GET /WonderFlixWatchParty/Requests?filter=all` non si prova con la chiave API (serve un utente Seerr): le date e `AwaitingRelease` si provano con l'app nel 25b;
   - nel log nessun `Warning` del plugin dopo l'avvio; nella configurazione del plugin `SeerrUrl`, `SonarrUrl`, `RadarrUrl` ancora al loro posto.
4. **Riporta all'utente** l'esito in breve: versione, funzioni, numeri del calendario, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 25b). Le app 0.19.x non chiamano il calendario e leggono `AwaitingRelease` come "Approvata".

### Task 10: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 9: merge fast-forward su `main` e push (memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente tag e niente manifest: il plugin 1.13.0 si pubblica alla fine del 25b, insieme all'app 0.20.0.
