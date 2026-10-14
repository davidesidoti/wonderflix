# WonderFlix — Piano 22a: match del film, plugin 1.10.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec P nel plugin 1.10.0:
- la sala del match in memoria: apertura, inviti (avviso e voce nella cassetta), ingresso, uscita, "Inizia";
- la pila: 30 titoli a caso con i filtri, non visti né iniziati da nessun membro e visibili a tutti; "Altri 30";
- i voti in ordine, i match, i quasi match;
- l'avvio del party: accesso ai membri e sala chiusa con `PartyGroupId`;
- lo stato mandato ai membri con `MatchUpdated`, raggruppato ogni 250 ms;
- la pulizia (membri senza sessione da 60 s, chi ha aperto che esce, 1 h senza attività, sale chiuse tenute 5 minuti);
- la funzione `match` in `Info`, versione 1.10.0;
- una build di prova sul server.

L'app arriva nei piani 22b e 22c.

**Architecture:** la logica sta in `Hub/` e non conosce Jellyfin:
- `MatchFilters` (filtri della pila) e `MatchRoom` (una sala: membri, inviti, pila, voti, match, quasi match, stato; puro, senza lock);
- `MatchStackBuilder` (la pila: candidati a caso da `IMatchLibrary`, poi filtri, `CanSee` e `LastWatched` per ogni membro);
- `MatchService` (le regole degli endpoint, il lock, le pescate fuori dal lock, gli inviti, gli avvisi raggruppati, la pulizia).

L'adattatore Jellyfin `Server/JellyfinMatchLibrary` fa solo la query a caso sulla libreria di chi ha aperto. `MatchController` espone gli endpoint; `MatchHostedService` pulisce ogni 30 s.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md` (§3, §5, §6, §8, §10, §11.1, §12, §13).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 10):
1. **Chi chiama si ricava dal token** (utente), come `ActivityController`: la sala è per utente, non serve la sessione. Il nome viene da `IUserDirectory`.
2. **I filtri** arrivano con i valori dell'app (`Type` `movies`/`series`/`both`, `Duration` `any`/`90`/`120`, `Genre`); `Type` e `Duration` mancanti valgono `both` e `any`; un valore sconosciuto o un genere oltre 100 caratteri → 400.
3. **Pescata fuori dal lock.** `Start` e `More` mettono la sala in `Drawing`, pescano senza tenere il lock (la libreria fa query al database) e poi riprendono il lock. Mentre pesca: `Join` → `Started`, un secondo `Start` → `Started`, `More` → `NotFinished`, nessun avviso. Se intanto la sala si chiude, la pescata si butta e la risposta è `Closed`.
4. **Sala sconosciuta:** `Closed` per `Join`, `Invites`, `Start`, `Votes`, `More`, `Party`; `NotMember` per `GET`; `Leave` risponde 204 sempre.
5. **Rientro:** `Join` di chi è già membro risponde con lo stato, senza cambi (doppio clic, riconnessione).
6. **`Rev`** cresce solo con un cambio visibile nello stato: un `More` che non trova niente non lo cambia.
7. **Inviti:** solo amici attivi di chi ha aperto, non già membri; il limite `Invites` (20 al minuto) conta ogni destinatario come per i party: oltre il limite si invitano quelli che ci stanno e si risponde 429. Ogni invitato riceve `MatchInvite` sulle sue sessioni WonderFlix e la voce `MatchInvite` nella cassetta (una per sala: un nuovo invito la rimette in cima, non letta).
8. **La pila:** `IMatchLibrary.Candidates` fa solo la query (tipo, genere, non visti da chi ha aperto, a caso, fino a 300, senza i titoli esclusi). Tipo, durata, esclusi e doppioni si ricontrollano in `MatchStackBuilder`, che poi controlla `CanSee` e `LastWatched` di ogni membro, compreso chi ha aperto, fermandosi al primo che non passa.
9. **Avvisi:** lo stato si calcola sotto il lock e si manda fuori. Al più un `MatchUpdated` ogni 250 ms per sala; il primo dopo una pausa parte subito, gli altri aspettano e partono con l'ultimo stato. `Party` manda subito.
10. **Limite dei voti** per utente (`LimitTypes.MatchVotes`, 4 al secondo), controllato prima del lock.
11. **Verifiche su Jellyfin 10.11.9** (§12 della spec): vedi "Note tecniche verificate"; le differenze dalla spec si allineano nel Task 10.

## Global Constraints

- Plugin **1.10.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9. Ogni proprietà di `InternalItemsQuery` usata deve esistere nella 10.11.0.
- Endpoint sotto `/WonderFlixWatchParty`, con `[Authorize(Policy = Policies.SyncPlayHasAccess)]` come gli amici:
  - `POST Match`, `GET Match/{roomId}`;
  - `POST Match/{roomId}/Invites`, `/Join`, `/Leave`, `/Start`, `/Votes`, `/More`, `/Party`.
- **Mai 404:** `roomId` è una stringa senza vincoli di rotta; un id non valido → 400. I 409 hanno il corpo `{"Reason": "…"}` con i motivi di `MatchReasons`.
- Valori: 30 titoli per pila (`MatchStackBuilder.StackSize`), 300 candidati (`CandidateLimit`), 8 membri (`MatchRoom.MaxMembers`), 2 per iniziare (`MinMembers`), 5 quasi match (`MaxNearMatches`), soglia dei quasi match `ceil(membri / 2)`; 60 s senza sessione (`MatchService.MemberGrace`), 1 h senza attività (`InactiveAfter`), sale chiuse tenute 5 minuti (`ClosedKept`), avvisi ogni 250 ms (`PushInterval`), pulizia ogni 30 s (`MatchHostedService.CleanupInterval`); voti 4 al secondo per utente.
- Stato (`MatchStateDto`): `RoomId`, `Rev`, `Phase`, `CreatorId`, `CreatorName`, `Members` (`UserId`, `Name`, `Voted`), `Stack`, `Matches`, `NearMatches` (`ItemId`, `Yes`, `Of`), `ClosedReason` e `PartyGroupId` solo se ci sono. **Mai i voti dei singoli.**
- Avvisi nuovi: `{"Protocol":1,"Type":"MatchInvite","FromName":…,"RoomId":…}` e `{"Protocol":1,"Type":"MatchUpdated","State":{…}}`; voce di cassetta `Type` `MatchInvite` con `RoomId` e `FromName`.
- `Info`: `Version` "1.10.0", `Protocol` 1, `Features` con `"match"` dopo `"friendsActivity"`.
- Id di Jellyfin e delle sale in formato `"N"`.
- Log: **mai titoli o nomi**; solo id e numeri.

## Review Focus

1. **I voti dei singoli non escono mai:** né nelle risposte né in `MatchUpdated`, neanche a fine pila (i quasi match hanno solo i conteggi). Test: Task 1 (`TheSnapshotNeverHasTheVotes`), Task 5 (`UpdatesCarryCountsNotVotes`).
2. **Un membro esce durante la votazione:** i suoi no non bloccano più i match, e un titolo può diventare match in quel momento; se esce chi ha aperto, la sala si chiude per tutti. Test: Task 1 (`AMemberLeavingCanMakeAMatch`), Task 4 (`TheCreatorLeavingClosesTheRoom`).
3. **Un titolo che un membro non può vedere o ha già visto o iniziato** non entra mai nella pila, anche se è chi ha aperto ad averlo iniziato. Test: Task 2 (`OnlyTitlesEveryMemberCanSeeAndNeverWatched`).
4. **Una caduta della connessione** non fa uscire subito: un membro esce solo dopo 60 s senza sessioni WonderFlix, e chi si riconnette resta dentro. Test: Task 5 (`AMemberWithoutSessionsLeavesAfterTheGrace`).
5. **Un errore della libreria** (query o controllo di un candidato) non dà mai un 500: la pila viene vuota o senza quel candidato. Test: Task 2 (`LibraryErrorsGiveAShorterOrEmptyStack`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-22a`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(plugin): …"`.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.10.0`.
- **Test:**
  - un solo gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj del plugin ha `TreatWarningsAsErrors`: un warning è un errore), poi `dotnet build-server shutdown`;
  - la base di partenza è di **910** test verdi (verificato il 2026-10-14 su `main` `332ad61`).
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

Verificate il 2026-10-14 sul codice di `main` (`332ad61`) e sul sorgente di Jellyfin 10.11.9.

**Plugin** (`main`)
- `PartyService.InviteAsync` è il modello degli inviti: amici (`FriendService.AreFriends`), utenti attivi (`IUserDirectory.GetUser` → `UserRef.Enabled`), limite `LimitTypes.Invites` con `RateLimiter.TryAcquire(callerId "N", type)` per ogni destinatario, avviso con `IEventSender.TrySendAsync(sessionId, payload, CancellationToken.None)` alle sessioni di `ISessionDirectory.GetAppSessions()`, voce nella cassetta.
- `PartyDirectory.Get(groupId)` → `PartyView(GroupId, CreatorId, Mode, Code)` o null; `Grant(groupId, users)` dà a quegli utenti la visibilità del party (`IsVisible` → true per gli invitati).
- `InboxService`: le voci si aggiungono sotto `_lock` con un metodo di `InboxBook`, poi `Persist()` e `NotifyAsync(userIds)` (avviso `InboxChanged`); i metodi pubblici non lanciano (`catch` con `Warning`). `InboxBook.UpsertInvite` è il modello di una voce unica per chiave.
- `SocialEvent`: classe con proprietà facoltative (`JsonIgnore WhenWritingNull`) e metodi statici di costruzione; `ProtocolJsonTests` ne controlla il JSON esatto.
- `HubStatus` (`Ok`, `Forbidden`, `Invalid`, `RateLimited`, `Conflict`) sta in `Hub/PartyHub.cs`. Gli errori con corpo si fanno con `new ObjectResult(dto) { StatusCode = … }` (`AccountErrors`, `RequestsController`).
- `ActivityController.CallerAsync()`: `(await authorizationContext.GetAuthorizationInfo(HttpContext)).UserId`.
- `PresenceTracker` è il modello dei timer: `time.CreateTimer(callback, null, delay, Timeout.InfiniteTimeSpan)`, sotto lock, `Dispose` dei timer.
- `ServiceRegistrationTests.AllServicesResolve` conta **5** servizi in background.
- `InfoControllerTests` controlla `"1.9.0"` e i due elenchi di funzioni.

**Jellyfin 10.11.9** (sorgente `jellyfin/jellyfin` al tag `v10.11.9`, confrontato con `v10.11.0`): vedi "Verifiche su Jellyfin 10.11.9" nel Task 7 (query della libreria, `IsPlayed` per tipo, `LastPlayedDate` all'inizio della riproduzione, ingresso in SyncPlay, ordine degli episodi).

**Test**
- `FakeServer` implementa `ISessionDirectory`, `IUserDirectory`, `ILibraryAccess` (`Unseen`, `LibraryFails`), `IRecommendationLibrary` (`Watched`), `IEventSender` (`Sent`, `SentTo(sessionId)`, `Failing`). `AddUser(name, enabled: …)`, `AddSession(id, user)`.
- `TestRecommendations.Friends(server, folder, time)` e `MakeFriendsAsync(friends, a, b)`; `TestInbox.Create(server, folder, time)`; `TempFolder`; `InterfaceStub<T>` (`Handlers["GetItemList"]`); `FakeAuthorizationContext(AuthorizationInfo)`; `FakeTimeProvider` (`Advance`).
- Utenti di Jellyfin nei test dei controller: `new User("mario", "provider", "reset")` e la stessa id in `FakeServer.Users`.

## File

| File | Responsabilità |
|---|---|
| `Protocol/MatchDtos.cs` | fasi, motivi, stato, corpi delle richieste, errore |
| `Hub/MatchFilters.cs` | filtri della pila e loro lettura |
| `Hub/MatchRoom.cs` | una sala: membri, inviti, pila, voti, match, quasi match, assenze, stato |
| `Hub/IMatchLibrary.cs` | `MatchCandidate` e l'interfaccia della query a caso |
| `Hub/MatchStackBuilder.cs` | la pila: candidati, filtri, `CanSee`, `LastWatched` |
| `Hub/MatchService.cs` | regole degli endpoint, lock, pescate, inviti, avvisi, pulizia |
| `Protocol/SocialEvent.cs`, `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs`, `Hub/LimitTypes.cs`, `Hub/RateLimiter.cs` (modifiche) | avvisi `MatchInvite`/`MatchUpdated`, voce `MatchInvite`, limite dei voti |
| `Api/MatchController.cs` | endpoint |
| `Server/JellyfinMatchLibrary.cs` | la query a caso su Jellyfin |
| `MatchHostedService.cs` | pulizia ogni 30 s |
| `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `Plugin.cs`, `../meta.template.json`, `../README.md` (modifiche) | montaggio, versione, documentazione |

Tutti i percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test, scritti `Tests/…`), se non è detto altro.

---

## Gruppo A — sala e regole

### Task 1: `MatchDtos`, `MatchFilters`, `MatchRoom`

**Files:**
- Create: `Protocol/MatchDtos.cs`, `Hub/MatchFilters.cs`, `Hub/MatchRoom.cs`
- Test: `Tests/MatchFiltersTests.cs`, `Tests/MatchRoomTests.cs`

**Interfaces:**
- Produces:
  - `MatchPhases` (`Waiting`, `Voting`, `Closed`), `MatchClosedReasons` (`CreatorLeft`, `Inactive`, `PartyStarted`), `MatchReasons` (`InAnotherRoom`, `NotMember`, `NotCreator`, `Started`, `Closed`, `Full`, `NotInvited`, `NotEnoughMembers`, `NotStarted`, `NotNext`, `NotFinished`, `NotYourParty`);
  - `record MatchMemberDto(string UserId, string Name, int Voted)`, `record MatchNearMatchDto(string ItemId, int Yes, int Of)`, `record MatchStateDto(string RoomId, long Rev, string Phase, string CreatorId, string CreatorName, IReadOnlyList<MatchMemberDto> Members, IReadOnlyList<string> Stack, IReadOnlyList<string> Matches, IReadOnlyList<MatchNearMatchDto> NearMatches, string? ClosedReason, string? PartyGroupId)`, `record MatchErrorDto(string Reason)`;
  - corpi: `MatchStartRequest { Type, Duration, Genre }`, `MatchVoteRequest { ItemId, Yes }`, `MatchPartyRequest { GroupId }` (gli inviti usano `InviteRequest` dei party);
  - `record MatchFilters(bool Movies, bool Series, TimeSpan? MaxRuntime, string? Genre)` con `MaxGenreLength = 100` e `static MatchFilters? Parse(string? type, string? duration, string? genre)`;
  - `MatchRoom(Guid id, Guid creatorId, string creatorName, DateTimeOffset now)` con `MaxMembers = 8`, `MinMembers = 2`, `MaxNearMatches = 5`; proprietà `Id`, `CreatorId`, `CreatorName`, `Phase`, `Rev`, `Drawing` (`get; set;`), `Filters`, `LastActivityAt`, `ClosedAt`, `ClosedReason`, `PartyGroupId`, `IsOpen`, `MemberIds`, `MemberCount`, `Shown`, `AllFinished`; metodi `bool IsMember(Guid)`, `void Invite(Guid)`, `string? Join(Guid, string, DateTimeOffset)`, `bool Remove(Guid)`, `void Start(MatchFilters, IReadOnlyList<Guid>, DateTimeOffset)`, `bool AddToStack(IReadOnlyList<Guid>, DateTimeOffset)`, `string? Vote(Guid, Guid, bool, DateTimeOffset)`, `void Close(string, Guid?, DateTimeOffset)`, `IReadOnlyList<Guid> Absent(IReadOnlySet<Guid>, DateTimeOffset, TimeSpan)`, `MatchStateDto Snapshot()`.

- [ ] **Step 1: test che falliscono**

`Tests/MatchFiltersTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class MatchFiltersTests
{
    [Fact]
    public void TheAppValuesBecomeFilters()
    {
        Assert.Equal(new MatchFilters(true, false, TimeSpan.FromMinutes(90), "Horror"), MatchFilters.Parse("movies", "90", " Horror "));
        Assert.Equal(new MatchFilters(false, true, TimeSpan.FromMinutes(120), null), MatchFilters.Parse("series", "120", ""));
        Assert.Equal(new MatchFilters(true, true, null, null), MatchFilters.Parse("both", "any", null));
    }

    [Fact]
    public void MissingTypeAndDurationAreBothAndAny()
    {
        Assert.Equal(new MatchFilters(true, true, null, null), MatchFilters.Parse(null, null, "  "));
    }

    [Fact]
    public void UnknownValuesAreRefused()
    {
        Assert.Null(MatchFilters.Parse("films", "any", null));
        Assert.Null(MatchFilters.Parse("both", "60", null));
        Assert.Null(MatchFilters.Parse("both", "any", new string('a', MatchFilters.MaxGenreLength + 1)));
        Assert.NotNull(MatchFilters.Parse("both", "any", new string('a', MatchFilters.MaxGenreLength)));
    }
}
```

`Tests/MatchRoomTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class MatchRoomTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 14, 20, 0, 0, TimeSpan.Zero);
    private static readonly MatchFilters AnyTitle = new(true, true, null, null);

    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _peach = Guid.NewGuid();
    private readonly Guid _daisy = Guid.NewGuid();
    private readonly Guid _dune = Guid.NewGuid();
    private readonly Guid _alien = Guid.NewGuid();
    private readonly Guid _heat = Guid.NewGuid();

    private MatchRoom Room(params Guid[] guests)
    {
        var room = new MatchRoom(Guid.NewGuid(), _mario, "Mario", Now);
        foreach (var guest in guests)
        {
            room.Invite(guest);
            Assert.Null(room.Join(guest, guest == _luigi ? "Luigi" : "Ospite", Now));
        }

        return room;
    }

    private MatchRoom Voting(params Guid[] guests)
    {
        var room = Room(guests);
        room.Start(AnyTitle, [_dune, _alien, _heat], Now);
        return room;
    }

    private static IReadOnlyList<string> Ids(params Guid[] ids) => ids.Select(id => id.ToString("N")).ToList();

    [Fact]
    public void ARoomStartsWaitingWithTheCreator()
    {
        var room = Room();
        var state = room.Snapshot();

        Assert.Equal(MatchPhases.Waiting, state.Phase);
        Assert.Equal(_mario.ToString("N"), state.CreatorId);
        Assert.Equal("Mario", state.CreatorName);
        Assert.Equal(new MatchMemberDto(_mario.ToString("N"), "Mario", 0), Assert.Single(state.Members));
        Assert.Empty(state.Stack);
        Assert.Null(state.ClosedReason);
        Assert.True(room.IsOpen);
    }

    [Fact]
    public void OnlyInvitedUsersJoinWhileWaitingUpToEight()
    {
        var room = Room();
        Assert.Equal(MatchReasons.NotInvited, room.Join(_luigi, "Luigi", Now));

        room.Invite(_luigi);
        var rev = room.Rev;
        Assert.Null(room.Join(_luigi, "Luigi", Now));
        Assert.True(room.Rev > rev);

        // Di nuovo: già dentro, niente cambia.
        rev = room.Rev;
        Assert.Null(room.Join(_luigi, "Luigi", Now));
        Assert.Equal(rev, room.Rev);

        for (var i = room.MemberCount; i < MatchRoom.MaxMembers; i++)
        {
            var guest = Guid.NewGuid();
            room.Invite(guest);
            Assert.Null(room.Join(guest, "Ospite", Now));
        }

        room.Invite(_peach);
        Assert.Equal(MatchReasons.Full, room.Join(_peach, "Peach", Now));
    }

    [Fact]
    public void NobodyJoinsAfterTheStartOrWhileDrawing()
    {
        var drawing = Room();
        drawing.Invite(_luigi);
        drawing.Drawing = true;
        Assert.Equal(MatchReasons.Started, drawing.Join(_luigi, "Luigi", Now));

        var voting = Voting();
        voting.Invite(_luigi);
        Assert.Equal(MatchReasons.Started, voting.Join(_luigi, "Luigi", Now));

        voting.Close(MatchClosedReasons.Inactive, null, Now);
        Assert.Equal(MatchReasons.Closed, voting.Join(_luigi, "Luigi", Now));
    }

    [Fact]
    public void VotesGoInOrder()
    {
        var room = Voting(_luigi);

        Assert.Equal(MatchReasons.NotNext, room.Vote(_mario, _alien, true, Now));
        Assert.Null(room.Vote(_mario, _dune, true, Now));
        Assert.Equal(MatchReasons.NotNext, room.Vote(_mario, _dune, false, Now));
        Assert.Null(room.Vote(_mario, _alien, false, Now));
        Assert.Equal(MatchReasons.NotMember, room.Vote(_peach, _dune, true, Now));

        var members = room.Snapshot().Members;
        Assert.Equal(2, members[0].Voted);
        Assert.Equal(0, members[1].Voted);
    }

    [Fact]
    public void NoVotesBeforeTheStartOrAfterTheEnd()
    {
        var waiting = Room(_luigi);
        Assert.Equal(MatchReasons.NotStarted, waiting.Vote(_mario, _dune, true, Now));

        var room = Voting(_luigi);
        foreach (var item in new[] { _dune, _alien, _heat })
        {
            Assert.Null(room.Vote(_mario, item, true, Now));
        }

        Assert.Equal(MatchReasons.NotNext, room.Vote(_mario, _dune, true, Now));

        room.Close(MatchClosedReasons.Inactive, null, Now);
        Assert.Equal(MatchReasons.Closed, room.Vote(_luigi, _dune, true, Now));
    }

    [Fact]
    public void AMatchIsATitleEveryoneLikes()
    {
        var room = Voting(_luigi);
        room.Vote(_mario, _dune, true, Now);
        room.Vote(_mario, _alien, true, Now);
        Assert.Empty(room.Snapshot().Matches);

        room.Vote(_luigi, _dune, false, Now);
        room.Vote(_luigi, _alien, true, Now);

        Assert.Equal(Ids(_alien), room.Snapshot().Matches);
    }

    [Fact]
    public void MatchesKeepTheOrderTheyCameOut()
    {
        var room = Voting(_luigi);
        room.Vote(_luigi, _dune, true, Now);
        room.Vote(_luigi, _alien, true, Now);
        room.Vote(_mario, _dune, true, Now);
        room.Vote(_mario, _alien, true, Now);

        Assert.Equal(Ids(_dune, _alien), room.Snapshot().Matches);
    }

    [Fact]
    public void AMemberLeavingCanMakeAMatch()
    {
        var room = Voting(_luigi, _peach);
        room.Vote(_mario, _dune, true, Now);
        room.Vote(_luigi, _dune, true, Now);
        room.Vote(_peach, _dune, false, Now);
        Assert.Empty(room.Snapshot().Matches);

        var rev = room.Rev;
        Assert.True(room.Remove(_peach));

        Assert.True(room.Rev > rev);
        Assert.Equal(Ids(_dune), room.Snapshot().Matches);
        Assert.False(room.IsMember(_peach));
        Assert.False(room.Remove(_peach));
    }

    [Fact]
    public void TheCreatorIsNotRemovedLikeTheOthers()
    {
        var room = Voting(_luigi);
        Assert.False(room.Remove(_mario));
        Assert.True(room.IsMember(_mario));
    }

    [Fact]
    public void AloneEveryYesIsAMatch()
    {
        var room = Voting(_luigi);
        room.Vote(_mario, _dune, true, Now);
        room.Remove(_luigi);

        Assert.Equal(Ids(_dune), room.Snapshot().Matches);
    }

    [Fact]
    public void NearMatchesComeOnlyWhenEveryoneHasFinished()
    {
        var room = Voting(_luigi, _peach);
        // Dune: 2 sì su 3; Alien: 1 su 3; Heat: 3 su 3 (match).
        Vote(room, _mario, true, true, true);
        Vote(room, _luigi, true, false, true);
        Assert.Empty(room.Snapshot().NearMatches);
        Assert.False(room.AllFinished);

        Vote(room, _peach, false, false, true);

        Assert.True(room.AllFinished);
        var state = room.Snapshot();
        Assert.Equal(Ids(_heat), state.Matches);
        Assert.Equal(new MatchNearMatchDto(_dune.ToString("N"), 2, 3), Assert.Single(state.NearMatches));
    }

    [Fact]
    public void NearMatchesGoFromTheMostLikedUpToFive()
    {
        var room = Room(_luigi);
        var stack = Enumerable.Range(0, 7).Select(_ => Guid.NewGuid()).ToList();
        room.Start(AnyTitle, stack, Now);
        // Su 2 membri la soglia è 1 sì: mario dice sì a tutti, luigi a nessuno.
        foreach (var item in stack)
        {
            room.Vote(_mario, item, true, Now);
            room.Vote(_luigi, item, false, Now);
        }

        var near = room.Snapshot().NearMatches;
        Assert.Equal(MatchRoom.MaxNearMatches, near.Count);
        Assert.Equal(stack.Take(5).Select(id => id.ToString("N")), near.Select(n => n.ItemId));
        Assert.All(near, n => Assert.Equal((1, 2), (n.Yes, n.Of)));
    }

    [Fact]
    public void TheMoreLikedComeFirstAmongNearMatches()
    {
        var room = Voting(_luigi, _peach, _daisy);
        // Quattro membri, soglia 2: Dune 2 sì, Alien 3 sì, Heat 1 sì.
        Vote(room, _mario, true, true, false);
        Vote(room, _luigi, true, true, false);
        Vote(room, _peach, false, true, true);
        Vote(room, _daisy, false, false, false);

        Assert.Equal(
            new[] { new MatchNearMatchDto(_alien.ToString("N"), 3, 4), new MatchNearMatchDto(_dune.ToString("N"), 2, 4) },
            room.Snapshot().NearMatches);
    }

    [Fact]
    public void MoreTitlesNeverRepeatOnes()
    {
        var room = Voting();
        var rev = room.Rev;

        Assert.False(room.AddToStack([_dune, _alien], Now));
        Assert.Equal(rev, room.Rev);

        var extra = Guid.NewGuid();
        Assert.True(room.AddToStack([_heat, extra], Now));
        Assert.Equal(Ids(_dune, _alien, _heat, extra), room.Snapshot().Stack);
        Assert.Contains(extra, room.Shown);
        Assert.True(room.Rev > rev);
    }

    [Fact]
    public void AnEmptyStackIsFinishedWithNoNearMatches()
    {
        var room = Room(_luigi);
        room.Start(AnyTitle, [], Now);

        Assert.True(room.AllFinished);
        Assert.Empty(room.Snapshot().NearMatches);
        Assert.Equal(AnyTitle, room.Filters);
    }

    [Fact]
    public void ClosingKeepsTheMembersAndTheParty()
    {
        var room = Voting(_luigi);
        var party = Guid.NewGuid();
        room.Close(MatchClosedReasons.PartyStarted, party, Now.AddMinutes(1));

        var state = room.Snapshot();
        Assert.Equal(MatchPhases.Closed, state.Phase);
        Assert.Equal(MatchClosedReasons.PartyStarted, state.ClosedReason);
        Assert.Equal(party.ToString("N"), state.PartyGroupId);
        Assert.Equal(2, state.Members.Count);
        Assert.Equal(Now.AddMinutes(1), room.ClosedAt);
        Assert.False(room.IsOpen);

        // Una seconda chiusura non cambia niente.
        var rev = room.Rev;
        room.Close(MatchClosedReasons.Inactive, null, Now.AddMinutes(2));
        Assert.Equal(rev, room.Rev);
        Assert.Equal(MatchClosedReasons.PartyStarted, room.ClosedReason);
    }

    [Fact]
    public void AbsentMembersCountFromWhenTheyLostTheirSessions()
    {
        var room = Voting(_luigi);
        var grace = TimeSpan.FromSeconds(60);

        Assert.Empty(room.Absent(new HashSet<Guid> { _mario }, Now, grace));
        Assert.Empty(room.Absent(new HashSet<Guid> { _mario }, Now.AddSeconds(59), grace));
        Assert.Equal(new[] { _luigi }, room.Absent(new HashSet<Guid> { _mario }, Now.AddSeconds(60), grace));

        // Riconnesso: si riparte da capo.
        Assert.Empty(room.Absent(new HashSet<Guid> { _mario, _luigi }, Now.AddSeconds(61), grace));
        Assert.Empty(room.Absent(new HashSet<Guid> { _mario }, Now.AddSeconds(100), grace));
    }

    [Fact]
    public void TheSnapshotNeverHasTheVotes()
    {
        var room = Voting(_luigi);
        Vote(room, _mario, true, false, true);
        Vote(room, _luigi, false, false, true);

        var json = JsonSerializer.Serialize(room.Snapshot());

        Assert.DoesNotContain("Yes\":true", json, StringComparison.Ordinal);
        Assert.DoesNotContain("Votes", json, StringComparison.Ordinal);
        Assert.Equal(
            "{\"RoomId\":\"" + room.Id.ToString("N") + "\",\"Rev\":" + room.Rev + ",\"Phase\":\"Voting\","
            + "\"CreatorId\":\"" + _mario.ToString("N") + "\",\"CreatorName\":\"Mario\","
            + "\"Members\":[{\"UserId\":\"" + _mario.ToString("N") + "\",\"Name\":\"Mario\",\"Voted\":3},"
            + "{\"UserId\":\"" + _luigi.ToString("N") + "\",\"Name\":\"Luigi\",\"Voted\":3}],"
            + "\"Stack\":[\"" + _dune.ToString("N") + "\",\"" + _alien.ToString("N") + "\",\"" + _heat.ToString("N") + "\"],"
            + "\"Matches\":[\"" + _heat.ToString("N") + "\"],"
            + "\"NearMatches\":[{\"ItemId\":\"" + _dune.ToString("N") + "\",\"Yes\":1,\"Of\":2}]}",
            json);
    }

    private void Vote(MatchRoom room, Guid user, params bool[] answers)
    {
        var stack = new[] { _dune, _alien, _heat };
        for (var i = 0; i < answers.Length; i++)
        {
            Assert.Null(room.Vote(user, stack[i], answers[i], Now));
        }
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~MatchFiltersTests|FullyQualifiedName~MatchRoomTests"`
Expected: errore di compilazione (`MatchFilters`, `MatchRoom`, `MatchPhases`… non esistono).

- [ ] **Step 3: il codice**

`Protocol/MatchDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Fasi di una sala del match (spec P §6.1).</summary>
public static class MatchPhases
{
    public const string Waiting = "Waiting";
    public const string Voting = "Voting";
    public const string Closed = "Closed";
}

/// <summary>Perché una sala si è chiusa (spec P §6.1).</summary>
public static class MatchClosedReasons
{
    /// <summary>È uscito chi l'ha aperta (Leave, o 60 s senza sessioni).</summary>
    public const string CreatorLeft = "CreatorLeft";

    /// <summary>Un'ora senza voti né ingressi.</summary>
    public const string Inactive = "Inactive";

    /// <summary>Chi l'ha aperta ha avviato il party: c'è PartyGroupId.</summary>
    public const string PartyStarted = "PartyStarted";
}

/// <summary>I motivi dei 409 degli endpoint del match (spec P §6.4), nel corpo {Reason}.</summary>
public static class MatchReasons
{
    public const string InAnotherRoom = "InAnotherRoom";
    public const string NotMember = "NotMember";
    public const string NotCreator = "NotCreator";
    public const string Started = "Started";
    public const string Closed = "Closed";
    public const string Full = "Full";
    public const string NotInvited = "NotInvited";
    public const string NotEnoughMembers = "NotEnoughMembers";
    public const string NotStarted = "NotStarted";
    public const string NotNext = "NotNext";
    public const string NotFinished = "NotFinished";
    public const string NotYourParty = "NotYourParty";
}

/// <summary>Un membro della sala: quanti voti ha dato, mai quali.</summary>
public sealed record MatchMemberDto(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Voted")] int Voted);

/// <summary>Un quasi match (spec P §6.3): quanti sì su quanti membri.</summary>
public sealed record MatchNearMatchDto(
    [property: JsonPropertyName("ItemId")] string ItemId,
    [property: JsonPropertyName("Yes")] int Yes,
    [property: JsonPropertyName("Of")] int Of);

/// <summary>
/// Lo stato della sala (spec P §6.4): nelle risposte e in MatchUpdated.
/// Mai i voti dei singoli.
/// </summary>
public sealed record MatchStateDto(
    [property: JsonPropertyName("RoomId")] string RoomId,
    [property: JsonPropertyName("Rev")] long Rev,
    [property: JsonPropertyName("Phase")] string Phase,
    [property: JsonPropertyName("CreatorId")] string CreatorId,
    [property: JsonPropertyName("CreatorName")] string CreatorName,
    [property: JsonPropertyName("Members")] IReadOnlyList<MatchMemberDto> Members,
    [property: JsonPropertyName("Stack")] IReadOnlyList<string> Stack,
    [property: JsonPropertyName("Matches")] IReadOnlyList<string> Matches,
    [property: JsonPropertyName("NearMatches")] IReadOnlyList<MatchNearMatchDto> NearMatches,
    [property: JsonPropertyName("ClosedReason")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? ClosedReason,
    [property: JsonPropertyName("PartyGroupId")][property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PartyGroupId);

/// <summary>Il corpo di un 409 del match.</summary>
public sealed record MatchErrorDto(
    [property: JsonPropertyName("Reason")] string Reason);

/// <summary>Corpo di POST Match/{roomId}/Start: i filtri, con i valori dell'app.</summary>
public sealed class MatchStartRequest
{
    /// <summary>"movies", "series" o "both".</summary>
    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    /// <summary>"any", "90" o "120" (minuti, solo per i film).</summary>
    [JsonPropertyName("Duration")]
    public string? Duration { get; set; }

    /// <summary>Il nome di un genere; vuoto o assente per tutti.</summary>
    [JsonPropertyName("Genre")]
    public string? Genre { get; set; }
}

/// <summary>Corpo di POST Match/{roomId}/Votes.</summary>
public sealed class MatchVoteRequest
{
    [JsonPropertyName("ItemId")]
    public string? ItemId { get; set; }

    [JsonPropertyName("Yes")]
    public bool? Yes { get; set; }
}

/// <summary>Corpo di POST Match/{roomId}/Party.</summary>
public sealed class MatchPartyRequest
{
    [JsonPropertyName("GroupId")]
    public string? GroupId { get; set; }
}
```

`Hub/MatchFilters.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// I filtri della pila del match (spec P §6.2), con gli stessi valori di
/// "Cosa guardo stasera?" nell'app: tipo movies/series/both, durata
/// any/90/120 (solo per i film), un genere per nome o nessuno.
/// </summary>
public sealed record MatchFilters(bool Movies, bool Series, TimeSpan? MaxRuntime, string? Genre)
{
    /// <summary>Lunghezza massima del nome di un genere.</summary>
    public const int MaxGenreLength = 100;

    /// <summary>
    /// I filtri dei valori dell'app; null se uno non è valido. Tipo e durata
    /// mancanti valgono "both" e "any"; un genere vuoto vale "tutti".
    /// </summary>
    public static MatchFilters? Parse(string? type, string? duration, string? genre)
    {
        var name = string.IsNullOrWhiteSpace(genre) ? null : genre.Trim();
        if (name is { Length: > MaxGenreLength } || duration is not (null or "any" or "90" or "120"))
        {
            return null;
        }

        TimeSpan? limit = duration switch
        {
            "90" => TimeSpan.FromMinutes(90),
            "120" => TimeSpan.FromMinutes(120),
            _ => null,
        };
        return type switch
        {
            null or "both" => new MatchFilters(true, true, limit, name),
            "movies" => new MatchFilters(true, false, limit, name),
            "series" => new MatchFilters(false, true, limit, name),
            _ => null,
        };
    }
}
```

`Hub/MatchRoom.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Una sala del match (spec P §6.1, §6.3): membri, inviti, pila, voti, match
/// e quasi match. Solo dati e regole, senza lock: la usa
/// <see cref="MatchService"/> sotto il suo. I voti dei singoli non escono
/// mai: <see cref="Snapshot"/> ha solo i conteggi.
/// </summary>
public sealed class MatchRoom
{
    /// <summary>Membri al massimo, compreso chi ha aperto (spec P §3).</summary>
    public const int MaxMembers = 8;

    /// <summary>Membri per iniziare: chi ha aperto e almeno un amico.</summary>
    public const int MinMembers = 2;

    /// <summary>Quasi match al massimo (spec P §6.3).</summary>
    public const int MaxNearMatches = 5;

    private readonly List<Member> _members = [];
    private readonly HashSet<Guid> _invited = [];
    private readonly List<Guid> _stack = [];
    private readonly HashSet<Guid> _shown = [];
    private readonly Dictionary<Guid, Dictionary<Guid, bool>> _votes = [];
    private readonly List<Guid> _matches = [];

    public MatchRoom(Guid id, Guid creatorId, string creatorName, DateTimeOffset now)
    {
        Id = id;
        CreatorId = creatorId;
        CreatorName = creatorName;
        LastActivityAt = now;
        _members.Add(new Member(creatorId, creatorName));
    }

    public Guid Id { get; }

    public Guid CreatorId { get; }

    public string CreatorName { get; }

    public string Phase { get; private set; } = MatchPhases.Waiting;

    /// <summary>Cresce a ogni cambio visibile nello stato: l'app scarta gli stati più vecchi.</summary>
    public long Rev { get; private set; } = 1;

    /// <summary>Il plugin sta pescando titoli (Start o More): niente ingressi né altre pescate.</summary>
    public bool Drawing { get; set; }

    /// <summary>I filtri dell'inizio, per "Altri 30"; null in attesa.</summary>
    public MatchFilters? Filters { get; private set; }

    /// <summary>Apertura, ultimo ingresso o ultimo voto (spec P §6.1: 1 h senza attività chiude).</summary>
    public DateTimeOffset LastActivityAt { get; private set; }

    public DateTimeOffset? ClosedAt { get; private set; }

    public string? ClosedReason { get; private set; }

    public Guid? PartyGroupId { get; private set; }

    public bool IsOpen => Phase != MatchPhases.Closed;

    public IReadOnlyList<Guid> MemberIds => _members.Select(m => m.UserId).ToList();

    public int MemberCount => _members.Count;

    /// <summary>Tutti i titoli mai messi nella pila: "Altri 30" non li ripesca.</summary>
    public IReadOnlyCollection<Guid> Shown => _shown;

    /// <summary>In votazione, ogni membro ha votato tutta la pila (anche vuota).</summary>
    public bool AllFinished =>
        Phase == MatchPhases.Voting && _members.All(m => Voted(m.UserId) == _stack.Count);

    public bool IsMember(Guid userId) => _members.Any(m => m.UserId == userId);

    public void Invite(Guid userId) => _invited.Add(userId);

    /// <summary>
    /// Entra un invitato; restituisce il motivo del no (MatchReasons) o null.
    /// Chi è già membro "rientra" senza cambi.
    /// </summary>
    public string? Join(Guid userId, string name, DateTimeOffset now)
    {
        if (!IsOpen)
        {
            return MatchReasons.Closed;
        }

        if (IsMember(userId))
        {
            return null;
        }

        if (Phase != MatchPhases.Waiting || Drawing)
        {
            return MatchReasons.Started;
        }

        if (!_invited.Contains(userId))
        {
            return MatchReasons.NotInvited;
        }

        if (_members.Count >= MaxMembers)
        {
            return MatchReasons.Full;
        }

        _members.Add(new Member(userId, name));
        LastActivityAt = now;
        Rev++;
        return null;
    }

    /// <summary>
    /// Esce un membro che non ha aperto la sala: i suoi voti si tolgono e i
    /// match si ricalcolano su chi resta (spec P §6.3). false se non c'era o
    /// se è chi l'ha aperta: per lui si chiude la sala (<see cref="Close"/>).
    /// </summary>
    public bool Remove(Guid userId)
    {
        if (userId == CreatorId || _members.RemoveAll(m => m.UserId == userId) == 0)
        {
            return false;
        }

        _votes.Remove(userId);
        UpdateMatches();
        Rev++;
        return true;
    }

    /// <summary>"Inizia": i filtri e la prima pila (anche vuota).</summary>
    public void Start(MatchFilters filters, IReadOnlyList<Guid> stack, DateTimeOffset now)
    {
        Filters = filters;
        Phase = MatchPhases.Voting;
        Add(stack);
        LastActivityAt = now;
        Rev++;
    }

    /// <summary>"Altri 30": titoli nuovi in fondo alla pila; false se non ce n'era nessuno nuovo.</summary>
    public bool AddToStack(IReadOnlyList<Guid> more, DateTimeOffset now)
    {
        LastActivityAt = now;
        if (!Add(more))
        {
            return false;
        }

        Rev++;
        return true;
    }

    /// <summary>
    /// Il voto di un membro per il suo prossimo titolo; restituisce il motivo
    /// del no (MatchReasons) o null. I voti vanno in ordine: un altro titolo
    /// è NotNext.
    /// </summary>
    public string? Vote(Guid userId, Guid itemId, bool yes, DateTimeOffset now)
    {
        if (!IsOpen)
        {
            return MatchReasons.Closed;
        }

        if (!IsMember(userId))
        {
            return MatchReasons.NotMember;
        }

        if (Phase != MatchPhases.Voting)
        {
            return MatchReasons.NotStarted;
        }

        var next = Voted(userId);
        if (next >= _stack.Count || _stack[next] != itemId)
        {
            return MatchReasons.NotNext;
        }

        if (!_votes.TryGetValue(userId, out var mine))
        {
            mine = [];
            _votes[userId] = mine;
        }

        mine[itemId] = yes;
        LastActivityAt = now;
        UpdateMatches();
        Rev++;
        return null;
    }

    /// <summary>Chiude la sala; una sala già chiusa non cambia.</summary>
    public void Close(string reason, Guid? partyGroupId, DateTimeOffset now)
    {
        if (!IsOpen)
        {
            return;
        }

        Phase = MatchPhases.Closed;
        ClosedReason = reason;
        PartyGroupId = partyGroupId;
        ClosedAt = now;
        Drawing = false;
        Rev++;
    }

    /// <summary>
    /// Segna da quando ogni membro è senza sessioni WonderFlix (online sono gli
    /// utenti che ne hanno almeno una) e restituisce chi lo è da almeno grace
    /// (spec P §6.1). Chi torna online riparte da capo.
    /// </summary>
    public IReadOnlyList<Guid> Absent(IReadOnlySet<Guid> online, DateTimeOffset now, TimeSpan grace)
    {
        var absent = new List<Guid>();
        foreach (var member in _members)
        {
            if (online.Contains(member.UserId))
            {
                member.MissingSince = null;
                continue;
            }

            member.MissingSince ??= now;
            if (now - member.MissingSince.Value >= grace)
            {
                absent.Add(member.UserId);
            }
        }

        return absent;
    }

    /// <summary>Lo stato per le app: conteggi, pila, match e quasi match; mai i voti dei singoli.</summary>
    public MatchStateDto Snapshot() =>
        new(
            N(Id),
            Rev,
            Phase,
            N(CreatorId),
            CreatorName,
            _members.Select(m => new MatchMemberDto(N(m.UserId), m.Name, Voted(m.UserId))).ToList(),
            _stack.Select(N).ToList(),
            _matches.Select(N).ToList(),
            NearMatches(),
            ClosedReason,
            PartyGroupId is { } party ? N(party) : null);

    private int Voted(Guid userId) => _votes.TryGetValue(userId, out var mine) ? mine.Count : 0;

    private bool? VoteOf(Guid userId, Guid itemId) =>
        _votes.TryGetValue(userId, out var mine) && mine.TryGetValue(itemId, out var yes) ? yes : null;

    private bool Add(IReadOnlyList<Guid> items)
    {
        var added = false;
        foreach (var item in items)
        {
            if (_shown.Add(item))
            {
                _stack.Add(item);
                added = true;
            }
        }

        return added;
    }

    // I match crescono soltanto: i voti non cambiano e, senza un membro (e i
    // suoi no), un titolo può solo diventare match. Restano nell'ordine in cui
    // sono usciti; quelli nati insieme nell'ordine della pila.
    private void UpdateMatches()
    {
        foreach (var item in _stack)
        {
            if (!_matches.Contains(item) && _members.All(m => VoteOf(m.UserId, item) == true))
            {
                _matches.Add(item);
            }
        }
    }

    // Spec P §6.3: solo a fine pila; almeno ceil(membri / 2) sì, dal più
    // votato e, a parità, nell'ordine della pila.
    private List<MatchNearMatchDto> NearMatches()
    {
        if (!AllFinished)
        {
            return [];
        }

        var of = _members.Count;
        var threshold = (of + 1) / 2;
        return _stack
            .Where(item => !_matches.Contains(item))
            .Select((item, index) => (Item: item, Index: index, Yes: _members.Count(m => VoteOf(m.UserId, item) == true)))
            .Where(near => near.Yes >= threshold)
            .OrderByDescending(near => near.Yes)
            .ThenBy(near => near.Index)
            .Take(MaxNearMatches)
            .Select(near => new MatchNearMatchDto(N(near.Item), near.Yes, of))
            .ToList();
    }

    private static string N(Guid id) => id.ToString("N");

    private sealed class Member(Guid userId, string name)
    {
        public Guid UserId { get; } = userId;

        public string Name { get; } = name;

        /// <summary>Da quando non ha sessioni WonderFlix; null se ne ha.</summary>
        public DateTimeOffset? MissingSince { get; set; }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): match room with votes, matches and near matches"
```

### Task 2: `IMatchLibrary` e `MatchStackBuilder`

**Files:**
- Create: `Hub/IMatchLibrary.cs`, `Hub/MatchStackBuilder.cs`
- Modify: `Tests/FakeServer.cs` (implementa `IMatchLibrary`)
- Test: `Tests/MatchStackBuilderTests.cs`

**Interfaces:**
- Consumes: `MatchFilters` (Task 1); `ILibraryAccess.CanSee`, `IRecommendationLibrary.LastWatched`.
- Produces:
  - `record MatchCandidate(Guid Id, bool IsMovie, long? RunTimeTicks)`;
  - `interface IMatchLibrary { IReadOnlyList<MatchCandidate> Candidates(Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit); }`;
  - `MatchStackBuilder(IMatchLibrary library, ILibraryAccess access, IRecommendationLibrary history, ILogger<MatchStackBuilder> logger)` con `StackSize = 30`, `CandidateLimit = 300` e `IReadOnlyList<Guid> Draw(Guid creatorId, IReadOnlyList<Guid> members, MatchFilters filters, IReadOnlyCollection<Guid> exclude)`;
  - in `FakeServer`: `List<MatchCandidate> MatchCandidates`, `List<(Guid UserId, MatchFilters Filters, IReadOnlyCollection<Guid> Exclude, int Limit)> MatchQueries`, `bool MatchLibraryFails`.

- [ ] **Step 1: test che falliscono**

In `Tests/FakeServer.cs`:
- aggiungi `IMatchLibrary` all'elenco delle interfacce della classe;
- prima di `TrySendAsync`:

```csharp
    /// <summary>I candidati della query a caso del match, già "a caso" nell'ordine della lista.</summary>
    public List<MatchCandidate> MatchCandidates { get; } = [];

    /// <summary>Ogni query del match: utente, filtri, esclusi, limite.</summary>
    public List<(Guid UserId, MatchFilters Filters, IReadOnlyCollection<Guid> Exclude, int Limit)> MatchQueries { get; } = [];

    /// <summary>Se true, la query del match lancia, come un errore del database.</summary>
    public bool MatchLibraryFails { get; set; }

    // Come Jellyfin: niente esclusi; tipo e genere li ricontrolla chi chiama.
    public IReadOnlyList<MatchCandidate> Candidates(Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit)
    {
        MatchQueries.Add((userId, filters, exclude.ToList(), limit));
        return MatchLibraryFails
            ? throw new InvalidOperationException("database non disponibile")
            : MatchCandidates.Where(c => !exclude.Contains(c.Id)).Take(limit).ToList();
    }
```

`Tests/MatchStackBuilderTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class MatchStackBuilderTests
{
    private static readonly MatchFilters AnyTitle = new(true, true, null, null);

    private readonly FakeServer _server = new();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;

    public MatchStackBuilderTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
    }

    private MatchStackBuilder Builder() =>
        new(_server, _server, _server, NullLogger<MatchStackBuilder>.Instance);

    private Guid Movie(TimeSpan? runtime = null)
    {
        var candidate = new MatchCandidate(Guid.NewGuid(), true, runtime?.Ticks);
        _server.MatchCandidates.Add(candidate);
        return candidate.Id;
    }

    private Guid Series()
    {
        var candidate = new MatchCandidate(Guid.NewGuid(), false, null);
        _server.MatchCandidates.Add(candidate);
        return candidate.Id;
    }

    private IReadOnlyList<Guid> Draw(MatchFilters? filters = null, IReadOnlyCollection<Guid>? exclude = null) =>
        Builder().Draw(_mario.Id, [_mario.Id, _luigi.Id], filters ?? AnyTitle, exclude ?? []);

    [Fact]
    public void TheQueryIsOnTheCreatorsLibrary()
    {
        var shown = new[] { Guid.NewGuid() };
        var filters = new MatchFilters(true, false, null, "Horror");
        Draw(filters, shown);

        var query = Assert.Single(_server.MatchQueries);
        Assert.Equal(_mario.Id, query.UserId);
        Assert.Equal(filters, query.Filters);
        Assert.Equal(shown, query.Exclude);
        Assert.Equal(MatchStackBuilder.CandidateLimit, query.Limit);
    }

    [Fact]
    public void OnlyTitlesEveryMemberCanSeeAndNeverWatched()
    {
        var hidden = Movie();
        var seenByLuigi = Movie();
        var startedByMario = Series();
        var good = Movie();
        _server.Unseen.Add((_luigi.Id, hidden));
        _server.Watched[(_luigi.Id, seenByLuigi)] = DateTimeOffset.UnixEpoch;
        _server.Watched[(_mario.Id, startedByMario)] = DateTimeOffset.UnixEpoch;

        Assert.Equal(new[] { good }, Draw());
    }

    [Fact]
    public void TheTypeIsCheckedAgain()
    {
        var movie = Movie();
        var series = Series();

        Assert.Equal(new[] { movie }, Draw(new MatchFilters(true, false, null, null)));
        Assert.Equal(new[] { series }, Draw(new MatchFilters(false, true, null, null)));
        Assert.Equal(new[] { movie, series }, Draw());
    }

    [Fact]
    public void TheDurationLimitsOnlyMoviesAndNeedsAKnownRuntime()
    {
        var short1 = Movie(TimeSpan.FromMinutes(89));
        Movie(TimeSpan.FromMinutes(90));
        Movie();
        var series = Series();

        Assert.Equal(new[] { short1, series }, Draw(new MatchFilters(true, true, TimeSpan.FromMinutes(90), null)));
    }

    [Fact]
    public void ExcludedAndRepeatedTitlesAreSkipped()
    {
        var old = Movie();
        var fresh = Movie();
        _server.MatchCandidates.Add(new MatchCandidate(fresh, true, null));

        // La finta li toglie già; il costruttore li ricontrolla comunque.
        Assert.Equal(new[] { fresh }, Builder().Draw(_mario.Id, [_mario.Id], AnyTitle, new HashSet<Guid> { old }));
        Assert.Equal(new[] { old, fresh }, Draw());
    }

    [Fact]
    public void TheStackStopsAtThirty()
    {
        for (var i = 0; i < MatchStackBuilder.StackSize + 5; i++)
        {
            Movie();
        }

        Assert.Equal(MatchStackBuilder.StackSize, Draw().Count);
    }

    [Fact]
    public void ChecksStopAtTheFirstMemberThatFails()
    {
        var hidden = Movie();
        _server.Unseen.Add((_mario.Id, hidden));

        Draw();

        Assert.DoesNotContain(_server.SeenChecks, check => check.UserId == _luigi.Id);
    }

    [Fact]
    public void LibraryErrorsGiveAShorterOrEmptyStack()
    {
        Movie();
        _server.MatchLibraryFails = true;
        Assert.Empty(Draw());

        _server.MatchLibraryFails = false;
        _server.LibraryFails = true;
        Assert.Empty(Draw());
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~MatchStackBuilderTests"`
Expected: errore di compilazione (`IMatchLibrary`, `MatchCandidate`, `MatchStackBuilder` non esistono).

- [ ] **Step 3: il codice**

`Hub/IMatchLibrary.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un titolo candidato alla pila: un film (con la durata, se nota) o una serie.</summary>
public sealed record MatchCandidate(Guid Id, bool IsMovie, long? RunTimeTicks);

/// <summary>La libreria come serve al match (adattatore di ILibraryManager e IUserManager).</summary>
public interface IMatchLibrary
{
    /// <summary>
    /// Film e serie a caso della libreria che userId può vedere, del tipo e
    /// del genere dei filtri, mai visti da lui, senza gli exclude; al
    /// massimo limit. La durata non la filtra: la controlla chi chiama.
    /// </summary>
    IReadOnlyList<MatchCandidate> Candidates(Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit);
}
```

`Hub/MatchStackBuilder.cs`:

```csharp
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// La pila del match (spec P §6.2): candidati a caso dalla libreria di chi
/// ha aperto la sala, poi tipo, durata, esclusi e, per ogni membro (anche
/// chi ha aperto), "lo può vedere" e "non l'ha mai visto né iniziato". I
/// controlli di un candidato si fermano al primo che non passa. Non lancia:
/// gli errori della libreria danno una pila più corta o vuota.
/// </summary>
public sealed class MatchStackBuilder(
    IMatchLibrary library,
    ILibraryAccess access,
    IRecommendationLibrary history,
    ILogger<MatchStackBuilder> logger)
{
    /// <summary>Titoli di una pila, all'inizio e a ogni "Altri 30" (spec P §3).</summary>
    public const int StackSize = 30;

    /// <summary>Candidati chiesti alla libreria per una pila (spec P §6.2).</summary>
    public const int CandidateLimit = 300;

    public IReadOnlyList<Guid> Draw(
        Guid creatorId, IReadOnlyList<Guid> members, MatchFilters filters, IReadOnlyCollection<Guid> exclude)
    {
        IReadOnlyList<MatchCandidate> candidates;
        try
        {
            candidates = library.Candidates(creatorId, filters, exclude, CandidateLimit);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pila del match non pescata per {UserId}", creatorId);
            return [];
        }

        var stack = new List<Guid>();
        foreach (var candidate in candidates)
        {
            if (stack.Count == StackSize)
            {
                break;
            }

            if (exclude.Contains(candidate.Id) || stack.Contains(candidate.Id) || !Fits(candidate, filters))
            {
                continue;
            }

            try
            {
                if (members.All(member => access.CanSee(member, candidate.Id) && history.LastWatched(member, candidate.Id) is null))
                {
                    stack.Add(candidate.Id);
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Candidato {ItemId} del match scartato", candidate.Id.ToString("N"));
            }
        }

        logger.LogDebug("Pila del match per {UserId}: {Count} titoli su {Candidates} candidati", creatorId, stack.Count, candidates.Count);
        return stack;
    }

    // Come "Cosa guardo stasera?" nell'app: con un limite, un film senza durata non passa.
    private static bool Fits(MatchCandidate candidate, MatchFilters filters) =>
        candidate.IsMovie
            ? filters.Movies && (filters.MaxRuntime is not { } limit || candidate.RunTimeTicks < limit.Ticks)
            : filters.Series;
}
```

(`candidate.RunTimeTicks < limit.Ticks` è falso quando `RunTimeTicks` è null: il film senza durata non passa.)

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): match stack from the library with member checks"
```

### Task 3: avvisi e voce di cassetta del match, limite dei voti

**Files:**
- Modify: `Protocol/SocialEvent.cs`, `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs`, `Hub/LimitTypes.cs`, `Hub/RateLimiter.cs`
- Test: `Tests/ProtocolJsonTests.cs`, `Tests/InboxBookTests.cs`, `Tests/InboxServiceTests.cs`, `Tests/RateLimiterTests.cs` (test nuovi in fondo)

**Interfaces:**
- Consumes: `MatchStateDto` (Task 1).
- Produces:
  - `SocialEventTypes.MatchInvite`, `SocialEventTypes.MatchUpdated`; proprietà `SocialEvent.RoomId` e `SocialEvent.State` (`MatchStateDto?`); `SocialEvent.MatchInvite(string roomId, string fromName)`, `SocialEvent.MatchUpdated(MatchStateDto state)`;
  - `InboxEntryTypes.MatchInvite`, `InboxEntry.RoomId`; `InboxBook.UpsertMatchInvite(Guid userId, string roomId, string fromName, DateTimeOffset now)`; `InboxService.AddMatchInvitesAsync(Guid roomId, string fromName, IReadOnlyList<Guid> invitees)`;
  - `LimitTypes.MatchVotes` (4 al secondo).

- [ ] **Step 1: test che falliscono**

In fondo a `Tests/ProtocolJsonTests.cs` (aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;` se manca):

```csharp
    [Fact]
    public void MatchEventsCarryTheRoomOrTheState()
    {
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"MatchInvite\",\"FromName\":\"Mario\",\"RoomId\":\"r1\"}",
            JsonSerializer.Serialize(SocialEvent.MatchInvite("r1", "Mario")));

        var state = new MatchStateDto("r1", 3, MatchPhases.Waiting, "u1", "Mario", [new MatchMemberDto("u1", "Mario", 0)], [], [], [], null, null);
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"MatchUpdated\",\"State\":{\"RoomId\":\"r1\",\"Rev\":3,\"Phase\":\"Waiting\","
            + "\"CreatorId\":\"u1\",\"CreatorName\":\"Mario\",\"Members\":[{\"UserId\":\"u1\",\"Name\":\"Mario\",\"Voted\":0}],"
            + "\"Stack\":[],\"Matches\":[],\"NearMatches\":[]}}",
            JsonSerializer.Serialize(SocialEvent.MatchUpdated(state)));
    }
```

In fondo a `Tests/InboxBookTests.cs` (con gli `using` del file):

```csharp
    [Fact]
    public void AMatchInviteIsOneEntryPerRoom()
    {
        var book = new InboxBook();
        var user = Guid.NewGuid();
        var at = new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero);

        var first = book.UpsertMatchInvite(user, "r1", "Mario", at);
        book.MarkRead(user, first.Seq);
        var again = book.UpsertMatchInvite(user, "r1", "Mario", at.AddMinutes(1));
        book.UpsertMatchInvite(user, "r2", "Luigi", at.AddMinutes(2));

        var entries = book.List(user);
        Assert.Equal(2, entries.Count);
        var r1 = Assert.Single(entries, e => e.RoomId == "r1");
        Assert.Equal(InboxEntryTypes.MatchInvite, r1.Type);
        Assert.Equal("Mario", r1.FromName);
        Assert.False(r1.Read);
        Assert.True(again.Seq > first.Seq);
        Assert.Equal(at.AddMinutes(1), r1.CreatedAt);
    }
```

In fondo a `Tests/InboxServiceTests.cs` (usa i campi della classe: `_server`, `_inbox`, `_luigi`):

```csharp
    [Fact]
    public async Task MatchInvitesGoToTheInboxAndPingTheSessions()
    {
        _server.AddSession("s-luigi-match", _luigi);
        var room = Guid.NewGuid();

        await _inbox.AddMatchInvitesAsync(room, "Mario", [_luigi.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries, e => e.Type == InboxEntryTypes.MatchInvite);
        Assert.Equal(room.ToString("N"), entry.RoomId);
        Assert.Equal("Mario", entry.FromName);
        Assert.Contains(_server.SentTo("s-luigi-match"), payload => payload.Contains("InboxChanged", StringComparison.Ordinal));

        // Nessun invitato: niente da fare.
        await _inbox.AddMatchInvitesAsync(room, "Mario", []);
        Assert.Single(_inbox.Get(_luigi.Id).Entries, e => e.Type == InboxEntryTypes.MatchInvite);
    }
```

In fondo a `Tests/RateLimiterTests.cs`:

```csharp
    [Fact]
    public void MatchVotesAreFourASecond()
    {
        var time = new Microsoft.Extensions.Time.Testing.FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 4; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.MatchVotes));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.MatchVotes));
        time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.MatchVotes));
    }
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ProtocolJsonTests|FullyQualifiedName~InboxBookTests|FullyQualifiedName~InboxServiceTests|FullyQualifiedName~RateLimiterTests"`
Expected: errore di compilazione (`SocialEvent.MatchInvite`, `UpsertMatchInvite`, `AddMatchInvitesAsync`, `LimitTypes.MatchVotes` non esistono).

- [ ] **Step 3: il codice**

In `Protocol/SocialEvent.cs`:
- in `SocialEventTypes`, dopo `InboxChanged`:

```csharp
    /// <summary>Un amico invita a una sala del match (spec P §6.5).</summary>
    public const string MatchInvite = "MatchInvite";

    /// <summary>Lo stato di una sala del match di cui si è membri (spec P §6.5).</summary>
    public const string MatchUpdated = "MatchUpdated";
```

- in `SocialEvent`, dopo la proprietà `Mode`:

```csharp
    /// <summary>MatchInvite: la sala, in formato "N".</summary>
    [JsonPropertyName("RoomId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? RoomId { get; init; }

    /// <summary>MatchUpdated: lo stato della sala.</summary>
    [JsonPropertyName("State")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public MatchStateDto? State { get; init; }
```

- in fondo ai metodi statici:

```csharp
    public static SocialEvent MatchInvite(string roomId, string fromName) =>
        new() { Type = SocialEventTypes.MatchInvite, RoomId = roomId, FromName = fromName };

    public static SocialEvent MatchUpdated(MatchStateDto state) =>
        new() { Type = SocialEventTypes.MatchUpdated, State = state };
```

(L'ordine dei campi nel JSON segue l'ordine delle proprietà: `FromName` viene prima di `RoomId`, come nel test.)

In `Protocol/InboxDtos.cs`:
- in `InboxEntryTypes`, dopo `Recommendation`:

```csharp
    /// <summary>Un amico invita a una sala del match (spec P §6.5).</summary>
    public const string MatchInvite = "MatchInvite";
```

- in `InboxEntry`, dopo `Channels`:

```csharp
    /// <summary>MatchInvite: la sala del match, in formato "N".</summary>
    [JsonPropertyName("RoomId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? RoomId { get; set; }
```

- nel commento di `FromName`: "Invite e MatchInvite: chi ha invitato. Recommendation: chi consiglia."

In `Hub/InboxBook.cs`, dopo `UpsertInvite`:

```csharp
    /// <summary>
    /// L'invito a una sala del match (spec P §6.5): una voce per sala; un
    /// nuovo invito la rimette in cima e non letta.
    /// </summary>
    public InboxEntry UpsertMatchInvite(Guid userId, string roomId, string fromName, DateTimeOffset now)
    {
        var inbox = Inbox(userId);
        var existing = inbox.Entries.FirstOrDefault(e =>
            e.Type == InboxEntryTypes.MatchInvite && string.Equals(e.RoomId, roomId, StringComparison.OrdinalIgnoreCase));
        if (existing is null)
        {
            return Add(userId, new InboxEntry
            {
                Type = InboxEntryTypes.MatchInvite,
                CreatedAt = now,
                RoomId = roomId,
                FromName = fromName,
            });
        }

        existing.FromName = fromName;
        existing.CreatedAt = now;
        existing.Read = false;
        existing.Seq = inbox.NextSeq++;
        return existing.Copy();
    }
```

(Controlla che `UpsertInvite` rimetta la voce in cima allo stesso modo: se ordina le voci per `Seq` o le sposta in testa alla lista, fai lo stesso qui.)

In `Hub/InboxService.cs`:
- nel commento della classe, dopo "i consigli degli amici (spec N)": ", gli inviti al match (spec P)";
- dopo `AddInvitesAsync`:

```csharp
    /// <summary>
    /// Le voci d'invito a una sala del match (spec P §6.5), una per sala e
    /// invitato, e l'avviso InboxChanged alle loro sessioni. Gli invitati
    /// sono già controllati da MatchService. Non lancia: un errore finisce
    /// nel log.
    /// </summary>
    public async Task AddMatchInvitesAsync(Guid roomId, string fromName, IReadOnlyList<Guid> invitees)
    {
        if (invitees.Count == 0)
        {
            return;
        }

        try
        {
            var room = roomId.ToString("N");
            var now = time.GetUtcNow();
            lock (_lock)
            {
                foreach (var userId in invitees)
                {
                    Book.UpsertMatchInvite(userId, room, fromName, now);
                }

                Persist();
            }

            logger.LogDebug("Voci d'invito alla sala del match {RoomId}: {Count}", room, invitees.Count);
            await NotifyAsync(invitees).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci d'invito alla sala del match {RoomId} non create o non notificate", roomId.ToString("N"));
        }
    }
```

In `Hub/LimitTypes.cs`, in fondo:

```csharp
    /// <summary>Voti del match, per utente: quattro al secondo (spec P §6.3).</summary>
    public const string MatchVotes = "MatchVotes";
```

In `Hub/RateLimiter.cs`, in `Limits` dopo `Recommendations`: `[LimitTypes.MatchVotes] = (4, TimeSpan.FromSeconds(1)),`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde (il conteggio delle voci di `InboxEntryTypes` o il JSON di altre voci, se un test li controlla, non cambiano: `RoomId` manca nelle voci degli altri tipi).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): match invite and update events, inbox entry and vote limit"
```

### Task 4: `MatchService`, sala in attesa

**Files:**
- Create: `Hub/MatchService.cs`
- Create (test): `Tests/TestMatch.cs`
- Test: `Tests/MatchServiceTests.cs`

**Interfaces:**
- Consumes: `MatchRoom`, `MatchFilters`, DTO (Task 1); `MatchStackBuilder` (Task 2); `SocialEvent.MatchInvite`/`MatchUpdated`, `InboxService.AddMatchInvitesAsync`, `LimitTypes.MatchVotes` (Task 3); `FriendService`, `IUserDirectory`, `ISessionDirectory`, `IEventSender`, `PartyDirectory`, `RateLimiter`, `TimeProvider`.
- Produces:
  - `record MatchOutcome(HubStatus Status, string? Reason, MatchStateDto? State)` con `Ok(MatchStateDto?)`, `Conflict(string reason)`, `static readonly RateLimited` (gli id e i corpi non validi li respinge il controller);
  - `MatchService(MatchStackBuilder stacks, FriendService friends, IUserDirectory users, ISessionDirectory sessions, IEventSender sender, InboxService inbox, PartyDirectory parties, RateLimiter limiter, TimeProvider time, ILogger<MatchService> logger) : IDisposable` con `MemberGrace` (60 s), `InactiveAfter` (1 h), `ClosedKept` (5 min), `PushInterval` (250 ms) e i metodi `Open(Guid userId)`, `Get(Guid userId, Guid roomId)`, `Task<MatchOutcome> InviteAsync(Guid userId, Guid roomId, IReadOnlyList<string>? userIds)`, `Join(Guid userId, Guid roomId)`, `Leave(Guid userId, Guid roomId)` (void), `Start(Guid userId, Guid roomId, MatchFilters filters)`; nel Task 5 anche `Vote`, `More`, `Party`, `Cleanup`;
  - `TestMatch.Create(FakeServer, TempFolder, TimeProvider, FriendService, PartyDirectory? parties = null)`.

- [ ] **Step 1: test che falliscono**

`Tests/TestMatch.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il match dei test: server finto, amici e cassetta veri, file in una cartella temporanea.</summary>
internal static class TestMatch
{
    public static MatchService Create(
        FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, PartyDirectory? parties = null) =>
        new(
            new MatchStackBuilder(server, server, server, NullLogger<MatchStackBuilder>.Instance),
            friends,
            server,
            server,
            server,
            TestInbox.Create(server, folder, time),
            parties ?? new PartyDirectory(time),
            new RateLimiter(time),
            time,
            NullLogger<MatchService>.Instance);
}
```

`Tests/MatchServiceTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class MatchServiceTests : IDisposable
{
    private static readonly MatchFilters AnyTitle = new(true, true, null, null);

    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero));
    private readonly FriendService _friends;
    private readonly PartyDirectory _parties;
    private readonly MatchService _match;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;

    public MatchServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
        _server.AddSession("s-peach", _peach);
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _parties = new PartyDirectory(_time);
        _match = TestMatch.Create(_server, _folder, _time, _friends, _parties);
    }

    public void Dispose()
    {
        _match.Dispose();
        _folder.Dispose();
    }

    private async Task<Guid> RoomWithLuigiAsync()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        Assert.Equal(HubStatus.Ok, (await _match.InviteAsync(_mario.Id, room, [Id(_luigi.Id)])).Status);
        Assert.Equal(HubStatus.Ok, _match.Join(_luigi.Id, room).Status);
        return room;
    }

    private static string Id(Guid id) => id.ToString("N");

    private IReadOnlyList<MatchStateDto> Updates(string sessionId) =>
        _server.SentTo(sessionId)
            .Select(payload => JsonSerializer.Deserialize<JsonElement>(payload))
            .Where(json => json.GetProperty("Type").GetString() == SocialEventTypes.MatchUpdated)
            .Select(json => json.GetProperty("State").Deserialize<MatchStateDto>()!)
            .ToList();

    private static void AssertConflict(string reason, MatchOutcome outcome)
    {
        Assert.Equal(HubStatus.Conflict, outcome.Status);
        Assert.Equal(reason, outcome.Reason);
    }

    [Fact]
    public void OpeningGivesAWaitingRoomWithTheCreator()
    {
        var outcome = _match.Open(_mario.Id);

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Equal(MatchPhases.Waiting, outcome.State!.Phase);
        Assert.Equal("Mario", outcome.State.CreatorName);
        Assert.Equal(Id(_mario.Id), Assert.Single(outcome.State.Members).UserId);
    }

    [Fact]
    public void OneOpenRoomPerUser()
    {
        _match.Open(_mario.Id);
        AssertConflict(MatchReasons.InAnotherRoom, _match.Open(_mario.Id));
    }

    [Fact]
    public async Task OnlyMembersReadTheRoom()
    {
        var room = await RoomWithLuigiAsync();

        Assert.Equal(2, _match.Get(_luigi.Id, room).State!.Members.Count);
        AssertConflict(MatchReasons.NotMember, _match.Get(_peach.Id, room));
        AssertConflict(MatchReasons.NotMember, _match.Get(_mario.Id, Guid.NewGuid()));
    }

    [Fact]
    public async Task InvitesGoOnlyToFriendsWithAnEventAndAnInboxEntry()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);

        var outcome = await _match.InviteAsync(_mario.Id, room, [Id(_luigi.Id), Id(_peach.Id), "non-un-id", Id(_mario.Id)]);

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Contains(
            _server.SentTo("s-luigi"),
            payload => payload == JsonSerializer.Serialize(SocialEvent.MatchInvite(Id(room), "Mario")));
        Assert.DoesNotContain(_server.SentTo("s-peach"), payload => payload.Contains("MatchInvite", StringComparison.Ordinal));
        Assert.DoesNotContain(_server.SentTo("s-mario"), payload => payload.Contains("MatchInvite", StringComparison.Ordinal));
        AssertConflict(MatchReasons.NotInvited, _match.Join(_peach.Id, room));
    }

    [Fact]
    public async Task OnlyTheCreatorInvitesWhileWaiting()
    {
        var room = await RoomWithLuigiAsync();
        await TestRecommendations.MakeFriendsAsync(_friends, _luigi.Id, _peach.Id);

        AssertConflict(MatchReasons.NotCreator, await _match.InviteAsync(_luigi.Id, room, [Id(_peach.Id)]));
        AssertConflict(MatchReasons.Closed, await _match.InviteAsync(_mario.Id, Guid.NewGuid(), [Id(_luigi.Id)]));

        _match.Start(_mario.Id, room, AnyTitle);
        AssertConflict(MatchReasons.Started, await _match.InviteAsync(_mario.Id, room, [Id(_peach.Id)]));
    }

    [Fact]
    public async Task InvitesBeyondTheLimitAre429()
    {
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        var friends = new List<string>();
        for (var i = 0; i < 21; i++)
        {
            var friend = _server.AddUser("Amico" + i);
            await TestRecommendations.MakeFriendsAsync(_friends, friend.Id, _mario.Id);
            friends.Add(Id(friend.Id));
        }

        Assert.Equal(HubStatus.RateLimited, (await _match.InviteAsync(_mario.Id, room, friends)).Status);
        // I primi 20 sono stati invitati.
        Assert.Equal(HubStatus.Ok, _match.Join(Guid.Parse(friends[0]), room).Status);
        AssertConflict(MatchReasons.NotInvited, _match.Join(Guid.Parse(friends[20]), room));
    }

    [Fact]
    public async Task JoiningTellsWhyNot()
    {
        var room = await RoomWithLuigiAsync();

        // Di nuovo: già dentro.
        Assert.Equal(HubStatus.Ok, _match.Join(_luigi.Id, room).Status);
        AssertConflict(MatchReasons.Closed, _match.Join(_luigi.Id, Guid.NewGuid()));

        // Peach invitata ma già in un'altra sala aperta.
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _peach.Id);
        await _match.InviteAsync(_mario.Id, room, [Id(_peach.Id)]);
        _match.Open(_peach.Id);
        AssertConflict(MatchReasons.InAnotherRoom, _match.Join(_peach.Id, room));
    }

    [Fact]
    public async Task MembersHearWhoJoins()
    {
        var room = await RoomWithLuigiAsync();

        var update = Updates("s-mario")[^1];
        Assert.Equal(Id(room), update.RoomId);
        Assert.Equal(2, update.Members.Count);
        Assert.NotEmpty(Updates("s-luigi"));
    }

    [Fact]
    public async Task OnlyTheCreatorStartsWithAFriend()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        AssertConflict(MatchReasons.NotEnoughMembers, _match.Start(_mario.Id, room, AnyTitle));

        await _match.InviteAsync(_mario.Id, room, [Id(_luigi.Id)]);
        _match.Join(_luigi.Id, room);
        AssertConflict(MatchReasons.NotCreator, _match.Start(_luigi.Id, room, AnyTitle));
        AssertConflict(MatchReasons.Closed, _match.Start(_mario.Id, Guid.NewGuid(), AnyTitle));
    }

    [Fact]
    public async Task StartingDrawsTheStackForTheMembers()
    {
        var room = await RoomWithLuigiAsync();
        var dune = new MatchCandidate(Guid.NewGuid(), true, null);
        var alien = new MatchCandidate(Guid.NewGuid(), true, null);
        _server.MatchCandidates.AddRange([dune, alien]);
        _server.Watched[(_luigi.Id, dune.Id)] = DateTimeOffset.UnixEpoch;

        var outcome = _match.Start(_mario.Id, room, AnyTitle);

        Assert.Equal(HubStatus.Ok, outcome.Status);
        Assert.Equal(MatchPhases.Voting, outcome.State!.Phase);
        Assert.Equal(new[] { Id(alien.Id) }, outcome.State.Stack);
        Assert.Equal(_mario.Id, Assert.Single(_server.MatchQueries).UserId);
        // L'ingresso di luigi è appena partito: lo stato nuovo arriva dopo PushInterval.
        _time.Advance(MatchService.PushInterval);
        Assert.Equal(new[] { Id(alien.Id) }, Updates("s-luigi")[^1].Stack);
        AssertConflict(MatchReasons.Started, _match.Start(_mario.Id, room, AnyTitle));
    }

    [Fact]
    public async Task UpdatesAreAtMostOneEvery250Milliseconds()
    {
        var room = await RoomWithLuigiAsync();
        // L'ingresso di luigi è partito subito; questi due aspettano e partono insieme.
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _peach.Id);
        await _match.InviteAsync(_mario.Id, room, [Id(_peach.Id)]);
        var before = Updates("s-mario").Count;
        _match.Join(_peach.Id, room);
        _match.Leave(_peach.Id, room);
        Assert.Equal(before, Updates("s-mario").Count);

        _time.Advance(MatchService.PushInterval);

        var updates = Updates("s-mario");
        Assert.Equal(before + 1, updates.Count);
        Assert.Equal(2, updates[^1].Members.Count);
        Assert.Equal(_match.Get(_mario.Id, room).State!.Rev, updates[^1].Rev);

        // Dopo una pausa il primo cambio parte subito.
        _time.Advance(TimeSpan.FromSeconds(1));
        _match.Leave(_luigi.Id, room);
        Assert.Single(Updates("s-mario")[^1].Members);
    }

    [Fact]
    public async Task LeavingRemovesTheMemberAndAnUnknownRoomIsFine()
    {
        var room = await RoomWithLuigiAsync();

        _match.Leave(_luigi.Id, room);
        _match.Leave(_luigi.Id, room);
        _match.Leave(_luigi.Id, Guid.NewGuid());

        AssertConflict(MatchReasons.NotMember, _match.Get(_luigi.Id, room));
        Assert.Single(_match.Get(_mario.Id, room).State!.Members);
    }

    [Fact]
    public async Task TheCreatorLeavingClosesTheRoom()
    {
        var room = await RoomWithLuigiAsync();

        _match.Leave(_mario.Id, room);
        _time.Advance(MatchService.PushInterval);

        var state = _match.Get(_luigi.Id, room).State!;
        Assert.Equal(MatchPhases.Closed, state.Phase);
        Assert.Equal(MatchClosedReasons.CreatorLeft, state.ClosedReason);
        Assert.Equal(MatchPhases.Closed, Updates("s-luigi")[^1].Phase);
        // Una sala chiusa non conta più: si può aprirne un'altra.
        Assert.Equal(HubStatus.Ok, _match.Open(_luigi.Id).Status);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~MatchServiceTests"`
Expected: errore di compilazione (`MatchService`, `MatchOutcome` non esistono).

- [ ] **Step 3: il codice**

`Hub/MatchService.cs` (i metodi `Vote`, `More`, `Party` e `Cleanup` arrivano nel Task 5, nello stesso file):

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di un'azione del match: lo stato se riuscita, il motivo di un 409.</summary>
public sealed record MatchOutcome(HubStatus Status, string? Reason, MatchStateDto? State)
{
    public static readonly MatchOutcome RateLimited = new(HubStatus.RateLimited, null, null);

    public static MatchOutcome Ok(MatchStateDto? state = null) => new(HubStatus.Ok, null, state);

    public static MatchOutcome Conflict(string reason) => new(HubStatus.Conflict, reason, null);
}

/// <summary>
/// Le sale del match (spec P §6): in memoria, una per utente. Regole degli
/// endpoint, pescate della pila fuori dal lock, inviti, avvisi MatchUpdated
/// raggruppati e pulizia. Non conosce Jellyfin: parla con le interfacce di
/// Hub. Sicuro tra thread.
/// </summary>
public sealed class MatchService(
    MatchStackBuilder stacks,
    FriendService friends,
    IUserDirectory users,
    ISessionDirectory sessions,
    IEventSender sender,
    InboxService inbox,
    PartyDirectory parties,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<MatchService> logger) : IDisposable
{
    /// <summary>Quanto un membro può restare senza sessioni WonderFlix (spec P §6.1).</summary>
    public static readonly TimeSpan MemberGrace = TimeSpan.FromSeconds(60);

    /// <summary>Senza voti né ingressi per tanto, la sala si chiude (spec P §6.1).</summary>
    public static readonly TimeSpan InactiveAfter = TimeSpan.FromHours(1);

    /// <summary>Quanto si tiene una sala chiusa, per chi si riconnette (spec P §6.1).</summary>
    public static readonly TimeSpan ClosedKept = TimeSpan.FromMinutes(5);

    /// <summary>Al più un MatchUpdated per sala ogni tanto (spec P §6.5).</summary>
    public static readonly TimeSpan PushInterval = TimeSpan.FromMilliseconds(250);

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, MatchRoom> _rooms = [];
    private readonly Dictionary<Guid, PushState> _pushes = [];

    /// <summary>Apre una sala con chi chiama come unico membro.</summary>
    public MatchOutcome Open(Guid userId)
    {
        var name = users.GetUser(userId)?.Name ?? string.Empty;
        lock (_lock)
        {
            if (OpenRoomOf(userId) is not null)
            {
                return MatchOutcome.Conflict(MatchReasons.InAnotherRoom);
            }

            var room = new MatchRoom(Guid.NewGuid(), userId, name, time.GetUtcNow());
            _rooms[room.Id] = room;
            logger.LogDebug("Sala del match {RoomId} aperta da {UserId}", N(room.Id), N(userId));
            return MatchOutcome.Ok(room.Snapshot());
        }
    }

    /// <summary>Lo stato, per i membri (anche di una sala chiusa da poco).</summary>
    public MatchOutcome Get(Guid userId, Guid roomId)
    {
        lock (_lock)
        {
            return _rooms.TryGetValue(roomId, out var room) && room.IsMember(userId)
                ? MatchOutcome.Ok(room.Snapshot())
                : MatchOutcome.Conflict(MatchReasons.NotMember);
        }
    }

    /// <summary>
    /// Invita amici attivi di chi ha aperto la sala, in attesa (spec P §6.5);
    /// gli altri id si saltano. Oltre il limite invita quelli che ci stanno e
    /// risponde RateLimited. Avviso MatchInvite e voce nella cassetta.
    /// </summary>
    public async Task<MatchOutcome> InviteAsync(Guid userId, Guid roomId, IReadOnlyList<string>? userIds)
    {
        var targets = new List<Guid>();
        var limited = false;
        string fromName;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotCreator);
            }

            if (room.Phase != MatchPhases.Waiting || room.Drawing)
            {
                return MatchOutcome.Conflict(MatchReasons.Started);
            }

            foreach (var raw in userIds ?? [])
            {
                if (!Guid.TryParse(raw, out var id) || targets.Contains(id) || room.IsMember(id))
                {
                    continue;
                }

                if (users.GetUser(id) is not { Enabled: true } || !friends.AreFriends(userId, id))
                {
                    continue;
                }

                if (!limiter.TryAcquire(N(userId), LimitTypes.Invites))
                {
                    limited = true;
                    break;
                }

                room.Invite(id);
                targets.Add(id);
            }

            fromName = room.CreatorName;
        }

        logger.LogDebug("Inviti alla sala del match {RoomId}: {Count}", N(roomId), targets.Count);
        var payload = JsonSerializer.Serialize(SocialEvent.MatchInvite(N(roomId), fromName));
        await SendAsync(targets, payload).ConfigureAwait(false);
        await inbox.AddMatchInvitesAsync(roomId, fromName, targets).ConfigureAwait(false);
        return limited ? MatchOutcome.RateLimited : MatchOutcome.Ok();
    }

    /// <summary>Entra un invitato, in attesa. Chi è già membro riceve lo stato.</summary>
    public MatchOutcome Join(Guid userId, Guid roomId)
    {
        var name = users.GetUser(userId)?.Name ?? string.Empty;
        Delivery? delivery;
        MatchStateDto state;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room))
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.IsOpen && !room.IsMember(userId) && OpenRoomOf(userId) is not null)
            {
                return MatchOutcome.Conflict(MatchReasons.InAnotherRoom);
            }

            var rev = room.Rev;
            if (room.Join(userId, name, time.GetUtcNow()) is { } reason)
            {
                return MatchOutcome.Conflict(reason);
            }

            delivery = room.Rev == rev ? null : Push(room, immediate: false);
            state = room.Snapshot();
        }

        Deliver(delivery);
        return MatchOutcome.Ok(state);
    }

    /// <summary>
    /// Esce chi chiama; se ha aperto la sala, la sala si chiude per tutti
    /// (spec P §6.1). Una sala sconosciuta o già chiusa non cambia.
    /// </summary>
    public void Leave(Guid userId, Guid roomId)
    {
        Delivery? delivery = null;
        lock (_lock)
        {
            if (_rooms.TryGetValue(roomId, out var room) && room.IsOpen && room.IsMember(userId))
            {
                if (userId == room.CreatorId)
                {
                    room.Close(MatchClosedReasons.CreatorLeft, null, time.GetUtcNow());
                    logger.LogDebug("Sala del match {RoomId} chiusa: {Reason}", N(roomId), MatchClosedReasons.CreatorLeft);
                }
                else
                {
                    room.Remove(userId);
                }

                delivery = Push(room, immediate: false);
            }
        }

        Deliver(delivery);
    }

    /// <summary>
    /// "Inizia" (spec P §6.2): solo chi ha aperto, in attesa, con almeno
    /// MinMembers membri. La pila si pesca fuori dal lock (piano 22a,
    /// decisione 3); se intanto la sala si chiude, la pescata si butta.
    /// </summary>
    public MatchOutcome Start(Guid userId, Guid roomId, MatchFilters filters)
    {
        IReadOnlyList<Guid> members;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotCreator);
            }

            if (room.Phase != MatchPhases.Waiting || room.Drawing)
            {
                return MatchOutcome.Conflict(MatchReasons.Started);
            }

            if (room.MemberCount < MatchRoom.MinMembers)
            {
                return MatchOutcome.Conflict(MatchReasons.NotEnoughMembers);
            }

            room.Drawing = true;
            members = room.MemberIds;
        }

        var stack = stacks.Draw(userId, members, filters, []);

        Delivery? delivery;
        MatchStateDto state;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            room.Drawing = false;
            room.Start(filters, stack, time.GetUtcNow());
            delivery = Push(room, immediate: false);
            state = room.Snapshot();
        }

        Deliver(delivery);
        return MatchOutcome.Ok(state);
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var push in _pushes.Values)
            {
                push.Timer?.Dispose();
            }

            _pushes.Clear();
        }
    }

    // Solo sotto _lock. La sala aperta di cui l'utente è membro.
    private MatchRoom? OpenRoomOf(Guid userId) =>
        _rooms.Values.FirstOrDefault(room => room.IsOpen && room.IsMember(userId));

    // Solo sotto _lock. Spec P §6.5: il primo cambio dopo una pausa parte
    // subito; quelli dentro PushInterval aspettano il timer e partono con
    // l'ultimo stato. immediate manda subito (avvio del party).
    private Delivery? Push(MatchRoom room, bool immediate)
    {
        if (!_pushes.TryGetValue(room.Id, out var push))
        {
            push = new PushState();
            _pushes[room.Id] = push;
        }

        var now = time.GetUtcNow();
        if (immediate || (push.Timer is null && (push.LastAt is not { } last || now - last >= PushInterval)))
        {
            push.Timer?.Dispose();
            push.Timer = null;
            push.LastAt = now;
            return new Delivery(room.Snapshot(), room.MemberIds);
        }

        if (push.Timer is null)
        {
            var roomId = room.Id;
            push.Timer = time.CreateTimer(_ => FirePush(roomId), null, push.LastAt!.Value + PushInterval - now, Timeout.InfiniteTimeSpan);
        }

        return null;
    }

    private void FirePush(Guid roomId)
    {
        Delivery? delivery = null;
        lock (_lock)
        {
            if (_pushes.TryGetValue(roomId, out var push))
            {
                push.Timer?.Dispose();
                push.Timer = null;
                push.LastAt = time.GetUtcNow();
                if (_rooms.TryGetValue(roomId, out var room))
                {
                    delivery = new Delivery(room.Snapshot(), room.MemberIds);
                }
            }
        }

        Deliver(delivery);
    }

    // Fuori dal lock: le sessioni e gli invii passano da Jellyfin.
    private void Deliver(Delivery? delivery)
    {
        if (delivery is null)
        {
            return;
        }

        var payload = JsonSerializer.Serialize(SocialEvent.MatchUpdated(delivery.State));
        _ = SendAsync(delivery.UserIds, payload);
    }

    private async Task SendAsync(IReadOnlyCollection<Guid> userIds, string payload)
    {
        if (userIds.Count == 0)
        {
            return;
        }

        IReadOnlyList<string> targets;
        try
        {
            targets = sessions.GetAppSessions().Where(s => userIds.Contains(s.UserId)).Select(s => s.SessionId).ToList();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Sessioni per gli avvisi del match non lette");
            return;
        }

        foreach (var sessionId in targets)
        {
            try
            {
                // Mai il token della richiesta: l'avviso non si ferma con lei.
                await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Avviso del match non inviato alla sessione {SessionId}", sessionId);
            }
        }
    }

    private static string N(Guid id) => id.ToString("N");

    private sealed record Delivery(MatchStateDto State, IReadOnlyList<Guid> UserIds);

    private sealed class PushState
    {
        public DateTimeOffset? LastAt { get; set; }

        public ITimer? Timer { get; set; }
    }
}
```

Note sul codice:
- `Join` controlla `InAnotherRoom` solo per chi non è già membro di questa sala: il rientro risponde con lo stato (decisione 5).
- `Join`, `Leave` e `Start` calcolano lo stato e i destinatari sotto il lock, e mandano dopo (`Deliver`): `GetAppSessions` e `TrySendAsync` passano da Jellyfin.
- `Start` di una sala che si chiude mentre pesca risponde `Closed` (decisione 3): `Close` rimette `Drawing` a false.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): match service with rooms, invites, joins and start"
```

### Task 5: `MatchService`, voti, "Altri 30", party e pulizia

**Files:**
- Modify: `Hub/MatchService.cs`
- Test: `Tests/MatchServiceTests.cs` (test nuovi in fondo)

**Interfaces:**
- Consumes: `MatchService` (Task 4), `PartyDirectory.Get`/`Grant`.
- Produces: in `MatchService`
  - `MatchOutcome Vote(Guid userId, Guid roomId, Guid itemId, bool yes)`;
  - `MatchOutcome More(Guid userId, Guid roomId)`;
  - `MatchOutcome Party(Guid userId, Guid roomId, Guid groupId)`;
  - `int Cleanup()` (quanti cambi: sale chiuse o dimenticate, membri tolti).

- [ ] **Step 1: test che falliscono**

In fondo a `Tests/MatchServiceTests.cs`:

```csharp
    private async Task<(Guid Room, Guid Dune, Guid Alien)> VotingRoomAsync()
    {
        var room = await RoomWithLuigiAsync();
        var dune = new MatchCandidate(Guid.NewGuid(), true, null);
        var alien = new MatchCandidate(Guid.NewGuid(), true, null);
        _server.MatchCandidates.AddRange([dune, alien]);
        Assert.Equal(HubStatus.Ok, _match.Start(_mario.Id, room, AnyTitle).Status);
        return (room, dune.Id, alien.Id);
    }

    [Fact]
    public async Task VotesMakeMatchesForEveryone()
    {
        var (room, dune, _) = await VotingRoomAsync();

        Assert.Equal(HubStatus.Ok, _match.Vote(_mario.Id, room, dune, true).Status);
        Assert.Equal(HubStatus.Ok, _match.Vote(_luigi.Id, room, dune, true).Status);
        _time.Advance(MatchService.PushInterval);

        Assert.Equal(new[] { Id(dune) }, _match.Get(_luigi.Id, room).State!.Matches);
        Assert.Equal(new[] { Id(dune) }, Updates("s-luigi")[^1].Matches);
    }

    [Fact]
    public async Task VotesTellWhyNot()
    {
        var (room, dune, alien) = await VotingRoomAsync();

        AssertConflict(MatchReasons.NotNext, _match.Vote(_mario.Id, room, alien, true));
        AssertConflict(MatchReasons.NotMember, _match.Vote(_peach.Id, room, dune, true));
        AssertConflict(MatchReasons.Closed, _match.Vote(_mario.Id, Guid.NewGuid(), dune, true));

        var waiting = Guid.Parse(_match.Open(_peach.Id).State!.RoomId);
        AssertConflict(MatchReasons.NotStarted, _match.Vote(_peach.Id, waiting, dune, true));
    }

    [Fact]
    public async Task VotesBeyondFourASecondAre429()
    {
        var room = await RoomWithLuigiAsync();
        for (var i = 0; i < 6; i++)
        {
            _server.MatchCandidates.Add(new MatchCandidate(Guid.NewGuid(), true, null));
        }

        var stack = _match.Start(_mario.Id, room, AnyTitle).State!.Stack.Select(Guid.Parse).ToList();
        for (var i = 0; i < 4; i++)
        {
            Assert.Equal(HubStatus.Ok, _match.Vote(_mario.Id, room, stack[i], false).Status);
        }

        Assert.Equal(HubStatus.RateLimited, _match.Vote(_mario.Id, room, stack[4], false).Status);
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal(HubStatus.Ok, _match.Vote(_mario.Id, room, stack[4], false).Status);
    }

    [Fact]
    public async Task UpdatesCarryCountsNotVotes()
    {
        var (room, dune, alien) = await VotingRoomAsync();
        _match.Vote(_mario.Id, room, dune, true);
        _match.Vote(_mario.Id, room, alien, false);
        _match.Vote(_luigi.Id, room, dune, false);
        _match.Vote(_luigi.Id, room, alien, false);
        _time.Advance(MatchService.PushInterval);

        var update = Updates("s-luigi")[^1];
        Assert.All(update.Members, member => Assert.Equal(2, member.Voted));
        Assert.Empty(update.Matches);
        // Su due membri basta un sì per un quasi match; non si dice di chi.
        Assert.Equal(new MatchNearMatchDto(Id(dune), 1, 2), Assert.Single(update.NearMatches));
        Assert.All(_server.SentTo("s-luigi"), payload => Assert.DoesNotContain("\"Votes\"", payload, StringComparison.Ordinal));
    }

    [Fact]
    public async Task MoreNeedsEveryoneToHaveFinished()
    {
        var (room, dune, alien) = await VotingRoomAsync();
        AssertConflict(MatchReasons.NotFinished, _match.More(_mario.Id, room));

        foreach (var user in new[] { _mario.Id, _luigi.Id })
        {
            _match.Vote(user, room, dune, false);
            _match.Vote(user, room, alien, false);
        }

        AssertConflict(MatchReasons.NotCreator, _match.More(_luigi.Id, room));

        // Niente di nuovo: pila e Rev restano.
        var rev = _match.Get(_mario.Id, room).State!.Rev;
        var same = _match.More(_mario.Id, room);
        Assert.Equal(HubStatus.Ok, same.Status);
        Assert.Equal(rev, same.State!.Rev);
        Assert.Equal(2, same.State.Stack.Count);
        // La query non ripesca i titoli già mostrati.
        Assert.True(_server.MatchQueries[^1].Exclude.ToHashSet().SetEquals([dune, alien]));

        var heat = new MatchCandidate(Guid.NewGuid(), true, null);
        _server.MatchCandidates.Add(heat);
        var more = _match.More(_mario.Id, room);
        Assert.Equal(new[] { Id(dune), Id(alien), Id(heat.Id) }, more.State!.Stack);
    }

    [Fact]
    public async Task MoreIsOnlyWhileVoting()
    {
        var room = await RoomWithLuigiAsync();
        AssertConflict(MatchReasons.NotStarted, _match.More(_mario.Id, room));
        AssertConflict(MatchReasons.Closed, _match.More(_mario.Id, Guid.NewGuid()));
    }

    [Fact]
    public async Task ThePartyLetsTheMembersInAndClosesTheRoom()
    {
        var (room, dune, _) = await VotingRoomAsync();
        // Un avviso in attesa: il party lo scavalca e manda subito.
        _match.Vote(_mario.Id, room, dune, true);
        var group = Guid.NewGuid();
        _parties.Register(group, _mario.Id, PartyModes.Private);

        Assert.Equal(HubStatus.Ok, _match.Party(_mario.Id, room, group).Status);

        Assert.True(_parties.IsVisible(group, _luigi.Id, _ => false));
        var update = Updates("s-luigi")[^1];
        Assert.Equal(MatchPhases.Closed, update.Phase);
        Assert.Equal(MatchClosedReasons.PartyStarted, update.ClosedReason);
        Assert.Equal(Id(group), update.PartyGroupId);
        Assert.Equal(Id(group), _match.Get(_luigi.Id, room).State!.PartyGroupId);
    }

    [Fact]
    public async Task OnlyTheCreatorStartsTheirOwnParty()
    {
        var (room, _, _) = await VotingRoomAsync();
        var mine = Guid.NewGuid();
        var luigis = Guid.NewGuid();
        _parties.Register(mine, _mario.Id, PartyModes.Private);
        _parties.Register(luigis, _luigi.Id, PartyModes.Private);

        AssertConflict(MatchReasons.NotCreator, _match.Party(_luigi.Id, room, luigis));
        AssertConflict(MatchReasons.NotYourParty, _match.Party(_mario.Id, room, luigis));
        AssertConflict(MatchReasons.NotYourParty, _match.Party(_mario.Id, room, Guid.NewGuid()));
        AssertConflict(MatchReasons.Closed, _match.Party(_mario.Id, Guid.NewGuid(), mine));

        var waiting = Guid.Parse(_match.Open(_peach.Id).State!.RoomId);
        AssertConflict(MatchReasons.NotStarted, _match.Party(_peach.Id, waiting, mine));
    }

    [Fact]
    public async Task AMemberWithoutSessionsLeavesAfterTheGrace()
    {
        var room = await RoomWithLuigiAsync();
        var luigiSession = _server.Sessions.Single(s => s.UserId == _luigi.Id);
        _server.Sessions.Remove(luigiSession);

        _match.Cleanup();
        _time.Advance(MatchService.MemberGrace - TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(2, _match.Get(_mario.Id, room).State!.Members.Count);

        // Riconnesso in tempo: si riparte da capo.
        _server.Sessions.Add(luigiSession);
        _match.Cleanup();
        _server.Sessions.Remove(luigiSession);
        _match.Cleanup();
        _time.Advance(MatchService.MemberGrace - TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(2, _match.Get(_mario.Id, room).State!.Members.Count);

        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal(1, _match.Cleanup());
        Assert.Single(_match.Get(_mario.Id, room).State!.Members);
    }

    [Fact]
    public async Task TheCreatorWithoutSessionsClosesTheRoom()
    {
        var room = await RoomWithLuigiAsync();
        _server.Sessions.RemoveAll(s => s.UserId == _mario.Id);

        _match.Cleanup();
        _time.Advance(MatchService.MemberGrace);
        _match.Cleanup();

        Assert.Equal(MatchClosedReasons.CreatorLeft, _match.Get(_luigi.Id, room).State!.ClosedReason);
    }

    [Fact]
    public async Task AnIdleRoomClosesAfterAnHourAndIsForgottenFiveMinutesLater()
    {
        var room = await RoomWithLuigiAsync();

        _time.Advance(MatchService.InactiveAfter - TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(MatchPhases.Waiting, _match.Get(_mario.Id, room).State!.Phase);

        _time.Advance(TimeSpan.FromSeconds(1));
        _match.Cleanup();
        Assert.Equal(MatchClosedReasons.Inactive, _match.Get(_mario.Id, room).State!.ClosedReason);

        _time.Advance(MatchService.ClosedKept);
        _match.Cleanup();
        AssertConflict(MatchReasons.NotMember, _match.Get(_mario.Id, room));
    }
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~MatchServiceTests"`
Expected: errore di compilazione (`Vote`, `More`, `Party`, `Cleanup` non esistono).

- [ ] **Step 3: il codice**

In `Hub/MatchService.cs`, dopo `Start`:

```csharp
    /// <summary>
    /// Il voto di un membro per il suo prossimo titolo (spec P §6.3). Il
    /// limite (4 al secondo per utente) si controlla prima del lock.
    /// </summary>
    public MatchOutcome Vote(Guid userId, Guid roomId, Guid itemId, bool yes)
    {
        if (!limiter.TryAcquire(N(userId), LimitTypes.MatchVotes))
        {
            return MatchOutcome.RateLimited;
        }

        Delivery? delivery;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room))
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.Vote(userId, itemId, yes, time.GetUtcNow()) is { } reason)
            {
                return MatchOutcome.Conflict(reason);
            }

            delivery = Push(room, immediate: false);
        }

        Deliver(delivery);
        return MatchOutcome.Ok();
    }

    /// <summary>
    /// "Altri 30" (spec P §6.3): solo chi ha aperto, quando tutti hanno
    /// finito; stessi filtri, senza i titoli già mostrati. Pesca fuori dal
    /// lock come Start.
    /// </summary>
    public MatchOutcome More(Guid userId, Guid roomId)
    {
        IReadOnlyList<Guid> members;
        MatchFilters filters;
        IReadOnlyCollection<Guid> shown;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotCreator);
            }

            if (room.Phase != MatchPhases.Voting || room.Filters is null)
            {
                return MatchOutcome.Conflict(MatchReasons.NotStarted);
            }

            if (room.Drawing || !room.AllFinished)
            {
                return MatchOutcome.Conflict(MatchReasons.NotFinished);
            }

            room.Drawing = true;
            members = room.MemberIds;
            filters = room.Filters;
            shown = room.Shown.ToHashSet();
        }

        var more = stacks.Draw(userId, members, filters, shown);

        Delivery? delivery = null;
        MatchStateDto state;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            room.Drawing = false;
            if (room.AddToStack(more, time.GetUtcNow()))
            {
                delivery = Push(room, immediate: false);
            }

            state = room.Snapshot();
        }

        Deliver(delivery);
        return MatchOutcome.Ok(state);
    }

    /// <summary>
    /// Avvio del party (spec P §6.6): solo chi ha aperto, in votazione, con
    /// un party registrato da lui. I membri vedono il party privato (Grant),
    /// la sala si chiude con PartyGroupId e l'avviso parte subito.
    /// </summary>
    public MatchOutcome Party(Guid userId, Guid roomId, Guid groupId)
    {
        Delivery? delivery;
        lock (_lock)
        {
            if (!_rooms.TryGetValue(roomId, out var room) || !room.IsOpen)
            {
                return MatchOutcome.Conflict(MatchReasons.Closed);
            }

            if (room.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotCreator);
            }

            if (room.Phase != MatchPhases.Voting)
            {
                return MatchOutcome.Conflict(MatchReasons.NotStarted);
            }

            if (parties.Get(groupId) is not { } party || party.CreatorId != userId)
            {
                return MatchOutcome.Conflict(MatchReasons.NotYourParty);
            }

            parties.Grant(groupId, room.MemberIds.Where(id => id != userId));
            room.Close(MatchClosedReasons.PartyStarted, groupId, time.GetUtcNow());
            delivery = Push(room, immediate: true);
        }

        logger.LogDebug("Sala del match {RoomId} chiusa: party {GroupId}", N(roomId), N(groupId));
        Deliver(delivery);
        return MatchOutcome.Ok();
    }

    /// <summary>
    /// La pulizia (spec P §6.1): membri senza sessioni WonderFlix da
    /// MemberGrace (per chi ha aperto si chiude la sala), sale senza attività
    /// da InactiveAfter, sale chiuse da ClosedKept. Restituisce quanti cambi.
    /// </summary>
    public int Cleanup()
    {
        var online = sessions.GetAppSessions().Select(s => s.UserId).ToHashSet();
        var now = time.GetUtcNow();
        var deliveries = new List<Delivery>();
        var changes = 0;
        lock (_lock)
        {
            foreach (var room in _rooms.Values.ToList())
            {
                if (!room.IsOpen)
                {
                    if (now - room.ClosedAt!.Value >= ClosedKept)
                    {
                        _rooms.Remove(room.Id);
                        if (_pushes.Remove(room.Id, out var push))
                        {
                            push.Timer?.Dispose();
                        }

                        changes++;
                    }

                    continue;
                }

                var rev = room.Rev;
                var absent = room.Absent(online, now, MemberGrace);
                if (absent.Contains(room.CreatorId))
                {
                    room.Close(MatchClosedReasons.CreatorLeft, null, now);
                }
                else
                {
                    foreach (var userId in absent)
                    {
                        room.Remove(userId);
                    }
                }

                if (room.IsOpen && now - room.LastActivityAt >= InactiveAfter)
                {
                    room.Close(MatchClosedReasons.Inactive, null, now);
                }

                if (room.Rev != rev)
                {
                    changes++;
                    if (!room.IsOpen)
                    {
                        logger.LogDebug("Sala del match {RoomId} chiusa: {Reason}", N(room.Id), room.ClosedReason);
                    }

                    if (Push(room, immediate: false) is { } delivery)
                    {
                        deliveries.Add(delivery);
                    }
                }
            }
        }

        foreach (var delivery in deliveries)
        {
            Deliver(delivery);
        }

        return changes;
    }
```

Note sul codice:
- `Vote` di una sala chiusa risponde `Closed` (da `MatchRoom.Vote`); `More` e `Party` in attesa rispondono `NotStarted` (da allineare nella spec, Task 10).
- `Party` chiama `PartyDirectory` sotto il lock del match: `PartyDirectory` ha il suo lock e non richiama mai il match.
- `Cleanup` legge le sessioni prima del lock; se `GetAppSessions` lancia, l'eccezione arriva a `MatchHostedService`, che la scrive nel log.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): match votes, more titles, party start and cleanup"
```

---

## Gruppo B — endpoint e Jellyfin

### Task 6: `MatchController`

**Files:**
- Create: `Api/MatchController.cs`
- Test: `Tests/MatchControllerTests.cs`

**Interfaces:**
- Consumes: `MatchService` (Task 4 e 5), `MatchFilters.Parse` (Task 1), `InviteRequest` (party).
- Produces: `MatchController(IAuthorizationContext authorizationContext, MatchService matches)` con `Open()`, `Get(string roomId)`, `Invite(string roomId, InviteRequest?)`, `Join(string roomId)`, `Leave(string roomId)`, `Start(string roomId, MatchStartRequest?)`, `Vote(string roomId, MatchVoteRequest?)`, `More(string roomId)`, `Party(string roomId, MatchPartyRequest?)`.

- [ ] **Step 1: test che falliscono**

`Tests/MatchControllerTests.cs`:

```csharp
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class MatchControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero));
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly FriendService _friends;
    private readonly PartyDirectory _parties;
    private readonly MatchService _match;

    public MatchControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true, true);
        _server.AddSession("s-mario", _server.Users[_mario.Id]);
        _server.AddSession("s-luigi", _server.Users[_luigi.Id]);
        _friends = TestRecommendations.Friends(_server, _folder, _time);
        _parties = new PartyDirectory(_time);
        _match = TestMatch.Create(_server, _folder, _time, _friends, _parties);
    }

    public void Dispose()
    {
        _match.Dispose();
        _folder.Dispose();
    }

    private MatchController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new MatchController(new FakeAuthorizationContext(auth), _match)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static MatchStateDto State(ActionResult<MatchStateDto> result) =>
        Assert.IsType<MatchStateDto>(Assert.IsType<OkObjectResult>(result.Result).Value);

    private static void AssertReason(string reason, IActionResult? result)
    {
        var conflict = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Equal(new MatchErrorDto(reason), conflict.Value);
    }

    [Fact]
    public async Task TheWholeMatchGoesThroughTheEndpoints()
    {
        await TestRecommendations.MakeFriendsAsync(_friends, _mario.Id, _luigi.Id);
        var dune = Guid.NewGuid();
        _server.MatchCandidates.Add(new MatchCandidate(dune, true, null));

        var room = State(await Controller(_mario).Open()).RoomId;
        Assert.IsType<NoContentResult>(await Controller(_mario).Invite(room, new InviteRequest { UserIds = [_luigi.Id.ToString("N")] }));
        Assert.Equal(2, State(await Controller(_luigi).Join(room)).Members.Count);

        var started = State(await Controller(_mario).Start(room, new MatchStartRequest { Type = "movies", Duration = "any" }));
        Assert.Equal(new[] { dune.ToString("N") }, started.Stack);

        var yes = new MatchVoteRequest { ItemId = dune.ToString("N"), Yes = true };
        Assert.IsType<NoContentResult>(await Controller(_mario).Vote(room, yes));
        Assert.IsType<NoContentResult>(await Controller(_luigi).Vote(room, yes));
        Assert.Equal(new[] { dune.ToString("N") }, State(await Controller(_luigi).Get(room)).Matches);
        Assert.Single(State(await Controller(_mario).More(room)).Stack);

        var group = Guid.NewGuid();
        _parties.Register(group, _mario.Id, PartyModes.Private);
        Assert.IsType<NoContentResult>(await Controller(_mario).Party(room, new MatchPartyRequest { GroupId = group.ToString("N") }));
        Assert.Equal(group.ToString("N"), State(await Controller(_luigi).Get(room)).PartyGroupId);
        Assert.IsType<NoContentResult>(await Controller(_luigi).Leave(room));
    }

    [Fact]
    public async Task ConflictsCarryTheReason()
    {
        var room = State(await Controller(_mario).Open()).RoomId;
        var someone = Guid.NewGuid().ToString("N");

        AssertReason(MatchReasons.InAnotherRoom, (await Controller(_mario).Open()).Result);
        AssertReason(MatchReasons.NotMember, (await Controller(_luigi).Get(room)).Result);
        AssertReason(MatchReasons.NotInvited, (await Controller(_luigi).Join(room)).Result);
        AssertReason(MatchReasons.NotEnoughMembers, (await Controller(_mario).Start(room, new MatchStartRequest())).Result);
        AssertReason(MatchReasons.NotStarted, await Controller(_mario).Vote(room, new MatchVoteRequest { ItemId = someone, Yes = false }));
        AssertReason(MatchReasons.NotStarted, (await Controller(_mario).More(room)).Result);
        AssertReason(MatchReasons.NotCreator, await Controller(_luigi).Invite(room, new InviteRequest()));
        AssertReason(MatchReasons.Closed, await Controller(_mario).Party(someone, new MatchPartyRequest { GroupId = someone }));
    }

    [Fact]
    public async Task BadIdsAndBodiesAre400AndNever404()
    {
        var room = State(await Controller(_mario).Open()).RoomId;

        Assert.IsType<BadRequestResult>((await Controller(_mario).Get("non-un-id")).Result);
        Assert.IsType<BadRequestResult>((await Controller(_mario).Join("non-un-id")).Result);
        Assert.IsType<BadRequestResult>((await Controller(_mario).More("non-un-id")).Result);
        Assert.IsType<BadRequestResult>(await Controller(_mario).Leave("non-un-id"));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Invite("non-un-id", new InviteRequest()));
        Assert.IsType<BadRequestResult>((await Controller(_mario).Start(room, new MatchStartRequest { Type = "films" })).Result);
        Assert.IsType<BadRequestResult>(await Controller(_mario).Vote(room, new MatchVoteRequest { ItemId = "x", Yes = true }));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Vote(room, new MatchVoteRequest { ItemId = Guid.NewGuid().ToString("N") }));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Vote(room, null));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Party(room, new MatchPartyRequest { GroupId = "x" }));
        Assert.IsType<BadRequestResult>(await Controller(_mario).Party(room, null));

        // Una sala sconosciuta: uscire va sempre bene.
        Assert.IsType<NoContentResult>(await Controller(_mario).Leave(Guid.NewGuid().ToString("N")));
    }

    [Fact]
    public async Task VotesBeyondTheLimitAre429()
    {
        var room = State(await Controller(_mario).Open()).RoomId;
        var vote = new MatchVoteRequest { ItemId = Guid.NewGuid().ToString("N"), Yes = true };
        for (var i = 0; i < 4; i++)
        {
            AssertReason(MatchReasons.NotStarted, await Controller(_mario).Vote(room, vote));
        }

        var limited = Assert.IsType<StatusCodeResult>(await Controller(_mario).Vote(room, vote));
        Assert.Equal(StatusCodes.Status429TooManyRequests, limited.StatusCode);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~MatchControllerTests"`
Expected: errore di compilazione (`MatchController` non esiste).

- [ ] **Step 3: il codice**

`Api/MatchController.cs`:

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
/// Il match del film (spec P §6.4), con la stessa policy degli amici. Chi
/// chiama è l'utente dell'autenticazione. Mai 404: roomId senza vincoli di
/// rotta, un id non valido è 400; i 409 hanno {Reason}.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class MatchController(
    IAuthorizationContext authorizationContext,
    MatchService matches) : ControllerBase
{
    /// <summary>Apre una sala; 409 InAnotherRoom se chi chiama è già in una.</summary>
    [HttpPost("Match")]
    public async Task<ActionResult<MatchStateDto>> Open() =>
        Result(matches.Open(await CallerAsync().ConfigureAwait(false)));

    /// <summary>Lo stato della sala, per i membri.</summary>
    [HttpGet("Match/{roomId}")]
    public async Task<ActionResult<MatchStateDto>> Get([FromRoute] string roomId) =>
        Guid.TryParse(roomId, out var id)
            ? Result(matches.Get(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Invita amici, in attesa (solo chi ha aperto).</summary>
    [HttpPost("Match/{roomId}/Invites")]
    public async Task<ActionResult> Invite([FromRoute] string roomId, [FromBody] InviteRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id))
        {
            return BadRequest();
        }

        var caller = await CallerAsync().ConfigureAwait(false);
        return Result(await matches.InviteAsync(caller, id, request?.UserIds).ConfigureAwait(false));
    }

    /// <summary>Entra un invitato.</summary>
    [HttpPost("Match/{roomId}/Join")]
    public async Task<ActionResult<MatchStateDto>> Join([FromRoute] string roomId) =>
        Guid.TryParse(roomId, out var id)
            ? Result(matches.Join(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Esce chi chiama; 204 anche se non era nella sala.</summary>
    [HttpPost("Match/{roomId}/Leave")]
    public async Task<ActionResult> Leave([FromRoute] string roomId)
    {
        if (!Guid.TryParse(roomId, out var id))
        {
            return BadRequest();
        }

        matches.Leave(await CallerAsync().ConfigureAwait(false), id);
        return NoContent();
    }

    /// <summary>"Inizia" con i filtri; 400 con un filtro sconosciuto.</summary>
    [HttpPost("Match/{roomId}/Start")]
    public async Task<ActionResult<MatchStateDto>> Start([FromRoute] string roomId, [FromBody] MatchStartRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id)
            || MatchFilters.Parse(request?.Type, request?.Duration, request?.Genre) is not { } filters)
        {
            return BadRequest();
        }

        return Result(matches.Start(await CallerAsync().ConfigureAwait(false), id, filters));
    }

    /// <summary>Il voto per il prossimo titolo; 400 senza ItemId valido o senza Yes.</summary>
    [HttpPost("Match/{roomId}/Votes")]
    public async Task<ActionResult> Vote([FromRoute] string roomId, [FromBody] MatchVoteRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id)
            || !Guid.TryParse(request?.ItemId, out var itemId)
            || request?.Yes is not { } yes)
        {
            return BadRequest();
        }

        return Result(matches.Vote(await CallerAsync().ConfigureAwait(false), id, itemId, yes));
    }

    /// <summary>"Altri 30", quando tutti hanno finito (solo chi ha aperto).</summary>
    [HttpPost("Match/{roomId}/More")]
    public async Task<ActionResult<MatchStateDto>> More([FromRoute] string roomId) =>
        Guid.TryParse(roomId, out var id)
            ? Result(matches.More(await CallerAsync().ConfigureAwait(false), id))
            : BadRequest();

    /// <summary>Il party avviato da chi ha aperto: i membri ci entrano, la sala si chiude.</summary>
    [HttpPost("Match/{roomId}/Party")]
    public async Task<ActionResult> Party([FromRoute] string roomId, [FromBody] MatchPartyRequest? request)
    {
        if (!Guid.TryParse(roomId, out var id) || !Guid.TryParse(request?.GroupId, out var groupId))
        {
            return BadRequest();
        }

        return Result(matches.Party(await CallerAsync().ConfigureAwait(false), id, groupId));
    }

    private static ActionResult Result(MatchOutcome outcome) => outcome.Status switch
    {
        HubStatus.Ok when outcome.State is { } state => new OkObjectResult(state),
        HubStatus.Ok => new NoContentResult(),
        HubStatus.Conflict => new ObjectResult(new MatchErrorDto(outcome.Reason ?? MatchReasons.Closed))
        {
            StatusCode = StatusCodes.Status409Conflict,
        },
        HubStatus.RateLimited => new StatusCodeResult(StatusCodes.Status429TooManyRequests),
        _ => new BadRequestResult(),
    };

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
git commit -m "feat(plugin): match endpoints"
```

### Task 7: adattatore di Jellyfin e servizio in background

**Files:**
- Create: `Server/JellyfinMatchLibrary.cs`, `MatchHostedService.cs`
- Test: `Tests/JellyfinMatchLibraryTests.cs`, `Tests/MatchHostedServiceTests.cs`

**Interfaces:**
- Consumes: `IMatchLibrary`, `MatchCandidate`, `MatchFilters` (Task 1 e 2), `MatchService.Cleanup` (Task 5).
- Produces: `JellyfinMatchLibrary(ILibraryManager libraryManager, IUserManager userManager) : IMatchLibrary`; `MatchHostedService(MatchService matches, TimeProvider time, ILogger<MatchHostedService> logger) : IHostedService, IDisposable` con `CleanupInterval` (30 s).

**Verifiche su Jellyfin 10.11.9** (fatte il 2026-10-14 sul sorgente ai tag `v10.11.9` e `v10.11.0`; servono a questo task):
- `InternalItemsQuery` ha in entrambe le versioni `User`, `Recursive` (`bool`), `IncludeItemTypes` (`BaseItemKind[]`), `Genres` (`IReadOnlyList<string>`, nomi), `IsPlayed` (`bool?`), `IsVirtualItem`, `ExcludeItemIds` (`Guid[]`), `OrderBy` (`IReadOnlyList<(ItemSortBy, SortOrder)>`), `Limit` (`int?`). **Non** c'è un filtro sulla durata (niente `MaxRunTimeTicks`): la durata la controlla `MatchStackBuilder`.
- **Il costruttore `new InternalItemsQuery(user)`** mette nella query i limiti d'età, gli elementi senza classificazione bloccati e i tag bloccati/consentiti dell'utente (`SetUser`). Scrivere solo `User = user` li salterebbe. `LibraryManager.GetItemList(query)` aggiunge le librerie dell'utente (senza genitori nella query) e alla fine ricontrolla `IsVisible(user)`: i risultati possono essere meno di `Limit`.
- **`ItemSortBy.Random`** diventa `ORDER BY RANDOM()` prima del `Limit`: un campione a caso vero.
- **`IsPlayed = false`:**
  - con **solo** `Series` nella query vuol dire "nessun episodio visto";
  - con film e serie **insieme**, Jellyfin guarda la riga dell'utente sulla serie stessa, che non vale. **Quindi una query per tipo.**
  - Per un film vale solo il segno "visto": un film iniziato passa, e lo toglie `LastWatched` in `MatchStackBuilder`.
- **Inizio della riproduzione** (`SessionManager.OnPlaybackStart`): `LastPlayedDate` e `PlayCount` cambiano subito. `LastWatched` (film: la sua `LastPlayedDate`; serie: quella dell'episodio visto più di recente) vale quindi anche per i titoli solo iniziati, come assume la spec.
- **Ingresso in un gruppo SyncPlay:** `SyncPlayManager` rifiuta chi non vede tutta la coda (`HasAccessToPlayQueue` → `IsVisibleStandalone`, avviso `LibraryAccessDenied` al client). È lo stesso controllo di `ILibraryAccess.CanSee`. Un episodio eredita la classificazione della serie.
- **`/Shows/{id}/Episodes` senza stagione** (per l'app, piano 22c): gli speciali (stagione 0) vengono prima, o in mezzo con `DisplaySpecialsWithinSeasons`; `isMissing=false` toglie gli episodi virtuali. Il "primo episodio" va scelto con `ParentIndexNumber >= 1`.

- [ ] **Step 1: test che falliscono**

`Tests/JellyfinMatchLibraryTests.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class JellyfinMatchLibraryTests
{
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly List<InternalItemsQuery> _queries = [];
    private readonly Movie _dune = new() { Id = Guid.NewGuid(), Name = "Dune", RunTimeTicks = TimeSpan.FromMinutes(155).Ticks };
    private readonly Series _bear = new() { Id = Guid.NewGuid(), Name = "The Bear" };

    private JellyfinMatchLibrary Library()
    {
        var (libraryManager, library) = InterfaceStub<ILibraryManager>.Create();
        library.Handlers["GetItemList"] = args =>
        {
            var query = (InternalItemsQuery)args[0]!;
            _queries.Add(query);
            return query.IncludeItemTypes.SequenceEqual([BaseItemKind.Movie])
                ? new List<BaseItem> { _dune }
                : new List<BaseItem> { _bear };
        };
        var (userManager, users) = InterfaceStub<IUserManager>.Create();
        users.Handlers["GetUserById"] = args => (Guid)args[0]! == _luigi.Id ? _luigi : null;
        return new JellyfinMatchLibrary(libraryManager, userManager);
    }

    [Fact]
    public void OneRandomQueryPerTypeOnTheUsersLibrary()
    {
        var exclude = new[] { Guid.NewGuid() };

        var candidates = Library().Candidates(_luigi.Id, new MatchFilters(true, true, null, "Drama"), exclude, 300);

        Assert.Equal(2, _queries.Count);
        Assert.Equal(new[] { BaseItemKind.Movie }, _queries[0].IncludeItemTypes);
        Assert.Equal(new[] { BaseItemKind.Series }, _queries[1].IncludeItemTypes);
        Assert.All(_queries, query =>
        {
            Assert.Same(_luigi, query.User);
            Assert.True(query.Recursive);
            Assert.False(query.IsPlayed);
            Assert.False(query.IsVirtualItem);
            Assert.Equal(new[] { "Drama" }, query.Genres);
            Assert.Equal(exclude, query.ExcludeItemIds);
            Assert.Equal(new[] { (ItemSortBy.Random, SortOrder.Ascending) }, query.OrderBy);
            Assert.Equal(150, query.Limit);
        });
        Assert.Equal(2, candidates.Count);
        Assert.Contains(new MatchCandidate(_dune.Id, true, TimeSpan.FromMinutes(155).Ticks), candidates);
        Assert.Contains(new MatchCandidate(_bear.Id, false, null), candidates);
    }

    [Fact]
    public void OneTypeGetsTheWholeLimitAndNoGenreMeansAll()
    {
        Library().Candidates(_luigi.Id, new MatchFilters(true, false, TimeSpan.FromMinutes(90), null), [], 300);

        var query = Assert.Single(_queries);
        Assert.Equal(new[] { BaseItemKind.Movie }, query.IncludeItemTypes);
        Assert.Equal(300, query.Limit);
        Assert.Empty(query.Genres);
    }

    [Fact]
    public void TheQueryCarriesTheUsersContentLimits()
    {
        // Il costruttore con l'utente mette i suoi limiti d'età nella query: con "User = …" mancherebbero.
        _luigi.MaxParentalRatingScore = 12;

        Library().Candidates(_luigi.Id, new MatchFilters(true, false, null, null), [], 300);

        Assert.NotNull(Assert.Single(_queries).MaxParentalRating);
    }

    [Fact]
    public void AnUnknownUserGetsNothing()
    {
        Assert.Empty(Library().Candidates(Guid.NewGuid(), new MatchFilters(true, true, null, null), [], 300));
        Assert.Empty(Library().Candidates(Guid.Empty, new MatchFilters(true, true, null, null), [], 300));
        Assert.Empty(_queries);
    }
}
```

(Se `User.MaxParentalRatingScore` non ha un setter pubblico, togli `TheQueryCarriesTheUsersContentLimits` e segnalalo: il costruttore resta obbligatorio nel codice.)

`Tests/MatchHostedServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class MatchHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 14, 20, 0, 0, TimeSpan.Zero));
    private readonly MatchService _match;
    private readonly UserRef _mario;

    public MatchHostedServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _server.AddSession("s-mario", _mario);
        _match = TestMatch.Create(_server, _folder, _time, TestRecommendations.Friends(_server, _folder, _time));
    }

    public void Dispose()
    {
        _match.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public async Task CleanupRunsEveryThirtySeconds()
    {
        using var hosted = new MatchHostedService(_match, _time, NullLogger<MatchHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        var room = Guid.Parse(_match.Open(_mario.Id).State!.RoomId);
        _server.Sessions.Clear();

        // 30 s: si segna l'assenza; 60 s dopo chi ha aperto è fuori e la sala si chiude.
        for (var i = 0; i < 3; i++)
        {
            _time.Advance(MatchHostedService.CleanupInterval);
        }

        Assert.Equal(MatchClosedReasons.CreatorLeft, _match.Get(_mario.Id, room).State!.ClosedReason);
        await hosted.StopAsync(CancellationToken.None);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~JellyfinMatchLibraryTests|FullyQualifiedName~MatchHostedServiceTests"`
Expected: errore di compilazione (`JellyfinMatchLibrary`, `MatchHostedService` non esistono).

- [ ] **Step 3: il codice**

`Server/JellyfinMatchLibrary.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// La query a caso del match su Jellyfin (spec P §6.2): film e serie della
/// libreria che l'utente vede, del genere scelto, mai visti da lui, in
/// ordine casuale. Una query per tipo: con film e serie insieme Jellyfin
/// guarderebbe "visto" sulla riga della serie, che non vale (piano 22a, Task 7).
/// </summary>
public sealed class JellyfinMatchLibrary(ILibraryManager libraryManager, IUserManager userManager) : IMatchLibrary
{
    // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
    public IReadOnlyList<MatchCandidate> Candidates(
        Guid userId, MatchFilters filters, IReadOnlyCollection<Guid> exclude, int limit)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return [];
        }

        BaseItemKind[] kinds = (filters.Movies, filters.Series) switch
        {
            (true, true) => [BaseItemKind.Movie, BaseItemKind.Series],
            (true, false) => [BaseItemKind.Movie],
            (false, true) => [BaseItemKind.Series],
            _ => [],
        };
        var candidates = new List<MatchCandidate>();
        foreach (var kind in kinds)
        {
            // Il costruttore con l'utente porta i suoi limiti d'età e i tag
            // bloccati; GetItemList aggiunge le sue librerie e ricontrolla
            // IsVisible, quindi i risultati possono essere meno di Limit.
            var query = new InternalItemsQuery(user)
            {
                IncludeItemTypes = [kind],
                Recursive = true,
                IsVirtualItem = false,
                IsPlayed = false,
                ExcludeItemIds = [.. exclude],
                OrderBy = [(ItemSortBy.Random, SortOrder.Ascending)],
                Limit = limit / kinds.Length,
            };
            if (filters.Genre is { } genre)
            {
                query.Genres = [genre];
            }

            candidates.AddRange(libraryManager.GetItemList(query)
                .Select(item => new MatchCandidate(item.Id, item is Movie, item.RunTimeTicks)));
        }

        // Ognuna delle due liste è già a caso: si mescolano tra loro.
        var shuffled = candidates.ToArray();
        Random.Shared.Shuffle(shuffled);
        return shuffled;
    }
}
```

`MatchHostedService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// La pulizia delle sale del match (spec P §6.1) ogni
/// <see cref="CleanupInterval"/>: membri senza sessioni, sale inattive,
/// sale chiuse da dimenticare.
/// </summary>
public sealed class MatchHostedService(
    MatchService matches,
    TimeProvider time,
    ILogger<MatchHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si pulisce: con 60 s di grazia un membro esce tra 60 e 90 s.</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromSeconds(30);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
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
            var changes = matches.Cleanup();
            if (changes > 0)
            {
                logger.LogDebug("Pulizia delle sale del match: {Count} cambi", changes);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia delle sale del match non riuscita");
        }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi la suite intera: verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): random match candidates from Jellyfin and room cleanup"
```

### Task 8: montaggio, `Info` e plugin 1.10.0

**Files:**
- Modify: `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `../meta.template.json`, `../README.md`
- Modify (test): `Tests/ServiceRegistrationTests.cs`, `Tests/InfoControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `Tests/ServiceRegistrationTests.cs`, prima del conteggio dei servizi in background:

```csharp
        // Match del film (spec P).
        Assert.Same(provider.GetRequiredService<MatchService>(), provider.GetRequiredService<MatchService>());
        Assert.NotNull(provider.GetRequiredService<MatchStackBuilder>());
        Assert.IsType<Server.JellyfinMatchLibrary>(provider.GetRequiredService<IMatchLibrary>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.MatchController>(provider));
```

e il conteggio diventa:

```csharp
        // Il promemoria dei contatti, oltre ai due di prima.
        // I consigli (spec N), oltre ai tre di prima.
        // L'attività degli amici (spec O), oltre ai quattro di prima.
        // Le sale del match (spec P), oltre ai cinque di prima.
        Assert.Equal(6, provider.GetServices<IHostedService>().Count());
```

In `Tests/InfoControllerTests.cs`: versione `"1.10.0"` e, nei due elenchi di funzioni, `"match"` dopo `"friendsActivity"`.

Cerca con `grep` altri test che controllano le funzioni di `Info`, la versione o la `Description` del plugin (per esempio `PluginPagesTests`) e aggiornali con la stessa regola.

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~InfoControllerTests"`
Expected: FAIL (servizi non registrati, funzione mancante, versione 1.9.0).

- [ ] **Step 3: il codice**

In `PluginServiceRegistrator.cs`, dopo il blocco "Cosa guardano gli amici (spec O)":

```csharp
        // Match del film (spec P).
        serviceCollection.AddSingleton<IMatchLibrary, JellyfinMatchLibrary>();
        serviceCollection.AddSingleton<MatchStackBuilder>();
        serviceCollection.AddSingleton<MatchService>();
```

e in fondo, dopo `ActivityHostedService`: `serviceCollection.AddHostedService<MatchHostedService>();`.

In `Protocol/WatchPartyProtocol.cs`: nel commento di `Features` aggiungi "spec P §6.7"; l'elenco diventa
`["friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home", "recommendations", "friendsActivity", "match"];`.

Nel csproj: `<Version>1.10.0</Version>`.

In `Plugin.cs`: nel commento della classe, dopo "e, dalla 1.9.0, cosa guardano gli amici (spec O)", aggiungi "e, dalla 1.10.0, il match del film (spec P)". `Description` diventa:

```csharp
    public override string Description =>
        "Names, chat, reactions, friends, what friends are watching, the movie match, notifications, recommendations between friends, password recovery and the Home rows (upcoming from Sonarr and Radarr) for WonderFlix.";
```

In `../meta.template.json`:
- `description`: dopo "what friends are watching" aggiungi ", a movie match (friends swipe yes or no on titles and start a party with the ones everyone likes)";
- `overview`: dopo "friends activity" aggiungi ", movie match".

In `../README.md`:
- nell'introduzione, dopo la frase della 1.9.0: "Dalla 1.10.0 c'è il match del film: gli amici in una sala votano sì o no su una pila di titoli e partono in un party privato con quelli che piacciono a tutti (spec P, `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md`).";
- un punto nuovo dopo "Cosa guardano gli amici (dalla 1.9.0)":

```markdown
- **Match del film (dalla 1.10.0):** le sale stanno in memoria, una per
  utente, al massimo 8 membri. `POST Match` apre una sala; chi l'ha aperta
  invita amici (`POST Match/{roomId}/Invites`, avviso `MatchInvite` e voce
  nella cassetta), gli invitati entrano con `POST Match/{roomId}/Join`
  finché è in attesa. `POST Match/{roomId}/Start` `{Type, Duration, Genre}`
  pesca 30 titoli a caso che nessun membro ha visto o iniziato e che tutti
  possono vedere; `POST Match/{roomId}/Votes` `{ItemId, Yes}` vota in ordine;
  un match è un titolo a cui tutti hanno detto sì, i quasi match arrivano a
  fine pila; `POST Match/{roomId}/More` pesca altri 30 titoli.
  `POST Match/{roomId}/Party` `{GroupId}` dà ai membri l'accesso al party
  privato di chi ha aperto e chiude la sala. Lo stato (`GET Match/{roomId}`
  e l'avviso `MatchUpdated`, al più ogni 250 ms) ha i conteggi, mai i voti
  dei singoli. Un membro senza sessioni WonderFlix per 60 s esce; se esce
  chi ha aperto, o dopo un'ora senza voti, la sala si chiude. I 409 hanno
  `{Reason}`.
```

- nel punto "Funzioni": "…dalla 1.9.0 anche `friendsActivity`, dalla 1.10.0 anche `match`…"; e "Quelli di `Match` hanno la stessa policy degli amici.";
- in "Installazione a mano": `pack.sh 1.10.0` e `WonderFlix Watch Party_1.10.0.0/`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): movie match wiring and plugin 1.10.0"
```

---

## Gruppo C — server e chiusura

### Task 9: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo B si ferma qui. L'orchestratore fa prima la review finale del branch e i ritocchi, poi questi passi (un solo riavvio di Jellyfin, con il codice già rivisto, **dopo l'OK dell'utente al riavvio**). Sul server WonderFlix lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando. Gli script vanno scritti in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`). **Nessuno script stampa chiavi o token.**

1. **Riferimenti della dll:** controllo dei riferimenti della dll di Release contro gli assembly di Jellyfin 10.11.9 (come per le versioni passate): nessun membro non risolto.
2. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.10.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.10.0.0/`.
3. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix": base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - `mkdir -p ~/wfwp-backup`; sposta `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.9.0.0` in `~/wfwp-backup/1.9.0.0-catalogo` (se c'è già, con un suffisso); copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.9.0-prima-22a.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.10.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log di oggi `Loaded plugin: "WonderFlix Watch Party" "1.10.0.0"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.10.0.0, rimetti `~/wfwp-backup/1.9.0.0-catalogo` e la configurazione salvata, riavvia, e segnalalo.
4. **Controlli** (stessa base e intestazione; risposte riassunte con `python3`, mai stampate intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.10.0`; funzioni con `match`, e ancora `friendsActivity`, `recommendations`, `home`, `requests`, `account`;
   - `POST /WonderFlixWatchParty/Match` con la sola chiave API: risponde **non 404** (la chiave non ha un utente, la policy degli amici la respinge: 401 o 403); il percorso esiste;
   - nella configurazione `SeerrUrl`, `SonarrUrl`, `ContactReminderDays`, `HomeRowsSeen` ancora al loro posto;
   - nel log nessun `Warning` del plugin dopo l'avvio.
   - Il giro completo (sala, inviti, voti, party) si prova con l'app nei piani 22b e 22c.
5. **Riporta all'utente** l'esito in breve: versione, funzioni, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 22c). Le app 0.15.x non chiamano gli endpoint del match.

### Task 10: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md`
- Modify: `docs/superpowers/plans/2026-10-14-wonderflix-22a-match-plugin.md` (solo una voce "Dalle review dei gruppi" nelle decisioni, se ci sono differenze)

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvata il 2026-10-14; piano 22a realizzato (`docs/superpowers/plans/2026-10-14-wonderflix-22a-match-plugin.md`), build di prova sul server; piani 22b e 22c da scrivere".
- **§6.2:** una query per tipo (film e serie separati) con `new InternalItemsQuery(user)`; la durata si controlla dopo la query (Jellyfin non ha un filtro sulla durata); 150 candidati per tipo quando ci sono tutti e due (Task 7); pescata fuori dal lock con `Drawing` (decisione 3).
- **§6.4:** sala sconosciuta → `Closed`, e `NotMember` per `GET` (decisione 4); `Join` di chi è già membro risponde con lo stato (decisione 5); `More` e `Party` in attesa → `NotStarted`; `More` durante una pescata → `NotFinished`; i filtri mancanti valgono `both`/`any` (decisione 2).
- **§6.5:** il limite degli inviti è quello dei party (stessa chiave: inviti al match e ai party si sommano); `Rev` cresce solo con un cambio visibile (decisione 6).
- **§12:** le verifiche fatte (Task 7, "Verifiche su Jellyfin 10.11.9"), compreso che l'ingresso in SyncPlay usa lo stesso controllo di `CanSee` e la posizione degli speciali.
- **§13:** 22a realizzato; il plugin 1.10.0 resta build di prova fino alla fine del 22c.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze.

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the movie match spec with plan 22a"
```

### Task 11: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 9: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente tag e niente manifest: il plugin 1.10.0 si pubblica alla fine del 22c, insieme all'app 0.16.0.
