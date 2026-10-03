# WonderFlix — Piano 13b: nuovi titoli e release (plugin 1.2.0, app 0.7.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** seconda metà della Spec G: il plugin raccoglie i film e gli episodi nuovi della libreria in "ondate" e lascia a ogni utente una voce "Novità" nella cassetta; l'admin ha nella Dashboard la casella "Notify new titles" e il pulsante "Send now"; l'app mostra la voce Novità. Poi la release: plugin 1.2.0 dal Catalogo, app 0.7.0 non obbligatoria, issue #7 chiusa come non pianificata.

**Spec:** `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md` (§6.6, §6.8, §7.1, §7.6, §9, §11). Il piano 13a (`docs/superpowers/plans/2026-10-03-wonderflix-13a-cassetta-notifiche.md`) è realizzato e su `main` (`866506f`).

**Decisioni del piano (approvate dall'utente il 2026-10-04):**
1. **Serie nuove:** come nello spec, si annunciano solo i film e gli episodi delle serie **seguite**; una serie appena arrivata che nessuno segue non compare.
2. **"Send now"** nella pagina della Dashboard (solo admin): mostra quanti titoli aspettano e chiude l'ondata subito, anche durante una scansione.
3. **Casella spenta a metà ondata:** l'ondata in corso si butta; con la casella spenta non si raccoglie niente.
4. **Attesa tecnica** (dalla ricerca): passati i 15 minuti di quiete, se Jellyfin sta ancora scansionando la libreria o un titolo non ha ancora i metadati, l'ondata aspetta; il limite di 2 ore resta.

**Architecture:**
- **Plugin:** `PluginConfiguration.NotifyNewTitles` (letta ogni volta tramite `INewTitlesSettings`) → `NewTitlesHostedService` ascolta `ILibraryManager.ItemAdded/ItemRemoved`, filtra con `NewTitleRules` (solo film ed episodi veri, anche per i tolti) e chiama `NewTitlesCollector` (O(1) sotto lock). Il collector tiene una `NewTitlesWave` (id aggiunti, id esterni dei tolti, tempi), la controlla ogni minuto, alla chiusura rilegge i titoli con `ILibraryTitles` (adattatore `JellyfinLibraryTitles`: `GetItemById`, conteggi sul database per "serie seguita") e consegna una voce per utente a `InboxService.AddNewTitlesAsync`. `InboxController` aggiunge gli endpoint admin `GET Inbox/NewTitles` e `POST Inbox/NewTitles/Send`; la pagina della Dashboard ha la casella e "Send now".
- **App:** `NewTitlesEntry` (+ `NewTitleMovie/Episode/Series`, `formatEpisodeRanges`) in `lib/core/social/inbox_models.dart` → pannello Notifiche: icona `sparkles`, "Novità: 2 film, 10 episodi", prime 5 righe, "Mostra tutto (N)", "…e altri N titoli"; una riga apre la scheda (`/item/<id>`) e chiude il pannello.

**Tech Stack:** C# net9.0 contro Jellyfin.Controller/Model 10.11.0 (test con le dll 10.11.9), xUnit, `Microsoft.Extensions.TimeProvider.Testing`; Flutter 3.47.5, flutter_riverpod 3, go_router 18, lucide_icons_flutter.

**Worktree:** `.claude/worktrees/piano-13b`, branch `feat/piano-13b`. **Base:** `main` con questo piano. **Test a inizio piano:** 1475 Flutter, 185 plugin.

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce. Non fare push. Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-13b`). Comandi git semplici, niente `git -C`, niente variabili nei comandi git. Mai `git checkout -- <file>` su un file che hai modificato.
- **Prima di ogni commit lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde e senza warning (il plugin ha `TreatWarningsAsErrors`). **Prima di ogni commit lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit. Dopo ogni modifica agli ARB: `flutter gen-l10n` (la cartella `lib/l10n/gen/` non si committa).
- **Formattazione e fine riga:** niente `dart format` né `dotnet format` su file interi; edit mirati; ogni file tiene le sue terminazioni di riga (molti file della working copy sono CRLF, l'indice è LF con `core.autocrlf=true`).
- **Durate, misure, limiti:** costanti nominate e commentate. Commenti in italiano, codice in inglese (anche nel C#: commenti `///` in italiano, identificatori in inglese). Nel C# sempre le graffe.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; durate da `WfMotion`; `clock.now()`, mai `DateTime.now()`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, un setter non pubblico di Jellyfin): correggilo in modo minimo, nello spirito del piano, e segnalalo. Preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-04 (dump per riflessione delle API pubbliche di Jellyfin 10.11.0 e 10.11.9; sorgenti di jellyfin v10.11.0/v10.11.9, jellyfin-web v10.11.9, plugin TVDB e template dei plugin):

- **API usate, identiche in 10.11.0 e 10.11.9:** `ILibraryManager.ItemAdded`/`ItemRemoved` (`EventHandler<ItemChangeEventArgs>`, `ItemChangeEventArgs.Item` con setter), `ILibraryManager.GetItemById(Guid)` (null se non c'è; lancia con `Guid.Empty`), `int ILibraryManager.GetCount(InternalItemsQuery)`, `bool ILibraryManager.IsScanRunning`; `InternalItemsQuery(User)` con `Guid[] ItemIds`, `Guid[] ExcludeItemIds`, `BaseItemKind[] IncludeItemTypes`, `string SeriesPresentationUniqueKey`, `bool? IsFavorite`, `bool? IsPlayed`, `bool? IsResumable`, `bool? IsVirtualItem`; `BaseItem`: `Path`, `IsVirtualItem`, `ExtraType?`, `OwnerId`, `DateLastRefreshed`, `ProviderIds` (dizionario senza maiuscole), `ProductionYear`, `ParentIndexNumber`, `IndexNumber`, `Name`; `Episode`: `SeriesId`, `SeriesName`, `SeriesPresentationUniqueKey`, `FindSeriesPresentationUniqueKey()`; `ProviderIdsExtensions.TryGetProviderId(IHasProviderIds, MetadataProvider, out string?)` (`MediaBrowser.Model.Entities`); `MetadataProvider.Tmdb/Imdb/Tvdb`; `Jellyfin.Data.Enums.BaseItemKind.Episode`.
- **Eventi della libreria:** arrivano **sincroni, uno per elemento, dai thread della scansione** (anche in parallelo), dalla coda dei refresh e dalle API. Ogni chiamata è in un try/catch di Jellyfin, ma un'eccezione ferma gli altri ascoltatori di quell'evento: i gestori non devono lanciare, devono essere O(1) e non toccare il database. `ItemAdded` arriva per **ogni** tipo (serie, stagioni, collezioni, persone…), e anche per gli **episodi segnaposto "mancanti"** del plugin TVDB (`IsVirtualItem = true`, senza `Path`). Gli extra e i trailer locali non passano da `ItemAdded` (hanno `ExtraType` e/o `OwnerId`); `Trailer` non deriva da `Movie`.
- **Insidia principale:** quando arriva un episodio vero, TVDB **toglie il suo segnaposto** (stesso id TVDB) → `ItemRemoved` di un `Episode` virtuale. Il filtro "titolo vero" va applicato **anche ai tolti**, altrimenti ogni episodio nuovo sembrerebbe una sostituzione.
- **Metadati:** all'`ItemAdded` l'elemento è appena risolto: nome dal file, id esterni spesso vuoti, numeri di stagione/episodio spesso `null`; il refresh dei metadati arriva dopo (con `ItemUpdated`) e lo dice `DateLastRefreshed != DateTime.MinValue`. Quindi gli aggiunti si **rileggono alla chiusura** dell'ondata; per i tolti gli id esterni si leggono **subito** nel gestore. L'id di un elemento viene dal percorso: un file rinominato (Radarr/Sonarr) = `ItemRemoved` del vecchio + `ItemAdded` del nuovo, in ordine qualunque; lo stesso percorso aggiornato = solo `ItemUpdated`.
- **"Serie seguita":** `IUserDataManager.GetUserData` legge i dati utente in memoria, che Jellyfin azzera sul genitore a ogni aggiunta: può dire "non preferita" per una preferita. Si usano **conteggi sul database** con `GetCount`: preferita (`ItemIds = [serie]`, `IsFavorite = true`), poi un altro episodio visto (`IsPlayed`), poi uno iniziato (`IsResumable`, posizione > 0), con `SeriesPresentationUniqueKey`, escludendo gli episodi nuovi. I filtri per utente richiedono il costruttore `InternalItemsQuery(user)`.
- **Configurazione del plugin:** `Plugin` è costruito dopo `RegisterServices` e prima dei servizi in background, **non è nel DI**: si legge con un `Plugin.Instance` statico. Salvando dalla Dashboard Jellyfin **sostituisce** l'oggetto `Configuration` (e scrive `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`): la configurazione va **letta ogni volta**, mai messa da parte. Un XML che non corrisponde viene sostituito dai valori predefiniti.
- **Pagina della Dashboard (jellyfin-web 10.11):** `pageshow` arriva sempre; `ApiClient.getPluginConfiguration(id)` / `ApiClient.updatePluginConfiguration(id, config)` / `Dashboard.processPluginConfigurationUpdateResult` (toglie il caricamento e mostra "Impostazioni salvate"); i nomi delle proprietà sono PascalCase; la casella vuole `emby-checkbox` in `data-require`.
- **Test del plugin:** `FakeTimeProvider.Advance` esegue i timer scaduti in modo sincrono, una volta per periodo attraversato. `InterfaceStub<T>`: i gestori si registrano per nome (`add_ItemAdded`, `GetItemById`, `GetCount`, `GetUserById`). `new Movie { … }`, `new Episode { … }`, `new Series { … }` si costruiscono nei test; `new User("mario", "provider", "reset")` dà un utente vero.
- **App, navigazione:** `/item/<id>` apre la scheda di un film o di una serie (`lib/app/navigation.dart`, `itemRoute`). Il pannello Notifiche sta sotto il router della shell, quindi `context.push` funziona; nei widget test con `pumpApp` (senza router) non si naviga: la prova della navigazione usa un `GoRouter` vero (come `test/features/friends/friends_shell_test.dart`, "con un vero router").
- **App, modelli:** `InboxEntry` è `sealed`: aggiungendo `NewTitlesEntry` vanno aggiornati nello **stesso task** gli `switch` di `lib/features/inbox/inbox_panel.dart` (icona e contenuto), altrimenti l'analyzer si ferma.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InboxDtos.cs` | modifica | voce `NewTitles`, film/serie/episodi, risposte admin |
| `…/Configuration/PluginConfiguration.cs` | crea | `NotifyNewTitles` |
| `…/Plugin.cs` | modifica | `BasePlugin<PluginConfiguration>`, `Instance` |
| `…/Hub/INewTitlesSettings.cs`, `…/Server/PluginNewTitlesSettings.cs` | crea | la casella, letta ogni volta |
| `…/Hub/InboxService.cs` | modifica | `AddNewTitlesAsync` |
| `…/Hub/ILibraryTitles.cs`, `NewTitlesWave.cs`, `NewTitlesCollector.cs` | crea | titoli riletti, ondata, raccoglitore |
| `…/Server/NewTitleRules.cs`, `JellyfinLibraryTitles.cs` | crea | filtro e id esterni, adattatore |
| `…/NewTitlesHostedService.cs`, `PluginServiceRegistrator.cs` | crea/modifica | eventi della libreria, servizi |
| `…/Api/InboxController.cs` | modifica | `GET Inbox/NewTitles`, `POST Inbox/NewTitles/Send` (admin) |
| `…/Configuration/configPage.html` | modifica | casella, titoli in attesa, "Send now" |
| `jellyfin-plugin-watch-party/README.md` | modifica | nuovi titoli |
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/*` | crea/modifica | test |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi delle novità |
| `lib/core/social/inbox_models.dart` | modifica | `NewTitles*`, `formatEpisodeRanges`, `NewTitlesEntry` |
| `lib/app/navigation.dart` | modifica | `openItemById` |
| `lib/features/inbox/inbox_panel.dart` | modifica | la voce Novità |
| `test/support/social_fakes.dart` | modifica | `testNewTitles` |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`, `docs/RELEASING.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–4):** plugin. **Poi ci si ferma** (Task 5: lo fa l'orchestratore, deploy sul server).
- **Gruppo B (Task 6–8):** app.
- **Gruppo C (Task 9):** allineamento dello spec e dei documenti, verifica finale, build.
- **Release** (dopo la prova manuale e il merge, con l'utente): fuori dai task.

---

## Gruppo A — plugin

### Task 1: voce Novità nel protocollo, casella `NotifyNewTitles`, `AddNewTitlesAsync`

**Files:**
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/InboxDtos.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/PluginConfiguration.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Plugin.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/INewTitlesSettings.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/PluginNewTitlesSettings.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/InboxService.cs`
- Test: `ProtocolJsonTests.cs`, `InboxBookTests.cs`, `InboxServiceTests.cs`, `PluginConfigurationTests.cs` (nuovo)

- [ ] **Step 1: test che falliscono**

In `ProtocolJsonTests.cs`, prima della chiusura della classe:

```csharp
    [Fact]
    public void NewTitlesEntriesUseProtocolNames()
    {
        var entry = new InboxEntry
        {
            Id = "e2",
            Seq = 4,
            Type = InboxEntryTypes.NewTitles,
            CreatedAt = new DateTimeOffset(2026, 10, 4, 9, 0, 0, TimeSpan.Zero),
            Movies =
            [
                new NewTitleMovie { ItemId = "m1", Name = "Dune", Year = 2024 },
                new NewTitleMovie { ItemId = "m2", Name = "Senza anno" },
            ],
            Series =
            [
                new NewTitleSeries
                {
                    SeriesId = "s1",
                    Name = "The Bear",
                    Episodes = [new NewTitleEpisode { Season = 3, Episode = 1 }, new NewTitleEpisode()],
                },
            ],
            More = 2,
        };

        var json = JsonDocument.Parse(JsonSerializer.Serialize(entry)).RootElement;

        Assert.Equal(
            new[] { "Id", "Seq", "Type", "CreatedAt", "Read", "Movies", "Series", "More" },
            json.EnumerateObject().Select(p => p.Name));
        Assert.Equal("{\"ItemId\":\"m1\",\"Name\":\"Dune\",\"Year\":2024}", json.GetProperty("Movies")[0].GetRawText());
        Assert.Equal("{\"ItemId\":\"m2\",\"Name\":\"Senza anno\"}", json.GetProperty("Movies")[1].GetRawText());
        var episodes = json.GetProperty("Series")[0].GetProperty("Episodes");
        Assert.Equal("{\"Season\":3,\"Episode\":1}", episodes[0].GetRawText());
        Assert.Equal("{}", episodes[1].GetRawText());
        Assert.Equal("{\"Enabled\":true,\"Pending\":3}", JsonSerializer.Serialize(new NewTitlesStatus(true, 3)));
        Assert.Equal("{\"Titles\":5,\"Recipients\":2}", JsonSerializer.Serialize(new NewTitlesSendResponse(5, 2)));
    }
```

In `InboxBookTests.cs` aggiungi `using System.Text.Json;` e:

```csharp
    [Fact]
    public void NewTitlesEntriesRoundTripThroughTheFile()
    {
        var book = new InboxBook();
        book.Add(_mario, new InboxEntry
        {
            Type = InboxEntryTypes.NewTitles,
            CreatedAt = Now,
            Movies = [new NewTitleMovie { ItemId = "m1", Name = "Dune", Year = 2024 }],
            Series = [new NewTitleSeries { SeriesId = "s1", Name = "The Bear", Episodes = [new NewTitleEpisode { Season = 3, Episode = 1 }] }],
            More = 3,
        });

        var copy = InboxBook.FromFile(JsonSerializer.Deserialize<InboxFile>(JsonSerializer.Serialize(book.ToFile()))!);

        var entry = Assert.Single(copy.List(_mario));
        Assert.Equal("Dune", Assert.Single(entry.Movies!).Name);
        Assert.Equal(1, Assert.Single(Assert.Single(entry.Series!).Episodes).Episode);
        Assert.Equal(3, entry.More);
    }
```

In `InboxServiceTests.cs`:

```csharp
    [Fact]
    public async Task NewTitlesEntriesGoToTheirUsersAndNotifyThem()
    {
        var entries = new Dictionary<Guid, InboxEntry>
        {
            [_mario.Id] = new InboxEntry
            {
                Type = InboxEntryTypes.NewTitles,
                CreatedAt = _time.GetUtcNow(),
                Movies = [new NewTitleMovie { ItemId = "m1", Name = "Dune" }],
                Series = [],
            },
        };

        await _inbox.AddNewTitlesAsync(entries);
        await _inbox.AddNewTitlesAsync(new Dictionary<Guid, InboxEntry>());

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.NewTitles, entry.Type);
        Assert.False(entry.Read);
        Assert.Empty(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(new[] { "InboxChanged" }, _server.SentTo("s-mario").Select(Type));
        Assert.Empty(_server.SentTo("s-luigi"));
    }
```

Crea `PluginConfigurationTests.cs`:

```csharp
using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PluginConfigurationTests
{
    [Fact]
    public void NewTitlesAreOnByDefaultAndTheSettingSurvivesTheXml()
    {
        Assert.True(new PluginConfiguration().NotifyNewTitles);

        // Jellyfin salva la configurazione con XmlSerializer.
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, new PluginConfiguration { NotifyNewTitles = false });
        using var reader = new StringReader(writer.ToString());

        Assert.False(((PluginConfiguration)serializer.Deserialize(reader)!).NotifyNewTitles);
    }

    [Fact]
    public void WithoutThePluginInstanceNewTitlesStayOn()
    {
        // Nei test Jellyfin non crea il plugin: vale il predefinito.
        Assert.True(new PluginNewTitlesSettings().NotifyNewTitles);
    }
}
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`NewTitleMovie`, `NewTitlesStatus`, `PluginConfiguration`, `AddNewTitlesAsync` non esistono).

- [ ] **Step 3: il protocollo**

In `Protocol/InboxDtos.cs`:

- in `InboxEntryTypes` aggiungi:

```csharp
    /// <summary>Riepilogo di un'ondata di nuovi titoli (spec G §6.6).</summary>
    public const string NewTitles = "NewTitles";
```

- in `InboxEntry`, dopo la proprietà `Text`:

```csharp
    /// <summary>NewTitles: i film, per nome.</summary>
    [JsonPropertyName("Movies")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<NewTitleMovie>? Movies { get; set; }

    /// <summary>NewTitles: le serie seguite con i loro episodi nuovi, per nome.</summary>
    [JsonPropertyName("Series")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<NewTitleSeries>? Series { get; set; }

    /// <summary>NewTitles: film e serie oltre il tetto delle righe; manca se 0.</summary>
    [JsonPropertyName("More")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? More { get; set; }
```

e il commento di `Copy()` (aggiungilo sopra il metodo):

```csharp
    /// <summary>Copia superficiale: le liste di NewTitles non si cambiano mai dopo la creazione.</summary>
```

- in fondo al file:

```csharp
/// <summary>Un film nuovo nella voce NewTitles.</summary>
public sealed class NewTitleMovie
{
    /// <summary>L'elemento, in formato "N".</summary>
    [JsonPropertyName("ItemId")]
    public string ItemId { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("Year")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Year { get; set; }
}

/// <summary>Una serie seguita con i suoi episodi nuovi, nella voce NewTitles.</summary>
public sealed class NewTitleSeries
{
    /// <summary>La serie, in formato "N": la riga apre la sua scheda.</summary>
    [JsonPropertyName("SeriesId")]
    public string SeriesId { get; set; } = string.Empty;

    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    /// <summary>Per stagione e numero.</summary>
    [JsonPropertyName("Episodes")]
    public List<NewTitleEpisode> Episodes { get; set; } = [];
}

/// <summary>Un episodio nuovo: stagione e numero, se Jellyfin li conosce.</summary>
public sealed class NewTitleEpisode
{
    [JsonPropertyName("Season")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Season { get; set; }

    [JsonPropertyName("Episode")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? Episode { get; set; }
}

/// <summary>Risposta di GET Inbox/NewTitles (admin): la casella e i titoli in attesa.</summary>
public sealed record NewTitlesStatus(
    [property: JsonPropertyName("Enabled")] bool Enabled,
    [property: JsonPropertyName("Pending")] int Pending);

/// <summary>Risposta di POST Inbox/NewTitles/Send (admin): titoli annunciati e utenti che li hanno ricevuti.</summary>
public sealed record NewTitlesSendResponse(
    [property: JsonPropertyName("Titles")] int Titles,
    [property: JsonPropertyName("Recipients")] int Recipients);
```

- [ ] **Step 4: la casella**

Crea `Configuration/PluginConfiguration.cs`:

```csharp
using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Configuration;

/// <summary>
/// Impostazioni del plugin (spec G §6.8), salvate da Jellyfin in
/// plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml e cambiate
/// dalla pagina nella Dashboard. Proprietà pubbliche con get e set: le scrive
/// XmlSerializer.
/// </summary>
public class PluginConfiguration : BasePluginConfiguration
{
    /// <summary>Raccogli i titoli nuovi della libreria e mandane il riepilogo (spec G §6.6).</summary>
    public bool NotifyNewTitles { get; set; } = true;
}
```

Crea `Hub/INewTitlesSettings.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>La casella "Notify new titles" della Dashboard (spec G §6.8).</summary>
public interface INewTitlesSettings
{
    /// <summary>Il valore di adesso: va letto ogni volta.</summary>
    bool NotifyNewTitles { get; }
}
```

Crea `Server/PluginNewTitlesSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La casella dalla configurazione del plugin.</summary>
public sealed class PluginNewTitlesSettings : INewTitlesSettings
{
    // Si legge ogni volta: salvando dalla Dashboard Jellyfin sostituisce
    // l'oggetto della configurazione. Senza plugin (nei test) vale il
    // predefinito.
    public bool NotifyNewTitles => Plugin.Instance?.Configuration.NotifyNewTitles ?? true;
}
```

In `Plugin.cs`:
- aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;`;
- il commento della classe: la frase "Non ha impostazioni; la sua pagina nella Dashboard serve per gli annunci (spec G §6.8)." diventa "Ha una sola impostazione, NotifyNewTitles; la sua pagina nella Dashboard serve per quella, per gli annunci e per mandare subito i nuovi titoli (spec G §6.8).";
- `public class Plugin : BasePlugin<BasePluginConfiguration>, IHasWebPages` → `public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages`;
- dopo `PluginId`:

```csharp
    /// <summary>
    /// L'istanza creata da Jellyfin, che non la mette nel DI: da qui si legge
    /// la configurazione di adesso (<see cref="Server.PluginNewTitlesSettings"/>).
    /// </summary>
    public static Plugin? Instance { get; private set; }
```

- nel costruttore, dentro le graffe: `Instance = this;`.

(`using MediaBrowser.Model.Plugins;` resta: serve per `IHasWebPages` e `PluginPageInfo`.)

- [ ] **Step 5: le voci nella cassetta**

In `Hub/InboxService.cs`, dopo `AddInvitesAsync`:

```csharp
    /// <summary>
    /// Le voci dei nuovi titoli (spec G §6.6), una per utente, e l'avviso alle
    /// sue sessioni. Non lancia: un errore finisce nel log.
    /// </summary>
    public async Task AddNewTitlesAsync(IReadOnlyDictionary<Guid, InboxEntry> entries)
    {
        if (entries.Count == 0)
        {
            return;
        }

        try
        {
            lock (_lock)
            {
                foreach (var (userId, entry) in entries)
                {
                    Book.Add(userId, entry);
                }

                Persist();
            }

            await NotifyAsync(entries.Keys.ToList()).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci dei nuovi titoli non create o non notificate");
        }
    }
```

e nel commento della classe aggiungi "voci dei nuovi titoli" all'elenco ("…annunci dell'admin, voci d'invito, voci dei nuovi titoli, pulizia…").

- [ ] **Step 6: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the new titles entry and the NotifyNewTitles setting"
```

### Task 2: ondata e raccoglitore dei nuovi titoli

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/ILibraryTitles.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/NewTitlesWave.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/NewTitlesCollector.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FakeServer.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/TestNewTitles.cs`
- Test: `NewTitlesWaveTests.cs` (nuovo), `NewTitlesCollectorTests.cs` (nuovo)

- [ ] **Step 1: server finto e raccoglitore di prova**

In `FakeServer.cs` la classe implementa anche `ILibraryTitles` e `INewTitlesSettings`:

```csharp
internal sealed class FakeServer : ISessionDirectory, IGroupDirectory, IEventSender, IUserDirectory, ILibraryAccess, ILibraryTitles, INewTitlesSettings
```

e, dopo `CanSee`, aggiungi:

```csharp
    /// <summary>Titoli della libreria per id, come li rilegge il raccoglitore dei nuovi titoli.</summary>
    public Dictionary<Guid, LibraryTitle> Titles { get; } = [];

    /// <summary>Coppie (utente, serie) seguite.</summary>
    public HashSet<(Guid UserId, Guid SeriesId)> Following { get; } = [];

    /// <summary>Jellyfin sta scansionando la libreria.</summary>
    public bool ScanRunning { get; set; }

    /// <summary>La casella "Notify new titles".</summary>
    public bool NotifyNewTitles { get; set; } = true;

    public bool IsScanRunning => ScanRunning;

    public LibraryTitle? Get(Guid itemId) =>
        LibraryFails ? throw new InvalidOperationException("libreria non disponibile") : Titles.GetValueOrDefault(itemId);

    public bool FollowsSeries(Guid userId, Guid seriesId, string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes) =>
        Following.Contains((userId, seriesId));
```

Crea `TestNewTitles.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il raccoglitore dei nuovi titoli dei test, sul server finto.</summary>
internal static class TestNewTitles
{
    public static NewTitlesCollector Create(FakeServer server, InboxService inbox, TimeProvider time) =>
        new(server, server, server, inbox, server, time, NullLogger<NewTitlesCollector>.Instance);
}
```

- [ ] **Step 2: test che falliscono**

Crea `NewTitlesWaveTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NewTitlesWaveTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 4, 20, 0, 0, TimeSpan.Zero);

    private static LibraryTitle Title(bool isMovie, params string[] keys) =>
        new(Guid.NewGuid(), isMovie, "x", null, Guid.Empty, string.Empty, string.Empty, null, null, keys, true);

    [Fact]
    public void QuietCountsFromTheLastChangeOverdueFromTheStart()
    {
        var wave = new NewTitlesWave(T0);
        wave.Add(Guid.NewGuid(), T0.AddMinutes(10));

        Assert.False(wave.IsQuiet(T0.AddMinutes(24), TimeSpan.FromMinutes(15)));
        Assert.True(wave.IsQuiet(T0.AddMinutes(25), TimeSpan.FromMinutes(15)));
        Assert.False(wave.IsOverdue(T0.AddMinutes(119), TimeSpan.FromHours(2)));
        Assert.True(wave.IsOverdue(T0.AddHours(2), TimeSpan.FromHours(2)));
    }

    [Fact]
    public void ARemovedTitleLeavesTheWaveAndMarksReplacementsOfTheSameKind()
    {
        var wave = new NewTitlesWave(T0);
        var id = Guid.NewGuid();
        wave.Add(id, T0);

        wave.Remove(id, isMovie: true, ["Tmdb:1"], T0.AddMinutes(1));

        Assert.Equal(0, wave.Count);
        Assert.Empty(wave.AddedIds);
        Assert.Equal(T0.AddMinutes(1), wave.LastChangeAt);
        Assert.True(wave.IsReplacement(Title(true, "tmdb:1")));
        Assert.False(wave.IsReplacement(Title(false, "Tmdb:1")));
        Assert.False(wave.IsReplacement(Title(true, "Tmdb:2")));
        Assert.False(wave.IsReplacement(Title(true)));
    }
}
```

Crea `NewTitlesCollectorTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class NewTitlesCollectorTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 4, 20, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly NewTitlesCollector _collector;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly Guid _bear = Guid.NewGuid();

    public NewTitlesCollectorTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _collector = TestNewTitles.Create(_server, _inbox, _time);
        _collector.Start();
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
    }

    public void Dispose()
    {
        _collector.Dispose();
        _folder.Dispose();
    }

    private Guid AddMovie(string name, int? year = 2024, string[]? keys = null, bool refreshed = true)
    {
        var id = Guid.NewGuid();
        _server.Titles[id] = new LibraryTitle(
            id, true, name, year, Guid.Empty, string.Empty, string.Empty, null, null, keys ?? [], refreshed);
        return id;
    }

    private Guid AddEpisode(Guid seriesId, int? season, int? episode, string seriesName = "The Bear")
    {
        var id = Guid.NewGuid();
        _server.Titles[id] = new LibraryTitle(
            id, false, $"Episodio {episode}", null, seriesId, seriesName, "chiave-" + seriesId.ToString("N"),
            season, episode, [], true);
        return id;
    }

    private InboxEntry? NewTitlesOf(UserRef user) =>
        _inbox.Get(user.Id).Entries.SingleOrDefault(e => e.Type == InboxEntryTypes.NewTitles);

    [Fact]
    public void AWaveClosesAfterFifteenQuietMinutes()
    {
        _collector.Added(AddMovie("Dune"));
        _time.Advance(TimeSpan.FromMinutes(14));
        var alien = AddMovie("Alien", 1979);
        _collector.Added(alien);
        _time.Advance(TimeSpan.FromMinutes(14));
        Assert.Null(NewTitlesOf(_mario));

        _time.Advance(TimeSpan.FromMinutes(1));

        var entry = NewTitlesOf(_mario);
        Assert.NotNull(entry);
        Assert.Equal(new[] { "Alien", "Dune" }, entry.Movies!.Select(m => m.Name));
        Assert.Equal(alien.ToString("N"), entry.Movies![0].ItemId);
        Assert.Equal(1979, entry.Movies[0].Year);
        Assert.Empty(entry.Series!);
        Assert.Null(entry.More);
        Assert.NotNull(NewTitlesOf(_luigi));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void ALongWaveClosesAfterTwoHours()
    {
        for (var i = 0; i < 13; i++)
        {
            _collector.Added(AddMovie($"Film {i:00}"));
            _time.Advance(TimeSpan.FromMinutes(10));
        }

        // Un titolo ogni 10 minuti: alla seconda ora l'ondata si chiude anche
        // senza quiete; l'ultimo apre l'ondata dopo.
        Assert.Equal(12, NewTitlesOf(_mario)!.Movies!.Count);
        Assert.Equal(1, _collector.Pending);
    }

    [Fact]
    public void AScanInProgressOrMissingMetadataPostponeTheClose()
    {
        _collector.Added(AddMovie("Dune"));
        _server.ScanRunning = true;
        _time.Advance(TimeSpan.FromMinutes(20));
        Assert.Null(NewTitlesOf(_mario));

        _server.ScanRunning = false;
        var raw = AddMovie("dune.part.two.2024.mkv", refreshed: false);
        _collector.Added(raw);
        _time.Advance(TimeSpan.FromMinutes(16));
        Assert.Null(NewTitlesOf(_mario));

        // Arrivano i metadati: nome vero.
        _server.Titles[raw] = _server.Titles[raw] with { Name = "Dune: Parte Due", Refreshed = true };
        _time.Advance(TimeSpan.FromMinutes(1));

        Assert.Equal(new[] { "Dune", "Dune: Parte Due" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
    }

    [Fact]
    public void TwoHoursCloseTheWaveEvenDuringAScan()
    {
        _server.ScanRunning = true;
        _collector.Added(AddMovie("Dune", refreshed: false));

        _time.Advance(NewTitlesCollector.MaxWait);

        Assert.NotNull(NewTitlesOf(_mario));
    }

    [Fact]
    public void ReplacementsAndShortLivedTitlesAreNotAnnounced()
    {
        // Radarr: il file vecchio tolto, quello nuovo aggiunto con lo stesso id TMDB.
        _collector.Removed(Guid.NewGuid(), isMovie: true, ["Tmdb:438631"]);
        _collector.Added(AddMovie("Dune", keys: ["Tmdb:438631", "Imdb:tt1160419"]));
        // Aggiunto e tolto nella stessa ondata.
        var gone = AddMovie("Temporaneo");
        _collector.Added(gone);
        _collector.Removed(gone, isMovie: true, []);
        // Cancellato prima della chiusura.
        var deleted = AddMovie("Cancellato");
        _collector.Added(deleted);
        _server.Titles.Remove(deleted);
        _collector.Added(AddMovie("Alien"));

        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Equal(new[] { "Alien" }, NewTitlesOf(_mario)!.Movies!.Select(m => m.Name));
    }

    [Fact]
    public void AReplacementNeedsTheSameKind()
    {
        _collector.Removed(Guid.NewGuid(), isMovie: false, ["Tvdb:42"]);
        _collector.Added(AddMovie("Film con lo stesso id", keys: ["Tvdb:42"]));

        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Single(NewTitlesOf(_mario)!.Movies!);
    }

    [Fact]
    public void EpisodesGoToFollowersMoviesToWhoCanSeeThem()
    {
        var second = AddEpisode(_bear, 3, 2);
        var first = AddEpisode(_bear, 3, 1);
        var film = AddMovie("Dune");
        _server.Following.Add((_mario.Id, _bear));
        _server.Unseen.Add((_luigi.Id, film));
        _collector.Added(second);
        _collector.Added(first);
        _collector.Added(film);

        _time.Advance(NewTitlesCollector.QuietTime);

        var mario = NewTitlesOf(_mario)!;
        var series = Assert.Single(mario.Series!);
        Assert.Equal(_bear.ToString("N"), series.SeriesId);
        Assert.Equal("The Bear", series.Name);
        Assert.Equal(new[] { (3, 1), (3, 2) }, series.Episodes.Select(e => (e.Season!.Value, e.Episode!.Value)));
        Assert.Single(mario.Movies!);
        // Luigi non segue la serie e non vede il film.
        Assert.Null(NewTitlesOf(_luigi));
    }

    [Fact]
    public void EpisodesTheUserCannotSeeAndEpisodesWithoutASeriesAreLeftOut()
    {
        var visible = AddEpisode(_bear, 1, 1);
        var hidden = AddEpisode(_bear, 1, 2);
        var orphan = AddEpisode(Guid.Empty, 1, 1, seriesName: "Senza serie");
        _server.Following.Add((_mario.Id, _bear));
        _server.Following.Add((_mario.Id, Guid.Empty));
        _server.Unseen.Add((_mario.Id, hidden));
        foreach (var id in new[] { visible, hidden, orphan })
        {
            _collector.Added(id);
        }

        _time.Advance(NewTitlesCollector.QuietTime);

        var series = Assert.Single(NewTitlesOf(_mario)!.Series!);
        Assert.Equal(new int?[] { 1 }, series.Episodes.Select(e => e.Episode));
    }

    [Fact]
    public void DisabledUsersGetNothing()
    {
        var bowser = _server.AddUser("Bowser", enabled: false);
        _collector.Added(AddMovie("Dune"));

        _time.Advance(NewTitlesCollector.QuietTime);

        Assert.Empty(_inbox.Get(bowser.Id).Entries);
        Assert.NotNull(NewTitlesOf(_mario));
    }

    [Fact]
    public void BeyondTheLimitTheRestIsCounted()
    {
        for (var i = 0; i < NewTitlesCollector.MaxLines + 3; i++)
        {
            _collector.Added(AddMovie($"Film {i:000}"));
        }

        _time.Advance(NewTitlesCollector.QuietTime);

        var entry = NewTitlesOf(_mario)!;
        Assert.Equal(NewTitlesCollector.MaxLines, entry.Movies!.Count);
        Assert.Equal("Film 000", entry.Movies[0].Name);
        Assert.Empty(entry.Series!);
        Assert.Equal(3, entry.More);
    }

    [Fact]
    public void TurningTheSettingOffDropsTheWave()
    {
        _collector.Added(AddMovie("Dune"));
        Assert.Equal(1, _collector.Pending);

        _server.NotifyNewTitles = false;
        Assert.Equal(0, _collector.Pending);
        _collector.Added(AddMovie("Alien"));
        _server.NotifyNewTitles = true;
        _time.Advance(TimeSpan.FromMinutes(30));

        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public void ASettingTurnedOffBeforeTheCloseDropsTheWaveToo()
    {
        _collector.Added(AddMovie("Dune"));
        _server.NotifyNewTitles = false;

        _time.Advance(NewTitlesCollector.QuietTime);
        _server.NotifyNewTitles = true;

        Assert.Null(NewTitlesOf(_mario));
        Assert.Equal(0, _collector.Pending);
    }

    [Fact]
    public async Task SendNowClosesAtOnceEvenDuringAScan()
    {
        _server.ScanRunning = true;
        _collector.Added(AddMovie("Dune"));
        _server.Following.Add((_mario.Id, _bear));
        _collector.Added(AddEpisode(_bear, 1, 1));

        var result = await _collector.SendNowAsync();

        Assert.Equal(new NewTitlesSendResponse(2, 2), result);
        Assert.Single(NewTitlesOf(_mario)!.Series!);
        Assert.Empty(NewTitlesOf(_luigi)!.Series!);
        Assert.Equal(new NewTitlesSendResponse(0, 0), await _collector.SendNowAsync());
    }

    [Fact]
    public void ALibraryErrorIsRetriedAtTheNextCheck()
    {
        _collector.Added(AddMovie("Dune"));
        _server.LibraryFails = true;
        _time.Advance(NewTitlesCollector.QuietTime);
        Assert.Null(NewTitlesOf(_mario));

        _server.LibraryFails = false;
        _time.Advance(NewTitlesCollector.CheckInterval);

        Assert.NotNull(NewTitlesOf(_mario));
    }
}
```

- [ ] **Step 3: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`LibraryTitle`, `ILibraryTitles`, `NewTitlesWave`, `NewTitlesCollector` non esistono).

- [ ] **Step 4: titoli e ondata**

Crea `Hub/ILibraryTitles.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un film o un episodio della libreria, riletto alla chiusura dell'ondata
/// (spec G §6.6). SeriesKey è la chiave con cui Jellyfin raggruppa gli
/// episodi della serie; Refreshed dice se i metadati sono arrivati (prima il
/// nome viene dal file e i numeri mancano).
/// </summary>
public sealed record LibraryTitle(
    Guid ItemId,
    bool IsMovie,
    string Name,
    int? Year,
    Guid SeriesId,
    string SeriesName,
    string SeriesKey,
    int? Season,
    int? Episode,
    IReadOnlyCollection<string> ExternalKeys,
    bool Refreshed);

/// <summary>La libreria come serve al riepilogo dei nuovi titoli (adattatore di ILibraryManager e IUserManager).</summary>
public interface ILibraryTitles
{
    /// <summary>Jellyfin sta scansionando la libreria.</summary>
    bool IsScanRunning { get; }

    /// <summary>Il titolo (film o episodio vero), riletto adesso; null se non c'è più o non è un titolo.</summary>
    LibraryTitle? Get(Guid itemId);

    /// <summary>
    /// L'utente segue la serie: è tra i suoi preferiti (La mia lista), oppure
    /// ha visto o iniziato un episodio che non è tra excludeEpisodes (quelli
    /// appena arrivati).
    /// </summary>
    bool FollowsSeries(Guid userId, Guid seriesId, string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes);
}
```

Crea `Hub/NewTitlesWave.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un'ondata di nuovi titoli (spec G §6.6): gli id aggiunti, gli id esterni
/// di quelli tolti e i tempi. Solo id, mai elementi di Jellyfin. Non è sicura
/// tra thread: la usa solo NewTitlesCollector, sotto lock.
/// </summary>
public sealed class NewTitlesWave(DateTimeOffset startedAt)
{
    private readonly HashSet<Guid> _added = [];
    private readonly List<(bool IsMovie, HashSet<string> Keys)> _removed = [];

    public DateTimeOffset StartedAt { get; } = startedAt;

    /// <summary>L'ultima aggiunta o rimozione.</summary>
    public DateTimeOffset LastChangeAt { get; private set; } = startedAt;

    /// <summary>Titoli aggiunti (e non tolti) finora.</summary>
    public int Count => _added.Count;

    public IEnumerable<Guid> AddedIds => _added;

    public void Add(Guid itemId, DateTimeOffset now)
    {
        _added.Add(itemId);
        LastChangeAt = now;
    }

    /// <summary>
    /// Un titolo tolto: se era arrivato in questa ondata sparisce; i suoi id
    /// esterni fanno riconoscere chi lo sostituisce.
    /// </summary>
    public void Remove(Guid itemId, bool isMovie, IReadOnlyCollection<string> externalKeys, DateTimeOffset now)
    {
        _added.Remove(itemId);
        if (externalKeys.Count > 0)
        {
            _removed.Add((isMovie, new HashSet<string>(externalKeys, StringComparer.OrdinalIgnoreCase)));
        }

        LastChangeAt = now;
    }

    /// <summary>
    /// Il titolo sostituisce uno tolto in questa ondata: stesso tipo e almeno
    /// un id esterno in comune (es. un file migliore da Radarr o Sonarr).
    /// </summary>
    public bool IsReplacement(LibraryTitle title) =>
        _removed.Any(r => r.IsMovie == title.IsMovie && title.ExternalKeys.Any(r.Keys.Contains));

    public bool IsQuiet(DateTimeOffset now, TimeSpan quiet) => now - LastChangeAt >= quiet;

    public bool IsOverdue(DateTimeOffset now, TimeSpan maxWait) => now - StartedAt >= maxWait;
}
```

- [ ] **Step 5: il raccoglitore**

Crea `Hub/NewTitlesCollector.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Il riepilogo dei nuovi titoli (spec G §6.6). Raccoglie in un'ondata i
/// film e gli episodi aggiunti alla libreria; ogni <see cref="CheckInterval"/>
/// guarda se chiuderla: dopo <see cref="QuietTime"/> senza novità, se la
/// scansione è finita e i metadati ci sono, e comunque dopo
/// <see cref="MaxWait"/>. Alla chiusura ogni utente attivo riceve una voce
/// con i film che può vedere e gli episodi (che può vedere) delle serie che
/// segue. Added e Removed arrivano dai thread della scansione: sono O(1)
/// sotto lock; il lavoro sul database si fa alla chiusura. Con la casella
/// spenta non si raccoglie e l'ondata in corso si butta.
/// </summary>
public sealed class NewTitlesCollector(
    ILibraryTitles library,
    ILibraryAccess access,
    IUserDirectory users,
    InboxService inbox,
    INewTitlesSettings settings,
    TimeProvider time,
    ILogger<NewTitlesCollector> logger) : IDisposable
{
    /// <summary>Senza novità per questo tempo l'ondata si chiude (spec G §6.6).</summary>
    public static readonly TimeSpan QuietTime = TimeSpan.FromMinutes(15);

    /// <summary>Dopo questo tempo dal primo titolo l'ondata si chiude comunque.</summary>
    public static readonly TimeSpan MaxWait = TimeSpan.FromHours(2);

    /// <summary>Ogni quanto si guarda se l'ondata si può chiudere.</summary>
    public static readonly TimeSpan CheckInterval = TimeSpan.FromMinutes(1);

    /// <summary>Righe al massimo per voce (un film o una serie = una riga); le altre si contano in More.</summary>
    public const int MaxLines = 500;

    private static readonly NewTitlesSendResponse Nothing = new(0, 0);

    private readonly Lock _lock = new();
    private NewTitlesWave? _wave;
    private ITimer? _timer;

    // 1 mentre una chiusura è in corso: il timer e "Send now" possono arrivare insieme.
    private int _closing;

    /// <summary>Titoli in attesa nell'ondata in corso; 0 con la casella spenta (e l'ondata si butta).</summary>
    public int Pending
    {
        get
        {
            if (!settings.NotifyNewTitles)
            {
                Discard();
                return 0;
            }

            lock (_lock)
            {
                return _wave?.Count ?? 0;
            }
        }
    }

    /// <summary>Fa partire il controllo periodico (all'avvio del plugin).</summary>
    public void Start()
    {
        lock (_lock)
        {
            _timer ??= time.CreateTimer(_ => _ = CheckSafelyAsync(), null, CheckInterval, CheckInterval);
        }
    }

    /// <summary>Un film o un episodio vero aggiunto alla libreria.</summary>
    public void Added(Guid itemId)
    {
        if (!settings.NotifyNewTitles)
        {
            Discard();
            return;
        }

        lock (_lock)
        {
            Current().Add(itemId, time.GetUtcNow());
        }
    }

    /// <summary>Un film o un episodio vero tolto dalla libreria, con i suoi id esterni.</summary>
    public void Removed(Guid itemId, bool isMovie, IReadOnlyCollection<string> externalKeys)
    {
        if (!settings.NotifyNewTitles)
        {
            Discard();
            return;
        }

        lock (_lock)
        {
            Current().Remove(itemId, isMovie, externalKeys, time.GetUtcNow());
        }
    }

    /// <summary>Chiude subito l'ondata ("Send now" nella Dashboard), anche durante una scansione.</summary>
    public Task<NewTitlesSendResponse> SendNowAsync() => CloseAsync(force: true);

    public void Dispose()
    {
        lock (_lock)
        {
            _timer?.Dispose();
            _timer = null;
        }
    }

    private async Task CheckSafelyAsync()
    {
        try
        {
            await CloseAsync(force: false).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Riepilogo dei nuovi titoli non riuscito: si riprova al prossimo controllo");
        }
    }

    private async Task<NewTitlesSendResponse> CloseAsync(bool force)
    {
        if (Interlocked.Exchange(ref _closing, 1) == 1)
        {
            return Nothing;
        }

        try
        {
            if (!settings.NotifyNewTitles)
            {
                Discard();
                return Nothing;
            }

            NewTitlesWave? wave;
            List<Guid> ids;
            lock (_lock)
            {
                wave = _wave;
                ids = wave?.AddedIds.ToList() ?? [];
            }

            if (wave is null)
            {
                return Nothing;
            }

            var now = time.GetUtcNow();
            var due = force || wave.IsOverdue(now, MaxWait);
            if (!due && (!wave.IsQuiet(now, QuietTime) || library.IsScanRunning))
            {
                return Nothing;
            }

            // Fuori dal lock: si legge dal database.
            var titles = new Dictionary<Guid, LibraryTitle>();
            Resolve(ids, titles);

            // Metadati non ancora arrivati (nome dal file, niente numeri): si
            // aspetta, entro MaxWait.
            if (!due && titles.Values.Any(t => !t.Refreshed))
            {
                return Nothing;
            }

            lock (_lock)
            {
                // L'ondata si stacca: quello che arriva da adesso apre la prossima.
                _wave = null;
                ids = wave.AddedIds.ToList();
            }

            Resolve(ids.Where(id => !titles.ContainsKey(id)), titles);
            var kept = ids
                .Where(titles.ContainsKey)
                .Select(id => titles[id])
                .Where(title => !wave.IsReplacement(title))
                .ToList();
            var entries = BuildEntries(kept, now);
            await inbox.AddNewTitlesAsync(entries).ConfigureAwait(false);
            logger.LogDebug("Nuovi titoli: ondata chiusa con {Titles} titoli per {Recipients} utenti", kept.Count, entries.Count);
            return new NewTitlesSendResponse(kept.Count, entries.Count);
        }
        finally
        {
            Volatile.Write(ref _closing, 0);
        }
    }

    private void Resolve(IEnumerable<Guid> ids, Dictionary<Guid, LibraryTitle> titles)
    {
        foreach (var id in ids)
        {
            if (library.Get(id) is { } title)
            {
                titles[id] = title;
            }
        }
    }

    private Dictionary<Guid, InboxEntry> BuildEntries(List<LibraryTitle> titles, DateTimeOffset now)
    {
        var entries = new Dictionary<Guid, InboxEntry>();
        if (titles.Count == 0)
        {
            return entries;
        }

        var movies = titles.Where(t => t.IsMovie).OrderBy(t => t.Name, StringComparer.OrdinalIgnoreCase).ToList();
        var episodesBySeries = titles.Where(t => !t.IsMovie && t.SeriesId != Guid.Empty).GroupBy(t => t.SeriesId).ToList();
        foreach (var user in users.GetUsers().Where(u => u.Enabled))
        {
            var userMovies = movies.Where(m => access.CanSee(user.Id, m.ItemId)).ToList();
            var userSeries = new List<NewTitleSeries>();
            foreach (var episodes in episodesBySeries)
            {
                var visible = episodes.Where(e => access.CanSee(user.Id, e.ItemId)).ToList();
                if (visible.Count == 0)
                {
                    continue;
                }

                var first = visible[0];
                var newEpisodes = episodes.Select(e => e.ItemId).ToList();
                if (!library.FollowsSeries(user.Id, episodes.Key, first.SeriesKey, newEpisodes))
                {
                    continue;
                }

                userSeries.Add(new NewTitleSeries
                {
                    SeriesId = episodes.Key.ToString("N"),
                    Name = first.SeriesName,
                    Episodes = visible
                        .OrderBy(e => e.Season ?? int.MaxValue)
                        .ThenBy(e => e.Episode ?? int.MaxValue)
                        .Select(e => new NewTitleEpisode { Season = e.Season, Episode = e.Episode })
                        .ToList(),
                });
            }

            if (userMovies.Count + userSeries.Count == 0)
            {
                continue;
            }

            entries[user.Id] = Entry(
                userMovies, userSeries.OrderBy(s => s.Name, StringComparer.OrdinalIgnoreCase).ToList(), now);
        }

        return entries;
    }

    private static InboxEntry Entry(List<LibraryTitle> movies, List<NewTitleSeries> series, DateTimeOffset now)
    {
        var lines = movies.Count + series.Count;
        var movieLines = movies
            .Take(MaxLines)
            .Select(m => new NewTitleMovie { ItemId = m.ItemId.ToString("N"), Name = m.Name, Year = m.Year })
            .ToList();
        return new InboxEntry
        {
            Type = InboxEntryTypes.NewTitles,
            CreatedAt = now,
            Movies = movieLines,
            Series = series.Take(MaxLines - movieLines.Count).ToList(),
            More = lines > MaxLines ? lines - MaxLines : null,
        };
    }

    private void Discard()
    {
        lock (_lock)
        {
            if (_wave is { Count: > 0 })
            {
                logger.LogDebug("Nuovi titoli: ondata scartata con {Count} titoli, casella spenta", _wave.Count);
            }

            _wave = null;
        }
    }

    // Solo sotto _lock.
    private NewTitlesWave Current() => _wave ??= new NewTitlesWave(time.GetUtcNow());
}
```

- [ ] **Step 6: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): collect new titles in waves and build one entry per user"
```

### Task 3: regole di Jellyfin, adattatore, eventi della libreria, servizi

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/NewTitleRules.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinLibraryTitles.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/NewTitlesHostedService.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Test: `NewTitlesAdapterTests.cs` (nuovo), `NewTitlesHostedServiceTests.cs` (nuovo), `ServiceRegistrationTests.cs`

- [ ] **Step 1: test che falliscono**

Crea `NewTitlesAdapterTests.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NewTitlesAdapterTests
{
    private static Movie Movie(string path = "/media/film/dune.mkv") =>
        new() { Id = Guid.NewGuid(), Name = "Dune", Path = path, ProductionYear = 2024 };

    [Fact]
    public void OnlyRealMoviesAndEpisodesAreTitles()
    {
        Assert.True(NewTitleRules.IsRealTitle(Movie()));
        Assert.True(NewTitleRules.IsRealTitle(new Episode { Id = Guid.NewGuid(), Path = "/media/tv/e1.mkv" }));
        Assert.False(NewTitleRules.IsRealTitle(null));
        // Il segnaposto "mancante" del plugin TVDB.
        Assert.False(NewTitleRules.IsRealTitle(new Episode { Id = Guid.NewGuid(), IsVirtualItem = true }));
        Assert.False(NewTitleRules.IsRealTitle(Movie(path: string.Empty)));
        Assert.False(NewTitleRules.IsRealTitle(
            new Movie { Id = Guid.NewGuid(), Path = "/x.mkv", ExtraType = ExtraType.BehindTheScenes }));
        Assert.False(NewTitleRules.IsRealTitle(new Movie { Id = Guid.NewGuid(), Path = "/x.mkv", OwnerId = Guid.NewGuid() }));
        Assert.False(NewTitleRules.IsRealTitle(new Series { Id = Guid.NewGuid(), Path = "/media/tv/The Bear" }));
        Assert.False(NewTitleRules.IsRealTitle(new Trailer { Id = Guid.NewGuid(), Path = "/media/film/trailer.mkv" }));
    }

    [Fact]
    public void ExternalKeysAreTmdbImdbAndTvdb()
    {
        var movie = Movie();
        movie.ProviderIds["Tmdb"] = "438631";
        movie.ProviderIds["Imdb"] = " tt1160419 ";
        movie.ProviderIds["Tvdb"] = string.Empty;
        movie.ProviderIds["MusicBrainzAlbum"] = "x";

        Assert.Equal(new[] { "Tmdb:438631", "Imdb:tt1160419" }, NewTitleRules.ExternalKeys(movie));
    }

    [Fact]
    public void TitlesAreReReadFromTheLibrary()
    {
        var movie = Movie();
        movie.ProviderIds["Tmdb"] = "438631";
        var seriesId = Guid.NewGuid();
        var episode = new Episode
        {
            Id = Guid.NewGuid(),
            Name = "Pilot",
            Path = "/media/tv/e1.mkv",
            SeriesId = seriesId,
            SeriesName = "The Bear",
            SeriesPresentationUniqueKey = "bear-key",
            ParentIndexNumber = 3,
            IndexNumber = 1,
            DateLastRefreshed = new DateTime(2026, 10, 4, 0, 0, 0, DateTimeKind.Utc),
        };
        var (library, stub) = InterfaceStub<ILibraryManager>.Create();
        stub.Handlers["GetItemById"] = args =>
            (Guid)args[0]! == movie.Id ? movie : (Guid)args[0]! == episode.Id ? episode : null;
        var titles = new JellyfinLibraryTitles(library, InterfaceStub<IUserManager>.Create().Proxy);

        var film = titles.Get(movie.Id)!;
        Assert.True(film.IsMovie);
        Assert.Equal("Dune", film.Name);
        Assert.Equal(2024, film.Year);
        Assert.Equal(new[] { "Tmdb:438631" }, film.ExternalKeys);
        Assert.False(film.Refreshed, "metadati mai aggiornati: DateLastRefreshed vuota");
        var ep = titles.Get(episode.Id)!;
        Assert.False(ep.IsMovie);
        Assert.Equal(seriesId, ep.SeriesId);
        Assert.Equal("The Bear", ep.SeriesName);
        Assert.Equal("bear-key", ep.SeriesKey);
        Assert.Equal(3, ep.Season);
        Assert.Equal(1, ep.Episode);
        Assert.True(ep.Refreshed);
        Assert.Null(titles.Get(Guid.NewGuid()));
        Assert.Null(titles.Get(Guid.Empty));
    }

    [Fact]
    public void FollowingIsAFavouriteOrAnotherEpisodePlayedOrStarted()
    {
        var user = new User("mario", "provider", "reset");
        var seriesId = Guid.NewGuid();
        var newEpisode = Guid.NewGuid();
        var (users, usersStub) = InterfaceStub<IUserManager>.Create();
        usersStub.Handlers["GetUserById"] = args => (Guid)args[0]! == user.Id ? user : null;
        var queries = new List<InternalItemsQuery>();
        var answers = new Queue<int>();
        var (library, stub) = InterfaceStub<ILibraryManager>.Create();
        stub.Handlers["GetCount"] = args =>
        {
            queries.Add((InternalItemsQuery)args[0]!);
            return answers.Dequeue();
        };
        var titles = new JellyfinLibraryTitles(library, users);

        // Preferita: basta la prima domanda.
        answers.Enqueue(1);
        Assert.True(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));
        var favourite = Assert.Single(queries);
        Assert.Equal(new[] { seriesId }, favourite.ItemIds);
        Assert.True(favourite.IsFavorite);

        // Un altro episodio visto.
        queries.Clear();
        answers.Enqueue(0);
        answers.Enqueue(1);
        Assert.True(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));
        var played = queries[1];
        Assert.Equal("bear-key", played.SeriesPresentationUniqueKey);
        Assert.Equal(new[] { BaseItemKind.Episode }, played.IncludeItemTypes);
        Assert.Equal(new[] { newEpisode }, played.ExcludeItemIds);
        Assert.True(played.IsPlayed);
        Assert.False(played.IsVirtualItem);

        // Un altro episodio iniziato.
        queries.Clear();
        answers.Enqueue(0);
        answers.Enqueue(0);
        answers.Enqueue(1);
        Assert.True(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));
        Assert.True(queries[2].IsResumable);

        // Niente.
        answers.Enqueue(0);
        answers.Enqueue(0);
        answers.Enqueue(0);
        Assert.False(titles.FollowsSeries(user.Id, seriesId, "bear-key", [newEpisode]));

        // Senza la chiave della serie solo la preferita; utente sconosciuto: no.
        queries.Clear();
        answers.Enqueue(0);
        Assert.False(titles.FollowsSeries(user.Id, seriesId, string.Empty, [newEpisode]));
        Assert.Single(queries);
        Assert.False(titles.FollowsSeries(Guid.NewGuid(), seriesId, "bear-key", [newEpisode]));
    }
}
```

(Se un setter di Jellyfin usato nei test non è pubblico, per esempio `IsVirtualItem`, `ExtraType`, `OwnerId` o `SeriesPresentationUniqueKey`, o se il costruttore `InternalItemsQuery(User)` lancia con un `User` nuovo, adatta il test in modo minimo e segnalalo.)

Crea `NewTitlesHostedServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class NewTitlesHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly NewTitlesCollector _collector;
    private readonly UserRef _mario;
    private readonly ILibraryManager _library;
    private readonly InterfaceStub<ILibraryManager> _stub;
    private EventHandler<ItemChangeEventArgs>? _added;
    private EventHandler<ItemChangeEventArgs>? _removed;

    public NewTitlesHostedServiceTests()
    {
        _collector = TestNewTitles.Create(_server, TestInbox.Create(_server, _folder, _time), _time);
        _mario = _server.AddUser("Mario");
        (_library, _stub) = InterfaceStub<ILibraryManager>.Create();
        _stub.Handlers["add_ItemAdded"] = args =>
        {
            _added = (EventHandler<ItemChangeEventArgs>?)args[0];
            return null;
        };
        _stub.Handlers["add_ItemRemoved"] = args =>
        {
            _removed = (EventHandler<ItemChangeEventArgs>?)args[0];
            return null;
        };
    }

    public void Dispose()
    {
        _collector.Dispose();
        _folder.Dispose();
    }

    private async Task<NewTitlesHostedService> StartAsync()
    {
        var service = new NewTitlesHostedService(_library, _collector, NullLogger<NewTitlesHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);
        Assert.NotNull(_added);
        Assert.NotNull(_removed);
        return service;
    }

    [Fact]
    public async Task OnlyRealTitlesReachTheCollectorAndPlaceholdersDoNotHideEpisodes()
    {
        var service = await StartAsync();
        var seriesId = Guid.NewGuid();
        // TVDB toglie il segnaposto dell'episodio mancante quando arriva quello
        // vero, con lo stesso id TVDB: non è una sostituzione.
        var placeholder = new Episode { Id = Guid.NewGuid(), IsVirtualItem = true, SeriesId = seriesId };
        placeholder.ProviderIds["Tvdb"] = "42";
        var real = new Episode { Id = Guid.NewGuid(), Path = "/media/tv/e1.mkv", SeriesId = seriesId };

        _removed!(_library, new ItemChangeEventArgs { Item = placeholder });
        _added!(_library, new ItemChangeEventArgs { Item = real });
        _added(_library, new ItemChangeEventArgs { Item = placeholder });
        _added(_library, new ItemChangeEventArgs { Item = new Series { Id = Guid.NewGuid(), Path = "/media/tv/The Bear" } });
        Assert.Equal(1, _collector.Pending);

        _server.Titles[real.Id] = new LibraryTitle(
            real.Id, false, "Pilot", null, seriesId, "The Bear", "bear-key", 1, 1, ["Tvdb:42"], true);
        _server.Following.Add((_mario.Id, seriesId));
        Assert.Equal(new Protocol.NewTitlesSendResponse(1, 1), await _collector.SendNowAsync());

        await service.StopAsync(CancellationToken.None);
        Assert.Contains(_stub.Calls, c => c.Name == "remove_ItemAdded");
        Assert.Contains(_stub.Calls, c => c.Name == "remove_ItemRemoved");
    }

    [Fact]
    public async Task ARealTitleRemovedAndAddedAgainIsAReplacement()
    {
        await StartAsync();
        var old = new Movie { Id = Guid.NewGuid(), Path = "/media/film/dune.720p.mkv" };
        old.ProviderIds["Tmdb"] = "438631";
        var better = new Movie { Id = Guid.NewGuid(), Path = "/media/film/dune.2160p.mkv" };

        _removed!(_library, new ItemChangeEventArgs { Item = old });
        _added!(_library, new ItemChangeEventArgs { Item = better });
        _server.Titles[better.Id] = new LibraryTitle(
            better.Id, true, "Dune", 2021, Guid.Empty, string.Empty, string.Empty, null, null, ["Tmdb:438631"], true);

        Assert.Equal(new Protocol.NewTitlesSendResponse(0, 0), await _collector.SendNowAsync());
    }
}
```

In `ServiceRegistrationTests.cs`, dopo gli `Assert` di `InboxStore`:

```csharp
        Assert.NotNull(provider.GetRequiredService<NewTitlesCollector>());
        Assert.IsType<Server.PluginNewTitlesSettings>(provider.GetRequiredService<INewTitlesSettings>());
```

e `Assert.Single(provider.GetServices<IHostedService>());` diventa `Assert.Equal(2, provider.GetServices<IHostedService>().Count());`.

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`NewTitleRules`, `JellyfinLibraryTitles`, `NewTitlesHostedService` non esistono).

- [ ] **Step 3: le regole**

Crea `Server/NewTitleRules.cs`:

```csharp
using System.Diagnostics.CodeAnalysis;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Quali elementi di Jellyfin sono "titoli" per il riepilogo dei nuovi titoli (spec G §6.6).</summary>
public static class NewTitleRules
{
    private static readonly MetadataProvider[] Providers =
        [MetadataProvider.Tmdb, MetadataProvider.Imdb, MetadataProvider.Tvdb];

    /// <summary>
    /// Un film o un episodio vero: non un segnaposto "mancante"
    /// (IsVirtualItem, li crea il plugin TVDB), con un file, non un extra né
    /// un trailer. Vale anche per i tolti: TVDB toglie il segnaposto quando
    /// arriva l'episodio vero, con lo stesso id TVDB, e non deve sembrare una
    /// sostituzione.
    /// </summary>
    public static bool IsRealTitle([NotNullWhen(true)] BaseItem? item) =>
        item is Movie or Episode
        && !item.IsVirtualItem
        && !string.IsNullOrEmpty(item.Path)
        && item.ExtraType is null
        && item.OwnerId == Guid.Empty;

    /// <summary>Gli id esterni TMDB, IMDb e TVDB, come "Tmdb:438631".</summary>
    public static IReadOnlyCollection<string> ExternalKeys(BaseItem item)
    {
        var keys = new List<string>();
        foreach (var provider in Providers)
        {
            if (item.TryGetProviderId(provider, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                keys.Add($"{provider}:{value.Trim()}");
            }
        }

        return keys;
    }
}
```

- [ ] **Step 4: l'adattatore**

Crea `Server/JellyfinLibraryTitles.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La libreria di Jellyfin per il riepilogo dei nuovi titoli.</summary>
public sealed class JellyfinLibraryTitles(ILibraryManager libraryManager, IUserManager userManager) : ILibraryTitles
{
    public bool IsScanRunning => libraryManager.IsScanRunning;

    // Con un id vuoto GetItemById lancia: il titolo non c'è e basta.
    public LibraryTitle? Get(Guid itemId)
    {
        if (itemId == Guid.Empty)
        {
            return null;
        }

        var item = libraryManager.GetItemById(itemId);
        if (!NewTitleRules.IsRealTitle(item))
        {
            return null;
        }

        var episode = item as Episode;
        var seriesKey = episode is null
            ? string.Empty
            : episode.SeriesPresentationUniqueKey ?? episode.FindSeriesPresentationUniqueKey() ?? string.Empty;
        return new LibraryTitle(
            item.Id,
            item is Movie,
            item.Name ?? string.Empty,
            item.ProductionYear,
            episode?.SeriesId ?? Guid.Empty,
            episode?.SeriesName ?? string.Empty,
            seriesKey,
            episode?.ParentIndexNumber,
            episode?.IndexNumber,
            NewTitleRules.ExternalKeys(item),
            item.DateLastRefreshed != DateTime.MinValue);
    }

    // Conteggi sul database: i dati utente in memoria della serie possono
    // essere vecchi (Jellyfin li azzera sul genitore a ogni aggiunta). I
    // filtri per utente vogliono il costruttore con l'utente.
    public bool FollowsSeries(Guid userId, Guid seriesId, string seriesKey, IReadOnlyCollection<Guid> excludeEpisodes)
    {
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return false;
        }

        if (seriesId != Guid.Empty
            && libraryManager.GetCount(new InternalItemsQuery(user) { ItemIds = [seriesId], IsFavorite = true }) > 0)
        {
            return true;
        }

        if (string.IsNullOrEmpty(seriesKey))
        {
            return false;
        }

        return libraryManager.GetCount(OtherEpisodes(user, seriesKey, excludeEpisodes, played: true)) > 0
            || libraryManager.GetCount(OtherEpisodes(user, seriesKey, excludeEpisodes, played: false)) > 0;
    }

    /// <summary>Gli altri episodi veri della serie, visti (played) o iniziati.</summary>
    private static InternalItemsQuery OtherEpisodes(User user, string seriesKey, IReadOnlyCollection<Guid> exclude, bool played)
    {
        var query = new InternalItemsQuery(user)
        {
            SeriesPresentationUniqueKey = seriesKey,
            IncludeItemTypes = [BaseItemKind.Episode],
            IsVirtualItem = false,
            ExcludeItemIds = exclude.ToArray(),
        };
        if (played)
        {
            query.IsPlayed = true;
        }
        else
        {
            query.IsResumable = true;
        }

        return query;
    }
}
```

- [ ] **Step 5: gli eventi della libreria e i servizi**

Crea `NewTitlesHostedService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Collega il raccoglitore dei nuovi titoli agli eventi della libreria di
/// Jellyfin (spec G §6.6). Gli eventi arrivano dai thread della scansione: i
/// gestori fanno solo il filtro e una chiamata O(1), e non lanciano mai (un
/// errore fermerebbe gli altri ascoltatori dello stesso evento).
/// </summary>
public sealed class NewTitlesHostedService(
    ILibraryManager libraryManager,
    NewTitlesCollector collector,
    ILogger<NewTitlesHostedService> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        libraryManager.ItemAdded += OnItemAdded;
        libraryManager.ItemRemoved += OnItemRemoved;
        collector.Start();
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        libraryManager.ItemAdded -= OnItemAdded;
        libraryManager.ItemRemoved -= OnItemRemoved;
        collector.Dispose();
        return Task.CompletedTask;
    }

    private void OnItemAdded(object? sender, ItemChangeEventArgs e)
    {
        try
        {
            var item = e.Item;
            if (NewTitleRules.IsRealTitle(item))
            {
                collector.Added(item.Id);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Nuovo titolo non raccolto");
        }
    }

    // Gli id esterni si leggono adesso: dopo la rimozione l'elemento non si rilegge più.
    private void OnItemRemoved(object? sender, ItemChangeEventArgs e)
    {
        try
        {
            var item = e.Item;
            if (NewTitleRules.IsRealTitle(item))
            {
                collector.Removed(item.Id, item is Movie, NewTitleRules.ExternalKeys(item));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Titolo tolto non registrato");
        }
    }
}
```

In `PluginServiceRegistrator.cs`, dopo `serviceCollection.AddSingleton<InboxService>();`:

```csharp
        serviceCollection.AddSingleton<INewTitlesSettings, PluginNewTitlesSettings>();
        serviceCollection.AddSingleton<ILibraryTitles, JellyfinLibraryTitles>();
        serviceCollection.AddSingleton<NewTitlesCollector>();
```

e dopo `serviceCollection.AddHostedService<WatchPartyHostedService>();`:

```csharp
        serviceCollection.AddHostedService<NewTitlesHostedService>();
```

- [ ] **Step 6: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): feed the new titles collector from the library events"
```

### Task 4: endpoint admin, pagina della Dashboard, README

**Files:**
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/InboxController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/configPage.html`
- Modify: `jellyfin-plugin-watch-party/README.md`
- Test: `InboxControllerTests.cs`, `PluginPagesTests.cs`

- [ ] **Step 1: test che falliscono**

In `InboxControllerTests.cs`:
- aggiungi il campo `private readonly NewTitlesCollector _newTitles;` e nel costruttore, dopo `_inbox = …`: `_newTitles = TestNewTitles.Create(_server, _inbox, _time);`;
- `Dispose` diventa:

```csharp
    public void Dispose()
    {
        _newTitles.Dispose();
        _folder.Dispose();
    }
```

- in `Controller(...)`: `new InboxController(new FakeAuthorizationContext(auth), _inbox)` → `new InboxController(new FakeAuthorizationContext(auth), _inbox, _newTitles, _server)`;
- aggiungi:

```csharp
    [Fact]
    public async Task NewTitlesStatusAndSendNow()
    {
        var controller = Controller(_mario);
        Assert.Equal(new NewTitlesStatus(true, 0), controller.GetNewTitles().Value);

        var dune = Guid.NewGuid();
        _server.Titles[dune] = new LibraryTitle(
            dune, true, "Dune", 2024, Guid.Empty, string.Empty, string.Empty, null, null, [], true);
        _newTitles.Added(dune);
        Assert.Equal(new NewTitlesStatus(true, 1), controller.GetNewTitles().Value);
        Assert.Equal(new NewTitlesSendResponse(1, 1), (await controller.SendNewTitles()).Value);
        Assert.Equal(new NewTitlesStatus(true, 0), controller.GetNewTitles().Value);

        _server.NotifyNewTitles = false;
        Assert.Equal(new NewTitlesStatus(false, 0), controller.GetNewTitles().Value);
    }

    [Fact]
    public void OnlyAdminsSeeAndSendNewTitles()
    {
        foreach (var name in new[] { nameof(InboxController.GetNewTitles), nameof(InboxController.SendNewTitles) })
        {
            var authorize = Assert.Single(typeof(InboxController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>());
            Assert.Equal(Policies.RequiresElevation, authorize.Policy);
        }
    }
```

In `PluginPagesTests.cs`, in fondo al test:

```csharp
        Assert.Contains("WonderFlixWatchParty/Inbox/NewTitles", html);
        Assert.Contains("NotifyNewTitles", html);
        Assert.Contains("emby-checkbox", html);
        // L'id con cui la pagina legge e salva la configurazione è quello del plugin.
        Assert.Contains(Plugin.PluginId.ToString(), html);
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: errori di compilazione (`GetNewTitles`, `SendNewTitles`, costruttore di `InboxController`).

- [ ] **Step 3: gli endpoint**

In `Api/InboxController.cs`:
- il costruttore primario diventa:

```csharp
public class InboxController(
    IAuthorizationContext authorizationContext,
    InboxService inbox,
    NewTitlesCollector newTitles,
    INewTitlesSettings newTitlesSettings) : ControllerBase
```

- nel commento della classe, "gli annunci solo per gli admin" diventa "gli annunci e i nuovi titoli in attesa solo per gli admin";
- dopo `Announce`:

```csharp
    /// <summary>La casella dei nuovi titoli e quanti ne aspettano (pagina della Dashboard); solo per gli admin.</summary>
    [HttpGet("Inbox/NewTitles")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<NewTitlesStatus> GetNewTitles() =>
        new NewTitlesStatus(newTitlesSettings.NotifyNewTitles, newTitles.Pending);

    /// <summary>Chiude subito l'ondata dei nuovi titoli ("Send now"); solo per gli admin.</summary>
    [HttpPost("Inbox/NewTitles/Send")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<NewTitlesSendResponse>> SendNewTitles() =>
        await newTitles.SendNowAsync().ConfigureAwait(false);
```

- [ ] **Step 4: la pagina**

Sostituisci `Configuration/configPage.html` con (l'annuncio resta com'è; si aggiunge la sezione dei nuovi titoli):

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>WonderFlix Watch Party</title>
</head>
<body>
    <div id="WonderFlixWatchPartyPage" data-role="page" class="page type-interior pluginConfigurationPage" data-require="emby-button,emby-textarea,emby-checkbox">
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
                <div class="verticalSection">
                    <h3 class="sectionTitle">New titles</h3>
                    <div class="checkboxContainer checkboxContainer-withDescription">
                        <label class="emby-checkbox-label">
                            <input id="WonderFlixNotifyNewTitles" type="checkbox" is="emby-checkbox" />
                            <span>Notify new titles</span>
                        </label>
                        <div class="fieldDescription checkboxFieldDescription">
                            New movies, and new episodes of the series each user follows, are summed up in their notifications
                            after 15 quiet minutes (2 hours at most). Turn it off before a big import: titles waiting are dropped.
                        </div>
                    </div>
                    <div id="WonderFlixNewTitlesPending" class="fieldDescription"></div>
                    <button is="emby-button" id="WonderFlixNewTitlesSend" type="button" class="raised block emby-button">
                        <span>Send now</span>
                    </button>
                    <div id="WonderFlixNewTitlesResult" class="fieldDescription"></div>
                </div>
            </div>
        </div>
        <script type="text/javascript">
            (function () {
                var pluginId = '882eb47e-668a-4935-ba55-c2858eb4ed90';
                var page = document.querySelector('#WonderFlixWatchPartyPage');
                var text = page.querySelector('#WonderFlixAnnouncementText');
                var count = page.querySelector('#WonderFlixAnnouncementCount');
                var result = page.querySelector('#WonderFlixAnnouncementResult');
                var notify = page.querySelector('#WonderFlixNotifyNewTitles');
                var pending = page.querySelector('#WonderFlixNewTitlesPending');
                var sendNow = page.querySelector('#WonderFlixNewTitlesSend');
                var newTitlesResult = page.querySelector('#WonderFlixNewTitlesResult');

                function refreshNewTitles() {
                    ApiClient.ajax({
                        type: 'GET',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Inbox/NewTitles'),
                        dataType: 'json'
                    }).then(function (status) {
                        notify.checked = status.Enabled;
                        pending.textContent = status.Pending === 1 ? '1 title waiting.' : status.Pending + ' titles waiting.';
                        sendNow.disabled = !status.Enabled || status.Pending === 0;
                    }, function () {
                        pending.textContent = 'Status not available.';
                        sendNow.disabled = true;
                    });
                }

                page.addEventListener('pageshow', refreshNewTitles);
                refreshNewTitles();

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
                        result.textContent = 'Sent to ' + response.Recipients + (response.Recipients === 1 ? ' user.' : ' users.');
                        text.value = '';
                        count.textContent = '0';
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        result.textContent = 'Not sent: check the message (1 to 500 characters) and try again.';
                    });
                    return false;
                });

                // La casella si salva subito, nella configurazione del plugin (NotifyNewTitles).
                notify.addEventListener('change', function () {
                    Dashboard.showLoadingMsg();
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        config.NotifyNewTitles = notify.checked;
                        return ApiClient.updatePluginConfiguration(pluginId, config);
                    }).then(function (saved) {
                        Dashboard.processPluginConfigurationUpdateResult(saved);
                        refreshNewTitles();
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        newTitlesResult.textContent = 'Setting not saved.';
                        refreshNewTitles();
                    });
                });

                sendNow.addEventListener('click', function () {
                    Dashboard.showLoadingMsg();
                    ApiClient.ajax({
                        type: 'POST',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Inbox/NewTitles/Send'),
                        dataType: 'json'
                    }).then(function (response) {
                        Dashboard.hideLoadingMsg();
                        newTitlesResult.textContent = response.Titles === 0
                            ? 'Nothing to send.'
                            : 'Sent ' + response.Titles + (response.Titles === 1 ? ' title' : ' titles')
                                + ' to ' + response.Recipients + (response.Recipients === 1 ? ' user.' : ' users.');
                        refreshNewTitles();
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        newTitlesResult.textContent = 'Not sent: try again.';
                        refreshNewTitles();
                    });
                });
            })();
        </script>
    </div>
</body>
</html>
```

- [ ] **Step 5: README**

In `jellyfin-plugin-watch-party/README.md`:
- la voce "Nessuna impostazione. …" diventa: "Un'impostazione, **Notify new titles** (accesa di default), nella pagina del plugin nella Dashboard (menu laterale, sotto Plugin): la stessa pagina manda un **annuncio** a tutti e, con **Send now**, il riepilogo dei nuovi titoli in attesa. Endpoint sotto `/WonderFlixWatchParty`; gli eventi arrivano ai client come `GeneralCommand` `SendString` con la chiave `WonderFlixWatchParty`.";
- la voce **Notifiche** diventa: "- **Notifiche:** la cassetta di ogni utente (inviti ai watch party, annunci, nuovi titoli) sta in `plugins/configurations/WonderFlixWatchParty/inbox.json`: 30 giorni, al massimo 100 voci per utente. Un file illeggibile diventa `inbox.json.bad`. **Nuovi titoli:** i film e gli episodi aggiunti alla libreria si raccolgono in un'ondata che si chiude dopo 15 minuti senza novità (al massimo 2 ore); ogni utente riceve i film che può vedere e gli episodi delle serie che segue (La mia lista, o un episodio visto o iniziato). L'impostazione sta in `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`.".

- [ ] **Step 6: i test passano e il pacchetto si crea**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

Run: `bash jellyfin-plugin-watch-party/pack.sh 1.2.0`
Expected: `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.2.0.0/` con la dll e `meta.json`.

- [ ] **Step 7: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the new titles controls to the admin page"
```

### Task 5: plugin sul server vero (orchestratore, nessun subagent)

Lo fa l'orchestratore dopo la review del gruppo A (lavoro sul server autorizzato, `ssh ultra`). Sul server c'è già la copia manuale `WonderFlix Watch Party_1.2.0.0` del piano 13a.

1. **Controllo dei riferimenti** della nuova dll contro Jellyfin 10.11.9 (progetto `refprobe` nella scratchpad, o ricrearlo: console `net9.0`, `FrameworkReference Microsoft.AspNetCore.App`, `Jellyfin.Controller`/`Jellyfin.Model` 10.11.9, risoluzione di ogni `TypeReference`/`MemberReference`). Atteso: 0 non risolti.
2. **Nessuno guarda?** Nel log del giorno nessuna riga "Processing playback tracker" negli ultimi 5 minuti; se qualcuno guarda, aspettare (o chiedere all'utente).
3. **Stop → copia → avvio:** `ssh ultra 'app-jellyfin stop'`; `scp -r "jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.2.0.0" ultra:.apps/jellyfin/data/plugins/` (sovrascrive la copia del 13a); `ssh ultra 'app-jellyfin start'`.
4. **Log:** `Loaded plugin: "WonderFlix Watch Party" "1.2.0.0"`, "avviato", "Amici in …", "Cassetta delle notifiche in …"; nessun errore del plugin.

## Gruppo B — app

### Task 6: testi delle novità

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan13b_inbox_test.dart` (nuovo)

- [ ] **Step 1: test che fallisce**

Crea `test/app/l10n_plan13b_inbox_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 13b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.inboxNewTitles('2 film, 10 episodi'), 'Novità: 2 film, 10 episodi');
    expect(it.inboxMovies(1), '1 film');
    expect(it.inboxMovies(3), '3 film');
    expect(it.inboxEpisodes(1), '1 episodio');
    expect(it.inboxEpisodes(10), '10 episodi');
    expect(it.inboxNewEpisodes(1), '1 episodio nuovo');
    expect(it.inboxNewEpisodes(3), '3 episodi nuovi');
    expect(it.inboxShowAll(12), 'Mostra tutto (12)');
    expect(it.inboxMore(1), '…e un altro titolo');
    expect(it.inboxMore(7), '…e altri 7 titoli');
    expect(en.inboxNewTitles('2 movies, 10 episodes'), 'New: 2 movies, 10 episodes');
    expect(en.inboxMovies(1), '1 movie');
    expect(en.inboxMovies(3), '3 movies');
    expect(en.inboxEpisodes(1), '1 episode');
    expect(en.inboxEpisodes(10), '10 episodes');
    expect(en.inboxNewEpisodes(1), '1 new episode');
    expect(en.inboxNewEpisodes(3), '3 new episodes');
    expect(en.inboxShowAll(12), 'Show all (12)');
    expect(en.inboxMore(1), '…and 1 more');
    expect(en.inboxMore(7), '…and 7 more');
  });
}
```

- [ ] **Step 2: il test non compila**

Run: `flutter test test/app/l10n_plan13b_inbox_test.dart`
Expected: errori di compilazione (getter mancanti).

- [ ] **Step 3: le stringhe**

In `l10n/app_it.arb`, dopo l'ultima voce (`"@inboxDaysAgo": {…}`, a cui va la virgola), prima della `}` finale:

```json
  "inboxNewTitles": "Novità: {summary}",
  "@inboxNewTitles": {"placeholders": {"summary": {"type": "String"}}},
  "inboxMovies": "{count, plural, =1{1 film} other{{count} film}}",
  "@inboxMovies": {"placeholders": {"count": {"type": "int"}}},
  "inboxEpisodes": "{count, plural, =1{1 episodio} other{{count} episodi}}",
  "@inboxEpisodes": {"placeholders": {"count": {"type": "int"}}},
  "inboxNewEpisodes": "{count, plural, =1{1 episodio nuovo} other{{count} episodi nuovi}}",
  "@inboxNewEpisodes": {"placeholders": {"count": {"type": "int"}}},
  "inboxShowAll": "Mostra tutto ({count})",
  "@inboxShowAll": {"placeholders": {"count": {"type": "int"}}},
  "inboxMore": "{count, plural, =1{…e un altro titolo} other{…e altri {count} titoli}}",
  "@inboxMore": {"placeholders": {"count": {"type": "int"}}}
```

In `l10n/app_en.arb`, dopo l'ultima voce (`"inboxDaysAgo": "{count} days ago"`, con la virgola):

```json
  "inboxNewTitles": "New: {summary}",
  "inboxMovies": "{count, plural, =1{1 movie} other{{count} movies}}",
  "inboxEpisodes": "{count, plural, =1{1 episode} other{{count} episodes}}",
  "inboxNewEpisodes": "{count, plural, =1{1 new episode} other{{count} new episodes}}",
  "inboxShowAll": "Show all ({count})",
  "inboxMore": "{count, plural, =1{…and 1 more} other{…and {count} more}}"
```

Run: `flutter gen-l10n`

- [ ] **Step 4: il test passa**

Run: `flutter test test/app/l10n_plan13b_inbox_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add l10n test/app/l10n_plan13b_inbox_test.dart
git commit -m "feat(app): add the new titles strings"
```

### Task 7: film, serie ed episodi nuovi; intervalli di episodi

**Files:**
- Modify: `lib/core/social/inbox_models.dart`
- Test: `test/core/social/inbox_models_test.dart`

- [ ] **Step 1: test che falliscono**

In `test/core/social/inbox_models_test.dart`, prima della `}` finale di `main`:

```dart
  test('film, serie ed episodi nuovi dal JSON', () {
    final movie = NewTitleMovie.fromJson(
        const {'ItemId': 'm1', 'Name': 'Dune', 'Year': 2024});
    expect((movie.itemId, movie.name, movie.year), ('m1', 'Dune', 2024));
    expect(NewTitleMovie.fromJson(const {'ItemId': 'm2', 'Name': 'X'}).year,
        isNull);
    final series = NewTitleSeries.fromJson(const {
      'SeriesId': 's1',
      'Name': 'The Bear',
      'Episodes': [
        {'Season': 3, 'Episode': 1},
        <String, dynamic>{},
      ],
    });
    expect(series.seriesId, 's1');
    expect(series.name, 'The Bear');
    expect(series.episodes.first.season, 3);
    expect(series.episodes.first.episode, 1);
    expect(series.episodes.last.season, isNull);
    expect(
        NewTitleSeries.fromJson(const {'SeriesId': 's2', 'Name': 'Y'})
            .episodes,
        isEmpty);
  });

  test('episodi in intervalli', () {
    List<NewTitleEpisode> episodes(List<(int, int)> list) => [
          for (final (season, episode) in list)
            NewTitleEpisode(season: season, episode: episode),
        ];
    expect(
        formatEpisodeRanges(episodes([for (var e = 1; e <= 10; e++) (3, e)])),
        'S3 E1–E10');
    expect(
        formatEpisodeRanges(
            episodes([(3, 6), (3, 1), (3, 2), (3, 3), (3, 4)])),
        'S3 E1–E4, E6');
    expect(formatEpisodeRanges(episodes([(3, 1), (2, 10), (3, 3), (3, 2)])),
        'S2 E10 · S3 E1–E3');
    expect(formatEpisodeRanges(episodes([(1, 5)])), 'S1 E5');
    expect(formatEpisodeRanges(episodes([(1, 5), (1, 5)])), 'S1 E5',
        reason: 'doppioni');
    expect(
        formatEpisodeRanges(const [
          NewTitleEpisode(season: 1, episode: 1),
          NewTitleEpisode(season: 1),
        ]),
        isNull,
        reason: 'basta un numero mancante');
    expect(formatEpisodeRanges(const []), isNull);
  });
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/core/social/inbox_models_test.dart`
Expected: errori di compilazione (`NewTitleMovie`, `NewTitleSeries`, `formatEpisodeRanges` non esistono).

- [ ] **Step 3: i modelli**

In `lib/core/social/inbox_models.dart` aggiungi in testa `import 'dart:collection';` e, dopo `AnnouncementEntry`:

```dart
/// Un film nuovo (spec G §6.6).
class NewTitleMovie {
  const NewTitleMovie({required this.itemId, required this.name, this.year});

  factory NewTitleMovie.fromJson(Map<String, dynamic> json) => NewTitleMovie(
        itemId: json['ItemId'] as String,
        name: json['Name'] as String,
        year: (json['Year'] as num?)?.toInt(),
      );

  final String itemId;
  final String name;
  final int? year;
}

/// Un episodio nuovo: stagione e numero, se Jellyfin li conosce.
class NewTitleEpisode {
  const NewTitleEpisode({this.season, this.episode});

  factory NewTitleEpisode.fromJson(Map<String, dynamic> json) =>
      NewTitleEpisode(
        season: (json['Season'] as num?)?.toInt(),
        episode: (json['Episode'] as num?)?.toInt(),
      );

  final int? season;
  final int? episode;
}

/// Una serie seguita con i suoi episodi nuovi; la riga apre la serie.
class NewTitleSeries {
  const NewTitleSeries({
    required this.seriesId,
    required this.name,
    required this.episodes,
  });

  factory NewTitleSeries.fromJson(Map<String, dynamic> json) => NewTitleSeries(
        seriesId: json['SeriesId'] as String,
        name: json['Name'] as String,
        episodes: [
          for (final raw in json['Episodes'] as List? ?? const [])
            NewTitleEpisode.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String seriesId;
  final String name;
  final List<NewTitleEpisode> episodes;
}

/// Gli episodi come intervalli per stagione (spec G §7.6): `S3 E1–E10`,
/// `S3 E1–E4, E6`, più stagioni unite da ` · ` (`S2 E10 · S3 E1–E3`).
/// `null` se manca anche un solo numero (chi mostra la riga scrive allora
/// "N episodi nuovi") o se non ci sono episodi.
String? formatEpisodeRanges(List<NewTitleEpisode> episodes) {
  if (episodes.isEmpty ||
      episodes.any((e) => e.season == null || e.episode == null)) {
    return null;
  }
  final bySeason = SplayTreeMap<int, SplayTreeSet<int>>();
  for (final episode in episodes) {
    (bySeason[episode.season!] ??= SplayTreeSet<int>()).add(episode.episode!);
  }
  return [
    for (final MapEntry(key: season, value: numbers) in bySeason.entries)
      'S$season ${_episodeRuns(numbers.toList())}',
  ].join(' · ');
}

/// Numeri ordinati e senza doppioni come `E1–E4, E6`.
String _episodeRuns(List<int> numbers) {
  final runs = <String>[];
  var start = numbers.first;
  var previous = start;
  for (final number in numbers.skip(1)) {
    if (number == previous + 1) {
      previous = number;
      continue;
    }
    runs.add(_episodeRun(start, previous));
    start = previous = number;
  }
  runs.add(_episodeRun(start, previous));
  return runs.join(', ');
}

String _episodeRun(int first, int last) =>
    first == last ? 'E$first' : 'E$first–E$last';
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/social/inbox_models_test.dart`
Expected: PASS.

- [ ] **Step 5: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/core/social/inbox_models.dart test/core/social/inbox_models_test.dart
git commit -m "feat(app): add the new titles models and episode ranges"
```

### Task 8: la voce Novità nel pannello

**Files:**
- Modify: `lib/core/social/inbox_models.dart`
- Modify: `lib/app/navigation.dart`
- Modify: `lib/features/inbox/inbox_panel.dart`
- Modify: `test/support/social_fakes.dart`
- Test: `test/core/social/inbox_models_test.dart`, `test/features/inbox/inbox_panel_test.dart`, `test/features/inbox/inbox_new_titles_navigation_test.dart` (nuovo)

`InboxEntry` è `sealed`: `NewTitlesEntry` e i due `switch` del pannello cambiano nello stesso commit.

- [ ] **Step 1: aiuto per i test**

In `test/support/social_fakes.dart`, dopo `testAnnouncement`:

```dart
/// Un riepilogo di nuovi titoli nella cassetta.
NewTitlesEntry testNewTitles({
  String id = 'n1',
  int seq = 1,
  bool read = false,
  List<NewTitleMovie> movies = const [],
  List<NewTitleSeries> series = const [],
  int more = 0,
  DateTime? createdAt,
}) =>
    NewTitlesEntry(
      id: id,
      seq: seq,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 4, 20),
      read: read,
      movies: movies,
      series: series,
      more: more,
    );
```

- [ ] **Step 2: test che falliscono**

In `test/core/social/inbox_models_test.dart`:

```dart
  test('voce delle novità', () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'n1',
          'Seq': 2,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-04T20:00:00+00:00',
          'Read': false,
          'Movies': [
            {'ItemId': 'm1', 'Name': 'Dune', 'Year': 2024},
          ],
          'Series': [
            {
              'SeriesId': 's1',
              'Name': 'The Bear',
              'Episodes': [
                {'Season': 3, 'Episode': 1},
                {'Season': 3, 'Episode': 2},
              ],
            },
          ],
          'More': 4,
        },
        {
          'Id': 'n2',
          'Seq': 1,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'Read': true,
        },
      ],
    });

    final first = snapshot.entries.first as NewTitlesEntry;
    expect(first.movies.single.name, 'Dune');
    expect(first.series.single.episodes, hasLength(2));
    expect(first.episodeCount, 2);
    expect(first.more, 4);
    final second = snapshot.entries.last as NewTitlesEntry;
    expect(second.movies, isEmpty);
    expect(second.series, isEmpty);
    expect(second.more, 0);
    expect(snapshot.unread, 1);
  });
```

In `test/features/inbox/inbox_panel_test.dart`, prima della `}` finale di `main`:

```dart
  testWidgets('novità: riepilogo, prime 5 righe, Mostra tutto, altri titoli',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testNewTitles(
        createdAt: fiveMinutesAgo(),
        movies: [
          for (var i = 1; i <= 4; i++)
            NewTitleMovie(itemId: 'm$i', name: 'Film $i', year: 2020 + i),
        ],
        series: const [
          NewTitleSeries(seriesId: 's1', name: 'The Bear', episodes: [
            NewTitleEpisode(season: 3, episode: 1),
            NewTitleEpisode(season: 3, episode: 2),
          ]),
          NewTitleSeries(seriesId: 's2', name: 'Senza numeri', episodes: [
            NewTitleEpisode(),
            NewTitleEpisode(season: 1, episode: 4),
          ]),
        ],
        more: 7,
      ),
    ], unread: 1);
    await pumpPanel(tester);

    expect(find.text('Novità: 4 film, 4 episodi'), findsOneWidget);
    expect(find.text('Film 1 (2021)'), findsOneWidget);
    expect(find.text('The Bear · S3 E1–E2'), findsOneWidget);
    expect(find.text('Senza numeri · 2 episodi nuovi'), findsNothing,
        reason: 'sesta riga, nascosta');
    expect(find.text('…e altri 7 titoli'), findsOneWidget);
    expect(find.text('5 min fa'), findsOneWidget);

    await tester.tap(find.text('Mostra tutto (6)'));
    await tester.pump();

    expect(find.text('Senza numeri · 2 episodi nuovi'), findsOneWidget);
    expect(find.text('Mostra tutto (6)'), findsNothing);
  });

  testWidgets('novità solo di film o solo di episodi', (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [
      testNewTitles(id: 'n1', seq: 2, createdAt: fiveMinutesAgo(), movies: const [
        NewTitleMovie(itemId: 'm1', name: 'Senza anno'),
      ]),
      testNewTitles(id: 'n2', seq: 1, createdAt: fiveMinutesAgo(), series: const [
        NewTitleSeries(seriesId: 's1', name: 'The Bear', episodes: [
          NewTitleEpisode(season: 1, episode: 1),
        ]),
      ]),
    ], unread: 2);
    await pumpPanel(tester);

    expect(find.text('Novità: 1 film'), findsOneWidget);
    expect(find.text('Senza anno'), findsOneWidget);
    expect(find.text('Novità: 1 episodio'), findsOneWidget);
    expect(find.textContaining('Mostra tutto'), findsNothing);
  });
```

Crea `test/features/inbox/inbox_new_titles_navigation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  testWidgets('una riga delle novità apre la scheda e chiude il pannello',
      (tester) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: [
        testNewTitles(
          movies: const [NewTitleMovie(itemId: 'm1', name: 'Dune')],
          series: const [
            NewTitleSeries(seriesId: 's1', name: 'The Bear', episodes: [
              NewTitleEpisode(season: 1, episode: 1),
            ]),
          ],
        ),
      ], unread: 1);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
            ),
          ),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Text('scheda ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const SizedBox.shrink()),
        ...socialTestOverrides(api,
            features: const SocialFeatures(inbox: true)),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();

    await tester.tap(find.text('The Bear · S1 E1'));
    await tester.pumpAndSettle();

    expect(find.text('scheda s1'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });
}
```

(Se alla prova servono altri provider sovrascritti, come in `pumpApp` o nella prova "con un vero router" di `test/features/friends/friends_shell_test.dart`, aggiungili e segnalalo.)

- [ ] **Step 3: i test non compilano**

Run: `flutter test test/core/social/inbox_models_test.dart test/features/inbox`
Expected: errori di compilazione (`NewTitlesEntry`, `testNewTitles`).

- [ ] **Step 4: la voce**

In `lib/core/social/inbox_models.dart`, dopo `NewTitleSeries`:

```dart
/// Il riepilogo di un'ondata di nuovi titoli (spec G §6.6): film che
/// l'utente può vedere ed episodi delle serie che segue.
final class NewTitlesEntry extends InboxEntry {
  const NewTitlesEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    this.movies = const [],
    this.series = const [],
    this.more = 0,
  });

  final List<NewTitleMovie> movies;
  final List<NewTitleSeries> series;

  /// Film e serie oltre il tetto delle righe del plugin.
  final int more;

  /// Episodi in tutto.
  int get episodeCount =>
      series.fold(0, (count, s) => count + s.episodes.length);
}
```

e in `inboxEntryFromJson`, prima di `_ => null,`:

```dart
    'NewTitles' => NewTitlesEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        movies: [
          for (final raw in json['Movies'] as List? ?? const [])
            NewTitleMovie.fromJson(raw as Map<String, dynamic>),
        ],
        series: [
          for (final raw in json['Series'] as List? ?? const [])
            NewTitleSeries.fromJson(raw as Map<String, dynamic>),
        ],
        more: (json['More'] as num?)?.toInt() ?? 0,
      ),
```

- [ ] **Step 5: aprire una scheda da un id**

In `lib/app/navigation.dart`, dopo `openItem`:

```dart
/// Apre la scheda di un film o di una serie di cui si conosce solo l'id (es.
/// una riga delle novità nella cassetta, spec G §7.6).
void openItemById(BuildContext context, String itemId) =>
    unawaited(context.push('/item/$itemId'));
```

- [ ] **Step 6: il pannello**

In `lib/features/inbox/inbox_panel.dart`:

- aggiungi l'import `'../../app/navigation.dart'`;
- in `InboxPanel`, dopo `dotSize`:

```dart
  /// Righe delle novità prima di "Mostra tutto".
  static const newTitlesPreview = 5;
```

- in `_EntryTileState.build`, nei due `switch (entry)` aggiungi il caso delle novità:

```dart
              NewTitlesEntry() => const _NewTitlesIcon(),
```

(in quello dell'icona, dopo `AnnouncementEntry() => const _AnnouncementIcon(),`) e

```dart
                NewTitlesEntry() =>
                  _NewTitlesContent(entry: entry, time: widget.time),
```

(in quello del contenuto, dopo il caso `AnnouncementEntry()`);

- dopo `_AnnouncementIcon`:

```dart
class _NewTitlesIcon extends StatelessWidget {
  const _NewTitlesIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: InboxPanel.leadingSize,
        height: InboxPanel.leadingSize,
        decoration: const BoxDecoration(
            color: WfColors.surfaceHigh, shape: BoxShape.circle),
        child: const Icon(LucideIcons.sparkles,
            size: 18, color: WfColors.gold),
      );
}
```

- in fondo al file:

```dart
/// Novità (spec G §7.6): riepilogo, le prime righe e "Mostra tutto". Una
/// riga apre la scheda del film o della serie e chiude il pannello.
class _NewTitlesContent extends ConsumerStatefulWidget {
  const _NewTitlesContent({required this.entry, required this.time});

  final NewTitlesEntry entry;
  final String time;

  @override
  ConsumerState<_NewTitlesContent> createState() => _NewTitlesContentState();
}

class _NewTitlesContentState extends ConsumerState<_NewTitlesContent> {
  bool _expanded = false;

  void _open(String itemId) {
    ref.read(shellPanelProvider.notifier).close();
    openItemById(context, itemId);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    final summary = [
      if (entry.movies.isNotEmpty) l.inboxMovies(entry.movies.length),
      if (entry.episodeCount > 0) l.inboxEpisodes(entry.episodeCount),
    ].join(', ');
    final lines = [
      for (final movie in entry.movies)
        (
          id: movie.itemId,
          text: movie.year == null
              ? movie.name
              : '${movie.name} (${movie.year})',
        ),
      for (final series in entry.series)
        (
          id: series.seriesId,
          text: '${series.name} · '
              '${formatEpisodeRanges(series.episodes) ?? l.inboxNewEpisodes(series.episodes.length)}',
        ),
    ];
    final shown = _expanded
        ? lines
        : lines.take(InboxPanel.newTitlesPreview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.inboxNewTitles(summary),
            style: const TextStyle(
                color: WfColors.cream, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        for (final line in shown)
          InkWell(
            key: Key('inbox-title-${line.id}'),
            onTap: () => _open(line.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mutedStyle),
            ),
          ),
        if (!_expanded && lines.length > InboxPanel.newTitlesPreview)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            style: TextButton.styleFrom(
              foregroundColor: WfColors.gold,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            child: Text(l.inboxShowAll(lines.length)),
          ),
        if (entry.more > 0) Text(l.inboxMore(entry.more), style: _mutedStyle),
        const SizedBox(height: 4),
        Text(widget.time, style: _timeStyle),
      ],
    );
  }
}
```

- [ ] **Step 7: i test passano**

Run: `flutter test test/core/social/inbox_models_test.dart test/features/inbox`
Expected: PASS.

- [ ] **Step 8: verifica e commit**

Run: `flutter analyze` (nessun problema) e `flutter test` (tutto verde).

```bash
git add lib/core/social/inbox_models.dart lib/app/navigation.dart lib/features/inbox/inbox_panel.dart test/support/social_fakes.dart test/core/social/inbox_models_test.dart test/features/inbox
git commit -m "feat(app): show the new titles entry in the notifications panel"
```

## Gruppo C — chiusura

### Task 9: spec e documenti allineati, verifica finale, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: allinea lo spec al codice** (leggi prima il codice vero: `NewTitlesCollector.cs`, `NewTitlesWave.cs`, `NewTitleRules.cs`, `JellyfinLibraryTitles.cs`, `NewTitlesHostedService.cs`, `InboxController.cs`, `configPage.html`, `inbox_models.dart`, `inbox_panel.dart`)

- **Stato:** "approvato; piani 13a e 13b realizzati (…13a…, `docs/superpowers/plans/2026-10-04-wonderflix-13b-nuovi-titoli-release.md`)".
- **§6.3:** aggiungi alla tabella `GET Inbox/NewTitles` → `{Enabled, Pending}` e `POST Inbox/NewTitles/Send` → `{Titles, Recipients}`, **solo admin** (`RequiresElevation`).
- **§6.6:** togli le note "arriva con il 13b"; aggiungi: il filtro "titolo vero" (film o episodio, non virtuale, con un file, non extra) vale per gli aggiunti **e** per i tolti (il segnaposto di TVDB tolto all'arrivo dell'episodio vero non è una sostituzione); gli id esterni dei tolti si leggono subito, gli aggiunti si rileggono alla chiusura; l'ondata aspetta oltre i 15 minuti se Jellyfin scansiona ancora o se un titolo non ha ancora i metadati, sempre entro le 2 ore; "Send now" la chiude subito; con la casella spenta non si raccoglie e l'ondata in corso si butta; "serie seguita" = preferita, o un altro episodio visto o iniziato, con conteggi sul database; controllo ogni minuto; una serie nuova che nessuno segue non compare (scelta dell'utente).
- **§6.8:** la pagina ha la casella **Notify new titles** (si salva subito nella configurazione, `PluginConfiguration.NotifyNewTitles`, letta ogni volta), "N titles waiting" e **Send now** (spento con la casella spenta o niente in attesa); il plugin è `BasePlugin<PluginConfiguration>` con `Plugin.Instance`.
- **§7.1:** `NewTitleMovie`, `NewTitleEpisode`, `NewTitleSeries`, `NewTitlesEntry` (`episodeCount`) e `formatEpisodeRanges` stanno in `lib/core/social/inbox_models.dart`.
- **§7.6:** Novità: icona `sparkles`; "Novità: 2 film, 10 episodi" (solo le parti presenti); prime 5 righe, "Mostra tutto (N)" (N = righe), poi tutte; una riga apre `/item/<id>` (la serie, per gli episodi) e chiude il pannello; "…e altri N titoli" se `More > 0`.
- **§9:** le chiavi delle novità passano dalla tabella del 13b a quella principale, con i testi veri.
- **§11:** la release è fatta come descritto nel piano 13b (aggiorna le frasi al futuro se servono).

- [ ] **Step 2: RELEASING**

In `docs/RELEASING.md`, sezione "Plugin", al punto 1, dopo la frase su `friends.json`, aggiungi: "La cassetta delle notifiche sta in `plugins/configurations/WonderFlixWatchParty/inbox.json` e l'impostazione dei nuovi titoli in `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`: un aggiornamento del plugin non le tocca."

- [ ] **Step 3: verifica finale**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: tutti verdi, nessun warning.

Run: `flutter analyze` → nessun problema; `flutter test` → tutto verde.

- [ ] **Step 4: build di release per la prova**

Copia `config/wonderflix.json` dalla root del repository principale nel worktree (se non c'è), poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe`. Se la build tocca `windows/flutter/generated_plugin*` con soli fine riga: `git checkout -- windows/flutter/`.

- [ ] **Step 5: commit**

```bash
git add docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md docs/RELEASING.md
git commit -m "docs: align spec G and releasing with plan 13b"
```

## Prova manuale (con l'utente, sul server reale)

Il plugin aggiornato è sul server (Task 5). L'exe lo avvia l'utente.

1. **Pagina della Dashboard:** la sezione "New titles" mostra la casella accesa e "0 titles waiting"; togliendo e rimettendo la spunta compare "Impostazioni salvate" e la scelta resta dopo un ricaricamento della pagina.
2. **Un titolo nuovo:** quando arriva un film o un episodio di una serie che segui (da Radarr/Sonarr, o aggiunto a mano), la pagina mostra "N titles waiting" (ricaricala); **Send now** → "Sent N titles to M users".
3. **Nell'app:** la voce Novità con l'icona `sparkles`, "Novità: …", le righe (film con l'anno, serie con gli intervalli), "Mostra tutto" se sono più di 5; un clic su una riga apre la scheda e chiude il pannello.
4. **Senza "Send now":** dopo 15 minuti di quiete la voce arriva da sola.
5. **Casella spenta:** "0 titles waiting" e "Send now" spento; un titolo che arriva non viene raccolto.
6. **Chi non segue la serie** non riceve gli episodi; chi non vede la libreria non riceve il film.

Se qualcosa non va, le correzioni si fanno con TDD nello stesso worktree prima del merge.

## Release (dopo la prova e il merge, con l'utente)

Fuori dai task: la fa l'orchestratore, passo per passo, con l'ok dell'utente dove indicato (`docs/RELEASING.md`).

1. **Merge:** con l'ok dell'utente, `git fetch`, fast-forward di `main` (rebase se serve), push, rimozione di worktree e branch.
2. **Plugin 1.2.0** (con l'ok dell'utente per il tag):
   - `git tag watch-party-plugin-v1.2.0` e push del tag; il workflow pubblica la **pre-release** con lo zip e il `.md5` (`releases/latest` resta l'app).
   - In `jellyfin-plugin-watch-party/manifest.json`: in cima a `versions` la voce `1.2.0.0` (changelog in italiano: "Cassetta delle notifiche: inviti ai watch party, annunci dell'admin dalla Dashboard, riepilogo dei nuovi titoli."; `sourceUrl` della release; `checksum` = contenuto del `.md5`; `timestamp`), e la `description`/`overview` del plugin aggiornate con le notifiche; commit `chore: publish the watch party plugin 1.2.0` e push.
3. **Server:** controllo che nessuno guardi; la cartella manuale `WonderFlix Watch Party_1.2.0.0` va in `~/wfwp-backup/1.2.0.0-manuale` (spostata, non cancellata); riavvio; l'utente aggiorna **WonderFlix Watch Party** dal **Catalogo**; riavvio; nel log `Loaded plugin … "1.2.0.0"` e la md5 della dll uguale a quella dello zip.
4. **App 0.7.0** (non obbligatoria): `version: 0.7.0` in `pubspec.yaml`, commit `chore: release 0.7.0`, push; con l'ok dell'utente `git tag v0.7.0` e push del tag; a pipeline finita **scrivo io** le note in italiano nella bozza (`gh release edit v0.7.0 --notes-file …`), **senza** il marcatore `min-version`; **pubblica l'utente**.
5. **Issue #7:** dopo la pubblicazione e con l'ok dell'utente, commento ("Discord scartato dopo la ricerca: al suo posto la cassetta delle notifiche in [WonderFlix 0.7.0](link)…") e chiusura come **non pianificata** (`gh issue close 7 --reason "not planned" --comment …`).
