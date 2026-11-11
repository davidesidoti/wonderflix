# Trailer dentro l'app — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** il pulsante "Trailer" fa partire il trailer dentro WonderFlix (Windows, web, iPhone, Fire TV), scaricato al momento dal plugin con yt-dlp e cancellato un'ora dopo l'ultima visione.

**Architecture:** il plugin risolve l'id YouTube del trailer (Jellyfin `RemoteTrailers`, poi Seerr/TMDB), lo scarica con il binario autonomo `yt-dlp_linux` in una cache che si pulisce da sola e lo serve come mp4 con `Range`; l'app chiede `Info` per mostrare il pulsante, poi `Start`/`Status` (job interrogato) e apre lo stream in una schermata trailer semplice basata su `VideoEngine`.

**Tech Stack:** .NET 9 / Jellyfin 10.11 (plugin, xunit, `FakeTimeProvider`), Flutter 3.47.5 / Riverpod 3 / go_router (app).

**Spec:** `docs/superpowers/specs/2026-11-10-wonderflix-trailer-in-app-design.md`

## Global Constraints

- Commit in italiano, autore solo l'utente: **niente** `Co-Authored-By`, niente "Generated with". Mai `closes`/`fixes`/`resolves` nei messaggi.
- Mai uccidere processi per nome immagine (`taskkill /IM`, `pkill`): solo per PID, e solo processi propri.
- Build release: `flutter build windows --release --dart-define-from-file=config/wonderflix.json` (da `app/`; copiare `config/wonderflix.json` dal checkout principale).
- Controlli app (da `app/`): `flutter gen-l10n`, `flutter analyze`, `flutter test`. Plugin (da `plugin/`): `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`.
- Plugin compilato su Jellyfin 10.11.0, test su 10.11.9: non dare per scontate firme di patch.
- Nessuna richiesta HTTP lunga: download solo come job interrogato (nginx taglia a 180 s).
- Off-TV la scheda resta identica, a parte il pulsante che apre la schermata trailer invece del browser. Nessun `launchUrl` per i trailer da nessuna parte.
- `dart format` solo sulle righe cambiate.
- Valori fissi: 720p max, `duration<=600`, `--max-filesize 200M`, timeout processo 3 min, file cancellati 60 min dopo l'ultima visione, pulizia ogni 5 min, tetto cache 1 GB, cache risoluzioni 24 h, binario riscaricato dopo 7 giorni, polling app ogni 1 s per massimo 3 min.
- Versioni finali: plugin 1.28.0, app 0.39.0.

## Review Focus

1. Due utenti premono lo stesso trailer insieme → un solo download, entrambi lo vedono (test in Task 3).
2. Si chiude la schermata durante "Preparo il trailer…" → il polling si ferma senza errori; il download sul server finisce e il file sparisce dopo un'ora (test in Task 6).
3. Video troppo lungo, troppo grande, vietato o tolto da YouTube → `Failed` → "Trailer non disponibile", mai una schermata nera (test in Task 3 e Task 6).
4. La pulizia passa mentre qualcuno sta guardando → il file non si cancella finché lo stream è aperto (test in Task 3).
5. Utente che non può vedere l'elemento (librerie, limiti d'età) → `Info` dice non disponibile e `Start` dà `None`; un id YouTube mai risolto → 404 sullo stream (test in Task 2 e Task 4).

---

### Task 1: yt-dlp nel plugin + spike nel container

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/YtDlpBinary.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/ITrailerDownloader.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/YtDlpDownloader.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/TrailerPaths.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/YtDlpTests.cs`

**Interfaces:**
- Produces:
  - `public static class TrailerPaths { static string Root(IApplicationPaths p); static string Bin(IApplicationPaths p); static string Cache(IApplicationPaths p); }`: `Root` = `Path.Combine(p.PluginConfigurationsPath, FriendStore.FolderName, "trailers")`, poi `bin/` e `cache/`.
  - `public enum TrailerDownloadOutcome { Ok, Unavailable, Failed }` (`Unavailable` = video vietato/tolto/troppo lungo/troppo grande; `Failed` = rete, processo, timeout).
  - `public interface ITrailerDownloader { Task<TrailerDownloadOutcome> DownloadAsync(string videoId, string targetMp4Path, CancellationToken cancellationToken); }`: scrive solo `targetMp4Path` a download finito (passa da `<id>.part.*` e rinomina).
  - `public static class YtDlpArguments { static IReadOnlyList<string> For(string videoId, string partTemplate, string ffmpegPath); }`
  - `public static class YtDlpBinary { static string? ExpectedHash(string sha256Sums, string fileName); }` più l'istanza `YtDlpBinary(IHttpClientFactory, IApplicationPaths, TimeProvider, ILogger<YtDlpBinary>)` con `Task<string> EnsureAsync(bool forceRefresh, CancellationToken)` che restituisce il percorso eseguibile.

- [ ] **Step 1: test che falliscono** in `YtDlpTests.cs`:

```csharp
[Fact] public void ArgumentsPinFormatLimitsAndFfmpeg()
{
    var args = YtDlpArguments.For("25WcssMq1VM", "/c/cache/25WcssMq1VM.part.%(ext)s", "/usr/lib/jellyfin-ffmpeg/ffmpeg");
    Assert.Equal("https://www.youtube.com/watch?v=25WcssMq1VM", args[^1]);
    Assert.Contains("--no-playlist", args);
    Assert.Equal("bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/b[height<=720][ext=mp4]", After(args, "-f"));
    Assert.Equal("mp4", After(args, "--merge-output-format"));
    Assert.Equal("duration<=600", After(args, "--match-filter"));
    Assert.Equal("200M", After(args, "--max-filesize"));
    Assert.Equal("/usr/lib/jellyfin-ffmpeg/ffmpeg", After(args, "--ffmpeg-location"));
    Assert.Equal("/c/cache/25WcssMq1VM.part.%(ext)s", After(args, "-o"));
}

[Fact] public void ExpectedHashReadsTheLineOfTheFile() =>
    Assert.Equal("ab12", YtDlpBinary.ExpectedHash("ff00  yt-dlp\nab12  yt-dlp_linux\ncd34  yt-dlp_linux.zip\n", "yt-dlp_linux"));

[Fact] public void ExpectedHashIsNullWhenTheFileIsMissing() =>
    Assert.Null(YtDlpBinary.ExpectedHash("ff00  yt-dlp\n", "yt-dlp_linux"));
```

(`After(args, flag)` = l'elemento dopo `flag`, helper privato del test.)

- [ ] **Step 2:** `dotnet test ... --filter YtDlpTests` → FAIL (tipi mancanti).
- [ ] **Step 3: implementare.** `YtDlpBinary.EnsureAsync`: se `bin/yt-dlp_linux` esiste, ha meno di 7 giorni (`File.GetLastWriteTimeUtc` contro `TimeProvider`) e non c'è `forceRefresh`, lo restituisce; altrimenti scarica `https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux` e `.../SHA2-256SUMS` con un `HttpClient` nominato (registrato in Task 4), confronta lo SHA-256 (minuscolo) con `ExpectedHash`, scrive in un `.tmp`, `File.SetUnixFileMode(... UserRead|UserWrite|UserExecute)`, rinomina; un semaforo evita due download insieme; se il controllo fallisce lancia e non tocca il binario vecchio. Comando `--no-progress` incluso negli argomenti. `YtDlpDownloader(YtDlpBinary, IMediaEncoder, ILogger)`: ffmpeg da `IMediaEncoder.EncoderPath`; `Process` con `ArgumentList`, stdout/stderr letti in asincrono, timeout 3 min con `CancellationTokenSource` collegato, `Kill(entireProcessTree: true)` su timeout/annullamento, cancella i `<id>.part*` rimasti; codice di uscita ≠ 0: se stderr contiene `does not pass filter`, `File is larger than max-filesize`, `Video unavailable`, `Private video` o `Sign in to confirm your age` → `Unavailable`; se contiene `Unable to extract` o `nsig` → `EnsureAsync(forceRefresh: true)` e un solo nuovo tentativo; altrimenti `Failed`. Uscita 0 ma nessun `<id>.part.mp4` → `Unavailable` (yt-dlp esce 0 quando `--match-filter` scarta il video). Log in italiano, senza URL di googlevideo.
- [ ] **Step 4:** `dotnet test ... --filter YtDlpTests` → PASS.
- [ ] **Step 5: commit** `feat(plugin): yt-dlp per i trailer`.
- [ ] **Step 6: spike nel container (non va su `main`).** Su un branch usa e getta `spike/trailer-ytdlp`, un `IHostedService` provvisorio che 60 s dopo l'avvio chiama `EnsureAsync(false)`, logga `--version` e scarica `25WcssMq1VM` in `TrailerPaths.Cache`, poi logga esito, dimensione e durata. Pacchetto con `bash plugin/pack.sh 1.27.99`, deploy sul seedbox seguendo CLAUDE.md (nessuno che guarda, data/md5 della dll, altre sessioni con `ListAgents`, `app-jellyfin stop`/copia/`start`, attesa di `Healthy`). Riuscito se il log dice `Ok` e il file esiste in `~/.apps/jellyfin/data/plugins/configurations/WonderFlixWatchParty/trailers/cache/`. Poi: cancellare il file, rimettere la dll 1.27.0 ufficiale, cancellare il branch. **Se fallisce, fermarsi e tornare dall'utente** (ripiego dello spec: servizio fuori dal container).

---

### Task 2: da quale video viene il trailer

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/ITrailerLibrary.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinTrailerLibrary.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/YouTubeId.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/TrailerResolver.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/TrailerResolverTests.cs`, `FakeTrailerLibrary.cs`

**Interfaces:**
- Consumes: `ISeerrClient.GetMovieAsync/GetTvAsync(int tmdbId, string language, CancellationToken)`, `SeerrMapping.TrailerUrl(IEnumerable<SeerrVideo>)`, `ISeerrSettings.IsConfigured()`, `ILibraryAccess.CanSee`.
- Produces:
  - `public sealed record TrailerItem(string MediaType, int? TmdbId, IReadOnlyList<string> RemoteTrailerUrls);` (`MediaType` = `"movie"` o `"tv"`)
  - `public interface ITrailerLibrary { TrailerItem? Find(Guid userId, Guid itemId); }`: null se l'elemento non esiste, non è `Movie`/`Series` o l'utente non lo vede (`ILibraryAccess.CanSee`).
  - `public static class YouTubeId { static string? FromUrl(string? url); static bool IsValid(string id); }`: accetta `youtube.com/watch?v=`, `youtu.be/`, `youtube.com/embed/`, `youtube-nocookie.com/embed/`, `m.youtube.com`; id = `^[A-Za-z0-9_-]{11}$`.
  - `public sealed record TrailerSubject(Guid? ItemId, string? MediaType, int? TmdbId);`
  - `public sealed record ResolvedTrailer(string VideoId, string? Name);`
  - `public sealed class TrailerResolver(ITrailerLibrary, ISeerrClient, ISeerrSettings, TimeProvider)` con `Task<ResolvedTrailer?> ResolveAsync(Guid userId, TrailerSubject subject, CancellationToken)` e `bool WasResolved(string videoId)`.

- [ ] **Step 1: test che falliscono** (con `FakeSeerrClient`, `FakeSeerrSettings`, `FakeTimeProvider`):
  - `JellyfinTrailerComesFirst`: elemento con `RemoteTrailerUrls = ["https://www.youtube.com/watch?v=AmsN8z7tl48"]` e TMDB 1 → `VideoId == "AmsN8z7tl48"`, Seerr mai chiamato.
  - `SeerrFillsTheGap`: elemento film senza trailer, TMDB 1375646, Seerr con un video YouTube Trailer `https://www.youtube.com/watch?v=25WcssMq1VM` → `"25WcssMq1VM"`, chiamato con lingua `"it"`.
  - `TmdbSubjectGoesStraightToSeerr`: `TrailerSubject(null, "tv", 42)` → `GetTvAsync(42, "it", …)`.
  - `NothingWhenSeerrIsNotConfigured`: elemento senza trailer, settings vuoti → null, Seerr mai chiamato.
  - `NothingForAnItemTheUserCannotSee`: `Find` restituisce null → null.
  - `AnswersAreRememberedForADay`: due `ResolveAsync` → una sola chiamata a Seerr; dopo `Advance(TimeSpan.FromHours(24) + 1 s)` → due.
  - `SeerrErrorsAreNotRemembered`: Seerr lancia `SeerrException` (o l'eccezione che usa `SeerrClient`) → null, e la volta dopo richiama.
  - `WasResolvedOnlyForReturnedIds`: dopo aver risolto `25WcssMq1VM` → true; `dQw4w9WgXcQ` → false.
  - `YouTubeIdParsesTheKnownShapes` (Theory): i cinque formati sopra → l'id; `https://vimeo.com/1`, `javascript:x`, `null`, id di 10 caratteri → null.
- [ ] **Step 2:** `dotnet test ... --filter "TrailerResolverTests"` → FAIL.
- [ ] **Step 3: implementare.** Cache in `ConcurrentDictionary` con chiave `(userId?, itemId, mediaType, tmdbId)`; per un elemento della libreria la chiave include l'utente, perché `CanSee` dipende da lui. "Nessun trailer" si ricorda, gli errori di Seerr no. `WasResolved` usa un insieme di id restituiti negli ultimi 24 h. `JellyfinTrailerLibrary(ILibraryManager, ILibraryAccess)`: `BaseItem.RemoteTrailers` (`MediaUrl.Url`), `GetProviderId(MetadataProvider.Tmdb)`.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: commit** `feat(plugin): da dove viene il trailer`.

---

### Task 3: cache dei file e job di download

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/TrailerCache.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Trailers/TrailerService.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/TrailersDtos.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/TrailerCacheTests.cs`, `TrailerServiceTests.cs`, `FakeTrailerDownloader.cs`

**Interfaces:**
- Consumes: `ITrailerDownloader`, `TrailerResolver`, `TrailerPaths.Cache`.
- Produces:
  - `public static class TrailerStates { const string None = "None", Downloading = "Downloading", Ready = "Ready", Failed = "Failed"; }`
  - DTO (`Protocol/TrailersDtos.cs`): `TrailerSubjectRequest { string? ItemId; string? Type; int? TmdbId; }`, `TrailerInfoDto(bool Available, string? Name)`, `TrailerStatusDto(string? Key, string State)` (`Key` con `JsonIgnore(Condition = Never)`).
  - `public sealed class TrailerCache(string folder, TimeProvider time)`: `static readonly TimeSpan KeepFor = 60 min`, `const long MaxBytes = 1L << 30`, `void Clear()`, `string PathFor(string videoId)`, `bool Has(string videoId)` (aggiorna l'ultima visione), `void Touch(string videoId)`, `IDisposable OpenLease(string videoId)`, `void Sweep()`, `void MakeRoom(long incomingBytes = 200L << 20)`.
  - `public sealed class TrailerService(TrailerResolver, ITrailerDownloader, TrailerCache, ILogger<TrailerService>)`: `Task<TrailerInfoDto> InfoAsync(Guid userId, TrailerSubject, CancellationToken)`, `Task<TrailerStatusDto> StartAsync(Guid userId, TrailerSubject, CancellationToken)`, `TrailerStatusDto? Status(string key)` (null = chiave sconosciuta → 404), `(string Path, IDisposable Lease)? OpenStream(string key)`.

- [ ] **Step 1: test che falliscono.** `TrailerCacheTests` (cartella temporanea, `FakeTimeProvider`):
  - `SweepDeletesFilesUnseenForAnHour`: file toccato a t0; `Advance(59 min)` + `Sweep` → c'è; `Advance(2 min)` + `Sweep` → sparito.
  - `TouchKeepsAFileAlive`: `Touch` a 50 min, `Sweep` a 70 min → c'è.
  - `AnOpenLeaseBlocksDeletion`: lease aperta, `Advance(2 h)` + `Sweep` → c'è; dopo `Dispose` + `Sweep` → sparito.
  - `SweepRemovesOrphanParts`: `x.part.mp4` più vecchio di 10 min → sparito.
  - `ClearEmptiesTheFolder`.
  - `MakeRoomDropsTheLeastRecentlySeen`: tre file da 400 MB finti (`SetLength`), `MakeRoom(400 MB)` → resta sotto 1 GB, cancellato quello visto meno di recente, mai uno con lease.

  `TrailerServiceTests` (`FakeTrailerDownloader` con cancello per tenere il download aperto):
  - `StartDownloadsOnceForTwoUsers`: due `StartAsync` sullo stesso trailer mentre il cancello è chiuso → `DownloadCalls == 1`, entrambi `Downloading`; apertura → `Status` `Ready` per tutti e due.
  - `ReadyFileIsServedWithoutDownloading`: file già in cache → `StartAsync` dà `Ready` subito, `DownloadCalls == 0`.
  - `UnavailableAndFailedBecomeFailed` (Theory su `Unavailable`, `Failed`, eccezione) → `Failed`; uno `StartAsync` successivo riprova (un job fallito non si ricorda).
  - `NoTrailerIsNone`: resolver senza risultato → `State == "None"`, `Key == null`.
  - `StatusOfAnUnknownKeyIsNull`.
  - `OpenStreamOnlyForReadyResolvedKeys`: chiave risolta e pronta → path e lease; chiave mai risolta, o ancora in download → null.
- [ ] **Step 2:** `dotnet test ... --filter "TrailerCacheTests|TrailerServiceTests"` → FAIL.
- [ ] **Step 3: implementare.** Job in un `ConcurrentDictionary<string, Task<TrailerDownloadOutcome>>`; il download gira con `CancellationToken.None` (deve finire anche se la richiesta si chiude); `MakeRoom` prima di partire; `Status` e `OpenStream` toccano il file.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: commit** `feat(plugin): cache e download dei trailer`.

---

### Task 4: API, servizio in background, registrazione, versione 1.28.0

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Api/TrailersController.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/TrailersHostedService.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj` (versione), `plugin/README.md`
- Test: `TrailersControllerTests.cs`, `TrailersHostedServiceTests.cs`, `InfoControllerTests.cs` (versione), `ServiceRegistrationTests.cs` se elenca i servizi

**Interfaces:**
- Consumes: `TrailerService`, `TrailerCache`, `IAuthorizationContext` (come `SubtitlesController.CallerAsync`).
- Produces (rotta `WonderFlixWatchParty`, `[Authorize]`):
  - `GET Trailers/Info?itemId=|tmdbId=&type=movie|tv` → `TrailerInfoDto`; 400 se mancano entrambi o `type` non è `movie`/`tv`.
  - `POST Trailers/Start` corpo `TrailerSubjectRequest` → `TrailerStatusDto`; 400 come sopra.
  - `GET Trailers/Status?key=` → `TrailerStatusDto`, 404 se chiave sconosciuta.
  - `GET Trailers/{key}/Stream` → `PhysicalFile(path, "video/mp4", enableRangeProcessing: true)`; la lease si rilascia con `HttpContext.Response.RegisterForDispose`; 404 se `OpenStream` è null.

- [ ] **Step 1: test che falliscono:** `InfoNeedsASubject` (400), `InfoRejectsAnUnknownType` (400 per `type=person`), `StartReturnsTheJobState`, `StatusOfAnUnknownKeyIs404`, `StreamOfAnUnresolvedKeyIs404`, `StreamServesMp4WithRanges` (`PhysicalFileResult.EnableRangeProcessing == true`, `ContentType == "video/mp4"`); `TrailersHostedServiceTests`: `StartClearsTheCache`, `SweepRunsEveryFiveMinutes` (con `FakeTimeProvider`, come gli altri hosted service). `InfoControllerTests`: versione attesa `1.28.0`.
- [ ] **Step 2:** `dotnet test ... --filter "Trailers"` → FAIL.
- [ ] **Step 3: implementare** controller, hosted service (`Clear()` all'avvio, `Sweep()` ogni 5 min, log `Trailer: cache svuotata`), registrazione (`AddHttpClient(YtDlpBinary.HttpClientName)` con timeout 2 min; singleton di `YtDlpBinary`, `ITrailerDownloader`→`YtDlpDownloader`, `ITrailerLibrary`→`JellyfinTrailerLibrary`, `TrailerResolver`, `TrailerCache` con `TrailerPaths.Cache`, `TrailerService`; `AddHostedService<TrailersHostedService>()`), versione 1.28.0 nel csproj, sezione "Trailer" nel README (yt-dlp scaricato da GitHub, cartella, durata un'ora, tetto 1 GB). Controllare dal vivo nello step 5 del Task 7 che `[Authorize]` accetti `ApiKey` nella query sullo stream; se non la accetta, autenticare lo stream come fa Jellyfin per `/Videos/{id}/stream` e annotarlo.
- [ ] **Step 4:** tutta la suite plugin → PASS (rilanciare una volta i test instabili noti di CLAUDE.md prima di indagare).
- [ ] **Step 5: commit** `feat(plugin): API dei trailer e pulizia automatica`.

---

### Task 5: API dei trailer nell'app

**Files:**
- Create: `app/lib/core/trailers/trailers_api.dart`
- Test: `app/test/core/trailers/trailers_api_test.dart`

**Interfaces:**
- Consumes: `JellyfinHttp` (come `RequestsApi`), `withApiKey` di `core/jellyfin/media_url.dart`.
- Produces:
  - `sealed class TrailerSubject` con `LibraryTrailer(String itemId)` e `TmdbTrailer(String type, int tmdbId)` (`type` = `'movie'`/`'tv'`).
  - `enum TrailerState { none, downloading, ready, failed }`
  - `class TrailerStatus { final String? key; final TrailerState state; }`
  - `class TrailersApi { Future<bool> available(TrailerSubject s); Future<TrailerStatus> start(TrailerSubject s); Future<TrailerStatus> status(String key); String streamUrl(String key); }`. `available` restituisce false su 404 (plugin vecchio) e su qualunque errore; `start`/`status` lanciano `TrailerUnavailableException` su errore o 404. Uno `State` sconosciuto vale `failed`.
  - `final trailersApiProvider = Provider<TrailersApi>(...)` e `final trailerAvailableProvider = FutureProvider.autoDispose.family<bool, TrailerSubject>(...)` (`TrailerSubject` con `==`/`hashCode`).

- [ ] **Step 1: test che falliscono** (stesso schema di `requests_api_test.dart`): `availableSendsItemId` (`GET /WonderFlixWatchParty/Trailers/Info?itemId=abc`), `availableSendsTmdb` (`?tmdbId=7&type=tv`), `availableIsFalseOn404`, `startPostsTheSubjectAndParsesTheState` (`{"Key":"25WcssMq1VM","State":"Downloading"}`), `unknownStateIsFailed`, `streamUrlCarriesTheApiKey` (`…/WonderFlixWatchParty/Trailers/25WcssMq1VM/Stream?ApiKey=<token>`).
- [ ] **Step 2:** `flutter test test/core/trailers` → FAIL.
- [ ] **Step 3: implementare.** 404 nei `quietStatuses`.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: commit** `feat(app): API dei trailer`.

---

### Task 6: schermata trailer

**Files:**
- Create: `app/lib/features/trailer/trailer_screen.dart`
- Create: `app/lib/features/trailer/trailer_controller.dart`
- Modify: `app/lib/app/navigation.dart` (`trailerRoute`), `app/lib/app/router.dart` (rotta fuori dallo shell, come `/play/:id`, con `playerPage`), `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/trailer/trailer_screen_test.dart`

**Interfaces:**
- Consumes: `TrailersApi`, `videoEngineFactoryProvider` (`features/player/player_providers.dart`), `VideoEngine`, `VideoSource`.
- Produces:
  - `String trailerRoute(TrailerSubject subject, {String? title, String? backdropItemId})` → `/trailer/item/<id>` oppure `/trailer/tmdb/<type>/<tmdbId>`, con `title` e `backdrop` in query.
  - `TrailerScreen({required TrailerSubject subject, String? title, String? backdropItemId})`.
  - Testi: `trailerPreparing` "Preparo il trailer…", `trailerUnavailable` "Trailer non disponibile", `trailerClose` "Chiudi" (it; in en "Preparing the trailer…", "Trailer not available", "Close").

- [ ] **Step 1: test che falliscono** (API finta e `VideoEngine` finto tramite override di `trailersApiProvider` e `videoEngineFactoryProvider`; pump espliciti, niente `pumpAndSettle` con l'indicatore indeterminato):
  - `preparingThenPlays`: `start` → `downloading`, due `status` → `downloading` poi `ready` → si vede "Preparo il trailer…", poi l'engine riceve `open(VideoSource(url: streamUrl))` e `play()`.
  - `failedShowsUnavailable`: `start` → `failed` → "Trailer non disponibile" e "Chiudi"; l'engine non viene aperto.
  - `noneShowsUnavailable`.
  - `givesUpAfterThreeMinutes`: `status` sempre `downloading`, pump di 181 s → "Trailer non disponibile".
  - `closingWhilePreparingStopsPolling`: chiusa la schermata dopo il primo `status`, pump di 5 s → nessuna altra chiamata, nessuna eccezione.
  - `closesAtTheEnd`: `completedStream` emette true → la rotta si chiude.
  - `tvKeys`: con TV attiva (come negli altri test TV), `select` → `pause()`/`play()`, freccia destra → `seek(position + 10 s)`, sinistra → `seek(position - 10 s)` (mai sotto zero); un `LogicalKeyboardKey.goBack` non chiude due volte.
  - `playBlockedShowsAPlayButton`: `playBlockedStream` emette → pulsante play grande; toccarlo chiama `play()`.
- [ ] **Step 2:** `flutter test test/features/trailer` → FAIL.
- [ ] **Step 3: implementare.** Sfondo nero con il backdrop del titolo (`WfImage`) mentre prepara; controlli play/pausa, barra della posizione (trascinabile off-TV), chiudi; si nascondono dopo 3 s senza input come nel player; `engine.dispose()` in `dispose`. `trailer_controller.dart` fa il polling (`Timer` da 1 s, si ferma in `dispose`).
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: commit** `feat(app): schermata del trailer`.

---

### Task 7: pulsante ovunque, TV, scheda richieste, versione 0.39.0

**Files:**
- Modify: `app/lib/features/playback/play_launcher.dart` (`playTrailer`, `remoteTrailerUri`)
- Modify: `app/lib/features/detail/detail_header.dart` (`hasTrailer`, `!tv` sul pulsante del ramo largo)
- Modify: `app/lib/features/space/space_title_dialog.dart` (`hasTrailer`)
- Modify: `app/lib/features/requests/tmdb_title_screen.dart` (`_trailerUri`, `launchUrl` del trailer)
- Modify: `docs/RELEASING.md` (riga nella checklist), `app/pubspec.yaml` (0.39.0)
- Test: i test esistenti di dettaglio, richieste e Spazio che toccano il trailer, più `app/test/features/playback/play_trailer_test.dart`

**Interfaces:**
- Consumes: `trailerAvailableProvider`, `trailerRoute`, `LibraryTrailer`, `TmdbTrailer`.
- Produces: `bool hasTrailerOf(WidgetRef ref, JellyfinItem item)` in `play_launcher.dart` = trailer locale, oppure `RemoteTrailers` con id YouTube, oppure `trailerAvailableProvider(LibraryTrailer(item.id))` vero, solo per film e serie; la chiamata a `Info` parte solo se i primi due mancano.

- [ ] **Step 1: test che falliscono:**
  - `play_trailer_test.dart`: `localTrailerStillOpensThePlayer` (va su `playerRoute(<id del trailer locale>)`); `remoteTrailerOpensTheTrailerScreen` (va su `trailerRoute(LibraryTrailer(item.id), …)`, `launchUrl` mai chiamato).
  - dettaglio: `trailerButtonShowsWhenThePluginHasOne` (film senza `RemoteTrailers`, API finta `available` = true → pulsante "Trailer"); `noTrailerButtonWhenThePluginIsOld` (404 → nessun pulsante); `tvShowsTheTrailerButton` (TV, ramo largo → pulsante raggiungibile con il focus).
  - richieste: `tmdbTrailerOpensTheTrailerScreen` (con `trailerUrl` → `trailerRoute(TmdbTrailer('movie', id))`).
- [ ] **Step 2:** `flutter test` sui file toccati → FAIL.
- [ ] **Step 3: implementare.** `playTrailer`: trailer locale come oggi; altrimenti `context.push(trailerRoute(LibraryTrailer(item.id), title: item.name, backdropItemId: item.id))`. Nessun `launchUrl` per i trailer: togliere l'import di `url_launcher` dove non serve più. Il pulsante della scheda richieste compare quando c'è `trailerUrl` (lo dà già il plugin) e apre `trailerRoute(TmdbTrailer(type, tmdbId))`. Riga nella checklist di `docs/RELEASING.md`: "Trailer: Colony da Windows, iPhone e Fire Stick parte dentro l'app; un titolo con trailer Jellyfin; un titolo senza; dopo un'ora il file non è più sul seedbox". Versione 0.39.0 nello stesso commit.
- [ ] **Step 4:** `flutter gen-l10n`, `flutter analyze`, `flutter test` → tutto verde.
- [ ] **Step 5: commit** `feat(app): trailer dentro l'app anche su TV e nelle richieste`.
- [ ] **Step 6: prova dal vivo prima della revisione finale.** dll 1.28.0 sul seedbox (regole di CLAUDE.md), build release Windows, avvio dell'exe; Colony: il pulsante c'è, "Preparo il trailer…", parte; `ls` della cache sul seedbox; un'ora dopo la cartella è vuota. Controllare che lo stream con `ApiKey` risponda 206 a una richiesta `Range` (`curl -H "Range: bytes=0-99"`).
