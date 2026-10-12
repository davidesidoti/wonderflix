# WonderFlix — Piano 20a: consigli tra amici, plugin 1.8.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server dello Spec N nel plugin 1.8.0:
- l'archivio dei consigli (`recommendations.json`) con i filtri a lettura (amicizia, 60 giorni, permessi, visto dopo il consiglio);
- gli endpoint `Recommendations/Targets`, `POST Recommendations`, `GET Recommendations`, `DELETE Recommendations/{itemId}`;
- la voce `Recommendation` nella cassetta delle notifiche;
- il limite di 30 destinatari all'ora;
- la funzione `recommendations` in `Info` e la riga `recommended` della Home, accesa una volta sola anche nella Home dell'admin già salvata;
- una build di prova sul server.

L'app arriva nel piano 20b.

**Architecture:** la logica sta in `Hub/` e non conosce Jellyfin: `RecommendationBook` (archivio in memoria, puro), `RecommendationStore` (file), `RecommendationService` (regole, amici, permessi, cassetta, limiti), `IRecommendationLibrary` (titolo consigliabile e ultima visione). L'adattatore Jellyfin (`Server/JellyfinRecommendationLibrary`) fa una domanda al database per serie. Un servizio in background nuovo (`RecommendationsHostedService`) legge il file all'avvio, accende la riga nuova nella Home dell'admin e pulisce ogni 5 minuti.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md` (§3, §6, §8, §10, §11.1, §12, §13).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 8):
1. **Pulizia in un servizio suo** (`RecommendationsHostedService`, ogni 5 minuti) invece che in `WatchPartyHostedService`: legge anche il file all'avvio e accende la riga nella Home dell'admin. `WatchPartyHostedService` resta com'è (e i suoi 5 test pure).
2. **La pulizia periodica** toglie i mittenti che non esistono più o non sono più amici, i titoli più vecchi di 60 giorni e i destinatari che non esistono più. Permessi (`CanSee`) e "visto" li controlla solo `GET Recommendations`: sono domande alla libreria per ogni titolo di ogni utente, e conta solo quello che l'utente vede.
3. **Rimozione condizionata:** `GET` legge i titoli sotto lock, fa le domande alla libreria **fuori dal lock** e poi toglie un titolo solo se il suo consiglio più recente è ancora quello controllato (`RemoveIfLatest`). Un consiglio arrivato nel frattempo non si perde.
4. **Errore della libreria in `GET`:** se `CanSee` o `LastWatched` lanciano per un titolo, il titolo resta (riga `Warning`) e la risposta arriva lo stesso.
5. **Limite tutto o niente:** `RateLimiter.TryAcquire(key, type, count)` prende `count` posti insieme o nessuno. Con più destinatari validi di quelli che restano: 429 e niente salvato (spec §6.2).
6. **Messaggio:** gli a capo diventano spazi, le righe vuote spariscono, spazi ai bordi tolti; vuoto = nessun messaggio. Lunghezza in punti di codice (come gli annunci): 200 emoji passano.
7. **"Visto"** = `LastPlayedDate` dei dati utente (film) o dell'episodio visto più di recente (serie: `InternalItemsQuery` con `AncestorIds` = la serie, `OrderBy` `DatePlayed` decrescente, `Limit` 1). Verificato sul sorgente di Jellyfin 10.11.9 il 2026-10-12: `ItemSortBy.DatePlayed` ordina per `LastPlayedDate` dell'utente della query; `BaseItem.MarkPlayed` senza data tiene la data che c'era, altrimenti mette adesso (`datePlayed ?? data.LastPlayedDate ?? DateTime.UtcNow`). Quindi "segna come visto" di un titolo mai visto lo toglie dalla riga; di un titolo già visto prima del consiglio no (accettato, spec §12).
8. **Riga della Home:** `HomeRowIds.AddedLater = ["recommended"]` e `PluginConfiguration.HomeRowsSeen` (stringa di id separati da virgole). Con `HomeRows` `null` la riga si segna vista e basta: se poi l'admin salva la sua Home con l'app 0.14.0 e la spegne, al riavvio dopo non torna accesa.
9. **`Targets`** dà gli amici **attivi** (non disabilitati), per nome; l'app li riordina (online prima).

**Dalle review dei gruppi** (il codice differisce dal codice dei task):
- Due test sono async (xUnit1031, che con `TreatWarningsAsErrors` è un errore).
- `RemoveSender` toglie il mittente solo se il suo `CreatedAt` è ancora quello controllato: chi riconsiglia nel frattempo resta.
- `CleanMessage` tratta come separatori ogni carattere di controllo e U+2028/U+2029, non solo gli a capo.
- Il log `Debug` di `GET` dà anche i titoli da togliere per motivo (oltre 60 giorni, non visibili, visti).

## Global Constraints

- Plugin **1.8.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9.
- Endpoint sotto `/WonderFlixWatchParty`, controller con `[Authorize(Policy = Policies.SyncPlayHasAccess)]` come gli amici: `GET Recommendations/Targets?itemId=`, `POST Recommendations`, `GET Recommendations`, `DELETE Recommendations/{itemId}`. **Mai 404**: `itemId` è una stringa senza vincoli di rotta.
- Archivio `recommendations.json` in `<PluginConfigurationsPath>/WonderFlixWatchParty/`, accanto a `inbox.json`.
- Limiti: messaggio 200 punti di codice; `To` da 1 a 50 id; 50 titoli per destinatario; 60 giorni; 30 destinatari all'ora per mittente (`LimitTypes.Recommendations`).
- Si consigliano solo film e serie (`Movie`, `Series`).
- Voce della cassetta `Recommendation`: `ItemId`, `FromUserId`, `FromName`, `Title` ("Dune (2021)"), `Text` (assente senza messaggio); una per mittente e titolo.
- `Info`: `Version` "1.8.0", `Protocol` 1, `Features` con `"recommendations"` dopo `"home"`.
- Id della Home: `recommended` subito dopo `nextUp` in `HomeRowIds.Known`.
- Log: **mai titoli, messaggi o nomi**; solo id e numeri.

## Review Focus

1. **Errore della libreria durante `GET Recommendations`** (Jellyfin lancia su `CanSee` o sulla domanda delle visioni): la riga deve arrivare lo stesso, con il titolo ancora lì. Test: Task 3 (`ALibraryErrorKeepsTheTitleAndTheAnswer`).
2. **Consiglio che arriva mentre `GET` sta filtrando** lo stesso titolo (un amico riconsiglia un titolo appena visto): il consiglio nuovo non deve sparire. Test: Task 1 (`RemoveIfLatestKeepsATitleRecommendedAgainMeanwhile`).
3. **Messaggi strani**: solo spazi o a capo (= nessun messaggio), più righe (unite con spazi), 200 emoji (passano), 201 caratteri (400). Test: Task 3 (`MessagesAreCleanedAndCountedInCodePoints`).
4. **Destinatari sbagliati in `To`**: testo che non è un id, chi chiama, doppioni, non amici, disabilitati, senza accesso al titolo → saltati in silenzio, non 400. Test: Task 3 (`InvalidRecipientsAreSkippedSilently`).
5. **Riconsiglio dopo una visione**: il titolo visto esce; se un amico lo riconsiglia dopo, torna. Un amico tolto sparisce dai mittenti ma gli altri tengono il titolo. Test: Task 3 (`WatchedTitlesLeaveAndComeBackWhenRecommendedAgain`, `AnUnfriendedSenderLeavesTheOthersStay`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-20a`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(plugin): …"`.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.8.0`.
- **Test:**
  - un solo gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj del plugin ha `TreatWarningsAsErrors`: un warning è un errore), poi `dotnet build-server shutdown`;
  - la base di partenza è di **810** test verdi (verificato il 2026-10-12 su `main` `985bf59`).
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
  - nel registro mai titoli, messaggi o nomi.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un dettaglio di un test, un'API di Jellyfin con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-12 sul codice di `main` (`985bf59`), sui pacchetti NuGet di Jellyfin 10.11.0 e sul sorgente di Jellyfin 10.11.9.

**Plugin** (`main`)
- `InboxStore`/`InboxService`/`InboxBook` sono il modello per archivio, servizio e libro: lock, scrittura atomica (`.tmp` + `File.Move`), file illeggibile in `.bad`, rinomina non riuscita tollerata, `Persist()` che non lancia sugli errori di disco, avviso `InboxChanged` con `SocialEvent.InboxChanged()`.
- `InboxEntry` ha già `FromName`, `Title`, `Text`, `ItemId` (`[JsonIgnore(WhenWritingNull)]`); manca `FromUserId`.
- `FriendService.AreFriends(a, b)` e `FriendsOf(user)` prendono il loro lock: si possono chiamare da dentro il lock dei consigli (`FriendService` non chiama mai i consigli).
- `IUserDirectory.GetUser(id)` → `UserRef(Id, Name, Enabled, CanJoinParties, IsAdmin)` o `null`; `ISessionDirectory.GetAppSessions()` → sessioni WonderFlix (`CallerSession(SessionId, UserId, UserName)`).
- `ILibraryAccess.CanSee(userId, itemId)` (librerie e limiti d'età, anche offline).
- `RateLimiter.TryAcquire(key, type)` con la tabella `Limits` per tipo; `LimitTypes` contiene i tipi che non sono eventi.
- `HubResult<T>.Ok(value)` / `Fail(HubStatus)`; `HubStatus.Ok`, `Invalid`, `RateLimited`.
- `HomeRowIds` (`Known`, `Normalize`, `Parse`, `Serialize`), `IHomeLayoutStore` (`Rows`, `Save`), `PluginHomeLayoutStore` (legge `Plugin.Instance` ogni volta, `_lock`, `plugin.SaveConfiguration()`). `HomeControllerTests` ha un `FakeHomeLayoutStore` privato che implementa `IHomeLayoutStore`.
- `WatchPartyProtocol.Features` è l'elenco fisso di `Info`; `InfoControllerTests` controlla versione e funzioni.
- `ServiceRegistrationTests.AllServicesResolve` registra gli stub di Jellyfin e conta **3** servizi in background.

**Jellyfin**
- `IUserDataManager.GetUserData(User, BaseItem)` → `UserItemData?` con `LastPlayedDate` (`DateTime?`), in `MediaBrowser.Controller.Library` / `MediaBrowser.Controller.Entities`.
- `Jellyfin.Data.Enums.ItemSortBy`, `Jellyfin.Database.Implementations.Enums.SortOrder`. `InternalItemsQuery(User)` con `AncestorIds`, `IncludeItemTypes`, `IsVirtualItem`, `OrderBy` (`IReadOnlyList<(ItemSortBy, SortOrder)>`), `Limit`.
- `ILibraryManager.GetItemById(Guid)` (lancia con `Guid.Empty`) e `GetItemList(InternalItemsQuery)`.

**Test**
- `FakeServer` implementa `ISessionDirectory`, `IUserDirectory`, `ILibraryAccess` (`Unseen`, `LibraryFails`), `IEventSender` (`SentTo`), `ILibraryTitles` (ha già un metodo `Get(Guid)`: il metodo nuovo si chiama `GetTitle`).
- `TestInbox.Create(server, folder, time)`, `TempFolder` (`InboxFile`, …), `InterfaceStub<T>` (`Handlers["Nome"]`, `Calls`), `FakeAuthorizationContext(AuthorizationInfo)`, `RecordingLogger<T>`, `FakeTimeProvider`.
- Utenti di Jellyfin nei test dei controller: `new User("mario", "provider", "reset")` e la stessa id in `FakeServer.Users`.

## File

| File | Responsabilità |
|---|---|
| `Hub/RecommendationFile.cs` | contenuto di `recommendations.json` |
| `Hub/RecommendationBook.cs` | consigli in memoria: aggiunte, tetto, rimozioni, pulizia, file |
| `Hub/RecommendationStore.cs` | il file su disco |
| `Hub/IRecommendationLibrary.cs` | titolo consigliabile e ultima visione |
| `Hub/RecommendationService.cs` | regole: destinatari, invio, filtro a lettura, "Non mi interessa", pulizia |
| `Hub/InboxBook.cs`, `Hub/InboxService.cs`, `Protocol/InboxDtos.cs` (modifiche) | voce `Recommendation` |
| `Hub/RateLimiter.cs`, `Hub/LimitTypes.cs` (modifiche) | `Recommendations`, 30 all'ora, posti multipli |
| `Protocol/RecommendationDtos.cs` | corpi e risposte |
| `Api/RecommendationsController.cs` | i 4 endpoint |
| `Home/HomeRowIds.cs`, `Home/IHomeLayoutStore.cs`, `Server/PluginHomeLayoutStore.cs`, `Configuration/PluginConfiguration.cs` (modifiche) | riga `recommended`, `HomeRowsSeen` |
| `Server/JellyfinRecommendationLibrary.cs` | adattatore di Jellyfin |
| `RecommendationsHostedService.cs` | avvio e pulizia |
| `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `Plugin.cs`, `../meta.template.json`, `../README.md` (modifiche) | montaggio, versione, documentazione |

Tutti i percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test), se non è detto altro.

---

## Gruppo A — archivio e regole

### Task 1: l'archivio dei consigli

**Files:**
- Create: `Hub/RecommendationFile.cs`, `Hub/RecommendationBook.cs`, `Hub/RecommendationStore.cs`
- Modify (test): `TempFolder.cs`
- Test: `RecommendationBookTests.cs`, `RecommendationStoreTests.cs`

**Interfaces:**
- Consumes: niente di nuovo.
- Produces:
  - `record RecommendationSender(Guid UserId, string? Message, DateTimeOffset CreatedAt)`;
  - `record RecommendedTitle(Guid ItemId, IReadOnlyList<RecommendationSender> From)` con `DateTimeOffset LatestAt`;
  - `RecommendationBook`: `const int MaxTitles = 50`, `List(Guid userId)`, `Add(Guid toUserId, Guid itemId, Guid fromUserId, string? message, DateTimeOffset now)`, `bool Remove(Guid userId, Guid itemId)`, `bool RemoveIfLatest(Guid userId, Guid itemId, DateTimeOffset latestAt)`, `bool RemoveSender(Guid userId, Guid itemId, Guid fromUserId)`, `int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists, Func<Guid, Guid, bool> keepSender)`, `static FromFile(RecommendationFile)`, `ToFile()`;
  - `RecommendationStore(string filePath, ILogger<RecommendationStore>)`: `const string FileName = "recommendations.json"`, `FilePath`, `static DefaultPath(IApplicationPaths)`, `Load()`, `Save(RecommendationBook)`;
  - `TempFolder.RecommendationsFile`.

- [ ] **Step 1: i test che falliscono**

In `TempFolder.cs`, dopo `ContactsFile`:

```csharp
    /// <summary>Percorso di recommendations.json, accanto a inbox.json.</summary>
    public string RecommendationsFile => System.IO.Path.Combine(Path, "WonderFlixWatchParty", "recommendations.json");
```

`RecommendationBookTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RecommendationBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 12, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _peach = Guid.NewGuid();
    private readonly Guid _dune = Guid.NewGuid();
    private readonly Guid _bear = Guid.NewGuid();

    [Fact]
    public void TitlesAreListedNewestFirstWithTheirSendersNewestFirst()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, "da vedere", Now);
        book.Add(_luigi, _bear, _mario, null, Now.AddMinutes(1));
        book.Add(_luigi, _dune, _peach, "bellissimo", Now.AddMinutes(2));

        var titles = book.List(_luigi);

        Assert.Equal(new[] { _dune, _bear }, titles.Select(t => t.ItemId));
        Assert.Equal(new[] { _peach, _mario }, titles[0].From.Select(f => f.UserId));
        Assert.Equal(Now.AddMinutes(2), titles[0].LatestAt);
        Assert.Null(titles[1].From[0].Message);
        Assert.Empty(book.List(_mario));
    }

    [Fact]
    public void RecommendingAgainUpdatesMessageAndDateWithoutDuplicates()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, "da vedere", Now);
        book.Add(_luigi, _dune, _mario, null, Now.AddDays(1));

        var sender = Assert.Single(Assert.Single(book.List(_luigi)).From);
        Assert.Null(sender.Message);
        Assert.Equal(Now.AddDays(1), sender.CreatedAt);
    }

    [Fact]
    public void AtMost50TitlesTheOldestGoes()
    {
        var book = new RecommendationBook();
        var items = Enumerable.Range(0, RecommendationBook.MaxTitles + 1).Select(_ => Guid.NewGuid()).ToList();
        for (var i = 0; i < items.Count; i++)
        {
            book.Add(_luigi, items[i], _mario, null, Now.AddMinutes(i));
        }

        var titles = book.List(_luigi);
        Assert.Equal(RecommendationBook.MaxTitles, titles.Count);
        Assert.DoesNotContain(items[0], titles.Select(t => t.ItemId));
        Assert.Equal(items[^1], titles[0].ItemId);
    }

    [Fact]
    public void RemoveSenderDropsTheTitleOnlyWithoutSendersLeft()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        book.Add(_luigi, _dune, _peach, null, Now);

        Assert.True(book.RemoveSender(_luigi, _dune, _mario));
        Assert.Equal(_peach, Assert.Single(Assert.Single(book.List(_luigi)).From).UserId);
        Assert.False(book.RemoveSender(_luigi, _dune, _mario));
        Assert.True(book.RemoveSender(_luigi, _dune, _peach));
        Assert.Empty(book.List(_luigi));
        Assert.False(book.RemoveSender(_mario, _dune, _peach));
    }

    [Fact]
    public void RemoveIfLatestKeepsATitleRecommendedAgainMeanwhile()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        var seen = Assert.Single(book.List(_luigi)).LatestAt;

        // Peach consiglia Dune mentre GET sta ancora controllando la visione di prima.
        book.Add(_luigi, _dune, _peach, null, Now.AddMinutes(5));

        Assert.False(book.RemoveIfLatest(_luigi, _dune, seen));
        Assert.Single(book.List(_luigi));
        Assert.True(book.RemoveIfLatest(_luigi, _dune, Now.AddMinutes(5)));
        Assert.Empty(book.List(_luigi));
    }

    [Fact]
    public void RemoveDropsTheTitleForThatUserOnly()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, null, Now);
        book.Add(_peach, _dune, _mario, null, Now);

        Assert.True(book.Remove(_luigi, _dune));
        Assert.False(book.Remove(_luigi, _dune));
        Assert.Empty(book.List(_luigi));
        Assert.Single(book.List(_peach));
    }

    [Fact]
    public void PruneDropsOldTitlesLostSendersAndMissingUsers()
    {
        var book = new RecommendationBook();
        var gone = Guid.NewGuid();
        book.Add(_luigi, _dune, _mario, null, Now.AddDays(-70));
        book.Add(_luigi, _dune, _peach, null, Now.AddDays(-10)); // la data del titolo è questa: resta
        book.Add(_luigi, _bear, _mario, null, Now.AddDays(-61));
        book.Add(gone, _bear, _mario, null, Now);

        // Peach non è più amica di Luigi; l'utente "gone" non c'è più.
        var removed = book.Prune(
            Now.AddDays(-60),
            userId => userId != gone,
            (to, from) => from != _peach);

        // Dune perde Peach, poi resta solo il consiglio di 70 giorni fa: esce.
        Assert.Equal(3, removed);
        Assert.Empty(book.List(_luigi));
        Assert.Empty(book.List(gone));
    }

    [Fact]
    public void TheFileKeepsEverythingAndRejectsBrokenEntries()
    {
        var book = new RecommendationBook();
        book.Add(_luigi, _dune, _mario, "da vedere", Now);
        book.Add(_luigi, _dune, _peach, null, Now.AddMinutes(1));

        var copy = RecommendationBook.FromFile(book.ToFile());

        var title = Assert.Single(copy.List(_luigi));
        Assert.Equal(_dune, title.ItemId);
        Assert.Equal(new[] { _peach, _mario }, title.From.Select(f => f.UserId));
        Assert.Equal("da vedere", title.From[1].Message);
        Assert.Null(title.From[0].Message);

        Assert.Throws<FormatException>(() => RecommendationBook.FromFile(new RecommendationFile
        {
            Users = new() { ["non-un-id"] = [] },
        }));
        Assert.Throws<FormatException>(() => RecommendationBook.FromFile(new RecommendationFile
        {
            Users = new() { [_luigi.ToString("N")] = [null] },
        }));
        Assert.Throws<FormatException>(() => RecommendationBook.FromFile(new RecommendationFile
        {
            Users = new()
            {
                [_luigi.ToString("N")] = [new RecommendationFileTitle { ItemId = _dune.ToString("N"), From = [null] }],
            },
        }));
    }
}
```

`RecommendationStoreTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 12, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private RecommendationStore Store() => new(_folder.RecommendationsFile, NullLogger<RecommendationStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().List(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.RecommendationsFile));
    }

    [Fact]
    public void SaveCreatesTheFolderAndLoadReadsItBack()
    {
        var (luigi, dune, mario) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var book = new RecommendationBook();
        book.Add(luigi, dune, mario, "da vedere", Now);

        Store().Save(book);

        Assert.True(File.Exists(_folder.RecommendationsFile));
        Assert.False(File.Exists(_folder.RecommendationsFile + ".tmp"));
        var sender = Assert.Single(Assert.Single(Store().Load().List(luigi)).From);
        Assert.Equal(mario, sender.UserId);
        Assert.Equal("da vedere", sender.Message);
        Assert.Equal(Now, sender.CreatedAt);
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RecommendationsFile)!);
        File.WriteAllText(_folder.RecommendationsFile, "{ non è json");

        Assert.Empty(Store().Load().List(Guid.NewGuid()));

        Assert.False(File.Exists(_folder.RecommendationsFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.RecommendationsFile + ".bad"));
    }

    [Fact]
    public void FailedMoveAsideStillStartsEmptyAndTheNextSaveOverwrites()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RecommendationsFile)!);
        File.WriteAllText(_folder.RecommendationsFile, "{ non è json");

        // Una cartella al posto di recommendations.json.bad: File.Move(..., overwrite: true) fallisce.
        Directory.CreateDirectory(_folder.RecommendationsFile + ".bad");

        var store = Store();
        var book = store.Load();
        Assert.Empty(book.List(Guid.NewGuid()));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.RecommendationsFile));

        var (luigi, dune, mario) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        book.Add(luigi, dune, mario, null, Now);
        store.Save(book);

        Assert.Single(Store().Load().List(luigi));
    }

    [Fact]
    public void BrokenEntriesAreMovedAsideToo()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.RecommendationsFile)!);
        File.WriteAllText(
            _folder.RecommendationsFile,
            "{\"Version\":1,\"Users\":{\"" + Guid.NewGuid().ToString("N") + "\":[{\"ItemId\":\"x\",\"From\":[]}]}}");

        Store().Load();

        Assert.True(File.Exists(_folder.RecommendationsFile + ".bad"));
    }

    [Fact]
    public void DefaultPathIsNextToTheInbox()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");
        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "recommendations.json"),
            RecommendationStore.DefaultPath(paths));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~RecommendationBookTests|FullyQualifiedName~RecommendationStoreTests"`
Expected: FAIL (tipi mancanti).

- [ ] **Step 3: il codice**

`Hub/RecommendationFile.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di recommendations.json (spec N §6.1): per ogni destinatario
/// (id in formato "N") i titoli consigliati con i loro mittenti. Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="RecommendationBook.FromFile"/>.
/// </summary>
public sealed class RecommendationFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Users")]
    public Dictionary<string, List<RecommendationFileTitle?>?>? Users { get; set; } = [];
}

/// <summary>Un titolo consigliato, nel file.</summary>
public sealed class RecommendationFileTitle
{
    /// <summary>Il film o la serie, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("From")]
    public List<RecommendationFileSender?>? From { get; set; } = [];
}

/// <summary>Chi ha consigliato il titolo, nel file.</summary>
public sealed class RecommendationFileSender
{
    /// <summary>L'amico, in formato "N".</summary>
    [JsonPropertyName("UserId")]
    public string? UserId { get; set; }

    /// <summary>Il messaggio; manca se non c'è.</summary>
    [JsonPropertyName("Message")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Message { get; set; }

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }
}
```

`Hub/RecommendationBook.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Chi ha consigliato un titolo (spec N §6.1): l'amico, il messaggio (null se nessuno) e quando.</summary>
public sealed record RecommendationSender(Guid UserId, string? Message, DateTimeOffset CreatedAt);

/// <summary>Un titolo consigliato a un utente, con i mittenti dal più recente.</summary>
public sealed record RecommendedTitle(Guid ItemId, IReadOnlyList<RecommendationSender> From)
{
    /// <summary>La "data" del titolo (spec N §6.1): il consiglio più recente.</summary>
    public DateTimeOffset LatestAt => From.Count == 0 ? DateTimeOffset.MinValue : From.Max(f => f.CreatedAt);
}

/// <summary>
/// I consigli in memoria (spec N §6.1): per destinatario, titoli con i loro
/// mittenti. Non è sicuro tra thread: lo usa solo RecommendationService,
/// sotto lock.
/// </summary>
public sealed class RecommendationBook
{
    /// <summary>Titoli al massimo per destinatario: oltre esce quello con la data più vecchia.</summary>
    public const int MaxTitles = 50;

    private readonly Dictionary<Guid, List<Title>> _users = [];

    /// <summary>I titoli dell'utente dalla data più recente, ognuno con i mittenti dal più recente (copie).</summary>
    public IReadOnlyList<RecommendedTitle> List(Guid userId) =>
        _users.TryGetValue(userId, out var titles)
            ? titles.Select(t => t.Snapshot()).OrderByDescending(t => t.LatestAt).ToList()
            : [];

    /// <summary>
    /// Il consiglio di fromUserId a toUserId: se lo stesso amico aveva già
    /// consigliato il titolo, messaggio e data si aggiornano.
    /// </summary>
    public void Add(Guid toUserId, Guid itemId, Guid fromUserId, string? message, DateTimeOffset now)
    {
        var titles = Titles(toUserId);
        var title = titles.Find(t => t.ItemId == itemId);
        if (title is null)
        {
            title = new Title(itemId);
            titles.Add(title);
        }

        title.From.RemoveAll(f => f.UserId == fromUserId);
        title.From.Add(new RecommendationSender(fromUserId, message, now));
        if (titles.Count > MaxTitles)
        {
            titles.Remove(titles.MinBy(t => t.LatestAt)!);
        }
    }

    /// <summary>Toglie il titolo all'utente ("Non mi interessa"); true se c'era.</summary>
    public bool Remove(Guid userId, Guid itemId) =>
        _users.TryGetValue(userId, out var titles) && titles.RemoveAll(t => t.ItemId == itemId) > 0;

    /// <summary>
    /// Toglie il titolo solo se il suo consiglio più recente è ancora
    /// latestAt: un consiglio arrivato dopo il controllo lo tiene (piano 20a,
    /// decisione 3).
    /// </summary>
    public bool RemoveIfLatest(Guid userId, Guid itemId, DateTimeOffset latestAt) =>
        _users.TryGetValue(userId, out var titles)
        && titles.RemoveAll(t => t.ItemId == itemId && t.LatestAt == latestAt) > 0;

    /// <summary>Toglie un mittente dal titolo; il titolo senza mittenti esce. True se c'era.</summary>
    public bool RemoveSender(Guid userId, Guid itemId, Guid fromUserId)
    {
        if (!_users.TryGetValue(userId, out var titles)
            || titles.Find(t => t.ItemId == itemId) is not { } title
            || title.From.RemoveAll(f => f.UserId == fromUserId) == 0)
        {
            return false;
        }

        if (title.From.Count == 0)
        {
            titles.Remove(title);
        }

        return true;
    }

    /// <summary>
    /// Pulizia (spec N §6.3, piano 20a decisione 2): toglie i destinatari che
    /// non esistono più, i mittenti che keepSender(destinatario, mittente)
    /// scarta e poi i titoli senza mittenti o con la data prima di cutoff.
    /// Restituisce quanti titoli ha tolto.
    /// </summary>
    public int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists, Func<Guid, Guid, bool> keepSender)
    {
        var removed = 0;
        foreach (var (userId, titles) in _users.ToList())
        {
            if (!userExists(userId))
            {
                removed += titles.Count;
                _users.Remove(userId);
                continue;
            }

            foreach (var title in titles)
            {
                title.From.RemoveAll(f => !keepSender(userId, f.UserId));
            }

            removed += titles.RemoveAll(t => t.From.Count == 0 || t.LatestAt < cutoff);
            if (titles.Count == 0)
            {
                _users.Remove(userId);
            }
        }

        return removed;
    }

    /// <summary>Dal file; FormatException se un utente, un titolo o un mittente non è valido.</summary>
    public static RecommendationBook FromFile(RecommendationFile file)
    {
        var book = new RecommendationBook();
        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("consigli di un utente non validi");
            }

            var titles = book.Titles(userId);
            foreach (var raw in value)
            {
                if (raw is null || !Guid.TryParse(raw.ItemId, out var itemId) || raw.From is null)
                {
                    throw new FormatException("titolo consigliato non valido");
                }

                var title = new Title(itemId);
                foreach (var sender in raw.From)
                {
                    if (sender is null || !Guid.TryParse(sender.UserId, out var fromUserId))
                    {
                        throw new FormatException("mittente non valido");
                    }

                    var message = string.IsNullOrEmpty(sender.Message) ? null : sender.Message;
                    title.From.Add(new RecommendationSender(fromUserId, message, sender.CreatedAt));
                }

                if (title.From.Count > 0)
                {
                    titles.Add(title);
                }
            }
        }

        return book;
    }

    public RecommendationFile ToFile() => new()
    {
        Users = _users.ToDictionary(
            pair => pair.Key.ToString("N"),
            pair => (List<RecommendationFileTitle?>?)pair.Value
                .Select(t => t.Snapshot())
                .OrderByDescending(t => t.LatestAt)
                .Select(t => (RecommendationFileTitle?)new RecommendationFileTitle
                {
                    ItemId = t.ItemId.ToString("N"),
                    From = t.From
                        .Select(f => (RecommendationFileSender?)new RecommendationFileSender
                        {
                            UserId = f.UserId.ToString("N"),
                            Message = f.Message,
                            CreatedAt = f.CreatedAt,
                        })
                        .ToList(),
                })
                .ToList()),
    };

    private List<Title> Titles(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var titles))
        {
            titles = [];
            _users[userId] = titles;
        }

        return titles;
    }

    private sealed class Title(Guid itemId)
    {
        public Guid ItemId { get; } = itemId;

        public List<RecommendationSender> From { get; } = [];

        public DateTimeOffset LatestAt => From.Count == 0 ? DateTimeOffset.MinValue : From.Max(f => f.CreatedAt);

        public RecommendedTitle Snapshot() => new(ItemId, From.OrderByDescending(f => f.CreatedAt).ToList());
    }
}
```

`Hub/RecommendationStore.cs`:

```csharp
using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// recommendations.json su disco (spec N §6.1), accanto a inbox.json nelle
/// configurazioni dei plugin. Non è sicuro tra thread: lo usa solo
/// RecommendationService, sotto lock.
/// </summary>
public sealed class RecommendationStore(string filePath, ILogger<RecommendationStore> logger)
{
    public const string FileName = "recommendations.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// recommendations.json.bad e si riparte vuoti; se non si riesce a
    /// spostarlo si riparte vuoti lo stesso (il prossimo salvataggio lo
    /// sovrascrive).
    /// </summary>
    public RecommendationBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new RecommendationBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<RecommendationFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return RecommendationBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Consigli illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Come la cassetta: lo spostamento è una copia di cortesia, i consigli
                // devono funzionare lo stesso. Nel log solo il percorso, mai il contenuto.
                logger.LogWarning(moveError, "Consigli illeggibili e non spostabili in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return new RecommendationBook();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(RecommendationBook book)
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

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde (810 + 14).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recommendations store"
```

---

### Task 2: titoli consigliabili e voce nella cassetta

**Files:**
- Create: `Hub/IRecommendationLibrary.cs`
- Modify: `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs`
- Modify (test): `FakeServer.cs`
- Test: `InboxRecommendationTests.cs`

**Interfaces:**
- Consumes: niente dal Task 1.
- Produces:
  - `record RecommendableItem(Guid Id, string Name, int? Year)` con `string DisplayTitle` ("Dune (2021)", o solo il nome senza anno);
  - `interface IRecommendationLibrary { RecommendableItem? GetTitle(Guid itemId); DateTimeOffset? LastWatched(Guid userId, Guid itemId); }`;
  - `InboxEntryTypes.Recommendation = "Recommendation"`, `InboxEntry.FromUserId`;
  - `InboxBook.UpsertRecommendation(Guid userId, InboxEntry entry)`;
  - `InboxService.AddRecommendationsAsync(Guid fromUserId, string fromName, RecommendableItem item, string? message, IReadOnlyList<Guid> recipients)` (non lancia);
  - `FakeServer`: `Dictionary<Guid, RecommendableItem> Recommendables`, `Dictionary<(Guid UserId, Guid ItemId), DateTimeOffset> Watched`, `AddRecommendable(string name, int? year = null)`; `LibraryFails` vale anche per `LastWatched`.

- [ ] **Step 1: i test che falliscono**

In `FakeServer.cs` aggiungi `IRecommendationLibrary` all'elenco delle interfacce della classe e, prima di `TrySendAsync`:

```csharp
    /// <summary>Film e serie che si possono consigliare (spec N), per id.</summary>
    public Dictionary<Guid, RecommendableItem> Recommendables { get; } = [];

    /// <summary>Ultima visione per (utente, film o serie).</summary>
    public Dictionary<(Guid UserId, Guid ItemId), DateTimeOffset> Watched { get; } = [];

    public RecommendableItem AddRecommendable(string name, int? year = null)
    {
        var item = new RecommendableItem(Guid.NewGuid(), name, year);
        Recommendables[item.Id] = item;
        return item;
    }

    public RecommendableItem? GetTitle(Guid itemId) => Recommendables.GetValueOrDefault(itemId);

    public DateTimeOffset? LastWatched(Guid userId, Guid itemId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile")
        : Watched.TryGetValue((userId, itemId), out var at) ? at : null;
```

`InboxRecommendationTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxRecommendationTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;

    public InboxRecommendationTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose() => _folder.Dispose();

    [Fact]
    public void TheTitleHasTheYearWhenKnown()
    {
        Assert.Equal("Dune (2021)", new RecommendableItem(Guid.NewGuid(), "Dune", 2021).DisplayTitle);
        Assert.Equal("Dune", new RecommendableItem(Guid.NewGuid(), "Dune", null).DisplayTitle);
    }

    [Fact]
    public async Task EachRecipientGetsAnEntryAndItsSessionsAreNotified()
    {
        var dune = _server.AddRecommendable("Dune", 2021);

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", dune, "da vedere", [_luigi.Id, _peach.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(InboxEntryTypes.Recommendation, entry.Type);
        Assert.Equal(dune.Id.ToString("N"), entry.ItemId);
        Assert.Equal(_mario.Id.ToString("N"), entry.FromUserId);
        Assert.Equal("Mario", entry.FromName);
        Assert.Equal("Dune (2021)", entry.Title);
        Assert.Equal("da vedere", entry.Text);
        Assert.False(entry.Read);
        Assert.Single(_inbox.Get(_peach.Id).Entries);
        Assert.Equal(
            "InboxChanged",
            JsonDocument.Parse(Assert.Single(_server.SentTo("s-luigi"))).RootElement.GetProperty("Type").GetString());
    }

    [Fact]
    public async Task RecommendingAgainUpdatesTheSameEntry()
    {
        var dune = _server.AddRecommendable("Dune");
        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", dune, "da vedere", [_luigi.Id]);
        var first = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        await _inbox.MarkReadAsync(_luigi.Id, first.Seq);
        _time.Advance(TimeSpan.FromHours(1));

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", dune, null, [_luigi.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(first.Id, entry.Id);
        Assert.True(entry.Seq > first.Seq);
        Assert.False(entry.Read);
        Assert.Null(entry.Text);
        Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);

        // Un altro amico, o un altro titolo: un'altra voce.
        await _inbox.AddRecommendationsAsync(_peach.Id, "Peach", dune, null, [_luigi.Id]);
        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", _server.AddRecommendable("The Bear"), null, [_luigi.Id]);
        Assert.Equal(3, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task ASendingErrorStaysInTheLog()
    {
        _server.Failing.Add("s-luigi");

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", _server.AddRecommendable("Dune"), null, [_luigi.Id]);

        Assert.Single(_inbox.Get(_luigi.Id).Entries);
    }

    [Fact]
    public void TheEntryWritesOnlyItsFields()
    {
        var json = JsonSerializer.Serialize(new InboxEntry
        {
            Id = "a", Seq = 1, Type = InboxEntryTypes.Recommendation, ItemId = "b", FromUserId = "c", FromName = "Mario", Title = "Dune",
        });

        using var document = JsonDocument.Parse(json);
        Assert.Equal("c", document.RootElement.GetProperty("FromUserId").GetString());
        Assert.False(document.RootElement.TryGetProperty("Text", out _));
        Assert.False(document.RootElement.TryGetProperty("GroupId", out _));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~InboxRecommendationTests"`
Expected: FAIL (tipi e membri mancanti).

- [ ] **Step 3: il codice**

`Hub/IRecommendationLibrary.cs`:

```csharp
using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un film o una serie che si può consigliare (spec N §6.2).</summary>
public sealed record RecommendableItem(Guid Id, string Name, int? Year)
{
    /// <summary>Il titolo della voce nella cassetta: "Dune (2021)", o solo il nome senza anno.</summary>
    public string DisplayTitle =>
        Year is { } year ? string.Create(CultureInfo.InvariantCulture, $"{Name} ({year})") : Name;
}

/// <summary>La libreria come serve ai consigli (adattatore di ILibraryManager, IUserManager e IUserDataManager).</summary>
public interface IRecommendationLibrary
{
    /// <summary>Il film o la serie; null se non c'è o è un altro tipo (episodio, stagione, collezione…).</summary>
    RecommendableItem? GetTitle(Guid itemId);

    /// <summary>
    /// Quando l'utente ha guardato il titolo l'ultima volta (spec N §6.3):
    /// per un film la sua ultima visione, per una serie quella dell'episodio
    /// visto più di recente. Null se mai, o se utente o titolo non ci sono.
    /// </summary>
    DateTimeOffset? LastWatched(Guid userId, Guid itemId);
}
```

In `Protocol/InboxDtos.cs`:
- in `InboxEntryTypes`, dopo `ContactReminder`:

```csharp

    /// <summary>Un amico consiglia un film o una serie (spec N §6.4).</summary>
    public const string Recommendation = "Recommendation";
```

- in `InboxEntry`, dopo `FromName`:

```csharp

    /// <summary>Recommendation: chi consiglia, in formato "N" (la sua voce si aggiorna se riconsiglia).</summary>
    [JsonPropertyName("FromUserId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromUserId { get; set; }
```

- i commenti di `FromName`, `Title`, `Text` e `ItemId` diventano:
  - `FromName`: `/// <summary>Invite: chi ha invitato. Recommendation: chi consiglia.</summary>`;
  - `Title`: `/// <summary>Invite: il titolo, dal nome del gruppo ("Host · Titolo"). RequestAvailable e RequestPending: il titolo da Seerr ("Dune (2021)"). Recommendation: nome e anno ("Dune (2021)").</summary>`;
  - `Text`: `/// <summary>Announcement: il testo dell'admin. Recommendation: il messaggio; manca senza messaggio.</summary>`;
  - `ItemId`: `/// <summary>RequestAvailable: il titolo nella libreria, in formato "N", se Seerr lo conosce. Recommendation: il film o la serie consigliati.</summary>`.

In `Hub/InboxBook.cs`, dopo `UpsertRequest`:

```csharp
    /// <summary>
    /// Il consiglio di un amico (spec N §6.4): se l'utente ha già la voce
    /// dello stesso amico per lo stesso titolo, la aggiorna (nome, titolo,
    /// messaggio, ora, di nuovo non letta, Seq nuovo: torna in cima),
    /// altrimenti la aggiunge. Restituisce una copia.
    /// </summary>
    public InboxEntry UpsertRecommendation(Guid userId, InboxEntry entry)
    {
        var inbox = Inbox(userId);
        var existing = inbox.Entries.FirstOrDefault(e =>
            e.Type == InboxEntryTypes.Recommendation
            && string.Equals(e.FromUserId, entry.FromUserId, StringComparison.OrdinalIgnoreCase)
            && string.Equals(e.ItemId, entry.ItemId, StringComparison.OrdinalIgnoreCase));
        if (existing is null)
        {
            return Add(userId, entry);
        }

        existing.FromName = entry.FromName;
        existing.Title = entry.Title;
        existing.Text = entry.Text;
        existing.CreatedAt = entry.CreatedAt;
        existing.Read = false;
        existing.Seq = inbox.NextSeq++;
        return existing.Copy();
    }
```

In `Hub/InboxService.cs`, dopo `RemoveContactRemindersAsync`:

```csharp
    /// <summary>
    /// Le voci di un consiglio (spec N §6.4), una per destinatario, e
    /// l'avviso alle loro sessioni. I destinatari sono già controllati da
    /// RecommendationService. Non lancia: un errore finisce nel log.
    /// </summary>
    public async Task AddRecommendationsAsync(
        Guid fromUserId, string fromName, RecommendableItem item, string? message, IReadOnlyList<Guid> recipients)
    {
        if (recipients.Count == 0)
        {
            return;
        }

        try
        {
            var now = time.GetUtcNow();
            lock (_lock)
            {
                foreach (var userId in recipients)
                {
                    Book.UpsertRecommendation(userId, new InboxEntry
                    {
                        Type = InboxEntryTypes.Recommendation,
                        CreatedAt = now,
                        ItemId = item.Id.ToString("N"),
                        FromUserId = fromUserId.ToString("N"),
                        FromName = fromName,
                        Title = item.DisplayTitle,
                        Text = message,
                    });
                }

                Persist();
            }

            logger.LogDebug("Voci del consiglio di {ItemId} a {Count} utenti", item.Id.ToString("N"), recipients.Count);
            await NotifyAsync(recipients).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci del consiglio di {ItemId} non create o non notificate", item.Id.ToString("N"));
        }
    }
```

Nel commento della classe `InboxService`: "…i promemoria dei contatti (spec L), i consigli degli amici (spec N), pulizia…".

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recommendation entries in the inbox"
```

---

### Task 3: le regole dei consigli

**Files:**
- Create: `Protocol/RecommendationDtos.cs`, `Hub/RecommendationService.cs`
- Modify: `Hub/LimitTypes.cs`, `Hub/RateLimiter.cs`
- Create (test): `TestRecommendations.cs`
- Test: `RecommendationServiceTests.cs`, `RateLimiterTests.cs` (modifica)

**Interfaces:**
- Consumes: `RecommendationBook`, `RecommendationStore` (Task 1); `IRecommendationLibrary`, `RecommendableItem`, `InboxService.AddRecommendationsAsync` (Task 2); `FriendService`, `IUserDirectory`, `ISessionDirectory`, `ILibraryAccess`, `RateLimiter`.
- Produces:
  - DTO: `RecommendationTarget(UserId, Name, Online, CanSee)`, `RecommendationTargetsResponse(Friends)`, `RecommendRequest { ItemId, To, Message }`, `RecommendResponse(Sent)`, `RecommendationFrom(UserId, Name, Message, CreatedAt)`, `RecommendationItem(ItemId, From)`, `RecommendationsResponse(Items)`;
  - `LimitTypes.Recommendations`; `RateLimiter.TryAcquire(string key, string type, int count)`;
  - `RecommendationService(RecommendationStore, FriendService, IUserDirectory, ISessionDirectory, ILibraryAccess, IRecommendationLibrary, InboxService, RateLimiter, TimeProvider, ILogger<RecommendationService>)` con `MaxAge` (60 giorni), `MaxMessageLength` (200), `MaxRecipients` (50), `Load()`, `Targets(Guid, string?)`, `RecommendAsync(Guid, RecommendRequest?)`, `List(Guid)`, `Dismiss(Guid, string?)`, `Cleanup()`;
  - test: `TestRecommendations.Create(FakeServer, TempFolder, TimeProvider, FriendService)` e `TestRecommendations.Friends(FakeServer, TempFolder, TimeProvider)`.

- [ ] **Step 1: i test che falliscono**

In `RateLimiterTests.cs`, in fondo alla classe:

```csharp
    [Fact]
    public void RecommendationsThirtyRecipientsPerHourAllOrNothing()
    {
        var limiter = new RateLimiter(_time);
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Recommendations, 25));
        Assert.False(limiter.TryAcquire("u1", LimitTypes.Recommendations, 6), "non ci stanno: nessun posto preso");
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Recommendations, 5));
        Assert.False(limiter.TryAcquire("u1", LimitTypes.Recommendations));
        Assert.True(limiter.TryAcquire("u2", LimitTypes.Recommendations, 30));
        _time.Advance(TimeSpan.FromHours(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Recommendations, 30));
    }
```

`TestRecommendations.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I consigli dei test: server finto, amici e cassetta veri, file in una cartella temporanea.</summary>
internal static class TestRecommendations
{
    public static FriendService Friends(FakeServer server, TempFolder folder, TimeProvider time) =>
        new(
            new FriendStore(folder.FriendsFile, NullLogger<FriendStore>.Instance),
            server, server, server, new RateLimiter(time), time, NullLogger<FriendService>.Instance);

    public static RecommendationService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, InboxService? inbox = null) =>
        new(
            new RecommendationStore(folder.RecommendationsFile, NullLogger<RecommendationStore>.Instance),
            friends, server, server, server, server,
            inbox ?? TestInbox.Create(server, folder, time),
            new RateLimiter(time), time, NullLogger<RecommendationService>.Instance);

    /// <summary>
    /// a e b diventano amici: a chiede, b accetta. Le richieste hanno un
    /// limite per chi chiede (20 all'ora) e vanno solo verso utenti attivi:
    /// per dare tanti amici a uno, o un amico disabilitato, chiede l'altro.
    /// </summary>
    public static async Task MakeFriendsAsync(FriendService friends, Guid a, Guid b)
    {
        await friends.RequestAsync(a, b);
        await friends.AcceptAsync(b, a);
    }
}
```

`RecommendationServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly InboxService _inbox;
    private readonly RecommendationService _service;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly RecommendableItem _dune;

    public RecommendationServiceTests()
    {
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _inbox = TestInbox.Create(_server, _folder, _time);
        _service = TestRecommendations.Create(_server, _folder, _time, _friends, _inbox);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _dune = _server.AddRecommendable("Dune", 2021);
        TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id).GetAwaiter().GetResult();
        TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _peach.Id).GetAwaiter().GetResult();
        TestRecommendations.MakeFriendsAsync(_friends, _peach.Id, _luigi.Id).GetAwaiter().GetResult();
    }

    public void Dispose() => _folder.Dispose();

    private static string N(Guid id) => id.ToString("N");

    private Task<HubResult<RecommendResponse>> Recommend(
        UserRef from, RecommendableItem item, string? message, params UserRef[] to) =>
        _service.RecommendAsync(
            from.Id, new RecommendRequest { ItemId = N(item.Id), To = to.Select(u => (string?)N(u.Id)).ToList(), Message = message });

    [Fact]
    public void TargetsAreActiveFriendsByNameWithOnlineAndAccess()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);
        TestRecommendations.MakeFriendsAsync(_friends, bowser.Id, _mario.Id).GetAwaiter().GetResult();
        _server.AddSession("s-peach", _peach);
        _server.Unseen.Add((_luigi.Id, _dune.Id));

        var result = _service.Targets(_mario.Id, N(_dune.Id));

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(
            new[] { ("Luigi", false, false), ("Peach", true, true) },
            result.Value!.Friends.Select(f => (f.Name, f.Online, f.CanSee)));
        Assert.Equal(N(_luigi.Id), result.Value.Friends[0].UserId);
    }

    [Fact]
    public void TargetsNeedATitleTheCallerCanSee()
    {
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, null).Status);
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, "non-un-id").Status);
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, N(Guid.NewGuid())).Status);
        _server.Unseen.Add((_mario.Id, _dune.Id));
        Assert.Equal(HubStatus.Invalid, _service.Targets(_mario.Id, N(_dune.Id)).Status);
    }

    [Fact]
    public async Task ARecommendationReachesTheListAndTheInbox()
    {
        var result = await Recommend(_mario, _dune, "da vedere", _luigi, _peach);

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(2, result.Value!.Sent);
        var item = Assert.Single(_service.List(_luigi.Id).Items);
        Assert.Equal(N(_dune.Id), item.ItemId);
        var from = Assert.Single(item.From);
        Assert.Equal((N(_mario.Id), "Mario", "da vedere", _time.GetUtcNow()), (from.UserId, from.Name, from.Message, from.CreatedAt));
        var entry = Assert.Single(_inbox.Get(_peach.Id).Entries);
        Assert.Equal(InboxEntryTypes.Recommendation, entry.Type);
        Assert.Equal("Dune (2021)", entry.Title);
        Assert.Empty(_service.List(_mario.Id).Items);
    }

    [Fact]
    public async Task InvalidRecipientsAreSkippedSilently()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);
        TestRecommendations.MakeFriendsAsync(_friends, bowser.Id, _mario.Id).GetAwaiter().GetResult();
        var toad = _server.AddUser("Toad"); // non amico
        _server.Unseen.Add((_peach.Id, _dune.Id));

        var result = await _service.RecommendAsync(_mario.Id, new RecommendRequest
        {
            ItemId = N(_dune.Id),
            To = ["non-un-id", null, N(_mario.Id), N(_luigi.Id), N(_luigi.Id), N(toad.Id), N(bowser.Id), N(_peach.Id), N(Guid.NewGuid())],
        });

        Assert.Equal(1, result.Value!.Sent);
        Assert.Single(_service.List(_luigi.Id).Items);
        Assert.Empty(_service.List(_peach.Id).Items);
        Assert.Empty(_inbox.Get(toad.Id).Entries);

        // Nessuno valido: riuscito, ma non arriva a nessuno.
        Assert.Equal(0, (await Recommend(_mario, _dune, null, toad)).Value!.Sent);
    }

    [Fact]
    public async Task BadRequestsAreInvalid()
    {
        var episode = new RecommendableItem(Guid.NewGuid(), "Pilot", null); // non in Recommendables: non è un film né una serie
        Assert.Equal(HubStatus.Invalid, (await _service.RecommendAsync(_mario.Id, null)).Status);
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, episode, null, _luigi)).Status);
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, _dune, null)).Status);
        Assert.Equal(
            HubStatus.Invalid,
            (await _service.RecommendAsync(_mario.Id, new RecommendRequest { ItemId = N(_dune.Id), To = null })).Status);
        Assert.Equal(
            HubStatus.Invalid,
            (await _service.RecommendAsync(_mario.Id, new RecommendRequest
            {
                ItemId = N(_dune.Id),
                To = Enumerable.Range(0, RecommendationService.MaxRecipients + 1).Select(_ => (string?)N(_luigi.Id)).ToList(),
            })).Status);

        _server.Unseen.Add((_mario.Id, _dune.Id));
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, _dune, null, _luigi)).Status);
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task MessagesAreCleanedAndCountedInCodePoints()
    {
        await Recommend(_mario, _dune, "  \n \r\n ", _luigi);
        Assert.Null(Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Message);

        await Recommend(_mario, _dune, " da vedere\r\n\r\nstasera ", _luigi);
        Assert.Equal("da vedere stasera", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Message);

        Assert.Equal(HubStatus.Ok, (await Recommend(_mario, _dune, string.Concat(Enumerable.Repeat("😂", 200)), _luigi)).Status);
        Assert.Equal(HubStatus.Invalid, (await Recommend(_mario, _dune, new string('a', 201), _luigi)).Status);
    }

    [Fact]
    public async Task TooManyRecipientsInAnHourAreRateLimitedAndNothingIsSaved()
    {
        var friends = Enumerable.Range(0, 31).Select(i => _server.AddUser($"Amico {i}")).ToList();
        foreach (var friend in friends)
        {
            // Chiede l'amico: Mario ha un limite di 20 richieste all'ora.
            await TestRecommendations.MakeFriendsAsync(_friends, friend.Id, _mario.Id);
        }

        Assert.Equal(30, (await Recommend(_mario, _dune, null, friends.Take(30).ToArray())).Value!.Sent);
        var other = _server.AddRecommendable("The Bear");

        Assert.Equal(HubStatus.RateLimited, (await Recommend(_mario, other, null, friends[30])).Status);

        Assert.Empty(_service.List(friends[30].Id).Items);
        Assert.Empty(_inbox.Get(friends[30].Id).Entries);
    }

    [Fact]
    public async Task TwoFriendsGiveOneTitleWithBothSenders()
    {
        await Recommend(_mario, _dune, "da vedere", _luigi);
        _time.Advance(TimeSpan.FromMinutes(1));
        await Recommend(_peach, _dune, null, _luigi);

        var item = Assert.Single(_service.List(_luigi.Id).Items);
        Assert.Equal(new[] { "Peach", "Mario" }, item.From.Select(f => f.Name));
        Assert.Equal(2, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task TitlesOlderThan60DaysLeave()
    {
        await Recommend(_mario, _dune, null, _luigi);
        _time.Advance(RecommendationService.MaxAge);
        Assert.Single(_service.List(_luigi.Id).Items);

        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task TitlesTheRecipientCanNoLongerSeeLeave()
    {
        await Recommend(_mario, _dune, null, _luigi);
        _server.Unseen.Add((_luigi.Id, _dune.Id));

        Assert.Empty(_service.List(_luigi.Id).Items);

        // Tolto per sempre: anche con l'accesso di nuovo non torna.
        _server.Unseen.Clear();
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task WatchedTitlesLeaveAndComeBackWhenRecommendedAgain()
    {
        // Visto prima del consiglio: resta.
        _server.Watched[(_luigi.Id, _dune.Id)] = _time.GetUtcNow().AddDays(-3);
        await Recommend(_mario, _dune, null, _luigi);
        Assert.Single(_service.List(_luigi.Id).Items);

        // Visto dopo: esce.
        _time.Advance(TimeSpan.FromHours(2));
        _server.Watched[(_luigi.Id, _dune.Id)] = _time.GetUtcNow();
        Assert.Empty(_service.List(_luigi.Id).Items);

        // Riconsigliato dopo la visione: torna.
        _time.Advance(TimeSpan.FromHours(1));
        await Recommend(_peach, _dune, "di nuovo!", _luigi);
        Assert.Equal("Peach", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Name);
    }

    [Fact]
    public async Task AnUnfriendedSenderLeavesTheOthersStay()
    {
        await Recommend(_mario, _dune, null, _luigi);
        await Recommend(_peach, _dune, null, _luigi);
        await _friends.RemoveAsync(_luigi.Id, _mario.Id);

        Assert.Equal("Peach", Assert.Single(Assert.Single(_service.List(_luigi.Id).Items).From).Name);

        await _friends.RemoveAsync(_luigi.Id, _peach.Id);
        Assert.Empty(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task ALibraryErrorKeepsTheTitleAndTheAnswer()
    {
        await Recommend(_mario, _dune, null, _luigi);
        _server.LibraryFails = true;

        Assert.Single(_service.List(_luigi.Id).Items);

        _server.LibraryFails = false;
        Assert.Single(_service.List(_luigi.Id).Items);
    }

    [Fact]
    public async Task NotInterestedRemovesTheTitleOnly()
    {
        var bear = _server.AddRecommendable("The Bear");
        await Recommend(_mario, _dune, null, _luigi);
        await Recommend(_mario, bear, null, _luigi);

        _service.Dismiss(_luigi.Id, N(_dune.Id));
        _service.Dismiss(_luigi.Id, "non-un-id");
        _service.Dismiss(_luigi.Id, null);

        Assert.Equal(N(bear.Id), Assert.Single(_service.List(_luigi.Id).Items).ItemId);
        // La voce della cassetta resta (spec N §6.4).
        Assert.Equal(2, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task CleanupDropsOldTitlesLostSendersAndMissingUsersAndSaves()
    {
        await Recommend(_mario, _dune, null, _luigi, _peach);
        await _friends.RemoveAsync(_peach.Id, _mario.Id);
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(2, _service.Cleanup());

        var saved = new RecommendationStore(
            _folder.RecommendationsFile, Microsoft.Extensions.Logging.Abstractions.NullLogger<RecommendationStore>.Instance).Load();
        Assert.Empty(saved.List(_luigi.Id));
        Assert.Empty(saved.List(_peach.Id));
        Assert.Equal(0, _service.Cleanup());
    }

    [Fact]
    public async Task RecommendationsSurviveARestart()
    {
        await Recommend(_mario, _dune, "da vedere", _luigi);

        var restarted = TestRecommendations.Create(_server, _folder, _time, _friends, _inbox);

        Assert.Equal("da vedere", Assert.Single(Assert.Single(restarted.List(_luigi.Id).Items).From).Message);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~RecommendationServiceTests|FullyQualifiedName~RateLimiterTests"`
Expected: FAIL (tipi mancanti).

- [ ] **Step 3: il codice**

In `Hub/LimitTypes.cs`, in fondo alla classe:

```csharp

    /// <summary>Destinatari dei consigli, per utente: trenta all'ora (spec N §6.5).</summary>
    public const string Recommendations = "Recommendations";
```

In `Hub/RateLimiter.cs`:
- nella tabella `Limits`, dopo `PasswordChecks`: `[LimitTypes.Recommendations] = (30, TimeSpan.FromHours(1)),`;
- `TryAcquire(string key, string type)` diventa una chiamata all'overload nuovo, che prende il suo corpo:

```csharp
    /// <summary>true (e si conta) se la chiave può farne un altro di questo tipo adesso.</summary>
    public bool TryAcquire(string key, string type) => TryAcquire(key, type, 1);

    /// <summary>
    /// true (e si contano tutti) se la chiave può farne count di questo tipo
    /// adesso; altrimenti false e non si conta niente (spec N §6.2: tutti i
    /// destinatari o nessuno).
    /// </summary>
    public bool TryAcquire(string key, string type, int count)
    {
        if (!Limits.TryGetValue(type, out var limit))
        {
            return true;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (!_sent.TryGetValue((key, type), out var times))
            {
                if (_sent.Count >= SweepThreshold)
                {
                    Sweep(now);
                }

                times = new Queue<DateTimeOffset>();
                _sent[(key, type)] = times;
            }

            while (times.Count > 0 && now - times.Peek() >= limit.Window)
            {
                times.Dequeue();
            }

            if (times.Count + count > limit.Count)
            {
                return false;
            }

            for (var i = 0; i < count; i++)
            {
                times.Enqueue(now);
            }

            return true;
        }
    }
```

`Protocol/RecommendationDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un amico nel pannello "Consiglia a…" (spec N §6.2).</summary>
public sealed record RecommendationTarget(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Online")] bool Online,
    [property: JsonPropertyName("CanSee")] bool CanSee);

/// <summary>Risposta di GET Recommendations/Targets.</summary>
public sealed record RecommendationTargetsResponse(
    [property: JsonPropertyName("Friends")] IReadOnlyList<RecommendationTarget> Friends);

/// <summary>Corpo di POST Recommendations.</summary>
public sealed class RecommendRequest
{
    /// <summary>Il film o la serie, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    /// <summary>Gli amici, in formato "N".</summary>
    [JsonPropertyName("To")]
    public List<string?>? To { get; set; }

    [JsonPropertyName("Message")]
    public string? Message { get; set; }
}

/// <summary>Risposta di POST Recommendations: a quanti amici è arrivato.</summary>
public sealed record RecommendResponse(
    [property: JsonPropertyName("Sent")] int Sent);

/// <summary>Chi ha consigliato un titolo, in GET Recommendations.</summary>
public sealed record RecommendationFrom(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Message"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Message,
    [property: JsonPropertyName("CreatedAt")] DateTimeOffset CreatedAt);

/// <summary>Un titolo consigliato, in GET Recommendations.</summary>
public sealed record RecommendationItem(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("From")] IReadOnlyList<RecommendationFrom> From);

/// <summary>Risposta di GET Recommendations: i titoli dalla data più recente.</summary>
public sealed record RecommendationsResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<RecommendationItem> Items);
```

`Hub/RecommendationService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// I consigli tra amici (spec N §6): destinatari, invio con voce nella
/// cassetta, filtro a lettura, "Non mi interessa" e pulizia. File con
/// <see cref="RecommendationStore"/>. Sicuro tra thread.
/// </summary>
public sealed class RecommendationService(
    RecommendationStore store,
    FriendService friends,
    IUserDirectory users,
    ISessionDirectory sessions,
    ILibraryAccess access,
    IRecommendationLibrary library,
    InboxService inbox,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<RecommendationService> logger)
{
    /// <summary>Quanto resta un titolo dopo il suo consiglio più recente (spec N §6.3).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(60);

    /// <summary>Lunghezza massima del messaggio, in punti di codice (spec N §6.2).</summary>
    public const int MaxMessageLength = 200;

    /// <summary>Destinatari al massimo in una richiesta (spec N §6.2).</summary>
    public const int MaxRecipients = 50;

    private readonly Lock _lock = new();
    private RecommendationBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private RecommendationBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Consigli in {Path}", store.FilePath);
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

    /// <summary>
    /// Gli amici attivi di chi chiama, per nome, con online e accesso al
    /// titolo (spec N §6.2). Invalid se il titolo non è un film o una serie
    /// che chi chiama vede.
    /// </summary>
    public HubResult<RecommendationTargetsResponse> Targets(Guid callerId, string? itemId)
    {
        if (Recommendable(callerId, itemId) is not { } item)
        {
            return HubResult<RecommendationTargetsResponse>.Fail(HubStatus.Invalid);
        }

        var online = sessions.GetAppSessions().Select(s => s.UserId).ToHashSet();
        var targets = friends.FriendsOf(callerId)
            .Select(users.GetUser)
            .OfType<UserRef>()
            .Where(u => u.Enabled)
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .Select(u => new RecommendationTarget(Id(u.Id), u.Name, online.Contains(u.Id), access.CanSee(u.Id, item.Id)))
            .ToList();
        return HubResult<RecommendationTargetsResponse>.Ok(new RecommendationTargetsResponse(targets));
    }

    /// <summary>
    /// Consiglia il titolo (spec N §6.2). Invalid per titolo, messaggio o
    /// destinatari non validi; i destinatari che non vanno bene si saltano in
    /// silenzio; RateLimited oltre il limite, senza salvare niente.
    /// </summary>
    public async Task<HubResult<RecommendResponse>> RecommendAsync(Guid callerId, RecommendRequest? request)
    {
        if (request is null || Recommendable(callerId, request.ItemId) is not { } item)
        {
            return HubResult<RecommendResponse>.Fail(HubStatus.Invalid);
        }

        var message = CleanMessage(request.Message);
        if ((message?.EnumerateRunes().Count() ?? 0) > MaxMessageLength
            || request.To is not { Count: > 0 } to
            || to.Count > MaxRecipients)
        {
            return HubResult<RecommendResponse>.Fail(HubStatus.Invalid);
        }

        var recipients = to
            .Select(raw => Guid.TryParse(raw, out var id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty && id != callerId)
            .Distinct()
            .Where(id => friends.AreFriends(callerId, id)
                && users.GetUser(id) is { Enabled: true }
                && access.CanSee(id, item.Id))
            .ToList();
        if (recipients.Count == 0)
        {
            logger.LogDebug("Consiglio di {ItemId}: nessun destinatario valido", Id(item.Id));
            return HubResult<RecommendResponse>.Ok(new RecommendResponse(0));
        }

        if (!limiter.TryAcquire(Id(callerId), LimitTypes.Recommendations, recipients.Count))
        {
            return HubResult<RecommendResponse>.Fail(HubStatus.RateLimited);
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            foreach (var userId in recipients)
            {
                Book.Add(userId, item.Id, callerId, message, now);
            }

            Persist();
        }

        logger.LogDebug("Consiglio di {ItemId} a {Count} amici", Id(item.Id), recipients.Count);
        var fromName = users.GetUser(callerId)?.Name ?? string.Empty;
        await inbox.AddRecommendationsAsync(callerId, fromName, item, message, recipients).ConfigureAwait(false);
        return HubResult<RecommendResponse>.Ok(new RecommendResponse(recipients.Count));
    }

    /// <summary>
    /// I consigli validi dell'utente (spec N §6.3), dalla data più recente.
    /// Quello che non vale più si toglie dall'archivio. Le domande alla
    /// libreria si fanno fuori dal lock (piano 20a, decisione 3); un errore
    /// della libreria tiene il titolo (decisione 4).
    /// </summary>
    public RecommendationsResponse List(Guid userId)
    {
        IReadOnlyList<RecommendedTitle> titles;
        lock (_lock)
        {
            titles = Book.List(userId);
        }

        var cutoff = time.GetUtcNow() - MaxAge;
        var keep = new List<RecommendedTitle>();
        var lostSenders = new List<(Guid ItemId, Guid FromUserId)>();
        var lostTitles = new List<RecommendedTitle>();
        foreach (var title in titles)
        {
            var from = title.From.Where(f => users.GetUser(f.UserId) is not null && friends.AreFriends(userId, f.UserId)).ToList();
            lostSenders.AddRange(title.From.Where(f => !from.Contains(f)).Select(f => (title.ItemId, f.UserId)));
            if (from.Count == 0)
            {
                continue;
            }

            var current = title with { From = from };
            if (current.LatestAt < cutoff)
            {
                lostTitles.Add(current);
                continue;
            }

            try
            {
                if (!access.CanSee(userId, title.ItemId) || library.LastWatched(userId, title.ItemId) > current.LatestAt)
                {
                    lostTitles.Add(current);
                    continue;
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Consiglio di {ItemId}: libreria non disponibile, il titolo resta", Id(title.ItemId));
            }

            keep.Add(current);
        }

        if (lostSenders.Count > 0 || lostTitles.Count > 0)
        {
            lock (_lock)
            {
                var changed = false;
                foreach (var (itemId, fromUserId) in lostSenders)
                {
                    changed |= Book.RemoveSender(userId, itemId, fromUserId);
                }

                foreach (var title in lostTitles)
                {
                    changed |= Book.RemoveIfLatest(userId, title.ItemId, title.LatestAt);
                }

                if (changed)
                {
                    Persist();
                }
            }

            logger.LogDebug(
                "Consigli di {UserId}: tolti {Titles} titoli e {Senders} mittenti", Id(userId), lostTitles.Count, lostSenders.Count);
        }

        var items = keep
            .OrderByDescending(t => t.LatestAt)
            .Select(t => new RecommendationItem(
                Id(t.ItemId),
                t.From
                    .Select(f => new RecommendationFrom(Id(f.UserId), users.GetUser(f.UserId)?.Name ?? string.Empty, f.Message, f.CreatedAt))
                    .ToList()))
            .ToList();
        return new RecommendationsResponse(items);
    }

    /// <summary>"Non mi interessa" (spec N §6.2): toglie il titolo; niente se non c'è o l'id non vale.</summary>
    public void Dismiss(Guid userId, string? itemId)
    {
        if (!Guid.TryParse(itemId, out var id))
        {
            return;
        }

        lock (_lock)
        {
            if (Book.Remove(userId, id))
            {
                Persist();
            }
        }
    }

    /// <summary>
    /// Pulizia periodica (piano 20a, decisione 2): mittenti che non esistono
    /// più o non sono più amici, titoli oltre <see cref="MaxAge"/>,
    /// destinatari cancellati. Restituisce quanti titoli ha tolto.
    /// </summary>
    public int Cleanup()
    {
        lock (_lock)
        {
            var removed = Book.Prune(
                time.GetUtcNow() - MaxAge,
                userId => users.GetUser(userId) is not null,
                (to, from) => users.GetUser(from) is not null && friends.AreFriends(to, from));
            if (removed > 0)
            {
                Persist();
            }

            return removed;
        }
    }

    /// <summary>
    /// Gli a capo diventano spazi, le righe vuote spariscono, spazi ai bordi
    /// tolti (piano 20a, decisione 6); null se non resta niente.
    /// </summary>
    internal static string? CleanMessage(string? text)
    {
        if (text is null)
        {
            return null;
        }

        var joined = string.Join(' ', text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        return joined.Length == 0 ? null : joined;
    }

    // Il titolo, se è un film o una serie che chi chiama vede.
    private RecommendableItem? Recommendable(Guid callerId, string? itemId) =>
        Guid.TryParse(itemId, out var id) && id != Guid.Empty
        && library.GetTitle(id) is { } item
        && access.CanSee(callerId, id)
            ? item
            : null;

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
            logger.LogWarning(ex, "Consigli non salvati in {Path}", store.FilePath);
        }
    }

    private static string Id(Guid id) => id.ToString("N");
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recommendation rules, filters and rate limit"
```

---

## Gruppo B — endpoint e Home

### Task 4: gli endpoint

**Files:**
- Create: `Api/RecommendationsController.cs`
- Test: `RecommendationsControllerTests.cs`

**Interfaces:**
- Consumes: `RecommendationService` (Task 3), `TestRecommendations` (Task 3).
- Produces: `RecommendationsController(IAuthorizationContext, RecommendationService)` con `GetTargets(string? itemId)`, `Recommend(RecommendRequest?)`, `GetRecommendations()`, `Dismiss(string itemId)`.

- [ ] **Step 1: i test che falliscono**

`RecommendationsControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly RecommendationService _service;
    private readonly RecommendableItem _dune;

    public RecommendationsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true, true);
        var friends = TestRecommendations.Friends(_server, _folder, _time);
        TestRecommendations.MakeFriendsAsync(friends, _mario.Id, _luigi.Id).GetAwaiter().GetResult();
        _service = TestRecommendations.Create(_server, _folder, _time, friends);
        _dune = _server.AddRecommendable("Dune", 2021);
    }

    public void Dispose() => _folder.Dispose();

    private RecommendationsController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new RecommendationsController(new FakeAuthorizationContext(auth), _service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    private static string N(Guid id) => id.ToString("N");

    [Fact]
    public async Task RecommendListAndDismiss()
    {
        var targets = (await Controller(_mario).GetTargets(N(_dune.Id))).Value!;
        Assert.Equal("Luigi", Assert.Single(targets.Friends).Name);

        var sent = (await Controller(_mario).Recommend(new RecommendRequest
        {
            ItemId = N(_dune.Id), To = [N(_luigi.Id)], Message = "da vedere",
        })).Value!;
        Assert.Equal(1, sent.Sent);

        var item = Assert.Single((await Controller(_luigi).GetRecommendations()).Value!.Items);
        Assert.Equal("Mario", Assert.Single(item.From).Name);

        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_luigi).Dismiss(N(_dune.Id))));
        Assert.Empty((await Controller(_luigi).GetRecommendations()).Value!.Items);

        // Mai 404: un id che non c'è, o che non è un id, dà 204.
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_luigi).Dismiss("non-un-id")));
    }

    [Fact]
    public async Task BadRequestsAre400AndTooManyAre429()
    {
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).GetTargets("non-un-id")).Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).GetTargets(null)).Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await Controller(_mario).Recommend(null)).Result!));
        Assert.Equal(
            StatusCodes.Status400BadRequest,
            Status((await Controller(_mario).Recommend(new RecommendRequest
            {
                ItemId = N(_dune.Id), To = [N(_luigi.Id)], Message = new string('a', 201),
            })).Result!));

        for (var i = 0; i < 30; i++)
        {
            await Controller(_mario).Recommend(new RecommendRequest { ItemId = N(_dune.Id), To = [N(_luigi.Id)] });
        }

        Assert.Equal(
            StatusCodes.Status429TooManyRequests,
            Status((await Controller(_mario).Recommend(new RecommendRequest { ItemId = N(_dune.Id), To = [N(_luigi.Id)] })).Result!));
    }

    [Fact]
    public void TheControllerNeedsWatchPartyAccessAndNeverRouteConstraints()
    {
        Assert.Equal(
            Policies.SyncPlayHasAccess,
            Assert.Single(typeof(RecommendationsController).GetCustomAttributes<AuthorizeAttribute>()).Policy);
        // La riflessione non garantisce l'ordine dei metodi: si confrontano gli elenchi ordinati.
        var routes = typeof(RecommendationsController).GetMethods()
            .SelectMany(m => m.GetCustomAttributes<Microsoft.AspNetCore.Mvc.Routing.HttpMethodAttribute>())
            .Select(a => a.Template)
            .Order(StringComparer.Ordinal)
            .ToList();
        Assert.Equal(
            new[] { "Recommendations", "Recommendations", "Recommendations/Targets", "Recommendations/{itemId}" },
            routes);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~RecommendationsControllerTests"`
Expected: FAIL (controller mancante).

- [ ] **Step 3: il codice**

`Api/RecommendationsController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I consigli tra amici (spec N §6.2), con la stessa policy degli amici.
/// Chi chiama è l'utente dell'autenticazione. Come il resto del plugin,
/// mai 404: gli id sono stringhe senza vincoli di rotta.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class RecommendationsController(
    IAuthorizationContext authorizationContext,
    RecommendationService recommendations) : ControllerBase
{
    /// <summary>Gli amici a cui si può consigliare il titolo, con online e accesso.</summary>
    [HttpGet("Recommendations/Targets")]
    public async Task<ActionResult<RecommendationTargetsResponse>> GetTargets([FromQuery] string? itemId)
    {
        var result = recommendations.Targets(await CallerAsync().ConfigureAwait(false), itemId);
        return result.Status == HubStatus.Ok ? result.Value! : BadRequest();
    }

    /// <summary>Consiglia il titolo agli amici scelti; risponde a quanti è arrivato.</summary>
    [HttpPost("Recommendations")]
    public async Task<ActionResult<RecommendResponse>> Recommend([FromBody] RecommendRequest? request)
    {
        var result = await recommendations.RecommendAsync(await CallerAsync().ConfigureAwait(false), request).ConfigureAwait(false);
        if (result.Status == HubStatus.Ok)
        {
            return result.Value!;
        }

        return result.Status == HubStatus.RateLimited ? StatusCode(StatusCodes.Status429TooManyRequests) : BadRequest();
    }

    /// <summary>I consigli ricevuti ancora validi, dal più recente.</summary>
    [HttpGet("Recommendations")]
    public async Task<ActionResult<RecommendationsResponse>> GetRecommendations() =>
        recommendations.List(await CallerAsync().ConfigureAwait(false));

    /// <summary>"Non mi interessa"; 204 anche se il titolo non c'è.</summary>
    [HttpDelete("Recommendations/{itemId}")]
    public async Task<ActionResult> Dismiss([FromRoute] string itemId)
    {
        recommendations.Dismiss(await CallerAsync().ConfigureAwait(false), itemId);
        return NoContent();
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
```

Lo scopo del test delle rotte è che nessun template abbia vincoli (`:guid`): un vincolo risponderebbe 404, cioè "plugin assente".

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recommendations endpoints"
```

---

### Task 5: la riga "Consigliati per te" nella Home

**Files:**
- Modify: `Home/HomeRowIds.cs`, `Home/IHomeLayoutStore.cs`, `Server/PluginHomeLayoutStore.cs`, `Configuration/PluginConfiguration.cs`
- Test: `HomeRowIdsTests.cs`, `PluginConfigurationTests.cs`, `HomeControllerTests.cs` (modifiche)

**Interfaces:**
- Consumes: niente dai task precedenti.
- Produces:
  - `HomeRowIds.Known` con `"recommended"` dopo `"nextUp"`; `HomeRowIds.AddedLater`; `HomeRowIds.ParseSeen(string?)`; `HomeRowIds.WithLaterRows(IReadOnlyList<string>? rows, IReadOnlyList<string> seen)` → `(IReadOnlyList<string>? Rows, IReadOnlyList<string> Seen)?`;
  - `PluginConfiguration.HomeRowsSeen` (`string?`);
  - `IHomeLayoutStore.AddLaterRows()` → `bool` (true se ha salvato).

- [ ] **Step 1: i test che falliscono**

In `HomeRowIdsTests.cs`:
- il primo test diventa:

```csharp
    [Fact]
    public void TheKnownRowsAreTheElevenOfTheSpecsInTheDefaultOrder()
    {
        Assert.Equal(
            new[]
            {
                "resume", "nextUp", "recommended", "requests", "latestMovies", "latestSeries",
                "becauseYouWatched", "continueSaga", "upcomingSeries", "upcomingMovies", "myList",
            },
            HomeRowIds.Known);
        Assert.Equal(new[] { "recommended" }, HomeRowIds.AddedLater);
    }
```

- in fondo alla classe:

```csharp
    [Fact]
    public void LaterRowsGoAfterTheirLastEarlierRowOnce()
    {
        // Dopo nextUp, anche se l'admin l'ha spostata.
        var change = HomeRowIds.WithLaterRows(["myList", "nextUp", "resume"], []);
        Assert.Equal(new[] { "myList", "nextUp", "resume", "recommended" }, change!.Value.Rows);
        Assert.Equal(new[] { "recommended" }, change.Value.Seen);

        Assert.Equal(new[] { "nextUp", "recommended", "myList" }, HomeRowIds.WithLaterRows(["nextUp", "myList"], [])!.Value.Rows);

        // Né resume né nextUp accese: in testa.
        Assert.Equal(new[] { "recommended", "myList" }, HomeRowIds.WithLaterRows(["myList"], [])!.Value.Rows);
        Assert.Equal(new[] { "recommended" }, HomeRowIds.WithLaterRows([], [])!.Value.Rows);

        // Già accesa: resta dov'è, si segna vista.
        var on = HomeRowIds.WithLaterRows(["recommended", "resume"], []);
        Assert.Equal(new[] { "recommended", "resume" }, on!.Value.Rows);

        // Già vista: niente da fare, anche se l'admin l'ha spenta.
        Assert.Null(HomeRowIds.WithLaterRows(["resume"], ["recommended"]));
    }

    [Fact]
    public void ANeverSetHomeOnlyMarksTheLaterRowsSeen()
    {
        var change = HomeRowIds.WithLaterRows(null, []);
        Assert.Null(change!.Value.Rows);
        Assert.Equal(new[] { "recommended" }, change.Value.Seen);
    }

    [Fact]
    public void SeenRowsAreReadFromTheStoredText()
    {
        Assert.Empty(HomeRowIds.ParseSeen(null));
        Assert.Empty(HomeRowIds.ParseSeen(string.Empty));
        Assert.Equal(new[] { "recommended", "x" }, HomeRowIds.ParseSeen(" recommended,,x,recommended"));
    }
```

In `PluginConfigurationTests.cs`, dopo `WithoutThePluginInstanceTheHomeLayoutIsTheDefaultAndCannotBeSaved`:

```csharp
    [Fact]
    public void TheSeenHomeRowsSurviveTheXmlAndWithoutThePluginNothingIsAdded()
    {
        Assert.Null(new PluginConfiguration().HomeRowsSeen);
        Assert.Equal("recommended", RoundTrip(new PluginConfiguration { HomeRowsSeen = "recommended" }).HomeRowsSeen);
        Assert.False(new PluginHomeLayoutStore().AddLaterRows());
    }
```

(`RoundTrip` è l'aiuto che il file usa già per `HomeRows`.)

In `HomeControllerTests.cs`, nel `FakeHomeLayoutStore` privato, dopo `Save`:

```csharp

        public bool AddLaterRows() => false;
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~HomeRowIdsTests|FullyQualifiedName~PluginConfigurationTests|FullyQualifiedName~HomeControllerTests"`
Expected: FAIL (compilazione: membri mancanti).

- [ ] **Step 3: il codice**

In `Home/HomeRowIds.cs`:
- nel commento della classe: "Le righe della Home di WonderFlix (spec M §6.1, spec N §6.7)…";
- in `Known`, dopo `"nextUp",`: `"recommended",`;
- dopo `Known`:

```csharp

    /// <summary>
    /// Le righe nate dopo la 1.7.0 (spec N §6.7): una Home dell'admin salvata
    /// prima non le ha e, senza aggiungerle, sarebbero spente per tutti.
    /// </summary>
    public static readonly IReadOnlyList<string> AddedLater = ["recommended"];
```

- in fondo alla classe:

```csharp

    /// <summary>Le righe già viste dal testo salvato (`HomeRowsSeen`): id senza spazi, senza vuoti e doppioni.</summary>
    public static IReadOnlyList<string> ParseSeen(string? stored) =>
        stored is null
            ? []
            : stored.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Distinct(StringComparer.Ordinal)
                .ToList();

    /// <summary>
    /// La Home dell'admin con le righe di <see cref="AddedLater"/> non ancora
    /// viste (spec N §6.7): ognuna va subito dopo l'ultima riga accesa che la
    /// precede in <see cref="Known"/>, oppure in testa (la regola di spec M
    /// §6.4); una già accesa resta dov'è. Con rows null (mai impostata) le
    /// righe si segnano viste e basta (piano 20a, decisione 8). Null se non
    /// c'è niente da cambiare.
    /// </summary>
    public static (IReadOnlyList<string>? Rows, IReadOnlyList<string> Seen)? WithLaterRows(
        IReadOnlyList<string>? rows, IReadOnlyList<string> seen)
    {
        var missing = AddedLater.Where(id => !seen.Contains(id, StringComparer.Ordinal)).ToList();
        if (missing.Count == 0)
        {
            return null;
        }

        var result = rows?.ToList();
        if (result is not null)
        {
            foreach (var id in missing.Where(id => !result.Contains(id, StringComparer.Ordinal)))
            {
                var earlier = Known.TakeWhile(known => known != id).ToHashSet(StringComparer.Ordinal);
                result.Insert(result.FindLastIndex(earlier.Contains) + 1, id);
            }
        }

        return (result, seen.Concat(missing).ToList());
    }
```

In `Home/IHomeLayoutStore.cs`, dopo `Save`:

```csharp

    /// <summary>
    /// Accende una volta sola le righe nate dopo che l'admin ha salvato la
    /// sua Home (<see cref="HomeRowIds.WithLaterRows"/>); true se ha salvato.
    /// </summary>
    bool AddLaterRows();
```

In `Server/PluginHomeLayoutStore.cs`, dopo `Save`:

```csharp

    public bool AddLaterRows()
    {
        // Senza plugin (nei test) non c'è niente da salvare.
        var plugin = Plugin.Instance;
        if (plugin is null)
        {
            return false;
        }

        lock (_lock)
        {
            var config = plugin.Configuration;
            var change = HomeRowIds.WithLaterRows(HomeRowIds.Parse(config.HomeRows), HomeRowIds.ParseSeen(config.HomeRowsSeen));
            if (change is null)
            {
                return false;
            }

            var (rows, seen) = change.Value;
            config.HomeRows = rows is null ? null : HomeRowIds.Serialize(rows);
            config.HomeRowsSeen = HomeRowIds.Serialize(seen);
            plugin.SaveConfiguration();
            return true;
        }
    }
```

In `Configuration/PluginConfiguration.cs`, dopo `HomeRows`:

```csharp

    /// <summary>
    /// Le righe nate dopo la 1.7.0 già accese una volta nella Home
    /// dell'admin (spec N §6.7), separate da virgole: una riga spenta dopo
    /// dall'admin non si riaccende. Null: nessuna.
    /// </summary>
    public string? HomeRowsSeen { get; set; }
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde. Se altri test controllano `HomeRowIds.Known` (es. `HomeControllerTests` con l'elenco intero), aggiornali con `recommended` dopo `nextUp`.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recommended Home row, turned on once in the admin Home"
```

---

## Gruppo C — montaggio

### Task 6: adattatore, servizio in background, versione 1.8.0

**Files:**
- Create: `Server/JellyfinRecommendationLibrary.cs`, `RecommendationsHostedService.cs`
- Modify: `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `../meta.template.json`, `../README.md`
- Test: `JellyfinRecommendationLibraryTests.cs`, `RecommendationsHostedServiceTests.cs`, `ServiceRegistrationTests.cs`, `InfoControllerTests.cs` (modifiche)

**Interfaces:**
- Consumes: tutto dai Task 1–5.
- Produces: `JellyfinRecommendationLibrary(ILibraryManager, IUserManager, IUserDataManager)`; `RecommendationsHostedService(RecommendationService, IHomeLayoutStore, TimeProvider, ILogger<RecommendationsHostedService>)` con `CleanupInterval` (5 minuti); plugin 1.8.0 montato.

- [ ] **Step 1: i test che falliscono**

`JellyfinRecommendationLibraryTests.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinRecommendationLibraryTests
{
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly Dictionary<Guid, BaseItem> _items = [];
    private readonly Dictionary<Guid, DateTime?> _played = [];
    private readonly List<InternalItemsQuery> _queries = [];
    private BaseItem? _latestEpisode;

    private JellyfinRecommendationLibrary Library()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemById"] = args => _items.GetValueOrDefault((Guid)args[0]!);
        library.Handlers["GetItemList"] = args =>
        {
            _queries.Add((InternalItemsQuery)args[0]!);
            return _latestEpisode is null ? new List<BaseItem>() : new List<BaseItem> { _latestEpisode };
        };
        var (userManager, users) = InterfaceStub<IUserManager>.Create();
        users.Handlers["GetUserById"] = args => (Guid)args[0]! == _luigi.Id ? _luigi : null;
        var (userDataManager, userData) = InterfaceStub<IUserDataManager>.Create();
        userData.Handlers["GetUserData"] = args =>
            _played.TryGetValue(((BaseItem)args[1]!).Id, out var date) ? new UserItemData { Key = "k", LastPlayedDate = date } : null;
        return new JellyfinRecommendationLibrary(libraryManager, userManager, userDataManager);
    }

    private T Add<T>(T item)
        where T : BaseItem
    {
        _items[item.Id] = item;
        return item;
    }

    [Fact]
    public void OnlyMoviesAndSeriesCanBeRecommended()
    {
        var movie = Add(new Movie { Id = Guid.NewGuid(), Name = "Dune", ProductionYear = 2021 });
        var series = Add(new Series { Id = Guid.NewGuid(), Name = "The Bear" });
        var episode = Add(new Episode { Id = Guid.NewGuid(), Name = "Pilot" });
        var library = Library();

        Assert.Equal(("Dune", 2021), (library.GetTitle(movie.Id)!.Name, library.GetTitle(movie.Id)!.Year));
        Assert.Equal("The Bear", library.GetTitle(series.Id)!.Name);
        Assert.Null(library.GetTitle(series.Id)!.Year);
        Assert.Null(library.GetTitle(episode.Id));
        Assert.Null(library.GetTitle(Guid.NewGuid()));
        Assert.Null(library.GetTitle(Guid.Empty));
    }

    [Fact]
    public void AMovieIsWatchedWhenItsLastPlayedDateIs()
    {
        var movie = Add(new Movie { Id = Guid.NewGuid(), Name = "Dune" });
        var library = Library();
        Assert.Null(library.LastWatched(_luigi.Id, movie.Id));

        _played[movie.Id] = new DateTime(2026, 10, 12, 21, 0, 0, DateTimeKind.Unspecified);
        Assert.Equal(new DateTimeOffset(2026, 10, 12, 21, 0, 0, TimeSpan.Zero), library.LastWatched(_luigi.Id, movie.Id));

        // Utente o titolo che non ci sono.
        Assert.Null(library.LastWatched(Guid.NewGuid(), movie.Id));
        Assert.Null(library.LastWatched(_luigi.Id, Guid.NewGuid()));
        Assert.Null(library.LastWatched(Guid.Empty, Guid.Empty));
    }

    [Fact]
    public void ASeriesIsWatchedWhenItsLatestEpisodeIs()
    {
        var series = Add(new Series { Id = Guid.NewGuid(), Name = "The Bear" });
        var library = Library();
        Assert.Null(library.LastWatched(_luigi.Id, series.Id));

        _latestEpisode = new Episode { Id = Guid.NewGuid() };
        _played[_latestEpisode.Id] = new DateTime(2026, 10, 12, 22, 0, 0, DateTimeKind.Utc);
        Assert.Equal(new DateTimeOffset(2026, 10, 12, 22, 0, 0, TimeSpan.Zero), library.LastWatched(_luigi.Id, series.Id));

        // Una domanda sola: gli episodi veri della serie, dall'ultimo visto dall'utente.
        var query = _queries[^1];
        Assert.Same(_luigi, query.User);
        Assert.Equal(new[] { series.Id }, query.AncestorIds);
        Assert.Equal(new[] { BaseItemKind.Episode }, query.IncludeItemTypes);
        Assert.False(query.IsVirtualItem);
        Assert.Equal(1, query.Limit);
        Assert.Equal((ItemSortBy.DatePlayed, SortOrder.Descending), Assert.Single(query.OrderBy));
    }
}
```

(Se `UserItemData` non ha `Key` obbligatorio, togli `Key = "k"`; se `query.User` ha un altro nome nella 10.11.9, usa quello: il controllo è che la domanda sia per l'utente.)

`RecommendationsHostedServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecommendationsHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));

    public void Dispose() => _folder.Dispose();

    [Fact]
    public async Task StartTurnsOnTheLaterRowsAndTheTimerCleansUp()
    {
        var friends = TestRecommendations.Friends(_server, _folder, _time);
        var service = TestRecommendations.Create(_server, _folder, _time, friends);
        var mario = _server.AddUser("Mario");
        var luigi = _server.AddUser("Luigi");
        await TestRecommendations.MakeFriendsAsync(friends, mario.Id, luigi.Id);
        var dune = _server.AddRecommendable("Dune");
        await service.RecommendAsync(mario.Id, new RecommendRequest { ItemId = dune.Id.ToString("N"), To = [luigi.Id.ToString("N")] });
        var layout = new FakeLayout();

        using var hosted = new RecommendationsHostedService(service, layout, _time, NullLogger<RecommendationsHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        Assert.Equal(1, layout.Calls);

        _server.Users.Remove(luigi.Id);
        _time.Advance(RecommendationsHostedService.CleanupInterval);

        var saved = new RecommendationStore(_folder.RecommendationsFile, NullLogger<RecommendationStore>.Instance).Load();
        Assert.Empty(saved.List(luigi.Id));

        await hosted.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task AFailingHomeLayoutDoesNotStopTheStart()
    {
        var friends = TestRecommendations.Friends(_server, _folder, _time);
        var service = TestRecommendations.Create(_server, _folder, _time, friends);

        using var hosted = new RecommendationsHostedService(
            service, new FakeLayout { Fails = true }, _time, NullLogger<RecommendationsHostedService>.Instance);

        await hosted.StartAsync(CancellationToken.None);
        await hosted.StopAsync(CancellationToken.None);
    }

    private sealed class FakeLayout : IHomeLayoutStore
    {
        public int Calls { get; private set; }

        public bool Fails { get; init; }

        public IReadOnlyList<string>? Rows => null;

        public void Save(IReadOnlyList<string>? rows)
        {
        }

        public bool AddLaterRows()
        {
            Calls++;
            return Fails ? throw new InvalidOperationException("configurazione non salvata") : false;
        }
    }
}
```

In `ServiceRegistrationTests.AllServicesResolve`:
- dopo `services.AddSingleton(InterfaceStub<ILibraryManager>.Create().Proxy);`: `services.AddSingleton(InterfaceStub<IUserDataManager>.Create().Proxy);`;
- prima del conteggio dei servizi in background:

```csharp
        // Consigli tra amici (spec N).
        Assert.Same(provider.GetRequiredService<RecommendationService>(), provider.GetRequiredService<RecommendationService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "recommendations.json"),
            provider.GetRequiredService<RecommendationStore>().FilePath);
        Assert.IsType<Server.JellyfinRecommendationLibrary>(provider.GetRequiredService<IRecommendationLibrary>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RecommendationsController>(provider));
```

- il conteggio diventa `Assert.Equal(4, provider.GetServices<IHostedService>().Count());` con il commento "// I consigli (spec N), oltre ai tre di prima.".

In `InfoControllerTests`: versione `"1.8.0"`; nei due elenchi delle funzioni `"recommendations"` subito dopo `"home"`.

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~JellyfinRecommendationLibraryTests|FullyQualifiedName~RecommendationsHostedServiceTests|FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~InfoControllerTests"`
Expected: FAIL (tipi mancanti, versione 1.7.0, funzione mancante).

- [ ] **Step 3: il codice**

`Server/JellyfinRecommendationLibrary.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La libreria di Jellyfin per i consigli: film e serie, e l'ultima visione di un utente.</summary>
public sealed class JellyfinRecommendationLibrary(
    ILibraryManager libraryManager,
    IUserManager userManager,
    IUserDataManager userDataManager) : IRecommendationLibrary
{
    // Con un id vuoto GetItemById lancia: il titolo non c'è e basta.
    public RecommendableItem? GetTitle(Guid itemId) =>
        itemId != Guid.Empty && libraryManager.GetItemById(itemId) is { } item && item is Movie or Series
            ? new RecommendableItem(item.Id, item.Name ?? string.Empty, item.ProductionYear)
            : null;

    public DateTimeOffset? LastWatched(Guid userId, Guid itemId)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        var item = itemId == Guid.Empty ? null : libraryManager.GetItemById(itemId);
        if (user is null || item is null)
        {
            return null;
        }

        if (item is Series)
        {
            // Una domanda sola al database (piano 20a, decisione 7): l'episodio
            // vero della serie visto per ultimo da questo utente. DatePlayed
            // ordina per LastPlayedDate dell'utente della query; gli episodi
            // mai visti (null) vanno in fondo.
            item = libraryManager.GetItemList(new InternalItemsQuery(user)
            {
                AncestorIds = [item.Id],
                IncludeItemTypes = [BaseItemKind.Episode],
                IsVirtualItem = false,
                OrderBy = [(ItemSortBy.DatePlayed, SortOrder.Descending)],
                Limit = 1,
            }).FirstOrDefault();
            if (item is null)
            {
                return null;
            }
        }

        // Jellyfin salva le date in UTC, a volte senza dirlo (Kind Unspecified).
        var played = userDataManager.GetUserData(user, item)?.LastPlayedDate;
        return played is { } date ? new DateTimeOffset(DateTime.SpecifyKind(date, DateTimeKind.Utc)) : null;
    }
}
```

`RecommendationsHostedService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// I consigli tra amici in background (spec N, piano 20a decisione 1):
/// all'avvio legge recommendations.json e accende una volta sola la riga
/// "Consigliati per te" nella Home dell'admin già salvata; ogni
/// <see cref="CleanupInterval"/> pulisce i consigli che non valgono più.
/// </summary>
public sealed class RecommendationsHostedService(
    RecommendationService recommendations,
    IHomeLayoutStore layout,
    TimeProvider time,
    ILogger<RecommendationsHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si puliscono i consigli (come le notifiche).</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            recommendations.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Consigli non caricati all'avvio");
        }

        // A parte: un errore della configurazione non ferma i consigli.
        try
        {
            if (layout.AddLaterRows())
            {
                logger.LogInformation("Home dell'admin: accese le righe nuove");
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Home dell'admin: righe nuove non accese");
        }

        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    private void Cleanup()
    {
        try
        {
            var removed = recommendations.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolti {Count} consigli che non valgono più", removed);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dei consigli non riuscita");
        }
    }
}
```

In `PluginServiceRegistrator.cs`, dopo `serviceCollection.AddSingleton<ILibraryTitles, JellyfinLibraryTitles>();`:

```csharp
        // Consigli tra amici (spec N).
        serviceCollection.AddSingleton(provider => new RecommendationStore(
            RecommendationStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<RecommendationStore>>()));
        serviceCollection.AddSingleton<IRecommendationLibrary, JellyfinRecommendationLibrary>();
        serviceCollection.AddSingleton<RecommendationService>();
```

e in fondo, dopo `ContactReminderHostedService`: `serviceCollection.AddHostedService<RecommendationsHostedService>();`.

In `Protocol/WatchPartyProtocol.cs`: nel commento di `Features` aggiungi "spec N §6.6"; l'elenco diventa
`["friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home", "recommendations"];`.

Nel csproj: `<Version>1.8.0</Version>`.

In `Plugin.cs`: nel commento della classe aggiungi "e, dalla 1.8.0, i consigli tra amici (spec N)"; `Description` diventa:

```csharp
    public override string Description =>
        "Names, chat, reactions, friends, notifications, recommendations between friends, password recovery and the Home rows (upcoming from Sonarr and Radarr) for WonderFlix.";
```

In `../meta.template.json`:
- `description`: dopo "an in-app notifications inbox (invites, new titles, admin announcements, requests)" aggiungi ", recommendations between friends";
- `overview`: dopo "notifications" aggiungi ", recommendations".

In `../README.md`:
- nell'introduzione, dopo la frase della 1.7.0: "Dalla 1.8.0 tiene i consigli tra amici: un utente consiglia un film o una serie ai suoi amici, che lo trovano nella cassetta e nella riga \"Consigliati per te\" della Home (spec N, `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md`).";
- un punto nuovo dopo "Home (dalla 1.7.0)":

```markdown
- **Consigli (dalla 1.8.0):** `GET Recommendations/Targets?itemId=` dà gli
  amici attivi con online e accesso al titolo; `POST Recommendations`
  `{ItemId, To, Message}` consiglia un film o una serie (messaggio fino a 200
  caratteri, fino a 50 amici, 30 destinatari all'ora; chi non è amico o non
  vede il titolo si salta) e crea la voce `Recommendation` nella cassetta;
  `GET Recommendations` dà i consigli ricevuti ancora validi (escono quelli
  visti dopo il consiglio, quelli che l'utente non vede più, quelli di chi
  non è più amico e quelli di più di 60 giorni); `DELETE
  Recommendations/{itemId}` è "Non mi interessa". I dati stanno in
  `recommendations.json`, accanto a `inbox.json`. All'avvio la riga
  `recommended` si accende una volta sola nella Home dell'admin già salvata
  (`HomeRowsSeen`).
```

- nel punto "Funzioni": "…dalla 1.7.0 anche `home`, dalla 1.8.0 anche `recommendations`…"; e "Quelli di `Recommendations` hanno la stessa policy degli amici.";
- in "Installazione a mano": `pack.sh 1.8.0` e `WonderFlix Watch Party_1.8.0.0/`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde. Se `PluginPagesTests` controlla la `Description` del plugin, aggiornalo.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recommendations wiring and plugin 1.8.0"
```

---

## Gruppo D — server e chiusura

### Task 7: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo C si ferma qui. L'orchestratore fa prima la review finale del branch e i ritocchi, poi questi passi (un solo riavvio di Jellyfin, con il codice già rivisto). Sul server WonderFlix lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando. Gli script vanno scritti in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`). **Nessuno script stampa chiavi o token.**

1. **Riferimenti della dll:** controllo dei riferimenti della dll di Release contro gli assembly di Jellyfin 10.11.9 (come per le versioni passate): nessun membro non risolto.
2. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.8.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.8.0.0/`.
3. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix": base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - `mkdir -p ~/wfwp-backup`; sposta `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.7.0.0` in `~/wfwp-backup/1.7.0.0-catalogo`; copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.7.0-prima-20a.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.8.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log di oggi `Loaded plugin: "WonderFlix Watch Party" "1.8.0.0"`, `Consigli in "/config/data/plugins/configurations/WonderFlixWatchParty/recommendations.json"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.8.0.0, rimetti `~/wfwp-backup/1.7.0.0-catalogo` e la configurazione salvata, riavvia, e segnalalo.
4. **Controlli** (stessa base e intestazione; risposte riassunte con `python3`, mai stampate intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.8.0`; funzioni con `recommendations`, e ancora `home`, `requests`, `account`;
   - `GET /WonderFlixWatchParty/Recommendations` con la sola chiave API: risponde **non 404** (la chiave non ha un utente, la policy degli amici la respinge: 401 o 403); il percorso esiste;
   - nella configurazione `<HomeRowsSeen>recommended</HomeRowsSeen>` e `HomeRows` com'era (oggi non impostata: assente o vuota come prima); `SeerrUrl`, `SonarrUrl`, `ContactReminderDays` ancora al loro posto;
   - nel log nessun `Warning` del plugin dopo l'avvio.
   - Il giro completo (consiglio, riga, cassetta, visione) si prova con l'app nel piano 20b.
5. **Riporta all'utente** l'esito in breve: versione, funzioni, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 20b). L'app 0.13.0 non usa le funzioni nuove e scarta le voci `Recommendation` (non ce ne saranno finché nessuno consiglia).

### Task 8: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md`
- Modify: `docs/superpowers/plans/2026-10-12-wonderflix-20a-consigli-plugin.md` (solo una voce "Dalle review dei gruppi" nelle decisioni, se ci sono differenze)

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvata il 2026-10-12; piano 20a realizzato (`docs/superpowers/plans/2026-10-12-wonderflix-20a-consigli-plugin.md`), build di prova sul server; piano 20b da scrivere".
- **§6.2:** `Targets` dà gli amici attivi, per nome (decisione 9); il messaggio: a capo → spazi, righe vuote tolte, lunghezza in punti di codice (decisione 6); 429 tutto o niente (decisione 5).
- **§6.3:** la pulizia periodica sta in `RecommendationsHostedService` e controlla mittenti, 60 giorni e destinatari cancellati; permessi e visto solo in `GET` (decisioni 1 e 2); rimozione condizionata e titolo tenuto su errore della libreria (decisioni 3 e 4); "visto" con `LastPlayedDate` e la domanda per serie (decisione 7); `MarkPlayed` senza data tiene la data che c'era.
- **§6.7:** `HomeRowIds.AddedLater`, `HomeRowsSeen`; con `HomeRows` null si segna vista e basta (decisione 8).
- **§12:** i primi due punti verificati sul sorgente di Jellyfin 10.11.9 (decisione 7); il terzo resta per il 20b.
- **§13:** 20a realizzato; il plugin 1.8.0 resta build di prova fino alla fine del 20b.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze.

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the recommendations spec with plan 20a"
```

### Task 9: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 7: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente tag e niente manifest: il plugin 1.8.0 si pubblica alla fine del 20b, insieme all'app 0.14.0.
