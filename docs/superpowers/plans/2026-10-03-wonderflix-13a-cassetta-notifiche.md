# WonderFlix — Piano 13a: cassetta delle notifiche (plugin + app)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prima metà della Spec G: la cassetta delle notifiche nel plugin "WonderFlix Watch Party" (voci su disco, inviti ai watch party, annunci dell'admin dalla Dashboard di Jellyfin) e l'icona con il pannello "Notifiche" nell'app.

**Spec:** `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md` (§3–5, §6.1–6.5, §6.7, §6.8 senza la casella dei nuovi titoli, §6.9, §7 senza la voce Novità, §8, §9, §10). I **nuovi titoli** (§6.6, la voce Novità, `formatEpisodeRanges`, la casella "Notify new titles") e la **release** sono del **piano 13b**.

**Decisioni del piano (approvate dall'utente il 2026-10-03):**
1. `Info` passa in un controller con `[Authorize]` semplice; l'app lo chiede anche a chi non ha accesso ai watch party e a quell'utente lascia solo `inbox` (niente amici né party).
2. I pannelli laterali hanno un contenitore comune (`ShellSidePanel`) e uno stato unico `shellPanelProvider` (nessuno / amici / notifiche) al posto di `friendsPanelProvider`: un pannello alla volta per costruzione.
3. Nel 13a la pagina della Dashboard ha solo l'annuncio; la casella dei nuovi titoli arriva col 13b.
4. Una voce che arriva col pannello Notifiche aperto prende il pallino dorato ma viene segnata subito come letta.

**Architecture:**
- **Plugin (1.2.0):** `InboxBook` (regole in memoria: Seq, limiti, letture, inviti che si aggiornano) + `InboxStore` (`inbox.json` accanto a `friends.json`, scrittura atomica) + `InboxService` (lock, annunci, voci d'invito, pulizia, avviso `InboxChanged`) + `ILibraryAccess` (elemento in riproduzione, visibilità per utente; adattatore `JellyfinLibraryAccess`) + `InboxController` (REST, `[Authorize]`; annunci solo admin) + `InfoController` + pagina HTML incorporata (`IHasWebPages`). `PartyService.InviteAsync` chiama `InboxService.AddInvitesAsync`. `Info.Features` aggiunge `"inbox"`; `Protocol` resta 1.
- **App:** `lib/core/social/inbox_models.dart` + `SocialApi` (cassetta) → `SocialAvailability` (`inbox`, anche senza watch party) → `lib/features/inbox/` (`InboxController`, `InboxPanel`, `InboxButton`, `InboxPanelHost`) → `lib/app/shell_panels.dart` (`shellPanelProvider`) + `lib/ui/shell_side_panel.dart` (contenitore comune, usato anche dal pannello Amici) → shell (`app_shell.dart`, `back_navigation.dart`).

**Tech Stack:** C# net9.0 contro Jellyfin.Controller/Model 10.11.0 (test con le dll 10.11.9), xUnit, `Microsoft.Extensions.TimeProvider.Testing`; Flutter 3.47.5, flutter_riverpod 3, dio, intl, clock, fake_async, lucide_icons_flutter.

**Worktree:** `.claude/worktrees/piano-13a`, branch `feat/piano-13a`. **Base:** `main` con lo spec G (`c06605f`) e questo piano. **Test a inizio piano:** 1415 Flutter, 139 plugin.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-13a`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git.
- **Prima di ogni commit lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde e senza warning (il plugin ha `TreatWarningsAsErrors`). **Prima di ogni commit lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit. Dopo ogni modifica agli ARB: `flutter gen-l10n` (la cartella `lib/l10n/gen/` non si committa).
- **Formattazione e fine riga:** niente `dart format` né `dotnet format` su file interi; edit mirati. Il repository salva in LF (`core.autocrlf=true`).
- **Durate, misure, limiti:** costanti nominate e commentate. Commenti in italiano, codice in inglese (anche nel C#: commenti `///` in italiano, identificatori in inglese). Nel C# sempre le graffe, anche per un `if` di una riga, come nel resto del plugin.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; durate da `WfMotion`; `clock.now()`, mai `DateTime.now()`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-03 (dump per riflessione delle API pubbliche di Jellyfin 10.11.0, 10.11.9 e 10.11.11 dalla cache NuGet; sorgenti di jellyfin e jellyfin-web v10.11.9; codice del repository):

- **API di Jellyfin usate, identiche in 10.11.0, 10.11.9 e 10.11.11:** `BaseItem.IsVisibleStandalone(User)` (librerie e limiti d'età del profilo), `ILibraryManager.GetItemById(Guid)` (null se non c'è), `SessionInfo.FullNowPlayingItem` (`BaseItem`) e `SessionInfo.NowPlayingItem` (`BaseItemDto`, `Id` è `Guid`), `Episode.SeriesId` (`Guid`, `MediaBrowser.Controller.Entities.TV`), `IUserManager.GetUserById(Guid)`, `IHasWebPages.GetPages()`, `PluginPageInfo` (`Name`, `DisplayName`, `EmbeddedResourcePath`, `EnableInMainMenu`), `Policies.RequiresElevation` (`MediaBrowser.Common.Api`).
- **Autorizzazione ASP.NET:** `[Authorize]` senza policy = qualunque utente autenticato. Un `[Authorize(Policy = …)]` sul metodo si **somma** a quello della classe (tutte e due devono passare): non può allargarlo. Per questo `Info` va in un controller suo, e gli annunci (`RequiresElevation`) stanno in un controller con `[Authorize]` semplice.
- **Rotte:** niente vincoli `{id:guid}` sugli id delle voci: una rotta che non corrisponde risponde 404, che per l'app vuol dire "plugin assente". L'id si accetta come stringa.
- **Pagina nella Dashboard (10.11):** la dashboard React carica ancora le pagine HTML dei plugin (`/web/ConfigurationPage?name=`, **anonima**: l'HTML non deve contenere dati). Con `EnableInMainMenu` la pagina compare nel menu laterale sotto "Plugin" (l'icona `MenuIcon` è ignorata nella 10.11). Forma della pagina come nel template ufficiale (`jellyfin-plugin-template`): `div` con `data-role="page" class="page type-interior pluginConfigurationPage"`, script dentro la pagina, oggetti globali `ApiClient` e `Dashboard`. La risorsa incorporata si chiama `<RootNamespace>.Configuration.configPage.html`.
- **Test del plugin:** `FakeTimeProvider.Advance` esegue i timer scaduti in modo sincrono (un timer periodico scatta una volta per ogni periodo attraversato: per saltare 30 giorni si avanza **prima** di creare il timer). `InterfaceStub<T>` fa da stub per le interfacce di Jellyfin; i membri senza gestore restituiscono `null`/default. `new Movie { Id = … }` e `new Episode { Id = …, SeriesId = … }` si costruiscono nei test; `SessionInfo` ha il costruttore `(ISessionManager, ILogger)` e `FullNowPlayingItem` si imposta.
- **`System.Text.Json`:** `DateTimeOffset` si scrive in ISO-8601 (`2026-10-03T20:00:00+00:00`); i test non confrontano la stringa esatta della data (l'encoder potrebbe scrivere `+` come `+`), la leggono con `GetDateTimeOffset()`.
- **App, eventi:** `parsePartyEvent` (`party_channel_models.dart`) scrive una riga `info` per ogni tipo che non è in `socialEventTypes`: `InboxChanged` va aggiunto lì. `parseSocialEvent` scarta in silenzio i tipi che non conosce (così fanno le app 0.6.0 con `InboxChanged`).
- **App, disponibilità:** oggi `SocialAvailability.build` restituisce `SocialFeatures.none` senza chiamare `Info` se `syncPlayAccessProvider.canJoin` è falso. `WatchPartyDirectory` e `FriendsButton` controllano già da sé l'accesso ai watch party.
- **App, date:** `DateFormat.MMMd(localeName)` (`package:intl`) dà "3 ott" / "Oct 3". Nell'app e nei widget test i dati delle date li carica `GlobalMaterialLocalizations`; in un `test()` puro si chiama prima `initializeDateFormatting()` (`package:intl/date_symbol_data_local.dart`).
- **App, immagini:** gli endpoint immagine di Jellyfin sono anonimi e il parametro `tag` è facoltativo: `/Items/{id}/Images/Primary?maxWidth=…` dà l'immagine attuale. Nei widget test `pumpApp` sostituisce le immagini di rete con un riquadro grigio.
- **App, test:** `FakeSocialApi` **implementa** `SocialApi`: ogni metodo nuovo di `SocialApi` va aggiunto anche lì nello stesso task. `pumpApp` non va toccato (sovrascrivere due volte un provider è un errore). Le prove con la vera `AppShell` sovrascrivono `watchPartyEventsProvider` (vedi `test/features/friends/friends_shell_test.dart`).
- **Riverpod 3:** dentro `build` non si cambia lo stato (si usa `Future.microtask`); `ref.mounted` prima di usare `ref` dopo un `await`; un `Provider.autoDispose` letto solo con `ref.read` nasce e muore subito. Un `Notifier` si ricostruisce alla lettura successiva dopo il cambio di una dipendenza.
- **Flutter:** `Badge` (Material 3) per il numero sull'icona. Niente `CircularProgressIndicator` nei pannelli: con `pumpAndSettle` non finirebbe mai (mentre carica il pannello resta vuoto). `Focus(onFocusChange: …)` scatta anche quando il fuoco passa a un discendente.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InboxDtos.cs` | crea | voce, risposta di `GET Inbox`, corpi delle richieste |
| `…/Protocol/SocialEvent.cs`, `WatchPartyProtocol.cs` | modifica | `InboxChanged`, `Features` con `inbox` |
| `…/Api/InfoController.cs` | crea | `GET Info` per ogni utente autenticato |
| `…/Api/WatchPartyController.cs` | modifica | senza `GetInfo` |
| `…/Hub/InboxFile.cs`, `InboxBook.cs`, `InboxStore.cs` | crea | formato del file, regole, disco |
| `…/Hub/ILibraryAccess.cs`, `PartyNames.cs`, `InboxService.cs` | crea | libreria, titolo dal nome del gruppo, servizio |
| `…/Hub/PartyService.cs` | modifica | voci d'invito, `PartyNames` |
| `…/Server/JellyfinLibraryAccess.cs` | crea | adattatore |
| `…/Api/InboxController.cs` | crea | endpoint della cassetta e degli annunci |
| `…/Configuration/configPage.html`, `Plugin.cs`, `.csproj` | crea/modifica | pagina nella Dashboard, versione 1.2.0 |
| `…/PluginServiceRegistrator.cs`, `WatchPartyHostedService.cs` | modifica | servizi, caricamento e pulizia |
| `jellyfin-plugin-watch-party/README.md`, `meta.template.json` | modifica | descrizione |
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/*` | crea/modifica | test |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi della cassetta |
| `lib/core/party_channel/party_channel_models.dart` | modifica | `InboxChanged` scartato in silenzio dal canale |
| `lib/core/social/social_models.dart`, `inbox_models.dart`, `social_api.dart` | modifica/crea | funzione `inbox`, avviso, modelli, chiamate |
| `lib/core/jellyfin/image_urls.dart` | modifica | `primaryOf` (immagine da un id) |
| `lib/features/social/social_providers.dart` | modifica | `SocialFeatures.inbox`, `Info` anche senza watch party |
| `lib/features/settings/diagnostics.dart` | modifica | "notifiche" tra le funzioni |
| `lib/features/inbox/inbox_controller.dart`, `inbox_time.dart`, `inbox_panel.dart`, `inbox_button.dart` | crea | stato, ora relativa, pannello, icona e contenitore |
| `lib/app/shell_panels.dart`, `lib/ui/shell_side_panel.dart` | crea | pannello aperto, contenitore comune |
| `lib/features/friends/friends_panel.dart`, `friends_button.dart`, `lib/app/back_navigation.dart`, `lib/app/app_shell.dart` | modifica | stato unico dei pannelli, icona e pannello Notifiche |
| `test/support/social_fakes.dart` | modifica | cassetta finta, voci di prova |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–5):** plugin. **Poi ci si ferma** (Task 6: lo fa l'orchestratore, deploy sul server).
- **Gruppo B (Task 7–9):** testi, modelli e disponibilità nell'app.
- **Gruppo C (Task 10–11):** stato della cassetta e pannelli della shell.
- **Gruppo D (Task 12–13):** interfaccia.
- **Gruppo E (Task 14):** allineamento dello spec, verifica finale, build.

---

## Gruppo A — plugin

### Task 1: protocollo della cassetta, `Info` per tutti, versione 1.2.0

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InboxDtos.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/SocialEvent.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/InfoController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/WatchPartyController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ProtocolJsonTests.cs`, `InfoControllerTests.cs` (nuovo), `WatchPartyControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `ProtocolJsonTests.cs`, prima della chiusura della classe, aggiungi:

```csharp
    [Fact]
    public void InboxEntriesSkipTheFieldsOfOtherTypes()
    {
        var at = new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);
        var entry = new InboxEntry
        {
            Id = "e1",
            Seq = 3,
            Type = InboxEntryTypes.Announcement,
            CreatedAt = at,
            Text = "Stasera manutenzione",
        };

        var json = JsonDocument.Parse(JsonSerializer.Serialize(entry)).RootElement;

        Assert.Equal(
            new[] { "Id", "Seq", "Type", "CreatedAt", "Read", "Text" },
            json.EnumerateObject().Select(p => p.Name));
        Assert.Equal(3, json.GetProperty("Seq").GetInt64());
        Assert.Equal(at, json.GetProperty("CreatedAt").GetDateTimeOffset());
        Assert.False(json.GetProperty("Read").GetBoolean());
        Assert.Equal("{\"Entries\":[],\"Unread\":0}", JsonSerializer.Serialize(new InboxResponse([], 0)));
        Assert.Equal("{\"Recipients\":4}", JsonSerializer.Serialize(new AnnouncementResponse(4)));
        Assert.Equal("{\"Protocol\":1,\"Type\":\"InboxChanged\"}", JsonSerializer.Serialize(SocialEvent.InboxChanged()));
    }

    [Fact]
    public void InboxRequestsReadAnyCaseOfNames()
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        Assert.Equal(42L, JsonSerializer.Deserialize<InboxReadRequest>("{\"upTo\":42}", options)!.UpTo);
        Assert.Equal("ciao", JsonSerializer.Deserialize<AnnouncementRequest>("{\"text\":\"ciao\"}", options)!.Text);
    }
```

Crea `InfoControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Microsoft.AspNetCore.Authorization;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InfoControllerTests
{
    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = new InfoController().GetInfo().Value!;
        Assert.Equal("1.2.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends", "parties", "inbox" }, info.Features);
    }

    [Fact]
    public void InfoIsForEveryAuthenticatedUser()
    {
        // Nessuna policy: basta essere autenticati, anche senza accesso ai
        // watch party (la cassetta delle notifiche vale per tutti).
        var authorize = Assert.Single(typeof(InfoController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(InfoController).GetMethod(nameof(InfoController.GetInfo))!
            .GetCustomAttributes<AuthorizeAttribute>());
    }
}
```

In `WatchPartyControllerTests.cs` togli il test `InfoReportsVersionProtocolAndFeatures` (tutto il metodo con il suo `[Fact]`): `Info` non sta più in quel controller.

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`InboxEntry`, `InfoController`, `SocialEvent.InboxChanged` non esistono).

- [ ] **Step 3: DTO della cassetta**

Crea `Protocol/InboxDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Tipi delle voci della cassetta delle notifiche (spec G §6.2).</summary>
public static class InboxEntryTypes
{
    public const string Invite = "Invite";
    public const string Announcement = "Announcement";
}

/// <summary>
/// Una voce della cassetta delle notifiche (spec G §6.2): la stessa forma in
/// inbox.json e nelle risposte di GET Inbox. I campi di un tipo mancano
/// negli altri. Si cambia solo sotto il lock di InboxService; fuori di lì
/// girano copie (<see cref="Copy"/>).
/// </summary>
public sealed class InboxEntry
{
    [JsonPropertyName("Id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>Progressivo per utente: cresce a ogni voce nuova o aggiornata.</summary>
    [JsonPropertyName("Seq")]
    public long Seq { get; set; }

    [JsonPropertyName("Type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("CreatedAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("Read")]
    public bool Read { get; set; }

    /// <summary>Invite: il gruppo SyncPlay, in formato "N".</summary>
    [JsonPropertyName("GroupId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? GroupId { get; set; }

    /// <summary>Invite: chi ha invitato.</summary>
    [JsonPropertyName("FromName")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? FromName { get; set; }

    /// <summary>Invite: il titolo, dal nome del gruppo ("Host · Titolo").</summary>
    [JsonPropertyName("Title")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Title { get; set; }

    /// <summary>Invite: l'elemento della locandina (la serie, per un episodio), in formato "N".</summary>
    [JsonPropertyName("ImageItemId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ImageItemId { get; set; }

    /// <summary>Announcement: il testo dell'admin.</summary>
    [JsonPropertyName("Text")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Text { get; set; }

    public InboxEntry Copy() => (InboxEntry)MemberwiseClone();
}

/// <summary>Risposta di GET Inbox: le voci dalla più recente e quante non lette.</summary>
public sealed record InboxResponse(
    [property: JsonPropertyName("Entries")] IReadOnlyList<InboxEntry> Entries,
    [property: JsonPropertyName("Unread")] int Unread);

/// <summary>Corpo di POST Inbox/Read: segna lette le voci fino a questo Seq.</summary>
public sealed class InboxReadRequest
{
    [JsonPropertyName("UpTo")]
    public long UpTo { get; set; }
}

/// <summary>Corpo di POST Inbox/Announcements.</summary>
public sealed class AnnouncementRequest
{
    [JsonPropertyName("Text")]
    public string? Text { get; set; }
}

/// <summary>Risposta di POST Inbox/Announcements: a quanti utenti è arrivato.</summary>
public sealed record AnnouncementResponse(
    [property: JsonPropertyName("Recipients")] int Recipients);
```

- [ ] **Step 4: avviso `InboxChanged` e funzione `inbox`**

In `Protocol/SocialEvent.cs`, in `SocialEventTypes` dopo `PartyInvite`:

```csharp
    /// <summary>La cassetta delle notifiche dell'utente è cambiata (spec G §6.4).</summary>
    public const string InboxChanged = "InboxChanged";
```

e in `SocialEvent`, dopo il metodo `PartyInvite(...)`:

```csharp
    public static SocialEvent InboxChanged() => new() { Type = SocialEventTypes.InboxChanged };
```

In `Protocol/WatchPartyProtocol.cs` sostituisci il commento e il valore di `Features`:

```csharp
    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7, spec
    /// G §6.3). Il protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends", "parties", "inbox"];
```

- [ ] **Step 5: `InfoController` e versione**

Crea `Api/InfoController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// GET Info per ogni utente autenticato (spec G §7.2): la cassetta delle
/// notifiche vale anche per chi non ha accesso ai watch party. Non può
/// stare nei controller con la policy SyncPlay: un attributo sul metodo si
/// somma a quello della classe, non lo allarga.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class InfoController : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin, del protocollo e funzioni in più.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(PluginVersion, WatchPartyProtocol.Version, WatchPartyProtocol.Features);
}
```

In `Api/WatchPartyController.cs` togli la proprietà `PluginVersion` e il metodo `GetInfo` (con il suo commento `/// <summary>Versione del plugin, del protocollo e funzioni in più.</summary>` e l'attributo `[HttpGet("Info")]`). Il resto del controller non cambia.

Nel `.csproj` del plugin: `<Version>1.1.0</Version>` → `<Version>1.2.0</Version>`.

- [ ] **Step 6: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi (142: 139 − 1 tolto + 4 nuovi), nessun warning.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the inbox protocol and open Info to every user"
```

### Task 2: regole della cassetta (`InboxBook`) e formato del file

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/InboxFile.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/InboxBook.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InboxBookTests.cs`

- [ ] **Step 1: test che falliscono**

Crea `InboxBookTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InboxBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _mario = Guid.NewGuid();

    private static InboxEntry Announcement(string text, DateTimeOffset? at = null) =>
        new() { Type = InboxEntryTypes.Announcement, CreatedAt = at ?? Now, Text = text };

    [Fact]
    public void EntriesTakeIncreasingSeqAndListNewestFirst()
    {
        var book = new InboxBook();
        var first = book.Add(_mario, Announcement("uno"));
        var second = book.Add(_mario, Announcement("due"));

        Assert.Equal(1, first.Seq);
        Assert.Equal(2, second.Seq);
        Assert.NotEqual(first.Id, second.Id);
        Assert.Equal(new[] { "due", "uno" }, book.List(_mario).Select(e => e.Text));
        Assert.Empty(book.List(Guid.NewGuid()));
    }

    [Fact]
    public void ListGivesCopies()
    {
        var book = new InboxBook();
        book.Add(_mario, Announcement("uno"));
        book.List(_mario)[0].Read = true;
        Assert.False(book.List(_mario)[0].Read);
    }

    [Fact]
    public void BeyondTheLimitTheOldestGoes()
    {
        var book = new InboxBook();
        for (var i = 0; i <= InboxBook.MaxEntries; i++)
        {
            book.Add(_mario, Announcement($"n{i}"));
        }

        var entries = book.List(_mario);
        Assert.Equal(InboxBook.MaxEntries, entries.Count);
        Assert.DoesNotContain(entries, e => e.Text == "n0");
        Assert.Equal($"n{InboxBook.MaxEntries}", entries[0].Text);
    }

    [Fact]
    public void ASecondInviteToTheSameGroupUpdatesTheEntry()
    {
        var book = new InboxBook();
        var invite = book.UpsertInvite(_mario, "g1", "Luigi", "Dune", "m1", Now);
        book.Add(_mario, Announcement("in mezzo"));
        book.MarkRead(_mario, long.MaxValue);

        var again = book.UpsertInvite(_mario, "G1", "Peach", "Dune", "m1", Now.AddMinutes(5));

        Assert.Equal(invite.Id, again.Id);
        Assert.Equal(3, again.Seq);
        var entries = book.List(_mario);
        Assert.Equal(2, entries.Count);
        Assert.Equal(invite.Id, entries[0].Id);
        Assert.Equal("Peach", entries[0].FromName);
        Assert.Equal(Now.AddMinutes(5), entries[0].CreatedAt);
        Assert.False(entries[0].Read);
        Assert.True(entries[1].Read);
    }

    [Fact]
    public void MarkReadStopsAtUpTo()
    {
        var book = new InboxBook();
        book.Add(_mario, Announcement("uno"));
        book.Add(_mario, Announcement("due"));

        Assert.True(book.MarkRead(_mario, 1));
        Assert.Equal(new[] { false, true }, book.List(_mario).Select(e => e.Read));
        Assert.False(book.MarkRead(_mario, 1));
        Assert.False(book.MarkRead(Guid.NewGuid(), 5));
    }

    [Fact]
    public void RemoveAndClear()
    {
        var book = new InboxBook();
        var first = book.Add(_mario, Announcement("uno"));
        book.Add(_mario, Announcement("due"));

        Assert.True(book.Remove(_mario, first.Id));
        Assert.False(book.Remove(_mario, first.Id));
        Assert.Single(book.List(_mario));
        Assert.True(book.Clear(_mario));
        Assert.False(book.Clear(_mario));
        Assert.Empty(book.List(_mario));
        // Il Seq continua: una voce nuova non riusa quelli già visti dall'app.
        Assert.Equal(3, book.Add(_mario, Announcement("tre")).Seq);
    }

    [Fact]
    public void PruneDropsOldEntriesAndMissingUsers()
    {
        var book = new InboxBook();
        var luigi = Guid.NewGuid();
        book.Add(_mario, Announcement("vecchia", Now.AddDays(-31)));
        book.Add(_mario, Announcement("nuova", Now));
        book.Add(luigi, Announcement("di Luigi"));

        Assert.Equal(2, book.Prune(Now.AddDays(-30), id => id == _mario));

        Assert.Equal(new[] { "nuova" }, book.List(_mario).Select(e => e.Text));
        Assert.Empty(book.List(luigi));
    }

    [Fact]
    public void TheFileRoundTripsAndKeepsTheSeq()
    {
        var book = new InboxBook();
        book.UpsertInvite(_mario, "g1", "Luigi", "Dune", "m1", Now);
        book.Add(_mario, Announcement("ciao"));
        book.Clear(_mario);
        book.Add(_mario, Announcement("dopo"));

        var copy = InboxBook.FromFile(book.ToFile());

        Assert.Equal(new[] { "dopo" }, copy.List(_mario).Select(e => e.Text));
        Assert.Equal(4, copy.Add(_mario, Announcement("ancora")).Seq);
    }

    [Fact]
    public void ABadFileIsRefused()
    {
        var mario = _mario.ToString("N");
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { ["x"] = new InboxFileUser() } }));
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { [mario] = null } }));
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { [mario] = new InboxFileUser { Entries = [null] } } }));
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { [mario] = new InboxFileUser { Entries = [new InboxEntry()] } } }));
    }
}
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`InboxBook`, `InboxFile` non esistono).

- [ ] **Step 3: formato del file**

Crea `Hub/InboxFile.cs`:

```csharp
using System.Text.Json.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Contenuto di inbox.json (spec G §6.1). Id utente in formato "N". Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="InboxBook.FromFile"/>.
/// </summary>
public sealed class InboxFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Users")]
    public Dictionary<string, InboxFileUser?>? Users { get; set; } = [];
}

/// <summary>La cassetta di un utente, nel file.</summary>
public sealed class InboxFileUser
{
    /// <summary>Il prossimo Seq da dare.</summary>
    [JsonPropertyName("NextSeq")]
    public long NextSeq { get; set; } = 1;

    [JsonPropertyName("Entries")]
    public List<InboxEntry?>? Entries { get; set; } = [];
}
```

- [ ] **Step 4: le regole**

Crea `Hub/InboxBook.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Le cassette delle notifiche in memoria (spec G §6.1–6.2, §6.5): voci,
/// Seq, letture, limiti, inviti che si aggiornano. Non è sicuro tra
/// thread: lo usa solo InboxService, sotto lock.
/// </summary>
public sealed class InboxBook
{
    /// <summary>Voci al massimo per utente: oltre si toglie quella con il Seq più basso.</summary>
    public const int MaxEntries = 100;

    private readonly Dictionary<Guid, UserInbox> _users = [];

    /// <summary>Le voci dell'utente dalla più recente (Seq più alto), come copie.</summary>
    public IReadOnlyList<InboxEntry> List(Guid userId) =>
        _users.TryGetValue(userId, out var inbox)
            ? inbox.Entries.OrderByDescending(e => e.Seq).Select(e => e.Copy()).ToList()
            : [];

    /// <summary>Aggiunge una voce, che prende il Seq (e un Id se non l'ha); restituisce una copia.</summary>
    public InboxEntry Add(Guid userId, InboxEntry entry)
    {
        var inbox = Inbox(userId);
        if (string.IsNullOrEmpty(entry.Id))
        {
            entry.Id = Guid.NewGuid().ToString("N");
        }

        entry.Seq = inbox.NextSeq++;
        inbox.Entries.Add(entry);
        if (inbox.Entries.Count > MaxEntries)
        {
            inbox.Entries.Remove(inbox.Entries.MinBy(e => e.Seq)!);
        }

        return entry.Copy();
    }

    /// <summary>
    /// L'invito al gruppo (spec G §6.5): se l'utente ne ha già uno per lo
    /// stesso gruppo lo aggiorna (mittente, ora, di nuovo non letto, Seq
    /// nuovo: torna in cima), altrimenti lo aggiunge. Restituisce una copia.
    /// </summary>
    public InboxEntry UpsertInvite(
        Guid userId, string groupId, string fromName, string title, string imageItemId, DateTimeOffset now)
    {
        var inbox = Inbox(userId);
        var existing = inbox.Entries.FirstOrDefault(e =>
            e.Type == InboxEntryTypes.Invite && string.Equals(e.GroupId, groupId, StringComparison.OrdinalIgnoreCase));
        if (existing is null)
        {
            return Add(userId, new InboxEntry
            {
                Type = InboxEntryTypes.Invite,
                CreatedAt = now,
                GroupId = groupId,
                FromName = fromName,
                Title = title,
                ImageItemId = imageItemId,
            });
        }

        existing.FromName = fromName;
        existing.Title = title;
        existing.ImageItemId = imageItemId;
        existing.CreatedAt = now;
        existing.Read = false;
        existing.Seq = inbox.NextSeq++;
        return existing.Copy();
    }

    /// <summary>Segna lette le voci con Seq fino a upTo; true se qualcosa è cambiato.</summary>
    public bool MarkRead(Guid userId, long upTo)
    {
        if (!_users.TryGetValue(userId, out var inbox))
        {
            return false;
        }

        var changed = false;
        foreach (var entry in inbox.Entries.Where(e => !e.Read && e.Seq <= upTo))
        {
            entry.Read = true;
            changed = true;
        }

        return changed;
    }

    /// <summary>Toglie una voce; true se c'era.</summary>
    public bool Remove(Guid userId, string entryId) =>
        _users.TryGetValue(userId, out var inbox)
        && inbox.Entries.RemoveAll(e => string.Equals(e.Id, entryId, StringComparison.OrdinalIgnoreCase)) > 0;

    /// <summary>Svuota la cassetta (il Seq continua da dov'era); true se c'era qualcosa.</summary>
    public bool Clear(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var inbox) || inbox.Entries.Count == 0)
        {
            return false;
        }

        inbox.Entries.Clear();
        return true;
    }

    /// <summary>
    /// Toglie le voci create prima di cutoff e le cassette degli utenti che
    /// non esistono più; restituisce quante voci ha tolto.
    /// </summary>
    public int Prune(DateTimeOffset cutoff, Func<Guid, bool> userExists)
    {
        var removed = 0;
        foreach (var (userId, inbox) in _users.ToList())
        {
            if (!userExists(userId))
            {
                removed += inbox.Entries.Count;
                _users.Remove(userId);
                continue;
            }

            removed += inbox.Entries.RemoveAll(e => e.CreatedAt < cutoff);
        }

        return removed;
    }

    /// <summary>Dal file; FormatException se un utente o una voce non è valida.</summary>
    public static InboxBook FromFile(InboxFile file)
    {
        var book = new InboxBook();
        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("cassetta di un utente non valida");
            }

            var inbox = book.Inbox(userId);
            foreach (var entry in value.Entries ?? [])
            {
                if (entry is null || string.IsNullOrEmpty(entry.Id) || string.IsNullOrEmpty(entry.Type))
                {
                    throw new FormatException("voce non valida");
                }

                inbox.Entries.Add(entry);
            }

            // Un NextSeq scritto a mano non deve ridare un Seq già usato.
            inbox.NextSeq = Math.Max(value.NextSeq, inbox.Entries.Select(e => e.Seq).DefaultIfEmpty(0).Max() + 1);
        }

        return book;
    }

    public InboxFile ToFile() => new()
    {
        Users = _users.ToDictionary(
            pair => pair.Key.ToString("N"),
            pair => (InboxFileUser?)new InboxFileUser
            {
                NextSeq = pair.Value.NextSeq,
                Entries = pair.Value.Entries.OrderBy(e => e.Seq).Select(e => (InboxEntry?)e.Copy()).ToList(),
            }),
    };

    private UserInbox Inbox(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var inbox))
        {
            inbox = new UserInbox();
            _users[userId] = inbox;
        }

        return inbox;
    }

    private sealed class UserInbox
    {
        public long NextSeq { get; set; } = 1;

        public List<InboxEntry> Entries { get; } = [];
    }
}
```

- [ ] **Step 5: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the inbox rules"
```

### Task 3: cassetta su disco (`InboxStore`)

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/InboxStore.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/TempFolder.cs`
- Test: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InboxStoreTests.cs`

- [ ] **Step 1: test che falliscono**

In `TempFolder.cs`, dopo `FriendsFile`:

```csharp
    /// <summary>Percorso di inbox.json, accanto a friends.json.</summary>
    public string InboxFile => System.IO.Path.Combine(Path, "WonderFlixWatchParty", "inbox.json");
```

Crea `InboxStoreTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxStoreTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private InboxStore Store() => new(_folder.InboxFile, NullLogger<InboxStore>.Instance);

    [Fact]
    public void MissingFileIsEmpty()
    {
        Assert.Empty(Store().Load().List(Guid.NewGuid()));
        Assert.False(File.Exists(_folder.InboxFile));
    }

    [Fact]
    public void SaveCreatesTheFolderAndLoadReadsItBack()
    {
        var mario = Guid.NewGuid();
        var book = new InboxBook();
        book.Add(mario, new InboxEntry { Type = InboxEntryTypes.Announcement, CreatedAt = Now, Text = "ciao" });

        Store().Save(book);

        Assert.True(File.Exists(_folder.InboxFile));
        Assert.False(File.Exists(_folder.InboxFile + ".tmp"));
        var entry = Assert.Single(Store().Load().List(mario));
        Assert.Equal("ciao", entry.Text);
        Assert.Equal(Now, entry.CreatedAt);
    }

    [Fact]
    public void UnreadableFileIsMovedAsideAndStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.InboxFile)!);
        File.WriteAllText(_folder.InboxFile, "{ non è json");

        Assert.Empty(Store().Load().List(Guid.NewGuid()));

        Assert.False(File.Exists(_folder.InboxFile));
        Assert.Equal("{ non è json", File.ReadAllText(_folder.InboxFile + ".bad"));
    }

    [Fact]
    public void NullEntriesAreMovedAsideToo()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.InboxFile)!);
        File.WriteAllText(
            _folder.InboxFile,
            "{\"Version\":1,\"Users\":{\"" + Guid.NewGuid().ToString("N") + "\":{\"NextSeq\":1,\"Entries\":[null]}}}");

        Store().Load();

        Assert.True(File.Exists(_folder.InboxFile + ".bad"));
    }

    [Fact]
    public void DefaultPathIsNextToTheFriends()
    {
        var (paths, stub) = InterfaceStub<IApplicationPaths>.Create();
        stub.Handlers["get_PluginConfigurationsPath"] = _ => Path.Combine("data", "plugins", "configurations");
        Assert.Equal(
            Path.Combine("data", "plugins", "configurations", "WonderFlixWatchParty", "inbox.json"),
            InboxStore.DefaultPath(paths));
    }
}
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`InboxStore` non esiste).

- [ ] **Step 3: il file su disco**

Crea `Hub/InboxStore.cs`:

```csharp
using System.Text.Json;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// inbox.json su disco (spec G §6.1), accanto a friends.json nelle
/// configurazioni dei plugin. Non è sicuro tra thread: lo usa solo
/// InboxService, sotto lock.
/// </summary>
public sealed class InboxStore(string filePath, ILogger<InboxStore> logger)
{
    public const string FileName = "inbox.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// inbox.json.bad e si riparte vuoti.
    /// </summary>
    public InboxBook Load()
    {
        if (!File.Exists(FilePath))
        {
            return new InboxBook();
        }

        try
        {
            var file = JsonSerializer.Deserialize<InboxFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return InboxBook.FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            File.Move(FilePath, bad, overwrite: true);
            logger.LogWarning(ex, "Cassetta delle notifiche illeggibile: file spostato in {Path}, si riparte vuoti", bad);
            return new InboxBook();
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(InboxBook book)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, book.ToFile(), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia inbox.json vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }
}
```

- [ ] **Step 4: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): keep the inbox on disk"
```

### Task 4: `InboxService`, libreria e voci d'invito

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/ILibraryAccess.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyNames.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/InboxService.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/PartyService.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FakeServer.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/TestInbox.cs`
- Test: `InboxServiceTests.cs` (nuovo), `PartyServiceTests.cs`; costruttori di `PartyService` in `PartyAnnouncerTests.cs`, `PartiesControllerTests.cs`, `FriendsControllerTests.cs`, `WatchPartyHostedServiceTests.cs`

- [ ] **Step 1: server finto con la libreria e cassetta di prova**

In `FakeServer.cs` la classe implementa anche `ILibraryAccess`:

```csharp
internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender, IUserDirectory, ILibraryAccess
```

e, prima di `TrySendAsync`, aggiungi:

```csharp
    /// <summary>Elemento in riproduzione per sessione (spec G §6.5).</summary>
    public Dictionary<string, PlayingItem> Playing { get; } = [];

    /// <summary>Coppie (utente, elemento) che l'utente non può vedere (librerie o limiti d'età).</summary>
    public HashSet<(Guid UserId, Guid ItemId)> Unseen { get; } = [];

    /// <summary>Se true, la libreria lancia, come un errore di Jellyfin.</summary>
    public bool LibraryFails { get; set; }

    public PlayingItem? NowPlaying(string sessionId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile")
        : Exists(sessionId) ? Playing.GetValueOrDefault(sessionId) : null;

    public bool CanSee(Guid userId, Guid itemId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile")
        : Users.ContainsKey(userId) && !Unseen.Contains((userId, itemId));
```

Crea `TestInbox.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>La cassetta delle notifiche dei test: server finto e file in una cartella temporanea.</summary>
internal static class TestInbox
{
    public static InboxService Create(FakeServer server, TempFolder folder, TimeProvider time) =>
        new(
            new InboxStore(folder.InboxFile, NullLogger<InboxStore>.Instance),
            server, server, server, server, time, NullLogger<InboxService>.Instance);
}
```

- [ ] **Step 2: test che falliscono**

Crea `InboxServiceTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly CallerSession _marioSession;

    public InboxServiceTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _marioSession = _server.AddSession("s-mario", _mario);
        _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose() => _folder.Dispose();

    private static string Type(string payload) => JsonDocument.Parse(payload).RootElement.GetProperty("Type").GetString()!;

    private static GroupSummary Group(params string[] participants) =>
        new(Guid.NewGuid(), "Mario · Dune", "Playing", participants);

    [Fact]
    public async Task AnnouncementsReachEveryActiveUser()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);

        var result = await _inbox.AnnounceAsync("  Stasera manutenzione  ");

        Assert.Equal(HubStatus.Ok, result.Status);
        Assert.Equal(2, result.Value!.Recipients);
        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.Announcement, entry.Type);
        Assert.Equal("Stasera manutenzione", entry.Text);
        Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);
        Assert.Equal(1, _inbox.Get(_luigi.Id).Unread);
        Assert.Empty(_inbox.Get(bowser.Id).Entries);
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-luigi").Select(Type));
    }

    [Fact]
    public async Task AnnouncementsNeedOneTo500Characters()
    {
        Assert.Equal(HubStatus.Invalid, (await _inbox.AnnounceAsync(null)).Status);
        Assert.Equal(HubStatus.Invalid, (await _inbox.AnnounceAsync("   ")).Status);
        Assert.Equal(HubStatus.Invalid, (await _inbox.AnnounceAsync(new string('a', 501))).Status);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(HubStatus.Ok, (await _inbox.AnnounceAsync(new string('a', 500))).Status);
        // Punti di codice, non unità UTF-16: 500 emoji passano.
        Assert.Equal(HubStatus.Ok, (await _inbox.AnnounceAsync(string.Concat(Enumerable.Repeat("😂", 500)))).Status);
    }

    [Fact]
    public async Task ReadingRemovingAndClearingNotifyOnlyOnChange()
    {
        await _inbox.AnnounceAsync("uno");
        await _inbox.AnnounceAsync("due");
        _server.Sent.Clear();
        var entries = _inbox.Get(_mario.Id).Entries;

        await _inbox.MarkReadAsync(_mario.Id, entries[1].Seq);
        Assert.Equal(1, _inbox.Get(_mario.Id).Unread);
        await _inbox.MarkReadAsync(_mario.Id, entries[1].Seq);
        Assert.Single(_server.SentTo("s-mario"));
        Assert.Empty(_server.SentTo("s-luigi"));

        await _inbox.RemoveAsync(_mario.Id, entries[0].Id);
        await _inbox.RemoveAsync(_mario.Id, entries[0].Id);
        await _inbox.RemoveAsync(_mario.Id, null);
        Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(2, _server.SentTo("s-mario").Count);

        await _inbox.ClearAsync(_mario.Id);
        await _inbox.ClearAsync(_mario.Id);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(3, _server.SentTo("s-mario").Count);
        Assert.Equal(2, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task EntriesSurviveARestart()
    {
        await _inbox.AnnounceAsync("ciao");

        var again = TestInbox.Create(_server, _folder, _time);

        Assert.Equal("ciao", Assert.Single(again.Get(_mario.Id).Entries).Text);
    }

    [Fact]
    public async Task CleanupDropsOldEntriesAndDeletedUsers()
    {
        await _inbox.AnnounceAsync("vecchio");
        _time.Advance(TimeSpan.FromDays(20));
        await _inbox.AnnounceAsync("recente");
        _time.Advance(TimeSpan.FromDays(11));
        _server.Users.Remove(_luigi.Id);

        Assert.Equal(3, _inbox.Cleanup());

        Assert.Equal(new[] { "recente" }, _inbox.Get(_mario.Id).Entries.Select(e => e.Text));
        Assert.Empty(_inbox.Get(_luigi.Id).Entries);
    }

    [Fact]
    public async Task InvitesNeedAPlayingItemTheInviteeCanSee()
    {
        var group = Group("Mario");
        var peach = _server.AddUser("Peach");

        // Niente in riproduzione: nessuna voce.
        await _inbox.AddInvitesAsync(_marioSession, group, [_luigi.Id]);
        Assert.Empty(_inbox.Get(_luigi.Id).Entries);

        var movie = Guid.NewGuid();
        var poster = Guid.NewGuid();
        _server.Playing["s-mario"] = new PlayingItem(movie, poster);
        // Peach non ha accesso alla libreria del film.
        _server.Unseen.Add((peach.Id, movie));
        await _inbox.AddInvitesAsync(_marioSession, group, [_luigi.Id, peach.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(InboxEntryTypes.Invite, entry.Type);
        Assert.Equal(group.Id.ToString("N"), entry.GroupId);
        Assert.Equal("Mario", entry.FromName);
        Assert.Equal("Dune", entry.Title);
        Assert.Equal(poster.ToString("N"), entry.ImageItemId);
        Assert.False(entry.Read);
        Assert.Empty(_inbox.Get(peach.Id).Entries);
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-luigi").Select(Type));
    }

    [Fact]
    public async Task ThePlayingItemCanComeFromAnotherParticipant()
    {
        var peach = _server.AddUser("Peach");
        var movie = Guid.NewGuid();
        _server.Playing["s-luigi"] = new PlayingItem(movie, movie);

        await _inbox.AddInvitesAsync(_marioSession, Group("Mario", "Luigi"), [peach.Id]);

        Assert.Single(_inbox.Get(peach.Id).Entries);
    }

    [Fact]
    public async Task ALibraryErrorLeavesNoEntryAndDoesNotThrow()
    {
        _server.Playing["s-mario"] = new PlayingItem(Guid.NewGuid(), Guid.NewGuid());
        _server.LibraryFails = true;

        await _inbox.AddInvitesAsync(_marioSession, Group("Mario"), [_luigi.Id]);

        Assert.Empty(_inbox.Get(_luigi.Id).Entries);
        Assert.Empty(_server.SentTo("s-luigi"));
    }
}
```

In `PartyServiceTests.cs`:
- aggiungi il campo `private readonly InboxService _inbox;` (dopo `_announcer`);
- nel costruttore, prima di `_service = new PartyService(`, aggiungi `_inbox = TestInbox.Create(_server, _folder, _time);`;
- nella creazione di `_service` sostituisci `new RateLimiter(_time), NullLogger<PartyService>.Instance);` con `new RateLimiter(_time), _inbox, NullLogger<PartyService>.Instance);`;
- dopo il test `InvitesReachOnlySessionsThatCanSeeTheGroup` aggiungi:

```csharp
    [Fact]
    public async Task InvitesAlsoLeaveAnEntryInTheInbox()
    {
        await MakeFriends(_mario, _luigi);
        _service.Register(_marioSession, _group, PartyModes.Private);
        var movie = Guid.NewGuid();
        _server.Playing["s-mario"] = new PlayingItem(movie, movie);
        _server.Sent.Clear();

        await _service.InviteAsync(_marioSession, _group, [_luigi.Id.ToString("N")]);

        Assert.Equal(new[] { "PartyInvite", "InboxChanged" }, _server.SentTo("s-luigi").Select(Type));
        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(GroupN, entry.GroupId);
        Assert.Equal("Mario", entry.FromName);
        Assert.Equal("Dune", entry.Title);
    }
```

Negli altri test che costruiscono `PartyService` passa una cassetta di prova, subito prima del logger:
- `PartyAnnouncerTests.cs`, `PartiesControllerTests.cs`, `FriendsControllerTests.cs`: `new RateLimiter(_time), NullLogger<PartyService>.Instance);` → `new RateLimiter(_time), TestInbox.Create(_server, _folder, _time), NullLogger<PartyService>.Instance);`
- `WatchPartyHostedServiceTests.cs` (due volte): `new RateLimiter(time), NullLogger<PartyService>.Instance);` → `new RateLimiter(time), TestInbox.Create(server, folder, time), NullLogger<PartyService>.Instance);`

- [ ] **Step 3: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`ILibraryAccess`, `PlayingItem`, `InboxService` non esistono).

- [ ] **Step 4: libreria e nome dei gruppi**

Crea `Hub/ILibraryAccess.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un elemento in riproduzione: il suo id e quello della locandina (la serie, per un episodio).</summary>
public sealed record PlayingItem(Guid ItemId, Guid ImageItemId);

/// <summary>
/// La libreria come serve alla cassetta delle notifiche (adattatore di
/// ISessionManager, ILibraryManager e IUserManager).
/// </summary>
public interface ILibraryAccess
{
    /// <summary>L'elemento in riproduzione nella sessione; null se nessuno o se la sessione non c'è.</summary>
    PlayingItem? NowPlaying(string sessionId);

    /// <summary>
    /// L'utente può vedere l'elemento (librerie e limiti d'età del profilo),
    /// anche senza una sessione aperta; false se uno dei due non esiste.
    /// </summary>
    bool CanSee(Guid userId, Guid itemId);
}
```

Crea `Hub/PartyNames.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Il nome che l'app dà ai gruppi SyncPlay: "Host · Titolo".</summary>
public static class PartyNames
{
    /// <summary>Tra host e titolo.</summary>
    public const string Separator = " · ";

    /// <summary>Il titolo da "Host · Titolo"; il nome intero se non ha quella forma.</summary>
    public static string TitleOf(string name)
    {
        var separator = name.IndexOf(Separator, StringComparison.Ordinal);
        return separator < 0 ? name : name[(separator + Separator.Length)..];
    }
}
```

- [ ] **Step 5: il servizio**

Crea `Hub/InboxService.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// La cassetta delle notifiche (spec G §6): voci su disco con
/// <see cref="InboxStore"/>, letture e cancellazioni, annunci dell'admin,
/// voci d'invito, pulizia e avviso InboxChanged alle sessioni WonderFlix
/// dell'utente. Sicuro tra thread.
/// </summary>
public sealed class InboxService(
    InboxStore store,
    IUserDirectory users,
    ISessionDirectory sessions,
    IEventSender sender,
    ILibraryAccess library,
    TimeProvider time,
    ILogger<InboxService> logger)
{
    /// <summary>Quanto resta una voce (spec G §6.1).</summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    /// <summary>Lunghezza massima di un annuncio, in punti di codice (spec G §6.7).</summary>
    public const int MaxAnnouncementLength = 500;

    private readonly Lock _lock = new();
    private InboxBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private InboxBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Cassetta delle notifiche in {Path}", store.FilePath);
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

    /// <summary>Le voci dell'utente dalla più recente e quante non lette.</summary>
    public InboxResponse Get(Guid userId)
    {
        lock (_lock)
        {
            var entries = Book.List(userId);
            return new InboxResponse(entries, entries.Count(e => !e.Read));
        }
    }

    /// <summary>Segna lette le voci fino a upTo.</summary>
    public Task MarkReadAsync(Guid userId, long upTo) =>
        ChangeAsync(userId, book => book.MarkRead(userId, upTo));

    /// <summary>Toglie una voce; niente se non c'è (si può ripetere).</summary>
    public Task RemoveAsync(Guid userId, string? entryId) =>
        string.IsNullOrWhiteSpace(entryId)
            ? Task.CompletedTask
            : ChangeAsync(userId, book => book.Remove(userId, entryId));

    public Task ClearAsync(Guid userId) => ChangeAsync(userId, book => book.Clear(userId));

    /// <summary>
    /// Un annuncio dell'admin a ogni utente attivo (spec G §6.7). Invalid se
    /// il testo, senza spazi ai bordi, è vuoto o più lungo di
    /// <see cref="MaxAnnouncementLength"/>.
    /// </summary>
    public async Task<HubResult<AnnouncementResponse>> AnnounceAsync(string? text)
    {
        var trimmed = text?.Trim() ?? string.Empty;
        var length = trimmed.EnumerateRunes().Count();
        if (length == 0 || length > MaxAnnouncementLength)
        {
            return HubResult<AnnouncementResponse>.Fail(HubStatus.Invalid);
        }

        var recipients = users.GetUsers().Where(u => u.Enabled).Select(u => u.Id).ToList();
        var now = time.GetUtcNow();
        lock (_lock)
        {
            foreach (var userId in recipients)
            {
                Book.Add(userId, new InboxEntry { Type = InboxEntryTypes.Announcement, CreatedAt = now, Text = trimmed });
            }

            Persist();
        }

        logger.LogDebug("Annuncio a {Count} utenti", recipients.Count);
        await NotifyAsync(recipients).ConfigureAwait(false);
        return HubResult<AnnouncementResponse>.Ok(new AnnouncementResponse(recipients.Count));
    }

    /// <summary>
    /// Le voci d'invito (spec G §6.5), solo per gli invitati che possono
    /// vedere l'elemento in riproduzione nel party: quello della sessione di
    /// chi invita o, se lì non c'è, di un altro partecipante con l'app.
    /// Senza elemento, nessuna voce. Non lancia: un errore finisce nel log.
    /// </summary>
    public async Task AddInvitesAsync(CallerSession inviter, GroupSummary group, IReadOnlyList<Guid> invitees)
    {
        if (invitees.Count == 0)
        {
            return;
        }

        List<Guid> allowed;
        try
        {
            var playing = FindPlaying(inviter, group);
            if (playing is null)
            {
                logger.LogDebug("Inviti al watch party {GroupId}: niente in riproduzione, nessuna voce", group.Id);
                return;
            }

            allowed = invitees.Where(userId => library.CanSee(userId, playing.ItemId)).ToList();
            var groupId = group.Id.ToString("N");
            var title = PartyNames.TitleOf(group.Name);
            var image = playing.ImageItemId.ToString("N");
            var now = time.GetUtcNow();
            lock (_lock)
            {
                foreach (var userId in allowed)
                {
                    Book.UpsertInvite(userId, groupId, inviter.UserName, title, image, now);
                }

                if (allowed.Count > 0)
                {
                    Persist();
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci d'invito al watch party {GroupId} non create", group.Id);
            return;
        }

        logger.LogDebug("Voci d'invito al watch party {GroupId}: {Count}", group.Id, allowed.Count);
        await NotifyAsync(allowed).ConfigureAwait(false);
    }

    /// <summary>
    /// Toglie le voci più vecchie di <see cref="MaxAge"/> e le cassette degli
    /// utenti cancellati da Jellyfin; restituisce quante voci.
    /// </summary>
    public int Cleanup()
    {
        lock (_lock)
        {
            var removed = Book.Prune(time.GetUtcNow() - MaxAge, userId => users.GetUser(userId) is not null);
            if (removed > 0)
            {
                Persist();
            }

            return removed;
        }
    }

    private PlayingItem? FindPlaying(CallerSession inviter, GroupSummary group)
    {
        var playing = library.NowPlaying(inviter.SessionId);
        if (playing is not null)
        {
            return playing;
        }

        foreach (var session in sessions.GetAppSessions())
        {
            if (session.SessionId == inviter.SessionId
                || !group.Participants.Contains(session.UserName, StringComparer.OrdinalIgnoreCase))
            {
                continue;
            }

            playing = library.NowPlaying(session.SessionId);
            if (playing is not null)
            {
                return playing;
            }
        }

        return null;
    }

    private async Task ChangeAsync(Guid userId, Func<InboxBook, bool> change)
    {
        bool changed;
        lock (_lock)
        {
            changed = change(Book);
            if (changed)
            {
                Persist();
            }
        }

        if (changed)
        {
            await NotifyAsync([userId]).ConfigureAwait(false);
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
            logger.LogWarning(ex, "Cassetta delle notifiche non salvata in {Path}", store.FilePath);
        }
    }

    private Task NotifyAsync(IReadOnlyCollection<Guid> userIds)
    {
        var payload = JsonSerializer.Serialize(SocialEvent.InboxChanged());
        var targets = sessions.GetAppSessions()
            .Where(s => userIds.Contains(s.UserId))
            .Select(s => s.SessionId)
            .ToList();
        return Task.WhenAll(targets.Select(sessionId => SendAsync(sessionId, payload)));
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
            logger.LogWarning(ex, "Avviso della cassetta non inviato alla sessione {SessionId}", sessionId);
        }
    }
}
```

- [ ] **Step 6: gli inviti finiscono nella cassetta**

In `Hub/PartyService.cs`:

1. Nel costruttore primario, dopo `RateLimiter limiter,` aggiungi `InboxService inbox,` (prima di `ILogger<PartyService> logger`).
2. Togli la costante `GroupNameSeparator` (con il suo commento) e il metodo privato `TitleOf` (con il suo commento) in fondo alla classe; in `PartyOf` sostituisci `TitleOf(group.Name)` con `PartyNames.TitleOf(group.Name)`.
3. Il commento di `InviteAsync` diventa:

```csharp
    /// <summary>
    /// Invita amici di caller che non sono nel party; gli altri id si saltano.
    /// Oltre il limite invita quelli che ci stanno e risponde RateLimited.
    /// L'avviso va solo alle sessioni degli invitati che vedono il gruppo:
    /// dalle altre (niente accesso alla libreria della coda) non si entra.
    /// Gli invitati che possono vedere il titolo trovano anche la voce nella
    /// cassetta delle notifiche (spec G §6.5).
    /// </summary>
```

e, dopo `await Task.WhenAll(invitees.Select(sessionId => SendAsync(sessionId, payload))).ConfigureAwait(false);`, aggiungi:

```csharp
        await inbox.AddInvitesAsync(caller, group, targets).ConfigureAwait(false);
```

- [ ] **Step 7: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

- [ ] **Step 8: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the inbox service with announcements and invite entries"
```

### Task 5: adattatore, endpoint, pagina nella Dashboard, servizi

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinLibraryAccess.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/InboxController.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/configPage.html`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Plugin.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `PluginServiceRegistrator.cs`, `WatchPartyHostedService.cs`
- Modify: `jellyfin-plugin-watch-party/README.md`, `jellyfin-plugin-watch-party/meta.template.json`
- Test: `ServerAdapterTests.cs`, `InboxControllerTests.cs` (nuovo), `PluginPagesTests.cs` (nuovo), `ServiceRegistrationTests.cs`, `WatchPartyHostedServiceTests.cs`

- [ ] **Step 1: test che falliscono**

In `ServerAdapterTests.cs` aggiungi gli `using` `MediaBrowser.Controller.Entities.Movies;` e `MediaBrowser.Controller.Entities.TV;` e, prima della chiusura della classe:

```csharp
    [Fact]
    public void ThePlayingItemComesFromTheSessionWithTheSeriesPoster()
    {
        var movie = new Movie { Id = Guid.NewGuid() };
        var episode = new Episode { Id = Guid.NewGuid(), SeriesId = Guid.NewGuid() };
        var (manager, stub) = InterfaceStub<ISessionManager>.Create();
        var withMovie = Session("s-1", "d1", "WonderFlix", Guid.NewGuid(), "Mario");
        withMovie.FullNowPlayingItem = movie;
        var withEpisode = Session("s-2", "d2", "WonderFlix", Guid.NewGuid(), "Luigi");
        withEpisode.FullNowPlayingItem = episode;
        var idle = Session("s-3", "d3", "WonderFlix", Guid.NewGuid(), "Peach");
        stub.Handlers["get_Sessions"] = _ => new[] { withMovie, withEpisode, idle };
        var access = new JellyfinLibraryAccess(
            manager, InterfaceStub<ILibraryManager>.Create().Proxy, InterfaceStub<IUserManager>.Create().Proxy);

        Assert.Equal(new PlayingItem(movie.Id, movie.Id), access.NowPlaying("s-1"));
        Assert.Equal(new PlayingItem(episode.Id, episode.SeriesId), access.NowPlaying("s-2"));
        Assert.Null(access.NowPlaying("s-3"));
        Assert.Null(access.NowPlaying("s-x"));
    }

    [Fact]
    public void WithoutTheUserOrTheItemNothingIsVisible()
    {
        // Gli stub restituiscono null: utente ed elemento non esistono.
        var access = new JellyfinLibraryAccess(
            InterfaceStub<ISessionManager>.Create().Proxy,
            InterfaceStub<ILibraryManager>.Create().Proxy,
            InterfaceStub<IUserManager>.Create().Proxy);

        Assert.False(access.CanSee(Guid.NewGuid(), Guid.NewGuid()));
        Assert.False(access.CanSee(Guid.Empty, Guid.NewGuid()));
        Assert.False(access.CanSee(Guid.NewGuid(), Guid.Empty));
    }
```

(Se costruire `Movie` o `Episode` nel test lanciasse un'eccezione di Jellyfin, segnalalo: quel controllo passa alla prova manuale.)

Crea `InboxControllerTests.cs`:

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

public sealed class InboxControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly InboxService _inbox;

    public InboxControllerTests()
    {
        // Senza accesso ai watch party: la cassetta vale lo stesso.
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, false);
        _inbox = TestInbox.Create(_server, _folder, _time);
    }

    public void Dispose() => _folder.Dispose();

    private InboxController Controller(User user)
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = user, IsAuthenticated = true };
        return new InboxController(new FakeAuthorizationContext(auth), _inbox)
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
    public async Task ReadRemoveAndClearAnswer204()
    {
        await _inbox.AnnounceAsync("uno");
        await _inbox.AnnounceAsync("due");
        var controller = Controller(_mario);
        var inbox = (await controller.GetInbox()).Value!;
        Assert.Equal(2, inbox.Unread);

        Assert.Equal(204, Status(await controller.MarkRead(new InboxReadRequest { UpTo = inbox.Entries[0].Seq })));
        Assert.Equal(0, (await controller.GetInbox()).Value!.Unread);
        Assert.Equal(204, Status(await controller.RemoveEntry(inbox.Entries[0].Id)));
        // Una voce che non c'è (o un id che non è un Guid): 204 lo stesso, mai 404.
        Assert.Equal(204, Status(await controller.RemoveEntry("non-esiste")));
        Assert.Single((await controller.GetInbox()).Value!.Entries);
        Assert.Equal(204, Status(await controller.Clear()));
        Assert.Empty((await controller.GetInbox()).Value!.Entries);
        Assert.Equal(400, Status(await controller.MarkRead(null)));
    }

    [Fact]
    public async Task AnnouncementsAnswerTheRecipientsOr400()
    {
        var controller = Controller(_mario);
        Assert.Equal(1, (await controller.Announce(new AnnouncementRequest { Text = "ciao" })).Value!.Recipients);
        Assert.Equal(400, Status((await controller.Announce(new AnnouncementRequest { Text = " " })).Result!));
        Assert.Equal(400, Status((await controller.Announce(null)).Result!));
    }

    [Fact]
    public void EveryUserReadsTheInboxOnlyAdminsAnnounce()
    {
        var authorize = Assert.Single(typeof(InboxController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        var announce = Assert.Single(typeof(InboxController).GetMethod(nameof(InboxController.Announce))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.RequiresElevation, announce.Policy);
    }
}
```

Crea `PluginPagesTests.cs`:

```csharp
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PluginPagesTests
{
    [Fact]
    public void TheDashboardPageIsEmbeddedAndSendsAnnouncements()
    {
        var page = Assert.Single(Plugin.Pages);
        Assert.Equal("WonderFlixWatchParty", page.Name);
        Assert.Equal("WonderFlix Watch Party", page.DisplayName);
        Assert.True(page.EnableInMainMenu);

        using var stream = typeof(Plugin).Assembly.GetManifestResourceStream(page.EmbeddedResourcePath);
        Assert.NotNull(stream);
        using var reader = new StreamReader(stream);
        var html = reader.ReadToEnd();
        Assert.Contains("pluginConfigurationPage", html);
        Assert.Contains("WonderFlixWatchParty/Inbox/Announcements", html);
        Assert.Contains("maxlength=\"500\"", html);
    }
}
```

In `ServiceRegistrationTests.cs`: aggiungi `services.AddSingleton(InterfaceStub<ILibraryManager>.Create().Proxy);` dopo lo stub di `IUserManager` (`ILibraryManager` è in `MediaBrowser.Controller.Library`, già importato) e, dopo l'`Assert.EndsWith` di `friends.json`:

```csharp
        Assert.NotNull(provider.GetRequiredService<InboxService>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "inbox.json"),
            provider.GetRequiredService<InboxStore>().FilePath);
```

In `WatchPartyHostedServiceTests.cs`, nei due test esistenti, la cassetta del Task 4 va data anche al servizio:
- subito prima di `var parties = new PartyService(` dichiara `var inbox = TestInbox.Create(server, folder, time);`;
- in `new PartyService(…)` sostituisci `TestInbox.Create(server, folder, time)` con `inbox`;
- `new WatchPartyHostedService(` diventa:

```csharp
        using var service = new WatchPartyHostedService(
            manager, hub, friends, presence, parties, inbox, time, NullLogger<WatchPartyHostedService>.Instance);
```

Poi aggiungi in fondo alla classe:

```csharp
    [Fact]
    public async Task CleanupAlsoDropsExpiredNotifications()
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
        var inbox = TestInbox.Create(server, folder, time);
        var directory = new PartyDirectory(time);
        using var announcer = new PartyAnnouncer(
            directory, server, server, friends, server, time, NullLogger<PartyAnnouncer>.Instance);
        var parties = new PartyService(
            directory, server, server, server, friends, new PartyRegistry(), announcer, server,
            new RateLimiter(time), inbox, NullLogger<PartyService>.Instance);
        var mario = server.AddUser("Mario");
        await inbox.AnnounceAsync("vecchio");
        // Prima di creare il timer della pulizia: un timer periodico
        // scatterebbe una volta per ogni periodo saltato.
        time.Advance(InboxService.MaxAge + TimeSpan.FromMinutes(1));
        using var service = new WatchPartyHostedService(
            InterfaceStub<ISessionManager>.Create().Proxy, hub, friends, presence, parties, inbox, time,
            NullLogger<WatchPartyHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);

        time.Advance(WatchPartyHostedService.CleanupInterval);

        Assert.Empty(inbox.Get(mario.Id).Entries);
        await service.StopAsync(CancellationToken.None);
    }
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`JellyfinLibraryAccess`, `InboxController`, `Plugin.Pages` non esistono; `WatchPartyHostedService` senza il parametro `inbox`).

- [ ] **Step 3: adattatore della libreria**

Crea `Server/JellyfinLibraryAccess.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La libreria di Jellyfin: elemento in riproduzione e visibilità per utente.</summary>
public sealed class JellyfinLibraryAccess(
    ISessionManager sessionManager,
    ILibraryManager libraryManager,
    IUserManager userManager) : ILibraryAccess
{
    public PlayingItem? NowPlaying(string sessionId)
    {
        var session = sessionManager.Sessions.FirstOrDefault(s => string.Equals(s.Id, sessionId, StringComparison.Ordinal));
        if (session is null)
        {
            return null;
        }

        // Di solito c'è l'elemento intero; se no, quello del DTO.
        var item = session.FullNowPlayingItem;
        if (item is null && session.NowPlayingItem is { } dto && dto.Id != Guid.Empty)
        {
            item = libraryManager.GetItemById(dto.Id);
        }

        if (item is null)
        {
            return null;
        }

        var image = item is Episode episode && episode.SeriesId != Guid.Empty ? episode.SeriesId : item.Id;
        return new PlayingItem(item.Id, image);
    }

    // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
    public bool CanSee(Guid userId, Guid itemId)
    {
        if (userId == Guid.Empty || itemId == Guid.Empty)
        {
            return false;
        }

        var user = userManager.GetUserById(userId);
        var item = libraryManager.GetItemById(itemId);
        return user is not null && item is not null && item.IsVisibleStandalone(user);
    }
}
```

- [ ] **Step 4: endpoint della cassetta**

Crea `Api/InboxController.cs`:

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
/// La cassetta delle notifiche (spec G §6.3): per ogni utente autenticato,
/// anche senza accesso ai watch party; gli annunci solo per gli admin. Chi
/// chiama è l'utente dell'autenticazione. Come il resto del plugin, mai 404:
/// l'id di una voce è una stringa (un vincolo di rotta risponderebbe 404).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class InboxController(IAuthorizationContext authorizationContext, InboxService inbox) : ControllerBase
{
    /// <summary>Le voci dalla più recente e quante non lette.</summary>
    [HttpGet("Inbox")]
    public async Task<ActionResult<InboxResponse>> GetInbox() =>
        inbox.Get(await CallerAsync().ConfigureAwait(false));

    /// <summary>Segna lette le voci fino a UpTo (il Seq della più recente vista).</summary>
    [HttpPost("Inbox/Read")]
    public async Task<ActionResult> MarkRead([FromBody] InboxReadRequest? request)
    {
        if (request is null)
        {
            return BadRequest();
        }

        await inbox.MarkReadAsync(await CallerAsync().ConfigureAwait(false), request.UpTo).ConfigureAwait(false);
        return NoContent();
    }

    /// <summary>Toglie una voce; 204 anche se non c'è.</summary>
    [HttpDelete("Inbox/Entries/{entryId}")]
    public async Task<ActionResult> RemoveEntry([FromRoute] string entryId)
    {
        await inbox.RemoveAsync(await CallerAsync().ConfigureAwait(false), entryId).ConfigureAwait(false);
        return NoContent();
    }

    /// <summary>Svuota la cassetta di chi chiama.</summary>
    [HttpDelete("Inbox")]
    public async Task<ActionResult> Clear()
    {
        await inbox.ClearAsync(await CallerAsync().ConfigureAwait(false)).ConfigureAwait(false);
        return NoContent();
    }

    /// <summary>Un annuncio a tutti gli utenti attivi; solo per gli admin (dalla pagina nella Dashboard).</summary>
    [HttpPost("Inbox/Announcements")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<AnnouncementResponse>> Announce([FromBody] AnnouncementRequest? request)
    {
        var result = await inbox.AnnounceAsync(request?.Text).ConfigureAwait(false);
        return result.Status == HubStatus.Ok ? result.Value! : BadRequest();
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
```

- [ ] **Step 5: pagina nella Dashboard**

Crea `Configuration/configPage.html` (testi in inglese, come il resto del plugin):

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>WonderFlix Watch Party</title>
</head>
<body>
    <div id="WonderFlixWatchPartyPage" data-role="page" class="page type-interior pluginConfigurationPage" data-require="emby-button,emby-textarea">
        <div data-role="content">
            <div class="content-primary">
                <h2 class="sectionTitle">WonderFlix Watch Party</h2>
                <form id="WonderFlixAnnouncementForm">
                    <div class="verticalSection">
                        <h3 class="sectionTitle">Announcement</h3>
                        <div class="inputContainer">
                            <textarea is="emby-textarea" id="WonderFlixAnnouncementText" class="emby-textarea" rows="5" maxlength="500"></textarea>
                            <div class="fieldDescription">
                                Sent to the notifications of every active user in WonderFlix.
                                <span id="WonderFlixAnnouncementCount">0</span>/500
                            </div>
                        </div>
                        <button is="emby-button" type="submit" class="raised button-submit block emby-button">
                            <span>Send to everyone</span>
                        </button>
                        <div id="WonderFlixAnnouncementResult" class="fieldDescription"></div>
                    </div>
                </form>
            </div>
        </div>
        <script type="text/javascript">
            (function () {
                var page = document.querySelector('#WonderFlixWatchPartyPage');
                var text = page.querySelector('#WonderFlixAnnouncementText');
                var count = page.querySelector('#WonderFlixAnnouncementCount');
                var result = page.querySelector('#WonderFlixAnnouncementResult');

                text.addEventListener('input', function () {
                    count.textContent = text.value.length;
                });

                page.querySelector('#WonderFlixAnnouncementForm').addEventListener('submit', function (e) {
                    e.preventDefault();
                    var message = text.value.trim();
                    if (!message) {
                        result.textContent = 'Write a message first.';
                        return false;
                    }

                    Dashboard.showLoadingMsg();
                    ApiClient.ajax({
                        type: 'POST',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Inbox/Announcements'),
                        data: JSON.stringify({ Text: message }),
                        contentType: 'application/json',
                        dataType: 'json'
                    }).then(function (response) {
                        Dashboard.hideLoadingMsg();
                        result.textContent = 'Sent to ' + response.Recipients + ' users.';
                        text.value = '';
                        count.textContent = '0';
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        result.textContent = 'Not sent: check the message (1 to 500 characters) and try again.';
                    });
                    return false;
                });
            })();
        </script>
    </div>
</body>
</html>
```

Nel `.csproj` del plugin, dopo l'`ItemGroup` con `InternalsVisibleTo`:

```xml
  <ItemGroup>
    <EmbeddedResource Include="Configuration\configPage.html" />
  </ItemGroup>
```

Sostituisci `Plugin.cs` con:

```csharp
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Plugin "WonderFlix Watch Party" (spec E, F, G): nomi, chat e reazioni nei
/// watch party SyncPlay di WonderFlix, gli amici e la cassetta delle
/// notifiche. Non ha impostazioni; la sua pagina nella Dashboard serve per
/// gli annunci (spec G §6.8).
/// </summary>
public class Plugin : BasePlugin<BasePluginConfiguration>, IHasWebPages
{
    /// <summary>Id del plugin, uguale in meta.json e manifest.json.</summary>
    public static readonly Guid PluginId = Guid.Parse("882eb47e-668a-4935-ba55-c2858eb4ed90");

    /// <summary>
    /// La pagina nella Dashboard (menu laterale, sotto Plugin). Name deve
    /// essere unico tra tutti i plugin: Jellyfin cerca la pagina per nome.
    /// </summary>
    internal static readonly IReadOnlyList<PluginPageInfo> Pages =
    [
        new PluginPageInfo
        {
            Name = "WonderFlixWatchParty",
            DisplayName = "WonderFlix Watch Party",
            EmbeddedResourcePath = typeof(Plugin).Namespace + ".Configuration.configPage.html",
            EnableInMainMenu = true,
        },
    ];

    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
    }

    public override string Name => "WonderFlix Watch Party";

    public override Guid Id => PluginId;

    public override string Description =>
        "Names, chat, reactions, friends and notifications for SyncPlay watch parties in WonderFlix.";

    public IEnumerable<PluginPageInfo> GetPages() => Pages;
}
```

- [ ] **Step 6: servizi, caricamento e pulizia**

In `PluginServiceRegistrator.cs`, dopo la registrazione di `FriendService`:

```csharp
        serviceCollection.AddSingleton<ILibraryAccess, JellyfinLibraryAccess>();
        serviceCollection.AddSingleton(provider => new InboxStore(
            InboxStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<InboxStore>>()));
        serviceCollection.AddSingleton<InboxService>();
```

In `WatchPartyHostedService.cs`:
- nel commento della classe aggiungi, in fondo: "Alla stessa pulizia toglie le notifiche scadute (spec G §6.1).";
- nel costruttore primario, dopo `PartyService parties,` aggiungi `InboxService inbox,`;
- in `StartAsync`, dopo il blocco `try { friends.Load(); } catch …`:

```csharp
        try
        {
            inbox.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Cassetta delle notifiche non caricata all'avvio");
        }
```

- in `Cleanup`, dentro il `try`, dopo il blocco di `removedParties`:

```csharp
            var removedEntries = inbox.Cleanup();
            if (removedEntries > 0)
            {
                logger.LogDebug("Tolte {Count} notifiche scadute", removedEntries);
            }
```

- [ ] **Step 7: descrizione del plugin**

In `meta.template.json`:
- `"description"` → `"Names, chat, reactions, friends and notifications for SyncPlay watch parties in WonderFlix."`
- `"overview"` → `"WonderFlix watch party: names, chat, reactions, friends, notifications"`

In `README.md`:
- primo paragrafo: dopo "…e tiene la lista amici (spec F, `docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`)" aggiungi "e la cassetta delle notifiche (spec G, `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`)";
- la voce che comincia con "Nessuna configurazione." diventa: "Nessuna impostazione. La pagina del plugin nella Dashboard (menu laterale, sotto Plugin) serve per mandare un **annuncio** a tutti. Endpoint sotto `/WonderFlixWatchParty`; gli eventi arrivano ai client come `GeneralCommand` `SendString` con la chiave `WonderFlixWatchParty`.";
- dopo la voce **Dati** aggiungi: "- **Notifiche:** la cassetta di ogni utente (inviti ai watch party, annunci) sta in `plugins/configurations/WonderFlixWatchParty/inbox.json`: 30 giorni, al massimo 100 voci per utente. Un file illeggibile diventa `inbox.json.bad`.";
- nell'installazione a mano: `pack.sh 1.1.0` → `pack.sh 1.2.0` e `WonderFlix Watch Party_1.1.0.0` → `WonderFlix Watch Party_1.2.0.0`.

- [ ] **Step 8: i test passano e il pacchetto si crea**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

Run: `bash jellyfin-plugin-watch-party/pack.sh 1.2.0`
Expected: crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.2.0.0/` con la dll e `meta.json` (la cartella `artifacts/` è ignorata da git).

- [ ] **Step 9: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the inbox endpoints and the dashboard page for announcements"
```

### Task 6: plugin 1.2.0 sul server vero (orchestratore, nessun subagent)

Lo fa l'orchestratore dopo la review del gruppo A (lavoro sul server autorizzato, `ssh ultra`).

1. **Controllo dei riferimenti.** Nella scratchpad ricrea il progetto console `net9.0` con `<FrameworkReference Include="Microsoft.AspNetCore.App" />` e i pacchetti `Jellyfin.Controller`/`Jellyfin.Model` **10.11.9**: carica `artifacts/WonderFlix Watch Party_1.2.0.0/Jellyfin.Plugin.WonderFlixWatchParty.dll` e risolve ogni `TypeReference` e `MemberReference` (`System.Reflection.Metadata`, `module.ResolveType`/`ResolveMember`; si ignorano `BadImageFormatException`/`ArgumentException` dei membri generici). Atteso: 0 non risolti.
2. **Nessuno guarda?** Nel log del giorno (`~/.apps/jellyfin/log/log_YYYYMMDD.log`) le ultime righe `Playback start`/`Playback stopped`. Se qualcuno sta guardando, chiedere all'utente prima di andare avanti.
3. **Stop → copia → avvio** (copiare sopra la dll caricata fa cadere il vecchio processo in chiusura):
   - `ssh ultra 'app-jellyfin stop'`;
   - `scp -r "jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.2.0.0" ultra:.apps/jellyfin/data/plugins/`;
   - `ssh ultra 'app-jellyfin start'`.
   La cartella `WonderFlix Watch Party_1.1.0.0` del Catalogo resta: Jellyfin carica la versione più alta e segna l'altra come sostituita. Alla release (13b) la copia manuale va in `~/wfwp-backup/` prima di aggiornare dal Catalogo.
4. **Log:** `Loaded plugin: "WonderFlix Watch Party" "1.2.0.0"`, "WonderFlix Watch Party 1.2.0.0 avviato", "Cassetta delle notifiche in …/plugins/configurations/WonderFlixWatchParty/inbox.json".
5. La prova dell'annuncio dalla Dashboard si fa nella prova manuale con l'utente (è lui l'admin).

## Gruppo B — testi, modelli e disponibilità nell'app

### Task 7: testi della cassetta

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan13a_test.dart` (nuovo)

Si riusano chiavi che esistono già: `retry` ("Riprova"), `watchPartyJoin` ("Unisciti"), `friendsClose` ("Chiudi", tooltip della ×).

- [ ] **Step 1: test che fallisce**

Crea `test/app/l10n_plan13a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 13a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.inboxTitle, 'Notifiche');
    expect(it.inboxClear, 'Svuota');
    expect(it.inboxClearConfirm, 'Conferma');
    expect(it.inboxRemove, 'Rimuovi');
    expect(it.inboxEmpty, 'Nessuna notifica');
    expect(it.inboxUnavailable, 'Notifiche non disponibili');
    expect(it.inboxActionFailed,
        'Non è stato possibile aggiornare le notifiche');
    expect(it.inboxInviteFrom('Luigi'), 'Luigi ti invita a guardare');
    expect(it.inboxAlreadyIn, 'Ci sei già');
    expect(it.inboxPartyEnded, 'Party finito');
    expect(it.inboxAnnouncement, 'Annuncio');
    expect(it.inboxNow, 'adesso');
    expect(it.inboxMinutesAgo(5), '5 min fa');
    expect(it.inboxHoursAgo(2), '2 h fa');
    expect(it.inboxYesterday, 'ieri');
    expect(it.inboxDaysAgo(3), '3 giorni fa');
    expect(en.inboxTitle, 'Notifications');
    expect(en.inboxClear, 'Clear all');
    expect(en.inboxClearConfirm, 'Confirm');
    expect(en.inboxRemove, 'Remove');
    expect(en.inboxEmpty, 'No notifications');
    expect(en.inboxUnavailable, 'Notifications unavailable');
    expect(en.inboxActionFailed, "Couldn't update notifications");
    expect(en.inboxInviteFrom('Luigi'), 'Luigi invited you to watch');
    expect(en.inboxAlreadyIn, "You're in it");
    expect(en.inboxPartyEnded, 'Party ended');
    expect(en.inboxAnnouncement, 'Announcement');
    expect(en.inboxNow, 'just now');
    expect(en.inboxMinutesAgo(5), '5 min ago');
    expect(en.inboxHoursAgo(2), '2 h ago');
    expect(en.inboxYesterday, 'yesterday');
    expect(en.inboxDaysAgo(3), '3 days ago');
  });
}
```

- [ ] **Step 2: il test non compila**

Run: `flutter test test/app/l10n_plan13a_test.dart`
Expected: errori di compilazione (getter `inbox…` mancanti).

- [ ] **Step 3: le stringhe**

In `l10n/app_it.arb`, dopo l'ultima voce (`"@partyInviteTitle": {…}`, a cui va aggiunta la virgola), prima della `}` finale:

```json
  "inboxTitle": "Notifiche",
  "inboxClear": "Svuota",
  "inboxClearConfirm": "Conferma",
  "inboxRemove": "Rimuovi",
  "inboxEmpty": "Nessuna notifica",
  "inboxUnavailable": "Notifiche non disponibili",
  "inboxActionFailed": "Non è stato possibile aggiornare le notifiche",
  "inboxInviteFrom": "{name} ti invita a guardare",
  "@inboxInviteFrom": {"placeholders": {"name": {"type": "String"}}},
  "inboxAlreadyIn": "Ci sei già",
  "inboxPartyEnded": "Party finito",
  "inboxAnnouncement": "Annuncio",
  "inboxNow": "adesso",
  "inboxMinutesAgo": "{count} min fa",
  "@inboxMinutesAgo": {"placeholders": {"count": {"type": "int"}}},
  "inboxHoursAgo": "{count} h fa",
  "@inboxHoursAgo": {"placeholders": {"count": {"type": "int"}}},
  "inboxYesterday": "ieri",
  "inboxDaysAgo": "{count} giorni fa",
  "@inboxDaysAgo": {"placeholders": {"count": {"type": "int"}}}
```

In `l10n/app_en.arb`, dopo l'ultima voce (`"partyInviteTitle": "{name} invites you"`, con la virgola):

```json
  "inboxTitle": "Notifications",
  "inboxClear": "Clear all",
  "inboxClearConfirm": "Confirm",
  "inboxRemove": "Remove",
  "inboxEmpty": "No notifications",
  "inboxUnavailable": "Notifications unavailable",
  "inboxActionFailed": "Couldn't update notifications",
  "inboxInviteFrom": "{name} invited you to watch",
  "inboxAlreadyIn": "You're in it",
  "inboxPartyEnded": "Party ended",
  "inboxAnnouncement": "Announcement",
  "inboxNow": "just now",
  "inboxMinutesAgo": "{count} min ago",
  "inboxHoursAgo": "{count} h ago",
  "inboxYesterday": "yesterday",
  "inboxDaysAgo": "{count} days ago"
```

Run: `flutter gen-l10n`

- [ ] **Step 4: il test passa**

Run: `flutter test test/app/l10n_plan13a_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add l10n test/app/l10n_plan13a_test.dart
git commit -m "feat(app): add the notifications strings"
```

### Task 8: modelli della cassetta, avviso `InboxChanged`, chiamate al plugin

**Files:**
- Modify: `lib/core/party_channel/party_channel_models.dart`
- Modify: `lib/core/social/social_models.dart`
- Create: `lib/core/social/inbox_models.dart`
- Modify: `lib/core/social/social_api.dart`
- Modify: `lib/core/jellyfin/image_urls.dart`
- Modify: `test/support/social_fakes.dart`
- Test: `test/core/social/inbox_models_test.dart` (nuovo), `test/core/social/social_models_test.dart`, `test/core/social/social_api_test.dart`, `test/core/party_channel/party_channel_models_test.dart`, `test/core/jellyfin/image_urls_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/core/social/inbox_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/inbox_models.dart';

import '../../support/social_fakes.dart';

void main() {
  test('voci della cassetta: invito, annuncio; i tipi sconosciuti si saltano',
      () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 3,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00.1234567+00:00',
          'Read': false,
          'GroupId': 'g1',
          'FromName': 'Luigi',
          'Title': 'Dune',
          'ImageItemId': 'm1',
        },
        {
          'Id': 'n1',
          'Seq': 2,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-03T19:00:00+00:00',
          'Read': false,
        },
        {
          'Id': 'a1',
          'Seq': 1,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+02:00',
          'Read': true,
          'Text': 'Stasera manutenzione',
        },
      ],
      'Unread': 2,
    });

    expect(snapshot.entries, hasLength(2));
    expect(snapshot.unread, 2);
    expect(snapshot.maxSeq, 3);
    final invite = snapshot.entries.first as InviteEntry;
    expect(invite.id, 'i1');
    expect(invite.seq, 3);
    expect(invite.read, isFalse);
    expect(invite.groupId, 'g1');
    expect(invite.fromName, 'Luigi');
    expect(invite.title, 'Dune');
    expect(invite.imageItemId, 'm1');
    expect(invite.createdAt, DateTime.utc(2026, 10, 3, 20, 0, 0, 123, 456));
    final announcement = snapshot.entries.last as AnnouncementEntry;
    expect(announcement.text, 'Stasera manutenzione');
    expect(announcement.read, isTrue);
    expect(announcement.createdAt, DateTime.utc(2026, 10, 3, 16));
  });

  test('cassetta vuota; invito senza locandina', () {
    expect(InboxSnapshot.fromJson(const {}).entries, isEmpty);
    expect(InboxSnapshot.fromJson(const {}).unread, 0);
    expect(InboxSnapshot.empty.maxSeq, 0);
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 1,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'GroupId': 'g1',
          'FromName': 'Luigi',
          'Title': 'Dune',
        },
      ],
      'Unread': 1,
    });
    final invite = snapshot.entries.single as InviteEntry;
    expect(invite.imageItemId, isNull);
    expect(invite.read, isFalse);
  });

  test('tutto letto; senza una voce', () {
    final snapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);

    expect(snapshot.markedRead().unread, 0);
    expect(snapshot.markedRead().entries, hasLength(2));
    final without = snapshot.without('i1');
    expect(without.entries.map((e) => e.id), ['a1']);
    expect(without.unread, 0);
    expect(snapshot.without('a1').unread, 1);
    expect(identical(snapshot.without('x'), snapshot), isTrue);
  });
}
```

In `test/core/social/social_models_test.dart`, nel test `avvisi del plugin`, dopo l'`expect` di `FriendsChanged`:

```dart
    expect(parseSocialEvent('{"Protocol":1,"Type":"InboxChanged"}'),
        isA<InboxChangedEvent>());
```

In `test/core/party_channel/party_channel_models_test.dart`, nel test che controlla gli avvisi sociali scartati in silenzio, prima di `expect(records, isEmpty);`:

```dart
    expect(parsePartyEvent('{"Protocol":1,"Type":"InboxChanged"}'), isNull);
```

In `test/core/social/social_api_test.dart` aggiungi l'import `package:wonderflix/core/social/inbox_models.dart` e il test:

```dart
  test('cassetta: lettura, letto, rimozione, svuota', () async {
    adapter.handler = (options) =>
        switch ('${options.method} ${options.path}') {
          'GET /WonderFlixWatchParty/Inbox' => const FakeResponse(200, {
              'Entries': [
                {
                  'Id': 'a1',
                  'Seq': 1,
                  'Type': 'Announcement',
                  'CreatedAt': '2026-10-03T20:00:00+00:00',
                  'Read': false,
                  'Text': 'ciao',
                },
              ],
              'Unread': 1,
            }),
          _ => const FakeResponse(204),
        };

    final inbox = await api.inbox();
    expect((inbox.entries.single as AnnouncementEntry).text, 'ciao');
    expect(inbox.unread, 1);
    await api.markInboxRead(7);
    expect(adapter.requests.last.data, {'UpTo': 7});
    await api.removeInboxEntry('a1');
    await api.clearInbox();
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'GET /WonderFlixWatchParty/Inbox',
      'POST /WonderFlixWatchParty/Inbox/Read',
      'DELETE /WonderFlixWatchParty/Inbox/Entries/a1',
      'DELETE /WonderFlixWatchParty/Inbox',
    ]);
  });
```

In `test/core/jellyfin/image_urls_test.dart` aggiungi:

```dart
  test('immagine principale da un id, senza tag', () {
    final image = urls.primaryOf('m1');
    expect(image.url,
        'https://media.example.com/jf/Items/m1/Images/Primary?maxWidth=120&quality=90');
    expect(image.blurHash, isNull);
    expect(urls.primaryOf('m1', maxWidth: 300).url, contains('maxWidth=300'));
  });
```

In `test/support/social_fakes.dart`:
- aggiungi l'import `package:wonderflix/core/social/inbox_models.dart`;
- in `FakeSocialApi`, dopo `invite(...)`:

```dart
  /// Risposta di [inbox].
  InboxSnapshot inboxSnapshot = InboxSnapshot.empty;

  /// Se valorizzato, [inbox] aspetta che si completi (la risposta è quella
  /// del momento della chiamata).
  Completer<void>? inboxGate;

  @override
  Future<InboxSnapshot> inbox() async {
    calls.add('inbox');
    final result = inboxSnapshot;
    await inboxGate?.future;
    _fail();
    return result;
  }

  @override
  Future<void> markInboxRead(int upTo) async {
    calls.add('read $upTo');
    _fail();
  }

  @override
  Future<void> removeInboxEntry(String id) async {
    calls.add('remove-entry $id');
    _fail();
  }

  @override
  Future<void> clearInbox() async {
    calls.add('clear-inbox');
    _fail();
  }
```

- in fondo al file:

```dart
/// Un invito nella cassetta: Luigi, "Dune", gruppo `g1`.
InviteEntry testInvite({
  String id = 'i1',
  int seq = 1,
  bool read = false,
  String groupId = 'g1',
  String fromName = 'Luigi',
  String title = 'Dune',
  DateTime? createdAt,
}) =>
    InviteEntry(
      id: id,
      seq: seq,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 3, 20),
      read: read,
      groupId: groupId,
      fromName: fromName,
      title: title,
      imageItemId: 'm1',
    );

/// Un annuncio dell'admin nella cassetta.
AnnouncementEntry testAnnouncement({
  String id = 'a1',
  int seq = 1,
  bool read = false,
  String text = 'Stasera manutenzione',
  DateTime? createdAt,
}) =>
    AnnouncementEntry(
      id: id,
      seq: seq,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 3, 20),
      read: read,
      text: text,
    );

/// Come arriva dal WebSocket l'avviso che la cassetta è cambiata.
PartyChannelReceived inboxChangedReceived() => PartyChannelReceived(
    jsonEncode({'Protocol': 1, 'Type': 'InboxChanged'}));
```

Attenzione: `_fail()` consuma `nextFailure` in ogni chiamata, anche in `markInboxRead` (che l'app fa da sola aprendo il pannello). Nei test si imposta `nextFailure` subito prima dell'azione che deve fallire.

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/core`
Expected: errori di compilazione (`InboxSnapshot`, `InboxChangedEvent`, `primaryOf`, metodi di `SocialApi` mancanti).

- [ ] **Step 3: modelli della cassetta**

Crea `lib/core/social/inbox_models.dart`:

```dart
import 'dart:math' as math;

/// Una voce della cassetta delle notifiche (spec G §6.2).
sealed class InboxEntry {
  const InboxEntry({
    required this.id,
    required this.seq,
    required this.createdAt,
    required this.read,
  });

  final String id;

  /// Progressivo per utente: cresce a ogni voce nuova o aggiornata.
  final int seq;

  /// In UTC.
  final DateTime createdAt;

  /// Già letta secondo il plugin.
  final bool read;
}

/// Un amico ci ha invitato in un watch party (spec G §6.5).
final class InviteEntry extends InboxEntry {
  const InviteEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.groupId,
    required this.fromName,
    required this.title,
    this.imageItemId,
  });

  final String groupId;
  final String fromName;
  final String title;

  /// La locandina (la serie, per un episodio); `null` se il plugin non l'ha.
  final String? imageItemId;
}

/// Un annuncio dell'admin (spec G §6.7).
final class AnnouncementEntry extends InboxEntry {
  const AnnouncementEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.text,
  });

  final String text;
}

/// Una voce di `GET Inbox`; `null` se il tipo non lo conosciamo (es. le
/// voci di una versione più nuova del plugin).
InboxEntry? inboxEntryFromJson(Map<String, dynamic> json) {
  final id = json['Id'] as String;
  final seq = (json['Seq'] as num).toInt();
  final createdAt = DateTime.parse(json['CreatedAt'] as String).toUtc();
  final read = json['Read'] as bool? ?? false;
  return switch (json['Type']) {
    'Invite' => InviteEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        groupId: json['GroupId'] as String,
        fromName: json['FromName'] as String,
        title: json['Title'] as String,
        imageItemId: json['ImageItemId'] as String?,
      ),
    'Announcement' => AnnouncementEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        text: json['Text'] as String,
      ),
    _ => null,
  };
}

/// Risposta di `GET Inbox`: le voci dalla più recente e quante non lette.
class InboxSnapshot {
  const InboxSnapshot({this.entries = const [], this.unread = 0});

  factory InboxSnapshot.fromJson(Map<String, dynamic> json) => InboxSnapshot(
        entries: [
          for (final raw in json['Entries'] as List? ?? const [])
            if (inboxEntryFromJson(raw as Map<String, dynamic>)
                case final entry?)
              entry,
        ],
        unread: (json['Unread'] as num?)?.toInt() ?? 0,
      );

  static const empty = InboxSnapshot();

  final List<InboxEntry> entries;
  final int unread;

  /// Il Seq più alto (0 se vuota): fin lì si segna letto.
  int get maxSeq => entries.fold(0, (max, e) => math.max(max, e.seq));

  /// Tutto letto. Le voci restano come sono: chi apre il pannello decide
  /// quali hanno il pallino.
  InboxSnapshot markedRead() => InboxSnapshot(entries: entries, unread: 0);

  /// Senza la voce [id]; se era non letta il conto scende.
  InboxSnapshot without(String id) {
    final removed = entries.where((e) => e.id == id).toList();
    if (removed.isEmpty) return this;
    return InboxSnapshot(
      entries: [
        for (final e in entries)
          if (e.id != id) e,
      ],
      unread: math.max(0, unread - removed.where((e) => !e.read).length),
    );
  }
}
```

- [ ] **Step 4: funzione, avviso e chiamate**

In `lib/core/social/social_models.dart`:
- in `PluginFeatures` aggiungi:

```dart
  /// La cassetta delle notifiche (spec G).
  static const inbox = 'inbox';
```

- dopo `PartyInviteEvent`:

```dart
/// La cassetta delle notifiche è cambiata: si rilegge `GET Inbox` (spec G
/// §6.4).
final class InboxChangedEvent extends SocialEvent {
  const InboxChangedEvent();
}
```

- in `parseSocialEvent`, dopo il `case 'PartyInvite':` (e il suo `return`):

```dart
      case 'InboxChanged':
        return const InboxChangedEvent();
```

In `lib/core/party_channel/party_channel_models.dart` aggiungi `'InboxChanged',` in fondo a `socialEventTypes`, e nel commento sopra "(spec F §6.8)" diventa "(spec F §6.8, spec G §6.4)".

In `lib/core/social/social_api.dart` aggiungi l'import `'inbox_models.dart'` e, dopo `invite(...)`:

```dart
  /// La cassetta delle notifiche (spec G §6.3).
  Future<InboxSnapshot> inbox() => _call(() async => InboxSnapshot.fromJson(
      asJsonMap(await _http.get('$_base/Inbox', quietStatuses: _quiet))));

  /// Segna lette le voci fino a [upTo] (il Seq della più recente vista).
  Future<void> markInboxRead(int upTo) => _call(() => _http.post(
      '$_base/Inbox/Read',
      body: {'UpTo': upTo},
      quietStatuses: _quiet));

  /// Toglie una voce (il plugin risponde 204 anche se non c'è più).
  Future<void> removeInboxEntry(String id) => _call(() =>
      _http.delete('$_base/Inbox/Entries/$id', quietStatuses: _quiet));

  /// Svuota la cassetta.
  Future<void> clearInbox() =>
      _call(() => _http.delete('$_base/Inbox', quietStatuses: _quiet));
```

In `lib/core/jellyfin/image_urls.dart`, dopo `poster(...)`:

```dart
  /// Immagine principale di un elemento di cui si conosce solo l'id (es. la
  /// locandina di un invito nella cassetta, spec G §7.6): senza tag
  /// Jellyfin dà quella attuale.
  ImageRef primaryOf(String itemId, {int maxWidth = 120}) => ImageRef(
      '$_base/Items/$itemId/Images/Primary?maxWidth=$maxWidth&quality=90');
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/core`
Expected: PASS.

- [ ] **Step 6: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/core test/core test/support/social_fakes.dart
git commit -m "feat(app): add the inbox models and plugin calls"
```

### Task 9: funzione `inbox`, `Info` anche senza watch party, diagnostica

**Files:**
- Modify: `lib/features/social/social_providers.dart`
- Modify: `lib/features/settings/diagnostics.dart`
- Test: `test/features/social/social_providers_test.dart`, `test/features/settings/diagnostics_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/features/social/social_providers_test.dart`:

1. Il test `senza utente o senza watch party: nessuna funzione, nessuna chiamata` diventa:

```dart
  test('senza utente: nessuna funzione, nessuna chiamata', () async {
    api.install();
    final signedOut = container(session: const SessionSignedOut());
    await pumpEventQueue();
    expect(signedOut.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, isEmpty);
  });

  test('senza accesso ai watch party: Info si chiede, resta solo la cassetta',
      () async {
    api.install(features: const {
      PluginFeatures.friends,
      PluginFeatures.parties,
      PluginFeatures.inbox,
    });
    final c = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(inbox: true));
    expect(api.calls, ['info']);
  });

  test('Info con la cassetta: funzione inbox', () async {
    api.install(features: const {PluginFeatures.friends, PluginFeatures.inbox});
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true, inbox: true));
  });
```

2. Nel test `un Info lento non vale per chi entra dopo senza watch party` le ultime due righe diventano:

```dart
    expect(c.read(socialAvailabilityProvider), SocialFeatures.none);
    expect(api.calls, ['info', 'info'],
        reason: 'il nuovo utente chiede Info per sé; amici e party restano '
            'spenti perché non ha accesso ai watch party');
```

In `test/features/settings/diagnostics_test.dart`, nel test `describePluginFeatures`, aggiungi:

```dart
    expect(
        describePluginFeatures(const {
          PluginFeatures.friends,
          PluginFeatures.parties,
          PluginFeatures.inbox,
        }),
        'amici, party, notifiche');
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/social test/features/settings/diagnostics_test.dart`
Expected: FAIL (`inbox` non esiste in `SocialFeatures`; nessuna chiamata a `Info` senza accesso ai watch party).

- [ ] **Step 3: la funzione `inbox`**

In `lib/features/social/social_providers.dart`, `SocialFeatures`:

```dart
  const SocialFeatures({
    this.friends = false,
    this.parties = false,
    this.inbox = false,
    this.known = true,
  });
```

dopo `final bool parties;`:

```dart
  /// La cassetta delle notifiche (spec G): c'è anche per chi non ha accesso
  /// ai watch party.
  final bool inbox;
```

e `==`, `hashCode`, `toString` la includono:

```dart
  @override
  bool operator ==(Object other) =>
      other is SocialFeatures &&
      other.friends == friends &&
      other.parties == parties &&
      other.inbox == inbox &&
      other.known == known;

  @override
  int get hashCode => Object.hash(friends, parties, inbox, known);

  @override
  String toString() => 'SocialFeatures(friends: $friends, parties: $parties, '
      'inbox: $inbox, known: $known)';
```

- [ ] **Step 4: `Info` anche senza watch party**

In `SocialAvailability`:
- nel commento della classe, la frase "Senza utente, senza accesso ai watch party o senza plugin: nessuna funzione, e l'app si comporta come la 0.5.1." diventa: "Senza utente o senza plugin: nessuna funzione, e l'app si comporta come la 0.5.1. Senza accesso ai watch party `Info` si chiede lo stesso (la cassetta delle notifiche vale per tutti, spec G §7.2), ma amici e party restano spenti.";
- dopo `Timer? _retry;` aggiungi:

```dart
  /// L'utente può entrare nei watch party: senza, amici e party restano
  /// spenti anche se il plugin li ha.
  bool _canJoin = false;
```

- in `build`, il controllo

```dart
    if (userId == null || !ref.watch(syncPlayAccessProvider).canJoin) {
      return SocialFeatures.none;
    }
```

diventa

```dart
    if (userId == null) return SocialFeatures.none;
    _canJoin = ref.watch(syncPlayAccessProvider).canJoin;
```

- in `refresh`, l'`_apply(SocialFeatures(…))` della risposta riuscita diventa:

```dart
      _apply(SocialFeatures(
        friends: _canJoin && info.features.contains(PluginFeatures.friends),
        parties: _canJoin && info.features.contains(PluginFeatures.parties),
        inbox: info.features.contains(PluginFeatures.inbox),
      ));
```

In `lib/features/settings/diagnostics.dart`, in `describePluginFeatures`, dopo la riga di `parties`:

```dart
    if (features.contains(PluginFeatures.inbox)) 'notifiche',
```

e il commento sopra diventa "Funzioni del plugin per la diagnostica (spec F §7.2, spec G §7.2)."

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/social test/features/settings/diagnostics_test.dart`
Expected: PASS.

- [ ] **Step 6: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/features/social lib/features/settings/diagnostics.dart test/features/social test/features/settings/diagnostics_test.dart
git commit -m "feat(app): know the inbox feature, also without watch party access"
```

## Gruppo C — stato della cassetta e pannelli della shell

### Task 10: `InboxController`

**Files:**
- Create: `lib/features/inbox/inbox_controller.dart`
- Test: `test/features/inbox/inbox_controller_test.dart` (nuovo)

- [ ] **Step 1: test che falliscono**

Crea `test/features/inbox/inbox_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/inbox/inbox_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    events = StreamController<ServerEvent>.broadcast();
    addTearDown(events.close);
  });

  ProviderContainer container(
      {SocialFeatures features = const SocialFeatures(inbox: true)}) {
    final c = ProviderContainer.test(
        overrides:
            socialTestOverrides(api, events: events.stream, features: features));
    c.listen(inboxControllerProvider, (_, _) {});
    return c;
  }

  int loads() => api.calls.where((call) => call == 'inbox').length;

  test('senza la funzione: vuota, nessuna chiamata', () async {
    final c = container(features: SocialFeatures.none);
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(api.calls, isEmpty);
  });

  test('legge alla nascita, a ogni InboxChanged e a ogni riconnessione',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [testAnnouncement()], unread: 1);
    final c = container();
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).loaded, isTrue);
    expect(c.read(inboxControllerProvider).unread, 1);

    events.add(inboxChangedReceived());
    await pumpEventQueue();
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    // La prima connessione non è una riconnessione: niente lettura in più.
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(loads(), 3);
  });

  test('pannello aperto: le non lette diventano lette e prendono il pallino',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);

    controller.panelOpened();
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'i1'});
    await pumpEventQueue();
    expect(api.calls, contains('read 2'));

    // Il plugin ora dice tutto letto: il pallino resta finché il pannello è
    // aperto.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2, read: true),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ]);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).highlighted, {'i1'});

    // Una voce nuova a pannello aperto: pallino e subito letta.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a2', seq: 3),
      testInvite(id: 'i1', seq: 2, read: true),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'i1', 'a2'});
    expect(api.calls, contains('read 3'));

    controller.panelClosed();
    expect(c.read(inboxControllerProvider).highlighted, isEmpty);

    // A pannello chiuso le voci nuove restano non lette.
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a3', seq: 4),
      testAnnouncement(id: 'a2', seq: 3, read: true),
    ], unread: 1);
    events.add(inboxChangedReceived());
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).unread, 1);
    expect(api.calls, isNot(contains('read 4')));
  });

  test('Rimuovi e Svuota si vedono subito; se non riescono si rilegge',
      () async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1),
    ], unread: 2);
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);

    expect(await controller.remove('i1'), isNull);
    expect(c.read(inboxControllerProvider).snapshot.entries.map((e) => e.id),
        ['a1']);
    expect(c.read(inboxControllerProvider).unread, 1);
    expect(api.calls, contains('remove-entry i1'));

    api.nextFailure = SocialFailure.network;
    final cleared = controller.clear();
    expect(c.read(inboxControllerProvider).snapshot.entries, isEmpty);
    expect(await cleared, SocialFailure.network);
    await pumpEventQueue();
    // Il plugin ha ancora tutte e due le voci: si rilegge.
    expect(c.read(inboxControllerProvider).snapshot.entries, hasLength(2));
  });

  test('un caricamento non riuscito lo segna; Riprova rilegge', () async {
    api.nextFailure = SocialFailure.network;
    final c = container();
    await pumpEventQueue();
    expect(c.read(inboxControllerProvider).failed, isTrue);
    expect(c.read(inboxControllerProvider).loaded, isFalse);

    await c.read(inboxControllerProvider.notifier).reload();
    expect(c.read(inboxControllerProvider).failed, isFalse);
    expect(c.read(inboxControllerProvider).loaded, isTrue);
  });

  test('una risposta lenta non vale dopo una più recente', () async {
    final c = container();
    await pumpEventQueue();
    final controller = c.read(inboxControllerProvider.notifier);
    final gate = api.inboxGate = Completer<void>();
    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement(id: 'old')], unread: 1);
    final slow = controller.reload();
    api.inboxGate = null;
    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement(id: 'new')], unread: 1);
    await controller.reload();

    gate.complete();
    await slow;

    expect(c.read(inboxControllerProvider).snapshot.entries.single.id, 'new');
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/inbox/inbox_controller_test.dart`
Expected: errori di compilazione (`inbox_controller.dart` non esiste).

- [ ] **Step 3: il controller**

Crea `lib/features/inbox/inbox_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/social/inbox_models.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';

final _log = Logger('social');

/// La cassetta delle notifiche come la vede l'app (spec G §7.3).
class InboxState {
  const InboxState({
    this.snapshot = InboxSnapshot.empty,
    this.loaded = false,
    this.failed = false,
    this.highlighted = const {},
  });

  final InboxSnapshot snapshot;

  /// Almeno un caricamento è riuscito.
  final bool loaded;

  /// L'ultimo caricamento non è riuscito (resta la cassetta di prima).
  final bool failed;

  /// Id delle voci con il pallino dorato: non lette quando il pannello si è
  /// aperto, o arrivate a pannello aperto (spec G §7.5). Si svuota alla
  /// chiusura.
  final Set<String> highlighted;

  /// Il numero sull'icona.
  int get unread => snapshot.unread;

  InboxState copyWith({
    InboxSnapshot? snapshot,
    bool? loaded,
    bool? failed,
    Set<String>? highlighted,
  }) =>
      InboxState(
        snapshot: snapshot ?? this.snapshot,
        loaded: loaded ?? this.loaded,
        failed: failed ?? this.failed,
        highlighted: highlighted ?? this.highlighted,
      );
}

/// Legge la cassetta dal plugin: alla nascita, a ogni avviso
/// `InboxChanged`, a ogni riconnessione del WebSocket e all'apertura del
/// pannello. Con il pannello aperto le voci non lette diventano subito
/// lette (sul plugin fino alla più recente) e prendono il pallino.
class InboxController extends Notifier<InboxState> {
  /// Cresce a ogni caricamento e a ogni azione: vale solo la risposta
  /// dell'ultimo caricamento, e una lettura partita prima di un'azione non
  /// la disfa.
  int _loads = 0;

  /// Il pannello Notifiche è aperto (lo dice `ShellPanelController`).
  bool _panelOpen = false;

  @override
  InboxState build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _loads++;
    // Utente nuovo o logout: il pannello di prima non c'è più.
    _panelOpen = false;
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.inbox))) {
      return const InboxState();
    }
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is InboxChangedEvent) unawaited(reload());
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
    return const InboxState();
  }

  /// Rilegge la cassetta dal plugin.
  Future<void> reload() async {
    if (!ref.mounted || !ref.read(socialAvailabilityProvider).inbox) return;
    final load = ++_loads;
    try {
      final snapshot = await ref.read(socialApiProvider).inbox();
      if (!ref.mounted || load != _loads) return;
      state = _seenIfOpen(
          state.copyWith(snapshot: snapshot, loaded: true, failed: false));
    } on Object catch (error) {
      _log.info('notifiche non caricate: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
      if (!ref.mounted || load != _loads) return;
      state = state.copyWith(failed: true);
    }
  }

  /// Il pannello si è aperto: le non lette diventano lette, e si rilegge.
  void panelOpened() {
    if (_panelOpen) return;
    _panelOpen = true;
    state = _seenIfOpen(state);
    unawaited(reload());
  }

  /// Il pannello si è chiuso: niente più pallini.
  void panelClosed() {
    _panelOpen = false;
    if (state.highlighted.isNotEmpty) {
      state = state.copyWith(highlighted: const {});
    }
  }

  /// Toglie una voce; `null` se riuscita.
  Future<SocialFailure?> remove(String entryId) => _act(
      state.snapshot.without(entryId), (api) => api.removeInboxEntry(entryId));

  /// Svuota la cassetta; `null` se riuscita.
  Future<SocialFailure?> clear() =>
      _act(InboxSnapshot.empty, (api) => api.clearInbox());

  /// Con il pannello aperto le non lette diventano lette: sul plugin fino
  /// alla più recente, qui subito, con il pallino.
  InboxState _seenIfOpen(InboxState next) {
    final snapshot = next.snapshot;
    if (!_panelOpen || snapshot.unread == 0) return next;
    unawaited(_markRead(snapshot.maxSeq));
    return next.copyWith(
      snapshot: snapshot.markedRead(),
      highlighted: {
        ...next.highlighted,
        for (final entry in snapshot.entries)
          if (!entry.read) entry.id,
      },
    );
  }

  Future<void> _markRead(int upTo) async {
    try {
      await ref.read(socialApiProvider).markInboxRead(upTo);
    } on Object catch (error) {
      // Il numero torna alla prossima lettura (spec G §8): niente messaggio.
      _log.info('notifiche non segnate lette: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
    }
  }

  /// Mostra subito [optimistic]; se l'azione non riesce rilegge (nel
  /// frattempo la cassetta può essere cambiata). `null` se riuscita.
  Future<SocialFailure?> _act(
      InboxSnapshot optimistic, Future<void> Function(SocialApi api) action) async {
    // Una lettura partita prima non deve rimettere la voce tolta.
    _loads++;
    state = state.copyWith(snapshot: optimistic);
    try {
      await action(ref.read(socialApiProvider));
      return null;
    } on SocialException catch (error) {
      if (ref.mounted) unawaited(reload());
      return error.failure;
    } on Object catch (error) {
      _log.info('azione sulle notifiche non riuscita: ${error.runtimeType}');
      if (ref.mounted) unawaited(reload());
      return SocialFailure.network;
    }
  }
}

final inboxControllerProvider =
    NotifierProvider<InboxController, InboxState>(InboxController.new);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/inbox/inbox_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/features/inbox test/features/inbox
git commit -m "feat(app): add the inbox controller"
```

### Task 11: un pannello alla volta (`shellPanelProvider`) e contenitore comune

**Files:**
- Create: `lib/app/shell_panels.dart`
- Create: `lib/ui/shell_side_panel.dart`
- Modify: `lib/features/friends/friends_panel.dart`, `lib/features/friends/friends_button.dart`, `lib/app/back_navigation.dart`
- Test: `test/app/shell_panels_test.dart` (nuovo), `test/app/back_navigation_test.dart`, `test/features/friends/friends_panel_test.dart`

- [ ] **Step 1: test che falliscono**

Crea `test/app/shell_panels_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/friends/friends_controller.dart';
import 'package:wonderflix/features/inbox/inbox_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../support/social_fakes.dart';

void main() {
  test('un pannello alla volta: aprirne uno chiude l\'altro', () async {
    final api = FakeSocialApi()
      ..inboxSnapshot =
          InboxSnapshot(entries: [testAnnouncement(seq: 4)], unread: 1);
    final c = ProviderContainer.test(
        overrides: socialTestOverrides(api,
            features: const SocialFeatures(friends: true, inbox: true)));
    c.listen(shellPanelProvider, (_, _) {});
    c.listen(inboxControllerProvider, (_, _) {});
    c.listen(friendsControllerProvider, (_, _) {});
    await pumpEventQueue();
    api.calls.clear();
    final panels = c.read(shellPanelProvider.notifier);

    panels.open(ShellPanel.friends);
    expect(c.read(shellPanelProvider), ShellPanel.friends);
    await pumpEventQueue();
    expect(api.calls, contains('friends'), reason: 'aprire Amici li rilegge');

    panels.open(ShellPanel.inbox);
    expect(c.read(shellPanelProvider), ShellPanel.inbox);
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'a1'});
    await pumpEventQueue();
    expect(api.calls, contains('read 4'));

    panels.toggle(ShellPanel.friends);
    expect(c.read(shellPanelProvider), ShellPanel.friends);
    expect(c.read(inboxControllerProvider).highlighted, isEmpty,
        reason: 'chiudere Notifiche toglie i pallini');

    panels.toggle(ShellPanel.friends);
    expect(c.read(shellPanelProvider), ShellPanel.none);
  });
}
```

In `test/app/back_navigation_test.dart`:
- l'import di `package:wonderflix/features/friends/friends_panel.dart` diventa `package:wonderflix/app/shell_panels.dart`;
- `friendsPanelProvider.overrideWith(_OpenFriendsPanel.new)` (due volte) → `shellPanelProvider.overrideWith(_OpenFriendsPanel.new)`;
- `Future<ProviderSubscription<bool>> pumpWithOpenPanel(` → `Future<ProviderSubscription<ShellPanel>> pumpWithOpenPanel(`;
- `container.listen(friendsPanelProvider, (_, _) {})` → `container.listen(shellPanelProvider, (_, _) {})`;
- `expect(panel.read(), isTrue);` → `expect(panel.read(), ShellPanel.friends);`;
- `expect(panel.read(), isFalse);` (tre volte) → `expect(panel.read(), ShellPanel.none);`;
- `.read(friendsPanelProvider.notifier)` → `.read(shellPanelProvider.notifier)`;
- la classe in fondo diventa:

```dart
/// Pannello Amici già aperto (senza toccare amici né plugin).
class _OpenFriendsPanel extends ShellPanelController {
  @override
  ShellPanel build() => ShellPanel.friends;
}
```

In `test/features/friends/friends_panel_test.dart` (test `"Ho un codice": il trattino da sé, poi entra e il pannello si chiude`):
- aggiungi l'import `package:wonderflix/app/shell_panels.dart`;
- `container.listen(friendsPanelProvider, (_, _) {});` → `container.listen(shellPanelProvider, (_, _) {});`
- `container.read(friendsPanelProvider.notifier).open();` → `container.read(shellPanelProvider.notifier).open(ShellPanel.friends);`
- `expect(container.read(friendsPanelProvider), isFalse);` → `expect(container.read(shellPanelProvider), ShellPanel.none);`

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/app/shell_panels_test.dart test/app/back_navigation_test.dart test/features/friends`
Expected: errori di compilazione (`shell_panels.dart` non esiste).

- [ ] **Step 3: lo stato dei pannelli**

Crea `lib/app/shell_panels.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/friends/friends_controller.dart';
import '../features/inbox/inbox_controller.dart';

/// I pannelli laterali della shell (spec F §8.3, spec G §7.5).
enum ShellPanel { none, friends, inbox }

/// Il pannello laterale aperto: uno alla volta, aprirne uno chiude l'altro.
/// Aprire Amici rilegge gli amici; aprire e chiudere Notifiche lo dice alla
/// cassetta (letture e pallini). Non dipende da altri provider: lo legge
/// anche la gestione dei tasti indietro. Si azzera quando nessuno lo guarda
/// più (es. la shell smontata al logout).
class ShellPanelController extends Notifier<ShellPanel> {
  @override
  ShellPanel build() => ShellPanel.none;

  void open(ShellPanel panel) {
    if (panel == ShellPanel.none) {
      close();
      return;
    }
    if (state == panel) return;
    _leaving();
    state = panel;
    switch (panel) {
      case ShellPanel.friends:
        unawaited(ref.read(friendsControllerProvider.notifier).reload());
      case ShellPanel.inbox:
        ref.read(inboxControllerProvider.notifier).panelOpened();
      case ShellPanel.none:
        break;
    }
  }

  void close() {
    if (state == ShellPanel.none) return;
    _leaving();
    state = ShellPanel.none;
  }

  void toggle(ShellPanel panel) => state == panel ? close() : open(panel);

  /// Il pannello di adesso sta per chiudersi.
  void _leaving() {
    if (state == ShellPanel.inbox) {
      ref.read(inboxControllerProvider.notifier).panelClosed();
    }
  }
}

final shellPanelProvider =
    NotifierProvider.autoDispose<ShellPanelController, ShellPanel>(
        ShellPanelController.new);
```

- [ ] **Step 4: il contenitore comune**

Crea `lib/ui/shell_side_panel.dart` (è il contenitore che oggi sta in `FriendsPanelHost`, reso generico):

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/motion.dart';

/// Pannello laterale sopra la shell e la barra (spec F §8.3, spec G §7.5):
/// entra da destra (con le animazioni ridotte solo in dissolvenza), il resto
/// della finestra si scurisce. Esc e un clic sullo scuro lo chiudono; con un
/// menu aperto sopra la pagina Esc è del menu.
class ShellSidePanel extends StatefulWidget {
  const ShellSidePanel({
    super.key,
    required this.open,
    required this.onClose,
    required this.scrimKey,
    required this.child,
    this.onEscape,
  });

  /// Larghezza, e quota massima della finestra.
  static const width = 360.0;
  static const maxWidthFraction = 0.9;

  final bool open;
  final VoidCallback onClose;

  /// Chiave dello scuro (la cercano i test).
  final Key scrimKey;
  final Widget child;

  /// Esc a pannello aperto: `true` se l'ha usato il contenuto (es. chiude un
  /// campo); altrimenti il pannello si chiude.
  final bool Function()? onEscape;

  @override
  State<ShellSidePanel> createState() => _ShellSidePanelState();
}

class _ShellSidePanelState extends State<ShellSidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: widget.open ? 1 : 0,
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
  void didUpdateWidget(ShellSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
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
  /// indietro di pagina. Con un menu aperto la route della pagina non è
  /// quella corrente: Esc lo gestisce il menu.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        !widget.open ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    if (widget.onEscape?.call() ?? false) return true;
    widget.onClose();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(ShellSidePanel.width,
            constraints.maxWidth * ShellSidePanel.maxWidthFraction);
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
                    key: widget.scrimKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
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
                        ? Opacity(opacity: t, child: widget.child)
                        : FractionalTranslation(
                            translation: Offset(1 - t, 0),
                            child: widget.child,
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

- [ ] **Step 5: il pannello Amici sullo stato comune**

In `lib/features/friends/friends_panel.dart`:

1. Togli `FriendsPanelController` e `friendsPanelProvider` (con i loro commenti). `friendsPanelVisibleProvider` diventa:

```dart
/// Il pannello si vede: aperto e con la funzione amici del plugin.
final friendsPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(shellPanelProvider) == ShellPanel.friends &&
    ref.watch(socialAvailabilityProvider.select((f) => f.friends)));
```

2. In `FriendsPanel` le due costanti di misura diventano una sola:

```dart
  /// Larghezza: quella dei pannelli laterali.
  static const width = ShellSidePanel.width;
```

(`maxWidthFraction` sparisce: ora è di `ShellSidePanel`).

3. Ogni `ref.read(friendsPanelProvider.notifier).close()` (la × dell'intestazione, l'ingresso con il codice, Unisciti di un amico) diventa `ref.read(shellPanelProvider.notifier).close()`.

4. Sostituisci tutta la classe `FriendsPanelHost` e il suo stato (`_FriendsPanelHostState`) con:

```dart
/// Pannello Amici sopra la shell e la barra (spec F §8.3), nel contenitore
/// comune dei pannelli laterali. Con il fuoco nel campo "Ho un codice" il
/// primo Esc chiude il campo, non il pannello.
class FriendsPanelHost extends ConsumerWidget {
  const FriendsPanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Funzione sparita a pannello aperto: si chiude davvero.
    ref.listen(friendsPanelVisibleProvider, (_, visible) {
      if (!visible && ref.read(shellPanelProvider) == ShellPanel.friends) {
        ref.read(shellPanelProvider.notifier).close();
      }
    });
    return ShellSidePanel(
      open: ref.watch(friendsPanelVisibleProvider),
      onClose: () => ref.read(shellPanelProvider.notifier).close(),
      scrimKey: const Key('friends-panel-scrim'),
      onEscape: () {
        final focus = FocusManager.instance.primaryFocus;
        if (focus is! _PartyCodeFocusNode) return false;
        focus.onEscape();
        return true;
      },
      child: const FriendsPanel(),
    );
  }
}
```

5. Import: aggiungi `'../../app/shell_panels.dart'` e `'../../ui/shell_side_panel.dart'`; togli quelli rimasti inutilizzati (l'analyzer li segnala: probabilmente `dart:math`, `package:flutter/services.dart`, `'../../app/motion.dart'`).

In `lib/features/friends/friends_button.dart`: l'import di `'friends_panel.dart'` diventa `'../../app/shell_panels.dart'`; `ref.watch(friendsPanelProvider);` → `ref.watch(shellPanelProvider);` e `onPressed: () => ref.read(friendsPanelProvider.notifier).toggle(),` → `onPressed: () => ref.read(shellPanelProvider.notifier).toggle(ShellPanel.friends),`.

In `lib/app/back_navigation.dart`:
- l'import di `'../features/friends/friends_panel.dart'` diventa `'shell_panels.dart'`;
- nel commento della classe "con il pannello Amici aperto Esc e i tasti indietro (…) chiudono solo lui" diventa "con un pannello laterale aperto (Amici o Notifiche) Esc e i tasti indietro (…) chiudono solo lui";
- in `_onKey`:

```dart
    // Con un pannello laterale aperto Esc chiude solo lui (lo gestisce il
    // pannello). `shellPanelProvider` non dipende da altri provider.
    if (key == LogicalKeyboardKey.escape &&
        ref.read(shellPanelProvider) != ShellPanel.none) {
      return false;
    }
```

- in `_goBack`:

```dart
    // Con un pannello laterale aperto i tasti indietro chiudono lui e basta
    // (Esc non arriva qui: lo gestisce il pannello).
    if (ref.read(shellPanelProvider) != ShellPanel.none) {
      ref.read(shellPanelProvider.notifier).close();
      return true;
    }
```

- [ ] **Step 6: i test passano**

Run: `flutter test test/app test/features/friends`
Expected: PASS (anche `friends_shell_test.dart`, che non cambia: chiavi, tooltip ed Esc restano gli stessi).

- [ ] **Step 7: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/app lib/ui/shell_side_panel.dart lib/features/friends test/app test/features/friends
git commit -m "refactor(app): one side panel at a time with a shared container"
```

## Gruppo D — interfaccia

### Task 12: il pannello Notifiche (contenuto) e l'ora relativa

**Files:**
- Create: `lib/features/inbox/inbox_time.dart`
- Create: `lib/features/inbox/inbox_panel.dart`
- Test: `test/features/inbox/inbox_time_test.dart` (nuovo), `test/features/inbox/inbox_panel_test.dart` (nuovo)

- [ ] **Step 1: test che falliscono**

Crea `test/features/inbox/inbox_time_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/features/inbox/inbox_time.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('ora relativa delle voci', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 10, 3, 20, 30);
    String label(DateTime at, [AppLocalizations? l]) =>
        inboxTimeLabel(at, now, l ?? it);

    expect(label(now.subtract(const Duration(seconds: 30))), 'adesso');
    expect(label(now.add(const Duration(seconds: 30))), 'adesso',
        reason: 'un orologio un po\' avanti sul server');
    expect(label(now.subtract(const Duration(minutes: 5))), '5 min fa');
    expect(label(now.subtract(const Duration(hours: 2))), '2 h fa');
    expect(label(DateTime(2026, 10, 2, 23)), 'ieri');
    expect(label(DateTime(2026, 10, 2, 8)), 'ieri');
    expect(label(DateTime(2026, 9, 30, 12)), '3 giorni fa');
    expect(label(DateTime(2026, 9, 27, 12)), '6 giorni fa');
    expect(label(DateTime(2026, 9, 26, 12)), '26 set');
    expect(label(DateTime(2026, 9, 26, 12), en), 'Sep 26');
    expect(label(now.subtract(const Duration(minutes: 5)), en), '5 min ago');
    // Poco dopo mezzanotte una voce di poco prima resta in minuti.
    expect(
        inboxTimeLabel(
            DateTime(2026, 10, 2, 23, 50), DateTime(2026, 10, 3, 0, 10), it),
        '20 min fa');
  });
}
```

Crea `test/features/inbox/inbox_panel_test.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSocialApi api;
  late FakeSyncPlayApi syncPlay;
  late StreamController<ServerEvent> events;

  setUp(() {
    api = FakeSocialApi();
    syncPlay = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    syncPlay.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
  });

  tearDown(() => events.close());

  /// Cinque minuti fa: l'ora relativa è "5 min fa" qualunque sia il giorno
  /// della prova.
  DateTime fiveMinutesAgo() =>
      clock.now().toUtc().subtract(const Duration(minutes: 5));

  Future<void> pumpPanel(WidgetTester tester,
      {List<GroupInfo> parties = const []}) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
        ),
      ),
      overrides: [
        ...socialTestOverrides(api,
            events: events.stream,
            features: const SocialFeatures(parties: true, inbox: true)),
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory(parties)),
        syncPlayApiProvider.overrideWithValue(syncPlay),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
      ],
    );
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));

  testWidgets('vuota: "Nessuna notifica", niente Svuota', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Notifiche'), findsOneWidget);
    expect(find.text('Nessuna notifica'), findsOneWidget);
    expect(find.text('Svuota'), findsNothing);
  });

  testWidgets('caricamento non riuscito: "Notifiche non disponibili" e Riprova',
      (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    expect(find.text('Notifiche non disponibili'), findsOneWidget);

    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Stasera manutenzione'), findsOneWidget);
  });

  testWidgets('annuncio: etichetta, testo, ora; la × compare al passaggio e '
      'toglie la voce', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    expect(find.text('Annuncio'), findsOneWidget);
    expect(find.text('Stasera manutenzione'), findsOneWidget);
    expect(find.text('5 min fa'), findsOneWidget);

    Opacity removeOpacity() => tester.widget<Opacity>(find
        .ancestor(of: find.byTooltip('Rimuovi'), matching: find.byType(Opacity))
        .first);
    expect(removeOpacity().opacity, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Annuncio')));
    await tester.pump();
    expect(removeOpacity().opacity, 1);

    await tester.tap(find.byTooltip('Rimuovi'));
    await tester.pump();
    expect(api.calls, contains('remove-entry a1'));
    expect(find.text('Stasera manutenzione'), findsNothing);
  });

  testWidgets('× non riuscita: lo dice', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.network;
    await tester.tap(find.byTooltip('Rimuovi'));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile aggiornare le notifiche'),
        findsOneWidget);
  });

  testWidgets('invito: Unisciti se il party è nell\'elenco, altrimenti '
      '"Party finito"', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
      testInvite(
          id: 'i2',
          groupId: 'g2',
          title: 'Alien',
          createdAt: fiveMinutesAgo()),
    ], unread: 2);
    await pumpPanel(tester, parties: [testGroup()]);
    expect(find.text('Luigi ti invita a guardare'), findsNWidgets(2));
    expect(find.text('Dune'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i2')), findsNothing);
    expect(find.text('Party finito'), findsOneWidget);
  });

  testWidgets('invito: Unisciti entra e chiude il pannello; poi "Ci sei già"',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', groupId: 'g1', createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester, parties: [testGroup()]);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();

    await tester.tap(find.byKey(const Key('inbox-join-i1')));
    await tester.pumpAndSettle();
    expect(syncPlay.calls, contains('join g1'));
    expect(container.read(shellPanelProvider), ShellPanel.none);
    expect(find.text('Ci sei già'), findsOneWidget);
    expect(find.byKey(const Key('inbox-join-i1')), findsNothing);

    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('pallino dorato sulle voci non lette all\'apertura',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(id: 'a2', seq: 2, createdAt: fiveMinutesAgo()),
      testAnnouncement(
          id: 'a1', seq: 1, read: true, createdAt: fiveMinutesAgo()),
    ], unread: 1);
    await pumpPanel(tester);
    final container = containerOf(tester);
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('inbox-unread-a2')), findsOneWidget);
    expect(find.byKey(const Key('inbox-unread-a1')), findsNothing);
    expect(api.calls, contains('read 2'));
  });

  testWidgets('Svuota → Conferma per 4 s; Conferma svuota', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testAnnouncement(createdAt: fiveMinutesAgo())], unread: 1);
    await pumpPanel(tester);

    await tester.tap(find.text('Svuota'));
    await tester.pump();
    expect(find.text('Conferma'), findsOneWidget);
    await tester.pump(InboxPanel.clearConfirmFor);
    expect(find.text('Svuota'), findsOneWidget);

    await tester.tap(find.text('Svuota'));
    await tester.pump();
    await tester.tap(find.text('Conferma'));
    await tester.pump();
    expect(api.calls, contains('clear-inbox'));
    expect(find.text('Nessuna notifica'), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/inbox`
Expected: errori di compilazione (`inbox_time.dart`, `inbox_panel.dart` non esistono).

- [ ] **Step 3: l'ora relativa**

Crea `lib/features/inbox/inbox_time.dart`:

```dart
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';

/// Fino a quanti giorni fa l'ora si dice in giorni; dopo, la data.
const inboxDaysShown = 6;

/// Ora relativa di una voce della cassetta (spec G §7.6): "adesso" (meno di
/// un minuto, anche nel futuro se l'orologio del server è avanti), "5 min
/// fa", "2 h fa" (stesso giorno), "ieri", "3 giorni fa" (fino a
/// [inboxDaysShown]), poi la data breve nella lingua dell'app.
String inboxTimeLabel(DateTime createdAt, DateTime now, AppLocalizations l) {
  final elapsed = now.difference(createdAt);
  if (elapsed < const Duration(minutes: 1)) return l.inboxNow;
  if (elapsed < const Duration(hours: 1)) {
    return l.inboxMinutesAgo(elapsed.inMinutes);
  }
  final local = createdAt.toLocal();
  final days = _calendarDays(local, now.toLocal());
  if (days <= 0) return l.inboxHoursAgo(elapsed.inHours);
  if (days == 1) return l.inboxYesterday;
  if (days <= inboxDaysShown) return l.inboxDaysAgo(days);
  return DateFormat.MMMd(l.localeName).format(local);
}

/// Giorni di calendario tra le due date (locali), senza l'effetto dell'ora
/// legale.
int _calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
```

- [ ] **Step 4: il pannello**

Crea `lib/features/inbox/inbox_panel.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/inbox_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../watch_party/watch_party_actions.dart';
import '../watch_party/watch_party_directory.dart';
import '../watch_party/watch_party_session.dart';
import 'inbox_controller.dart';
import 'inbox_time.dart';

/// Esegue un'azione sulla cassetta; se non riesce lo dice con una snackbar
/// (spec G §8).
Future<void> runInboxAction(
    BuildContext context, Future<SocialFailure?> Function() action) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = await action();
  if (failure == null) return;
  messenger?.showSnackBar(SnackBar(content: Text(l.inboxActionFailed)));
}

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);
const _timeStyle = TextStyle(color: WfColors.creamMuted, fontSize: 12);

/// Lo stesso gruppo, con o senza trattini e maiuscole.
String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Contenuto del pannello "Notifiche" (spec G §7.5–7.6): intestazione con
/// Svuota, voci dalla più recente.
class InboxPanel extends ConsumerWidget {
  const InboxPanel({super.key});

  /// Larghezza: quella dei pannelli laterali.
  static const width = ShellSidePanel.width;

  /// Per quanto resta "Conferma" dopo "Svuota".
  static const clearConfirmFor = Duration(seconds: 4);

  /// Larghezza della miniatura dell'invito e dell'icona dell'annuncio.
  static const leadingSize = 40.0;

  /// Altezza della miniatura dell'invito (locandina 2:3).
  static const posterHeight = 60.0;

  /// Lato del pallino delle voci non lette.
  static const dotSize = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hasEntries = ref.watch(
        inboxControllerProvider.select((s) => s.snapshot.entries.isNotEmpty));
    return Material(
      key: const Key('inbox-panel'),
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
                  child: Text(l.inboxTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                if (hasEntries) const _ClearButton(),
                IconButton(
                  tooltip: l.friendsClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () =>
                      ref.read(shellPanelProvider.notifier).close(),
                ),
              ],
            ),
          ),
          const Expanded(child: _Entries()),
        ],
      ),
    );
  }
}

/// "Svuota" → "Conferma" per [InboxPanel.clearConfirmFor] (nell'app non ci
/// sono dialoghi).
class _ClearButton extends ConsumerStatefulWidget {
  const _ClearButton();

  @override
  ConsumerState<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends ConsumerState<_ClearButton> {
  Timer? _confirm;

  @override
  void dispose() {
    _confirm?.cancel();
    super.dispose();
  }

  void _ask() {
    _confirm?.cancel();
    setState(() {
      _confirm = Timer(InboxPanel.clearConfirmFor, () {
        if (mounted) setState(() => _confirm = null);
      });
    });
  }

  void _clear() {
    _confirm?.cancel();
    setState(() => _confirm = null);
    unawaited(runInboxAction(
        context, () => ref.read(inboxControllerProvider.notifier).clear()));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final confirming = _confirm != null;
    return TextButton(
      key: Key(confirming ? 'inbox-clear-confirm' : 'inbox-clear'),
      onPressed: confirming ? _clear : _ask,
      style: TextButton.styleFrom(
        foregroundColor: confirming ? WfColors.error : WfColors.creamMuted,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(confirming ? l.inboxClearConfirm : l.inboxClear),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final inbox = ref.watch(inboxControllerProvider);
    if (!inbox.loaded) {
      // Mentre carica la prima volta il pannello resta vuoto.
      if (!inbox.failed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.inboxUnavailable, style: _mutedStyle),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(
                  ref.read(inboxControllerProvider.notifier).reload()),
              style: TextButton.styleFrom(
                foregroundColor: WfColors.gold,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    final entries = inbox.snapshot.entries;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(l.inboxEmpty, style: _mutedStyle),
      );
    }
    final now = clock.now();
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final entry in entries)
          _EntryTile(
            key: ValueKey('inbox-${entry.id}'),
            entry: entry,
            highlighted: inbox.highlighted.contains(entry.id),
            time: inboxTimeLabel(entry.createdAt, now, l),
          ),
      ],
    );
  }
}

/// Una voce: pallino (se evidenziata), miniatura o icona, contenuto, ×
/// (visibile al passaggio del mouse e col fuoco).
class _EntryTile extends ConsumerStatefulWidget {
  const _EntryTile({
    super.key,
    required this.entry,
    required this.highlighted,
    required this.time,
  });

  final InboxEntry entry;
  final bool highlighted;
  final String time;

  @override
  ConsumerState<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends ConsumerState<_EntryTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: InboxPanel.dotSize,
              child: widget.highlighted
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        key: Key('inbox-unread-${entry.id}'),
                        width: InboxPanel.dotSize,
                        height: InboxPanel.dotSize,
                        decoration: const BoxDecoration(
                            color: WfColors.gold, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            switch (entry) {
              InviteEntry() => _InvitePoster(entry: entry),
              AnnouncementEntry() => const _AnnouncementIcon(),
            },
            const SizedBox(width: 12),
            Expanded(
              child: switch (entry) {
                InviteEntry() =>
                  _InviteContent(entry: entry, time: widget.time),
                AnnouncementEntry() =>
                  _AnnouncementContent(entry: entry, time: widget.time),
              },
            ),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Opacity(
                opacity: _hovered || _focused ? 1 : 0,
                child: IconButton(
                  tooltip: l.inboxRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.x,
                      size: 16, color: WfColors.creamMuted),
                  onPressed: () => unawaited(runInboxAction(
                      context,
                      () => ref
                          .read(inboxControllerProvider.notifier)
                          .remove(entry.id))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitePoster extends ConsumerWidget {
  const _InvitePoster({required this.entry});

  final InviteEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageId = entry.imageItemId;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: InboxPanel.leadingSize,
        height: InboxPanel.posterHeight,
        child: WfImage(
          image: imageId == null
              ? null
              : ref.watch(imageUrlsProvider).primaryOf(imageId),
        ),
      ),
    );
  }
}

class _AnnouncementIcon extends StatelessWidget {
  const _AnnouncementIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: InboxPanel.leadingSize,
        height: InboxPanel.leadingSize,
        decoration: const BoxDecoration(
            color: WfColors.surfaceHigh, shape: BoxShape.circle),
        child: const Icon(LucideIcons.megaphone,
            size: 18, color: WfColors.gold),
      );
}

/// Invito: chi, cosa e Unisciti finché il party c'è (spec G §7.6).
class _InviteContent extends ConsumerWidget {
  const _InviteContent({required this.entry, required this.time});

  final InviteEntry entry;
  final String time;

  /// Entra nel party; riuscito, il pannello si chiude.
  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final joined = await joinWatchParty(context, ref, entry.groupId);
    if (joined && context.mounted) {
      ref.read(shellPanelProvider.notifier).close();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final groupId = _normalizeId(entry.groupId);
    final inGroupId = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? s.group?.id : null));
    // L'invito rende il party visibile finché esiste: se è nell'elenco, si
    // può entrare.
    final listed = ref.watch(watchPartyDirectoryProvider
        .select((groups) => groups.any((g) => _normalizeId(g.id) == groupId)));
    final Widget action;
    if (inGroupId != null && _normalizeId(inGroupId) == groupId) {
      action = Text(l.inboxAlreadyIn, style: _mutedStyle);
    } else if (listed) {
      action = TextButton(
        key: Key('inbox-join-${entry.id}'),
        onPressed: () => unawaited(_join(context, ref)),
        style: TextButton.styleFrom(
          foregroundColor: WfColors.gold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(l.watchPartyJoin),
      );
    } else {
      action = Text(l.inboxPartyEnded, style: _mutedStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.inboxInviteFrom(entry.fromName),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: _mutedStyle),
        Text(entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: WfColors.cream, fontWeight: FontWeight.w600)),
        Row(
          children: [
            Text(time, style: _timeStyle),
            const Spacer(),
            action,
          ],
        ),
      ],
    );
  }
}

/// Annuncio dell'admin: etichetta e testo intero, selezionabile.
class _AnnouncementContent extends StatelessWidget {
  const _AnnouncementContent({required this.entry, required this.time});

  final AnnouncementEntry entry;
  final String time;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.inboxAnnouncement,
            style: const TextStyle(
                color: WfColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        SelectableText(entry.text,
            style: const TextStyle(color: WfColors.cream)),
        const SizedBox(height: 4),
        Text(time, style: _timeStyle),
      ],
    );
  }
}
```

(`WfColors.surfaceHigh`, `WfColors.error`, `WfColors.gold`, `WfColors.cream`, `WfColors.creamMuted` esistono già in `lib/app/theme.dart`. Se un nome è diverso, usa quello vero e segnalalo.)

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/inbox`
Expected: PASS.

- [ ] **Step 6: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/features/inbox test/features/inbox
git commit -m "feat(app): add the notifications panel"
```

### Task 13: icona nella barra, pannello sopra la shell

**Files:**
- Create: `lib/features/inbox/inbox_button.dart`
- Modify: `lib/app/app_shell.dart`
- Test: `test/features/inbox/inbox_shell_test.dart` (nuovo)

- [ ] **Step 1: test che falliscono**

Crea `test/features/inbox/inbox_shell_test.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/app_shell.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_button.dart';
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
      {SocialFeatures features =
          const SocialFeatures(friends: true, inbox: true)}) async {
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

  Finder badge(String text) => find.descendant(
      of: find.byKey(const Key('inbox-button')), matching: find.text(text));

  test('numero sull\'icona: oltre 99 "99+"', () {
    expect(inboxBadgeLabel(5), '5');
    expect(inboxBadgeLabel(99), '99');
    expect(inboxBadgeLabel(100), '99+');
  });

  testWidgets('senza la cassetta: niente icona', (tester) async {
    await pumpShell(tester, features: const SocialFeatures(friends: true));
    expect(find.byKey(const Key('inbox-button')), findsNothing);
  });

  testWidgets('senza accesso ai watch party: Notifiche sì, Amici no',
      (tester) async {
    await pumpShell(tester, features: const SocialFeatures(inbox: true));
    expect(find.byKey(const Key('inbox-button')), findsOneWidget);
    expect(find.byKey(const Key('friends-button')), findsNothing);
  });

  testWidgets('icona con i non letti; aprendo diventano letti; Esc e un clic '
      'fuori chiudono', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testAnnouncement(
          seq: 3,
          createdAt: clock.now().toUtc().subtract(const Duration(minutes: 5))),
    ], unread: 1);
    await pumpShell(tester);
    await tester.pump();
    expect(badge('1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inbox-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-panel')), findsOneWidget);
    expect(api.calls, contains('read 3'));
    expect(badge('1'), findsNothing);
    expect(find.byKey(const Key('inbox-unread-a1')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('inbox-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-panel')), findsNothing);
  });

  testWidgets('un avviso InboxChanged aggiorna il numero', (tester) async {
    await pumpShell(tester);
    await tester.pump();
    expect(badge('1'), findsNothing);

    api.inboxSnapshot =
        InboxSnapshot(entries: [testAnnouncement()], unread: 1);
    events.add(inboxChangedReceived());
    await tester.pump();
    await tester.pump();
    expect(badge('1'), findsOneWidget);
  });

  testWidgets('un pannello alla volta: Notifiche chiude Amici',
      (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('friends-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsOneWidget);

    // La barra è sotto lo scuro del pannello Amici: si apre Notifiche dallo
    // stato.
    ProviderScope.containerOf(tester.element(find.byType(AppShell)))
        .read(shellPanelProvider.notifier)
        .open(ShellPanel.inbox);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('friends-panel')), findsNothing);
    expect(find.byKey(const Key('inbox-panel')), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/inbox/inbox_shell_test.dart`
Expected: errori di compilazione (`inbox_button.dart` non esiste).

- [ ] **Step 3: icona e contenitore**

Crea `lib/features/inbox/inbox_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shell_side_panel.dart';
import '../social/social_providers.dart';
import 'inbox_controller.dart';
import 'inbox_panel.dart';

/// Oltre questo numero l'icona mostra "99+".
const inboxBadgeMax = 99;

/// Il numero sull'icona.
String inboxBadgeLabel(int count) =>
    count > inboxBadgeMax ? '$inboxBadgeMax+' : '$count';

/// Icona "Notifiche" nella barra, con il numero dorato dei non letti (spec
/// G §7.4). Solo con la cassetta del plugin, anche senza accesso ai watch
/// party.
class InboxButton extends ConsumerWidget {
  const InboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.inbox))) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final count = ref.watch(inboxControllerProvider.select((s) => s.unread));
    // Tiene vivo lo stato dei pannelli finché la barra c'è.
    ref.watch(shellPanelProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        key: const Key('inbox-button'),
        tooltip: l.inboxTitle,
        onPressed: () =>
            ref.read(shellPanelProvider.notifier).toggle(ShellPanel.inbox),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(inboxBadgeLabel(count)),
          backgroundColor: WfColors.gold,
          textColor: WfColors.bg,
          child: const Icon(LucideIcons.inbox, size: 20, color: WfColors.cream),
        ),
      ),
    );
  }
}

/// Il pannello si vede: aperto e con la cassetta del plugin.
final inboxPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(shellPanelProvider) == ShellPanel.inbox &&
    ref.watch(socialAvailabilityProvider.select((f) => f.inbox)));

/// Pannello Notifiche sopra la shell e la barra (spec G §7.5), nel
/// contenitore comune dei pannelli laterali.
class InboxPanelHost extends ConsumerWidget {
  const InboxPanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Funzione sparita a pannello aperto: si chiude davvero.
    ref.listen(inboxPanelVisibleProvider, (_, visible) {
      if (!visible && ref.read(shellPanelProvider) == ShellPanel.inbox) {
        ref.read(shellPanelProvider.notifier).close();
      }
    });
    return ShellSidePanel(
      open: ref.watch(inboxPanelVisibleProvider),
      onClose: () => ref.read(shellPanelProvider.notifier).close(),
      scrimKey: const Key('inbox-panel-scrim'),
      child: const InboxPanel(),
    );
  }
}
```

- [ ] **Step 4: nella shell**

In `lib/app/app_shell.dart`:
- aggiungi l'import `'../features/inbox/inbox_button.dart'`;
- dopo `const FriendsButton(),` aggiungi `const InboxButton(),`;
- dopo `const Positioned.fill(child: FriendsPanelHost()),`:

```dart
            // Pannello Notifiche, sopra la barra e le schede (spec G §7.5).
            const Positioned.fill(child: InboxPanelHost()),
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/inbox test/app test/features/friends`
Expected: PASS.

- [ ] **Step 6: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/features/inbox lib/app/app_shell.dart test/features/inbox
git commit -m "feat(app): add the notifications icon and panel to the shell"
```

## Gruppo E — chiusura

### Task 14: spec allineato, verifica finale, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`

- [ ] **Step 1: allinea lo spec al codice**

Nello spec G:
- **Stato** (in testa): "approvato; piano 13a realizzato (`docs/superpowers/plans/2026-10-03-wonderflix-13a-cassetta-notifiche.md`); nuovi titoli e release nel piano 13b".
- **§6.3**, dopo la tabella degli endpoint: "`GET Info` sta in un controller suo (`InfoController`) con `[Authorize]` semplice: un attributo sul metodo non allarga la policy SyncPlay della classe. L'id di una voce in `DELETE Inbox/Entries/{id}` è una stringa senza vincoli di rotta (un vincolo risponderebbe 404, cioè "plugin assente")."
- **§6.8**: "La casella **Notify new titles** arriva con il piano 13b; nel 13a la pagina ha solo l'annuncio, e il plugin resta `BasePlugin<BasePluginConfiguration>`."
- **§7.2**, in fondo: "Senza accesso ai watch party l'app chiede `Info` lo stesso e tiene solo `inbox`: amici e party restano spenti."
- **§7.5**, primo punto: aggiungi "Lo stato è unico (`shellPanelProvider`: nessuno / amici / notifiche) e il contenitore è comune (`ShellSidePanel`, usato anche dal pannello Amici)." e, al punto **Apertura**: "Una voce che arriva a pannello aperto prende il pallino e viene segnata subito come letta."
- **§7.6**, ora relativa: "{n} h fa" vale per lo **stesso giorno di calendario**; poi "ieri".
- **§9**: togli `inboxTooltip` (tooltip e titolo usano `inboxTitle`), `inboxRetry` (si usa `retry`), `inboxJoin` (si usa `watchPartyJoin`), `diagnosticsFeatureInbox` (la diagnostica scrive "notifiche" come testo fisso, come "amici" e "party"); il segnaposto dei numeri è `{count}`; la × dell'intestazione usa `friendsClose` ("Chiudi"). Le chiavi `inboxNewTitles`, `inboxMovies`, `inboxEpisodes`, `inboxNewEpisodes`, `inboxShowAll`, `inboxMore` restano per il piano 13b.

- [ ] **Step 2: verifica finale**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi (circa 172), nessun warning.

Run: `flutter analyze`
Expected: nessun problema.

Run: `flutter test`
Expected: tutti verdi (1415 di partenza più i nuovi).

- [ ] **Step 3: build di release per la prova**

Copia `config/wonderflix.json` dalla root del repository principale nel worktree (se non c'è già), poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe`. Se la build tocca `windows/flutter/generated_plugin*` con soli fine riga: `git checkout -- windows/flutter/`.

- [ ] **Step 4: commit**

```bash
git add docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md
git commit -m "docs: align spec G with plan 13a"
```

## Prova manuale (con l'utente, sul server reale)

Il plugin 1.2.0 è già sul server (Task 6). L'exe lo avvia **sempre** l'utente (le app lanciate da questa sessione hanno l'AppData virtualizzato); la seconda istanza con `WONDERFLIX_PROFILE=b` e un secondo utente Jellyfin.

1. **Annuncio.** Dashboard di Jellyfin → menu laterale → "WonderFlix Watch Party" → scrivi un messaggio → **Send to everyone** → "Sent to N users". In tutte e due le app l'icona Notifiche mostra **1** entro un attimo.
2. **Pannello.** Clic sull'icona: si apre da destra, l'annuncio ha il pallino dorato, il numero sparisce. Testo selezionabile, ora relativa. Esc, × e clic fuori chiudono. La × della voce compare passando col mouse e la toglie; **Svuota** → **Conferma** (4 s) svuota.
3. **Invito ad app chiusa.** A crea un party (anche Privato) e fa partire il film; B chiude WonderFlix; A usa **Invita amici** su B. B riapre l'app: icona **1**, nel pannello l'invito con la locandina, "A ti invita a guardare" e il titolo, **Unisciti** → B entra nel party e il pannello si chiude. A party finito l'invito dice "Party finito".
4. **Invito ad app aperta.** Come oggi compare la scheda in alto a destra; in più l'invito è nella cassetta. Un secondo invito allo stesso party non crea una voce nuova: quella di prima torna in cima, non letta.
5. **Un pannello alla volta.** Con Amici aperto, Esc o un clic fuori lo chiudono; aprendo Notifiche, Amici non resta aperto. Alt+← con un pannello aperto chiude il pannello, non la pagina.
6. **Diagnostica** (Impostazioni → copia diagnostica): "Funzioni del plugin: amici, party, notifiche".
7. **Facoltativo:** un utente senza accesso ai watch party vede l'icona Notifiche e l'annuncio, non l'icona Amici.

Se qualcosa non va, le correzioni si fanno con TDD nello stesso worktree prima del merge.

## Dopo la prova (fuori dai task)

- Con l'ok dell'utente ("fai il merge su main e pusha"): `git fetch`, fast-forward di `main` (rebase se l'utente ha fatto commit dal sito), push, rimozione di worktree e branch.
- **Nessuna release** dopo il 13a: il plugin 1.2.0 dal Catalogo e l'app 0.7.0 (non obbligatoria) arrivano con il piano 13b, dopo i nuovi titoli. Sul server resta la copia manuale `WonderFlix Watch Party_1.2.0.0` fino alla release.
