# WonderFlix — Piano 17a: saghe

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte K1 della Spec K. Ci sono:
- nel **plugin 1.5.0**, l'endpoint `GET WonderFlixWatchParty/Collections` con la funzione `collections`;
- nell'app, la **pagina della saga** (`/collection/:id`);
- le **righe "Fa parte di"** nella scheda del film;
- la vista **"Saghe"** nel catalogo Film (`/movies?view=sagas`);
- le **saghe nella ricerca**.

I profili sono nel piano 17b; le immagini del profilo, l'endpoint degli avatar e la release nel 17c.

**Spec:** `docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md` (§3.1, §4, §5, §6, §7.1, §7.3, §8, §11, §12, §13, §14, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 11):
1. **Adattatore delle collezioni:** `JellyfinCollectionDirectory` legge la cartella con `ICollectionManager.GetCollectionsFolder(false)`. Poi chiama `GetChildren(user, true, new InternalItemsQuery())` sulla cartella e su ogni `BoxSet`, la stessa chiamata che Jellyfin fa per `GET /Items?parentId=…`, quindi con gli stessi filtri di visibilità. Nei test si prova solo il caso senza utente o senza cartella: gli oggetti veri di Jellyfin si provano sul server (Task 3 e Task 12).
2. **Versione:** il csproj passa a 1.5.0 già qui, per la build di prova installata sul server. Tag, manifest e Catalogo si fanno nel 17c.
3. **Il titolo di una riga come link:** `MediaRow` riceve `onTitleTap`; il titolo ha una freccia (`LucideIcons.arrowRight`, diversa dalle frecce di scorrimento).
4. **"Questo film":** `PosterCard` riceve `markLabel`, un'etichetta fissa con il bordo oro sempre acceso. Il film aperto, nella sua riga, non si apre di nuovo (`onTap` vuoto).
5. **Pagina della saga:** una testata sua (`CollectionHeader`), non `DetailHeader`, che ha preferiti, visto e trailer pensati per un titolo. Il contenitore che sfuma salendo (`_ScrollFade` di `detail_header.dart`) diventa pubblico come `HeaderScrollFade` e lo usano tutte e due.
6. **Vista "Saghe":** è nell'indirizzo (`/movies?view=sagas`). Il selettore usa `context.go` come le schede delle pagine Richieste e Amministrazione. Ricerca e ordinamento restano nello stato della vista (non nell'indirizzo).
7. **`FilterPicker`:** il menu `_Picker` di `catalog_filters_bar.dart` diventa pubblico, per l'ordinamento delle saghe.
8. **Ricerca:** se la libreria non trova niente ma ci sono saghe, "Nessun risultato" non compare.
9. **Testi inglesi:** "Collections" e "collection", come in Jellyfin.

**Architecture:**
- **Plugin:** `ICollectionDirectory` (Hub) e `JellyfinCollectionDirectory` (Server), `CollectionsController`, DTO in `CollectionDtos.cs`, funzione `collections` in `WatchPartyProtocol.Features`.
- **App, dati:**
  - `ItemKind.boxSet` e la rotta `/collection/:id`;
  - `PluginFeatures.collections` e `SocialFeatures.collections`;
  - `CollectionSummary` e `CollectionsApi` in `lib/core/social/`;
  - `ImageUrls.primaryWithTag` e `LibraryApi.collectionItems`.
- **App, logica:** `collections_logic.dart` (funzioni pure) e `collections_providers.dart` (`collectionsProvider` in cache, l'indice per titolo, i titoli di una saga).
- **App, interfaccia:** `CollectionRows`, `CollectionScreen` con `CollectionHeader`, `CollectionCard`, `CollectionsGrid`, `SagasSearchSection`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, lucide_icons_flutter; plugin .NET 9, Jellyfin 10.11.0 (riferimento), xUnit.

**Worktree:** `.claude/worktrees/piano-17a`, branch `feat/piano-17a`. **Base:** `main` con questo piano. **Test a inizio piano:** 2129 Flutter e 383 plugin (contati il 2026-10-07 su `4eb43d0`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `flutter`, `dart`, `dotnet` o `git`, prima rinfresca il PATH (la shell dello strumento ha un PATH vecchio):
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-17a`).
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`. Un messaggio su più righe va in un file e si usa `git commit -F <file>`: in PowerShell 5.1 le virgolette dentro un here-string si rompono.
  - `bash` non è nel PATH: lo script `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.5.0`.
- **Prima di ogni commit:**
  - per i task dell'app: `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera);
  - per i task del plugin: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` tutto verde (il csproj ha `TreatWarningsAsErrors`).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
  - Dopo `dotnet test`, fai `dotnet build-server shutdown`, altrimenti il worktree resta occupato.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; `clock.now()`, mai `DateTime.now()`.
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` senza valore (`LoadingView`) non si ferma mai, quindi `pumpAndSettle` va in timeout. Mentre c'è uno spinner, usa `pump()` o `pump(durata)`.
- **Provider `autoDispose`:** restano vivi solo con un ascoltatore; nei test di provider usa `container.listen(...)` prima di leggere. I container dei test hanno `retry: (_, _) => null`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-07 sul codice di `main` (`4eb43d0`), sui pacchetti NuGet di Jellyfin 10.11.0 (riflessione) e sul server, in sola lettura.

**Plugin**
- Rotte sotto `[Route("WonderFlixWatchParty")]`. `[Authorize]` senza policy per Info, Inbox e Requests. Il chiamante è `(await authorizationContext.GetAuthorizationInfo(HttpContext)).UserId`. I controller non rispondono mai 404.
- `WatchPartyProtocol.Features = ["friends", "parties", "inbox", "queue"]`; `FeaturesWith(requests)` aggiunge `"requests"` in fondo. `InfoControllerTests` controlla la versione (`"1.4.0"`) e le funzioni.
- I DTO sono `record` con `[property: JsonPropertyName("…")]` (vedi `FriendDtos.cs`). `ProtocolJsonTests` controlla il JSON.
- Gli adattatori di `Server\` prendono i servizi dal costruttore e si registrano in `PluginServiceRegistrator`. `ServiceRegistrationTests` registra degli stub (`InterfaceStub<T>.Create().Proxy`) per i servizi di Jellyfin che servono.
- `InterfaceStub<T>`: i gestori stanno in `Handlers["NomeMetodo"]`, le chiamate in `Calls`. Un metodo senza gestore che restituisce un riferimento dà `null`, anche se è un `Task<…>`: per `GetCollectionsFolder` serve un gestore che dia `Task.FromResult<Folder?>(null)`.
- Firme di Jellyfin 10.11.0:
  - `ICollectionManager.GetCollectionsFolder(bool createIfNeeded)` → `Task<Folder?>`;
  - `Folder.GetChildren(User user, bool includeLinkedChildren, InternalItemsQuery query)` → `IReadOnlyList<BaseItem>`; `BoxSet` la ridefinisce (ordina secondo `DisplayOrder`);
  - `BaseItem.GetImageInfo(ImageType, int)` → `ItemImageInfo?`;
  - `IImageProcessor.GetImageCacheTag(BaseItem, ItemImageInfo)` → `string`;
  - `IUserManager.GetUserById(Guid)`: con `Guid.Empty` lancia.
- `GET /Items?parentId=…` di Jellyfin, con un utente, fa `GetChildren(user, true, new InternalItemsQuery { … })` sulla cartella: da lì viene la visibilità (librerie e controllo parentale, `IsVisible(user)`).
- `pack.sh <versione>` crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_<versione>.0/` con dll e `meta.json`.

**Server** (spec §3.1)
- 101 collezioni nella cartella nascosta `8679d105-69ec-1298-1200-c4116da3e90b`. Un utente normale le vede con `/Items?parentId=<cartella>`; i film di una collezione con `/Items?parentId=<collezione>` (senza `recursive`), per esempio "Matrix - Collezione" (`f2dad769a40265dd509bdc158f5c8b2c`) con 3 film.
- `/Items?includeItemTypes=BoxSet&recursive=true`, `searchTerm` e `/Search/Hints` danno 0 collezioni, per tutti.
- Jellyfin risponde sotto `http://127.0.0.1:17502/jellyfin/…` (la radice dà 302). Sul server è installato dal Catalogo il plugin `WonderFlix Watch Party_1.4.0.0`.

**App**
- `ItemKind` (`lib/core/jellyfin/item_models.dart`): `movie`, `series`, `season`, `episode`, `person`, `other`. `ItemKind.parse` confronta `apiName`. Nessuno `switch` esaustivo su `ItemKind`: `itemRoute` (`lib/app/navigation.dart`) ha `default`.
- `SocialFeatures` (`lib/features/social/social_providers.dart`) ha `friends`, `parties`, `inbox`, `requests`, `known`, con `==`, `hashCode` e `toString`. `SocialAvailability.refresh` legge `info.features`. `PluginFeatures` è in `lib/core/social/social_models.dart`.
- **Test:**
  - `FakeSocialAvailability(features)` è in `test/support/social_fakes.dart`, e `FakeSocialApi.install(features: …)` imposta `Info`;
  - `FakeLibraryApi` (`test/support/library_fakes.dart`) implementa `LibraryApi`: un metodo nuovo di `LibraryApi` va aggiunto anche lì;
  - `testItem(...)` crea un `JellyfinItem` (il `Type` è `kind.apiName`).
- **JSON:** `json_fields.dart` ha `jsonString`, `jsonDate`, `jsonStrings`, `jsonList(data, parse)`, che salta le voci `null` e lancia `ServerErrorException(null)` se il corpo non è un elenco. `asJsonMap` è in `jellyfin_http.dart`.
- **HTTP:** `JellyfinHttp.get(path, query:, quietStatuses:)`; `restartGatewayStatuses = {502, 503, 504}`. Test con `FakeAdapter((options) => FakeResponse(status, body))` e `JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter)`.
- **`LibraryApi`:** `_list(data)` legge `Items`. `cardImageParams` = `fields: PrimaryImageAspectRatio,Genres`, `enableImageTypes: Primary,Backdrop,Thumb,Logo`, `imageTypeLimit: 1`. `library_api_test.dart` ha `last()` con `.path` e `.query`.
- **`ImageUrls`** (`lib/core/jellyfin/image_urls.dart`): `primaryOf(itemId, maxWidth:)` senza tag, `logo(item)`, `backdrop(item)`.
- **Scheda:**
  - `MovieDetailView`: `StaggerGroup(count: detailEntranceCount)` con `DetailHeader` (elementi 0–4), `CastRow` (5), `SimilarRow` (6). `detailEntranceCount` = 8;
  - `itemProvider(id)` (`detail_providers.dart`) legge `GET /Items/{id}` e guarda `libraryRevisionProvider`;
  - `ItemDetailScreen` è il modello della pagina: sfondo `DetailBackdrop(item:, launch:, controller:)` dietro, `WfSwitcher` con `DetailSkeleton`, `ErrorView` e la vista;
  - `DetailHeader` ha i gradienti, il logo o il nome in maiuscolo, la trama (4 righe) e i pulsanti; il contenitore privato `_ScrollFade(controller:, child:)` fa sfumare il testo salendo.
- **Componenti:**
  - `MediaRow(title:, height:, itemCount:, itemBuilder:, animateEntrance:)`, con le frecce di scorrimento `Key('row-previous')` e `Key('row-next')`;
  - `PosterCard(item:, onTap:, heroSource:, width:)`, con il bordo oro al passaggio del mouse;
  - `primaryActionFor(target, userData)` dà `ResumeAction` (posizione > 0 e non visto) o `PlayAction`;
  - `playItem(context, ref, item)` riprende da solo dal minutaggio salvato;
  - `watchUserData(ref, item)` legge i dati utente aggiornati.
- **Catalogo:**
  - `CatalogScreen(kind:)`: titolo maiuscolo con `l.catalogCount(total)`, `CatalogFiltersBar`, griglia (`maxCrossAxisExtent` 180, `childAspectRatio` 0.55);
  - `_Picker<T>` è privato in `catalog_filters_bar.dart`; `filtersBarHeight` = 40;
  - la rotta `/movies` è `const CatalogScreen(key: ValueKey('movies'), kind: ItemKind.movie)` in `lib/app/router.dart`;
  - `WfTabButton(label:, selected:, onTap:)` è in `lib/ui/wf_tab_button.dart`.
- **Ricerca** (`search_screen.dart`): `ListView` con il campo, poi `WfSwitcher(child: _results(...))` e `RequestablesSection`. `SearchController.minLength` = 2. Il file importa `material.dart` con `hide SearchController`.
- **Test di widget:**
  - `pumpApp(tester, widget, overrides:, surfaceSize:)` (`test/support/pump_app.dart`) monta con `home:`, senza router;
  - `FakeSessionController(const SessionSignedIn(testUser))`;
  - nei widget test senza `socialAvailabilityProvider` sovrascritto, `SocialAvailability` non trova il plugin (il provider di `ClientInfo` non c'è) e dà `SocialFeatures.none`: i test di oggi restano come sono.
- **ARB:** il modello è `l10n/app_it.arb`; i plurali hanno la forma `"{count, plural, =1{…} other{…}}"`, con `@chiave` e i `placeholders`. Le chiavi nuove vanno in fondo, prima della `}` finale (aggiungi la virgola alla riga prima). Ci sono già: `navMovies` ("Film"), `catalogSortLabel` ("Ordina per"), `catalogSortDateAdded` ("Data di aggiunta"), `retry` ("Riprova").

---

## Gruppo A — plugin

### Task 1: endpoint `Collections` e funzione `collections`

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/ICollectionDirectory.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/CollectionDtos.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/CollectionsController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/CollectionsControllerTests.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoControllerTests.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ProtocolJsonTests.cs`

- [ ] **Step 1: i test del controller**

Crea `CollectionsControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class CollectionsControllerTests
{
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly FakeCollections _collections = new();

    private CollectionsController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new CollectionsController(new FakeAuthorizationContext(auth), _collections)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task ListsTheCallersCollectionsWithJellyfinIds()
    {
        var matrix = Guid.NewGuid();
        var first = Guid.NewGuid();
        var second = Guid.NewGuid();
        var created = new DateTime(2026, 5, 1, 10, 0, 0, DateTimeKind.Utc);
        _collections.Result =
        [
            new CollectionInfo(matrix, "Matrix - Collezione", "matrix - collezione", "tag1", created, [first, second]),
        ];

        var entry = Assert.Single((await Controller().GetCollections()).Value!.Collections);
        // Gli id come li dà Jellyfin all'app: 32 cifre esadecimali, senza trattini.
        Assert.Equal(matrix.ToString("N"), entry.Id);
        Assert.Equal("Matrix - Collezione", entry.Name);
        Assert.Equal("matrix - collezione", entry.SortName);
        Assert.Equal("tag1", entry.PrimaryImageTag);
        Assert.Equal(created, entry.DateCreated);
        Assert.Equal(new[] { first.ToString("N"), second.ToString("N") }, entry.ItemIds);
        Assert.Equal(new[] { _mario.Id }, _collections.Callers);
    }

    [Fact]
    public async Task CollectionsWithoutVisibleTitlesAreLeftOut()
    {
        _collections.Result =
        [
            new CollectionInfo(Guid.NewGuid(), "Vuota", "vuota", null, DateTime.UtcNow, []),
            new CollectionInfo(Guid.NewGuid(), "Alien", "alien", null, DateTime.UtcNow, [Guid.NewGuid()]),
        ];

        var entry = Assert.Single((await Controller().GetCollections()).Value!.Collections);
        Assert.Equal("Alien", entry.Name);
        Assert.Null(entry.PrimaryImageTag);
    }

    [Fact]
    public async Task NoCollectionsIsAnEmptyList()
    {
        Assert.Empty((await Controller().GetCollections()).Value!.Collections);
    }

    [Fact]
    public void EveryAuthenticatedUserCanAsk()
    {
        // Le saghe non dipendono dal watch party: nessuna policy.
        var authorize = Assert.Single(typeof(CollectionsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(CollectionsController).GetMethod(nameof(CollectionsController.GetCollections))!
            .GetCustomAttributes<AuthorizeAttribute>());
    }

    private sealed class FakeCollections : ICollectionDirectory
    {
        public List<Guid> Callers { get; } = [];

        public IReadOnlyList<CollectionInfo> Result { get; set; } = [];

        public Task<IReadOnlyList<CollectionInfo>> GetCollectionsAsync(Guid userId)
        {
            Callers.Add(userId);
            return Task.FromResult(Result);
        }
    }
}
```

In `ProtocolJsonTests.cs`, aggiungi in fondo alla classe:

```csharp
    [Fact]
    public void CollectionsUseProtocolNames()
    {
        var created = new DateTime(2026, 5, 1, 10, 0, 0, DateTimeKind.Utc);
        Assert.Equal(
            "{\"Collections\":[{\"Id\":\"c1\",\"Name\":\"Matrix\",\"SortName\":\"matrix\",\"PrimaryImageTag\":null,"
            + "\"DateCreated\":\"2026-05-01T10:00:00Z\",\"ItemIds\":[\"m1\"]}]}",
            JsonSerializer.Serialize(new CollectionsResponse([new CollectionEntry("c1", "Matrix", "matrix", null, created, ["m1"])])));
    }
```

In `InfoControllerTests.cs` cambia le attese:

```csharp
    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = new InfoController(new FakeSeerrSettings { Url = string.Empty }).GetInfo().Value!;
        Assert.Equal("1.5.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends", "parties", "inbox", "queue", "collections" }, info.Features);
    }

    [Fact]
    public void RequestsAppearOnlyWithSeerrConfigured()
    {
        Assert.Equal(
            new[] { "friends", "parties", "inbox", "queue", "collections", "requests" },
            new InfoController(new FakeSeerrSettings()).GetInfo().Value!.Features);
        Assert.DoesNotContain(
            "requests", new InfoController(new FakeSeerrSettings { ApiKey = " " }).GetInfo().Value!.Features);
    }
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
Expected: errore di compilazione (`ICollectionDirectory`, `CollectionsController`, `CollectionsResponse` non esistono).

- [ ] **Step 3: interfaccia, DTO, controller, funzione, versione**

Crea `Hub/ICollectionDirectory.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Una collezione (BoxSet) come la vede un utente, con i titoli che può vedere (spec K §7.1).</summary>
public sealed record CollectionInfo(
    Guid Id,
    string Name,
    string SortName,
    string? PrimaryImageTag,
    DateTime DateCreated,
    IReadOnlyList<Guid> ItemIds);

/// <summary>Le collezioni di Jellyfin (adattatore di ICollectionManager, IUserManager e IImageProcessor).</summary>
public interface ICollectionDirectory
{
    /// <summary>
    /// Le collezioni che l'utente vede, ognuna con i titoli collegati che può
    /// vedere; vuoto se l'utente o la cartella delle collezioni non ci sono.
    /// </summary>
    Task<IReadOnlyList<CollectionInfo>> GetCollectionsAsync(Guid userId);
}
```

Crea `Protocol/CollectionDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Una collezione in GET Collections (spec K §7.1): gli id nel formato di Jellyfin ("N").</summary>
public sealed record CollectionEntry(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("SortName")] string SortName,
    [property: JsonPropertyName("PrimaryImageTag")] string? PrimaryImageTag,
    [property: JsonPropertyName("DateCreated")] DateTime DateCreated,
    [property: JsonPropertyName("ItemIds")] IReadOnlyList<string> ItemIds);

/// <summary>Risposta di GET Collections.</summary>
public sealed record CollectionsResponse(
    [property: JsonPropertyName("Collections")] IReadOnlyList<CollectionEntry> Collections);
```

Crea `Api/CollectionsController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le collezioni (BoxSet) con i loro titoli, per ogni utente autenticato
/// (spec K §7.1): Jellyfin non dice in quali collezioni sta un film, e le
/// collezioni stanno in una cartella che gli utenti non vedono. Una
/// collezione senza titoli visibili non c'è. Come il resto del plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class CollectionsController(
    IAuthorizationContext authorizationContext,
    ICollectionDirectory collections) : ControllerBase
{
    /// <summary>Le collezioni di chi chiama, con gli id dei titoli che vede.</summary>
    [HttpGet("Collections")]
    public async Task<ActionResult<CollectionsResponse>> GetCollections()
    {
        var caller = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        var found = await collections.GetCollectionsAsync(caller).ConfigureAwait(false);
        return new CollectionsResponse(found
            .Where(collection => collection.ItemIds.Count > 0)
            .Select(collection => new CollectionEntry(
                collection.Id.ToString("N"),
                collection.Name,
                collection.SortName,
                collection.PrimaryImageTag,
                collection.DateCreated,
                collection.ItemIds.Select(id => id.ToString("N")).ToList()))
            .ToList());
    }
}
```

In `Protocol/WatchPartyProtocol.cs` sostituisci il commento e la riga di `Features`:

```csharp
    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7, spec
    /// G §6.3, spec H §7, spec K §7.1). Il protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends", "parties", "inbox", "queue", "collections"];
```

Nel csproj: `<Version>1.4.0</Version>` → `<Version>1.5.0</Version>`.

- [ ] **Step 4: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
Expected: tutti verdi (383 + 5 nuovi = 388). Poi `dotnet build-server shutdown`.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): list the collections a user can see"
```

### Task 2: l'adattatore delle collezioni di Jellyfin

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinCollectionDirectory.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/CollectionDirectoryTests.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ServiceRegistrationTests.cs`

- [ ] **Step 1: i test**

Crea `CollectionDirectoryTests.cs`:

```csharp
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>
/// Solo i casi senza utente o senza cartella: le collezioni vere (BoxSet e i
/// loro figli collegati) hanno bisogno del server, e si provano lì (piano
/// 17a, Task 3 e Task 12).
/// </summary>
public class CollectionDirectoryTests
{
    [Fact]
    public async Task WithoutTheUserOrTheFolderThereAreNoCollections()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        // Come UserManager vero: con un id vuoto lancia.
        userStub.Handlers["GetUserById"] = args => (Guid)args[0]! == Guid.Empty
            ? throw new ArgumentException("userId vuoto")
            : (Guid)args[0]! == mario.Id ? mario : null;
        var (collections, collectionStub) = InterfaceStub<ICollectionManager>.Create();
        collectionStub.Handlers["GetCollectionsFolder"] = _ => Task.FromResult<Folder?>(null);
        var directory = new JellyfinCollectionDirectory(
            collections, users, InterfaceStub<IImageProcessor>.Create().Proxy);

        Assert.Empty(await directory.GetCollectionsAsync(Guid.Empty));
        Assert.Empty(await directory.GetCollectionsAsync(Guid.NewGuid()));
        Assert.DoesNotContain(collectionStub.Calls, c => c.Name == "GetCollectionsFolder");
        Assert.DoesNotContain(userStub.Calls, c => c.Name == "GetUserById" && (Guid)c.Args[0]! == Guid.Empty);

        Assert.Empty(await directory.GetCollectionsAsync(mario.Id));
        var folderCall = Assert.Single(collectionStub.Calls, c => c.Name == "GetCollectionsFolder");
        // Mai creare la cartella: senza collezioni non serve.
        Assert.False((bool)folderCall.Args[0]!);
    }
}
```

In `ServiceRegistrationTests.cs`:
- aggiungi gli `using`:

```csharp
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
```

- dopo `services.AddSingleton(InterfaceStub<ILibraryManager>.Create().Proxy);` aggiungi:

```csharp
        services.AddSingleton(InterfaceStub<ICollectionManager>.Create().Proxy);
        services.AddSingleton(InterfaceStub<IImageProcessor>.Create().Proxy);
```

- prima di `Assert.Equal(2, provider.GetServices<IHostedService>().Count());` aggiungi:

```csharp
        Assert.IsType<Server.JellyfinCollectionDirectory>(provider.GetRequiredService<ICollectionDirectory>());
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
Expected: errore di compilazione (`JellyfinCollectionDirectory` non esiste).

- [ ] **Step 3: l'adattatore e la registrazione**

Crea `Server/JellyfinCollectionDirectory.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Collections;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Le collezioni di Jellyfin (spec K §7.1): quelle della cartella delle
/// collezioni che l'utente vede, ognuna con i titoli collegati
/// (LinkedChildren) che l'utente può vedere. È la stessa chiamata che
/// Jellyfin fa per GET /Items?parentId=…: GetChildren(user, true, …)
/// filtra per librerie e controllo parentale.
/// </summary>
public sealed class JellyfinCollectionDirectory(
    ICollectionManager collectionManager,
    IUserManager userManager,
    IImageProcessor imageProcessor) : ICollectionDirectory
{
    public async Task<IReadOnlyList<CollectionInfo>> GetCollectionsAsync(Guid userId)
    {
        // Con un id vuoto UserManager lancia: l'utente non c'è e basta.
        var user = userId == Guid.Empty ? null : userManager.GetUserById(userId);
        if (user is null)
        {
            return [];
        }

        // Senza collezioni la cartella non c'è, e non va creata.
        var folder = await collectionManager.GetCollectionsFolder(false).ConfigureAwait(false);
        if (folder is null)
        {
            return [];
        }

        return folder.GetChildren(user, true, new InternalItemsQuery())
            .OfType<BoxSet>()
            .Select(boxSet => new CollectionInfo(
                boxSet.Id,
                boxSet.Name ?? string.Empty,
                boxSet.SortName ?? boxSet.Name ?? string.Empty,
                PrimaryTag(boxSet),
                boxSet.DateCreated,
                boxSet.GetChildren(user, true, new InternalItemsQuery()).Select(item => item.Id).ToList()))
            .ToList();
    }

    /// <summary>Il tag della locandina, come lo mette Jellyfin in ImageTags; null senza locandina.</summary>
    private string? PrimaryTag(BoxSet boxSet)
    {
        var image = boxSet.GetImageInfo(ImageType.Primary, 0);
        return image is null ? null : imageProcessor.GetImageCacheTag(boxSet, image);
    }
}
```

In `PluginServiceRegistrator.cs`, dopo `serviceCollection.AddSingleton<ILibraryAccess, JellyfinLibraryAccess>();`:

```csharp
        serviceCollection.AddSingleton<ICollectionDirectory, JellyfinCollectionDirectory>();
```

- [ ] **Step 4: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
Expected: tutti verdi (389). Poi `dotnet build-server shutdown`.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): read collections and their titles from Jellyfin"
```

## Gruppo B — STOP

### Task 3: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo A si ferma qui. L'orchestratore:

1. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato (lo script chiama `dotnet`), `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.5.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.5.0.0/`.
2. **Server** (`ssh ultra`; vedi la memoria `ultra-ssh` per le virgolette con `scp` e per gli script):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave "Wonderflix", o il log), come per le release passate; se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - sposta la cartella del Catalogo `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.4.0.0` in `~/wfwp-backup/1.4.0.0-catalogo`;
   - `scp -r "<cartella 1.5.0.0>" ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.5.0.0"` e nessun errore del plugin. L'avvio può durare minuti (il disco condiviso è lento).
3. **Controllo** con la chiave "Wonderflix" (base `http://127.0.0.1:17502/jellyfin`):
   - `GET /WonderFlixWatchParty/Info` ha `collections`;
   - `GET /WonderFlixWatchParty/Collections` risponde 200. Con una chiave API non c'è un utente, quindi la risposta è `{"Collections":[]}`.

   Le collezioni vere, viste da un utente, si controllano nella prova a mano (Task 12).

## Gruppo C — app, dati

### Task 4: i testi

**Files:**
- Modify: `l10n/app_it.arb`
- Modify: `l10n/app_en.arb`
- Create: `test/app/l10n_plan17a_test.dart`

- [ ] **Step 1: il test**

Crea `test/app/l10n_plan17a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 17a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.collectionsTab, 'Saghe');
    expect(it.collectionsCount(1), '1 saga');
    expect(it.collectionsCount(101), '101 saghe');
    expect(it.collectionFilmCount(1), '1 film');
    expect(it.collectionFilmCount(3), '3 film');
    expect(it.collectionWatched(1), '1 visto');
    expect(it.collectionWatched(0), '0 visti');
    expect(it.collectionPartOf('Matrix - Collezione'), 'Fa parte di: Matrix - Collezione');
    expect(it.collectionPlay('Matrix'), 'Riproduci "Matrix"');
    expect(it.collectionResume('Matrix'), 'Riprendi "Matrix"');
    expect(en.collectionsTab, 'Collections');
    expect(en.collectionsCount(2), '2 collections');
    expect(en.collectionFilmCount(1), '1 movie');
    expect(en.collectionPartOf('Alien'), 'Part of: Alien');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.collectionThisMovie,
        l.collectionsSearchHint,
        l.collectionsSortName,
        l.collectionsSortSize,
        l.collectionsEmpty,
        l.collectionsNoMatch,
      ], everyElement(isNotEmpty));
    }
  });
}
```

- [ ] **Step 2: il test non compila**

Run: `flutter test test/app/l10n_plan17a_test.dart`
Expected: errore di compilazione (`collectionsTab` non esiste).

- [ ] **Step 3: le chiavi**

In `l10n/app_it.arb`, in fondo (aggiungi la virgola alla riga di `adminSeerrNotConfigured`):

```json
  "collectionsTab": "Saghe",
  "collectionsCount": "{count, plural, =1{1 saga} other{{count} saghe}}",
  "@collectionsCount": {"placeholders": {"count": {"type": "int"}}},
  "collectionFilmCount": "{count, plural, =1{1 film} other{{count} film}}",
  "@collectionFilmCount": {"placeholders": {"count": {"type": "int"}}},
  "collectionWatched": "{count, plural, =1{1 visto} other{{count} visti}}",
  "@collectionWatched": {"placeholders": {"count": {"type": "int"}}},
  "collectionPartOf": "Fa parte di: {name}",
  "@collectionPartOf": {"placeholders": {"name": {"type": "String"}}},
  "collectionThisMovie": "Questo film",
  "collectionPlay": "Riproduci \"{title}\"",
  "@collectionPlay": {"placeholders": {"title": {"type": "String"}}},
  "collectionResume": "Riprendi \"{title}\"",
  "@collectionResume": {"placeholders": {"title": {"type": "String"}}},
  "collectionsSearchHint": "Cerca una saga",
  "collectionsSortName": "Nome",
  "collectionsSortSize": "Numero di film",
  "collectionsEmpty": "Nessuna saga",
  "collectionsNoMatch": "Nessuna saga con questo nome"
```

In `l10n/app_en.arb`, in fondo (aggiungi la virgola alla riga prima):

```json
  "collectionsTab": "Collections",
  "collectionsCount": "{count, plural, =1{1 collection} other{{count} collections}}",
  "collectionFilmCount": "{count, plural, =1{1 movie} other{{count} movies}}",
  "collectionWatched": "{count, plural, other{{count} watched}}",
  "collectionPartOf": "Part of: {name}",
  "collectionThisMovie": "This movie",
  "collectionPlay": "Play \"{title}\"",
  "collectionResume": "Resume \"{title}\"",
  "collectionsSearchHint": "Search a collection",
  "collectionsSortName": "Name",
  "collectionsSortSize": "Number of movies",
  "collectionsEmpty": "No collections",
  "collectionsNoMatch": "No collection with this name"
```

Run: `flutter gen-l10n`

- [ ] **Step 4: il test passa**

Run: `flutter test test/app/l10n_plan17a_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add l10n test/app/l10n_plan17a_test.dart
git commit -m "feat(app): add the texts for sagas"
```

### Task 5: modelli e API

**Files:**
- Modify: `lib/core/jellyfin/item_models.dart`
- Modify: `lib/app/navigation.dart`
- Modify: `lib/core/social/social_models.dart`
- Modify: `lib/features/social/social_providers.dart`
- Create: `lib/core/social/collections_models.dart`
- Create: `lib/core/social/collections_api.dart`
- Modify: `lib/core/jellyfin/image_urls.dart`
- Modify: `lib/core/jellyfin/library_api.dart`
- Modify: `test/support/library_fakes.dart`
- Modify: `test/app/navigation_test.dart`
- Modify: `test/core/jellyfin/image_urls_test.dart`
- Modify: `test/core/jellyfin/library_api_test.dart`
- Modify: `test/features/social/social_providers_test.dart`
- Create: `test/core/social/collections_api_test.dart`

- [ ] **Step 1: i test**

In `test/app/navigation_test.dart`, dentro `test('itemRoute', …)`, in fondo:

```dart
    expect(ItemKind.parse('BoxSet'), ItemKind.boxSet);
    expect(itemRoute(testItem(id: 'c1', kind: ItemKind.boxSet)), '/collection/c1');
```

In `test/core/jellyfin/image_urls_test.dart`, in fondo a `main`:

```dart
  test('locandina da id e tag (una saga, spec K §8.4)', () {
    final image = urls.primaryWithTag('c1', 't1');
    expect(image.url,
        'https://media.example.com/jf/Items/c1/Images/Primary?tag=t1&maxWidth=400&quality=90');
    expect(urls.primaryWithTag('c1', 't1', maxWidth: 300).url, contains('maxWidth=300'));
  });
```

In `test/core/jellyfin/library_api_test.dart`, dopo il test `itemsByIds: con una lista vuota…`:

```dart
  test('collectionItems: i titoli della saga in ordine di uscita (spec K §8.1)',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['m1', 'm2']));
    final items = await api.collectionItems('u1', 'c1');
    expect(last().path, '/Items');
    expect(last().query['userId'], 'u1');
    expect(last().query['parentId'], 'c1');
    expect(last().query['sortBy'], 'PremiereDate,ProductionYear,SortName');
    expect(last().query['sortOrder'], 'Ascending');
    // I titoli sono collegati alla collezione, non suoi discendenti.
    expect(last().query.containsKey('recursive'), isFalse);
    expect(last().query['enableImageTypes'], 'Primary,Backdrop,Thumb,Logo');
    expect(items.map((item) => item.id), ['m1', 'm2']);
  });
```

In `test/features/social/social_providers_test.dart`, dopo il test `Info con le richieste…`:

```dart
  test('Info con le saghe: funzione collections, anche senza watch party',
      () async {
    api.install(features: const {PluginFeatures.collections});
    final c = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(collections: true));
  });
```

Crea `test/core/social/collections_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/collections_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late CollectionsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'Collections': []}));
    api = CollectionsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('legge le saghe con i loro titoli', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Collections': [
            {
              'Id': 'c1',
              'Name': 'Matrix - Collezione',
              'SortName': 'matrix - collezione',
              'PrimaryImageTag': 't1',
              'DateCreated': '2026-05-01T10:00:00Z',
              'ItemIds': ['m1', 'm2', 'm3'],
            },
          ],
        });
    final saga = (await api.collections()).single;
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Collections');
    expect(saga.id, 'c1');
    expect(saga.name, 'Matrix - Collezione');
    expect(saga.sortName, 'matrix - collezione');
    expect(saga.primaryImageTag, 't1');
    expect(saga.dateCreated, DateTime.utc(2026, 5, 1, 10));
    expect(saga.itemIds, ['m1', 'm2', 'm3']);
    expect(saga.size, 3);
  });

  test('letture tolleranti: senza Id la voce si scarta, il resto ha dei valori di partenza',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Collections': [
            {'Name': 'Senza id', 'ItemIds': ['m1']},
            'non un oggetto',
            {'Id': 'c2', 'Name': 'Alien', 'PrimaryImageTag': null, 'ItemIds': 5},
          ],
        });
    final saga = (await api.collections()).single;
    expect(saga.id, 'c2');
    expect(saga.sortName, 'alien');
    expect(saga.primaryImageTag, isNull);
    expect(saga.dateCreated, isNull);
    expect(saga.itemIds, isEmpty);
  });

  test('corpo di forma inattesa: errore del server', () async {
    adapter.handler = (_) => const FakeResponse(200, ['no']);
    await expectLater(api.collections(), throwsA(isA<ServerErrorException>()));
    adapter.handler = (_) => const FakeResponse(200, {'Collections': 'no'});
    await expectLater(api.collections(), throwsA(isA<ServerErrorException>()));
  });

  test('plugin senza l\'endpoint: 404', () async {
    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(api.collections(), throwsA(isA<NotFoundException>()));
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/app/navigation_test.dart test/core/jellyfin/image_urls_test.dart test/core/jellyfin/library_api_test.dart test/features/social/social_providers_test.dart test/core/social/collections_api_test.dart`
Expected: errori di compilazione (`ItemKind.boxSet`, `primaryWithTag`, `collectionItems`, `PluginFeatures.collections`, `CollectionsApi`).

- [ ] **Step 3: il codice**

In `lib/core/jellyfin/item_models.dart`, nell'enum `ItemKind`, tra `person` e `other`:

```dart
  person('Person'),

  /// Una collezione (saga) di Jellyfin (spec K §8.1).
  boxSet('BoxSet'),
  other('');
```

In `lib/app/navigation.dart`, nello `switch` di `itemRoute`, prima di `default:`:

```dart
    case ItemKind.boxSet:
      return '/collection/${item.id}';
```

e dopo `openItemById`:

```dart
/// Apre la pagina della saga [collectionId] (spec K §8.2).
void openCollection(BuildContext context, String collectionId) =>
    unawaited(context.push('/collection/$collectionId'));
```

In `lib/core/social/social_models.dart`, in `PluginFeatures`, dopo `requests`:

```dart

  /// Le saghe, cioè le collezioni di Jellyfin (spec K §7.1).
  static const collections = 'collections';
```

In `lib/features/social/social_providers.dart`, in `SocialFeatures`:
- il costruttore:

```dart
  const SocialFeatures({
    this.friends = false,
    this.parties = false,
    this.inbox = false,
    this.requests = false,
    this.collections = false,
    this.known = true,
  });
```

- il campo, dopo `requests`:

```dart
  /// Le saghe (spec K §8.1): non dipendono dai watch party.
  final bool collections;
```

- `==`, `hashCode` e `toString`:

```dart
  @override
  bool operator ==(Object other) =>
      other is SocialFeatures &&
      other.friends == friends &&
      other.parties == parties &&
      other.inbox == inbox &&
      other.requests == requests &&
      other.collections == collections &&
      other.known == known;

  @override
  int get hashCode =>
      Object.hash(friends, parties, inbox, requests, collections, known);

  @override
  String toString() => 'SocialFeatures(friends: $friends, parties: $parties, '
      'inbox: $inbox, requests: $requests, collections: $collections, '
      'known: $known)';
```

- in `SocialAvailability.refresh`, nell'`_apply(SocialFeatures(…))`, dopo `requests:`:

```dart
        collections: info.features.contains(PluginFeatures.collections),
```

Crea `lib/core/social/collections_models.dart`:

```dart
import '../jellyfin/json_fields.dart';

/// Una saga (collezione di Jellyfin) come la dà il plugin (spec K §7.1).
class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.name,
    required this.sortName,
    this.primaryImageTag,
    this.dateCreated,
    this.itemIds = const [],
  });

  /// `null` senza `Id`: la voce si scarta. Gli altri campi mancanti hanno un
  /// valore di partenza (nome vuoto, `SortName` dal nome in minuscolo).
  static CollectionSummary? fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'Id');
    if (id == null) return null;
    final name = jsonString(json, 'Name') ?? '';
    return CollectionSummary(
      id: id,
      name: name,
      sortName: jsonString(json, 'SortName') ?? name.toLowerCase(),
      primaryImageTag: jsonString(json, 'PrimaryImageTag'),
      dateCreated: jsonDate(json, 'DateCreated'),
      itemIds: switch (json['ItemIds']) {
        final List<dynamic> ids => jsonStrings(ids),
        _ => const [],
      },
    );
  }

  final String id;
  final String name;

  /// Chiave d'ordinamento di Jellyfin.
  final String sortName;

  /// Tag della locandina; `null` senza locandina.
  final String? primaryImageTag;

  /// Aggiunta alla libreria.
  final DateTime? dateCreated;

  /// I titoli della saga che l'utente vede.
  final List<String> itemIds;

  /// Quanti titoli ha la saga.
  int get size => itemIds.length;
}
```

Crea `lib/core/social/collections_api.dart`:

```dart
import '../jellyfin/json_fields.dart';
import '../jellyfin/jellyfin_http.dart';
import 'collections_models.dart';

/// L'elenco delle saghe del plugin (spec K §7.1). Gli errori sono
/// `ApiException`; un corpo di forma inattesa è `ServerErrorException`.
class CollectionsApi {
  CollectionsApi(this._http);

  final JellyfinHttp _http;

  static const _path = '/WonderFlixWatchParty/Collections';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  Future<List<CollectionSummary>> collections() async {
    final json = asJsonMap(await _http.get(_path, quietStatuses: _quiet));
    return jsonList(json['Collections'], CollectionSummary.fromJson);
  }
}
```

In `lib/core/jellyfin/image_urls.dart`, dopo `primaryOf`:

```dart
  /// Locandina di un elemento di cui si conoscono id e tag (una saga, spec K
  /// §8.4): con il tag l'immagine si rinnova quando cambia.
  ImageRef primaryWithTag(String itemId, String tag, {int maxWidth = 400}) =>
      ImageRef(
          '$_base/Items/$itemId/Images/Primary?tag=$tag&maxWidth=$maxWidth&quality=90');
```

In `lib/core/jellyfin/library_api.dart`, dopo `itemsByIds`:

```dart
  /// I titoli della saga [collectionId] che l'utente vede, in ordine di
  /// uscita (spec K §8.1). Senza `recursive`: i titoli sono collegati alla
  /// collezione, non suoi discendenti.
  Future<List<JellyfinItem>> collectionItems(
          String userId, String collectionId) async =>
      _list(await _http.get('/Items', query: {
        ...cardImageParams,
        'userId': userId,
        'parentId': collectionId,
        'sortBy': 'PremiereDate,ProductionYear,SortName',
        'sortOrder': 'Ascending',
      }));
```

In `test/support/library_fakes.dart`, in `FakeLibraryApi`:
- i campi, dopo `itemsByIdsCalls`:

```dart
  /// Titoli di ogni saga, in ordine (per [collectionItems]).
  final Map<String, List<JellyfinItem>> itemsByCollection = {};

  /// Saghe chieste a [collectionItems].
  final collectionItemsCalls = <String>[];
```

- il metodo, dopo `itemsByIds`:

```dart
  @override
  Future<List<JellyfinItem>> collectionItems(
      String userId, String collectionId) {
    collectionItemsCalls.add(collectionId);
    return _answer(() => itemsByCollection[collectionId] ?? const []);
  }
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/app/navigation_test.dart test/core/jellyfin/image_urls_test.dart test/core/jellyfin/library_api_test.dart test/features/social/social_providers_test.dart test/core/social/collections_api_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): read sagas from the plugin and the titles of a saga"
```

### Task 6: logica e provider delle saghe

**Files:**
- Create: `lib/features/collections/collections_logic.dart`
- Create: `lib/features/collections/collections_providers.dart`
- Create: `test/support/collections_fakes.dart`
- Create: `test/features/collections/collections_logic_test.dart`
- Create: `test/features/collections/collections_providers_test.dart`

- [ ] **Step 1: il supporto ai test e i test**

Crea `test/support/collections_fakes.dart`:

```dart
import 'package:wonderflix/core/social/collections_api.dart';
import 'package:wonderflix/core/social/collections_models.dart';

/// `CollectionsApi` in memoria: elenco configurabile e chiamate contate.
class FakeCollectionsApi implements CollectionsApi {
  List<CollectionSummary> collectionsList = [];

  /// Se valorizzato, ogni chiamata lancia questo errore.
  Object? error;

  int calls = 0;

  @override
  Future<List<CollectionSummary>> collections() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return collectionsList;
  }
}

/// Una saga di prova: `SortName` è il nome in minuscolo.
CollectionSummary testCollection({
  String id = 'c1',
  String name = 'Matrix - Collezione',
  List<String> itemIds = const ['m1', 'm2'],
  String? tag = 'tag-c1',
  DateTime? dateCreated,
}) =>
    CollectionSummary(
      id: id,
      name: name,
      sortName: name.toLowerCase(),
      primaryImageTag: tag,
      dateCreated: dateCreated,
      itemIds: itemIds,
    );
```

Crea `test/features/collections/collections_logic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/collections/collections_logic.dart';

import '../../support/collections_fakes.dart';
import '../../support/library_fakes.dart';

void main() {
  test('foldForSearch: minuscolo, senza accenti e senza spazi ai lati', () {
    expect(foldForSearch('  Mátrix ÉÈ '), 'matrix ee');
    expect(foldForSearch('Amélie, Pinocchio, Ñandú'), 'amelie, pinocchio, nandu');
  });

  test('collectionKey: senza trattini e in minuscolo', () {
    expect(collectionKey('0088B3BF-1B19-EF2D-962F-A145C461538A'),
        '0088b3bf1b19ef2d962fa145c461538a');
  });

  test('indexCollections: dalla saga più piccola, a parità per nome, senza doppioni',
      () {
    final marvel = testCollection(id: 'c1', name: 'Marvel Universe', itemIds: ['m1', 'm2', 'm3']);
    final ironMan = testCollection(id: 'c2', name: 'Iron Man - Collezione', itemIds: ['M1', 'm2']);
    final avengers = testCollection(id: 'c3', name: 'Avengers - Collezione', itemIds: ['m1', 'm1', 'm4']);
    final index = indexCollections([marvel, ironMan, avengers]);
    expect(index['m1']!.map((c) => c.id), ['c3', 'c2', 'c1']);
    expect(index['m2']!.map((c) => c.id), ['c2', 'c1']);
    expect(index['m4']!.map((c) => c.id), ['c3']);
    expect(index['m9'], isNull);
  });

  test('filterCollections: il nome contiene il testo, senza maiuscole e accenti', () {
    final sagas = [
      testCollection(id: 'c1', name: 'Mátrix - Collezione'),
      testCollection(id: 'c2', name: 'Alien - Collezione'),
    ];
    expect(filterCollections(sagas, 'MATRIX').map((c) => c.id), ['c1']);
    expect(filterCollections(sagas, ' ').map((c) => c.id), ['c1', 'c2']);
    expect(filterCollections(sagas, 'zzz'), isEmpty);
  });

  test('matchCollections: in ordine di nome, al massimo [max], niente con un testo vuoto',
      () {
    final sagas = [
      for (final name in ['Star Wars', 'Star Trek', 'Stargate', 'Alien'])
        testCollection(id: name, name: name),
    ];
    expect(matchCollections(sagas, 'star', max: 2).map((c) => c.name),
        ['Star Trek', 'Star Wars']);
    expect(matchCollections(sagas, '  ', max: 12), isEmpty);
  });

  test('sortCollections: per nome, per numero di film, per data di aggiunta', () {
    final alien = testCollection(
        id: 'a', name: 'Alien', itemIds: ['1', '2'], dateCreated: DateTime.utc(2026, 1, 1));
    final matrix = testCollection(
        id: 'm', name: 'Matrix', itemIds: ['1', '2', '3'], dateCreated: DateTime.utc(2026, 6, 1));
    final dune = testCollection(id: 'd', name: 'Dune', itemIds: ['1', '2']);
    final sagas = [matrix, dune, alien];
    expect(sortCollections(sagas, CollectionSort.name).map((c) => c.id), ['a', 'd', 'm']);
    expect(sortCollections(sagas, CollectionSort.size).map((c) => c.id), ['m', 'a', 'd']);
    // Senza data in fondo.
    expect(sortCollections(sagas, CollectionSort.dateAdded).map((c) => c.id), ['m', 'a', 'd']);
    // L'elenco di partenza non cambia.
    expect(sagas.map((c) => c.id), ['m', 'd', 'a']);
  });

  test('sagaTarget e watchedCount', () {
    UserItemData data(JellyfinItem item) => item.userData;
    final first = testItem(id: 'm1', played: true);
    final second = testItem(id: 'm2', positionTicks: 10);
    final third = testItem(id: 'm3');
    expect(sagaTarget([first, second, third], data)!.id, 'm2');
    expect(sagaTarget([first, testItem(id: 'm4', played: true)], data)!.id, 'm1');
    expect(sagaTarget(const [], data), isNull);
    expect(watchedCount([first, second, third], data), 1);
  });
}
```

Crea `test/features/collections/collections_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeCollectionsApi collections;
  late FakeLibraryApi library;
  late FakeSocialAvailability availability;

  setUp(() {
    collections = FakeCollectionsApi()
      ..collectionsList = [testCollection(id: 'c1', itemIds: ['m1', 'm2'])];
    library = FakeLibraryApi();
    availability =
        FakeSocialAvailability(const SocialFeatures(collections: true));
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: [
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          socialAvailabilityProvider.overrideWith(() => availability),
          collectionsApiProvider.overrideWithValue(collections),
          libraryApiProvider.overrideWithValue(library),
        ],
        retry: (_, _) => null,
      );

  test('con la funzione: legge le saghe e costruisce l\'indice', () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), hasLength(1));
    expect(c.read(collectionsByItemProvider)['m1']!.single.id, 'c1');
    expect(collections.calls, 1);
  });

  test('senza la funzione: vuoto e nessuna chiamata', () async {
    availability = FakeSocialAvailability(SocialFeatures.none);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), isEmpty);
    expect(c.read(collectionsByItemProvider), isEmpty);
    expect(collections.calls, 0);
  });

  test('la funzione che arriva dopo fa leggere le saghe', () async {
    availability = FakeSocialAvailability(SocialFeatures.unknown);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    expect(await c.read(collectionsProvider.future), isEmpty);
    availability.set(const SocialFeatures(collections: true));
    expect(await c.read(collectionsProvider.future), hasLength(1));
  });

  test('una libreria cambiata fa rileggere le saghe', () async {
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    await c.read(collectionsProvider.future);
    c.read(libraryRevisionProvider.notifier).bump();
    await c.read(collectionsProvider.future);
    expect(collections.calls, 2);
  });

  test('errore: l\'indice resta vuoto', () async {
    collections.error = const ServerErrorException(null);
    final c = container();
    c.listen(collectionsProvider, (_, _) {});
    await expectLater(c.read(collectionsProvider.future),
        throwsA(isA<ServerErrorException>()));
    expect(c.read(collectionsByItemProvider), isEmpty);
  });

  test('i titoli di una saga', () async {
    library.itemsByCollection['c1'] = [testItem(id: 'm1'), testItem(id: 'm2')];
    final c = container();
    c.listen(collectionItemsProvider('c1'), (_, _) {});
    final items = await c.read(collectionItemsProvider('c1').future);
    expect(items.map((item) => item.id), ['m1', 'm2']);
    expect(library.collectionItemsCalls, ['c1']);
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/collections`
Expected: errori di compilazione (`collections_logic.dart` e `collections_providers.dart` non esistono).

- [ ] **Step 3: la logica e i provider**

Crea `lib/features/collections/collections_logic.dart`:

```dart
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';

/// Ordinamenti della vista "Saghe" (spec K §8.4).
enum CollectionSort {
  /// Per `SortName`.
  name,

  /// Dalla saga con più film; a parità per nome.
  size,

  /// Dalla più recente; senza data in fondo, a parità per nome.
  dateAdded,
}

/// Lettere accentate e la loro forma semplice, per la ricerca.
const _plainLetters = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ç': 'c', 'ñ': 'n',
};

/// Testo per i confronti della ricerca: minuscolo, senza accenti e senza
/// spazi ai lati (spec K §8.5).
String foldForSearch(String text) {
  final buffer = StringBuffer();
  for (final char in text.trim().toLowerCase().split('')) {
    buffer.write(_plainLetters[char] ?? char);
  }
  return buffer.toString();
}

/// Id di Jellyfin confrontabili: senza trattini e in minuscolo.
String collectionKey(String id) => id.replaceAll('-', '').toLowerCase();

int _byName(CollectionSummary a, CollectionSummary b) =>
    a.sortName.compareTo(b.sortName);

/// Le saghe di ogni titolo, per [collectionKey] dell'id: dalla più piccola
/// alla più grande, a parità per nome (spec K §8.3).
Map<String, List<CollectionSummary>> indexCollections(
    List<CollectionSummary> collections) {
  final index = <String, List<CollectionSummary>>{};
  for (final collection in collections) {
    for (final id in collection.itemIds) {
      final sagas = index.putIfAbsent(collectionKey(id), () => []);
      if (sagas.every((saga) => saga.id != collection.id)) sagas.add(collection);
    }
  }
  for (final sagas in index.values) {
    sagas.sort((a, b) {
      final bySize = a.size.compareTo(b.size);
      return bySize != 0 ? bySize : _byName(a, b);
    });
  }
  return index;
}

/// Le saghe il cui nome contiene [query] (confronto con [foldForSearch]);
/// tutte, con [query] vuota.
List<CollectionSummary> filterCollections(
    List<CollectionSummary> collections, String query) {
  final folded = foldForSearch(query);
  if (folded.isEmpty) return collections;
  return [
    for (final collection in collections)
      if (foldForSearch(collection.name).contains(folded)) collection,
  ];
}

/// Le saghe per la ricerca: al massimo [max], in ordine di nome; nessuna
/// con un testo vuoto (spec K §8.5).
List<CollectionSummary> matchCollections(
    List<CollectionSummary> collections, String term,
    {required int max}) {
  if (foldForSearch(term).isEmpty) return const [];
  final found = filterCollections(collections, term).toList()..sort(_byName);
  return found.take(max).toList();
}

/// [collections] in un elenco nuovo, ordinato per [sort].
List<CollectionSummary> sortCollections(
    List<CollectionSummary> collections, CollectionSort sort) {
  final int Function(CollectionSummary, CollectionSummary) compare =
      switch (sort) {
    CollectionSort.name => _byName,
    CollectionSort.size => (a, b) {
        final bySize = b.size.compareTo(a.size);
        return bySize != 0 ? bySize : _byName(a, b);
      },
    CollectionSort.dateAdded => (a, b) {
        final first = a.dateCreated;
        final second = b.dateCreated;
        if (first != null && second != null && first != second) {
          return second.compareTo(first);
        }
        if (first == null && second != null) return 1;
        if (first != null && second == null) return -1;
        return _byName(a, b);
      },
  };
  return collections.toList()..sort(compare);
}

/// Il titolo da proporre nella pagina di una saga (spec K §8.2): il primo,
/// in ordine di uscita, non ancora visto; se sono tutti visti, il primo.
/// `null` senza titoli.
JellyfinItem? sagaTarget(List<JellyfinItem> items,
    UserItemData Function(JellyfinItem item) userDataOf) {
  for (final item in items) {
    if (!userDataOf(item).played) return item;
  }
  return items.isEmpty ? null : items.first;
}

/// Quanti titoli di [items] sono visti.
int watchedCount(List<JellyfinItem> items,
        UserItemData Function(JellyfinItem item) userDataOf) =>
    items.where((item) => userDataOf(item).played).length;
```

Crea `lib/features/collections/collections_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_api.dart';
import '../../core/social/collections_models.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import 'collections_logic.dart';

final _log = Logger('collections');

final collectionsApiProvider = Provider<CollectionsApi>(
    (ref) => CollectionsApi(ref.watch(jellyfinHttpProvider)));

/// Le saghe dell'utente (spec K §8.1): solo con la funzione `collections`
/// del plugin; senza, vuoto e nessuna chiamata. Si rilegge quando cambia la
/// libreria o l'utente. Resta in cache (non `autoDispose`): la usano la
/// scheda del film, il catalogo e la ricerca.
final collectionsProvider =
    FutureProvider<List<CollectionSummary>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final available = ref.watch(
      socialAvailabilityProvider.select((features) => features.collections));
  if (!available) return const [];
  ref.watch(currentUserIdProvider);
  final api = ref.watch(collectionsApiProvider);
  try {
    return await api.collections();
  } on Object catch (error) {
    // Solo il tipo: il messaggio può citare la risposta.
    _log.warning('saghe non lette: ${error.runtimeType}');
    rethrow;
  }
});

/// Le saghe di ogni titolo, per `collectionKey` dell'id (spec K §8.3);
/// vuoto finché l'elenco non c'è o se non si è potuto leggere.
final collectionsByItemProvider =
    Provider<Map<String, List<CollectionSummary>>>((ref) =>
        indexCollections(ref.watch(collectionsProvider).value ?? const []));

/// I titoli di una saga che l'utente vede, in ordine di uscita (spec K §8.1).
final collectionItemsProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, String>((ref, collectionId) {
  ref.watch(libraryRevisionProvider);
  ref.watch(userDataRevisionProvider);
  return ref
      .watch(libraryApiProvider)
      .collectionItems(ref.watch(currentUserIdProvider), collectionId);
});
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/collections`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): cache sagas and index them by title"
```

## Gruppo D — app, scheda e pagina della saga

### Task 7: righe "Fa parte di"

**Files:**
- Modify: `lib/ui/poster_card.dart`
- Modify: `lib/ui/media_row.dart`
- Create: `lib/features/collections/collection_rows.dart`
- Modify: `lib/features/detail/movie_detail_view.dart`
- Modify: `test/support/pump_app.dart`
- Create: `test/features/collections/collection_rows_test.dart`
- Modify: `test/features/detail/movie_detail_test.dart`

- [ ] **Step 1: il supporto ai test e i test**

In `test/support/pump_app.dart`:
- aggiungi l'import `import 'package:go_router/go_router.dart';`;
- in fondo al file:

```dart
/// Come [pumpApp], ma con un [router]: per i test che navigano.
Future<void> pumpAppRouter(
  WidgetTester tester,
  GoRouter router, {
  List<Override> overrides = const [],
  Size surfaceSize = const Size(1440, 900),
}) async {
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      serverEventsBindingProvider.overrideWithValue(null),
      imageBuilderProvider.overrideWithValue(
          (image, fit) => const ColoredBox(color: Color(0xFF333333))),
      carouselAutoplayProvider.overrideWithValue(false),
      ...overrides,
    ],
    retry: (_, _) => null,
    child: MaterialApp.router(
      routerConfig: router,
      theme: buildWonderflixTheme(),
      locale: const Locale('it'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => WfMotionScope(
          motion: const WfMotion(MotionLevel.reduced), child: child!),
    ),
  ));
  await tester.pump();
}
```

Crea `test/features/collections/collection_rows_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collection_rows.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeCollectionsApi collections;

  setUp(() {
    library = FakeLibraryApi()
      ..itemsByCollection['c1'] = [
        testItem(id: 'm1', name: 'Matrix'),
        testItem(id: 'm2', name: 'Matrix Reloaded'),
      ]
      ..itemsByCollection['c2'] = [
        testItem(id: 'm1', name: 'Matrix'),
        testItem(id: 'm9', name: 'Animatrix'),
        testItem(id: 'm2', name: 'Matrix Reloaded'),
      ];
    collections = FakeCollectionsApi()
      ..collectionsList = [
        testCollection(id: 'c2', name: 'Universo Matrix', itemIds: ['m1', 'm9', 'm2']),
        testCollection(id: 'c1', name: 'Matrix - Collezione', itemIds: ['m1', 'm2']),
        testCollection(id: 'c3', name: 'Solo Matrix', itemIds: ['m1']),
      ];
  });

  List<Override> overrides(
          {SocialFeatures features = const SocialFeatures(collections: true)}) =>
      [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialAvailabilityProvider
            .overrideWith(() => FakeSocialAvailability(features)),
        collectionsApiProvider.overrideWithValue(collections),
      ];

  const rows = Scaffold(
      body: SingleChildScrollView(child: CollectionRows(itemId: 'm1')));

  Future<void> pumpRows(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(collections: true)}) async {
    await pumpApp(tester, rows,
        overrides: overrides(features: features),
        surfaceSize: const Size(1440, 1400));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('una riga per saga con almeno 2 film, dalla più piccola',
      (tester) async {
    await pumpRows(tester);
    final small = find.text('Fa parte di: Matrix - Collezione');
    final big = find.text('Fa parte di: Universo Matrix');
    expect(small, findsOneWidget);
    expect(big, findsOneWidget);
    expect(tester.getTopLeft(small).dy, lessThan(tester.getTopLeft(big).dy));
    expect(find.text('Fa parte di: Solo Matrix'), findsNothing);
    expect(find.text('Animatrix'), findsOneWidget);
    // Il film aperto è segnato in tutte e due le righe.
    expect(find.text('Questo film'), findsNWidgets(2));
  });

  testWidgets('plugin senza saghe: nessuna riga e nessuna chiamata',
      (tester) async {
    await pumpRows(tester, features: SocialFeatures.none);
    expect(find.textContaining('Fa parte di'), findsNothing);
    expect(collections.calls, 0);
    expect(library.collectionItemsCalls, isEmpty);
  });

  testWidgets('il titolo della riga apre la pagina della saga', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => rows),
      GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              Scaffold(body: Text('saga ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(tester, router,
        overrides: overrides(), surfaceSize: const Size(1440, 1400));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Fa parte di: Matrix - Collezione'));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });
}
```

In `test/features/detail/movie_detail_test.dart`:
- aggiungi gli import:

```dart
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/social_fakes.dart';
```

- in fondo a `main`:

```dart
  testWidgets('la riga "Fa parte di" sta prima di "Simili" (spec K §8.3)',
      (tester) async {
    api.itemsByCollection['c1'] = [
      testItem(id: 'm1', name: 'Dune: Parte Due'),
      testItem(id: 'm3', name: 'Dune: Messia'),
    ];
    final collections = FakeCollectionsApi()
      ..collectionsList = [
        testCollection(id: 'c1', name: 'Dune - Collezione', itemIds: ['m1', 'm3']),
      ];
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        surfaceSize: const Size(1440, 2200),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          socialAvailabilityProvider.overrideWith(() =>
              FakeSocialAvailability(const SocialFeatures(collections: true))),
          collectionsApiProvider.overrideWithValue(collections),
        ]);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final saga = find.text('Fa parte di: Dune - Collezione');
    expect(saga, findsOneWidget);
    expect(find.text('Dune: Messia'), findsOneWidget);
    expect(tester.getTopLeft(saga).dy,
        lessThan(tester.getTopLeft(find.text('Simili')).dy));
  });
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/collections/collection_rows_test.dart test/features/detail/movie_detail_test.dart`
Expected: errori di compilazione (`collection_rows.dart` non esiste).

- [ ] **Step 3: card, riga, righe delle saghe, scheda**

In `lib/ui/poster_card.dart`:
- nel costruttore, dopo `this.width,`:

```dart
    this.markLabel,
```

- il campo, dopo `width`:

```dart

  /// Etichetta fissa sulla locandina, con il bordo oro sempre acceso: il
  /// titolo aperto nella riga della sua saga ("Questo film", spec K §8.3).
  final String? markLabel;
```

- in `build`, dopo `final heroSource = …;`:

```dart
    final mark = widget.markLabel;
```

- nel bordo dell'`AnimatedContainer`:

```dart
                    border: Border.all(
                        color: _hover || mark != null
                            ? WfColors.gold
                            : Colors.transparent,
                        width: 2),
```

- nello `Stack` della locandina, dopo il badge di visto e del conteggio:

```dart
                        if (mark != null)
                          Positioned(
                              top: 6, left: 6, child: _MarkChip(label: mark)),
```

- in fondo al file:

```dart
/// Etichetta oro in alto a sinistra della locandina.
class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: WfColors.gold, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: const TextStyle(
              color: WfColors.bg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
```

In `lib/ui/media_row.dart`:
- nel costruttore, dopo `this.animateEntrance = false,`:

```dart
    this.onTitleTap,
```

- il campo, dopo `animateEntrance`:

```dart

  /// Con [onTitleTap] il titolo è un link, con una freccia (spec K §8.3).
  final VoidCallback? onTitleTap;
```

- in `build`, sostituisci `Flexible(child: Text(widget.title, style: WfText.display(24))),` con:

```dart
                Flexible(child: _title()),
```

- nello state, dopo `_scroll`:

```dart
  Widget _title() {
    final title = Text(widget.title,
        overflow: TextOverflow.ellipsis, style: WfText.display(24));
    final onTap = widget.onTitleTap;
    if (onTap == null) return title;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('row-title-link'),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: title),
            const SizedBox(width: 8),
            const Icon(LucideIcons.arrowRight, size: 20, color: WfColors.gold),
          ],
        ),
      ),
    );
  }
```

Crea `lib/features/collections/collection_rows.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';

/// Righe "Fa parte di" della scheda di un film (spec K §8.3): una per ogni
/// saga del film con almeno [minSagaSize] titoli, dalla più piccola alla
/// più grande. Senza saghe non mostra nulla.
class CollectionRows extends ConsumerWidget {
  const CollectionRows({super.key, required this.itemId});

  final String itemId;

  /// Una saga con un titolo solo non ha altri titoli da proporre.
  static const minSagaSize = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sagas = [
      for (final saga in ref.watch(collectionsByItemProvider)[
              collectionKey(itemId)] ??
          const <CollectionSummary>[])
        if (saga.size >= minSagaSize) saga,
    ];
    if (sagas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final saga in sagas)
          _SagaRow(key: ValueKey(saga.id), saga: saga, itemId: itemId),
      ],
    );
  }
}

/// I titoli di una saga in ordine di uscita; finché carica, o se non si
/// leggono, la riga non c'è (come "Simili").
class _SagaRow extends ConsumerWidget {
  const _SagaRow({super.key, required this.saga, required this.itemId});

  final CollectionSummary saga;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(collectionItemsProvider(saga.id)).value ??
        const <JellyfinItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final current = collectionKey(itemId);
    return MediaRow(
      title: l.collectionPartOf(saga.name),
      onTitleTap: () => openCollection(context, saga.id),
      height: 300,
      itemCount: items.length,
      // Le card volano con la riga, come "Simili".
      animateEntrance: true,
      itemBuilder: (context, i) {
        final item = items[i];
        final isCurrent = collectionKey(item.id) == current;
        return PosterCard(
          item: item,
          width: 160,
          heroSource: 'saga.${saga.id}.$i',
          markLabel: isCurrent ? l.collectionThisMovie : null,
          // Il film aperto non si riapre.
          onTap: isCurrent ? () {} : null,
        );
      },
    );
  }
}
```

In `lib/features/detail/movie_detail_view.dart`:
- l'import `import '../collections/collection_rows.dart';`;
- nella `ListView`, al posto di `StaggerItem(index: 6, child: SimilarRow(itemId: item.id)),`:

```dart
          StaggerItem(index: 6, child: CollectionRows(itemId: item.id)),
          StaggerItem(index: 7, child: SimilarRow(itemId: item.id)),
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/collections/collection_rows_test.dart test/features/detail`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): show the sagas of a movie in its page"
```

### Task 8: pagina della saga

**Files:**
- Modify: `lib/features/detail/detail_header.dart`
- Create: `lib/features/collections/collection_screen.dart`
- Modify: `lib/app/router.dart`
- Create: `test/features/collections/collection_screen_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/collections/collection_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/collections/collection_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()
      ..itemsById['c1'] = testItem(
          id: 'c1',
          name: 'Matrix - Collezione',
          kind: ItemKind.boxSet,
          year: null,
          runtimeMinutes: null,
          overview: 'Due realtà.')
      ..itemsByCollection['c1'] = [
        testItem(id: 'm1', name: 'Matrix', played: true),
        testItem(
            id: 'm2',
            name: 'Matrix Reloaded',
            positionTicks: 600000000,
            playedPercentage: 10),
        testItem(id: 'm3', name: 'Matrix Revolutions'),
      ];
  });

  Future<void> pumpCollection(WidgetTester tester) async {
    await pumpApp(
        tester, const Scaffold(body: CollectionScreen(collectionId: 'c1')),
        surfaceSize: const Size(1440, 1400),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ]);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('testata, conteggio, sinossi e film in ordine', (tester) async {
    await pumpCollection(tester);
    expect(find.text('MATRIX - COLLEZIONE'), findsOneWidget);
    expect(find.text('3 film · 1 visto'), findsOneWidget);
    expect(find.text('Due realtà.'), findsOneWidget);
    expect(find.text('Matrix Revolutions'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Matrix')).dx,
        lessThan(tester.getTopLeft(find.text('Matrix Reloaded')).dx));
    expect(api.collectionItemsCalls, ['c1']);
  });

  testWidgets('pulsante: il primo film non visto, ripreso se iniziato',
      (tester) async {
    await pumpCollection(tester);
    expect(find.text('Riprendi "Matrix Reloaded"'), findsOneWidget);
  });

  testWidgets('tutti visti: si riparte dal primo', (tester) async {
    api.itemsByCollection['c1'] = [
      testItem(id: 'm1', name: 'Matrix', played: true),
      testItem(id: 'm2', name: 'Matrix Reloaded', played: true),
    ];
    await pumpCollection(tester);
    expect(find.text('Riproduci "Matrix"'), findsOneWidget);
    expect(find.text('2 film · 2 visti'), findsOneWidget);
  });

  testWidgets('nessuno visto: il primo', (tester) async {
    api.itemsByCollection['c1'] = [
      testItem(id: 'm1', name: 'Matrix'),
      testItem(id: 'm2', name: 'Matrix Reloaded'),
    ];
    await pumpCollection(tester);
    expect(find.text('Riproduci "Matrix"'), findsOneWidget);
    expect(find.text('2 film · 0 visti'), findsOneWidget);
  });

  testWidgets('saga che non c\'è: errore con Riprova', (tester) async {
    api.itemsById.clear();
    await pumpCollection(tester);
    expect(find.text('Riprova'), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/collections/collection_screen_test.dart`
Expected: errore di compilazione (`collection_screen.dart` non esiste).

- [ ] **Step 3: il contenitore pubblico, la pagina, la rotta**

In `lib/features/detail/detail_header.dart`, rinomina la classe privata `_ScrollFade` in `HeaderScrollFade` (dichiarazione, costruttore e l'uso in `DetailHeader`) e cambia il commento:

```dart
/// Opacità e salita del testo di una testata con lo scroll (scheda e pagina
/// della saga).
class HeaderScrollFade extends StatelessWidget {
  const HeaderScrollFade(
      {super.key, required this.controller, required this.child});
```

Crea `lib/features/collections/collection_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/shell_header.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../detail/detail_backdrop.dart';
import '../detail/detail_header.dart';
import '../detail/detail_providers.dart';
import '../detail/header_parallax.dart';
import '../detail/primary_action.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';

/// "Riprendi "Titolo"" o "Riproduci "Titolo"" (spec K §8.2).
String collectionActionLabel(AppLocalizations l, PrimaryAction action) =>
    switch (action) {
      ResumeAction() => l.collectionResume(action.target.name),
      PlayAction() => l.collectionPlay(action.target.name),
    };

/// Pagina di una saga, `/collection/:id` (spec K §8.2). Come la scheda di un
/// titolo: lo sfondo è un livello dietro, il contenuto sfuma tra caricamento,
/// errore e dati.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemProvider(widget.collectionId));
    final collection = async.value;
    final (state, content) = async.when(
      loading: () =>
          ('loading', const DetailSkeleton(headerHeight: detailHeaderHeight)),
      error: (error, _) => (
        'error',
        ErrorView(
            error: error,
            onRetry: () => ref.invalidate(itemProvider(widget.collectionId))),
      ),
      data: (item) =>
          ('data', CollectionView(collection: item, controller: _scroll)),
    );
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          child: collection != null
              ? DetailBackdrop(
                  item: collection, launch: null, controller: _scroll)
              : const SizedBox.shrink(),
        ),
        Positioned.fill(
          child: WfSwitcher(
            expand: true,
            child: KeyedSubtree(key: ValueKey(state), child: content),
          ),
        ),
      ],
    );
  }
}

/// Testata e griglia dei titoli di una saga (spec K §8.2).
class CollectionView extends ConsumerWidget {
  const CollectionView({super.key, required this.collection, this.controller});

  final JellyfinItem collection;

  /// Scroll della pagina (lo segue anche lo sfondo).
  final ScrollController? controller;

  /// Elementi della testata che entrano scaglionati (logo, conteggio,
  /// sinossi, pulsante).
  static const entranceCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(collectionItemsProvider(collection.id));
    final items = async.value;
    final error = async.error;
    final target = items == null
        ? null
        : sagaTarget(items, (item) => watchUserData(ref, item));
    final action =
        target == null ? null : primaryActionFor(target, watchUserData(ref, target));
    final page = StaggerGroup(
      count: entranceCount,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
                collection: collection,
                items: items,
                action: action,
                controller: controller),
          ),
          if (items != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.55,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) =>
                      PosterCard(item: items[i], heroSource: 'collection.$i'),
                  childCount: items.length,
                ),
              ),
            )
          else if (error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(collectionItemsProvider(collection.id))),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.only(bottom: 40), child: LoadingView()),
            ),
        ],
      ),
    );
    final scroll = controller;
    // Senza controller (vista montata da sola) niente titolo nella barra.
    if (scroll == null) return page;
    final reduced = WfMotion.of(context).isReduced;
    return ShellHeaderPublisher(
      controller: scroll,
      visibleAt: (offset) => barTitleVisible(offset, reduced: reduced),
      header: ShellHeader(
        title: collection.name,
        actionLabel: action == null ? null : collectionActionLabel(l, action),
        onAction: action == null
            ? null
            : () => unawaited(playItem(context, ref, action.target)),
      ),
      child: page,
    );
  }
}

/// Parte alta della pagina di una saga (spec K §8.2): logo o nome,
/// "N film · M visti", sinossi e pulsante principale. Lo sfondo è dietro
/// alla pagina (`DetailBackdrop`), come nella scheda di un titolo.
class CollectionHeader extends ConsumerWidget {
  const CollectionHeader({
    super.key,
    required this.collection,
    required this.items,
    required this.action,
    this.controller,
  });

  final JellyfinItem collection;

  /// `null` finché i titoli non sono arrivati.
  final List<JellyfinItem>? items;

  /// `null` senza titoli.
  final PrimaryAction? action;

  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final logo = ref.watch(imageUrlsProvider).logo(collection);
    final list = items;
    final primary = action;
    final overview = collection.overview;
    final watched = list == null
        ? 0
        : watchedCount(list, (item) => watchUserData(ref, item));
    return SizedBox(
      height: detailHeaderHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [WfColors.bg, Color(0xD90A0A0A), Colors.transparent],
                stops: [0, 0.4, 0.8],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [WfColors.bg, Colors.transparent],
                stops: [0, 0.5],
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: detailHeaderTextBottom,
            child: HeaderScrollFade(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  StaggerItem(
                    index: 0,
                    child: logo != null
                        ? SizedBox(
                            height: 120,
                            width: 460,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: WfImage(image: logo, fit: BoxFit.contain),
                            ),
                          )
                        : Text(collection.name.toUpperCase(),
                            maxLines: 2, style: WfText.display(56)),
                  ),
                  if (list != null) ...[
                    const SizedBox(height: 12),
                    StaggerItem(
                      index: 1,
                      child: Text(
                          '${l.collectionFilmCount(list.length)} · '
                          '${l.collectionWatched(watched)}',
                          style: const TextStyle(color: WfColors.creamMuted)),
                    ),
                  ],
                  if (overview != null) ...[
                    const SizedBox(height: 12),
                    StaggerItem(
                      index: 2,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Text(overview,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.45)),
                      ),
                    ),
                  ],
                  if (primary != null) ...[
                    const SizedBox(height: 20),
                    StaggerItem(
                      index: 3,
                      child: WfButton.primary(
                        label: collectionActionLabel(l, primary),
                        icon: LucideIcons.play,
                        onPressed: () => unawaited(
                            playItem(context, ref, primary.target)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

In `lib/app/router.dart`:
- l'import `import '../features/collections/collection_screen.dart';`;
- dopo la rotta `/person/:id`:

```dart
          GoRoute(
            path: '/collection/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              CollectionScreen(
                key: ValueKey(state.pathParameters['id']),
                collectionId: state.pathParameters['id']!,
              ),
              underBar: false,
            ),
          ),
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/collections test/features/detail`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): add the saga page"
```

## Gruppo E — app, catalogo e ricerca

### Task 9: vista "Saghe" nel catalogo Film

**Files:**
- Modify: `lib/features/catalog/catalog_filters_bar.dart`
- Create: `lib/features/collections/collection_card.dart`
- Create: `lib/features/collections/collections_grid.dart`
- Modify: `lib/features/catalog/catalog_screen.dart`
- Modify: `lib/app/router.dart`
- Create: `test/features/collections/collections_grid_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/collections/collections_grid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/catalog/catalog_screen.dart';
import 'package:wonderflix/features/collections/collections_providers.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/collections_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late FakeCollectionsApi collections;

  setUp(() {
    library = FakeLibraryApi()
      ..onItems = (query, start, limit) =>
          pageOf([testItem(id: 'm1', name: 'Dune')]);
    collections = FakeCollectionsApi()
      ..collectionsList = [
        testCollection(
            id: 'c1',
            name: 'Matrix - Collezione',
            itemIds: ['m1', 'm2', 'm3'],
            dateCreated: DateTime.utc(2026, 1, 1)),
        testCollection(
            id: 'c2',
            name: 'Alien - Collezione',
            itemIds: ['m4', 'm5'],
            dateCreated: DateTime.utc(2026, 6, 1)),
      ];
  });

  Future<void> pumpCatalog(WidgetTester tester, String location,
      {SocialFeatures features = const SocialFeatures(collections: true)}) async {
    final router = GoRouter(initialLocation: location, routes: [
      GoRoute(
        path: '/movies',
        builder: (context, state) => Scaffold(
          body: CatalogScreen(
            key: const ValueKey('movies'),
            kind: ItemKind.movie,
            view: CatalogView.parse(state.uri.queryParameters['view']),
          ),
        ),
      ),
      GoRoute(
          path: '/collection/:id',
          builder: (context, state) =>
              Scaffold(body: Text('saga ${state.pathParameters['id']}'))),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      libraryApiProvider.overrideWithValue(library),
      sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser))),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
      collectionsApiProvider.overrideWithValue(collections),
    ]);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('il selettore porta dai film alle saghe', (tester) async {
    await pumpCatalog(tester, '/movies');
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Saghe'), findsOneWidget);

    await tester.tap(find.text('Saghe'));
    await tester.pump();
    await tester.pump();
    expect(find.text('2 saghe'), findsOneWidget);
    expect(find.text('Matrix - Collezione'), findsOneWidget);
    expect(find.text('3 film'), findsOneWidget);
    expect(find.text('Tutti i generi'), findsNothing,
        reason: 'generi e anni non valgono per le saghe');
  });

  testWidgets('senza la funzione: niente selettore, ?view=sagas mostra i film',
      (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas',
        features: SocialFeatures.none);
    expect(find.text('Saghe'), findsNothing);
    expect(find.text('Dune'), findsOneWidget);
    expect(collections.calls, 0);
  });

  testWidgets('ricerca per nome e ordinamento', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas');
    // Per nome: Alien prima di Matrix.
    expect(tester.getTopLeft(find.text('Alien - Collezione')).dx,
        lessThan(tester.getTopLeft(find.text('Matrix - Collezione')).dx));

    await tester.tap(find.text('Ordina per: Nome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordina per: Numero di film').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Matrix - Collezione')).dx,
        lessThan(tester.getTopLeft(find.text('Alien - Collezione')).dx));

    await tester.enterText(
        find.byKey(const Key('collections-search')), 'ALIEN');
    await tester.pumpAndSettle();
    expect(find.text('Alien - Collezione'), findsOneWidget);
    expect(find.text('Matrix - Collezione'), findsNothing);

    await tester.enterText(find.byKey(const Key('collections-search')), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Nessuna saga con questo nome'), findsOneWidget);
  });

  testWidgets('clic su una saga: la sua pagina', (tester) async {
    await pumpCatalog(tester, '/movies?view=sagas');
    await tester.tap(find.text('Matrix - Collezione'));
    await tester.pumpAndSettle();
    expect(find.text('saga c1'), findsOneWidget);
  });

  testWidgets('nessuna saga', (tester) async {
    collections.collectionsList = [];
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.text('Nessuna saga'), findsOneWidget);
  });

  testWidgets('errore con Riprova', (tester) async {
    collections.error = const ServerUnreachableException();
    await pumpCatalog(tester, '/movies?view=sagas');
    expect(find.text('Riprova'), findsOneWidget);

    collections.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Matrix - Collezione'), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/collections/collections_grid_test.dart`
Expected: errore di compilazione (`CatalogView` non esiste).

- [ ] **Step 3: menu pubblico, card, griglia, catalogo, rotta**

In `lib/features/catalog/catalog_filters_bar.dart`, rinomina `_Picker` in `FilterPicker` (la classe, il costruttore e i tre usi in `CatalogFiltersBar`) e mettile il commento:

```dart
/// Un menu della barra dei filtri (catalogo, La mia lista, vista "Saghe").
class FilterPicker<T> extends StatelessWidget {
  const FilterPicker(
      {super.key, required this.value, required this.items, required this.onChanged});
```

Crea `lib/features/collections/collection_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Card di una saga (vista "Saghe", ricerca): locandina, nome, numero di
/// film (spec K §8.4). Il clic apre la pagina della saga. Senza anteprima al
/// passaggio del mouse: l'anteprima è dei titoli.
class CollectionCard extends ConsumerStatefulWidget {
  const CollectionCard({super.key, required this.collection, this.width});

  final CollectionSummary collection;

  /// `null`: la larghezza disponibile (griglie).
  final double? width;

  @override
  ConsumerState<CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends ConsumerState<CollectionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final collection = widget.collection;
    final tag = collection.primaryImageTag;
    final image = tag == null
        ? null
        : ref.watch(imageUrlsProvider).primaryWithTag(collection.id, tag);
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => openCollection(context, collection.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: WfMotion.fast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _hover ? WfColors.gold : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: WfImage(image: image, fallbackIcon: LucideIcons.layers),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(l.collectionFilmCount(collection.size),
                  style:
                      const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

Crea `lib/features/collections/collections_grid.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../catalog/catalog_filters_bar.dart';
import 'collection_card.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';

/// Larghezza del campo di ricerca della vista "Saghe".
const collectionsSearchWidth = 280.0;

/// Vista "Saghe" del catalogo Film (spec K §8.4): ricerca per nome,
/// ordinamento e griglia delle saghe. Niente pagine: l'elenco è già tutto in
/// cache ([collectionsProvider]). Ricerca e ordinamento restano nella vista.
class CollectionsGrid extends ConsumerStatefulWidget {
  const CollectionsGrid({super.key});

  @override
  ConsumerState<CollectionsGrid> createState() => _CollectionsGridState();
}

class _CollectionsGridState extends ConsumerState<CollectionsGrid> {
  final _scroll = SmoothScrollController();
  String _query = '';
  CollectionSort _sort = CollectionSort.name;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: collectionsSearchWidth,
                height: filtersBarHeight,
                child: TextField(
                  key: const Key('collections-search'),
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: l.collectionsSearchHint,
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.search,
                        size: 18, color: WfColors.creamMuted),
                  ),
                ),
              ),
              FilterPicker<CollectionSort>(
                value: _sort,
                items: {
                  CollectionSort.name:
                      '${l.catalogSortLabel}: ${l.collectionsSortName}',
                  CollectionSort.size:
                      '${l.catalogSortLabel}: ${l.collectionsSortSize}',
                  CollectionSort.dateAdded:
                      '${l.catalogSortLabel}: ${l.catalogSortDateAdded}',
                },
                onChanged: (sort) => setState(() => _sort = sort),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: WfSwitcher(expand: true, child: _body(l))),
      ],
    );
  }

  /// Contenuto sotto ricerca e ordinamento, con una chiave per stato (per
  /// [WfSwitcher]).
  Widget _body(AppLocalizations l) {
    const muted = TextStyle(color: WfColors.creamMuted);
    final async = ref.watch(collectionsProvider);
    final list = async.value;
    if (list == null) {
      final error = async.error;
      if (error != null) {
        return ErrorView(
            key: const ValueKey('error'),
            error: error,
            onRetry: () => ref.invalidate(collectionsProvider));
      }
      return const PosterGridSkeleton(key: ValueKey('loading'));
    }
    if (list.isEmpty) {
      return Center(
          key: const ValueKey('empty'),
          child: Text(l.collectionsEmpty, style: muted));
    }
    final shown = sortCollections(filterCollections(list, _query), _sort);
    if (shown.isEmpty) {
      return Center(
          key: const ValueKey('no-match'),
          child: Text(l.collectionsNoMatch, style: muted));
    }
    return KeyedSubtree(
      key: const ValueKey('data'),
      child: Builder(builder: (context) => _grid(context, shown)),
    );
  }

  Widget _grid(BuildContext context, List<CollectionSummary> shown) {
    // La griglia che esce in dissolvenza non tiene `_scroll` (vedi il catalogo).
    final outgoing = WfSwitcher.isOutgoing(context);
    return CustomScrollView(
      controller: outgoing ? null : _scroll,
      primary: false,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 24,
              crossAxisSpacing: 16,
              childAspectRatio: 0.55,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => CollectionCard(
                  key: ValueKey(shown[i].id), collection: shown[i]),
              childCount: shown.length,
            ),
          ),
        ),
      ],
    );
  }
}
```

In `lib/features/catalog/catalog_screen.dart`:
- gli import, oltre a quelli che ci sono:

```dart
import 'package:go_router/go_router.dart';

import '../../ui/wf_tab_button.dart';
import '../collections/collections_grid.dart';
import '../collections/collections_providers.dart';
import '../social/social_providers.dart';
```

- prima di `class CatalogScreen`:

```dart
/// Vista del catalogo Film: i titoli o le saghe (spec K §8.4). Sta
/// nell'indirizzo (`/movies?view=sagas`).
enum CatalogView {
  titles,
  sagas;

  static CatalogView parse(String? value) => value == 'sagas' ? sagas : titles;
}
```

- il widget:

```dart
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen(
      {super.key, required this.kind, this.view = CatalogView.titles});

  final ItemKind kind;

  /// Solo per i film. Senza la funzione `collections` del plugin vale come
  /// [CatalogView.titles].
  final CatalogView view;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}
```

- sostituisci tutto il metodo `build` di `_CatalogScreenState` con `build` e `_titles`:

```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sagasAvailable = widget.kind == ItemKind.movie &&
        ref.watch(socialAvailabilityProvider
            .select((features) => features.collections));
    final sagas = sagasAvailable && widget.view == CatalogView.sagas;
    final title = widget.kind == ItemKind.series ? l.navSeries : l.navMovies;
    final String? count;
    if (sagas) {
      final list = ref.watch(collectionsProvider).value;
      count = list == null || list.isEmpty
          ? null
          : l.collectionsCount(list.length);
    } else {
      final total = ref.watch(catalogControllerProvider(widget.kind)).total;
      count = total > 0 ? l.catalogCount(total) : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title.toUpperCase(), style: WfText.display(40)),
              const SizedBox(width: 16),
              if (count != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(count,
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
            ],
          ),
        ),
        if (sagasAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
            child: Row(
              children: [
                WfTabButton(
                    label: l.navMovies,
                    selected: !sagas,
                    onTap: () => context.go('/movies')),
                const SizedBox(width: 20),
                WfTabButton(
                    label: l.collectionsTab,
                    selected: sagas,
                    onTap: () => context.go('/movies?view=sagas')),
              ],
            ),
          ),
        if (sagas)
          const Expanded(child: CollectionsGrid())
        else
          ..._titles(context, l),
      ],
    );
  }

  /// Filtri e griglia dei titoli.
  List<Widget> _titles(BuildContext context, AppLocalizations l) {
    final provider = catalogControllerProvider(widget.kind);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final filters = ref.watch(catalogFiltersProvider(widget.kind)).value ??
        const LibraryFilters();

    // Su schermi grandi la prima pagina può non riempire la finestra: senza
    // scroll non scatterebbe mai il caricamento successivo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current = ref.read(provider);
      if (current.items.isEmpty) _autoLoadedAt = -1; // nuova query
      if (_scroll.position.maxScrollExtent == 0 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(controller.loadMore());
      }
    });

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: CatalogFiltersBar(
          filters: filters,
          query: state.query,
          onChanged: (query) => unawaited(controller.setQuery(query)),
        ),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: WfSwitcher(
          expand: true,
          child: _body(context, l, state, controller),
        ),
      ),
    ];
  }
```

In `lib/app/router.dart`, la rotta `/movies`:

```dart
          GoRoute(
              path: '/movies',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  // Stessa chiave per le due viste: cambiando vista la
                  // pagina resta la stessa (spec K §8.4).
                  CatalogScreen(
                      key: const ValueKey('movies'),
                      kind: ItemKind.movie,
                      view: CatalogView.parse(
                          state.uri.queryParameters['view'])),
                  underBar: true)),
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/collections test/features/catalog`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): add the Sagas view to the movie catalog"
```

### Task 10: saghe nella ricerca

**Files:**
- Create: `lib/features/collections/sagas_search_section.dart`
- Modify: `lib/features/search/search_screen.dart`
- Modify: `test/features/search/search_screen_test.dart`

- [ ] **Step 1: i test**

In `test/features/search/search_screen_test.dart`:
- gli import:

```dart
import 'package:wonderflix/features/collections/collections_providers.dart';

import '../../support/collections_fakes.dart';
```

- in fondo a `main`:

```dart
  group('saghe (spec K §8.5)', () {
    late FakeCollectionsApi collections;

    setUp(() {
      collections = FakeCollectionsApi()
        ..collectionsList = [
          testCollection(id: 'c1', name: 'Mátrix - Collezione'),
          testCollection(id: 'c2', name: 'Alien - Collezione'),
        ];
    });

    Future<void> pumpSearch(WidgetTester tester, FakeLibraryApi api) async {
      await pumpApp(tester, const Scaffold(body: SearchScreen()), overrides: [
        libraryApiProvider.overrideWithValue(api),
        requestsAvailableProvider.overrideWithValue(false),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        socialAvailabilityProvider.overrideWith(() =>
            FakeSocialAvailability(const SocialFeatures(collections: true))),
        collectionsApiProvider.overrideWithValue(collections),
      ]);
    }

    testWidgets('senza badare a maiuscole e accenti, sopra i film',
        (tester) async {
      final api = FakeLibraryApi()
        ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
            ? pageOf([testItem(id: 'm1', name: 'Matrix')])
            : pageOf([]))
        ..people = [];
      await pumpSearch(tester, api);
      await tester.enterText(find.byType(TextField), 'MATRIX');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Saghe'), findsOneWidget);
      expect(find.text('Mátrix - Collezione'), findsOneWidget);
      expect(find.text('Alien - Collezione'), findsNothing);
      expect(tester.getTopLeft(find.text('Saghe')).dy,
          lessThan(tester.getTopLeft(find.text('Film')).dy));
      expect(collections.calls, 1);
    });

    testWidgets('solo saghe: niente "Nessun risultato"', (tester) async {
      await pumpSearch(tester, FakeLibraryApi());
      await tester.enterText(find.byType(TextField), 'alien');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Alien - Collezione'), findsOneWidget);
      expect(find.text('Nessun risultato per "alien"'), findsNothing);
    });

    testWidgets('niente saghe che corrispondono: nessuna sezione',
        (tester) async {
      await pumpSearch(tester, FakeLibraryApi());
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Saghe'), findsNothing);
      expect(find.text('Nessun risultato per "zzz"'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: i test non passano**

Run: `flutter test test/features/search/search_screen_test.dart`
Expected: i tre test nuovi falliscono (nessuna sezione "Saghe").

- [ ] **Step 3: la sezione e la ricerca**

Crea `lib/features/collections/sagas_search_section.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'collection_card.dart';

/// Sezione "Saghe" della ricerca (spec K §8.5): le saghe il cui nome
/// contiene il testo cercato, prese dall'elenco in cache, senza chiamate.
class SagasSearchSection extends StatelessWidget {
  const SagasSearchSection({super.key, required this.sagas});

  /// Quante saghe al massimo.
  static const maxResults = 12;

  final List<CollectionSummary> sagas;

  @override
  Widget build(BuildContext context) {
    if (sagas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).collectionsTab,
              style: WfText.display(26)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 24,
            children: [
              for (final saga in sagas)
                CollectionCard(
                    key: ValueKey(saga.id), collection: saga, width: 150),
            ],
          ),
        ],
      ),
    );
  }
}
```

In `lib/features/search/search_screen.dart`:
- gli import:

```dart
import '../../core/social/collections_models.dart';
import '../collections/collections_logic.dart';
import '../collections/collections_providers.dart';
import '../collections/sagas_search_section.dart';
```

- in `build`, dopo `final controller = …;`:

```dart
    final sagas = state.term.length < SearchController.minLength
        ? const <CollectionSummary>[]
        : matchCollections(
            ref.watch(collectionsProvider).value ?? const [], state.term,
            max: SagasSearchSection.maxResults);
```

- nella `ListView`, al posto di `WfSwitcher(child: _results(context, l, state)),`:

```dart
        SagasSearchSection(sagas: sagas),
        WfSwitcher(
            child: _results(context, l, state, hasSagas: sagas.isNotEmpty)),
```

- la firma di `_results` e il caso vuoto:

```dart
  /// Risultati, con una chiave per stato (per [WfSwitcher]). Con delle saghe
  /// trovate ([hasSagas]) "Nessun risultato" non compare.
  Widget _results(BuildContext context, AppLocalizations l, SearchState state,
      {required bool hasSagas}) {
```

```dart
    if (results.isEmpty) {
      if (hasSagas) return const SizedBox.shrink(key: ValueKey('empty'));
      return Text(l.searchNoResults(state.term),
          key: const ValueKey('empty'), style: muted);
    }
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/search`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): find sagas in the search"
```

## Gruppo F — chiusura

### Task 11: allineamento della spec e build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md`

- [ ] **Step 1: la spec**

Nella spec:
- **Stato:** "approvato; piano 17a realizzato (`docs/superpowers/plans/2026-10-07-wonderflix-17a-saghe.md`), piani 17b e 17c da scrivere".
- **§7.1:** l'adattatore chiama `GetChildren(user, true, new InternalItemsQuery())` sulla cartella e su ogni `BoxSet`, come `GET /Items?parentId=…` di Jellyfin. Nei test del plugin si provano solo i casi senza utente o senza cartella; le collezioni vere si provano sul server. Il csproj è già a 1.5.0.
- **§8.2:** la testata è `CollectionHeader`, con `HeaderScrollFade` in comune con `DetailHeader`.
- **§8.3:** il titolo della riga ha la freccia `LucideIcons.arrowRight`; il film aperto ha l'etichetta "Questo film" (`PosterCard.markLabel`) e non si riapre.
- **§8.4:** ricerca e ordinamento restano nella vista (non nell'indirizzo); il menu è `FilterPicker`, reso pubblico da `catalog_filters_bar.dart`.
- **§8.5:** con delle saghe trovate e nessun titolo, "Nessun risultato" non compare.
- **§11:** in inglese "Collections" / "collection".
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 2: build**

Copia `config/wonderflix.json` dalla root del repository principale nel worktree (`config/`), se non c'è. Poi:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Senza `--dart-define-from-file` l'app parte su "Configurazione mancante".

- [ ] **Step 3: commit**

Suite intera, `flutter analyze` e test del plugin, poi:

```powershell
git add docs
git commit -m "docs: align the sagas and profiles spec with plan 17a"
```

### Task 12: prova a mano (orchestratore e utente)

Prima l'orchestratore, sul server e in sola lettura:
- i numeri attesi dal database: 101 collezioni, quanti film in "Marvel Universe" (64) e in "Matrix - Collezione" (3).

Poi l'utente, con la build del Task 11 (`build\windows\x64\runner\Release\wonderflix.exe` nel worktree):
1. **Scheda:** un film di Matrix e uno della Marvel. Devono comparire le righe "Fa parte di", la più piccola prima, con "Questo film" sul film aperto. Il titolo della riga apre la pagina della saga.
2. **Pagina della saga:** "Marvel Universe" (64 film, in ordine di uscita) e Matrix. Controllare il conteggio dei visti e il pulsante: un film iniziato dà "Riprendi"; con tutti visti si riparte dal primo.
3. **Catalogo:** Film → Saghe, con "101 saghe" per l'admin; ricerca "star" (ci sono i due doppioni di Star Wars); ordinamento per numero di film (prima "Marvel Universe").
4. **Ricerca:** "matrix" mostra la saga sopra i film.
5. **Utente normale** (se l'utente ha un secondo account): la seconda istanza `WONDERFLIX_PROFILE=b` vede le saghe, e solo con i film delle sue librerie.

Con l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`). Il plugin 1.5.0.0 resta installato a mano sul server fino alla release del 17c.
