# Ricerche via Prowlarr — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** le ricerche del plugin (ciclo automatico, ricerca a mano, Alleggerisci) passano da Prowlarr + `GET /parse` + `POST /release/push` invece di `GET /release` di Sonarr/Radarr, così Sonarr non si riempie la cache e non va in OutOfMemory.

**Architecture:** un `IProwlarrClient` nuovo e un `IReleaseFinder` che, data una `DownloadKey`, costruisce le query, cerca su Prowlarr, attribuisce ogni release con `/parse` e restituisce gli stessi `ArrRelease` di oggi (più link e sorgente). `DownloadService` chiama il finder al posto di `arr.SearchReleasesAsync`/`arr.GrabReleaseAsync`. Il grab è un push; per i download intenzionali che il push rifiuta per file/coda/monitoraggio il plugin aggiunge il torrent a qBittorrent e lo importa per cartella quando finisce. La strada vecchia resta per "Cerca con Sonarr/Radarr" e quando Prowlarr non è configurato.

**Tech Stack:** C# net9.0 (Jellyfin 10.11.0, test xUnit contro 10.11.9), Flutter 3.47.5 + Riverpod 3.

**Spec:** `docs/superpowers/specs/2026-11-11-ricerche-prowlarr-design.md`

## Global Constraints

- Prowlarr non configurato (`ProwlarrUrl` o `ProwlarrApiKey` vuoti) → comportamento identico a oggi, test esistenti verdi senza modifiche di comportamento.
- Query per titolo, mai per ID (`tvdbid`/`imdbid`/`tmdbid` non si mandano a Prowlarr).
- Indexer: solo quelli del servizio con `/prowlarr/<id>/` nel `baseUrl` e `enableInteractiveSearch` true.
- Al massimo 8 query Prowlarr per ricerca; parse con parallelismo massimo 4.
- Push: al massimo 3 tentativi per ricerca; un rifiuto di regola non è `GrabRefused`, non porta in NeedsYou, non entra in `RefusedReleases`.
- Nessuna chiave API né query nei log (come `ArrClient`, riga 11).
- Il ciclo automatico non usa mai la strada vecchia quando Prowlarr è configurato.
- Codici `Reason` nuovi esatti: `WrongTitle`, `NotWanted`, `Restricted`, `Blocklisted`. Valore `Engine` esatto: `"Prowlarr"` o `"Arr"`.
- Plugin 1.29.0 (aggiornare `InfoControllerTests`); app 0.40.0 con riga nuova in `docs/RELEASING.md`.
- Commenti e messaggi di log in italiano, codice in inglese. Nessun `Co-Authored-By`, nessun "closes/fixes/resolves" nei commit.
- Build/test plugin da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`. App da `app/`: `flutter gen-l10n`, `flutter analyze`, `flutter test`. Release exe: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Non uccidere processi per nome immagine (`taskkill /IM`, `pkill`).

## Review Focus

1. Un torrent messo da noi in qBittorrent appare in Sonarr come voce "senza titolo" (verificato sul seedbox: `seriesId`/`episodeId` null): non deve comparire nella lista "Download senza titolo" con "Rimuovi", né essere tolto. Test nel Task 7.
2. Un `magnetUrl` senza `downloadUrl` (Nyaa) deve funzionare sia nel push sia nell'aggiunta diretta a qBittorrent. Test nei Task 4 e 7.
3. Prowlarr giù o che risponde 429/timeout a una query: la ricerca continua con le altre query; se falliscono tutte, `SearchFailed` come oggi (non "niente trovato"). Test nel Task 5.
4. Un push che Sonarr approva ma il client rifiuta (torrent già presente, HTTP 500): è un rifiuto del client (`GrabRefused` come oggi), non un rifiuto di regola. Test nel Task 8.
5. `/parse` che attribuisce la release a un'altra stagione della stessa serie: `WrongTitle`, non candidata. Test nel Task 4.

---

### Task 1: Client Prowlarr e impostazioni

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Home/IProwlarrClient.cs`, `Home/ProwlarrClient.cs`, `Home/ProwlarrJson.cs`
- Modify: `Configuration/PluginConfiguration.cs` (accanto a `SonarrUrl`, riga ~73), `Home/IArrSettings.cs`, `Server/PluginArrSettings.cs`, `PluginServiceRegistrator.cs` (~80-87), `Configuration/configPage.html` (campi Arr ~93-105, JS ~658-701)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ProwlarrClientTests.cs`, `FakeArrSettings.cs`

**Interfaces:**
- Produces:
  - `PluginConfiguration.ProwlarrUrl`, `ProwlarrApiKey` (string, default `""`).
  - `IArrSettings.Prowlarr` → `ArrEndpoint` (stesso tipo di Sonarr/Radarr, con `IsConfigured`).
  - `IProwlarrClient.SearchAsync(ProwlarrQuery query, CancellationToken ct) : Task<IReadOnlyList<ProwlarrRelease>>`
  - `record ProwlarrQuery(string Type, string Query, int? Season, int? Episode, IReadOnlyList<int> IndexerIds, IReadOnlyList<int> Categories)` — `Type` è `"search"`, `"tvsearch"` o `"movie"`.
  - `class ProwlarrRelease { string? Guid; int IndexerId; string? Indexer; string? Title; long Size; int? Seeders; string? DownloadUrl; string? MagnetUrl; string? Protocol; DateTimeOffset? PublishDate; string? InfoUrl }`
  - `ProwlarrClient.QueryTimeout = TimeSpan.FromMinutes(2)`; errori come `ArrException` (riusa la classificazione di `ArrClient`).

- [ ] **Step 1: test** `ProwlarrClientTests.SearchSendsTitleIndexersAndCategories`: con `FakeSeerrHttp`, `SearchAsync(new("tvsearch","Slime",2,null,[8,11],[5070,5000]))` chiama `GET {url}/api/v1/search?type=tvsearch&query=Slime&season=2&indexerIds=8&indexerIds=11&categories=5070&categories=5000` con header `X-Api-Key`; nessun `ep=`. `SearchParsesReleases`: il JSON `[{"guid":"g","indexerId":8,"indexer":"Nyaa.si","title":"T","size":123,"seeders":4,"magnetUrl":"magnet:?x","protocol":"torrent","publishDate":"2026-11-01T00:00:00Z"}]` dà una release con quei valori e `DownloadUrl` null. `NotConfiguredThrows`: endpoint vuoto → `ArrException` con l'errore "non configurato" di `ArrClient`.
- [ ] **Step 2:** `dotnet test … --filter ProwlarrClientTests` → FAIL (tipo mancante).
- [ ] **Step 3:** implementa client, settings, DI (HttpClient `WonderFlixArr`), pagina di configurazione (campi "Prowlarr URL" e "Prowlarr API key" come quelli di Sonarr, salvati con il resto).
- [ ] **Step 4:** test verdi, tutta la suite verde.
- [ ] **Step 5:** commit `feat(plugin): client Prowlarr e impostazioni`.

### Task 2: Arr — parse, push e dati per i controlli

**Files:**
- Modify: `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs`
- Test: `Tests/ArrClientTests.cs`, `Tests/FakeArrClient.cs`

**Interfaces:**
- Produces (in `IArrClient`):
  - `ParseAsync(ArrKind kind, string title, CancellationToken ct) : Task<ArrParse>` — `GET parse?title=`, `DefaultTimeout`.
  - `PushReleaseAsync(ArrKind kind, ArrPushRelease release, CancellationToken ct) : Task<ArrPushResult>` — `POST release/push`, `GrabTimeout`.
  - `GetSeriesByIdAsync(int seriesId, CancellationToken ct) : Task<SonarrSeries>` (`GET series/{id}`).
  - `GetQualityDefinitionsAsync(ArrKind, ct) : Task<IReadOnlyList<ArrQualityDefinition?>>`, `GetReleaseProfilesAsync(ArrKind, ct) : Task<IReadOnlyList<ArrReleaseProfile?>>`, `GetBlocklistAsync(ArrKind, ct) : Task<IReadOnlyList<ArrBlocklistItem?>>` (tutte le pagine).
- Produces (JSON):
  - `ArrParse { ArrParsedInfo? ParsedEpisodeInfo; ArrParsedInfo? ParsedMovieInfo; SonarrSeries? Series; RadarrMovie? Movie; List<SonarrEpisode?>? Episodes; int CustomFormatScore }`, `ArrParsedInfo { ArrQualityModel? Quality; bool FullSeason; int SeasonNumber; List<int>? EpisodeNumbers; List<int>? AbsoluteEpisodeNumbers }`.
  - `ArrPushRelease { string Title; string? DownloadUrl; string? MagnetUrl; string Protocol; DateTimeOffset PublishDate; long Size; int IndexerId; int? Seeders }`.
  - `ArrPushResult { bool Approved; bool TemporarilyRejected; bool Rejected; List<string>? Rejections }` (primo elemento della lista restituita).
  - `SonarrSeries.SeriesType` (string), `SonarrSeries.AlternateTitles : List<SonarrAlternateTitle?>?` con `{ string? Title; int? SeasonNumber; int? SceneSeasonNumber }`.
  - `SonarrEpisode.AbsoluteEpisodeNumber`, `SceneAbsoluteEpisodeNumber`, `SceneSeasonNumber`, `SceneEpisodeNumber` (int?).
  - `RadarrMovie.OriginalTitle`, `OriginalLanguage { string? Name }`, `AlternateTitles : List<RadarrAlternateTitle?>?` con `{ string? Title; ArrLanguage? Language }`.
  - `ArrIndexer.Fields : List<ArrField?>?` (`{ string? Name; JsonElement? Value }`) più helper `ProwlarrId` (int?, da `baseUrl` `/prowlarr/(\d+)/`), `Categories`, `AnimeCategories`, `MinimumSeeders`, `EnableInteractiveSearch`, `Name`.
  - `ArrQualityProfile.MinFormatScore` (int).
  - `ArrQualityDefinition { ArrQuality? Quality; double? MinSize; double? MaxSize }` (MB per minuto, come Sonarr/Radarr).
  - `ArrReleaseProfile { bool Enabled; List<string>? Required; List<string>? Ignored; List<int>? Tags }` (Sonarr v4 e Radarr hanno questa forma; `Required`/`Ignored` possono essere stringhe o liste: accettare entrambe).
  - `ArrBlocklistItem { string? SourceTitle; string? Indexer; int? SeriesId; int? MovieId }`.
- `FakeArrClient`: un `Func<>` + lista di chiamate per ognuno dei nuovi metodi, come `Releases`/`Grab`.

- [ ] **Step 1: test** in `ArrClientTests`: `ParseSendsTitleAndReadsEpisodes` (URI `parse?title=…` codificato, `Series.Id`, `Episodes[0].SeasonNumber`, `ParsedEpisodeInfo.FullSeason`, `CustomFormatScore`); `PushPostsReleaseAndReadsDecision` (body con `title`, `magnetUrl`, `protocol:"torrent"`, `indexerId`; risposta `[{"approved":false,"rejected":true,"rejections":["Not an upgrade"]}]` → `Rejected` true e il motivo); `PushServerErrorThrows500` (`ArrException` con `Status` 500); `IndexerReadsProwlarrIdAndFields` (`baseUrl` `http://h:20790/prowlarr/11/` → `ProwlarrId` 11, `minimumSeeders` 1, `categories` [5000,5070]); `ReleaseProfileAcceptsStringOrList`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** verde, suite verde.
- [ ] **Step 5:** commit `feat(plugin): parse, push, blocklist e release profile di Sonarr/Radarr`.

### Task 3: Le query per Prowlarr

**Files:**
- Create: `Downloads/ReleaseQueries.cs`
- Test: `Tests/ReleaseQueriesTests.cs`

**Interfaces:**
- Consumes: `SonarrSeries`, `SonarrEpisode`, `RadarrMovie` (Task 2), `DownloadKey`.
- Produces: `static class ReleaseQueries` con
  - `ForSeason(SonarrSeries series, int season) : IReadOnlyList<(string Type, string Query, int? Season, int? Episode)>`
  - `ForEpisode(SonarrSeries series, SonarrEpisode episode) : …stesso tipo`
  - `ForMovie(RadarrMovie movie) : …stesso tipo`
  - `const int MaxQueries = 8`.

Regole (dalla spec §3):
- Stagione: prima `("tvsearch", series.Title, season, null)`; poi `("search", alt, null, null)` per ogni titolo alternativo con `SceneSeasonNumber == season`, poi quelli con `SceneSeasonNumber == -1` o `SeasonNumber == -1`.
- Episodio: `("tvsearch", series.Title, episode.SeasonNumber, episode.EpisodeNumber)`; per `SeriesType == "anime"` anche `("search", "<titolo> <abs>")` con `abs` = `AbsoluteEpisodeNumber` a 2 cifre, per il titolo principale e per i titoli alternativi della stagione scene (`SceneSeasonNumber == episode.SceneSeasonNumber`) con `SceneEpisodeNumber` a 2 cifre.
- Film: `("movie", "<Title> <Year>")`, poi `("movie", OriginalTitle)` se diverso, poi i titoli alternativi in italiano e in inglese.
- Deduplica senza maiuscole/minuscole e spazi doppi; tronca a `MaxQueries` mantenendo l'ordine.

- [ ] **Step 1: test** con i dati veri di Slime (serie 265, tipo anime, i 13 titoli alternativi del 2026-11-11): `SeasonUsesTitleThenSeasonAltTitlesThenGeneral` → `[tvsearch "That Time I Got Reincarnated as a Slime" s2, search "Tensei Shitara Slime Datta Ken S2", search "Tensei shitara Slime Datta Ken 2nd Season", search "That Time I Got Reincarnated as a Slime Season 2", search "Tensei Shitara Slime Datta Ken", search "Tensei Shitara Slime Datta Ken That Time I Got Reincarnated as a Slime", search "Vita da Slime", search "Meine Wiedergeburt als Schleim in einer anderen Welt"]` (8, nessun titolo S3/S4); `AnimeEpisodeAddsAbsoluteNumbers` (S2E01, abs 25, scene 2/1 → contiene `"That Time I Got Reincarnated as a Slime 25"` e `"Tensei Shitara Slime Datta Ken S2 01"`); `StandardEpisodeIsOneTvSearch`; `MovieUsesYearOriginalAndItalian` ("Ao Haru Ride"/"A un passo da te"); `DuplicatesAndCapRemoved`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde.
- [ ] **Step 5:** commit `feat(plugin): query per titolo da mandare a Prowlarr`.

### Task 4: Dal risultato di Prowlarr all'`ArrRelease`

**Files:**
- Create: `Downloads/ParsedRelease.cs`
- Modify: `Home/ArrJson.cs` (`ArrRelease`)
- Test: `Tests/ParsedReleaseTests.cs`

**Interfaces:**
- Produces:
  - In `ArrRelease`, `[JsonIgnore]`: `ReleaseSource Source` (enum `Arr` default, `Prowlarr`), `string? DownloadUrl`, `string? MagnetUrl`, `string? Protocol`, `DateTimeOffset? PublishDate`, `string? WrongTitle` (non null = attribuita ad altro; testo breve per il log).
  - `static ArrRelease ParsedRelease.From(ProwlarrRelease found, ArrParse parse, int serviceIndexerId, DownloadKey key)` — `Guid` = `found.Guid`, `IndexerId` = id indexer **del servizio**, `Quality` dal parse, `CustomFormatScore`, `FullSeason`, `SeasonNumber`, `EpisodeNumbers` = numeri degli `parse.Episodes` della stagione della chiave, `MappedEpisodeNumbers` = gli stessi; `Rejections` vuoto.
  - `WrongTitle` non null quando: serie/film del parse assente o con id diverso da quello della chiave; per una stagione o un episodio, nessun episodio del parse nella stagione della chiave; per un episodio, l'episodio della chiave non è tra quelli del parse.

- [ ] **Step 1: test**: `MapsQualityScoreAndSeasonEpisodes`; `MagnetOnlyKeepsMagnet` (Review Focus 2); `OtherSeriesIsWrongTitle`; `NoSeriesIsWrongTitle`; `OtherSeasonIsWrongTitle` (Review Focus 5: chiave `season:265:2`, parse con episodi di S3); `EpisodeNotCoveredIsWrongTitle`; `UsesServiceIndexerId`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde.
- [ ] **Step 5:** commit `feat(plugin): release di Prowlarr attribuite con il parse di Sonarr/Radarr`.

### Task 5: Il finder (ricerca)

**Files:**
- Create: `Downloads/IReleaseFinder.cs`, `Downloads/ReleaseFinder.cs`
- Modify: `PluginServiceRegistrator.cs`
- Test: `Tests/ReleaseFinderTests.cs`, `Tests/FakeProwlarrClient.cs`, `Tests/FakeReleaseFinder.cs`

**Interfaces:**
- Consumes: Task 1-4.
- Produces:
  - `enum SearchEngine { Prowlarr, Arr }`
  - `record FinderResult(IReadOnlyList<ArrRelease?> Releases, IReadOnlyList<ArrRelease> WrongTitle, SearchEngine Engine)`
  - `IReleaseFinder.UsesProwlarr : bool` (Prowlarr configurato).
  - `IReleaseFinder.SearchAsync(DownloadKey key, SearchEngine engine, CancellationToken ct, TimeSpan? arrTimeout = null) : Task<FinderResult>` — `Arr` (o Prowlarr non configurato): `arr.SearchReleasesAsync(service, query, ct, arrTimeout)` come oggi (sposta qui `QueryOf`), `Source = Arr`. `Prowlarr`: legge serie (`GetSeriesByIdAsync`) + episodio (`GetEpisodeAsync`) o film (`GetMovieAsync`), indexer del servizio (Global Constraints), query del Task 3, una alla volta, deduplica per `IndexerId|Guid`, parse con parallelismo 4, `ParsedRelease.From`; le `WrongTitle` vanno in `FinderResult.WrongTitle`, non in `Releases`.
  - Categorie per indexer: `AnimeCategories` per serie anime se presenti, altrimenti `Categories`; una query raggruppa gli indexer con le stesse categorie.
  - Errori: una query che fallisce si salta (log warning senza query); se falliscono tutte, o la lettura di serie/film/indexer fallisce, rilancia l'`ArrException` (il chiamante fa `SearchFailed`).

- [ ] **Step 1: test** con `FakeArrClient` + `FakeProwlarrClient`: `ArrEngineUsesReleaseEndpoint` (stessa query di oggi, nessuna chiamata a Prowlarr); `NotConfiguredFallsBackToArr`; `ProwlarrSearchesOnlyInteractiveProwlarrIndexers` (indexer 2 con interattiva off escluso); `DeduplicatesByIndexerAndGuid`; `WrongTitleSeparated`; `OneFailedQueryIsSkipped` / `AllQueriesFailedThrows` (Review Focus 3); `AnimeUsesAnimeCategories`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde.
- [ ] **Step 5:** commit `feat(plugin): ricerca delle release via Prowlarr`.

### Task 6: Motivi di scarto e riassunto

**Files:**
- Modify: `Downloads/DownloadRule.cs` (`RuleInput` è alla riga 7)
- Create: `Downloads/ReleaseChecks.cs`
- Test: `Tests/DownloadRuleTests.cs`, `Tests/ReleaseChecksTests.cs`

**Interfaces:**
- Produces:
  - `record ChecksContext(ArrQualityProfile? Profile, IReadOnlyList<ArrQualityDefinition> Definitions, IReadOnlyList<ArrReleaseProfile> ReleaseProfiles, IReadOnlyList<ArrBlocklistItem> Blocklist, IReadOnlyDictionary<int, int> MinSeeders, IReadOnlyList<int> TitleTags)` — `MinSeeders` per id indexer del servizio; `TitleTags` i tag della serie/film: un release profile con tag vale solo se condivide almeno un tag, senza tag vale sempre.
  - `static (string Reason, string? Detail)? ReleaseChecks.Check(ArrRelease r, ChecksContext c, int runtimeMinutes)` nell'ordine: `Blocklisted` (stesso `SourceTitle`, senza maiuscole, stesso titolo della chiave), `Restricted` (manca un `Required` o c'è un `Ignored`, confronto senza maiuscole; detail = il termine), `NotWanted` (qualità non `Allowed` nel profilo, o fuori `MinSize`/`MaxSize` × runtime, o seeder < `MinSeeders` dell'indexer, o `CustomFormatScore` < `Profile.MinFormatScore`).
  - `RuleInput` riceve `ChecksContext? Checks` (null = come oggi). `DownloadRule.Choose` applica `ReleaseChecks.Check` solo alle release con `Source == Prowlarr`, prima della regola `TooSmall`, e mette il risultato in `RuleRejected(release, reason, detail)`.
  - `DownloadRule.Summarize`: conta `TooSmall` solo per `Reason == "TooSmall"`; i nuovi motivi non gonfiano più quel conteggio (oggi ogni non-`Arr` è `TooSmall`, riga ~145).
- `SeasonPackRule.ChoosePack` usa lo stesso filtro (riceve lo stesso `RuleInput`).

- [ ] **Step 1: test**: un test per ognuno dei 4 motivi con il dettaglio atteso; `ArrSourceIgnoresChecks`; `SummarizeCountsOnlyTooSmall`; `SeasonPackSkipsRejected`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde, suite verde (nessun test esistente cambia).
- [ ] **Step 5:** commit `feat(plugin): motivi di scarto per le release di Prowlarr`.

### Task 7: Grab — push e aggiunta diretta a qBittorrent

**Files:**
- Modify: `Downloads/IReleaseFinder.cs`, `Downloads/ReleaseFinder.cs`, `Space/IQbitClient.cs`, `Space/QbitClient.cs`, `Downloads/DownloadBook.cs`, `Downloads/DownloadService.cs` (giro), `Downloads/DownloadService.Admin.cs` (`ImportExistingAsync` ~388, `UnknownDownloads` ~1004)
- Test: `Tests/ReleaseFinderTests.cs`, `Tests/QbitClientTests.cs`, `Tests/FakeQbitClient.cs`, `Tests/DownloadServiceDirectGrabTests.cs`

**Interfaces:**
- Produces:
  - `enum GrabKind { Grabbed, Pending, RuleRefused, ClientRefused, Direct }` e `record GrabResult(GrabKind Kind, string? Reason, string? Hash)`.
  - `IReleaseFinder.GrabAsync(ArrKind service, ArrRelease release, bool intentional, CancellationToken ct) : Task<GrabResult>`:
    - `Source == Arr` → `arr.GrabReleaseAsync` come oggi (`Grabbed`; le eccezioni passano).
    - `Prowlarr` → `PushReleaseAsync`. `Approved` → `Grabbed`; `TemporarilyRejected` → `Pending`; `Rejected`: se `intentional` e **tutti** i motivi iniziano con uno di `"Existing file on disk"`, `"Not an upgrade"`, `"Release in queue"`, `"Series is not monitored"`, `"Episode is not monitored"`, `"Movie is not monitored"`, `"Not a Custom Format upgrade"`, `"Existing file meets cutoff"` (case-insensitive) → aggiunge a qBittorrent → `Direct` con l'hash; altrimenti `RuleRefused` con il primo motivo. `ArrException` con `Status >= 500` passa (il chiamante lo tratta come oggi → `ClientRefused` del Review Focus 4).
  - `IQbitClient.AddAsync(string link, string category, CancellationToken ct) : Task<string>` — `POST /api/v2/torrents/add` (`urls`, `category`, `tags=wonderflix`), poi cerca il torrent nuovo; hash dal magnet (`xt=urn:btih:`) quando c'è, altrimenti il torrent nuovo della categoria apparso entro 60 s; `QbitException` se non appare. Categoria: dal download client qBittorrent del servizio (`tvCategory`/`movieCategory`; aggiungi `IArrClient.GetDownloadClientsAsync` se serve, con il suo test).
  - `DownloadBook.DirectGrabs : Dictionary<string,string>` (hash minuscolo → chiave del titolo), salvato in `downloads.json`; una voce resta finché il torrent esiste in qBittorrent.
  - `DownloadEntry.DirectHash : string?`.
  - Nel giro (`RunCycleAsync`): per ogni voce con `DirectHash` e torrent con `Progress >= 1` → stesso import per cartella di `ImportExistingAsync` (estrai il corpo in `ImportFolderAsync(DownloadKey key, QbitTorrent torrent, bool lighten)` e chiamalo da entrambi), poi `DirectHash = null`. Torrent sparito → `DirectHash = null`, voce di nuovo da cercare come un download sparito oggi.
  - `UnknownDownloads` esclude i `DownloadId` presenti in `Book.DirectGrabs` (Review Focus 1). Le voci di `DirectGrabs` il cui torrent non c'è più si tolgono nel giro.

- [ ] **Step 1: test**: `PushApprovedIsGrabbed`; `PushTemporarilyRejectedIsPending`; `IntentionalNotUpgradeGoesDirect` (chiama `AddAsync` con il magnet e la categoria `series`); `NotIntentionalNotUpgradeIsRuleRefused`; `MixedRejectionsAreRuleRefused` (un motivo di file + "Quality not wanted" → `RuleRefused`); `QbitAddUsesMagnetHash` / `QbitAddTorrentFileFindsNewHash` (Review Focus 2); `DirectGrabImportedWhenComplete` (giro: torrent a `Progress` 1 → `ManualImportAsync` con `copy: true`, `DirectHash` null); `DirectGrabNotListedAsUnknown` (Review Focus 1); `DirectGrabGoneIsSearchedAgain`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde, suite verde.
- [ ] **Step 5:** commit `feat(plugin): grab con push e download diretti in qBittorrent`.

### Task 8: Il ciclo automatico usa il finder

**Files:**
- Modify: `Downloads/DownloadService.cs` (costruttore, riga ~27), `Downloads/DownloadService.Search.cs` (`ToSearchItem` ~267, `SearchOneAsync` ~297, `GrabChoiceAsync` ~412), `Downloads/DownloadService.Seasons.cs` se serve
- Test: `Tests/DownloadServiceSearchTests.cs`, `Tests/DownloadServiceSeasonTests.cs`, i costruttori di test di `DownloadService`

**Interfaces:**
- Consumes: `IReleaseFinder` (Task 5, 7), `ChecksContext` (Task 6).
- Produces: `DownloadService(…, IReleaseFinder? finder = null)`; con `finder` null si costruisce un finder che usa sempre la strada `Arr` (test esistenti invariati).
- `SearchItem` porta la `DownloadKey` invece della query.
- `SearchOneAsync`: `finder.SearchAsync(key, SearchEngine.Prowlarr, ct, ArrClient.CycleSearchTimeout)`; `ChecksContext` letto una volta per servizio e per giro, con `ReadContextAsync` (estendilo); il timeout di `Split` vale solo per `Engine == Arr`.
- Grab: fino a 3 candidate in ordine di regola (`rule.Candidates`, per le stagioni il pack poi i successivi pack validi): `RuleRefused` → prossima, senza `RememberRefused`; `Direct` → voce "in download" con `DirectHash`; `Grabbed`/`Pending` → come oggi; `ArrException` ≥ 500 → `GrabRefused` come oggi (Review Focus 4). Tre `RuleRefused` → `NothingChosen` come per nessuna release valida (log con il primo motivo).
- `intentional` = `forceImport` (tappabuchi per peso).
- "Trovato poco" nel ciclo: solo log informativo; nessuno stato nuovo.

- [ ] **Step 1: test**: `CycleSearchesWithProwlarrEngine`; `RuleRefusedTriesNextCandidate`; `ThreeRuleRefusalsAreNothingChosen` (nessun `NeedsYou`, `RefusedReleases` vuoto); `ClientRefusedIsGrabRefused` (push → `ArrException` 500); `StopgapBySizeGoesDirectWhenPushRefuses`; tutti i test esistenti del ciclo verdi.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde, suite verde.
- [ ] **Step 5:** commit `feat(plugin): il giro dei download cerca su Prowlarr`.

### Task 9: Ricerca a mano, Alleggerisci e "Cerca con Sonarr/Radarr"

**Files:**
- Modify: `Downloads/DownloadService.SearchJobs.cs` (`StartSearch` ~46, `RunSearchAsync` ~166), `Downloads/DownloadService.Admin.cs` (`SearchForAdminAsync` ~1149, `GrabAsync` ~139, `GrabGuardedAsync` ~655, `GrabBestAsync` ~232, ~1434), `Protocol/DownloadsDtos.cs` (`SearchStartRequest` ~245, `DownloadSearchDto` ~151), `Api/DownloadsController.cs`
- Test: `Tests/DownloadServiceAdminTests.cs`, `Tests/DownloadServiceSearchJobTests.cs`, `Tests/DownloadsControllerTests.cs`

**Interfaces:**
- Produces:
  - `SearchStartRequest.Engine : string?` (`"Arr"` = strada vecchia; altro o assente = Prowlarr). `StartSearch(string key, bool again, SearchEngine engine = SearchEngine.Prowlarr)`; un engine diverso da quello del job esistente conta come `again`.
  - `DownloadSearchDto` aggiunge in coda `[JsonPropertyName("Engine")] string Engine` e `[JsonPropertyName("LowResults")] bool LowResults`. `LowResults` = nessuna candidata valida, oppure chiave di stagione e nessuna candidata con `FullSeason`. `Rejected` include le `WrongTitle` con `Reason = "WrongTitle"`.
  - Il grab dell'admin usa la release ricordata in `_lastSearch` (che ora ha link e sorgente) e `finder.GrabAsync` con `intentional` = `lighten || ManualImportPending atteso (WouldImport falso con file attuale) || stagione/episodio non monitorato`. `Direct` → come un grab riuscito (`GrabOutcome.Ok`), voce in download con `DirectHash`, e per `lighten` lo stesso `MarkLightened` di oggi. `RuleRefused` → `GrabOutcome.Refused` con il motivo nel log. Il "risultati scaduti, ricerco" (404/400) solo per `Source == Arr`.
  - `GrabBestAsync`: stessa logica a tentativi del Task 8.

- [ ] **Step 1: test**: `StartSearchDefaultsToProwlarr`; `EngineArrUsesReleaseEndpoint`; `ChangingEngineRestartsJob`; `LowResultsWhenNoFullSeasonPack`; `WrongTitleListedAsRejected`; `LightenNotUpgradeGoesDirect` (il caso di Slime: push rifiuta "Not an upgrade" → `AddAsync`, `GrabOutcome.Ok`, segnato alleggerito); `AdminGrabAfterThirtyMinutesStillWorks` (Prowlarr: nessuna nuova ricerca); controller: `Engine` letto dal body.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** verde, suite verde.
- [ ] **Step 5:** commit `feat(plugin): ricerca a mano e Alleggerisci via Prowlarr, Cerca con Sonarr/Radarr`.

### Task 10: App — avviso "trovato poco", pulsante e motivi nuovi

**Files:**
- Modify: `app/lib/core/downloads/download_models.dart` (`RejectedReason` ~89, `DownloadSearch` ~708), `app/lib/core/downloads/downloads_api.dart` (`searchStart` ~105), `app/lib/features/downloads/download_search_controller.dart`, `app/lib/features/downloads/download_search_page.dart`, `app/lib/features/downloads/download_labels.dart` (~166), `app/l10n/*.arb`
- Test: `app/test/…` accanto ai test esistenti della pagina di ricerca e dei modelli

**Interfaces:**
- Consumes: DTO del Task 9.
- Produces: `RejectedReason` con `wrongTitle('WrongTitle')`, `notWanted('NotWanted')`, `restricted('Restricted')`, `blocklisted('Blocklisted')`; `DownloadSearch.engine` (`SearchEngine.prowlarr|arr`, default prowlarr se assente) e `lowResults` (default false); `searchStart(key, {bool again, bool viaArr = false})` manda `'Engine': 'Arr'` solo con `viaArr`.
- UI: con `lowResults` un avviso sopra i risultati; sempre un pulsante "Cerca con Sonarr" (serie) / "Cerca con Radarr" (film) che rilancia la ricerca con `viaArr: true`; con `engine == arr` l'intestazione dice che i risultati vengono da Sonarr/Radarr. Testi italiani (e inglesi negli altri `.arb`) per avviso, pulsante e i quattro motivi brevi: "Altro titolo", "Qualità non voluta", "Termini vietati", "In blocklist".

- [ ] **Step 1: test**: parsing di `Engine`/`LowResults` e dei 4 motivi (JSON vecchio senza i campi → default); widget: avviso visibile solo con `lowResults`; tap sul pulsante → `searchStart` con `Engine: Arr`.
- [ ] **Step 2:** FAIL. **Step 3:** implementa. **Step 4:** `flutter gen-l10n`, `flutter analyze`, `flutter test` verdi.
- [ ] **Step 5:** commit `feat(app): avviso "trovato poco" e Cerca con Sonarr/Radarr`.

### Task 11: Versioni e checklist

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` (`<Version>1.29.0</Version>`), `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoControllerTests.cs`, `app/pubspec.yaml` (`version: 0.40.0`), `docs/RELEASING.md` (riga nuova nella checklist manuale: "Ricerca a mano di una stagione anime: risultati da Prowlarr in pochi secondi, motivi di scarto brevi, 'Cerca con Sonarr' rifà la ricerca; Alleggerisci finisce")
- Test: suite plugin e app

- [ ] **Step 1:** aggiorna; `dotnet test …` e `flutter test` verdi.
- [ ] **Step 2:** commit `chore: plugin 1.29.0 e app 0.40.0`.

### Task 12: Confronto sul seedbox prima del test a mano

Non è codice del prodotto: lo fa il coordinatore, non un subagent.

- [ ] **Step 1:** build del plugin, deploy della dll sul seedbox seguendo `CLAUDE.md` (controllo visioni in corso, md5 e altre sessioni; `app-jellyfin stop`/copia/`start`; attesa di `Healthy` e della riga `avviato`). Inserire `ProwlarrUrl` `http://149.40.59.140:20790/prowlarr` e la chiave di Prowlarr nella configurazione del plugin (leggerla da `~/.apps/prowlarr/config.xml` con uno script, mai stamparla).
- [ ] **Step 2:** per 4 titoli (un episodio anime in corso, il pack Slime S02, un episodio di una serie normale, un film italiano) ricerca a mano con Prowlarr e con "Cerca con Sonarr/Radarr": annotare candidate valide e scelta. Atteso: la scelta della strada vecchia è tra le candidate valide della nuova. Per Slime S02 la ricerca a mano sulla strada nuova finisce in pochi minuti.
- [ ] **Step 3:** RSS di Sonarr prima e dopo; nessun riavvio del watchdog per OutOfMemory durante le prove (`~/.local/state/sonarr-watchdog/watchdog.log`).
- [ ] **Step 4:** release exe e avvio per il test a mano dell'utente.
