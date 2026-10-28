# WonderFlix — Piano 29a: download automatici, plugin 1.14.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec T nel plugin 1.14.0:
- la regola di scelta dell'admin (§4);
- il ciclo in background che cerca, sceglie, scarica, segue la coda e gli upgrade (§5);
- l'elenco "Da ripassare" (§6);
- le azioni admin: ricerca con la regola, scarica, "cambia", "va bene così", ricerca subito;
- la configurazione, la funzione `downloads` in `Info`, la versione 1.14.0 e una build di prova sul server.

L'app arriva nel piano 29b: usa i JSON di "Global Constraints", quindi **i nomi delle proprietà JSON non si cambiano**.

**Architecture:**
- `IArrClient` impara la ricerca manuale, il download di una release, la coda, i file e i profili, con un invio generico (GET/POST/DELETE) al posto del solo `GetAsync`.
- Tre parti pure, senza I/O, con i loro test: `DownloadRule` (la regola e "lo importerebbero?"), `DownloadSchedule` (quando ricercare), `SeasonPackRule` (pack o episodi).
- `DownloadBook` tiene lo stato in memoria; `DownloadStore` lo salva in `downloads.json`, come `ReportStore`.
- `DownloadService` fa il ciclo (`RunCycleAsync`), l'elenco da ripassare (`BuildReviewAsync`) e le azioni admin. `DownloadsHostedService` lo fa girare con i timer. `DownloadsController` espone gli endpoint admin.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md` (tutta; l'app è §8).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 13):
1. **Chiavi dei titoli:** `movie:{idRadarr}`, `episode:{idEpisodioSonarr}`, `season:{idSerieSonarr}:{numeroStagione}`.
2. **Download falliti senza la cronologia:** un titolo "in download" che sparisce dalla coda senza che Radarr/Sonarr abbiano il file è fallito (Radarr e Sonarr mettono già in blocklist la release fallita). Niente lettura di `history` (spec §7.2).
3. **Download fermo:** `sizeleft` uguale per 24 ore. Non si leggono i seeders della coda.
4. **Punteggio dopo l'import:** è quello della release scaricata, già nota. Non si rilegge il file.
5. **"Lo importerebbero?":** posizione della qualità nel profilo (gli `items` ammessi vanno dal più basso al più alto; un gruppo è una posizione sola). Importa se la posizione nuova è più alta, o se è uguale e il punteggio è più alto.
6. **Pack di stagione e singoli dalla stessa ricerca:** la ricerca di stagione di Sonarr restituisce pack e singoli episodi. I singoli si raggruppano per episodio e se ne prende il migliore con la regola. Se ogni episodio mancante ne ha uno, si confronta la somma con il pack (§5.4). Se il pack non conviene, la voce di stagione si divide in voci di episodio da cercare subito. Niente ricerche in più.
7. **Ritmo del giro:** un giro ogni 15 minuti, al massimo 10 ricerche per giro, 10 secondi tra l'una e l'altra; l'elenco da ripassare ogni 24 ore. Dopo un'approvazione in WonderFlix il giro parte dopo 1 minuto, il tempo che Seerr aggiunga il titolo a Radarr/Sonarr.
8. **Soglie per profilo senza riga in configurazione:** profilo con "anime" nel nome (senza maiuscole): minimo 1, obiettivo nessuno; altrimenti minimo 50, obiettivo 150.
9. **Import manuale con sostituzione:** si prova solo per una release scelta dall'admin che Radarr/Sonarr non importerebbero. Se l'import manuale fallisce, la voce va in "Serve te" con `ImportBlocked`.

## Global Constraints

- Plugin **1.14.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9.
- **Endpoint** sotto `/WonderFlixWatchParty`, tutti in `DownloadsController` con `[Authorize(Policy = Policies.RequiresElevation)]` sulla classe (come `AccountAdminController`):
  - `GET Downloads` → `DownloadsOverviewDto`;
  - `GET Downloads/Search?key=` → `DownloadSearchDto` (ricerca dal vivo, fino a 2 minuti); 400 per una chiave non valida;
  - `POST Downloads/Grab` corpo `{"Key","Guid","IndexerId"}` → 204; 409 `{"Reason":"Expired"}` se la release non c'è più; 400 per corpo o chiave non validi;
  - `POST Downloads/Accept` corpo `{"Key"}` → 204 ("va bene così");
  - `POST Downloads/SearchNow` corpo `{"Key"}` → 202;
  - `GET Downloads/Profiles` → `[DownloadProfileDto]` (per la pagina di configurazione).
- **JSON** (PascalCase, tutti i campi scritti anche se null):
  - `DownloadReleaseDto`: `Guid`, `IndexerId`, `Indexer`, `Title`, `Quality` (nome, es. `"WEBRip-1080p"`), `Resolution` (int), `SizeBytes` (long), `Score` (int), `Seeders` (int?).
  - `DownloadChoiceDto`: `Key`, `Kind`, `Title`, `PosterUrl`, `At`, `Release` (`DownloadReleaseDto`), `PreviousSizeBytes` (long?), `PreviousScore` (int?), `ByAdmin` (bool).
  - `DownloadItemDto`: `Key`, `Kind`, `Title`, `PosterUrl`, `State`, `Reason`, `AvailableSince`, `LastSearchAt`, `NextSearchAt`.
  - `ReviewItemDto`: `Key`, `Kind`, `Title`, `PosterUrl`, `Score`, `SizeBytes`, `Quality`.
  - `DownloadsOverviewDto`: `Enabled`, `Recent` (`[DownloadChoiceDto]`, dalla più recente, 90 giorni), `Waiting` (`[DownloadItemDto]`, compresi quelli `NeedsYou`), `Review` (`[ReviewItemDto]`), `ReviewAt`, `SonarrError`, `RadarrError`.
  - `DownloadCandidateDto`: `Rank` (da 1), `Release`, `IsChoice`, `WouldImport`.
  - `DownloadRejectedDto`: `Release`, `Reason`, `Detail`.
  - `DownloadCurrentFileDto`: `SizeBytes`, `Score`, `Quality`.
  - `DownloadSearchDto`: `Key`, `Kind`, `Title`, `RuntimeMinutes`, `Current` (`DownloadCurrentFileDto?`), `Candidates`, `Rejected`, `ValidCount`, `TotalCount`, `Error`.
  - `DownloadProfileDto`: `Service` (`"Radarr"`/`"Sonarr"`), `ProfileId`, `Name`, `MinScore`, `TargetScore` (int?).
- **Valori stringa:**
  - `Kind`: `Movie`, `Episode`, `Season`;
  - `State`: `Waiting`, `Downloading`, `UpgradeWatch`, `NeedsYou`;
  - `Reason` di una voce: `NothingFound`, `BelowMinScore`, `ImportBlocked`, `SearchFailed`, o null;
  - `Reason` di uno scarto: `Arr` (rifiuto di Radarr/Sonarr, `Detail` = il primo testo), `TooSmall` (`Detail` = GB all'ora con due decimali, `"0.62"`);
  - errori: i codici di `UpcomingErrors` (`NotConfigured`, `Unauthorized`, `Unreachable`).
- **Valori della spec:**
  - `DownloadRule.DefaultMinGbPerHour = 0.8`; GB = 10⁹ byte;
  - durata se manca: `FallbackMovieMinutes = 100`, `FallbackEpisodeMinutes = 40`;
  - soglie predefinite: decisione 8;
  - `DownloadSchedule`: 6 ore fino a 7 giorni, 24 ore fino a 30 giorni, poi 7 giorni;
  - `NeedsYouAfter = 7 giorni` senza candidati validi;
  - `UpgradeWindow = 30 giorni`;
  - `StalledAfter = 24 ore`;
  - `SeasonPackRule.MaxPackRatio = 1.2`;
  - storia delle scelte: `ChoiceRetention = 90 giorni`;
  - giro: decisione 7 (`CycleInterval = 15 min`, `MaxSearchesPerCycle = 10`, `PauseBetweenSearches = 10 s`, `ReviewInterval = 24 h`, `NudgeDelay = 1 min`);
  - ricerca: `ArrClient.SearchTimeout = 2 min`.
- **Rifiuti ignorati** (prefissi, senza badare alle maiuscole): `"Existing file on disk"`, `"Not an upgrade"`, `"Release in queue"`. Il primo implementatore li controlla sul server (Task 1) e li scrive nel registro.
- **`Info`:** `Version` "1.14.0", `Protocol` 1, `Features` con `"downloads"` subito dopo `"calendar"`, presente quando c'è almeno Sonarr o Radarr.
- **Configurazione** (`PluginConfiguration`): `DownloadsEnabled` (bool, `false`), `DownloadsMinGbPerHour` (double, `0.8`), `DownloadProfileRules` (`DownloadProfileRule[]`, vuoto; `DownloadProfileRule` ha `Service` string, `ProfileId` int, `MinScore` int, `TargetScore` int?).
- **Id e date:** id di Jellyfin in formato `"N"`; `TimeProvider`, mai `DateTimeOffset.UtcNow`.
- **Log:** **mai titoli di release, chiavi, indirizzi o query**, solo servizio, percorso senza query, chiave del titolo (`movie:12`), codici d'errore. `Warning` per Sonarr o Radarr che non rispondono.
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi; messaggi in italiano.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.

## Review Focus

1. **Prima accensione con tanti titoli mancanti** (28 film, 155 episodi): un giro non fa più di 10 ricerche e non scarica due volte lo stesso titolo; i titoli già in coda non si cercano. Test: Task 7 (`ACycleSearchesAtMostTenTitles`, `ATitleInTheQueueIsNotSearched`).
2. **Un torrent lento ma vivo** non va trattato come fermo: conta solo un `sizeleft` immobile per 24 ore. Test: Task 6 (`ASlowDownloadIsNotStalled`).
3. **Radarr risponde e Sonarr no (o il contrario):** il giro continua con l'altro servizio e la panoramica riporta l'errore di quello fermo. Test: Task 7 (`OneServiceDownKeepsTheOther`), Task 11 (`TheOverviewReportsAServiceError`).
4. **`downloads.json` rovinato o di una versione futura:** il plugin parte vuoto, sposta il file in `.bad` e non smette di funzionare. Test: Task 5 (`ABrokenFileStartsEmpty`).
5. **L'admin preme "scarica" dopo 30 minuti** (risultati scaduti in Radarr): WonderFlix rifà la ricerca e scarica la stessa release se c'è ancora, altrimenti 409 `Expired`. Test: Task 9 (`AnExpiredReleaseIsSearchedAgain`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/download-automatici`): fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" plugin/pack.sh 1.14.0`.
- **Test:**
  - un gruppo: `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj ha `TreatWarningsAsErrors`), poi `dotnet build-server shutdown`;
  - il primo implementatore conta i test verdi di partenza e li scrive nel registro.
- **Server** (solo dove il task lo dice): `ssh ultra`. Le chiavi si leggono da `~/.apps/radarr/config.xml` e `~/.apps/sonarr/config.xml` sul server e **non si stampano mai**. Radarr `http://127.0.0.1:17527/radarr`, Sonarr `http://127.0.0.1:17526/sonarr`. Solo letture e ricerche (`GET release`): **mai** `POST release`, `DELETE queue` o comandi sul server vero.
- **Formattazione:** ogni file tiene le sue terminazioni di riga (working copy CRLF, indice LF; i file nuovi vanno bene con LF). UTF-8 con gli strumenti di modifica dei file, mai `Set-Content`/`Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese; ogni tipo nuovo ha il suo `/// <summary>` con il riferimento alla spec ("spec T §4");
  - durate e limiti come costanti nominate e commentate; `TimeProvider`;
  - DTO `record` con `[property: JsonPropertyName("…")]` in `Protocol/DownloadsDtos.cs`; modelli di Sonarr/Radarr come classi con proprietà `{ get; set; }` in `Home/ArrJson.cs`;
  - `Lock` di .NET 9.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo; preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-28 sul codice di `main` (`716e744`) e sul server.

- **`ArrClient.GetAsync<T>(kind, path, ct)`** (privato): chiave, timeout `Timeout` (10 s, `internal init` per i test), errori come `ArrException` (`NotConfigured`, `Unauthorized`, `Unreachable`), log senza query. `Classify(status)`: 401/403 → `Unauthorized`, il resto → `Unreachable`.
- **`FakeArrClient`** in `Tests/`: gestori `Func<…>` e liste di chiamate sotto `_lock`. **`FakeArrSettings`** (`Sonarr`, `Radarr`, `ArrEndpoint.None`). `ArrClientTests` usa `FakeSeerrHttp`, indirizzi `https://arr.example/sonarr` e `/radarr`, chiavi `sonarr-key`/`radarr-key`.
- **`ReportStore`/`ReportBook`/`ReportsHostedService`**: il modello da copiare per file, `.bad`, caricamento all'avvio e timer con `time.CreateTimer`.
- **`RequestsService.ApproveAsync(Guid userId, int requestId, ApproveBody? body, string language, CancellationToken)`**: dopo un'approvazione riuscita si chiama il "nudge" (Task 10).
- **`WatchPartyProtocol.FeaturesWith(bool requests, bool upcomingSeries, bool upcomingMovies)`**: `calendar` c'è con almeno uno dei due; `InfoControllerTests` controlla versione e funzioni.
- **DI:** `PluginServiceRegistrator`; `ServiceRegistrationTests` conta **8** servizi in background (diventano 9).
- **Server** (spec §2 e controlli del 2026-10-28):
  - `GET movie`: ogni film ha `id`, `title`, `year`, `runtime`, `monitored`, `isAvailable`, `hasFile`, `qualityProfileId`, `movieFile.id`, `images`; il punteggio del file non c'è (`movieFile.customFormatScore` null).
  - `GET moviefile` vuole `movieId` o `movieFileIds` (ripetibile: `moviefile?movieFileIds=1&movieFileIds=2`); ogni file ha `movieId`, `customFormatScore`, `size`, `quality.quality`.
  - `GET episodefile` vuole `seriesId`; ogni file ha `id`, `seasonNumber`, `customFormatScore`, `size`, `quality.quality`.
  - `GET wanted/missing?page=&pageSize=&monitored=true&includeSeries=true` (Sonarr): `{totalRecords, records:[{id, seriesId, seasonNumber, episodeNumber, airDateUtc, monitored, hasFile, series:{title, runtime, qualityProfileId, status, images}}]}`. 145 episodi oggi.
  - `GET queue?page=&pageSize=`: `{totalRecords, records:[{id, movieId | episodeId+seriesId+seasonNumber, downloadId, size, sizeleft, trackedDownloadState}]}`. `trackedDownloadState`: `downloading`, `importBlocked`, `importPending`, `importing`, `imported`, `failedPending`, `failed`, `ignored`.
  - `GET qualityprofile`: `items` ammessi dal più basso al più alto; un gruppo ha `name` e `items[].quality`, una qualità sola ha `quality` e niente `name`. Radarr Main: HDTV-720p, WEB 720p, Bluray-720p, HDTV-1080p, WEB 1080p, Bluray-1080p.
  - `GET release`: campi in spec §2. In Sonarr anche `fullSeason` e `episodeNumbers`. `quality.quality` ha `id`, `name`, `resolution`.
  - `GET indexer`: `id`, `priority` (numero più basso = preferito).

## File

| File | Responsabilità |
|---|---|
| `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs` | le chiamate nuove e i loro modelli |
| `Downloads/DownloadRule.cs` | la regola (§4) e "lo importerebbero?" |
| `Downloads/DownloadSchedule.cs`, `Downloads/SeasonPackRule.cs` | quando ricercare; pack o episodi |
| `Downloads/IDownloadSettings.cs`, `Server/PluginDownloadSettings.cs`, `Configuration/PluginConfiguration.cs` | le impostazioni |
| `Downloads/DownloadBook.cs`, `Downloads/DownloadStore.cs` | lo stato e `downloads.json` |
| `Downloads/DownloadService.cs` | il ciclo, l'elenco da ripassare, le azioni admin |
| `Downloads/DownloadKey.cs` | le chiavi dei titoli |
| `DownloadsHostedService.cs` | i timer |
| `Protocol/DownloadsDtos.cs`, `Api/DownloadsController.cs` | gli endpoint |
| `Hub/RequestsService.cs` | il nudge dopo un'approvazione |
| `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs`, csproj, `Configuration/configPage.html`, `../meta.template.json`, `../README.md` | montaggio, `Info`, configurazione, versione, documentazione |

I percorsi sono relativi a `plugin/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test, scritti `Tests/…`), se non è detto altro.

---

### Task 1: le chiamate nuove a Sonarr e Radarr

**Files:**
- Modify: `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs`
- Modify (test): `Tests/FakeArrClient.cs`
- Test: `Tests/ArrClientTests.cs`

**Interfaces:**
- Produces (modelli in `Home/ArrJson.cs`):
  - `ArrQuality { int Id; string? Name; int Resolution }`; `ArrQualityModel { ArrQuality? Quality }`.
  - `ArrRelease { string? Guid; int IndexerId; string? Indexer; string? Title; long Size; int? Seeders; ArrQualityModel? Quality; int CustomFormatScore; bool Rejected; List<string>? Rejections; bool FullSeason; List<int>? EpisodeNumbers; int SeasonNumber }`.
  - `ArrQualityProfileItem { string? Name; ArrQuality? Quality; List<ArrQualityProfileItem>? Items; bool Allowed }`; `ArrQualityProfile { int Id; string? Name; List<ArrQualityProfileItem>? Items }`.
  - `ArrQueueItem { int Id; int? MovieId; int? EpisodeId; int? SeriesId; int? SeasonNumber; string? DownloadId; long Size; long Sizeleft; string? TrackedDownloadState }`.
  - `ArrFile { int Id; int MovieId; int SeasonNumber; int CustomFormatScore; long Size; ArrQualityModel? Quality }` (film ed episodi).
  - `ArrIndexer { int Id; int Priority }`.
  - `RadarrMovie` in più: `int Id`, `int Runtime`, `bool Monitored`, `bool IsAvailable`, `int QualityProfileId`, `ArrFileRef? MovieFile` (`ArrFileRef { int Id }`).
  - `SonarrSeries` in più: `int Runtime`, `int QualityProfileId`, `string? Status`, `SonarrSeriesStatistics? Statistics` (`EpisodeFileCount`).
  - `SonarrEpisode` in più: `int Id`, `bool Monitored`, `int EpisodeFileId`.
  - `ArrPage<T> { int TotalRecords; List<T?>? Records }`.
- Produces (`IArrClient`, tutti lanciano `ArrException`):
  - `Task<IReadOnlyList<ArrRelease?>> SearchReleasesAsync(ArrKind kind, string query, CancellationToken ct)` → `release?{query}` (`movieId=12`, `episodeId=34`, `seriesId=5&seasonNumber=2`), timeout `SearchTimeout`;
  - `Task GrabReleaseAsync(ArrKind kind, string guid, int indexerId, CancellationToken ct)` → `POST release` con `{"guid","indexerId"}`;
  - `Task<IReadOnlyList<RadarrMovie?>> GetLibraryMoviesAsync(CancellationToken ct)` → Radarr `movie`;
  - `Task<IReadOnlyList<SonarrEpisode?>> GetMissingEpisodesAsync(CancellationToken ct)` → Sonarr `wanted/missing?page={n}&pageSize=250&monitored=true&includeSeries=true`, tutte le pagine;
  - `Task<IReadOnlyList<ArrFile?>> GetMovieFilesAsync(IReadOnlyList<int> movieFileIds, CancellationToken ct)` → Radarr `moviefile?movieFileIds=…`, a gruppi di 100;
  - `Task<IReadOnlyList<ArrFile?>> GetEpisodeFilesAsync(int seriesId, CancellationToken ct)` → Sonarr `episodefile?seriesId=`;
  - `Task<IReadOnlyList<ArrQualityProfile?>> GetQualityProfilesAsync(ArrKind kind, CancellationToken ct)` → `qualityprofile`;
  - `Task<IReadOnlyList<ArrQueueItem?>> GetQueueAsync(ArrKind kind, CancellationToken ct)` → `queue?page={n}&pageSize=250`, tutte le pagine;
  - `Task RemoveFromQueueAsync(ArrKind kind, int queueId, bool blocklist, CancellationToken ct)` → `DELETE queue/{id}?removeFromClient=true&blocklist={true|false}`;
  - `Task<IReadOnlyList<ArrIndexer?>> GetIndexersAsync(ArrKind kind, CancellationToken ct)` → `indexer`.
  - `public static readonly TimeSpan SearchTimeout = TimeSpan.FromMinutes(2)`;
  - `ArrException` impara `int? Status`: lo stato HTTP di una risposta non riuscita (null per rete e timeout). Serve al Task 9 per riconoscere una release scaduta.
- Produces (`FakeArrClient`): un gestore e una lista di chiamate per ogni metodo nuovo, come quelli che ci sono (predefiniti: elenchi vuoti, `Task.CompletedTask`).

- [ ] **Step 1: controlla sul server** (sola lettura, regole sopra) i testi dei rifiuti di una ricerca di Radarr e di una di Sonarr su un titolo con il file. Scrivi nel registro i prefissi di "file presente" e "in coda" che trovi; se non coincidono con quelli di Global Constraints, aggiorna la costante del Task 2 e segnalalo.
- [ ] **Step 2: test che falliscono** in `Tests/ArrClientTests.cs`:
  - `SearchingAMovieAsksRadarrForReleases`: indirizzo `https://arr.example/radarr/api/v3/release?movieId=915`, chiave `radarr-key`; risposta con una release `{"guid":"g1","indexerId":3,"indexer":"ItaTorrents (Prowlarr)","title":"Animals (2026) iTA-ENG WEBDL 1080p x264-Dr4gon mkv","size":2900000000,"seeders":7,"quality":{"quality":{"id":3,"name":"WEBDL-1080p","resolution":1080}},"customFormatScore":150,"rejected":true,"rejections":["Existing file on disk has a equal or higher Custom Format score: 150"]}` → tutti i campi letti.
  - `GrabbingPostsGuidAndIndexer`: `POST https://arr.example/radarr/api/v3/release` con corpo `{"guid":"g1","indexerId":3}`.
  - `MissingEpisodesReadEveryPage`: due pagine (`totalRecords` 300, 250 + 50 record) → 300 episodi, due chiamate con `page=1` e `page=2`.
  - `MovieFilesAreAskedInGroupsOfAHundred`: 150 id → due chiamate, la prima con 100 `movieFileIds`.
  - `RemovingFromTheQueueCanBlocklist`: `DELETE …/queue/77?removeFromClient=true&blocklist=true`.
  - `ASlowSearchUsesTheSearchTimeout`: con `Timeout` 50 ms e una risposta di 200 ms la ricerca riesce; una lettura normale va in `Unreachable`.
  - Aggiungi le chiamate nuove al test del log (`TheLogHasThePathButNeverTheKeyOrTheQuery`): nel registro i percorsi (`release`, `wanted/missing`, `queue`), mai `movieId=`, `guid` o il titolo della release.
- [ ] **Step 3: i test falliscono** (`--filter "FullyQualifiedName~ArrClientTests"`).
- [ ] **Step 4: il codice.** `GetAsync` diventa `SendAsync<T>(kind, HttpMethod method, string path, object? body, TimeSpan timeout, ct)`, con le stesse regole di errore e di log (metodo nel log); `GetAsync` resta come scorciatoia. Le pagine con un aiutante privato `GetAllPagesAsync<T>`.
- [ ] **Step 5: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 6: commit** `git commit -m "feat(plugin): ricerca manuale, download, coda, file e profili di Sonarr e Radarr"`

### Task 2: la regola di scelta

**Files:**
- Create: `Downloads/DownloadRule.cs`
- Test: `Tests/DownloadRuleTests.cs`

**Interfaces:**
- Consumes: `ArrRelease`, `ArrQualityProfile` (Task 1).
- Produces:
  - `public sealed record RuleInput(int RuntimeMinutes, bool IsMovie, double MinGbPerHour, int MinScore, IReadOnlyDictionary<int, int> IndexerPriority)`; `RuntimeMinutes` 0 → durata di ripiego.
  - `public sealed record RuleRejected(ArrRelease Release, string Reason, string? Detail)` (`Reason`: `"Arr"`, `"TooSmall"`).
  - `public sealed record RuleResult(IReadOnlyList<ArrRelease> Candidates, IReadOnlyList<RuleRejected> Rejected, ArrRelease? Choice, bool BelowMinScore)`: `Candidates` già ordinati; `Choice` = il primo, se il suo punteggio è ≥ `MinScore`; `BelowMinScore` vero se ci sono candidati ma il primo è sotto.
  - `public static class DownloadRule`:
    - `RuleResult Choose(IEnumerable<ArrRelease?> releases, RuleInput input)`;
    - `bool WouldImport(ArrQualityProfile profile, int newQualityId, int newScore, int? currentQualityId, int? currentScore)` (decisione 5; senza file attuale → vero; qualità non nel profilo → falso);
    - `double GbPerHour(long sizeBytes, int runtimeMinutes)`;
    - `IReadOnlyList<string> IgnoredRejectionPrefixes` (Global Constraints);
    - `const double DefaultMinGbPerHour = 0.8`, `const int FallbackMovieMinutes = 100`, `const int FallbackEpisodeMinutes = 40`.
  - Ordine (§4): punteggio decrescente; risoluzione 1080 prima di 720 (risoluzione decrescente); peso crescente; seeders decrescenti (null come 0); priorità dell'indexer crescente (indexer sconosciuto: 25); `Guid` come ultimo spareggio, perché l'ordine sia stabile.
  - Si scartano: release null o senza `Guid`; con un rifiuto che non comincia con un prefisso ignorato (`Arr`, `Detail` = il primo di questi); sotto `MinGbPerHour` (`TooSmall`).

- [ ] **Step 1: test che falliscono** in `Tests/DownloadRuleTests.cs`, con i dati veri di spec §1 (Animals, 106 minuti; In the Grey, 97 minuti):
  - `TheLightestTopScoreWins`: Animals con WEBDL x264 2,9 GB 150, WEBRip x265 1,89 GB 150, HEVC 4,83 GB 150 → scelta il WEBRip da 1,89 GB.
  - `ScoreComesBeforeWeight`: 9,71 GB Bluray 150 e 1,2 GB WEBRip 50 → 9,71 GB.
  - `TenEightyBeatsSevenTwentyAtTheSameScore`: Amistad (155 minuti), 1080p 9,47 GB 150 e 720p 8,38 GB 150 → 1080p.
  - `ExistingFileRejectionsAreIgnored`: una release con solo `Existing file on disk has a equal or higher Custom Format score: 150` resta candidata; una con `WEBDL-1080p is not wanted in profile` è scartata con `Reason` `"Arr"` e quel testo.
  - `TooSmallReleasesAreRejected`: 106 minuti, 1,0 GB (0,57 GB/ora) → `TooSmall`, `Detail` `"0.57"`; 1,5 GB passa.
  - `RuntimeFallsBackWhenMissing`: durata 0 di un film → si calcola su 100 minuti.
  - `BelowMinScoreHasNoChoice`: unico candidato con punteggio 0, minimo 50 → `Choice` null, `BelowMinScore` vero.
  - `TheSameFileOnTwoIndexersPrefersSeedersThenPriority`: stesso peso e punteggio, seeders 5 e 11 → 11; seeders uguali, priorità 25 e 20 → 20.
  - `WouldImportFollowsTheProfileOrder`: con il profilo Main di Radarr (ordine in Note tecniche): WEBRip-1080p 150 su Bluray-1080p 0 → falso; Bluray 0 su WEBRip 150 → vero; con WEB 1080p e Bluray-1080p in un gruppo solo: WEBRip 150 su Bluray 0 → vero, WEBRip 150 su Bluray 150 → falso; 720p 150 su 1080p 50 → falso; nessun file → vero.
- [ ] **Step 2: i test falliscono** (`DownloadRuleTests`).
- [ ] **Step 3: il codice** con le firme sopra.
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): regola di scelta dei download dell'admin"`

### Task 3: quando ricercare, pack o episodi

**Files:**
- Create: `Downloads/DownloadSchedule.cs`, `Downloads/SeasonPackRule.cs`, `Downloads/DownloadKey.cs`
- Test: `Tests/DownloadScheduleTests.cs`, `Tests/SeasonPackRuleTests.cs`, `Tests/DownloadKeyTests.cs`

**Interfaces:**
- Consumes: `DownloadRule`, `RuleInput`, `RuleResult` (Task 2).
- Produces:
  - `public static class DownloadSchedule`: `DateTimeOffset Next(DateTimeOffset since, DateTimeOffset now)` (età `now − since` < 7 giorni → `now + 6 h`; < 30 giorni → `now + 24 h`; altrimenti `now + 7 giorni`); costanti `NeedsYouAfter`, `UpgradeWindow`, `StalledAfter` (Global Constraints).
  - `public static class SeasonPackRule`: `ArrRelease? ChoosePack(IEnumerable<ArrRelease?> releases, IReadOnlyCollection<int> missingEpisodes, RuleInput perEpisode)`; `const double MaxPackRatio = 1.2`. Il pack (`FullSeason` vero) si sceglie con `DownloadRule.Choose` su `perEpisode` con la durata moltiplicata per il numero di episodi mancanti. I singoli (`FullSeason` falso, un solo numero in `EpisodeNumbers`) si scelgono per episodio con `perEpisode`. Decisione 6: si prende il pack se c'è una scelta di pack e (manca un episodio tra i singoli, o pack ≤ 1,2 × somma dei singoli scelti). Null vuol dire: dividere la stagione in episodi.
  - `public readonly record struct DownloadKey(string Kind, int Id, int Season)`: `static bool TryParse(string? raw, out DownloadKey key)`, `override string ToString()` (`movie:12`, `episode:34`, `season:5:2`); `Kind` uno tra `"Movie"`, `"Episode"`, `"Season"`.

- [ ] **Step 1: test che falliscono:**
  - `DownloadScheduleTests`: `EverySixHoursInTheFirstWeek` (età 2 giorni → +6 h), `DailyUntilThirtyDays` (età 10 giorni → +24 h), `WeeklyAfter` (età 40 giorni → +7 giorni), `TheBoundariesGoToTheSlowerPace` (età esatta 7 giorni → +24 h; 30 giorni → +7 giorni).
  - `SeasonPackRuleTests`: 10 episodi da 45 minuti mancanti; `ALightPackWins` (pack 11 GB, singoli 1 GB l'uno → pack, 11 ≤ 12); `AHeavyPackLoses` (pack 14 GB, singoli 1 GB → null); `AMissingSingleTakesThePack` (9 singoli su 10 → pack anche se pesante); `NothingValidSplits` (nessun pack valido → null).
  - `DownloadKeyTests`: `RoundTrips` per i tre tipi; `RejectsGarbage` (`""`, `"movie:"`, `"movie:-1"`, `"film:3"`, `"season:5"`, null → falso).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice** con le firme sopra.
- [ ] **Step 4: i test passano** (gruppi, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): ritmo delle ricerche e scelta tra pack e episodi"`

### Task 4: le impostazioni

**Files:**
- Create: `Downloads/IDownloadSettings.cs`, `Server/PluginDownloadSettings.cs`
- Modify: `Configuration/PluginConfiguration.cs`
- Create (test): `Tests/FakeDownloadSettings.cs`
- Test: `Tests/PluginDownloadSettingsTests.cs`

**Interfaces:**
- Produces:
  - `DownloadProfileRule` (in `Configuration/`, classe XML-serializzabile con `Service`, `ProfileId`, `MinScore`, `TargetScore`) e i tre campi di Global Constraints in `PluginConfiguration`.
  - `public sealed record ProfileThresholds(int MinScore, int? TargetScore)`.
  - `public interface IDownloadSettings { bool Enabled { get; } double MinGbPerHour { get; } ProfileThresholds For(ArrKind kind, int profileId, string? profileName); }`.
  - `PluginDownloadSettings`: legge ogni volta `Plugin.Instance?.Configuration`, come `PluginArrSettings`. `MinGbPerHour` fuori da 0,1–20 (o NaN) → 0,8. `For`: la riga di configurazione con lo stesso servizio e id; altrimenti decisione 8.
  - `FakeDownloadSettings`: proprietà impostabili, `For` con un dizionario e la decisione 8 come ripiego.

- [ ] **Step 1: test che falliscono** in `Tests/PluginDownloadSettingsTests.cs` (sulle funzioni `internal static` che `PluginDownloadSettings` usa, come `PluginArrSettings.ClampDays`): `AnimeProfilesHaveNoTarget` (`"[Anime] 1080p"` → 1, null; `"Anime Main Profile"` → 1, null), `OtherProfilesAimAtOneFifty` (`"Main Profile"` → 50, 150), `AConfiguredRuleWins`, `AWrongWeightFallsBack` (0, −1, NaN, 50 → 0,8).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): impostazioni dei download automatici"`

### Task 5: lo stato e `downloads.json`

**Files:**
- Create: `Downloads/DownloadBook.cs`, `Downloads/DownloadStore.cs`
- Test: `Tests/DownloadBookTests.cs`, `Tests/DownloadStoreTests.cs`

**Interfaces:**
- Consumes: `DownloadKey` (Task 3).
- Produces:
  - `public sealed class DownloadEntry` (classe con `{ get; set; }`, serializzata così com'è): `string Key`, `string Kind`, `string Title`, `string? PosterUrl`, `string State`, `string? Reason`, `DateTimeOffset AvailableSince`, `DateTimeOffset? LastSearchAt`, `DateTimeOffset? NextSearchAt`, `DateTimeOffset? UpgradeUntil`, `int? QueueId`, `long? LastSizeLeft`, `DateTimeOffset? LastProgressAt`, `int? CurrentScore`, `int? CurrentQualityId`, `bool ManualImportPending`, `int ProfileId`, `int RuntimeMinutes`.
  - `public sealed class DownloadChoice`: i campi di `DownloadChoiceDto` (release come campi piatti: `Guid`, `IndexerId`, `Indexer`, `ReleaseTitle`, `Quality`, `QualityId`, `Resolution`, `SizeBytes`, `Score`, `Seeders`) più `Key`, `Kind`, `Title`, `PosterUrl`, `At`, `PreviousSizeBytes`, `PreviousScore`, `ByAdmin`.
  - `public sealed class ReviewItem`: i campi di `ReviewItemDto`.
  - `public sealed class DownloadFile { int Version = 1; List<DownloadEntry> Entries; List<DownloadChoice> Choices; List<ReviewItem> Review; DateTimeOffset? ReviewAt; List<string> Accepted }`.
  - `public sealed class DownloadBook`: `DownloadEntry? Get(string key)`, `void Put(DownloadEntry entry)`, `bool Remove(string key)`, `IReadOnlyList<DownloadEntry> Entries`, `void AddChoice(DownloadChoice choice)`, `IReadOnlyList<DownloadChoice> Choices` (dalla più recente), `int Prune(DateTimeOffset now)` (toglie le scelte più vecchie di 90 giorni), `void SetReview(IReadOnlyList<ReviewItem> items, DateTimeOffset at)`, `bool Accept(string key)` (aggiunge ad `Accepted` e toglie dalla review), `bool IsAccepted(string key)`, `static DownloadBook FromFile(DownloadFile file)`, `DownloadFile ToFile()`. Non è sicuro tra thread: lo usa solo `DownloadService`, sotto lock.
  - `public sealed class DownloadStore(string filePath, ILogger<DownloadStore> logger)`: `const string FileName = "downloads.json"`, `static string DefaultPath(IApplicationPaths paths)` (cartella di `FriendStore.FolderName`, come `ReportStore`), `DownloadBook Load()`, `void Save(DownloadBook book)` (file temporaneo e rinomina, come `ReportStore`).

- [ ] **Step 1: test che falliscono:**
  - `DownloadBookTests`: `ChoicesOlderThanNinetyDaysArePruned`, `ChoicesComeNewestFirst`, `AcceptingRemovesFromReview`, `ARoundTripKeepsEverything` (`FromFile(ToFile())`).
  - `DownloadStoreTests` (cartella temporanea, come `ReportStore`): `AMissingFileStartsEmpty`, `SaveThenLoad`, `ABrokenFileStartsEmpty` (JSON rotto → vuoto, file spostato in `downloads.json.bad`), `AFutureVersionStartsEmpty` (`Version` 2 → vuoto e `.bad`).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, copiando caricamento, `.bad` e salvataggio da `ReportStore`.
- [ ] **Step 4: i test passano** (gruppi, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): stato dei download in downloads.json"`

### Task 6: il ciclo, prima parte (cosa seguire, la coda)

**Files:**
- Create: `Downloads/DownloadService.cs`
- Test: `Tests/DownloadServiceCycleTests.cs`

**Interfaces:**
- Consumes: Task 1–5; `IArrSettings`, `TimeProvider`, `ILogger<DownloadService>`.
- Produces:
  - `public sealed class DownloadService(IArrClient arr, IArrSettings arrSettings, IDownloadSettings settings, DownloadStore store, TimeProvider time, ILogger<DownloadService> logger)`:
    - `void Load()` (all'avvio);
    - `Task<CycleReport> RunCycleAsync(CancellationToken ct)`; con `settings.Enabled` falso non fa niente e restituisce `CycleReport.Skipped`;
    - `public sealed record CycleReport(int Searched, int Grabbed, string? SonarrError, string? RadarrError) { public static readonly CycleReport Skipped; }`.
    - `internal TimeSpan Pause { get; init; } = PauseBetweenSearches` (i test la mettono a zero);
    - `public event Action? Nudged` e `public void Nudge()`, che lo lancia: chiede un giro presto (lo ascolta il servizio in background, Task 11; lo chiamano `SearchNow` e `RequestsService`).
  - Questa parte del giro (la ricerca è nel Task 7):
    1. **Film:** da `GetLibraryMoviesAsync`, quelli `Monitored`, senza file e `IsAvailable` hanno una voce (`movie:{id}`, `State` `Waiting`, `AvailableSince` = la prima volta che li si vede, `NextSearchAt` = adesso). Titolo `"{Title} ({Year})"`, poster = immagine `poster` (`RemoteUrl`).
    2. **Episodi:** da `GetMissingEpisodesAsync`, quelli `Monitored` con `AirDateUtc` passata hanno una voce `episode:{id}` (`AvailableSince` = `AirDateUtc`). Titolo `"{serie} · S{ss}E{ee}"`. Le stagioni nel Task 8.
    3. **Coda:** da `GetQueueAsync` di entrambi. Una voce con un elemento in coda (per `MovieId` o `EpisodeId`) diventa `Downloading` con `QueueId`, anche se non l'ha scaricata WonderFlix; un elemento in coda senza voce ne crea una. `importBlocked` → `NeedsYou`/`ImportBlocked` (o import manuale, Task 10). `sizeleft` cambiato → `LastProgressAt` = adesso; uguale da 24 ore → `RemoveFromQueueAsync(…, blocklist: true)`, voce `Waiting` con `NextSearchAt` adesso.
    4. **Fine download:** una voce `Downloading` che non è più in coda: se Radarr/Sonarr hanno il file → import riuscito (Task 7, upgrade); se no → fallito: `Waiting`, `NextSearchAt` adesso.
    5. **Uscite:** una voce `Waiting` o `NeedsYou` il cui titolo non è più monitorato, non esiste più o ha il file (scaricato da altri) esce.
    6. Un servizio non configurato o in errore: le sue voci restano come sono; l'errore (`UpcomingErrors.Code`) va in `CycleReport` e nella panoramica.
    7. Alla fine `store.Save` e `book.Prune`.

- [ ] **Step 1: test che falliscono** in `Tests/DownloadServiceCycleTests.cs` (`FakeArrClient`, `FakeArrSettings`, `FakeDownloadSettings` con `Enabled` vero, `FakeTimeProvider`, `DownloadStore` in una cartella temporanea):
  - `ADisabledServiceDoesNothing`: `Enabled` falso → nessuna chiamata a Radarr/Sonarr, `Skipped`.
  - `AMissingAvailableMovieGetsAnEntry`; `AMovieNotYetAvailableHasNone` (`IsAvailable` falso); `AnUnmonitoredMovieHasNone`.
  - `AnAiredMissingEpisodeGetsAnEntry`; `AFutureEpisodeHasNone`.
  - `AQueuedTitleIsDownloading`, anche se la voce non c'era.
  - `ASlowDownloadIsNotStalled`: `sizeleft` che scende un poco ogni giro per 3 giorni → mai rimosso.
  - `AStuckDownloadIsRemovedAfterADay`: `sizeleft` uguale per 24 h → una `RemoveFromQueueAsync(Radarr, id, blocklist: true)`, voce `Waiting`.
  - `AFailedDownloadGoesBackToWaiting`: la voce `Downloading` sparisce dalla coda senza file → `Waiting`.
  - `ImportBlockedNeedsYou`: `trackedDownloadState` `importBlocked` → `NeedsYou`, `ImportBlocked`.
  - `ATitleDownloadedElsewhereLeaves`: voce `Waiting`, il film ora ha il file → la voce non c'è più.
  - `OneServiceDownKeepsTheOther`: Sonarr lancia `ArrException(Unreachable)` → le voci dei film si aggiornano, `SonarrError` `"Unreachable"`, le voci degli episodi restano.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.** Un `Lock` intorno al `DownloadBook`; mai il lock durante una chiamata a Radarr/Sonarr (si legge, si rilascia, si chiama, si riprende).
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): download automatici, titoli da seguire e coda"`

### Task 7: il ciclo, seconda parte (ricerca, download, upgrade)

**Files:**
- Modify: `Downloads/DownloadService.cs`
- Test: `Tests/DownloadServiceSearchTests.cs`

**Interfaces:**
- Consumes: Task 2, 3, 6.
- Produces (dentro `RunCycleAsync`, dopo la parte del Task 6):
  1. Le voci da cercare: `Waiting`, `NeedsYou` (non `ImportBlocked`) e `UpgradeWatch` con `NextSearchAt` ≤ adesso; prima la `NextSearchAt` più vecchia; al massimo `MaxSearchesPerCycle`; `Pause` tra due ricerche. Prima di ogni ricerca si rilegge `settings.Enabled`: spento a metà giro, il giro si ferma dopo il titolo in corso (spec §11).
  2. Per ogni voce: profili (`GetQualityProfilesAsync`) e priorità degli indexer (`GetIndexersAsync`) letti una volta per giro e servizio; `RuleInput` con durata, `settings.MinGbPerHour`, `settings.For(...).MinScore`; ricerca (`movieId=` / `episodeId=`); `DownloadRule.Choose`.
  3. **Scelta e nessun file:** `GrabReleaseAsync`, voce `Downloading`, `CurrentScore`/`CurrentQualityId` = la scelta, una `DownloadChoice` (`ByAdmin` falso).
  4. **`UpgradeWatch`:** si scarica solo se la scelta ha punteggio > `CurrentScore` **e** `WouldImport` è vero; la `DownloadChoice` ha `PreviousScore` e `PreviousSizeBytes`.
  5. **Niente scelta:** `NextSearchAt = DownloadSchedule.Next(AvailableSince, now)` (in `UpgradeWatch` dalla data della scelta); `BelowMinScore` → `NeedsYou`/`BelowMinScore`; nessun candidato da almeno `NeedsYouAfter` → `NeedsYou`/`NothingFound`; ricerca in errore → `Reason` `SearchFailed`, la voce resta e si riprova al giro dopo.
  6. **Import riuscito** (Task 6, punto 4): con obiettivo del profilo nullo o `CurrentScore` < obiettivo → `UpgradeWatch` con `UpgradeUntil` = scelta + 30 giorni; altrimenti la voce esce. Dopo `UpgradeUntil` la voce esce (la riprende "Da ripassare").

- [ ] **Step 1: test che falliscono** in `Tests/DownloadServiceSearchTests.cs`:
  - `TheRuleChoiceIsGrabbed`: film Animals con le tre release del Task 2 → una `GrabReleaseAsync(Radarr, guid del WEBRip, indexerId)`, voce `Downloading`, una scelta.
  - `ACycleSearchesAtMostTenTitles`: 25 film mancanti → 10 ricerche; il giro dopo altre 10.
  - `ATitleInTheQueueIsNotSearched`.
  - `NothingValidWaitsSixHours`: nessun candidato → nessun download, `NextSearchAt` = +6 h.
  - `AfterAWeekNothingNeedsYou`: `AvailableSince` di 8 giorni fa, nessun candidato → `NeedsYou`/`NothingFound`, e la voce si ricerca ancora al suo turno.
  - `BelowMinScoreNeedsYouAtOnce`.
  - `AnImportBelowTargetWatchesForUpgrades`: scelta 50 importata → `UpgradeWatch`, `UpgradeUntil` +30 giorni.
  - `AnImportAtTargetLeaves`: scelta 150 importata, obiettivo 150 → la voce esce.
  - `AnUpgradeNeedsAHigherScoreAndAnImport`: `UpgradeWatch` con 50 e WEBRip-1080p; una release 150 WEBRip → scaricata con `PreviousScore` 50; una release 50 più leggera → no; una release 150 di qualità più bassa nel profilo → no.
  - `TheUpgradeWindowCloses`: dopo 30 giorni la voce esce.
  - `TurningOffMidCycleStops`: `Enabled` diventa falso durante la prima ricerca → una ricerca sola, nessun'altra.
  - `ASearchErrorKeepsTheEntry`: la ricerca lancia → `Reason` `SearchFailed`, nessun download.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): download automatici, ricerca, scelta e upgrade"`

### Task 8: le stagioni intere

**Files:**
- Modify: `Downloads/DownloadService.cs`
- Test: `Tests/DownloadServiceSeasonTests.cs`

**Interfaces:**
- Consumes: `SeasonPackRule` (Task 3), `IArrClient.GetSeriesEpisodesAsync` (c'è già).
- Produces:
  - Nel Task 6, punto 2: per ogni serie con episodi mancanti si leggono i suoi episodi una volta per giro. Una stagione > 0 in cui tutti gli episodi hanno `AirDateUtc` passata (nessuno senza data o futuro) e tutti quelli monitorati mancano diventa **una** voce `season:{serie}:{n}` (titolo `"{serie} · Stagione {n}"`, `AvailableSince` = la messa in onda dell'ultimo episodio) al posto delle voci dei singoli episodi.
  - Ricerca `seriesId={serie}&seasonNumber={n}` e `SeasonPackRule.ChoosePack`: pack → download come nel Task 7; null → la voce di stagione esce e ogni episodio mancante ha la sua voce con `NextSearchAt` adesso; il giro dopo non la ricrea (si segna nella voce di episodio `FromSplit`, campo `bool` in più di `DownloadEntry`, e una stagione con un episodio `FromSplit` non si riunisce).
  - Coda: un elemento con `SeasonNumber` e senza un solo `EpisodeId` (pack) segna `Downloading` la voce di stagione.

- [ ] **Step 1: test che falliscono** in `Tests/DownloadServiceSeasonTests.cs`: `AFinishedMissingSeasonIsOneEntry`; `ASeasonStillAiringStaysEpisodes`; `APartlyDownloadedSeasonStaysEpisodes`; `ALightPackIsGrabbed`; `AHeavyPackSplitsIntoEpisodes` (e il giro dopo restano episodi).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): download automatici delle stagioni intere"`

### Task 9: le azioni admin

**Files:**
- Modify: `Downloads/DownloadService.cs`
- Create: `Protocol/DownloadsDtos.cs`
- Test: `Tests/DownloadServiceAdminTests.cs`

**Interfaces:**
- Consumes: Task 2–8.
- Produces (tutti i DTO di Global Constraints in `Protocol/DownloadsDtos.cs`, più `GrabRequest(Key, Guid, IndexerId)`, `KeyRequest(Key)`, `DownloadsErrorDto(Reason)`):
  - `Task<DownloadSearchDto?> SearchAsync(string key, CancellationToken ct)`: null per una chiave non valida. Anche per titoli senza voce (da "Da ripassare"): titolo, durata e profilo si leggono da Radarr (`GetLibraryMoviesAsync`, filtrato) o Sonarr (`GetSeriesAsync`, `GetSeriesEpisodesAsync`). `Current` dal file (`GetMovieFilesAsync` / `GetEpisodeFilesAsync`; per una stagione il file con il punteggio più basso). `WouldImport` di ogni candidato rispetto a `Current`. `IsChoice` sulla scelta della regola. I risultati restano in memoria per chiave (`LastSearch`, con l'ora). Errore di Radarr/Sonarr → `Error` con il codice e liste vuote.
  - `Task<GrabOutcome> GrabAsync(string key, string guid, int indexerId, CancellationToken ct)`; `public enum GrabOutcome { Ok, Invalid, Expired }`:
    - release cercata in `LastSearch` della chiave; se manca, o se `GrabReleaseAsync` lancia `ArrException` con risposta 404/400, si rifà la ricerca e si riprova una volta con la stessa `guid`; se non c'è più → `Expired`;
    - **"cambia"**: se la voce è `Downloading` con `QueueId`, prima `RemoveFromQueueAsync(…, blocklist: false)`;
    - `WouldImport` falso rispetto al file → `ManualImportPending` vero (Task 10);
    - voce `Downloading`, una `DownloadChoice` con `ByAdmin` vero e, se c'era un file, `PreviousScore`/`PreviousSizeBytes`; la voce esce da "Da ripassare".
  - `bool Accept(string key)`: "va bene così" (`DownloadBook.Accept`); falso per una chiave non valida.
  - `bool SearchNow(string key)`: `NextSearchAt` = adesso e nudge; falso se la chiave non ha una voce.
  - `DownloadsOverviewDto Overview()`: `Recent` dalle scelte, `Waiting` dalle voci (`Waiting`, `NeedsYou`, `Downloading`, `UpgradeWatch`), `Review` senza le chiavi accettate, gli errori dell'ultimo giro.
  - `Task<IReadOnlyList<DownloadProfileDto>> ProfilesAsync(CancellationToken ct)`: i profili dei due servizi con le soglie di `settings.For`; un servizio in errore non c'è.
  - Lo stato HTTP di un errore è `ArrException.Status` (Task 1).

- [ ] **Step 1: test che falliscono** in `Tests/DownloadServiceAdminTests.cs`: `SearchMarksTheChoiceAndRejected` (Animals: il WEBRip `IsChoice`, una release `TooSmall` tra gli scarti); `SearchShowsTheCurrentFile`; `AnInvalidKeyIsNull`; `GrabUsesTheLastSearch`; `AnExpiredReleaseIsSearchedAgain` (la prima `GrabReleaseAsync` lancia con stato 404 → nuova ricerca e secondo tentativo; se la `guid` non c'è più → `Expired`); `ChangingADownloadRemovesTheOldOne` (voce `Downloading` con `QueueId` 77 → `RemoveFromQueueAsync(…, 77, blocklist: false)` prima del download); `AGrabThatWouldNotImportIsFlagged`; `AcceptHidesFromReview`; `ProfilesHaveTheirThresholds`.
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppo, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): ricerca con la regola e download scelti dall'admin"`

### Task 10: "Da ripassare" e import manuale

**Files:**
- Modify: `Downloads/DownloadService.cs`, `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs`, `Tests/FakeArrClient.cs`
- Test: `Tests/DownloadServiceReviewTests.cs`, `Tests/ArrClientTests.cs`

**Interfaces:**
- Consumes: Task 1, 5, 6.
- Produces:
  - `Task BuildReviewAsync(CancellationToken ct)` (§6): film con `MovieFile.Id` > 0 → `GetMovieFilesAsync`; serie con `Statistics.EpisodeFileCount` > 0 → `GetEpisodeFilesAsync`, raggruppati per stagione > 0 (punteggio = il più basso, peso = la somma). Entra chi ha obiettivo non nullo e punteggio sotto; più le voci uscite da `UpgradeWatch` senza obiettivo raggiunto (Task 7). Senza le chiavi accettate. Ordine: punteggio crescente, poi peso decrescente. `DownloadBook.SetReview(items, now)`. Con un servizio in errore si tengono le righe vecchie di quel servizio.
  - Import manuale (decisione 9), nel Task 6 punto 3: un elemento `importBlocked` di una voce con `ManualImportPending` → `ManualImportAsync`; se lancia o la coda resta `importBlocked` al giro dopo → `NeedsYou`/`ImportBlocked` e `ManualImportPending` falso.
  - `IArrClient`: `Task<IReadOnlyList<ArrManualImportItem?>> GetManualImportAsync(ArrKind kind, string downloadId, CancellationToken ct)` → `manualimport?downloadId=&filterExistingFiles=false`; `Task ManualImportAsync(ArrKind kind, IReadOnlyList<ArrManualImportItem> items, CancellationToken ct)` → `POST command` con `{"name":"ManualImport","importMode":"auto","files":[…]}`, dove ogni file ha `path`, `movieId` o `seriesId`+`episodeIds`, `quality`, `languages`, `releaseGroup`, `downloadId`, copiati dalla risposta della GET. `ArrManualImportItem` tiene i campi della GET come `JsonElement` per poterli rimandare uguali.

- [ ] **Step 1: verifica sul server** (sola lettura): `GET manualimport?downloadId=<un download importato di recente>&filterExistingFiles=false` su Radarr; scrivi nel registro i campi della risposta. Se mancano `path`, `quality` o `languages`, ferma il task e segnalalo: in quel caso l'import manuale non si fa e `ManualImportPending` porta subito a `ImportBlocked`.
- [ ] **Step 2: test che falliscono:** in `DownloadServiceReviewTests`: `FilesBelowTargetAreListed` (Amistad 0 e 12,4 GB, Firebreak 50, In the Grey 150 → i primi due, Amistad prima); `AnimeWithoutTargetIsNotListed`; `ASeasonUsesItsWorstEpisode`; `AcceptedTitlesStayOut`; `ABlockedImportIsImportedByHand` (`ManualImportPending` + `importBlocked` → una `ManualImportAsync` con i file della GET); `AFailedManualImportNeedsYou`. In `ArrClientTests`: `ManualImportPostsTheCommand`.
- [ ] **Step 3: i test falliscono.**
- [ ] **Step 4: il codice.**
- [ ] **Step 5: i test passano** (gruppi, poi la suite intera).
- [ ] **Step 6: commit** `git commit -m "feat(plugin): elenco da ripassare e import manuale"`

### Task 11: servizio in background, endpoint, `Info`, nudge

**Files:**
- Create: `DownloadsHostedService.cs`, `Api/DownloadsController.cs`
- Modify: `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs`, `Hub/RequestsService.cs`
- Test: `Tests/DownloadsHostedServiceTests.cs`, `Tests/DownloadsControllerTests.cs`, `Tests/InfoControllerTests.cs`, `Tests/ServiceRegistrationTests.cs`, `Tests/RequestsServiceTests.cs`

**Interfaces:**
- Consumes: `DownloadService` (Task 6–10).
- Produces:
  - `DownloadsHostedService(DownloadService downloads, TimeProvider time, ILogger<DownloadsHostedService> logger)`: all'avvio `Load()`; un timer ogni `CycleInterval` per `RunCycleAsync`, uno ogni `ReviewInterval` per `BuildReviewAsync` (il primo dopo 5 minuti dall'avvio). Un giro alla volta: se il precedente non è finito, quello nuovo salta. Su `DownloadService.Nudged` fa partire un giro dopo `NudgeDelay` (più nudge vicini fanno un giro solo). Eccezioni nel log come `Warning`, mai fuori.
  - `DownloadsController` con gli endpoint di Global Constraints. `Search`: 400 se `SearchAsync` dà null. `Grab`: `Ok` → 204, `Invalid` → 400, `Expired` → 409 `{"Reason":"Expired"}`. `Accept`: 204 o 400. `SearchNow`: 202 o 400.
  - `WatchPartyProtocol.DownloadsFeature = "downloads"`, dopo `calendar` nelle stesse condizioni.
  - `RequestsService`: dopo un'approvazione riuscita chiama `downloads.Nudge()` (dipendenza nuova `DownloadService`, da aggiungere nei costruttori dei test, come nel piano 25a).

- [ ] **Step 1: test che falliscono:** `DownloadsHostedServiceTests` (`OneCycleAtATime`, `ANudgeRunsACycleAfterAMinute`, `AFailingCycleIsLogged`); `DownloadsControllerTests` (`ExpiredIsConflict`, `ABadKeyIsBadRequest`, `TheOverviewReportsAServiceError`, `TheClassRequiresElevation` via reflection sull'attributo); `InfoControllerTests` (versione `"1.14.0"`, `"downloads"` dopo `"calendar"`); `ServiceRegistrationTests` (9 servizi in background); `RequestsServiceTests` (`ApprovingNudgesTheDownloads`).
- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (gruppi, poi la suite intera).
- [ ] **Step 5: commit** `git commit -m "feat(plugin): endpoint e servizio dei download automatici"`

### Task 12: pagina di configurazione, README, versione, prova sul server

**Files:**
- Modify: `Configuration/configPage.html`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs` (se tiene la versione), `../meta.template.json`, `../README.md`

- [ ] **Step 1: pagina di configurazione.** Sotto "Sonarr and Radarr", una sezione "Automatic downloads": interruttore `DownloadsEnabled`, numero `DownloadsMinGbPerHour` (min 0.1, max 20, step 0.1), e una tabella dei profili caricata da `GET /WonderFlixWatchParty/Downloads/Profiles` (`ApiClient.getJSON`) con due numeri per riga (minimo e obiettivo, vuoto = nessuno). Al salvataggio `DownloadProfileRules` con una riga per profilo. Testi in inglese come il resto della pagina.
- [ ] **Step 2: README.** Una sezione "Download automatici" con le istruzioni di spec §9 (Prowlarr "Standard" senza RSS, "Redownload Failed" spenti, profili uniti per risoluzione, Seerr "Radarr Anime" con prevent search, interruttore), nell'ordine.
- [ ] **Step 3: versione** 1.14.0 nel csproj e dove c'è 1.13.0 (`meta.template.json`, `Info`); la suite intera è verde.
- [ ] **Step 4: pacchetto** con `& "C:\Program Files\Git\bin\bash.exe" plugin/pack.sh 1.14.0`. La build di prova sul server la fa il controller della sessione con l'utente, non l'implementatore: segnala nel registro lo zip pronto.
- [ ] **Step 5: commit** `git commit -m "feat(plugin): configurazione dei download automatici, README e versione 1.14.0"`

### Task 13: allineare la spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md`

- [ ] **Step 1:** nella spec, le decisioni del piano 1–9 dove cambiano o precisano il testo (§5.3a download falliti senza cronologia, §5.4 pack e singoli dalla stessa ricerca, §7.2 senza `history`), e lo **Stato** "piano 29a realizzato".
- [ ] **Step 2: commit** `git commit -m "docs: spec T allineata al piano 29a"`
