# "Serve te" spiegato e risolvibile — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ogni riga "Serve te" della scheda Download spiega cosa è successo e offre i pulsanti per risolverlo dall'app: tappabuchi, "Va bene, aspetto", import forzato, scarta e ricerca.

**Architecture:** il plugin tiene sulla `DownloadEntry` i dati nuovi (riassunto dell'ultima ricerca, tappabuchi, silenzio, release rifiutate, messaggio di blocco) e manda per ogni voce la lista ordinata delle azioni possibili. L'app compone la frase dai dati e disegna i pulsanti dalla lista, con il primo in evidenza nelle righe "Serve te". Quattro endpoint nuovi.

**Tech Stack:** .NET 9 (plugin Jellyfin 10.11, xUnit), Flutter 3.47.5 (Riverpod 3, Dio, ARB).

**Spec:** `docs/superpowers/specs/2026-10-31-wonderflix-serve-te-design.md`. La Spec T (`2026-10-28-wonderflix-download-automatici-design.md`) descrive il ciclo di oggi.

## Global Constraints

- Plugin 1.18.0 (`Jellyfin.Plugin.WonderFlixWatchParty.csproj` `<Version>` e `InfoControllerTests`); app 0.27.0 (`app/pubspec.yaml`).
- L'app nuova con il plugin 1.17.0: `Actions` assente o vuoto → righe come oggi ("Guarda" e, fuori da "Serve te", "Cerca ora").
- Il plugin non manda testi, tranne `BlockedMessage` (messaggio di Sonarr/Radarr così com'è).
- DTO: un campo nullable che deve esserci sempre ha `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]`.
- Chiamate lente (`GrabBest`): lato app `receiveTimeout: DownloadsApi.searchTimeout`; lato plugin il grab e l'import usano `CancellationToken.None`, non `RequestAborted`.
- Testi italiani e inglesi in `app/l10n/app_it.arb` e `app_en.arb`; dopo ogni modifica `flutter gen-l10n`.
- Commenti e doc nel codice in italiano, come il codice intorno. Commit in italiano, senza `closes`/`fixes`/`resolves` e senza trailer `Co-Authored-By`.
- Mai killare processi per nome immagine (`taskkill /IM`, `pkill`).
- Build di release dell'app: `flutter build windows --release --dart-define-from-file=config/wonderflix.json` (da `app/`).
- Comandi di controllo: plugin (da `plugin/`) `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`; app (da `app/`) `flutter gen-l10n`, `flutter analyze`, `flutter test`. In PowerShell aggiornare prima il PATH: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`.
- **Scostamento dalla spec §6 (mia scelta):** il pulsante consigliato non lo decide l'app. Il plugin mette l'azione consigliata **prima** nella lista `Actions` e l'app evidenzia `actions.first` solo nelle righe `needsYou`.

## Review Focus

1. **Voce salvata dal plugin 1.17.0** (senza i campi nuovi) letta dal 1.18.0: `Summary` null, `RefusedReleases` null, `Stopgap` null. Nessuna eccezione, e le azioni di `NothingFound` sono `[Pick, SearchNow, Snooze]`. Test in Task 5.
2. **Click doppio o voce cambiata nel frattempo:** "Importa comunque" o "Scarta" su una voce che il giro ha già spostato rispondono 409 `Changed`, e l'app rilegge mostrando "è cambiato qualcosa". Test in Task 4 (plugin) e Task 6 (API).
3. **`GrabBest` mentre il giro scarica lo stesso titolo:** risponde `Busy`, come `Grab`, e non fa due grab. Test in Task 4.
4. **Silenzio e titolo che poi scarica:** `Grabbed` toglie `Snoozed`, così un titolo silenziato che va in coda e fallisce torna a dare l'avviso. Test in Task 2.
5. **Tappabuchi per peso con lo stesso punteggio che Sonarr non importerebbe:** il grab parte con `ManualImportPending = true`, così il giro fa l'import a mano una volta. Test in Task 3.

---

### Task 1: dati della voce e regole pure

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadBook.cs` (classe `DownloadEntry` + nuova classe `DownloadSummary` + costanti `DownloadStopgaps`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadRule.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DownloadRuleTests.cs`

**Interfaces:**
- Produces:
  - `DownloadEntry`: `string? Stopgap` (`DownloadStopgaps.Score`/`Size`), `bool Snoozed`, `DownloadSummary? Summary`, `List<string>? RefusedReleases`, `string? DownloadId`, `string? BlockedMessage`. Doc in italiano su ognuno.
  - `public static class DownloadStopgaps { public const string Score = "Score"; public const string Size = "Size"; }`
  - `public sealed class DownloadSummary { int Found; int? BestScore; int MinScore; int TooSmall; int ArrRejected; string? TopRejection; bool StopgapAvailable; }` (proprietà get/set, serializzata nel libro).
  - `DownloadRule.ReleaseId(string guid, int indexerId) => $"{indexerId}|{guid}"`.
  - `DownloadRule.ChooseStopgap(RuleResult rule) -> (ArrRelease? Release, string? Kind)`.
  - `DownloadRule.StopgapKindOf(int score, long sizeBytes, int runtimeMinutes, bool isMovie, double minGbPerHour, int minScore) -> string?`.
  - `DownloadRule.Summarize(RuleResult rule, int found, int minScore) -> DownloadSummary`.

- [ ] **Step 1: scrivere i test che falliscono** in `DownloadRuleTests.cs`, con `DownloadTestData.Release(...)` e una `RuleInput` da 0,8 GB/ora, film da 100 minuti:
  - `AStopgapIsTheBestBelowMinimum`: candidati a 40 e 30, minimo 100 → `ChooseStopgap` dà il 40 con `Kind == "Score"`.
  - `AStopgapAmongTooSmallIsTheHeaviest`: nessun candidato, scartati `TooSmall` da 0,5 e 0,7 GB/ora con lo stesso punteggio, più uno rifiutato da Arr (`Rejections = ["Not English"]`) → sceglie lo 0,7 con `Kind == "Size"`. Il rifiutato da Arr non viene mai scelto, anche se ha il punteggio più alto.
  - `NoStopgapWithOnlyArrRejections`: solo rifiuti Arr → `(null, null)`.
  - `StopgapKindFollowsTheRules`: troppo piccolo → `"Size"` (anche se sotto il minimo); peso ok e punteggio < minimo → `"Score"`; tutto ok → `null`; con `runtimeMinutes` 0 usa i fallback 100/40 come `Choose`.
  - `TheSummaryCountsAndPicksTheCommonestRejection`: 5 release, due rifiutate `"Not English"`, una `"Quality not wanted"`, una `TooSmall`, una candidata a 40 con minimo 100 → `Found 5, BestScore 40, MinScore 100, TooSmall 1, ArrRejected 3, TopRejection "Not English", StopgapAvailable true`. A parità di conteggio vince il primo incontrato.

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter DownloadRuleTests`. Atteso: errori di compilazione per i membri che mancano.

- [ ] **Step 3: implementare in `DownloadRule.cs` e `DownloadBook.cs`.**
  - `ChooseStopgap`: se `rule.BelowMinScore` dà `(rule.Candidates[0], Score)`. Altrimenti prende i `rule.Rejected` con `Reason == "TooSmall"`, ordinati per punteggio decrescente, risoluzione decrescente, **peso decrescente**, poi seeders e guid come in `Choose`, e dà il primo con `Size`.
  - `StopgapKindOf`: usa `GbPerHour` e gli stessi fallback di durata di `Choose`.
  - `TopRejection` = il testo `Detail` più frequente tra i rifiuti `Reason == "Arr"`.

- [ ] **Step 4: eseguire i test e vederli passare** con lo stesso comando. Atteso: tutti verdi.

- [ ] **Step 5: commit** — `feat(plugin): dati e regole del tappabuchi e del riassunto di ricerca`

---

### Task 2: il giro, cioè riassunto, silenzio e release rifiutate

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.Search.cs` (`SearchItem`, `ToSearchItem`, `SearchOneAsync`, `GrabChoiceAsync`, `NothingChosen`, `Grabbed`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadSchedule.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DownloadServiceSearchTests.cs`

**Interfaces:**
- Consumes: Task 1 (`Summarize`, `ReleaseId`, campi della voce).
- Produces: `DownloadSchedule.SnoozedPace = TimeSpan.FromDays(7)`. `SearchItem` guadagna `IReadOnlySet<string> Refused` (dagli `entry.RefusedReleases`).

- [ ] **Step 1: scrivere i test che falliscono** in `DownloadServiceSearchTests.cs`, sullo stile di `BelowMinScoreNeedsYouAtOnce` e `AfterAWeekNothingNeedsYou`:
  - `NothingChosenKeepsASummary`: ricerca con una candidata a 40 (minimo 100) e una `TooSmall` → `entry.Summary` ha `Found 2, BestScore 40, TooSmall 1, StopgapAvailable true`.
  - `ASnoozedTitleStaysQuietWhenNothingIsFound`: voce `Waiting` con `Snoozed = true`, `Reason = NothingFound`, disponibile da 10 giorni, ricerca vuota → resta `Waiting` con `Reason NothingFound` e `NextSearchAt == now + 7 giorni`.
  - `ASnoozedTitleSpeaksAgainWhenSomethingLowIsFound`: come sopra, ma con una candidata sotto il minimo → `NeedsYou` / `BelowMinScore` e `Snoozed == false`.
  - `AGrabClearsSnoozeAndSummary`: voce silenziata con riassunto, la ricerca trova una scelta valida → `Snoozed == false`, `Summary == null`, `State == Downloading`.
  - `ARefusedReleaseIsRememberedAndSkipped`: il grab di A risponde 500 → `RefusedReleases` contiene `ReleaseId(A)`, `NextSearchAt == now + DownloadService.CycleInterval`. Al giro dopo, con A e B nei risultati, si scarica B.
  - `AtMostTwentyRefusedReleases`: con 20 rifiutate, una nuova toglie la più vecchia.

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando: `dotnet test ... --filter DownloadServiceSearchTests`. Atteso: falliscono i 6 test nuovi.

- [ ] **Step 3: implementare.**
  - In `SearchOneAsync`, prima di qualunque regola (anche `SeasonPackRule.ChoosePack`), si tolgono le release con `ReleaseId` in `item.Refused`.
  - Solo per film ed episodi, `NothingChosen(entry, result, minScore, found, now)` salva `entry.Summary = DownloadRule.Summarize(...)`, dove `found` = release con guid.
  - In `NothingChosen`: se `entry.Snoozed` e non `belowMinScore` → `Waiting`, `Reason = NothingFound`, `NextSearchAt = now + SnoozedPace`. Se `belowMinScore` → `Snoozed = false` e il percorso di oggi.
  - Nel `catch` 5xx di `GrabChoiceAsync`: aggiunge `ReleaseId` in coda a `RefusedReleases` (massimo 20, via le più vecchie) e mette `NextSearchAt = now + CycleInterval` al posto di `DownloadSchedule.Next`.
  - `Grabbed` mette `Snoozed = false` e `Summary = null`.

- [ ] **Step 4: eseguire i test e vederli passare**, poi l'intera suite dei download: `--filter Download`. Atteso: tutti verdi.

- [ ] **Step 5: commit** — `feat(plugin): riassunto della ricerca, silenzio e release rifiutate nel giro`

---

### Task 3: il ciclo di vita del tappabuchi

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.cs` (`OnImported`, `Apply` passo 4-5)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.Search.cs` (`SearchOneAsync` per gli upgrade, `GrabChoiceAsync`)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DownloadServiceCycleTests.cs`, `DownloadServiceSearchTests.cs`

**Interfaces:**
- Consumes: Task 1 (`StopgapKindOf`, `DownloadStopgaps`). `entry.Stopgap` lo scrive il grab dell'admin (Task 4); nei test si imposta a mano.
- Produces: `GrabChoiceAsync(SearchItem item, ArrRelease choice, ArrQualityProfile? profile, bool forceImport, CancellationToken)`. `SearchItem` guadagna `string? Stopgap`.

- [ ] **Step 1: scrivere i test che falliscono.**
  - Cycle: `AStopgapWatchesForUpgradesEvenAboveTarget`: voce con `Stopgap = Size`, `CurrentScore = 150` (obiettivo 150), file troppo piccolo, importata → `UpgradeWatch`, non rimossa.
  - Cycle: `AStopgapIsNotDroppedAfterThirtyDays`: `UpgradeWatch` con `Stopgap = Score` e `UpgradeUntil` passato → resta. La prossima ricerca è a 7 giorni (`DownloadSchedule.Next` dopo il trentesimo giorno).
  - Cycle: `AnImportThatMeetsTheRulesEndsTheStopgap`: tappabuchi per punteggio, importato un file da 120 (minimo 100, obiettivo 150) → `Stopgap == null`, `UpgradeWatch` con `UpgradeUntil == scelta + 30 giorni`.
  - Search: `AScoreStopgapStepsUpBelowTheMinimum`: tappabuchi `Score` a 40, release a 70 di peso giusto che Sonarr importerebbe → si scarica. Dopo l'import resta `Stopgap == Score`.
  - Search: `AScoreStopgapIgnoresAnEqualScore`: release a 40 → niente grab.
  - Search: `ASizeStopgapTakesAnEqualScoreAndForcesTheImport`: tappabuchi `Size` a 150, release della stessa qualità a 150 di peso giusto (`WouldImport` falso) → grab con `entry.ManualImportPending == true`.
  - Search: `ASizeStopgapNeverTakesATooSmallRelease`: unica release a 200 ma troppo piccola → niente grab.

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando: `--filter "DownloadServiceCycleTests|DownloadServiceSearchTests"`. Atteso: falliscono i 7 test nuovi.

- [ ] **Step 3: implementare.**
  - `OnImported`: prima di decidere ricalcola `entry.Stopgap` con `StopgapKindOf` sul file presente (`CurrentScore`, `CurrentSizeBytes`, `RuntimeMinutes`, `MinScore`/`MinGbPerHour` delle soglie), ma solo se la voce era già tappabuchi. Un tappabuchi non si toglie mai per obiettivo o per "accettato": va in `UpgradeWatch`. Il resto resta com'è.
  - `Apply` passo 4-5: la condizione `now >= entry.UpgradeUntil` vale solo con `entry.Stopgap is null`.
  - `SearchOneAsync`, upgrade di un tappabuchi: `Choose` con `input with { MinScore = int.MinValue }`. Accetta la scelta se:
    - `Score`: punteggio > attuale e `WouldImport`;
    - `Size`: punteggio ≥ attuale. Se non `WouldImport` → `forceImport: true`.
  - `GrabChoiceAsync` dopo `Grabbed` mette `entry.ManualImportPending = forceImport`. Gli upgrade che non sono tappabuchi restano come oggi (`IsUpgrade`).

- [ ] **Step 4: eseguire i test e vederli passare**, poi `--filter Download`. Atteso: tutti verdi.

- [ ] **Step 5: commit** — `feat(plugin): il tappabuchi cerca un file migliore senza limite di tempo`

---

### Task 4: le azioni dell'admin e gli endpoint

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.Admin.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.cs` (`Track`, `OnImportBlocked`: `DownloadId` e `BlockedMessage`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/GrabOutcome.cs` (dove sta l'enum; altrimenti accanto)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Api/DownloadsController.cs`
- Test: `DownloadServiceAdminTests.cs`, `DownloadsControllerTests.cs`, `DownloadServiceCycleTests.cs`

**Interfaces:**
- Consumes: Task 1 (`ChooseStopgap`, `ReleaseId`), Task 2 (`RefusedReleases`), Task 3 (`Stopgap`).
- Produces:
  - `GrabOutcome.NothingToGrab` (nuovo valore).
  - `Task<GrabOutcome> GrabBestAsync(string key, CancellationToken ct)`.
  - `bool Snooze(string key)` (falso se la voce non è `NeedsYou`/`NothingFound`).
  - `enum BlockedOutcome { Ok, Invalid, Changed, Failed, Unavailable }`.
  - `Task<(BlockedOutcome Outcome, string? Error)> ImportBlockedAsync(string key)`.
  - `Task<BlockedOutcome> DiscardBlockedAsync(string key)`.
  - Endpoint: `POST Downloads/GrabBest`, `Snooze`, `Import`, `Discard`, tutti con body `KeyRequest`.

- [ ] **Step 1: scrivere i test che falliscono.**
  - Cycle: `ABlockedImportKeepsTheDownloadAndSonarrsMessage`: coda `importBlocked` con `DownloadId "abc"` e `StatusMessages` `[{Messages:["Not an upgrade","Not an upgrade","Sample"]}]` → `entry.DownloadId == "abc"`, `entry.BlockedMessage == "Not an upgrade\nSample"` (stesso modo di `SpaceService.Lighten.cs`: distinti, al massimo 3). Un giro dopo, con il download non più bloccato → `BlockedMessage == null`.
  - Admin: `GrabBestTakesTheBestBelowMinimumAndMarksAStopgap`: voce `NeedsYou/BelowMinScore`, la ricerca dà 40 e 30 → grab del 40, `entry.Stopgap == Score`.
  - Admin: `GrabBestTakesTheHeaviestTooSmall` → `Stopgap == Size`.
  - Admin: `GrabBestSkipsRefusedReleases`: il 40 è in `RefusedReleases`, c'è un 30 → grab del 30.
  - Admin: `GrabBestWithNothingToTakeSaysSo` → `NothingToGrab`, nessun grab.
  - Admin: `GrabBestWhileTheCycleGrabsIsBusy`: chiave in `_grabbing` (stesso modo dei test di `Grab`) → `Busy`.
  - Admin: `SnoozeMovesNothingFoundToWaiting` → `Waiting`, `Snoozed`, `Reason NothingFound`, `NextSearchAt == now + 7 giorni`, `NeedsYouAlerts()` vuoto. `SnoozeRefusesOtherStates` → falso su `BelowMinScore`.
  - Admin: `ImportBlockedStartsTheManualImport` → `Ok`, la voce va in `Downloading` con `Reason` null. `ImportBlockedReportsNoFiles` → `(Failed, "NoFiles")`, la voce resta `NeedsYou`. `ImportBlockedOnAnotherStateIsChanged` → `Changed`.
  - Admin: `DiscardRemovesWithBlocklistAndSearchesAgain` → `RemoveFromQueueAsync(..., blocklist: true, removeFromClient: true)`, voce `Waiting` con `NextSearchAt == now`, nudge. `DiscardOfAnUpgradeGoesBackToUpgradeWatch`: con `PreviousScore` → `UpgradeWatch` con il file di prima.
  - Controller: le mappature `NothingToGrab` → 409 `{"Reason":"NothingToGrab"}`; `Snooze` falso → 400; `Changed` → 409 `Changed`; `Failed` → 502 con `Reason` = codice (`NoFiles`, oppure `ImportFailed` per gli altri); `Unavailable` → 503 `Unavailable`; ok → 204.

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando: `--filter "DownloadServiceAdminTests|DownloadsControllerTests|DownloadServiceCycleTests"`.

- [ ] **Step 3: implementare.**
  - `GrabBestAsync`: solo film ed episodi (stagione → `Invalid`). `RunSearchAsync` (nuova ricerca, che resta in `_lastSearch`) → `DownloadRule.ChooseStopgap` sulla regola calcolata sulle release **senza le rifiutate** → `GrabAsync(key, guid, indexerId, CancellationToken.None)` → se `Ok`, sotto lock, `entry.Stopgap = kind` e salva. La regola si ricalcola in `GrabBestAsync`: `ApplyRule` non è nel `AdminSearch`, bastano le sue `Releases` e la stessa `RuleInput` (salvarla in `AdminSearch` se serve).
  - `RemoveOldDownloadAsync` prende `bool blocklist = false` e lo passa a `RemoveFromQueueAsync`. `DiscardBlockedAsync` lo usa con `true`, poi `BackToUpgradeWatch` (se `PreviousScore` c'è) oppure `BackToWaiting`, salva e `Nudge()`.
  - `ImportBlockedAsync` richiede `NeedsYou` + `ImportBlocked` + `DownloadId`, altrimenti `Changed`. Chiama `ImportDownloadAsync(service, downloadId, CancellationToken.None)`; con esito null mette la voce in `Downloading` e `Nudge()`.
  - Nel controller, `GrabBest` riusa lo `switch` di `Grab` più `NothingToGrab`.

- [ ] **Step 4: eseguire i test e vederli passare**, poi tutta la suite del plugin. Atteso: tutti verdi (se falliscono `SubtitleServiceTests.AFailedDownloadIsFailed` o `ArrClientTests.ASlowSearchUsesTheSearchTimeout`, rilanciare: sono instabili).

- [ ] **Step 5: commit** — `feat(plugin): tappabuchi, silenzio, import e scarto dagli endpoint dei download`

---

### Task 5: le azioni nella panoramica e la versione 1.18.0

**Files:**
- Create: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadActions.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/DownloadsDtos.cs` (`DownloadItemDto` + nuovo `DownloadSummaryDto`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Downloads/DownloadService.Admin.cs` (`Overview`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` (1.18.0), `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoControllerTests.cs`
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DownloadActionsTests.cs` (nuovo), `DownloadServiceAdminTests.cs`, `DownloadBookTests.cs`

**Interfaces:**
- Consumes: i campi della voce dei Task 1-4.
- Produces:
  - `public static class DownloadActions { const string GrabBest="GrabBest", Pick="Pick", SearchNow="SearchNow", Snooze="Snooze", Import="Import", Discard="Discard"; static IReadOnlyList<string> For(DownloadEntry entry); }`
  - `DownloadItemDto` guadagna, in fondo: `IReadOnlyList<string> Actions`, `DownloadSummaryDto? Summary` (Never), `string? BlockedMessage` (Never), `bool Snoozed`.
  - `DownloadSummaryDto(int Found, int? BestScore /*Never*/, int MinScore, int TooSmall, int ArrRejected, string? TopRejection /*Never*/, bool StopgapAvailable)`, JSON PascalCase come gli altri.

- [ ] **Step 1: scrivere i test che falliscono** in `DownloadActionsTests.cs`: un `[Theory]` o un test per riga di questa tabella. L'ordine conta, perché il primo è il consigliato.

| Voce | `For` |
|---|---|
| `NeedsYou/BelowMinScore`, film | `GrabBest, Pick, SearchNow` |
| `NeedsYou/BelowMinScore`, stagione | `Pick, SearchNow` |
| `NeedsYou/NothingFound`, `Summary.StopgapAvailable`, episodio | `GrabBest, Pick, SearchNow, Snooze` |
| `NeedsYou/NothingFound`, `Summary.Found > 0`, niente tappabuchi | `Pick, SearchNow, Snooze` |
| `NeedsYou/NothingFound`, `Summary.Found == 0` | `Snooze, SearchNow` |
| `NeedsYou/NothingFound`, `Summary` null (voce del 1.17.0) | `Pick, SearchNow, Snooze` |
| `NeedsYou/ImportBlocked` con `DownloadId` | `Import, Discard` |
| `NeedsYou/ImportBlocked` senza `DownloadId` | `Discard` |
| `NeedsYou/GrabRefused` | `Pick, SearchNow` |
| `Waiting`, `Downloading`, `UpgradeWatch` | `Pick, SearchNow` |

  Poi: `DownloadBookTests.AnOldEntryLoadsWithoutTheNewFields` (il JSON di una voce senza i campi nuovi si carica: `Summary`/`RefusedReleases`/`Stopgap` null, `Snoozed` falso) e `DownloadServiceAdminTests.TheOverviewCarriesActionsAndSummary` (una voce `NothingFound` silenziata → DTO con `Snoozed true` e `Summary` valorizzato; JSON con `"Actions"`, `"Summary"`, `"BlockedMessage":null`).

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando: `--filter "DownloadActionsTests|DownloadBookTests|DownloadServiceAdminTests"`.

- [ ] **Step 3: implementare `DownloadActions.For` e il mapping in `Overview`**, poi portare la versione a 1.18.0 nel csproj e in `InfoControllerTests`.

- [ ] **Step 4: eseguire tutta la suite del plugin.** Atteso: tutti verdi.

- [ ] **Step 5: commit** — `feat(plugin): azioni e riassunto nella panoramica dei download, versione 1.18.0`

---

### Task 6: modelli e API dell'app

**Files:**
- Modify: `app/lib/core/downloads/download_models.dart`
- Modify: `app/lib/core/downloads/downloads_api.dart`
- Test: `app/test/core/downloads/download_models_test.dart`, `app/test/core/downloads/downloads_api_test.dart`

**Interfaces:**
- Consumes: il JSON del Task 5 e gli endpoint del Task 4.
- Produces:
  - `enum DownloadAction { grabBest('GrabBest'), pick('Pick'), searchNow('SearchNow'), snooze('Snooze'), import('Import'), discard('Discard'); }`. Il valore sconosciuto si **salta**, così un plugin più nuovo non rompe l'app.
  - `class DownloadSummary { found, bestScore (int?), minScore, tooSmall, arrRejected, topRejection (String?), stopgapAvailable }` con `fromJson`.
  - `DownloadItem` guadagna `List<DownloadAction> actions` (default `const []`), `DownloadSummary? summary`, `String? blockedMessage`, `bool snoozed` (default false).
  - `DownloadsApi.grabBest(String key)` (con `receiveTimeout: searchTimeout`), `snooze(String key)`, `importBlocked(String key)`, `discard(String key)`.
  - `DownloadsFailure` guadagna `nothingToGrab` (409 `NothingToGrab`), `changed` (409 `Changed`), `noFiles` (502 `NoFiles`), `importFailed` (502 `ImportFailed`).

- [ ] **Step 1: scrivere i test che falliscono.**
  - Modelli: un item con `"Actions":["GrabBest","Nuova","Pick"]` dà `[grabBest, pick]`. `Summary` e `BlockedMessage` si leggono. Un item senza i campi nuovi (JSON del 1.17.0) dà `actions` vuoto, `summary` null e `snoozed` falso.
  - API, sullo stile dei test esistenti: ogni metodo fa la POST giusta con `{'Key': key}`. `grabBest` passa `receiveTimeout == DownloadsApi.searchTimeout`. Le quattro mappature nuove degli errori, con `409 Busy` ancora `busy` e `409` senza motivo ancora `expired`.

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando (da `app/`): `flutter test test/core/downloads`.

- [ ] **Step 3: implementare.**

- [ ] **Step 4: eseguire `flutter test test/core/downloads` e `flutter analyze`.** Atteso: verdi, nessun problema.

- [ ] **Step 5: commit** — `feat(app): modelli e chiamate per le azioni di "Serve te"`

---

### Task 7: righe "Serve te" con spiegazione e pulsanti, versione 0.27.0

**Files:**
- Modify: `app/lib/features/downloads/download_rows.dart` (`DownloadItemRow`)
- Modify: `app/lib/features/downloads/download_labels.dart` (nuova `downloadExplanation`)
- Modify: `app/lib/features/downloads/downloads_tab.dart` (callback delle azioni, SnackBar, rilettura)
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb`, `app/pubspec.yaml` (0.27.0)
- Test: `app/test/features/downloads/download_labels_test.dart`, `app/test/features/downloads/downloads_tab_test.dart`

**Interfaces:**
- Consumes: Task 6.
- Produces: `String downloadExplanation(AppLocalizations l, DownloadItem item, String service)` in `download_labels.dart`. Restituisce vuoto quando non c'è niente da spiegare. `service` è `'Radarr'` per i film, altrimenti `'Sonarr'`.
- `DownloadItemRow` prende `Future<void> Function(DownloadAction) onAction` al posto di `onWatch`/`onSearchNow`. Con `item.actions` vuoto mostra i pulsanti di oggi (fallback per il plugin 1.17.0).

**Testi (it / en).** I placeholder sono interi o stringhe, come negli ARB di oggi:

| Chiave | Italiano | Inglese |
|---|---|---|
| `downloadsExplainLowScore` | `{found, plural, =1{1 file trovato} other{{found} file trovati}}, il migliore ha punteggio {best} (minimo {min}). Puoi scaricarlo intanto: appena arriva un file migliore lo sostituisco.` | `{found, plural, =1{1 file found} other{{found} files found}}, the best scores {best} (minimum {min}). You can download it for now: as soon as a better file shows up I'll replace it.` |
| `downloadsExplainAllRejected` | `{found, plural, =1{1 file trovato, scartato} other{{found} file trovati, tutti scartati}}: {parts}.` | `{found, plural, =1{1 file found, rejected} other{{found} files found, all rejected}}: {parts}.` |
| `downloadsExplainTooSmall` | `{count, plural, =1{1 troppo piccolo} other{{count} troppo piccoli}}` | `{count} too small` |
| `downloadsExplainArrRejected` | `{count, plural, =1{1 rifiutato da {service}} other{{count} rifiutati da {service}}}` | `{count} rejected by {service}` |
| `downloadsExplainStopgapHint` | `Il più grande tra i piccoli va bene come tappabuchi.` | `The largest of the small ones will do for now.` |
| `downloadsExplainNoResults` | `Nessun risultato sugli indexer. Spesso succede perché non è ancora uscito in digitale: continuo a cercare.` | `No results on the indexers. Often it isn't out digitally yet: I'll keep searching.` |
| `downloadsExplainBlocked` | `Il file è scaricato ma {service} non lo importa.` | `The file is downloaded but {service} won't import it.` |
| `downloadsExplainBlockedWhy` | `Motivo di {service}:` | `{service} says:` |
| `downloadsExplainRefused` | `qBittorrent ha rifiutato il file scelto (di solito perché c'è già). Al prossimo giro provo il successivo della lista, oppure scegline uno tu.` | `qBittorrent refused the chosen file (usually because it's already there). Next round I'll try the next one on the list, or pick one yourself.` |
| `downloadsActionGrabBest` | `Scarica il migliore intanto` | `Download the best for now` |
| `downloadsActionGrabBestBusy` | `Cerco e scarico…` | `Searching and downloading…` |
| `downloadsActionPick` | `Scegli tu` | `Pick yourself` |
| `downloadsActionPickOther` | `Scegli un altro file` | `Pick another file` |
| `downloadsActionSnooze` | `Va bene, aspetto` | `OK, I'll wait` |
| `downloadsActionImport` | `Importa comunque` | `Import anyway` |
| `downloadsActionDiscard` | `Scarta e cerca un altro` | `Discard and find another` |
| `downloadsSnoozedTag` | `senza avvisi` | `no alerts` |
| `downloadsActionDone` | `Fatto` | `Done` |
| `downloadsFailureNothingToGrab` | `Non c'è più niente da scaricare: ricarico` | `Nothing left to download: reloading` |
| `downloadsFailureChanged` | `È cambiato qualcosa nel frattempo: ricarico` | `Something changed in the meantime: reloading` |
| `downloadsFailureNoFiles` | `Nel download non c'è un file da importare` | `There's no file to import in the download` |
| `downloadsFailureImportFailed` | `Import non riuscito` | `Import failed` |

`TopRejection`, quando c'è, va tra parentesi dopo "rifiutati da {service}" così com'è. Con `BelowMinScore` e `bestScore` null si usa solo lo stato.

- [ ] **Step 1: scrivere i test che falliscono.**
  - `download_labels_test.dart`, `downloadExplanation` in italiano:
    - `BelowMinScore` con summary `found 6, best 40, min 100` → testo `downloadsExplainLowScore`.
    - `NothingFound` con `found 14, tooSmall 9, arrRejected 5, topRejection "Not English", stopgapAvailable` → contiene `9 troppo piccoli`, `5 rifiutati da Radarr (Not English)` e l'hint.
    - `found 0` → `downloadsExplainNoResults`.
    - `ImportBlocked` → `downloadsExplainBlocked` con `Sonarr`.
    - `GrabRefused` → `downloadsExplainRefused`.
    - `Waiting` → vuoto.
  - `downloads_tab_test.dart`, sullo stile dei test esistenti (API finta):
    - riga `needsYou` con azioni `[grabBest, pick, searchNow]` → tre pulsanti nell'ordine, il primo `FilledButton` (evidenziato), gli altri come oggi;
    - tap su "Scarica il migliore intanto" → chiama `grabBest(key)`, poi rilegge la panoramica;
    - errore `nothingToGrab` → SnackBar `downloadsFailureNothingToGrab` e rilettura;
    - riga `ImportBlocked` con `blockedMessage` → mostra il messaggio e i pulsanti Importa/Scarta, senza "Cerca ora";
    - `GrabRefused` → l'azione `pick` si chiama `downloadsActionPickOther`;
    - riga `Waiting` con `snoozed` → etichetta `senza avvisi`;
    - item senza `actions` (plugin vecchio) → "Guarda" e "Cerca ora" come oggi, e in `needsYou` solo "Guarda".

- [ ] **Step 2: eseguire i test e vederli fallire.** Comando: `flutter gen-l10n` poi `flutter test test/features/downloads`.

- [ ] **Step 3: implementare.**
  - La frase va sotto le righe di oggi, colore `WfColors.cream`, 13 px.
  - `blockedMessage` va sotto in monospazio su `WfColors.surfaceHigh`, come nel mockup.
  - Il pulsante evidenziato è la variante piena di `AdminActionButton`: se non esiste, aggiungere un parametro `primary` che usa `FilledButton` con le stesse dimensioni.
  - `pick` apre `_open(key, title)`.
  - Le azioni passano da un unico `_act(DownloadAction, DownloadItem)` in `downloads_tab.dart` che chiama l'API, mostra lo SnackBar (errore con `downloadsFailureLabel`, esteso alle quattro voci nuove; successo con `downloadsActionDone` solo per snooze/import/discard/grabBest) e poi `_reload()`.
  - Mentre `grabBest` lavora, il suo pulsante mostra `downloadsActionGrabBestBusy`.
  - Portare `pubspec.yaml` a 0.27.0.

- [ ] **Step 4: eseguire `flutter gen-l10n`, `flutter analyze`, `flutter test`.** Atteso: tutto verde. Se cambiano solo le terminazioni di riga di `windows/flutter/generated_plugin*`, ripristinarli con `git checkout --`.

- [ ] **Step 5: commit** — `feat(app): righe "Serve te" con spiegazione e pulsanti, versione 0.27.0`

---

## Dopo i task

Revisione finale di tutto il branch, poi la build di release (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`) per il test a mano dell'admin. Prima del test a mano il plugin va copiato sul seedbox (`app-jellyfin stop`, copia della dll, `app-jellyfin start`). Merge su `main` solo dopo l'ok dell'admin.
