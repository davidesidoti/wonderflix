# WonderFlix — Piano 10a: plugin del watch party, canale e nomi negli avvisi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** primo piano dello Spec E. Nasce il plugin del server Jellyfin "WonderFlix Watch Party" (registro dei gruppi, storico della chat, limiti, inoltro sul WebSocket), e l'app impara a parlarci: entra nel canale con il gruppo, riceve e manda eventi, e gli avvisi del watch party dicono **chi** ha agito ("Luigi ha messo in pausa"). Chat e reazioni hanno qui solo la parte dati; l'interfaccia arriva nei piani 10b e 10c.

**Decisioni prese con l'utente (2026-10-02):**
1. **Sonda prima di tutto** (gruppo A): plugin minimo con `Info` e un endpoint temporaneo `Probe` che manda un `SendString` alla sessione di chi chiama. L'utente lo copia via SFTP su Ultra.cc e riavvia Jellyfin; la verifica si fa da jellyfin-web, senza toccare l'app. `Probe` si toglie nel Task 6.
2. **Logica del plugin dietro interfacce nostre** (`ISessionDirectory`, `IGroupDirectory`, `IEventSender`) con adattatori sottili verso `ISessionManager`/`ISyncPlayManager`; test con finti scritti a mano, niente librerie di mock; tempo con `TimeProvider`/`FakeTimeProvider`.
3. **Pacchetti Jellyfin 10.11.0** (il minimo: il plugin si carica su ogni 10.11.x).
4. **JSON esplicito**: `[JsonPropertyName]` in PascalCase su tutti i DTO.
5. **Pacchetto senza JPRM**: `meta.template.json` + `pack.sh` (cartella da installare); lo zip lo fa il workflow. Sostituisce il `build.yaml` dello spec (§6.1, da allineare nel Task 15).
6. **Lato app**: tutta la §7 dello spec (anche stato della chat e flusso delle reazioni, senza interfaccia), la §8 e la §13.
7. Il plugin **non si pubblica** in questo piano: `manifest.json` nasce senza versioni.
8. Prova manuale finale: plugin completo copiato via SFTP al posto della sonda, due istanze (`WONDERFLIX_PROFILE=b`), meglio con due utenti Jellyfin diversi.

**Architecture:**
- `jellyfin-plugin-watch-party/` (nuova cartella del repository): progetto `Jellyfin.Plugin.WonderFlixWatchParty` (net9.0) con `Protocol/` (DTO e validazione), `Hub/` (registro, storico, limiti, `PartyHub`, interfacce), `Server/` (adattatori Jellyfin), `Api/WatchPartyController`, `WatchPartyHostedService`; progetto di test xUnit `Jellyfin.Plugin.WonderFlixWatchParty.Tests`; `pack.sh`, `meta.template.json`, `manifest.json`, README; workflow `.github/workflows/watch-party-plugin.yml`.
- App: `lib/core/party_channel/` (modelli del protocollo e `PartyChannelApi`, Dart puro); `ServerEvent` nuovo `PartyChannelReceived`; `lib/features/watch_party/party_channel.dart` (`PartyChannel`, tenuto vivo da `watchPartyRoutingProvider`); `PartyNotices` impara ad aspettare il nome (`setAttribution`, `attribute`); il player e "Guarda insieme" annunciano le nostre azioni; la diagnostica mostra il plugin.

**Tech Stack:** C# 13 / .NET 9 (SDK 9 o 10), Jellyfin.Controller 10.11.0, xUnit 2.9, Microsoft.Extensions.TimeProvider.Testing 9.10; Flutter 3.47.5, flutter_riverpod 3, dio, fake_async, clock.

**Spec:** `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`. **Worktree:** `.claude/worktrees/piano-10a`, branch `feat/piano-10a`.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves`), nemmeno come verbi normali.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-10a`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde (a inizio piano: 1102 test). **Prima di ogni commit lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde, nessun warning (il progetto del plugin ha `TreatWarningsAsErrors`).
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit. Dopo ogni modifica agli ARB: `flutter gen-l10n` (la cartella `lib/l10n/gen/` non si committa).
- **Formattazione e fine riga:** niente `dart format` né `dotnet format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Durate e misure:** costanti nominate e commentate. Commenti in italiano, codice in inglese, come nel resto del codice (anche nel C#: commenti `///` in italiano, identificatori in inglese).
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate compilando un prototipo contro i pacchetti veri (2026-10-02) e sul codice di Jellyfin 10.11.9:

- **Pacchetti NuGet:** `Jellyfin.Controller`/`Jellyfin.Model` esistono in 10.11.0 e da 10.11.2 a 10.11.11 (non c'è 10.11.1). La versione dell'assembly cambia a ogni patch: si compila contro **10.11.0** (un riferimento a 10.11.0.0 si lega a una versione più nuova, non a una più vecchia). Nel plugin vanno con `ExcludeAssets=runtime` (le dll le ha il server). **Il progetto di test deve riferire di nuovo `Jellyfin.Controller` e `Jellyfin.Model` senza `ExcludeAssets`**, altrimenti i test falliscono con `FileNotFoundException: MediaBrowser.Controller`.
- `Microsoft.AspNetCore.App` arriva già dai pacchetti Jellyfin: `ControllerBase`, `[Authorize]`, `IHostedService` non chiedono altri riferimenti. Nessun file di soluzione: `dotnet test <cartella del progetto di test>` compila anche il plugin.
- **`BasePlugin<BasePluginConfiguration>`** (`MediaBrowser.Common.Plugins`, `MediaBrowser.Model.Plugins`): costruttore `(IApplicationPaths, IXmlSerializer)`; `Name` astratto, `Id` e `Description` virtuali. Nessuna pagina di configurazione richiesta.
- **`IPluginServiceRegistrator`** (`MediaBrowser.Controller.Plugins`): `void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)`; serve un costruttore senza parametri. **Jellyfin non registra `TimeProvider`**: `TryAddSingleton(TimeProvider.System)`.
- **`Policies.SyncPlayHasAccess`** esiste (`MediaBrowser.Common.Api`), valore `"SyncPlayHasAccess"`: passa se l'utente può creare o entrare nei gruppi.
- **`IAuthorizationContext`** (`MediaBrowser.Controller.Net`): `Task<AuthorizationInfo> GetAuthorizationInfo(HttpContext)`. `AuthorizationInfo.UserId` è calcolato da `User?.Id` (nei test: `User = new User("mario", "p", "r")`, `Jellyfin.Database.Implementations.Entities`); poi `DeviceId`, `Client`.
- **`ISessionManager`** (`MediaBrowser.Controller.Session`, nullabilità spenta): `IEnumerable<SessionInfo> Sessions`; `event EventHandler<SessionEventArgs> SessionEnded` (arriva su un altro thread, poi la `SessionInfo` viene chiusa: leggere subito `Id`); `Task SendGeneralCommand(string controllingSessionId, string sessionId, GeneralCommand command, CancellationToken)`: con `controllingSessionId` **null** non controlla i permessi; un id sconosciuto lancia `ResourceNotFoundException` (`MediaBrowser.Common.Extensions`) in modo sincrono; senza WebSocket aperto non fa nulla.
- Jellyfin distingue le sessioni per **client + dispositivo**: la sessione di chi chiama è quella con lo stesso `DeviceId`, `Client` e `UserId` dell'autenticazione.
- **`SessionInfo`** (`sealed`): costruttore `(ISessionManager, ILogger)` senza controlli: nei test `new SessionInfo(null!, NullLogger.Instance) { Id = …, DeviceId = …, Client = …, UserId = …, UserName = … }`.
- **`GeneralCommand`** (`MediaBrowser.Model.Session`): `Name = GeneralCommandType.SendString`, `Arguments` è in sola lettura ma modificabile: `Arguments = { [chiave] = valore }` compila.
- **`ISyncPlayManager`** (`MediaBrowser.Controller.SyncPlay`): `GroupInfoDto GetGroup(SessionInfo session, Guid groupId)` restituisce **null** se il gruppo non esiste o l'utente non può vederne la coda. `GroupInfoDto.Participants` (`MediaBrowser.Model.SyncPlay`) sono i **nomi utente**, senza ripetizioni; costruttore `(Guid, string, GroupStateType, IReadOnlyList<string>, DateTime)`.
- **JSON dei controller:** PascalCase (`JsonDefaults.PascalCaseOptions`), `[JsonPropertyName]` vince; i `Guid` scritti dal server sono in formato `"N"` (32 cifre, senza trattini), quelli con i trattini sono accettati in ingresso; i nomi nei corpi delle richieste non distinguono le maiuscole. Il messaggio sul WebSocket: `{"MessageId":"…","Data":{"Name":"SendString","ControllingUserId":"000…0","Arguments":{"WonderFlixWatchParty":"<json>"}},"MessageType":"GeneralCommand"}`.
- **Installazione manuale:** il server legge ogni cartella dentro `plugins/`; nome della cartella `Nome_Versione` (es. `WonderFlix Watch Party_1.0.0.0`); `meta.json` facoltativo ma consigliato (campi `category, changelog, description, guid, name, overview, owner, targetAbi, timestamp, version, status, autoUpdate, imagePath, assemblies`; `assemblies` è l'elenco delle dll da caricare). Il pacchetto contiene **solo** `Jellyfin.Plugin.WonderFlixWatchParty.dll` + `meta.json`.
- **Manifest del repository:** `[{guid, name, description, overview, owner, category, versions: [{version, changelog, targetAbi, sourceUrl, checksum (MD5), timestamp}]}]`; `sourceUrl` deve finire con `.zip`.
- **App, test:** `clientInfoProvider` e `appConfigProvider` lanciano se non sovrascritti, quindi `jellyfinHttpProvider` non esiste nei test che non li sovrascrivono. Ogni test in cui `PartyChannel` nasce **ed** entra in un gruppo sovrascrive `partyChannelApiProvider` con `FakePartyChannelApi` (di default il plugin è assente): sono `party_channel_test`, `party_player_test`, `party_handover_test`, `watch_party_routing_test`, `watch_party_actions_test`, `diagnostics_test`. `PartyNotices` **non** legge il canale: è il canale che passa gli annunci agli avvisi, così i test degli avvisi non cambiano.
- **Riverpod 3:** dentro `build` non si cambia lo stato; il canale nato a gruppo già in corso entra con un `Future.microtask`. `ref.mounted` dopo ogni `await`.
- **fake_async:** `clock.now()` segue il tempo finto; gli eventi di uno `StreamController.broadcast` arrivano con `flushMicrotasks()`.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` | crea | progetto del plugin |
| `…/Plugin.cs`, `…/PluginServiceRegistrator.cs`, `…/WatchPartyHostedService.cs` | crea | plugin, servizi, `SessionEnded` + pulizia ogni 5 min |
| `…/Protocol/*.cs` | crea | costanti, DTO, validazione degli eventi |
| `…/Hub/*.cs` | crea | `CallerSession`, interfacce, `PartyRegistry`, `ChatHistory`, `RateLimiter`, `PartyHub` |
| `…/Server/*.cs` | crea | adattatori `ISessionManager`/`ISyncPlayManager` |
| `…/Api/WatchPartyController.cs` | crea | endpoint `Info`, `Join`, `Leave`, `Events` (e `Probe` fino al Task 6) |
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/*` | crea | test xUnit |
| `jellyfin-plugin-watch-party/pack.sh`, `meta.template.json`, `manifest.json`, `README.md`, `.gitignore`, `.gitattributes` | crea | pacchetto, repository, istruzioni |
| `.github/workflows/watch-party-plugin.yml` | crea | test e pre-release del plugin |
| `lib/core/party_channel/party_channel_models.dart`, `party_channel_api.dart` | crea | protocollo e chiamate al plugin |
| `lib/core/jellyfin/server_events.dart` | modifica | `PartyChannelReceived` |
| `lib/features/watch_party/watch_party_providers.dart` | modifica | `partyChannelApiProvider` |
| `lib/features/watch_party/party_notices.dart`, `party_notice_pill.dart`, `l10n/app_*.arb` | modifica | nome di chi agisce |
| `lib/features/watch_party/party_channel.dart` | crea | `PartyChannel` |
| `lib/features/watch_party/watch_party_routing.dart` | modifica | tiene vivo il canale |
| `lib/features/player/player_screen.dart`, `lib/features/watch_party/watch_party_actions.dart` | modifica | annunci delle nostre azioni |
| `lib/features/settings/diagnostics.dart` | modifica | riga del plugin |
| `test/…` | crea/modifica | test e finti (`watch_party_fakes.dart`) |
| `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1):** scheletro del plugin e sonda. **Poi ci si ferma** (Task 2, lo fa l'orchestratore con l'utente).
- **Gruppo B (Task 3–7):** plugin completo, pacchetto, workflow.
- **Gruppo C (Task 8–10):** nucleo del canale nell'app.
- **Gruppo D (Task 11–12):** nomi negli avvisi e `PartyChannel`.
- **Gruppo E (Task 13–14):** annunci e diagnostica.
- **Gruppo F (Task 15):** allineamento dello spec e verifica finale.

---

## Gruppo A — scheletro del plugin e sonda

### Task 1: progetto del plugin, `Info` e sonda `Probe`

**Files:**
- Create: `jellyfin-plugin-watch-party/.gitignore`, `jellyfin-plugin-watch-party/.gitattributes`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Plugin.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InfoResponse.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/WatchPartyController.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/Jellyfin.Plugin.WonderFlixWatchParty.Tests.csproj`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoTests.cs`
- Create: `jellyfin-plugin-watch-party/meta.template.json`, `jellyfin-plugin-watch-party/pack.sh`

- [ ] **Step 1: file di contorno**

`jellyfin-plugin-watch-party/.gitignore`:

```gitignore
bin/
obj/
artifacts/
```

`jellyfin-plugin-watch-party/.gitattributes` (lo script deve restare LF anche su Windows, altrimenti bash si ferma su `\r`):

```gitattributes
*.sh text eol=lf
```

- [ ] **Step 2: progetti**

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <RootNamespace>Jellyfin.Plugin.WonderFlixWatchParty</RootNamespace>
    <Version>1.0.0</Version>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

  <!-- 10.11.0, il minimo: il plugin si carica su ogni 10.11.x. Le dll di
       Jellyfin le ha il server: nel pacchetto va solo la nostra. -->
  <ItemGroup>
    <PackageReference Include="Jellyfin.Controller" Version="10.11.0">
      <ExcludeAssets>runtime</ExcludeAssets>
    </PackageReference>
    <PackageReference Include="Jellyfin.Model" Version="10.11.0">
      <ExcludeAssets>runtime</ExcludeAssets>
    </PackageReference>
  </ItemGroup>

  <ItemGroup>
    <InternalsVisibleTo Include="Jellyfin.Plugin.WonderFlixWatchParty.Tests" />
  </ItemGroup>

</Project>
```

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/Jellyfin.Plugin.WonderFlixWatchParty.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.14.1" />
    <PackageReference Include="xunit" Version="2.9.3" />
    <PackageReference Include="xunit.runner.visualstudio" Version="3.1.5" PrivateAssets="All" />
    <PackageReference Include="Microsoft.Extensions.TimeProvider.Testing" Version="9.10.0" />
    <!-- Il plugin esclude le dll di Jellyfin (le ha il server); i test le
         devono caricare, quindi si riferiscono di nuovo qui. -->
    <PackageReference Include="Jellyfin.Controller" Version="10.11.0" />
    <PackageReference Include="Jellyfin.Model" Version="10.11.0" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\Jellyfin.Plugin.WonderFlixWatchParty\Jellyfin.Plugin.WonderFlixWatchParty.csproj" />
  </ItemGroup>

</Project>
```

- [ ] **Step 3: scrivi il test che fallisce**

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

// Provvisorio: nel Task 6 il controller cambia costruttore e il test passa in
// WatchPartyControllerTests.
public class InfoTests
{
    [Fact]
    public void InfoReportsVersionAndProtocol()
    {
        var controller = new WatchPartyController(null!, null!);
        var info = controller.GetInfo().Value!;
        Assert.Equal("1.0.0", info.Version);
        Assert.Equal(1, info.Protocol);
    }
}
```

- [ ] **Step 4: esegui il test e verifica che fallisca**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: FAIL in compilazione (`WatchPartyController` non esiste).

- [ ] **Step 5: implementa**

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Plugin.cs`:

```csharp
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Plugin "WonderFlix Watch Party" (spec E): nomi, chat e reazioni nei
/// watch party SyncPlay di WonderFlix. Non ha impostazioni.
/// </summary>
public class Plugin : BasePlugin<BasePluginConfiguration>
{
    /// <summary>Id del plugin, uguale in meta.json e manifest.json.</summary>
    public static readonly Guid PluginId = Guid.Parse("882eb47e-668a-4935-ba55-c2858eb4ed90");

    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
    }

    public override string Name => "WonderFlix Watch Party";

    public override Guid Id => PluginId;

    public override string Description => "Names, chat and reactions for SyncPlay watch parties in WonderFlix.";
}
```

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`:

```csharp
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>Registra i servizi del plugin nel server.</summary>
public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        // Jellyfin non registra un TimeProvider.
        serviceCollection.TryAddSingleton(TimeProvider.System);
    }
}
```

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Costanti del protocollo con l'app (spec E §6.3).</summary>
public static class WatchPartyProtocol
{
    /// <summary>Versione del protocollo: l'app la confronta con la sua.</summary>
    public const int Version = 1;

    /// <summary>
    /// Chiave degli Arguments del GeneralCommand SendString con cui gli
    /// eventi arrivano ai client. Non è "String", che jellyfin-web
    /// scriverebbe nel campo con il focus.
    /// </summary>
    public const string ArgumentKey = "WonderFlixWatchParty";

    /// <summary>Lunghezza massima di un messaggio, in punti di codice (come nell'app).</summary>
    public const int MaxChatLength = 200;
}
```

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InfoResponse.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Risposta di GET /WonderFlixWatchParty/Info.</summary>
public sealed record InfoResponse(
    [property: JsonPropertyName("Version")] string Version,
    [property: JsonPropertyName("Protocol")] int Protocol);
```

`jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/WatchPartyController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Session;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>Endpoint del plugin (spec E §6.2).</summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class WatchPartyController(
    IAuthorizationContext authorizationContext,
    ISessionManager sessionManager) : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin e del protocollo.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(PluginVersion, WatchPartyProtocol.Version);

    /// <summary>
    /// Sonda provvisoria (piano 10a, Task 2): manda un SendString alla
    /// sessione di chi chiama. Si toglie nel Task 6.
    /// </summary>
    [HttpPost("Probe")]
    public async Task<ActionResult> Probe(CancellationToken cancellationToken)
    {
        var auth = await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        var session = sessionManager.Sessions.FirstOrDefault(s =>
            string.Equals(s.DeviceId, auth.DeviceId, StringComparison.Ordinal)
            && string.Equals(s.Client, auth.Client, StringComparison.Ordinal)
            && s.UserId.Equals(auth.UserId));
        if (session is null)
        {
            return Conflict();
        }

        var command = new GeneralCommand
        {
            Name = GeneralCommandType.SendString,
            Arguments = { [WatchPartyProtocol.ArgumentKey] = "{\"Probe\":1}" },
        };
        await sessionManager.SendGeneralCommand(null, session.Id, command, cancellationToken).ConfigureAwait(false);
        return Ok(new { SessionId = session.Id, session.Client });
    }
}
```

- [ ] **Step 6: esegui il test**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS (1 test), nessun warning nel progetto del plugin.

- [ ] **Step 7: pacchetto da installare a mano**

`jellyfin-plugin-watch-party/meta.template.json` (`@VERSION@` e `@TIMESTAMP@` li sostituisce `pack.sh`):

```json
{
  "category": "General",
  "changelog": "",
  "description": "Names, chat and reactions for SyncPlay watch parties in WonderFlix.",
  "guid": "882eb47e-668a-4935-ba55-c2858eb4ed90",
  "name": "WonderFlix Watch Party",
  "overview": "WonderFlix watch party: names, chat, reactions",
  "owner": "davidesidoti",
  "targetAbi": "10.11.0.0",
  "timestamp": "@TIMESTAMP@",
  "version": "@VERSION@",
  "status": "Active",
  "autoUpdate": true,
  "imagePath": "",
  "assemblies": ["Jellyfin.Plugin.WonderFlixWatchParty.dll"]
}
```

`jellyfin-plugin-watch-party/pack.sh`:

```bash
#!/usr/bin/env bash
# Crea in artifacts/ la cartella del plugin da copiare nei plugin di Jellyfin
# (dll + meta.json, spec E §6.8). Lo zip per il repository lo fa il workflow.
# Uso, dalla root del repository:
#   bash jellyfin-plugin-watch-party/pack.sh 1.0.0
set -euo pipefail

version="${1:?versione mancante, es. 1.0.0}"
here="$(cd "$(dirname "$0")" && pwd)"
artifacts="$here/artifacts"
folder="$artifacts/WonderFlix Watch Party_$version.0"

rm -rf "$artifacts"
dotnet publish "$here/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj" \
  --configuration Release --output "$artifacts/publish" -p:Version="$version"
mkdir -p "$folder"
cp "$artifacts/publish/Jellyfin.Plugin.WonderFlixWatchParty.dll" "$folder/"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sed -e "s/@VERSION@/$version.0/" -e "s/@TIMESTAMP@/$timestamp/" \
  "$here/meta.template.json" > "$folder/meta.json"
echo "$folder"
```

Run: `bash jellyfin-plugin-watch-party/pack.sh 1.0.0`
Expected: l'ultima riga è il percorso di `artifacts/WonderFlix Watch Party_1.0.0.0`; dentro ci sono **solo** `Jellyfin.Plugin.WonderFlixWatchParty.dll` e `meta.json` (con `"version": "1.0.0.0"` e una data vera). `git status` non mostra `artifacts/`, `bin/`, `obj/`.

- [ ] **Step 8: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat: add the watch party plugin skeleton with a probe endpoint"
```

### Task 2: sonda sul server vero (orchestratore e utente, nessun subagent)

Il piano si **ferma qui** finché la sonda non è verificata. Lo fa l'orchestratore insieme all'utente; nessun file cambia.

- [ ] **Step 1:** l'orchestratore costruisce il pacchetto nel worktree (`bash jellyfin-plugin-watch-party/pack.sh 1.0.0`) e dà all'utente il percorso della cartella `WonderFlix Watch Party_1.0.0.0`.
- [ ] **Step 2:** l'utente trova la cartella dei plugin di Jellyfin su Ultra.cc via SSH, per esempio con:

```bash
find ~ -maxdepth 6 -type d -name plugins -path '*jellyfin*' 2>/dev/null
```

poi copia via SFTP la cartella `WonderFlix Watch Party_1.0.0.0` dentro `plugins/` e riavvia Jellyfin dal pannello di Ultra.cc. In Dashboard → Plugin deve comparire "WonderFlix Watch Party" 1.0.0.0, attivo. Se compare come "Non supportato" o "Errore", si leggono i log di Jellyfin (Dashboard → Log) cercando `WonderFlix`.
- [ ] **Step 3:** l'utente apre jellyfin-web del suo server nel pannello del browser ed **entra lui** (l'orchestratore non scrive mai credenziali). Poi l'orchestratore esegue nella pagina (strumento JavaScript del browser) e legge solo il risultato:

```js
const seen = [];
const socket = ApiClient._webSocket;
if (socket) socket.addEventListener('message', (e) => {
  if (String(e.data).includes('WonderFlixWatchParty')) seen.push(String(e.data));
});
const info = await ApiClient.getJSON(ApiClient.getUrl('WonderFlixWatchParty/Info'));
const probe = await ApiClient.ajax({
  type: 'POST', url: ApiClient.getUrl('WonderFlixWatchParty/Probe'), dataType: 'json',
});
await new Promise((resolve) => setTimeout(resolve, 1500));
const anonymous = (await fetch(ApiClient.getUrl('WonderFlixWatchParty/Info'))).status;
({ info, probe, socket: !!socket, seen, anonymous })
```

Atteso: `info` = `{Version: '1.0.0', Protocol: 1}`; `probe` con `SessionId`; `seen` con **un** messaggio `GeneralCommand` il cui `Data.Name` è `SendString` e `Data.Arguments.WonderFlixWatchParty` è `{"Probe":1}`; `anonymous` ≠ 404 (**esito della sonda, 2026-10-02:** tutto come atteso; senza autenticazione la risposta è **400**, come per gli endpoint SyncPlay di Jellyfin: la loro policy va in errore su un utente anonimo. Plugin in `~/.apps/jellyfin/data/plugins/`, riavvio con `ssh ultra app-jellyfin restart`). Se `ApiClient._webSocket` non esiste in questa versione di jellyfin-web, cercare la proprietà del socket con `Object.keys(ApiClient)` e ripetere; in alternativa l'utente esegue lo stesso codice negli strumenti per sviluppatori del suo browser e guarda la scheda Network → WS.
- [ ] **Step 4:** esito all'utente. Se il messaggio non arriva o il plugin non si carica, **non** si prosegue: si torna al design (spec E §17, primo rischio). Se tutto torna, si riparte con il gruppo B.

---

## Gruppo B — plugin completo

### Task 3: protocollo (DTO e validazione)

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/EventTypes.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/EventRequest.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/StampedEvent.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/JoinResponse.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/EventValidator.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/EventValidatorTests.cs`, `ProtocolJsonTests.cs`

- [ ] **Step 1: scrivi i test che falliscono**

`EventValidatorTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class EventValidatorTests
{
    private static EventRequest Request(
        string? type,
        string? action = null,
        long? ticks = null,
        string? text = null,
        string? reaction = null) =>
        new() { Type = type, Action = action, PositionTicks = ticks, Text = text, Reaction = reaction };

    [Theory]
    [InlineData("Pause")]
    [InlineData("Unpause")]
    [InlineData("NextItem")]
    [InlineData("NewQueue")]
    public void ActionsWithoutPosition(string action)
    {
        var valid = EventValidator.Validate(Request(EventTypes.Action, action, ticks: 5));
        Assert.NotNull(valid);
        Assert.Equal(EventTypes.Action, valid.Type);
        Assert.Equal(action, valid.Action);
        Assert.Null(valid.PositionTicks);
    }

    [Fact]
    public void SeekNeedsAPosition()
    {
        Assert.Equal(600000000L, EventValidator.Validate(Request(EventTypes.Action, "Seek", 600000000))!.PositionTicks);
        Assert.Equal(0L, EventValidator.Validate(Request(EventTypes.Action, "Seek", 0))!.PositionTicks);
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action, "Seek")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action, "Seek", -1)));
    }

    [Fact]
    public void UnknownTypesAndActionsAreInvalid()
    {
        Assert.Null(EventValidator.Validate(null));
        Assert.Null(EventValidator.Validate(Request(null)));
        Assert.Null(EventValidator.Validate(Request("Poll")));
        // I valori distinguono le maiuscole (i nomi delle proprietà no).
        Assert.Null(EventValidator.Validate(Request("chat", text: "x")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action, "Shuffle")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action)));
    }

    [Fact]
    public void ChatTextIsNormalizedAndLimited()
    {
        Assert.Equal("ciao a tutti", EventValidator.Validate(Request(EventTypes.Chat, text: "  ciao\r\na tutti\n "))!.Text);
        Assert.Null(EventValidator.Validate(Request(EventTypes.Chat, text: "  \n ")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Chat)));
        Assert.NotNull(EventValidator.Validate(Request(EventTypes.Chat, text: new string('x', 200))));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Chat, text: new string('x', 201))));
        // Un'emoji vale un carattere, come nell'app.
        var emoji = string.Concat(Enumerable.Repeat("😂", 200));
        Assert.NotNull(EventValidator.Validate(Request(EventTypes.Chat, text: emoji)));
    }

    [Fact]
    public void ReactionsAreShortLowercaseIds()
    {
        Assert.Equal("joy", EventValidator.Validate(Request(EventTypes.Reaction, reaction: "joy"))!.Reaction);
        // Il plugin non controlla l'elenco: le app ignorano quelle che non conoscono.
        Assert.NotNull(EventValidator.Validate(Request(EventTypes.Reaction, reaction: "heart")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction, reaction: "Joy")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction, reaction: "joy\n")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction, reaction: new string('a', 21))));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction)));
    }
}
```

`ProtocolJsonTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ProtocolJsonTests
{
    [Fact]
    public void StampedEventUsesProtocolNamesAndSkipsEmptyFields()
    {
        var stamped = new StampedEvent
        {
            Id = "e1",
            GroupId = "g1",
            Type = EventTypes.Chat,
            UserId = "u1",
            UserName = "Mario",
            SentAt = "2026-10-02T21:14:03.512Z",
            Text = "ciao",
        };
        Assert.Equal(
            "{\"Protocol\":1,\"Id\":\"e1\",\"GroupId\":\"g1\",\"Type\":\"Chat\",\"UserId\":\"u1\","
            + "\"UserName\":\"Mario\",\"SentAt\":\"2026-10-02T21:14:03.512Z\",\"Text\":\"ciao\"}",
            JsonSerializer.Serialize(stamped));
    }

    [Fact]
    public void EventRequestReadsAnyCaseOfNames()
    {
        // Come i controller di Jellyfin: nomi delle proprietà senza maiuscole.
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var request = JsonSerializer.Deserialize<EventRequest>(
            "{\"type\":\"Action\",\"Action\":\"Seek\",\"PositionTicks\":600000000}", options)!;
        Assert.Equal("Action", request.Type);
        Assert.Equal("Seek", request.Action);
        Assert.Equal(600000000L, request.PositionTicks);
    }

    [Fact]
    public void InfoAndJoinResponsesUseProtocolNames()
    {
        Assert.Equal("{\"Version\":\"1.0.0\",\"Protocol\":1}", JsonSerializer.Serialize(new InfoResponse("1.0.0", 1)));
        Assert.Equal("{\"Messages\":[]}", JsonSerializer.Serialize(new JoinResponse([])));
    }
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: FAIL in compilazione (`EventValidator`, `EventRequest`, … non esistono).

- [ ] **Step 3: implementa**

`Protocol/EventTypes.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi di evento del protocollo (spec E §6.3).</summary>
public static class EventTypes
{
    public const string Action = "Action";
    public const string Chat = "Chat";
    public const string Reaction = "Reaction";
}
```

`Protocol/EventRequest.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Corpo di POST …/Groups/{groupId}/Events: un evento mandato dall'app.</summary>
public sealed class EventRequest
{
    [JsonPropertyName("Type")]
    public string? Type { get; set; }

    /// <summary>Per Action: Pause, Unpause, Seek, NextItem, NewQueue.</summary>
    [JsonPropertyName("Action")]
    public string? Action { get; set; }

    /// <summary>Per Action Seek.</summary>
    [JsonPropertyName("PositionTicks")]
    public long? PositionTicks { get; set; }

    [JsonPropertyName("Text")]
    public string? Text { get; set; }

    [JsonPropertyName("Reaction")]
    public string? Reaction { get; set; }
}
```

`Protocol/StampedEvent.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Un evento timbrato dal plugin (spec E §6.3): chi l'ha mandato lo dice la
/// sessione autenticata, mai il corpo della richiesta. È la risposta di
/// Events, una voce dello storico e il contenuto inoltrato ai client.
/// </summary>
public sealed class StampedEvent
{
    [JsonPropertyName("Protocol")]
    public int Protocol { get; init; } = WatchPartyProtocol.Version;

    /// <summary>Guid in formato "N": l'app lo usa per togliere i doppioni.</summary>
    [JsonPropertyName("Id")]
    public required string Id { get; init; }

    [JsonPropertyName("GroupId")]
    public required string GroupId { get; init; }

    [JsonPropertyName("Type")]
    public required string Type { get; init; }

    [JsonPropertyName("UserId")]
    public required string UserId { get; init; }

    [JsonPropertyName("UserName")]
    public required string UserName { get; init; }

    /// <summary>Ora UTC del server, es. 2026-10-02T21:14:03.512Z.</summary>
    [JsonPropertyName("SentAt")]
    public required string SentAt { get; init; }

    [JsonPropertyName("Action")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Action { get; init; }

    [JsonPropertyName("PositionTicks")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public long? PositionTicks { get; init; }

    [JsonPropertyName("Text")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Text { get; init; }

    [JsonPropertyName("Reaction")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Reaction { get; init; }
}
```

`Protocol/JoinResponse.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Risposta di Join: lo storico della chat, dal messaggio più vecchio.</summary>
public sealed record JoinResponse(
    [property: JsonPropertyName("Messages")] IReadOnlyList<StampedEvent> Messages);
```

`Protocol/EventValidator.cs`:

```csharp
using System.Text.RegularExpressions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un evento valido e normalizzato, pronto da timbrare.</summary>
public sealed record ValidatedEvent(
    string Type,
    string? Action = null,
    long? PositionTicks = null,
    string? Text = null,
    string? Reaction = null);

/// <summary>Validazione degli eventi mandati dall'app (spec E §6.3).</summary>
public static partial class EventValidator
{
    private static readonly HashSet<string> Actions = new(StringComparer.Ordinal)
    {
        "Pause", "Unpause", "Seek", "NextItem", "NewQueue",
    };

    /// <summary>L'evento valido e normalizzato; null se non è valido.</summary>
    public static ValidatedEvent? Validate(EventRequest? request)
    {
        if (request is null)
        {
            return null;
        }

        switch (request.Type)
        {
            case EventTypes.Action:
                if (request.Action is not { } action || !Actions.Contains(action))
                {
                    return null;
                }

                if (action != "Seek")
                {
                    return new ValidatedEvent(EventTypes.Action, action);
                }

                return request.PositionTicks is >= 0
                    ? new ValidatedEvent(EventTypes.Action, action, request.PositionTicks)
                    : null;
            case EventTypes.Chat:
                var text = NormalizeText(request.Text);
                var length = text.EnumerateRunes().Count();
                return length is >= 1 and <= WatchPartyProtocol.MaxChatLength
                    ? new ValidatedEvent(EventTypes.Chat, Text: text)
                    : null;
            case EventTypes.Reaction:
                // Il plugin non controlla l'elenco: le app ignorano quelle che non conoscono.
                return request.Reaction is { } reaction && ReactionPattern().IsMatch(reaction)
                    ? new ValidatedEvent(EventTypes.Reaction, Reaction: reaction)
                    : null;
            default:
                return null;
        }
    }

    /// <summary>A capo diventati spazi, spazi esterni tolti (come normalizeChatText dell'app).</summary>
    public static string NormalizeText(string? text) =>
        LineBreaks().Replace(text ?? string.Empty, " ").Trim();

    [GeneratedRegex(@"^[a-z]{1,20}\z")]
    private static partial Regex ReactionPattern();

    [GeneratedRegex(@"[\r\n]+")]
    private static partial Regex LineBreaks();
}
```

- [ ] **Step 4: esegui i test**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat: validate and stamp watch party plugin events"
```

### Task 4: registro, storico e limiti

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyRegistry.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/ChatHistory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/RateLimiter.cs`
- Test: `…Tests/PartyRegistryTests.cs`, `…Tests/ChatHistoryTests.cs`, `…Tests/RateLimiterTests.cs`

- [ ] **Step 1: scrivi i test che falliscono**

`PartyRegistryTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PartyRegistryTests
{
    private static readonly Guid G1 = Guid.Parse("11111111111111111111111111111111");
    private static readonly Guid G2 = Guid.Parse("22222222222222222222222222222222");

    private static IEnumerable<string> Names(PartyRegistry registry, Guid group) =>
        registry.GetSessions(group).Select(s => $"{s.SessionId}:{s.UserName}").Order();

    [Fact]
    public void RegisterAndList()
    {
        var registry = new PartyRegistry();
        registry.Register(G1, "s1", "Mario");
        registry.Register(G1, "s2", "Luigi");
        Assert.Equal(new[] { "s1:Mario", "s2:Luigi" }, Names(registry, G1));
        Assert.True(registry.IsRegistered(G1, "s2"));
        Assert.Empty(registry.GetSessions(G2));
    }

    [Fact]
    public void ASessionIsInOneGroupOnly()
    {
        var registry = new PartyRegistry();
        registry.Register(G1, "s1", "Mario");
        registry.Register(G2, "s1", "Mario");
        Assert.False(registry.IsRegistered(G1, "s1"));
        Assert.True(registry.IsRegistered(G2, "s1"));
        Assert.Equal(G2, Assert.Single(registry.GetGroups()));
    }

    [Fact]
    public void UnregisterRemoveSessionAndRemoveGroup()
    {
        var registry = new PartyRegistry();
        registry.Register(G1, "s1", "Mario");
        registry.Register(G1, "s2", "Luigi");
        registry.Unregister(G1, "s1");
        Assert.False(registry.IsRegistered(G1, "s1"));
        registry.RemoveSession("s2");
        Assert.Empty(registry.GetGroups());
        registry.Register(G1, "s3", "Peach");
        registry.RemoveGroup(G1);
        Assert.Empty(registry.GetSessions(G1));
    }
}
```

`ChatHistoryTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ChatHistoryTests
{
    private static StampedEvent Chat(string id) => new()
    {
        Id = id,
        GroupId = "g",
        Type = EventTypes.Chat,
        UserId = "u",
        UserName = "Mario",
        SentAt = "2026-10-02T21:00:00.000Z",
        Text = id,
    };

    [Fact]
    public void KeepsTheLast50InOrder()
    {
        var history = new ChatHistory();
        var group = Guid.NewGuid();
        for (var i = 1; i <= 55; i++)
        {
            history.Add(group, Chat($"m{i}"));
        }

        var messages = history.Get(group);
        Assert.Equal(ChatHistory.Capacity, messages.Count);
        Assert.Equal("m6", messages[0].Id);
        Assert.Equal("m55", messages[^1].Id);
    }

    [Fact]
    public void GroupsAreSeparateAndRemovable()
    {
        var history = new ChatHistory();
        var g1 = Guid.NewGuid();
        var g2 = Guid.NewGuid();
        history.Add(g1, Chat("a"));
        history.Add(g2, Chat("b"));
        Assert.Equal("a", Assert.Single(history.Get(g1)).Id);
        history.Remove(g1);
        Assert.Empty(history.Get(g1));
        Assert.Equal(g2, Assert.Single(history.GetGroups()));
    }
}
```

`RateLimiterTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RateLimiterTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 2, 21, 0, 0, TimeSpan.Zero));

    private static void Allow(RateLimiter limiter, string type, int times)
    {
        for (var i = 0; i < times; i++)
        {
            Assert.True(limiter.TryAcquire("s1", type), $"{type} n. {i + 1}");
        }
    }

    [Fact]
    public void ChatFivePerTenSeconds()
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, EventTypes.Chat, 5);
        Assert.False(limiter.TryAcquire("s1", EventTypes.Chat));
        Assert.True(limiter.TryAcquire("s2", EventTypes.Chat), "ogni sessione ha i suoi limiti");
        Assert.True(limiter.TryAcquire("s1", EventTypes.Reaction), "ogni tipo ha i suoi limiti");
        _time.Advance(TimeSpan.FromSeconds(9));
        Assert.False(limiter.TryAcquire("s1", EventTypes.Chat));
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(limiter.TryAcquire("s1", EventTypes.Chat));
    }

    [Fact]
    public void ReactionsEightPerFiveSecondsActionsTwentyPerTen()
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, EventTypes.Reaction, 8);
        Assert.False(limiter.TryAcquire("s1", EventTypes.Reaction));
        Allow(limiter, EventTypes.Action, 20);
        Assert.False(limiter.TryAcquire("s1", EventTypes.Action));
        _time.Advance(TimeSpan.FromSeconds(5));
        Assert.True(limiter.TryAcquire("s1", EventTypes.Reaction));
        Assert.False(limiter.TryAcquire("s1", EventTypes.Action));
    }

    [Fact]
    public void ForgetClearsASession()
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, EventTypes.Chat, 5);
        limiter.Forget("s1");
        Assert.True(limiter.TryAcquire("s1", EventTypes.Chat));
    }
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: FAIL in compilazione.

- [ ] **Step 3: implementa**

`Hub/PartyRegistry.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Gruppo → sessioni WonderFlix registrate, con il nome utente di ciascuna
/// (spec E §6.5). Una sessione sta in un solo gruppo, come in SyncPlay.
/// Sicuro tra thread.
/// </summary>
public sealed class PartyRegistry
{
    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Dictionary<string, string>> _groups = [];

    public void Register(Guid groupId, string sessionId, string userName)
    {
        lock (_lock)
        {
            RemoveSessionLocked(sessionId);
            if (!_groups.TryGetValue(groupId, out var sessions))
            {
                sessions = new Dictionary<string, string>(StringComparer.Ordinal);
                _groups[groupId] = sessions;
            }

            sessions[sessionId] = userName;
        }
    }

    public bool IsRegistered(Guid groupId, string sessionId)
    {
        lock (_lock)
        {
            return _groups.TryGetValue(groupId, out var sessions) && sessions.ContainsKey(sessionId);
        }
    }

    public void Unregister(Guid groupId, string sessionId)
    {
        lock (_lock)
        {
            if (_groups.TryGetValue(groupId, out var sessions)
                && sessions.Remove(sessionId)
                && sessions.Count == 0)
            {
                _groups.Remove(groupId);
            }
        }
    }

    /// <summary>Toglie la sessione da qualunque gruppo.</summary>
    public void RemoveSession(string sessionId)
    {
        lock (_lock)
        {
            RemoveSessionLocked(sessionId);
        }
    }

    public IReadOnlyList<(string SessionId, string UserName)> GetSessions(Guid groupId)
    {
        lock (_lock)
        {
            return _groups.TryGetValue(groupId, out var sessions)
                ? sessions.Select(s => (SessionId: s.Key, UserName: s.Value)).ToList()
                : [];
        }
    }

    public IReadOnlyList<Guid> GetGroups()
    {
        lock (_lock)
        {
            return _groups.Keys.ToList();
        }
    }

    public void RemoveGroup(Guid groupId)
    {
        lock (_lock)
        {
            _groups.Remove(groupId);
        }
    }

    private void RemoveSessionLocked(string sessionId)
    {
        foreach (var (groupId, sessions) in _groups.ToList())
        {
            if (sessions.Remove(sessionId) && sessions.Count == 0)
            {
                _groups.Remove(groupId);
            }
        }
    }
}
```

`Hub/ChatHistory.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Ultimi messaggi della chat di ogni gruppo, solo in memoria (spec E §6.5):
/// si perdono al riavvio del server. Sicuro tra thread.
/// </summary>
public sealed class ChatHistory
{
    /// <summary>Messaggi tenuti per gruppo.</summary>
    public const int Capacity = 50;

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, Queue<StampedEvent>> _groups = [];

    public void Add(Guid groupId, StampedEvent message)
    {
        lock (_lock)
        {
            if (!_groups.TryGetValue(groupId, out var messages))
            {
                messages = new Queue<StampedEvent>();
                _groups[groupId] = messages;
            }

            messages.Enqueue(message);
            while (messages.Count > Capacity)
            {
                messages.Dequeue();
            }
        }
    }

    /// <summary>I messaggi del gruppo, dal più vecchio.</summary>
    public IReadOnlyList<StampedEvent> Get(Guid groupId)
    {
        lock (_lock)
        {
            return _groups.TryGetValue(groupId, out var messages) ? messages.ToList() : [];
        }
    }

    public IReadOnlyList<Guid> GetGroups()
    {
        lock (_lock)
        {
            return _groups.Keys.ToList();
        }
    }

    public void Remove(Guid groupId)
    {
        lock (_lock)
        {
            _groups.Remove(groupId);
        }
    }
}
```

`Hub/RateLimiter.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Limiti di frequenza per sessione e tipo di evento, a finestra scorrevole
/// (spec E §6.6). Sicuro tra thread.
/// </summary>
public sealed class RateLimiter(TimeProvider time)
{
    private static readonly Dictionary<string, (int Count, TimeSpan Window)> Limits =
        new(StringComparer.Ordinal)
        {
            [EventTypes.Chat] = (5, TimeSpan.FromSeconds(10)),
            [EventTypes.Reaction] = (8, TimeSpan.FromSeconds(5)),
            [EventTypes.Action] = (20, TimeSpan.FromSeconds(10)),
        };

    private readonly Lock _lock = new();
    private readonly Dictionary<(string SessionId, string Type), Queue<DateTimeOffset>> _sent = [];

    /// <summary>true (e l'evento si conta) se la sessione può mandarne un altro di questo tipo adesso.</summary>
    public bool TryAcquire(string sessionId, string type)
    {
        if (!Limits.TryGetValue(type, out var limit))
        {
            return true;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (!_sent.TryGetValue((sessionId, type), out var times))
            {
                times = new Queue<DateTimeOffset>();
                _sent[(sessionId, type)] = times;
            }

            while (times.Count > 0 && now - times.Peek() >= limit.Window)
            {
                times.Dequeue();
            }

            if (times.Count >= limit.Count)
            {
                return false;
            }

            times.Enqueue(now);
            return true;
        }
    }

    /// <summary>La sessione è finita: i suoi conteggi non servono più.</summary>
    public void Forget(string sessionId)
    {
        lock (_lock)
        {
            foreach (var key in _sent.Keys.Where(k => k.SessionId == sessionId).ToList())
            {
                _sent.Remove(key);
            }
        }
    }
}
```

(`System.Threading.Lock` esiste da .NET 9; con `lock (_lock)` il compilatore usa il suo `EnterScope`.)

- [ ] **Step 4: esegui i test**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat: keep watch party sessions, chat history and rate limits"
```

### Task 5: `PartyHub`

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/CallerSession.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/ISessionDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/IGroupDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/IEventSender.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyHub.cs`
- Create: `…Tests/FakeServer.cs`, `…Tests/PartyHubTests.cs`

- [ ] **Step 1: interfacce (servono ai test)**

`Hub/CallerSession.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Chi chiama: la sua sessione Jellyfin e il suo utente.</summary>
public sealed record CallerSession(string SessionId, Guid UserId, string UserName);
```

`Hub/ISessionDirectory.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Le sessioni del server (adattatore di ISessionManager).</summary>
public interface ISessionDirectory
{
    /// <summary>
    /// La sessione di chi chiama, dal dispositivo, dal client e dall'utente
    /// dell'autenticazione; null se non c'è.
    /// </summary>
    CallerSession? FindCaller(string? deviceId, string? client, Guid userId);

    /// <summary>La sessione esiste ancora.</summary>
    bool Exists(string sessionId);
}
```

`Hub/IGroupDirectory.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>I gruppi SyncPlay (adattatore di ISyncPlayManager).</summary>
public interface IGroupDirectory
{
    /// <summary>
    /// I nomi utente dei partecipanti del gruppo, visto dalla sessione;
    /// null se il gruppo non esiste, l'utente non può vederlo o la sessione
    /// non c'è più.
    /// </summary>
    IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId);
}
```

`Hub/IEventSender.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Invio di un evento a una sessione, sul suo WebSocket.</summary>
public interface IEventSender
{
    /// <summary>Manda payload alla sessione; false se la sessione non esiste più.</summary>
    Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken);
}
```

- [ ] **Step 2: scrivi i test che falliscono**

`…Tests/FakeServer.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Server finto: sessioni, gruppi SyncPlay e invii, in memoria.</summary>
internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender
{
    public List<CallerSession> Sessions { get; } = [];

    /// <summary>Gruppo → nomi utente dei partecipanti.</summary>
    public Dictionary<Guid, List<string>> Groups { get; } = [];

    public List<(string SessionId, string Payload)> Sent { get; } = [];

    /// <summary>Sessioni per cui l'invio lancia un errore.</summary>
    public HashSet<string> Failing { get; } = [];

    public CallerSession AddSession(string sessionId, string userName)
    {
        var session = new CallerSession(sessionId, Guid.NewGuid(), userName);
        Sessions.Add(session);
        return session;
    }

    // Nei test il dispositivo di una sessione ha lo stesso id della sessione.
    public CallerSession? FindCaller(string? deviceId, string? client, Guid userId) =>
        Sessions.FirstOrDefault(s => s.SessionId == deviceId && s.UserId == userId);

    public bool Exists(string sessionId) => Sessions.Any(s => s.SessionId == sessionId);

    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId) =>
        Exists(sessionId) && Groups.TryGetValue(groupId, out var participants) ? participants : null;

    public Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken)
    {
        if (Failing.Contains(sessionId))
        {
            throw new InvalidOperationException("invio fallito");
        }

        if (!Exists(sessionId))
        {
            return Task.FromResult(false);
        }

        Sent.Add((sessionId, payload));
        return Task.FromResult(true);
    }
}
```

`…Tests/PartyHubTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PartyHubTests
{
    private static readonly Guid Group = Guid.Parse("9a1e2b3c-4d5e-6f70-8192-a3b4c5d6e7f8");

    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 2, 21, 14, 3, 512, TimeSpan.Zero));
    private readonly PartyHub _hub;
    private readonly CallerSession _mario;
    private readonly CallerSession _luigi;

    public PartyHubTests()
    {
        _hub = new PartyHub(
            _server, _server, _server, new PartyRegistry(), new ChatHistory(), new RateLimiter(_time), _time,
            NullLogger<PartyHub>.Instance);
        _mario = _server.AddSession("s-mario", "Mario");
        _luigi = _server.AddSession("s-luigi", "Luigi");
        _server.Groups[Group] = ["Mario", "Luigi"];
    }

    private static EventRequest Chat(string text) => new() { Type = EventTypes.Chat, Text = text };

    private CallerSession AddPeach()
    {
        _server.Groups[Group].Add("Peach");
        return _server.AddSession("s-peach", "Peach");
    }

    [Fact]
    public void JoinOutsideTheGroupIsForbidden()
    {
        var bowser = _server.AddSession("s-bowser", "Bowser");
        Assert.Equal(HubStatus.Forbidden, _hub.Join(bowser, Group).Status);
        Assert.Equal(HubStatus.Forbidden, _hub.Join(_mario, Guid.NewGuid()).Status);
    }

    [Fact]
    public async Task JoinReturnsTheChatHistory()
    {
        Assert.Equal(HubStatus.Ok, _hub.Join(_luigi, Group).Status);
        await _hub.PostAsync(_luigi, Group, Chat("ciao"), CancellationToken.None);
        await _hub.PostAsync(_luigi, Group, new EventRequest { Type = EventTypes.Reaction, Reaction = "joy" }, CancellationToken.None);
        var joined = _hub.Join(_mario, Group);
        Assert.Equal(HubStatus.Ok, joined.Status);
        Assert.Equal("ciao", Assert.Single(joined.Value!).Text);
    }

    [Fact]
    public async Task NamesComeFromTheSessionNotFromTheBody()
    {
        _hub.Join(_mario, Group);
        var result = await _hub.PostAsync(_mario, Group, Chat("che scena"), CancellationToken.None);
        Assert.Equal(HubStatus.Ok, result.Status);
        var stamped = result.Value!;
        Assert.Equal("Mario", stamped.UserName);
        Assert.Equal(_mario.UserId.ToString("N"), stamped.UserId);
        Assert.Equal(Group.ToString("N"), stamped.GroupId);
        Assert.Equal("2026-10-02T21:14:03.512Z", stamped.SentAt);
        Assert.Equal(32, stamped.Id.Length);
        Assert.Equal(WatchPartyProtocol.Version, stamped.Protocol);
        Assert.Equal("che scena", stamped.Text);
    }

    [Fact]
    public async Task EventsGoToTheOtherSessionsOnly()
    {
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        await _hub.PostAsync(
            _mario, Group, new EventRequest { Type = EventTypes.Action, Action = "Seek", PositionTicks = 600000000 },
            CancellationToken.None);
        var (sessionId, payload) = Assert.Single(_server.Sent);
        Assert.Equal("s-luigi", sessionId);
        var json = JsonDocument.Parse(payload).RootElement;
        Assert.Equal("Action", json.GetProperty("Type").GetString());
        Assert.Equal("Seek", json.GetProperty("Action").GetString());
        Assert.Equal(600000000L, json.GetProperty("PositionTicks").GetInt64());
        Assert.Equal("Mario", json.GetProperty("UserName").GetString());
        Assert.False(json.TryGetProperty("Text", out _));
    }

    [Fact]
    public async Task SessionsThatLeftTheGroupOrEndedAreDropped()
    {
        var peach = AddPeach();
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        _hub.Join(peach, Group);
        _server.Groups[Group].Remove("Luigi");
        _server.Sessions.Remove(peach);
        await _hub.PostAsync(_mario, Group, Chat("ci siete?"), CancellationToken.None);
        Assert.Empty(_server.Sent);
        // Luigi torna nel gruppo SyncPlay ma non si è registrato di nuovo.
        _server.Groups[Group].Add("Luigi");
        await _hub.PostAsync(_mario, Group, Chat("e adesso?"), CancellationToken.None);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task AFailedSendDoesNotStopTheOthers()
    {
        var peach = AddPeach();
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        _hub.Join(peach, Group);
        _server.Failing.Add("s-luigi");
        var result = await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal("s-peach", Assert.Single(_server.Sent).SessionId);
    }

    [Fact]
    public async Task InvalidForbiddenAndRateLimited()
    {
        Assert.Equal(HubStatus.Invalid, (await _hub.PostAsync(_mario, Group, Chat("  "), CancellationToken.None)).Status);
        var bowser = _server.AddSession("s-bowser", "Bowser");
        Assert.Equal(HubStatus.Forbidden, (await _hub.PostAsync(bowser, Group, Chat("ciao"), CancellationToken.None)).Status);
        for (var i = 0; i < 5; i++)
        {
            Assert.Equal(HubStatus.Ok, (await _hub.PostAsync(_mario, Group, Chat($"m{i}"), CancellationToken.None)).Status);
        }

        var limited = await _hub.PostAsync(_mario, Group, Chat("troppo"), CancellationToken.None);
        Assert.Equal(HubStatus.RateLimited, limited.Status);
        Assert.Equal(5, _hub.Join(_luigi, Group).Value!.Count);
    }

    [Fact]
    public async Task PostingRegistersTheSender()
    {
        _hub.Join(_luigi, Group);
        await _hub.PostAsync(_mario, Group, new EventRequest { Type = EventTypes.Reaction, Reaction = "joy" }, CancellationToken.None);
        _server.Sent.Clear();
        await _hub.PostAsync(_luigi, Group, Chat("ciao Mario"), CancellationToken.None);
        Assert.Equal("s-mario", Assert.Single(_server.Sent).SessionId);
    }

    [Fact]
    public async Task LeaveAndRemoveSessionStopForwarding()
    {
        var peach = AddPeach();
        _hub.Join(_mario, Group);
        _hub.Join(_luigi, Group);
        _hub.Join(peach, Group);
        _hub.Leave(_luigi, Group);
        _hub.RemoveSession("s-peach");
        await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        Assert.Empty(_server.Sent);
    }

    [Fact]
    public async Task CleanupDropsEndedGroupsAndTheirHistory()
    {
        _hub.Join(_mario, Group);
        await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        Assert.Equal(0, _hub.Cleanup());
        _server.Groups.Remove(Group);
        Assert.Equal(1, _hub.Cleanup());
        _server.Groups[Group] = ["Mario", "Luigi"];
        Assert.Empty(_hub.Join(_mario, Group).Value!);
    }

    [Fact]
    public async Task CleanupDropsGroupsWithoutLiveSessions()
    {
        _hub.Join(_mario, Group);
        await _hub.PostAsync(_mario, Group, Chat("ciao"), CancellationToken.None);
        _server.Sessions.Remove(_mario);
        Assert.Equal(1, _hub.Cleanup());
        Assert.Empty(_hub.Join(_luigi, Group).Value!);
    }
}
```

- [ ] **Step 3: esegui i test e verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: FAIL in compilazione (`PartyHub` non esiste).

- [ ] **Step 4: implementa**

`Hub/PartyHub.cs`:

```csharp
using System.Globalization;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di un'operazione di <see cref="PartyHub"/>.</summary>
public enum HubStatus
{
    /// <summary>Riuscita.</summary>
    Ok,

    /// <summary>Gruppo inesistente o utente non nel gruppo (403).</summary>
    Forbidden,

    /// <summary>Evento non valido (400).</summary>
    Invalid,

    /// <summary>Limite di frequenza superato (429).</summary>
    RateLimited,
}

/// <summary>Esito con il valore, se riuscita.</summary>
public sealed record HubResult<T>(HubStatus Status, T? Value)
    where T : class
{
    public static HubResult<T> Ok(T value) => new(HubStatus.Ok, value);

    public static HubResult<T> Fail(HubStatus status) => new(status, null);
}

/// <summary>
/// Il centro del plugin (spec E §6): registro dei gruppi, storico della chat,
/// limiti e inoltro. Non conosce Jellyfin: parla con le interfacce di Hub.
/// </summary>
public sealed class PartyHub(
    IGroupDirectory groups,
    ISessionDirectory sessions,
    IEventSender sender,
    PartyRegistry registry,
    ChatHistory history,
    RateLimiter limiter,
    TimeProvider time,
    ILogger<PartyHub> logger)
{
    /// <summary>Registra la sessione nel gruppo e restituisce lo storico della chat.</summary>
    public HubResult<IReadOnlyList<StampedEvent>> Join(CallerSession caller, Guid groupId)
    {
        if (ParticipantsFor(caller, groupId) is null)
        {
            return HubResult<IReadOnlyList<StampedEvent>>.Fail(HubStatus.Forbidden);
        }

        registry.Register(groupId, caller.SessionId, caller.UserName);
        logger.LogDebug("Sessione {SessionId} nel watch party {GroupId}", caller.SessionId, groupId);
        return HubResult<IReadOnlyList<StampedEvent>>.Ok(history.Get(groupId));
    }

    public void Leave(CallerSession caller, Guid groupId) =>
        registry.Unregister(groupId, caller.SessionId);

    /// <summary>
    /// Valida, timbra, conserva (solo la chat) e inoltra un evento agli altri
    /// membri. Registra anche chi lo manda, se non lo era (es. dopo un
    /// riavvio del plugin).
    /// </summary>
    public async Task<HubResult<StampedEvent>> PostAsync(
        CallerSession caller,
        Guid groupId,
        EventRequest? request,
        CancellationToken cancellationToken)
    {
        var valid = EventValidator.Validate(request);
        if (valid is null)
        {
            return HubResult<StampedEvent>.Fail(HubStatus.Invalid);
        }

        var participants = ParticipantsFor(caller, groupId);
        if (participants is null)
        {
            return HubResult<StampedEvent>.Fail(HubStatus.Forbidden);
        }

        if (!limiter.TryAcquire(caller.SessionId, valid.Type))
        {
            return HubResult<StampedEvent>.Fail(HubStatus.RateLimited);
        }

        registry.Register(groupId, caller.SessionId, caller.UserName);
        var stamped = new StampedEvent
        {
            Id = Guid.NewGuid().ToString("N"),
            GroupId = groupId.ToString("N"),
            Type = valid.Type,
            UserId = caller.UserId.ToString("N"),
            UserName = caller.UserName,
            SentAt = time.GetUtcNow().UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
            Action = valid.Action,
            PositionTicks = valid.PositionTicks,
            Text = valid.Text,
            Reaction = valid.Reaction,
        };
        if (valid.Type == EventTypes.Chat)
        {
            history.Add(groupId, stamped);
        }

        // Mai il testo nei log (spec E §6.6).
        logger.LogDebug("Evento {Type} di {UserId} nel watch party {GroupId}", valid.Type, caller.UserId, groupId);
        await ForwardAsync(groupId, caller.SessionId, participants, stamped, cancellationToken).ConfigureAwait(false);
        return HubResult<StampedEvent>.Ok(stamped);
    }

    /// <summary>Una sessione è finita (evento SessionEnded di Jellyfin).</summary>
    public void RemoveSession(string sessionId)
    {
        registry.RemoveSession(sessionId);
        limiter.Forget(sessionId);
    }

    /// <summary>
    /// Toglie registro e storico dei gruppi finiti o senza sessioni vive
    /// (spec E §6.5). Restituisce quanti gruppi ha tolto.
    /// </summary>
    public int Cleanup()
    {
        var removed = 0;
        foreach (var groupId in registry.GetGroups().Concat(history.GetGroups()).Distinct().ToList())
        {
            var alive = registry.GetSessions(groupId).Any(s =>
                sessions.Exists(s.SessionId) && groups.GetParticipants(s.SessionId, groupId) is not null);
            if (alive)
            {
                continue;
            }

            registry.RemoveGroup(groupId);
            history.Remove(groupId);
            removed++;
        }

        return removed;
    }

    /// <summary>
    /// I partecipanti del gruppo se chi chiama ne fa parte (confronto dei
    /// nomi senza maiuscole, spec E §6.4); altrimenti null.
    /// </summary>
    private IReadOnlyList<string>? ParticipantsFor(CallerSession caller, Guid groupId)
    {
        var participants = groups.GetParticipants(caller.SessionId, groupId);
        return participants is not null && participants.Contains(caller.UserName, StringComparer.OrdinalIgnoreCase)
            ? participants
            : null;
    }

    /// <summary>
    /// Inoltra alle sessioni registrate del gruppo, tranne chi ha mandato
    /// l'evento; toglie dal registro le sessioni finite e quelle il cui
    /// utente non è più tra i partecipanti.
    /// </summary>
    private async Task ForwardAsync(
        Guid groupId,
        string senderSessionId,
        IReadOnlyList<string> participants,
        StampedEvent stamped,
        CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.Serialize(stamped);
        var targets = new List<string>();
        foreach (var (sessionId, userName) in registry.GetSessions(groupId))
        {
            if (sessionId == senderSessionId)
            {
                continue;
            }

            if (!sessions.Exists(sessionId) || !participants.Contains(userName, StringComparer.OrdinalIgnoreCase))
            {
                registry.Unregister(groupId, sessionId);
                continue;
            }

            targets.Add(sessionId);
        }

        await Task.WhenAll(targets.Select(sessionId => SendAsync(groupId, sessionId, payload, cancellationToken)))
            .ConfigureAwait(false);
    }

    private async Task SendAsync(Guid groupId, string sessionId, string payload, CancellationToken cancellationToken)
    {
        try
        {
            if (!await sender.TrySendAsync(sessionId, payload, cancellationToken).ConfigureAwait(false))
            {
                registry.Unregister(groupId, sessionId);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Evento del watch party non inoltrato alla sessione {SessionId}", sessionId);
        }
    }
}
```

- [ ] **Step 5: esegui i test**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat: forward watch party events to the other group members"
```

### Task 6: adattatori Jellyfin, controller finale e servizio di pulizia

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinSessionDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinGroupDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinEventSender.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/WatchPartyHostedService.cs`
- Modify (riscrivi): `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/WatchPartyController.cs` (senza `Probe`)
- Modify (riscrivi): `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Delete: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoTests.cs`
- Create: `…Tests/InterfaceStub.cs`, `…Tests/FakeAuthorizationContext.cs`, `…Tests/ServerAdapterTests.cs`, `…Tests/WatchPartyControllerTests.cs`, `…Tests/WatchPartyHostedServiceTests.cs`

- [ ] **Step 1: scrivi i test che falliscono**

`…Tests/InterfaceStub.cs` (stub di un'interfaccia senza librerie di mock):

```csharp
using System.Reflection;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>
/// Stub di un'interfaccia costruito con DispatchProxy. Registra le chiamate;
/// i membri senza gestore restituiscono il valore di default (o
/// Task.CompletedTask).
/// </summary>
public class InterfaceStub<T> : DispatchProxy
    where T : class
{
    /// <summary>Gestori per nome del metodo (es. "get_Sessions", "add_SessionEnded").</summary>
    public Dictionary<string, Func<object?[], object?>> Handlers { get; } = new(StringComparer.Ordinal);

    public List<(string Name, object?[] Args)> Calls { get; } = [];

    public static (T Proxy, InterfaceStub<T> Stub) Create()
    {
        var proxy = DispatchProxy.Create<T, InterfaceStub<T>>();
        return (proxy, (InterfaceStub<T>)(object)proxy);
    }

    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        ArgumentNullException.ThrowIfNull(targetMethod);
        args ??= [];
        Calls.Add((targetMethod.Name, args));
        if (Handlers.TryGetValue(targetMethod.Name, out var handler))
        {
            return handler(args);
        }

        var returnType = targetMethod.ReturnType;
        if (returnType == typeof(void))
        {
            return null;
        }

        if (returnType == typeof(Task))
        {
            return Task.CompletedTask;
        }

        return returnType.IsValueType ? Activator.CreateInstance(returnType) : null;
    }
}
```

`…Tests/FakeAuthorizationContext.cs`:

```csharp
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Autenticazione fissa per i test del controller.</summary>
internal sealed class FakeAuthorizationContext(AuthorizationInfo info) : IAuthorizationContext
{
    public Task<AuthorizationInfo> GetAuthorizationInfo(HttpContext requestContext) => Task.FromResult(info);

    public Task<AuthorizationInfo> GetAuthorizationInfo(HttpRequest requestContext) => Task.FromResult(info);
}
```

`…Tests/ServerAdapterTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;
using MediaBrowser.Model.Session;
using MediaBrowser.Model.SyncPlay;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ServerAdapterTests
{
    private static SessionInfo Session(string id, string deviceId, string client, Guid userId, string userName) =>
        new(null!, NullLogger.Instance)
        {
            Id = id,
            DeviceId = deviceId,
            Client = client,
            UserId = userId,
            UserName = userName,
        };

    [Fact]
    public void FindsTheCallerByDeviceClientAndUser()
    {
        var userId = Guid.NewGuid();
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var web = Session("s-web", "d1", "Jellyfin Web", userId, "Mario");
        var app = Session("s-app", "d1", "WonderFlix", userId, "Mario");
        stub.Handlers["get_Sessions"] = _ => new[] { web, app };
        var directory = new JellyfinSessionDirectory(manager);

        Assert.Equal(new CallerSession("s-app", userId, "Mario"), directory.FindCaller("d1", "WonderFlix", userId));
        Assert.Null(directory.FindCaller("d1", "WonderFlix", Guid.NewGuid()));
        Assert.Null(directory.FindCaller(null, "WonderFlix", userId));
        Assert.Null(directory.FindCaller("d1", "WonderFlix", Guid.Empty));
        Assert.True(directory.Exists("s-web"));
        Assert.False(directory.Exists("s-x"));
    }

    [Fact]
    public void ParticipantsComeFromSyncPlay()
    {
        var group = Guid.NewGuid();
        var (manager, sessions) = InterfaceStub<ISessionManager>.Create();
        var mario = Session("s1", "d1", "WonderFlix", Guid.NewGuid(), "Mario");
        sessions.Handlers["get_Sessions"] = _ => new[] { mario };
        var (syncPlay, groups) = InterfaceStub<ISyncPlayManager>.Create();
        groups.Handlers["GetGroup"] = args => ReferenceEquals(args[0], mario) && (Guid)args[1]! == group
            ? new GroupInfoDto(group, "Mario · Dune", GroupStateType.Paused, new[] { "Mario", "Luigi" }, DateTime.UtcNow)
            : null;
        var directory = new JellyfinGroupDirectory(manager, syncPlay);

        Assert.Equal(new[] { "Mario", "Luigi" }, directory.GetParticipants("s1", group));
        Assert.Null(directory.GetParticipants("s1", Guid.NewGuid()));
        Assert.Null(directory.GetParticipants("s-x", group));
    }

    [Fact]
    public async Task SenderUsesSendStringWithoutAControllingSession()
    {
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var sender = new JellyfinEventSender(manager);

        Assert.True(await sender.TrySendAsync("s1", "{\"Type\":\"Chat\"}", CancellationToken.None));
        var call = Assert.Single(stub.Calls, c => c.Name == "SendGeneralCommand");
        Assert.Null(call.Args[0]);
        Assert.Equal("s1", call.Args[1]);
        var command = Assert.IsType<GeneralCommand>(call.Args[2]);
        Assert.Equal(GeneralCommandType.SendString, command.Name);
        Assert.Equal("{\"Type\":\"Chat\"}", command.Arguments["WonderFlixWatchParty"]);

        stub.Handlers["SendGeneralCommand"] =
            _ => Task.FromException(new ResourceNotFoundException("Session s2 not found."));
        Assert.False(await sender.TrySendAsync("s2", "{}", CancellationToken.None));
    }
}
```

`…Tests/WatchPartyControllerTests.cs`:

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

public class WatchPartyControllerTests
{
    private static readonly Guid Group = Guid.NewGuid();

    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _user = new("mario", "provider", "reset");
    private readonly PartyHub _hub;

    public WatchPartyControllerTests()
    {
        _hub = new PartyHub(
            _server, _server, _server, new PartyRegistry(), new ChatHistory(), new RateLimiter(_time), _time,
            NullLogger<PartyHub>.Instance);
        _server.Sessions.Add(new CallerSession("s-mario", _user.Id, "Mario"));
        _server.Groups[Group] = ["Mario"];
    }

    private WatchPartyController Controller(string deviceId = "s-mario")
    {
        var auth = new AuthorizationInfo
        {
            DeviceId = deviceId,
            Client = "WonderFlix",
            User = _user,
            IsAuthenticated = true,
        };
        return new WatchPartyController(new FakeAuthorizationContext(auth), _server, _hub)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static EventRequest Chat(string text) => new() { Type = EventTypes.Chat, Text = text };

    [Fact]
    public void InfoReportsVersionAndProtocol()
    {
        var info = Controller().GetInfo().Value!;
        Assert.Equal("1.0.0", info.Version);
        Assert.Equal(1, info.Protocol);
    }

    [Fact]
    public async Task UnknownCallerIs409()
    {
        var controller = Controller("altro-dispositivo");
        Assert.IsType<ConflictResult>((await controller.Join(Group)).Result);
        Assert.IsType<ConflictResult>((await controller.PostEvent(Group, Chat("x"), CancellationToken.None)).Result);
        Assert.IsType<NoContentResult>(await controller.Leave(Group));
    }

    [Fact]
    public async Task JoinOkAndForbidden()
    {
        var joined = await Controller().Join(Group);
        Assert.Empty(joined.Value!.Messages);
        var forbidden = await Controller().Join(Guid.NewGuid());
        Assert.Equal(StatusCodes.Status403Forbidden, Assert.IsType<StatusCodeResult>(forbidden.Result).StatusCode);
    }

    [Fact]
    public async Task EventsOkInvalidAndRateLimited()
    {
        var controller = Controller();
        var ok = await controller.PostEvent(Group, Chat("ciao"), CancellationToken.None);
        Assert.Equal("Mario", ok.Value!.UserName);
        var invalid = await controller.PostEvent(Group, new EventRequest { Type = "Poll" }, CancellationToken.None);
        Assert.IsType<BadRequestResult>(invalid.Result);
        for (var i = 0; i < 4; i++)
        {
            await controller.PostEvent(Group, Chat("x"), CancellationToken.None);
        }

        var limited = await controller.PostEvent(Group, Chat("x"), CancellationToken.None);
        Assert.Equal(StatusCodes.Status429TooManyRequests, Assert.IsType<StatusCodeResult>(limited.Result).StatusCode);
    }

    [Fact]
    public async Task LeaveStopsForwarding()
    {
        var luigi = _server.AddSession("s-luigi", "Luigi");
        _server.Groups[Group].Add("Luigi");
        _hub.Join(luigi, Group);
        await Controller().Join(Group);
        Assert.IsType<NoContentResult>(await Controller().Leave(Group));
        await _hub.PostAsync(luigi, Group, Chat("ciao"), CancellationToken.None);
        Assert.Empty(_server.Sent);
    }
}
```

`…Tests/WatchPartyHostedServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class WatchPartyHostedServiceTests
{
    [Fact]
    public async Task EndedSessionsLeaveAndEndedGroupsAreCleaned()
    {
        var server = new FakeServer();
        var time = new FakeTimeProvider();
        var hub = new PartyHub(
            server, server, server, new PartyRegistry(), new ChatHistory(), new RateLimiter(time), time,
            NullLogger<PartyHub>.Instance);
        var group = Guid.NewGuid();
        var mario = server.AddSession("s-mario", "Mario");
        var luigi = server.AddSession("s-luigi", "Luigi");
        server.Groups[group] = ["Mario", "Luigi"];
        hub.Join(mario, group);
        hub.Join(luigi, group);

        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        EventHandler<SessionEventArgs>? ended = null;
        stub.Handlers["add_SessionEnded"] = args =>
        {
            ended = (EventHandler<SessionEventArgs>?)args[0];
            return null;
        };
        using var service = new WatchPartyHostedService(manager, hub, time, NullLogger<WatchPartyHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);
        Assert.NotNull(ended);

        ended(manager, new SessionEventArgs { SessionInfo = new SessionInfo(manager, NullLogger.Instance) { Id = "s-luigi" } });
        await hub.PostAsync(mario, group, new EventRequest { Type = EventTypes.Chat, Text = "ciao" }, CancellationToken.None);
        Assert.Empty(server.Sent);

        // Il gruppo finisce: alla pulizia successiva registro e storico spariscono.
        server.Groups.Remove(group);
        time.Advance(WatchPartyHostedService.CleanupInterval);
        server.Groups[group] = ["Mario", "Luigi"];
        Assert.Empty(hub.Join(luigi, group).Value!);

        await service.StopAsync(CancellationToken.None);
        Assert.Contains(stub.Calls, c => c.Name == "remove_SessionEnded");
    }
}
```

Elimina `InfoTests.cs` (il test passa in `WatchPartyControllerTests`).

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: FAIL in compilazione (adattatori, servizio e nuovo costruttore del controller non esistono).

- [ ] **Step 3: implementa gli adattatori**

`Server/JellyfinSessionDirectory.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le sessioni di Jellyfin.</summary>
public sealed class JellyfinSessionDirectory(ISessionManager sessionManager) : ISessionDirectory
{
    public CallerSession? FindCaller(string? deviceId, string? client, Guid userId)
    {
        if (string.IsNullOrEmpty(deviceId) || userId == Guid.Empty)
        {
            return null;
        }

        // Jellyfin distingue le sessioni per client e dispositivo.
        var session = sessionManager.Sessions.FirstOrDefault(s =>
            string.Equals(s.DeviceId, deviceId, StringComparison.Ordinal)
            && string.Equals(s.Client, client, StringComparison.Ordinal)
            && s.UserId.Equals(userId));
        return session is null ? null : new CallerSession(session.Id, session.UserId, session.UserName);
    }

    public bool Exists(string sessionId) =>
        sessionManager.Sessions.Any(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));
}
```

`Server/JellyfinGroupDirectory.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using MediaBrowser.Controller.SyncPlay;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>I gruppi SyncPlay di Jellyfin.</summary>
public sealed class JellyfinGroupDirectory(
    ISessionManager sessionManager,
    ISyncPlayManager syncPlayManager) : IGroupDirectory
{
    public IReadOnlyList<string>? GetParticipants(string sessionId, Guid groupId)
    {
        var session = sessionManager.Sessions.FirstOrDefault(s =>
            string.Equals(s.Id, sessionId, StringComparison.Ordinal));
        // GetGroup restituisce null se il gruppo non esiste o l'utente non
        // può vederne la coda.
        return session is null ? null : syncPlayManager.GetGroup(session, groupId)?.Participants;
    }
}
```

`Server/JellyfinEventSender.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Inoltro come GeneralCommand SendString sul WebSocket della sessione
/// (spec E §6.7).
/// </summary>
public sealed class JellyfinEventSender(ISessionManager sessionManager) : IEventSender
{
    public async Task<bool> TrySendAsync(string sessionId, string payload, CancellationToken cancellationToken)
    {
        var command = new GeneralCommand
        {
            Name = GeneralCommandType.SendString,
            Arguments = { [WatchPartyProtocol.ArgumentKey] = payload },
        };
        try
        {
            // Senza una sessione che comanda il server non controlla i
            // permessi di controllo remoto; senza WebSocket aperto non manda
            // nulla.
            await sessionManager.SendGeneralCommand(null, sessionId, command, cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch (ResourceNotFoundException)
        {
            return false;
        }
    }
}
```

- [ ] **Step 4: servizio di pulizia**

`WatchPartyHostedService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Session;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Toglie dai gruppi le sessioni finite e, ogni <see cref="CleanupInterval"/>,
/// registro e storico dei gruppi finiti (spec E §6.5).
/// </summary>
public sealed class WatchPartyHostedService(
    ISessionManager sessionManager,
    PartyHub hub,
    TimeProvider time,
    ILogger<WatchPartyHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Ogni quanto si puliscono i gruppi finiti.</summary>
    public static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(5);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionEnded += OnSessionEnded;
        _timer = time.CreateTimer(_ => Cleanup(), null, CleanupInterval, CleanupInterval);
        logger.LogInformation("WonderFlix Watch Party {Version} avviato", typeof(Plugin).Assembly.GetName().Version);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.SessionEnded -= OnSessionEnded;
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    // L'evento arriva su un altro thread e poi la SessionInfo viene chiusa:
    // si legge subito l'id.
    private void OnSessionEnded(object? sender, SessionEventArgs e) => hub.RemoveSession(e.SessionInfo.Id);

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

- [ ] **Step 5: controller finale e registrazione**

Riscrivi `Api/WatchPartyController.cs` (la sonda `Probe` sparisce):

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
/// Endpoint del plugin (spec E §6.2). Non risponde mai 404: per l'app un 404
/// vuol dire che la rotta non esiste, cioè plugin assente.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize(Policy = Policies.SyncPlayHasAccess)]
[Produces(MediaTypeNames.Application.Json)]
public class WatchPartyController(
    IAuthorizationContext authorizationContext,
    ISessionDirectory sessions,
    PartyHub hub) : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin e del protocollo.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(PluginVersion, WatchPartyProtocol.Version);

    /// <summary>Registra la sessione nel gruppo; restituisce lo storico della chat.</summary>
    [HttpPost("Groups/{groupId:guid}/Join")]
    public async Task<ActionResult<JoinResponse>> Join([FromRoute] Guid groupId)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = hub.Join(caller, groupId);
        if (result.Status != HubStatus.Ok)
        {
            return Failure(result.Status);
        }

        return new JoinResponse(result.Value!);
    }

    /// <summary>Toglie la sessione dal gruppo.</summary>
    [HttpPost("Groups/{groupId:guid}/Leave")]
    public async Task<ActionResult> Leave([FromRoute] Guid groupId)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is not null)
        {
            hub.Leave(caller, groupId);
        }

        return NoContent();
    }

    /// <summary>Un annuncio, un messaggio o una reazione: lo timbra e lo inoltra.</summary>
    [HttpPost("Groups/{groupId:guid}/Events")]
    public async Task<ActionResult<StampedEvent>> PostEvent(
        [FromRoute] Guid groupId,
        [FromBody] EventRequest? request,
        CancellationToken cancellationToken)
    {
        var caller = await FindCallerAsync().ConfigureAwait(false);
        if (caller is null)
        {
            return Conflict();
        }

        var result = await hub.PostAsync(caller, groupId, request, cancellationToken).ConfigureAwait(false);
        if (result.Status != HubStatus.Ok)
        {
            return Failure(result.Status);
        }

        return result.Value!;
    }

    private ActionResult Failure(HubStatus status) => status switch
    {
        HubStatus.Forbidden => StatusCode(StatusCodes.Status403Forbidden),
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

Riscrivi `PluginServiceRegistrator.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>Registra i servizi del plugin nel server.</summary>
public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        // Jellyfin non registra un TimeProvider.
        serviceCollection.TryAddSingleton(TimeProvider.System);
        serviceCollection.AddSingleton<ISessionDirectory, JellyfinSessionDirectory>();
        serviceCollection.AddSingleton<IGroupDirectory, JellyfinGroupDirectory>();
        serviceCollection.AddSingleton<IEventSender, JellyfinEventSender>();
        serviceCollection.AddSingleton<PartyRegistry>();
        serviceCollection.AddSingleton<ChatHistory>();
        serviceCollection.AddSingleton<RateLimiter>();
        serviceCollection.AddSingleton<PartyHub>();
        serviceCollection.AddHostedService<WatchPartyHostedService>();
    }
}
```

- [ ] **Step 6: esegui i test**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, nessun warning nel plugin. Poi `bash jellyfin-plugin-watch-party/pack.sh 1.0.0` funziona ancora.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat: serve the watch party plugin endpoints and drop the probe"
```

### Task 7: manifest, README e workflow

**Files:**
- Create: `jellyfin-plugin-watch-party/manifest.json`
- Create: `jellyfin-plugin-watch-party/README.md`
- Create: `.github/workflows/watch-party-plugin.yml`

- [ ] **Step 1: manifest del repository (ancora senza versioni)**

`jellyfin-plugin-watch-party/manifest.json`:

```json
[
  {
    "guid": "882eb47e-668a-4935-ba55-c2858eb4ed90",
    "name": "WonderFlix Watch Party",
    "description": "Names, chat and reactions for SyncPlay watch parties in WonderFlix.",
    "overview": "WonderFlix watch party: names, chat, reactions",
    "owner": "davidesidoti",
    "category": "General",
    "versions": []
  }
]
```

- [ ] **Step 2: README**

`jellyfin-plugin-watch-party/README.md`:

````markdown
# WonderFlix Watch Party (plugin di Jellyfin)

Plugin del server Jellyfin per il watch party di WonderFlix (spec E,
`docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`):
dice chi ha agito, porta la chat e le reazioni tra i membri di un gruppo
SyncPlay. Senza il plugin WonderFlix funziona lo stesso, con gli avvisi
anonimi.

- Jellyfin **10.11.x** (net9.0, `targetAbi` 10.11.0.0). Per Jellyfin 12 serve
  una build nuova (net10.0).
- Nessuna configurazione. Endpoint sotto `/WonderFlixWatchParty`; gli eventi
  arrivano ai client come `GeneralCommand` `SendString` con la chiave
  `WonderFlixWatchParty`.

## Installazione dal repository

1. Dashboard → Plugin → Repository → **+**: nome a piacere, URL
   `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`.
2. Catalogo → **WonderFlix Watch Party** → Installa.
3. Riavvia Jellyfin.

## Installazione a mano (prove)

1. Dalla root del repository: `bash jellyfin-plugin-watch-party/pack.sh 1.0.0`.
   Crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.0.0.0/`
   con la dll e `meta.json`.
2. Copia la cartella dentro `plugins/` della cartella dati di Jellyfin (su
   Ultra.cc via SFTP).
3. Riavvia Jellyfin. In Dashboard → Plugin compare "WonderFlix Watch Party",
   attivo.

Prima di installare dal Catalogo togli la cartella copiata a mano.

## Sviluppo

- Test: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`.
- Release: tag `watch-party-plugin-vX.Y.Z` → il workflow
  `watch-party-plugin.yml` pubblica una **pre-release** con lo zip e il suo
  MD5. Mai "latest": l'app legge `releases/latest` per i propri
  aggiornamenti. Poi si aggiunge la versione a `manifest.json`.
````

- [ ] **Step 3: workflow**

`.github/workflows/watch-party-plugin.yml`:

```yaml
name: Watch party plugin

# Test del plugin di Jellyfin a ogni modifica della sua cartella; con un tag
# watch-party-plugin-vX.Y.Z pubblica una pre-release con lo zip (spec E §6.8).
# I filtri sui percorsi non valgono per i tag.
on:
  push:
    branches: [main]
    tags: ['watch-party-plugin-v*.*.*']
    paths:
      - 'jellyfin-plugin-watch-party/**'
      - '.github/workflows/watch-party-plugin.yml'
  pull_request:
    paths:
      - 'jellyfin-plugin-watch-party/**'
      - '.github/workflows/watch-party-plugin.yml'

permissions:
  contents: write

jobs:
  plugin:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: jellyfin-plugin-watch-party
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'

      - name: Test
        run: dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release

      - name: Pacchetto
        if: startsWith(github.ref, 'refs/tags/watch-party-plugin-v')
        run: |
          version="${GITHUB_REF_NAME#watch-party-plugin-v}"
          bash ./pack.sh "$version"
          zip_name="wonderflix-watch-party_${version}.zip"
          (cd "artifacts/WonderFlix Watch Party_${version}.0" && zip -j "../${zip_name}" Jellyfin.Plugin.WonderFlixWatchParty.dll meta.json)
          md5sum "artifacts/${zip_name}" | cut -d ' ' -f 1 > "artifacts/${zip_name}.md5"
          echo "VERSION=${version}" >> "$GITHUB_ENV"

      # Pre-release e mai "latest": l'app legge releases/latest per i propri
      # aggiornamenti.
      - name: Pre-release
        if: startsWith(github.ref, 'refs/tags/watch-party-plugin-v')
        env:
          GH_TOKEN: ${{ github.token }}
        run: >
          gh release create "$GITHUB_REF_NAME"
          "artifacts/wonderflix-watch-party_${VERSION}.zip"
          "artifacts/wonderflix-watch-party_${VERSION}.zip.md5"
          --prerelease --latest=false
          --title "WonderFlix Watch Party ${VERSION}"
          --notes "Plugin di Jellyfin per il watch party di WonderFlix. Aggiungere la versione a jellyfin-plugin-watch-party/manifest.json."
```

- [ ] **Step 4: verifica e commit**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → PASS. Controlla che il JSON di `manifest.json` sia valido (es. `python -c "import json,sys; json.load(open('jellyfin-plugin-watch-party/manifest.json'))"`, oppure `node -e`).

```bash
git add jellyfin-plugin-watch-party .github/workflows/watch-party-plugin.yml
git commit -m "build: add the watch party plugin manifest and workflow"
```
---

## Gruppo C — nucleo del canale nell'app

### Task 8: modelli del protocollo (`party_channel_models.dart`)

**Files:**
- Create: `lib/core/party_channel/party_channel_models.dart`
- Create: `test/core/party_channel/party_channel_models_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/core/party_channel/party_channel_models_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';

/// Evento timbrato come lo manda il plugin, con [fields] sopra i campi
/// comuni.
Map<String, dynamic> stamped(Map<String, dynamic> fields) => {
      'Protocol': 1,
      'Id': 'e1',
      'GroupId': 'g1',
      'UserId': 'u2',
      'UserName': 'Luigi',
      'SentAt': '2026-10-02T21:14:03.512Z',
      ...fields,
    };

void main() {
  test('azione con posizione, da stringa JSON', () {
    final event = parsePartyEvent(jsonEncode(stamped(
        {'Type': 'Action', 'Action': 'Seek', 'PositionTicks': 37350000000})));
    expect(event, isA<PartyActionEvent>());
    event as PartyActionEvent;
    expect(event.action, PartyAction.seek);
    expect(event.position, const Duration(hours: 1, minutes: 2, seconds: 15));
    expect(event.id, 'e1');
    expect(event.groupId, 'g1');
    expect(event.userId, 'u2');
    expect(event.userName, 'Luigi');
    expect(event.sentAt, DateTime.utc(2026, 10, 2, 21, 14, 3, 512));
  });

  test('azione senza posizione, messaggio e reazione, da mappa', () {
    final pause =
        parsePartyEvent(stamped({'Type': 'Action', 'Action': 'Pause'}));
    expect((pause as PartyActionEvent).action, PartyAction.pause);
    expect(pause.position, isNull);

    final chat = parsePartyEvent(stamped({'Type': 'Chat', 'Text': 'che scena'}));
    expect((chat as PartyChatEvent).text, 'che scena');

    final reaction =
        parsePartyEvent(stamped({'Type': 'Reaction', 'Reaction': 'clap'}));
    expect((reaction as PartyReactionEvent).reaction, PartyReaction.clap);
  });

  test('scartati: protocollo, tipo, azione o reazione sconosciuti, campi '
      'mancanti, JSON non valido', () {
    expect(parsePartyEvent(stamped({'Protocol': 2, 'Type': 'Chat', 'Text': 'x'})),
        isNull);
    expect(parsePartyEvent(stamped({'Type': 'Poll'})), isNull);
    expect(parsePartyEvent(stamped({'Type': 'Action', 'Action': 'Shuffle'})),
        isNull);
    expect(parsePartyEvent(stamped({'Type': 'Reaction', 'Reaction': 'heart'})),
        isNull);
    expect(parsePartyEvent(stamped({'Type': 'Chat'})), isNull);
    expect(parsePartyEvent({'Protocol': 1, 'Type': 'Chat', 'Text': 'x'}),
        isNull);
    expect(parsePartyEvent('non json'), isNull);
    expect(parsePartyEvent(42), isNull);
  });

  test('eventi da mandare', () {
    expect(const PartyOutgoingAction(PartyAction.pause).toJson(),
        {'Type': 'Action', 'Action': 'Pause'});
    expect(
        const PartyOutgoingAction(PartyAction.seek,
                position: Duration(minutes: 1))
            .toJson(),
        {'Type': 'Action', 'Action': 'Seek', 'PositionTicks': 600000000});
    expect(const PartyOutgoingChat('ciao').toJson(),
        {'Type': 'Chat', 'Text': 'ciao'});
    expect(const PartyOutgoingReaction(PartyReaction.joy).toJson(),
        {'Type': 'Reaction', 'Reaction': 'joy'});
  });

  test('reazioni: id, emoji e tasti 1–6', () {
    expect(PartyReaction.values.map((r) => r.id),
        ['joy', 'scream', 'cry', 'wow', 'clap', 'facepalm']);
    expect(PartyReaction.values.map((r) => r.emoji).join(), '😂😱😢😮👏🤦');
    expect(PartyReaction.values.map((r) => r.key), [1, 2, 3, 4, 5, 6]);
    expect(PartyReaction.fromId('wow'), PartyReaction.wow);
    expect(PartyReaction.fromId('heart'), isNull);
  });

  test('testo dei messaggi: a capo, spazi, lunghezza in punti di codice', () {
    expect(normalizeChatText('  ciao\r\na tutti\n '), 'ciao a tutti');
    expect(chatTextLength('😂 ok'), 4);
    expect(maxChatLength, 200);
  });

  test('Info del plugin', () {
    final info = PartyPluginInfo.fromJson({'Version': '1.0.0', 'Protocol': 1});
    expect(info.version, '1.0.0');
    expect(info.protocol, 1);
  });
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/core/party_channel/party_channel_models_test.dart`
Expected: FAIL in compilazione (`party_channel_models.dart` non esiste).

- [ ] **Step 3: implementa**

Crea `lib/core/party_channel/party_channel_models.dart`:

```dart
import 'dart:convert';

import 'package:logging/logging.dart';

import '../jellyfin/item_models.dart';

final _log = Logger('watchparty');

/// Versione del protocollo tra l'app e il plugin "WonderFlix Watch Party"
/// (spec E §6.3). Un plugin con un protocollo diverso vale come assente.
const partyChannelProtocol = 1;

/// Chiave degli `Arguments` del `GeneralCommand` `SendString` con cui il
/// plugin inoltra gli eventi (spec E §6.3). Non è `String`, che jellyfin-web
/// scriverebbe nel campo con il focus.
const partyChannelArgumentKey = 'WonderFlixWatchParty';

/// Lunghezza massima di un messaggio in punti di codice Unicode (spec E
/// §6.3); il plugin usa lo stesso limite.
const maxChatLength = 200;

/// Il testo di un messaggio come lo vuole il plugin: a capo diventati spazi,
/// spazi esterni tolti.
String normalizeChatText(String text) =>
    text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

/// Lunghezza di un messaggio in punti di codice (un'emoji semplice vale 1).
int chatTextLength(String text) => text.runes.length;

/// Risposta di `GET /WonderFlixWatchParty/Info`.
class PartyPluginInfo {
  const PartyPluginInfo({required this.version, required this.protocol});

  factory PartyPluginInfo.fromJson(Map<String, dynamic> json) =>
      PartyPluginInfo(
        version: json['Version'] as String,
        protocol: (json['Protocol'] as num).toInt(),
      );

  final String version;
  final int protocol;
}

/// Azioni annunciate al gruppo: hanno i nomi delle richieste SyncPlay.
enum PartyAction {
  pause('Pause'),
  unpause('Unpause'),
  seek('Seek'),
  nextItem('NextItem'),
  newQueue('NewQueue');

  const PartyAction(this.wire);

  /// Nome nel protocollo.
  final String wire;

  static PartyAction? fromWire(Object? value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

/// Reazioni rapide (spec E §10.1). In rete viaggia [id], mai l'emoji.
enum PartyReaction {
  joy('joy', '😂'),
  scream('scream', '😱'),
  cry('cry', '😢'),
  wow('wow', '😮'),
  clap('clap', '👏'),
  facepalm('facepalm', '🤦');

  const PartyReaction(this.id, this.emoji);

  final String id;
  final String emoji;

  /// Tasto della reazione, da 1 a 6.
  int get key => index + 1;

  /// `null` per le reazioni che questa versione dell'app non conosce.
  static PartyReaction? fromId(Object? id) {
    for (final reaction in values) {
      if (reaction.id == id) return reaction;
    }
    return null;
  }
}

/// Un evento timbrato dal plugin (spec E §6.3): chi l'ha mandato lo dice il
/// server, non il client.
sealed class PartyEvent {
  const PartyEvent({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.sentAt,
  });

  final String id;
  final String groupId;
  final String userId;
  final String userName;

  /// Ora UTC del server.
  final DateTime sentAt;
}

/// Un membro annuncia un'azione sul gruppo (spec E §7.4).
final class PartyActionEvent extends PartyEvent {
  const PartyActionEvent({
    required super.id,
    required super.groupId,
    required super.userId,
    required super.userName,
    required super.sentAt,
    required this.action,
    this.position,
  });

  final PartyAction action;

  /// Solo per [PartyAction.seek].
  final Duration? position;
}

final class PartyChatEvent extends PartyEvent {
  const PartyChatEvent({
    required super.id,
    required super.groupId,
    required super.userId,
    required super.userName,
    required super.sentAt,
    required this.text,
  });

  final String text;
}

final class PartyReactionEvent extends PartyEvent {
  const PartyReactionEvent({
    required super.id,
    required super.groupId,
    required super.userId,
    required super.userName,
    required super.sentAt,
    required this.reaction,
  });

  final PartyReaction reaction;
}

/// Legge un evento timbrato, da stringa JSON (WebSocket) o già decodificato
/// (storico di `Join`, risposta di `Events`). `null`, con una riga nel log,
/// se è malformato, di un altro protocollo o di un tipo che non conosciamo.
PartyEvent? parsePartyEvent(Object? raw) {
  try {
    final json = raw is String ? jsonDecode(raw) : raw;
    if (json is! Map<String, dynamic>) {
      throw const FormatException('non è un oggetto');
    }
    final protocol = json['Protocol'];
    if (protocol != partyChannelProtocol) {
      _log.info('evento del canale con protocollo $protocol: scartato');
      return null;
    }
    final id = json['Id'] as String;
    final groupId = json['GroupId'] as String;
    final userId = json['UserId'] as String;
    final userName = json['UserName'] as String;
    final sentAt = DateTime.parse(json['SentAt'] as String).toUtc();
    switch (json['Type']) {
      case 'Action':
        final action = PartyAction.fromWire(json['Action']);
        if (action == null) break;
        final ticks = json['PositionTicks'];
        return PartyActionEvent(
          id: id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          sentAt: sentAt,
          action: action,
          position: ticks is num ? ticksToDuration(ticks.toInt()) : null,
        );
      case 'Chat':
        return PartyChatEvent(
          id: id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          sentAt: sentAt,
          text: json['Text'] as String,
        );
      case 'Reaction':
        final reaction = PartyReaction.fromId(json['Reaction']);
        if (reaction == null) break;
        return PartyReactionEvent(
          id: id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          sentAt: sentAt,
          reaction: reaction,
        );
    }
    _log.info('evento del canale non riconosciuto '
        '(${json['Type']}): scartato');
    return null;
  } on Object catch (error) {
    _log.info('evento del canale non valido: $error');
    return null;
  }
}

/// Evento da mandare al plugin (corpo di `Events`, spec E §6.3).
sealed class PartyOutgoing {
  const PartyOutgoing();

  Map<String, dynamic> toJson();
}

final class PartyOutgoingAction extends PartyOutgoing {
  const PartyOutgoingAction(this.action, {this.position});

  final PartyAction action;
  final Duration? position;

  @override
  Map<String, dynamic> toJson() {
    final position = this.position;
    return {
      'Type': 'Action',
      'Action': action.wire,
      if (position != null) 'PositionTicks': durationToTicks(position),
    };
  }
}

final class PartyOutgoingChat extends PartyOutgoing {
  const PartyOutgoingChat(this.text);

  final String text;

  @override
  Map<String, dynamic> toJson() => {'Type': 'Chat', 'Text': text};
}

final class PartyOutgoingReaction extends PartyOutgoing {
  const PartyOutgoingReaction(this.reaction);

  final PartyReaction reaction;

  @override
  Map<String, dynamic> toJson() => {'Type': 'Reaction', 'Reaction': reaction.id};
}
```

- [ ] **Step 4: esegui i test e verifica che passino**

Run: `flutter test test/core/party_channel/party_channel_models_test.dart`
Expected: PASS (7 test).

- [ ] **Step 5: commit**

```bash
git add lib/core/party_channel/party_channel_models.dart test/core/party_channel/party_channel_models_test.dart
git commit -m "feat: add the watch party channel protocol models"
```

### Task 9: il WebSocket riconosce gli eventi del plugin

**Files:**
- Modify: `lib/core/jellyfin/server_events.dart` (nuovo `ServerEvent` dopo `SyncPlayGroupUpdated`; nuovo caso in `parseServerMessage`)
- Test: `test/core/jellyfin/server_events_test.dart`

- [ ] **Step 1: scrivi il test che fallisce**

In `test/core/jellyfin/server_events_test.dart`, dopo il test `'parseServerMessage: messaggi SyncPlay'`, aggiungi:

```dart
  test('parseServerMessage: eventi del plugin del watch party', () {
    final event = parseServerMessage(jsonEncode({
      'MessageType': 'GeneralCommand',
      'Data': {
        'Name': 'SendString',
        'ControllingUserId': '00000000000000000000000000000000',
        'Arguments': {'WonderFlixWatchParty': '{"Type":"Chat"}'},
      },
    }));
    expect(event, isA<PartyChannelReceived>());
    expect((event as PartyChannelReceived).payload, '{"Type":"Chat"}');

    // Gli altri GeneralCommand restano ignorati.
    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'GeneralCommand',
          'Data': {
            'Name': 'DisplayMessage',
            'Arguments': {'Header': 'x', 'Text': 'y'},
          },
        })),
        isNull);
    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'GeneralCommand',
          'Data': {
            'Name': 'SendString',
            'Arguments': {'String': 'ciao'},
          },
        })),
        isNull);
    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'GeneralCommand',
          'Data': {
            'Name': 'SendString',
            'Arguments': {'WonderFlixWatchParty': 42},
          },
        })),
        isNull);
    expect(
        parseServerMessage(
            jsonEncode({'MessageType': 'GeneralCommand', 'Data': 'x'})),
        isNull);
  });
```

- [ ] **Step 2: esegui il test e verifica che fallisca**

Run: `flutter test test/core/jellyfin/server_events_test.dart`
Expected: FAIL in compilazione (`PartyChannelReceived` non esiste).

- [ ] **Step 3: implementa**

In `lib/core/jellyfin/server_events.dart` aggiungi l'import subito **prima** di `import '../syncplay/syncplay_models.dart';` (ordine alfabetico):

```dart
import '../party_channel/party_channel_models.dart';
```

Dopo la classe `SyncPlayGroupUpdated` aggiungi:

```dart
/// Evento del plugin "WonderFlix Watch Party" (spec E §7.1): il JSON
/// dell'evento timbrato, da leggere con `parsePartyEvent`.
final class PartyChannelReceived extends ServerEvent {
  const PartyChannelReceived(this.payload);

  final String payload;
}
```

In `parseServerMessage`, prima di `default:`, aggiungi:

```dart
      case 'GeneralCommand':
        // Il plugin del watch party inoltra i suoi eventi come `SendString`
        // con una chiave sua (spec E §6.3). Gli altri comandi non ci
        // riguardano.
        if (data is! Map<String, dynamic> || data['Name'] != 'SendString') {
          return null;
        }
        final arguments = data['Arguments'];
        final payload = arguments is Map<String, dynamic>
            ? arguments[partyChannelArgumentKey]
            : null;
        return payload is String ? PartyChannelReceived(payload) : null;
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/core/jellyfin/server_events_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin/server_events.dart test/core/jellyfin/server_events_test.dart
git commit -m "feat: read watch party plugin events from the websocket"
```

### Task 10: `PartyChannelApi`, provider e finti per i test

**Files:**
- Create: `lib/core/party_channel/party_channel_api.dart`
- Create: `test/core/party_channel/party_channel_api_test.dart`
- Modify: `lib/features/watch_party/watch_party_providers.dart` (nuovo `partyChannelApiProvider`)
- Modify: `test/support/watch_party_fakes.dart` (`FakePartyChannelApi`, `partyPayload`, `testChatEvent`, `testActionEvent`)

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/core/party_channel/party_channel_api_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PartyChannelApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = PartyChannelApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Map<String, dynamic> chat(String id, String text) => {
        'Protocol': 1,
        'Id': id,
        'GroupId': 'g1',
        'UserId': 'u2',
        'UserName': 'Luigi',
        'SentAt': '2026-10-02T21:00:00Z',
        'Type': 'Chat',
        'Text': text,
      };

  test('info', () async {
    adapter.handler =
        (_) => const FakeResponse(200, {'Version': '1.0.0', 'Protocol': 1});
    final info = await api.info();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Info');
    expect(info.version, '1.0.0');
    expect(info.protocol, 1);
  });

  test('join: storico della chat, scarta il resto', () async {
    adapter.handler = (_) => FakeResponse(200, {
          'Messages': [
            chat('e1', 'ciao'),
            {'Type': 'Chat'},
            chat('e2', 'pronti?'),
          ],
        });
    final history = await api.join('g1');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Groups/g1/Join');
    expect(history.map((event) => event.text), ['ciao', 'pronti?']);
  });

  test('leave', () async {
    await api.leave('g1');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Groups/g1/Leave');
  });

  test('send: corpo e risposta timbrata', () async {
    adapter.handler = (_) => FakeResponse(200, chat('e9', 'che scena'));
    final stamped = await api.send('g1', const PartyOutgoingChat('che scena'));
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Groups/g1/Events');
    expect(adapter.requests.single.data, {'Type': 'Chat', 'Text': 'che scena'});
    expect((stamped as PartyChatEvent).id, 'e9');
  });

  Future<PartyChannelFailure> failure(int status) async {
    adapter.handler = (_) => FakeResponse(status, {'error': 'x'});
    try {
      await api.send('g1', const PartyOutgoingChat('x'));
    } on PartyChannelException catch (error) {
      return error.failure;
    }
    fail('nessun errore con $status');
  }

  test('errori classificati (spec E §6.2)', () async {
    expect(await failure(404), PartyChannelFailure.unavailable);
    expect(await failure(400), PartyChannelFailure.rejected);
    expect(await failure(401), PartyChannelFailure.rejected);
    expect(await failure(403), PartyChannelFailure.rejected);
    expect(await failure(409), PartyChannelFailure.sessionUnknown);
    expect(await failure(429), PartyChannelFailure.rateLimited);
    expect(await failure(500), PartyChannelFailure.network);
  });

  test('rete assente e risposte di forma inattesa', () async {
    Matcher failsWith(PartyChannelFailure failure) =>
        throwsA(isA<PartyChannelException>()
            .having((error) => error.failure, 'failure', failure));

    adapter.handler = (_) => throw const SocketException('offline');
    await expectLater(api.info(), failsWith(PartyChannelFailure.network));

    adapter.handler = (_) => const FakeResponse(200, {'Version': '1.0.0'});
    await expectLater(api.info(), failsWith(PartyChannelFailure.network));

    adapter.handler = (_) => const FakeResponse(200, {'Type': 'Chat'});
    await expectLater(api.send('g1', const PartyOutgoingChat('x')),
        failsWith(PartyChannelFailure.network));
  });
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/core/party_channel/party_channel_api_test.dart`
Expected: FAIL in compilazione (`party_channel_api.dart` non esiste).

- [ ] **Step 3: implementa l'API**

Crea `lib/core/party_channel/party_channel_api.dart`:

```dart
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'party_channel_models.dart';

final _log = Logger('watchparty');

/// Perché una chiamata al plugin non è riuscita (spec E §6.2).
enum PartyChannelFailure {
  /// 404: la rotta non esiste, cioè il plugin non è installato (il plugin
  /// non risponde mai 404 di suo).
  unavailable,

  /// 429: troppi eventi in poco tempo.
  rateLimited,

  /// 400, 401, 403: evento non valido, o non siamo nel gruppo.
  rejected,

  /// 409: il plugin non trova la nostra sessione.
  sessionUnknown,

  /// Rete assente, errore del server o risposta di forma inattesa.
  network,
}

class PartyChannelException implements Exception {
  const PartyChannelException(this.failure);

  final PartyChannelFailure failure;

  @override
  String toString() => 'PartyChannelException(${failure.name})';
}

/// Endpoint del plugin "WonderFlix Watch Party" (spec E §6.2). Lancia solo
/// [PartyChannelException].
class PartyChannelApi {
  PartyChannelApi(this._http);

  static const _base = '/WonderFlixWatchParty';

  final JellyfinHttp _http;

  Future<PartyPluginInfo> info() => _call(() async =>
      PartyPluginInfo.fromJson(asJsonMap(await _http.get('$_base/Info'))));

  /// Registra la nostra sessione nel gruppo; restituisce lo storico della
  /// chat, dal messaggio più vecchio.
  Future<List<PartyChatEvent>> join(String groupId) => _call(() async {
        final json =
            asJsonMap(await _http.post('$_base/Groups/$groupId/Join'));
        return [
          for (final raw in json['Messages'] as List? ?? const [])
            if (parsePartyEvent(raw) case final PartyChatEvent event) event,
        ];
      });

  Future<void> leave(String groupId) =>
      _call(() => _http.post('$_base/Groups/$groupId/Leave'));

  /// Manda [event] al gruppo; restituisce l'evento timbrato dal plugin.
  Future<PartyEvent> send(String groupId, PartyOutgoing event) =>
      _call(() async {
        final stamped = parsePartyEvent(await _http
            .post('$_base/Groups/$groupId/Events', body: event.toJson()));
        if (stamped == null) throw const ServerErrorException(null);
        return stamped;
      });

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const PartyChannelException(PartyChannelFailure.unavailable);
    } on UnauthorizedException {
      throw const PartyChannelException(PartyChannelFailure.rejected);
    } on ForbiddenException {
      throw const PartyChannelException(PartyChannelFailure.rejected);
    } on ServerErrorException catch (error) {
      throw PartyChannelException(switch (error.statusCode) {
        400 => PartyChannelFailure.rejected,
        409 => PartyChannelFailure.sessionUnknown,
        429 => PartyChannelFailure.rateLimited,
        _ => PartyChannelFailure.network,
      });
    } on ApiException {
      throw const PartyChannelException(PartyChannelFailure.network);
    } on Object catch (error) {
      // Risposta di forma inattesa (es. `Info` senza `Protocol`).
      _log.info('risposta del plugin del watch party non valida: $error');
      throw const PartyChannelException(PartyChannelFailure.network);
    }
  }
}
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/core/party_channel/party_channel_api_test.dart`
Expected: PASS (6 test).

- [ ] **Step 5: provider**

In `lib/features/watch_party/watch_party_providers.dart` aggiungi l'import (in ordine, dopo `import '../../core/jellyfin/server_events.dart';`):

```dart
import '../../core/party_channel/party_channel_api.dart';
```

e, dopo `syncPlayApiProvider`:

```dart
final partyChannelApiProvider = Provider<PartyChannelApi>(
    (ref) => PartyChannelApi(ref.watch(jellyfinHttpProvider)));
```

- [ ] **Step 6: finti per i test**

In `test/support/watch_party_fakes.dart` aggiungi gli import (in ordine con quelli esistenti):

```dart
import 'dart:async';
import 'dart:convert';

import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';

import 'test_data.dart';
```

(`dart:` in cima al file, poi `package:`, poi l'import relativo dopo tutti gli altri.) Poi in fondo al file:

```dart
/// `PartyChannelApi` in memoria. Di default il plugin è assente: `info`
/// lancia `unavailable`, come un server senza plugin, e i test che non
/// parlano del canale restano come prima.
class FakePartyChannelApi implements PartyChannelApi {
  /// Risposta di [info]; `null` = plugin assente (404).
  PartyPluginInfo? pluginInfo;

  /// Storico restituito da [join].
  List<PartyChatEvent> history = const [];

  /// Errore di [join], se valorizzato.
  PartyChannelFailure? joinFailure;

  /// Errori delle prossime [send], uno per chiamata.
  final sendFailures = <PartyChannelFailure>[];

  /// Se valorizzato, [send] aspetta che si completi.
  Completer<void>? sendGate;

  /// Chiamate in ordine: `info`, `join g1`, `leave g1`, `send g1 Chat`.
  final calls = <String>[];

  /// Eventi passati a [send], anche quelli falliti.
  final sent = <PartyOutgoing>[];

  int _ids = 0;

  /// Plugin presente, con il nostro protocollo.
  void install({String version = '1.0.0'}) => pluginInfo =
      PartyPluginInfo(version: version, protocol: partyChannelProtocol);

  @override
  Future<PartyPluginInfo> info() async {
    calls.add('info');
    final info = pluginInfo;
    if (info == null) {
      throw const PartyChannelException(PartyChannelFailure.unavailable);
    }
    return info;
  }

  @override
  Future<List<PartyChatEvent>> join(String groupId) async {
    calls.add('join $groupId');
    final failure = joinFailure;
    if (failure != null) throw PartyChannelException(failure);
    return history;
  }

  @override
  Future<void> leave(String groupId) async => calls.add('leave $groupId');

  /// Timbra l'evento come il plugin, con [testUser] e id `srv-1`, `srv-2`, …
  @override
  Future<PartyEvent> send(String groupId, PartyOutgoing event) async {
    final json = event.toJson();
    calls.add('send $groupId ${json['Type']}');
    sent.add(event);
    await sendGate?.future;
    if (sendFailures.isNotEmpty) {
      throw PartyChannelException(sendFailures.removeAt(0));
    }
    return parsePartyEvent(jsonDecode(partyPayload(json,
        id: 'srv-${++_ids}',
        groupId: groupId,
        userId: testUser.id,
        userName: testUser.name,
        sentAt: clock.now().toUtc())))!;
  }
}

/// Evento timbrato di prova come lo inoltra il plugin (stringa JSON):
/// [fields] sopra i campi comuni.
String partyPayload(
  Map<String, dynamic> fields, {
  String id = 'e1',
  String groupId = 'g1',
  String userId = 'u2',
  String userName = 'Luigi',
  DateTime? sentAt,
}) =>
    jsonEncode({
      'Protocol': partyChannelProtocol,
      'Id': id,
      'GroupId': groupId,
      'UserId': userId,
      'UserName': userName,
      'SentAt': (sentAt ?? DateTime.utc(2026, 10, 2, 21)).toIso8601String(),
      ...fields,
    });

PartyChatEvent testChatEvent(
  String text, {
  String id = 'e1',
  String userId = 'u2',
  String userName = 'Luigi',
  DateTime? sentAt,
}) =>
    parsePartyEvent(partyPayload({'Type': 'Chat', 'Text': text},
        id: id, userId: userId, userName: userName, sentAt: sentAt))!
        as PartyChatEvent;

PartyActionEvent testActionEvent(
  PartyAction action, {
  String id = 'e1',
  String userName = 'Luigi',
  Duration? position,
}) =>
    parsePartyEvent(partyPayload({
      'Type': 'Action',
      'Action': action.wire,
      if (position != null) 'PositionTicks': durationToTicks(position),
    }, id: id, userName: userName))! as PartyActionEvent;
```

- [ ] **Step 7: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/core/party_channel/party_channel_api.dart lib/features/watch_party/watch_party_providers.dart test/core/party_channel/party_channel_api_test.dart test/support/watch_party_fakes.dart
git commit -m "feat: call the watch party plugin endpoints"
```

---

## Gruppo D — nomi negli avvisi e `PartyChannel`

### Task 11: gli avvisi aspettano il nome (`PartyNotices`)

**Files:**
- Modify: `lib/features/watch_party/party_notices.dart`
- Modify: `lib/features/watch_party/party_notice_pill.dart` (`partyNoticeText`)
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `test/support/watch_party_fakes.dart` (`FakePartyNotices`)
- Test: `test/features/watch_party/party_notices_test.dart`, `test/features/watch_party/party_notice_pill_test.dart`

- [ ] **Step 1: testi nuovi negli ARB**

In `l10n/app_it.arb`, subito dopo la riga `"@watchPartyNoticeNowWatching": {"placeholders": {"title": {"type": "String"}}},`, aggiungi:

```json
  "watchPartyNoticePausedBy": "{name} ha messo in pausa",
  "@watchPartyNoticePausedBy": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyNoticeResumedBy": "{name} ha ripreso",
  "@watchPartyNoticeResumedBy": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyNoticeForcedResumeBy": "{name} ha fatto ripartire senza aspettare",
  "@watchPartyNoticeForcedResumeBy": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyNoticeSeekBy": "{name} ha saltato a {time}",
  "@watchPartyNoticeSeekBy": {"placeholders": {"name": {"type": "String"}, "time": {"type": "String"}}},
  "watchPartyNoticeNextEpisodeBy": "{name} ha avviato: {title}",
  "@watchPartyNoticeNextEpisodeBy": {"placeholders": {"name": {"type": "String"}, "title": {"type": "String"}}},
  "watchPartyNoticeNowWatchingBy": "{name} ha scelto: {title}",
  "@watchPartyNoticeNowWatchingBy": {"placeholders": {"name": {"type": "String"}, "title": {"type": "String"}}},
```

In `l10n/app_en.arb` (che non ha i metadati `@`), subito dopo `"watchPartyNoticeNowWatching": "Now watching: {title}",`:

```json
  "watchPartyNoticePausedBy": "{name} paused",
  "watchPartyNoticeResumedBy": "{name} resumed",
  "watchPartyNoticeForcedResumeBy": "{name} resumed without waiting",
  "watchPartyNoticeSeekBy": "{name} jumped to {time}",
  "watchPartyNoticeNextEpisodeBy": "{name} started: {title}",
  "watchPartyNoticeNowWatchingBy": "{name} picked: {title}",
```

Run: `flutter gen-l10n` (nessun avviso).

- [ ] **Step 2: scrivi i test che falliscono**

In `test/features/watch_party/party_notice_pill_test.dart`, dopo il test `'testi di tutti gli avvisi'`, aggiungi:

```dart
  test('testi con il nome di chi agisce (spec E §8)', () {
    String text(PartyNotice notice) => partyNoticeText(l, notice);
    const time = Duration(minutes: 32, seconds: 10);
    expect(text(const PartyNotice(PartyNoticeKind.paused, name: 'Luigi')),
        'Luigi ha messo in pausa');
    expect(text(const PartyNotice(PartyNoticeKind.resumed, name: 'Luigi')),
        'Luigi ha ripreso');
    expect(
        text(const PartyNotice(PartyNoticeKind.forcedResume, name: 'Luigi')),
        'Luigi ha fatto ripartire senza aspettare');
    expect(
        text(const PartyNotice(PartyNoticeKind.seeked,
            name: 'Luigi', position: time)),
        'Luigi ha saltato a 32:10');
    expect(
        text(const PartyNotice(PartyNoticeKind.nextEpisode,
            name: 'Luigi', title: 'S1:E5 · Titolo')),
        'Luigi ha avviato: S1:E5 · Titolo');
    expect(
        text(const PartyNotice(PartyNoticeKind.nowWatching,
            name: 'Luigi', title: 'Dune')),
        'Luigi ha scelto: Dune');
    // Le proprie azioni restano in seconda persona.
    expect(
        text(const PartyNotice(PartyNoticeKind.paused,
            mine: true, name: 'Mario')),
        'Hai messo in pausa');
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
        partyNoticeText(
            en,
            const PartyNotice(PartyNoticeKind.seeked,
                name: 'Luigi', position: time)),
        'Luigi jumped to 32:10');
  });
```

In `test/features/watch_party/party_notices_test.dart` aggiungi l'import:

```dart
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
```

e, in fondo a `main()` (dopo tutti i test esistenti, perché usano le funzioni locali `mount`, `emit`, `seekCommand`, …):

```dart
  group('nome di chi agisce (spec E §8)', () {
    test('annuncio arrivato prima: l\'avviso ha subito il nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().attribute(testActionEvent(PartyAction.pause));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('annuncio arrivato dopo: l\'avviso lo aspetta', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current(), isNull, reason: 'aspetta il nome');
        async.elapse(const Duration(milliseconds: 120));
        notices().attribute(testActionEvent(PartyAction.pause));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, 'Luigi');
        finish(async);
      });
    });

    test('nessun annuncio entro 300 ms: avviso senza nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(
            PartyNotices.attributionWait - const Duration(milliseconds: 1));
        expect(current(), isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('canale spento: nessuna attesa', () {
      fakeAsync((async) {
        mount(async);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('annuncio più vecchio di 2 s: non vale', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().attribute(testActionEvent(PartyAction.pause));
        async.elapse(PartyNotices.announcementLifetime +
            const Duration(milliseconds: 1));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(PartyNotices.attributionWait);
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('l\'annuncio si consuma: un secondo avviso uguale resta senza nome',
        () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().attribute(testActionEvent(PartyAction.pause));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(PartyNotices.attributionWait);
        expect(current()?.name, 'Luigi');
        async.elapse(PartyNotices.showFor);
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('ripresa forzata e salto prendono il nome dall\'annuncio giusto', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async,
            const GroupStateUpdate('g1', GroupState.waiting, 'Buffer'));
        notices().attribute(
            testActionEvent(PartyAction.unpause, id: 'a1', userName: 'Peach'));
        emit(async,
            const GroupStateUpdate('g1', GroupState.playing, 'Unpause'));
        expect(current()?.kind, PartyNoticeKind.forcedResume);
        expect(current()?.name, 'Peach');

        async.elapse(PartyNotices.showFor);
        const position = Duration(minutes: 32, seconds: 10);
        seekCommand(async, position);
        notices().attribute(
            testActionEvent(PartyAction.seek, id: 'a2', position: position));
        emit(async, const GroupStateUpdate('g1', GroupState.waiting, 'Seek'));
        expect(current()?.kind, PartyNoticeKind.seeked);
        expect(current()?.name, 'Luigi');
        expect(current()?.position, position);
        finish(async);
      });
    });

    test('episodio successivo: nome e titolo', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, PlayQueueUpdate('g1', testSeriesQueue()));
        notices().attribute(testActionEvent(PartyAction.nextItem));
        emit(
            async,
            PlayQueueUpdate(
                'g1',
                testSeriesQueue(
                    playingIndex: 1,
                    reason: 'NextItem',
                    lastUpdate: DateTime.utc(2026, 9, 30, 10, 5))));
        expect(current()?.kind, PartyNoticeKind.nextEpisode);
        expect(current()?.name, 'Luigi');
        expect(current()?.title, isNotNull);
        finish(async);
      });
    });

    test('canale spento con avvisi in attesa: escono subito senza nome', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        expect(current(), isNull);
        notices().setAttribution(false);
        expect(current()?.kind, PartyNoticeKind.paused);
        expect(current()?.name, isNull);
        finish(async);
      });
    });

    test('le proprie azioni non aspettano, e l\'eco non produce avvisi', () {
      fakeAsync((async) {
        mount(async);
        notices().setAttribution(true);
        notices().mine(PartyNoticeKind.paused);
        expect(current()?.mine, isTrue);
        emit(async, const GroupStateUpdate('g1', GroupState.paused, 'Pause'));
        async.elapse(PartyNotices.attributionWait);
        async.elapse(PartyNotices.showFor);
        expect(current(), isNull);
        finish(async);
      });
    });
  });
```

- [ ] **Step 3: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart`
Expected: FAIL in compilazione (`setAttribution`, `attribute`, `attributionWait` non esistono; i nuovi metodi di `AppLocalizations` non usati ancora non danno errore).

- [ ] **Step 4: implementa in `party_notices.dart`**

Aggiungi l'import (in ordine, prima di `import '../../core/syncplay/syncplay_models.dart';`):

```dart
import '../../core/party_channel/party_channel_models.dart';
```

In `PartyNotice` sostituisci il commento di `name`:

```dart
  /// Per entrate e uscite.
  final String? name;
```

con:

```dart
  /// Chi ha agito: nelle entrate e nelle uscite, e nelle azioni altrui
  /// annunciate dal plugin del watch party (spec E §8).
  final String? name;
```

e aggiungi dopo il campo `title`:

```dart

  /// Lo stesso avviso con il nome di chi ha agito.
  PartyNotice withName(String name) => PartyNotice(kind,
      mine: mine, position: position, name: name, title: title);
```

Prima della classe `PartyNotices` aggiungi:

```dart
/// Avviso di un'azione altrui in attesa del nome (vedi
/// [PartyNotices.attributionWait]).
class _WaitingNotice {
  _WaitingNotice(this.notice, this.action);

  final PartyNotice notice;
  final PartyAction action;
  Timer? timer;
}
```

In `PartyNotices`, dopo `echoWindow`:

```dart

  /// Attesa massima del nome di chi ha agito, con il canale del plugin
  /// attivo (spec E §8): l'annuncio arriva di solito insieme all'avviso di
  /// SyncPlay, poche decine di millisecondi prima o dopo.
  static const attributionWait = Duration(milliseconds: 300);

  /// Per quanto un annuncio del canale resta abbinabile a un avviso.
  static const announcementLifetime = Duration(seconds: 2);
```

e dopo il campo `Duration? _lastSeek;`:

```dart

  /// Il canale del plugin è attivo: gli avvisi altrui aspettano il nome.
  bool _attribution = false;

  /// Annunci arrivati prima del loro avviso.
  final _announcements = <({PartyActionEvent event, DateTime at})>[];

  /// Avvisi che aspettano il loro annuncio, in ordine di arrivo.
  final _waiting = <_WaitingNotice>[];
```

In `build()`, dopo `_lastSeek = null;`:

```dart
    _attribution = false;
    _cancelWaiting();
```

e in `ref.onDispose` aggiungi `_cancelWaiting();` dopo `_timer?.cancel();`.

Dopo il metodo `mine` aggiungi:

```dart

  /// Il canale del plugin è attivo ([enabled]) o spento (spec E §8). Spento:
  /// gli avvisi in attesa escono subito senza nome.
  void setAttribution(bool enabled) {
    _attribution = enabled;
    if (enabled) return;
    final waiting = [..._waiting];
    _cancelWaiting();
    for (final entry in waiting) {
      show(entry.notice);
    }
  }

  /// Annuncio di un altro membro arrivato dal canale: dà il nome all'avviso
  /// che lo aspetta (il più vecchio), o resta da parte per
  /// [announcementLifetime].
  void attribute(PartyActionEvent event) {
    final index =
        _waiting.indexWhere((waiting) => waiting.action == event.action);
    if (index >= 0) {
      final waiting = _waiting.removeAt(index);
      waiting.timer?.cancel();
      show(waiting.notice.withName(event.userName));
      return;
    }
    _pruneAnnouncements();
    _announcements.add((event: event, at: clock.now()));
  }
```

In `_clear()`, dopo `_lastSeek = null;`:

```dart
    _cancelWaiting();
```

Dopo `_isEcho` aggiungi:

```dart

  void _cancelWaiting() {
    for (final waiting in _waiting) {
      waiting.timer?.cancel();
    }
    _waiting.clear();
    _announcements.clear();
  }

  void _pruneAnnouncements() {
    final now = clock.now();
    _announcements.removeWhere(
        (announcement) => now.difference(announcement.at) > announcementLifetime);
  }

  /// Nome dell'annuncio più recente di [action] ancora valido; l'annuncio si
  /// consuma.
  String? _takeAnnouncement(PartyAction action) {
    _pruneAnnouncements();
    final index = _announcements
        .lastIndexWhere((announcement) => announcement.event.action == action);
    if (index < 0) return null;
    return _announcements.removeAt(index).event.userName;
  }

  /// Avviso di un'azione altrui (spec E §8): con il nome se l'annuncio è già
  /// arrivato; altrimenti, con il canale attivo, lo aspetta al massimo
  /// [attributionWait].
  void _showOthers(PartyNotice notice) {
    final action = _actionOf(notice.kind);
    if (action == null) {
      show(notice);
      return;
    }
    final name = _takeAnnouncement(action);
    if (name != null) {
      show(notice.withName(name));
    } else if (!_attribution) {
      show(notice);
    } else {
      final waiting = _WaitingNotice(notice, action);
      waiting.timer = Timer(attributionWait, () {
        _waiting.remove(waiting);
        show(waiting.notice);
      });
      _waiting.add(waiting);
    }
  }

  static PartyAction? _actionOf(PartyNoticeKind kind) => switch (kind) {
        PartyNoticeKind.paused => PartyAction.pause,
        PartyNoticeKind.resumed ||
        PartyNoticeKind.forcedResume =>
          PartyAction.unpause,
        PartyNoticeKind.seeked => PartyAction.seek,
        PartyNoticeKind.nextEpisode => PartyAction.nextItem,
        PartyNoticeKind.nowWatching => PartyAction.newQueue,
        _ => null,
      };
```

In `_onUpdate`, nel caso `GroupStateUpdate`, sostituisci:

```dart
          show(PartyNotice(kind, position: position));
        } else {
          show(PartyNotice(kind));
        }
```

con:

```dart
          _showOthers(PartyNotice(kind, position: position));
        } else {
          _showOthers(PartyNotice(kind));
        }
```

In `_announce` sostituisci `show(PartyNotice(kind,` con `_showOthers(PartyNotice(kind,`.

- [ ] **Step 5: testi con il nome in `party_notice_pill.dart`**

Sostituisci il corpo di `partyNoticeText` fino a `PartyNoticeKind.nowWatching` compreso:

```dart
String partyNoticeText(AppLocalizations l, PartyNotice notice) {
  final time = formatClock(notice.position ?? Duration.zero);
  return switch (notice.kind) {
    PartyNoticeKind.paused =>
      notice.mine ? l.watchPartyNoticePausedByYou : l.watchPartyNoticePaused,
    PartyNoticeKind.resumed =>
      notice.mine ? l.watchPartyNoticeResumedByYou : l.watchPartyNoticeResumed,
    PartyNoticeKind.forcedResume => l.watchPartyNoticeForcedResume,
    PartyNoticeKind.seeked => notice.mine
        ? l.watchPartyNoticeSeekByYou(time)
        : l.watchPartyNoticeSeek(time),
    PartyNoticeKind.joined => l.watchPartyNoticeJoined(notice.name ?? ''),
    PartyNoticeKind.left => l.watchPartyNoticeLeft(notice.name ?? ''),
    PartyNoticeKind.nextEpisode =>
      l.watchPartyNoticeNextEpisode(notice.title ?? ''),
    PartyNoticeKind.nowWatching =>
      l.watchPartyNoticeNowWatching(notice.title ?? ''),
```

con:

```dart
String partyNoticeText(AppLocalizations l, PartyNotice notice) {
  final time = formatClock(notice.position ?? Duration.zero);
  final title = notice.title ?? '';
  // Chi ha agito, nelle azioni altrui annunciate dal canale (spec E §8).
  final by = notice.mine ? null : notice.name;
  return switch (notice.kind) {
    PartyNoticeKind.paused => notice.mine
        ? l.watchPartyNoticePausedByYou
        : by != null
            ? l.watchPartyNoticePausedBy(by)
            : l.watchPartyNoticePaused,
    PartyNoticeKind.resumed => notice.mine
        ? l.watchPartyNoticeResumedByYou
        : by != null
            ? l.watchPartyNoticeResumedBy(by)
            : l.watchPartyNoticeResumed,
    PartyNoticeKind.forcedResume => by != null
        ? l.watchPartyNoticeForcedResumeBy(by)
        : l.watchPartyNoticeForcedResume,
    PartyNoticeKind.seeked => notice.mine
        ? l.watchPartyNoticeSeekByYou(time)
        : by != null
            ? l.watchPartyNoticeSeekBy(by, time)
            : l.watchPartyNoticeSeek(time),
    PartyNoticeKind.joined => l.watchPartyNoticeJoined(notice.name ?? ''),
    PartyNoticeKind.left => l.watchPartyNoticeLeft(notice.name ?? ''),
    PartyNoticeKind.nextEpisode => by != null
        ? l.watchPartyNoticeNextEpisodeBy(by, title)
        : l.watchPartyNoticeNextEpisode(title),
    PartyNoticeKind.nowWatching => by != null
        ? l.watchPartyNoticeNowWatchingBy(by, title)
        : l.watchPartyNoticeNowWatching(title),
```

(il resto dello `switch` non cambia).

- [ ] **Step 6: `FakePartyNotices` registra il canale**

In `test/support/watch_party_fakes.dart`, dentro `FakePartyNotices`, dopo `hiddenMineCalls`:

```dart

  /// Chiamate di `setAttribution`, in ordine.
  final attributionCalls = <bool>[];

  /// Annunci passati ad `attribute`.
  final attributed = <PartyActionEvent>[];

  @override
  void setAttribution(bool enabled) => attributionCalls.add(enabled);

  @override
  void attribute(PartyActionEvent event) => attributed.add(event);
```

- [ ] **Step 7: esegui i test**

Run: `flutter test test/features/watch_party/`
Expected: PASS (anche i test esistenti degli avvisi: con il canale spento nulla cambia).

- [ ] **Step 8: commit**

```bash
git add l10n/app_it.arb l10n/app_en.arb lib/features/watch_party/party_notices.dart lib/features/watch_party/party_notice_pill.dart test/support/watch_party_fakes.dart test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart
git commit -m "feat: name who acted in watch party notices"
```

### Task 12: `PartyChannel`

**Files:**
- Create: `lib/features/watch_party/party_channel.dart`
- Create: `test/features/watch_party/party_channel_test.dart`
- Modify: `lib/features/watch_party/watch_party_routing.dart` (tiene vivo il canale)
- Modify: `test/features/watch_party/watch_party_routing_test.dart`, `test/features/watch_party/party_handover_test.dart` (override del canale)

- [ ] **Step 1: scrivi i test che falliscono**

Crea `test/features/watch_party/party_channel_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/party_channel/party_channel_api.dart';
import 'package:wonderflix/core/party_channel/party_channel_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late FakePartyChannelApi channelApi;
  late FakePartyNotices notices;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeSyncPlayApi();
    channelApi = FakePartyChannelApi();
    notices = FakePartyNotices();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// Dentro la zona finta: container e, con [listen], il canale vivo.
  void mount(FakeAsync async, {bool listen = true}) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      partyChannelApiProvider.overrideWithValue(channelApi),
      partyNoticesProvider.overrideWith(() => notices),
    ]);
    if (listen) container.listen(partyChannelProvider, (_, _) {});
    async.flushMicrotasks();
  }

  void joinGroup(FakeAsync async) {
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    async.flushMicrotasks();
  }

  void leaveGroup(FakeAsync async) {
    unawaited(container.read(watchPartySessionProvider.notifier).leave());
    async.flushMicrotasks();
  }

  void finish(FakeAsync async) {
    container.dispose();
    async.flushMicrotasks();
  }

  PartyChannelState channel() => container.read(partyChannelProvider);
  PartyChannel notifier() => container.read(partyChannelProvider.notifier);

  void receive(FakeAsync async, String payload) {
    events.add(PartyChannelReceived(payload));
    async.flushMicrotasks();
  }

  List<Map<String, dynamic>> sentJson() =>
      [for (final event in channelApi.sent) event.toJson()];

  test('plugin assente: canale spento, nessun Join né Leave', () {
    fakeAsync((async) {
      mount(async);
      joinGroup(async);
      expect(channelApi.calls, ['info']);
      expect(channel().availability, PartyPluginAvailability.unavailable);
      expect(channel().active, isFalse);
      expect(notices.attributionCalls, isNot(contains(true)));
      leaveGroup(async);
      expect(channelApi.calls, ['info']);
      finish(async);
    });
  });

  test('plugin presente: Info, Join con lo storico, avvisi con il nome', () {
    fakeAsync((async) {
      channelApi
        ..install()
        ..history = [testChatEvent('ciao', id: 'h1')];
      mount(async);
      joinGroup(async);
      expect(channelApi.calls, ['info', 'join g1']);
      expect(channel().availability, PartyPluginAvailability.available);
      expect(channel().pluginVersion, '1.0.0');
      expect(channel().active, isTrue);
      expect(channel().messages.single.event.text, 'ciao');
      expect(channel().messages.single.mine, isFalse);
      expect(channel().unread, 0, reason: 'lo storico non conta come nuovo');
      expect(notices.attributionCalls, [true]);
      finish(async);
    });
  });

  test('protocollo diverso: come assente, con la versione', () {
    fakeAsync((async) {
      channelApi.pluginInfo =
          const PartyPluginInfo(version: '2.0.0', protocol: 2);
      mount(async);
      joinGroup(async);
      expect(channelApi.calls, ['info']);
      expect(channel().availability, PartyPluginAvailability.unavailable);
      expect(channel().pluginVersion, '2.0.0');
      expect(channel().active, isFalse);
      finish(async);
    });
  });

  test('canale nato a gruppo già in corso: entra subito', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async, listen: false);
      joinGroup(async);
      expect(channelApi.calls, isEmpty);
      container.listen(partyChannelProvider, (_, _) {});
      async.flushMicrotasks();
      expect(channelApi.calls, ['info', 'join g1']);
      expect(channel().active, isTrue);
      finish(async);
    });
  });

  test('rientro dopo una riconnessione: di nuovo Join, storico senza doppioni',
      () {
    fakeAsync((async) {
      channelApi
        ..install()
        ..history = [testChatEvent('ciao', id: 'h1')];
      mount(async);
      joinGroup(async);
      channelApi.history = [
        testChatEvent('ciao', id: 'h1'),
        testChatEvent('pronti?',
            id: 'h2', sentAt: DateTime.utc(2026, 10, 2, 21, 1)),
      ];
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      expect(channelApi.calls, ['info', 'join g1', 'join g1']);
      expect(channel().messages.map((m) => m.event.text), ['ciao', 'pronti?']);
      finish(async);
    });
  });

  test('Join fallito per la rete: spento, si riprova al rientro', () {
    fakeAsync((async) {
      channelApi
        ..install()
        ..joinFailure = PartyChannelFailure.network;
      mount(async);
      joinGroup(async);
      expect(channel().active, isFalse);
      expect(channel().availability, PartyPluginAvailability.available);
      channelApi.joinFailure = null;
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      expect(channel().active, isTrue);
      finish(async);
    });
  });

  test('uscita dal gruppo: Leave e stato azzerato', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      receive(async, partyPayload({'Type': 'Chat', 'Text': 'ciao'}));
      leaveGroup(async);
      expect(channelApi.calls.last, 'leave g1');
      expect(channel().active, isFalse);
      expect(channel().messages, isEmpty);
      expect(channel().unread, 0);
      expect(channel().received, 0);
      expect(channel().availability, PartyPluginAvailability.available);
      expect(notices.attributionCalls.last, isFalse);
      finish(async);
    });
  });

  test('ricezione: annunci agli avvisi, chat, reazioni', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      final chats = <PartyChatEntry>[];
      final reactions = <PartyReactionEvent>[];
      notifier().chatArrivals.listen(chats.add);
      notifier().reactions.listen(reactions.add);

      receive(async,
          partyPayload({'Type': 'Action', 'Action': 'Pause'}, id: 'a1'));
      expect(notices.attributed.single.action, PartyAction.pause);

      receive(
          async, partyPayload({'Type': 'Chat', 'Text': 'che scena'}, id: 'c1'));
      expect(channel().messages.single.event.text, 'che scena');
      expect(channel().unread, 1, reason: 'nessuna chat a schermo');
      expect(chats.single.event.userName, 'Luigi');

      receive(async,
          partyPayload({'Type': 'Reaction', 'Reaction': 'joy'}, id: 'r1'));
      expect(reactions.single.reaction, PartyReaction.joy);
      expect(channel().received, 3);
      finish(async);
    });
  });

  test('ricezione: scarta altri gruppi, doppioni ed eventi non validi', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      receive(async,
          partyPayload({'Type': 'Chat', 'Text': 'altro'}, groupId: 'g2'));
      receive(async, partyPayload({'Type': 'Chat', 'Text': 'uno'}, id: 'c1'));
      receive(async, partyPayload({'Type': 'Chat', 'Text': 'uno'}, id: 'c1'));
      receive(async, '{"Type":"Chat"}');
      expect(channel().messages.map((m) => m.event.text), ['uno']);
      expect(channel().received, 1);
      finish(async);
    });
  });

  test('id del gruppo con o senza trattini', () {
    fakeAsync((async) {
      const plain = '9a1e2b3c4d5e6f708192a3b4c5d6e7f8';
      api.onCall = (call) {
        if (call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(
              GroupJoined(plain, testGroup(id: plain))));
        }
      };
      channelApi.install();
      mount(async);
      unawaited(container.read(watchPartySessionProvider.notifier).join(plain));
      async.flushMicrotasks();
      receive(
          async,
          partyPayload({'Type': 'Chat', 'Text': 'ok'},
              groupId: '9a1e2b3c-4d5e-6f70-8192-a3b4c5d6e7f8'));
      expect(channel().messages.single.event.text, 'ok');
      finish(async);
    });
  });

  test('i propri messaggi da un altro PC sono "mine"', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      receive(
          async,
          partyPayload({'Type': 'Chat', 'Text': 'dal portatile'},
              userId: 'u1', userName: 'Mario'));
      expect(channel().messages.single.mine, isTrue);
      finish(async);
    });
  });

  test('con la chat a schermo i messaggi non contano come non letti', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      receive(async, partyPayload({'Type': 'Chat', 'Text': '1'}, id: 'c1'));
      expect(channel().unread, 1);
      notifier().markRead();
      expect(channel().unread, 0);
      notifier().attachChatLayer();
      receive(async, partyPayload({'Type': 'Chat', 'Text': '2'}, id: 'c2'));
      expect(channel().unread, 0);
      notifier().detachChatLayer();
      receive(async, partyPayload({'Type': 'Chat', 'Text': '3'}, id: 'c3'));
      expect(channel().unread, 1);
      finish(async);
    });
  });

  test('sendChat: subito in attesa, poi confermato', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      final chats = <PartyChatEntry>[];
      notifier().chatArrivals.listen(chats.add);
      channelApi.sendGate = Completer<void>();
      PartyChatSendResult? result;
      unawaited(notifier().sendChat('  che scena\n').then((r) => result = r));
      async.flushMicrotasks();
      expect(channel().messages.single.pending, isTrue);
      expect(channel().messages.single.mine, isTrue);
      expect(channel().messages.single.event.text, 'che scena');
      expect(chats.single.pending, isTrue);
      channelApi.sendGate!.complete();
      async.flushMicrotasks();
      expect(result, PartyChatSendResult.sent);
      expect(channel().messages.single.pending, isFalse);
      expect(channel().messages.single.event.id, 'srv-1');
      expect(channel().sent, 1);
      expect(sentJson(), [
        {'Type': 'Chat', 'Text': 'che scena'},
      ]);
      finish(async);
    });
  });

  test('sendChat: troppi messaggi o errore → messaggio tolto, esito', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      final results = <PartyChatSendResult>[];
      channelApi.sendFailures
        ..add(PartyChannelFailure.rateLimited)
        ..add(PartyChannelFailure.network);
      unawaited(notifier().sendChat('uno').then(results.add));
      async.flushMicrotasks();
      unawaited(notifier().sendChat('due').then(results.add));
      async.flushMicrotasks();
      expect(results,
          [PartyChatSendResult.rateLimited, PartyChatSendResult.failed]);
      expect(channel().messages, isEmpty);
      expect(channel().sent, 0);
      finish(async);
    });
  });

  test('sendChat: testo vuoto o troppo lungo, o canale spento → niente invio',
      () {
    fakeAsync((async) {
      mount(async);
      joinGroup(async);
      final results = <PartyChatSendResult>[];
      unawaited(notifier().sendChat('ciao').then(results.add));
      async.flushMicrotasks();
      expect(results, [PartyChatSendResult.failed], reason: 'canale spento');

      channelApi.install();
      events.add(const ServerConnected(true));
      async.flushMicrotasks();
      expect(channel().active, isTrue);
      unawaited(notifier().sendChat('   ').then(results.add));
      unawaited(notifier().sendChat('x' * (maxChatLength + 1)).then(results.add));
      async.flushMicrotasks();
      expect(results, List.filled(3, PartyChatSendResult.failed));
      expect(channelApi.calls.where((call) => call.startsWith('send')), isEmpty);
      finish(async);
    });
  });

  test('409: rientra nel canale e riprova una volta', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      channelApi.sendFailures.add(PartyChannelFailure.sessionUnknown);
      PartyChatSendResult? result;
      unawaited(notifier().sendChat('ciao').then((r) => result = r));
      async.flushMicrotasks();
      expect(result, PartyChatSendResult.sent);
      expect(channelApi.calls.skip(2),
          ['send g1 Chat', 'join g1', 'send g1 Chat']);
      finish(async);
    });
  });

  test('404 durante un invio: plugin sparito, canale spento', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      channelApi.sendFailures.add(PartyChannelFailure.unavailable);
      notifier().announce(PartyAction.pause);
      async.flushMicrotasks();
      expect(channel().active, isFalse);
      expect(channel().availability, PartyPluginAvailability.unavailable);
      expect(notices.attributionCalls.last, isFalse);
      finish(async);
    });
  });

  test('reazioni e annunci', () {
    fakeAsync((async) {
      channelApi.install();
      mount(async);
      joinGroup(async);
      final reactions = <PartyReactionEvent>[];
      notifier().reactions.listen(reactions.add);
      notifier().sendReaction(PartyReaction.clap);
      async.flushMicrotasks();
      expect(reactions.single.reaction, PartyReaction.clap);
      expect(reactions.single.userId, testUser.id,
          reason: 'la propria reazione parte subito');

      notifier()
        ..announce(PartyAction.seek, position: const Duration(minutes: 1))
        ..announceMine(PartyNoticeKind.paused)
        ..announceMine(PartyNoticeKind.joined);
      async.flushMicrotasks();
      expect(sentJson(), [
        {'Type': 'Reaction', 'Reaction': 'clap'},
        {'Type': 'Action', 'Action': 'Seek', 'PositionTicks': 600000000},
        {'Type': 'Action', 'Action': 'Pause'},
      ]);
      expect(channel().sent, 3);
      finish(async);
    });
  });

  test('canale spento: reazioni e annunci non partono', () {
    fakeAsync((async) {
      mount(async);
      joinGroup(async);
      final reactions = <PartyReactionEvent>[];
      notifier().reactions.listen(reactions.add);
      notifier()
        ..sendReaction(PartyReaction.joy)
        ..announce(PartyAction.pause);
      async.flushMicrotasks();
      expect(reactions, isEmpty);
      expect(channelApi.sent, isEmpty);
      finish(async);
    });
  });
}
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_channel_test.dart`
Expected: FAIL in compilazione (`party_channel.dart` non esiste).

- [ ] **Step 3: implementa**

Crea `lib/features/watch_party/party_channel.dart`:

```dart
import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/party_channel/party_channel_api.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../auth/session_controller.dart';
import 'party_notices.dart';
import 'watch_party_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Il plugin "WonderFlix Watch Party" sul server (spec E §7.3).
enum PartyPluginAvailability {
  /// Non ancora chiesto.
  unknown,
  available,

  /// Assente, o con un protocollo che non parliamo.
  unavailable,
}

/// Esito di [PartyChannel.sendChat].
enum PartyChatSendResult { sent, rateLimited, failed }

/// Un messaggio della chat.
class PartyChatEntry {
  const PartyChatEntry(this.event, {required this.mine, this.pending = false});

  final PartyChatEvent event;

  /// Scritto dal nostro utente (anche da un altro PC): nome "Tu".
  final bool mine;

  /// Mandato da noi e non ancora confermato dal plugin.
  final bool pending;
}

class PartyChannelState {
  const PartyChannelState({
    this.availability = PartyPluginAvailability.unknown,
    this.pluginVersion,
    this.active = false,
    this.messages = const [],
    this.unread = 0,
    this.sent = 0,
    this.received = 0,
  });

  final PartyPluginAvailability availability;
  final String? pluginVersion;

  /// Il canale funziona per il gruppo in cui siamo.
  final bool active;

  /// Storico della chat del gruppo, dal più vecchio; al massimo
  /// [PartyChannel.maxMessages].
  final List<PartyChatEntry> messages;

  /// Messaggi arrivati con la chat fuori dallo schermo (spec E §9.5).
  final int unread;

  /// Eventi mandati e ricevuti nel gruppo (diagnostica).
  final int sent;
  final int received;

  PartyChannelState copyWith({
    PartyPluginAvailability? availability,
    String? pluginVersion,
    bool? active,
    List<PartyChatEntry>? messages,
    int? unread,
    int? sent,
    int? received,
  }) =>
      PartyChannelState(
        availability: availability ?? this.availability,
        pluginVersion: pluginVersion ?? this.pluginVersion,
        active: active ?? this.active,
        messages: messages ?? this.messages,
        unread: unread ?? this.unread,
        sent: sent ?? this.sent,
        received: received ?? this.received,
      );
}

typedef _Membership = ({String groupId, int rejoins});

_Membership? _membershipOf(WatchPartyState party) {
  final group = party.group;
  return party.inGroup && group != null
      ? (groupId: group.id, rejoins: party.rejoins)
      : null;
}

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Il canale del plugin "WonderFlix Watch Party" (spec E §7.3): entra nel
/// gruppo del plugin quando si entra in un gruppo SyncPlay, riceve gli
/// eventi degli altri e manda i nostri. Senza plugin resta spento e l'app
/// fa come prima.
///
/// Gli annunci ricevuti vanno agli avvisi ([PartyNotices.attribute]); chat e
/// reazioni restano qui per il player.
class PartyChannel extends Notifier<PartyChannelState> {
  static const maxMessages = 50;

  /// Attesa massima di `Info` chiesto dalla diagnostica.
  static const infoTimeout = Duration(seconds: 5);

  /// Id degli eventi già visti che si ricordano (doppioni dopo un rientro).
  static const _seenLimit = 200;

  // Creati una volta sola, come in [WatchPartySession]: chi si iscrive lo
  // fa una volta e resta iscritto anche se il canale si ricostruisce.
  final _reactions = StreamController<PartyReactionEvent>.broadcast();
  final _chat = StreamController<PartyChatEntry>.broadcast();

  final _seen = Queue<String>();
  final _seenIds = <String>{};
  JellyfinUser? _user;

  /// Gruppo del canale attivo; `null` = canale spento.
  String? _groupId;

  /// Cambia a ogni ingresso e uscita: un `Join` partito prima non vale più.
  int _generation = 0;

  /// Livelli chat del player montati (spec E §9.5).
  int _chatLayers = 0;

  int _localIds = 0;

  @override
  PartyChannelState build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    final session = ref.read(sessionControllerProvider);
    _user = session is SessionSignedIn ? session.user : null;
    _groupId = null;
    _generation++;
    _forgetSeen();
    if (userId == null) return const PartyChannelState();
    final subscription = ref.watch(watchPartyEventsProvider).listen(_onEvent);
    ref.onDispose(() => unawaited(subscription.cancel()));
    ref.listen(watchPartySessionProvider.select(_membershipOf), _onMembership);
    // Il canale può nascere a gruppo già in corso: si entra appena finita la
    // build (lo stato non si cambia durante la build).
    final initial = _membershipOf(ref.read(watchPartySessionProvider));
    if (initial != null) {
      final generation = _generation;
      Future.microtask(() {
        if (ref.mounted && generation == _generation && _groupId == null) {
          unawaited(_join(initial.groupId));
        }
      });
    }
    return const PartyChannelState();
  }

  /// Reazioni da mostrare: degli altri e, subito, le nostre.
  Stream<PartyReactionEvent> get reactions => _reactions.stream;

  /// Messaggi nuovi: degli altri e i nostri appena mandati (`pending`).
  Stream<PartyChatEntry> get chatArrivals => _chat.stream;

  /// Manda un messaggio (spec E §9.4): compare subito come `pending`, e
  /// diventa confermato con la risposta del plugin. Se l'invio fallisce il
  /// messaggio sparisce.
  Future<PartyChatSendResult> sendChat(String text) async {
    final groupId = _groupId;
    final user = _user;
    final normalized = normalizeChatText(text);
    if (groupId == null ||
        user == null ||
        normalized.isEmpty ||
        chatTextLength(normalized) > maxChatLength) {
      return PartyChatSendResult.failed;
    }
    final local = PartyChatEntry(
      PartyChatEvent(
        id: 'local-${++_localIds}',
        groupId: groupId,
        userId: user.id,
        userName: user.name,
        sentAt: clock.now().toUtc(),
        text: normalized,
      ),
      mine: true,
      pending: true,
    );
    _addMessage(local);
    _chat.add(local);
    try {
      final stamped = await _send(groupId, PartyOutgoingChat(normalized));
      if (!ref.mounted || _groupId != groupId) return PartyChatSendResult.sent;
      _remember(stamped.id);
      final confirmed = PartyChatEntry(
          stamped is PartyChatEvent ? stamped : local.event,
          mine: true);
      state = state.copyWith(
        sent: state.sent + 1,
        messages: [
          for (final entry in state.messages)
            identical(entry, local) ? confirmed : entry,
        ],
      );
      return PartyChatSendResult.sent;
    } on PartyChannelException catch (error) {
      _log.info('messaggio del watch party non inviato: $error');
      if (ref.mounted) {
        state = state.copyWith(messages: [
          for (final entry in state.messages)
            if (!identical(entry, local)) entry,
        ]);
      }
      return error.failure == PartyChannelFailure.rateLimited
          ? PartyChatSendResult.rateLimited
          : PartyChatSendResult.failed;
    }
  }

  /// Manda una reazione: la nostra si vede subito, senza aspettare il
  /// plugin (spec E §10.4).
  void sendReaction(PartyReaction reaction) {
    final groupId = _groupId;
    final user = _user;
    if (groupId == null || user == null) return;
    _reactions.add(PartyReactionEvent(
      id: 'local-${++_localIds}',
      groupId: groupId,
      userId: user.id,
      userName: user.name,
      sentAt: clock.now().toUtc(),
      reaction: reaction,
    ));
    unawaited(_sendQuietly(PartyOutgoingReaction(reaction)));
  }

  /// Annuncia agli altri un'azione nostra sul gruppo (spec E §7.4).
  void announce(PartyAction action, {Duration? position}) {
    if (_groupId == null) return;
    unawaited(_sendQuietly(PartyOutgoingAction(action, position: position)));
  }

  /// Annuncia un'azione nata in `GroupAuthority` (pausa, ripresa, salto); le
  /// altre non si annunciano da qui.
  void announceMine(PartyNoticeKind kind, {Duration? position}) {
    final action = switch (kind) {
      PartyNoticeKind.paused => PartyAction.pause,
      PartyNoticeKind.resumed ||
      PartyNoticeKind.forcedResume =>
        PartyAction.unpause,
      PartyNoticeKind.seeked => PartyAction.seek,
      _ => null,
    };
    if (action != null) announce(action, position: position);
  }

  /// La chat è stata aperta: niente più non letti.
  void markRead() {
    if (state.unread != 0) state = state.copyWith(unread: 0);
  }

  /// Un livello chat del player è a schermo: i messaggi in arrivo non
  /// contano come non letti (spec E §9.5). Ogni chiamata va chiusa da
  /// [detachChatLayer] (durante un passaggio tra player sono due).
  void attachChatLayer() => _chatLayers++;

  void detachChatLayer() {
    if (_chatLayers > 0) _chatLayers--;
  }

  /// Per la diagnostica (spec E §13): se il plugin non risulta presente
  /// chiede `Info`, al massimo per [infoTimeout].
  Future<void> refreshInfo() async {
    if (state.availability == PartyPluginAvailability.available) return;
    try {
      final info =
          await ref.read(partyChannelApiProvider).info().timeout(infoTimeout);
      if (!ref.mounted) return;
      state = state.copyWith(
        availability: info.protocol == partyChannelProtocol
            ? PartyPluginAvailability.available
            : PartyPluginAvailability.unavailable,
        pluginVersion: info.version,
      );
    } on PartyChannelException catch (error) {
      if (ref.mounted && error.failure == PartyChannelFailure.unavailable) {
        state =
            state.copyWith(availability: PartyPluginAvailability.unavailable);
      }
    } on Object catch (error) {
      _log.info('plugin del watch party non verificato: $error');
    }
  }

  void _onMembership(_Membership? previous, _Membership? next) {
    if (previous != null && previous.groupId != next?.groupId) {
      _leave(previous.groupId);
    }
    if (next != null) unawaited(_join(next.groupId));
  }

  /// Entra nel canale del gruppo (anche dopo un rientro): `Info` finché il
  /// plugin non risulta presente, poi `Join` con lo storico.
  Future<void> _join(String groupId) async {
    final generation = ++_generation;
    try {
      final api = ref.read(partyChannelApiProvider);
      if (state.availability != PartyPluginAvailability.available) {
        final info = await api.info();
        if (!ref.mounted || generation != _generation) return;
        if (info.protocol != partyChannelProtocol) {
          _log.warning('plugin del watch party ${info.version} con '
              'protocollo ${info.protocol}: canale spento');
          _deactivate(
              availability: PartyPluginAvailability.unavailable,
              version: info.version);
          return;
        }
        state = state.copyWith(
            availability: PartyPluginAvailability.available,
            pluginVersion: info.version);
      }
      final history = await api.join(groupId);
      if (!ref.mounted || generation != _generation) return;
      _groupId = groupId;
      state = state.copyWith(active: true, messages: _merge(history));
      ref.read(partyNoticesProvider.notifier).setAttribution(true);
      _log.info('canale del watch party attivo '
          '(${history.length} messaggi nello storico)');
    } on PartyChannelException catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _log.info('canale del watch party spento: $error');
      _deactivate(
          availability: error.failure == PartyChannelFailure.unavailable
              ? PartyPluginAvailability.unavailable
              : null);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _log.warning('canale del watch party non disponibile: $error');
      _deactivate();
    }
  }

  void _leave(String groupId) {
    _generation++;
    final active = _groupId != null &&
        _normalizeId(_groupId!) == _normalizeId(groupId);
    _groupId = null;
    _forgetSeen();
    state = PartyChannelState(
        availability: state.availability, pluginVersion: state.pluginVersion);
    ref.read(partyNoticesProvider.notifier).setAttribution(false);
    if (!active) return;
    unawaited(ref.read(partyChannelApiProvider).leave(groupId).catchError(
        (Object error) =>
            _log.info('uscita dal canale del watch party non inviata: $error')));
  }

  /// Canale spento per il gruppo corrente (plugin assente o sparito, errori).
  void _deactivate({PartyPluginAvailability? availability, String? version}) {
    _groupId = null;
    if (!ref.mounted) return;
    state = state.copyWith(
        active: false, availability: availability, pluginVersion: version);
    ref.read(partyNoticesProvider.notifier).setAttribution(false);
  }

  void _onEvent(ServerEvent event) {
    if (event is! PartyChannelReceived) return;
    final groupId = _groupId;
    if (groupId == null) return;
    final parsed = parsePartyEvent(event.payload);
    if (parsed == null ||
        _normalizeId(parsed.groupId) != _normalizeId(groupId) ||
        !_remember(parsed.id)) {
      return;
    }
    state = state.copyWith(received: state.received + 1);
    switch (parsed) {
      case PartyActionEvent():
        ref.read(partyNoticesProvider.notifier).attribute(parsed);
      case PartyChatEvent():
        final entry = PartyChatEntry(parsed, mine: parsed.userId == _user?.id);
        _addMessage(entry);
        if (_chatLayers == 0) state = state.copyWith(unread: state.unread + 1);
        _chat.add(entry);
      case PartyReactionEvent():
        _reactions.add(parsed);
    }
  }

  /// `false` se l'evento [id] è già arrivato.
  bool _remember(String id) {
    if (!_seenIds.add(id)) return false;
    _seen.add(id);
    if (_seen.length > _seenLimit) _seenIds.remove(_seen.removeFirst());
    return true;
  }

  void _forgetSeen() {
    _seen.clear();
    _seenIds.clear();
  }

  /// Storico ricevuto unito ai messaggi presenti, senza doppioni, in ordine
  /// di invio; al massimo [maxMessages].
  List<PartyChatEntry> _merge(List<PartyChatEvent> history) {
    final byId = {for (final entry in state.messages) entry.event.id: entry};
    for (final event in history) {
      _remember(event.id);
      byId.putIfAbsent(
          event.id, () => PartyChatEntry(event, mine: event.userId == _user?.id));
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.event.sentAt.compareTo(b.event.sentAt));
    return merged.length > maxMessages
        ? merged.sublist(merged.length - maxMessages)
        : merged;
  }

  void _addMessage(PartyChatEntry entry) {
    final messages = [...state.messages, entry];
    state = state.copyWith(
        messages: messages.length > maxMessages
            ? messages.sublist(messages.length - maxMessages)
            : messages);
  }

  /// Manda [event]. Con 409 (il plugin non trova la sessione) rientra nel
  /// canale e riprova una volta; con 404 il plugin è sparito e il canale si
  /// spegne (spec E §12).
  Future<PartyEvent> _send(String groupId, PartyOutgoing event) async {
    final api = ref.read(partyChannelApiProvider);
    try {
      try {
        return await api.send(groupId, event);
      } on PartyChannelException catch (error) {
        if (error.failure != PartyChannelFailure.sessionUnknown) rethrow;
        _log.info('il plugin non trova la sessione: rientro nel canale');
        final history = await api.join(groupId);
        if (ref.mounted && _groupId == groupId) {
          state = state.copyWith(messages: _merge(history));
        }
        return await api.send(groupId, event);
      }
    } on PartyChannelException catch (error) {
      if (error.failure == PartyChannelFailure.unavailable &&
          _groupId == groupId) {
        _log.warning('plugin del watch party sparito: canale spento');
        _deactivate(availability: PartyPluginAvailability.unavailable);
      }
      rethrow;
    }
  }

  /// Invio senza esito per chi chiama (reazioni, annunci): gli errori
  /// finiscono nel log.
  Future<void> _sendQuietly(PartyOutgoing event) async {
    final groupId = _groupId;
    if (groupId == null) return;
    try {
      await _send(groupId, event);
      if (ref.mounted) state = state.copyWith(sent: state.sent + 1);
    } on PartyChannelException catch (error) {
      _log.info('evento ${event.toJson()['Type']} del watch party non '
          'inviato: $error');
    }
  }
}

final partyChannelProvider =
    NotifierProvider<PartyChannel, PartyChannelState>(PartyChannel.new);
```

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/watch_party/party_channel_test.dart`
Expected: PASS (19 test).

- [ ] **Step 5: il canale resta vivo in tutta l'app**

In `lib/features/watch_party/watch_party_routing.dart` aggiungi l'import `import 'party_channel.dart';` (in ordine) e, in `watchPartyRoutingProvider`, dopo `ref.listen(partyNoticesProvider, (_, _) {});`:

```dart
  // Il canale del plugin segue il gruppo anche fuori dal player (storico
  // della chat, messaggi non letti, spec E §7.3).
  ref.listen(partyChannelProvider, (_, _) {});
```

Nei test che ascoltano `watchPartyRoutingProvider` il canale ora nasce davvero: senza un override proverebbe a usare `jellyfinHttpProvider`. Aggiungi agli `overrides`:
- `test/features/watch_party/watch_party_routing_test.dart` (nel `ProviderContainer.test` del `setUp`);
- `test/features/watch_party/party_handover_test.dart` (nel `ProviderContainer` del banco di prova);

la riga

```dart
      partyChannelApiProvider.overrideWithValue(FakePartyChannelApi()),
```

(`FakePartyChannelApi` viene da `../../support/watch_party_fakes.dart`, già importato in entrambi; `partyChannelApiProvider` da `watch_party_providers.dart`, già importato).

- [ ] **Step 6: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/watch_party/party_channel.dart lib/features/watch_party/watch_party_routing.dart test/features/watch_party/party_channel_test.dart test/features/watch_party/watch_party_routing_test.dart test/features/watch_party/party_handover_test.dart
git commit -m "feat: join the watch party plugin channel with the group"
```

---

## Gruppo E — annunci e diagnostica

### Task 13: le nostre azioni si annunciano

**Files:**
- Modify: `lib/features/player/player_screen.dart` (`_attachParty`, `_playNext`, nuovo `_requestNextInParty`)
- Modify: `lib/features/watch_party/watch_party_actions.dart` (`startWatchParty`)
- Test: `test/features/watch_party/party_player_test.dart`, `test/features/watch_party/watch_party_actions_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In `test/features/watch_party/party_player_test.dart`:
- aggiungi gli import `package:wonderflix/core/party_channel/party_channel_models.dart`;
- tra le variabili `late` aggiungi `late FakePartyChannelApi channelApi;`;
- in `pumpPartyPlayer`, prima di `router = GoRouter(`, aggiungi `channelApi = FakePartyChannelApi()..install();`;
- negli `overrides` del `ProviderContainer`, dopo `watchPartyEventsProvider.overrideWithValue(events.stream),`, aggiungi `partyChannelApiProvider.overrideWithValue(channelApi),`.

Poi in fondo a `main()` (dopo tutti i test esistenti: usano le funzioni locali `pumpPartyPlayer`, `queueSeries`, `finish`):

```dart
  List<Map<String, dynamic>> announced() => [
        for (final event in channelApi.sent)
          if (event is PartyOutgoingAction) event.toJson(),
      ];

  testWidgets('canale: la ripresa dal player si annuncia (spec E §7.4)',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(channelApi.calls, containsAllInOrder(['info', 'join g1']));
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(announced(), [
      {'Type': 'Action', 'Action': 'Unpause'},
    ]);
    await finish(tester);
  });

  testWidgets('canale: il prossimo episodio chiesto dall\'utente si annuncia',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    await tester.tap(find.byTooltip(l.playerNextEpisode));
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    expect(announced(), [
      {'Type': 'Action', 'Action': 'NextItem'},
    ]);
    await finish(tester);
  });

  testWidgets('canale: l\'episodio dopo a fine video non si annuncia',
      (tester) async {
    await pumpPartyPlayer(tester);
    await queueSeries(tester);
    engine.emitCompleted();
    await tester.pump();
    await tester.pump();
    expect(api.calls, contains('next p1'));
    expect(announced(), isEmpty);
    await finish(tester);
  });
```

In `test/features/watch_party/watch_party_actions_test.dart`:
- aggiungi l'import `package:wonderflix/features/watch_party/party_channel.dart`;
- tra le variabili `late` aggiungi `late FakePartyChannelApi channelApi;` e nel `setUp` `channelApi = FakePartyChannelApi()..install();`;
- negli `overrides` di `pumpButton` aggiungi `partyChannelApiProvider.overrideWithValue(channelApi),`;
- dopo il test `'dentro un gruppo: solo la nuova coda'` aggiungi:

```dart
  testWidgets('dentro un gruppo: la nuova coda si annuncia (spec E §7.4)',
      (tester) async {
    await pumpButton(tester);
    // Come nell'app, dove lo tiene vivo `watchPartyRoutingProvider`.
    container(tester).listen(partyChannelProvider, (_, _) {});
    unawaited(container(tester)
        .read(watchPartySessionProvider.notifier)
        .join('g1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('via'));
    await tester.pumpAndSettle();
    expect([for (final event in channelApi.sent) event.toJson()], [
      {'Type': 'Action', 'Action': 'NewQueue'},
    ]);
    await leave(tester);
  });
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/watch_party/party_player_test.dart test/features/watch_party/watch_party_actions_test.dart`
Expected: i tre test nuovi del canale nel player e quello della nuova coda FAIL (nessun annuncio); gli altri PASS.

- [ ] **Step 3: implementa nel player**

In `lib/features/player/player_screen.dart` aggiungi gli import (in ordine):

```dart
import '../../core/party_channel/party_channel_models.dart';
```

(dopo `import '../../core/media_session/media_session.dart';`) e

```dart
import '../watch_party/party_channel.dart';
```

(dopo `import '../watch_party/party_badge.dart';`).

In `_attachParty` sostituisci:

```dart
    final notices = ref.read(partyNoticesProvider.notifier);
```

con:

```dart
    final notices = ref.read(partyNoticesProvider.notifier);
    final channel = ref.read(partyChannelProvider.notifier);
```

e il parametro `onAction` di `GroupAuthority`:

```dart
      onAction: (kind, {position}) => notices.mine(kind,
          position: position, show: !_chrome.isRecentKeyAction(kind)),
```

con:

```dart
      onAction: (kind, {position}) {
        notices.mine(kind,
            position: position, show: !_chrome.isRecentKeyAction(kind));
        // Spec E §7.4: gli altri vedono il nostro nome.
        channel.announceMine(kind, position: position);
      },
```

In `_playNext`, nel ramo `if (_inParty)`, sostituisci:

```dart
        unawaited(ref
            .read(watchPartySessionProvider.notifier)
            .nextItem(widget.args.party!));
```

con:

```dart
        unawaited(_requestNextInParty(widget.args.party!));
```

e aggiungi subito dopo il metodo `_playNext`:

```dart

  /// Chiede al gruppo l'elemento dopo [playlistItemId] e, se la richiesta
  /// parte, la annuncia agli altri (spec E §7.4). Il canale si prende prima
  /// dell'attesa: nel frattempo il player può chiudersi.
  Future<void> _requestNextInParty(String playlistItemId) async {
    final channel = ref.read(partyChannelProvider.notifier);
    final requested = await ref
        .read(watchPartySessionProvider.notifier)
        .nextItem(playlistItemId);
    if (requested) channel.announce(PartyAction.nextItem);
  }
```

`_onFinished` resta com'è: a fine video l'elemento dopo lo chiedono tutti, e non si annuncia.

- [ ] **Step 4: implementa in `startWatchParty`**

In `lib/features/watch_party/watch_party_actions.dart` aggiungi gli import (in ordine):

```dart
import '../../core/party_channel/party_channel_models.dart';
import 'party_channel.dart';
```

e sostituisci:

```dart
        if (container.read(watchPartySessionProvider).inGroup) {
          await session.setQueue(queue, start: start);
        } else {
```

con:

```dart
        if (container.read(watchPartySessionProvider).inGroup) {
          await session.setQueue(queue, start: start);
          // Spec E §7.4: gli altri vedono chi ha scelto il titolo.
          container
              .read(partyChannelProvider.notifier)
              .announce(PartyAction.newQueue);
        } else {
```

- [ ] **Step 5: esegui i test**

Run: `flutter test test/features/watch_party/ test/features/player/`
Expected: PASS.

- [ ] **Step 6: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/player/player_screen.dart lib/features/watch_party/watch_party_actions.dart test/features/watch_party/party_player_test.dart test/features/watch_party/watch_party_actions_test.dart
git commit -m "feat: announce our watch party actions to the group"
```

### Task 14: diagnostica del plugin

**Files:**
- Modify: `lib/features/settings/diagnostics.dart`
- Test: `test/features/settings/diagnostics_test.dart`

- [ ] **Step 1: scrivi i test che falliscono**

In `test/features/settings/diagnostics_test.dart` aggiungi gli import:

```dart
import 'package:wonderflix/features/watch_party/party_channel.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
```

Cambia `container` perché accetti il finto del plugin:

```dart
  Future<ProviderContainer> container(FakeSystemApi system,
      {FakePartyChannelApi? channelApi}) async {
```

e aggiungi agli `overrides`:

```dart
      partyChannelApiProvider
          .overrideWithValue(channelApi ?? FakePartyChannelApi()),
```

Poi aggiungi i test (in fondo a `main()`):

```dart
  test('describePartyChannel: plugin, canale e contatori, niente testi', () {
    expect(describePartyChannel(const PartyChannelState()),
        'sconosciuto, canale=spento, inviati=0, ricevuti=0');
    expect(
        describePartyChannel(const PartyChannelState(
            availability: PartyPluginAvailability.unavailable)),
        'assente, canale=spento, inviati=0, ricevuti=0');
    expect(
        describePartyChannel(const PartyChannelState(
            availability: PartyPluginAvailability.unavailable,
            pluginVersion: '2.0.0')),
        '2.0.0 (protocollo diverso), canale=spento, inviati=0, ricevuti=0');
    expect(
        describePartyChannel(const PartyChannelState(
          availability: PartyPluginAvailability.available,
          pluginVersion: '1.0.0',
          active: true,
          sent: 3,
          received: 5,
        )),
        '1.0.0 (protocollo 1), canale=attivo, inviati=3, ricevuti=5');
  });

  test('buildDiagnostics: riga del plugin del watch party', () {
    final text = buildDiagnostics(
      appVersion: '0.1.0',
      windowsVersion: 'w',
      serverVersion: '10.11.9',
      player: const PlayerSettings(),
      discord: const DiscordSettings(),
      recentErrors: const [],
      watchPartyPlugin: 'assente, canale=spento, inviati=0, ricevuti=0',
    );
    expect(
        text,
        contains('Plugin watch party: assente, canale=spento, inviati=0, '
            'ricevuti=0\n'));
  });

  test('collectDiagnostics: chiede Info al plugin se non è noto', () async {
    final channelApi = FakePartyChannelApi()..install();
    final c = await container(FakeSystemApi(), channelApi: channelApi);
    final text = await c.read(collectDiagnosticsProvider)();
    expect(channelApi.calls, ['info']);
    expect(
        text,
        contains('Plugin watch party: 1.0.0 (protocollo 1), canale=spento, '
            'inviati=0, ricevuti=0\n'));
  });
```

- [ ] **Step 2: esegui i test e verifica che falliscano**

Run: `flutter test test/features/settings/diagnostics_test.dart`
Expected: FAIL in compilazione (`describePartyChannel`, `watchPartyPlugin` non esistono).

- [ ] **Step 3: implementa**

In `lib/features/settings/diagnostics.dart` aggiungi gli import (in ordine):

```dart
import '../../core/party_channel/party_channel_models.dart';
```

e

```dart
import '../watch_party/party_channel.dart';
```

Dopo `describeWatchParty` aggiungi:

```dart

/// Plugin e canale del watch party per la diagnostica (spec E §13). Niente
/// testi né nomi: solo versione e contatori.
String describePartyChannel(PartyChannelState state) {
  final version = state.pluginVersion;
  final plugin = switch (state.availability) {
    PartyPluginAvailability.available =>
      '$version (protocollo $partyChannelProtocol)',
    PartyPluginAvailability.unavailable =>
      version == null ? 'assente' : '$version (protocollo diverso)',
    PartyPluginAvailability.unknown => 'sconosciuto',
  };
  return '$plugin, canale=${state.active ? 'attivo' : 'spento'}, '
      'inviati=${state.sent}, ricevuti=${state.received}';
}
```

In `buildDiagnostics` aggiungi il parametro `String? watchPartyPlugin,` dopo `String? watchParty,` e, dopo la riga `if (watchParty != null) buffer.writeln('Watch party: $watchParty');`:

```dart
  if (watchPartyPlugin != null) {
    buffer.writeln('Plugin watch party: $watchPartyPlugin');
  }
```

In `collectDiagnosticsProvider`, dopo il blocco `try` del watch party (prima di `return buildDiagnostics(`):

```dart
          String? watchPartyPlugin;
          try {
            await ref.read(partyChannelProvider.notifier).refreshInfo();
            watchPartyPlugin =
                describePartyChannel(ref.read(partyChannelProvider));
          } on Object catch (error) {
            _log.info('stato del plugin del watch party non disponibile: '
                '$error');
          }
```

e passa `watchPartyPlugin: watchPartyPlugin,` a `buildDiagnostics`.

- [ ] **Step 4: esegui i test**

Run: `flutter test test/features/settings/diagnostics_test.dart`
Expected: PASS (anche i test esistenti: `buildDiagnostics` senza il parametro nuovo non scrive la riga).

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutto verde.

```bash
git add lib/features/settings/diagnostics.dart test/features/settings/diagnostics_test.dart
git commit -m "feat: show the watch party plugin in diagnostics"
```

---

## Gruppo F — chiusura

### Task 15: spec allineato e verifica finale

**Files:**
- Modify: `docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`

- [ ] **Step 1: allinea lo spec all'implementazione**

Nello spec:

1. Riga **Stato** dell'intestazione: sostituisci `approvato in brainstorming, da dividere nei piani 10a, 10b e 10c` con `approvato; piano 10a realizzato (\`docs/superpowers/plans/2026-10-02-wonderflix-10a-watch-party-plugin-nomi.md\`), 10b e 10c da fare`.
2. **§6.1**, blocco della struttura: togli la riga `Jellyfin.Plugin.WonderFlixWatchParty.sln` e sostituisci la riga di `build.yaml` con queste due:

```
  meta.template.json                             meta.json del pacchetto (versione e data le mette pack.sh)
  pack.sh                                        build di release e cartella da installare
```

   e nel punto **Dipendenze** aggiungi alla fine: ` Il progetto di test riferisce di nuovo gli stessi pacchetti senza \`ExcludeAssets\`, altrimenti non carica le dll di Jellyfin.`
3. **§6.8**, primo punto del workflow con il tag: sostituisci `build di release, zip \`wonderflix-watch-party_X.Y.Z.zip\` con la dll e \`meta.json\`` con `\`pack.sh\` (build di release e cartella con la dll e \`meta.json\`), zip \`wonderflix-watch-party_X.Y.Z.zip\``.
4. **§7.3**, in fondo all'elenco aggiungi:

```markdown
- **Avvisi:** gli annunci ricevuti vanno a `PartyNotices.attribute`; quando il canale si accende o si spegne lo dice a `PartyNotices.setAttribution`. Gli avvisi non leggono il canale.
- **Vita:** il canale lo tiene vivo `watchPartyRoutingProvider` (in `WonderflixApp`), così segue il gruppo anche fuori dal player. Se nasce a gruppo già in corso entra subito dopo la build.
- **Per il player (10b, 10c):** `chatArrivals` (messaggi nuovi, anche i propri `pending`), `reactions`, `attachChatLayer`/`detachChatLayer`, `markRead`; per la diagnostica `refreshInfo`.
```

5. **§13**, primo punto: sostituisci tutto il punto con:

```markdown
- La diagnostica (Impostazioni → copia della diagnostica) aggiunge una riga `Plugin watch party: …`, per esempio `Plugin watch party: 1.0.0 (protocollo 1), canale=attivo, inviati=3, ricevuti=5`, oppure `assente, canale=spento, …`, `2.0.0 (protocollo diverso), …`, `sconosciuto, …`. Come il resto della diagnostica non è tradotta. **Mai testi né nomi.** Se il plugin non è già noto, la diagnostica chiede `Info` (al massimo 5 s).
```

6. **§14**, tabella: togli le quattro righe `diagnosticsPartyPlugin`, `diagnosticsPartyPluginVersion`, `diagnosticsPartyPluginMissing`, `diagnosticsPartyPluginUnknown` (la diagnostica non usa gli ARB).
7. **§6.2**, dopo la frase sugli errori aggiungi: ` Senza autenticazione la risposta è 400, come per gli endpoint SyncPlay di Jellyfin (la policy \`SyncPlayHasAccess\` va in errore su un utente anonimo); l'app manda sempre l'autenticazione.`
8. **§17**, primo punto: sostituisci `verificato sul codice di 10.11.9, non ancora sul server: è lo scopo della sonda.` con `verificato sul server vero con la sonda del piano 10a (2026-10-02).`

- [ ] **Step 2: verifica completa**

Run, dalla root del worktree:
- `flutter analyze` → `No issues found!`
- `flutter test` → tutto verde (1102 + i nuovi test)
- `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` → tutto verde
- `git log --format=%B main..HEAD | grep -i -E "co-authored|generated with"` → nessuna riga
- `git status` pulito (a parte, eventualmente, `windows/flutter/` con soli fine riga: `git checkout -- windows/flutter/`)

- [ ] **Step 3: commit**

```bash
git add docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md
git commit -m "docs: align spec E with plan 10a"
```

- [ ] **Step 4: prova manuale (orchestratore e utente)**

Dopo la revisione finale e le correzioni approvate dall'utente:
1. Build di release dell'app nel worktree: `flutter build windows --release --dart-define-from-file=config/wonderflix.json` (con `export PATH="/c/Users/sidot/.cargo/bin:$PATH"`); l'exe lo avvia l'utente.
2. `bash jellyfin-plugin-watch-party/pack.sh 1.0.0`; l'utente sostituisce via SFTP la cartella della sonda con quella nuova (stesso nome) e riavvia Jellyfin.
3. Prova con due istanze (`WONDERFLIX_PROFILE=b` per la seconda), meglio con due utenti Jellyfin diversi:
   - gruppo creato da una, l'altra entra; pausa, ripresa, salto, episodio successivo, "Guarda insieme" con un altro titolo → l'altra istanza vede "Nome ha …";
   - avvisi propri sempre "Hai …"; ingressi e uscite come prima;
   - WebSocket che cade (rete staccata qualche secondo) → dopo il rientro i nomi tornano;
   - diagnostica copiata: riga `Plugin watch party: 1.0.0 (protocollo 1), canale=attivo, …`;
   - plugin tolto dal server (cartella spostata, riavvio) → avvisi di nuovo anonimi, nessun errore visibile.
