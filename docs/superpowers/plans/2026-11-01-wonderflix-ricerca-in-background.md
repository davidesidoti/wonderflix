# Ricerca dei download in background — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la ricerca manuale dei download (anche una stagione anime da 5+ minuti) gira in background nel plugin; l'app avvia, chiede lo stato ogni 3 s e mostra barra e tempo che scorre.

**Architecture:** il `DownloadService` tiene al più un job di ricerca per chiave (in memoria, sotto `_lock`, con un token del servizio). Due endpoint nuovi (`SearchStart`, `SearchStatus`) e il vecchio `Search` che aspetta il job. L'app usa i nuovi endpoint solo con la funzione `downloadsSearchJobs` in `GET Info`.

**Tech Stack:** .NET 9 (plugin Jellyfin 10.11, xUnit), Flutter 3.47.5 con flutter_riverpod 3.x, dio.

**Spec:** `docs/superpowers/specs/2026-11-01-wonderflix-ricerca-in-background-design.md` (Spec W). Gli esecutori leggono spec e piano.

## Global Constraints

- Worktree `.claude/worktrees/pwa-ios`, branch `fix/pwa-ios`. Non toccare la checkout principale.
- Commit in italiano, Conventional Commits (`feat(plugin): …`, `feat(app): …`). **Niente** trailer `Co-Authored-By` né righe "Generated with". **Mai** le parole `closes`, `fixes`, `resolves`. Più righe: `git commit -F <file>`.
- Mai uccidere processi per nome immagine (`taskkill /IM`, `pkill`).
- Testi e commenti in italiano, codice in inglese, densità dei commenti come il codice intorno.
- `ArrClient.ReleaseSearchTimeout` = 15 minuti; `SearchTimeout` resta 2 minuti (manualimport).
- Risultati ed errori di un job valgono 30 minuti (`DownloadService.SearchResultLifetime`).
- Polling dell'app ogni 3 s; dopo 3 errori di rete di fila, errore a schermo.
- Plugin 1.19.0 (csproj e `InfoControllerTests`). Funzione `downloadsSearchJobs`.
- DTO: i campi nullable letti sempre hanno `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]`.
- Lavoro che deve finire: mai `HttpContext.RequestAborted` per il job.
- Test plugin (da `plugin/`): `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`. `ArrClientTests.ASlowSearchUsesTheSearchTimeout`, `SubtitleServiceTests.AFailedDownloadIsFailed` e `DownloadAlertsTests` sono instabili: rieseguire prima di indagare.
- Controlli app (da `app/`, PowerShell con il PATH rinfrescato: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`): `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- Build release Windows, se serve: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Widget test con barra indeterminata: niente `pumpAndSettle`, pompare a mano.
- I file `app/windows/flutter/generated_plugin*` riscritti solo nei fine riga: `git checkout --` prima del commit.

## Review Focus

1. Plugin riavviato mentre l'app chiede lo stato: `SearchStatus` dice `None`, l'app deve rifare `startSearch(again: false)` e non girare a vuoto → test in Task 5.
2. Due schede (o due admin) sullo stesso titolo: una sola chiamata a Sonarr → test in Task 2.
3. Orologio del telefono avanti rispetto al server (`StartedAt` nel futuro): il tempo mostra `0:00`, mai negativo → test in Task 6.
4. Riapertura dopo un job finito con errore: si vede l'errore e Sonarr non viene richiamato → test in Task 2 (plugin) e Task 5 (app).
5. Pagina chiusa durante il polling: nessuna richiesta dopo → test in Task 5.

---

### Task 0: commit dei fix già sul ramo (lo fa il coordinatore)

- [ ] Tre commit separati, nell'ordine: `fix(app): niente connectTimeout nel browser, la ricerca dei download non si ferma a 10 s` (`app/lib/core/jellyfin/jellyfin_http.dart`); `fix(web): COEP require-corp, Safari non conosce credentialless` (`app/deploy/*.conf`); `fix(app): un'immagine fallita esce dalla cache e mostra l'icona` (`app/lib/ui/wf_image.dart`). Più spec e piano: `docs: spec W e piano della ricerca in background`.

### Task 1: limite di 15 minuti per le ricerche di release

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Home/ArrClient.cs` (costanti a riga 24-25, `SearchReleasesAsync` a riga 81)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Home/IArrClient.cs:32` (commento)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ArrClientTests.cs:657`

**Interfaces:**
- Produces: `public static readonly TimeSpan ReleaseSearchTimeout = TimeSpan.FromMinutes(15);` in `ArrClient`.

- [ ] **Step 1:** in `ASlowSearchUsesTheSearchTimeout` aggiungi `Assert.Equal(TimeSpan.FromMinutes(15), ArrClient.ReleaseSearchTimeout);` e rinominalo `ASlowSearchUsesTheReleaseSearchTimeout`. Guarda come `Client(TimeSpan)` passa il limite: se oggi sostituisce `SearchTimeout`, fai in modo che il parametro del test sostituisca `ReleaseSearchTimeout` per `release` e che `manualimport` (in `AGrabAndTheManualImportReadWaitLonger`) resti su `SearchTimeout`.
- [ ] **Step 2:** esegui `dotnet test … --filter ArrClientTests`: FAIL (costante assente).
- [ ] **Step 3:** aggiungi la costante con il commento "le stagioni anime: Sonarr cerca un episodio alla volta (spec W §4.1)" e usala in `SearchReleasesAsync`. Aggiorna il commento di `IArrClient`.
- [ ] **Step 4:** `dotnet test … --filter ArrClientTests`: PASS.
- [ ] **Step 5:** commit `feat(plugin): 15 minuti per una ricerca di release, le stagioni anime superano i 2`.

### Task 2: job di ricerca nel DownloadService

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.SearchJobs.cs`
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadSearchStates.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.Admin.cs` (`SearchAsync` a riga 113-133; `ItemDto` a riga 736-745)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/DownloadsDtos.cs` (accanto a `DownloadSearchDto`, riga 120)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/DownloadsHostedService.cs:55` (`StopAsync`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FakeArrClient.cs` (solo se serve un gate; `Releases` è già un `Func` sostituibile)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DownloadServiceSearchJobTests.cs` (setup copiato da `DownloadServiceAdminTests`)

**Interfaces:**
- Produces:
  - `public static class DownloadSearchStates { Running, Done, Missing, None }` (const string con lo stesso nome).
  - `public sealed record DownloadSearchStatusDto(string Key, string State, DateTimeOffset? StartedAt, string Service, DownloadSearchDto? Result)` con `JsonPropertyName` come i fratelli; `StartedAt` e `Result` con `JsonIgnore(Never)`.
  - `public static readonly TimeSpan SearchResultLifetime = TimeSpan.FromMinutes(30);` in `DownloadService`.
  - `public DownloadSearchStatusDto? StartSearch(string key, bool again)`: null per una chiave non valida.
  - `public DownloadSearchStatusDto? SearchStatus(string key)`: null per una chiave non valida; `None` se non c'è un job o è scaduto.
  - `public void StopSearches()`: annulla i job (chiamata da `DownloadsHostedService.StopAsync`).
  - `SearchAsync(key, ct)` invariato nella firma: avvia o aggancia con `again: true` e aspetta il job con `WaitAsync(ct)`; null per `Missing`.

Regole (spec W §4.2-4.4): un job per chiave normalizzata (`parsed.ToString()`); gira con un token di un `CancellationTokenSource` del servizio, mai quello della richiesta; il lavoro è `ReadAsync(ServiceOf(kind), c => RunSearchAsync(parsed, c), token)`; errore → DTO con `Error` costruito come oggi in `SearchAsync`; `RunSearchAsync` null → `Missing`; con `Done`, `StartedAt` è l'ora della ricerca; `Service` è `ServiceOf(kind).ToString()`. Le chiavi dei job in corso stanno in un insieme a parte da `_searching`; `ItemDto` dà `Searching` se la chiave è in uno dei due. `Again` con un job in corso aggancia quello.

- [ ] **Step 1: test che falliscono** in `DownloadServiceSearchJobTests` (un `TaskCompletionSource` dentro `arr.Releases` tiene la ricerca aperta; `FakeTimeProvider` per i 30 minuti):
  - `StartReturnsRunningAndSearchesInTheBackground`: `State == "Running"`, `StartedAt == time.GetUtcNow()`, `Service == "Radarr"` per `movie:12`; dopo il rilascio del gate `SearchStatus("movie:12").State == "Done"` e `Result.Candidates` come in `DownloadServiceAdminTests`.
  - `ASecondStartJoinsTheRunningSearch`: due `StartSearch` (il secondo con `again: true`) → `arr.SearchReleaseCalls` ha 1 elemento.
  - `AFinishedSearchIsReusedForThirtyMinutes`: dopo la fine, `StartSearch(key, false)` → `Done`, 1 chiamata; `time.Advance(TimeSpan.FromMinutes(31))` → `SearchStatus` dà `None`, `StartSearch(key, false)` → `Running`, 2 chiamate.
  - `AgainStartsANewSearch`: dopo la fine, `StartSearch(key, true)` → `Running`, 2 chiamate.
  - `AnArrErrorIsDoneWithErrorAndIsNotRetriedOnReopen`: `arr.Releases` lancia `ArrException(ArrError.Unreachable)` → `Done`, `Result.Error == "Unreachable"` (il codice di `UpcomingErrors`); `StartSearch(key, false)` → stesso errore, 1 chiamata.
  - `AMissingTitleIsMissing`: chiave di un film assente → `Missing`; `StartSearch("garbage", false)` e `SearchStatus("garbage")` → null.
  - `TheOldSearchWaitsAndItsCancellationDoesNotStopTheJob`: `SearchAsync` con un token annullato a metà lancia `OperationCanceledException`; il job finisce lo stesso (`SearchStatus` → `Done`).
  - `TheOldSearchAlwaysSearchesAgain`: dopo un job finito, `SearchAsync` fa una seconda chiamata a Sonarr/Radarr.
  - `TheOverviewShowsSearchingDuringAnAdminSearch`: con il gate chiuso, la voce della chiave in `OverviewAsync` ha `Phase == "Searching"`; dopo, non più `Searching`.
  - `StopSearchesCancelsTheJob`: `StopSearches()` con il gate chiuso → il token passato a `Releases` è annullato.
- [ ] **Step 2:** `dotnet test … --filter DownloadServiceSearchJobTests`: FAIL (non compila).
- [ ] **Step 3:** implementa costanti, DTO, `DownloadService.SearchJobs.cs` (stato del job a scelta dell'esecutore, sotto `_lock`), il nuovo `SearchAsync`, `ItemDto`, `StopSearches` in `StopAsync`.
- [ ] **Step 4:** esegui i test nuovi e poi tutta la suite del plugin: PASS (i test esistenti di `SearchAsync` in Admin, Season e Alerts devono passare invariati).
- [ ] **Step 5:** commit `feat(plugin): ricerca dell'admin in background, un job per titolo con i risultati per 30 minuti`.

### Task 3: endpoint, funzione in GET Info, versione 1.19.0

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Api/DownloadsController.cs` (dopo `Search`, riga 26-32)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/DownloadsDtos.cs` (accanto a `KeyRequest`, riga 159)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs` (dopo `DownloadsFeature`, e in `FeaturesWith` accanto a `features.Add(DownloadsFeature)`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj:6` → `1.19.0`
- Test: `DownloadsControllerTests.cs`, `InfoControllerTests.cs:17`

**Interfaces:**
- Consumes: `StartSearch`, `SearchStatus` (Task 2).
- Produces: `POST Downloads/SearchStart` body `SearchStartRequest { Key: string?, Again: bool }` → 200 `DownloadSearchStatusDto`, 400 se `Key` manca o è invalida; `GET Downloads/SearchStatus?key=` → 200 o 400. `public const string DownloadsSearchJobsFeature = "downloadsSearchJobs";`.

- [ ] **Step 1: test che falliscono:** `SearchStartReturnsTheStatus`, `SearchStartWithoutAKeyIsBadRequest`, `SearchStatusOfAnInvalidKeyIsBadRequest` in `DownloadsControllerTests`; in `InfoControllerTests` versione `"1.19.0"` e `downloadsSearchJobs` presente dove c'è `downloads` (e assente dove manca).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementa; aggiorna il commento di `Search` ("Ricerca dal vivo (fino a 2 minuti)" → aspetta il job; per le app 0.27).
- [ ] **Step 4:** tutta la suite del plugin: PASS.
- [ ] **Step 5:** commit `feat(plugin): SearchStart e SearchStatus, funzione downloadsSearchJobs, versione 1.19.0`.

### Task 4: API e modelli nell'app

**Files:**
- Modify: `app/lib/core/downloads/downloads_api.dart` (dopo `search`, riga 78-85)
- Modify: `app/lib/core/downloads/download_models.dart` (dopo `DownloadSearch`, riga 587)
- Modify: `app/lib/core/social/social_models.dart` (`PluginFeatures`, `SocialFeatures` con il campo nuovo e `none`)
- Modify: `app/lib/features/social/social_providers.dart:271`
- Modify: `app/test/support/download_fakes.dart` (`FakeDownloadsApi`)
- Test: `app/test/core/downloads/downloads_api_test.dart`, `app/test/core/downloads/download_models_test.dart`, il test di `social_providers` che controlla le funzioni

**Interfaces:**
- Produces:
  - `enum DownloadSearchJobState { running, done, missing, none }`
  - `class DownloadSearchStatus { final String key; final DownloadSearchJobState state; final DateTime? startedAt; final String service; final DownloadSearch? result; static DownloadSearchStatus? fromJson(Map<String, dynamic>) }`: null per uno `State` sconosciuto o `Done` senza `Result` valido.
  - `Future<DownloadSearchStatus> startSearch(String key, {bool again = false})` → `POST $_base/SearchStart` body `{'Key': key, 'Again': again}`.
  - `Future<DownloadSearchStatus> searchStatus(String key)` → `GET $_base/SearchStatus` query `{'key': key}`.
  - `PluginFeatures.downloadsSearchJobs = 'downloadsSearchJobs'`; `SocialFeatures.downloadsSearchJobs` (bool, default false).
  - `FakeDownloadsApi`: `startSearch`/`searchStatus` registrano le chiamate nel log esistente (`start movie:1 again`, `status movie:1`) e rispondono da una coda di `DownloadSearchStatus` (o lanciano un `DownloadsException` messo in coda).

- [ ] **Step 1: test che falliscono:** parsing di `Running` (con `StartedAt`), `Done` (con il `Result` di `testSearch`), `Missing`, `None`, `State` sconosciuto → null; le due chiamate API (metodo, path, body/query) con l'adapter finto di `downloads_api_test`; la funzione letta da `GET Info`.
- [ ] **Step 2:** `flutter test test/core/downloads`: FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** `flutter analyze` e i test toccati: PASS.
- [ ] **Step 5:** commit `feat(app): API e modelli della ricerca in background`.

### Task 5: controller con il polling

**Files:**
- Modify: `app/lib/features/downloads/download_search_controller.dart`
- Test: `app/test/features/downloads/download_search_controller_test.dart` (con `fake_async` per i 3 s)

**Interfaces:**
- Consumes: Task 4.
- Produces:
  - `typedef DownloadSearchRunning = ({DateTime startedAt, String service, bool reconnecting});`
  - `downloadSearchRunningProvider`: `NotifierProvider.autoDispose.family<…, DownloadSearchRunning?, String>`, tenuto vivo dal controller come `downloadGrabbingProvider`; null quando la ricerca non è in corso.
  - `static const pollInterval = Duration(seconds: 3);` e `static const maxPollFailures = 3;` in `DownloadSearchController`.
  - `Future<void> retry()`: riprende senza rilanciare (`startSearch(again: false)`).
  - `searchAgain()`: con la funzione `startSearch(again: true)`; senza, come oggi.

Regole: la funzione si legge da `socialAvailabilityProvider` (`SocialFeatures.downloadsSearchJobs`). `Done` → `AsyncData(result)` e running a null. `Missing` → errore `DownloadsException(DownloadsFailure.invalid)`, come il 400 di oggi. `None` durante il polling → `startSearch(again: false)`. Un `DownloadsException(network)` durante il polling mette `reconnecting: true` e si riprova al giro dopo; al terzo di fila → `AsyncError`. Smontando il provider il timer si annulla.

- [ ] **Step 1: test che falliscono** (con la funzione accesa):
  - `startsThenPollsUntilDone`: coda `running, running, done` → dopo 6 s lo stato è `AsyncData(testSearch)`; log `start movie:1`, `status movie:1`, `status movie:1`.
  - `exposesStartedAtAndServiceWhileRunning`.
  - `aFinishedErrorIsShownWithoutSearchingAgain`: `start` risponde `Done` con un `Result` che ha `error: 'Unreachable'` → `AsyncData` con quell'errore, nessuna `status`.
  - `aRestartedPluginStartsAgain`: `running`, poi `none` → la chiamata dopo è `start movie:1` (senza `again`).
  - `transientNetworkErrorsKeepPolling`: `running`, errore di rete, `done` → `AsyncData`, e `reconnecting` era true dopo l'errore.
  - `threeNetworkErrorsShowTheError`, poi `retry()` → `start movie:1` senza `again`.
  - `closingThePageStopsPolling`: dispose del container, `async.elapse(10 s)` → nessuna `status` nuova.
  - `searchAgainSendsAgain` → `start movie:1 again`.
  - `missingIsInvalid`.
  - Senza la funzione: `usesTheOldSearch` (log `search movie:1`, come i test di oggi).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** `flutter test test/features/downloads`: PASS (i test esistenti senza la funzione restano verdi).
- [ ] **Step 5:** commit `feat(app): la ricerca dei download chiede lo stato ogni 3 secondi`.

### Task 6: pagina e testi

**Files:**
- Modify: `app/lib/features/downloads/download_search_page.dart:151-160` (ramo `isLoading`) e il ramo d'errore
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb` (accanto a `downloadsSearchWaiting`)
- Test: `app/test/features/downloads/download_search_page_test.dart`

**Interfaces:**
- Consumes: `downloadSearchRunningProvider`, `retry()` (Task 5).

Testi (it / en):
- `downloadsSearchRunning(service, elapsed)`: "Ricerca su {service} in corso · {elapsed}" / "Searching {service} · {elapsed}"
- `downloadsSearchRunningHint`: "Le stagioni anime possono richiedere qualche minuto: puoi chiudere, i risultati restano pronti." / "Anime seasons can take a few minutes: you can close this, the results will be ready."
- `downloadsSearchReconnecting`: "Connessione persa, riprovo…" / "Connection lost, retrying…"
- `downloadsSearchRetry`: "Riprova" / "Retry"

Regole: con un `DownloadSearchRunning` a schermo `LinearProgressIndicator` indeterminata, il testo con il tempo (`m:ss`, minuti oltre 59 senza ore; da `clock.now()` di `package:clock`; negativo → `0:00`), aggiornato ogni secondo da un `Timer.periodic` del widget, la riga di aiuto in `WfColors.creamMuted`, e con `reconnecting` la riga "Connessione persa". Senza running (plugin vecchio, primo istante) resta la schermata di oggi. Sull'errore di rete del polling il pulsante è "Riprova" (`retry()`); sugli altri resta "Ricerca di nuovo".

- [ ] **Step 1: test che falliscono** (pompare a mano, niente `pumpAndSettle`): `showsTheBarAndTheElapsedTime` (`withClock` fermo, `startedAt` 2 min 15 s prima → "Ricerca su Sonarr in corso · 2:15"; dopo `pump(1 s)` → "2:16"); `aFutureStartedAtShowsZero` ("· 0:00"); `showsReconnecting`; `aPollingErrorOffersRetry` (tocco → `retry` nel log del fake).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter gen-l10n`, `flutter analyze`, `flutter test`: PASS.
- [ ] **Step 5:** commit `feat(app): barra e tempo che scorre durante la ricerca dei download`.

### Task 7: controllo finale e prova (coordinatore)

- [ ] Review di tutto il ramo (subagente revisore).
- [ ] Suite del plugin e dell'app per intero.
- [ ] Plugin 1.19.0 sul seedbox al posto del dll (`app-jellyfin stop`, copia, `app-jellyfin start`, attesa di "Healthy" e di `WonderFlix Watch Party "1.19.0" avviato`).
- [ ] Sito di prova: build web con `--base-href /wonderflix-prova/` e copia con tar (RELEASING.md, "Sito di prova").
- [ ] Prova io: la ricerca di "A Sign of Affection" S1 dal sito di prova arriva al risultato; poi la prova a mano dell'utente su iPhone.
