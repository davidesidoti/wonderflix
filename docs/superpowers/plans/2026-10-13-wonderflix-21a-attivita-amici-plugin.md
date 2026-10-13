# WonderFlix — Piano 21a: cosa guardano gli amici, plugin 1.9.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server dello Spec O nel plugin 1.9.0:
- "Sta guardando" in `GET Friends` (campo `NowPlaying`, solo per chi può vedere il titolo, mai per un amico in un party);
- la posizione dell'amico per "Guarda insieme" (`GET Friends/{userId}/NowPlaying`);
- l'aggiornamento della presenza a inizio e fine di ogni riproduzione WonderFlix;
- il registro delle visioni (dopo 5 minuti o alla fine, 30 giorni, 100 titoli per utente) e la riga "Visti dagli amici" (`GET Activity/FriendsWatched`);
- l'interruttore "Mostra agli amici cosa guardo" (`GET`/`PUT Activity/Settings`);
- la funzione `friendsActivity` in `Info` e la riga `friendsWatched` della Home;
- una build di prova sul server.

L'app arriva nel piano 21b.

**Architecture:** la logica sta in `Hub/` e non conosce Jellyfin:
- `ActivityBook` (scelte e visioni in memoria, puro) e `ActivityStore` (file `activity.json`);
- `ActivityService` (regole: condivisione, registrazione, "Sta guardando", posizione, riga, pulizia);
- `IPlaybackDirectory` (le riproduzioni delle sessioni WonderFlix).

Gli adattatori Jellyfin sono in `Server/`: `JellyfinPlaybackDirectory` legge `ISessionManager.Sessions`, e `PlayingTitles` traduce elementi ed eventi di riproduzione. Un servizio in background nuovo (`ActivityHostedService`) ascolta `PlaybackStart`/`PlaybackProgress`/`PlaybackStopped`, legge il file all'avvio e pulisce ogni 5 minuti.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md` (§3, §6, §8, §10, §11.1, §12, §13).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 8):
1. **Un file solo:** `activity.json` tiene sia le scelte (`Hidden`: chi ha spento la condivisione) sia le visioni (`Users`), invece di `privacy.json` + `activity.json`. Un archivio, un libro, un lock: spegnere e cancellare le visioni è un cambio solo, scritto una volta.
2. **Solo i resoconti veri dell'app contano.** Verificato sul sorgente di Jellyfin 10.11.9 il 2026-10-13: dopo ogni resoconto Jellyfin manda da sé un `PlaybackProgress` al secondo (`SessionInfo.StartAutomaticProgress`, `IsAutomated = true`). Il plugin li scarta: per la soglia dei 5 minuti bastano i resoconti dell'app (ogni 10 s).
3. **`PlaybackProgress` arriva dentro la richiesta dell'app**, chiamato senza `try/catch` (`SessionManager.cs:928`): un'eccezione farebbe fallire il resoconto. Il servizio in background ha il suo `try/catch` e fa poco (un insieme in memoria e, una volta per titolo, un salvataggio). `PlaybackStart` e `PlaybackStopped` girano invece in `Task.Run`, con le eccezioni già prese da Jellyfin.
4. **Posizione per "Guarda insieme" = `PlayState.PositionTicks` così com'è.** Jellyfin la fa avanzare di un secondo alla volta mentre si guarda (la spec §6.5 diceva di aggiungere il tempo dall'ultimo resoconto: lo conterebbe due volte). `LastPlaybackCheckIn` (aggiornato solo dai resoconti veri) serve solo a scegliere la sessione più recente.
5. **"Sta guardando" bloccato** dopo un player chiuso male: non succede. Jellyfin (`CheckForIdlePlayback`, ogni 5 minuti) chiama `OnPlaybackStopped` per le sessioni senza resoconti da più di 5 minuti, e il plugin riceve `PlaybackStopped` come per uno stop normale. Lo stato sparisce da 5 a 10 minuti dopo.
6. **Party:** se una sessione WonderFlix dell'amico è nel registro dei party (`PartyRegistry.GroupOf`), `NowPlaying` manca, anche quando il party non è visibile a chi guarda (spec §6.2.1). SyncPlay non cambia i resoconti di riproduzione (verificato): le visioni nei party si registrano come le altre.
7. **Un episodio senza serie** (`SeriesId` vuoto) compare in "Sta guardando" con il suo nome, ma non si registra: la riga mostra solo film e serie.
8. **Una registrazione per titolo e sessione:** in memoria si ricorda la coppia (sessione, film o serie). A `PlaybackStopped` la sessione si dimentica; alla pulizia si dimenticano le sessioni che non ci sono più. Uno stop dopo una registrazione già fatta non riscrive il file.
9. **Errori di Jellyfin in "Sta guardando":** se la lettura delle sessioni o `CanSee` lanciano, `NowPlaying` manca (`Warning`) e `GET Friends` risponde lo stesso.
10. **Dalle review dei gruppi:**
    - **Stop dal controllo di inattività:** `CheckForIdlePlayback` manda `PlaybackStopped` (non automatico) 5–10 minuti dopo con la posizione fatta avanzare da Jellyfin, che supererebbe i 5 minuti anche per un'app chiusa al minuto 1. `PlaybackReport` ha quindi `LastCheckIn` (`LastPlaybackCheckIn` della sessione, in UTC) e uno stop conta per la posizione solo se `now - LastCheckIn <= ActivityService.MaxReportAge` (1 minuto); con un resoconto più vecchio conta solo `PlayedToCompletion`.
    - **`activity.json` illeggibile:** il controllo `Shares(friendId)` di "Sta guardando" è dentro il `try` di `Playing`: un errore di lettura dà `NowPlaying` assente (`Warning`), mai un 500 su `GET Friends`. Non si ripiega su un registro vuoto.
    - **Test in più:** la posizione di un amico in un party dà 409.

## Global Constraints

- Plugin **1.9.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9. Non usare `ISessionManager.ToSessionInfoDto` (non c'è nella 10.11.0).
- Endpoint sotto `/WonderFlixWatchParty`, con `[Authorize(Policy = Policies.SyncPlayHasAccess)]` come gli amici:
  - `GET Friends` (con `NowPlaying` nelle voci);
  - `GET Friends/{userId}/NowPlaying`;
  - `GET Activity/Settings` e `PUT Activity/Settings`;
  - `GET Activity/FriendsWatched`.
- **Mai 404:** `userId` è una stringa senza vincoli di rotta; ogni caso negativo della posizione è 409.
- Archivio `activity.json` in `<PluginConfigurationsPath>/WonderFlixWatchParty/`, accanto a `inbox.json`.
- Limiti: 5 minuti per contare una visione; 30 giorni; 100 titoli per utente; 30 titoli nella riga, scelti tra al massimo 60.
- Solo sessioni con `Client == "WonderFlix"`; solo film (`Movie`) ed episodi (`Episode`); si registra il film o la serie.
- `ShareActivity` acceso se l'utente non l'ha mai cambiato.
- `Info`: `Version` "1.9.0", `Protocol` 1, `Features` con `"friendsActivity"` dopo `"recommendations"`.
- Id della Home: `friendsWatched` subito dopo `recommended` in `HomeRowIds.Known`; `AddedLater` = `["recommended", "friendsWatched"]`.
- Log: **mai titoli o nomi**; solo id e numeri.

## Review Focus

1. **Amico in un party che chi guarda non vede:** né `Party` né `NowPlaying`; non si deve scoprire cosa guarda un party nascosto. Test: Task 3 (`NothingIsShownWithoutSharingAccessOrInAParty`).
2. **Titolo che chi guarda non può vedere** (libreria o limite d'età): l'amico risulta solo "Online" e la posizione dà 409. Test: Task 3 (`NothingIsShownWithoutSharingAccessOrInAParty`, `ThePositionIsTheFriendsCurrentOne`).
3. **Jellyfin lancia mentre si legge "Sta guardando":** `GET Friends` risponde lo stesso, con l'amico online e senza `NowPlaying`. Test: Task 3 (`APlaybackErrorLeavesOnlyOnline`).
4. **Spegnere e riaccendere la condivisione:** le visioni spariscono subito, non si registra niente mentre è spenta e le vecchie non tornano. Test: Task 1 (`TurningSharingOffDeletesTheViewsAndStopsRecording`), Task 2 (`NothingIsRecordedWhileSharingIsOff`).
5. **Un errore nel gestore di `PlaybackProgress`** non deve arrivare a Jellyfin, altrimenti fallirebbe il resoconto dell'app. Test: Task 5 (`AFailingReportDoesNotReachJellyfin`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `dotnet` o `git`, prima rinfresca il PATH (la shell dello strumento ha un PATH vecchio):
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-21a`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(plugin): …"`.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.9.0`.
- **Test:**
  - un solo gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj del plugin ha `TreatWarningsAsErrors`: un warning è un errore), poi `dotnet build-server shutdown`;
  - la base di partenza è di **859** test verdi (verificato il 2026-10-13 su `main` `3b20b7a`).
- **Formattazione e fine riga:**
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese;
  - durate, misure e limiti come costanti nominate e commentate;
  - `TimeProvider`, mai `DateTimeOffset.UtcNow`;
  - DTO `record` con `[property: JsonPropertyName("…")]`, oppure classi con `[JsonPropertyName]` per i corpi delle richieste;
  - id di Jellyfin in formato `"N"`;
  - `Lock` di .NET 9 per le sezioni critiche;
  - nel registro mai titoli o nomi.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un dettaglio di un test, un'API di Jellyfin con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-13 sul codice di `main` (`3b20b7a`) e sul sorgente di Jellyfin 10.11.9 (confrontato con la 10.11.0: i file di riproduzione e di sessione sono uguali).

**Plugin** (`main`)
- `RecommendationStore`/`RecommendationService`/`RecommendationBook` sono il modello per archivio, servizio e libro:
  - lock;
  - scrittura atomica (`.tmp` + `File.Move`);
  - file illeggibile spostato in `.bad`, rinomina non riuscita tollerata;
  - `Persist()` che non lancia sugli errori di disco;
  - il file letto alla prima occasione, con la riga `Information` del percorso.
- `FriendService.GetFriends(userId, partyOf)` costruisce `FriendEntry(UserId, Name, Online, Party)`; `partyOf` si chiama solo per gli amici online. `FriendsOf`/`AreFriends` prendono il loro lock (`FriendService` non chiama mai l'attività).
- `PresenceTracker.Changed(userId)`: dopo `Delay` (2 s) manda `FriendsChanged` agli amici online (`SocialEvent.FriendsChanged()`, serializzato con `JsonSerializer.Serialize`).
- `PartyRegistry.GroupOf(sessionId)` → `Guid?`: il gruppo in cui l'app di quella sessione è entrata. `Register(groupId, sessionId, userName)`.
- `ILibraryAccess.CanSee(userId, itemId)`, `IRecommendationLibrary.LastWatched(userId, itemId)` (ultima visione di un film o di una serie, da qualunque app).
- `HubResult<T>.Ok(value)` / `Fail(HubStatus)`; `HubStatus.Conflict` (409).
- `HomeRowIds.WithLaterRows` inserisce ogni riga di `AddedLater` non vista dopo l'ultima riga accesa che la precede in `Known`; `RecommendationsHostedService` chiama già `layout.AddLaterRows()` all'avvio: basta aggiungere l'id.
- `ServiceRegistrationTests.AllServicesResolve` conta **4** servizi in background.

**Jellyfin 10.11.9**
- `ISessionManager`:
  - `event EventHandler<PlaybackProgressEventArgs> PlaybackStart`, `PlaybackProgress`;
  - `event EventHandler<PlaybackStopEventArgs> PlaybackStopped`;
  - li sollevano `POST /Sessions/Playing`, `/Playing/Progress`, `/Playing/Stopped`.
- `PlaybackProgressEventArgs` (`MediaBrowser.Controller.Library`, `#nullable disable`), proprietà con `set`:
  - `SessionInfo Session` (mai null in un evento sollevato);
  - `BaseItem Item` (l'elemento intero della libreria: un episodio è un `Episode`; null con un id vuoto);
  - `long? PlaybackPositionTicks`, `bool IsPaused`, `bool IsAutomated`, `string ClientName`.
- `PlaybackStopEventArgs : PlaybackProgressEventArgs` aggiunge `bool PlayedToCompletion`.
- `SessionInfo` (`MediaBrowser.Controller.Session`), costruttore `new SessionInfo(ISessionManager, ILogger)`:
  - `PlayState` (`PlayerStateInfo`, `MediaBrowser.Model.Session`) con `long? PositionTicks` e `bool IsPaused`;
  - `DateTime LastPlaybackCheckIn` (UTC, solo resoconti veri);
  - `BaseItem FullNowPlayingItem` e `BaseItemDto NowPlayingItem`, tolti da `OnPlaybackStopped`.
- `Episode`: `SeriesId` (`Guid`), `SeriesName`, `IndexNumber` (numero), `ParentIndexNumber` (stagione); `Movie` e `Episode` in `MediaBrowser.Controller.Entities.Movies` / `.TV`.

**Test**
- `FakeServer` implementa `ISessionDirectory`, `IUserDirectory`, `ILibraryAccess` (`Unseen`, `LibraryFails`), `IRecommendationLibrary` (`Watched`, `LastWatched` lancia con `LibraryFails`), `IEventSender` (`SentTo`). `AddUser(name, enabled: …)`, `AddSession(id, user)`.
- `TestRecommendations.Friends(server, folder, time)` e `MakeFriendsAsync(friends, a, b)`; `TempFolder`, `InterfaceStub<T>` (`Handlers["add_PlaybackStart"]`, `Calls`), `FakeAuthorizationContext(AuthorizationInfo)`, `FakeTimeProvider`.
- Utenti di Jellyfin nei test dei controller: `new User("mario", "provider", "reset")` e la stessa id in `FakeServer.Users`; nei test `FindCaller` trova la sessione con `SessionId == DeviceId`.

## File

| File | Responsabilità |
|---|---|
| `Hub/ActivityFile.cs` | contenuto di `activity.json` |
| `Hub/ActivityBook.cs` | scelte e visioni in memoria: registrazione, tetto, spegnimento, pulizia, file |
| `Hub/ActivityStore.cs` | il file su disco |
| `Hub/IPlaybackDirectory.cs` | `PlayingTitle`, `AppPlayback`, `PlaybackReport` e l'interfaccia delle riproduzioni |
| `Hub/ActivityService.cs` | regole: condivisione, registrazione, "Sta guardando", posizione, riga, pulizia |
| `Protocol/ActivityDtos.cs` | `FriendNowPlaying`, `FriendPosition`, impostazioni, riga |
| `Protocol/FriendDtos.cs`, `Hub/FriendService.cs` (modifiche) | `NowPlaying` in `FriendEntry` |
| `Api/FriendsController.cs` (modifica), `Api/ActivityController.cs` | endpoint |
| `Server/PlayingTitles.cs`, `Server/JellyfinPlaybackDirectory.cs` | adattatori di Jellyfin |
| `ActivityHostedService.cs` | eventi di riproduzione, avvio e pulizia |
| `PluginServiceRegistrator.cs`, `Home/HomeRowIds.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `Plugin.cs`, `../meta.template.json`, `../README.md` (modifiche) | montaggio, riga, versione, documentazione |

Tutti i percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test), se non è detto altro.

---

## Gruppo A — archivio e regole

### Task 1: `ActivityBook`, `ActivityFile`, `ActivityStore`

**Files:**
- Create: `Hub/ActivityFile.cs`, `Hub/ActivityBook.cs`, `Hub/ActivityStore.cs`
- Modify: `Tests/TempFolder.cs`
- Test: `Tests/ActivityBookTests.cs`, `Tests/ActivityStoreTests.cs`

**Interfaces:**
- Produces:
  - `record WatchedTitle(Guid ItemId, DateTimeOffset WatchedAt)`;
  - `ActivityBook` con `MaxTitles = 100`, `bool Shares(Guid)`, `bool SetShare(Guid, bool)`, `bool Record(Guid userId, Guid itemId, DateTimeOffset at)`, `IReadOnlyList<WatchedTitle> Views(Guid)` (dal più recente), `int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists)`, `static ActivityBook FromFile(ActivityFile)`, `ActivityFile ToFile()`;
  - `ActivityStore(string filePath, ILogger<ActivityStore>)` con `FileName = "activity.json"`, `FilePath`, `static DefaultPath(IApplicationPaths)`, `ActivityBook Load()`, `void Save(ActivityBook)`;
  - `TempFolder.ActivityFile`.

- [ ] **Step 1: test che falliscono**

In `Tests/TempFolder.cs`, dopo `RecommendationsFile`:

```csharp
    /// <summary>Percorso di activity.json, accanto a inbox.json.</summary>
    public string ActivityFile => System.IO.Path.Combine(Path, "WonderFlixWatchParty", "activity.json");
```

`Tests/ActivityBookTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ActivityBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 13, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ATitleIsKeptOnceWithItsLatestDate()
    {
        var book = new ActivityBook();
        var user = Guid.NewGuid();
        var dune = Guid.NewGuid();
        var bear = Guid.NewGuid();

        Assert.True(book.Record(user, dune, Now));
        book.Record(user, bear, Now.AddMinutes(1));
        book.Record(user, dune, Now.AddMinutes(2));

        Assert.Equal(
            new[] { new WatchedTitle(dune, Now.AddMinutes(2)), new WatchedTitle(bear, Now.AddMinutes(1)) },
            book.Views(user));
        Assert.Empty(book.Views(Guid.NewGuid()));
    }

    [Fact]
    public void OverTheCapTheOldestTitleLeaves()
    {
        var book = new ActivityBook();
        var user = Guid.NewGuid();
        var first = Guid.NewGuid();
        book.Record(user, first, Now);
        for (var i = 1; i <= ActivityBook.MaxTitles; i++)
        {
            book.Record(user, Guid.NewGuid(), Now.AddMinutes(i));
        }

        var views = book.Views(user);
        Assert.Equal(ActivityBook.MaxTitles, views.Count);
        Assert.DoesNotContain(views, v => v.ItemId == first);
    }

    [Fact]
    public void TurningSharingOffDeletesTheViewsAndStopsRecording()
    {
        var book = new ActivityBook();
        var user = Guid.NewGuid();
        Assert.True(book.Shares(user));
        book.Record(user, Guid.NewGuid(), Now);

        Assert.True(book.SetShare(user, false));
        Assert.False(book.Shares(user));
        Assert.Empty(book.Views(user));
        Assert.False(book.Record(user, Guid.NewGuid(), Now));
        Assert.Empty(book.Views(user));
        Assert.False(book.SetShare(user, false));

        // Riaccesa: si registra di nuovo, ma le visioni cancellate non tornano.
        Assert.True(book.SetShare(user, true));
        Assert.True(book.Shares(user));
        Assert.Empty(book.Views(user));
        Assert.False(book.SetShare(user, true));
    }

    [Fact]
    public void PruneDropsOldViewsAndMissingUsers()
    {
        var book = new ActivityBook();
        var mario = Guid.NewGuid();
        var gone = Guid.NewGuid();
        var hiddenGone = Guid.NewGuid();
        var old = Guid.NewGuid();
        var recent = Guid.NewGuid();
        book.Record(mario, old, Now.AddDays(-31));
        book.Record(mario, recent, Now.AddDays(-1));
        book.Record(gone, recent, Now);
        book.SetShare(hiddenGone, false);

        // La visione vecchia, quella di chi non c'è più e la scelta di chi non c'è più.
        Assert.Equal(3, book.Prune(Now.AddDays(-30), id => id == mario));
        Assert.Equal(new[] { new WatchedTitle(recent, Now.AddDays(-1)) }, book.Views(mario));
        Assert.Empty(book.Views(gone));
        Assert.True(book.Shares(hiddenGone));
        Assert.Equal(0, book.Prune(Now.AddDays(-30), id => id == mario));
    }

    [Fact]
    public void TheFileRoundTrips()
    {
        var book = new ActivityBook();
        var mario = Guid.NewGuid();
        var luigi = Guid.NewGuid();
        var dune = Guid.NewGuid();
        book.Record(mario, dune, Now);
        book.SetShare(luigi, false);

        var file = book.ToFile();
        var copy = ActivityBook.FromFile(JsonSerializer.Deserialize<ActivityFile>(JsonSerializer.Serialize(file))!);

        Assert.Equal(book.Views(mario), copy.Views(mario));
        Assert.False(copy.Shares(luigi));
        Assert.True(copy.Shares(mario));
        Assert.Equal(dune.ToString("N"), file.Users![mario.ToString("N")]![0]!.ItemId);
        Assert.Equal(new[] { luigi.ToString("N") }, file.Hidden);
    }

    [Fact]
    public void AHiddenUserInTheFileHasNoViews()
    {
        var mario = Guid.NewGuid().ToString("N");
        var file = new ActivityFile
        {
            Hidden = [mario],
            Users = new() { [mario] = [new ActivityFileView { ItemId = Guid.NewGuid().ToString("N"), WatchedAt = Now }] },
        };

        var book = ActivityBook.FromFile(file);

        Assert.Empty(book.Views(Guid.Parse(mario)));
        Assert.False(book.Shares(Guid.Parse(mario)));
    }

    [Theory]
    [InlineData("{\"Users\":{\"x\":[]}}")]
    [InlineData("{\"Users\":{\"0f8fad5bd9cb469fa16570867728950e\":[{\"ItemId\":\"y\"}]}}")]
    [InlineData("{\"Users\":{\"0f8fad5bd9cb469fa16570867728950e\":[null]}}")]
    [InlineData("{\"Users\":{\"0f8fad5bd9cb469fa16570867728950e\":null}}")]
    [InlineData("{\"Hidden\":[\"x\"]}")]
    [InlineData("{\"Hidden\":[null]}")]
    public void ABrokenFileIsAFormatError(string json) =>
        Assert.Throws<FormatException>(() => ActivityBook.FromFile(JsonSerializer.Deserialize<ActivityFile>(json)!));
}
```

`Tests/ActivityStoreTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityStoreTests : IDisposable
{
    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private ActivityStore Store() => new(_folder.ActivityFile, NullLogger<ActivityStore>.Instance);

    [Fact]
    public void AMissingFileIsAnEmptyBook()
    {
        var book = Store().Load();

        Assert.Empty(book.Views(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.ActivityFile));
    }

    [Fact]
    public void SavedViewsAndChoicesComeBack()
    {
        var mario = Guid.NewGuid();
        var luigi = Guid.NewGuid();
        var dune = Guid.NewGuid();
        var at = new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero);
        var book = new ActivityBook();
        book.Record(mario, dune, at);
        book.SetShare(luigi, false);

        Store().Save(book);
        var loaded = Store().Load();

        Assert.Equal(new[] { new WatchedTitle(dune, at) }, loaded.Views(mario));
        Assert.False(loaded.Shares(luigi));
        Assert.False(File.Exists(_folder.ActivityFile + ".tmp"));
    }

    [Fact]
    public void AnUnreadableFileMovesToBadAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ActivityFile)!);
        File.WriteAllText(_folder.ActivityFile, "{ rotto");

        var book = Store().Load();

        Assert.Empty(book.Views(Guid.NewGuid()));
        Assert.True(File.Exists(_folder.ActivityFile + ".bad"));
        Assert.False(File.Exists(_folder.ActivityFile));
    }

    [Fact]
    public void AnUnreadableFileThatCannotMoveStillStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ActivityFile)!);
        File.WriteAllText(_folder.ActivityFile, "{\"Hidden\":[\"x\"]}");

        // Una cartella al posto di activity.json.bad: File.Move(..., overwrite: true) fallisce.
        Directory.CreateDirectory(_folder.ActivityFile + ".bad");

        var book = Store().Load();

        Assert.True(book.Shares(Guid.NewGuid()));
    }

    [Fact]
    public void TheDefaultPathIsNextToTheInbox()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");

        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "activity.json"),
            ActivityStore.DefaultPath(paths));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ActivityBookTests|FullyQualifiedName~ActivityStoreTests"`
Expected: errore di compilazione (`ActivityBook`, `ActivityFile`, `ActivityStore` non esistono).

- [ ] **Step 3: il codice**

`Hub/ActivityFile.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di activity.json (spec O §6.1 e §6.4, piano 21a decisione 1):
/// chi ha spento "Mostra agli amici cosa guardo" e, per ogni utente (id in
/// formato "N"), i film e le serie guardati. Tutto nullable: un file scritto
/// a mano o rovinato si scopre in <see cref="ActivityBook.FromFile"/>.
/// </summary>
public sealed class ActivityFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    /// <summary>Chi non mostra cosa guarda, in formato "N"; chi non c'è mostra.</summary>
    [JsonPropertyName("Hidden")]
    public List<string?>? Hidden { get; set; } = [];

    [JsonPropertyName("Users")]
    public Dictionary<string, List<ActivityFileView?>?>? Users { get; set; } = [];
}

/// <summary>Una visione, nel file.</summary>
public sealed class ActivityFileView
{
    /// <summary>Il film o la serie, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("WatchedAt")]
    public DateTimeOffset WatchedAt { get; set; }
}
```

`Hub/ActivityBook.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Una visione registrata (spec O §6.4): il film o la serie, e l'ultima volta.</summary>
public sealed record WatchedTitle(Guid ItemId, DateTimeOffset WatchedAt);

/// <summary>
/// L'attività in memoria (spec O §6.1 e §6.4): chi non mostra cosa guarda
/// e le visioni di ognuno. Non è sicuro tra thread: lo usa solo
/// ActivityService, sotto lock.
/// </summary>
public sealed class ActivityBook
{
    /// <summary>Titoli al massimo per utente: oltre esce quello visto meno di recente.</summary>
    public const int MaxTitles = 100;

    private readonly HashSet<Guid> _hidden = [];
    private readonly Dictionary<Guid, List<WatchedTitle>> _users = [];

    /// <summary>L'utente mostra agli amici cosa guarda (acceso se non l'ha mai cambiato).</summary>
    public bool Shares(Guid userId) => !_hidden.Contains(userId);

    /// <summary>
    /// Cambia la scelta; spenta, toglie anche le visioni dell'utente. True se
    /// qualcosa è cambiato.
    /// </summary>
    public bool SetShare(Guid userId, bool share)
    {
        if (share)
        {
            return _hidden.Remove(userId);
        }

        var removed = _users.Remove(userId);
        return _hidden.Add(userId) || removed;
    }

    /// <summary>
    /// La visione del titolo: se c'era già si aggiorna la data. Niente (false)
    /// se l'utente non mostra cosa guarda.
    /// </summary>
    public bool Record(Guid userId, Guid itemId, DateTimeOffset at)
    {
        if (!Shares(userId))
        {
            return false;
        }

        if (!_users.TryGetValue(userId, out var titles))
        {
            titles = [];
            _users[userId] = titles;
        }

        titles.RemoveAll(t => t.ItemId == itemId);
        titles.Add(new WatchedTitle(itemId, at));
        if (titles.Count > MaxTitles)
        {
            titles.Remove(titles.MinBy(t => t.WatchedAt)!);
        }

        return true;
    }

    /// <summary>Le visioni dell'utente, dalla più recente.</summary>
    public IReadOnlyList<WatchedTitle> Views(Guid userId) =>
        _users.TryGetValue(userId, out var titles) ? titles.OrderByDescending(t => t.WatchedAt).ToList() : [];

    /// <summary>
    /// Pulizia (spec O §6.4): toglie le visioni prima di cutoff e gli utenti
    /// che non esistono più, scelte comprese. Restituisce quante voci ha tolto.
    /// </summary>
    public int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists)
    {
        var removed = _hidden.RemoveWhere(id => !userExists(id));
        foreach (var (userId, titles) in _users.ToList())
        {
            if (!userExists(userId))
            {
                removed += titles.Count;
                _users.Remove(userId);
                continue;
            }

            removed += titles.RemoveAll(t => t.WatchedAt < cutoff);
            if (titles.Count == 0)
            {
                _users.Remove(userId);
            }
        }

        return removed;
    }

    /// <summary>Dal file; FormatException se un utente o una visione non è valida.</summary>
    public static ActivityBook FromFile(ActivityFile file)
    {
        var book = new ActivityBook();
        foreach (var raw in file.Hidden ?? [])
        {
            if (!Guid.TryParse(raw, out var userId))
            {
                throw new FormatException("scelta di un utente non valida");
            }

            book._hidden.Add(userId);
        }

        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("visioni di un utente non valide");
            }

            foreach (var view in value)
            {
                if (view is null || !Guid.TryParse(view.ItemId, out var itemId))
                {
                    throw new FormatException("visione non valida");
                }

                // Chi ha spento non ha visioni, anche se il file ne avesse.
                book.Record(userId, itemId, view.WatchedAt);
            }
        }

        return book;
    }

    public ActivityFile ToFile() => new()
    {
        Hidden = _hidden.Select(id => (string?)id.ToString("N")).ToList(),
        Users = _users.ToDictionary(
            pair => pair.Key.ToString("N"),
            pair => (List<ActivityFileView?>?)pair.Value
                .OrderByDescending(t => t.WatchedAt)
                .Select(t => (ActivityFileView?)new ActivityFileView { ItemId = t.ItemId.ToString("N"), WatchedAt = t.WatchedAt })
                .ToList()),
    };
}
```

`Hub/ActivityStore.cs`:

```csharp
using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// activity.json su disco (spec O §6.1, piano 21a decisione 1), accanto a
/// inbox.json nelle configurazioni dei plugin. Non è sicuro tra thread: lo
/// usa solo ActivityService, sotto lock.
/// </summary>
public sealed class ActivityStore(string filePath, ILogger<ActivityStore> logger)
{
    public const string FileName = "activity.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// activity.json.bad e si riparte vuoti; se non si riesce a spostarlo si
    /// riparte vuoti lo stesso (il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public ActivityBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new ActivityBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<ActivityFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return ActivityBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Attività degli amici illeggibile: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Come i consigli: lo spostamento è una copia di cortesia. Nel log solo il percorso.
                logger.LogWarning(moveError, "Attività degli amici illeggibile e non spostabile in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new ActivityBook();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(ActivityBook book)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, book.ToFile(), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia il file vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): activity book and activity.json store"
```

### Task 2: `ActivityService`, condivisione e registrazione

**Files:**
- Create: `Hub/IPlaybackDirectory.cs`, `Hub/ActivityService.cs`
- Modify: `Tests/FakeServer.cs`
- Create: `Tests/TestActivity.cs`
- Test: `Tests/ActivityServiceTests.cs`

**Interfaces:**
- Consumes: `ActivityBook`, `ActivityStore`, `WatchedTitle` (Task 1); `FriendService`, `IUserDirectory`, `ISessionDirectory`, `PartyRegistry`, `ILibraryAccess`, `IRecommendationLibrary`, `PresenceTracker` (esistenti).
- Produces:
  - `record PlayingTitle(Guid ItemId, string Name, Guid? TitleId, Guid? SeriesId, string? SeriesName, int? Season, int? Episode)`;
  - `record AppPlayback(string SessionId, Guid UserId, PlayingTitle Item, long PositionTicks, DateTimeOffset LastCheckIn)`;
  - `record PlaybackReport(string SessionId, Guid UserId, Guid? TitleId, long PositionTicks, bool Completed)`;
  - `interface IPlaybackDirectory { IReadOnlyList<AppPlayback> GetAppPlayback(); }`;
  - `ActivityService` (costruttore sotto) con `MinWatch` (5 min), `MaxAge` (30 giorni), `Load()`, `bool Shares(Guid)`, `void SetShare(Guid, bool)`, `void PlaybackChanged(Guid)`, `void Report(PlaybackReport, bool stopped)`, `int Cleanup()`;
  - `FakeServer.Playback`, `FakeServer.PlaybackFails`;
  - `TestActivity.Create(...)`, `TestActivity.Report(...)`, `TestActivity.Movie(...)`.

- [ ] **Step 1: test che falliscono**

In `Tests/FakeServer.cs`:
- aggiungi `IPlaybackDirectory` all'elenco delle interfacce della classe;
- in fondo alla classe, prima di `TrySendAsync`:

```csharp
    /// <summary>Le riproduzioni nelle sessioni WonderFlix (spec O).</summary>
    public List<AppPlayback> Playback { get; } = [];

    /// <summary>Se true, leggere le riproduzioni lancia, come un errore di Jellyfin.</summary>
    public bool PlaybackFails { get; set; }

    public IReadOnlyList<AppPlayback> GetAppPlayback() =>
        PlaybackFails ? throw new InvalidOperationException("sessioni non disponibili") : Playback;
```

`Tests/TestActivity.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>L'attività dei test: server finto, amici e presenza veri, file in una cartella temporanea.</summary>
internal static class TestActivity
{
    // friends e registry servono dal Task 3 (il costruttore del Task 2 non li prende ancora).
    public static ActivityService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, PresenceTracker presence,
        PartyRegistry? registry = null) =>
        new(
            new ActivityStore(folder.ActivityFile, NullLogger<ActivityStore>.Instance),
            server, server, presence, time, NullLogger<ActivityService>.Instance);

    /// <summary>Le visioni salvate di un utente, rilette dal file.</summary>
    public static IReadOnlyList<WatchedTitle> Saved(TempFolder folder, Guid userId) =>
        new ActivityStore(folder.ActivityFile, NullLogger<ActivityStore>.Instance).Load().Views(userId);

    public static PlaybackReport Report(CallerSession session, Guid? titleId, TimeSpan position, bool completed = false) =>
        new(session.SessionId, session.UserId, titleId, position.Ticks, completed);

    public static AppPlayback Movie(
        CallerSession session, Guid movieId, string name = "Dune", TimeSpan position = default, DateTimeOffset checkIn = default) =>
        new(session.SessionId, session.UserId, new PlayingTitle(movieId, name, movieId, null, null, null, null), position.Ticks, checkIn);
}
```

`Tests/ActivityServiceTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityServiceTests : IDisposable
{
    private static readonly string FriendsChanged = JsonSerializer.Serialize(SocialEvent.FriendsChanged());

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ActivityService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly CallerSession _session;

    public ActivityServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _service = TestActivity.Create(_server, _folder, _time, _friends, _presence);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _session = _server.AddSession("s-mario", _mario);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public void AViewIsRecordedAfterFiveMinutesOnce()
    {
        var dune = Guid.NewGuid();
        var start = _time.GetUtcNow();

        _service.Report(TestActivity.Report(_session, dune, ActivityService.MinWatch - TimeSpan.FromSeconds(1)), stopped: false);
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));

        _service.Report(TestActivity.Report(_session, dune, ActivityService.MinWatch), stopped: false);
        Assert.Equal(new[] { new WatchedTitle(dune, start) }, TestActivity.Saved(_folder, _mario.Id));

        // Altri resoconti e lo stop della stessa visione non riscrivono la data.
        _time.Advance(TimeSpan.FromMinutes(2));
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(7)), stopped: false);
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(8)), stopped: true);
        Assert.Equal(new[] { new WatchedTitle(dune, start) }, TestActivity.Saved(_folder, _mario.Id));

        // Dopo lo stop, una nuova visione aggiorna la data.
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(9)), stopped: false);
        Assert.Equal(new[] { new WatchedTitle(dune, _time.GetUtcNow()) }, TestActivity.Saved(_folder, _mario.Id));
    }

    [Fact]
    public void AFinishedOrLongStopIsRecorded()
    {
        var short1 = Guid.NewGuid();
        var finished = Guid.NewGuid();
        var longStop = Guid.NewGuid();

        _service.Report(TestActivity.Report(_session, short1, TimeSpan.FromMinutes(2)), stopped: true);
        _service.Report(TestActivity.Report(_session, finished, TimeSpan.FromMinutes(1), completed: true), stopped: true);
        _service.Report(TestActivity.Report(_session, longStop, ActivityService.MinWatch), stopped: true);

        var saved = TestActivity.Saved(_folder, _mario.Id).Select(v => v.ItemId).ToList();
        Assert.DoesNotContain(short1, saved);
        Assert.Contains(finished, saved);
        Assert.Contains(longStop, saved);
    }

    [Fact]
    public void AnEpisodeWithoutSeriesIsNotRecorded()
    {
        _service.Report(TestActivity.Report(_session, null, TimeSpan.FromMinutes(30)), stopped: false);
        _service.Report(TestActivity.Report(_session, null, TimeSpan.FromMinutes(40), completed: true), stopped: true);

        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));
    }

    [Fact]
    public void NothingIsRecordedWhileSharingIsOff()
    {
        Assert.True(_service.Shares(_mario.Id));
        _service.SetShare(_mario.Id, false);
        Assert.False(_service.Shares(_mario.Id));

        _service.Report(TestActivity.Report(_session, Guid.NewGuid(), TimeSpan.FromMinutes(10)), stopped: false);
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));

        _service.SetShare(_mario.Id, true);
        var bear = Guid.NewGuid();
        _service.Report(TestActivity.Report(_session, bear, TimeSpan.FromMinutes(10)), stopped: false);
        Assert.Equal(bear, Assert.Single(TestActivity.Saved(_folder, _mario.Id)).ItemId);
    }

    [Fact]
    public async Task TurningSharingOffDeletesTheViewsAndTellsTheFriends()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        _server.AddSession("s-luigi", _luigi);
        _service.Report(TestActivity.Report(_session, Guid.NewGuid(), TimeSpan.FromMinutes(10)), stopped: false);
        _server.Sent.Clear();

        _service.SetShare(_mario.Id, false);
        _time.Advance(PresenceTracker.Delay);

        Assert.Equal(new[] { FriendsChanged }, _server.SentTo("s-luigi"));
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));
        Assert.False(new ActivityStore(_folder.ActivityFile, NullLogger<ActivityStore>.Instance).Load().Shares(_mario.Id));

        // Già spenta: niente da dire agli amici.
        _server.Sent.Clear();
        _service.SetShare(_mario.Id, false);
        _time.Advance(PresenceTracker.Delay);
        Assert.Empty(_server.SentTo("s-luigi"));
    }

    [Fact]
    public async Task PlaybackChangesTellTheFriendsOnlyWhenSharing()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        _server.AddSession("s-luigi", _luigi);
        _server.Sent.Clear();

        _service.PlaybackChanged(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(new[] { FriendsChanged }, _server.SentTo("s-luigi"));

        _service.SetShare(_mario.Id, false);
        _time.Advance(PresenceTracker.Delay);
        _server.Sent.Clear();

        _service.PlaybackChanged(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Empty(_server.SentTo("s-luigi"));
    }

    [Fact]
    public void CleanupDropsOldViewsAndForgetsEndedSessions()
    {
        var dune = Guid.NewGuid();
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(6)), stopped: false);

        // La sessione finisce senza stop: alla pulizia si dimentica, e una visione nuova si registra.
        _server.Sessions.Remove(_session);
        _time.Advance(TimeSpan.FromHours(1));
        Assert.Equal(0, _service.Cleanup());
        _service.Report(TestActivity.Report(_session, dune, TimeSpan.FromMinutes(7)), stopped: false);
        Assert.Equal(_time.GetUtcNow(), Assert.Single(TestActivity.Saved(_folder, _mario.Id)).WatchedAt);

        _time.Advance(ActivityService.MaxAge + TimeSpan.FromMinutes(1));
        Assert.Equal(1, _service.Cleanup());
        Assert.Empty(TestActivity.Saved(_folder, _mario.Id));
    }

    [Fact]
    public void CleanupForgetsUsersThatNoLongerExist()
    {
        _service.Report(TestActivity.Report(_session, Guid.NewGuid(), TimeSpan.FromMinutes(6)), stopped: false);
        _service.SetShare(_luigi.Id, false);
        _server.Users.Remove(_mario.Id);
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(2, _service.Cleanup());
        var saved = new ActivityStore(_folder.ActivityFile, NullLogger<ActivityStore>.Instance).Load();
        Assert.Empty(saved.Views(_mario.Id));
        Assert.True(saved.Shares(_luigi.Id));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ActivityServiceTests"`
Expected: errore di compilazione (`IPlaybackDirectory`, `AppPlayback`, `ActivityService` non esistono).

- [ ] **Step 3: il codice**

`Hub/IPlaybackDirectory.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un film o un episodio in riproduzione (spec O §6.2). TitleId è quello che
/// si registra: il film, o la serie dell'episodio; null per un episodio
/// senza serie (piano 21a, decisione 7).
/// </summary>
public sealed record PlayingTitle(
    Guid ItemId, string Name, Guid? TitleId, Guid? SeriesId, string? SeriesName, int? Season, int? Episode);

/// <summary>
/// Una riproduzione in una sessione WonderFlix: la posizione (Jellyfin la fa
/// avanzare da sé ogni secondo, piano 21a decisione 4) e l'ultimo resoconto
/// dell'app.
/// </summary>
public sealed record AppPlayback(
    string SessionId, Guid UserId, PlayingTitle Item, long PositionTicks, DateTimeOffset LastCheckIn);

/// <summary>
/// Un resoconto vero di una sessione WonderFlix (spec O §6.3–6.4), da un
/// evento di riproduzione: il film o la serie (null per un episodio senza
/// serie), la posizione e se è arrivato alla fine.
/// </summary>
public sealed record PlaybackReport(string SessionId, Guid UserId, Guid? TitleId, long PositionTicks, bool Completed);

/// <summary>Le riproduzioni del server (adattatore di ISessionManager).</summary>
public interface IPlaybackDirectory
{
    /// <summary>I film e gli episodi in riproduzione nelle sessioni WonderFlix con un utente.</summary>
    IReadOnlyList<AppPlayback> GetAppPlayback();
}
```

`Hub/ActivityService.cs` (la parte di lettura arriva nel Task 3):

```csharp
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Cosa guardano gli amici (spec O §6): "Mostra agli amici cosa guardo",
/// registro delle visioni WonderFlix, "Sta guardando", posizione per
/// "Guarda insieme", riga "Visti dagli amici" e pulizia. File con
/// <see cref="ActivityStore"/>. Sicuro tra thread.
/// </summary>
public sealed class ActivityService(
    ActivityStore store,
    IUserDirectory users,
    ISessionDirectory sessions,
    PresenceTracker presence,
    TimeProvider time,
    ILogger<ActivityService> logger)
{
    /// <summary>Posizione da cui una riproduzione conta come visione (spec O §6.4).</summary>
    public static readonly TimeSpan MinWatch = TimeSpan.FromMinutes(5);

    /// <summary>Quanto resta una visione nel registro e nella riga (spec O §6.4, §6.6).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    private readonly Lock _lock = new();

    // Solo sotto _lock: le visioni già registrate, per sessione e titolo (piano 21a, decisione 8).
    private readonly HashSet<(string SessionId, Guid TitleId)> _recorded = [];

    private ActivityBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private ActivityBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Attività degli amici in {Path}", store.FilePath);
            }

            return _book;
        }
    }

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Book;
        }
    }

    /// <summary>L'utente mostra agli amici cosa guarda (acceso se non l'ha mai cambiato).</summary>
    public bool Shares(Guid userId)
    {
        lock (_lock)
        {
            return Book.Shares(userId);
        }
    }

    /// <summary>
    /// "Mostra agli amici cosa guardo" (spec O §6.1): spenta, le visioni
    /// dell'utente si cancellano. Se è cambiata, gli amici rileggono.
    /// </summary>
    public void SetShare(Guid userId, bool share)
    {
        bool changed;
        lock (_lock)
        {
            changed = Book.SetShare(userId, share);
            if (changed)
            {
                Persist();
            }
        }

        if (changed)
        {
            logger.LogDebug("Condivisione dell'attività di {UserId}: {Share}", userId, share);
            presence.Changed(userId);
        }
    }

    /// <summary>
    /// Una riproduzione WonderFlix è iniziata o finita (spec O §6.3): gli
    /// amici rileggono "Sta guardando", se l'utente lo mostra.
    /// </summary>
    public void PlaybackChanged(Guid userId)
    {
        if (Shares(userId))
        {
            presence.Changed(userId);
        }
    }

    /// <summary>
    /// Un resoconto vero (spec O §6.4): la visione si registra alla prima
    /// posizione oltre <see cref="MinWatch"/>, oppure allo stop se si è
    /// arrivati alla fine o oltre <see cref="MinWatch"/>; una volta per
    /// sessione e titolo (piano 21a, decisione 8).
    /// </summary>
    public void Report(PlaybackReport report, bool stopped)
    {
        var watched = report.Completed || report.PositionTicks >= MinWatch.Ticks;
        lock (_lock)
        {
            var already = report.TitleId is { } id && _recorded.Contains((report.SessionId, id));
            if (stopped)
            {
                _recorded.RemoveWhere(r => r.SessionId == report.SessionId);
            }

            if (already || !watched || report.TitleId is not { } titleId)
            {
                return;
            }

            if (!stopped)
            {
                _recorded.Add((report.SessionId, titleId));
            }

            if (Book.Record(report.UserId, titleId, time.GetUtcNow()))
            {
                Persist();
                logger.LogDebug("Visione di {ItemId} registrata per {UserId}", Id(titleId), report.UserId);
            }
        }
    }

    /// <summary>
    /// Pulizia periodica (spec O §6.4): visioni oltre <see cref="MaxAge"/>,
    /// utenti che non esistono più, sessioni finite senza stop. Restituisce
    /// quante voci ha tolto dal registro.
    /// </summary>
    public int Cleanup()
    {
        lock (_lock)
        {
            _recorded.RemoveWhere(r => !sessions.Exists(r.SessionId));
            var removed = Book.Prune(time.GetUtcNow() - MaxAge, userId => users.GetUser(userId) is not null);
            if (removed > 0)
            {
                Persist();
            }

            return removed;
        }
    }

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        try
        {
            store.Save(Book);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Attività degli amici non salvata in {Path}", store.FilePath);
        }
    }

    private static string Id(Guid id) => id.ToString("N");
}
```

Il costruttore ha solo quello che il Task 2 usa: un parametro del costruttore primario mai letto è il warning CS9113, che qui è un errore. Il Task 3 aggiunge gli altri.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): activity service with sharing and view recording"
```

### Task 3: "Sta guardando", posizione e riga "Visti dagli amici"

**Files:**
- Create: `Protocol/ActivityDtos.cs`
- Modify: `Protocol/FriendDtos.cs`, `Hub/FriendService.cs`, `Hub/ActivityService.cs`
- Test: `Tests/ActivityReadTests.cs`

**Interfaces:**
- Consumes: Task 2.
- Produces:
  - `FriendNowPlaying(ItemId, Title, SeriesId?, SeriesName?, Season?, Episode?)`, `FriendPosition(ItemId, PositionTicks)`, `ActivitySettings { bool? ShareActivity }`, `ActivitySettingsResponse(ShareActivity)`, `FriendWatcher(UserId, Name, WatchedAt)`, `FriendsWatchedItem(ItemId, By)`, `FriendsWatchedResponse(Items)` in `Protocol`;
  - `FriendEntry(..., FriendNowPlaying? NowPlaying = null)`;
  - `FriendService.GetFriends(Guid userId, Func<Guid, FriendParty?>? partyOf = null, Func<Guid, FriendNowPlaying?>? nowPlayingOf = null)`;
  - `ActivityService.NowPlayingFor(Guid viewerId, Guid friendId)` → `FriendNowPlaying?`;
  - `ActivityService.Position(Guid callerId, string? friendId)` → `HubResult<FriendPosition>` (`Conflict` se non vale);
  - `ActivityService.FriendsWatched(Guid callerId)` → `FriendsWatchedResponse`;
  - `ActivityService.MaxFriendsWatched = 30`, `MaxChecked = 60`.

- [ ] **Step 1: test che falliscono**

`Tests/ActivityReadTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityReadTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly PartyRegistry _registry = new();
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ActivityService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly CallerSession _luigiSession;

    public ActivityReadTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _service = TestActivity.Create(_server, _folder, _time, _friends, _presence, _registry);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _luigiSession = _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private Task FriendsAsync(UserRef a, UserRef b) => TestRecommendations.MakeFriendsAsync(_friends, a.Id, b.Id);

    private FriendEntry Luigi() =>
        _friends.GetFriends(_mario.Id, nowPlayingOf: f => _service.NowPlayingFor(_mario.Id, f)).Friends.Single(f => f.Name == "Luigi");

    [Fact]
    public async Task AFriendWatchingAMovieShowsIt()
    {
        await FriendsAsync(_mario, _luigi);
        var dune = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(_luigiSession, dune));

        var entry = Luigi();

        Assert.True(entry.Online);
        Assert.Equal(new FriendNowPlaying(dune.ToString("N"), "Dune", null, null, null, null), entry.NowPlaying);
    }

    [Fact]
    public async Task AnEpisodeCarriesSeriesSeasonAndNumber()
    {
        await FriendsAsync(_mario, _luigi);
        var episode = Guid.NewGuid();
        var series = Guid.NewGuid();
        _server.Playback.Add(new AppPlayback(
            "s-luigi", _luigi.Id, new PlayingTitle(episode, "Pilot", series, series, "The Bear", 2, 3), 0, default));

        Assert.Equal(
            new FriendNowPlaying(episode.ToString("N"), "Pilot", series.ToString("N"), "The Bear", 2, 3),
            Luigi().NowPlaying);
    }

    [Fact]
    public async Task NothingIsShownWithoutSharingAccessOrInAParty()
    {
        await FriendsAsync(_mario, _luigi);
        var dune = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(_luigiSession, dune));

        _service.SetShare(_luigi.Id, false);
        Assert.Null(Luigi().NowPlaying);
        _service.SetShare(_luigi.Id, true);

        _server.Unseen.Add((_mario.Id, dune));
        Assert.Null(Luigi().NowPlaying);
        Assert.True(Luigi().Online);
        _server.Unseen.Clear();

        // In un party che Mario non vede (nessun Party nella voce): niente "Sta guardando".
        _registry.Register(Guid.NewGuid(), "s-luigi", "Luigi");
        var entry = Luigi();
        Assert.Null(entry.Party);
        Assert.Null(entry.NowPlaying);
    }

    [Fact]
    public async Task TheMostRecentSessionWins()
    {
        await FriendsAsync(_mario, _luigi);
        var other = _server.AddSession("s-luigi-2", _luigi);
        var old = Guid.NewGuid();
        var recent = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(_luigiSession, recent, "Recente", checkIn: _time.GetUtcNow()));
        _server.Playback.Add(TestActivity.Movie(other, old, "Vecchio", checkIn: _time.GetUtcNow().AddMinutes(-1)));

        Assert.Equal(recent.ToString("N"), Luigi().NowPlaying!.ItemId);
    }

    [Fact]
    public async Task APlaybackErrorLeavesOnlyOnline()
    {
        await FriendsAsync(_mario, _luigi);
        _server.Playback.Add(TestActivity.Movie(_luigiSession, Guid.NewGuid()));
        _server.PlaybackFails = true;

        var entry = Luigi();

        Assert.True(entry.Online);
        Assert.Null(entry.NowPlaying);
    }

    [Fact]
    public async Task OfflineFriendsAndFriendsInAVisiblePartyAreNotAsked()
    {
        var peach = _server.AddUser("Peach");
        await FriendsAsync(_mario, _luigi);
        await FriendsAsync(_mario, peach);
        var asked = new List<Guid>();
        var party = new FriendParty(Guid.NewGuid().ToString("N"), "Dune");

        var response = _friends.GetFriends(
            _mario.Id,
            partyOf: f => party,
            nowPlayingOf: f =>
            {
                asked.Add(f);
                return null;
            });

        Assert.Empty(asked);
        Assert.Equal(party, response.Friends.Single(f => f.Name == "Luigi").Party);
    }

    [Fact]
    public async Task ThePositionIsTheFriendsCurrentOne()
    {
        var dune = Guid.NewGuid();
        var luigiId = _luigi.Id.ToString("N");

        // Non amici: 409 anche se Luigi guarda.
        _server.Playback.Add(TestActivity.Movie(_luigiSession, dune, position: TimeSpan.FromMinutes(42)));
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, luigiId).Status);

        await FriendsAsync(_mario, _luigi);
        var result = _service.Position(_mario.Id, luigiId);
        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(new FriendPosition(dune.ToString("N"), TimeSpan.FromMinutes(42).Ticks), result.Value);

        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, "x").Status);
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, null).Status);

        _server.Unseen.Add((_mario.Id, dune));
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, luigiId).Status);
        _server.Unseen.Clear();

        _server.Playback.Clear();
        Assert.Equal(HubStatus.Conflict, _service.Position(_mario.Id, luigiId).Status);
    }

    [Fact]
    public async Task FriendsWatchedGroupsTitlesNewestFirst()
    {
        var peach = _server.AddUser("Peach");
        await FriendsAsync(_mario, _luigi);
        await FriendsAsync(_mario, peach);
        var peachSession = new CallerSession("s-peach", peach.Id, "Peach");
        var dune = Guid.NewGuid();
        var bear = Guid.NewGuid();
        var start = _time.GetUtcNow();

        _service.Report(TestActivity.Report(_luigiSession, dune, TimeSpan.FromMinutes(6)), stopped: false);
        _time.Advance(TimeSpan.FromMinutes(30));
        _service.Report(TestActivity.Report(_luigiSession, bear, TimeSpan.FromMinutes(6)), stopped: false);
        _time.Advance(TimeSpan.FromMinutes(30));
        _service.Report(TestActivity.Report(peachSession, dune, TimeSpan.FromMinutes(6)), stopped: false);

        var items = _service.FriendsWatched(_mario.Id).Items;

        Assert.Equal(new[] { dune.ToString("N"), bear.ToString("N") }, items.Select(i => i.ItemId));
        Assert.Equal(
            new[]
            {
                new FriendWatcher(peach.Id.ToString("N"), "Peach", start.AddHours(1)),
                new FriendWatcher(_luigi.Id.ToString("N"), "Luigi", start),
            },
            items[0].By);
        Assert.Equal(new[] { new FriendWatcher(_luigi.Id.ToString("N"), "Luigi", start.AddMinutes(30)) }, items[1].By);
    }

    [Fact]
    public async Task FriendsWatchedSkipsWhatTheViewerSawCannotSeeOrIsOldOrNotFromFriends()
    {
        var peach = _server.AddUser("Peach");
        var toad = _server.AddUser("Toad");
        await FriendsAsync(_mario, _luigi);
        await FriendsAsync(_mario, toad);
        var old = Guid.NewGuid();
        var seen = Guid.NewGuid();
        var hidden = Guid.NewGuid();
        var stranger = Guid.NewGuid();
        var disabled = Guid.NewGuid();
        var kept = Guid.NewGuid();

        _service.Report(TestActivity.Report(_luigiSession, old, TimeSpan.FromMinutes(6)), stopped: false);
        _time.Advance(ActivityService.MaxAge + TimeSpan.FromMinutes(1));
        _service.Report(TestActivity.Report(_luigiSession, seen, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(_luigiSession, hidden, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(_luigiSession, kept, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(new CallerSession("s-peach", peach.Id, "Peach"), stranger, TimeSpan.FromMinutes(6)), stopped: false);
        _service.Report(TestActivity.Report(new CallerSession("s-toad", toad.Id, "Toad"), disabled, TimeSpan.FromMinutes(6)), stopped: false);
        _server.Watched[(_mario.Id, seen)] = _time.GetUtcNow().AddYears(-1);
        _server.Unseen.Add((_mario.Id, hidden));
        _server.Users[toad.Id] = toad with { Enabled = false };

        var items = _service.FriendsWatched(_mario.Id).Items;

        Assert.Equal(new[] { kept.ToString("N") }, items.Select(i => i.ItemId));
    }

    [Fact]
    public async Task FriendsWatchedStopsAtThirty()
    {
        await FriendsAsync(_mario, _luigi);
        for (var i = 0; i < 35; i++)
        {
            _service.Report(TestActivity.Report(_luigiSession, Guid.NewGuid(), TimeSpan.FromMinutes(6)), stopped: false);
            _time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.Equal(ActivityService.MaxFriendsWatched, _service.FriendsWatched(_mario.Id).Items.Count);
    }

    [Fact]
    public async Task ALibraryErrorSkipsTheTitle()
    {
        await FriendsAsync(_mario, _luigi);
        _service.Report(TestActivity.Report(_luigiSession, Guid.NewGuid(), TimeSpan.FromMinutes(6)), stopped: false);
        _server.LibraryFails = true;

        Assert.Empty(_service.FriendsWatched(_mario.Id).Items);
    }

    [Fact]
    public void NowPlayingIsLeftOutWhenMissing()
    {
        var plain = JsonSerializer.Serialize(new FriendEntry("u", "Luigi", true, null));
        Assert.DoesNotContain("NowPlaying", plain, StringComparison.Ordinal);
        Assert.Contains("\"Party\":null", plain, StringComparison.Ordinal);

        var movie = JsonSerializer.Serialize(new FriendEntry("u", "Luigi", true, null, new FriendNowPlaying("i", "Dune", null, null, null, null)));
        Assert.Contains("\"NowPlaying\":{\"ItemId\":\"i\",\"Title\":\"Dune\"}", movie, StringComparison.Ordinal);
    }
}
```

(Se `UserRef` non è un `record` positional e `with` non compila, costruisci un nuovo `UserRef(toad.Id, "Toad", false, true, false)`.)

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ActivityReadTests"`
Expected: errore di compilazione (`FriendNowPlaying`, `NowPlayingFor`, `Position`, `FriendsWatched` non esistono).

- [ ] **Step 3: il codice**

`Protocol/ActivityDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Cosa sta guardando un amico (spec O §6.2): il film o l'episodio; per un
/// episodio anche serie, stagione e numero, ognuno assente se Jellyfin non
/// lo conosce.
/// </summary>
public sealed record FriendNowPlaying(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("SeriesId")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SeriesId,
    [property: JsonPropertyName("SeriesName")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SeriesName,
    [property: JsonPropertyName("Season")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? Season,
    [property: JsonPropertyName("Episode")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? Episode);

/// <summary>Risposta di GET Friends/{userId}/NowPlaying (spec O §6.5): l'elemento e dove è arrivato l'amico.</summary>
public sealed record FriendPosition(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("PositionTicks")] long PositionTicks);

/// <summary>Corpo di PUT Activity/Settings.</summary>
public sealed class ActivitySettings
{
    [JsonPropertyName("ShareActivity")]
    public bool? ShareActivity { get; set; }
}

/// <summary>Risposta di GET Activity/Settings.</summary>
public sealed record ActivitySettingsResponse(
    [property: JsonPropertyName("ShareActivity")] bool ShareActivity);

/// <summary>Un amico che ha visto il titolo, e quando l'ultima volta.</summary>
public sealed record FriendWatcher(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("WatchedAt")] DateTimeOffset WatchedAt);

/// <summary>Un titolo della riga "Visti dagli amici", con chi l'ha visto dal più recente.</summary>
public sealed record FriendsWatchedItem(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("By")] IReadOnlyList<FriendWatcher> By);

/// <summary>Risposta di GET Activity/FriendsWatched (spec O §6.6).</summary>
public sealed record FriendsWatchedResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<FriendsWatchedItem> Items);
```

In `Protocol/FriendDtos.cs`, `FriendEntry` diventa:

```csharp
/// <summary>Un amico, con il suo stato; NowPlaying (spec O §6.2) manca se non vale.</summary>
public sealed record FriendEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Online")] bool Online,
    [property: JsonPropertyName("Party")] FriendParty? Party,
    [property: JsonPropertyName("NowPlaying")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] FriendNowPlaying? NowPlaying = null);
```

In `Hub/FriendService.cs`, `GetFriends`:

```csharp
    /// <summary>
    /// Amici e richieste. partyOf dice il party visibile in cui sta un amico
    /// online (spec F §6.3); nowPlayingOf cosa guarda un amico online fuori
    /// da un party visibile (spec O §6.2). Si chiamano fuori dal lock.
    /// </summary>
    public FriendsResponse GetFriends(
        Guid userId, Func<Guid, FriendParty?>? partyOf = null, Func<Guid, FriendNowPlaying?>? nowPlayingOf = null)
```

e nella costruzione della voce:

```csharp
        var friends = friendUsers
            .Select(u =>
            {
                var isOnline = online.Contains(u.Id);
                var party = isOnline ? partyOf?.Invoke(u.Id) : null;
                var nowPlaying = isOnline && party is null ? nowPlayingOf?.Invoke(u.Id) : null;
                return new FriendEntry(Id(u.Id), u.Name, isOnline, party, nowPlaying);
            })
            .ToList();
```

In `Hub/ActivityService.cs`:
- aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;`;
- il costruttore diventa (l'ordine conta: lo usano `TestActivity` e il DI):

```csharp
public sealed class ActivityService(
    ActivityStore store,
    FriendService friends,
    IUserDirectory users,
    ISessionDirectory sessions,
    IPlaybackDirectory playback,
    PartyRegistry registry,
    ILibraryAccess access,
    IRecommendationLibrary library,
    PresenceTracker presence,
    TimeProvider time,
    ILogger<ActivityService> logger)
```

- in `Tests/TestActivity.cs`, `Create` passa tutto (togli il commento su friends e registry):

```csharp
        new(
            new ActivityStore(folder.ActivityFile, NullLogger<ActivityStore>.Instance),
            friends, server, server, server, registry ?? new PartyRegistry(), server, server, presence, time,
            NullLogger<ActivityService>.Instance);
```

- dopo `MaxAge`:

```csharp
    /// <summary>Titoli al massimo nella riga "Visti dagli amici" (spec O §6.6).</summary>
    public const int MaxFriendsWatched = 30;

    /// <summary>Titoli al massimo controllati con la libreria per riempire la riga (spec O §6.6).</summary>
    public const int MaxChecked = 60;
```

- dopo `PlaybackChanged`:

```csharp
    /// <summary>
    /// Cosa guarda friendId, se viewerId può saperlo (spec O §6.2); null
    /// altrimenti. Non controlla l'amicizia: la chiama GET Friends solo per
    /// gli amici online fuori da un party visibile.
    /// </summary>
    public FriendNowPlaying? NowPlayingFor(Guid viewerId, Guid friendId)
    {
        if (Playing(viewerId, friendId) is not { } current)
        {
            return null;
        }

        var item = current.Item;
        return new FriendNowPlaying(
            Id(item.ItemId), item.Name, item.SeriesId is { } series ? Id(series) : null, item.SeriesName, item.Season, item.Episode);
    }

    /// <summary>
    /// Dove è arrivato l'amico, per "Guarda insieme" (spec O §6.5). Conflict
    /// se non è amico, non guarda, non lo mostra o chi chiama non vede il titolo.
    /// </summary>
    public HubResult<FriendPosition> Position(Guid callerId, string? friendId)
    {
        if (!Guid.TryParse(friendId, out var id)
            || !friends.AreFriends(callerId, id)
            || Playing(callerId, id) is not { } current)
        {
            return HubResult<FriendPosition>.Fail(HubStatus.Conflict);
        }

        return HubResult<FriendPosition>.Ok(new FriendPosition(Id(current.Item.ItemId), current.PositionTicks));
    }

    /// <summary>
    /// La riga "Visti dagli amici" (spec O §6.6): le visioni degli ultimi
    /// <see cref="MaxAge"/> degli amici attivi che mostrano cosa guardano,
    /// per titolo dal più recente, senza i titoli che chi chiama non vede o
    /// ha già visto o iniziato. Un errore della libreria salta il titolo.
    /// </summary>
    public FriendsWatchedResponse FriendsWatched(Guid callerId)
    {
        var cutoff = time.GetUtcNow() - MaxAge;
        var friendUsers = friends.FriendsOf(callerId)
            .Select(users.GetUser)
            .OfType<UserRef>()
            .Where(u => u.Enabled)
            .ToList();
        List<Candidate> candidates;
        lock (_lock)
        {
            candidates = friendUsers
                .Where(u => Book.Shares(u.Id))
                .SelectMany(u => Book.Views(u.Id).Where(v => v.WatchedAt >= cutoff).Select(v => (User: u, View: v)))
                .GroupBy(x => x.View.ItemId)
                .Select(g => new Candidate(
                    g.Key,
                    g.OrderByDescending(x => x.View.WatchedAt)
                        .Select(x => new FriendWatcher(Id(x.User.Id), x.User.Name, x.View.WatchedAt))
                        .ToList()))
                .OrderByDescending(c => c.By[0].WatchedAt)
                .Take(MaxChecked)
                .ToList();
        }

        // Fuori dal lock: domande alla libreria.
        var items = new List<FriendsWatchedItem>();
        foreach (var candidate in candidates)
        {
            if (items.Count == MaxFriendsWatched)
            {
                break;
            }

            try
            {
                if (!access.CanSee(callerId, candidate.ItemId) || library.LastWatched(callerId, candidate.ItemId) is not null)
                {
                    continue;
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Titolo {ItemId} saltato in Visti dagli amici", Id(candidate.ItemId));
                continue;
            }

            items.Add(new FriendsWatchedItem(Id(candidate.ItemId), candidate.By));
        }

        return new FriendsWatchedResponse(items);
    }

    // La riproduzione di friendId che viewerId può conoscere (spec O §6.2 e §6.5), o null.
    private AppPlayback? Playing(Guid viewerId, Guid friendId)
    {
        if (!Shares(friendId))
        {
            return null;
        }

        try
        {
            // Un party, anche nascosto a chi guarda, non si rivela con "Sta guardando" (piano 21a, decisione 6).
            if (sessions.GetAppSessions().Any(s => s.UserId == friendId && registry.GroupOf(s.SessionId) is not null))
            {
                return null;
            }

            var current = playback.GetAppPlayback().Where(p => p.UserId == friendId).MaxBy(p => p.LastCheckIn);
            return current is not null && access.CanSee(viewerId, current.Item.ItemId) ? current : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Riproduzione di {UserId} non letta", friendId);
            return null;
        }
    }

    private sealed record Candidate(Guid ItemId, List<FriendWatcher> By);
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `--filter "FullyQualifiedName~FriendServiceTests|FullyQualifiedName~ProtocolJsonTests"`.
Expected: PASS. Poi la suite intera: verde (le voci senza `NowPlaying` si scrivono come prima).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): now playing for friends, position and friends watched row"
```

---

## Gruppo B — endpoint e Jellyfin

### Task 4: endpoint

**Files:**
- Modify: `Api/FriendsController.cs`
- Create: `Api/ActivityController.cs`
- Modify: `Tests/FriendsControllerTests.cs` (costruttore del controller e test nuovi)
- Test: `Tests/ActivityControllerTests.cs`

**Interfaces:**
- Consumes: `ActivityService` (Task 2 e 3).
- Produces: `FriendsController(IAuthorizationContext, ISessionDirectory, FriendService, PartyService, ActivityService)` con `GetNowPlaying(string userId)`; `ActivityController(IAuthorizationContext, ActivityService)` con `GetSettings()`, `SetSettings(ActivitySettings?)`, `GetFriendsWatched()`.

- [ ] **Step 1: test che falliscono**

In `Tests/FriendsControllerTests.cs`:
- campi nuovi `private readonly PresenceTracker _presence;` e `private readonly ActivityService _activity;`, creati nel costruttore dopo `_parties`:

```csharp
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _activity = TestActivity.Create(_server, _folder, _time, _friends, _presence, _registry);
```

- in `Dispose`, prima di `_folder.Dispose()`: `_presence.Dispose();`;
- in `Controller(...)`: `new FriendsController(new FakeAuthorizationContext(auth), _server, _friends, _parties, _activity)`;
- cerca con `grep` altri `new FriendsController(` nei test e aggiungi lo stesso argomento;
- test nuovi in fondo alla classe:

```csharp
    [Fact]
    public async Task FriendsShowWhatTheyAreWatching()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        await _friends.AcceptAsync(_luigi.Id, _mario.Id);
        var luigiSession = _server.AddSession("d-luigi", _server.Users[_luigi.Id]);
        var dune = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(luigiSession, dune));

        var response = (await Controller(_mario).GetFriends()).Value!;

        Assert.Equal("Dune", Assert.Single(response.Friends).NowPlaying!.Title);
    }

    [Fact]
    public async Task ThePositionIs409UnlessTheFriendIsWatching()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        await _friends.AcceptAsync(_luigi.Id, _mario.Id);
        var luigiId = _luigi.Id.ToString("N");

        Assert.IsType<ConflictResult>((await Controller(_mario).GetNowPlaying(luigiId)).Result);
        Assert.IsType<ConflictResult>((await Controller(_mario).GetNowPlaying("non-un-id")).Result);

        var luigiSession = _server.AddSession("d-luigi", _server.Users[_luigi.Id]);
        var dune = Guid.NewGuid();
        _server.Playback.Add(TestActivity.Movie(luigiSession, dune, position: TimeSpan.FromMinutes(3)));

        var position = (await Controller(_mario).GetNowPlaying(luigiId)).Value!;
        Assert.Equal(new FriendPosition(dune.ToString("N"), TimeSpan.FromMinutes(3).Ticks), position);
    }
```

(Se il campo del registro dei party in `FriendsControllerTests` ha un altro nome, usa quello: è lo stesso `PartyRegistry` passato a `PartyService`.)

`Tests/ActivityControllerTests.cs`:

```csharp
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ActivityService _activity;

    public ActivityControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true, true);
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _activity = TestActivity.Create(_server, _folder, _time, _friends, _presence);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private ActivityController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new ActivityController(new FakeAuthorizationContext(auth), _activity)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task SharingIsOnUntilTurnedOff()
    {
        Assert.True((await Controller(_mario).GetSettings()).Value!.ShareActivity);

        Assert.IsType<NoContentResult>(await Controller(_mario).SetSettings(new ActivitySettings { ShareActivity = false }));
        Assert.False((await Controller(_mario).GetSettings()).Value!.ShareActivity);
        Assert.True((await Controller(_luigi).GetSettings()).Value!.ShareActivity);

        Assert.IsType<NoContentResult>(await Controller(_mario).SetSettings(new ActivitySettings { ShareActivity = true }));
        Assert.True((await Controller(_mario).GetSettings()).Value!.ShareActivity);
    }

    [Fact]
    public async Task AMissingChoiceIs400()
    {
        Assert.IsType<BadRequestResult>(await Controller(_mario).SetSettings(null));
        Assert.IsType<BadRequestResult>(await Controller(_mario).SetSettings(new ActivitySettings()));
    }

    [Fact]
    public async Task FriendsWatchedListsTheFriendsViews()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var dune = Guid.NewGuid();
        _activity.Report(new PlaybackReport("s-luigi", _luigi.Id, dune, TimeSpan.FromMinutes(6).Ticks, false), stopped: false);

        var items = (await Controller(_mario).GetFriendsWatched()).Value!.Items;

        Assert.Equal(dune.ToString("N"), Assert.Single(items).ItemId);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~FriendsControllerTests|FullyQualifiedName~ActivityControllerTests"`
Expected: errore di compilazione (`ActivityController`, `GetNowPlaying` e il quinto argomento di `FriendsController` non esistono).

- [ ] **Step 3: il codice**

In `Api/FriendsController.cs`:
- il commento della classe aggiunge "e cosa guardano (spec O §6.2, §6.5)";
- il costruttore riceve `ActivityService activity` dopo `PartyService parties`;
- `GetFriends` passa anche `nowPlayingOf`:

```csharp
        return friends.GetFriends(
            auth.UserId,
            viewer is null ? null : friendId => parties.PartyOf(viewer, friendId),
            friendId => activity.NowPlayingFor(auth.UserId, friendId));
```

- dopo `GetFriends`:

```csharp
    /// <summary>
    /// Dove è arrivato l'amico, per "Guarda insieme" (spec O §6.5); 409 se
    /// non sta guardando o chi chiama non può saperlo. userId senza vincoli
    /// di rotta: mai 404.
    /// </summary>
    [HttpGet("Friends/{userId}/NowPlaying")]
    public async Task<ActionResult<FriendPosition>> GetNowPlaying([FromRoute] string userId)
    {
        var result = activity.Position(await CallerAsync().ConfigureAwait(false), userId);
        return result.Status == HubStatus.Ok ? result.Value! : Conflict();
    }
```

`Api/ActivityController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Cosa guardano gli amici (spec O §6.1, §6.6), con la stessa policy degli
/// amici. Chi chiama è l'utente dell'autenticazione.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class ActivityController(
    IAuthorizationContext authorizationContext,
    ActivityService activity) : ControllerBase
{
    /// <summary>"Mostra agli amici cosa guardo" di chi chiama.</summary>
    [HttpGet("Activity/Settings")]
    public async Task<ActionResult<ActivitySettingsResponse>> GetSettings() =>
        new ActivitySettingsResponse(activity.Shares(await CallerAsync().ConfigureAwait(false)));

    /// <summary>Cambia la scelta; spenta, cancella le visioni registrate. 400 senza ShareActivity.</summary>
    [HttpPut("Activity/Settings")]
    public async Task<ActionResult> SetSettings([FromBody] ActivitySettings? settings)
    {
        if (settings?.ShareActivity is not { } share)
        {
            return BadRequest();
        }

        activity.SetShare(await CallerAsync().ConfigureAwait(false), share);
        return NoContent();
    }

    /// <summary>La riga "Visti dagli amici".</summary>
    [HttpGet("Activity/FriendsWatched")]
    public async Task<ActionResult<FriendsWatchedResponse>> GetFriendsWatched() =>
        activity.FriendsWatched(await CallerAsync().ConfigureAwait(false));

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): friends now playing and activity endpoints"
```

### Task 5: adattatori di Jellyfin e servizio in background

**Files:**
- Create: `Server/PlayingTitles.cs`, `Server/JellyfinPlaybackDirectory.cs`, `ActivityHostedService.cs`
- Test: `Tests/PlaybackAdapterTests.cs`, `Tests/ActivityHostedServiceTests.cs`

**Interfaces:**
- Consumes: `PlayingTitle`, `AppPlayback`, `PlaybackReport`, `IPlaybackDirectory`, `ActivityService` (Task 2 e 3).
- Produces:
  - `PlayingTitles.From(BaseItem?)` → `PlayingTitle?`;
  - `PlayingTitles.Report(PlaybackProgressEventArgs)` → `PlaybackReport?`;
  - `JellyfinPlaybackDirectory(ISessionManager, ILibraryManager) : IPlaybackDirectory`;
  - `ActivityHostedService(ISessionManager, ActivityService, TimeProvider, ILogger<ActivityHostedService>)` con `CleanupInterval` (5 min).

- [ ] **Step 1: test che falliscono**

`Tests/PlaybackAdapterTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Session;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PlaybackAdapterTests
{
    private static SessionInfo Session(ISessionManager manager, string id, string client, Guid userId) =>
        new(manager, NullLogger.Instance) { Id = id, DeviceId = id, Client = client, UserId = userId };

    [Fact]
    public void OnlyMoviesAndEpisodesArePlayingTitles()
    {
        var movie = new Movie { Id = Guid.NewGuid(), Name = "Dune" };
        var series = Guid.NewGuid();
        var episode = new Episode
        {
            Id = Guid.NewGuid(), Name = "Pilot", SeriesId = series, SeriesName = "The Bear", ParentIndexNumber = 2, IndexNumber = 3,
        };
        var orphan = new Episode { Id = Guid.NewGuid(), Name = "Speciale" };

        Assert.Equal(new PlayingTitle(movie.Id, "Dune", movie.Id, null, null, null, null), PlayingTitles.From(movie));
        Assert.Equal(new PlayingTitle(episode.Id, "Pilot", series, series, "The Bear", 2, 3), PlayingTitles.From(episode));
        Assert.Equal(new PlayingTitle(orphan.Id, "Speciale", null, null, null, null, null), PlayingTitles.From(orphan));
        Assert.Null(PlayingTitles.From(new Trailer { Id = Guid.NewGuid() }));
        Assert.Null(PlayingTitles.From(new Series { Id = Guid.NewGuid() }));
        Assert.Null(PlayingTitles.From(null));
    }

    [Fact]
    public void OnlyRealWonderFlixReportsCount()
    {
        var (manager, _) = InterfaceStub<ISessionManager>.Create();
        var userId = Guid.NewGuid();
        var movie = new Movie { Id = Guid.NewGuid() };
        PlaybackProgressEventArgs Progress(string client, bool automated = false) => new()
        {
            Session = Session(manager, "s-1", client, userId),
            Item = movie,
            PlaybackPositionTicks = 42,
            IsAutomated = automated,
        };

        Assert.Equal(new PlaybackReport("s-1", userId, movie.Id, 42, false), PlayingTitles.Report(Progress("WonderFlix")));
        Assert.Null(PlayingTitles.Report(Progress("Jellyfin Web")));
        Assert.Null(PlayingTitles.Report(Progress("WonderFlix", automated: true)));
        Assert.Null(PlayingTitles.Report(new PlaybackProgressEventArgs { Session = Session(manager, "s-1", "WonderFlix", Guid.Empty), Item = movie }));
        Assert.Null(PlayingTitles.Report(new PlaybackProgressEventArgs { Session = Session(manager, "s-1", "WonderFlix", userId), Item = new Trailer() }));

        var stopped = new PlaybackStopEventArgs
        {
            Session = Session(manager, "s-1", "WonderFlix", userId), Item = movie, PlaybackPositionTicks = null, PlayedToCompletion = true,
        };
        Assert.Equal(new PlaybackReport("s-1", userId, movie.Id, 0, true), PlayingTitles.Report(stopped));
    }

    [Fact]
    public void ThePlaybackDirectoryListsWonderFlixSessionsThatPlay()
    {
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var mario = Guid.NewGuid();
        var movie = new Movie { Id = Guid.NewGuid(), Name = "Dune" };
        var fromDto = new Movie { Id = Guid.NewGuid(), Name = "Alien" };
        var checkIn = new DateTime(2026, 10, 13, 20, 0, 0, DateTimeKind.Utc);

        var playing = Session(manager, "s-1", "WonderFlix", mario);
        playing.FullNowPlayingItem = movie;
        playing.PlayState = new PlayerStateInfo { PositionTicks = 600 };
        playing.LastPlaybackCheckIn = checkIn;
        var web = Session(manager, "s-2", "Jellyfin Web", mario);
        web.FullNowPlayingItem = movie;
        var idle = Session(manager, "s-3", "WonderFlix", mario);
        var trailer = Session(manager, "s-4", "WonderFlix", mario);
        trailer.FullNowPlayingItem = new Trailer { Id = Guid.NewGuid() };
        var dtoOnly = Session(manager, "s-5", "WonderFlix", mario);
        dtoOnly.NowPlayingItem = new BaseItemDto { Id = fromDto.Id };
        stub.Handlers["get_Sessions"] = _ => new[] { playing, web, idle, trailer, dtoOnly };
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => (Guid)args[0]! == fromDto.Id ? fromDto : null;

        var list = new JellyfinPlaybackDirectory(manager, libraryManager).GetAppPlayback();

        Assert.Equal(2, list.Count);
        Assert.Equal(
            new AppPlayback("s-1", mario, new PlayingTitle(movie.Id, "Dune", movie.Id, null, null, null, null), 600, new DateTimeOffset(checkIn)),
            list[0]);
        Assert.Equal("s-5", list[1].SessionId);
        Assert.Equal(fromDto.Id, list[1].Item.ItemId);
        Assert.Equal(0, list[1].PositionTicks);
    }
}
```

(Se `ILibraryManager.GetItemById` ha più overload e lo stub non lo prende per nome, guarda come `ServerAdapterTests.ThePlayingItemFallsBackToTheDtoWhenTheFullItemIsMissing` prepara lo stesso stub e fai uguale.)

`Tests/ActivityHostedServiceTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ActivityHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 13, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly ISessionManager _manager;
    private readonly InterfaceStub<ISessionManager> _stub;
    private EventHandler<PlaybackProgressEventArgs>? _start;
    private EventHandler<PlaybackProgressEventArgs>? _progress;
    private EventHandler<PlaybackStopEventArgs>? _stopped;

    public ActivityHostedServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        (_manager, _stub) = InterfaceStub<ISessionManager>.Create();
        _stub.Handlers["add_PlaybackStart"] = args => { _start = (EventHandler<PlaybackProgressEventArgs>?)args[0]; return null; };
        _stub.Handlers["add_PlaybackProgress"] = args => { _progress = (EventHandler<PlaybackProgressEventArgs>?)args[0]; return null; };
        _stub.Handlers["add_PlaybackStopped"] = args => { _stopped = (EventHandler<PlaybackStopEventArgs>?)args[0]; return null; };
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    private T Args<T>(UserRef user, Guid movieId, TimeSpan position)
        where T : PlaybackProgressEventArgs, new() => new T
    {
        Session = new SessionInfo(_manager, NullLogger.Instance) { Id = "s-" + user.Name, Client = "WonderFlix", UserId = user.Id },
        Item = new Movie { Id = movieId },
        PlaybackPositionTicks = position.Ticks,
    };

    [Fact]
    public async Task ReportsAreRecordedAndTheTimerCleansUp()
    {
        var mario = _server.AddUser("Mario");
        var activity = TestActivity.Create(_server, _folder, _time, _friends, _presence);
        using var hosted = new ActivityHostedService(_manager, activity, _time, NullLogger<ActivityHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        Assert.NotNull(_start);
        Assert.NotNull(_progress);
        Assert.NotNull(_stopped);

        var dune = Guid.NewGuid();
        _progress(_manager, Args<PlaybackProgressEventArgs>(mario, dune, TimeSpan.FromMinutes(6)));
        Assert.Equal(dune, Assert.Single(TestActivity.Saved(_folder, mario.Id)).ItemId);

        _server.Users.Remove(mario.Id);
        _time.Advance(ActivityHostedService.CleanupInterval);
        Assert.Empty(TestActivity.Saved(_folder, mario.Id));

        await hosted.StopAsync(CancellationToken.None);
        Assert.Contains(_stub.Calls, c => c.Name == "remove_PlaybackStart");
        Assert.Contains(_stub.Calls, c => c.Name == "remove_PlaybackProgress");
        Assert.Contains(_stub.Calls, c => c.Name == "remove_PlaybackStopped");
    }

    [Fact]
    public async Task StartAndStopTellTheFriends()
    {
        var mario = _server.AddUser("Mario");
        var luigi = _server.AddUser("Luigi");
        await TestRecommendations.MakeFriendsAsync(_friends, mario.Id, luigi.Id);
        _server.AddSession("s-luigi", luigi);
        var activity = TestActivity.Create(_server, _folder, _time, _friends, _presence);
        using var hosted = new ActivityHostedService(_manager, activity, _time, NullLogger<ActivityHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        var friendsChanged = JsonSerializer.Serialize(SocialEvent.FriendsChanged());
        _server.Sent.Clear();

        _start!(_manager, Args<PlaybackProgressEventArgs>(mario, Guid.NewGuid(), TimeSpan.Zero));
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(new[] { friendsChanged }, _server.SentTo("s-luigi"));

        _server.Sent.Clear();
        _stopped!(_manager, Args<PlaybackStopEventArgs>(mario, Guid.NewGuid(), TimeSpan.FromMinutes(1)));
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(new[] { friendsChanged }, _server.SentTo("s-luigi"));

        await hosted.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task AFailingReportDoesNotReachJellyfin()
    {
        var mario = _server.AddUser("Mario");

        // Un percorso con un carattere nullo: il salvataggio lancia ArgumentException, che Persist non prende.
        var store = new ActivityStore(Path.Combine(_folder.Path, "rotto\0", "activity.json"), NullLogger<ActivityStore>.Instance);
        var activity = new ActivityService(
            store, _friends, _server, _server, _server, new PartyRegistry(), _server, _server, _presence, _time,
            NullLogger<ActivityService>.Instance);
        var logger = new RecordingLogger<ActivityHostedService>();
        using var hosted = new ActivityHostedService(_manager, activity, _time, logger);
        await hosted.StartAsync(CancellationToken.None);

        var error = Record.Exception(() => _progress!(_manager, Args<PlaybackProgressEventArgs>(mario, Guid.NewGuid(), TimeSpan.FromMinutes(6))));

        Assert.Null(error);
        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning);
        await hosted.StopAsync(CancellationToken.None);
    }
}
```

(`RecordingLogger<T>.Entries` è un elenco di `(Level, Exception, Message)`. Se su questa macchina il carattere nullo non fa lanciare il salvataggio, trova un altro modo perché `Report` lanci un'eccezione che `Persist` non prende, senza cambiare `ActivityService` per il test.)

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~PlaybackAdapterTests|FullyQualifiedName~ActivityHostedServiceTests"`
Expected: errore di compilazione (`PlayingTitles`, `JellyfinPlaybackDirectory`, `ActivityHostedService` non esistono).

- [ ] **Step 3: il codice**

`Server/PlayingTitles.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Elementi ed eventi di riproduzione di Jellyfin come li vede l'attività degli amici (spec O).</summary>
public static class PlayingTitles
{
    /// <summary>Il film o l'episodio; null per ogni altro tipo (trailer, video, musica, serie…).</summary>
    public static PlayingTitle? From(BaseItem? item) => item switch
    {
        Movie movie => new PlayingTitle(movie.Id, movie.Name ?? string.Empty, movie.Id, null, null, null, null),
        Episode episode => new PlayingTitle(
            episode.Id,
            episode.Name ?? string.Empty,
            SeriesOf(episode),
            SeriesOf(episode),
            episode.SeriesName,
            episode.ParentIndexNumber,
            episode.IndexNumber),
        _ => null,
    };

    /// <summary>
    /// Il resoconto di un evento di riproduzione: solo dalle sessioni
    /// WonderFlix con un utente, per film ed episodi, e non gli avanzamenti
    /// che Jellyfin manda da sé ogni secondo (piano 21a, decisione 2).
    /// </summary>
    public static PlaybackReport? Report(PlaybackProgressEventArgs e)
    {
        var session = e.Session;
        if (e.IsAutomated
            || session is null
            || !string.Equals(session.Client, WatchPartyProtocol.ClientName, StringComparison.Ordinal)
            || session.UserId.Equals(Guid.Empty)
            || From(e.Item) is not { } title)
        {
            return null;
        }

        return new PlaybackReport(
            session.Id, session.UserId, title.TitleId, e.PlaybackPositionTicks ?? 0, e is PlaybackStopEventArgs { PlayedToCompletion: true });
    }

    private static Guid? SeriesOf(Episode episode) => episode.SeriesId == Guid.Empty ? null : episode.SeriesId;
}
```

`Server/JellyfinPlaybackDirectory.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le riproduzioni delle sessioni WonderFlix di Jellyfin (spec O §6.2, §6.5).</summary>
public sealed class JellyfinPlaybackDirectory(ISessionManager sessionManager, ILibraryManager libraryManager) : IPlaybackDirectory
{
    public IReadOnlyList<AppPlayback> GetAppPlayback()
    {
        var list = new List<AppPlayback>();
        foreach (var session in sessionManager.Sessions)
        {
            if (!string.Equals(session.Client, WatchPartyProtocol.ClientName, StringComparison.Ordinal)
                || session.UserId.Equals(Guid.Empty)
                || PlayingTitles.From(ItemOf(session)) is not { } title)
            {
                continue;
            }

            // Jellyfin fa avanzare PositionTicks da sé ogni secondo (piano 21a, decisione 4);
            // LastPlaybackCheckIn è in UTC, a volte senza dirlo.
            list.Add(new AppPlayback(
                session.Id,
                session.UserId,
                title,
                session.PlayState?.PositionTicks ?? 0,
                new DateTimeOffset(DateTime.SpecifyKind(session.LastPlaybackCheckIn, DateTimeKind.Utc))));
        }

        return list;
    }

    // Di solito c'è l'elemento intero; se no, quello del DTO (come JellyfinLibraryAccess.NowPlaying).
    private BaseItem? ItemOf(SessionInfo session) =>
        session.FullNowPlayingItem
        ?? (session.NowPlayingItem is { } dto && dto.Id != Guid.Empty ? libraryManager.GetItemById(dto.Id) : null);
}
```

`ActivityHostedService.cs` (nella cartella del plugin, accanto a `RecommendationsHostedService.cs`):

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// L'attività degli amici in background (spec O §6.3–6.4): all'avvio legge
/// activity.json; a inizio e fine di ogni riproduzione WonderFlix gli amici
/// rileggono "Sta guardando"; i resoconti registrano le visioni; ogni
/// <see cref="CleanupInterval"/> pulisce il registro.
/// </summary>
public sealed class ActivityHostedService(
    ISessionManager sessionManager,
    ActivityService activity,
    TimeProvider time,
    ILogger<ActivityHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si pulisce il registro (come i consigli).</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            activity.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Attività degli amici non caricata all'avvio");
        }

        sessionManager.PlaybackStart += OnPlaybackStart;
        sessionManager.PlaybackProgress += OnPlaybackProgress;
        sessionManager.PlaybackStopped += OnPlaybackStopped;
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.PlaybackStart -= OnPlaybackStart;
        sessionManager.PlaybackProgress -= OnPlaybackProgress;
        sessionManager.PlaybackStopped -= OnPlaybackStopped;
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    private void OnPlaybackStart(object? sender, PlaybackProgressEventArgs e) =>
        Handle(e, report => activity.PlaybackChanged(report.UserId));

    // Arriva dentro la richiesta dell'app, senza try/catch di Jellyfin
    // (piano 21a, decisione 3): un errore qui farebbe fallire il resoconto.
    private void OnPlaybackProgress(object? sender, PlaybackProgressEventArgs e) =>
        Handle(e, report => activity.Report(report, stopped: false));

    private void OnPlaybackStopped(object? sender, PlaybackStopEventArgs e) =>
        Handle(e, report =>
        {
            activity.Report(report, stopped: true);
            activity.PlaybackChanged(report.UserId);
        });

    private void Handle(PlaybackProgressEventArgs e, Action<PlaybackReport> action)
    {
        try
        {
            if (PlayingTitles.Report(e) is { } report)
            {
                action(report);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Resoconto di riproduzione non gestito");
        }
    }

    private void Cleanup()
    {
        try
        {
            var removed = activity.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolte {Count} voci dell'attività degli amici", removed);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dell'attività degli amici non riuscita");
        }
    }
}
```

Nota: in `OnPlaybackStopped` la presenza si avvisa anche se lo stop non registra niente; `PlaybackChanged` controlla da sé la condivisione. Uno stop senza elemento (`Item` null) non arriva a `Report`: in quel caso la presenza si aggiorna alla fine della sessione o alla riproduzione successiva (accettato).

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): playback adapters and activity hosted service"
```

### Task 6: montaggio, riga della Home, `Info` e plugin 1.9.0

**Files:**
- Modify: `PluginServiceRegistrator.cs`, `Home/HomeRowIds.cs`, `Protocol/WatchPartyProtocol.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `../meta.template.json`, `../README.md`
- Modify (test): `Tests/ServiceRegistrationTests.cs`, `Tests/HomeRowIdsTests.cs`, `Tests/InfoControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `Tests/ServiceRegistrationTests.cs`, prima del conteggio dei servizi in background:

```csharp
        // Cosa guardano gli amici (spec O).
        Assert.Same(provider.GetRequiredService<ActivityService>(), provider.GetRequiredService<ActivityService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "activity.json"),
            provider.GetRequiredService<ActivityStore>().FilePath);
        Assert.IsType<Server.JellyfinPlaybackDirectory>(provider.GetRequiredService<IPlaybackDirectory>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.ActivityController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.FriendsController>(provider));
```

e il conteggio diventa:

```csharp
        // Il promemoria dei contatti, oltre ai due di prima.
        // I consigli (spec N), oltre ai tre di prima.
        // L'attività degli amici (spec O), oltre ai quattro di prima.
        Assert.Equal(5, provider.GetServices<IHostedService>().Count());
```

In `Tests/HomeRowIdsTests.cs`:
- `TheKnownRowsAreTheElevenOfTheSpecsInTheDefaultOrder` si chiama `TheKnownRowsAreTheTwelveOfTheSpecsInTheDefaultOrder`; l'elenco ha `"friendsWatched"` dopo `"recommended"`; `AddedLater` è `new[] { "recommended", "friendsWatched" }`;
- `LaterRowsGoAfterTheirLastEarlierRowOnce` diventa:

```csharp
    [Fact]
    public void LaterRowsGoAfterTheirLastEarlierRowOnce()
    {
        // Dopo nextUp, anche se l'admin l'ha spostata; friendsWatched subito dopo recommended.
        var change = HomeRowIds.WithLaterRows(["myList", "nextUp", "resume"], []);
        Assert.Equal(new[] { "myList", "nextUp", "resume", "recommended", "friendsWatched" }, change!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, change.Value.Seen);

        Assert.Equal(
            new[] { "nextUp", "recommended", "friendsWatched", "myList" },
            HomeRowIds.WithLaterRows(["nextUp", "myList"], [])!.Value.Rows);

        // Né resume né nextUp accese: in testa.
        Assert.Equal(new[] { "recommended", "friendsWatched", "myList" }, HomeRowIds.WithLaterRows(["myList"], [])!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, HomeRowIds.WithLaterRows([], [])!.Value.Rows);

        // Già accesa: resta dov'è; l'altra va dopo l'ultima che la precede.
        var on = HomeRowIds.WithLaterRows(["recommended", "resume"], []);
        Assert.Equal(new[] { "recommended", "resume", "friendsWatched" }, on!.Value.Rows);

        // La Home della 1.8.0, con recommended già vista (anche se spenta): arriva solo friendsWatched.
        var from18 = HomeRowIds.WithLaterRows(["resume"], ["recommended"]);
        Assert.Equal(new[] { "resume", "friendsWatched" }, from18!.Value.Rows);
        Assert.Equal(new[] { "recommended", "friendsWatched" }, from18.Value.Seen);

        // Tutte già viste: niente da fare.
        Assert.Null(HomeRowIds.WithLaterRows(["resume"], ["recommended", "friendsWatched"]));
    }
```

- in `ANeverSetHomeOnlyMarksTheLaterRowsSeen` il `Seen` atteso è `new[] { "recommended", "friendsWatched" }`.

In `Tests/InfoControllerTests.cs`: versione `"1.9.0"` e, nei due elenchi di funzioni, `"friendsActivity"` dopo `"recommendations"`.

Cerca con `grep` altri test che contano gli id della Home o le funzioni di `Info` (per esempio `HomeControllerTests`, `PluginPagesTests`, `RecommendationsHostedServiceTests`) e aggiornali con la stessa regola.

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~HomeRowIdsTests|FullyQualifiedName~InfoControllerTests"`
Expected: FAIL (servizi non registrati, id e funzioni mancanti, versione 1.8.0).

- [ ] **Step 3: il codice**

In `PluginServiceRegistrator.cs`, dopo il blocco "Consigli tra amici (spec N)":

```csharp
        // Cosa guardano gli amici (spec O).
        serviceCollection.AddSingleton(provider => new ActivityStore(
            ActivityStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<ActivityStore>>()));
        serviceCollection.AddSingleton<IPlaybackDirectory, JellyfinPlaybackDirectory>();
        serviceCollection.AddSingleton<ActivityService>();
```

e in fondo, dopo `RecommendationsHostedService`: `serviceCollection.AddHostedService<ActivityHostedService>();`.

In `Home/HomeRowIds.cs`:
- nel commento della classe aggiungi "spec O §6.7";
- `Known`: `"friendsWatched"` subito dopo `"recommended"`;
- `AddedLater`:

```csharp
    /// <summary>
    /// Le righe nate dopo la 1.7.0 (spec N §6.7, spec O §6.7): una Home
    /// dell'admin salvata prima non le ha e, senza aggiungerle, sarebbero
    /// spente per tutti.
    /// </summary>
    public static readonly IReadOnlyList<string> AddedLater = ["recommended", "friendsWatched"];
```

In `Protocol/WatchPartyProtocol.cs`: nel commento di `Features` aggiungi "spec O §6.7"; l'elenco diventa
`["friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home", "recommendations", "friendsActivity"];`.

Nel csproj: `<Version>1.9.0</Version>`.

In `Plugin.cs`: nel commento della classe, dopo "dalla 1.8.0, i consigli tra amici (spec N)", aggiungi "e, dalla 1.9.0, cosa guardano gli amici (spec O)". `Description` diventa:

```csharp
    public override string Description =>
        "Names, chat, reactions, friends, what friends are watching, notifications, recommendations between friends, password recovery and the Home rows (upcoming from Sonarr and Radarr) for WonderFlix.";
```

In `../meta.template.json`:
- `description`: dopo "recommendations between friends" aggiungi ", what friends are watching";
- `overview`: dopo "recommendations" aggiungi ", friends activity".

In `../README.md`:
- nell'introduzione, dopo la frase della 1.8.0: "Dalla 1.9.0 mostra agli amici cosa si sta guardando in WonderFlix e i titoli visti negli ultimi 30 giorni, con un interruttore per non mostrarlo (spec O, `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md`).";
- un punto nuovo dopo "Consigli (dalla 1.8.0)":

```markdown
- **Cosa guardano gli amici (dalla 1.9.0):** in `GET Friends` ogni amico
  online fuori da un party può avere `NowPlaying` (film o episodio di una
  sessione WonderFlix; mai se chi guarda non può vedere il titolo o l'amico
  è in un party). `GET Friends/{userId}/NowPlaying` dà la posizione per
  "Guarda insieme" (409 se non vale). Il plugin registra le visioni
  WonderFlix oltre 5 minuti (film o serie, 30 giorni, 100 per utente) in
  `activity.json`; `GET Activity/FriendsWatched` dà la riga "Visti dagli
  amici" (titoli degli amici che chi chiama vede e non ha mai visto, al
  massimo 30). `GET`/`PUT Activity/Settings` `{ShareActivity}` è
  "Mostra agli amici cosa guardo" (acceso di default; spento cancella le
  visioni). Gli amici rileggono a inizio e fine di ogni riproduzione. All'avvio
  la riga `friendsWatched` si accende una volta sola nella Home dell'admin già
  salvata (`HomeRowsSeen`).
```

- nel punto "Funzioni": "…dalla 1.8.0 anche `recommendations`, dalla 1.9.0 anche `friendsActivity`…"; e "Quelli di `Activity` hanno la stessa policy degli amici.";
- in "Installazione a mano": `pack.sh 1.9.0` e `WonderFlix Watch Party_1.9.0.0/`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde. Se `PluginPagesTests` controlla la `Description` del plugin, aggiornalo.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): friends activity wiring and plugin 1.9.0"
```

---

## Gruppo C — server e chiusura

### Task 7: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo B si ferma qui. L'orchestratore fa prima la review finale del branch e i ritocchi, poi questi passi (un solo riavvio di Jellyfin, con il codice già rivisto). Sul server WonderFlix lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando. Gli script vanno scritti in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`). **Nessuno script stampa chiavi o token.**

1. **Riferimenti della dll:** controllo dei riferimenti della dll di Release contro gli assembly di Jellyfin 10.11.9 (come per le versioni passate): nessun membro non risolto.
2. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.9.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.9.0.0/`.
3. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix": base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - `mkdir -p ~/wfwp-backup`; sposta `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.8.0.0` in `~/wfwp-backup/1.8.0.0-catalogo` (se c'è già, con un suffisso); copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.8.0-prima-21a.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.9.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log di oggi `Loaded plugin: "WonderFlix Watch Party" "1.9.0.0"`, `Attività degli amici in "/config/data/plugins/configurations/WonderFlixWatchParty/activity.json"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.9.0.0, rimetti `~/wfwp-backup/1.8.0.0-catalogo` e la configurazione salvata, riavvia, e segnalalo.
4. **Controlli** (stessa base e intestazione; risposte riassunte con `python3`, mai stampate intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.9.0`; funzioni con `friendsActivity`, e ancora `recommendations`, `home`, `requests`, `account`;
   - `GET /WonderFlixWatchParty/Activity/FriendsWatched` con la sola chiave API: risponde **non 404** (la chiave non ha un utente, la policy degli amici la respinge: 401 o 403); il percorso esiste;
   - nella configurazione `<HomeRowsSeen>recommended,friendsWatched</HomeRowsSeen>` e `HomeRows` com'era (oggi non impostata); `SeerrUrl`, `SonarrUrl`, `ContactReminderDays` ancora al loro posto;
   - nel log nessun `Warning` del plugin dopo l'avvio, e nessun errore nei resoconti di riproduzione (`Resoconto di riproduzione non gestito`) se qualcuno guarda.
   - Il giro completo (Sta guardando, Guarda insieme, riga, interruttore) si prova con l'app nel piano 21b.
5. **Riporta all'utente** l'esito in breve: versione, funzioni, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 21b). Dal momento dell'installazione il plugin registra le visioni WonderFlix di tutti (privacy visibile di default, spec §3.1); l'app 0.14.0 ignora `NowPlaying` e la riga nuova, quindi gli amici non vedono ancora niente.

### Task 8: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md`
- Modify: `docs/superpowers/plans/2026-10-13-wonderflix-21a-attivita-amici-plugin.md` (solo una voce "Dalle review dei gruppi" nelle decisioni, se ci sono differenze)

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvata il 2026-10-13; piano 21a realizzato (`docs/superpowers/plans/2026-10-13-wonderflix-21a-attivita-amici-plugin.md`), build di prova sul server; piano 21b da scrivere".
- **§6.1 e §6.4:** un file solo, `activity.json`, con `Hidden` e `Users` (decisione 1).
- **§6.3 e §6.4:** solo i resoconti veri (`IsAutomated` falso, decisione 2); il gestore di `PlaybackProgress` con il suo `try/catch` (decisione 3); una registrazione per sessione e titolo, sessioni dimenticate allo stop e alla pulizia (decisione 8); episodio senza serie non registrato (decisione 7).
- **§6.2:** party = sessione nel registro dei party (decisione 6); errori → `NowPlaying` assente (decisione 9).
- **§6.5:** la posizione è `PlayState.PositionTicks` com'è, senza aggiungere tempo né tagliare alla durata (decisione 4).
- **§12:** tutti i punti verificati sul sorgente di Jellyfin 10.11.9 (decisioni 2–6), compreso "Sta guardando" che sparisce da 5 a 10 minuti dopo un player chiuso male.
- **§13:** 21a realizzato; il plugin 1.9.0 resta build di prova fino alla fine del 21b.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze.

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the friends activity spec with plan 21a"
```

### Task 9: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 7: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente tag e niente manifest: il plugin 1.9.0 si pubblica alla fine del 21b, insieme all'app 0.15.0.
