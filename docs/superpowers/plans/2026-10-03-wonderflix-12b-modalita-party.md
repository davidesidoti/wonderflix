# WonderFlix — Piano 12b: modalità dei party (plugin + app + release)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** seconda metà della Spec F (issue #5): party **Pubblico / Solo amici / Privato**, codice per i privati, "Invita amici", elenco dei party filtrato dal plugin, "Nel watch party: titolo" nella lista amici; poi plugin 1.1.0 dal Catalogo e app **0.6.0 obbligatoria**.

**Spec:** `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md` (§6.4–6.9, §7.1, §8.3 "Ho un codice" e "Nel watch party", §9, §10, §11, §12, §13). Il piano 12a (amici) è su `main` (`1b9b497`).

**Architecture:**
- **Plugin (1.1.0, stessa versione: non è ancora uscita):** `PartyDirectory` (RAM: modalità, codici, invitati, attesa di 10 s dei gruppi non registrati) + `PartyService` (registrazione, elenco filtrato, dettagli, codice, inviti, "in un party" per la lista amici, pulizia, avvisi `PartyStarted`/`PartyInvite`) + `PartiesController`. `IGroupDirectory` impara a elencare i gruppi (`ISyncPlayManager.ListGroups`). `Info.Features` = `["friends", "parties"]`.
- **App:** `PartyMode` e modelli del plugin; `SocialApi` con gli endpoint dei party; `WatchPartySession.create` registra il party **prima** della coda (se fallisce esce dal gruppo); menu delle modalità su "Guarda insieme" (scheda e player); `CurrentParty` (modalità e codice del gruppo in cui siamo); codice e "Invita amici" nei menu del chip e del distintivo; elenco e schede dei party dal plugin; "Ho un codice" e "Nel watch party" nel pannello Amici.

**Tech Stack:** C# net9.0 (compilato contro Jellyfin 10.11.0, test contro 10.11.9 = il server), xUnit, `Microsoft.Extensions.TimeProvider.Testing`; Flutter 3.47.5, flutter_riverpod 3, shared_preferences, fake_async, lucide_icons_flutter.

**Worktree:** `.claude/worktrees/piano-12b`, branch `feat/piano-12b`. **Base:** `main` con questo piano. **Test a inizio piano:** 1313 Flutter, 88 plugin.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali: solo il riferimento `(#5)` in fondo all'oggetto, dove indicato.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-12b`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde e senza warning (il plugin ha `TreatWarningsAsErrors`). **Prima di ogni commit lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit. Dopo ogni modifica agli ARB: `flutter gen-l10n` (la cartella `lib/l10n/gen/` non si committa).
- **Formattazione e fine riga:** niente `dart format` né `dotnet format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Durate, misure, limiti:** costanti nominate e commentate. Commenti in italiano, codice in inglese (anche nel C#: commenti `///` in italiano, identificatori in inglese).
- **Se il codice del piano ha un errore** (analyzer, import, un'API con firma diversa, uno `switch` non più esaustivo per un valore d'enum nuovo, un dettaglio di un test): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-03:

- **Jellyfin cambia API anche nelle patch della 10.11** (`IUserManager.Users` è sparito tra la 10.11.0 e la 10.11.9). Il plugin si compila contro la **10.11.0** (il minimo), i test girano con le dll della **10.11.9** (il server): un membro tolto fa fallire i test. Prima di ogni deploy l'orchestratore risolve tutti i riferimenti del plugin contro la 10.11.9 (Task 6).
- **SyncPlay, stabile tra 10.11.0 e 10.11.9:** `ISyncPlayManager.ListGroups(SessionInfo, ListGroupsRequest)` → `List<GroupInfoDto>` (`ListGroupsRequest` in `MediaBrowser.Controller.SyncPlay.Requests`, costruttore senza argomenti); `GetGroup(SessionInfo, Guid)` → `GroupInfoDto` o null. `GroupInfoDto` (`MediaBrowser.Model.SyncPlay`): `GroupId`, `GroupName`, `State` (`GroupStateType`: `Idle`, `Waiting`, `Paused`, `Playing`), `Participants` (nomi utente), `LastUpdatedAt`; costruttore `(Guid, string, GroupStateType, IReadOnlyList<string>, DateTime)`. `ListGroups` e `GetGroup` mostrano solo i gruppi di cui l'utente della sessione può vedere la coda.
- **Codici:** `System.Security.Cryptography.RandomNumberGenerator.GetString(ReadOnlySpan<char>, int)` (da .NET 8).
- **JSON del plugin:** i controller di Jellyfin leggono i corpi senza distinguere le maiuscole e scrivono PascalCase saltando i `null` (`WhenWritingNull`): un campo `null` può **mancare** nella risposta. `JsonSerializer` con le opzioni di default (gli avvisi sul WebSocket) scrive i caratteri non ASCII come `\uXXXX` (es. `·`): l'app li legge senza problemi.
- **App, creazione del gruppo:** `WatchPartySession.create` fa `_enter` (attende la conferma del server: dopo, `state.group` c'è) e poi `setNewQueue`. È il punto in cui registrare il party: prima della coda, quindi prima che si apra un player.
- **App, avvisi del party:** `PartyNotices.show(PartyNotice)` (`partyNoticesProvider`) mette in coda un avviso per la pillola del player; testo e icona in `party_notice_pill.dart` (`switch` esaustivi su `PartyNoticeKind`). Anche `party_channel.dart` (~riga 272) fa uno `switch` su un tipo di avviso: un valore nuovo può richiedere un ramo.
- **App, menu ancorati:** `showMenu(context:, position: RelativeRect, popUpAnimationStyle: wfPopUpAnimation(context), items:)`; la posizione si calcola dal `RenderBox` del pulsante rispetto all'`Overlay` del `Navigator` (come fa `PopupMenuButton`). Funziona anche nel player (il distintivo del party usa già un menu).
- **App, test:** nessun test usa `onWatchTogether` di `PlayerOverlay`. I test che costruiscono `WatchPartyInvites`/`WatchPartyDirectory` sovrascrivono sessione ed eventi del WebSocket; se un test esistente fallisce perché `socialAvailabilityProvider` o `socialApiProvider` non si costruiscono, aggiungi `socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(SocialFeatures.none))` e `socialApiProvider.overrideWithValue(FakeSocialApi())`. `SharedPreferences` nei test: `SharedPreferences.setMockInitialValues({})`, poi `await SharedPreferences.getInstance()` e `sharedPreferencesProvider.overrideWithValue(prefs)`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/…/Protocol/PartyDtos.cs`, `SocialEvent.cs`, `WatchPartyProtocol.cs` | crea/modifica | modalità, richieste e risposte dei party, avvisi `PartyStarted`/`PartyInvite`, `Features` |
| `…/Hub/LimitTypes.cs`, `RateLimiter.cs` | modifica | 5 codici al minuto, 20 inviti al minuto |
| `…/Hub/PartyDirectory.cs` | crea | party in RAM, codici, visibilità |
| `…/Hub/IGroupDirectory.cs`, `…/Server/JellyfinGroupDirectory.cs` | modifica | elenco e dettaglio dei gruppi SyncPlay |
| `…/Hub/PartyRegistry.cs`, `FriendService.cs` | modifica | gruppo di una sessione; amicizia e amici per i party; "in un party" nella lista |
| `…/Hub/PartyService.cs` | crea | regole dei party, avvisi, pulizia |
| `…/Api/PartiesController.cs`, `FriendsController.cs`, `WatchPartyController.cs` | crea/modifica | endpoint Parties, lista amici con il party, presenza a ingresso/uscita |
| `…/WatchPartyHostedService.cs`, `PluginServiceRegistrator.cs`, `README.md` | modifica | pulizia dei party, servizi, documentazione |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi dei party |
| `lib/core/syncplay/party_mode.dart`, `syncplay_models.dart` | crea/modifica | `PartyMode`, `GroupInfo.mode` |
| `lib/core/social/social_models.dart`, `social_api.dart`, `lib/core/party_channel/party_channel_models.dart` | modifica | modelli, avvisi e chiamate dei party |
| `lib/features/watch_party/watch_party_session.dart`, `watch_party_actions.dart` | modifica | registrazione prima della coda, errore |
| `lib/features/watch_party/party_mode_preference.dart`, `current_party.dart` | crea | ultima modalità usata, party corrente |
| `lib/features/watch_party/watch_party_directory.dart`, `watch_party_invites.dart`, `watch_party_button.dart` | modifica | elenco e schede dal plugin, icona della modalità, codice e inviti nel chip |
| `lib/features/watch_party/party_mode_menu.dart`, `party_invite_menu.dart`, `lib/ui/wf_menus.dart` | crea/modifica | menu delle modalità e degli inviti |
| `lib/features/watch_party/party_notices.dart`, `party_notice_pill.dart`, `party_badge.dart` | modifica | avvisi del codice e degli inviti, menu del distintivo |
| `lib/features/detail/detail_header.dart`, `lib/features/player/player_overlay.dart`, `player_screen.dart` | modifica | "Guarda insieme" con il menu |
| `lib/features/friends/friends_panel.dart`, `party_code_field.dart` | modifica/crea | "Ho un codice", "Nel watch party" |
| `test/support/social_fakes.dart` | modifica | finti dei party |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/…`, `docs/RELEASING.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–5):** plugin. **Poi ci si ferma** (Task 6: l'orchestratore rimette il plugin sul server).
- **Gruppo B (Task 7–10):** nucleo nell'app.
- **Gruppo C (Task 11–13):** interfaccia.
- **Gruppo D (Task 14):** allineamento, verifica finale, build. Dopo la prova: **release** (sezione in fondo, orchestratore con l'utente).

---

## Gruppo A — plugin

### Task 1: protocollo dei party, funzione `parties`, limiti

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/PartyDtos.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/SocialEvent.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/LimitTypes.cs`, `Hub/RateLimiter.cs`
- Test: `…Tests/ProtocolJsonTests.cs`, `…Tests/RateLimiterTests.cs`, `…Tests/WatchPartyControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `ProtocolJsonTests.cs` aggiungi:

```csharp
    [Fact]
    public void PartyEventsAndResponsesUseProtocolNames()
    {
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"PartyStarted\",\"GroupId\":\"g1\",\"Name\":\"Dune\",\"Mode\":\"Friends\"}",
            JsonSerializer.Serialize(SocialEvent.PartyStarted("g1", "Dune", PartyModes.Friends)));
        Assert.Equal(
            "{\"Protocol\":1,\"Type\":\"PartyInvite\",\"FromName\":\"Mario\",\"GroupId\":\"g1\",\"Name\":\"Dune\"}",
            JsonSerializer.Serialize(SocialEvent.PartyInvite("g1", "Dune", "Mario")));
        Assert.Equal("{\"Code\":\"K7PQ2X\"}", JsonSerializer.Serialize(new RegisterPartyResponse("K7PQ2X")));
        Assert.Equal(
            "{\"GroupId\":\"g1\",\"Name\":\"Dune\",\"State\":\"Idle\",\"Participants\":[\"Mario\"],\"Mode\":\"Private\"}",
            JsonSerializer.Serialize(new PartySummary("g1", "Dune", "Idle", new[] { "Mario" }, PartyModes.Private)));
        Assert.Equal(
            "{\"Mode\":\"Public\",\"Code\":null}",
            JsonSerializer.Serialize(new PartyDetails(PartyModes.Public, null)));
        Assert.Equal("{\"GroupId\":\"g1\"}", JsonSerializer.Serialize(new JoinByCodeResponse("g1")));
    }

    [Fact]
    public void PartyRequestsReadAnyCaseOfNames()
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        Assert.Equal("Friends", JsonSerializer.Deserialize<RegisterPartyRequest>("{\"mode\":\"Friends\"}", options)!.Mode);
        Assert.Equal("K7P-Q2X", JsonSerializer.Deserialize<JoinByCodeRequest>("{\"code\":\"K7P-Q2X\"}", options)!.Code);
        Assert.Equal(
            new[] { "u2", "u3" },
            JsonSerializer.Deserialize<InviteRequest>("{\"userIds\":[\"u2\",\"u3\"]}", options)!.UserIds);
    }

    [Fact]
    public void PartyModesAreExact()
    {
        Assert.True(PartyModes.IsValid("Public"));
        Assert.True(PartyModes.IsValid("Friends"));
        Assert.True(PartyModes.IsValid("Private"));
        Assert.False(PartyModes.IsValid("public"));
        Assert.False(PartyModes.IsValid(null));
    }
```

In `RateLimiterTests.cs` aggiungi:

```csharp
    [Fact]
    public void CodeAttemptsAndInvitesArePerMinute()
    {
        var time = new FakeTimeProvider();
        var limiter = new RateLimiter(time);
        for (var i = 0; i < 5; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.CodeAttempts));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.CodeAttempts));
        for (var i = 0; i < 20; i++)
        {
            Assert.True(limiter.TryAcquire("u1", LimitTypes.Invites));
        }

        Assert.False(limiter.TryAcquire("u1", LimitTypes.Invites));
        time.Advance(TimeSpan.FromMinutes(1));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.CodeAttempts));
        Assert.True(limiter.TryAcquire("u1", LimitTypes.Invites));
    }
```

In `WatchPartyControllerTests.InfoReportsVersionProtocolAndFeatures` l'ultima asserzione diventa:

```csharp
        Assert.Equal(new[] { "friends", "parties" }, info.Features);
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`PartyModes`, `RegisterPartyResponse`, `SocialEvent.PartyStarted`, `LimitTypes.CodeAttempts` non esistono).

- [ ] **Step 3: DTO dei party**

`Protocol/PartyDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Modalità di un party (spec F §6.4). Esatte, con la maiuscola.</summary>
public static class PartyModes
{
    public const string Public = "Public";
    public const string Friends = "Friends";
    public const string Private = "Private";

    public static bool IsValid(string? mode) => mode is Public or Friends or Private;
}

/// <summary>Corpo di POST Parties/{groupId}.</summary>
public sealed class RegisterPartyRequest
{
    [JsonPropertyName("Mode")]
    public string? Mode { get; set; }
}

/// <summary>Risposta della registrazione: il codice, solo per i privati.</summary>
public sealed record RegisterPartyResponse(
    [property: JsonPropertyName("Code")] string? Code);

/// <summary>Un party dell'elenco (GET Parties).</summary>
public sealed record PartySummary(
    [property: JsonPropertyName("GroupId")] string GroupId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("State")] string State,
    [property: JsonPropertyName("Participants")] IReadOnlyList<string> Participants,
    [property: JsonPropertyName("Mode")] string Mode);

/// <summary>Modalità e codice del party (GET Parties/{groupId}, solo per i partecipanti).</summary>
public sealed record PartyDetails(
    [property: JsonPropertyName("Mode")] string Mode,
    [property: JsonPropertyName("Code")] string? Code);

/// <summary>Corpo di POST Parties/Join.</summary>
public sealed class JoinByCodeRequest
{
    [JsonPropertyName("Code")]
    public string? Code { get; set; }
}

/// <summary>Il gruppo del codice.</summary>
public sealed record JoinByCodeResponse(
    [property: JsonPropertyName("GroupId")] string GroupId);

/// <summary>Corpo di POST Parties/{groupId}/Invites.</summary>
public sealed class InviteRequest
{
    [JsonPropertyName("UserIds")]
    public List<string>? UserIds { get; set; }
}
```

- [ ] **Step 4: avvisi dei party**

In `Protocol/SocialEvent.cs`:
- in `SocialEventTypes` aggiungi:

```csharp
    public const string PartyStarted = "PartyStarted";
    public const string PartyInvite = "PartyInvite";
```

- nella classe `SocialEvent`, dopo `FromName`:

```csharp
    [JsonPropertyName("GroupId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? GroupId { get; init; }

    /// <summary>Nome del gruppo SyncPlay ("Host · Titolo").</summary>
    [JsonPropertyName("Name")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Name { get; init; }

    [JsonPropertyName("Mode")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Mode { get; init; }
```

- dopo `FriendsChanged()`:

```csharp
    public static SocialEvent PartyStarted(string groupId, string name, string mode) =>
        new() { Type = SocialEventTypes.PartyStarted, GroupId = groupId, Name = name, Mode = mode };

    public static SocialEvent PartyInvite(string groupId, string name, string fromName) =>
        new() { Type = SocialEventTypes.PartyInvite, GroupId = groupId, Name = name, FromName = fromName };
```

- nel commento della classe, la frase sulle app 0.5.x diventa: "Non ha Id: le app 0.5.x lo scartano (anche quando ha il GroupId del loro gruppo)."

- [ ] **Step 5: funzione `parties` e limiti**

In `Protocol/WatchPartyProtocol.cs`: `public static readonly IReadOnlyList<string> Features = ["friends", "parties"];`

In `Hub/LimitTypes.cs` aggiungi:

```csharp
    /// <summary>Codici dei party privati provati (ogni tentativo conta).</summary>
    public const string CodeAttempts = "CodeAttempts";

    /// <summary>Destinatari degli inviti ai party.</summary>
    public const string Invites = "Invites";
```

In `Hub/RateLimiter.cs`, nel dizionario `Limits`:

```csharp
            [LimitTypes.CodeAttempts] = (5, TimeSpan.FromMinutes(1)),
            [LimitTypes.Invites] = (20, TimeSpan.FromMinutes(1)),
```

- [ ] **Step 6: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → PASS, nessun warning.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the party protocol and limits (#5)"
```

---

### Task 2: party in RAM (`PartyDirectory`)

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyDirectory.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/PartyDirectoryTests.cs`

- [ ] **Step 1: test che falliscono**

`PartyDirectoryTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PartyDirectoryTests
{
    private readonly FakeTimeProvider _time = new();
    private readonly PartyDirectory _parties;
    private readonly Guid _group = Guid.NewGuid();
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();

    public PartyDirectoryTests() => _parties = new PartyDirectory(_time);

    [Fact]
    public void RegistersOnceAndOnlyPrivatePartiesHaveACode()
    {
        var view = _parties.Register(_group, _mario, PartyModes.Public)!;
        Assert.Null(view.Code);
        Assert.Equal(_mario, view.CreatorId);
        Assert.Null(_parties.Register(_group, _luigi, PartyModes.Private));
        Assert.Equal(PartyModes.Public, _parties.Get(_group)!.Mode);

        var other = Guid.NewGuid();
        var code = _parties.Register(other, _mario, PartyModes.Private)!.Code!;
        Assert.Equal(PartyDirectory.CodeLength, code.Length);
        Assert.All(code, c => Assert.Contains(c, PartyDirectory.CodeAlphabet));
        Assert.Equal(other, _parties.FindByCode(code));
        // Minuscole, trattino e spazi non contano.
        Assert.Equal(other, _parties.FindByCode($" {code[..3].ToLowerInvariant()}-{code[3..]} "));
        Assert.Null(_parties.FindByCode("ZZZ-ZZZ"));
        Assert.Null(_parties.FindByCode("troppo-lungo"));
        Assert.Null(_parties.FindByCode(null));
    }

    [Fact]
    public void CodesAreUnique()
    {
        var codes = Enumerable.Range(0, 300)
            .Select(_ => _parties.Register(Guid.NewGuid(), _mario, PartyModes.Private)!.Code)
            .ToList();
        Assert.Equal(codes.Count, codes.Distinct().Count());
    }

    [Fact]
    public void VisibilityFollowsTheMode()
    {
        var friends = Guid.NewGuid();
        var secret = Guid.NewGuid();
        _parties.Register(_group, _mario, PartyModes.Public);
        _parties.Register(friends, _mario, PartyModes.Friends);
        _parties.Register(secret, _mario, PartyModes.Private);
        bool FriendOfMario(Guid creator) => creator == _mario;
        bool Nobody(Guid creator) => false;

        Assert.True(_parties.IsVisible(_group, _luigi, Nobody));
        Assert.True(_parties.IsVisible(friends, _luigi, FriendOfMario));
        Assert.False(_parties.IsVisible(friends, _luigi, Nobody));
        Assert.False(_parties.IsVisible(secret, _luigi, FriendOfMario));
        // Il creatore lo vede sempre; chi è invitato (o entra col codice) anche.
        Assert.True(_parties.IsVisible(secret, _mario, Nobody));
        _parties.Grant(secret, [_luigi]);
        Assert.True(_parties.IsVisible(secret, _luigi, Nobody));
    }

    [Fact]
    public void UnregisteredGroupsBecomePublicAfterTheGrace()
    {
        Assert.False(_parties.IsVisible(_group, _luigi, _ => false));
        _parties.Seen(_group);
        _time.Advance(PartyDirectory.UnregisteredGrace - TimeSpan.FromSeconds(1));
        _parties.Seen(_group);
        Assert.False(_parties.IsVisible(_group, _luigi, _ => false));
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(_parties.IsVisible(_group, _luigi, _ => false));
    }

    [Fact]
    public void ForgetRemovesEndedPartiesAndTheirCodes()
    {
        var code = _parties.Register(_group, _mario, PartyModes.Private)!.Code;
        var alive = Guid.NewGuid();
        _parties.Register(alive, _mario, PartyModes.Public);
        _parties.Seen(Guid.NewGuid());

        Assert.Equal(1, _parties.Forget(id => id == alive));

        Assert.Null(_parties.Get(_group));
        Assert.Null(_parties.FindByCode(code));
        Assert.NotNull(_parties.Get(alive));
    }
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`PartyDirectory` non esiste).

- [ ] **Step 3: `PartyDirectory`**

`Hub/PartyDirectory.cs`:

```csharp
using System.Security.Cryptography;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un party registrato, come lo legge chi lo chiede.</summary>
public sealed record PartyView(Guid GroupId, Guid CreatorId, string Mode, string? Code);

/// <summary>
/// Party registrati, in RAM (spec F §6.4–6.6): modalità, codici dei privati,
/// invitati e da quando il plugin vede i gruppi non registrati. Vivono
/// quanto i gruppi SyncPlay. Sicuro tra thread.
/// </summary>
public sealed class PartyDirectory(TimeProvider time)
{
    /// <summary>Un gruppo mai registrato diventa pubblico dopo questa attesa.</summary>
    public static readonly TimeSpan UnregisteredGrace = TimeSpan.FromSeconds(10);

    public const int CodeLength = 6;

    /// <summary>Simboli dei codici: niente 0/O/1/I/L, che si confondono.</summary>
    public const string CodeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Entry> _parties = [];
    private readonly Dictionary<string, Guid> _codes = new(StringComparer.Ordinal);
    private readonly Dictionary<Guid, DateTimeOffset> _firstSeen = [];

    /// <summary>Registra il party; null se lo era già. I privati hanno un codice.</summary>
    public PartyView? Register(Guid groupId, Guid creatorId, string mode)
    {
        lock (_lock)
        {
            if (_parties.ContainsKey(groupId))
            {
                return null;
            }

            string? code = null;
            if (mode == PartyModes.Private)
            {
                do
                {
                    code = RandomNumberGenerator.GetString(CodeAlphabet, CodeLength);
                }
                while (_codes.ContainsKey(code));

                _codes[code] = groupId;
            }

            var entry = new Entry(creatorId, mode, code);
            _parties[groupId] = entry;
            return entry.View(groupId);
        }
    }

    public PartyView? Get(Guid groupId)
    {
        lock (_lock)
        {
            return _parties.TryGetValue(groupId, out var entry) ? entry.View(groupId) : null;
        }
    }

    /// <summary>Il plugin vede il gruppo in un elenco: per uno non registrato parte l'attesa.</summary>
    public void Seen(Guid groupId)
    {
        lock (_lock)
        {
            _firstSeen.TryAdd(groupId, time.GetUtcNow());
        }
    }

    /// <summary>
    /// viewer può vedere il gruppo (spec F §6.4), a parte il caso
    /// "partecipante", che decide chi chiama. isFriendOfCreator si chiama
    /// fuori dal lock (va a chiedere agli amici).
    /// </summary>
    public bool IsVisible(Guid groupId, Guid viewer, Func<Guid, bool> isFriendOfCreator)
    {
        string mode;
        Guid creator;
        bool invited;
        lock (_lock)
        {
            if (!_parties.TryGetValue(groupId, out var entry))
            {
                return _firstSeen.TryGetValue(groupId, out var seen) && time.GetUtcNow() - seen >= UnregisteredGrace;
            }

            (mode, creator, invited) = (entry.Mode, entry.CreatorId, entry.Invited.Contains(viewer));
        }

        return mode == PartyModes.Public
            || invited
            || creator == viewer
            || (mode == PartyModes.Friends && isFriendOfCreator(creator));
    }

    /// <summary>Il gruppo del codice (maiuscole, spazi e trattini non contano); null se non c'è.</summary>
    public Guid? FindByCode(string? code)
    {
        var normalized = NormalizeCode(code);
        if (normalized is null)
        {
            return null;
        }

        lock (_lock)
        {
            return _codes.TryGetValue(normalized, out var groupId) ? groupId : null;
        }
    }

    /// <summary>Chi è invitato, o è entrato con il codice, vede il party.</summary>
    public void Grant(Guid groupId, IEnumerable<Guid> users)
    {
        lock (_lock)
        {
            if (_parties.TryGetValue(groupId, out var entry))
            {
                entry.Invited.UnionWith(users);
            }
        }
    }

    /// <summary>
    /// Toglie party e attese dei gruppi finiti (alive si chiama fuori dal
    /// lock: chiede a Jellyfin). Restituisce quanti party ha tolto.
    /// </summary>
    public int Forget(Func<Guid, bool> alive)
    {
        List<Guid> known;
        lock (_lock)
        {
            known = _parties.Keys.Concat(_firstSeen.Keys).Distinct().ToList();
        }

        var ended = known.Where(id => !alive(id)).ToList();
        var removed = 0;
        lock (_lock)
        {
            foreach (var id in ended)
            {
                if (_parties.Remove(id, out var entry))
                {
                    removed++;
                    if (entry.Code is not null)
                    {
                        _codes.Remove(entry.Code);
                    }
                }

                _firstSeen.Remove(id);
            }
        }

        return removed;
    }

    /// <summary>Il codice in forma canonica; null se non ha la lunghezza giusta.</summary>
    public static string? NormalizeCode(string? code)
    {
        if (code is null)
        {
            return null;
        }

        var normalized = string.Concat(code.Where(char.IsLetterOrDigit)).ToUpperInvariant();
        return normalized.Length == CodeLength ? normalized : null;
    }

    private sealed class Entry(Guid creatorId, string mode, string? code)
    {
        public Guid CreatorId { get; } = creatorId;

        public string Mode { get; } = mode;

        public string? Code { get; } = code;

        public HashSet<Guid> Invited { get; } = [];

        public PartyView View(Guid groupId) => new(groupId, CreatorId, Mode, Code);
    }
}
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → PASS, nessun warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): keep party modes, codes and invites in memory (#5)"
```

---

### Task 3: gruppi SyncPlay, gruppo di una sessione, amici per i party

**Files:**
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/IGroupDirectory.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinGroupDirectory.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyRegistry.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/FriendService.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FakeServer.cs`
- Test: `…Tests/ServerAdapterTests.cs`, `…Tests/PartyRegistryTests.cs`, `…Tests/FriendServiceTests.cs`

- [ ] **Step 1: test che falliscono**

In `ServerAdapterTests.cs` (usings: `MediaBrowser.Controller.SyncPlay.Requests`, `MediaBrowser.Model.SyncPlay` se mancano) aggiungi:

```csharp
    [Fact]
    public void GroupsAreListedAndReadFromSyncPlay()
    {
        var group = Guid.NewGuid();
        var (manager, sessions) = InterfaceStub<ISessionManager>.Create();
        var mario = Session("s1", "d1", "WonderFlix", Guid.NewGuid(), "Mario");
        sessions.Handlers["get_Sessions"] = _ => new[] { mario };
        var dto = new GroupInfoDto(group, "Mario · Dune", GroupStateType.Playing, new[] { "Mario", "Luigi" }, DateTime.UtcNow);
        var (syncPlay, groups) = InterfaceStub<ISyncPlayManager>.Create();
        groups.Handlers["ListGroups"] = args => ReferenceEquals(args[0], mario) && args[1] is ListGroupsRequest
            ? new List<GroupInfoDto> { dto }
            : new List<GroupInfoDto>();
        groups.Handlers["GetGroup"] = args => ReferenceEquals(args[0], mario) && (Guid)args[1]! == group ? dto : null;
        var directory = new JellyfinGroupDirectory(manager, syncPlay);

        var listed = Assert.Single(directory.ListGroups("s1"));
        Assert.Equal(new GroupSummary(group, "Mario · Dune", "Playing", dto.Participants), listed);
        Assert.Empty(directory.ListGroups("s-x"));
        Assert.Equal("Mario · Dune", directory.GetGroup("s1", group)!.Name);
        Assert.Null(directory.GetGroup("s1", Guid.NewGuid()));
        Assert.Null(directory.GetGroup("s-x", group));
    }
```

In `PartyRegistryTests.cs` aggiungi:

```csharp
    [Fact]
    public void GroupOfASession()
    {
        var registry = new PartyRegistry();
        var group = Guid.NewGuid();
        registry.Register(group, "s1", "Mario");
        Assert.Equal(group, registry.GroupOf("s1"));
        Assert.Null(registry.GroupOf("s2"));
        registry.Unregister(group, "s1");
        Assert.Null(registry.GroupOf("s1"));
    }
```

In `FriendServiceTests.cs` aggiungi:

```csharp
    [Fact]
    public async Task FriendshipQueriesForParties()
    {
        await MakeFriends(_mario, _luigi);
        Assert.True(_friends.AreFriends(_mario.Id, _luigi.Id));
        Assert.True(_friends.AreFriends(_luigi.Id, _mario.Id));
        Assert.False(_friends.AreFriends(_mario.Id, _peach.Id));
        Assert.Equal(new[] { _luigi.Id }, _friends.FriendsOf(_mario.Id));
    }

    [Fact]
    public async Task GetFriendsAsksThePartyOnlyForOnlineFriends()
    {
        await MakeFriends(_mario, _luigi);
        await MakeFriends(_mario, _peach);
        var asked = new List<Guid>();

        var friends = _friends.GetFriends(_mario.Id, id =>
        {
            asked.Add(id);
            return new FriendParty("g1", "Dune");
        }).Friends;

        Assert.Equal(new[] { _luigi.Id }, asked);
        Assert.Equal("Dune", friends.Single(f => f.Name == "Luigi").Party!.Title);
        Assert.Null(friends.Single(f => f.Name == "Peach").Party);
    }
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`ListGroups`, `GroupSummary`, `GroupOf`, `AreFriends` non esistono).

- [ ] **Step 3: gruppi SyncPlay**

`Hub/IGroupDirectory.cs` (tutto il file):

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un gruppo SyncPlay come lo vede una sessione.</summary>
public sealed record GroupSummary(Guid Id, string Name, string State, IReadOnlyList<string> Participants);

/// <summary>I gruppi SyncPlay (adattatore di ISyncPlayManager).</summary>
public interface IGroupDirectory
{
    /// <summary>
    /// I nomi utente dei partecipanti del gruppo, visto dalla sessione;
    /// null se il gruppo non esiste, l'utente non può vederlo o la sessione
    /// non c'è più.
    /// </summary>
    IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId);

    /// <summary>
    /// I gruppi visti dalla sessione (quelli di cui l'utente può vedere la
    /// coda); vuoto se la sessione non c'è.
    /// </summary>
    IReadOnlyList<GroupSummary> ListGroups(string sessionId);

    /// <summary>Il gruppo visto dalla sessione; null come per <see cref="GetParticipants"/>.</summary>
    GroupSummary? GetGroup(string sessionId, Guid groupId);
}
```

`Server/JellyfinGroupDirectory.cs` (tutto il file):

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Controller.SyncPlay.Requests;
using MediaBrowser.Model.SyncPlay;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I gruppi SyncPlay di Jellyfin.</summary>
public sealed class JellyfinGroupDirectory(
    ISessionManager sessionManager,
    ISyncPlayManager syncPlayManager) : IGroupDirectory
{
    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        GetGroup(sessionId, groupId)?.Participants;

    public IReadOnlyList<GroupSummary> ListGroups(string sessionId)
    {
        var session = Find(sessionId);
        return session is null
            ? []
            : syncPlayManager.ListGroups(session, new ListGroupsRequest()).Select(ToSummary).ToList();
    }

    public GroupSummary? GetGroup(string sessionId, Guid groupId)
    {
        var session = Find(sessionId);
        // GetGroup restituisce null se il gruppo non esiste o l'utente non
        // può vederne la coda.
        return session is not null && syncPlayManager.GetGroup(session, groupId) is { } group
            ? ToSummary(group)
            : null;
    }

    private SessionInfo? Find(string sessionId) =>
        sessionManager.Sessions.FirstOrDefault(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));

    private static GroupSummary ToSummary(GroupInfoDto group) =>
        new(group.GroupId, group.GroupName, group.State.ToString(), group.Participants);
}
```

In `…Tests/FakeServer.cs` aggiungi (usings invariati):

```csharp
    /// <summary>Nome di ogni gruppo; di default "Host · Titolo".</summary>
    public Dictionary<Guid, string> GroupNames { get; } = [];

    public IReadOnlyList<GroupSummary> ListGroups(string sessionId) =>
        Exists(sessionId) ? Groups.Keys.Select(Summary).ToList() : [];

    public GroupSummary? GetGroup(string sessionId, Guid groupId) =>
        Exists(sessionId) && Groups.ContainsKey(groupId) ? Summary(groupId) : null;

    private GroupSummary Summary(Guid groupId) =>
        new(groupId, GroupNames.GetValueOrDefault(groupId, "Host · Titolo"), "Idle", Groups[groupId]);
```

- [ ] **Step 4: gruppo di una sessione**

In `Hub/PartyRegistry.cs`, dopo `IsRegistered`:

```csharp
    /// <summary>Il gruppo in cui è registrata la sessione; null se in nessuno.</summary>
    public Guid? GroupOf(string sessionId)
    {
        lock (_lock)
        {
            foreach (var (groupId, sessions) in _groups)
            {
                if (sessions.ContainsKey(sessionId))
                {
                    return groupId;
                }
            }

            return null;
        }
    }
```

- [ ] **Step 5: amici per i party**

In `Hub/FriendService.cs`:
- dopo `Load()`:

```csharp
    public bool AreFriends(Guid a, Guid b)
    {
        lock (_lock)
        {
            return Graph.AreFriends(a, b);
        }
    }

    public IReadOnlyList<Guid> FriendsOf(Guid userId)
    {
        lock (_lock)
        {
            return Graph.FriendsOf(userId);
        }
    }
```

- `GetFriends` diventa (il party si chiede fuori dal lock, e solo per gli amici online):

```csharp
    /// <summary>
    /// Amici e richieste. partyOf dice il party visibile in cui sta un amico
    /// online (spec F §6.3); si chiama fuori dal lock.
    /// </summary>
    public FriendsResponse GetFriends(Guid userId, Func<Guid, FriendParty?>? partyOf = null)
    {
        var online = OnlineUsers();
        List<UserRef> friendUsers;
        List<PersonEntry> incoming;
        List<PersonEntry> outgoing;
        lock (_lock)
        {
            var graph = Graph;
            friendUsers = graph.FriendsOf(userId)
                .Select(id => users.GetUser(id))
                .OfType<UserRef>()
                .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
            incoming = People(graph.IncomingOf(userId).Select(r => r.From));
            outgoing = People(graph.OutgoingOf(userId).Select(r => r.To));
        }

        var friends = friendUsers
            .Select(u =>
            {
                var isOnline = online.Contains(u.Id);
                return new FriendEntry(Id(u.Id), u.Name, isOnline, isOnline ? partyOf?.Invoke(u.Id) : null);
            })
            .ToList();
        return new FriendsResponse(friends, incoming, outgoing);
    }
```

(se `People` è dichiarato come restituisce `List<PersonEntry>` va bene; se restituisce un altro tipo, adatta le variabili.)

- [ ] **Step 6: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → PASS, nessun warning.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): list syncplay groups and expose friendships to parties (#5)"
```

---

### Task 4: regole dei party (`PartyService`)

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyService.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/PartyServiceTests.cs`

- [ ] **Step 1: test che falliscono**

`PartyServiceTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PartyServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FriendService _friends;
    private readonly PartyRegistry _registry = new();
    private readonly PartyService _service;
    private readonly Guid _group = Guid.NewGuid();
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;
    private readonly CallerSession _marioSession;
    private readonly CallerSession _luigiSession;
    private readonly CallerSession _peachSession;

    public PartyServiceTests()
    {
        _friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _service = new PartyService(
            new PartyDirectory(_time), _server, _server, _server, _friends, _registry, _server,
            new RateLimiter(_time), NullLogger<PartyService>.Instance);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _marioSession = _server.AddSession("s-mario", _mario);
        _luigiSession = _server.AddSession("s-luigi", _luigi);
        _peachSession = _server.AddSession("s-peach", _peach);
        _server.Groups[_group] = ["Mario"];
        _server.GroupNames[_group] = "Mario · Dune";
    }

    public void Dispose() => _folder.Dispose();

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private async Task MakeFriends(UserRef a, UserRef b)
    {
        await _friends.RequestAsync(a.Id, b.Id);
        await _friends.AcceptAsync(b.Id, a.Id);
        _server.Sent.Clear();
    }

    private IEnumerable<string> Visible(CallerSession caller) => _service.ListVisible(caller).Select(p => p.GroupId);

    private string GroupN => _group.ToString("N");

    [Fact]
    public async Task RegistrationNeedsAParticipantAValidModeAndHappensOnce()
    {
        Assert.Equal(HubStatus.Forbidden, (await _service.RegisterAsync(_peachSession, _group, PartyModes.Public)).Status);
        Assert.Equal(HubStatus.Invalid, (await _service.RegisterAsync(_marioSession, _group, "public")).Status);
        var ok = await _service.RegisterAsync(_marioSession, _group, PartyModes.Public);
        Assert.Equal(HubStatus.Ok, ok.Status);
        Assert.Null(ok.Value!.Code);
        Assert.Equal(HubStatus.Conflict, (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Status);
    }

    [Fact]
    public async Task PublicPartiesAreAnnouncedToEveryoneElse()
    {
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Public);

        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("PartyStarted", json.GetProperty("Type").GetString());
        Assert.Equal(GroupN, json.GetProperty("GroupId").GetString());
        Assert.Equal("Mario · Dune", json.GetProperty("Name").GetString());
        Assert.Equal("Public", json.GetProperty("Mode").GetString());
        Assert.Single(_server.SentTo("s-peach"));
        Assert.Empty(_server.SentTo("s-mario"));
    }

    [Fact]
    public async Task FriendsPartiesAreAnnouncedOnlyToFriendsAndPrivateToNobody()
    {
        await MakeFriends(_mario, _luigi);
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Friends);
        Assert.Equal(new[] { "PartyStarted" }, _server.SentTo("s-luigi").Select(Type));
        Assert.Empty(_server.SentTo("s-peach"));

        var secret = Guid.NewGuid();
        _server.Groups[secret] = ["Mario"];
        _server.Sent.Clear();
        var code = (await _service.RegisterAsync(_marioSession, secret, PartyModes.Private)).Value!.Code;
        Assert.Equal(PartyDirectory.CodeLength, code!.Length);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task TheListFollowsTheModes()
    {
        await MakeFriends(_mario, _luigi);
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Friends);

        Assert.Equal(new[] { GroupN }, Visible(_marioSession));
        Assert.Equal(new[] { GroupN }, Visible(_luigiSession));
        Assert.Empty(Visible(_peachSession));
        var summary = _service.ListVisible(_luigiSession).Single();
        Assert.Equal("Friends", summary.Mode);
        Assert.Equal("Mario · Dune", summary.Name);
        Assert.Equal(new[] { "Mario" }, summary.Participants);
    }

    [Fact]
    public void UnregisteredGroupsShowUpAfterTheGraceAsPublic()
    {
        var other = Guid.NewGuid();
        _server.Groups[other] = ["Bowser"];
        Assert.DoesNotContain(other.ToString("N"), Visible(_peachSession));
        _time.Advance(PartyDirectory.UnregisteredGrace);
        var summary = _service.ListVisible(_peachSession).Single(p => p.GroupId == other.ToString("N"));
        Assert.Equal("Public", summary.Mode);
    }

    [Fact]
    public async Task DetailsOnlyForParticipants()
    {
        var code = (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Value!.Code;
        var details = _service.GetDetails(_marioSession, _group);
        Assert.Equal(HubStatus.Ok, details.Status);
        Assert.Equal(new PartyDetails("Private", code), details.Value);
        Assert.Equal(HubStatus.Forbidden, _service.GetDetails(_peachSession, _group).Status);
    }

    [Fact]
    public async Task TheCodeOpensThePartyAndAttemptsAreLimited()
    {
        var code = (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Value!.Code!;

        Assert.Equal(HubStatus.Forbidden, _service.JoinByCode(_peachSession, "ZZZZZZ").Status);
        var joined = _service.JoinByCode(_peachSession, $"{code[..3].ToLowerInvariant()}-{code[3..]}");
        Assert.Equal(HubStatus.Ok, joined.Status);
        Assert.Equal(GroupN, joined.Value!.GroupId);
        Assert.Equal(new[] { GroupN }, Visible(_peachSession));

        for (var i = 0; i < 3; i++)
        {
            _service.JoinByCode(_peachSession, "ZZZZZZ");
        }

        Assert.Equal(HubStatus.RateLimited, _service.JoinByCode(_peachSession, code).Status);
    }

    [Fact]
    public async Task ACodeOfAnEndedPartyDoesNotWork()
    {
        var code = (await _service.RegisterAsync(_marioSession, _group, PartyModes.Private)).Value!.Code!;
        _server.Groups.Remove(_group);
        Assert.Equal(HubStatus.Forbidden, _service.JoinByCode(_peachSession, code).Status);
        Assert.Equal(1, _service.Cleanup());
    }

    [Fact]
    public async Task InvitesGoOnlyToFriendsOutsideTheParty()
    {
        await MakeFriends(_mario, _luigi);
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Private);
        _server.Sent.Clear();

        Assert.Equal(HubStatus.Forbidden, await _service.InviteAsync(_peachSession, _group, [_luigi.Id.ToString("N")]));
        Assert.Equal(
            HubStatus.Ok,
            await _service.InviteAsync(_marioSession, _group, [_luigi.Id.ToString("N"), _peach.Id.ToString("N"), "nonsense"]));

        var payload = Assert.Single(_server.SentTo("s-luigi"));
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("PartyInvite", json.GetProperty("Type").GetString());
        Assert.Equal("Mario", json.GetProperty("FromName").GetString());
        Assert.Equal("Mario · Dune", json.GetProperty("Name").GetString());
        Assert.Empty(_server.SentTo("s-peach"));
        Assert.Equal(new[] { GroupN }, Visible(_luigiSession));
        Assert.Empty(Visible(_peachSession));
    }

    [Fact]
    public async Task InvitesAreLimitedPerMinute()
    {
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Private);
        var ids = new List<string>();
        for (var i = 0; i < 21; i++)
        {
            var friend = _server.AddUser($"Toad {i:00}");
            await _friends.RequestAsync(friend.Id, _mario.Id);
            await _friends.AcceptAsync(_mario.Id, friend.Id);
            ids.Add(friend.Id.ToString("N"));
        }

        Assert.Equal(HubStatus.RateLimited, await _service.InviteAsync(_marioSession, _group, ids));
    }

    [Fact]
    public async Task PartyOfAFriendIsShownOnlyIfVisible()
    {
        await MakeFriends(_luigi, _peach);
        _server.Groups[_group] = ["Mario", "Luigi"];
        _registry.Register(_group, "s-luigi", "Luigi");
        await _service.RegisterAsync(_marioSession, _group, PartyModes.Friends);

        Assert.Null(_service.PartyOf(_peach.Id, "Peach", _luigi.Id));
        await MakeFriends(_mario, _peach);
        Assert.Equal(new FriendParty(GroupN, "Dune"), _service.PartyOf(_peach.Id, "Peach", _luigi.Id));
        Assert.Null(_service.PartyOf(_peach.Id, "Peach", _mario.Id));
    }
}
```

(`PartyOf(_peach.Id, "Peach", _mario.Id)` è null perché Mario non ha una sessione registrata nel `PartyRegistry`: "in un party" vuol dire "con l'app dentro il gruppo".)

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`PartyService` non esiste).

- [ ] **Step 3: `PartyService`**

`Hub/PartyService.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Regole dei party (spec F §6.4–6.8): registrazione con la modalità,
/// elenco filtrato, dettagli, codici, inviti, "in un party" per la lista
/// amici, pulizia e avvisi. Non conosce Jellyfin: parla con le interfacce
/// di Hub.
/// </summary>
public sealed class PartyService(
    PartyDirectory parties,
    IGroupDirectory groups,
    ISessionDirectory sessions,
    IUserDirectory users,
    FriendService friends,
    PartyRegistry registry,
    IEventSender sender,
    RateLimiter limiter,
    ILogger<PartyService> logger)
{
    /// <summary>Registra il party appena creato da caller e avvisa chi lo deve sapere.</summary>
    public async Task<HubResult<RegisterPartyResponse>> RegisterAsync(CallerSession caller, Guid groupId, string? mode)
    {
        if (!PartyModes.IsValid(mode))
        {
            return HubResult<RegisterPartyResponse>.Fail(HubStatus.Invalid);
        }

        var group = groups.GetGroup(caller.SessionId, groupId);
        if (group is null || !IsParticipant(group, caller.UserName))
        {
            return HubResult<RegisterPartyResponse>.Fail(HubStatus.Forbidden);
        }

        var view = parties.Register(groupId, caller.UserId, mode!);
        if (view is null)
        {
            return HubResult<RegisterPartyResponse>.Fail(HubStatus.Conflict);
        }

        logger.LogDebug("Watch party {GroupId} registrato da {UserId}: {Mode}", groupId, caller.UserId, mode);
        await NotifyStartedAsync(caller.UserId, group, mode!).ConfigureAwait(false);
        return HubResult<RegisterPartyResponse>.Ok(new RegisterPartyResponse(view.Code));
    }

    /// <summary>I party che caller può vedere, dall'elenco SyncPlay della sua sessione.</summary>
    public IReadOnlyList<PartySummary> ListVisible(CallerSession caller)
    {
        var result = new List<PartySummary>();
        foreach (var group in groups.ListGroups(caller.SessionId))
        {
            parties.Seen(group.Id);
            if (!IsVisibleTo(group, caller.UserId, caller.UserName))
            {
                continue;
            }

            var mode = parties.Get(group.Id)?.Mode ?? PartyModes.Public;
            result.Add(new PartySummary(Id(group.Id), group.Name, group.State, group.Participants, mode));
        }

        return result;
    }

    /// <summary>Modalità e codice, per chi è nel gruppo.</summary>
    public HubResult<PartyDetails> GetDetails(CallerSession caller, Guid groupId)
    {
        var group = groups.GetGroup(caller.SessionId, groupId);
        if (group is null || !IsParticipant(group, caller.UserName))
        {
            return HubResult<PartyDetails>.Fail(HubStatus.Forbidden);
        }

        var view = parties.Get(groupId);
        return HubResult<PartyDetails>.Ok(new PartyDetails(view?.Mode ?? PartyModes.Public, view?.Code));
    }

    /// <summary>
    /// Il gruppo di un codice: chi lo usa diventa invitato (il party compare
    /// nel suo elenco). Ogni tentativo conta per il limite.
    /// </summary>
    public HubResult<JoinByCodeResponse> JoinByCode(CallerSession caller, string? code)
    {
        if (!limiter.TryAcquire(Id(caller.UserId), LimitTypes.CodeAttempts))
        {
            return HubResult<JoinByCodeResponse>.Fail(HubStatus.RateLimited);
        }

        var groupId = parties.FindByCode(code);
        // Un codice di un gruppo finito non vale più.
        if (groupId is null || groups.GetGroup(caller.SessionId, groupId.Value) is null)
        {
            return HubResult<JoinByCodeResponse>.Fail(HubStatus.Forbidden);
        }

        parties.Grant(groupId.Value, [caller.UserId]);
        return HubResult<JoinByCodeResponse>.Ok(new JoinByCodeResponse(Id(groupId.Value)));
    }

    /// <summary>
    /// Invita amici di caller che non sono nel party; gli altri id si saltano.
    /// Oltre il limite invita quelli che ci stanno e risponde RateLimited.
    /// </summary>
    public async Task<HubStatus> InviteAsync(CallerSession caller, Guid groupId, IReadOnlyList<string>? userIds)
    {
        var group = groups.GetGroup(caller.SessionId, groupId);
        if (group is null || !IsParticipant(group, caller.UserName))
        {
            return HubStatus.Forbidden;
        }

        var targets = new List<Guid>();
        var limited = false;
        foreach (var raw in userIds ?? [])
        {
            if (!Guid.TryParse(raw, out var id) || targets.Contains(id))
            {
                continue;
            }

            var user = users.GetUser(id);
            if (user is null || !friends.AreFriends(caller.UserId, id) || IsParticipant(group, user.Name))
            {
                continue;
            }

            if (!limiter.TryAcquire(Id(caller.UserId), LimitTypes.Invites))
            {
                limited = true;
                break;
            }

            targets.Add(id);
        }

        parties.Grant(groupId, targets);
        logger.LogDebug("Inviti al watch party {GroupId} da {UserId}: {Count}", groupId, caller.UserId, targets.Count);
        var payload = JsonSerializer.Serialize(SocialEvent.PartyInvite(Id(groupId), group.Name, caller.UserName));
        await Task.WhenAll(targets.Select(id => SendToUserAsync(id, payload))).ConfigureAwait(false);
        return limited ? HubStatus.RateLimited : HubStatus.Ok;
    }

    /// <summary>
    /// Il party in cui sta friendId (con l'app dentro il gruppo), se viewer
    /// può vederlo; null altrimenti (spec F §6.3).
    /// </summary>
    public FriendParty? PartyOf(Guid viewerId, string viewerName, Guid friendId)
    {
        foreach (var session in sessions.GetAppSessions().Where(s => s.UserId == friendId))
        {
            var groupId = registry.GroupOf(session.SessionId);
            if (groupId is null)
            {
                continue;
            }

            var group = groups.GetGroup(session.SessionId, groupId.Value);
            if (group is not null && IsVisibleTo(group, viewerId, viewerName))
            {
                return new FriendParty(Id(group.Id), TitleOf(group.Name));
            }
        }

        return null;
    }

    /// <summary>Toglie i party dei gruppi finiti; restituisce quanti.</summary>
    public int Cleanup()
    {
        var appSessions = sessions.GetAppSessions().Select(s => s.SessionId).ToList();
        return parties.Forget(groupId => appSessions.Any(sessionId => groups.GetGroup(sessionId, groupId) is not null));
    }

    private bool IsVisibleTo(GroupSummary group, Guid viewerId, string viewerName) =>
        IsParticipant(group, viewerName)
        || parties.IsVisible(group.Id, viewerId, creator => friends.AreFriends(creator, viewerId));

    private async Task NotifyStartedAsync(Guid creatorId, GroupSummary group, string mode)
    {
        IEnumerable<Guid> audience = mode switch
        {
            PartyModes.Public => sessions.GetAppSessions().Select(s => s.UserId).Distinct().Where(id => id != creatorId),
            PartyModes.Friends => friends.FriendsOf(creatorId),
            _ => [],
        };
        var payload = JsonSerializer.Serialize(SocialEvent.PartyStarted(Id(group.Id), group.Name, mode));
        await Task.WhenAll(audience.Select(id => SendToUserAsync(id, payload))).ConfigureAwait(false);
    }

    private async Task SendToUserAsync(Guid userId, string payload)
    {
        foreach (var session in sessions.GetAppSessions().Where(s => s.UserId == userId))
        {
            try
            {
                // Mai il token della richiesta: l'avviso non si ferma con lei.
                await sender.TrySendAsync(session.SessionId, payload, CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Avviso del party non inviato alla sessione {SessionId}", session.SessionId);
            }
        }
    }

    private static bool IsParticipant(GroupSummary group, string userName) =>
        group.Participants.Contains(userName, StringComparer.OrdinalIgnoreCase);

    /// <summary>Il titolo da "Host · Titolo"; il nome intero se non ha quella forma.</summary>
    private static string TitleOf(string name)
    {
        var separator = name.IndexOf(" · ", StringComparison.Ordinal);
        return separator < 0 ? name : name[(separator + 3)..];
    }

    private static string Id(Guid id) => id.ToString("N");
}
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → PASS, nessun warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add party registration, filtered list, codes and invites (#5)"
```

---

### Task 5: endpoint dei party, lista amici con il party, presenza a ingresso e uscita, pulizia

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/PartiesController.cs`
- Modify: `…/Api/FriendsController.cs`, `…/Api/WatchPartyController.cs`, `…/WatchPartyHostedService.cs`, `…/PluginServiceRegistrator.cs`, `jellyfin-plugin-watch-party/README.md`
- Test: `…Tests/PartiesControllerTests.cs`, `…Tests/FriendsControllerTests.cs`, `…Tests/WatchPartyControllerTests.cs`, `…Tests/WatchPartyHostedServiceTests.cs`, `…Tests/ServiceRegistrationTests.cs`

- [ ] **Step 1: test che falliscono**

`PartiesControllerTests.cs`:

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

public sealed class PartiesControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly User _peach = new("peach", "provider", "reset");
    private readonly Guid _group = Guid.NewGuid();
    private readonly PartyService _parties;

    public PartiesControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, true);
        _server.Users[_peach.Id] = new UserRef(_peach.Id, "Peach", true, true);
        _server.Sessions.Add(new CallerSession("s-mario", _mario.Id, "Mario"));
        _server.Sessions.Add(new CallerSession("s-peach", _peach.Id, "Peach"));
        _server.Groups[_group] = ["Mario"];
        var friends = new FriendService(
            new FriendStore(_folder.FriendsFile, NullLogger<FriendStore>.Instance),
            _server, _server, _server, new RateLimiter(_time), _time, NullLogger<FriendService>.Instance);
        _parties = new PartyService(
            new PartyDirectory(_time), _server, _server, _server, friends, new PartyRegistry(), _server,
            new RateLimiter(_time), NullLogger<PartyService>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    private PartiesController Controller(User user, string deviceId)
    {
        var auth = new AuthorizationInfo { DeviceId = deviceId, Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new PartiesController(new FakeAuthorizationContext(auth), _server, _parties)
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
    public async Task RegisterListDetailsAndCode()
    {
        var mario = Controller(_mario, "s-mario");
        var peach = Controller(_peach, "s-peach");

        var registered = await mario.Register(_group, new RegisterPartyRequest { Mode = PartyModes.Private });
        var code = registered.Value!.Code!;
        Assert.Equal(StatusCodes.Status409Conflict, Status((await mario.Register(_group, new RegisterPartyRequest { Mode = "Private" })).Result!));
        Assert.Equal(StatusCodes.Status400BadRequest, Status((await mario.Register(Guid.NewGuid(), new RegisterPartyRequest { Mode = "x" })).Result!));

        var details = await mario.Details(_group);
        Assert.Equal(code, details.Value!.Code);
        Assert.Equal(StatusCodes.Status403Forbidden, Status((await peach.Details(_group)).Result!));

        Assert.Empty(Assert.IsAssignableFrom<IReadOnlyList<PartySummary>>(
            Assert.IsType<OkObjectResult>((await peach.List()).Result).Value));
        var joined = await peach.JoinByCode(new JoinByCodeRequest { Code = code });
        Assert.Equal(_group.ToString("N"), joined.Value!.GroupId);
        Assert.Single(Assert.IsAssignableFrom<IReadOnlyList<PartySummary>>(
            Assert.IsType<OkObjectResult>((await peach.List()).Result).Value));
        Assert.Equal(StatusCodes.Status403Forbidden, Status((await peach.JoinByCode(new JoinByCodeRequest { Code = "ZZZZZZ" })).Result!));
    }

    [Fact]
    public async Task InvitesAndUnknownSessions()
    {
        var mario = Controller(_mario, "s-mario");
        await mario.Register(_group, new RegisterPartyRequest { Mode = PartyModes.Public });
        Assert.IsType<NoContentResult>(await mario.Invite(_group, new InviteRequest { UserIds = [] }));
        Assert.Equal(StatusCodes.Status403Forbidden, Status(await Controller(_peach, "s-peach").Invite(_group, new InviteRequest())));

        // Senza la sessione di chi chiama: 409, come il canale.
        var stranger = Controller(_mario, "altro-dispositivo");
        Assert.IsType<ConflictResult>((await stranger.List()).Result);
        Assert.IsType<ConflictResult>((await stranger.Register(_group, new RegisterPartyRequest { Mode = "Public" })).Result);
    }
}
```

In `FriendsControllerTests.cs`:
- il costruttore crea anche un `PartyService` (come in `PartiesControllerTests`, con `new PartyDirectory(_time)`, `_server`, `_friends`, `new PartyRegistry()`, `new RateLimiter(_time)`) e il controller diventa `new FriendsController(new FakeAuthorizationContext(auth), _friends, _parties)`;
- nuovo test:

```csharp
    [Fact]
    public async Task FriendsShowTheirVisibleParty()
    {
        await Controller(_mario).SendRequest(_luigi.Id);
        await Controller(_luigi).AcceptRequest(_mario.Id);
        var group = Guid.NewGuid();
        _server.Groups[group] = ["Luigi"];
        _server.GroupNames[group] = "Luigi · Dune";
        _server.Sessions.Add(new CallerSession("s-luigi", _luigi.Id, "Luigi"));
        _registry.Register(group, "s-luigi", "Luigi");
        await _parties.RegisterAsync(new CallerSession("s-luigi", _luigi.Id, "Luigi"), group, PartyModes.Friends);

        var friend = Assert.Single((await Controller(_mario).GetFriends()).Value!.Friends);
        Assert.Equal("Dune", friend.Party!.Title);
    }
```

(il `PartyRegistry` del test va tenuto in un campo `_registry` e passato al `PartyService`.)

In `WatchPartyControllerTests.cs`:
- il costruttore crea anche `FriendService` (con `TempFolder`) e `PresenceTracker`, e il controller diventa `new WatchPartyController(new FakeAuthorizationContext(auth), _server, _hub, _presence)`; la classe implementa `IDisposable` e cancella la cartella;
- nuovo test:

```csharp
    [Fact]
    public async Task JoiningOrLeavingTellsFriends()
    {
        var luigi = _server.AddUser("Luigi");
        _server.Users[_user.Id] = new UserRef(_user.Id, "Mario", true, true);
        _server.AddSession("s-luigi", luigi);
        await _friends.RequestAsync(_user.Id, luigi.Id);
        await _friends.AcceptAsync(luigi.Id, _user.Id);
        _server.Sent.Clear();

        await Controller().Join(Group);
        _time.Advance(PresenceTracker.Delay);
        Assert.Single(_server.SentTo("s-luigi"));

        await Controller().Leave(Group);
        _time.Advance(PresenceTracker.Delay);
        Assert.Equal(2, _server.SentTo("s-luigi").Count);
    }
```

In `WatchPartyHostedServiceTests.cs` i due servizi si costruiscono con anche un `PartyService` (dopo `presence`): `new WatchPartyHostedService(manager, hub, friends, presence, parties, time, NullLogger<WatchPartyHostedService>.Instance)`, con `parties` costruito come sopra (`new PartyService(new PartyDirectory(time), server, server, server, friends, new PartyRegistry(), server, new RateLimiter(time), NullLogger<PartyService>.Instance)`).

In `ServiceRegistrationTests.AllServicesResolve` aggiungi `Assert.NotNull(provider.GetRequiredService<PartyService>());`.

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`PartiesController`, costruttori nuovi).

- [ ] **Step 3: `PartiesController`**

`Api/PartiesController.cs`:

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
/// Endpoint dei party (spec F §6.7). Serve la sessione di chi chiama (i
/// gruppi SyncPlay si vedono da una sessione): senza, 409 come il canale.
/// Mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class PartiesController(
    IAuthorizationContext authorizationContext,
    ISessionDirectory sessions,
    PartyService parties) : ControllerBase
{
    /// <summary>Registra il party appena creato con la sua modalità.</summary>
    [HttpPost("Parties/{groupId:guid}")]
    public async Task<ActionResult<RegisterPartyResponse>> Register(
        [FromRoute] Guid groupId,
        [FromBody] RegisterPartyRequest? request)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = await parties.RegisterAsync(caller, groupId, request?.Mode).ConfigureAwait(false);
        return result.Status == HubStatus.Ok ? result.Value! : Failure(result.Status);
    }

    /// <summary>I party che chi chiama può vedere.</summary>
    [HttpGet("Parties")]
    public async Task<ActionResult<IReadOnlyList<PartySummary>>> List()
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        return caller is null ? Conflict() : Ok(parties.ListVisible(caller));
    }

    /// <summary>Modalità e codice, per chi è nel gruppo.</summary>
    [HttpGet("Parties/{groupId:guid}")]
    public async Task<ActionResult<PartyDetails>> Details([FromRoute] Guid groupId)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = parties.GetDetails(caller, groupId);
        return result.Status == HubStatus.Ok ? result.Value! : Failure(result.Status);
    }

    /// <summary>Il gruppo di un codice.</summary>
    [HttpPost("Parties/Join")]
    public async Task<ActionResult<JoinByCodeResponse>> JoinByCode([FromBody] JoinByCodeRequest? request)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = parties.JoinByCode(caller, request?.Code);
        return result.Status == HubStatus.Ok ? result.Value! : Failure(result.Status);
    }

    /// <summary>Invita amici di chi chiama.</summary>
    [HttpPost("Parties/{groupId:guid}/Invites")]
    public async Task<ActionResult> Invite([FromRoute] Guid groupId, [FromBody] InviteRequest? request)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var status = await parties.InviteAsync(caller, groupId, request?.UserIds).ConfigureAwait(false);
        return status == HubStatus.Ok ? NoContent() : Failure(status);
    }

    private ActionResult Failure(HubStatus status) => status switch
    {
        HubStatus.Forbidden => StatusCode(StatusCodes.Status403Forbidden),
        HubStatus.Conflict => Conflict(),
        HubStatus.RateLimited => StatusCode(StatusCodes.Status429TooManyRequests),
        _ => BadRequest(),
    };

    private async Task<CallerSession?> FindCallerAsync()
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        return sessions.FindCaller(auth.DeviceId, auth.Client, auth.UserId);
    }
}
```

- [ ] **Step 4: lista amici con il party**

In `Api/FriendsController.cs`:
- il costruttore prende anche `PartyService parties`;
- `GetFriends` diventa:

```csharp
    /// <summary>Amici con il loro stato (e il party visibile in cui stanno), richieste in arrivo e inviate.</summary>
    [HttpGet("Friends")]
    public async Task<ActionResult<FriendsResponse>> GetFriends()
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        var userName = auth.User?.Username ?? string.Empty;
        return friends.GetFriends(auth.UserId, friendId => parties.PartyOf(auth.UserId, userName, friendId));
    }
```

- [ ] **Step 5: presenza a ingresso e uscita dal canale**

In `Api/WatchPartyController.cs`:
- il costruttore prende anche `PresenceTracker presence`;
- in `Join`, dopo un `hub.Join` riuscito e prima del `return new JoinResponse(...)`: `presence.Changed(caller.UserId);`
- in `Leave`, dentro `if (caller is not null)`, dopo `hub.Leave(...)`: `presence.Changed(caller.UserId);`
- nel commento della classe: "Ingresso e uscita cambiano la presenza: gli amici vedono "Nel watch party" (spec F §6.3)."

- [ ] **Step 6: pulizia e servizi**

In `WatchPartyHostedService.cs`:
- il costruttore prende anche `PartyService parties` (dopo `presence`);
- in `Cleanup()`, dopo il blocco di `hub.Cleanup()` (dentro lo stesso `try`):

```csharp
            var removedParties = parties.Cleanup();
            if (removedParties > 0)
            {
                logger.LogDebug("Tolti {Count} party finiti", removedParties);
            }
```

(con i costruttori primari `parties` è il parametro, non un campo: niente `this.`.)

In `PluginServiceRegistrator.cs`, dopo `PresenceTracker`:

```csharp
        serviceCollection.AddSingleton<PartyDirectory>();
        serviceCollection.AddSingleton<PartyService>();
```

In `README.md` (elenco puntato iniziale) aggiungi:

```markdown
- **Party:** l'app registra ogni gruppo con la sua modalità (pubblico, solo
  amici, privato con codice) e chiede al plugin l'elenco già filtrato
  (`GET Parties`). I party stanno in RAM e spariscono con i gruppi SyncPlay.
```

- [ ] **Step 7: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → PASS, nessun warning. Poi `bash jellyfin-plugin-watch-party/pack.sh 1.1.0` → cartella `artifacts/WonderFlix Watch Party_1.1.0.0/`.

- [ ] **Step 8: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): expose the party endpoints and party presence (#5)"
```

---

### Task 6: il plugin aggiornato sul server (orchestratore, nessun subagent)

Il piano **si ferma qui** finché il plugin non gira sul server. Lo fa l'orchestratore (accesso `ssh ultra` autorizzato); nessun file del repository cambia.

- [ ] **Step 1: compatibilità con il server.** Nella scratchpad, un progetto console `net9.0` con `<FrameworkReference Include="Microsoft.AspNetCore.App" />` e i pacchetti `Jellyfin.Controller`/`Jellyfin.Model` **10.11.9**, che carica la dll del plugin e risolve ogni `TypeReference` e `MemberReference` (`System.Reflection.Metadata`, `module.ResolveType`/`ResolveMember`; ignora `BadImageFormatException`/`ArgumentException` dei membri di tipi generici). Atteso: **0 non risolti**. Se qualcosa non si risolve, si torna al gruppo A.
- [ ] **Step 2:** controllare nel log di Jellyfin (`~/.apps/jellyfin/log/log_<data>.log`, righe `PlaybackReporting`) che nessuno stia guardando; se sì, chiedere all'utente.
- [ ] **Step 3:** copia della dll e del `meta.json` sopra la cartella copiata a mano nel 12a, e riavvio:

```bash
scp "jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.1.0.0/Jellyfin.Plugin.WonderFlixWatchParty.dll" "jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.1.0.0/meta.json" "ultra:.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.1.0.0/"
ssh ultra app-jellyfin restart
```

- [ ] **Step 4:** nel log: `Loaded plugin: "WonderFlix Watch Party" "1.1.0.0"`, `avviato`, `Amici in …`, nessuna eccezione. Esito all'utente; poi gruppo B. Le app 0.5.1 e la build del 12a continuano a funzionare (`Features` cresce, il protocollo no).

---

## Gruppo B — nucleo nell'app

### Task 7: testi dei party

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan12b_test.dart`

- [ ] **Step 1: test che fallisce**

`test/app/l10n_plan12b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 12b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.friendsInParty('Dune'), 'Nel watch party: Dune');
    expect(it.partyModePublic, 'Pubblico');
    expect(it.partyModePublicHint, 'Lo vedono tutti, avviso a tutti');
    expect(it.partyModeFriends, 'Solo amici');
    expect(it.partyModeFriendsHint, 'Lo vedono i tuoi amici, avviso solo a loro');
    expect(it.partyModePrivate, 'Privato');
    expect(it.partyModePrivateHint,
        'Nessun avviso; si entra con il codice o con un invito');
    expect(it.partyCreateFailed, 'Non è stato possibile creare il watch party');
    expect(it.partyHaveCode, 'Ho un codice');
    expect(it.partyCodeHint, 'Codice del party');
    expect(it.partyCodeJoin, 'Entra');
    expect(it.partyCodeInvalid, 'Codice non valido o party finito');
    expect(it.partyCodeTooMany, 'Troppi tentativi, riprova tra un minuto');
    expect(it.partyCode('K7P-Q2X'), 'Codice K7P-Q2X');
    expect(it.partyCodeCopied, 'Codice copiato');
    expect(it.partyPrivateCreated('K7P-Q2X'), 'Party privato · codice K7P-Q2X');
    expect(it.partyInviteFriends, 'Invita amici');
    expect(it.partyInvited, 'Invitato');
    expect(it.partyInviteSent('Luigi'), 'Invito mandato a Luigi');
    expect(it.partyNoFriendsToInvite, 'Nessun amico da invitare');
    expect(it.partyInviteTitle('Luigi'), 'Luigi ti invita');
    expect(en.friendsInParty('Dune'), 'In a watch party: Dune');
    expect(en.partyModePublic, 'Public');
    expect(en.partyModePublicHint, 'Everyone sees it and gets notified');
    expect(en.partyModeFriends, 'Friends only');
    expect(en.partyModeFriendsHint,
        'Only your friends see it and get notified');
    expect(en.partyModePrivate, 'Private');
    expect(en.partyModePrivateHint,
        'No notifications; join with the code or an invite');
    expect(en.partyCreateFailed, "Couldn't create the watch party");
    expect(en.partyHaveCode, 'I have a code');
    expect(en.partyCodeHint, 'Party code');
    expect(en.partyCodeJoin, 'Join');
    expect(en.partyCodeInvalid, 'Invalid code or the party has ended');
    expect(en.partyCodeTooMany, 'Too many attempts, try again in a minute');
    expect(en.partyCode('K7P-Q2X'), 'Code K7P-Q2X');
    expect(en.partyCodeCopied, 'Code copied');
    expect(en.partyPrivateCreated('K7P-Q2X'), 'Private party · code K7P-Q2X');
    expect(en.partyInviteFriends, 'Invite friends');
    expect(en.partyInvited, 'Invited');
    expect(en.partyInviteSent('Luigi'), 'Invite sent to Luigi');
    expect(en.partyNoFriendsToInvite, 'No friends to invite');
    expect(en.partyInviteTitle('Luigi'), 'Luigi invites you');
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan12b_test.dart`
Expected: errori di compilazione (`friendsInParty` non esiste).

- [ ] **Step 3: testi**

In `l10n/app_it.arb`, dopo l'ultima chiave (oggi `"@friendRequestTitle": {...}`; metti la virgola alla riga prima):

```json
  "friendsInParty": "Nel watch party: {title}",
  "@friendsInParty": {"placeholders": {"title": {"type": "String"}}},
  "partyModePublic": "Pubblico",
  "partyModePublicHint": "Lo vedono tutti, avviso a tutti",
  "partyModeFriends": "Solo amici",
  "partyModeFriendsHint": "Lo vedono i tuoi amici, avviso solo a loro",
  "partyModePrivate": "Privato",
  "partyModePrivateHint": "Nessun avviso; si entra con il codice o con un invito",
  "partyCreateFailed": "Non è stato possibile creare il watch party",
  "partyHaveCode": "Ho un codice",
  "partyCodeHint": "Codice del party",
  "partyCodeJoin": "Entra",
  "partyCodeInvalid": "Codice non valido o party finito",
  "partyCodeTooMany": "Troppi tentativi, riprova tra un minuto",
  "partyCode": "Codice {code}",
  "@partyCode": {"placeholders": {"code": {"type": "String"}}},
  "partyCodeCopied": "Codice copiato",
  "partyPrivateCreated": "Party privato · codice {code}",
  "@partyPrivateCreated": {"placeholders": {"code": {"type": "String"}}},
  "partyInviteFriends": "Invita amici",
  "partyInvited": "Invitato",
  "partyInviteSent": "Invito mandato a {name}",
  "@partyInviteSent": {"placeholders": {"name": {"type": "String"}}},
  "partyNoFriendsToInvite": "Nessun amico da invitare",
  "partyInviteTitle": "{name} ti invita",
  "@partyInviteTitle": {"placeholders": {"name": {"type": "String"}}}
```

In `l10n/app_en.arb`, dopo l'ultima chiave (oggi `"friendRequestTitle": ...`; virgola alla riga prima):

```json
  "friendsInParty": "In a watch party: {title}",
  "partyModePublic": "Public",
  "partyModePublicHint": "Everyone sees it and gets notified",
  "partyModeFriends": "Friends only",
  "partyModeFriendsHint": "Only your friends see it and get notified",
  "partyModePrivate": "Private",
  "partyModePrivateHint": "No notifications; join with the code or an invite",
  "partyCreateFailed": "Couldn't create the watch party",
  "partyHaveCode": "I have a code",
  "partyCodeHint": "Party code",
  "partyCodeJoin": "Join",
  "partyCodeInvalid": "Invalid code or the party has ended",
  "partyCodeTooMany": "Too many attempts, try again in a minute",
  "partyCode": "Code {code}",
  "partyCodeCopied": "Code copied",
  "partyPrivateCreated": "Private party · code {code}",
  "partyInviteFriends": "Invite friends",
  "partyInvited": "Invited",
  "partyInviteSent": "Invite sent to {name}",
  "partyNoFriendsToInvite": "No friends to invite",
  "partyInviteTitle": "{name} invites you"
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: verifica**

Run: `flutter test test/app/l10n_plan12b_test.dart` → PASS; `flutter analyze`; `flutter test` → tutto verde (1314).

- [ ] **Step 5: commit**

```bash
git add l10n test/app/l10n_plan12b_test.dart
git commit -m "feat: add the party mode strings (#5)"
```

---

### Task 8: modalità, modelli e chiamate dei party

**Files:**
- Create: `lib/core/syncplay/party_mode.dart`
- Modify: `lib/core/syncplay/syncplay_models.dart` (`GroupInfo.mode`)
- Modify: `lib/core/social/social_models.dart`, `lib/core/social/social_api.dart`
- Modify: `lib/core/party_channel/party_channel_models.dart` (`socialEventTypes`)
- Modify: `test/support/social_fakes.dart`
- Test: `test/core/social/social_models_test.dart`, `test/core/social/social_api_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/core/social/social_models_test.dart` (import di `package:wonderflix/core/syncplay/party_mode.dart` e `package:wonderflix/core/syncplay/syncplay_models.dart`) aggiungi:

```dart
  test('modalità in rete', () {
    expect(PartyMode.fromWire('Friends'), PartyMode.friends);
    expect(PartyMode.private.wire, 'Private');
    expect(PartyMode.fromWire('friends'), isNull);
  });

  test('party dell\'elenco del plugin come gruppi con la modalità', () {
    final group = partyGroupFromJson({
      'GroupId': 'g1',
      'Name': 'Mario · Dune',
      'State': 'Playing',
      'Participants': ['Mario', 'Luigi'],
      'Mode': 'Private',
    });
    expect(group.id, 'g1');
    expect(group.name, 'Mario · Dune');
    expect(group.state, GroupState.playing);
    expect(group.participants, ['Mario', 'Luigi']);
    expect(group.mode, PartyMode.private);
    expect(partyGroupFromJson({'GroupId': 'g2'}).mode, PartyMode.public);
  });

  test('dettagli del party: il codice può mancare', () {
    final private =
        PartyDetails.fromJson({'Mode': 'Private', 'Code': 'K7PQ2X'});
    expect(private.mode, PartyMode.private);
    expect(private.code, 'K7PQ2X');
    expect(PartyDetails.fromJson({'Mode': 'Public'}).code, isNull);
  });

  test('avvisi dei party', () {
    final started = parseSocialEvent('{"Protocol":1,"Type":"PartyStarted",'
        '"GroupId":"g1","Name":"Mario \\u00b7 Dune","Mode":"Friends"}');
    expect(started, isA<PartyStartedEvent>());
    started as PartyStartedEvent;
    expect(started.groupId, 'g1');
    expect(started.name, 'Mario · Dune');
    expect(started.mode, PartyMode.friends);
    final invite = parseSocialEvent('{"Protocol":1,"Type":"PartyInvite",'
        '"FromName":"Mario","GroupId":"g1","Name":"Mario · Dune"}');
    expect((invite! as PartyInviteEvent).fromName, 'Mario');
  });

  test('codici: forma canonica e forma da mostrare', () {
    expect(normalizePartyCode(' k7p-q2x '), 'K7PQ2X');
    expect(formatPartyCode('k7pq2x'), 'K7P-Q2X');
    expect(formatPartyCode('K7P'), 'K7P');
  });
```

In `test/core/party_channel/party_channel_models_test.dart`, nel test 'gli avvisi degli amici si scartano senza scrivere nel log' aggiungi prima di `expect(records, isEmpty)`:

```dart
    expect(
        parsePartyEvent('{"Protocol":1,"Type":"PartyStarted","GroupId":"g1",'
            '"Name":"Dune","Mode":"Public"}'),
        isNull);
    expect(
        parsePartyEvent('{"Protocol":1,"Type":"PartyInvite","GroupId":"g1",'
            '"Name":"Dune","FromName":"Mario"}'),
        isNull);
```

In `test/core/social/social_api_test.dart` aggiungi (import di `party_mode.dart`):

```dart
  test('party: registrazione, elenco, dettagli, codice, inviti', () async {
    adapter.handler = (options) => switch ('${options.method} ${options.path}') {
          'POST /WonderFlixWatchParty/Parties/g1' =>
            const FakeResponse(200, {'Code': 'K7PQ2X'}),
          'GET /WonderFlixWatchParty/Parties' => const FakeResponse(200, [
              {
                'GroupId': 'g1',
                'Name': 'Mario · Dune',
                'State': 'Idle',
                'Participants': ['Mario'],
                'Mode': 'Private',
              },
            ]),
          'GET /WonderFlixWatchParty/Parties/g1' =>
            const FakeResponse(200, {'Mode': 'Private', 'Code': 'K7PQ2X'}),
          'POST /WonderFlixWatchParty/Parties/Join' =>
            const FakeResponse(200, {'GroupId': 'g1'}),
          _ => const FakeResponse(204),
        };

    expect(await api.registerParty('g1', PartyMode.private), 'K7PQ2X');
    expect(adapter.requests.last.data, {'Mode': 'Private'});
    expect((await api.parties()).single.mode, PartyMode.private);
    expect((await api.partyDetails('g1')).code, 'K7PQ2X');
    expect(await api.joinByCode('K7PQ2X'), 'g1');
    expect(adapter.requests.last.data, {'Code': 'K7PQ2X'});
    await api.invite('g1', ['u2', 'u3']);
    expect(adapter.requests.last.path,
        '/WonderFlixWatchParty/Parties/g1/Invites');
    expect(adapter.requests.last.data, {
      'UserIds': ['u2', 'u3'],
    });
  });

  test('party: registrazione senza codice e codice sbagliato', () async {
    adapter.handler = (_) => const FakeResponse(200, <String, dynamic>{});
    expect(await api.registerParty('g1', PartyMode.public), isNull);
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(
        api.joinByCode('ZZZZZZ'),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.forbidden)));
  });
```

(se `RequestOptions.data` arriva già come stringa JSON invece che come mappa, confronta con `jsonDecode(... as String)` e segnalalo.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core`
Expected: errori di compilazione (`PartyMode`, `partyGroupFromJson`, `PartyDetails`, `registerParty` non esistono).

- [ ] **Step 3: modalità e `GroupInfo.mode`**

`lib/core/syncplay/party_mode.dart`:

```dart
/// Modalità di un watch party (spec F §6.4). In rete `Public`, `Friends`,
/// `Private`.
enum PartyMode {
  public('Public'),
  friends('Friends'),
  private('Private');

  const PartyMode(this.wire);

  final String wire;

  static PartyMode? fromWire(Object? value) {
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return null;
  }
}
```

In `lib/core/syncplay/syncplay_models.dart`:
- `import 'party_mode.dart';` ed `export 'party_mode.dart';` in cima (così chi usa `GroupInfo` ha anche `PartyMode`);
- in `GroupInfo`: parametro `this.mode` (facoltativo) nel costruttore, campo

```dart
  /// Modalità del party, se l'elenco viene dal plugin (spec F §9.6);
  /// `null` dall'elenco di Jellyfin.
  final PartyMode? mode;
```

- `copyWith` passa `mode: mode`.

- [ ] **Step 4: modelli e avvisi dei party**

In `lib/core/party_channel/party_channel_models.dart`:

```dart
const socialEventTypes = {
  'FriendRequest',
  'FriendsChanged',
  'PartyStarted',
  'PartyInvite',
};
```

In `lib/core/social/social_models.dart`:
- import di `../syncplay/syncplay_models.dart`;
- dopo `UserSearchResult`:

```dart
/// Lettere di un codice dei party privati (spec F §6.5).
const partyCodeLength = 6;

/// Il codice senza spazi e trattini, in maiuscolo: come lo vuole il plugin.
String normalizePartyCode(String text) =>
    text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

/// Il codice come si mostra: `K7P-Q2X`.
String formatPartyCode(String code) {
  final normalized = normalizePartyCode(code);
  return normalized.length == partyCodeLength
      ? '${normalized.substring(0, 3)}-${normalized.substring(3)}'
      : normalized;
}

/// Un party di `GET Parties` come gruppo SyncPlay con la modalità.
GroupInfo partyGroupFromJson(Map<String, dynamic> json) => GroupInfo(
      id: json['GroupId'] as String,
      name: json['Name'] as String? ?? '',
      state: parseGroupState(json['State']) ?? GroupState.idle,
      participants: (json['Participants'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      lastUpdatedAt: DateTime.utc(1970),
      mode: PartyMode.fromWire(json['Mode']) ?? PartyMode.public,
    );

/// Modalità e codice del party in cui siamo (`GET Parties/{groupId}`).
class PartyDetails {
  const PartyDetails({required this.mode, this.code});

  factory PartyDetails.fromJson(Map<String, dynamic> json) => PartyDetails(
        mode: PartyMode.fromWire(json['Mode']) ?? PartyMode.public,
        code: json['Code'] as String?,
      );

  final PartyMode mode;

  /// Solo per i privati (il plugin può ometterlo se `null`).
  final String? code;
}
```

- dopo `FriendsChangedEvent`:

```dart
/// Un party appena nato che possiamo vedere (pubblico, o di un amico).
final class PartyStartedEvent extends SocialEvent {
  const PartyStartedEvent(
      {required this.groupId, required this.name, required this.mode});

  final String groupId;

  /// "Host · Titolo".
  final String name;
  final PartyMode mode;
}

/// Un amico ci invita nel suo party.
final class PartyInviteEvent extends SocialEvent {
  const PartyInviteEvent(
      {required this.groupId, required this.name, required this.fromName});

  final String groupId;
  final String name;
  final String fromName;
}
```

- nello `switch` di `parseSocialEvent`:

```dart
      case 'PartyStarted':
        return PartyStartedEvent(
          groupId: json['GroupId'] as String,
          name: json['Name'] as String,
          mode: PartyMode.fromWire(json['Mode']) ?? PartyMode.public,
        );
      case 'PartyInvite':
        return PartyInviteEvent(
          groupId: json['GroupId'] as String,
          name: json['Name'] as String,
          fromName: json['FromName'] as String,
        );
```

- [ ] **Step 5: chiamate dei party**

In `lib/core/social/social_api.dart` (import di `../syncplay/syncplay_models.dart`), dopo `remove`:

```dart
  /// Registra il party appena creato (spec F §6.4): il codice per un
  /// privato, altrimenti `null`.
  Future<String?> registerParty(String groupId, PartyMode mode) =>
      _call(() async {
        final json = asJsonMap(await _http.post('$_base/Parties/$groupId',
            body: {'Mode': mode.wire}, quietStatuses: _quiet));
        return json['Code'] as String?;
      });

  /// I party che possiamo vedere, già filtrati dal plugin.
  Future<List<GroupInfo>> parties() => _call(() async {
        final json = await _http.get('$_base/Parties', quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            partyGroupFromJson(raw as Map<String, dynamic>),
        ];
      });

  /// Modalità e codice del party in cui siamo.
  Future<PartyDetails> partyDetails(String groupId) => _call(() async =>
      PartyDetails.fromJson(asJsonMap(await _http
          .get('$_base/Parties/$groupId', quietStatuses: _quiet))));

  /// Il gruppo di un codice (già in forma canonica).
  Future<String> joinByCode(String code) => _call(() async =>
      asJsonMap(await _http.post('$_base/Parties/Join',
          body: {'Code': code}, quietStatuses: _quiet))['GroupId'] as String);

  /// Invita amici nel party (solo i nostri amici fuori dal gruppo).
  Future<void> invite(String groupId, List<String> userIds) => _call(() =>
      _http.post('$_base/Parties/$groupId/Invites',
          body: {'UserIds': userIds}, quietStatuses: _quiet));
```

- [ ] **Step 6: finti**

In `test/support/social_fakes.dart` (import di `package:wonderflix/core/syncplay/syncplay_models.dart`), dentro `FakeSocialApi`:

```dart
  /// Codice di [registerParty] per i privati (come il plugin).
  String registerCode = 'K7PQ2X';

  /// Errore di [registerParty], se valorizzato.
  SocialFailure? registerFailure;

  /// Chiamato a ogni [registerParty], prima della risposta.
  void Function()? onRegister;

  /// Risposta di [parties].
  List<GroupInfo> partyList = const [];

  /// Risposte di [partyDetails], per gruppo (di default pubblico).
  final details = <String, PartyDetails>{};

  /// Codice canonico → gruppo, per [joinByCode]; un codice assente è 403.
  final codes = <String, String>{};

  /// Errore di [joinByCode], se valorizzato (prima di [codes]).
  SocialFailure? joinFailure;

  @override
  Future<String?> registerParty(String groupId, PartyMode mode) async {
    calls.add('register $groupId ${mode.wire}');
    onRegister?.call();
    final failure = registerFailure;
    if (failure != null) throw SocialException(failure);
    return mode == PartyMode.private ? registerCode : null;
  }

  @override
  Future<List<GroupInfo>> parties() async {
    calls.add('parties');
    _fail();
    return partyList;
  }

  @override
  Future<PartyDetails> partyDetails(String groupId) async {
    calls.add('details $groupId');
    _fail();
    return details[groupId] ?? const PartyDetails(mode: PartyMode.public);
  }

  @override
  Future<String> joinByCode(String code) async {
    calls.add('code $code');
    final failure = joinFailure;
    if (failure != null) throw SocialException(failure);
    final groupId = codes[code];
    if (groupId == null) throw const SocialException(SocialFailure.forbidden);
    return groupId;
  }

  @override
  Future<void> invite(String groupId, List<String> userIds) async {
    calls.add('invite $groupId ${userIds.join(',')}');
    _fail();
  }
```

e in fondo al file:

```dart
/// Come arriva dal WebSocket un party appena nato.
PartyChannelReceived partyStartedReceived(String groupId, String name,
        {PartyMode mode = PartyMode.public}) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'PartyStarted',
      'GroupId': groupId,
      'Name': name,
      'Mode': mode.wire,
    }));

/// Come arriva dal WebSocket un invito in un party.
PartyChannelReceived partyInviteReceived(
        String groupId, String name, String fromName) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'PartyInvite',
      'GroupId': groupId,
      'Name': name,
      'FromName': fromName,
    }));
```

- [ ] **Step 7: verifica**

Run: `flutter test test/core` → PASS. `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 8: commit**

```bash
git add lib/core test/core test/support/social_fakes.dart
git commit -m "feat: add party modes, models and plugin calls (#5)"
```

---

### Task 9: registrazione del party, ultima modalità, party corrente

**Files:**
- Modify: `lib/features/watch_party/watch_party_session.dart` (`create`, `WatchPartyFailure`)
- Modify: `lib/features/watch_party/watch_party_actions.dart` (`startWatchParty`, `watchPartyErrorText`)
- Create: `lib/features/watch_party/party_mode_preference.dart`
- Create: `lib/features/watch_party/current_party.dart`
- Test: `test/features/watch_party/watch_party_actions_test.dart`, `test/features/watch_party/party_mode_preference_test.dart`, `test/features/watch_party/current_party_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/features/watch_party/watch_party_actions_test.dart` (import di `package:shared_preferences/shared_preferences.dart`, `package:wonderflix/app/providers.dart`, `package:wonderflix/core/social/social_api.dart`, `package:wonderflix/core/syncplay/party_mode.dart`, `package:wonderflix/features/social/social_providers.dart`, `package:wonderflix/features/watch_party/current_party.dart`, `../../support/social_fakes.dart`), dentro `main` dopo `pumpButton`:

```dart
  late FakeSocialApi social;

  Future<void> pumpModeButton(WidgetTester tester, PartyMode mode) async {
    social = FakeSocialApi();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => unawaited(
                startWatchParty(context, ref, pilot, mode: mode)),
            child: const Text('via'),
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider.overrideWithValue(channelApi),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  }

  testWidgets('con una modalità: registra il party prima della coda',
      (tester) async {
    await pumpModeButton(tester, PartyMode.friends);
    var queuesAtRegister = -1;
    social.onRegister = () =>
        queuesAtRegister = api.calls.where((c) => c.startsWith('queue')).length;
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(social.calls, contains('register g1 Friends'));
    expect(queuesAtRegister, 0, reason: 'la coda arriva dopo la registrazione');
    expect(api.calls, ['create Mario · Breaking Bad', 'queue e4,e5']);
    await leave(tester);
  });

  testWidgets('privato: il codice resta nel party corrente, da annunciare',
      (tester) async {
    await pumpModeButton(tester, PartyMode.private);
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    final current = container(tester).read(currentPartyProvider);
    expect(current?.groupId, 'g1');
    expect(current?.mode, PartyMode.private);
    expect(current?.code, 'K7PQ2X');
    expect(current?.announceCode, isTrue);
    await leave(tester);
  });

  testWidgets('registrazione fallita: esce dal gruppo e lo dice',
      (tester) async {
    await pumpModeButton(tester, PartyMode.private);
    social.registerFailure = SocialFailure.network;
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect(api.calls, ['create Mario · Breaking Bad', 'leave']);
    expect(find.text('Non è stato possibile creare il watch party'),
        findsOneWidget);
    expect(container(tester).read(watchPartySessionProvider).inGroup, isFalse);
  });
```

(se `FakeSyncPlayApi` registra l'uscita con un nome diverso da `leave`, usa quello; il nome del creatore viene da `testUser` = Mario.)

`test/features/watch_party/party_mode_preference_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/syncplay/party_mode.dart';
import 'package:wonderflix/features/watch_party/party_mode_preference.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  }

  test('di default pubblico; la scelta si ricorda', () async {
    final first = await container({});
    expect(first.read(partyModePreferenceProvider), PartyMode.public);
    await first.read(partyModePreferenceProvider.notifier).set(PartyMode.friends);
    expect(first.read(partyModePreferenceProvider), PartyMode.friends);

    final prefs = first.read(sharedPreferencesProvider);
    expect(prefs.getString(PartyModePreference.key), 'Friends');
  });

  test('legge il valore salvato; uno sconosciuto vale pubblico', () async {
    expect((await container({PartyModePreference.key: 'Private'}))
        .read(partyModePreferenceProvider), PartyMode.private);
    expect((await container({PartyModePreference.key: 'boh'}))
        .read(partyModePreferenceProvider), PartyMode.public);
  });
}
```

`test/features/watch_party/current_party_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/current_party.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi social;
  late FakeSyncPlayApi syncPlay;
  late StreamController<ServerEvent> events;

  setUp(() {
    social = FakeSocialApi();
    syncPlay = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    syncPlay.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  ProviderContainer container({bool parties = true}) {
    final c = ProviderContainer.test(overrides: [
      ...socialTestOverrides(social,
          events: events.stream,
          features: SocialFeatures(friends: true, parties: parties)),
      syncPlayApiProvider.overrideWithValue(syncPlay),
    ]);
    c.listen(currentPartyProvider, (_, _) {});
    return c;
  }

  test('nel gruppo legge modalità e codice; fuori niente', () async {
    social.details['g1'] =
        const PartyDetails(mode: PartyMode.private, code: 'K7PQ2X');
    final c = container();
    expect(c.read(currentPartyProvider), isNull);
    await c.read(watchPartySessionProvider.notifier).join('g1');
    await pumpEventQueue();
    final current = c.read(currentPartyProvider)!;
    expect(current.code, 'K7PQ2X');
    expect(current.announceCode, isFalse,
        reason: 'si annuncia solo il party appena creato da noi');

    await c.read(watchPartySessionProvider.notifier).leave();
    await pumpEventQueue();
    expect(c.read(currentPartyProvider), isNull);
  });

  test('senza la funzione parties: niente', () async {
    final c = container(parties: false);
    await c.read(watchPartySessionProvider.notifier).join('g1');
    await pumpEventQueue();
    expect(c.read(currentPartyProvider), isNull);
    expect(social.calls, isNot(contains('details g1')));
    await c.read(watchPartySessionProvider.notifier).leave();
  });

  test('registrato da noi: la lettura non lo sovrascrive, il codice si '
      'annuncia una volta', () async {
    // Una lettura dei dettagli può partire prima della registrazione: la
    // sua risposta non deve cancellare il codice da annunciare.
    social.details['g1'] =
        const PartyDetails(mode: PartyMode.private, code: 'ALTRO1');
    final c = container();
    await c.read(watchPartySessionProvider.notifier).join('g1');
    c
        .read(currentPartyProvider.notifier)
        .registered('g1', PartyMode.private, 'K7PQ2X');
    await pumpEventQueue();
    expect(c.read(currentPartyProvider)!.code, 'K7PQ2X');
    expect(c.read(currentPartyProvider)!.announceCode, isTrue);
    c.read(currentPartyProvider.notifier).codeAnnounced();
    expect(c.read(currentPartyProvider)!.announceCode, isFalse);
    c.read(currentPartyProvider.notifier).invited('u2');
    expect(c.read(currentPartyProvider)!.invited, {'u2'});
    await c.read(watchPartySessionProvider.notifier).leave();
  });
}
```

(se `WatchPartySession.join` in un `ProviderContainer` senza widget lascia timer dell'orologio del server, chiudili con `leave()` alla fine di ogni test, come fanno i test della sessione; adatta se la sessione richiede altri override presenti in `test/features/watch_party/watch_party_session_test.dart`.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party`
Expected: errori di compilazione (`mode:` di `startWatchParty`, `currentPartyProvider`, `partyModePreferenceProvider` non esistono).

- [ ] **Step 3: registrazione prima della coda**

In `lib/features/watch_party/watch_party_session.dart`:
- `enum WatchPartyFailure { groupGone, accessDenied, timeout, network, registration }` e sopra `registration` il commento `/// Il plugin non ha registrato la modalità del party: si è usciti dal gruppo.`
- `create` diventa:

```dart
  /// Crea un gruppo con la coda di [item]. Con [register] il party si
  /// registra nel plugin appena il gruppo esiste e prima della coda (spec F
  /// §9.2): se non riesce si esce dal gruppo, perché dopo 10 s un gruppo
  /// non registrato diventa pubblico. Lancia [WatchPartyException].
  Future<void> create(
    JellyfinItem item, {
    List<String>? queue,
    Duration start = Duration.zero,
    Future<void> Function(String groupId)? register,
  }) async {
    if (state.phase == WatchPartyPhase.joining) return;
    final session = ref.read(sessionControllerProvider);
    final userName = session is SessionSignedIn ? session.user.name : '';
    await _enter(() => _api.create('$userName · ${partyTitle(item)}'));
    final groupId = state.group?.id;
    if (register != null && groupId != null) {
      try {
        await register(groupId);
      } on Object catch (error) {
        _log.warning('watch party non registrato: ${error.runtimeType}');
        await leave();
        throw const WatchPartyException(WatchPartyFailure.registration);
      }
    }
    try {
      await _api.setNewQueue(queue ?? [item.id], start: start);
    } on ApiException catch (error) {
      _log.warning('coda del watch party non impostata: $error');
      await leave();
      throw const WatchPartyException(WatchPartyFailure.network);
    }
  }
```

(mantieni il commento di documentazione esistente se ce n'è uno, aggiungendo la frase su [register].)

In `lib/features/watch_party/watch_party_actions.dart`:
- import di `../../core/syncplay/party_mode.dart`, `../social/social_providers.dart`, `current_party.dart`;
- `startWatchParty` prende `PartyMode? mode` (dopo `start`) e il ramo "fuori da un gruppo" diventa:

```dart
        } else {
          final social = container.read(socialApiProvider);
          final current = container.read(currentPartyProvider.notifier);
          await session.create(
            item,
            queue: queue,
            start: start,
            // Spec F §9.2: la modalità si registra prima della coda.
            register: mode == null
                ? null
                : (groupId) async {
                    final code = await social.registerParty(groupId, mode);
                    current.registered(groupId, mode, code);
                  },
          );
        }
```

(`socialApiProvider` e `currentPartyProvider` si leggono solo con una modalità: se `mode` è `null` sposta le due `container.read` dentro la lambda, così i test esistenti senza override non le toccano.)

- nel commento di `startWatchParty`: "Con [mode] il party si registra nel plugin con quella modalità (spec F §9.1–9.2); `null` = come la 0.5.1."
- in `watchPartyErrorText`, prima del ramo `_`:

```dart
      WatchPartyException(failure: WatchPartyFailure.registration) =>
        l.partyCreateFailed,
```

- [ ] **Step 4: ultima modalità usata**

`lib/features/watch_party/party_mode_preference.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/syncplay/party_mode.dart';

/// Ultima modalità scelta su "Guarda insieme", evidenziata nel menu (spec F
/// §9.1). Di default pubblico.
class PartyModePreference extends Notifier<PartyMode> {
  static const key = 'party.lastMode';

  @override
  PartyMode build() =>
      PartyMode.fromWire(ref.watch(sharedPreferencesProvider).getString(key)) ??
      PartyMode.public;

  Future<void> set(PartyMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(key, mode.wire);
  }
}

final partyModePreferenceProvider =
    NotifierProvider<PartyModePreference, PartyMode>(PartyModePreference.new);
```

- [ ] **Step 5: party corrente**

`lib/features/watch_party/current_party.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/syncplay/party_mode.dart';
import '../social/social_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Il party in cui siamo, come lo dice il plugin (spec F §9.3).
class CurrentParty {
  const CurrentParty({
    required this.groupId,
    required this.mode,
    this.code,
    this.invited = const {},
    this.announceCode = false,
  });

  final String groupId;
  final PartyMode mode;

  /// Solo per i privati.
  final String? code;

  /// Amici invitati da noi (il menu li mostra come "Invitato").
  final Set<String> invited;

  /// Il codice va mostrato una volta nella pillola del player: party privato
  /// appena creato da noi.
  final bool announceCode;

  CurrentParty copyWith({Set<String>? invited, bool? announceCode}) =>
      CurrentParty(
        groupId: groupId,
        mode: mode,
        code: code,
        invited: invited ?? this.invited,
        announceCode: announceCode ?? this.announceCode,
      );
}

/// Legge modalità e codice entrando in un gruppo (con la funzione `parties`
/// del plugin); `null` fuori da un gruppo.
class CurrentPartyController extends Notifier<CurrentParty?> {
  /// Cresce a ogni ricostruzione: una lettura superata non vale.
  int _loads = 0;

  @override
  CurrentParty? build() {
    final groupId = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? s.group?.id : null));
    final parties =
        ref.watch(socialAvailabilityProvider.select((f) => f.parties));
    final load = ++_loads;
    if (groupId == null || !parties) return null;
    unawaited(Future.microtask(() => _load(groupId, load)));
    return null;
  }

  Future<void> _load(String groupId, int load) async {
    // Registrato da noi intanto: il dato c'è già.
    if (!ref.mounted || load != _loads || state?.groupId == groupId) return;
    try {
      final details = await ref.read(socialApiProvider).partyDetails(groupId);
      if (!ref.mounted || load != _loads || state?.groupId == groupId) return;
      state = CurrentParty(
          groupId: groupId, mode: details.mode, code: details.code);
    } on Object catch (error) {
      _log.info('party corrente non letto: ${error.runtimeType}');
    }
  }

  /// Party appena creato e registrato da noi (spec F §9.2).
  void registered(String groupId, PartyMode mode, String? code) {
    state = CurrentParty(
      groupId: groupId,
      mode: mode,
      code: code,
      announceCode: mode == PartyMode.private && code != null,
    );
  }

  /// La pillola ha mostrato il codice.
  void codeAnnounced() {
    final current = state;
    if (current != null) state = current.copyWith(announceCode: false);
  }

  /// Abbiamo invitato [userId].
  void invited(String userId) {
    final current = state;
    if (current != null) {
      state = current.copyWith(invited: {...current.invited, userId});
    }
  }
}

final currentPartyProvider =
    NotifierProvider<CurrentPartyController, CurrentParty?>(
        CurrentPartyController.new);
```

- [ ] **Step 5b: `switch` esaustivi**

Se l'analyzer segnala `switch` non esaustivi su `WatchPartyFailure` altrove, aggiungi il ramo `registration` con lo stesso comportamento del ramo di rete.

- [ ] **Step 6: verifica**

Run: `flutter test test/features/watch_party` → PASS. `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/features/watch_party test/features/watch_party
git commit -m "feat: register the party mode before the queue (#5)"
```

---

### Task 10: elenco e schede dal plugin, icona della modalità

**Files:**
- Modify: `lib/features/watch_party/watch_party_directory.dart`
- Modify: `lib/features/watch_party/watch_party_invites.dart`
- Create: `lib/features/watch_party/party_mode_labels.dart`
- Modify: `lib/features/watch_party/watch_party_button.dart` (`_GroupTile`)
- Test: `test/features/watch_party/watch_party_directory_test.dart`, `test/features/watch_party/watch_party_invites_test.dart`, `test/features/watch_party/watch_party_button_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/support/watch_party_fakes.dart` aggiungi (import di `package:wonderflix/core/syncplay/syncplay_models.dart` se manca):

```dart
extension GroupInfoWithMode on GroupInfo {
  /// Lo stesso gruppo con la modalità del plugin (solo per i test).
  GroupInfo copyWithMode(PartyMode mode) => GroupInfo(
        id: id,
        name: name,
        state: state,
        participants: participants,
        lastUpdatedAt: lastUpdatedAt,
        mode: mode,
      );
}
```

In `test/features/watch_party/watch_party_directory_test.dart` (import di `package:wonderflix/core/syncplay/syncplay_models.dart`, `package:wonderflix/features/social/social_providers.dart`, `../../support/social_fakes.dart`) aggiungi:

```dart
  test('con la funzione parties l'elenco viene dal plugin', () {
    fakeAsync((async) {
      final social = FakeSocialApi()
        ..partyList = [
          testGroup(id: 'g9', name: 'Mario · Up')
              .copyWithMode(PartyMode.friends),
        ];
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        syncPlayApiProvider.overrideWithValue(api),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
      ]);
      container.listen(watchPartyDirectoryProvider, (_, _) {});
      async.flushMicrotasks();
      expect(social.calls, ['parties']);
      expect(api.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider).single.mode,
          PartyMode.friends);
      container.dispose();
    });
  });
```

In `test/features/watch_party/watch_party_invites_test.dart` (import di `package:wonderflix/features/social/social_providers.dart`, `../../support/social_fakes.dart`):
- l'helper `invite()` diventa `GroupInfo? invite() => container.read(watchPartyInvitesProvider)?.group;` (i test esistenti restano uguali);
- dopo `mount` aggiungi:

```dart
  /// Come [mount], con la funzione `parties` del plugin.
  void mountWithParties() {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
      socialApiProvider.overrideWithValue(FakeSocialApi()),
      socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
          const SocialFeatures(friends: true, parties: true))),
    ]);
    container.listen(watchPartyInvitesProvider, (_, _) {});
  }
```

- nuovi test:

```dart
  test('con la funzione parties: schede dagli avvisi del plugin', () {
    fakeAsync((async) {
      mountWithParties();
      async.flushMicrotasks();
      events.add(partyStartedReceived('g7', 'Luigi · Arrival'));
      async.flushMicrotasks();
      expect(invite()?.id, 'g7');
      expect(container.read(watchPartyInvitesProvider)!.invitedBy, isNull);
      final directory = container.read(watchPartyDirectoryProvider.notifier)
          as FakeWatchPartyDirectory;
      expect(directory.refreshCalls, greaterThan(0),
          reason: 'il party nuovo entra subito nell'elenco');

      events.add(partyInviteReceived('g8', 'Peach · Up', 'Peach'));
      async.flushMicrotasks();
      expect(container.read(watchPartyInvitesProvider)!.invitedBy, 'Peach');
      async.elapse(WatchPartyInvites.showFor);
      expect(invite(), isNull);
    });
  });

  test('con la funzione parties un gruppo nuovo nell'elenco non è un invito',
      () {
    fakeAsync((async) {
      mountWithParties();
      async.flushMicrotasks();
      groups(async, [g1]);
      groups(async, [g1, g2]);
      expect(invite(), isNull);
    });
  });
```

In `test/features/watch_party/watch_party_button_test.dart` (import di `package:lucide_icons_flutter/lucide_icons.dart`) aggiungi:

```dart
  testWidgets('elenco dal plugin: icona della modalità', (tester) async {
    await pumpButton(tester, [testGroup().copyWithMode(PartyMode.private)]);
    await tester.tap(find.byKey(const Key('watch-party-button')));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.lock), findsOneWidget);
  });
```

(se un test della scheda d'invito altrove legge lo stato come `GroupInfo`, adattalo a `.group`.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party`
Expected: errori di compilazione (`invitedBy`, `copyWithMode` in uso, `mode` del gruppo).

- [ ] **Step 3: etichette e icone delle modalità**

`lib/features/watch_party/party_mode_labels.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';

IconData partyModeIcon(PartyMode mode) => switch (mode) {
      PartyMode.public => LucideIcons.globe,
      PartyMode.friends => LucideIcons.users,
      PartyMode.private => LucideIcons.lock,
    };

String partyModeLabel(AppLocalizations l, PartyMode mode) => switch (mode) {
      PartyMode.public => l.partyModePublic,
      PartyMode.friends => l.partyModeFriends,
      PartyMode.private => l.partyModePrivate,
    };

String partyModeHint(AppLocalizations l, PartyMode mode) => switch (mode) {
      PartyMode.public => l.partyModePublicHint,
      PartyMode.friends => l.partyModeFriendsHint,
      PartyMode.private => l.partyModePrivateHint,
    };
```

- [ ] **Step 4: elenco dal plugin**

In `lib/features/watch_party/watch_party_directory.dart` (import di `../social/social_providers.dart`), `refresh` diventa:

```dart
  Future<void> refresh() async {
    if (ref.read(playerActiveProvider)) return;
    try {
      final groups = _partiesAvailable()
          ? await ref.read(socialApiProvider).parties()
          : await ref.read(syncPlayApiProvider).list();
      if (ref.mounted) state = groups;
    } on Object catch (error) {
      _log.info('elenco dei watch party non disponibile: $error');
    }
  }

  /// Con la funzione `parties` del plugin l'elenco è già filtrato per
  /// modalità (spec F §9.6). Se le funzioni non si possono leggere, come
  /// prima.
  bool _partiesAvailable() {
    try {
      return ref.read(socialAvailabilityProvider).parties;
    } on Object {
      return false;
    }
  }
```

e nel commento della classe: "Con la funzione `parties` legge `GET Parties` del plugin invece di `/SyncPlay/List`."

- [ ] **Step 5: schede dagli avvisi del plugin**

In `lib/features/watch_party/watch_party_invites.dart` (import di `../../core/social/social_models.dart`, `../social/social_providers.dart`):

```dart
/// La scheda d'invito: un gruppo appena nato o un invito di un amico.
class WatchPartyInvite {
  const WatchPartyInvite(this.group, {this.invitedBy});

  final GroupInfo group;

  /// Chi ci ha invitato (`PartyInvite`); `null` per un gruppo appena nato.
  final String? invitedBy;
}
```

- `WatchPartyInvites extends Notifier<WatchPartyInvite?>`; il provider diventa `NotifierProvider<WatchPartyInvites, WatchPartyInvite?>`.
- in `build`, al posto di `ref.listen(watchPartyDirectoryProvider, (_, groups) => _onGroups(groups));`:

```dart
    // Spec F §9.6: con la funzione `parties` le schede le annuncia il
    // plugin; altrimenti nascono dal confronto tra due letture dell'elenco.
    if (ref.watch(socialAvailabilityProvider.select((f) => f.parties))) {
      final subscription =
          ref.watch(socialEventsProvider).listen(_onSocialEvent);
      ref.onDispose(() => unawaited(subscription.cancel()));
    } else {
      ref.listen(watchPartyDirectoryProvider, (_, groups) => _onGroups(groups));
    }
```

- `_onGroups` finisce con `_offer(WatchPartyInvite(fresh.last));` al posto del blocco che controllava permessi, player e fase e impostava lo stato;
- nuovi metodi:

```dart
  void _onSocialEvent(SocialEvent event) {
    final invite = switch (event) {
      PartyStartedEvent() =>
        WatchPartyInvite(_group(event.groupId, event.name, event.mode)),
      PartyInviteEvent() => WatchPartyInvite(
          _group(event.groupId, event.name, null),
          invitedBy: event.fromName),
      _ => null,
    };
    if (invite == null) return;
    // Il party nuovo (o quello in cui siamo invitati) entra subito
    // nell'elenco del chip.
    unawaited(ref.read(watchPartyDirectoryProvider.notifier).refresh());
    _offer(invite);
  }

  GroupInfo _group(String id, String name, PartyMode? mode) => GroupInfo(
        id: id,
        name: name,
        state: GroupState.idle,
        participants: const [],
        lastUpdatedAt: DateTime.utc(1970),
        mode: mode,
      );

  /// Mostra [invite] per [showFor], con le regole di sempre: non per i
  /// gruppi già visitati, non dentro un gruppo o entrando, non con il player
  /// aperto, non senza il permesso di entrare.
  void _offer(WatchPartyInvite invite) {
    if (_visited.contains(_normalizeId(invite.group.id))) return;
    if (!ref.read(syncPlayAccessProvider).canJoin ||
        ref.read(playerActiveProvider) ||
        ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
      return;
    }
    _timer?.cancel();
    state = invite;
    _timer = Timer(showFor, dismiss);
  }
```

- `WatchPartyInviteCard`: `final invite = ref.watch(watchPartyInvitesProvider);`, la chiave è `ValueKey(invite.group.id)`, `_card` riceve l'invito e il titolo è:

```dart
                    child: Text(
                        invite.invitedBy != null
                            ? l.partyInviteTitle(invite.invitedBy!)
                            : l.watchPartyInviteTitle(names.host),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
```

con `final names = partyNameParts(invite.group);` e `joinWatchParty(context, ref, invite.group.id)`.

- [ ] **Step 6: icona della modalità nell'elenco del chip**

In `lib/features/watch_party/watch_party_button.dart` (import di `party_mode_labels.dart`), in `_GroupTile`, il `Text(group.name, …)` diventa:

```dart
                Row(
                  children: [
                    if (group.mode != null) ...[
                      Icon(partyModeIcon(group.mode!),
                          size: 14, color: WfColors.creamMuted),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
```

- [ ] **Step 7: verifica**

Run: `flutter test test/features/watch_party test/app` → PASS. `flutter analyze`; `flutter test` → tutto verde (gli altri test che leggono `watchPartyInvitesProvider` come `GroupInfo` vanno adattati a `.group`).

- [ ] **Step 8: commit**

```bash
git add lib/features/watch_party test/features/watch_party test/support/watch_party_fakes.dart
git commit -m "feat: list parties and invites from the plugin (#5)"
```

---

## Gruppo C — interfaccia

### Task 11: menu delle modalità su "Guarda insieme"

**Files:**
- Modify: `lib/ui/wf_menus.dart` (`menuPositionBelow`)
- Create: `lib/features/watch_party/party_mode_menu.dart`
- Modify: `lib/features/detail/detail_header.dart`, `lib/features/player/player_overlay.dart`, `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_mode_menu_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/watch_party/party_mode_menu_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/party_mode_menu.dart';
import 'package:wonderflix/features/watch_party/party_mode_preference.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeSocialApi social;
  late StreamController<ServerEvent> events;
  late SharedPreferences prefs;
  final film = testItem(id: 'm1', name: 'Dune');

  setUp(() {
    api = FakeSyncPlayApi();
    social = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('create')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pump(WidgetTester tester, {bool parties = true}) async {
    SharedPreferences.setMockInitialValues(
        {PartyModePreference.key: 'Friends'});
    prefs = await SharedPreferences.getInstance();
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => Builder(
              builder: (buttonContext) => TextButton(
                onPressed: () =>
                    unawaited(watchTogether(buttonContext, ref, film)),
                child: const Text('insieme'),
              ),
            ),
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(FakeLibraryApi()),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            SocialFeatures(friends: true, parties: parties))),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  }

  Future<void> leave(WidgetTester tester) async {
    final container =
        ProviderScope.containerOf(tester.element(find.text('insieme')));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('tre modalità, l\'ultima evidenziata; la scelta crea e registra',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    expect(find.text('Pubblico'), findsOneWidget);
    expect(find.text('Lo vedono tutti, avviso a tutti'), findsOneWidget);
    expect(find.text('Solo amici'), findsOneWidget);
    expect(find.text('Privato'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('party-mode-Friends')),
            matching: find.byKey(const Key('party-mode-selected'))),
        findsOneWidget);

    await tester.tap(find.text('Privato'));
    await tester.pumpAndSettle();
    expect(api.calls.first, 'create Mario · Dune');
    expect(social.calls, contains('register g1 Private'));
    expect(prefs.getString(PartyModePreference.key), 'Private');
    await leave(tester);
  });

  testWidgets('chiuso senza scegliere: niente gruppo', (tester) async {
    await pump(tester);
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('senza la funzione parties: nessun menu, come prima',
      (tester) async {
    await pump(tester, parties: false);
    await tester.tap(find.text('insieme'));
    await tester.pumpAndSettle();
    expect(find.text('Privato'), findsNothing);
    expect(api.calls.first, 'create Mario · Dune');
    expect(social.calls, isNot(contains(startsWith('register'))));
    await leave(tester);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party/party_mode_menu_test.dart`
Expected: errori di compilazione (`party_mode_menu.dart` non esiste).

- [ ] **Step 3: posizione dei menu ancorati**

In `lib/ui/wf_menus.dart` (se `RelativeRect`/`RenderBox`/`Navigator` non arrivano da `widgets.dart`, importa `package:flutter/material.dart` al suo posto):

```dart
/// Posizione di un menu aperto sotto [anchor], come quella di
/// `PopupMenuButton`; se sotto non c'è spazio `showMenu` lo apre sopra.
RelativeRect menuPositionBelow(BuildContext anchor) {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(button.size.bottomLeft(Offset.zero),
          ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(Offset.zero),
          ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );
}
```

- [ ] **Step 4: menu delle modalità**

`lib/features/watch_party/party_mode_menu.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../social/social_providers.dart';
import 'party_mode_labels.dart';
import 'party_mode_preference.dart';
import 'watch_party_actions.dart';
import 'watch_party_session.dart';

/// Menu delle modalità ancorato a [anchor] (spec F §9.1): l'ultima usata ha
/// il bordo oro. `null` se si chiude senza scegliere.
Future<PartyMode?> showPartyModeMenu(BuildContext anchor,
    {required PartyMode last}) {
  final l = AppLocalizations.of(anchor);
  return showMenu<PartyMode>(
    context: anchor,
    position: menuPositionBelow(anchor),
    popUpAnimationStyle: wfPopUpAnimation(anchor),
    items: [
      for (final mode in PartyMode.values)
        PopupMenuItem<PartyMode>(
          key: Key('party-mode-${mode.wire}'),
          value: mode,
          height: 64,
          child: _ModeTile(l: l, mode: mode, selected: mode == last),
        ),
    ],
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.l, required this.mode, required this.selected});

  final AppLocalizations l;
  final PartyMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        key: selected ? const Key('party-mode-selected') : null,
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? WfColors.gold : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(partyModeIcon(mode),
                size: 20, color: selected ? WfColors.gold : WfColors.cream),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(partyModeLabel(l, mode),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(partyModeHint(l, mode),
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// "Guarda insieme" (spec F §9.1–9.2). Con la funzione `parties` del plugin
/// e fuori da un gruppo chiede la modalità con un menu ancorato a
/// [menuAnchor] (di default [context]) e la ricorda; dentro un gruppo o
/// senza plugin fa come prima. `false` se si annulla o non riesce.
Future<bool> watchTogether(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  Duration start = Duration.zero,
  BuildContext? menuAnchor,
}) async {
  PartyMode? mode;
  if (_partiesAvailable(ref) && !ref.read(watchPartySessionProvider).inGroup) {
    mode = await showPartyModeMenu(menuAnchor ?? context,
        last: ref.read(partyModePreferenceProvider));
    if (mode == null || !context.mounted) return false;
    unawaited(ref.read(partyModePreferenceProvider.notifier).set(mode));
  }
  if (!context.mounted) return false;
  return startWatchParty(context, ref, item, start: start, mode: mode);
}

/// Se le funzioni del plugin non si possono leggere, come senza plugin.
bool _partiesAvailable(WidgetRef ref) {
  try {
    return ref.read(socialAvailabilityProvider).parties;
  } on Object {
    return false;
  }
}
```

- [ ] **Step 5: scheda e player**

In `lib/features/detail/detail_header.dart` (import di `../watch_party/party_mode_menu.dart`; togli quello di `watch_party_actions.dart` se non serve più), il `WfButton.secondary` di "Guarda insieme" diventa:

```dart
                          Builder(
                            // Il menu delle modalità si apre sotto il
                            // pulsante (spec F §9.1).
                            builder: (buttonContext) => WfButton.secondary(
                              label: l.watchPartyWatchTogether,
                              icon: LucideIcons.users,
                              onPressed: () => unawaited(watchTogether(
                                buttonContext,
                                ref,
                                action.target,
                                start: action is ResumeAction
                                    ? action.position
                                    : Duration.zero,
                              )),
                            ),
                          ),
```

In `lib/features/player/player_overlay.dart`:
- `final ValueChanged<BuildContext>? onWatchTogether;` con il commento `/// "Guarda insieme": riceve il contesto del pulsante, per ancorare il menu delle modalità.`
- il pulsante diventa:

```dart
                          if (onWatchTogether != null)
                            Builder(
                              builder: (buttonContext) => PlayerIconButton(
                                icon: const Icon(LucideIcons.users),
                                tooltip: l.watchPartyWatchTogether,
                                onPressed: () =>
                                    onWatchTogether!(buttonContext),
                              ),
                            ),
```

In `lib/features/player/player_screen.dart` (import di `../watch_party/party_mode_menu.dart`):
- `onWatchTogether: canWatchTogether ? (buttonContext) => unawaited(_watchTogether(buttonContext)) : null,`
- `_watchTogether` prende `BuildContext buttonContext` e chiama:

```dart
    final started = await watchTogether(context, ref, item,
        start: start, menuAnchor: buttonContext);
```

(il resto del metodo non cambia: se si annulla il menu `started` è `false` e il pulsante torna.)

- [ ] **Step 6: verifica**

Run: `flutter test test/features/watch_party/party_mode_menu_test.dart test/features/detail test/features/player` → PASS. `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/ui/wf_menus.dart lib/features test/features/watch_party/party_mode_menu_test.dart
git commit -m "feat: choose the party mode on watch together (#5)"
```

---

### Task 12: codice e "Invita amici" nei menu del party

**Files:**
- Modify: `lib/features/watch_party/party_notices.dart`, `lib/features/watch_party/party_notice_pill.dart`
- Create: `lib/features/watch_party/party_invite_menu.dart`
- Modify: `lib/features/watch_party/watch_party_button.dart` (`_InPartyButton`)
- Modify: `lib/features/watch_party/party_badge.dart` (`PartyBadge`)
- Test: `test/features/watch_party/watch_party_button_test.dart`, `test/features/watch_party/party_badge_menu_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/features/watch_party/watch_party_button_test.dart` (import di `package:flutter/services.dart`, `package:wonderflix/core/social/social_models.dart`, `package:wonderflix/features/social/social_providers.dart`, `package:wonderflix/features/watch_party/current_party.dart`, `../../support/social_fakes.dart`) aggiungi:

```dart
  /// Nel gruppo `g1` (Mario e Peach), con il plugin che sa amici e party.
  Future<ProviderContainer> pumpWithPlugin(
      WidgetTester tester, FakeSocialApi social) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: Align(
              alignment: Alignment.topRight, child: WatchPartyButton())),
      overrides: [
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory(const [])),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        partyChannelApiProvider.overrideWithValue(channelApi),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
      ],
    );
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined(
            'g1', testGroup(participants: const ['Mario', 'Peach']))));
      }
    };
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchPartyButton)));
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('nel gruppo privato: il codice si copia', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final social = FakeSocialApi()
      ..details['g1'] =
          const PartyDetails(mode: PartyMode.private, code: 'K7PQ2X');
    await pumpWithPlugin(tester, social);

    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codice K7P-Q2X'));
    await tester.pumpAndSettle();
    expect(copied, ['K7P-Q2X']);
    expect(find.text('Codice copiato'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('Invita amici: solo chi non è nel party; poi "Invitato"',
      (tester) async {
    final social = FakeSocialApi()
      ..snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true),
        testFriend('u3', 'Peach', online: true),
      ]);
    final container = await pumpWithPlugin(tester, social);

    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invita amici'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invite-u3')), findsNothing,
        reason: 'Peach è già nel party');
    await tester.tap(find.byKey(const ValueKey('invite-u2')));
    await tester.pumpAndSettle();
    expect(social.calls, contains('invite g1 u2'));
    expect(find.text('Invito mandato a Luigi'), findsOneWidget);
    expect(container.read(currentPartyProvider)!.invited, {'u2'});

    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invita amici'));
    await tester.pumpAndSettle();
    expect(find.text('Invitato'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await leave(tester);
  });

  testWidgets('Invita amici senza amici da invitare', (tester) async {
    await pumpWithPlugin(tester, FakeSocialApi());
    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invita amici'));
    await tester.pumpAndSettle();
    expect(find.text('Nessun amico da invitare'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await leave(tester);
  });
```

(`invited` nel test 'Invita amici' si legge dopo che `CurrentParty` ha caricato i dettagli: con i dettagli di default il gruppo è pubblico, quindi lo stato c'è.)

`test/features/watch_party/party_badge_menu_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/current_party.dart';
import 'package:wonderflix/features/watch_party/party_badge.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakeSocialApi social;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSyncPlayApi();
    social = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  Future<ProviderContainer> pumpBadge(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(body: Center(child: PartyBadge(onLeave: () {}))),
      overrides: [
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialApiProvider.overrideWithValue(social),
        socialAvailabilityProvider.overrideWith(() => FakeSocialAvailability(
            const SocialFeatures(friends: true, parties: true))),
      ],
    );
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PartyBadge)));
    container.listen(partyNoticesProvider, (_, _) {});
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> leave(ProviderContainer c, WidgetTester tester) async {
    await c.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  }

  testWidgets('codice copiato: lo dice la pillola', (tester) async {
    social.details['g1'] =
        const PartyDetails(mode: PartyMode.private, code: 'K7PQ2X');
    final c = await pumpBadge(tester);
    await tester.tap(find.byKey(const Key('party-badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codice K7P-Q2X'));
    await tester.pumpAndSettle();
    expect(c.read(partyNoticesProvider)?.kind, PartyNoticeKind.codeCopied);
    await leave(c, tester);
  });

  testWidgets('party privato appena creato: il codice nella pillola, una volta',
      (tester) async {
    final c = await pumpBadge(tester);
    c
        .read(currentPartyProvider.notifier)
        .registered('g1', PartyMode.private, 'K7PQ2X');
    await tester.pump();
    await tester.pump();
    final notice = c.read(partyNoticesProvider)!;
    expect(notice.kind, PartyNoticeKind.privateCode);
    expect(notice.title, 'K7P-Q2X');
    expect(c.read(currentPartyProvider)!.announceCode, isFalse);
    await leave(c, tester);
  });
}
```

(se le pillole degli avvisi lasciano timer attivi alla fine del test, avanza il tempo con `tester.pump(<durata dell'avviso>)` prima di uscire, come negli altri test degli avvisi.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/watch_party`
Expected: errori di compilazione o voci di menu assenti.

- [ ] **Step 3: avvisi nuovi**

In `lib/features/watch_party/party_notices.dart`, in fondo a `PartyNoticeKind`:

```dart

  /// Il codice del party privato appena creato da noi (spec F §9.4), in
  /// `title`.
  privateCode,

  /// Codice copiato negli appunti.
  codeCopied,

  /// Invito mandato a `name`.
  inviteSent,

  /// Invito non riuscito.
  inviteFailed,
```

In `lib/features/watch_party/party_notice_pill.dart`: nel testo

```dart
    PartyNoticeKind.privateCode => l.partyPrivateCreated(title),
    PartyNoticeKind.codeCopied => l.partyCodeCopied,
    PartyNoticeKind.inviteSent => l.partyInviteSent(notice.name ?? ''),
    PartyNoticeKind.inviteFailed => l.friendsActionFailed,
```

e nelle icone

```dart
      PartyNoticeKind.privateCode => LucideIcons.lock,
      PartyNoticeKind.codeCopied => LucideIcons.copy,
      PartyNoticeKind.inviteSent => LucideIcons.send,
      PartyNoticeKind.inviteFailed => LucideIcons.circleAlert,
```

(se l'analyzer segnala altri `switch` non esaustivi su `PartyNoticeKind`, aggiungi i rami con il comportamento neutro del file.)

- [ ] **Step 4: menu "Invita amici"**

`lib/features/watch_party/party_invite_menu.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../friends/friends_controller.dart';
import '../friends/friends_panel.dart' show sortFriends;
import '../social/social_providers.dart';
import 'current_party.dart';
import 'party_badge.dart' show MemberAvatar;
import 'watch_party_session.dart';

/// Esito di "Invita amici".
class InviteResult {
  const InviteResult(this.name, {this.failure});

  /// Chi abbiamo invitato.
  final String name;

  /// `null` se l'invito è partito.
  final SocialFailure? failure;
}

/// "Invita amici" (spec F §9.5): menu ancorato a [anchor] con gli amici non
/// ancora nel party, online prima; un clic manda l'invito. `null` se si
/// chiude senza scegliere.
Future<InviteResult?> showInviteFriendsMenu(
    BuildContext anchor, WidgetRef ref) async {
  final l = AppLocalizations.of(anchor);
  final groupId = ref.read(watchPartySessionProvider).group?.id;
  if (groupId == null) return null;
  // Lista fresca: chi è online e chi è già dentro cambiano spesso.
  await ref.read(friendsControllerProvider.notifier).reload();
  if (!anchor.mounted) return null;
  final members = {
    for (final member in ref.read(watchPartySessionProvider).members)
      member.toLowerCase(),
  };
  final friends = sortFriends(ref.read(friendsControllerProvider).snapshot.friends)
      .where((friend) => !members.contains(friend.name.toLowerCase()))
      .toList();
  final invited = ref.read(currentPartyProvider)?.invited ?? const <String>{};
  final picked = await showMenu<String>(
    context: anchor,
    position: menuPositionBelow(anchor),
    popUpAnimationStyle: wfPopUpAnimation(anchor),
    items: friends.isEmpty
        ? [
            PopupMenuItem<String>(
                enabled: false, child: Text(l.partyNoFriendsToInvite)),
          ]
        : [
            for (final friend in friends)
              PopupMenuItem<String>(
                key: ValueKey('invite-${friend.userId}'),
                value: friend.userId,
                enabled: !invited.contains(friend.userId),
                child: Row(
                  children: [
                    MemberAvatar(name: friend.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(friend.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: friend.online
                                  ? WfColors.cream
                                  : WfColors.creamMuted)),
                    ),
                    if (invited.contains(friend.userId)) ...[
                      const Icon(LucideIcons.check,
                          size: 16, color: WfColors.gold),
                      const SizedBox(width: 4),
                      Text(l.partyInvited,
                          style: const TextStyle(
                              color: WfColors.creamMuted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
          ],
  );
  if (picked == null || !anchor.mounted) return null;
  final name = friends.firstWhere((friend) => friend.userId == picked).name;
  try {
    await ref.read(socialApiProvider).invite(groupId, [picked]);
    ref.read(currentPartyProvider.notifier).invited(picked);
    return InviteResult(name);
  } on SocialException catch (error) {
    return InviteResult(name, failure: error.failure);
  }
}
```

- [ ] **Step 5: menu del chip "Nel watch party"**

In `lib/features/watch_party/watch_party_button.dart` (import di `dart:async` se manca, `package:flutter/services.dart`, `../../core/social/social_api.dart`, `../../core/social/social_models.dart`, `../social/social_providers.dart`, `current_party.dart`, `party_invite_menu.dart`), in `_InPartyButton.build`:
- prima del `return`:

```dart
    final code = ref.watch(currentPartyProvider.select((p) => p?.code));
    final canInvite = ref.watch(
        socialAvailabilityProvider.select((f) => f.friends && f.parties));
```

- in `onSelected`, nuovi casi:

```dart
          case 'code':
            if (code == null) return;
            unawaited(
                Clipboard.setData(ClipboardData(text: formatPartyCode(code))));
            ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text(l.partyCodeCopied)));
          case 'invite':
            unawaited(_inviteFromChip(context, ref));
```

- in `itemBuilder`, tra "Torna al player" ed "Esci":

```dart
        if (code != null)
          PopupMenuItem<String>(
            value: 'code',
            child: Row(
              children: [
                const Icon(LucideIcons.copy, size: 18, color: WfColors.cream),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(l.partyCode(formatPartyCode(code)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        if (canInvite)
          PopupMenuItem<String>(
            value: 'invite',
            child: Row(
              children: [
                const Icon(LucideIcons.userPlus,
                    size: 18, color: WfColors.cream),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(l.partyInviteFriends,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
```

- funzione in fondo al file:

```dart
/// "Invita amici" dal chip: l'esito in una snackbar (spec F §9.5).
Future<void> _inviteFromChip(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showInviteFriendsMenu(context, ref);
  if (result == null) return;
  messenger?.showSnackBar(SnackBar(
      content: Text(switch (result.failure) {
    null => l.partyInviteSent(result.name),
    SocialFailure.rateLimited => l.friendsTooMany,
    _ => l.friendsActionFailed,
  })));
}
```

- [ ] **Step 6: menu del distintivo nel player e codice appena creato**

In `lib/features/watch_party/party_badge.dart` (import di `dart:async`, `package:flutter/services.dart`, `../../core/social/social_models.dart`, `../social/social_providers.dart`, `current_party.dart`, `party_invite_menu.dart`, `party_notices.dart`), in `_PartyBadgeState.build`:
- dopo il `ref.listen` dei membri:

```dart
    final code = ref.watch(currentPartyProvider.select((p) => p?.code));
    final canInvite = ref.watch(
        socialAvailabilityProvider.select((f) => f.friends && f.parties));
    // Party privato appena creato da noi: il codice nella pillola, una
    // volta (spec F §9.2). Fuori dalla build: tocca altri provider.
    ref.listen<String?>(
        currentPartyProvider
            .select((p) => p != null && p.announceCode ? p.code : null),
        (_, announced) {
      if (announced == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(partyNoticesProvider.notifier).show(PartyNotice(
            PartyNoticeKind.privateCode,
            title: formatPartyCode(announced)));
        ref.read(currentPartyProvider.notifier).codeAnnounced();
      });
    }, fireImmediately: true);
```

- `onSelected`:

```dart
      onSelected: (value) {
        switch (value) {
          case 'leave':
            widget.onLeave();
          case 'code':
            if (code == null) return;
            unawaited(Clipboard.setData(
                ClipboardData(text: formatPartyCode(code))));
            ref
                .read(partyNoticesProvider.notifier)
                .show(const PartyNotice(PartyNoticeKind.codeCopied));
          case 'invite':
            unawaited(_invite());
        }
      },
```

- in `itemBuilder`, dopo il divisore dei membri e prima di "Esci", le stesse due voci del chip (`'code'` e `'invite'`, con `l.partyCode(formatPartyCode(code))` e `l.partyInviteFriends`);
- metodo nello stato:

```dart
  /// "Invita amici" dal player: l'esito nella pillola.
  Future<void> _invite() async {
    final result = await showInviteFriendsMenu(context, ref);
    if (result == null || !mounted) return;
    ref.read(partyNoticesProvider.notifier).show(PartyNotice(
        result.failure == null
            ? PartyNoticeKind.inviteSent
            : PartyNoticeKind.inviteFailed,
        name: result.name));
  }
```

- [ ] **Step 7: verifica**

Run: `flutter test test/features/watch_party test/features/player` → PASS. `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 8: commit**

```bash
git add lib/features/watch_party test/features/watch_party
git commit -m "feat: copy the party code and invite friends from the party menus (#5)"
```

---

### Task 13: "Ho un codice" e "Nel watch party" nel pannello Amici

**Files:**
- Create: `lib/features/friends/party_code_field.dart`
- Modify: `lib/features/friends/friends_panel.dart`
- Test: `test/features/friends/party_code_field_test.dart`, `test/features/friends/friends_panel_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/friends/party_code_field_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/friends/party_code_field.dart';

void main() {
  String format(String text) => PartyCodeFormatter()
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
      .text;

  test('maiuscole, solo lettere e cifre, trattino dopo 3, al massimo 6', () {
    expect(format('k7p'), 'K7P');
    expect(format('k7pq'), 'K7P-Q');
    expect(format('k7p q2x'), 'K7P-Q2X');
    expect(format('K7P-Q2X9'), 'K7P-Q2X');
    expect(format('K7P-'), 'K7P');
  });
}
```

In `test/features/friends/friends_panel_test.dart` (import di `dart:async`, `package:flutter_riverpod/flutter_riverpod.dart`, `package:wonderflix/core/jellyfin/server_events.dart`, `package:wonderflix/core/social/social_models.dart`, `package:wonderflix/core/syncplay/syncplay_models.dart`, `package:wonderflix/features/social/social_providers.dart`, `package:wonderflix/features/watch_party/watch_party_providers.dart`, `package:wonderflix/features/watch_party/watch_party_session.dart`, `../../support/watch_party_fakes.dart`), in fondo a `main`:

```dart
  group('party', () {
    late FakeSyncPlayApi syncPlay;
    late StreamController<ServerEvent> events;

    setUp(() {
      syncPlay = FakeSyncPlayApi();
      events = StreamController<ServerEvent>.broadcast();
      syncPlay.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
        }
      };
    });

    tearDown(() => events.close());

    Future<void> pumpPartyPanel(WidgetTester tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
          ),
        ),
        overrides: [
          ...socialTestOverrides(api,
              events: events.stream,
              features: const SocialFeatures(friends: true, parties: true)),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          partyChannelApiProvider
              .overrideWithValue(FakePartyChannelApi()..install()),
        ],
      );
      await tester.pump();
    }

    Future<void> leaveParty(WidgetTester tester) async {
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      await container.read(watchPartySessionProvider.notifier).leave();
      await tester.pump();
    }

    testWidgets('"Ho un codice": il trattino da sé, poi entra',
        (tester) async {
      api.codes['K7PQ2X'] = 'g1';
      await pumpPartyPanel(tester);
      await tester.tap(find.text('Ho un codice'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('party-code-field')), 'k7pq2x');
      await tester.pump();
      expect(find.text('K7P-Q2X'), findsOneWidget);
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('code K7PQ2X'));
      expect(syncPlay.calls, contains('join g1'));
      await leaveParty(tester);
    });

    testWidgets('codice sbagliato o troppi tentativi: lo dice',
        (tester) async {
      await pumpPartyPanel(tester);
      await tester.tap(find.text('Ho un codice'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('party-code-field')), 'ZZZZZZ');
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(find.text('Codice non valido o party finito'), findsOneWidget);

      api.joinFailure = SocialFailure.rateLimited;
      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      expect(find.text('Troppi tentativi, riprova tra un minuto'),
          findsOneWidget);
    });

    testWidgets('amico in un party visibile: "Nel watch party" e Unisciti',
        (tester) async {
      api.snapshot = const FriendsSnapshot(friends: [
        FriendEntry(
          userId: 'u2',
          name: 'Luigi',
          online: true,
          party: FriendParty(groupId: 'g1', title: 'Dune'),
        ),
      ]);
      await pumpPartyPanel(tester);
      expect(find.text('Nel watch party: Dune'), findsOneWidget);
      await tester.tap(find.byKey(const Key('friend-join-u2')));
      await tester.pumpAndSettle();
      expect(syncPlay.calls, contains('join g1'));
      expect(find.byKey(const Key('friend-join-u2')), findsNothing,
          reason: 'già nel gruppo');
      await leaveParty(tester);
    });

    testWidgets('senza la funzione parties: niente "Ho un codice"',
        (tester) async {
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
      await tester.pump();
      expect(find.text('Ho un codice'), findsNothing);
    });
  });
```

(il `FakeSocialApi` del file si chiama `api`; se i costruttori `const` di `FriendsSnapshot`/`FriendEntry`/`FriendParty` non lo permettono, togli `const`.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/friends`
Expected: errori di compilazione (`party_code_field.dart` non esiste) e testi assenti.

- [ ] **Step 3: formato del codice**

`lib/features/friends/party_code_field.dart`:

```dart
import 'package:flutter/services.dart';

import '../../core/social/social_models.dart';

/// Campo del codice di un party privato: maiuscole, solo lettere e cifre,
/// al massimo 6, con il trattino dopo le prime 3 (`K7P-Q2X`).
class PartyCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var code = normalizePartyCode(newValue.text);
    if (code.length > partyCodeLength) {
      code = code.substring(0, partyCodeLength);
    }
    final text =
        code.length > 3 ? '${code.substring(0, 3)}-${code.substring(3)}' : code;
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
```

- [ ] **Step 4: "Ho un codice"**

In `lib/features/friends/friends_panel.dart` (import di `../../core/social/social_models.dart` se manca, `../watch_party/watch_party_actions.dart`, `../watch_party/watch_party_session.dart`, `party_code_field.dart`):
- in `_FriendsPanelState.build`, tra il `Padding` del campo di ricerca e l'`Expanded`:

```dart
          if (!searching &&
              ref.watch(socialAvailabilityProvider.select((f) => f.parties)))
            const _PartyCodeEntry(),
```

- nuovo widget:

```dart
/// "Ho un codice" (spec F §9.4): un campo per entrare in un party privato.
class _PartyCodeEntry extends ConsumerStatefulWidget {
  const _PartyCodeEntry();

  @override
  ConsumerState<_PartyCodeEntry> createState() => _PartyCodeEntryState();
}

class _PartyCodeEntryState extends ConsumerState<_PartyCodeEntry> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _show() {
    setState(() => _open = true);
    // Il campo di ricerca ha già il focus: `autofocus` non basterebbe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _join() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final code = normalizePartyCode(_code.text);
    if (code.length != partyCodeLength) {
      setState(() => _error = l.partyCodeInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groupId = await ref.read(socialApiProvider).joinByCode(code);
      if (!mounted) return;
      final joined = await joinWatchParty(context, ref, groupId);
      if (!mounted) return;
      setState(() => _busy = false);
      if (joined) ref.read(friendsPanelProvider.notifier).close();
    } on SocialException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.failure == SocialFailure.rateLimited
            ? l.partyCodeTooMany
            : l.partyCodeInvalid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 4),
          child: TextButton.icon(
            onPressed: _show,
            icon: const Icon(LucideIcons.ticket, size: 16),
            label: Text(l.partyHaveCode),
            style: TextButton.styleFrom(foregroundColor: WfColors.gold),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('party-code-field'),
                  controller: _code,
                  focusNode: _focus,
                  inputFormatters: [PartyCodeFormatter()],
                  decoration: InputDecoration(
                      hintText: l.partyCodeHint, isDense: true),
                  onSubmitted: (_) => unawaited(_join()),
                ),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                  label: l.partyCodeJoin, onPressed: () => unawaited(_join())),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style:
                      const TextStyle(color: WfColors.error, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: "Nel watch party"**

In `_PersonRow` aggiungi il campo facoltativo `final String? subtitle;` (nel costruttore `this.subtitle`, commento `/// Seconda riga sotto il nome (es. "Nel watch party: Dune").`) e il `Text(name, …)` dentro `Expanded` diventa una colonna:

```dart
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: status == false
                            ? WfColors.creamMuted
                            : WfColors.cream)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12)),
              ],
            ),
          ),
```

(mantieni lo stile del nome che il file usa oggi.)

In `_FriendRowState.build`, il menu ⋯ / "Conferma rimozione" va in una variabile `menu` e il `return` diventa:

```dart
    final party = friend.party;
    // La sessione del watch party si guarda solo se serve (test e app
    // senza party non la costruiscono).
    final inGroupId = party == null
        ? null
        : ref.watch(watchPartySessionProvider
            .select((s) => s.inGroup ? s.group?.id : null));
    final showJoin = party != null && !_sameGroup(party.groupId, inGroupId);
    return _PersonRow(
      name: friend.name,
      online: friend.online,
      subtitle: party == null ? null : l.friendsInParty(party.title),
      trailing: showJoin
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  key: Key('friend-join-${friend.userId}'),
                  label: l.watchPartyJoin,
                  onPressed: () => unawaited(_join(party.groupId)),
                ),
                menu,
              ],
            )
          : menu,
    );
```

con, nello stato:

```dart
  /// Entra nel party dell'amico; riuscito, il pannello si chiude.
  Future<void> _join(String groupId) async {
    final joined = await joinWatchParty(context, ref, groupId);
    if (joined && mounted) ref.read(friendsPanelProvider.notifier).close();
  }
```

e in fondo al file:

```dart
/// Lo stesso gruppo, con o senza trattini e maiuscole.
bool _sameGroup(String a, String? b) =>
    b != null &&
    a.replaceAll('-', '').toLowerCase() == b.replaceAll('-', '').toLowerCase();
```

- [ ] **Step 6: verifica**

Run: `flutter test test/features/friends` → PASS. `flutter analyze`; `flutter test` → tutto verde.

- [ ] **Step 7: commit**

```bash
git add lib/features/friends test/features/friends
git commit -m "feat: join a private party by code and see friends in parties (#5)"
```

---

## Gruppo D — chiusura

### Task 14: spec e RELEASING allineati, verifica finale, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: spec allineato**

- **Stato:** `approvato; piani 12a e 12b realizzati (…12a-amici.md, …12b-modalita-party.md)`.
- §6.5: "Oltre **5 tentativi sbagliati al minuto** per utente: **429**." → "**Ogni tentativo** conta per il limite: oltre 5 al minuto per utente, **429**." E nella tabella dei limiti (§6.9) "Codici sbagliati" → "Codici provati".
- §6.7, `POST Parties/{groupId}`: aggiungi "400 se la modalità non è valida"; e una riga sotto la tabella: "Gli endpoint dei party vogliono la sessione di chi chiama (i gruppi SyncPlay si vedono da una sessione): senza, 409."
- §9.2, punto 2: "con `parties` disponibile, il party si registra dentro `WatchPartySession.create`, appena il gruppo esiste e **prima della coda**".
- §9.3: aggiungi "`announceCode`: il codice di un privato appena creato da noi si mostra una volta nella pillola (lo fa il distintivo del party)."
- §9.4: "Mostrarlo: … copia e conferma con una snackbar nella shell, con la pillola nel player."
- §9.5: "La lista degli amici si rilegge prima di aprire il menu; l'esito (inviato / errore) è una snackbar nella shell e la pillola nel player."
- §9.6: "`WatchPartyInvites` tiene un `WatchPartyInvite` (gruppo + chi invita); a ogni avviso del plugin anche l'elenco si rilegge."
- §8.3: "'Ho un codice' compare solo con la funzione `parties`; 'Unisciti' accanto a un amico non c'è se siamo già in quel gruppo."

- [ ] **Step 2: RELEASING**

In `docs/RELEASING.md`, sezione del plugin, dopo il punto 1:

```markdown
   I test del plugin girano con le dll della versione di Jellyfin del server
   (oggi 10.11.9, nel progetto di test), il plugin si compila contro la
   10.11.0: Jellyfin cambia API anche nelle patch. Quando il server si
   aggiorna, alza `Jellyfin.Controller`/`Jellyfin.Model` nel progetto di test
   e rilancia i test. Amicizie e richieste stanno in
   `plugins/configurations/WonderFlixWatchParty/friends.json`.
```

- [ ] **Step 3: verifica finale**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → tutto verde, nessun warning.
Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

- [ ] **Step 4: build di release per la prova**

```bash
cp ../../../config/wonderflix.json config/wonderflix.json
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

(se `config/wonderflix.json` c'è già, salta la copia.) Ripristina `windows/flutter/` se cambiano solo le fini riga.

- [ ] **Step 5: commit**

```bash
git add docs
git commit -m "docs: align spec F and releasing with plan 12b (#5)"
```

---

## Prova manuale (con l'utente, sul server reale)

Prerequisiti: Task 6 fatto. Due istanze dell'exe del worktree: A (utente A) e B con `WONDERFLIX_PROFILE=b` (utente B), amici dal 12a. Se c'è un terzo utente Jellyfin, una terza istanza C (`WONDERFLIX_PROFILE=c`) **non** amica.

1. **Pubblico:** in A "Guarda insieme" su un film → menu con tre modalità (l'ultima usata con il bordo oro) → **Pubblico**. B (e C) vedono la scheda "A ha avviato un watch party" e il party nell'elenco del chip con l'icona del globo; B entra.
2. **Solo amici:** A crea un party **Solo amici** → B riceve la scheda e lo vede nell'elenco (icona persone); C no.
3. **Privato:** A crea un party **Privato** → nel player la pillola "Party privato · codice XXX-XXX"; nessuno riceve la scheda; B non lo vede nell'elenco. B apre Amici → **Ho un codice** → scrive il codice (il trattino compare da sé) → **Entra** → è nel party. Un codice sbagliato dice "Codice non valido o party finito".
4. **Codice nei menu:** nel party privato, dal chip "Nel watch party" (fuori dal player) e dal distintivo nel player c'è "Codice XXX-XXX": copia → snackbar / pillola "Codice copiato".
5. **Invita amici:** A in un party privato → distintivo → **Invita amici** → B → pillola "Invito mandato a B"; B vede la scheda "A ti invita" con Unisciti; riaprendo il menu B è "Invitato".
6. **Lista amici:** con A nel party, nel pannello Amici di B c'è "Nel watch party: titolo" con **Unisciti** (se B può vederlo); dentro lo stesso gruppo Unisciti sparisce.
7. **Senza modalità:** "Guarda insieme" dentro un gruppo cambia solo la coda, senza menu.
8. (facoltativo) La 0.5.1 installata: un party creato lì compare agli altri come pubblico dopo una decina di secondi.
9. (facoltativo, se c'è un utente senza accesso alla libreria del film) Party **Pubblico** di A su quel film: quell'utente non riceve la scheda, non lo vede nell'elenco e, se è amico di A, nel pannello Amici non vede "Nel watch party".

## Dopo la prova: release (orchestratore con l'utente, fuori dai task)

1. **Merge e push** con l'ok dell'utente (fast-forward su `main`, `git fetch` e rebase se serve), rimozione di worktree e branch.
2. **Plugin 1.1.0:** `git tag watch-party-plugin-v1.1.0` e push → il workflow **Watch party plugin** crea la pre-release con `wonderflix-watch-party_1.1.0.zip` e `.zip.md5`. In `jellyfin-plugin-watch-party/manifest.json`: `description`/`overview` con amici e party, e in cima a `versions`:

   ```json
   {
     "version": "1.1.0.0",
     "changelog": "Lista amici; watch party pubblici, solo amici o privati con codice; inviti.",
     "targetAbi": "10.11.0.0",
     "sourceUrl": "https://github.com/davidesidoti/wonderflix/releases/download/watch-party-plugin-v1.1.0/wonderflix-watch-party_1.1.0.zip",
     "checksum": "<contenuto del file .md5>",
     "timestamp": "<data della pre-release, ISO-8601 UTC>"
   }
   ```

   Commit `chore: publish the watch party plugin 1.1.0` e push.
3. **Server:** nessuno sta guardando (log). La cartella copiata a mano ha lo stesso nome di quella che crea il Catalogo e finché è caricata il Catalogo può credere la 1.1.0.0 già installata, quindi:
   1. guardare se c'è ancora la cartella 1.0.0.0 del Catalogo (`ls ~/.apps/jellyfin/data/plugins/`);
   2. `mkdir -p ~/wfwp-backup && mv ~/.apps/jellyfin/data/plugins/"WonderFlix Watch Party_1.1.0.0" ~/wfwp-backup/1.1.0.0-manuale`;
   3. `app-jellyfin restart` (ora gira la 1.0.0.0 del Catalogo, o nessuna);
   4. l'utente installa o aggiorna **WonderFlix Watch Party** a 1.1.0.0 dal Catalogo;
   5. `app-jellyfin restart`;
   6. nel log `Loaded plugin: "WonderFlix Watch Party" "1.1.0.0"` e `Amici in …` (gli amici restano: il file è nelle configurazioni).
4. **App 0.6.0 obbligatoria:** `version: 0.6.0` in `pubspec.yaml`, commit `chore: release 0.6.0`, tag `v0.6.0`, push; finita la pipeline Release, note in italiano nella bozza con la riga `<!-- wonderflix:min-version=0.6.0 -->` (amici, modalità dei party, codice, inviti; perché è obbligatoria: le versioni vecchie vedrebbero i party privati). L'utente pubblica **solo dopo** il punto 3.
5. Con l'ok dell'utente, dopo la pubblicazione: commento e chiusura di **#5** e **#6** (cosa c'è, link a v0.6.0).
