# WonderFlix — Piano 24a: segnalazioni e sottotitoli, plugin 1.12.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec R nel plugin 1.12.0:
- l'archivio delle segnalazioni `reports.json` (solo le aperte), con gli endpoint per tutti (`POST Reports`, `GET Reports/Mine`) e per gli admin (`GET Reports`, `POST Reports/{id}/Resolve`);
- due voci nuove nella cassetta: `ReportPending` agli admin e `ReportResolved` a chi ha segnalato;
- cercare, scaricare e caricare sottotitoli lato server, per gli admin e per chi ha la spunta sottotitoli di Jellyfin;
- la funzione `reports` in `Info`, la versione 1.12.0 e una build di prova sul server.

L'app arriva nei piani 24b e 24c: si appoggia ai JSON di "Global Constraints", quindi **i nomi delle proprietà JSON non si cambiano**.

**Architecture:** la logica sta in `Hub/` e non conosce Jellyfin:
- `ReportBook` (in memoria), `ReportStore` (il file) e `ReportService` (regole, lock, notifiche, pulizia), sul modello di `RatingBook`/`RatingStore`/`RatingService`;
- `SubtitleService` (permessi e validazione).

Le domande a Jellyfin stanno dietro due interfacce:
- `IReportLibrary`, con l'adattatore `Server/JellyfinReportLibrary`;
- `ISubtitleTools`, con l'adattatore `Server/JellyfinSubtitleTools`, che usa `ISubtitleManager` e `IProviderManager`.

`InboxService` impara le voci nuove. `ReportsController` e `SubtitlesController` espongono gli endpoint; `ReportsHostedService` pulisce l'archivio ogni 5 minuti.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md` (§3, §5, §6, §8, §10, §11.1, §12, §13).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 8):
1. **"Già chiusa" è un 409, non un 404:** `POST Reports/{id}/Resolve` su una segnalazione che non c'è più → 409 `{"Reason":"Closed"}`. Il plugin non risponde mai 404, come per i voti: gli id sono stringhe senza vincoli di rotta, e un id non valido → 400.
2. **Le voci della cassetta riusano i campi che esistono già:**
   - `FromName` = chi segnala;
   - `Title` = nome del film o della serie;
   - `ImageItemId` = il film o la serie da aprire (fa anche da locandina);
   - `ItemId` = il titolo segnalato (film, serie, stagione o episodio);
   - `Text` = la nota della segnalazione (`ReportPending`) o la nota dell'admin (`ReportResolved`).
   I campi nuovi sono solo `ReportId`, `ReportType`, `Outcome`, `ItemType`, `SeasonNumber`, `EpisodeNumber`. Il livello ("S2 E3", "Stagione 2") lo compone l'app nella sua lingua, quindi il plugin non scrive testi in italiano.
3. **`ReportPending` contiene anche la nota** (`Text`): l'admin la vede comunque nel riquadro.
4. **Forma di una segnalazione nelle risposte (`ReportDto`):** `Id`, `Type`, `Note`?, `CreatedAt`, `UpdatedAt`, `UserId`, `UserName`, `ItemId`, `ItemType`, `ItemName`, `TitleId`, `TitleName`, `SeasonNumber`?, `EpisodeNumber`?.
   - `TitleType` della spec non serve: è `Movie` se `ItemType` è `Movie`, altrimenti `Series`. `SeriesName` diventa `TitleName`, che vale anche per i film.
   - I nomi si leggono dalla libreria a ogni risposta: dopo un'identifica si vede il nome nuovo.
   - Un titolo che non c'è più ha `ItemName`/`TitleName` vuoti, `ItemType` vuoto e `TitleId` = `ItemId`.
5. **Stessa forma per `GET Reports/Mine`**, ma con le sole segnalazioni di chi chiama: `{"Items":[…]}`.
6. **Gli admin che ricevono `ReportPending`:** gli utenti di `IUserDirectory.GetUsers()` con `IsAdmin` e `Enabled`, tranne chi segnala.
7. **Il permesso sottotitoli** si legge a ogni chiamata da `IUserDirectory`. `UserRef` prende un campo nuovo, facoltativo e in fondo: `bool CanManageSubtitles = false`. `JellyfinUserDirectory` lo legge da `PermissionKind.EnableSubtitleManagement`. Così un permesso tolto vale subito.
8. **Risultato dei sottotitoli a parte:** un enum `SubtitleStatus { Ok, Forbidden, Invalid, Failed }`. `HubStatus` resta com'è, perché altri `switch` lo usano. `Failed` → 502 `{"Reason":"DownloadFailed"}` oppure `{"Reason":"UploadFailed"}`.
9. **Il risultato di una ricerca** si appiattisce per l'app (`RemoteSubtitleDto`): i booleani di Jellyfin, che possono essere null, diventano `false`, e `AiTranslated || MachineTranslated` diventa `MachineTranslated`.
10. **Lingue:** tre lettere ASCII, e il plugin le porta in minuscolo (`ita`), sia per cercare sia per caricare. Altrimenti 400.
11. **Upload:** `Data` in base64 standard, al massimo 2 MiB (2 097 152 byte) decodificati; `Format` fra `srt`, `ass`, `ssa`, `vtt`, `sub`, senza badare alle maiuscole. Un errore di Jellyfin durante il salvataggio → 502 `UploadFailed`.
12. **Ordine:** `GET Reports` e `GET Reports/Mine` dalla `CreatedAt` più recente.
13. **Doppione** (stesso utente, titolo e tipo con una segnalazione aperta): `Note` nuova (anche vuota, che toglie la vecchia), `UpdatedAt` aggiornato, nessun avviso. La risposta è 200 con la segnalazione, come per una nuova.
14. **Pulizia:** toglie le segnalazioni di utenti e titoli che non esistono più, e poi le loro `ReportPending`. Nessuna `ReportResolved`. Come per i voti, durante una scansione o con un errore della libreria i titoli non si toccano.
15. **La chiave API** non ha un utente:
    - `POST Reports` e `GET Reports/Mine` rispondono 400;
    - gli endpoint dei sottotitoli rispondono 403;
    - `GET Reports` e Resolve funzionano, e chi chiude risulta "chiave API" nel log.

## Global Constraints

- Plugin **1.12.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9. Ogni membro di Jellyfin usato deve esistere nella 10.11.0.
- **Endpoint** sotto `/WonderFlixWatchParty`, con `[Authorize]` sulla classe:
  - `ReportsController`:
    - `POST Reports`, `GET Reports/Mine?itemId=` per ogni utente;
    - `GET Reports`, `POST Reports/{reportId}/Resolve` con `[Authorize(Policy = Policies.RequiresElevation)]` sul metodo;
  - `SubtitlesController`: `GET Subtitles/{itemId}/Search?language=&perfectMatch=`, `POST Subtitles/{itemId}/Download`, `POST Subtitles/{itemId}/Upload`. Il permesso lo controlla `SubtitleService`.
- **Mai 404.** Gli errori con corpo hanno `{"Reason": "…"}`:
  - `ReportReasons`: `LimitReached`, `Closed`;
  - `SubtitleReasons`: `DownloadFailed`, `UploadFailed`.
- **Valori:**
  - `ReportService.MaxOpenPerUser = 20`;
  - `ReportService.MaxNoteLength = 500` (punti di codice, dopo `RecommendationService.CleanMessage`), vale sia per la nota della segnalazione sia per quella di chiusura;
  - `SubtitleService.MaxUploadBytes = 2 * 1024 * 1024`;
  - `SubtitleService.UploadFormats = ["srt", "ass", "ssa", "vtt", "sub"]`;
  - pulizia ogni 5 minuti (`ReportsHostedService.StoreInterval`).
- **Tipi:**
  - `ReportTypes`: `Subtitles`, `Metadata`, `AudioVideo`, `Other`;
  - `ReportOutcomes`: `Fixed`, `CannotFix`;
  - `ItemType`: `Movie`, `Series`, `Season`, `Episode`.
- **JSON** (PascalCase, come il resto del plugin; `?` = assente se null):
  - `reports.json`: `{"Version":1,"Reports":[{"Id","UserId","ItemId","Type","Note"?,"CreatedAt","UpdatedAt"}]}`, id in formato `"N"`;
  - corpi:
    - `POST Reports`: `{"ItemId","Type","Note"?}`;
    - `Resolve`: `{"Outcome","Note"?}`;
    - `Download`: `{"SubtitleId"}`;
    - `Upload`: `{"Language","Format","IsForced","IsHearingImpaired","Data"}`;
  - `ReportDto`: vedi decisione 4. `ReportListDto`: `{"Items":[ReportDto…]}`. `POST Reports` risponde con un `ReportDto`; Resolve con 204;
  - `RemoteSubtitleDto`: `Id`, `ProviderName`, `Name`, `Language`, `Format`, `CommunityRating`?, `DownloadCount`?, `IsHashMatch`, `HearingImpaired`, `Forced`, `MachineTranslated`. La ricerca risponde con un array;
  - `InboxEntry`, campi nuovi: `ReportId`, `ReportType`, `Outcome`, `ItemType`, `SeasonNumber`, `EpisodeNumber` (tutti `WhenWritingNull`). Tipi nuovi: `InboxEntryTypes.ReportPending = "ReportPending"`, `InboxEntryTypes.ReportResolved = "ReportResolved"`.
- **`Info`:** `Version` "1.12.0", `Protocol` 1, `Features` con `"reports"` dopo `"ratings"`.
- **Id e date:** id di Jellyfin in formato `"N"`; date ISO-8601 UTC (`TimeProvider`, mai `DateTimeOffset.UtcNow`).
- **Log:** **mai note, nomi, titoli, contenuto dei sottotitoli o percorsi**, solo id e numeri.
  - `Debug`: segnalazione creata o aggiornata, ricerche e download;
  - `Information`: chiusura, con `AdminCaller.Describe`;
  - `Warning`: file illeggibile, errori di scrittura, errori della libreria, download o upload falliti (con l'eccezione, l'id dell'item e il provider).
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.

## Review Focus

1. **Due admin che chiudono la stessa segnalazione insieme:** il secondo riceve 409 `Closed`, e chi ha segnalato riceve **una** sola `ReportResolved`. Test: Task 3 (`ASecondResolveIsClosedAndNotifiesOnce`).
2. **L'admin che segnala e poi chiude da solo:** non riceve la propria `ReportPending` né una `ReportResolved`; gli altri admin la ricevono e poi la perdono. Test: Task 3 (`AnAdminReportingHimselfGetsNoEntries`).
3. **Admin disabilitati e non admin:** non ricevono `ReportPending`; chi ha solo la spunta sottotitoli neanche (decisione 2 della spec). Test: Task 3 (`PendingGoesToEnabledAdminsOnly`).
4. **Note con a capo, tab ed emoji:** gli a capo diventano spazi, e 500 emoji valgono 500 (punti di codice, non unità UTF-16); 501 → 400. Test: Task 2 (`NotesAreCleanedAndCountedInCodePoints`).
5. **Un problema passeggero durante la pulizia:** una scansione della libreria o un errore di Jellyfin non tolgono segnalazioni, e un errore del disco non annulla una segnalazione in memoria. Test: Task 2 (`CleanupKeepsReportsDuringAScanOrALibraryError`, `ADiskErrorKeepsTheReportInMemory`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-24a`): fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.12.0`.
- **Test** (in `jellyfin-plugin-watch-party`):
  - un gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj ha `TreatWarningsAsErrors`), poi `dotnet build-server shutdown`;
  - la base di partenza è di **1042** test verdi (verificato il 2026-10-21 su `main` `4d65303`).
- **Formattazione:** ogni file tiene le sue terminazioni di riga (working copy CRLF, indice LF; i file nuovi vanno bene con LF). UTF-8 con gli strumenti di modifica dei file, mai `Set-Content`/`Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese;
  - durate e limiti come costanti nominate e commentate; `TimeProvider`;
  - DTO `record` con `[property: JsonPropertyName("…")]` e `JsonIgnore(WhenWritingNull)` per i campi facoltativi; classi con `[JsonPropertyName]` per i corpi delle richieste;
  - `Lock` di .NET 9; id `"N"`.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un'API di Jellyfin con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo; preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-21 sul codice di `main` (`4d65303`) e sul sorgente di Jellyfin al tag `v10.11.9`.

**Plugin** (`main`)
- **Modello dell'archivio:** `RatingStore`/`RatingBook`/`RatingService`:
  - `Load()` con `.bad`; `Save()` con `.tmp` e `Flush(flushToDisk: true)`;
  - `Book` pigro sotto `_lock`;
  - `Persist()` con un `Warning` per `IOException`/`UnauthorizedAccessException`.
  `RecommendationService.CleanMessage(string?)` è `internal static`: toglie caratteri di controllo e spazi ai bordi e restituisce null se resta vuoto. Si riusa.
- **`InboxService`:**
  - voci sotto `_lock`, `Persist()`, poi `NotifyAsync(userIds)` (avviso `InboxChanged` alle sessioni WonderFlix degli utenti);
  - i metodi "Add…" non lanciano: un errore finisce in un `Warning`;
  - `InboxBook` ha `Add`, `Remove(userId, entryId)`, `RemoveType`, e il dizionario privato `_users` con `UserInbox.Entries`;
  - `MaxAge` è 30 giorni (la card della dashboard copre le segnalazioni più vecchie).
- **`InboxEntry`** (`Protocol/InboxDtos.cs`) è una classe mutabile con `Copy()`. Ha già `FromName`, `Title`, `ImageItemId`, `ItemId` e `Text`, tutti `WhenWritingNull`.
- **Utenti:** `UserRef(Guid Id, string Name, bool Enabled, bool CanJoinParties, bool IsAdmin = false)`. `JellyfinUserDirectory.ToRef` usa `user.HasPermission(PermissionKind.…)`. Nei test `FakeServer.AddUser(name, enabled, canJoinParties, isAdmin)`, e alcuni test costruiscono `new UserRef(...)` con argomenti per posizione: il campo nuovo va **in fondo e facoltativo**.
- **Controller:**
  - `RatingsAdminController` mette `[Authorize]` sulla classe e `RequiresElevation` sui metodi;
  - chi chiama si ricava con `(await authorizationContext.GetAuthorizationInfo(HttpContext)).UserId`;
  - `HubStatus` (`Ok`, `Forbidden`, `Invalid`, `RateLimited`, `Conflict`) e `HubResult<T>` stanno in `Hub/PartyHub.cs`.
- **Montaggio:**
  - `WatchPartyProtocol.Features` finisce con `"ratings"`;
  - `ServiceRegistrationTests` conta **7** servizi in background;
  - `InfoControllerTests` controlla `"1.11.0"` e le funzioni;
  - il csproj ha `<Version>1.11.0</Version>`.
- **Test:**
  - `FakeServer` implementa le interfacce di `Hub/`: `Users`, `AddUser`, `AddSession(id, user)`, `Unseen`, `LibraryFails`, `ScanRunning`, `Sent`, `SentTo`;
  - `TestInbox.Create(server, folder, time)`; `TempFolder` (con `RatingsFile` come modello);
  - `InterfaceStub<T>` (`Handlers["Nome"]`, `Calls`), `RecordingLogger<T>.Entries`, `FakeAuthorizationContext`, `FakeTimeProvider`;
  - `RatingsHostedServiceTests` è il modello del servizio in background.

**Jellyfin 10.11.9** (spec §12)
- **`ISubtitleManager`** (`MediaBrowser.Controller.Subtitles`):
  - `Task<RemoteSubtitleInfo[]> SearchSubtitles(Video video, string language, bool? isPerfectMatch, bool isAutomated, CancellationToken)`. Restituisce un array vuoto per tipi diversi da `Movie`/`Episode` o video non `VideoFile`;
  - `Task DownloadSubtitles(Video video, string subtitleId, CancellationToken)`;
  - `Task UploadSubtitle(Video video, SubtitleResponse response)`.
- **`SubtitleManager.DownloadSubtitles` rilancia l'errore** quando il provider fallisce (anche `RateLimitExceededException`). Il 204 sempre di Jellyfin viene da `SubtitleController`, che inghiotte l'eccezione. Quindi il plugin, chiamando il manager, sa che il download è fallito: decisione 8.
- **`UploadSubtitle`** lancia `ArgumentException` per un formato che Jellyfin non ammette, cioè non in `NamingOptions.SubtitleFileExtensions`. Salva `<nome del video>.<lingua>[.forced][.sdh].<formato>` accanto al video (se la libreria salva i sottotitoli con i media) e nella cartella dei metadati.
- **`SubtitleController`**, dopo download e upload: `_providerManager.QueueRefresh(item.Id, new MetadataRefreshOptions(new DirectoryService(_fileSystem)), RefreshPriority.High)`. Si copia identico.
- **`SubtitleResponse`** (`MediaBrowser.Model.Providers`): `Language`, `Format`, `IsForced`, `IsHearingImpaired`, `Stream`.
- **`PermissionKind.EnableSubtitleManagement`** = 22 esiste.
- **`DELETE /Videos/{id}/Subtitles/{index}`** è `RequiresElevation`: lo usa l'app direttamente (piano 24b).

## File

| File | Responsabilità |
|---|---|
| `Protocol/ReportDtos.cs` | tipi, esiti, motivi, `ReportDto`, `ReportListDto`, `ReportErrorDto`, corpi delle richieste |
| `Protocol/SubtitleDtos.cs` | `RemoteSubtitleDto`, `SubtitleReasons`, `SubtitleErrorDto`, corpi di Download e Upload |
| `Hub/ReportFile.cs`, `Hub/ReportBook.cs`, `Hub/ReportStore.cs` | `reports.json`: contenuto, segnalazioni in memoria, lettura e scrittura |
| `Hub/IReportLibrary.cs` | `ReportedItem` e la domanda alla libreria |
| `Hub/ReportService.cs` | creazione, elenchi, chiusura, notifiche, pulizia |
| `Hub/ISubtitleTools.cs`, `Hub/SubtitleService.cs` | sottotitoli: interfaccia verso Jellyfin, permessi e validazione |
| `Api/ReportsController.cs`, `Api/SubtitlesController.cs` | endpoint |
| `Server/JellyfinReportLibrary.cs`, `Server/JellyfinSubtitleTools.cs` | le domande a Jellyfin |
| `ReportsHostedService.cs` | la pulizia ogni 5 minuti |
| `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs`, `Hub/IUserDirectory.cs`, `Server/JellyfinUserDirectory.cs`, `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `Plugin.cs`, `../meta.template.json`, `../README.md` (modifiche) | cassetta, permesso, montaggio, versione, documentazione |

I percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test, scritti `Tests/…`), se non è detto altro.

---

## Gruppo A — segnalazioni

### Task 1: DTO e archivio delle segnalazioni

**Files:**
- Create: `Protocol/ReportDtos.cs`, `Hub/ReportFile.cs`, `Hub/ReportBook.cs`, `Hub/ReportStore.cs`
- Modify (test): `Tests/TempFolder.cs` (`ReportsFile`, accanto a `RatingsFile`)
- Test: `Tests/ReportBookTests.cs`, `Tests/ReportStoreTests.cs`

**Interfaces:**
- Produces:
  - `Protocol/ReportDtos.cs`:
    - `ReportTypes` (`Subtitles`, `Metadata`, `AudioVideo`, `Other`, più `static bool IsValid(string?)`), `ReportOutcomes` (`Fixed`, `CannotFix`, più `IsValid`), `ReportReasons` (`LimitReached`, `Closed`): classi statiche di `const string`, come `RatingReasons`;
    - `ReportDto(string Id, string Type, string? Note, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, string UserId, string UserName, string ItemId, string ItemType, string ItemName, string TitleId, string TitleName, int? SeasonNumber, int? EpisodeNumber)`;
    - `ReportListDto(IReadOnlyList<ReportDto> Items)`, `ReportErrorDto(string Reason)`;
    - corpi: `CreateReportRequest { string? ItemId; string? Type; string? Note }`, `ResolveReportRequest { string? Outcome; string? Note }`.
    - Ogni proprietà ha il nome JSON uguale al nome C#; quelle con `?` hanno `JsonIgnore(WhenWritingNull)`.
  - `StoredReport(Guid Id, Guid UserId, Guid ItemId, string Type, string? Note, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)` (in `ReportBook.cs`).
  - `ReportBook`:
    - `StoredReport? Get(Guid reportId)`;
    - `StoredReport? FindOpen(Guid userId, Guid itemId, string type)`;
    - `int CountOpen(Guid userId)`;
    - `void Add(StoredReport report)`;
    - `StoredReport UpdateNote(Guid reportId, string? note, DateTimeOffset now)` (chiamata solo con un id che c'è);
    - `bool Remove(Guid reportId)`;
    - `IReadOnlyList<StoredReport> All()` e `IReadOnlyList<StoredReport> ForUser(Guid userId, Guid itemId)`, tutte dalla `CreatedAt` più recente;
    - `IReadOnlyList<StoredReport> Prune(Func<Guid, bool> userExists, Func<Guid, bool> itemExists)`, che restituisce le tolte;
    - `static ReportBook FromFile(ReportFile)`, con `FormatException` per un id non valido, un `Type` non in `ReportTypes` o una voce null;
    - `ReportFile ToFile()`.
  - `ReportFile` (`Version`, `Reports: List<ReportFileEntry?>?`), `ReportFileEntry` (`Id`, `UserId`, `ItemId`, `Type`, `Note` con `WhenWritingNull`, `CreatedAt`, `UpdatedAt`).
  - `ReportStore(string filePath, ILogger<ReportStore> logger)`: `FileName = "reports.json"`, `DefaultPath(IApplicationPaths)`, `FilePath`, `ReportBook Load()`, `void Save(ReportBook)`. Lo stesso codice di `RatingStore`, con il `Warning` "Segnalazioni illeggibili…".

- [ ] **Step 1: test che falliscono**

`Tests/ReportBookTests.cs` (date `T0 = 2026-10-21 20:00 UTC`):

```csharp
[Fact]
public void FindOpenMatchesUserItemAndType()
{
    var book = new ReportBook();
    var report = Report(_mario, _episode, ReportTypes.Subtitles, T0);
    book.Add(report);
    Assert.Equal(report, book.FindOpen(_mario, _episode, ReportTypes.Subtitles));
    Assert.Null(book.FindOpen(_mario, _episode, ReportTypes.Metadata));
    Assert.Null(book.FindOpen(_luigi, _episode, ReportTypes.Subtitles));
    Assert.Equal(1, book.CountOpen(_mario));
    Assert.Equal(0, book.CountOpen(_luigi));
}

[Fact]
public void UpdateNoteKeepsCreatedAt()
{
    var book = new ReportBook();
    var report = Report(_mario, _episode, ReportTypes.Subtitles, T0) with { Note = "vecchia" };
    book.Add(report);
    var updated = book.UpdateNote(report.Id, null, T0.AddHours(1));
    Assert.Equal(report with { Note = null, UpdatedAt = T0.AddHours(1) }, updated);
    Assert.Equal(updated, book.Get(report.Id));
}

[Fact]
public void ListsAreNewestFirst()
{
    // tre segnalazioni a T0, T0+1h, T0+2h (la seconda di Luigi): All() le dà dalla più recente;
    // ForUser(mario, episodio) solo quelle di Mario su quell'episodio.
}

[Fact]
public void PruneReturnsTheRemovedReports()
{
    // Mario sull'episodio, Luigi sull'episodio, Mario sul film; Luigi non c'è più, il film neanche.
    var removed = book.Prune(user => user != _luigi, item => item != _movie);
    Assert.Equal(2, removed.Count);
    Assert.Equal(_mario, Assert.Single(book.All()).UserId);
}
```

`Tests/ReportStoreTests.cs`:
- `AMissingFileIsEmpty`.
- `TheSavedFileHasTheSpecShape`: una segnalazione senza nota, `Save`. Con `JsonDocument`: `Version` = 1, `Reports[0]` con `Id`, `UserId`, `ItemId` in `"N"`, `Type` = `"Subtitles"`, `CreatedAt`, `UpdatedAt` e **nessuna** proprietà `Note`. Un nuovo `Load()` dà lo stesso `StoredReport`.
- `AnUnreadableFileGoesToBad`: `{nope` → vuoto e `.bad`.
- `AnUnknownTypeMakesTheFileUnreadable`: `"Type": "Boh"` → vuoto e `.bad`.

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ReportBookTests|FullyQualifiedName~ReportStoreTests"`
Expected: FAIL (tipi mancanti).

- [ ] **Step 3: il codice** con le firme sopra. `ReportBook` è un `Dictionary<Guid, StoredReport>` per id.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): reports store and DTOs"
```

### Task 2: `IReportLibrary` e le regole di `ReportService`

In questo task `ReportService` non notifica ancora: le notifiche arrivano nel Task 3. Il costruttore però prende già `InboxService`, così il Task 3 non lo cambia.

**Files:**
- Create: `Hub/IReportLibrary.cs`, `Hub/ReportService.cs`, `Tests/TestReports.cs`
- Modify: `Hub/IUserDirectory.cs` (`CanManageSubtitles`, decisione 7: serve già al Task 3)
- Modify (test): `Tests/FakeServer.cs` (implementa `IReportLibrary`; `AddUser(..., bool canManageSubtitles = false)`)
- Test: `Tests/ReportServiceTests.cs`

**Interfaces:**
- Consumes: Task 1; `RecommendationService.CleanMessage`; `IUserDirectory`; `ILibraryAccess.CanSee`; `ILibraryTitles.IsScanRunning`; `InboxService`.
- Produces:
  - `Hub/IReportLibrary.cs`:
    ```csharp
    /// <summary>
    /// Un titolo che si può segnalare (spec R §6.2). Type: Movie, Series, Season o Episode.
    /// TitleId e TitleName: il film o la serie da aprire; SeasonNumber per stagioni ed episodi,
    /// EpisodeNumber per gli episodi.
    /// </summary>
    public sealed record ReportedItem(
        Guid Id, string Type, string Name, Guid TitleId, string TitleName, int? SeasonNumber, int? EpisodeNumber);

    public interface IReportLibrary
    {
        /// <summary>Il film, la serie, la stagione o l'episodio; null se non c'è, è un altro tipo o (stagione, episodio) non ha la serie.</summary>
        ReportedItem? Find(Guid itemId);
    }
    ```
  - `ReportOutcome(HubStatus Status, string? Reason, ReportDto? Report)` (in `ReportService.cs`, come `RatingOutcome`).
  - `ReportService(ReportStore store, IUserDirectory users, ILibraryAccess access, IReportLibrary library, ILibraryTitles titles, InboxService inbox, TimeProvider time, ILogger<ReportService> logger)`:
    - `const int MaxOpenPerUser = 20`, `const int MaxNoteLength = 500`, `void Load()`;
    - `Task<ReportOutcome> CreateAsync(Guid userId, CreateReportRequest? request)`;
    - `HubResult<ReportListDto> Mine(Guid userId, string? itemId)`;
    - `ReportListDto List()`;
    - `Task<ReportOutcome> ResolveAsync(Guid adminId, string? reportId, ResolveReportRequest? request)` (`Report` null quando riesce);
    - `int Cleanup()`;
    - `internal static string? CleanNote(string? note, out bool tooLong)`, con `CleanMessage` e il conteggio in rune.
  - `UserRef(Guid Id, string Name, bool Enabled, bool CanJoinParties, bool IsAdmin = false, bool CanManageSubtitles = false)`, con il commento "spunta 'gestione sottotitoli' di Jellyfin (spec R §6.4)".
  - `TestReports.Create(FakeServer server, TempFolder folder, TimeProvider time, InboxService inbox, ILogger<ReportService>? logger = null) : ReportService`.
  - `FakeServer`:
    - `Dictionary<Guid, ReportedItem> ReportedItems`;
    - `ReportedItem AddMovie(string name)`;
    - `(ReportedItem Series, ReportedItem Season, ReportedItem Episode) AddEpisode(string series, int season, int episode)`;
    - `bool ReportLibraryFails` (`Find` lancia `InvalidOperationException`).

**Regole** (spec §6.1, §6.2):
- **`CreateAsync`:**
  - `Invalid` se: l'utente non esiste; l'id non vale; `Type` non è valido; `Find` è null o lancia (`Warning` con l'id); `CanSee` è falso; la nota è troppo lunga;
  - poi, sotto lock: se c'è un doppione → `UpdateNote` (decisione 13); altrimenti, con già `MaxOpenPerUser` aperte → `Conflict` con `LimitReached`, oppure `Add` con un `Guid.NewGuid()`;
  - `Persist()`. Risponde con il `ReportDto` (`UserName` di chi chiama).
- **`Mine`:** `Invalid` per un id non valido o un utente che non esiste; poi `ForUser`.
- **`List`:** tutte, con i nomi da `Find` e `GetUser(...)?.Name ?? ""`. Un `Find` null o che lancia dà la decisione 4 (nomi vuoti, `TitleId` = `ItemId`), con un solo `Warning` per chiamata.
- **`ResolveAsync`:**
  - `Invalid` per un id non valido, un `Outcome` non valido o una nota troppo lunga;
  - `Conflict` con `Closed` se la segnalazione non c'è;
  - altrimenti `Remove`, `Persist()`, `Information` "Segnalazione {ReportId} chiusa ({Outcome}) da {Admin}".
- **`Cleanup`:**
  - `Prune` con `userExists` = `GetUser(id) is not null`;
  - `itemExists` = `true` se `titles.IsScanRunning`; altrimenti `Find(id) is not null`, e `true` se lancia (un solo `Warning` per giro);
  - `Persist()` se ha tolto qualcosa.
- **`Persist()`** come in `RatingService` ("Segnalazioni non salvate in {Path}").
- **`ToDto`:** `ItemType`, `ItemName`, `TitleId`, `TitleName`, `SeasonNumber`, `EpisodeNumber` da `ReportedItem`, con gli id in `"N"`.

- [ ] **Step 1: test che falliscono**

`Tests/ReportServiceTests.cs`. Utenti: Mario (chi segnala), Luigi, Peach admin. Titoli: `_movie = _server.AddMovie("Dune")`; `(_series, _season, _episode) = _server.AddEpisode("Breaking Bad", 2, 3)`.

```csharp
[Fact]
public async Task ACreatedReportHasTheTitleAndLevel()
{
    var outcome = await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, "  Mancano\ni sottotitoli "));
    Assert.Equal(HubStatus.Ok, outcome.Status);
    var dto = outcome.Report!;
    Assert.Equal("Mancano i sottotitoli", dto.Note);
    Assert.Equal(("Episode", N(_series.Id), "Breaking Bad", 2, 3), (dto.ItemType, dto.TitleId, dto.TitleName, dto.SeasonNumber, dto.EpisodeNumber));
    Assert.Equal(("Mario", N(_mario.Id), T0, T0), (dto.UserName, dto.UserId, dto.CreatedAt, dto.UpdatedAt));
    Assert.Equal(dto, Assert.Single(_service.List().Items));
}

[Fact]
public async Task ADuplicateUpdatesTheNote()
{
    var first = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, "Titolo in arabo"))).Report!;
    _time.Advance(TimeSpan.FromHours(1));
    var again = (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, null))).Report!;
    Assert.Equal(first.Id, again.Id);
    Assert.Null(again.Note);
    Assert.Equal(T0.AddHours(1), again.UpdatedAt);
    Assert.Single(_service.List().Items);
}

[Fact]
public async Task TheTwentyFirstOpenReportIsRefused()
{
    for (var i = 0; i < 20; i++)
    {
        Assert.Equal(HubStatus.Ok, (await _service.CreateAsync(_mario.Id, Request(_server.AddMovie($"Film {i}").Id, ReportTypes.Other, null))).Status);
    }

    var outcome = await _service.CreateAsync(_mario.Id, Request(_server.AddMovie("Ultimo").Id, ReportTypes.Other, null));
    Assert.Equal((HubStatus.Conflict, ReportReasons.LimitReached), (outcome.Status, outcome.Reason));
    // un doppione di una delle 20 resta ammesso
}

[Fact]
public async Task NotesAreCleanedAndCountedInCodePoints()
{
    var emoji = string.Concat(Enumerable.Repeat("🎬", 500));
    Assert.Equal(HubStatus.Ok, (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Other, emoji))).Status);
    Assert.Equal(HubStatus.Invalid, (await _service.CreateAsync(_mario.Id, Request(_movie.Id, ReportTypes.Metadata, emoji + "a"))).Status);
    Assert.Equal("a b c", (await _service.CreateAsync(_luigi.Id, Request(_movie.Id, ReportTypes.Other, "a\tb\r\nc"))).Report!.Note);
}
```

E inoltre:
- `InvalidRequestsAreRefused`: `null`; id non valido; `Type` `"Boh"`; titolo sconosciuto; `(mario, film)` in `Unseen`; `ReportLibraryFails`; un utente che non esiste (`Guid.Empty`, la chiave API) → tutti `Invalid`, e niente nel file.
- `MineHasOnlyTheCallersReportsOnThatItem`.
- `ListShowsEmptyNamesForAGoneTitle`: si toglie il titolo da `ReportedItems` → `ItemName` `""`, `TitleId` = `ItemId`.
- `ResolveRemovesTheReport`: `Fixed` con la nota → `Ok`, la lista è vuota, `Information` nel `RecordingLogger` senza la nota; un `Outcome` `"Boh"` → `Invalid`.
- `CleanupKeepsReportsDuringAScanOrALibraryError`: con `ScanRunning` niente cambia; con `ReportLibraryFails` niente cambia e c'è un solo `Warning`; un utente tolto da `Users` → la sua segnalazione sparisce.
- `ADiskErrorKeepsTheReportInMemory` (come in `RatingServiceTests`: la cartella del file è un file) → `Ok`, la segnalazione è in `List()`, e c'è un `Warning`.

- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~ReportServiceTests"`).

- [ ] **Step 3: il codice** con le firme e le regole sopra.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): report service rules"
```

### Task 3: le voci della cassetta e le notifiche

**Files:**
- Modify: `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs`, `Hub/ReportService.cs`
- Test: `Tests/InboxReportsTests.cs`, `Tests/ReportServiceTests.cs` (aggiunte)

**Interfaces:**
- Consumes: `StoredReport`, `ReportedItem`, `ReportService` (Task 1–2).
- Produces:
  - `InboxEntryTypes.ReportPending`, `InboxEntryTypes.ReportResolved` (commenti "spec R §6.3");
  - `InboxEntry`: `ReportId`, `ReportType`, `Outcome`, `ItemType` (`string?`), `SeasonNumber`, `EpisodeNumber` (`int?`), tutti `WhenWritingNull`, con un commento come gli altri;
  - `InboxBook.RemoveReport(string reportId) : IReadOnlyList<Guid>`: toglie le `ReportPending` con quel `ReportId` da tutte le cassette e restituisce gli utenti toccati;
  - `InboxService`, metodi che non lanciano (errore → `Warning` con l'id della segnalazione):
    - `Task AddReportPendingAsync(IReadOnlyList<Guid> userIds, StoredReport report, ReportedItem item, string fromName)`;
    - `Task AddReportResolvedAsync(Guid userId, StoredReport report, ReportedItem? item, string outcome, string? note)`;
    - `Task RemoveReportEntriesAsync(IReadOnlyCollection<Guid> reportIds)`, che avvisa solo gli utenti toccati.

**Campi delle voci** (decisione 2):

| Campo | `ReportPending` | `ReportResolved` |
|---|---|---|
| `ReportId` | id `"N"` | id `"N"` |
| `ReportType` | tipo | tipo |
| `FromName` | chi segnala | — |
| `Outcome` | — | `Fixed` / `CannotFix` |
| `Text` | nota della segnalazione | nota dell'admin |
| `ItemId`, `ItemType`, `SeasonNumber`, `EpisodeNumber` | da `ReportedItem` | da `ReportedItem`; se è null: `ItemId` dalla segnalazione, gli altri assenti |
| `Title`, `ImageItemId` | `TitleName`, `TitleId` | idem; se `ReportedItem` è null: `Title` `""`, `ImageItemId` assente |

**Collegamento in `ReportService`:**
- **segnalazione nuova:** `AddReportPendingAsync` agli admin della decisione 6. Un doppione non avvisa;
- **`ResolveAsync` riuscita:** prima `RemoveReportEntriesAsync([id])`, poi `AddReportResolvedAsync` a chi ha segnalato, ma solo se chi chiude non è chi ha segnalato. `item` è `Find` riletto adesso, o null se il titolo non c'è più o la libreria lancia;
- **`Cleanup`:** `RemoveReportEntriesAsync(tolte)`, scartando il `Task` con `_ =` (il metodo non lancia). Commento: "la pulizia gira su un timer: l'avviso parte da solo".
- Le chiamate alla cassetta stanno **fuori** dal lock di `ReportService`.

- [ ] **Step 1: test che falliscono**

`Tests/InboxReportsTests.cs` (come `InboxRecommendationTests`):
- `PendingEntriesCarryTheReport`: `AddReportPendingAsync([peach], report, episodio, "Mario")`. La voce ha `Type` `ReportPending`, `ReportId`, `ReportType` `Subtitles`, `FromName` `"Mario"`, `Text` = nota, `ItemId` = episodio, `ItemType` `"Episode"`, `SeasonNumber` 2, `EpisodeNumber` 3, `Title` `"Breaking Bad"`, `ImageItemId` = serie. Più un `InboxChanged` a Peach.
- `RemoveReportTouchesOnlyThatReport`: due admin con la voce della segnalazione A e uno anche con B → `RemoveReportEntriesAsync([A])` le toglie, B resta, e l'avviso va solo ai due toccati.
- `ResolvedWithAGoneTitleHasTheReportItemId`: `item` null → `ItemId` dalla segnalazione, `Title` `""`, niente `ImageItemId`.
- `TheJsonHasTheNewFieldsOnlyWhenSet`: una voce `Announcement` serializzata non ha `ReportId`, `Outcome`, `SeasonNumber`.

In `Tests/ReportServiceTests.cs`, ora con utenti Peach admin, Daisy admin disabilitata, Toad con `canManageSubtitles: true` (parametro del Task 2) e Mario e Luigi normali:

```csharp
[Fact]
public async Task PendingGoesToEnabledAdminsOnly()
{
    await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null));
    Assert.Equal(InboxEntryTypes.ReportPending, Assert.Single(_inbox.Get(_peach.Id).Entries).Type);
    Assert.Empty(_inbox.Get(_daisy.Id).Entries);
    Assert.Empty(_inbox.Get(_toad.Id).Entries);
    Assert.Empty(_inbox.Get(_mario.Id).Entries);
}

[Fact]
public async Task ResolvingNotifiesTheReporterAndClearsTheAdmins()
{
    var report = (await _service.CreateAsync(_mario.Id, Request(_episode.Id, ReportTypes.Subtitles, null))).Report!;
    var outcome = await _service.ResolveAsync(_peach.Id, report.Id, new ResolveReportRequest { Outcome = ReportOutcomes.Fixed, Note = "Aggiunti" });
    Assert.Equal(HubStatus.Ok, outcome.Status);
    Assert.Empty(_inbox.Get(_peach.Id).Entries);
    var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
    Assert.Equal((InboxEntryTypes.ReportResolved, ReportOutcomes.Fixed, "Aggiunti"), (entry.Type, entry.Outcome, entry.Text));
}

[Fact]
public async Task ASecondResolveIsClosedAndNotifiesOnce()
{
    // due admin (Peach e Rosalina); Peach chiude, poi Rosalina → Conflict/Closed; Mario ha una sola ReportResolved
}

[Fact]
public async Task AnAdminReportingHimselfGetsNoEntries()
{
    // Peach segnala: la ReportPending va solo a Rosalina; Peach chiude: Rosalina la perde, Peach non riceve ReportResolved
}
```

E inoltre:
- `ADuplicateDoesNotNotifyAgain`: dopo il doppione, Peach ha ancora una sola voce e c'è un solo `InboxChanged`.
- `CleanupClearsThePendingEntries`: tolto il titolo da `ReportedItems`, `Cleanup()` → Peach non ha più la voce, e Mario non riceve niente.

- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~InboxReportsTests|FullyQualifiedName~ReportServiceTests"`).

- [ ] **Step 3: il codice** con le firme e la tabella sopra. Le voci si aggiungono con `Book.Add`; ogni metodo segue lo schema `try { lock { …; Persist(); } await NotifyAsync(…); } catch (Exception ex) when (ex is not OperationCanceledException) { Warning }` dei metodi esistenti.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): report inbox entries"
```

## Gruppo B — sottotitoli, endpoint e Jellyfin

### Task 4: permesso sottotitoli e `SubtitleService`

**Files:**
- Create: `Protocol/SubtitleDtos.cs`, `Hub/ISubtitleTools.cs`, `Hub/SubtitleService.cs`, `Tests/FakeSubtitleTools.cs`
- Test: `Tests/SubtitleServiceTests.cs`

**Interfaces:**
- Consumes: `UserRef.CanManageSubtitles` e `FakeServer.AddUser(..., canManageSubtitles)` (Task 2).
- Produces:
  - `Protocol/SubtitleDtos.cs`:
    - `RemoteSubtitleDto(string Id, string ProviderName, string Name, string Language, string Format, float? CommunityRating, int? DownloadCount, bool IsHashMatch, bool HearingImpaired, bool Forced, bool MachineTranslated)`;
    - `SubtitleReasons` (`DownloadFailed`, `UploadFailed`), `SubtitleErrorDto(string Reason)`;
    - corpi: `DownloadSubtitleRequest { string? SubtitleId }`, `UploadSubtitleRequest { string? Language; string? Format; bool IsForced; bool IsHearingImpaired; string? Data }`.
  - `Hub/ISubtitleTools.cs`:
    ```csharp
    /// <summary>Un sottotitolo da salvare accanto al video (spec R §6.4); Language minuscolo a tre lettere, Format minuscolo.</summary>
    public sealed record SubtitleUpload(string Language, string Format, bool IsForced, bool IsHearingImpaired, byte[] Data);

    /// <summary>I sottotitoli di Jellyfin (adattatore di ISubtitleManager e IProviderManager).</summary>
    public interface ISubtitleTools
    {
        /// <summary>L'elemento è un film o un episodio.</summary>
        bool IsVideo(Guid itemId);

        Task<IReadOnlyList<RemoteSubtitleDto>> SearchAsync(Guid itemId, string language, bool? perfectMatch, CancellationToken cancellationToken);

        /// <summary>Scarica e mette in coda il refresh dell'elemento; lancia se il download fallisce.</summary>
        Task DownloadAsync(Guid itemId, string subtitleId, CancellationToken cancellationToken);

        /// <summary>Salva e mette in coda il refresh dell'elemento; lancia se il salvataggio fallisce.</summary>
        Task UploadAsync(Guid itemId, SubtitleUpload upload, CancellationToken cancellationToken);
    }
    ```
  - `SubtitleStatus { Ok, Forbidden, Invalid, Failed }` e `SubtitleResult<T>(SubtitleStatus Status, T? Value)` (in `SubtitleService.cs`).
  - `SubtitleService(ISubtitleTools tools, IUserDirectory users, ILibraryAccess access, ILogger<SubtitleService> logger)`:
    - `const int MaxUploadBytes = 2 * 1024 * 1024`;
    - `static readonly IReadOnlyList<string> UploadFormats`;
    - `Task<SubtitleResult<IReadOnlyList<RemoteSubtitleDto>>> SearchAsync(Guid userId, string? itemId, string? language, bool? perfectMatch, CancellationToken ct)`;
    - `Task<SubtitleStatus> DownloadAsync(Guid userId, string? itemId, DownloadSubtitleRequest? request, CancellationToken ct)`;
    - `Task<SubtitleStatus> UploadAsync(Guid userId, string? itemId, UploadSubtitleRequest? request, CancellationToken ct)`.
  - `FakeSubtitleTools : ISubtitleTools`, per i test:
    - `HashSet<Guid> Videos`;
    - `List<RemoteSubtitleDto> Results`;
    - `Exception? Failure` (lanciata da Download e Upload);
    - `bool LibraryFails` (`IsVideo` lancia);
    - `List<(Guid ItemId, string Language, bool? PerfectMatch)> Searches`;
    - `List<(Guid ItemId, string SubtitleId)> Downloads`;
    - `List<(Guid ItemId, SubtitleUpload Upload)> Uploads`.

**Regole, nell'ordine:**
1. **Permesso:** `users.GetUser(userId)` deve esistere, essere attivo e avere `IsAdmin || CanManageSubtitles`; altrimenti `Forbidden`.
2. **Titolo:** l'id deve valere, `access.CanSee(userId, id)` e `tools.IsVideo(id)` devono essere veri; altrimenti `Invalid`. Se uno dei due lancia: `Invalid` con un `Warning`.
3. **Valori:**
   - lingua: tre lettere ASCII dopo `Trim().ToLowerInvariant()`;
   - `SubtitleId` non vuoto;
   - upload: `Format` in `UploadFormats` (minuscolo), `Data` base64 valido (`Convert.TryFromBase64String` con un buffer di `MaxUploadBytes`) e non vuoto, al massimo `MaxUploadBytes`.
   Altrimenti `Invalid`.
4. **Chiamata a `tools`:** un'eccezione (non `OperationCanceledException`) in Download o Upload → `Failed`, con un `Warning` con l'id e, per il download, il provider, cioè la parte di `SubtitleId` prima di `_`. Un'eccezione nella ricerca → `Failed`.

- [ ] **Step 1: test che falliscono**

`Tests/SubtitleServiceTests.cs`. Utenti: Mario normale, Toad con la spunta, Peach admin senza spunta, Daisy con la spunta ma disabilitata. `_episode` in `Videos`.

```csharp
[Fact]
public async Task OnlyAdminsAndSubtitleManagersMayUseIt()
{
    Assert.Equal(SubtitleStatus.Forbidden, (await Search(_mario)).Status);
    Assert.Equal(SubtitleStatus.Forbidden, (await Search(_daisy)).Status);
    Assert.Equal(SubtitleStatus.Forbidden, (await _service.SearchAsync(Guid.Empty, N(_episode), "ita", null, default)).Status);
    Assert.Equal(SubtitleStatus.Ok, (await Search(_toad)).Status);
    Assert.Equal(SubtitleStatus.Ok, (await Search(_peach)).Status);
}

[Fact]
public async Task SearchNormalisesTheLanguage()
{
    await _service.SearchAsync(_toad.Id, N(_episode), " ITA ", true, default);
    Assert.Equal((_episode, "ita", (bool?)true), Assert.Single(_tools.Searches));
    Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, N(_episode), "it", null, default)).Status);
    Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, N(_episode), "it1", null, default)).Status);
}

[Fact]
public async Task AFailedDownloadIsFailed()
{
    _tools.Failure = new HttpRequestException("provider giù");
    var status = await _service.DownloadAsync(_toad.Id, N(_episode), new DownloadSubtitleRequest { SubtitleId = "open_123" }, default);
    Assert.Equal(SubtitleStatus.Failed, status);
    var warning = Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
    Assert.Contains("open", warning.Message);
}

[Fact]
public async Task UploadChecksFormatSizeAndBase64()
{
    Assert.Equal(SubtitleStatus.Ok, await Upload("SRT", Convert.ToBase64String("1\n00:00:01,000 --> 00:00:02,000\nCiao\n"u8.ToArray())));
    Assert.Equal(("ita", "srt"), (_tools.Uploads[0].Upload.Language, _tools.Uploads[0].Upload.Format));
    Assert.Equal(SubtitleStatus.Invalid, await Upload("exe", Convert.ToBase64String([1])));
    Assert.Equal(SubtitleStatus.Invalid, await Upload("srt", "non base64!"));
    Assert.Equal(SubtitleStatus.Invalid, await Upload("srt", ""));
    Assert.Equal(SubtitleStatus.Invalid, await Upload("srt", Convert.ToBase64String(new byte[SubtitleService.MaxUploadBytes + 1])));
    Assert.Equal(SubtitleStatus.Ok, await Upload("srt", Convert.ToBase64String(new byte[SubtitleService.MaxUploadBytes])));
}
```

E inoltre:
- `OnlyVisibleVideosCanBeUsed`: un id che non è in `Videos`, `(toad, episodio)` in `Unseen`, un id non valido, `LibraryFails` → `Invalid`.
- `AFailedUploadIsFailed`: `Failure` con Upload → `Failed`.
- `DownloadNeedsASubtitleId`: `null` o `""` → `Invalid`, e nessuna chiamata a `tools`.

- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~SubtitleServiceTests"`).

- [ ] **Step 3: il codice** con le firme e le regole sopra.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): subtitle service with permission checks"
```

### Task 5: `ReportsController` e `SubtitlesController`

**Files:**
- Create: `Api/ReportsController.cs`, `Api/SubtitlesController.cs`
- Test: `Tests/ReportsControllerTests.cs`, `Tests/SubtitlesControllerTests.cs`

**Interfaces:**
- Consumes: `ReportService` (Task 2–3), `SubtitleService` (Task 4).
- Produces:
  - `ReportsController(IAuthorizationContext authorizationContext, ReportService reports) : ControllerBase`, con `[ApiController]`, `[Route("WonderFlixWatchParty")]`, `[Authorize]`, `[Produces(MediaTypeNames.Application.Json)]`:
    - `POST Reports` → 200 `ReportDto`, 400, 409 `ReportErrorDto`;
    - `GET Reports/Mine?itemId=` → 200 `ReportListDto` o 400;
    - `GET Reports` (`RequiresElevation`) → 200 `ReportListDto`;
    - `POST Reports/{reportId}/Resolve` (`RequiresElevation`) → 204, 400, 409.
  - `SubtitlesController(IAuthorizationContext authorizationContext, SubtitleService subtitles) : ControllerBase`, con gli stessi attributi di classe:
    - `GET Subtitles/{itemId}/Search?language=&perfectMatch=` → 200 array, 400, 403, 502 (senza corpo);
    - `POST Subtitles/{itemId}/Download` → 204, 400, 403, 502 `{"Reason":"DownloadFailed"}`;
    - `POST Subtitles/{itemId}/Upload` → 204, 400, 403, 502 `{"Reason":"UploadFailed"}`.
  - Il token passato ai servizi è `HttpContext.RequestAborted`.

- [ ] **Step 1: test che falliscono** (come `RatingsControllerTests`, con `FakeAuthorizationContext`):
- `TheAdminEndpointsNeedElevation`: con `GetCustomAttributes<AuthorizeAttribute>()`, `List` e `Resolve` hanno `Policies.RequiresElevation`; `Create` e `Mine` nessuna policy di metodo; le due classi hanno `[Authorize]` senza policy.
- `CreateMapsTheOutcomes`: valido → `OkObjectResult` con `ReportDto`; non valido → `BadRequestResult`; oltre il limite → `ObjectResult` 409 con `ReportErrorDto("LimitReached")`.
- `ResolveMapsTheOutcomes`: 204; 400; seconda volta → 409 `Closed`.
- `SubtitleStatusesMapToCodes`: con `FakeSubtitleTools`, Forbidden → 403 (`StatusCodeResult`); Invalid → 400; download fallito → `ObjectResult` 502 con `SubtitleErrorDto("DownloadFailed")`; upload fallito → 502 `UploadFailed`; ricerca ok → `OkObjectResult` con l'array.

- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~ReportsControllerTests|FullyQualifiedName~SubtitlesControllerTests"`).

- [ ] **Step 3: il codice.** Chi chiama è `(await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId`, come in `RatingsController`. Commento di classe con la policy, come in `RatingsAdminController`.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): reports and subtitles endpoints"
```

### Task 6: adattatori di Jellyfin, permesso e pulizia

**Files:**
- Create: `Server/JellyfinReportLibrary.cs`, `Server/JellyfinSubtitleTools.cs`, `ReportsHostedService.cs`
- Modify: `Server/JellyfinUserDirectory.cs`
- Test: `Tests/JellyfinReportLibraryTests.cs`, `Tests/JellyfinSubtitleToolsTests.cs`, `Tests/ReportsHostedServiceTests.cs`, e un test in quello esistente di `JellyfinUserDirectory`, se c'è (altrimenti in `JellyfinReportLibraryTests`)

**Interfaces:**
- Consumes: `IReportLibrary`, `ReportedItem` (Task 2); `ISubtitleTools`, `SubtitleUpload`, `RemoteSubtitleDto` (Task 4); `ReportService.Load`/`Cleanup`.
- Produces:
  - `JellyfinReportLibrary(ILibraryManager libraryManager) : IReportLibrary`;
  - `JellyfinSubtitleTools(ILibraryManager libraryManager, ISubtitleManager subtitleManager, IProviderManager providerManager, IFileSystem fileSystem) : ISubtitleTools`;
  - `ReportsHostedService(ReportService reports, TimeProvider time, ILogger<ReportsHostedService> logger) : IHostedService, IDisposable`, con `StoreInterval` (5 min).

- [ ] **Step 1: verifiche sul sorgente** (spec §12)

Rileggi al tag `v10.11.0` le firme di "Note tecniche verificate" → "Jellyfin 10.11.9": `ISubtitleManager`, `SubtitleResponse`, `RemoteSubtitleInfo` (i campi del DTO, in particolare `AiTranslated`, `MachineTranslated`, `Forced`, `HearingImpaired`, `IsHashMatch`), `IProviderManager.QueueRefresh`, `MetadataRefreshOptions`, `DirectoryService`, `PermissionKind.EnableSubtitleManagement`. Se qualcosa è diverso o manca in 10.11.0, correggi l'adattatore in modo minimo (per esempio un campo assente vale `false`) e annotalo per il Task 8.

- [ ] **Step 2: test che falliscono**

`Tests/JellyfinReportLibraryTests.cs`, con `InterfaceStub<ILibraryManager>` (`GetItemById`):
- `ItemsMapToTheirLevel`:
  - `Movie { Name = "Dune" }` → `("Movie", "Dune", id, "Dune", null, null)`;
  - `Series { Name = "Breaking Bad" }` → `TitleId` = il suo id;
  - `Season { SeriesId, SeriesName = "Breaking Bad", IndexNumber = 2 }` → `("Season", TitleId = SeriesId, SeasonNumber 2)`;
  - `Episode { SeriesId, SeriesName, ParentIndexNumber = 2, IndexNumber = 3, Name = "Bit by a Dead Bee" }` → `("Episode", Name, 2, 3)`.
- `OtherItemsAreNull`: `BoxSet`, un id sconosciuto, `Guid.Empty`, una `Season` o un `Episode` con `SeriesId` vuoto → null.

`Tests/JellyfinSubtitleToolsTests.cs`, con `InterfaceStub<ISubtitleManager>`, `InterfaceStub<IProviderManager>`, `InterfaceStub<IFileSystem>`:
- `SearchMapsTheResults`: un `RemoteSubtitleInfo` con `IsHashMatch = null`, `AiTranslated = true`, `MachineTranslated = false`, `ThreeLetterISOLanguageName = "ita"` → `IsHashMatch` false, `MachineTranslated` true, `Language` `"ita"`. La chiamata ha `isAutomated` false.
- `DownloadQueuesARefreshOnlyOnSuccess`: download riuscito → una `QueueRefresh` con l'id e `RefreshPriority.High`; download che lancia → l'eccezione esce e non c'è nessuna `QueueRefresh`.
- `UploadPassesTheFileAndQueuesARefresh`: la `SubtitleResponse` ha lingua, formato, flag e lo stream con i byte dati.
- `IsVideoOnlyForMoviesAndEpisodes`.

`Tests/ReportsHostedServiceTests.cs` (come `RatingsHostedServiceTests`):
- `StartLoadsAndTheTimerCleans`: `StartAsync` legge il file (un `reports.json` illeggibile diventa `.bad` subito); un utente tolto da `Users` → dopo `Advance(5 min)` la sua segnalazione non è più nel file.

Permesso: `ToRef` di un utente con `EnableSubtitleManagement` → `CanManageSubtitles` true, senza → false.

- [ ] **Step 3: il codice**

- **`JellyfinReportLibrary.Find`:**
  - `itemId != Guid.Empty`, poi `GetItemById`;
  - `Movie` → `TitleId` = sé stesso;
  - `Series` → sé stesso;
  - `Season` con `SeriesId` non vuoto → serie, `SeasonNumber` = `IndexNumber`;
  - `Episode` con `SeriesId` non vuoto → serie, `ParentIndexNumber`, `IndexNumber`;
  - `Name` e `SeriesName` con `?? string.Empty`.
- **`JellyfinSubtitleTools`:**
  - `GetItemById(itemId) as Video`, con `Movie` o `Episode`; altrimenti `InvalidOperationException`;
  - `SearchSubtitles(video, language, perfectMatch, false, ct)`, poi la mappa;
  - `DownloadSubtitles(video, subtitleId, ct)`;
  - `UploadSubtitle(video, new SubtitleResponse { …, Stream = new MemoryStream(data, writable: false) })`;
  - dopo download e upload, la `QueueRefresh` identica a `SubtitleController`;
  - commento con le verifiche di "Note tecniche verificate".
- **`JellyfinUserDirectory.ToRef`:** `user.HasPermission(PermissionKind.EnableSubtitleManagement)` come sesto argomento.
- **`ReportsHostedService`:** come `RatingsHostedService` con un solo timer. `StartAsync` chiama `reports.Load()` nel suo `try/catch` (`Warning` "Segnalazioni non caricate all'avvio"), poi `time.CreateTimer(_ => Run(reports.Cleanup), …, StoreInterval, StoreInterval)`.

- [ ] **Step 4: i test passano** (`--filter "FullyQualifiedName~JellyfinReportLibraryTests|FullyQualifiedName~JellyfinSubtitleToolsTests|FullyQualifiedName~ReportsHostedServiceTests"`, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): Jellyfin adapters for reports and subtitles"
```

### Task 7: montaggio, `Info` e plugin 1.12.0

**Files:**
- Modify: `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `../meta.template.json`, `../README.md`
- Modify (test): `Tests/ServiceRegistrationTests.cs`, `Tests/InfoControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `Tests/ServiceRegistrationTests.cs`, prima del conteggio:

```csharp
        // Segnalazioni e sottotitoli (spec R).
        Assert.Same(provider.GetRequiredService<ReportService>(), provider.GetRequiredService<ReportService>());
        Assert.Same(provider.GetRequiredService<SubtitleService>(), provider.GetRequiredService<SubtitleService>());
        Assert.IsType<Server.JellyfinReportLibrary>(provider.GetRequiredService<IReportLibrary>());
        Assert.IsType<Server.JellyfinSubtitleTools>(provider.GetRequiredService<ISubtitleTools>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.ReportsController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.SubtitlesController>(provider));
```

Il conteggio diventa `Assert.Equal(8, …)`, con la riga di commento "Le segnalazioni (spec R), oltre ai sette di prima.". Se il provider dei test non ha `ISubtitleManager`, `IProviderManager` o `IFileSystem`, aggiungili come stub nello stesso modo degli altri servizi di Jellyfin.

In `Tests/InfoControllerTests.cs`: `"1.12.0"` e, nei due elenchi, `"reports"` dopo `"ratings"`. Cerca con `grep` altri test su versione, funzioni o `Description` e aggiornali con la stessa regola.

- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~InfoControllerTests"`).

- [ ] **Step 3: il codice**

- **`PluginServiceRegistrator.cs`**, dopo il blocco dei voti:
  ```csharp
        // Segnalazioni e sottotitoli (spec R).
        serviceCollection.AddSingleton(provider => new ReportStore(
            ReportStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<ReportStore>>()));
        serviceCollection.AddSingleton<IReportLibrary, JellyfinReportLibrary>();
        serviceCollection.AddSingleton<ReportService>();
        serviceCollection.AddSingleton<ISubtitleTools, JellyfinSubtitleTools>();
        serviceCollection.AddSingleton<SubtitleService>();
  ```
  e in fondo `serviceCollection.AddHostedService<ReportsHostedService>();`.
- **`WatchPartyProtocol.Features`:** "spec R §6.5" nel commento, `"reports"` dopo `"ratings"`.
- **csproj:** `<Version>1.12.0</Version>`.
- **`Plugin.cs`:** nel commento della classe "e, dalla 1.12.0, le segnalazioni e i sottotitoli (spec R)"; in `Description`, dopo "friends' ratings", ", problem reports and subtitle search".
- **`../meta.template.json`:**
  - `description`, dopo la frase dei voti: ", problem reports (users report a problem on a title, admins are notified and close it) and subtitle search and download for admins and users allowed to manage subtitles";
  - `overview`, dopo "friends' ratings": ", problem reports, subtitle search".
- **`../README.md`:**
  - nell'introduzione, dopo la frase della 1.11.0: "Dalla 1.12.0 ci sono le segnalazioni: chi trova un problema su un titolo lo segnala, gli admin ricevono una notifica e la chiudono, e chi ha segnalato riceve l'esito; in più admin e utenti con la spunta sottotitoli di Jellyfin cercano, scaricano e caricano sottotitoli (spec R, `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md`).";
  - un punto "**Segnalazioni e sottotitoli (dalla 1.12.0):**" dopo quello dei voti:
    - `reports.json`, solo le aperte, al massimo 20 per utente;
    - `POST Reports`, `GET Reports/Mine` per tutti; `GET Reports` e `POST Reports/{id}/Resolve` solo admin;
    - voci `ReportPending`/`ReportResolved`;
    - `Subtitles/{itemId}/Search|Download|Upload` per admin e spunta sottotitoli, con 502 `{Reason}` se il download o l'upload falliscono;
    - i 409 hanno `{Reason}`;
  - nel punto "Funzioni": "…dalla 1.11.0 anche `ratings`, dalla 1.12.0 anche `reports`…";
  - in "Installazione a mano": `pack.sh 1.12.0` e `WonderFlix Watch Party_1.12.0.0/`.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): reports wiring and plugin 1.12.0"
```

---

## Gruppo C — server e chiusura

### Task 8: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md`

- [ ] **Step 1: la spec**, controllando ogni frase sul codice:
- **Stato:** "approvata il 2026-10-21; piano 24a realizzato (`docs/superpowers/plans/2026-10-21-wonderflix-24a-segnalazioni-plugin.md`), build di prova sul server; piani 24b e 24c da realizzare".
- **§6.1:** il formato del file come nel codice.
- **§6.2:**
  - il 409 `Closed` al posto del 404 (decisione 1);
  - la forma di `ReportDto` (decisioni 4, 5);
  - doppione con risposta 200 (decisione 13);
  - la chiave API (decisione 15).
- **§6.3:** i campi delle voci come nella tabella del Task 3 (decisioni 2, 3).
- **§6.4:**
  - `SubtitleStatus` e i 502 con `{Reason}` (decisione 8);
  - `RemoteSubtitleDto` appiattito (decisione 9);
  - lingue e upload (decisioni 10, 11);
  - `UserRef.CanManageSubtitles` (decisione 7).
- **§12:** le verifiche fatte ("Note tecniche verificate"): il download rilancia l'errore, il refresh si copia da `SubtitleController`, `EnableSubtitleManagement` = 22. Restano aperti i punti per i piani 24b e 24c (immagini, `LockedFields`, `MediaSources.Path`).
- **§13:** 24a realizzato; il plugin 1.12.0 resta build di prova fino alla fine del 24b.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the reports spec with plan 24a"
```

### Task 9: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent si ferma dopo il Task 8. L'orchestratore fa la review finale del branch e i ritocchi, poi esegue questi passi, con un solo riavvio di Jellyfin e **dopo l'OK dell'utente al riavvio**.

Regole per il server:
- il server lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando;
- gli script vanno in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`);
- **nessuno script stampa chiavi o token.**

1. **Riferimenti della dll:** la dll di Release contro gli assembly di Jellyfin 10.11.9: nessun membro non risolto. Controlla in particolare `ISubtitleManager.SearchSubtitles`/`DownloadSubtitles`/`UploadSubtitle`, `RemoteSubtitleInfo.AiTranslated`/`MachineTranslated`, `IProviderManager.QueueRefresh`.
2. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.12.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.12.0.0/`.
3. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix": base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - salvataggi:
     - `mkdir -p ~/wfwp-backup`;
     - sposta `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.11.0.0` in `~/wfwp-backup/1.11.0.0-voti` (con un suffisso se c'è già);
     - copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.11.0-prima-24a.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.12.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log di oggi `Loaded plugin: "WonderFlix Watch Party" "1.12.0.0"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.12.0.0, rimetti `~/wfwp-backup/1.11.0.0-voti` e la configurazione salvata, riavvia, e segnalalo.
4. **Controlli** (stessa base e intestazione; risposte riassunte con `python3`, mai stampate intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.12.0`; funzioni con `reports`, e ancora `ratings`, `match`, `recommendations`, `home`, `account`;
   - `GET /WonderFlixWatchParty/Reports` con la chiave API: 200 con `{"Items":[]}`;
   - `POST /WonderFlixWatchParty/Reports` con la chiave API: 400 (nessun utente), **non 404**;
   - `GET /WonderFlixWatchParty/Subtitles/x/Search?language=ita` con la chiave API: 403, **non 404**;
   - nel log la riga del file delle segnalazioni e nessun `Warning` del plugin dopo l'avvio;
   - nella configurazione del plugin `SeerrUrl`, `SonarrUrl`, `ContactReminderDays`, `HomeRowsSeen` ancora al loro posto.
   - Il giro completo (segnalazione, notifica, ricerca e download di un sottotitolo vero con OpenSubtitles) si prova con l'app nel piano 24b.
5. **Riporta all'utente** l'esito in breve: versione, funzioni, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 24b). Le app 0.17.x non chiamano gli endpoint nuovi e ignorano i tipi di voce che non conoscono.

### Task 10: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 9: merge fast-forward su `main` e push (memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente tag e niente manifest: il plugin 1.12.0 si pubblica alla fine del 24b, insieme all'app 0.18.0.
