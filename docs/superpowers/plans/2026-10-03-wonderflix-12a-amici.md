# WonderFlix — Piano 12a: amici (plugin + app)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prima metà della Spec F (issue #6): lista amici con richiesta e accettazione, ricerca per nome e stato online, dal plugin "WonderFlix Watch Party" (amicizie salvate su disco) fino al pannello Amici dell'app.

**Spec:** `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md` (§3, §5, §6.1–6.3, §6.7–6.9 per la parte amici, §7, §8, §10, §11, §12). Le modalità dei party, i codici, gli inviti e "Nel watch party" nella lista amici sono del **piano 12b**: qui `Party` in `GET Friends` è sempre `null` e `Features` vale `["friends"]`.

**Architecture:**
- **Plugin (1.1.0):** `FriendGraph` (regole, in memoria) + `FriendStore` (file `friends.json` in `plugins/configurations/WonderFlixWatchParty/`, scrittura atomica) + `FriendService` (lock, ricerca, richieste, limiti, avvisi) + `PresenceTracker` (avvisa gli amici quando una sessione WonderFlix si apre o si chiude, raggruppando 2 s) + `FriendsController` (REST). Il nucleo parla con interfacce (`IUserDirectory`, `ISessionDirectory`, `IEventSender`) con adattatori in `Server/`, come in 1.0.0. `Info` aggiunge `Features: ["friends"]`; `Protocol` resta 1.
- **App:** `lib/core/social/` (modelli, `parseSocialEvent`, `SocialApi`) → `lib/features/social/social_providers.dart` (`SocialAvailability` da `Info`, `socialEventsProvider`) → `lib/features/friends/` (`FriendsController`, `FriendSearch`, `FriendRequestNotices`, pannello, icona, scheda della richiesta) → shell (`app_shell.dart`, `back_navigation.dart`).

**Tech Stack:** C# net9.0 contro Jellyfin.Controller/Model 10.11.0, xUnit, `Microsoft.Extensions.TimeProvider.Testing`; Flutter 3.47.5, flutter_riverpod 3, dio, fake_async, lucide_icons_flutter.

**Worktree:** `.claude/worktrees/piano-12a`, branch `feat/piano-12a`. **Base:** `main` con lo spec F (`19ef853`). **Test a inizio piano:** 1255 Flutter, 40 plugin.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali: solo il riferimento `(#6)` in fondo all'oggetto, dove indicato.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-12a`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde e senza warning (il plugin ha `TreatWarningsAsErrors`). **Prima di ogni commit lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit. Dopo ogni modifica agli ARB: `flutter gen-l10n` (la cartella `lib/l10n/gen/` non si committa).
- **Formattazione e fine riga:** niente `dart format` né `dotnet format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Durate, misure, limiti:** costanti nominate e commentate. Commenti in italiano, codice in inglese, come nel resto del codice (anche nel C#: commenti `///` in italiano, identificatori in inglese).
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-03 sui pacchetti NuGet 10.11.0, con un prototipo e sul server:

- **Cartella dei dati:** su Ultra.cc `~/.apps/jellyfin/data/plugins/configurations/` esiste, è dell'utente che fa girare Jellyfin ed è scrivibile; altri plugin ci tengono già sottocartelle. `IApplicationPaths.PluginConfigurationsPath` (`MediaBrowser.Common.Configuration`) la restituisce. Le cartelle dei plugin (`plugins/WonderFlix Watch Party_1.0.0.0`) cambiano nome a ogni versione: i dati **non** vanno lì.
- **Utenti:** `IUserManager` (`MediaBrowser.Controller.Library`) ha `IEnumerable<User> Users` e `User? GetUserById(Guid)`. `User` (`Jellyfin.Database.Implementations.Entities`): `Id`, `Username`; il costruttore `new User(nome, provider, reset)` dà un `Id` casuale e **nessun** permesso. `HasPermission(PermissionKind.IsDisabled)` (estensione in `Jellyfin.Data`, enum in `Jellyfin.Database.Implementations.Enums`) vale `false` senza permessi; `SetPermission(PermissionKind.IsDisabled, true)` aggiunge il permesso se manca (provato).
- **Sessioni:** `ISessionManager` ha gli eventi `SessionStarted` e `SessionEnded` (`EventHandler<SessionEventArgs>`, `SessionInfo` in `e.SessionInfo`: leggere subito `Id`, `Client`, `UserId`, poi l'oggetto viene chiuso). Le app WonderFlix si presentano come client `"WonderFlix"` (`ClientInfo` in `lib/main.dart`). Una caduta del WebSocket **chiude** la sessione Jellyfin (fatto osservato nei piani 5).
- **Test del plugin:** `FakeTimeProvider.Advance` esegue i timer scaduti in modo sincrono. `InterfaceStub<T>` (nei test) fa da stub per le interfacce di Jellyfin; i gestori si registrano per nome del metodo (`get_Users`, `GetUserById`, `get_PluginConfigurationsPath`, `add_SessionStarted`…). Il costruttore di `SessionInfo` è `(ISessionManager, ILogger)`.
- **Controller ASP.NET:** un metodo che restituisce `ActionResult<IReadOnlyList<T>>` **non** può fare `return lista;` (niente conversione implicita da un'interfaccia): si usa `Ok(lista)`. Un'azione non si può chiamare `Request` (nasconde `ControllerBase.Request`).
- **App, eventi del WebSocket:** `watchPartyEventsProvider` è uno stream broadcast (lo ascoltano già `PartyChannel` e `WatchPartySession`). Gli avvisi del plugin arrivano come `PartyChannelReceived(payload)`. `PartyChannel._onEvent` passa ogni payload a `parsePartyEvent`, che oggi scrive "evento del canale non valido" nel log per tutto ciò che non ha `Id`/`GroupId`: il Task 9 lo fa tacere per i tipi sociali.
- **App, test:** `clientInfoProvider` non è sovrascritto in `pumpApp`, quindi `jellyfinHttpProvider` (e `socialApiProvider`) lanciano nei widget test che non li sovrascrivono: `SocialAvailability` deve sopravvivere a qualunque errore. Nei test della diagnostica `clientInfoProvider` **è** sovrascritto: lì `socialApiProvider` va sovrascritto con `FakeSocialApi`, altrimenti dio prova a chiamare `media.example.com`. Le schermate con la vera `AppShell` nei test sono solo `test/app/app_shell_test.dart`, `app_shell_back_button_test.dart`, `app_shell_motion_test.dart` (tutti sovrascrivono `watchPartyEventsProvider`).
- **Riverpod 3:** dentro `build` non si cambia lo stato (si usa `Future.microtask`); `ref.mounted` prima di usare `ref` dopo un `await` e all'inizio di ciò che parte da un microtask; un `Provider.autoDispose` letto solo con `ref.read` nasce e muore subito. Sovrascrivere due volte lo stesso provider in uno `ProviderScope` è un errore: `pumpApp` non va toccato.
- **Flutter:** `Badge` (Material 3) per il numero sull'icona; una `Column` dentro un `Positioned` con solo `top`/`right` deve avere `mainAxisSize: MainAxisSize.min`. Niente `CircularProgressIndicator` nel pannello: con `pumpAndSettle` non finirebbe mai (mentre carica il pannello resta vuoto).

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`, `InfoResponse.cs` | modifica | `ClientName`, `Features`, `Info` con le funzioni |
| `…/Protocol/FriendDtos.cs`, `SocialEvent.cs` | crea | risposte REST degli amici, avvisi senza gruppo |
| `…/Hub/PartyHub.cs` (enum `HubStatus`), `RateLimiter.cs`, `LimitTypes.cs` | modifica/crea | esito 409, limiti per utente |
| `…/Hub/FriendGraph.cs`, `FriendFile.cs`, `FriendStore.cs` | crea | regole, formato del file, disco |
| `…/Hub/IUserDirectory.cs`, `ISessionDirectory.cs` | crea/modifica | utenti Jellyfin, sessioni WonderFlix aperte |
| `…/Hub/FriendService.cs`, `PresenceTracker.cs` | crea | amici, ricerca, avvisi, presenza |
| `…/WatchPartyHostedService.cs`, `PluginServiceRegistrator.cs`, `Plugin.cs`, `.csproj` | modifica | sessioni avviate/finite, servizi, versione 1.1.0 |
| `…/Server/JellyfinUserDirectory.cs`, `JellyfinSessionDirectory.cs` | crea/modifica | adattatori |
| `…/Api/FriendsController.cs`, `WatchPartyController.cs` | crea/modifica | endpoint Friends/Users, `Info` |
| `jellyfin-plugin-watch-party/README.md`, `meta.template.json` | modifica | dati del plugin, descrizione |
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/*` | crea/modifica | test |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi degli amici |
| `lib/core/jellyfin/jellyfin_http.dart` | modifica | `delete` con `quietStatuses` |
| `lib/core/party_channel/party_channel_models.dart` | modifica | `socialEventTypes`, scartati in silenzio |
| `lib/core/social/social_models.dart`, `social_api.dart` | crea | modelli, `parseSocialEvent`, `SocialApi` |
| `lib/features/social/social_providers.dart` | crea | `socialApiProvider`, `SocialAvailability`, `socialEventsProvider` |
| `lib/features/settings/diagnostics.dart` | modifica | riga "Funzioni del plugin" |
| `lib/features/friends/friends_controller.dart`, `friend_search.dart`, `friend_request_notices.dart` | crea | stato e logica |
| `lib/features/friends/friends_panel.dart`, `friends_button.dart`, `friend_request_card.dart` | crea | interfaccia |
| `lib/app/app_shell.dart`, `back_navigation.dart`, `theme.dart` | modifica | icona, pannello, schede, Esc, colore online |
| `test/support/social_fakes.dart` | crea | `FakeSocialApi`, `FakeSocialAvailability`, `socialTestOverrides` |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–6):** plugin. **Poi ci si ferma** (Task 7: lo fa l'orchestratore, deploy sul server).
- **Gruppo B (Task 8–10):** nucleo sociale nell'app.
- **Gruppo C (Task 11–12):** stato degli amici.
- **Gruppo D (Task 13–14):** interfaccia.
- **Gruppo E (Task 15):** allineamento dello spec, verifica finale, build.

---

## Gruppo A — plugin

### Task 1: protocollo degli amici, `Info` con le funzioni, esito 409, limiti per utente

**Files:**
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InfoResponse.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/FriendDtos.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/SocialEvent.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyHub.cs` (solo l'enum `HubStatus`)
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/LimitTypes.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/RateLimiter.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/WatchPartyController.cs` (solo `GetInfo`)
- Test: `…Tests/ProtocolJsonTests.cs`, `…Tests/RateLimiterTests.cs`, `…Tests/WatchPartyControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `ProtocolJsonTests.cs` sostituisci il test `InfoAndJoinResponsesUseProtocolNames` con:

```csharp
    [Fact]
    public void InfoAndJoinResponsesUseProtocolNames()
    {
        Assert.Equal(
            "{\"Version\":\"1.1.0\",\"Protocol\":1,\"Features\":[\"friends\"]}",
            JsonSerializer.Serialize(new InfoResponse("1.1.0", 1, ["friends"])));
        Assert.Equal("{\"Messages\":[]}", JsonSerializer.Serialize(new JoinResponse([])));
    }

    [Fact]
    public void SocialEventsHaveNoGroupAndSkipEmptyFields()
    {
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"FriendRequest\",\"FromUserId\":\"u1\",\"FromName\":\"Mario\"}",
            JsonSerializer.Serialize(SocialEvent.FriendRequest("u1", "Mario")));
        Assert.Equal("{\"Protocol\":1,\"Type\":\"FriendsChanged\"}", JsonSerializer.Serialize(SocialEvent.FriendsChanged()));
    }

    [Fact]
    public void FriendResponsesUseProtocolNames()
    {
        var friends = new FriendsResponse(
            [new FriendEntry("u2", "Luigi", true, null)],
            [new PersonEntry("u3", "Peach")],
            []);
        Assert.Equal(
            "{\"Friends\":[{\"UserId\":\"u2\",\"Name\":\"Luigi\",\"Online\":true,\"Party\":null}],"
            + "\"Incoming\":[{\"UserId\":\"u3\",\"Name\":\"Peach\"}],\"Outgoing\":[]}",
            JsonSerializer.Serialize(friends));
        Assert.Equal(
            "{\"UserId\":\"u2\",\"Name\":\"Luigi\",\"Relation\":\"Friend\"}",
            JsonSerializer.Serialize(new UserSearchResult("u2", "Luigi", FriendRelations.Friend)));
    }
```

In `RateLimiterTests.cs` aggiungi:

```csharp
    [Fact]
    public void FriendRequestsAreLimitedPerHour()
    {
        var time = new FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 20; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.FriendRequests));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.FriendRequests));
        Assert.True(limiter.TryAcquire("u2", LimitTypes.FriendRequests));
        time.Advance(TimeSpan.FromHours(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.FriendRequests));
    }

    [Fact]
    public void SearchesAreLimitedPerMinute()
    {
        var time = new FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 30; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.Searches));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.Searches));
        time.Advance(TimeSpan.FromMinutes(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Searches));
    }
```

(se `RateLimiterTests.cs` non ha già `using Microsoft.Extensions.Time.Testing;` e `using Jellyfin.Plugin.WonderFlixWatchParty.Hub;`, aggiungili.)

In `WatchPartyControllerTests.cs` sostituisci `InfoReportsVersionAndProtocol` con:

```csharp
    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = Controller().GetInfo().Value!;
        Assert.Equal("1.0.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends" }, info.Features);
    }
```

(la versione diventa `1.1.0` nel Task 6, insieme al csproj.)

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`SocialEvent`, `FriendsResponse`, `LimitTypes`, `InfoResponse` con 3 argomenti non esistono).

- [ ] **Step 3: protocollo**

`Protocol/WatchPartyProtocol.cs`, dentro la classe, dopo `MaxChatLength`:

```csharp

    /// <summary>Nome del client delle app WonderFlix nelle sessioni di Jellyfin.</summary>
    public const string ClientName = "WonderFlix";

    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7). Il
    /// protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends"];
```

`Protocol/InfoResponse.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Risposta di GET /WonderFlixWatchParty/Info.</summary>
public sealed record InfoResponse(
    [property: JsonPropertyName("Version")] string Version,
    [property: JsonPropertyName("Protocol")] int Protocol,
    [property: JsonPropertyName("Features")] IReadOnlyList<string> Features);
```

`Protocol/FriendDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Relazione tra chi cerca e un utente trovato (spec F §6.2).</summary>
public static class FriendRelations
{
    public const string None = "None";
    public const string Friend = "Friend";
    public const string Incoming = "Incoming";
    public const string Outgoing = "Outgoing";
}

/// <summary>Il party visibile in cui sta un amico (dal piano 12b; prima sempre null).</summary>
public sealed record FriendParty(
    [property: JsonPropertyName("GroupId")] string GroupId,
    [property: JsonPropertyName("Title")] string Title);

/// <summary>Un amico, con il suo stato.</summary>
public sealed record FriendEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Online")] bool Online,
    [property: JsonPropertyName("Party")] FriendParty? Party);

/// <summary>Chi ha mandato o ricevuto una richiesta in sospeso.</summary>
public sealed record PersonEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name);

/// <summary>Risposta di GET Friends.</summary>
public sealed record FriendsResponse(
    [property: JsonPropertyName("Friends")] IReadOnlyList<FriendEntry> Friends,
    [property: JsonPropertyName("Incoming")] IReadOnlyList<PersonEntry> Incoming,
    [property: JsonPropertyName("Outgoing")] IReadOnlyList<PersonEntry> Outgoing);

/// <summary>Un risultato di GET Users/Search.</summary>
public sealed record UserSearchResult(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Relation")] string Relation);
```

`Protocol/SocialEvent.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi degli avvisi che non riguardano un gruppo (spec F §6.8).</summary>
public static class SocialEventTypes
{
    public const string FriendRequest = "FriendRequest";
    public const string FriendsChanged = "FriendsChanged";
}

/// <summary>
/// Avviso del plugin a un utente, fuori dal canale di un gruppo (spec F
/// §6.8). Non ha Id né GroupId: le app 0.5.x lo scartano.
/// </summary>
public sealed class SocialEvent
{
    [JsonPropertyName("Protocol")]
    public int Protocol { get; init; } = WatchPartyProtocol.Version;

    [JsonPropertyName("Type")]
    public required string Type { get; init; }

    [JsonPropertyName("FromUserId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromUserId { get; init; }

    [JsonPropertyName("FromName")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromName { get; init; }

    public static SocialEvent FriendRequest(string fromUserId, string fromName) =>
        new() { Type = SocialEventTypes.FriendRequest, FromUserId = fromUserId, FromName = fromName };

    public static SocialEvent FriendsChanged() => new() { Type = SocialEventTypes.FriendsChanged };
}
```

- [ ] **Step 4: esito 409 e limiti per utente**

In `Hub/PartyHub.cs`, nell'enum `HubStatus`, dopo `RateLimited`:

```csharp

    /// <summary>Non ammessa nello stato attuale (409).</summary>
    Conflict,
```

`Hub/LimitTypes.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti che non sono tipi di evento (spec F §6.9). La chiave passata a
/// <see cref="RateLimiter.TryAcquire"/> è l'id dell'utente (formato "N").
/// </summary>
public static class LimitTypes
{
    /// <summary>Nuove richieste di amicizia.</summary>
    public const string FriendRequests = "FriendRequests";

    /// <summary>Ricerche di utenti.</summary>
    public const string Searches = "Searches";
}
```

In `Hub/RateLimiter.cs`:
- nel dizionario `Limits`, dopo la riga di `EventTypes.Action`, aggiungi:

```csharp
            [LimitTypes.FriendRequests] = (20, TimeSpan.FromHours(1)),
            [LimitTypes.Searches] = (30, TimeSpan.FromMinutes(1)),
```

- rinomina il parametro di `TryAcquire` da `sessionId` a `key` (anche nel corpo) e cambia il commento della classe e del metodo così:

```csharp
/// <summary>
/// Limiti di frequenza per chiave e tipo, a finestra scorrevole (spec E
/// §6.6, spec F §6.9). La chiave è la sessione per gli eventi del canale,
/// l'utente per gli amici. Sicuro tra thread.
/// </summary>
```

```csharp
    /// <summary>true (e si conta) se la chiave può farne un altro di questo tipo adesso.</summary>
    public bool TryAcquire(string key, string type)
```

(il dizionario `_sent` resta con la chiave `(string SessionId, string Type)`: cambia solo il nome del parametro del metodo.)

- [ ] **Step 5: `Info` con le funzioni**

In `Api/WatchPartyController.cs`:

```csharp
    /// <summary>Versione del plugin, del protocollo e funzioni in più.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(PluginVersion, WatchPartyProtocol.Version, WatchPartyProtocol.Features);
```

- [ ] **Step 6: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning (44 test).

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the friends protocol and per-user limits (#6)"
```

---

### Task 2: regole degli amici (`FriendGraph`) e formato del file

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/FriendFile.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/FriendGraph.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FriendGraphTests.cs`

- [ ] **Step 1: test che falliscono**

`FriendGraphTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class FriendGraphTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();
    private readonly Guid _peach = Guid.NewGuid();
    private readonly FriendGraph _graph = new();

    [Fact]
    public void RequestThenAcceptMakesFriendsBothWays()
    {
        Assert.Equal(FriendRequestOutcome.Sent, _graph.Request(_mario, _luigi, Now));
        Assert.Equal(_mario, Assert.Single(_graph.IncomingOf(_luigi)).From);
        Assert.Equal(_luigi, Assert.Single(_graph.OutgoingOf(_mario)).To);

        Assert.Equal(FriendChange.Done, _graph.Accept(_luigi, _mario));
        Assert.True(_graph.AreFriends(_mario, _luigi));
        Assert.True(_graph.AreFriends(_luigi, _mario));
        Assert.Equal(new[] { _luigi }, _graph.FriendsOf(_mario));
        Assert.Equal(new[] { _mario }, _graph.FriendsOf(_luigi));
        Assert.Empty(_graph.IncomingOf(_luigi));
        Assert.Empty(_graph.OutgoingOf(_mario));
    }

    [Fact]
    public void CrossedRequestsBecomeFriends()
    {
        _graph.Request(_mario, _luigi, Now);
        Assert.Equal(FriendRequestOutcome.BecameFriends, _graph.Request(_luigi, _mario, Now));
        Assert.True(_graph.AreFriends(_mario, _luigi));
        Assert.Empty(_graph.IncomingOf(_mario));
        Assert.Empty(_graph.IncomingOf(_luigi));
    }

    [Fact]
    public void RejectsSelfDuplicatesAndFriends()
    {
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _mario, Now));
        _graph.Request(_mario, _luigi, Now);
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _luigi, Now));
        _graph.Accept(_luigi, _mario);
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _luigi, Now));
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_luigi, _mario, Now));
    }

    [Fact]
    public void AcceptWithoutRequestIsMissing()
    {
        Assert.Equal(FriendChange.Missing, _graph.Accept(_luigi, _mario));
        Assert.False(_graph.AreFriends(_mario, _luigi));
    }

    [Fact]
    public void DeclineCancelAndRemove()
    {
        _graph.Request(_mario, _luigi, Now);
        Assert.True(_graph.Decline(_luigi, _mario));
        Assert.False(_graph.Decline(_luigi, _mario));
        Assert.Empty(_graph.OutgoingOf(_mario));

        _graph.Request(_mario, _peach, Now);
        Assert.True(_graph.Cancel(_mario, _peach));
        Assert.Empty(_graph.IncomingOf(_peach));

        _graph.Request(_mario, _luigi, Now);
        _graph.Accept(_luigi, _mario);
        Assert.True(_graph.Remove(_luigi, _mario));
        Assert.False(_graph.AreFriends(_mario, _luigi));
        Assert.False(_graph.Remove(_luigi, _mario));
    }

    [Fact]
    public void OutgoingRequestsAreLimited()
    {
        for (var i = 0; i < FriendGraph.MaxOutgoing; i++)
        {
            Assert.Equal(FriendRequestOutcome.Sent, _graph.Request(_mario, Guid.NewGuid(), Now));
        }

        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _luigi, Now));
    }

    [Fact]
    public void FriendsAreLimited()
    {
        for (var i = 0; i < FriendGraph.MaxFriends; i++)
        {
            var other = Guid.NewGuid();
            _graph.Request(other, _mario, Now);
            Assert.Equal(FriendChange.Done, _graph.Accept(_mario, other));
        }

        _graph.Request(_luigi, _mario, Now);
        Assert.Equal(FriendChange.Full, _graph.Accept(_mario, _luigi));
        Assert.Equal(FriendRequestOutcome.Rejected, _graph.Request(_mario, _peach, Now));
    }

    [Fact]
    public void PruneDropsUnknownUsers()
    {
        _graph.Request(_mario, _luigi, Now);
        _graph.Accept(_luigi, _mario);
        _graph.Request(_peach, _mario, Now);

        Assert.True(_graph.Prune(id => id != _peach));
        Assert.Empty(_graph.IncomingOf(_mario));
        Assert.True(_graph.AreFriends(_mario, _luigi));
        Assert.False(_graph.Prune(id => id != _peach));
    }

    [Fact]
    public void FileRoundTrip()
    {
        _graph.Request(_mario, _luigi, Now);
        _graph.Accept(_luigi, _mario);
        _graph.Request(_peach, _mario, Now);

        var copy = FriendGraph.FromFile(_graph.ToFile());
        Assert.True(copy.AreFriends(_mario, _luigi));
        var request = Assert.Single(copy.IncomingOf(_mario));
        Assert.Equal(_peach, request.From);
        Assert.Equal(Now, request.CreatedAt);
    }

    [Fact]
    public void FromFileRejectsBadIds()
    {
        Assert.Throws<FormatException>(() => FriendGraph.FromFile(new FriendFile { Friendships = [["x", "y"]] }));
        Assert.Throws<FormatException>(() => FriendGraph.FromFile(new FriendFile { Friendships = [["only-one"]] }));
        Assert.Throws<FormatException>(() =>
            FriendGraph.FromFile(new FriendFile { Requests = [new FriendFileRequest { From = null, To = "y" }] }));
    }
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`FriendGraph`, `FriendFile` non esistono).

- [ ] **Step 3: formato del file**

`Hub/FriendFile.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di friends.json (spec F §6.1). Id utente in formato "N". Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="FriendGraph.FromFile"/>.
/// </summary>
public sealed class FriendFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    /// <summary>Coppie di amici: ogni voce ha esattamente due id.</summary>
    [JsonPropertyName("Friendships")]
    public List<string[]>? Friendships { get; set; } = [];

    [JsonPropertyName("Requests")]
    public List<FriendFileRequest>? Requests { get; set; } = [];
}

/// <summary>Una richiesta in sospeso, nel file.</summary>
public sealed class FriendFileRequest
{
    [JsonPropertyName("From")]
    public string? From { get; set; }

    [JsonPropertyName("To")]
    public string? To { get; set; }

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }
}
```

- [ ] **Step 4: `FriendGraph`**

`Hub/FriendGraph.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di una richiesta di amicizia (spec F §6.2).</summary>
public enum FriendRequestOutcome
{
    /// <summary>Richiesta in sospeso.</summary>
    Sent,

    /// <summary>L'altro aveva già chiesto: ora sono amici.</summary>
    BecameFriends,

    /// <summary>Non ammessa (a sé stessi, doppia, già amici, limiti).</summary>
    Rejected,
}

/// <summary>Esito di un'accettazione.</summary>
public enum FriendChange
{
    /// <summary>Fatto.</summary>
    Done,

    /// <summary>La richiesta non c'è.</summary>
    Missing,

    /// <summary>Uno dei due ha già il massimo di amici.</summary>
    Full,
}

/// <summary>Una richiesta in sospeso.</summary>
public sealed record FriendRequestRecord(Guid From, Guid To, DateTimeOffset CreatedAt);

/// <summary>
/// Amicizie e richieste in sospeso, con le loro regole (spec F §6.2): niente
/// disco, niente Jellyfin. Non è sicuro tra thread: lo protegge
/// <see cref="FriendService"/>.
/// </summary>
public sealed class FriendGraph
{
    /// <summary>Amici al massimo per utente (spec F §6.9).</summary>
    public const int MaxFriends = 200;

    /// <summary>Richieste inviate in sospeso al massimo per utente (spec F §6.9).</summary>
    public const int MaxOutgoing = 50;

    // Coppie ordinate (il Guid minore prima): una sola voce per amicizia.
    private readonly HashSet<(Guid, Guid)> _friendships = [];
    private readonly List<FriendRequestRecord> _requests = [];

    public bool AreFriends(Guid a, Guid b) => _friendships.Contains(Pair(a, b));

    public IReadOnlyList<Guid> FriendsOf(Guid user) =>
        _friendships
            .Where(p => p.Item1 == user || p.Item2 == user)
            .Select(p => p.Item1 == user ? p.Item2 : p.Item1)
            .ToList();

    public IReadOnlyList<FriendRequestRecord> IncomingOf(Guid user) => _requests.Where(r => r.To == user).ToList();

    public IReadOnlyList<FriendRequestRecord> OutgoingOf(Guid user) => _requests.Where(r => r.From == user).ToList();

    public bool HasRequest(Guid from, Guid to) => _requests.Any(r => r.From == from && r.To == to);

    /// <summary>
    /// Richiesta di from a to. Se to aveva già chiesto a from diventano
    /// subito amici (la richiesta di to sparisce).
    /// </summary>
    public FriendRequestOutcome Request(Guid from, Guid to, DateTimeOffset now)
    {
        if (from == to || AreFriends(from, to) || HasRequest(from, to))
        {
            return FriendRequestOutcome.Rejected;
        }

        if (HasRequest(to, from))
        {
            if (!CanBefriend(from, to))
            {
                return FriendRequestOutcome.Rejected;
            }

            RemoveRequest(to, from);
            _friendships.Add(Pair(from, to));
            return FriendRequestOutcome.BecameFriends;
        }

        if (OutgoingOf(from).Count >= MaxOutgoing || FriendsOf(from).Count >= MaxFriends)
        {
            return FriendRequestOutcome.Rejected;
        }

        _requests.Add(new FriendRequestRecord(from, to, now));
        return FriendRequestOutcome.Sent;
    }

    /// <summary>user accetta la richiesta di from.</summary>
    public FriendChange Accept(Guid user, Guid from)
    {
        if (!HasRequest(from, user))
        {
            return FriendChange.Missing;
        }

        if (!CanBefriend(user, from))
        {
            return FriendChange.Full;
        }

        RemoveRequest(from, user);
        _friendships.Add(Pair(user, from));
        return FriendChange.Done;
    }

    /// <summary>user rifiuta la richiesta di from; false se non c'era.</summary>
    public bool Decline(Guid user, Guid from) => RemoveRequest(from, user);

    /// <summary>user annulla la propria richiesta a to; false se non c'era.</summary>
    public bool Cancel(Guid user, Guid to) => RemoveRequest(user, to);

    /// <summary>Toglie l'amicizia per tutti e due; false se non c'era.</summary>
    public bool Remove(Guid user, Guid friend) => _friendships.Remove(Pair(user, friend));

    /// <summary>
    /// Toglie amicizie e richieste di utenti che non esistono più; true se
    /// ha tolto qualcosa.
    /// </summary>
    public bool Prune(Func<Guid, bool> exists)
    {
        var removed = _friendships.RemoveWhere(p => !exists(p.Item1) || !exists(p.Item2));
        removed += _requests.RemoveAll(r => !exists(r.From) || !exists(r.To));
        return removed > 0;
    }

    public FriendFile ToFile() => new()
    {
        Friendships = _friendships.Select(p => new[] { p.Item1.ToString("N"), p.Item2.ToString("N") }).ToList(),
        Requests = _requests
            .Select(r => new FriendFileRequest { From = r.From.ToString("N"), To = r.To.ToString("N"), CreatedAt = r.CreatedAt })
            .ToList(),
    };

    /// <summary>Lancia <see cref="FormatException"/> se il file non ha la forma attesa.</summary>
    public static FriendGraph FromFile(FriendFile file)
    {
        var graph = new FriendGraph();
        foreach (var pair in file.Friendships ?? [])
        {
            if (pair is not { Length: 2 })
            {
                throw new FormatException("amicizia senza due id");
            }

            graph._friendships.Add(Pair(ParseId(pair[0]), ParseId(pair[1])));
        }

        foreach (var request in file.Requests ?? [])
        {
            graph._requests.Add(new FriendRequestRecord(ParseId(request.From), ParseId(request.To), request.CreatedAt));
        }

        return graph;
    }

    private bool CanBefriend(Guid a, Guid b) => FriendsOf(a).Count < MaxFriends && FriendsOf(b).Count < MaxFriends;

    private bool RemoveRequest(Guid from, Guid to) => _requests.RemoveAll(r => r.From == from && r.To == to) > 0;

    private static (Guid, Guid) Pair(Guid a, Guid b) => a.CompareTo(b) <= 0 ? (a, b) : (b, a);

    private static Guid ParseId(string? value) =>
        Guid.TryParse(value, out var id) ? id : throw new FormatException("id utente non valido");
}
```

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add friendship rules (#6)"
```

---

### Task 3: amici su disco (`FriendStore`)

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/FriendStore.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/TempFolder.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FriendStoreTests.cs`

- [ ] **Step 1: test che falliscono**

`TempFolder.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Cartella temporanea per un test, cancellata alla fine.</summary>
internal sealed class TempFolder : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "wfwp-" + Guid.NewGuid().ToString("N"));

    /// <summary>Percorso di friends.json in una sottocartella non ancora creata.</summary>
    public string FriendsFile => System.IO.Path.Combine(Path, "WonderFlixWatchParty", "friends.json");

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
```

`FriendStoreTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class FriendStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private FriendStore Store() => new(_folder.FriendsFile, NullLogger<FriendStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        var graph = Store().Load();
        Assert.Empty(graph.FriendsOf(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.FriendsFile));
    }

    [Fact]
    public void SaveCreatesTheFolderAndLoadReadsItBack()
    {
        var mario = Guid.NewGuid();
        var luigi = Guid.NewGuid();
        var graph = new FriendGraph();
        graph.Request(mario, luigi, Now);
        graph.Accept(luigi, mario);

        Store().Save(graph);

        Assert.True(File.Exists(_folder.FriendsFile));
        Assert.False(File.Exists(_folder.FriendsFile + ".tmp"));
        Assert.True(Store().Load().AreFriends(mario, luigi));
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.FriendsFile)!);
        File.WriteAllText(_folder.FriendsFile, "{ non è json");

        var graph = Store().Load();

        Assert.Empty(graph.FriendsOf(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.FriendsFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.FriendsFile + ".bad"));
    }

    [Fact]
    public void BadIdsAreMovedAsideToo()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.FriendsFile)!);
        File.WriteAllText(_folder.FriendsFile, "{\"Version\":1,\"Friendships\":[[\"x\",\"y\"]],\"Requests\":[]}");

        Store().Load();

        Assert.True(File.Exists(_folder.FriendsFile + ".bad"));
    }

    [Fact]
    public void DefaultPathIsInThePluginConfigurations()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");
        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "friends.json"),
            FriendStore.DefaultPath(paths));
    }
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`FriendStore` non esiste).

- [ ] **Step 3: `FriendStore`**

`Hub/FriendStore.cs`:

```csharp
using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// friends.json su disco (spec F §6.1). Non sta nella cartella del plugin,
/// che cambia nome a ogni versione, ma nelle configurazioni dei plugin. Non
/// è sicuro tra thread: lo usa solo <see cref="FriendService"/>, sotto lock.
/// </summary>
public sealed class FriendStore(string filePath, ILogger<FriendStore> logger)
{
    /// <summary>Sottocartella dentro le configurazioni dei plugin.</summary>
    public const string FolderName = "WonderFlixWatchParty";

    public const string FileName = "friends.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// friends.json.bad e si riparte vuoti.
    /// </summary>
    public FriendGraph Load()
    {
        if (!File.Exists(FilePath))
        {
            return new FriendGraph();
        }

        try
        {
            var file = JsonSerializer.Deserialize<FriendFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return FriendGraph.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            File.Move(FilePath, bad, overwrite: true);
            logger.LogWarning(ex, "Amici illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            return new FriendGraph();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(FriendGraph graph)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(graph.ToFile(), Options));
        File.Move(temporary, FilePath, overwrite: true);
    }
}
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): store friendships on disk (#6)"
```

---

### Task 4: utenti, sessioni WonderFlix e `FriendService`

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/IUserDirectory.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/ISessionDirectory.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinSessionDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/FriendService.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FakeServer.cs`
- Test: `…Tests/FriendServiceTests.cs`, `…Tests/ServerAdapterTests.cs`

- [ ] **Step 1: interfacce e server finto**

`Hub/IUserDirectory.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un utente di Jellyfin, come serve agli amici.</summary>
public sealed record UserRef(Guid Id, string Name, bool Enabled);

/// <summary>Gli utenti del server (adattatore di IUserManager).</summary>
public interface IUserDirectory
{
    IReadOnlyList<UserRef> GetUsers();

    /// <summary>null se l'utente non esiste (più).</summary>
    UserRef? GetUser(Guid userId);
}
```

In `Hub/ISessionDirectory.cs`, dentro l'interfaccia, dopo `Exists`:

```csharp

    /// <summary>
    /// Le sessioni aperte delle app WonderFlix con un utente: chi è online e
    /// a chi mandare gli avvisi (spec F §6.3).
    /// </summary>
    IReadOnlyList<CallerSession> GetAppSessions();
```

In `Server/JellyfinSessionDirectory.cs` aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;` e, dopo `Exists`:

```csharp

    public IReadOnlyList<CallerSession> GetAppSessions() =>
        sessionManager.Sessions
            .Where(s => string.Equals(s.Client, WatchPartyProtocol.ClientName, StringComparison.Ordinal)
                && !s.UserId.Equals(Guid.Empty))
            .Select(s => new CallerSession(s.Id, s.UserId, s.UserName))
            .ToList();
```

In `…Tests/FakeServer.cs`:
- la classe implementa anche `IUserDirectory`: `internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender, IUserDirectory`;
- aggiungi dentro la classe:

```csharp
    /// <summary>Utenti di Jellyfin, per id.</summary>
    public Dictionary<Guid, UserRef> Users { get; } = [];

    public UserRef AddUser(string name, bool enabled = true)
    {
        var user = new UserRef(Guid.NewGuid(), name, enabled);
        Users[user.Id] = user;
        return user;
    }

    /// <summary>Una sessione WonderFlix aperta di un utente di <see cref="Users"/>.</summary>
    public CallerSession AddSession(string sessionId, UserRef user)
    {
        var session = new CallerSession(sessionId, user.Id, user.Name);
        Sessions.Add(session);
        return session;
    }

    /// <summary>I payload mandati a una sessione, in ordine.</summary>
    public IReadOnlyList<string> SentTo(string sessionId) =>
        Sent.Where(s => s.SessionId == sessionId).Select(s => s.Payload).ToList();

    // Nei test tutte le sessioni sono di WonderFlix.
    public IReadOnlyList<CallerSession> GetAppSessions() => Sessions;

    public IReadOnlyList<UserRef> GetUsers() => Users.Values.ToList();

    public UserRef? GetUser(Guid userId) => Users.GetValueOrDefault(userId);
```

In `…Tests/ServerAdapterTests.cs` aggiungi:

```csharp
    [Fact]
    public void AppSessionsAreWonderFlixWithAUser()
    {
        var userId = Guid.NewGuid();
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        stub.Handlers["get_Sessions"] = _ => new[]
        {
            Session("s-web", "d1", "Jellyfin Web", userId, "Mario"),
            Session("s-app", "d1", "WonderFlix", userId, "Mario"),
            Session("s-anon", "d2", "WonderFlix", Guid.Empty, string.Empty),
        };
        var directory = new JellyfinSessionDirectory(manager);

        Assert.Equal(new[] { new CallerSession("s-app", userId, "Mario") }, directory.GetAppSessions());
    }
```

- [ ] **Step 2: test di `FriendService` che falliscono**

`FriendServiceTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class FriendServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero));
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly FriendService _friends;

    public FriendServiceTests()
    {
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
        _friends = Service();
    }

    public void Dispose() => _folder.Dispose();

    private FriendService Service() => new(
        new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
        _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private async Task MakeFriends(UserRef a, UserRef b)
    {
        Assert.Equal(HubStatus.Ok, await _friends.RequestAsync(a.Id, b.Id));
        Assert.Equal(HubStatus.Ok, await _friends.AcceptAsync(b.Id, a.Id));
        _server.Sent.Clear();
    }

    [Fact]
    public async Task RequestNotifiesTheTargetWithTheName()
    {
        Assert.Equal(HubStatus.Ok, await _friends.RequestAsync(_mario.Id, _luigi.Id));

        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("FriendRequest", json.GetProperty("Type").GetString());
        Assert.Equal(_mario.Id.ToString("N"), json.GetProperty("FromUserId").GetString());
        Assert.Equal("Mario", json.GetProperty("FromName").GetString());
        Assert.Empty(_server.SentTo("s-mario"));

        var luigi = _friends.GetFriends(_luigi.Id);
        Assert.Equal("Mario", Assert.Single(luigi.Incoming).Name);
        Assert.Equal("Luigi", Assert.Single(_friends.GetFriends(_mario.Id).Outgoing).Name);
    }

    [Fact]
    public async Task AcceptMakesFriendsNotifiesBothAndIsSaved()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();

        Assert.Equal(HubStatus.Ok, await _friends.AcceptAsync(_luigi.Id, _mario.Id));

        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
        // Un servizio nuovo rilegge il file.
        var reloaded = Service().GetFriends(_mario.Id);
        Assert.Equal("Luigi", Assert.Single(reloaded.Friends).Name);
    }

    [Fact]
    public async Task CrossedRequestBecomesFriendship()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();

        Assert.Equal(HubStatus.Ok, await _friends.RequestAsync(_luigi.Id, _mario.Id));

        Assert.Equal("Luigi", Assert.Single(_friends.GetFriends(_mario.Id).Friends).Name);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
    }

    [Fact]
    public async Task RefusedRequests()
    {
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, Guid.NewGuid()));
        var disabled = _server.AddUser("Bowser", enabled: false);
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, disabled.Id));
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, _mario.Id));
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        Assert.Equal(HubStatus.Conflict, await _friends.RequestAsync(_mario.Id, _luigi.Id));
    }

    [Fact]
    public async Task RequestsAreRateLimited()
    {
        for (var i = 0; i < 20; i++)
        {
            await _friends.RequestAsync(_mario.Id, Guid.NewGuid());
        }

        Assert.Equal(HubStatus.RateLimited, await _friends.RequestAsync(_mario.Id, _luigi.Id));
    }

    [Fact]
    public async Task AcceptOrDeclineWithoutRequestIsForbidden()
    {
        Assert.Equal(HubStatus.Forbidden, await _friends.AcceptAsync(_luigi.Id, _mario.Id));
        Assert.Equal(HubStatus.Forbidden, await _friends.DeclineAsync(_luigi.Id, _mario.Id));
    }

    [Fact]
    public async Task DeclineCancelAndRemoveNotifyBoth()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();
        Assert.Equal(HubStatus.Ok, await _friends.DeclineAsync(_luigi.Id, _mario.Id));
        Assert.Empty(_friends.GetFriends(_mario.Id).Outgoing);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));

        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        _server.Sent.Clear();
        Assert.Equal(HubStatus.Ok, await _friends.CancelAsync(_mario.Id, _luigi.Id));
        Assert.Empty(_friends.GetFriends(_luigi.Id).Incoming);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
        // Annullare una richiesta che non c'è non è un errore.
        Assert.Equal(HubStatus.Ok, await _friends.CancelAsync(_mario.Id, _luigi.Id));

        await MakeFriends(_mario, _luigi);
        Assert.Equal(HubStatus.Ok, await _friends.RemoveAsync(_luigi.Id, _mario.Id));
        Assert.Empty(_friends.GetFriends(_mario.Id).Friends);
        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-mario").Select(Type));
    }

    [Fact]
    public async Task FriendsAreSortedWithOnlineStateAndWithoutDeletedUsers()
    {
        await MakeFriends(_mario, _peach);
        await MakeFriends(_mario, _luigi);
        var daisy = _server.AddUser("Daisy");
        await MakeFriends(_mario, daisy);
        _server.Users.Remove(daisy.Id);

        var friends = _friends.GetFriends(_mario.Id).Friends;

        Assert.Equal(new[] { "Luigi", "Peach" }, friends.Select(f => f.Name));
        Assert.True(friends[0].Online);
        Assert.False(friends[1].Online);
        Assert.All(friends, f => Assert.Null(f.Party));
    }

    [Fact]
    public async Task SearchFindsNamesContainingTheText()
    {
        await MakeFriends(_mario, _luigi);
        await _friends.RequestAsync(_peach.Id, _mario.Id);
        _server.AddUser("Luisa", enabled: false);
        _server.AddUser("Waluigi");

        Assert.Empty(_friends.Search(_mario.Id, "l").Value!);
        Assert.Empty(_friends.Search(_mario.Id, "  ").Value!);

        var results = _friends.Search(_mario.Id, " LUI ").Value!;
        Assert.Equal(new[] { "Luigi", "Waluigi" }, results.Select(r => r.Name));
        Assert.Equal(new[] { FriendRelations.Friend, FriendRelations.None }, results.Select(r => r.Relation));
        Assert.Equal(FriendRelations.Incoming, Assert.Single(_friends.Search(_mario.Id, "pea").Value!).Relation);
        Assert.Equal(FriendRelations.Outgoing, Assert.Single(_friends.Search(_peach.Id, "mar").Value!).Relation);
        Assert.Empty(_friends.Search(_mario.Id, "mario").Value!);
    }

    [Fact]
    public void SearchReturnsAtMostTenAndIsRateLimited()
    {
        for (var i = 0; i < 12; i++)
        {
            _server.AddUser($"Toad {i:00}");
        }

        Assert.Equal(FriendService.MaxSearchResults, _friends.Search(_mario.Id, "toad").Value!.Count);
        for (var i = 1; i < 30; i++)
        {
            Assert.Equal(HubStatus.Ok, _friends.Search(_mario.Id, "toad").Status);
        }

        Assert.Equal(HubStatus.RateLimited, _friends.Search(_mario.Id, "toad").Status);
    }

    [Fact]
    public async Task NotifyFriendsReachesOnlyOnlineFriends()
    {
        await MakeFriends(_mario, _luigi);
        await MakeFriends(_mario, _peach);

        await _friends.NotifyFriendsAsync(_mario.Id);

        Assert.Equal(new[] { "FriendsChanged" }, _server.SentTo("s-luigi").Select(Type));
        Assert.Empty(_server.SentTo("s-mario"));
    }
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`FriendService` non esiste).

- [ ] **Step 4: `FriendService`**

`Hub/FriendService.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Amici e richieste (spec F §6.2–6.3): regole di <see cref="FriendGraph"/>,
/// file di <see cref="FriendStore"/>, nomi e sessioni da Jellyfin, avvisi
/// sul WebSocket. Sicuro tra thread.
/// </summary>
public sealed class FriendService(
    FriendStore store,
    IUserDirectory users,
    ISessionDirectory sessions,
    IEventSender sender,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<FriendService> logger)
{
    /// <summary>Lettere minime di una ricerca (spec F §6.2).</summary>
    public const int MinSearchLength = 2;

    /// <summary>Risultati al massimo di una ricerca (spec F §6.2).</summary>
    public const int MaxSearchResults = 10;

    private readonly Lock _lock = new();
    private FriendGraph? _graph;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private FriendGraph Graph
    {
        get
        {
            if (_graph is null)
            {
                _graph = store.Load();
                logger.LogInformation("Amici in {Path}", store.FilePath);
            }

            return _graph;
        }
    }

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Graph;
        }
    }

    public FriendsResponse GetFriends(Guid userId)
    {
        var online = OnlineUsers();
        lock (_lock)
        {
            var graph = Graph;
            var friends = graph.FriendsOf(userId)
                .Select(id => users.GetUser(id))
                .OfType<UserRef>()
                .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
                .Select(u => new FriendEntry(Id(u.Id), u.Name, online.Contains(u.Id), null))
                .ToList();
            return new FriendsResponse(
                friends,
                People(graph.IncomingOf(userId).Select(r => r.From)),
                People(graph.OutgoingOf(userId).Select(r => r.To)));
        }
    }

    public HubResult<IReadOnlyList<UserSearchResult>> Search(Guid userId, string? query)
    {
        var text = query?.Trim() ?? string.Empty;
        if (text.Length < MinSearchLength)
        {
            return HubResult<IReadOnlyList<UserSearchResult>>.Ok([]);
        }

        if (!limiter.TryAcquire(Id(userId), LimitTypes.Searches))
        {
            return HubResult<IReadOnlyList<UserSearchResult>>.Fail(HubStatus.RateLimited);
        }

        lock (_lock)
        {
            var graph = Graph;
            IReadOnlyList<UserSearchResult> results = users.GetUsers()
                .Where(u => u.Enabled && u.Id != userId && u.Name.Contains(text, StringComparison.OrdinalIgnoreCase))
                .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
                .Take(MaxSearchResults)
                .Select(u => new UserSearchResult(Id(u.Id), u.Name, RelationOf(graph, userId, u.Id)))
                .ToList();
            return HubResult<IReadOnlyList<UserSearchResult>>.Ok(results);
        }
    }

    /// <summary>from chiede l'amicizia a to.</summary>
    public async Task<HubStatus> RequestAsync(Guid from, Guid to)
    {
        if (!limiter.TryAcquire(Id(from), LimitTypes.FriendRequests))
        {
            return HubStatus.RateLimited;
        }

        if (users.GetUser(to) is not { Enabled: true })
        {
            return HubStatus.Conflict;
        }

        FriendRequestOutcome outcome;
        lock (_lock)
        {
            outcome = Graph.Request(from, to, time.GetUtcNow());
            if (outcome != FriendRequestOutcome.Rejected)
            {
                Persist();
            }
        }

        switch (outcome)
        {
            case FriendRequestOutcome.Sent:
                var name = users.GetUser(from)?.Name ?? string.Empty;
                await NotifyAsync(to, SocialEvent.FriendRequest(Id(from), name)).ConfigureAwait(false);
                return HubStatus.Ok;
            case FriendRequestOutcome.BecameFriends:
                await NotifyChangedAsync(from, to).ConfigureAwait(false);
                return HubStatus.Ok;
            default:
                return HubStatus.Conflict;
        }
    }

    /// <summary>user accetta la richiesta di from.</summary>
    public async Task<HubStatus> AcceptAsync(Guid user, Guid from)
    {
        FriendChange change;
        lock (_lock)
        {
            change = Graph.Accept(user, from);
            if (change == FriendChange.Done)
            {
                Persist();
            }
        }

        switch (change)
        {
            case FriendChange.Done:
                await NotifyChangedAsync(user, from).ConfigureAwait(false);
                return HubStatus.Ok;
            case FriendChange.Missing:
                return HubStatus.Forbidden;
            default:
                return HubStatus.Conflict;
        }
    }

    /// <summary>user rifiuta la richiesta di from: a from sparisce e basta.</summary>
    public Task<HubStatus> DeclineAsync(Guid user, Guid from) =>
        ChangeAsync(user, from, graph => graph.Decline(user, from), missing: HubStatus.Forbidden);

    /// <summary>user annulla la propria richiesta a to.</summary>
    public Task<HubStatus> CancelAsync(Guid user, Guid to) =>
        ChangeAsync(user, to, graph => graph.Cancel(user, to), missing: HubStatus.Ok);

    /// <summary>user toglie friend dagli amici, per tutti e due.</summary>
    public Task<HubStatus> RemoveAsync(Guid user, Guid friend) =>
        ChangeAsync(user, friend, graph => graph.Remove(user, friend), missing: HubStatus.Ok);

    /// <summary>
    /// Dice agli amici online di userId di rileggere gli amici (presenza,
    /// spec F §6.3).
    /// </summary>
    public Task NotifyFriendsAsync(Guid userId)
    {
        IReadOnlyList<Guid> friends;
        lock (_lock)
        {
            friends = Graph.FriendsOf(userId);
        }

        var online = OnlineUsers();
        return Task.WhenAll(friends.Where(online.Contains).Select(f => NotifyAsync(f, SocialEvent.FriendsChanged())));
    }

    private async Task<HubStatus> ChangeAsync(Guid a, Guid b, Func<FriendGraph, bool> change, HubStatus missing)
    {
        bool changed;
        lock (_lock)
        {
            changed = change(Graph);
            if (changed)
            {
                Persist();
            }
        }

        if (!changed)
        {
            return missing;
        }

        await NotifyChangedAsync(a, b).ConfigureAwait(false);
        return HubStatus.Ok;
    }

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        Graph.Prune(id => users.GetUser(id) is not null);
        try
        {
            store.Save(Graph);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Amici non salvati in {Path}", store.FilePath);
        }
    }

    private Task NotifyChangedAsync(Guid a, Guid b) =>
        Task.WhenAll(NotifyAsync(a, SocialEvent.FriendsChanged()), NotifyAsync(b, SocialEvent.FriendsChanged()));

    private async Task NotifyAsync(Guid userId, SocialEvent socialEvent)
    {
        var payload = JsonSerializer.Serialize(socialEvent);
        var targets = sessions.GetAppSessions().Where(s => s.UserId == userId).Select(s => s.SessionId).ToList();
        await Task.WhenAll(targets.Select(sessionId => SendAsync(sessionId, payload))).ConfigureAwait(false);
    }

    private async Task SendAsync(string sessionId, string payload)
    {
        try
        {
            // Mai il token della richiesta: l'avviso non si ferma con lei.
            await sender.TrySendAsync(sessionId, payload, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Avviso degli amici non inviato alla sessione {SessionId}", sessionId);
        }
    }

    private HashSet<Guid> OnlineUsers() => sessions.GetAppSessions().Select(s => s.UserId).ToHashSet();

    private List<PersonEntry> People(IEnumerable<Guid> ids) =>
        ids.Select(id => users.GetUser(id))
            .OfType<UserRef>()
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .Select(u => new PersonEntry(Id(u.Id), u.Name))
            .ToList();

    private static string RelationOf(FriendGraph graph, Guid me, Guid other) =>
        graph.AreFriends(me, other) ? FriendRelations.Friend
        : graph.HasRequest(other, me) ? FriendRelations.Incoming
        : graph.HasRequest(me, other) ? FriendRelations.Outgoing
        : FriendRelations.None;

    private static string Id(Guid id) => id.ToString("N");
}
```

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the friend service with search and notices (#6)"
```

---

### Task 5: presenza (`PresenceTracker`) e sessioni avviate

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PresenceTracker.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/WatchPartyHostedService.cs`
- Test: `…Tests/PresenceTrackerTests.cs`, `…Tests/WatchPartyHostedServiceTests.cs`

- [ ] **Step 1: test che falliscono**

`PresenceTrackerTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PresenceTrackerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FriendService _friends;
    private readonly PresenceTracker _presence;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;

    public PresenceTrackerTests()
    {
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _presence = new PresenceTracker(_friends, _time, NullLogger<PresenceTracker>.Instance);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose()
    {
        _presence.Dispose();
        _folder.Dispose();
    }

    [Fact]
    public async Task ChangesCloseTogetherBecomeOneNotice()
    {
        await _friends.RequestAsync(_mario.Id, _luigi.Id);
        await _friends.AcceptAsync(_luigi.Id, _mario.Id);
        _server.Sent.Clear();

        _presence.Changed(_mario.Id);
        _time.Advance(TimeSpan.FromSeconds(1));
        _presence.Changed(_mario.Id);
        Assert.Empty(_server.Sent);

        _time.Advance(PresenceTracker.Delay);
        Assert.Single(_server.SentTo("s-luigi"));

        // Dopo l'avviso, un cambio nuovo ne prepara un altro.
        _presence.Changed(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(2, _server.SentTo("s-luigi").Count);
    }

    [Fact]
    public void WithoutFriendsNobodyIsNotified()
    {
        _presence.Changed(_mario.Id);
        _time.Advance(PresenceTracker.Delay);
        Assert.Empty(_server.Sent);
    }
}
```

In `WatchPartyHostedServiceTests.cs`:
- aggiungi `using Microsoft.Extensions.Logging.Abstractions;` se manca (c'è già) e crea il servizio con amici e presenza. Sostituisci la riga `using var service = new WatchPartyHostedService(manager, hub, time, NullLogger<WatchPartyHostedService>.Instance);` con:

```csharp
        using var folder = new TempFolder();
        var friends = new FriendService(
            new FriendStore(folder.FriendsFile, NullLogger<FriendStore>.Instance),
            server, server, server, new RateLimiter(time), time, NullLogger<FriendService>.Instance);
        using var presence = new PresenceTracker(friends, time, NullLogger<PresenceTracker>.Instance);
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, time, NullLogger<WatchPartyHostedService>.Instance);
```

- in fondo alla stessa classe aggiungi:

```csharp
    [Fact]
    public async Task WonderFlixSessionsStartingOrEndingNotifyFriends()
    {
        var server = new FakeServer();
        var time = new FakeTimeProvider();
        var hub = new PartyHub(
            server, server, server, new PartyRegistry(), new ChatHistory(), new RateLimiter(time), time,
            NullLogger<PartyHub>.Instance);
        using var folder = new TempFolder();
        var friends = new FriendService(
            new FriendStore(folder.FriendsFile, NullLogger<FriendStore>.Instance),
            server, server, server, new RateLimiter(time), time, NullLogger<FriendService>.Instance);
        using var presence = new PresenceTracker(friends, time, NullLogger<PresenceTracker>.Instance);
        var mario = server.AddUser("Mario");
        var luigi = server.AddUser("Luigi");
        server.AddSession("s-luigi", luigi);
        await friends.RequestAsync(mario.Id, luigi.Id);
        await friends.AcceptAsync(luigi.Id, mario.Id);
        server.Sent.Clear();

        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        EventHandler<SessionEventArgs>? started = null;
        EventHandler<SessionEventArgs>? ended = null;
        stub.Handlers["add_SessionStarted"] = args =>
        {
            started = (EventHandler<SessionEventArgs>?)args[0];
            return null;
        };
        stub.Handlers["add_SessionEnded"] = args =>
        {
            ended = (EventHandler<SessionEventArgs>?)args[0];
            return null;
        };
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, time, NullLogger<WatchPartyHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);
        Assert.NotNull(started);
        Assert.NotNull(ended);
        SessionEventArgs Args(string client) => new()
        {
            SessionInfo = new SessionInfo(manager, NullLogger.Instance) { Id = "s-mario", Client = client, UserId = mario.Id },
        };

        started(manager, Args("Jellyfin Web"));
        time.Advance(PresenceTracker.Delay);
        Assert.Empty(server.Sent);

        started(manager, Args("WonderFlix"));
        time.Advance(PresenceTracker.Delay);
        Assert.Single(server.SentTo("s-luigi"));

        ended(manager, Args("WonderFlix"));
        time.Advance(PresenceTracker.Delay);
        Assert.Equal(2, server.SentTo("s-luigi").Count);

        await service.StopAsync(CancellationToken.None);
        Assert.Contains(stub.Calls, c => c.Name == "remove_SessionStarted");
    }
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`PresenceTracker`, costruttore del servizio).

- [ ] **Step 3: `PresenceTracker`**

`Hub/PresenceTracker.cs`:

```csharp
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Avvisa gli amici quando un utente va online o offline (spec F §6.3). I
/// cambi ravvicinati (riconnessioni, più dispositivi) diventano un solo
/// avviso, <see cref="Delay"/> dopo il primo: intanto le sessioni di
/// Jellyfin si sono assestate. Sicuro tra thread.
/// </summary>
public sealed class PresenceTracker(FriendService friends, TimeProvider time, ILogger<PresenceTracker> logger) : IDisposable
{
    /// <summary>Attesa tra il primo cambio e l'avviso agli amici.</summary>
    public static readonly TimeSpan Delay = TimeSpan.FromSeconds(2);

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, ITimer> _pending = [];

    /// <summary>Lo stato online di userId può essere cambiato.</summary>
    public void Changed(Guid userId)
    {
        lock (_lock)
        {
            if (_pending.ContainsKey(userId))
            {
                return;
            }

            _pending[userId] = time.CreateTimer(_ => Fire(userId), null, Delay, Timeout.InfiniteTimeSpan);
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var timer in _pending.Values)
            {
                timer.Dispose();
            }

            _pending.Clear();
        }
    }

    private void Fire(Guid userId)
    {
        lock (_lock)
        {
            if (_pending.Remove(userId, out var timer))
            {
                timer.Dispose();
            }
        }

        _ = NotifyAsync(userId);
    }

    private async Task NotifyAsync(Guid userId)
    {
        try
        {
            await friends.NotifyFriendsAsync(userId).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Presenza di {UserId} non comunicata agli amici", userId);
        }
    }
}
```

- [ ] **Step 4: servizio**

`WatchPartyHostedService.cs` (tutto il file):

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Toglie dai gruppi le sessioni finite, avvisa gli amici quando una
/// sessione WonderFlix si apre o si chiude (spec F §6.3) e, ogni
/// <see cref="CleanupInterval"/>, pulisce registro e storico dei gruppi
/// finiti (spec E §6.5).
/// </summary>
public sealed class WatchPartyHostedService(
    ISessionManager sessionManager,
    PartyHub hub,
    FriendService friends,
    PresenceTracker presence,
    TimeProvider time,
    ILogger<WatchPartyHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si puliscono i gruppi finiti.</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionStarted += OnSessionStarted;
        sessionManager.SessionEnded += OnSessionEnded;
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        logger.LogInformation("WonderFlix Watch Party {Version} avviato", typeof(Plugin).Assembly.GetName().Version);
        try
        {
            friends.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Amici non caricati all'avvio");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionStarted -= OnSessionStarted;
        sessionManager.SessionEnded -= OnSessionEnded;
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    // Gli eventi arrivano su un altro thread e poi la SessionInfo viene
    // chiusa: si legge subito quello che serve.
    private void OnSessionStarted(object? sender, SessionEventArgs e) =>
        PresenceChanged(e.SessionInfo.Client, e.SessionInfo.UserId);

    private void OnSessionEnded(object? sender, SessionEventArgs e)
    {
        var session = e.SessionInfo;
        var (id, client, userId) = (session.Id, session.Client, session.UserId);
        hub.RemoveSession(id);
        PresenceChanged(client, userId);
    }

    private void PresenceChanged(string? client, Guid userId)
    {
        if (string.Equals(client, WatchPartyProtocol.ClientName, StringComparison.Ordinal) && !userId.Equals(Guid.Empty))
        {
            presence.Changed(userId);
        }
    }

    private void Cleanup()
    {
        try
        {
            var removed = hub.Cleanup();
            if (removed > 0)
            {
                logger.LogDebug("Tolti {Count} watch party finiti", removed);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pulizia dei watch party non riuscita");
        }
    }
}
```

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): tell friends when someone goes online or offline (#6)"
```

---

### Task 6: adattatori, endpoint degli amici, servizi e versione 1.1.0

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinUserDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/FriendsController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `jellyfin-plugin-watch-party/meta.template.json`, `jellyfin-plugin-watch-party/README.md`
- Test: `…Tests/ServerAdapterTests.cs`, `…Tests/FriendsControllerTests.cs`, `…Tests/ServiceRegistrationTests.cs`, `…Tests/WatchPartyControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `ServerAdapterTests.cs` aggiungi gli using `Jellyfin.Data;`, `Jellyfin.Database.Implementations.Entities;`, `Jellyfin.Database.Implementations.Enums;`, `MediaBrowser.Controller.Library;` e il test:

```csharp
    [Fact]
    public void UsersComeFromTheUserManager()
    {
        var mario = new User("Mario", "provider", "reset");
        var bowser = new User("Bowser", "provider", "reset");
        bowser.SetPermission(PermissionKind.IsDisabled, true);
        var (manager, stub) = InterfaceStub<IUserManager>.Create();
        stub.Handlers["get_Users"] = _ => new[] { mario, bowser };
        stub.Handlers["GetUserById"] = args => (Guid)args[0]! == mario.Id ? mario : null;
        var directory = new JellyfinUserDirectory(manager);

        Assert.Equal(
            new[] { new UserRef(mario.Id, "Mario", true), new UserRef(bowser.Id, "Bowser", false) },
            directory.GetUsers());
        Assert.Equal(new UserRef(mario.Id, "Mario", true), directory.GetUser(mario.Id));
        Assert.Null(directory.GetUser(Guid.NewGuid()));
    }
```

`FriendsControllerTests.cs`:

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

public sealed class FriendsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _luigi = new("luigi", "provider", "reset");
    private readonly FriendService _friends;

    public FriendsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true);
        _server.Users[_luigi.Id] = new UserRef(_luigi.Id, "Luigi", true);
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    private FriendsController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new FriendsController(new FakeAuthorizationContext(auth), _friends)
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

    [Fact]
    public async Task RequestAcceptAndList()
    {
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_mario).SendRequest(_luigi.Id)));
        Assert.Equal(StatusCodes.Status409Conflict, Status(await Controller(_mario).SendRequest(_luigi.Id)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_luigi).AcceptRequest(_mario.Id)));

        var friends = (await Controller(_mario).GetFriends()).Value!;
        Assert.Equal("Luigi", Assert.Single(friends.Friends).Name);
    }

    [Fact]
    public async Task MissingRequestIsForbiddenAndCancelOrRemoveAreNoContent()
    {
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_luigi).AcceptRequest(_mario.Id)));
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_luigi).DeclineRequest(_mario.Id)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_mario).CancelRequest(_luigi.Id)));
        Assert.Equal(StatusCodes.Status204NoContent, Status(await Controller(_mario).RemoveFriend(_luigi.Id)));
    }

    [Fact]
    public async Task SearchReturnsResultsAndRateLimits()
    {
        var found = await Controller(_mario).Search("lui");
        var results = Assert.IsAssignableFrom<IReadOnlyList<UserSearchResult>>(Assert.IsType<OkObjectResult>(found.Result).Value);
        Assert.Equal("Luigi", Assert.Single(results).Name);

        for (var i = 1; i < 30; i++)
        {
            await Controller(_mario).Search("lui");
        }

        Assert.Equal(StatusCodes.Status429TooManyRequests, Status((await Controller(_mario).Search("lui")).Result!));
    }
}
```

`ServiceRegistrationTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ServiceRegistrationTests
{
    [Fact]
    public void AllServicesResolve()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(InterfaceStub<ISessionManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<ISyncPlayManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IUserManager>.Create().Proxy);
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.GetTempPath();
        services.AddSingleton(paths);

        new PluginServiceRegistrator().RegisterServices(services, null!);
        using var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetRequiredService<FriendService>());
        Assert.NotNull(provider.GetRequiredService<PresenceTracker>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "friends.json"),
            provider.GetRequiredService<FriendStore>().FilePath);
        Assert.Single(provider.GetServices<IHostedService>());
    }
}
```

In `WatchPartyControllerTests.InfoReportsVersionProtocolAndFeatures` cambia `"1.0.0"` in `"1.1.0"`.

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`JellyfinUserDirectory`, `FriendsController` non esistono).

- [ ] **Step 3: adattatore degli utenti**

`Server/JellyfinUserDirectory.cs`:

```csharp
using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Gli utenti di Jellyfin.</summary>
public sealed class JellyfinUserDirectory(IUserManager userManager) : IUserDirectory
{
    public IReadOnlyList<UserRef> GetUsers() => userManager.Users.Select(ToRef).ToList();

    public UserRef? GetUser(Guid userId) => userManager.GetUserById(userId) is { } user ? ToRef(user) : null;

    private static UserRef ToRef(User user) =>
        new(user.Id, user.Username, !user.HasPermission(PermissionKind.IsDisabled));
}
```

- [ ] **Step 4: endpoint degli amici**

`Api/FriendsController.cs`:

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
/// Endpoint degli amici (spec F §6.7). Chi chiama è l'utente
/// dell'autenticazione. Come il resto del plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class FriendsController(IAuthorizationContext authorizationContext, FriendService friends) : ControllerBase
{
    /// <summary>Amici con il loro stato, richieste in arrivo e inviate.</summary>
    [HttpGet("Friends")]
    public async Task<ActionResult<FriendsResponse>> GetFriends() =>
        friends.GetFriends(await CallerAsync().ConfigureAwait(false));

    /// <summary>Utenti il cui nome contiene q (almeno 2 lettere), al massimo 10.</summary>
    [HttpGet("Users/Search")]
    public async Task<ActionResult<IReadOnlyList<UserSearchResult>>> Search([FromQuery] string? q)
    {
        var result = friends.Search(await CallerAsync().ConfigureAwait(false), q);
        return result.Status == HubStatus.Ok ? Ok(result.Value) : Failure(result.Status);
    }

    [HttpPost("Friends/Requests/{userId:guid}")]
    public async Task<ActionResult> SendRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.RequestAsync(caller, userId).ConfigureAwait(false));
    }

    [HttpPost("Friends/Requests/{userId:guid}/Accept")]
    public async Task<ActionResult> AcceptRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.AcceptAsync(caller, userId).ConfigureAwait(false));
    }

    [HttpPost("Friends/Requests/{userId:guid}/Decline")]
    public async Task<ActionResult> DeclineRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.DeclineAsync(caller, userId).ConfigureAwait(false));
    }

    /// <summary>Annulla la propria richiesta a userId.</summary>
    [HttpDelete("Friends/Requests/{userId:guid}")]
    public async Task<ActionResult> CancelRequest([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.CancelAsync(caller, userId).ConfigureAwait(false));
    }

    [HttpDelete("Friends/{userId:guid}")]
    public async Task<ActionResult> RemoveFriend([FromRoute] Guid userId)
    {
        var caller = await CallerAsync().ConfigureAwait(false);
        return Failure(await friends.RemoveAsync(caller, userId).ConfigureAwait(false));
    }

    /// <summary>204 se riuscita, altrimenti il codice dell'esito.</summary>
    private ActionResult Failure(HubStatus status) => status switch
    {
        HubStatus.Ok => NoContent(),
        HubStatus.Forbidden => StatusCode(StatusCodes.Status403Forbidden),
        HubStatus.Conflict => Conflict(),
        HubStatus.RateLimited => StatusCode(StatusCodes.Status429TooManyRequests),
        _ => BadRequest(),
    };

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
```

(`Conflict()` restituisce un `ConflictResult`, che è uno `StatusCodeResult` con 409: va bene per il test.)

- [ ] **Step 5: servizi**

`PluginServiceRegistrator.cs`, aggiungi gli using `MediaBrowser.Common.Configuration;` e `Microsoft.Extensions.Logging;`, poi dopo la riga di `IEventSender`:

```csharp
        serviceCollection.AddSingleton<IUserDirectory, JellyfinUserDirectory>();
        serviceCollection.AddSingleton(provider => new FriendStore(
            FriendStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<FriendStore>>()));
        serviceCollection.AddSingleton<FriendService>();
        serviceCollection.AddSingleton<PresenceTracker>();
```

- [ ] **Step 6: versione, descrizione, README**

- `Jellyfin.Plugin.WonderFlixWatchParty.csproj`: `<Version>1.1.0</Version>`.
- `Plugin.cs`: `Description => "Names, chat, reactions and friends for SyncPlay watch parties in WonderFlix.";` e nel commento della classe "(spec E, spec F)". Il commento "Non ha impostazioni." resta.
- `meta.template.json`: `"description": "Names, chat, reactions and friends for SyncPlay watch parties in WonderFlix."`, `"overview": "WonderFlix watch party: names, chat, reactions, friends"`.
- `README.md`: nel primo paragrafo aggiungi "e tiene la lista amici (spec F, `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`)"; nell'elenco puntato aggiungi:

```markdown
- **Dati:** amicizie e richieste stanno in
  `plugins/configurations/WonderFlixWatchParty/friends.json` (non nella
  cartella del plugin, che cambia a ogni versione). Un file illeggibile
  diventa `friends.json.bad` e il plugin riparte vuoto.
```

e nell'esempio di "Installazione a mano" usa `1.1.0` / `WonderFlix Watch Party_1.1.0.0`.

- [ ] **Step 7: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning. Se `services.AddLogging()` non compila, il pacchetto `Microsoft.Extensions.Logging` non arriva dai riferimenti: aggiungi `<PackageReference Include="Microsoft.Extensions.Logging" Version="9.0.10" />` al solo progetto di test e segnalalo.

Run anche: `bash jellyfin-plugin-watch-party/pack.sh 1.1.0`
Expected: crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.1.0.0/` con la dll e `meta.json` (`artifacts/` è ignorata da git).

- [ ] **Step 8: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): expose the friends endpoints in plugin 1.1.0 (#6)"
```

---

### Task 7: plugin 1.1.0 sul server vero (orchestratore, nessun subagent)

Il piano **si ferma qui** finché il plugin non gira sul server. Lo fa l'orchestratore (accesso `ssh ultra` autorizzato dall'utente); nessun file del repository cambia.

- [ ] **Step 1:** nel worktree: `bash jellyfin-plugin-watch-party/pack.sh 1.1.0` → cartella `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.1.0.0/`.
- [ ] **Step 2:** chiedere all'utente se si può riavviare Jellyfin adesso (nessuno sta guardando). Senza il suo ok non si riavvia.
- [ ] **Step 3:** copia e riavvio:

```bash
scp -r "jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.1.0.0" ultra:.apps/jellyfin/data/plugins/
ssh ultra app-jellyfin restart
```

La cartella `WonderFlix Watch Party_1.0.0.0` installata dal Catalogo resta: Jellyfin carica la versione più alta e segna l'altra come superata. **Prima di installare la 1.1.0 dal Catalogo (piano 12b) la cartella copiata a mano va tolta** (spostata in `~/wfwp-backup/`, come nel 10c).
- [ ] **Step 4:** controllo nei log di Jellyfin (cartella da trovare con `ssh ultra 'ls -d ~/.apps/jellyfin/*/log* ~/.apps/jellyfin/log* 2>/dev/null'`), sul file più recente:

```bash
ssh ultra 'grep -h "WonderFlix\|Amici in" "$(ls -t <cartella dei log>/*.log | head -1)" | tail -10'
```

Atteso: `Loaded plugin: "WonderFlix Watch Party" "1.1.0.0"`, `WonderFlix Watch Party 1.1.0.0 avviato` e `Amici in …/plugins/configurations/WonderFlixWatchParty/friends.json`. Nessuna eccezione del plugin (se `IApplicationPaths` non si risolve, il log lo dice all'avvio: in quel caso si passa a `IServerApplicationPaths` nel Task 6 e si ripete).
- [ ] **Step 5:** esito all'utente; poi si riparte con il gruppo B. Le app 0.5.1 installate continuano a funzionare (protocollo 1 invariato).

---

## Gruppo B — nucleo sociale nell'app

### Task 8: testi degli amici

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan12a_test.dart`

- [ ] **Step 1: test che fallisce**

`test/app/l10n_plan12a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 12a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.friendsTitle, 'Amici');
    expect(it.friendsClose, 'Chiudi');
    expect(it.friendsSearchHint, 'Cerca per nome');
    expect(it.friendsSearchEmpty, 'Nessun utente trovato');
    expect(it.friendsAdd, 'Aggiungi');
    expect(it.friendsSent, 'Inviata');
    expect(it.friendsCancel, 'Annulla');
    expect(it.friendsAccept, 'Accetta');
    expect(it.friendsDecline, 'Rifiuta');
    expect(it.friendsAlready, 'Amici');
    expect(it.friendsRequests(3), 'Richieste (3)');
    expect(it.friendsPending, 'In attesa');
    expect(it.friendsEmpty,
        'Nessun amico ancora. Cerca qualcuno per nome qui sopra.');
    expect(it.friendsMore, 'Altre azioni');
    expect(it.friendsRemove, 'Rimuovi dagli amici');
    expect(it.friendsRemoveConfirm, 'Conferma rimozione');
    expect(it.friendsUnavailable, 'Amici non disponibili');
    expect(it.friendsActionFailed, 'Operazione non riuscita');
    expect(it.friendsTooMany, 'Troppe richieste, riprova più tardi');
    expect(it.friendsOnline, 'Online');
    expect(it.friendsOffline, 'Offline');
    expect(it.friendRequestTitle('Luigi'), 'Luigi vuole essere tuo amico');
    expect(en.friendsTitle, 'Friends');
    expect(en.friendsClose, 'Close');
    expect(en.friendsSearchHint, 'Search by name');
    expect(en.friendsSearchEmpty, 'No users found');
    expect(en.friendsAdd, 'Add');
    expect(en.friendsSent, 'Sent');
    expect(en.friendsCancel, 'Cancel');
    expect(en.friendsAccept, 'Accept');
    expect(en.friendsDecline, 'Decline');
    expect(en.friendsAlready, 'Friends');
    expect(en.friendsRequests(3), 'Requests (3)');
    expect(en.friendsPending, 'Pending');
    expect(en.friendsEmpty, 'No friends yet. Search for someone by name above.');
    expect(en.friendsMore, 'More actions');
    expect(en.friendsRemove, 'Remove friend');
    expect(en.friendsRemoveConfirm, 'Confirm removal');
    expect(en.friendsUnavailable, 'Friends unavailable');
    expect(en.friendsActionFailed, 'Something went wrong');
    expect(en.friendsTooMany, 'Too many requests, try again later');
    expect(en.friendsOnline, 'Online');
    expect(en.friendsOffline, 'Offline');
    expect(en.friendRequestTitle('Luigi'), 'Luigi wants to be your friend');
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan12a_test.dart`
Expected: errori di compilazione (`friendsTitle` non esiste).

- [ ] **Step 3: testi**

In `l10n/app_it.arb` sostituisci l'ultima riga di chiave `  "playerRecapSkipped": "Riassunto saltato"` con:

```json
  "playerRecapSkipped": "Riassunto saltato",
  "friendsTitle": "Amici",
  "friendsClose": "Chiudi",
  "friendsSearchHint": "Cerca per nome",
  "friendsSearchEmpty": "Nessun utente trovato",
  "friendsAdd": "Aggiungi",
  "friendsSent": "Inviata",
  "friendsCancel": "Annulla",
  "friendsAccept": "Accetta",
  "friendsDecline": "Rifiuta",
  "friendsAlready": "Amici",
  "friendsRequests": "Richieste ({count})",
  "@friendsRequests": {"placeholders": {"count": {"type": "int"}}},
  "friendsPending": "In attesa",
  "friendsEmpty": "Nessun amico ancora. Cerca qualcuno per nome qui sopra.",
  "friendsMore": "Altre azioni",
  "friendsRemove": "Rimuovi dagli amici",
  "friendsRemoveConfirm": "Conferma rimozione",
  "friendsUnavailable": "Amici non disponibili",
  "friendsActionFailed": "Operazione non riuscita",
  "friendsTooMany": "Troppe richieste, riprova più tardi",
  "friendsOnline": "Online",
  "friendsOffline": "Offline",
  "friendRequestTitle": "{name} vuole essere tuo amico",
  "@friendRequestTitle": {"placeholders": {"name": {"type": "String"}}}
```

In `l10n/app_en.arb` sostituisci `  "playerRecapSkipped": "Recap skipped"` con:

```json
  "playerRecapSkipped": "Recap skipped",
  "friendsTitle": "Friends",
  "friendsClose": "Close",
  "friendsSearchHint": "Search by name",
  "friendsSearchEmpty": "No users found",
  "friendsAdd": "Add",
  "friendsSent": "Sent",
  "friendsCancel": "Cancel",
  "friendsAccept": "Accept",
  "friendsDecline": "Decline",
  "friendsAlready": "Friends",
  "friendsRequests": "Requests ({count})",
  "friendsPending": "Pending",
  "friendsEmpty": "No friends yet. Search for someone by name above.",
  "friendsMore": "More actions",
  "friendsRemove": "Remove friend",
  "friendsRemoveConfirm": "Confirm removal",
  "friendsUnavailable": "Friends unavailable",
  "friendsActionFailed": "Something went wrong",
  "friendsTooMany": "Too many requests, try again later",
  "friendsOnline": "Online",
  "friendsOffline": "Offline",
  "friendRequestTitle": "{name} wants to be your friend"
```

Poi: `flutter gen-l10n`.

- [ ] **Step 4: verifica**

Run: `flutter test test/app/l10n_plan12a_test.dart` → PASS. Poi `flutter analyze` e `flutter test` (tutto verde, 1256).

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan12a_test.dart
git commit -m "feat: add the friends strings (#6)"
```

---

### Task 9: modelli e API sociali (`lib/core/social/`)

**Files:**
- Modify: `lib/core/jellyfin/jellyfin_http.dart` (`delete`)
- Modify: `lib/core/party_channel/party_channel_models.dart`
- Create: `lib/core/social/social_models.dart`, `lib/core/social/social_api.dart`
- Test: `test/core/social/social_models_test.dart`, `test/core/social/social_api_test.dart`, `test/core/party_channel/party_channel_models_test.dart`

- [ ] **Step 1: test che falliscono**

`test/core/social/social_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_models.dart';

void main() {
  test('Info: versione e funzioni; senza Features nessuna', () {
    final info = SocialPluginInfo.fromJson({
      'Version': '1.1.0',
      'Protocol': 1,
      'Features': ['friends', 7, 'parties'],
    });
    expect(info.version, '1.1.0');
    expect(info.features, {'friends', 'parties'});
    expect(
        SocialPluginInfo.fromJson({'Version': '1.0.0', 'Protocol': 1})
            .features,
        isEmpty);
  });

  test('amici e richieste', () {
    final snapshot = FriendsSnapshot.fromJson({
      'Friends': [
        {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'Party': null},
        {
          'UserId': 'u4',
          'Name': 'Daisy',
          'Online': false,
          'Party': {'GroupId': 'g1', 'Title': 'Dune'},
        },
      ],
      'Incoming': [
        {'UserId': 'u3', 'Name': 'Peach'},
      ],
      'Outgoing': [],
    });
    expect(snapshot.friends.map((f) => f.name), ['Luigi', 'Daisy']);
    expect(snapshot.friends.first.online, isTrue);
    expect(snapshot.friends.first.party, isNull);
    expect(snapshot.friends.last.party?.title, 'Dune');
    expect(snapshot.incoming.single.userId, 'u3');
    expect(snapshot.outgoing, isEmpty);
  });

  test('risultati della ricerca; relazione sconosciuta = nessuna', () {
    final result = UserSearchResult.fromJson(
        {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'Incoming'});
    expect(result.relation, FriendRelation.incoming);
    expect(
        UserSearchResult.fromJson(
                {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'Boh'})
            .relation,
        FriendRelation.none);
  });

  test('avvisi del plugin', () {
    final request = parseSocialEvent(
        '{"Protocol":1,"Type":"FriendRequest","FromUserId":"u2",'
        '"FromName":"Luigi"}');
    expect(request, isA<FriendRequestEvent>());
    expect((request! as FriendRequestEvent).fromName, 'Luigi');
    expect(parseSocialEvent('{"Protocol":1,"Type":"FriendsChanged"}'),
        isA<FriendsChangedEvent>());
    // Un evento del canale, un altro protocollo, JSON rotto: niente.
    expect(parseSocialEvent('{"Protocol":1,"Type":"Chat","Text":"ciao"}'),
        isNull);
    expect(parseSocialEvent('{"Protocol":2,"Type":"FriendsChanged"}'),
        isNull);
    expect(parseSocialEvent('{rotto'), isNull);
    expect(parseSocialEvent('{"Protocol":1,"Type":"FriendRequest"}'), isNull);
  });
}
```

`test/core/social/social_api_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SocialApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SocialApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('info', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Version': '1.1.0',
          'Protocol': 1,
          'Features': ['friends'],
        });
    final info = await api.info();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Info');
    expect(info.features, {'friends'});
  });

  test('amici', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'Party': null},
          ],
          'Incoming': [],
          'Outgoing': [],
        });
    final snapshot = await api.friends();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Friends');
    expect(snapshot.friends.single.name, 'Luigi');
  });

  test('ricerca', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'UserId': 'u2', 'Name': 'Luigi', 'Relation': 'None'},
        ]);
    final results = await api.search('lui');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Users/Search');
    expect(adapter.requests.single.queryParameters, {'q': 'lui'});
    expect(results.single.relation, FriendRelation.none);
  });

  test('azioni', () async {
    await api.request('u2');
    await api.accept('u2');
    await api.decline('u2');
    await api.cancel('u2');
    await api.remove('u2');
    expect(
        adapter.requests.map((r) => '${r.method} ${r.path}'),
        [
          'POST /WonderFlixWatchParty/Friends/Requests/u2',
          'POST /WonderFlixWatchParty/Friends/Requests/u2/Accept',
          'POST /WonderFlixWatchParty/Friends/Requests/u2/Decline',
          'DELETE /WonderFlixWatchParty/Friends/Requests/u2',
          'DELETE /WonderFlixWatchParty/Friends/u2',
        ]);
  });

  test('errori', () async {
    Future<SocialFailure?> failureOf(FakeResponse response) async {
      adapter.handler = (_) => response;
      try {
        await api.request('u2');
        return null;
      } on SocialException catch (error) {
        return error.failure;
      }
    }

    expect(await failureOf(const FakeResponse(404)), SocialFailure.unavailable);
    expect(await failureOf(const FakeResponse(403)), SocialFailure.forbidden);
    expect(await failureOf(const FakeResponse(409)), SocialFailure.conflict);
    expect(
        await failureOf(const FakeResponse(429)), SocialFailure.rateLimited);
    expect(await failureOf(const FakeResponse(500)), SocialFailure.network);
    adapter.handler = (_) => throw const SocketException('giù');
    await expectLater(
        api.friends(),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.network)));
    adapter.handler = (_) => const FakeResponse(200, {'Version': 3});
    await expectLater(
        api.info(),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.network)));
  });
}
```

In `test/core/party_channel/party_channel_models_test.dart` aggiungi (con `import 'package:logging/logging.dart';` se manca):

```dart
  test('gli avvisi degli amici si scartano senza scrivere nel log', () {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    expect(parsePartyEvent('{"Protocol":1,"Type":"FriendsChanged"}'), isNull);
    expect(
        parsePartyEvent('{"Protocol":1,"Type":"FriendRequest",'
            '"FromUserId":"u2","FromName":"Luigi"}'),
        isNull);
    expect(records, isEmpty);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/social test/core/party_channel/party_channel_models_test.dart`
Expected: errori di compilazione (`social_models.dart` non esiste) e, per il canale, `records` non vuoto.

- [ ] **Step 3: `delete` con esiti silenziosi**

In `lib/core/jellyfin/jellyfin_http.dart` sostituisci `delete` con:

```dart
  Future<dynamic> delete(String path,
          {Map<String, dynamic>? query, Set<int> quietStatuses = const {}}) =>
      _send(() => dio.delete<dynamic>(path, queryParameters: query),
          quietStatuses: quietStatuses);
```

- [ ] **Step 4: il canale scarta in silenzio gli avvisi sociali**

In `lib/core/party_channel/party_channel_models.dart`, sopra `parsePartyEvent`:

```dart
/// Tipi degli avvisi del plugin che non riguardano il canale del gruppo
/// (spec F §6.8): li legge `parseSocialEvent`, qui si scartano in silenzio.
const socialEventTypes = {'FriendRequest', 'FriendsChanged'};
```

e dentro `parsePartyEvent`, subito dopo il blocco che controlla `protocol`:

```dart
    if (socialEventTypes.contains(json['Type'])) return null;
```

- [ ] **Step 5: modelli**

`lib/core/social/social_models.dart`:

```dart
import 'dart:convert';

import 'package:logging/logging.dart';

import '../party_channel/party_channel_models.dart';

final _log = Logger('social');

/// Funzioni del plugin oltre al canale dello spec E (spec F §6.7).
abstract final class PluginFeatures {
  static const friends = 'friends';
  static const parties = 'parties';
}

/// Risposta di `GET /WonderFlixWatchParty/Info`, con le funzioni.
class SocialPluginInfo {
  const SocialPluginInfo({required this.version, required this.features});

  factory SocialPluginInfo.fromJson(Map<String, dynamic> json) =>
      SocialPluginInfo(
        version: json['Version'] as String,
        features: {
          for (final feature in json['Features'] as List? ?? const [])
            if (feature is String) feature,
        },
      );

  final String version;
  final Set<String> features;
}

/// Relazione con un utente trovato (spec F §6.2).
enum FriendRelation {
  none('None'),
  friend('Friend'),
  incoming('Incoming'),
  outgoing('Outgoing');

  const FriendRelation(this.wire);

  final String wire;

  static FriendRelation fromWire(Object? value) =>
      values.firstWhere((r) => r.wire == value, orElse: () => none);
}

/// Il party visibile in cui sta un amico (dal piano 12b).
class FriendParty {
  const FriendParty({required this.groupId, required this.title});

  final String groupId;
  final String title;
}

class FriendEntry {
  const FriendEntry({
    required this.userId,
    required this.name,
    required this.online,
    this.party,
  });

  factory FriendEntry.fromJson(Map<String, dynamic> json) {
    final party = json['Party'];
    return FriendEntry(
      userId: json['UserId'] as String,
      name: json['Name'] as String,
      online: json['Online'] as bool? ?? false,
      party: party is Map<String, dynamic>
          ? FriendParty(
              groupId: party['GroupId'] as String,
              title: party['Title'] as String)
          : null,
    );
  }

  final String userId;
  final String name;
  final bool online;
  final FriendParty? party;
}

/// Chi ha mandato o ricevuto una richiesta in sospeso.
class PersonEntry {
  const PersonEntry({required this.userId, required this.name});

  factory PersonEntry.fromJson(Map<String, dynamic> json) => PersonEntry(
      userId: json['UserId'] as String, name: json['Name'] as String);

  final String userId;
  final String name;
}

/// Risposta di `GET Friends`.
class FriendsSnapshot {
  const FriendsSnapshot({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });

  factory FriendsSnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) => [
          for (final raw in json[key] as List? ?? const [])
            raw as Map<String, dynamic>,
        ];
    return FriendsSnapshot(
      friends: [for (final raw in list('Friends')) FriendEntry.fromJson(raw)],
      incoming: [for (final raw in list('Incoming')) PersonEntry.fromJson(raw)],
      outgoing: [for (final raw in list('Outgoing')) PersonEntry.fromJson(raw)],
    );
  }

  static const empty = FriendsSnapshot();

  final List<FriendEntry> friends;
  final List<PersonEntry> incoming;
  final List<PersonEntry> outgoing;
}

class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.name,
    required this.relation,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        relation: FriendRelation.fromWire(json['Relation']),
      );

  final String userId;
  final String name;
  final FriendRelation relation;
}

/// Avvisi del plugin fuori dal canale di un gruppo (spec F §6.8).
sealed class SocialEvent {
  const SocialEvent();
}

/// Qualcuno ci ha chiesto l'amicizia.
final class FriendRequestEvent extends SocialEvent {
  const FriendRequestEvent({required this.fromUserId, required this.fromName});

  final String fromUserId;
  final String fromName;
}

/// Amici o richieste sono cambiati: si rilegge `GET Friends`.
final class FriendsChangedEvent extends SocialEvent {
  const FriendsChangedEvent();
}

/// Legge un avviso del plugin (stringa JSON dal WebSocket). `null` se non è
/// un avviso sociale; una riga nel log se è malformato.
SocialEvent? parseSocialEvent(Object? raw) {
  try {
    final json = raw is String ? jsonDecode(raw) : raw;
    if (json is! Map<String, dynamic> ||
        json['Protocol'] != partyChannelProtocol) {
      return null;
    }
    switch (json['Type']) {
      case 'FriendRequest':
        return FriendRequestEvent(
          fromUserId: json['FromUserId'] as String,
          fromName: json['FromName'] as String,
        );
      case 'FriendsChanged':
        return const FriendsChangedEvent();
    }
    return null;
  } on Object catch (error) {
    // Solo il tipo: il messaggio può citare il JSON.
    _log.info('avviso del plugin non valido: ${error.runtimeType}');
    return null;
  }
}
```

- [ ] **Step 6: API**

`lib/core/social/social_api.dart`:

```dart
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'social_models.dart';

final _log = Logger('social');

/// Perché una chiamata sociale al plugin non è riuscita (spec F §6.7).
enum SocialFailure {
  /// 404: la rotta non esiste, cioè plugin assente o vecchio (il plugin non
  /// risponde mai 404 di suo).
  unavailable,

  /// 400, 401, 403: non ammessa (es. una richiesta che non c'è più).
  forbidden,

  /// 409: non ammessa adesso (già amici, richiesta doppia, limiti).
  conflict,

  /// 429: troppe richieste in poco tempo.
  rateLimited,

  /// Rete assente, errore del server o risposta di forma inattesa.
  network,
}

class SocialException implements Exception {
  const SocialException(this.failure);

  final SocialFailure failure;

  @override
  String toString() => 'SocialException(${failure.name})';
}

/// Endpoint sociali del plugin "WonderFlix Watch Party" (spec F §6.7).
/// Lancia solo [SocialException].
class SocialApi {
  SocialApi(this._http);

  static const _base = '/WonderFlixWatchParty';

  /// Esiti previsti (plugin assente, già amici, troppe richieste): nel log
  /// come info, non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {404, 409, 429};

  final JellyfinHttp _http;

  Future<SocialPluginInfo> info() => _call(() async => SocialPluginInfo
      .fromJson(asJsonMap(await _http.get('$_base/Info', quietStatuses: _quiet))));

  Future<FriendsSnapshot> friends() => _call(() async => FriendsSnapshot
      .fromJson(asJsonMap(await _http.get('$_base/Friends', quietStatuses: _quiet))));

  /// Utenti il cui nome contiene [query] (il plugin vuole almeno 2 lettere).
  Future<List<UserSearchResult>> search(String query) => _call(() async {
        final json = await _http.get('$_base/Users/Search',
            query: {'q': query}, quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            UserSearchResult.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<void> request(String userId) => _call(() => _http
      .post('$_base/Friends/Requests/$userId', quietStatuses: _quiet));

  Future<void> accept(String userId) => _call(() => _http.post(
      '$_base/Friends/Requests/$userId/Accept',
      quietStatuses: _quiet));

  Future<void> decline(String userId) => _call(() => _http.post(
      '$_base/Friends/Requests/$userId/Decline',
      quietStatuses: _quiet));

  /// Annulla la nostra richiesta a [userId].
  Future<void> cancel(String userId) => _call(() => _http
      .delete('$_base/Friends/Requests/$userId', quietStatuses: _quiet));

  Future<void> remove(String userId) => _call(
      () => _http.delete('$_base/Friends/$userId', quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const SocialException(SocialFailure.unavailable);
    } on UnauthorizedException {
      throw const SocialException(SocialFailure.forbidden);
    } on ForbiddenException {
      throw const SocialException(SocialFailure.forbidden);
    } on ServerErrorException catch (error) {
      throw SocialException(switch (error.statusCode) {
        400 => SocialFailure.forbidden,
        409 => SocialFailure.conflict,
        429 => SocialFailure.rateLimited,
        _ => SocialFailure.network,
      });
    } on ApiException {
      throw const SocialException(SocialFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta sociale del plugin non valida: ${error.runtimeType}');
      throw const SocialException(SocialFailure.network);
    }
  }
}
```

- [ ] **Step 7: verifica**

Run: `flutter test test/core/social test/core/party_channel` → PASS.
Run: `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 8: commit**

```bash
git add lib/core test/core
git commit -m "feat: add the social models and plugin api (#6)"
```

---

### Task 10: funzioni del plugin, avvisi sociali e diagnostica

**Files:**
- Create: `lib/features/social/social_providers.dart`
- Modify: `lib/features/settings/diagnostics.dart`
- Create: `test/support/social_fakes.dart`
- Test: `test/features/social/social_providers_test.dart`, `test/features/settings/diagnostics_test.dart`

- [ ] **Step 1: finti per i test**

`test/support/social_fakes.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import 'fake_session_controller.dart';
import 'test_data.dart';

/// Plugin finto per gli amici. Di default è assente ([info] lancia 404).
class FakeSocialApi implements SocialApi {
  /// Risposta di [info]; `null` = plugin assente (404).
  SocialPluginInfo? pluginInfo;

  /// Errore di [info], se valorizzato (prima di [pluginInfo]).
  SocialFailure? infoFailure;

  FriendsSnapshot snapshot = FriendsSnapshot.empty;

  /// Risultati di [search], per testo cercato.
  final searchResults = <String, List<UserSearchResult>>{};

  /// Errore della prossima chiamata (tranne [info]); poi si azzera.
  SocialFailure? nextFailure;

  /// Se valorizzato, [friends] e [search] aspettano che si completi (la
  /// risposta è quella del momento della chiamata).
  Completer<void>? friendsGate;
  Completer<void>? searchGate;

  /// Chiamate in ordine: `info`, `friends`, `search lui`, `request u2`, …
  final calls = <String>[];

  /// Plugin presente con [features].
  void install({Set<String> features = const {PluginFeatures.friends}}) =>
      pluginInfo = SocialPluginInfo(version: '1.1.0', features: features);

  void _fail() {
    final failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    throw SocialException(failure);
  }

  @override
  Future<SocialPluginInfo> info() async {
    calls.add('info');
    final failure = infoFailure;
    if (failure != null) throw SocialException(failure);
    final info = pluginInfo;
    if (info == null) {
      throw const SocialException(SocialFailure.unavailable);
    }
    return info;
  }

  @override
  Future<FriendsSnapshot> friends() async {
    calls.add('friends');
    final result = snapshot;
    await friendsGate?.future;
    _fail();
    return result;
  }

  @override
  Future<List<UserSearchResult>> search(String query) async {
    calls.add('search $query');
    final result = searchResults[query] ?? const <UserSearchResult>[];
    await searchGate?.future;
    _fail();
    return result;
  }

  @override
  Future<void> request(String userId) async {
    calls.add('request $userId');
    _fail();
  }

  @override
  Future<void> accept(String userId) async {
    calls.add('accept $userId');
    _fail();
  }

  @override
  Future<void> decline(String userId) async {
    calls.add('decline $userId');
    _fail();
  }

  @override
  Future<void> cancel(String userId) async {
    calls.add('cancel $userId');
    _fail();
  }

  @override
  Future<void> remove(String userId) async {
    calls.add('remove $userId');
    _fail();
  }
}

/// Funzioni del plugin fisse, senza chiamate.
class FakeSocialAvailability extends SocialAvailability {
  FakeSocialAvailability([this.initial = const SocialFeatures(friends: true)]);

  final SocialFeatures initial;

  @override
  SocialFeatures build() => initial;

  @override
  Future<void> refresh() async {}

  void set(SocialFeatures features) => state = features;
}

FriendEntry testFriend(String userId, String name, {bool online = false}) =>
    FriendEntry(userId: userId, name: name, online: online);

PersonEntry testPerson(String userId, String name) =>
    PersonEntry(userId: userId, name: name);

UserSearchResult testSearchResult(String userId, String name,
        [FriendRelation relation = FriendRelation.none]) =>
    UserSearchResult(userId: userId, name: name, relation: relation);

/// Come arriva dal WebSocket una richiesta di amicizia.
PartyChannelReceived friendRequestReceived(String userId, String name) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'FriendRequest',
      'FromUserId': userId,
      'FromName': name,
    }));

PartyChannelReceived friendsChangedReceived() => PartyChannelReceived(
    jsonEncode({'Protocol': 1, 'Type': 'FriendsChanged'}));

/// Provider per i test degli amici: utente [testUser] collegato, eventi del
/// WebSocket da [events], plugin [api], funzioni [features]. Con
/// `session: false` la sessione la sovrascrive il test (es. `AppShell`).
List<Override> socialTestOverrides(
  FakeSocialApi api, {
  Stream<ServerEvent> events = const Stream.empty(),
  SocialFeatures features = const SocialFeatures(friends: true),
  bool session = true,
}) =>
    [
      if (session)
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      watchPartyEventsProvider.overrideWithValue(events),
      socialApiProvider.overrideWithValue(api),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ];
```

(compila solo insieme a `lib/features/social/social_providers.dart`, Step 4.)

- [ ] **Step 2: test che falliscono**

`test/features/social/social_providers_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container(
      {SessionState session = const SessionSignedIn(testUser)}) {
    final c = ProviderContainer.test(overrides: [
      sessionControllerProvider.overrideWith(() => FakeSessionController(session)),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      socialApiProvider.overrideWithValue(api),
    ]);
    c.listen(socialAvailabilityProvider, (_, _) {});
    return c;
  }

  test('senza utente o senza watch party: nessuna funzione, nessuna chiamata',
      () async {
    api.install();
    final signedOut = container(session: const SessionSignedOut());
    await pumpEventQueue();
    expect(signedOut.read(socialAvailabilityProvider), SocialFeatures.none);
    final noAccess = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(noAccess.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, isEmpty);
  });

  test('Info con gli amici: funzione attiva', () async {
    api.install();
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true));
    expect(api.calls, ['info']);
  });

  test('plugin assente: nessuna funzione', () async {
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
  });

  test('alla riconnessione rilegge Info; un errore di rete non cambia nulla',
      () async {
    api.install();
    final c = container();
    await pumpEventQueue();
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(api.calls, ['info'], reason: 'la prima connessione non conta');

    api.infoFailure = SocialFailure.network;
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider).friends, isTrue);

    api
      ..infoFailure = null
      ..pluginInfo = null;
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, ['info', 'info', 'info']);
  });

  test('avvisi sociali dal WebSocket', () async {
    final c = container();
    final received = <SocialEvent>[];
    final subscription = c.read(socialEventsProvider).listen(received.add);
    addTearDown(subscription.cancel);

    events
      ..add(friendRequestReceived('u2', 'Luigi'))
      ..add(const PartyChannelReceived('{"Protocol":1,"Type":"Chat"}'))
      ..add(const ServerConnected(true))
      ..add(friendsChangedReceived());
    await pumpEventQueue();

    expect(received, hasLength(2));
    expect((received.first as FriendRequestEvent).fromName, 'Luigi');
    expect(received.last, isA<FriendsChangedEvent>());
  });
}
```

In `test/features/settings/diagnostics_test.dart`:
- import di `package:wonderflix/core/social/social_models.dart`, `package:wonderflix/features/social/social_providers.dart` e `../../support/social_fakes.dart`;
- l'helper `container` prende anche `{FakeSocialApi? socialApi}` e aggiunge agli override `socialApiProvider.overrideWithValue(socialApi ?? FakeSocialApi()),` (senza, dio chiamerebbe davvero `media.example.com`);
- nuovi test:

```dart
  test('describePluginFeatures', () {
    expect(describePluginFeatures(const {}), 'nessuna');
    expect(describePluginFeatures(const {PluginFeatures.friends}), 'amici');
    expect(
        describePluginFeatures(
            const {PluginFeatures.friends, PluginFeatures.parties}),
        'amici, party');
  });

  test('buildDiagnostics: riga delle funzioni del plugin', () {
    final text = buildDiagnostics(
      appVersion: '0.1.0',
      windowsVersion: 'w',
      serverVersion: '10.11.9',
      player: const PlayerSettings(),
      discord: const DiscordSettings(),
      recentErrors: const [],
      pluginFeatures: 'amici',
    );
    expect(text, contains('Funzioni del plugin: amici\n'));
  });

  test('collectDiagnostics: funzioni del plugin, se c\'è', () async {
    final present = await container(FakeSystemApi(),
        socialApi: FakeSocialApi()..install());
    expect(await present.read(collectDiagnosticsProvider)(),
        contains('Funzioni del plugin: amici\n'));
    final absent = await container(FakeSystemApi());
    expect(await absent.read(collectDiagnosticsProvider)(),
        isNot(contains('Funzioni del plugin')));
  });
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/social test/features/settings/diagnostics_test.dart`
Expected: errori di compilazione (`social_providers.dart` non esiste; `social_fakes.dart` non compila).

- [ ] **Step 4: provider sociali**

`lib/features/social/social_providers.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../watch_party/watch_party_providers.dart';

final _log = Logger('social');

final socialApiProvider =
    Provider<SocialApi>((ref) => SocialApi(ref.watch(jellyfinHttpProvider)));

/// Funzioni del plugin che l'app può usare (spec F §7.2).
class SocialFeatures {
  const SocialFeatures({this.friends = false, this.parties = false});

  static const none = SocialFeatures();

  final bool friends;
  final bool parties;

  @override
  bool operator ==(Object other) =>
      other is SocialFeatures &&
      other.friends == friends &&
      other.parties == parties;

  @override
  int get hashCode => Object.hash(friends, parties);

  @override
  String toString() => 'SocialFeatures(friends: $friends, parties: $parties)';
}

/// Chiede `Info` al plugin dopo il login e a ogni riconnessione del
/// WebSocket (spec F §7.2). Senza utente, senza accesso ai watch party o
/// senza plugin: nessuna funzione, e l'app si comporta come la 0.5.1.
class SocialAvailability extends Notifier<SocialFeatures> {
  @override
  SocialFeatures build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null || !ref.watch(syncPlayAccessProvider).canJoin) {
      return SocialFeatures.none;
    }
    final subscription = ref.watch(watchPartyEventsProvider).listen((event) {
      if (event is ServerConnected && event.isReconnect) unawaited(refresh());
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    unawaited(Future.microtask(refresh));
    return SocialFeatures.none;
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    try {
      final info = await ref.read(socialApiProvider).info();
      if (!ref.mounted) return;
      state = SocialFeatures(
        friends: info.features.contains(PluginFeatures.friends),
        parties: info.features.contains(PluginFeatures.parties),
      );
    } on SocialException catch (error) {
      // Plugin assente, vecchio o senza permesso: niente funzioni. Un
      // errore di rete lascia quelle che c'erano.
      if (ref.mounted && error.failure != SocialFailure.network) {
        state = SocialFeatures.none;
      }
    } on Object catch (error) {
      // Anche un provider che non si può creare (es. nei test).
      _log.info('funzioni del plugin non verificate: ${error.runtimeType}');
    }
  }
}

final socialAvailabilityProvider =
    NotifierProvider<SocialAvailability, SocialFeatures>(
        SocialAvailability.new);

/// Avvisi del plugin fuori dal canale di un gruppo (spec F §7.3).
final socialEventsProvider = Provider<Stream<SocialEvent>>((ref) => ref
    .watch(watchPartyEventsProvider)
    .map((event) =>
        event is PartyChannelReceived ? parseSocialEvent(event.payload) : null)
    .where((event) => event != null)
    .cast<SocialEvent>());
```

- [ ] **Step 5: diagnostica**

In `lib/features/settings/diagnostics.dart`:
- import di `../../core/social/social_models.dart` e `../social/social_providers.dart`;
- dopo `describePartyChannel`:

```dart
/// Funzioni del plugin per la diagnostica (spec F §7.2).
String describePluginFeatures(Set<String> features) {
  final names = [
    if (features.contains(PluginFeatures.friends)) 'amici',
    if (features.contains(PluginFeatures.parties)) 'party',
  ];
  return names.isEmpty ? 'nessuna' : names.join(', ');
}
```

- `buildDiagnostics` prende anche `String? pluginFeatures` (dopo `watchPartyPlugin`) e, subito dopo la riga del plugin:

```dart
  if (pluginFeatures != null) {
    buffer.writeln('Funzioni del plugin: $pluginFeatures');
  }
```

- in `collectDiagnosticsProvider`, dopo il blocco di `watchPartyPlugin`:

```dart
          String? pluginFeatures;
          try {
            final info = await ref
                .read(socialApiProvider)
                .info()
                .timeout(PartyChannel.infoTimeout);
            pluginFeatures = describePluginFeatures(info.features);
          } on Object catch (error) {
            _log.info(
                'funzioni del plugin non disponibili: ${error.runtimeType}');
          }
```

e passa `pluginFeatures: pluginFeatures,` a `buildDiagnostics`.

- [ ] **Step 6: verifica**

Run: `flutter test test/features/social test/features/settings/diagnostics_test.dart` → PASS.
Run: `flutter analyze` → nessun problema; `flutter test` → tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/features/social lib/features/settings/diagnostics.dart test/features/social test/features/settings/diagnostics_test.dart test/support/social_fakes.dart
git commit -m "feat: read the plugin features and its social notices (#6)"
```

---

## Gruppo C — stato degli amici

### Task 11: `FriendsController`

**Files:**
- Create: `lib/features/friends/friends_controller.dart`
- Test: `test/features/friends/friends_controller_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/friends/friends_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friends_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi()
      ..snapshot = FriendsSnapshot(
        friends: [testFriend('u2', 'Luigi', online: true)],
        incoming: [testPerson('u3', 'Peach')],
      );
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container(
      {SocialFeatures features = const SocialFeatures(friends: true)}) {
    final c = ProviderContainer.test(
        overrides: socialTestOverrides(api,
            events: events.stream, features: features));
    c.listen(friendsControllerProvider, (_, _) {});
    return c;
  }

  test('carica amici e richieste appena nasce', () async {
    final c = container();
    await pumpEventQueue();
    final state = c.read(friendsControllerProvider);
    expect(state.loaded, isTrue);
    expect(state.snapshot.friends.single.name, 'Luigi');
    expect(state.incomingCount, 1);
    expect(api.calls, ['friends']);
  });

  test('senza la funzione amici non chiama il plugin', () async {
    final c = container(features: SocialFeatures.none);
    await pumpEventQueue();
    await c.read(friendsControllerProvider.notifier).reload();
    expect(c.read(friendsControllerProvider).loaded, isFalse);
    expect(api.calls, isEmpty);
  });

  test('rilegge agli avvisi del plugin e alla riconnessione', () async {
    container();
    await pumpEventQueue();
    events.add(friendRequestReceived('u4', 'Daisy'));
    await pumpEventQueue();
    events.add(friendsChangedReceived());
    await pumpEventQueue();
    events
      ..add(const ServerConnected(false))
      ..add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, ['friends', 'friends', 'friends', 'friends']);
  });

  test('un caricamento fallito lascia l\'elenco di prima', () async {
    final c = container();
    await pumpEventQueue();
    api.nextFailure = SocialFailure.network;
    await c.read(friendsControllerProvider.notifier).reload();
    final state = c.read(friendsControllerProvider);
    expect(state.failed, isTrue);
    expect(state.loaded, isTrue);
    expect(state.snapshot.friends.single.name, 'Luigi');
  });

  test('vale solo la risposta dell\'ultimo caricamento', () async {
    final c = container();
    await pumpEventQueue();
    final gate = api.friendsGate = Completer<void>();
    final slow = c.read(friendsControllerProvider.notifier).reload();
    api
      ..friendsGate = null
      ..snapshot = FriendsSnapshot.empty;
    await c.read(friendsControllerProvider.notifier).reload();
    gate.complete();
    await slow;
    expect(c.read(friendsControllerProvider).snapshot.friends, isEmpty);
  });

  test('azioni: chiamano il plugin, rileggono e dicono come è andata',
      () async {
    final c = container();
    await pumpEventQueue();
    final friends = c.read(friendsControllerProvider.notifier);
    expect(await friends.request('u4'), isNull);
    expect(await friends.accept('u3'), isNull);
    expect(await friends.decline('u3'), isNull);
    expect(await friends.cancel('u4'), isNull);
    expect(await friends.remove('u2'), isNull);
    api.nextFailure = SocialFailure.conflict;
    expect(await friends.request('u4'), SocialFailure.conflict);
    await pumpEventQueue();
    expect(api.calls.where((call) => call != 'friends'), [
      'request u4',
      'accept u3',
      'decline u3',
      'cancel u4',
      'remove u2',
      'request u4',
    ]);
    expect(api.calls.where((call) => call == 'friends'), hasLength(7));
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/friends/friends_controller_test.dart`
Expected: errori di compilazione (`friends_controller.dart` non esiste).

- [ ] **Step 3: `FriendsController`**

`lib/features/friends/friends_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';

final _log = Logger('social');

/// Amici e richieste dell'utente (spec F §8.1).
class FriendsState {
  const FriendsState({
    this.snapshot = FriendsSnapshot.empty,
    this.loaded = false,
    this.failed = false,
  });

  final FriendsSnapshot snapshot;

  /// Almeno un caricamento è riuscito.
  final bool loaded;

  /// L'ultimo caricamento non è riuscito (resta l'elenco di prima).
  final bool failed;

  /// Richieste in arrivo: il numero sull'icona Amici.
  int get incomingCount => snapshot.incoming.length;
}

/// Legge amici e richieste dal plugin: alla nascita, a ogni avviso
/// `FriendRequest`/`FriendsChanged`, a ogni riconnessione del WebSocket e
/// dopo ogni azione. Niente controlli periodici.
class FriendsController extends Notifier<FriendsState> {
  /// Cresce a ogni caricamento: vale solo la risposta dell'ultimo.
  int _loads = 0;

  @override
  FriendsState build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _loads++;
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.friends))) {
      return const FriendsState();
    }
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is FriendRequestEvent || event is FriendsChangedEvent) {
        unawaited(reload());
      }
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      // Gli avvisi persi mentre il WebSocket era giù.
      if (event is ServerConnected && event.isReconnect) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    unawaited(Future.microtask(reload));
    return const FriendsState();
  }

  /// Rilegge amici e richieste dal plugin.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(socialAvailabilityProvider).friends) return;
    final load = ++_loads;
    try {
      final snapshot = await ref.read(socialApiProvider).friends();
      if (!ref.mounted || load != _loads) return;
      state = FriendsState(snapshot: snapshot, loaded: true);
    } on Object catch (error) {
      _log.info('amici non caricati: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
      if (!ref.mounted || load != _loads) return;
      state = FriendsState(
          snapshot: state.snapshot, loaded: state.loaded, failed: true);
    }
  }

  Future<SocialFailure?> request(String userId) =>
      _act((api) => api.request(userId));

  Future<SocialFailure?> accept(String userId) =>
      _act((api) => api.accept(userId));

  Future<SocialFailure?> decline(String userId) =>
      _act((api) => api.decline(userId));

  Future<SocialFailure?> cancel(String userId) =>
      _act((api) => api.cancel(userId));

  Future<SocialFailure?> remove(String userId) =>
      _act((api) => api.remove(userId));

  /// Esegue un'azione e rilegge, anche se non è riuscita (nel frattempo
  /// lo stato può essere cambiato). `null` se è riuscita.
  Future<SocialFailure?> _act(Future<void> Function(SocialApi api) action) async {
    SocialFailure? failure;
    try {
      await action(ref.read(socialApiProvider));
    } on SocialException catch (error) {
      failure = error.failure;
    } on Object catch (error) {
      _log.info('azione sugli amici non riuscita: ${error.runtimeType}');
      failure = SocialFailure.network;
    }
    if (ref.mounted) unawaited(reload());
    return failure;
  }
}

final friendsControllerProvider =
    NotifierProvider<FriendsController, FriendsState>(FriendsController.new);
```

- [ ] **Step 4: verifica**

Run: `flutter test test/features/friends/friends_controller_test.dart` → PASS.
Run: `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/features/friends test/features/friends
git commit -m "feat: keep friends and requests in sync with the plugin (#6)"
```

---

### Task 12: ricerca (`FriendSearch`) e richiesta appena arrivata (`FriendRequestNotices`)

**Files:**
- Create: `lib/features/friends/friend_search.dart`
- Create: `lib/features/friends/friend_request_notices.dart`
- Test: `test/features/friends/friend_search_test.dart`, `test/features/friends/friend_request_notices_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/friends/friend_search_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/friends/friend_search.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() {
    api = FakeSocialApi()
      ..searchResults['lu'] = [testSearchResult('u9', 'Lucia')]
      ..searchResults['lui'] = [testSearchResult('u2', 'Luigi')];
  });

  ProviderContainer container() {
    final c = ProviderContainer.test(overrides: socialTestOverrides(api));
    c.listen(friendSearchProvider, (_, _) {});
    return c;
  }

  test('cerca 300 ms dopo l\'ultima lettera, da 2 lettere', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('l');
      async.elapse(FriendSearch.debounce);
      expect(api.calls, isEmpty);
      expect(c.read(friendSearchProvider).active, isFalse);

      search.setQuery('lu');
      async.elapse(const Duration(milliseconds: 200));
      search.setQuery(' lui ');
      expect(c.read(friendSearchProvider).searching, isTrue);
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();

      expect(api.calls, ['search lui']);
      final state = c.read(friendSearchProvider);
      expect(state.query, 'lui');
      expect(state.results.single.name, 'Luigi');
      expect(state.searching, isFalse);
    });
  });

  test('la risposta di una ricerca superata si scarta', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      final gate = api.searchGate = Completer<void>();
      search.setQuery('lu');
      async.elapse(FriendSearch.debounce);
      api.searchGate = null;
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      gate.complete();
      async.flushMicrotasks();
      expect(c.read(friendSearchProvider).results.single.name, 'Luigi');
    });
  });

  test('sotto 2 lettere i risultati spariscono', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      search.setQuery('l');
      expect(c.read(friendSearchProvider).results, isEmpty);
      expect(c.read(friendSearchProvider).active, isFalse);
    });
  });

  test('errore: lo dice e tiene i risultati; rerun ripete', () {
    fakeAsync((async) {
      final c = container();
      final search = c.read(friendSearchProvider.notifier);
      search.setQuery('lui');
      async.elapse(FriendSearch.debounce);
      async.flushMicrotasks();
      api.nextFailure = SocialFailure.rateLimited;
      unawaited(search.rerun());
      async.flushMicrotasks();
      expect(c.read(friendSearchProvider).failure, SocialFailure.rateLimited);
      expect(c.read(friendSearchProvider).results.single.name, 'Luigi');
      unawaited(search.rerun());
      async.flushMicrotasks();
      expect(c.read(friendSearchProvider).failure, isNull);
      expect(api.calls, ['search lui', 'search lui', 'search lui']);
    });
  });
}
```

`test/features/friends/friend_request_notices_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friend_request_notices.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  ProviderContainer container(
      {SocialFeatures features = const SocialFeatures(friends: true)}) {
    final c = ProviderContainer.test(
        overrides: socialTestOverrides(api,
            events: events.stream, features: features));
    c.listen(friendRequestNoticesProvider, (_, _) {});
    return c;
  }

  test('mostra la richiesta per 10 s', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider)?.fromName, 'Luigi');
      async.elapse(FriendRequestNotices.showFor);
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('non con il player aperto; aprirlo la toglie', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      final player = c.read(playerActiveProvider.notifier)..enter();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);

      player.leave();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNotNull);
      player.enter();
      // enter/leave pubblicano lo stato in un microtask.
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('accettata o rifiutata altrove: se ne va', () {
    fakeAsync((async) {
      api.snapshot =
          FriendsSnapshot(incoming: [testPerson('u2', 'Luigi')]);
      final c = container();
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNotNull);

      api.snapshot = FriendsSnapshot.empty;
      events.add(friendsChangedReceived());
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });

  test('senza la funzione amici: niente', () {
    fakeAsync((async) {
      final c = container(features: SocialFeatures.none);
      async.flushMicrotasks();
      events.add(friendRequestReceived('u2', 'Luigi'));
      async.flushMicrotasks();
      expect(c.read(friendRequestNoticesProvider), isNull);
    });
  });
}
```

(se `playerActiveProvider.enter()`/`leave()` hanno condizioni diverse da "entra/esce", adatta il test a come si usano in `player_screen.dart` e segnalalo.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/friends`
Expected: errori di compilazione (`friend_search.dart`, `friend_request_notices.dart` non esistono).

- [ ] **Step 3: `FriendSearch`**

`lib/features/friends/friend_search.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../social/social_providers.dart';

/// Ricerca di utenti nel pannello Amici (spec F §8.1, §8.3).
class FriendSearchState {
  const FriendSearchState({
    this.query = '',
    this.results = const [],
    this.searching = false,
    this.failure,
  });

  /// Testo cercato, senza spazi ai lati.
  final String query;
  final List<UserSearchResult> results;

  /// Una ricerca sta per partire o è in corso.
  final bool searching;

  /// Perché l'ultima ricerca non è riuscita; `null` se è riuscita.
  final SocialFailure? failure;

  /// Il pannello mostra i risultati al posto delle liste.
  bool get active => query.length >= FriendSearch.minLength;
}

class FriendSearch extends Notifier<FriendSearchState> {
  /// Attesa dall'ultima lettera alla ricerca.
  static const debounce = Duration(milliseconds: 300);

  /// Lettere minime, come nel plugin (spec F §6.2).
  static const minLength = 2;

  Timer? _timer;

  /// Cresce a ogni ricerca e a ogni testo nuovo: vale solo l'ultima.
  int _runs = 0;

  @override
  FriendSearchState build() {
    ref.onDispose(() => _timer?.cancel());
    return const FriendSearchState();
  }

  void setQuery(String text) {
    final query = text.trim();
    if (query == state.query) return;
    _timer?.cancel();
    _runs++;
    if (query.length < minLength) {
      state = FriendSearchState(query: query);
      return;
    }
    state = FriendSearchState(
        query: query, results: state.results, searching: true);
    _timer = Timer(debounce, () => unawaited(_run(query)));
  }

  /// Ripete la ricerca corrente (dopo un'azione su un risultato). Il
  /// pannello può essersi chiuso nel frattempo.
  Future<void> rerun() async {
    if (ref.mounted && state.active) await _run(state.query);
  }

  Future<void> _run(String query) async {
    final run = ++_runs;
    try {
      final results = await ref.read(socialApiProvider).search(query);
      if (!ref.mounted || run != _runs) return;
      state = FriendSearchState(query: query, results: results);
    } on Object catch (error) {
      if (!ref.mounted || run != _runs) return;
      state = FriendSearchState(
        query: query,
        results: state.results,
        failure: error is SocialException ? error.failure : SocialFailure.network,
      );
    }
  }
}

/// Vive finché il pannello è aperto.
final friendSearchProvider =
    NotifierProvider.autoDispose<FriendSearch, FriendSearchState>(
        FriendSearch.new);
```

- [ ] **Step 4: `FriendRequestNotices`**

`lib/features/friends/friend_request_notices.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import 'friends_controller.dart';

/// Richiesta di amicizia appena arrivata, per la scheda in alto a destra
/// (spec F §8.4): per [showFor], non con il player aperto. Il numero
/// sull'icona Amici resta comunque.
class FriendRequestNotices extends Notifier<FriendRequestEvent?> {
  static const showFor = Duration(seconds: 10);

  Timer? _timer;

  @override
  FriendRequestEvent? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _timer?.cancel();
    _timer = null;
    ref.onDispose(() => _timer?.cancel());
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.friends))) {
      return null;
    }
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is FriendRequestEvent) _show(event);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    ref.listen(playerActiveProvider, (_, active) {
      if (active) dismiss();
    });
    // Accettata o rifiutata altrove (pannello, altro dispositivo): c'era
    // tra le richieste in arrivo e non c'è più.
    ref.listen(friendsControllerProvider.select((s) => s.snapshot.incoming),
        (previous, incoming) {
      final shown = state;
      if (shown == null) return;
      bool has(List<PersonEntry>? people) =>
          people?.any((p) => p.userId == shown.fromUserId) ?? false;
      if (has(previous) && !has(incoming)) dismiss();
    });
    return null;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = null;
  }

  void _show(FriendRequestEvent event) {
    if (ref.read(playerActiveProvider)) return;
    _timer?.cancel();
    state = event;
    _timer = Timer(showFor, dismiss);
  }
}

final friendRequestNoticesProvider =
    NotifierProvider<FriendRequestNotices, FriendRequestEvent?>(
        FriendRequestNotices.new);
```

- [ ] **Step 5: verifica**

Run: `flutter test test/features/friends` → PASS.
Run: `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib/features/friends test/features/friends
git commit -m "feat: search users and surface new friend requests (#6)"
```

---

## Gruppo D — interfaccia

### Task 13: il pannello Amici (contenuto)

**Files:**
- Modify: `lib/app/theme.dart` (colore `online`)
- Create: `lib/features/friends/friends_panel.dart`
- Test: `test/features/friends/friends_panel_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/friends/friends_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friend_search.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<void> pumpPanel(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
        ),
      ),
      overrides: socialTestOverrides(api),
    );
    // Il primo caricamento parte da un microtask.
    await tester.pump();
  }

  testWidgets('amici: prima gli online, poi in ordine; pallino verde',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [
      testFriend('u5', 'Zelda'),
      testFriend('u2', 'Luigi', online: true),
      testFriend('u4', 'daisy'),
    ]);
    await pumpPanel(tester);

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('Luigi'), lessThan(y('daisy')));
    expect(y('daisy'), lessThan(y('Zelda')));
    expect(find.byKey(const Key('online-dot')), findsOneWidget);
    expect(find.text('AMICI'), findsOneWidget);
    expect(find.textContaining('RICHIESTE'), findsNothing);
  });

  testWidgets('nessun amico: invito a cercare', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Nessun amico ancora. Cerca qualcuno per nome qui sopra.'),
        findsOneWidget);
  });

  testWidgets('richieste: accetta, rifiuta, annulla', (tester) async {
    api.snapshot = FriendsSnapshot(
      incoming: [testPerson('u3', 'Peach')],
      outgoing: [testPerson('u4', 'Daisy')],
    );
    await pumpPanel(tester);
    expect(find.text('RICHIESTE (2)'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);

    await tester.tap(find.text('Accetta'));
    await tester.pump();
    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    await tester.tap(find.text('Annulla'));
    await tester.pump();

    expect(api.calls.where((call) => call != 'friends'),
        ['accept u3', 'decline u3', 'cancel u4']);
  });

  testWidgets('ricerca: l\'azione giusta per ogni risultato, poi rilegge',
      (tester) async {
    api.searchResults['lu'] = [
      testSearchResult('u2', 'Luigi'),
      testSearchResult('u6', 'Lucia', FriendRelation.outgoing),
      testSearchResult('u7', 'Ludovico', FriendRelation.incoming),
      testSearchResult('u8', 'Lucky', FriendRelation.friend),
    ];
    await pumpPanel(tester);

    await tester.enterText(find.byKey(const Key('friends-search')), 'lu');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();

    Finder inRow(String userId, String text) => find.descendant(
        of: find.byKey(ValueKey('search-$userId')), matching: find.text(text));
    expect(inRow('u2', 'Aggiungi'), findsOneWidget);
    expect(inRow('u6', 'Inviata'), findsOneWidget);
    expect(inRow('u6', 'Annulla'), findsOneWidget);
    expect(inRow('u7', 'Accetta'), findsOneWidget);
    expect(inRow('u8', 'Amici'), findsOneWidget);
    expect(find.text('AMICI'), findsNothing, reason: 'liste nascoste');

    await tester.tap(inRow('u2', 'Aggiungi'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, containsAllInOrder(['search lu', 'request u2', 'search lu']));
  });

  testWidgets('ricerca senza risultati', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byKey(const Key('friends-search')), 'zz');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();
    expect(find.text('Nessun utente trovato'), findsOneWidget);
  });

  testWidgets('rimozione: conferma per 4 s', (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await pumpPanel(tester);

    Future<void> askRemoval() async {
      await tester.tap(find.byTooltip('Altre azioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi dagli amici'));
      await tester.pumpAndSettle();
    }

    await askRemoval();
    expect(find.byKey(const Key('friend-remove-confirm')), findsOneWidget);
    await tester.pump(FriendsPanel.removeConfirmFor);
    expect(find.byKey(const Key('friend-remove-confirm')), findsNothing);
    expect(api.calls, isNot(contains('remove u2')));

    await askRemoval();
    await tester.tap(find.byKey(const Key('friend-remove-confirm')));
    await tester.pump();
    expect(api.calls, contains('remove u2'));
  });

  testWidgets('caricamento fallito: Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    await tester.pump();
    expect(find.text('Amici non disponibili'), findsOneWidget);

    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Luigi'), findsOneWidget);
  });

  testWidgets('azione rifiutata: lo dice', (tester) async {
    api.snapshot = FriendsSnapshot(incoming: [testPerson('u3', 'Peach')]);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.rateLimited;
    await tester.tap(find.text('Accetta'));
    await tester.pumpAndSettle();
    expect(find.text('Troppe richieste, riprova più tardi'), findsOneWidget);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/friends/friends_panel_test.dart`
Expected: errori di compilazione (`friends_panel.dart` non esiste).

- [ ] **Step 3: colore "online"**

In `lib/app/theme.dart`, in `WfColors` dopo `error`:

```dart
  /// Pallino degli amici online (spec F §8.3).
  static const online = Color(0xFF5BBF6A);
```

- [ ] **Step 4: pannello**

`lib/features/friends/friends_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../social/social_providers.dart';
import '../watch_party/party_badge.dart';
import 'friend_search.dart';
import 'friends_controller.dart';

/// Pannello Amici aperto o chiuso (spec F §8.3). Non dipende da niente:
/// lo legge anche la gestione di Esc. Si azzera quando nessuno lo guarda
/// più (es. la shell smontata al logout).
class FriendsPanelController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Apre il pannello e rilegge gli amici.
  void open() {
    if (state) return;
    state = true;
    unawaited(ref.read(friendsControllerProvider.notifier).reload());
  }

  void close() => state = false;

  void toggle() => state ? close() : open();
}

final friendsPanelProvider =
    NotifierProvider.autoDispose<FriendsPanelController, bool>(
        FriendsPanelController.new);

/// Il pannello si vede: aperto e con la funzione amici del plugin.
final friendsPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(friendsPanelProvider) &&
    ref.watch(socialAvailabilityProvider.select((f) => f.friends)));

/// Online prima, poi in ordine alfabetico (spec F §8.3).
List<FriendEntry> sortFriends(List<FriendEntry> friends) => [...friends]
  ..sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// Esegue un'azione sugli amici; se non riesce lo dice con una snackbar
/// (spec F §8.1).
Future<void> runFriendAction(
    BuildContext context, Future<SocialFailure?> Function() action) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = await action();
  if (failure == null) return;
  messenger?.showSnackBar(SnackBar(
      content: Text(failure == SocialFailure.rateLimited
          ? l.friendsTooMany
          : l.friendsActionFailed)));
}

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);

/// Contenuto del pannello Amici (spec F §8.3): ricerca, richieste, amici.
class FriendsPanel extends ConsumerStatefulWidget {
  const FriendsPanel({super.key});

  /// Larghezza, e quota massima della finestra.
  static const width = 360.0;
  static const maxWidthFraction = 0.9;

  /// Per quanto resta "Conferma rimozione".
  static const removeConfirmFor = Duration(seconds: 4);

  @override
  ConsumerState<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends ConsumerState<FriendsPanel> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final searching = ref.watch(friendSearchProvider.select((s) => s.active));
    return Material(
      key: const Key('friends-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.friendsTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: l.friendsClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () =>
                      ref.read(friendsPanelProvider.notifier).close(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const Key('friends-search'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l.friendsSearchHint,
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                isDense: true,
              ),
              onChanged: (text) =>
                  ref.read(friendSearchProvider.notifier).setQuery(text),
            ),
          ),
          Expanded(
            child: searching ? const _SearchResults() : const _FriendLists(),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final search = ref.watch(friendSearchProvider);
    if (search.results.isEmpty) {
      if (search.searching) return const SizedBox.shrink();
      return _Note(switch (search.failure) {
        null => l.friendsSearchEmpty,
        SocialFailure.rateLimited => l.friendsTooMany,
        _ => l.friendsActionFailed,
      });
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final result in search.results)
          _PersonRow(
            key: ValueKey('search-${result.userId}'),
            name: result.name,
            trailing: _SearchAction(result: result),
          ),
      ],
    );
  }
}

/// Azione su un risultato della ricerca, secondo la relazione.
class _SearchAction extends ConsumerWidget {
  const _SearchAction({required this.result});

  final UserSearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final friends = ref.read(friendsControllerProvider.notifier);
    final search = ref.read(friendSearchProvider.notifier);
    // Dopo l'azione la ricerca si ripete: la relazione è cambiata.
    void run(Future<SocialFailure?> Function() action) =>
        unawaited(() async {
          await runFriendAction(context, action);
          await search.rerun();
        }());
    final id = result.userId;
    return switch (result.relation) {
      FriendRelation.none => _ActionButton(
          label: l.friendsAdd, onPressed: () => run(() => friends.request(id))),
      FriendRelation.incoming => _ActionButton(
          label: l.friendsAccept,
          onPressed: () => run(() => friends.accept(id))),
      FriendRelation.outgoing => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.friendsSent, style: _mutedStyle),
            _ActionButton(
                label: l.friendsCancel,
                muted: true,
                onPressed: () => run(() => friends.cancel(id))),
          ],
        ),
      FriendRelation.friend => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.check, size: 16, color: WfColors.gold),
            const SizedBox(width: 4),
            Text(l.friendsAlready, style: _mutedStyle),
          ],
        ),
    };
  }
}

class _FriendLists extends ConsumerWidget {
  const _FriendLists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final friendsState = ref.watch(friendsControllerProvider);
    final controller = ref.read(friendsControllerProvider.notifier);
    if (!friendsState.loaded) {
      // Mentre carica la prima volta il pannello resta vuoto.
      if (!friendsState.failed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.friendsUnavailable, style: _mutedStyle),
            const SizedBox(height: 8),
            _ActionButton(
                label: l.retry, onPressed: () => unawaited(controller.reload())),
          ],
        ),
      );
    }
    final snapshot = friendsState.snapshot;
    final requests = snapshot.incoming.length + snapshot.outgoing.length;
    final friends = sortFriends(snapshot.friends);
    void run(Future<SocialFailure?> Function() action) =>
        unawaited(runFriendAction(context, action));
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (requests > 0) ...[
          _SectionTitle(l.friendsRequests(requests)),
          for (final person in snapshot.incoming)
            _PersonRow(
              key: ValueKey('incoming-${person.userId}'),
              name: person.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                      label: l.friendsAccept,
                      onPressed: () =>
                          run(() => controller.accept(person.userId))),
                  _ActionButton(
                      label: l.friendsDecline,
                      muted: true,
                      onPressed: () =>
                          run(() => controller.decline(person.userId))),
                ],
              ),
            ),
          for (final person in snapshot.outgoing)
            _PersonRow(
              key: ValueKey('outgoing-${person.userId}'),
              name: person.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.friendsPending, style: _mutedStyle),
                  _ActionButton(
                      label: l.friendsCancel,
                      muted: true,
                      onPressed: () =>
                          run(() => controller.cancel(person.userId))),
                ],
              ),
            ),
        ],
        _SectionTitle(l.friendsTitle),
        if (friends.isEmpty)
          _Note(l.friendsEmpty)
        else
          for (final friend in friends)
            _FriendRow(key: ValueKey('friend-${friend.userId}'), friend: friend),
      ],
    );
  }
}

/// Un amico: ⋯ → "Rimuovi dagli amici" → "Conferma rimozione" per
/// [FriendsPanel.removeConfirmFor] (nell'app non ci sono dialoghi).
class _FriendRow extends ConsumerStatefulWidget {
  const _FriendRow({super.key, required this.friend});

  final FriendEntry friend;

  @override
  ConsumerState<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends ConsumerState<_FriendRow> {
  Timer? _confirm;

  @override
  void dispose() {
    _confirm?.cancel();
    super.dispose();
  }

  void _askConfirm() {
    _confirm?.cancel();
    setState(() {
      _confirm = Timer(FriendsPanel.removeConfirmFor, () {
        if (mounted) setState(() => _confirm = null);
      });
    });
  }

  void _remove() {
    _confirm?.cancel();
    setState(() => _confirm = null);
    unawaited(runFriendAction(context,
        () => ref.read(friendsControllerProvider.notifier).remove(widget.friend.userId)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final friend = widget.friend;
    return _PersonRow(
      name: friend.name,
      online: friend.online,
      trailing: _confirm != null
          ? _ActionButton(
              key: const Key('friend-remove-confirm'),
              label: l.friendsRemoveConfirm,
              danger: true,
              onPressed: _remove,
            )
          : PopupMenuButton<String>(
              tooltip: l.friendsMore,
              icon: const Icon(LucideIcons.ellipsis,
                  size: 18, color: WfColors.creamMuted),
              popUpAnimationStyle: wfPopUpAnimation(context),
              onSelected: (_) => _askConfirm(),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                    value: 'remove', child: Text(l.friendsRemove)),
              ],
            ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    super.key,
    required this.name,
    required this.trailing,
    this.online,
  });

  final String name;
  final Widget trailing;

  /// `null`: stato non mostrato (ricerca, richieste).
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = online;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Semantics(
            label: status == null
                ? null
                : (status ? l.friendsOnline : l.friendsOffline),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(name: name),
                if (status == true)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      key: const Key('online-dot'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: WfColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: WfColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: status == false
                        ? WfColors.creamMuted
                        : WfColors.cream)),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.muted = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool muted;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: danger
              ? WfColors.error
              : muted
                  ? WfColors.creamMuted
                  : WfColors.gold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(label),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: WfColors.creamMuted, fontSize: 12, letterSpacing: 1)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(text, style: _mutedStyle),
      );
}
```

- [ ] **Step 5: verifica**

Run: `flutter test test/features/friends/friends_panel_test.dart` → PASS.
Run: `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib/app/theme.dart lib/features/friends test/features/friends
git commit -m "feat: add the friends panel (#6)"
```

---

### Task 14: icona nella barra, pannello sopra la shell, Esc, scheda della richiesta

**Files:**
- Modify: `lib/features/friends/friends_panel.dart` (aggiunge `FriendsPanelHost`)
- Create: `lib/features/friends/friends_button.dart`, `lib/features/friends/friend_request_card.dart`
- Modify: `lib/app/app_shell.dart`, `lib/app/back_navigation.dart`
- Test: `test/features/friends/friends_shell_test.dart`, `test/app/back_navigation_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/friends/friends_shell_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  Future<void> pumpShell(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(friends: true)}) async {
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        ...socialTestOverrides(api, events: events.stream, features: features),
        // Nessun elenco dei watch party (né timer).
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      ],
    );
    await tester.pump();
  }

  testWidgets('senza la funzione amici: niente icona', (tester) async {
    await pumpShell(tester, features: SocialFeatures.none);
    expect(find.byKey(const Key('friends-button')), findsNothing);
  });

  testWidgets('icona con il numero delle richieste; apre e chiude il pannello',
      (tester) async {
    api.snapshot = FriendsSnapshot(incoming: [
      testPerson('u3', 'Peach'),
      testPerson('u4', 'Daisy'),
    ]);
    await pumpShell(tester);
    await tester.pump();
    expect(find.byKey(const Key('friends-button')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final loads = api.calls.where((call) => call == 'friends').length;

    // Apre (e rilegge); Esc chiude solo il pannello.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);
    expect(api.calls.where((call) => call == 'friends').length, loads + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Un clic fuori chiude.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);

    // Anche la ×.
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
  });

  testWidgets('richiesta in arrivo: scheda con Accetta', (tester) async {
    await pumpShell(tester);
    events.add(friendRequestReceived('u3', 'Peach'));
    await tester.pumpAndSettle();
    expect(find.text('Peach vuole essere tuo amico'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const Key('friend-request-card')),
        matching: find.text('Accetta')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('accept u3'));
    expect(find.text('Peach vuole essere tuo amico'), findsNothing);
  });
}
```

In `test/app/back_navigation_test.dart` aggiungi l'import `package:wonderflix/features/friends/friends_panel.dart` e, in fondo a `main`, il test; dopo `main` la classe:

```dart
  testWidgets('Esc con il pannello Amici aperto: la pagina resta',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (context, state, child) => BackNavigationHandler(child: child),
          routes: [
            GoRoute(path: '/a', builder: (c, s) => const Text('pagina A')),
            GoRoute(path: '/b', builder: (c, s) => const Text('pagina B')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [friendsPanelProvider.overrideWith(_OpenFriendsPanel.new)],
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/b');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('pagina B'), findsOneWidget);
  });
```

```dart
/// Pannello Amici già aperto (senza toccare amici né plugin).
class _OpenFriendsPanel extends FriendsPanelController {
  @override
  bool build() => true;
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/friends/friends_shell_test.dart test/app/back_navigation_test.dart`
Expected: icona assente / Esc torna indietro (o errori di compilazione per i file nuovi).

- [ ] **Step 3: `FriendsPanelHost`**

In fondo a `lib/features/friends/friends_panel.dart` (aggiungi gli import `dart:math` come `math`, `package:flutter/services.dart` e `../../app/motion.dart`):

```dart
/// Pannello Amici sopra la shell e la barra (spec F §8.3): entra da destra
/// come "Audio e sottotitoli" (con le animazioni ridotte solo in
/// dissolvenza), il resto si scurisce. Esc, × e un clic sullo scuro lo
/// chiudono.
class FriendsPanelHost extends ConsumerStatefulWidget {
  const FriendsPanelHost({super.key});

  @override
  ConsumerState<FriendsPanelHost> createState() => _FriendsPanelHostState();
}

class _FriendsPanelHostState extends ConsumerState<FriendsPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: ref.read(friendsPanelVisibleProvider) ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    reverseCurve: WfMotion.accelerateReverse,
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Prima la curva (si stacca dal controller), poi il controller.
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Esc chiude il pannello; `BackNavigationHandler` intanto non torna
  /// indietro di pagina.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        !ref.read(friendsPanelVisibleProvider)) {
      return false;
    }
    ref.read(friendsPanelProvider.notifier).close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(friendsPanelVisibleProvider, (_, visible) {
      if (visible) {
        _controller.forward();
      } else {
        _controller.reverse();
        // Funzione sparita a pannello aperto: si chiude davvero.
        ref.read(friendsPanelProvider.notifier).close();
      }
    });
    final reduced = WfMotion.of(context).isReduced;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(FriendsPanel.width,
            constraints.maxWidth * FriendsPanel.maxWidthFraction);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            if (_controller.isDismissed) return const SizedBox.shrink();
            final t = _progress.value.clamp(0.0, 1.0);
            final closing = _controller.status == AnimationStatus.reverse;
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('friends-panel-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref.read(friendsPanelProvider.notifier).close(),
                    child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.54 * t)),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width,
                  child: IgnorePointer(
                    ignoring: closing,
                    child: reduced
                        ? Opacity(opacity: t, child: const FriendsPanel())
                        : FractionalTranslation(
                            translation: Offset(1 - t, 0),
                            child: const FriendsPanel(),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
```

(se `WfMotion.accelerateReverse` ha un altro nome, usa quello di `TracksPanelHost` in `lib/features/player/tracks_panel.dart`.)

- [ ] **Step 4: icona**

`lib/features/friends/friends_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../social/social_providers.dart';
import 'friends_controller.dart';
import 'friends_panel.dart';

/// Icona "Amici" nella barra, con il numero delle richieste in arrivo
/// (spec F §8.2). Solo con la funzione amici del plugin (che c'è solo con
/// l'accesso ai watch party).
class FriendsButton extends ConsumerWidget {
  const FriendsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.friends))) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final count =
        ref.watch(friendsControllerProvider.select((s) => s.incomingCount));
    // Tiene vivo lo stato del pannello finché la barra c'è.
    ref.watch(friendsPanelProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        key: const Key('friends-button'),
        tooltip: l.friendsTitle,
        onPressed: () => ref.read(friendsPanelProvider.notifier).toggle(),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: WfColors.gold,
          textColor: WfColors.bg,
          child: const Icon(LucideIcons.users, size: 20, color: WfColors.cream),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: scheda della richiesta**

`lib/features/friends/friend_request_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'friend_request_notices.dart';
import 'friends_controller.dart';
import 'friends_panel.dart';

/// Scheda "X vuole essere tuo amico" in alto a destra (spec F §8.4): entra
/// da destra e se ne va in dissolvenza, come l'invito ai watch party.
class FriendRequestCard extends ConsumerWidget {
  const FriendRequestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(friendRequestNoticesProvider);
    final current = request == null
        ? const SizedBox.shrink(key: ValueKey('no-friend-request'))
        : KeyedSubtree(
            key: ValueKey('request-${request.fromUserId}'),
            child: _card(context, ref, request));
    return AnimatedSwitcher(
      duration: WfMotion.of(context).duration(WfMotion.medium),
      transitionBuilder: (child, animation) => IgnorePointer(
        // La scheda che se ne va non accetta più clic.
        ignoring: child.key != current.key,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.3, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation, curve: WfMotion.emphasized)),
            child: child,
          ),
        ),
      ),
      child: current,
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, FriendRequestEvent request) {
    final l = AppLocalizations.of(context);
    final notices = ref.read(friendRequestNoticesProvider.notifier);
    final friends = ref.read(friendsControllerProvider.notifier);
    void answer(Future<SocialFailure?> Function() action) {
      notices.dismiss();
      unawaited(runFriendAction(context, action));
    }

    return Material(
      key: const Key('friend-request-card'),
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.userPlus,
                      size: 18, color: WfColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.friendRequestTitle(request.fromName),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: l.watchPartyDismiss,
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: notices.dismiss,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Row(
                  children: [
                    WfButton.primary(
                      label: l.friendsAccept,
                      icon: LucideIcons.userCheck,
                      onPressed: () =>
                          answer(() => friends.accept(request.fromUserId)),
                    ),
                    const SizedBox(width: 8),
                    WfButton.secondary(
                      label: l.friendsDecline,
                      icon: LucideIcons.userX,
                      onPressed: () =>
                          answer(() => friends.decline(request.fromUserId)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: shell e Esc**

In `lib/app/app_shell.dart`:
- import di `../features/friends/friend_request_card.dart`, `../features/friends/friends_button.dart`, `../features/friends/friends_panel.dart`;
- nella `Row` della barra, dopo `const WatchPartyButton(),` aggiungi `const FriendsButton(),`;
- sostituisci

```dart
            // Invito a un watch party appena nato (spec B §5.8).
            const Positioned(top: 72, right: 24, child: WatchPartyInviteCard()),
```

con

```dart
            // Invito a un watch party appena nato (spec B §5.8) e richiesta
            // di amicizia appena arrivata (spec F §8.4), una sotto l'altra.
            const Positioned(
              top: 72,
              right: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 8,
                children: [WatchPartyInviteCard(), FriendRequestCard()],
              ),
            ),
            // Pannello Amici, sopra la barra e le schede (spec F §8.3).
            const Positioned.fill(child: FriendsPanelHost()),
```

In `lib/app/back_navigation.dart`:
- import di `../features/friends/friends_panel.dart`;
- nel commento della classe aggiungi "; con il pannello Amici aperto Esc chiude solo lui";
- in `_onKey`, subito dopo il blocco dell'anteprima:

```dart
    // Con il pannello Amici aperto Esc chiude solo lui (lo gestisce il
    // pannello). `friendsPanelProvider` non dipende da altri provider.
    if (key == LogicalKeyboardKey.escape && ref.read(friendsPanelProvider)) {
      return false;
    }
```

- [ ] **Step 7: verifica**

Run: `flutter test test/features/friends test/app` → PASS.
Run: `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 8: commit**

```bash
git add lib/app lib/features/friends test/features/friends test/app/back_navigation_test.dart
git commit -m "feat: open the friends panel from the bar and show new requests (#6)"
```

---

## Gruppo E — chiusura

### Task 15: spec allineato, verifica finale, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`

- [ ] **Step 1: allinea lo spec a quanto realizzato**

- Riga **Stato**: `approvato; piano 12a realizzato (\`docs/superpowers/plans/2026-10-03-wonderflix-12a-amici.md\`); piano 12b da scrivere`.
- §7.2, sostituisci `La diagnostica aggiunge le funzioni alla riga "Plugin watch party: 1.1.0 (amici, party)".` con `La diagnostica aggiunge la riga "Funzioni del plugin: amici, party" (o "nessuna"; assente se il plugin non risponde).`
- §7.3, sostituisci `Eliminazione dei doppioni come nel canale (stesso evento ricevuto due volte entro 5 s).` con `Niente eliminazione dei doppioni: gli avvisi sociali non hanno un Id; \`FriendsChanged\` fa solo rileggere e una \`FriendRequest\` doppia rimostra la stessa scheda. Il canale del gruppo (\`parsePartyEvent\`) scarta questi tipi senza scriverli nel log.`
- §8.3, sostituisci `Entrata e uscita come \`TracksPanelHost\` (scivola di 24 px + dissolvenza; con "Ridotte" solo dissolvenza).` con `Entrata e uscita come \`TracksPanelHost\` (entra tutto da destra; con "Ridotte" solo dissolvenza). Mentre carica la prima volta il pannello resta vuoto (niente indicatore che gira).`
- §8.3, sostituisci `Al passaggio del mouse: **⋯** → "Rimuovi dagli amici"` con `**⋯** (sempre visibile) → "Rimuovi dagli amici"`.
- §8.4, sostituisci `Una sola scheda alla volta in quel posto: la più recente sostituisce l'altra.` con `L'invito ai watch party e la richiesta stanno in colonna (invito sopra), 8 px l'una dall'altra.`
- §11, nella tabella dopo `friendsTitle` aggiungi la riga `| \`friendsClose\` | Chiudi | Close |`.

- [ ] **Step 2: verifica finale**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → tutto verde, nessun warning (circa 75 test).
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → tutto verde (circa 1300).

- [ ] **Step 3: build di release per la prova**

```bash
cp ../../../config/wonderflix.json config/wonderflix.json
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Ripristina `windows/flutter/` se cambiano solo le fini riga.

- [ ] **Step 4: commit**

```bash
git add docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md
git commit -m "docs: align spec F with plan 12a (#6)"
```

---

## Prova manuale (con l'utente, sul server reale)

Prerequisiti: Task 7 fatto (plugin 1.1.0 sul server). Due istanze di `build/windows/x64/runner/Release/wonderflix.exe` del worktree: la prima con l'utente A, la seconda con `WONDERFLIX_PROFILE=b` e un **altro** utente Jellyfin (B).

1. Nelle due istanze c'è l'icona **Amici** nella barra. Impostazioni → Supporto → diagnostica: `Funzioni del plugin: amici`.
2. A apre il pannello, scrive 2 lettere del nome di B: B compare con **Aggiungi**. Clic → diventa **Inviata · Annulla**.
3. B vede la scheda "A vuole essere tuo amico" e il numero 1 sull'icona. **Accetta** dalla scheda → nel pannello di A (aperto) B compare tra gli amici, online (pallino verde), senza riaprire.
4. Chiudi l'istanza di B → entro pochi secondi nel pannello di A B diventa offline (nome attenuato). Riaprila → torna online.
5. A → ⋯ → **Rimuovi dagli amici** → **Conferma rimozione**: B sparisce anche dalla lista di B.
6. Richieste incrociate: A chiede a B e B chiede ad A prima di accettare → diventano subito amici.
7. B rifiuta una richiesta di A dal pannello: ad A la richiesta sparisce, nessun avviso.
8. Esc chiude il pannello senza cambiare pagina (anche da una scheda film); un clic fuori lo chiude.
9. Con il player aperto in B, A manda una richiesta: B vede solo il numero sull'icona alla chiusura del player, niente scheda sopra il film.
10. (facoltativo) La 0.5.1 installata funziona ancora nel watch party (chat e reazioni) con il plugin 1.1.0.

## Dopo la prova (fuori dai task)

- Con l'ok dell'utente: merge fast-forward su `main`, `git fetch` e rebase se `origin/main` è avanti, push, rimozione di worktree e branch.
- **Nessuna release** dopo il 12a: plugin 1.1.0 dal Catalogo e app 0.6.0 obbligatoria arrivano con il piano 12b. Il plugin copiato a mano resta sul server fino ad allora.
