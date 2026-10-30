# WonderFlix — Piano 30a: spazio sul seedbox, plugin 1.16.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec U nel plugin 1.16.0:
- il calcolo dello spazio: quota, divisione, segnali, liste Cancellare, Alleggerire e Pulizia (§4, §5);
- le operazioni con i passi (§6.1, §6.2), il seed obbligatorio con la rimozione a fine obbligo (§6.3), "Tienilo" (§6.4);
- "Alleggerisci" nella Spec T (il titolo diventa "va bene così");
- la configurazione, la funzione `space` in `Info`, la versione 1.16.0 e una build di prova sul server.

L'app arriva nel piano 30b, che usa i JSON di "Global Constraints": **i nomi delle proprietà JSON non si cambiano**.

**Architecture:**
- Parti pure, senza I/O, con i loro test:
  - `SeedRule`: un torrent si può togliere ora?
  - `SpaceMath`: quanti GB libera un titolo, subito e dopo il seed;
  - `SpaceSignals`: i segnali "via" e "tienilo";
  - `QuotaFile`: la quota letta dal file;
  - `FileProbe.ParseStat`: l'uscita di `stat`.
- I client:
  - `IArrClient` impara a cancellare e a smettere di monitorare;
  - `ISeerrClient` impara a togliere un media;
  - `IQbitClient` è nuovo.
- Gli accessi al server sono dietro interfacce, con un'implementazione vera in `Server/` e una finta nei test:
  - `IFileProbe` per `stat`, l'elenco dei file e la cancellazione;
  - `IViewingFacts` per la visione di Jellyfin;
  - `ILibraryRefresh` per aggiornare la libreria.
- `SpaceService`:
  - fa il calcolo (`ScanAsync`), il cui risultato resta **in memoria**;
  - esegue le operazioni, una alla volta;
  - controlla i torrent in attesa.
- `SpaceStore` salva in `space.json` i tenuti, i torrent in attesa e le operazioni.
- `SpaceHostedService` fa girare i timer; `SpaceController` espone gli endpoint admin.

**Tech Stack:** C# / .NET 9, ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Compilato contro Jellyfin 10.11.0; test e server con la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-30-wonderflix-spazio-seedbox-design.md` (tutta; l'app è §8). Si appoggia alla Spec T: `docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md`.

**Decisioni del piano** (rispetto alla spec; il Task 12 le riporta nella spec):
1. **Il calcolo resta in memoria.** Il primo parte 2 minuti dopo l'avvio, poi ogni 24 ore e su "ricalcola". Fino al primo risultato `ScannedAt` è null e `Scanning` è vero.
2. **Collegamento titolo ↔ torrent:** con il numero di device e di inode (`stat --printf "%d\t%i\t%h\t%s\t%n\n"`). Jellyfin gira in un container Ubuntu 24.04 che vede `/home/hashvps/{media,downloads,seedings}` con gli stessi percorsi e ha `/usr/bin/stat`. Controllato il 2026-10-30: lo stesso file dà `16673:31119496:2` da dentro e da fuori.
3. **Quota da un file.** Nel container `quota` non c'è. Un cron sul seedbox scrive `quota -w` in un file (Task 13). Il plugin lo legge (`SpaceQuotaFile`). Se il file è vuoto o non c'è, la quota non c'è e `Errors.Quota` = `NotConfigured`.
4. **Dimensioni** da Radarr (`sizeOnDisk`) e da Sonarr (`statistics.sizeOnDisk`, e per stagione `seasons[].statistics.sizeOnDisk`); i percorsi da `movieFile.path` e da `episodefile.path`.
5. **Seguito in arrivo** (solo film): un altro film di Radarr nella stessa `collection.tmdbId`, senza file e con `status` diverso da `released`. Radarr ha la collezione per 420 film su 825. Le serie non hanno questo segnale.
6. **Serie:**
   - una serie `ended` può essere candidata intera;
   - di una serie in corso sono candidate solo le stagioni, mai l'ultima (il numero più alto con episodi);
   - la stagione 0 (speciali) non è mai candidata;
   - Alleggerire lavora **per stagione** (chiave `season:{idSerie}:{n}`) e apre la ricerca della stagione della Spec T.
7. **Chi è "interessato":** gli utenti Jellyfin attivi che hanno aperto il titolo, più chi l'ha chiesto in Seerr. "Aperto" vuol dire `Played` o `PlaybackPositionTicks > 0` su un film o su almeno un episodio. "Finito" vuol dire `Played` sul film, o tutti gli episodi visti (con file) della serie o della stagione.
8. **Voti di una serie:** la media dei voti delle sue stagioni.
9. **Richieste** da Seerr, `GetRequestsAsync(1, "all", 100, skip, null)` con tutte le pagine. L'utente 1 è l'admin di Seerr. Il richiedente si riconosce da `RequestedBy.JellyfinUserId`.
10. **Tracker di un torrent:** il campo `tracker` di `torrents/info`. Solo se è vuoto si chiama `torrents/trackers` per quel torrent. Il dominio è protetto se l'host coincide con uno della lista o ne è un sottodominio.
11. **Chiavi:**
    - `movie:{idRadarr}`, `series:{idSonarr}`, `season:{idSonarr}:{n}`, `torrent:{hash}`;
    - `file:{h}`, dove `h` sono i primi 16 caratteri esadecimali minuscoli dello SHA-256 del percorso. Valgono per orfani e doppioni, e il tipo li distingue;
    - `all-torrents`.
    Movie, season ed episode hanno lo stesso formato della Spec T (`DownloadKey`).
12. **Rifare un'operazione:** riparte da capo. Un 404 di Radarr, Sonarr, qBittorrent o Seerr è "saltato" con `Gone`.
13. **Prima di cancellare** un film o una serie si tolgono dalla coda di Radarr/Sonarr i download di quel titolo, senza blocklist.
14. **"Generi che guardi spesso":** si calcolano a ogni `GET Space` per chi chiama. Sono i 3 generi più frequenti tra film e serie che ha visto (`Played`) o votato ≥ 4.

## Global Constraints

- Plugin **1.16.0**; `targetAbi` 10.11.0.0; compilato contro 10.11.0, test con 10.11.9.
- **Endpoint** sotto `/WonderFlixWatchParty`, in `SpaceController` con `[Authorize(Policy = Policies.RequiresElevation)]` sulla classe:
  - `GET Space` → `SpaceOverviewDto`;
  - `POST Space/Recalculate` → 202;
  - `POST Space/Operations` corpo `{"Kind","Key"}` → 202 `{"Id"}`. Errori: 400 per corpo o chiave non validi; 404 `{"Reason":"Unknown"}` per una chiave che non è nell'ultimo calcolo; 409 `{"Reason":"Busy"}` se un'operazione sulla stessa chiave è in coda o in corso; 409 `{"Reason":"NotReady"}` prima del primo calcolo;
  - `GET Space/Operations/{id}` → `SpaceOperationDto`, 404 se non c'è;
  - `POST Space/Kept` corpo `{"Key","Title"}` → 204; `DELETE Space/Kept?key=` → 204;
  - `DELETE Space/Pending/{hash}` → 204, 404 se non c'è.
- **`Downloads/Grab`** (Spec T): il corpo accetta anche `"Lighten"` (bool, facoltativo, `false` se manca).
- **JSON** (PascalCase, ogni campo scritto anche se null, `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]` sui nullable):
  - `SpaceQuotaDto`: `UsedBytes`, `LimitBytes` (long).
  - `SpaceBreakdownDto`: `MoviesBytes`, `SeriesBytes`, `AnimeBytes`, `TorrentOnlyBytes`, `OtherBytes` (long; `OtherBytes` = usati − gli altri, minimo 0, 0 senza quota).
  - `SpaceViewerDto`: `Name`, `Finished` (bool), `LastPlayed` (DateTimeOffset?).
  - `SpaceRequestDto`: `Name`, `At`.
  - `SpaceCandidateDto`: `Key`, `Kind` (`Movie`/`Series`/`Season`), `Title`, `Year` (int?), `SeasonNumber` (int?), `SeriesKey` (string?, solo per le stagioni), `ItemId` (string?, id Jellyfin formato `"N"`), `PosterUrl` (string?), `SizeBytes`, `FreeNowBytes`, `FreeLaterBytes`, `FreeLaterAt` (DateTimeOffset?), `InPackBytes`, `Via` ([string]), `Keep` ([string]), `Viewers` ([`SpaceViewerDto`]), `Requests` ([`SpaceRequestDto`]), `RatingAvg` (double?), `RatingCount` (int), `LastOpened` (DateTimeOffset?), `Added` (DateTimeOffset?), `Genres` ([string]).
  - `SpaceLightenDto`: `Key`, `Kind` (`Movie`/`Season`), `Title`, `SeasonNumber` (int?), `ItemId`, `PosterUrl`, `SizeBytes`, `ExcessBytes`, `GbPerHour` (double, due decimali).
  - `SpaceTorrentDto`: `Key`, `Hash`, `Name`, `Tracker` (host), `SizeBytes`, `Ratio` (double), `SeedingDays` (double, un decimale), `CanRemoveNow` (bool), `ExpectedAt` (DateTimeOffset?).
  - `SpaceFileDto`: `Key`, `Path`, `SizeBytes`, `Linked` (bool: ha altri hardlink, cancellarlo non libera spazio).
  - `SpaceCleanupDto`: `Torrents` ([`SpaceTorrentDto`]), `Orphans` ([`SpaceFileDto`]), `Duplicates` ([`SpaceFileDto`]).
  - `SpacePendingDto`: `Hash`, `Name`, `Tracker`, `SizeBytes`, `ExpectedAt`, `Title`.
  - `SpaceKeptDto`: `Key`, `Title`.
  - `SpaceStepDto`: `Name`, `State`, `Detail` (string?), `Done` (int?), `Waiting` (int?).
  - `SpaceOperationDto`: `Id`, `Kind`, `Key`, `Title`, `State`, `Auto` (bool), `StartedAt`, `EndedAt` (DateTimeOffset?), `EstimatedFreedBytes`, `PendingBytes`, `QuotaBeforeBytes` (long?), `QuotaAfterBytes` (long?), `Steps` ([`SpaceStepDto`]).
  - `SpaceErrorsDto`: `Radarr`, `Sonarr`, `Qbit`, `Seerr`, `Quota` (string? ciascuno).
  - `SpaceOverviewDto`: `ScannedAt` (DateTimeOffset?), `Scanning` (bool), `Quota` (`SpaceQuotaDto?`), `Breakdown`, `Delete` ([`SpaceCandidateDto`]), `Lighten` ([`SpaceLightenDto`]), `Cleanup`, `Pending` ([`SpacePendingDto`]), `Kept` ([`SpaceKeptDto`]), `Operations` ([`SpaceOperationDto`], le ultime 20, dalla più recente), `TopGenres` ([string]), `Errors`.
  - `SpaceStartedDto`: `Id`.
- **Valori stringa:**
  - `Via`: `NobodyWatching`, `NeverOpened`, `LowRating`.
  - `Keep`: `InProgress`, `RecentRequest`, `HighRating`, `SequelComing`.
  - `Kind` di un'operazione: `Movie`, `Series`, `Season`, `Torrent`, `AllTorrents`, `Orphan`, `Duplicate`.
  - `State` di un'operazione: `Queued`, `Running`, `Done`, `Failed`.
  - `State` di un passo: `Waiting`, `Running`, `Done`, `Skipped`, `Failed`, `NotDone`.
  - `Name` di un passo: `FindTorrents`, `RemoveFromQueue`, `DeleteFromRadarr`, `DeleteFromSonarr`, `UnmonitorSeason`, `DeleteEpisodeFiles`, `RemoveTorrents`, `RemoveFromSeerr`, `RefreshLibrary`, `DeleteFile`, `ReadQuota`.
  - `Detail`: `NotConfigured`, `Unauthorized`, `Unreachable`, `Gone`, `SeedRule`, `Failed`.
  - errori in `SpaceErrorsDto`: `NotConfigured`, `Unauthorized`, `Unreachable`.
- **Ordine delle liste:**
  - `Delete`: prima le righe senza `Keep`, poi per `FreeNowBytes + FreeLaterBytes` decrescente, poi `Key`;
  - `Lighten`: per `ExcessBytes` decrescente;
  - `Torrents`: prima `CanRemoveNow`, poi per `SizeBytes` decrescente;
  - `Orphans` e `Duplicates`: per `SizeBytes` decrescente.
- **Configurazione** (`PluginConfiguration`, valori iniziali):
  - `SpaceQbitUrl` `""`, `SpaceQbitUser` `""`, `SpaceQbitPassword` `""`;
  - `SpaceStaleMonths` 6, `SpaceRequestGraceDays` 60;
  - `SpaceLowRating` 2, `SpaceHighRating` 4, `SpaceMinRatings` 2;
  - `SpaceHeavyGbPerHour` 4.0;
  - `SpaceSeedTrackers` `"itatorrents.xyz,shareisland.org"`, `SpaceSeedRatio` 10.0, `SpaceSeedDays` 30;
  - `SpaceScanFolders` `"/home/hashvps/downloads\n/home/hashvps/seedings"` (una per riga);
  - `SpaceQuotaFile` `""`.
- **Altri valori:**
  - file video: estensioni `.mkv .mp4 .avi .m4v .ts`, sopra i 100 MB (`MinVideoBytes = 100_000_000`); GB = 10⁹ byte;
  - operazioni conservate 30 giorni (`OperationRetention`);
  - calcolo: 2 minuti dopo l'avvio (`FirstScanDelay`), poi ogni 24 ore (`ScanInterval`);
  - torrent in attesa: controllo ogni ora (`PendingInterval`);
  - `stat` a gruppi di 500 percorsi.
- **`Info`:** `Version` "1.16.0", `Features` con `"space"` subito dopo `"downloads"`, presente quando c'è almeno Sonarr o Radarr.
- **Sicurezza:**
  - la password di qBittorrent e le chiavi non tornano mai nelle risposte né nel registro;
  - il plugin cancella file dal disco solo dentro le cartelle di `SpaceScanFolders` o dentro i percorsi di Radarr/Sonarr (per i doppioni), mai altrove;
  - un percorso con `..` o fuori da queste radici si rifiuta (`Failed`).
- **Log:**
  - mai titoli, nomi di torrent, percorsi completi, query o password;
  - nel registro solo il tipo di operazione, la chiave senza il nome (`movie:12`, `torrent:` + i primi 8 caratteri dell'hash), il nome del passo e i codici d'errore;
  - `Warning` per i servizi che non rispondono.
- **Id e date:** id di Jellyfin in formato `"N"`; `TimeProvider`, mai `DateTimeOffset.UtcNow`.
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi; messaggi in italiano.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.

## Review Focus

1. **Un pack di stagione con un solo episodio da cancellare:** il torrent non si toglie, i GB vanno in `InPackBytes`, non in `FreeNowBytes`. Test: Task 2 (`APackWithOtherLibraryFilesIsKept`).
2. **Un file con un hardlink in più che il plugin non conosce** (copia in `seedings` fuori da qBittorrent): non promettere spazio. Test: Task 2 (`AnUnknownExtraLinkKeepsTheBytes`).
3. **Un torrent ItaTorrents ancora in download o fermo a ratio 3 da 10 giorni:** non si toglie ora. La data prevista è fra 20 giorni, e per uno in download non c'è data. Test: Task 1 (`AProtectedTorrentWaitsForThirtyDays`, `ADownloadingTorrentIsNeverRemovable`).
4. **qBittorrent spento o password sbagliata durante un'operazione su un film:** Radarr ha già cancellato, il passo dei torrent fallisce e l'operazione si ferma con i passi successivi `NotDone`. Rifarla salta Radarr (`Gone`) e toglie i torrent. Test: Task 9 (`QbitDownStopsAfterRadarr`, `RetryingSkipsWhatIsGone`).
5. **Una chiave `file:` di un percorso fuori dalle cartelle configurate** (un `space.json` modificato, o un percorso cambiato tra il calcolo e il clic): non si cancella niente. Test: Task 9 (`AFileOutsideTheRootsIsNeverDeleted`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
  - Messaggi su una riga sola, in italiano, senza virgolette interne: `git commit -m "feat(plugin): …"`.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `dotnet` o `git`, prima rinfresca il PATH:
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/spazio-seedbox`): fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" plugin/pack.sh 1.16.0`.
- **Test:**
  - un gruppo: `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj ha `TreatWarningsAsErrors`), poi `dotnet build-server shutdown`;
  - il primo implementatore conta i test verdi di partenza e li scrive nel registro.
- **Server** (solo dove il task lo dice): `ssh ultra`.
  - Le chiavi si leggono da `~/.apps/<app>/config.xml` e **non si stampano mai**.
  - Indirizzi: Radarr `http://127.0.0.1:17527/radarr`, Sonarr `http://127.0.0.1:17526/sonarr`, qBittorrent `http://127.0.0.1:17541`.
  - **Mai** un'operazione dello spazio, un `DELETE` o un `torrents/delete` sul server vero: solo letture.
- **Formattazione:** ogni file tiene le sue terminazioni di riga (working copy CRLF, indice LF; i file nuovi vanno bene con LF). UTF-8 con gli strumenti di modifica dei file, mai `Set-Content`/`Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese; ogni tipo nuovo ha il suo `/// <summary>` con il riferimento alla spec ("spec U §6.3");
  - durate e limiti come costanti nominate e commentate; `TimeProvider`;
  - DTO `record` con `[property: JsonPropertyName("…")]` in `Protocol/SpaceDtos.cs`; modelli di Sonarr/Radarr come classi con `{ get; set; }` in `Home/ArrJson.cs`, quelli di qBittorrent in `Space/QbitJson.cs`;
  - `Lock` di .NET 9.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo; preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-30 sul codice di `main` (`40c7ec3`) e sul server.

- **`ArrClient`:**
  - helper privati `SendAsync<T>(kind, method, path, body, timeout, ct)`, `SendWithoutResultAsync(kind, method, path, body, ct, timeout?)` e `GetAllPagesAsync<T>`;
  - errori come `ArrException(ArrError, inner, status)`, con `Status` per le risposte HTTP; `UpcomingErrors.Code(ArrError)` dà i codici;
  - `FakeArrClient` in `Tests/` ha gestori `Func<…>` e liste di chiamate.
- **Radarr `GET movie`:**
  - ogni film ha `id`, `title`, `year`, `tmdbId`, `runtime`, `hasFile`, `status` (`announced`/`inCinemas`/`released`), `sizeOnDisk`, `added`, `path`, `collection` (`{title, tmdbId}`, anche assente) e `movieFile` (`{id, path, size}`);
  - esempio: Coco (2017), `sizeOnDisk` 6374799956, `path` `/home/hashvps/media/movies/Coco (2017)`.
- **Sonarr `GET series`:**
  - `statistics.sizeOnDisk` e `seasons[]` con `seasonNumber`, `monitored`, `statistics.{episodeFileCount, sizeOnDisk}`; `status` `ended`/`continuing`; `path`; `added`;
  - `GET episodefile?seriesId=` dà `id`, `seasonNumber`, `path`, `size`;
  - `PUT series/{id}` vuole l'oggetto intero: si legge con `GET series/{id}` come `JsonNode`, si cambia `seasons[n].monitored` e si rimanda;
  - `DELETE episodefile/bulk` con corpo `{"episodeFileIds":[…]}`.
- **Cancellazioni:** `DELETE movie/{id}?deleteFiles=true&addImportExclusion=false` (Radarr) e `DELETE series/{id}?deleteFiles=true&addImportListExclusion=false` (Sonarr). Cestino spento in entrambi (`recycleBin` vuoto): lo spazio si libera subito.
- **Seerr:**
  - `SeerrClient.SendAsync<T>(method, path, asUser, body, ct, acceptedMeans)`. Una risposta 204 senza corpo va letta con una variante senza risultato, da aggiungere come in `ArrClient`;
  - `GET movie/{tmdbId}` e `GET tv/{tmdbId}` danno `mediaInfo.id`: `SeerrMediaInfo` oggi non ha `Id`, va aggiunto;
  - per togliere un media: `DELETE media/{id}`;
  - `SeerrRequest` ha `CreatedAt`, `RequestedBy.JellyfinUserId`, `Media.TmdbId`, `Media.TvdbId`, `Media.MediaType`.
- **qBittorrent** (WebUI API v2, `WebUI\LocalHostAuth=true`, serve il login anche da localhost):
  - `POST api/v2/auth/login` (form `username`, `password`): `Ok.` più il cookie `SID`, oppure `Fails.`;
  - `GET api/v2/torrents/info`: `hash`, `name`, `size`, `progress`, `ratio`, `seeding_time` (s), `tracker`, `state`, `save_path`, `content_path`;
  - `GET api/v2/torrents/files?hash=`: `name` relativo a `save_path`, `size`;
  - `GET api/v2/torrents/trackers?hash=`: `url`;
  - `POST api/v2/torrents/delete` (form `hashes=h1|h2`, `deleteFiles=true`).
  - Il cookie scade: un 403 vuol dire nuovo login e un solo nuovo tentativo.
- **Jellyfin:**
  - `ISeriesIndex.GetSeries()`/`GetMovies()` (`Home/ISeriesIndex.cs`) collegano gli item a TVDB e TMDB;
  - `IUserDirectory.GetUsers()` restituisce `UserRef(Id, Name, Enabled, …)`;
  - `IUserDataManager.GetUserData(user, item)` dà `Played`, `PlaybackPositionTicks`, `LastPlayedDate`, `IsFavorite`; esempi in `Server/JellyfinRatingLibrary.cs` (`HasWatched`) e in `Server/JellyfinRecommendationLibrary.cs` (`LastWatched`);
  - `ILibraryManager.QueueLibraryScan()` per aggiornare la libreria: da verificare su 10.11.0 e 10.11.9 (Task 8).
- **Voti:** `RatingService.Of(Guid itemId, IReadOnlyCollection<Guid> userIds)`. `RatingBook.ForItem(itemId)` dà tutti i voti di un film o di una stagione.
- **Spec T:**
  - `DownloadService.GrabAsync(key, guid, indexerId, ct)` e `Accept(key)`, che usa `Book.Accept` e `store.Save`;
  - `OnImported` (`DownloadService.cs`) mette in `UpgradeWatch` un titolo sotto l'obiettivo;
  - `IsDue` (`DownloadService.Search.cs`) ricerca gli `UpgradeWatch`;
  - `Book.IsAccepted(key)`.
- **Montaggio:** `PluginServiceRegistrator`; `ServiceRegistrationTests` conta **9** servizi in background (diventano 10). `WatchPartyProtocol.FeaturesWith(bool requests, bool upcomingSeries, bool upcomingMovies)`; `InfoControllerTests`.
- **Modello di store:** `Downloads/DownloadStore.cs` (file illeggibile in `.bad`, `DefaultPath(IApplicationPaths)`).

## File

| File | Responsabilità |
|---|---|
| `Space/SeedRule.cs`, `Space/SpaceMath.cs`, `Space/SpaceSignals.cs`, `Space/QuotaFile.cs` | le parti pure |
| `Space/ISpaceSettings.cs`, `Server/PluginSpaceSettings.cs`, `Configuration/PluginConfiguration.cs`, `Configuration/configPage.html` | le impostazioni |
| `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs` | cancellare, smettere di monitorare, campi nuovi |
| `Seerr/ISeerrClient.cs`, `Seerr/SeerrClient.cs`, `Seerr/SeerrJson.cs` | togliere un media |
| `Space/IQbitClient.cs`, `Space/QbitClient.cs`, `Space/QbitJson.cs` | qBittorrent |
| `Space/IFileProbe.cs`, `Server/LinuxFileProbe.cs` | `stat`, elenco e cancellazione dei file, lettura della quota |
| `Space/IViewingFacts.cs`, `Server/JellyfinViewingFacts.cs`, `Space/ILibraryRefresh.cs`, `Server/JellyfinLibraryRefresh.cs` | Jellyfin |
| `Space/SpaceBook.cs`, `Space/SpaceStore.cs` | tenuti, in attesa, operazioni; `space.json` |
| `Space/SpaceService.cs`, `Space/SpaceService.Scan.cs`, `Space/SpaceService.Operations.cs` | calcolo, operazioni, torrent in attesa |
| `SpaceHostedService.cs` | i timer |
| `Protocol/SpaceDtos.cs`, `Api/SpaceController.cs` | gli endpoint |
| `Downloads/DownloadService*.cs`, `Api/DownloadsController.cs`, `Protocol/DownloadsDtos.cs` | "Alleggerisci" |
| `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs`, csproj, `../meta.template.json`, `../README.md` | montaggio, `Info`, versione, documentazione |

I percorsi sono relativi a `plugin/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e a `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test, scritti `Tests/…`), se non è detto altro.

---

### Task 1: la regola del seed e la quota

**Files:**
- Create: `Space/SeedRule.cs`, `Space/QuotaFile.cs`, `Space/ISpaceSettings.cs`
- Test: `Tests/SeedRuleTests.cs`, `Tests/QuotaFileTests.cs`, `Tests/FakeSpaceSettings.cs`

**Interfaces:**
- Produces:
  - `public sealed record TorrentFacts(string Hash, string Name, string TrackerHost, long SizeBytes, double Progress, double Ratio, long SeedingSeconds)`.
  - `public sealed record SeedSettings(IReadOnlyList<string> ProtectedDomains, double Ratio, int Days)`.
  - `public sealed record SeedVerdict(bool CanRemoveNow, DateTimeOffset? ExpectedAt)`.
  - `public static class SeedRule`:
    - `SeedVerdict Check(TorrentFacts torrent, SeedSettings settings, DateTimeOffset now)`;
    - `bool IsProtected(string trackerHost, IReadOnlyList<string> domains)`;
    - `string HostOf(string? trackerUrl)` (vuoto per null o un URL non valido, minuscolo).
  - `public sealed record Quota(long UsedBytes, long LimitBytes)`; `public static class QuotaFile { Quota? Parse(string? text) }`.
  - `public interface ISpaceSettings`: `string QbitUrl`, `string QbitUser`, `string QbitPassword`, `int StaleMonths`, `int RequestGraceDays`, `int LowRating`, `int HighRating`, `int MinRatings`, `double HeavyGbPerHour`, `SeedSettings Seed`, `IReadOnlyList<string> ScanFolders`, `string QuotaFile`.
  - `FakeSpaceSettings` con proprietà `{ get; set; }` e i valori di Global Constraints, `ScanFolders` `["/srv/downloads", "/srv/seedings"]`.
- Regole di `Check`:
  - `Progress < 1` → `(false, null)`;
  - host non protetto → `(true, null)`;
  - protetto con `Ratio >= settings.Ratio` o `SeedingSeconds >= Days·86400` → `(true, null)`;
  - altrimenti `(false, now + (Days·86400 − SeedingSeconds) secondi)`.
- `IsProtected`: l'host è uguale a un dominio o finisce con `"." + dominio`, senza badare alle maiuscole.
- `Parse`: l'ultima riga non vuota divisa per spazi; il campo 1 sono i KB usati (togliendo un `*` finale), il 2 la quota, il 3 il limite. Il limite è il campo 3 se > 0, altrimenti il campo 2, altrimenti null. Tutto ×1024. Testo vuoto o numeri non validi → null.

- [ ] **Step 1: test che falliscono.**
  - `SeedRuleTests`:
    - `AnUnprotectedTorrentGoesNow`: host `tracker.example.org`, ratio 0,1 → `CanRemoveNow` vero.
    - `AProtectedTorrentWaitsForThirtyDays`: `itatorrents.xyz`, ratio 3, 10 giorni di seed, `now` 2026-10-30T12:00Z → falso, `ExpectedAt` 2026-11-19T12:00Z.
    - `RatioTenFreesAProtectedTorrent`: `shareisland.org`, ratio 10, 1 giorno → vero.
    - `ThirtyDaysFreeAProtectedTorrent`: ratio 0,5, `SeedingSeconds` 2_592_000 → vero.
    - `ASubdomainIsProtected`: `IsProtected("tracker.itatorrents.xyz", …)` vero; `IsProtected("notitatorrents.xyz", …)` falso.
    - `ADownloadingTorrentIsNeverRemovable`: `Progress` 0,99, host non protetto → `(false, null)`.
    - `HostOfReadsTheAnnounceUrl`: `"https://ShareIsland.org/announce/abc"` → `"shareisland.org"`; `null` → `""`.
  - `QuotaFileTests`:
    - `TheRealQuotaLineIsRead`: il testo `"Disk quotas for user hashvps (uid 1130): \n     Filesystem   blocks   quota   limit   grace   files   quota   limit   grace\n      /dev/sds1 11625889424  11718885376 11718885376          576640       0       0\n"` → `UsedBytes` 11625889424·1024, `LimitBytes` 11718885376·1024.
    - `AnOverQuotaStarIsIgnored`: `"/dev/sds1 11718885377* 11718885376 11718885376 …"` → usati letti.
    - `GarbageIsNull`: `""`, `null`, `"ciao"` → null.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~SeedRuleTests|FullyQualifiedName~QuotaFileTests"`).
- [ ] **Step 3: il codice**, in `Space/` (namespace `Jellyfin.Plugin.WonderFlixWatchParty.Space`).
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): regola del seed obbligatorio e lettura della quota"`

### Task 2: quanto spazio libera un titolo

**Files:**
- Create: `Space/SpaceMath.cs`
- Test: `Tests/SpaceMathTests.cs`

**Interfaces:**
- Consumes: `TorrentFacts`, `SeedSettings`, `SeedRule` (Task 1).
- Produces:
  - `public readonly record struct FileId(long Device, long Inode)`.
  - `public sealed record FileFact(string Path, FileId Id, int Links, long SizeBytes)`.
  - `public sealed record TorrentFile(string Path, FileId Id)`.
  - `public sealed record TorrentIndex(IReadOnlyList<TorrentFacts> Torrents, IReadOnlyDictionary<string, IReadOnlyList<TorrentFile>> FilesByHash)`, con un costruttore di comodo che costruisce anche `IReadOnlyDictionary<FileId, IReadOnlyList<string>> HashesByFile`.
  - `public sealed record SpaceEstimate(long FreeNowBytes, long FreeLaterBytes, DateTimeOffset? FreeLaterAt, long InPackBytes, IReadOnlyList<string> RemoveNow, IReadOnlyList<string> RemoveLater)` (hash).
  - `public static class SpaceMath`:
    - `SpaceEstimate Estimate(IReadOnlyList<FileFact> titleFiles, TorrentIndex index, IReadOnlySet<FileId> libraryFiles, SeedSettings seed, DateTimeOffset now)`;
    - `bool IsTorrentOnly(string hash, TorrentIndex index, IReadOnlyDictionary<FileId, int> links)`: tutti i file del torrent hanno `Links` uguale al numero di percorsi distinti di torrent con quel `FileId`, cioè nessun hardlink fuori dai torrent.
- Algoritmo di `Estimate`, per ogni file del titolo:
  1. `holders` = i torrent che contengono il suo `FileId`;
  2. `known` = 1 + i percorsi distinti di torrent con quel `FileId`. Se `Links > known`, ci sono hardlink sconosciuti e i byte vanno in `InPackBytes`;
  3. un holder è "rimovibile col titolo" se ogni suo `FileId` non è in `libraryFiles` oppure è tra i file del titolo. Se almeno un holder non lo è, i byte vanno in `InPackBytes`;
  4. altrimenti, se tutti gli holder hanno `SeedRule.Check(…).CanRemoveNow` (o non ci sono holder), i byte vanno in `FreeNowBytes`;
  5. altrimenti vanno in `FreeLaterBytes`, e `FreeLaterAt` è il più tardi degli `ExpectedAt`. Senza data, perché è in download, resta null.
  `RemoveNow` e `RemoveLater` sono gli holder rimovibili col titolo, divisi secondo la regola del seed, senza doppioni.

- [ ] **Step 1: test che falliscono** in `Tests/SpaceMathTests.cs` (date fisse; `now` 2026-10-30T12:00Z):
  - `AFileWithoutTorrentsIsFreedNow`: un file da 5 GB con `Links` 1, nessun torrent → `FreeNowBytes` 5_000_000_000.
  - `AnUnprotectedTorrentIsRemovedWithTheTitle`: un file con `Links` 2 e un torrent non protetto con lo stesso `FileId` → `FreeNowBytes` pieno, `RemoveNow` = [hash].
  - `AProtectedTorrentFreesLater`: come sopra con `itatorrents.xyz`, ratio 1, 5 giorni → `FreeLaterBytes` pieno, `FreeLaterAt` 2026-11-24T12:00Z, `RemoveLater` = [hash].
  - `APackWithOtherLibraryFilesIsKept`: un pack con due episodi in libreria e un titolo (stagione) che ne contiene uno solo → `InPackBytes` = la dimensione dell'episodio, `RemoveNow` vuoto.
  - `AWholeSeasonPackGoesWithTheSeason`: lo stesso pack, con il titolo che contiene tutti e due gli episodi → `FreeNowBytes` = la somma.
  - `AnUnknownExtraLinkKeepsTheBytes`: `Links` 3, un solo torrent → `InPackBytes`.
  - `CrossSeedSharesOnePath`: due torrent con lo stesso percorso e lo stesso `FileId`, `Links` 2 → `known` 2, `FreeNowBytes` pieno, `RemoveNow` con i due hash.
  - `TorrentOnlyMeansNoLibraryLink`: `IsTorrentOnly` vero con `Links` 1, falso con `Links` 2 e un solo percorso di torrent.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~SpaceMathTests"`).
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): stima dello spazio liberato da un titolo"`

### Task 3: i segnali

**Files:**
- Create: `Space/SpaceSignals.cs`
- Test: `Tests/SpaceSignalsTests.cs`

**Interfaces:**
- Consumes: `ISpaceSettings` (Task 1).
- Produces:
  - `public sealed record UserUsage(Guid UserId, string Name, bool Started, bool Finished, DateTimeOffset? LastPlayed)`.
  - `public sealed record RequestFact(Guid? UserId, string Name, DateTimeOffset At)`.
  - `public sealed record TitleFacts(DateTimeOffset? Added, IReadOnlyList<UserUsage> Usage, IReadOnlyList<RequestFact> Requests, double? RatingAvg, int RatingCount, bool SequelComing)`.
  - `public sealed record SpaceThresholds(int StaleMonths, int RequestGraceDays, int LowRating, int HighRating, int MinRatings)` con `static SpaceThresholds From(ISpaceSettings settings)`.
  - `public sealed record Signals(IReadOnlyList<string> Via, IReadOnlyList<string> Keep, DateTimeOffset? LastOpened)`.
  - `public static class SpaceSignals { Signals Evaluate(TitleFacts facts, SpaceThresholds t, DateTimeOffset now) }` e le costanti dei codici (`NobodyWatching`, …), in `SpaceSignalCodes`.
- Regole (`stale` = `now.AddMonths(-StaleMonths)`):
  - `LastOpened` = il più recente `LastPlayed` tra chi ha `Started`;
  - `NobodyWatching`: almeno uno `Started` e (`LastOpened` null oppure ≤ `stale`);
  - `NeverOpened`: nessuno `Started`, `Added` non null e ≤ `stale`;
  - `LowRating`: `RatingCount >= MinRatings` e `RatingAvg <= LowRating`; `HighRating`: `RatingCount >= MinRatings` e `RatingAvg >= HighRating`;
  - `InProgress`: qualcuno `Started`, non `Finished`, con `LastPlayed` > `stale`;
  - `RecentRequest`: una richiesta con `At` > `now − RequestGraceDays` il cui `UserId` non ha `Finished` (oppure senza `UserId`);
  - `SequelComing`: dal fatto.
  - L'ordine nelle liste è quello delle costanti, senza doppioni.

- [ ] **Step 1: test che falliscono** (`now` 2026-10-30T12:00Z, soglie predefinite):
  - `WatchedLongAgoIsNobodyWatching`: Anna `Finished`, `LastPlayed` 2026-03-01 → `Via` = [`NobodyWatching`], `LastOpened` 2026-03-01.
  - `MixedFinishedAndAbandonedIsNobodyWatching`: Anna finito il 2026-02-01, Luca a metà il 2026-04-01 → `NobodyWatching`, nessun `InProgress`.
  - `RecentlyOpenedIsNotStale`: Luca a metà il 2026-10-01 → `Via` vuoto, `Keep` = [`InProgress`].
  - `NeverOpenedAfterSixMonths`: nessun uso, `Added` 2026-04-01 → `NeverOpened`; `Added` 2026-06-01 → niente.
  - `LowRatingNeedsTwoVotes`: media 1,5 con 1 voto → niente; con 2 voti → `LowRating`.
  - `ARecentRequestNotWatchedKeeps`: richiesta di Anna il 2026-10-01, Anna senza uso → `Keep` contiene `RecentRequest`; con Anna `Finished` → no; richiesta del 2026-07-01 → no.
  - `SequelComingKeeps`: `SequelComing` vero → `Keep` contiene `SequelComing`.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~SpaceSignalsTests"`).
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): segnali per i candidati da cancellare"`

### Task 4: impostazioni e configurazione

**Files:**
- Create: `Server/PluginSpaceSettings.cs`
- Modify: `Configuration/PluginConfiguration.cs`, `Configuration/configPage.html`
- Test: `Tests/PluginSpaceSettingsTests.cs`

**Interfaces:**
- Consumes: `ISpaceSettings`, `SeedSettings` (Task 1).
- Produces:
  - `PluginSpaceSettings : ISpaceSettings`: legge `Plugin.Instance?.Configuration` a ogni accesso, come `PluginDownloadSettings`. Senza plugin valgono i valori predefiniti.
  - `internal static` helper puri, testati:
    - `IReadOnlyList<string> SplitDomains(string? csv)`: virgole e spazi, minuscolo, senza vuoti;
    - `IReadOnlyList<string> SplitFolders(string? lines)`: righe non vuote, `TrimEnd('/')`, solo percorsi assoliti che cominciano con `/`;
    - `int Clamp(int value, int min, int max, int fallback)`: un valore fuori dall'intervallo torna al predefinito.
  - Intervalli: `StaleMonths` 1–60, `RequestGraceDays` 0–365, voti 1–5, `MinRatings` 1–20, `HeavyGbPerHour` 0,5–50, `SeedRatio` 0–100, `SeedDays` 0–365.
- La pagina di configurazione ha una sezione "Spazio" con tutti i campi di Global Constraints. La password è un `input type="password"` che si salva solo se l'admin la scrive (come la chiave di Seerr, se la pagina già lo fa; altrimenti com'è per le altre chiavi).

- [ ] **Step 1: test che falliscono:**
  - `DomainsAreSplitAndLowercased`: `" ItaTorrents.xyz, shareisland.org,,"` → `["itatorrents.xyz","shareisland.org"]`.
  - `FoldersMustBeAbsolute`: `"/home/a/\nrelativo\n\n/home/b"` → `["/home/a","/home/b"]`.
  - `OutOfRangeFallsBack`: `Clamp(0, 1, 60, 6)` → 6.
  - `WithoutPluginDefaultsApply`: `new PluginSpaceSettings().StaleMonths` → 6, `.Seed.Days` → 30.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~PluginSpaceSettingsTests"`).
- [ ] **Step 3: il codice e la pagina di configurazione.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): impostazioni dello spazio"`

### Task 5: Radarr, Sonarr e Seerr: cancellare e campi nuovi

**Files:**
- Modify: `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs`, `Seerr/ISeerrClient.cs`, `Seerr/SeerrClient.cs`, `Seerr/SeerrJson.cs`
- Modify (test): `Tests/FakeArrClient.cs`, `Tests/FakeSeerrClient.cs`
- Test: `Tests/ArrClientTests.cs`, `Tests/SeerrClientTests.cs` (o il file dove sono i test di `SeerrClient`)

**Interfaces:**
- Produces (modelli):
  - `RadarrMovie`: `long SizeOnDisk`, `DateTimeOffset? Added`, `string? Path`, `string? Status`, `ArrCollection? Collection` (`ArrCollection { int TmdbId; string? Title }`); `ArrFileRef` in più: `string? Path`, `long Size`.
  - `SonarrSeries`: `string? Path`, `DateTimeOffset? Added`, `List<SonarrSeason?>? Seasons` (`SonarrSeason { int SeasonNumber; bool Monitored; SonarrSeasonStatistics? Statistics }`, `SonarrSeasonStatistics { int EpisodeFileCount; long SizeOnDisk }`); `SonarrSeriesStatistics` in più: `long SizeOnDisk`.
  - `ArrFile` in più: `string? Path`.
  - `SeerrMediaInfo` in più: `int Id`.
- Produces (`IArrClient`, tutti lanciano `ArrException`):
  - `Task DeleteMovieAsync(int movieId, CancellationToken ct)` → `DELETE movie/{id}?deleteFiles=true&addImportExclusion=false`;
  - `Task DeleteSeriesAsync(int seriesId, CancellationToken ct)` → `DELETE series/{id}?deleteFiles=true&addImportListExclusion=false`;
  - `Task SetSeasonMonitoredAsync(int seriesId, int seasonNumber, bool monitored, CancellationToken ct)` → `GET series/{id}` come `JsonNode`, cambia `monitored` della stagione in `seasons`, poi `PUT series/{id}` con lo stesso oggetto. Una stagione che non c'è → `ArrException(Unreachable, status: 404)`;
  - `Task DeleteEpisodeFilesAsync(IReadOnlyList<int> episodeFileIds, CancellationToken ct)` → `DELETE episodefile/bulk` con `{"episodeFileIds":[…]}`; elenco vuoto → nessuna chiamata.
- Produces (`ISeerrClient`, lanciano `SeerrException`):
  - `Task<int?> FindMediaIdAsync(string mediaType, int tmdbId, CancellationToken ct)` → `GET movie/{tmdbId}` o `GET tv/{tmdbId}` (lingua `en`), `MediaInfo?.Id`. 404 o `MediaInfo` null → null;
  - `Task DeleteMediaAsync(int mediaId, CancellationToken ct)` → `DELETE media/{id}` come admin (senza `X-API-User`), accetta 204.
- Produces (fake): gestori e liste di chiamate per ogni metodo nuovo; i predefiniti non fanno niente (`FindMediaIdAsync` → null).

- [ ] **Step 1: test che falliscono:**
  - `DeletingAMovieKeepsItRequestable`: `DELETE https://arr.example/radarr/api/v3/movie/12?deleteFiles=true&addImportExclusion=false`.
  - `DeletingASeriesKeepsItRequestable`: `…/sonarr/api/v3/series/5?deleteFiles=true&addImportListExclusion=false`.
  - `UnmonitoringASeasonPutsTheWholeSeries`: la risposta di `GET series/5` ha campi in più (`"title":"X","tags":[1],"seasons":[{"seasonNumber":1,"monitored":true},{"seasonNumber":2,"monitored":true}]`). Il `PUT series/5` manda gli stessi campi con solo la stagione 2 a `false`.
  - `DeletingEpisodeFilesSendsTheIds`: corpo `{"episodeFileIds":[7,8]}`; elenco vuoto → nessuna chiamata.
  - `MoviesReadSizeCollectionAndPath`: un film come in "Note tecniche" (Coco) → `SizeOnDisk`, `Collection.TmdbId` 1451578, `MovieFile.Path`.
  - `SeriesReadSeasonSizes`: `statistics.sizeOnDisk` e `seasons[1].statistics.sizeOnDisk` letti.
  - Seerr: `FindingAMediaIdReadsMediaInfo` (`{"id":3,"mediaInfo":{"id":42,"status":5}}` → 42); `AMissingMediaIsNull` (404 → null); `DeletingAMediaCallsDelete` (`DELETE …/api/v1/media/42`, risposta 204).
  - Nel test del log di `ArrClient`: i percorsi nuovi senza query.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~ArrClientTests|FullyQualifiedName~SeerrClient"`).
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): cancellazioni e dimensioni da Radarr, Sonarr e Seerr"`

### Task 6: il client di qBittorrent

**Files:**
- Create: `Space/IQbitClient.cs`, `Space/QbitClient.cs`, `Space/QbitJson.cs`, `Space/QbitException.cs`
- Modify: `PluginServiceRegistrator.cs` (`AddHttpClient(QbitClient.HttpClientName)` senza cookie automatici, come quello di Arr)
- Test: `Tests/QbitClientTests.cs`, `Tests/FakeQbitClient.cs`

**Interfaces:**
- Consumes: `ISpaceSettings` (Task 1).
- Produces:
  - `QbitTorrent { string? Hash; string? Name; long Size; double Progress; double Ratio; long SeedingTime; string? Tracker; string? State; string? SavePath; string? ContentPath }` (JSON snake_case: `seeding_time`, `save_path`, `content_path`).
  - `QbitFile { string? Name; long Size }`; `QbitTracker { string? Url }`.
  - `public enum QbitError { NotConfigured, Unauthorized, Unreachable, NotFound }`; `QbitException(QbitError error, Exception? inner = null)`.
  - `public interface IQbitClient`:
    - `Task<IReadOnlyList<QbitTorrent>> GetTorrentsAsync(CancellationToken ct)`;
    - `Task<IReadOnlyList<QbitFile>> GetFilesAsync(string hash, CancellationToken ct)`;
    - `Task<IReadOnlyList<QbitTracker>> GetTrackersAsync(string hash, CancellationToken ct)`;
    - `Task DeleteAsync(IReadOnlyList<string> hashes, CancellationToken ct)` → `deleteFiles=true`; un elenco vuoto non chiama.
  - `QbitClient(IHttpClientFactory, ISpaceSettings, ILogger<QbitClient>)`, `const string HttpClientName = "WonderFlixQbit"`, timeout 30 s:
    - il cookie `SID` si tiene in memoria, sotto lock;
    - senza cookie, o dopo un 403, si fa il login e si ripete la chiamata una sola volta;
    - il login `Fails.` → `Unauthorized`; rete, timeout o 5xx → `Unreachable`; URL vuoto → `NotConfigured`; un 404 su `files`/`trackers` → `NotFound`.
  - `FakeQbitClient`: torrent, file e tracker in dizionari; `Deleted` (le liste di hash cancellati); `Fail` (una `QbitError?` che fa fallire ogni chiamata).

- [ ] **Step 1: test che falliscono** (con `FakeSeerrHttp` o un handler finto come in `ArrClientTests`, URL `http://qbit.example`):
  - `LoginThenListTorrents`: prima `POST http://qbit.example/api/v2/auth/login` con form `username=u&password=p`, risposta `Ok.` e `Set-Cookie: SID=abc`; poi `GET …/api/v2/torrents/info` con `Cookie: SID=abc` → un torrent con `seeding_time` 864000 letto in `SeedingTime`.
  - `AnExpiredCookieLogsInAgainOnce`: la prima `torrents/info` risponde 403, il nuovo login va, la seconda risponde 200 → riuscito, due login. Se anche la seconda è 403 → `Unauthorized`.
  - `WrongPasswordIsUnauthorized`: login `Fails.` → `QbitException` `Unauthorized`.
  - `DeleteSendsHashesAndFiles`: form `hashes=a%7Cb&deleteFiles=true`.
  - `ThePasswordNeverReachesTheLog`: dopo login e chiamate, il logger finto non contiene `p` come valore della password né `SID=`.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~QbitClientTests"`).
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): client di qBittorrent"`

### Task 7: disco: `stat`, elenco e cancellazione dei file

**Files:**
- Create: `Space/IFileProbe.cs`, `Server/LinuxFileProbe.cs`
- Test: `Tests/LinuxFileProbeTests.cs`, `Tests/FakeFileProbe.cs`

**Interfaces:**
- Consumes: `FileId` (Task 2).
- Produces:
  - `public sealed record FileStamp(FileId Id, int Links, long SizeBytes)`.
  - `public interface IFileProbe`:
    - `Task<IReadOnlyDictionary<string, FileStamp>> StatAsync(IReadOnlyList<string> paths, CancellationToken ct)`: i file che non ci sono mancano dal risultato;
    - `IReadOnlyList<string> VideoFiles(string root)`: i file video sopra `MinVideoBytes` sotto `root`, ricorsivo, senza errori per le cartelle illeggibili (`EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true }`);
    - `bool Delete(string path, IReadOnlyList<string> allowedRoots)`: falso senza cancellare se `path` dopo `Path.GetFullPath` non sta sotto una radice o contiene `..`. Cancella il file e poi le cartelle rimaste vuote, risalendo fino alla radice esclusa;
    - `string? ReadText(string path)`: null se non si legge.
  - `public static class FileProbe` (in `Space/IFileProbe.cs`): `const long MinVideoBytes = 100_000_000`, `IReadOnlySet<string> VideoExtensions`, `IReadOnlyDictionary<string, FileStamp> ParseStat(string output)` (righe `dev\tino\tlinks\tsize\tpath`, quelle rotte si saltano).
  - `LinuxFileProbe`: `/usr/bin/stat --printf "%d\t%i\t%h\t%s\t%n\n" -- <percorsi>` con `ProcessStartInfo.ArgumentList`, a gruppi di 500. Legge lo stdout anche se il codice d'uscita è 1 (file mancanti). Timeout di 2 minuti per gruppo; allo scadere ferma **quel** processo (`process.Kill()` sull'oggetto, mai per nome).
  - `FakeFileProbe`: file in memoria (`Dictionary<string, FileStamp>`), `Deleted`, `Texts`.

- [ ] **Step 1: test che falliscono:**
  - `StatOutputIsParsed`: `"16673\t31119496\t2\t6374799956\t/home/x/Coco (2017).mkv\nrotta\n"` → una voce con `Id` (16673, 31119496), `Links` 2, dimensione e percorso con spazi e parentesi.
  - `DeleteRefusesOutsideTheRoots` (su una cartella temporanea vera): un file fuori da `allowedRoots` resta e il risultato è falso; un percorso `root/../altro.mkv` → falso.
  - `DeleteRemovesEmptyFolders`: `root/a/b/film.mkv` cancellato → `root/a` non c'è più, `root` resta.
  - `VideoFilesSkipsSmallAndOtherExtensions`: un file `.mkv` "sparse" da 150 MB (`FileStream.SetLength`), un `.mkv` da 1 KB e un `.nfo` da 150 MB → solo il primo.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~LinuxFileProbeTests"`).
- [ ] **Step 3: il codice.** `StatAsync` non si prova su Windows: il test di `ParseStat` copre la lettura.
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): stat, elenco e cancellazione dei file sul disco"`

### Task 8: Jellyfin: visione, preferiti, generi e aggiornamento della libreria

**Files:**
- Create: `Space/IViewingFacts.cs`, `Server/JellyfinViewingFacts.cs`, `Space/ILibraryRefresh.cs`, `Server/JellyfinLibraryRefresh.cs`
- Test: `Tests/FakeViewingFacts.cs`, `Tests/FakeLibraryRefresh.cs` (le classi Jellyfin non hanno test di unità, come `JellyfinRatingLibrary`)

**Interfaces:**
- Consumes: `UserUsage` (Task 3).
- Produces:
  - `public sealed record ItemViewing(Guid ItemId, DateTimeOffset? Added, IReadOnlyList<UserUsage> Usage, IReadOnlyList<string> Genres)`.
  - `public interface IViewingFacts`:
    - `ItemViewing? Movie(Guid itemId)`;
    - `ItemViewing? Series(Guid seriesId)`: unione degli episodi;
    - `IReadOnlyDictionary<int, ItemViewing> Seasons(Guid seriesId)`: per numero di stagione, con `ItemId` della stagione;
    - `bool IsFavorite(Guid userId, Guid itemId)`;
    - `IReadOnlyList<string> TopGenres(Guid userId, IReadOnlySet<Guid> highlyRated, int count)`: generi dei film e delle serie `Played` (una serie conta se ha almeno un episodio visto) o in `highlyRated`, dal più frequente, a parità in ordine alfabetico.
  - `Usage`: solo utenti attivi (`UserRef.Enabled`), regole della decisione 7. Gli episodi senza file (`IsVirtualItem`) non contano per "finito". `LastPlayed` è il più recente `LastPlayedDate` degli episodi.
  - `public interface ILibraryRefresh { void Refresh(); }`. `JellyfinLibraryRefresh` chiama `ILibraryManager.QueueLibraryScan()`.
  - `FakeViewingFacts` con dizionari; `FakeLibraryRefresh` conta le chiamate.

- [ ] **Step 1: controlla** che `ILibraryManager.QueueLibraryScan()` esista nella 10.11.0 (compilazione) e nella 10.11.9 (i DLL dei test). Se manca, cerca il metodo che fa la stessa cosa nelle due versioni e scrivi nel registro quale hai usato.
- [ ] **Step 2: il codice.** Le query come `JellyfinRecommendationLibrary` (`InternalItemsQuery` con `ParentId`/`AncestorIds`, `IncludeItemTypes = [BaseItemKind.Episode]`, `IsVirtualItem = false`). Una sola lettura di `GetUserData` per utente e item.
- [ ] **Step 3: la suite intera passa** (compilazione con `TreatWarningsAsErrors`).
- [ ] **Step 4: commit** `git commit -m "feat(plugin): visione, preferiti e generi da Jellyfin per lo spazio"`

### Task 9: SpaceBook, store e operazioni

**Files:**
- Create: `Space/SpaceBook.cs`, `Space/SpaceStore.cs`, `Space/SpaceService.cs`, `Space/SpaceService.Operations.cs`
- Test: `Tests/SpaceStoreTests.cs`, `Tests/SpaceOperationsTests.cs`

**Interfaces:**
- Consumes:
  - `IArrClient`, `ISeerrClient` (Task 5), `IQbitClient` (Task 6), `IFileProbe` (Task 7), `ILibraryRefresh` (Task 8), `ISpaceSettings`, `SeedRule`, `QuotaFile` (Task 1), `SpaceMath` (Task 2);
  - `IArrSettings`, `ISeerrSettings`, `TimeProvider`, `ILogger<SpaceService>`.
- Produces:
  - `SpaceFile { int Version = 1; List<KeptTitle> Kept; List<PendingTorrent> Pending; List<SpaceOperation> Operations }` (JSON con questi nomi), dove:
    - `KeptTitle { string Key; string Title }`;
    - `PendingTorrent { string Hash; string Name; string Tracker; long SizeBytes; DateTimeOffset? ExpectedAt; string Title }`;
    - `SpaceOperation` con i campi di `SpaceOperationDto` e `List<SpaceStep> Steps` (`SpaceStep { string Name; string State; string? Detail; int? Done; int? Waiting }`).
  - `SpaceBook` (non thread-safe, solo sotto il lock di `SpaceService`): `Keep(key, title)`, `Unkeep(key)`, `IsKept(key)`, `AddPending(PendingTorrent)` (senza doppioni per hash), `RemovePending(hash)`, `Pending`, `AddOperation`, `Operations` (dalla più recente), `Prune(DateTimeOffset now)` (via le operazioni più vecchie di `OperationRetention` = 30 giorni), `FromFile`/`ToFile` (`FormatException` per una versione diversa o un elenco null).
  - `SpaceStore(string filePath, ILogger<SpaceStore>)`, `const string FileName = "space.json"`, `DefaultPath(IApplicationPaths)`, `Load()`/`Save(SpaceBook)`, come `DownloadStore`.
  - `SpaceService` (singleton):
    - `public enum StartOutcome { Started, Invalid, Unknown, Busy, NotReady }`;
    - `public (StartOutcome Outcome, string? Id) Start(string kind, string key)`: controlla tipo e chiave, cerca la chiave nell'ultimo calcolo (per `Torrent`, `Orphan` e `Duplicate` anche il percorso o l'hash), crea l'operazione `Queued` con tutti i passi `Waiting`, la salva e la mette in coda (`Channel<string>`);
    - `public Task RunOperationsAsync(CancellationToken ct)`: legge la coda ed esegue un'operazione alla volta (la avvia il servizio in background);
    - `public SpaceOperationDto? Operation(string id)`;
    - `public void Keep(string key, string title)`, `public void Unkeep(string key)`, `public bool DropPending(string hash)`;
    - `public Task CheckPendingAsync(CancellationToken ct)`;
    - `internal SpaceScan? LastScan` (dal Task 10; qui basta un campo `internal set` per i test).
- **Passi per tipo** (spec §6.2):
  - `Movie`: `FindTorrents`, `RemoveFromQueue`, `DeleteFromRadarr`, `RemoveTorrents`, `RemoveFromSeerr`, `RefreshLibrary`, `ReadQuota`;
  - `Series`: come `Movie`, con `DeleteFromSonarr` al posto di `DeleteFromRadarr`;
  - `Season`: `FindTorrents`, `RemoveFromQueue`, `UnmonitorSeason`, `DeleteEpisodeFiles`, `RemoveTorrents`, `RefreshLibrary`, `ReadQuota`;
  - `Torrent`, `AllTorrents`: `RemoveTorrents`, `ReadQuota`;
  - `Orphan`, `Duplicate`: `DeleteFile`, `ReadQuota`.
- **Come girano:**
  - prima del primo passo si legge la quota (`QuotaBeforeBytes`);
  - `FindTorrents` rilegge dal vivo i percorsi del titolo (`moviefile`/`episodefile`), li passa a `stat`, legge i torrent e i loro file da qBittorrent e calcola `SpaceMath.Estimate`. Mette `Done` = quanti torrent si tolgono ora, `Waiting` = quanti in attesa, e `EstimatedFreedBytes`/`PendingBytes`. Senza qBittorrent configurato è `Skipped` con `NotConfigured`, e `RemoveTorrents` sarà `Skipped`;
  - `RemoveFromQueue` toglie dalla coda di Radarr/Sonarr le voci con `MovieId`/`SeriesId` (e stagione) del titolo, senza blocklist;
  - `RemoveTorrents` cancella i `RemoveNow`, aggiunge i `RemoveLater` a `Pending` (con `Title`) e mette `Done`/`Waiting`. Per `Torrent` controlla la regola del seed sul torrent dal vivo: se non si può, `Skipped` con `SeedRule`. `AllTorrents` prende i torrent "solo torrent" che oggi si possono togliere;
  - `RemoveFromSeerr` usa `FindMediaIdAsync("movie"|"tv", tmdbId)`, poi `DeleteMediaAsync`. Seerr non configurato → `Skipped` `NotConfigured`; media null → `Skipped` `Gone`;
  - `DeleteFile` chiama `IFileProbe.Delete` con le radici consentite: per `Orphan` sono `ScanFolders`, per `Duplicate` il `Path` del film o della serie da Radarr/Sonarr. Falso → `Failed` `Failed`;
  - `ReadQuota` mette `QuotaAfterBytes`;
  - errori: `ArrException`/`QbitException`/`SeerrException` con 404 → `Skipped` `Gone`, e si continua. Tutti gli altri → `Failed` con il codice (`NotConfigured`/`Unauthorized`/`Unreachable`), i passi rimasti `NotDone`, l'operazione `Failed`;
  - alla fine l'operazione è `Done`; `EndedAt` dal `TimeProvider`; si salva il file a ogni cambio di passo.
- **`CheckPendingAsync`:**
  - legge i torrent da qBittorrent; quelli in attesa che non ci sono più escono;
  - quelli che `SeedRule` ora permette si cancellano, e per ognuno si registra un'operazione `Torrent` con `Auto` = vero, già `Done`, con i passi `RemoveTorrents` e `ReadQuota`;
  - qBittorrent non risponde → si riprova al giro dopo.

- [ ] **Step 1: test che falliscono:**
  - `SpaceStoreTests`:
    - `TheFileRoundTrips`: un tenuto, un in attesa e un'operazione con due passi tornano uguali;
    - `ABrokenFileStartsEmpty`: `{"Version":2}` → vuoto e il file in `.bad`;
    - `OldOperationsArePruned`: un'operazione di 31 giorni fa sparisce.
  - `SpaceOperationsTests`, con i fake, `FakeTimeProvider`, una `SpaceScan` minima con un film `movie:12` (TMDB 354912, un file `/srv/media/Coco.mkv` hardlink a `/srv/downloads/Coco.mkv` in un torrent `h1` non protetto):
    - `AMovieRunsAllStepsInOrder`: l'ordine delle chiamate è coda di Radarr, `DeleteMovieAsync(12)`, `DeleteAsync(["h1"])`, `FindMediaIdAsync("movie",354912)`, `DeleteMediaAsync`, `Refresh()`. Tutti i passi `Done`, operazione `Done`;
    - `AProtectedTorrentGoesPending`: `h1` su `itatorrents.xyz` con ratio 1 → nessun `DeleteAsync`, `Pending` con `h1`, passo `RemoveTorrents` `Done` = 0, `Waiting` = 1;
    - `QbitDownStopsAfterRadarr`: `FakeQbitClient.Fail = Unreachable` dopo `FindTorrents` → `DeleteFromRadarr` `Done`, `RemoveTorrents` `Failed` `Unreachable`, `RemoveFromSeerr`/`RefreshLibrary`/`ReadQuota` `NotDone`, operazione `Failed`;
    - `RetryingSkipsWhatIsGone`: di nuovo la stessa operazione con Radarr che risponde 404 → `DeleteFromRadarr` `Skipped` `Gone`, torrent tolti, operazione `Done`;
    - `ASecondStartOnTheSameKeyIsBusy`: due `Start("Movie","movie:12")` di fila → `Started` poi `Busy`;
    - `AnUnknownKeyIsUnknown`: `movie:99` → `Unknown`; prima di un calcolo → `NotReady`;
    - `ASeasonUnmonitorsAndDeletesItsFiles`: `season:5:2` → `SetSeasonMonitoredAsync(5,2,false)` e `DeleteEpisodeFilesAsync` con gli id dei file della stagione 2; nessuna chiamata a Seerr;
    - `AFileOutsideTheRootsIsNeverDeleted`: un'operazione `Orphan` su un `file:` il cui percorso nel calcolo è `/etc/passwd` → `DeleteFile` `Failed`, `FakeFileProbe.Deleted` vuoto;
    - `PendingTorrentsGoWhenAllowed`: un in attesa con `ExpectedAt` fra 1 giorno; dopo 1 giorno con il torrent a 30 giorni di seed, `CheckPendingAsync` lo cancella, lo toglie dall'attesa e registra un'operazione `Auto`;
    - `QuotaBeforeAndAfterAreRecorded`: il testo di quota cambia tra prima e dopo → `QuotaBeforeBytes` e `QuotaAfterBytes` giusti.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~SpaceStoreTests|FullyQualifiedName~SpaceOperationsTests"`).
- [ ] **Step 3: il codice.** `SpaceScan` (Task 10) si può introdurre qui come record con i soli campi che servono alle operazioni:
  - film: id Radarr, TMDB, percorso della cartella;
  - serie: id Sonarr, TMDB, percorso della cartella;
  - per i file: chiave → percorso;
  - per i torrent: hash → `TorrentFacts`.
  Il Task 10 lo completa.
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): operazioni dello spazio con i passi e torrent in attesa di fine seed"`

### Task 10: il calcolo

**Files:**
- Create: `Space/SpaceService.Scan.cs`
- Modify: `Space/SpaceService.cs`
- Test: `Tests/SpaceScanTests.cs`

**Interfaces:**
- Consumes: tutto dai Task 1–9; `ISeriesIndex`, `RatingService`, `IUserDirectory`.
- Produces:
  - `public Task ScanAsync(CancellationToken ct)`: calcola e sostituisce `LastScan`. Una sola alla volta: una seconda chiamata durante un calcolo ritorna subito;
  - `public bool Scanning`;
  - `public SpaceOverviewDto Overview(Guid callerId)`: dall'ultimo calcolo, togliendo i tenuti e i preferiti di `callerId`, con `TopGenres` di `callerId`, `Pending`, `Kept` e le ultime 20 operazioni.
- **Come calcola:**
  1. legge da Radarr i film e da Sonarr le serie con i file di ogni serie (`GetEpisodeFilesAsync`); un servizio che non risponde va in `Errors` e le sue liste restano vuote;
  2. legge da qBittorrent i torrent e i loro file (`content_path` per un torrent con un solo file, altrimenti `GetFilesAsync`). Un tracker vuoto si cerca con `GetTrackersAsync` (decisione 10);
  3. passa a `stat` i file della libreria, i file dei torrent e i file video di `ScanFolders`, poi costruisce `TorrentIndex` e l'insieme dei `FileId` della libreria;
  4. collega film e serie a Jellyfin con `ISeriesIndex` (TMDB per i film, TVDB poi TMDB per le serie) e legge la visione con `IViewingFacts`;
  5. legge da Seerr le richieste (decisione 9). Un errore di Seerr va in `Errors.Seerr` e lascia le richieste vuote;
  6. i candidati:
     - film con `HasFile`;
     - serie `ended` intere;
     - stagioni con `episodeFileCount > 0`, tranne la stagione 0 e l'ultima di una serie in corso;
     - di una serie `ended` candidata intera non si mostrano le stagioni;
     - una riga entra in `Delete` se `Via` non è vuoto;
     - `Keep`, voti (decisione 8) e `SequelComing` (decisione 5) come da regole;
  7. `Lighten`:
     - film con `MovieFile.Size / 10⁹ / (runtime/60) > HeavyGbPerHour` (durata 0 → 100 minuti);
     - stagioni dove la somma dei file degli episodi supera `HeavyGbPerHour` × episodi × durata (durata 0 → 40 minuti);
     - `ExcessBytes` = dimensione − soglia × durata;
     - escluse le chiavi già in `Delete`;
  8. `Cleanup`:
     - `Torrents`: i torrent per cui `IsTorrentOnly` è vero;
     - `Orphans`: i file video di `ScanFolders` che non sono di nessun torrent (stesso percorso) e hanno `Links` 1;
     - `Duplicates`: i file video nelle cartelle di film e serie (`Path` di Radarr/Sonarr) che Radarr/Sonarr non conoscono, con `Linked` = `Links > 1`;
  9. `Breakdown`:
     - film e serie da `sizeOnDisk`, con `Anime` se il percorso contiene `/anime/`;
     - `TorrentOnlyBytes` = la somma dei torrent di `Cleanup.Torrents`;
     - `OtherBytes` come da Global Constraints;
  10. `PosterUrl` dalle immagini `poster` di Radarr/Sonarr (`RemoteUrl`), come la Spec T.

- [ ] **Step 1: test che falliscono** con i fake e dati piccoli:
  - `AStaleMovieIsADeleteCandidate`: un film visto da Anna 8 mesi fa → in `Delete` con `Via` [`NobodyWatching`], `Viewers` [Anna], `FreeNowBytes` = la dimensione.
  - `AKeptOrFavoriteTitleIsHidden`: lo stesso film tenuto → assente; non tenuto ma preferito di chi chiama → assente; preferito di un altro → presente.
  - `AContinuingSeriesOffersOldSeasonsOnly`: una serie `continuing` con le stagioni 1–3 tutte viste 1 anno fa → candidate la 1 e la 2 con `SeriesKey` `series:5`, la 3 no, la serie intera no.
  - `AnEndedSeriesIsWhole`: `ended` e vista tutta 1 anno fa → una riga `Series`, nessuna `Season`.
  - `SequelComingFromTheRadarrCollection`: un film nella collezione 10 con un altro film della 10 senza file e `status` `announced` → `Keep` contiene `SequelComing`.
  - `AHeavyMovieIsInLighten`: un film di 120 minuti da 12 GB con soglia 4 → `GbPerHour` 6,00, `ExcessBytes` 4_000_000_000.
  - `TorrentOnlyAndOrphansAreInCleanup`: un torrent con `Links` 1 → in `Torrents`; un file in `/srv/downloads` di nessun torrent con `Links` 1 → in `Orphans`.
  - `ADuplicateInAMovieFolder`: due `.mkv` nella cartella del film, Radarr ne conosce uno → l'altro in `Duplicates`.
  - `SonarrDownKeepsRadarr`: Sonarr `Unreachable` → film presenti, `Errors.Sonarr` = `Unreachable`.
  - `TheListsAreOrdered`: due candidati senza `Keep` (3 e 5 GB) e uno con `Keep` da 9 GB → l'ordine è 5, 3, 9.
- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~SpaceScanTests"`).
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): calcolo dello spazio, candidati e pulizia"`

### Task 11: endpoint, servizio in background, Alleggerisci, Info

**Files:**
- Create: `Protocol/SpaceDtos.cs` (se non è già nato nei task precedenti), `Api/SpaceController.cs`, `SpaceHostedService.cs`
- Modify:
  - `PluginServiceRegistrator.cs`: `SpaceStore`, `SpaceService`, `IQbitClient`, `IFileProbe`, `IViewingFacts`, `ILibraryRefresh`, `ISpaceSettings`, hosted service;
  - `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs`;
  - `Downloads/DownloadService.Admin.cs`, `Downloads/DownloadService.cs`, `Downloads/DownloadService.Search.cs`, `Api/DownloadsController.cs`, `Protocol/DownloadsDtos.cs`.
- Test: `Tests/SpaceControllerTests.cs`, `Tests/ServiceRegistrationTests.cs`, `Tests/InfoControllerTests.cs`, i test di `DownloadService` (`Tests/DownloadServiceTests.cs` o quello che c'è)

**Interfaces:**
- Consumes: `SpaceService` (Task 9–10).
- Produces:
  - gli endpoint di Global Constraints. `GET Space` usa l'utente di chi chiama (come gli altri controller: claim dell'utente Jellyfin). Con una chiave API senza utente si usa `Guid.Empty`: nessun preferito tolto, `TopGenres` vuoto;
  - `SpaceHostedService`: calcolo dopo `FirstScanDelay` e poi ogni `ScanInterval`; `CheckPendingAsync` ogni `PendingInterval`; `RunOperationsAsync` per tutta la vita del servizio. Timer con `time.CreateTimer`, come `DownloadsHostedService`. `POST Space/Recalculate` chiama `ScanAsync` senza aspettarlo;
  - `WatchPartyProtocol.SpaceFeature = "space"`, in `FeaturesWith` subito dopo `downloads` alle stesse condizioni;
  - Spec T:
    - `GrabRequest` ha `bool Lighten` (facoltativo);
    - `DownloadService.GrabAsync(string key, string guid, int indexerId, CancellationToken ct, bool lighten = false)`: con `lighten` e un esito `Ok`, `Book.Accept(key)` e salva;
    - `OnImported`: se `Book.IsAccepted(entry.Key)`, `Book.Remove(entry.Key)` invece di `UpgradeWatch`;
    - `IsDue`: un `UpgradeWatch` accettato non è dovuto.

- [ ] **Step 1: test che falliscono:**
  - `SpaceControllerTests`:
    - `StartReturnsTheId`: `POST Space/Operations` `{"Kind":"Movie","Key":"movie:12"}` → 202 con `Id`;
    - `StartMapsTheOutcomes`: `Busy`/`NotReady` → 409 con `Reason`; `Unknown` → 404 `{"Reason":"Unknown"}`; `Invalid` → 400;
    - `TheOperationIsReadable`: `GET Space/Operations/{id}` → i passi; un id sconosciuto → 404;
    - `KeepAndUnkeep`: `POST Space/Kept` poi `DELETE Space/Kept?key=movie:12` → 204 e 204;
    - `NullFieldsAreWritten`: il JSON di un candidato senza `Year` contiene `"Year":null`.
  - `ServiceRegistrationTests`: i servizi in background passano da 9 a **10**.
  - `InfoControllerTests`: `Version` "1.16.0"; `space` dopo `downloads` con Sonarr o Radarr, assente senza.
  - Download:
    - `ALightenGrabIsAccepted`: `GrabAsync(…, lighten: true)` → `IsAccepted`;
    - `AnAcceptedImportDoesNotWatchUpgrades`: dopo l'import di un titolo accettato con punteggio sotto l'obiettivo → nessuna voce `UpgradeWatch`;
    - `TheGrabBodyReadsLighten`: `{"Key":"movie:1","Guid":"g","IndexerId":3,"Lighten":true}` arriva a `GrabAsync` con `lighten` vero.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice; versione 1.16.0** nel csproj e in `../meta.template.json` (con la riga di changelog in italiano: "Scheda Spazio: candidati da cancellare, alleggerire e pulizia del seedbox").
- [ ] **Step 4: la suite intera passa.**
- [ ] **Step 5: commit** `git commit -m "feat(plugin): endpoint dello spazio, Alleggerisci nei download e versione 1.16.0"`

### Task 12: README e spec allineate

**Files:**
- Modify: `../README.md`, `docs/superpowers/specs/2026-10-30-wonderflix-spazio-seedbox-design.md`

- [ ] **Step 1: README del plugin**, sezione "Spazio":
  - cosa fa;
  - la configurazione di qBittorrent;
  - il cron della quota (Task 13);
  - la regola di qui da correggere (spec §6.3, nota);
  - che il cestino di Radarr e Sonarr deve restare spento perché la cancellazione liberi spazio.
- [ ] **Step 2: spec**, le decisioni del piano 1–14 dove cambiano o precisano il testo:
  - §4.2 seguito dalla collezione di Radarr;
  - §5.2 Alleggerire per stagione;
  - §5.4 e §9 quota dal file del cron;
  - §7.3 calcolo in memoria;
  - §12 collegamento con l'inode, `QueueLibraryScan`.
  "Stato": piano 30a realizzato.
- [ ] **Step 3: commit** `git commit -m "docs: spec U e README del plugin allineati al piano 30a"`

### Task 13: build di prova sul server

- [ ] **Step 1: pacchetto:** `& "C:\Program Files\Git\bin\bash.exe" plugin/pack.sh 1.16.0`.
- [ ] **Step 2: cron della quota** sul seedbox (`ssh ultra`). Aggiungi a `crontab -e` (senza togliere le righe che ci sono) la riga:
  `*/10 * * * * quota -w > /home/hashvps/.config/wonderflix-quota.txt 2>/dev/null`
  Poi lancia il comando una volta a mano. Controlla che il file si veda anche da dentro Jellyfin: `ls /proc/$(pgrep -u $USER -x jellyfin | head -1)/root/home/hashvps/.config/wonderflix-quota.txt`. Se dal container non si vede, usa una cartella che si vede, per esempio `/home/hashvps/.apps/jellyfin/`, e scrivila nel registro.
- [ ] **Step 3: installazione di prova**, come è descritto nel README (copia della cartella del plugin in `~/.apps/jellyfin/data/plugins/` con la nuova versione, `app-jellyfin restart`). La cartella più vecchia la toglie Jellyfin.
- [ ] **Step 4: configurazione.** L'indirizzo di qBittorrent `http://127.0.0.1:17541`, il file della quota e le cartelle li scrive l'implementatore nel file di configurazione del plugin (`~/.apps/jellyfin/data/plugins/configurations/`). **Utente e password di qBittorrent li inserisce l'admin** dalla dashboard: l'implementatore non li cerca e non li scrive.
- [ ] **Step 5: verifica in sola lettura:**
  - `GET /jellyfin/WonderFlixWatchParty/Info` contiene `space`;
  - dopo 2-3 minuti, `GET /jellyfin/WonderFlixWatchParty/Space` con una chiave API di Jellyfin (header `Authorization: MediaBrowser Token="…"`; se non ce n'è una, chiedila all'admin e non stamparla) restituisce `ScannedAt`, la quota e le liste non vuote;
  - nel log di Jellyfin nessun errore del plugin e nessun titolo o percorso.
  Annota nel registro il numero di candidati, di torrent "solo torrent" e i GB. **Non** avviare operazioni.
- [ ] **Step 6:** niente commit: il pacchetto non va nel repo.
