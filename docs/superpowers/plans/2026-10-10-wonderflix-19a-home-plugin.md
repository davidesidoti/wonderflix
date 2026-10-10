# WonderFlix — Piano 19a: Home su misura, plugin 1.7.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server dello Spec M nel plugin 1.7.0:
- la Home dell'admin (`Home/Layout`), letta da tutti e scritta dall'admin;
- le uscite in arrivo da Sonarr e Radarr (`Upcoming/Series`, `Upcoming/Movies`), con la cache e la prova del collegamento (`Upcoming/Test`);
- le funzioni `home`, `upcomingSeries`, `upcomingMovies` in `Info`;
- la sezione "Sonarr and Radarr" nella pagina della Dashboard;
- una build di prova sul server, configurata.

L'app arriva nei piani 19b e 19c.

**Architecture:** la logica sta nella nuova cartella `Home/` e non conosce Jellyfin: parla con interfacce (`IHomeLayoutStore`, `IArrSettings`, `IArrClient`, `ISeriesIndex`, e `ILibraryAccess` che c'è già). Le classi sono piccole e ognuna fa una cosa:
- `HomeRowIds`: gli id delle righe e la loro pulizia;
- `ArrClient`: HTTP verso Sonarr e Radarr (modello: `SeerrClient`);
- `UpcomingBuilder`: da calendario a uscite (filtri, blocchi di episodi, immagini, serie della libreria), funzioni pure;
- `UpcomingService`: cache di 15 minuti (errori 1 minuto) e serie scelta per ogni utente.

Gli adattatori stanno in `Server/` (`PluginHomeLayoutStore`, `PluginArrSettings`, `JellyfinSeriesIndex`), i controller in `Api/`.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`, API v3 di Sonarr 4 e Radarr 6. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md` (§3, §6.1, §6.2, §7, §9, §12.1, §13, §14, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 9):
1. **Codici d'errore in PascalCase:** `NotConfigured`, `Unauthorized`, `Unreachable`, come `SeerrTestResponse` e il resto del plugin. La spec §7.3 li scrive in camelCase.
2. **La Home dell'admin è una stringa nella configurazione** (`HomeRows`, id separati da virgole). Con XmlSerializer una stringa tiene distinti `null` (mai impostata) e `""` (tutte spente); un elenco no. Gli id sono confrontati con le maiuscole (`"Resume"` non vale).
3. **Periodi chiusi a sinistra e aperti a destra:**
   - serie da **ora − 12 ore** a **ora + giorni**;
   - film da **oggi 00:00 UTC** a **oggi + giorni + 1**, così "entro 90 giorni" comprende il novantesimo giorno.
4. **Serie della libreria:** a ogni lettura di Sonarr il plugin legge tutte le serie di Jellyfin una volta (`ISeriesIndex`) e le confronta per TVDB, TMDB o IMDb (IMDb senza maiuscole). Se due serie corrispondono (es. due librerie) si tengono entrambe; per ogni utente vale la prima che vede.
5. **La cache dipende dalle impostazioni** (indirizzo, chiave, giorni): se l'admin le cambia, la richiesta dopo rilegge, senza aspettare i 15 minuti. Una sola lettura alla volta anche con molte richieste insieme. La lettura gira senza il token di chi chiede: se uno chiude la richiesta, gli altri hanno la risposta lo stesso.
6. **Un errore inatteso** (non di Sonarr/Radarr) in una lettura vale `Unreachable` per 1 minuto e va nel log: la cache non resta mai su un'eccezione.
7. **Immagini:** solo `remoteUrl` assoluti `http`/`https`. I percorsi locali di Sonarr (`/MediaCover/…`, vogliono la chiave) e gli altri schemi non escono mai.
8. **Dati sporchi da Sonarr/Radarr:** elementi `null` negli elenchi, `series` o `airDateUtc` nulli (episodi senza data), `images: null`, titoli vuoti → l'elemento si salta, mai un'eccezione.
9. **La prova del collegamento** chiama solo `system/status` di ciascun servizio, in parallelo e senza cache.
10. **Configurazione sul server via API di Jellyfin** (Task 8): si rilegge la configurazione intera, si aggiungono i campi e si riscrive, come fa l'app con `NotifyNewTitles`. Niente modifica dell'XML a mano.
11. **Rilascio:** il plugin 1.7.0 va nel Catalogo alla fine del 19c, con l'app 0.13.0. Fino ad allora sul server resta la build di prova del Task 8; l'app 0.12 non usa le funzioni nuove.
12. **Dalle review dei gruppi** (il codice dei task sotto è quello di partenza: dove differisce, vale questa lista, e la spec è già allineata):
    - **Task 4:** `JellyfinSeriesIndex.GetSeries()` ordina le serie per `Id` (`.OrderBy(series => series.Id)` prima di `.ToList()`). Nel test gli id sono fissi e lo stub le restituisce in ordine inverso, così l'ordinamento si vede davvero; l'atteso è ordinato per id.
      - Perché (ruling del controller, dalla review del Task 3): `MatchSeries` tiene l'ordine della libreria e per ogni utente decide "la prima che vede" (decisione 4);
      - senza un ordine stabile, con due serie uguali (per esempio in due librerie) il collegamento di un utente potrebbe passare dall'una all'altra a ogni nuova lettura di Sonarr, cioè al massimo ogni 15 minuti.
    - **Task 5:** `UpcomingServiceTests.cs` ha bisogno di `using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;`: `ArrTestResult` è lì (le altre risposte si usano con `var`).
    - **Task 7:** `ServiceRegistrationTests` costruisce con `ActivatorUtilities.CreateInstance` anche `InfoController`, `HomeController` e `UpcomingController` (ruling del controller, dalla review del Task 6; è il modo già usato per i controller dell'account).
      - Perché: `InfoController` ora vuole `IArrSettings`, e una registrazione mancante romperebbe `GET Info` per ogni app senza che i test unitari se ne accorgano.
    - **Review finale** (commit `1c1741a`; la suite passa da 806 a 810 test):
      - **la prova controlla l'app** (`UpcomingService.TestOneAsync`): se `appName` di `system/status` non è quello atteso (senza badare alle maiuscole; un nome mancante vale un'altra app) dà `Unreachable`, e il log dice chi ha risposto. Con gli indirizzi scambiati (Sonarr dove va Radarr) lo stato risponde lo stesso: la prova diceva "collegato" e le due righe restavano vuote in silenzio. La decisione 9 vale con questo controllo in più;
      - **`Cached` riusa una lettura finita solo se `IsCompletedSuccessfully`**: se anche il registro lanciava nel `catch` della lettura, questa finiva in errore con scadenza `MaxValue` e ogni richiesta con le stesse impostazioni riceveva l'eccezione, per sempre (un caso che la decisione 6 non copriva: l'eccezione veniva dal registro stesso);
      - **la Dashboard** scrive "unknown version" se lo stato non ha la versione, non "connected (null)" (`arrText` in `configPage.html`; `PluginPagesTests` controlla il testo);
      - **un test in più**, `AnEpisodeOutLastNightIsStillUpcoming`: un episodio uscito 11 ore fa c'è ancora, uno di 13 ore fa no;
      - **l'ordine:** la review finale e questi ritocchi sono stati fatti **prima** dell'installazione sul server (Task 8), non dopo come scriveva il Task 8: si installa il codice già rivisto, con un solo riavvio di Jellyfin.
    - **Task 8:** la copia della configurazione si chiama `~/wfwp-backup/config-1.6.0-prima-19a.xml` (il piano diceva `config-1.6.0.xml`).

## Global Constraints

- Plugin **1.7.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9.
- Endpoint sotto `/WonderFlixWatchParty`:
  - `GET Home/Layout` per ogni utente collegato; `POST Home/Layout` solo admin;
  - `GET Upcoming/Series` e `GET Upcoming/Movies` per ogni utente collegato; `POST Upcoming/Test` solo admin.
- Id delle righe (spec §6.1), in quest'ordine: `resume`, `nextUp`, `requests`, `latestMovies`, `latestSeries`, `becauseYouWatched`, `continueSaga`, `upcomingSeries`, `upcomingMovies`, `myList`.
- Configurazione: `SonarrUrl`, `SonarrApiKey`, `RadarrUrl`, `RadarrApiKey` (vuoti), `UpcomingSeriesDays` 7 (1–60), `UpcomingMoviesDays` 90 (1–365), `HomeRows` (null).
- Cache 15 minuti, errori 1 minuto, attesa massima di Sonarr/Radarr 10 s.
- Mai 404: `Upcoming/*` risponde sempre 200, con `Items` vuoto ed `Error` in caso di problemi.
- Le chiavi di Sonarr e Radarr non lasciano mai il server e non vanno mai nel log; le immagini sono solo indirizzi pubblici.
- `Info`: `home` sempre; `upcomingSeries` con Sonarr configurato; `upcomingMovies` con Radarr configurato.
- `JellyfinSeriesId` solo se chi chiama vede la serie.

## Review Focus

1. **Dati sporchi da Sonarr/Radarr** (`[null]`, `series: null`, `airDateUtc: null`, `images: null`, titoli vuoti): l'elemento si salta, la risposta arriva lo stesso. Test: Task 2 (`NullsInsideTheListsDoNotBreakTheParsing`) e Task 3 (`OnlyEpisodesStillToDownloadInsideTheRangeWithANamedSeries`, `ExternalIdsAndOnlyPublicImageAddresses`).
2. **Immagini locali di Sonarr** (`/sonarr/MediaCover/…`) o con altri schemi: non escono mai. Test: Task 3 (`ExternalIdsAndOnlyPublicImageAddresses`).
3. **L'admin corregge un indirizzo sbagliato:** la richiesta dopo usa le impostazioni nuove, non l'errore in cache. Test: Task 5 (`ChangedSettingsDoNotUseTheOldCache`).
4. **Sonarr lento con molti utenti insieme:** una sola lettura per tutti; chi chiude la richiesta non la ferma agli altri. Test: Task 5 (`UsersAskingTogetherShareOneRead`, `ACancelledCallerDoesNotStopTheReadForTheOthers`).
5. **`POST Home/Layout` con id sconosciuti, doppioni, `null` o maiuscole diverse, o senza corpo:** id scartati, senza corpo 400; un elenco vuoto vale (tutte spente) ed è diverso da `null`. Test: Task 1 (`NormalizeKeepsTheOrderAndDropsUnknownDuplicatesNullsAndOtherCases`, `AMissingBodyIsABadRequestAndSavesNothing`, `TheHomeLayoutKeepsNeverSetApartFromAllOffThroughTheXml`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-19a`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(plugin): …"`.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.7.0`.
- **Test:**
  - un solo gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj del plugin ha `TreatWarningsAsErrors`: un warning è un errore), poi `dotnet build-server shutdown`;
  - la base di partenza è di **748** test verdi (verificato il 2026-10-10 su `main` `c0dd22d`).
- **Formattazione e fine riga:**
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese;
  - durate, misure e limiti come costanti nominate e commentate;
  - `TimeProvider`, mai `DateTimeOffset.UtcNow`;
  - DTO `record` con `[property: JsonPropertyName("…")]`, oppure classi con `[JsonPropertyName]` per i corpi delle richieste;
  - id di Jellyfin in formato `"N"`;
  - nel registro mai chiavi, token o query.
- **Se il codice del piano ha un errore** (compilazione, nullability, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-10 sul codice di `main` (`c0dd22d`), sui pacchetti NuGet di Jellyfin 10.11.0 e sul server, in sola lettura.

**Sonarr e Radarr** (chiamate vere dal server, 2026-10-10)
- Sonarr **4.0.20.3014**, Radarr **6.4.4.10685**, a `https://hashvps.proton.usbx.me/sonarr` e `…/radarr` (UrlBase `/sonarr` e `/radarr`). Le chiavi stanno in `~/.apps/{sonarr,radarr}/config.xml` (`<ApiKey>`). Il dominio `hashvps.vapor.usbx.me` di Home Screen Sections risponde 404.
- Intestazione `X-Api-Key`. Stato: `GET /api/v3/system/status` → `{"appName":"Sonarr","version":"4.0.20.3014",…}`.
- `GET /api/v3/calendar?start=…&end=…&includeSeries=true&unmonitored=false` (Sonarr): array di episodi con `seriesId`, `seasonNumber`, `episodeNumber`, `title`, `airDate`, `airDateUtc` (`"2026-10-12T01:00:00Z"`), `hasFile`, `monitored`, `tvdbId` (dell'episodio) e `series` con `title`, `tvdbId`, `tmdbId`, `imdbId`, `images` (`coverType` fra `banner`, `poster`, `fanart`, `clearlogo`; `url` locale `/sonarr/MediaCover/…`; `remoteUrl` pubblico). 16 episodi nei 7 giorni dal 2026-10-10.
- `GET /api/v3/calendar?start=…&end=…&unmonitored=false` (Radarr): array di film con `title`, `year`, `tmdbId`, `imdbId`, `inCinemas`, `digitalRelease`, `physicalRelease` (alcune possono mancare), `hasFile`, `images` (`poster`, `fanart`). Ci sono anche film già scaricati o fuori periodo per l'uscita digitale (es. "Leviticus": `hasFile` true, uscita fisica a novembre). 11 film nei 90 giorni prima dei filtri.

**Jellyfin**
- `BasePlugin<T>.SaveConfiguration()` esiste nella 10.11.0 (documentazione XML del pacchetto).
- `ILibraryManager.GetItemList(InternalItemsQuery)`; `InternalItemsQuery` con `IncludeItemTypes = [BaseItemKind.Series]` e `IsVirtualItem = false` come in `JellyfinLibraryTitles.HasOtherEpisodes`. Gli id esterni con `item.TryGetProviderId(MetadataProvider.Tvdb, out var value)` (`MediaBrowser.Model.Entities`), come in `NewTitleRules.ExternalKeys`.
- `Policies.RequiresElevation` sta in `MediaBrowser.Common.Api`. Un `[Authorize(Policy = …)]` sul metodo si somma a `[Authorize]` della classe (come `RequestsController.Test`).
- La configurazione si legge da `Plugin.Instance?.Configuration` a ogni uso: salvando dalla Dashboard Jellyfin sostituisce l'oggetto (`PluginSeerrSettings`).

**Plugin** (`main`)
- `SeerrClient` è il modello per `ArrClient`: nome del client HTTP registrato con `AllowAutoRedirect = false` e `RedactLoggedHeaders`, `Timeout` interno di 10 s, nel registro solo il percorso senza query, eccezioni classificate.
- `Lock` di .NET 9 per le sezioni critiche (`AccountSender`, `CodeBook`); `Task.Run` per il lavoro che non deve dipendere da chi chiede (`PasswordRecovery`).
- `InfoController` usa `WatchPartyProtocol.FeaturesWith(bool requests)`, chiamato solo lì.
- La pagina della Dashboard (`Configuration/configPage.html`) è un unico script `(function () { … })();`: i form leggono la configurazione intera e la riscrivono con i loro campi cambiati. Il form del recupero non salva finché non ha letto (`recoveryLoaded`) e usa `numberIn(field, fallback)` per i numeri; è la protezione da copiare.
- **Test:**
  - `FakeSeerrHttp` è un `HttpMessageHandler` + `IHttpClientFactory` generico: registra metodo, URI, `X-API-Key` (la ricerca dell'intestazione non bada alle maiuscole, quindi legge anche `X-Api-Key`) e risponde con `Respond`;
  - `FakeServer` implementa `ILibraryAccess`: `AddUser(name)` dà un `UserRef` con `Id`; `CanSee` è vero per gli utenti noti tranne le coppie in `Unseen`; `LibraryFails` lo fa lanciare;
  - `RecordingLogger<T>`, `InterfaceStub<T>` (`Handlers["Nome"]`, `Calls`), `FakeAuthorizationContext(AuthorizationInfo)`, `FakeTimeProvider`;
  - utenti di Jellyfin nei test: `new User("mario", "provider", "reset")`;
  - `InfoControllerTests` controlla la versione `"1.6.0"` e le funzioni; `PluginPagesTests` i testi della pagina (con `TagWithId`); `ServiceRegistrationTests` i servizi e 3 servizi in background.

## File

| File | Responsabilità |
|---|---|
| `Home/HomeRowIds.cs` | id delle righe, pulizia, lettura e scrittura del testo salvato |
| `Home/IHomeLayoutStore.cs`, `Server/PluginHomeLayoutStore.cs` | Home dell'admin nella configurazione del plugin |
| `Protocol/HomeDtos.cs`, `Api/HomeController.cs` | `GET`/`POST Home/Layout` |
| `Configuration/PluginConfiguration.cs` (modifica) | `HomeRows`, Sonarr, Radarr, giorni |
| `Home/IArrSettings.cs`, `Server/PluginArrSettings.cs` | indirizzi, chiavi e giorni |
| `Home/ArrJson.cs` | modelli JSON di Sonarr e Radarr |
| `Home/ArrException.cs` | `ArrError`, `ArrException`, `UpcomingErrors` |
| `Home/IArrClient.cs`, `Home/ArrClient.cs` | HTTP verso Sonarr e Radarr |
| `Home/ISeriesIndex.cs`, `Server/JellyfinSeriesIndex.cs` | serie della libreria con gli id esterni |
| `Home/UpcomingBuilder.cs` | da calendario a uscite |
| `Protocol/UpcomingDtos.cs`, `Home/UpcomingService.cs` | risposte, cache, serie per utente, prova |
| `Api/UpcomingController.cs` | `Upcoming/Series`, `Upcoming/Movies`, `Upcoming/Test` |
| `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs` (modifica) | funzioni `home`, `upcomingSeries`, `upcomingMovies` |
| `PluginServiceRegistrator.cs`, csproj, `Plugin.cs`, `Configuration/configPage.html`, `../meta.template.json`, `../README.md` (modifica) | montaggio, versione 1.7.0, Dashboard, documentazione |

Tutti i percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test), se non è detto altro.

---

## Gruppo A — Home dell'admin

### Task 1: la Home dell'admin

**Files:**
- Create: `Home/HomeRowIds.cs`, `Home/IHomeLayoutStore.cs`, `Server/PluginHomeLayoutStore.cs`, `Protocol/HomeDtos.cs`, `Api/HomeController.cs`
- Modify: `Configuration/PluginConfiguration.cs`
- Test: `HomeRowIdsTests.cs`, `HomeControllerTests.cs` (nuovi), `PluginConfigurationTests.cs` (modifica)

**Interfaces:**
- Produces:
  - `HomeRowIds.Known: IReadOnlyList<string>`, `HomeRowIds.Normalize(IEnumerable<string?>) → IReadOnlyList<string>`, `HomeRowIds.Parse(string?) → IReadOnlyList<string>?`, `HomeRowIds.Serialize(IReadOnlyList<string>) → string`;
  - `IHomeLayoutStore { IReadOnlyList<string>? Rows { get; } void Save(IReadOnlyList<string>? rows); }`;
  - `PluginConfiguration.HomeRows: string?`;
  - `HomeLayoutDto(IReadOnlyList<string>? Rows)`, `HomeLayoutRequest { List<string?>? Rows }`;
  - `HomeController(IHomeLayoutStore)` con `GetLayout()` e `SetLayout(HomeLayoutRequest?)`.

- [ ] **Step 1: i test che falliscono**

`HomeRowIdsTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HomeRowIdsTests
{
    [Fact]
    public void TheKnownRowsAreTheTenOfTheSpecInTheDefaultOrder()
    {
        Assert.Equal(
            new[]
            {
                "resume", "nextUp", "requests", "latestMovies", "latestSeries",
                "becauseYouWatched", "continueSaga", "upcomingSeries", "upcomingMovies", "myList",
            },
            HomeRowIds.Known);
    }

    [Fact]
    public void NormalizeKeepsTheOrderAndDropsUnknownDuplicatesNullsAndOtherCases()
    {
        Assert.Equal(
            new[] { "myList", "resume", "upcomingSeries" },
            HomeRowIds.Normalize(["myList", "bogus", "resume", null, "myList", "Resume", " nextUp", "upcomingSeries"]));
        Assert.Empty(HomeRowIds.Normalize([]));
    }

    [Fact]
    public void StoredTextKeepsNullApartFromEmpty()
    {
        Assert.Null(HomeRowIds.Parse(null));
        Assert.Empty(HomeRowIds.Parse(string.Empty)!);
        Assert.Equal(new[] { "nextUp", "resume" }, HomeRowIds.Parse("nextUp, resume,,bogus,nextUp"));
        Assert.Equal("nextUp,resume", HomeRowIds.Serialize(["nextUp", "resume"]));
        Assert.Equal(string.Empty, HomeRowIds.Serialize([]));
    }
}
```

`HomeControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class HomeControllerTests
{
    private readonly FakeHomeLayoutStore _store = new();

    private HomeController Controller() => new(_store);

    [Fact]
    public void WithoutAnAdminLayoutRowsAreNull()
    {
        Assert.Null(Controller().GetLayout().Value!.Rows);
    }

    [Fact]
    public void TheAdminLayoutIsSavedCleanAndReadBack()
    {
        var saved = Controller().SetLayout(
            new HomeLayoutRequest { Rows = ["upcomingMovies", "bogus", "resume", "upcomingMovies", null] });

        Assert.Equal(new[] { "upcomingMovies", "resume" }, saved.Value!.Rows);
        Assert.Equal(new[] { "upcomingMovies", "resume" }, _store.Rows);
        Assert.Equal(new[] { "upcomingMovies", "resume" }, Controller().GetLayout().Value!.Rows);
    }

    [Fact]
    public void AnEmptyListTurnsEveryRowOffAndNullGoesBackToTheDefault()
    {
        Assert.Empty(Controller().SetLayout(new HomeLayoutRequest { Rows = [] }).Value!.Rows!);
        Assert.Empty(_store.Rows!);

        Assert.Null(Controller().SetLayout(new HomeLayoutRequest { Rows = null }).Value!.Rows);
        Assert.Null(_store.Rows);
        Assert.Equal(2, _store.Saves);
    }

    [Fact]
    public void AMissingBodyIsABadRequestAndSavesNothing()
    {
        Assert.IsType<BadRequestResult>(Controller().SetLayout(null).Result);
        Assert.Equal(0, _store.Saves);
    }

    [Fact]
    public void EveryoneReadsOnlyAdminsWrite()
    {
        var authorize = Assert.Single(typeof(HomeController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(HomeController).GetMethod(nameof(HomeController.GetLayout))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(
            Policies.RequiresElevation,
            Assert.Single(typeof(HomeController).GetMethod(nameof(HomeController.SetLayout))!
                .GetCustomAttributes<AuthorizeAttribute>()).Policy);
    }

    private sealed class FakeHomeLayoutStore : IHomeLayoutStore
    {
        public IReadOnlyList<string>? Rows { get; private set; }

        public int Saves { get; private set; }

        public void Save(IReadOnlyList<string>? rows)
        {
            Rows = rows;
            Saves++;
        }
    }
}
```

In `PluginConfigurationTests.cs` aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Home;` in cima e questi test con l'helper in fondo alla classe:

```csharp
    [Fact]
    public void TheHomeLayoutKeepsNeverSetApartFromAllOffThroughTheXml()
    {
        Assert.Null(new PluginConfiguration().HomeRows);
        Assert.Null(RoundTrip(new PluginConfiguration()).HomeRows);
        Assert.Equal(string.Empty, RoundTrip(new PluginConfiguration { HomeRows = string.Empty }).HomeRows);
        Assert.Equal("nextUp,resume", RoundTrip(new PluginConfiguration { HomeRows = "nextUp,resume" }).HomeRows);
    }

    [Fact]
    public void WithoutThePluginInstanceTheHomeLayoutIsTheDefaultAndCannotBeSaved()
    {
        var store = new PluginHomeLayoutStore();
        Assert.Null(store.Rows);
        Assert.Throws<InvalidOperationException>(() => store.Save(["resume"]));
    }

    // Come la salva e la rilegge Jellyfin.
    private static PluginConfiguration RoundTrip(PluginConfiguration config)
    {
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, config);
        using var reader = new StringReader(writer.ToString());
        return (PluginConfiguration)serializer.Deserialize(reader)!;
    }
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~HomeRowIdsTests|FullyQualifiedName~HomeControllerTests|FullyQualifiedName~PluginConfigurationTests"`
Expected: errore di compilazione (`HomeRowIds`, `HomeController`, `HomeRows` non esistono).

- [ ] **Step 3: il codice**

`Home/HomeRowIds.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Le righe della Home di WonderFlix (spec M §6.1): id stabili, nell'ordine
/// predefinito. Il plugin li conosce solo per scartare quelli sbagliati
/// nella Home dell'admin; cosa mostrano lo decide l'app.
/// </summary>
public static class HomeRowIds
{
    public static readonly IReadOnlyList<string> Known =
    [
        "resume",
        "nextUp",
        "requests",
        "latestMovies",
        "latestSeries",
        "becauseYouWatched",
        "continueSaga",
        "upcomingSeries",
        "upcomingMovies",
        "myList",
    ];

    /// <summary>Solo gli id conosciuti, scritti esatti (maiuscole comprese), senza doppioni, nell'ordine dato.</summary>
    public static IReadOnlyList<string> Normalize(IEnumerable<string?> rows) =>
        rows.OfType<string>()
            .Where(row => Known.Contains(row, StringComparer.Ordinal))
            .Distinct(StringComparer.Ordinal)
            .ToList();

    /// <summary>Come si salva nella configurazione: gli id separati da virgole.</summary>
    public static string Serialize(IReadOnlyList<string> rows) => string.Join(',', rows);

    /// <summary>Dal testo salvato: null se mai impostato, altrimenti l'elenco pulito (anche vuoto).</summary>
    public static IReadOnlyList<string>? Parse(string? stored) =>
        stored is null
            ? null
            : Normalize(stored.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
}
```

`Home/IHomeLayoutStore.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>La Home dell'admin (spec M §6.2), salvata nella configurazione del plugin.</summary>
public interface IHomeLayoutStore
{
    /// <summary>Gli id delle righe accese, in ordine; null se mai impostata (vale l'ordine predefinito dell'app).</summary>
    IReadOnlyList<string>? Rows { get; }

    /// <summary>Salva la Home dell'admin; null torna all'ordine predefinito.</summary>
    void Save(IReadOnlyList<string>? rows);
}
```

`Server/PluginHomeLayoutStore.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>La Home dell'admin nella configurazione del plugin (`HomeRows`).</summary>
public sealed class PluginHomeLayoutStore : IHomeLayoutStore
{
    // Un salvataggio alla volta: due admin che salvano insieme non si mescolano.
    private readonly Lock _lock = new();

    // Si legge ogni volta, come PluginSeerrSettings: salvando dalla
    // Dashboard Jellyfin sostituisce l'oggetto della configurazione. Senza
    // plugin (nei test) vale l'ordine predefinito.
    public IReadOnlyList<string>? Rows => HomeRowIds.Parse(Plugin.Instance?.Configuration.HomeRows);

    public void Save(IReadOnlyList<string>? rows)
    {
        var plugin = Plugin.Instance ?? throw new InvalidOperationException("Il plugin non è caricato.");
        lock (_lock)
        {
            plugin.Configuration.HomeRows = rows is null ? null : HomeRowIds.Serialize(rows);
            plugin.SaveConfiguration();
        }
    }
}
```

In `Configuration/PluginConfiguration.cs`, dopo `ContactReminderDays`:

```csharp

    /// <summary>
    /// La Home dell'admin (spec M §6.2): gli id delle righe accese, in ordine,
    /// separati da virgole. Null: mai impostata, vale l'ordine predefinito
    /// dell'app; vuota: tutte le righe spente. Una stringa e non un elenco:
    /// con XmlSerializer null e vuoto restano diversi.
    /// </summary>
    public string? HomeRows { get; set; }
```

`Protocol/HomeDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Risposta di GET e POST Home/Layout (spec M §7.2): la Home dell'admin.
/// Rows null (o assente: Jellyfin può non scrivere i null) se mai impostata.
/// </summary>
public sealed record HomeLayoutDto([property: JsonPropertyName("Rows")] IReadOnlyList<string>? Rows);

/// <summary>Corpo di POST Home/Layout: Rows null torna all'ordine predefinito, vuoto spegne tutte le righe.</summary>
public sealed class HomeLayoutRequest
{
    [JsonPropertyName("Rows")]
    public List<string?>? Rows { get; set; }
}
```

`Api/HomeController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// La Home dell'admin (spec M §7.2): ogni utente collegato la legge, solo
/// l'admin la scrive (dalla dashboard admin dell'app).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Home")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class HomeController(IHomeLayoutStore layout) : ControllerBase
{
    [HttpGet("Layout")]
    public ActionResult<HomeLayoutDto> GetLayout() => new HomeLayoutDto(layout.Rows);

    /// <summary>Salva la Home dell'admin, senza gli id sconosciuti e i doppioni; risponde con quella salvata.</summary>
    [HttpPost("Layout")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<HomeLayoutDto> SetLayout([FromBody] HomeLayoutRequest? request)
    {
        if (request is null)
        {
            return BadRequest();
        }

        layout.Save(request.Rows is null ? null : HomeRowIds.Normalize(request.Rows));
        return new HomeLayoutDto(layout.Rows);
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera verde (`dotnet test …Tests --configuration Release`, poi `dotnet build-server shutdown`), poi:

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): admin Home layout endpoint"
```

---

## Gruppo B — Sonarr e Radarr

### Task 2: impostazioni e client di Sonarr e Radarr

**Files:**
- Create: `Home/IArrSettings.cs`, `Server/PluginArrSettings.cs`, `Home/ArrJson.cs`, `Home/ArrException.cs`, `Home/IArrClient.cs`, `Home/ArrClient.cs`
- Modify: `Configuration/PluginConfiguration.cs`
- Test: `FakeArrSettings.cs`, `ArrClientTests.cs` (nuovi), `PluginConfigurationTests.cs` (modifica)

**Interfaces:**
- Consumes: niente dai task precedenti.
- Produces:
  - `enum ArrKind { Sonarr, Radarr }`;
  - `sealed record ArrEndpoint(string Url, string ApiKey)` con `bool IsConfigured` e `static ArrEndpoint None`;
  - `IArrSettings { ArrEndpoint Sonarr; ArrEndpoint Radarr; int SeriesDays; int MovieDays; }` e `settings.Endpoint(ArrKind)`;
  - `ArrLimits` (giorni);
  - modelli `ArrImage`, `SonarrSeries`, `SonarrEpisode`, `RadarrMovie`, `ArrStatus`;
  - `enum ArrError { NotConfigured, Unauthorized, Unreachable }`, `ArrException(ArrError, Exception?)` con `Error`, `UpcomingErrors` (`NotConfigured`, `Unauthorized`, `Unreachable`, `Code(ArrError)`);
  - `IArrClient` con `GetEpisodesAsync(from, to, ct) → IReadOnlyList<SonarrEpisode?>`, `GetMoviesAsync(from, to, ct) → IReadOnlyList<RadarrMovie?>`, `GetStatusAsync(ArrKind, ct) → ArrStatus`;
  - `ArrClient.HttpClientName = "WonderFlixArr"`, `ArrClient.DefaultTimeout`, `internal Timeout`.

- [ ] **Step 1: i test che falliscono**

`FakeArrSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Sonarr e Radarr configurati, da cambiare nel test.</summary>
internal sealed class FakeArrSettings : IArrSettings
{
    public ArrEndpoint Sonarr { get; set; } = new("https://arr.example/sonarr", "sonarr-key");

    public ArrEndpoint Radarr { get; set; } = new("https://arr.example/radarr", "radarr-key");

    public int SeriesDays { get; set; } = ArrLimits.DefaultSeriesDays;

    public int MovieDays { get; set; } = ArrLimits.DefaultMovieDays;
}
```

`ArrClientTests.cs`:

```csharp
using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class ArrClientTests
{
    private static readonly DateTimeOffset From = new(2026, 10, 10, 2, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset To = new(2026, 10, 17, 14, 0, 0, TimeSpan.Zero);

    // Una voce del calendario di Sonarr 4 come arriva dal server (2026-10-10), accorciata.
    private const string SonarrCalendar = """
        [{"seriesId":12,"tvdbId":10834101,"episodeFileId":0,"seasonNumber":1,"episodeNumber":5,"title":"Episode 5",
          "airDate":"2026-10-11","airDateUtc":"2026-10-12T01:00:00Z","runtime":0,"hasFile":false,"monitored":true,
          "unverifiedSceneNumbering":false,
          "series":{"title":"American Hostage","sortTitle":"american hostage","status":"continuing","ended":false,
            "network":"FX","airTime":"21:00",
            "images":[
              {"coverType":"banner","url":"/sonarr/MediaCover/12/banner.jpg","remoteUrl":"https://artworks.thetvdb.com/b.jpg"},
              {"coverType":"poster","url":"/sonarr/MediaCover/12/poster.jpg","remoteUrl":"https://artworks.thetvdb.com/p.jpg"},
              {"coverType":"fanart","url":"/sonarr/MediaCover/12/fanart.jpg","remoteUrl":"https://artworks.thetvdb.com/f.jpg"}],
            "seasons":[{"seasonNumber":1,"monitored":true}],"year":2026,"path":"/media/tv/American Hostage",
            "tvdbId":462907,"tvRageId":0,"tvMazeId":0,"tmdbId":239618,"imdbId":"tt1234567","id":12}}]
        """;

    // Una voce del calendario di Radarr 6, accorciata.
    private const string RadarrCalendar = """
        [{"title":"Hope","originalTitle":"Hope","year":2026,"tmdbId":1058424,"imdbId":"tt0000001",
          "inCinemas":"2026-07-15T00:00:00Z","digitalRelease":"2026-10-13T00:00:00Z","hasFile":false,"monitored":true,
          "isAvailable":true,
          "images":[
            {"coverType":"poster","url":"/radarr/MediaCover/5/poster.jpg","remoteUrl":"https://image.tmdb.org/t/p/original/p.jpg"},
            {"coverType":"fanart","url":"/radarr/MediaCover/5/fanart.jpg","remoteUrl":"https://image.tmdb.org/t/p/original/f.jpg"}],
          "id":5}]
        """;

    private readonly FakeSeerrHttp _http = new();
    private readonly FakeArrSettings _settings = new();
    private readonly RecordingLogger<ArrClient> _logger = new();

    private ArrClient Client(TimeSpan? timeout = null) =>
        new(_http, _settings, _logger) { Timeout = timeout ?? ArrClient.DefaultTimeout };

    private void Answer(HttpStatusCode status, string json) =>
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(status, json));

    [Fact]
    public async Task TheSonarrCalendarAsksForTheRangeWithTheSeriesAndTheKey()
    {
        Answer(HttpStatusCode.OK, SonarrCalendar);

        var episodes = await Client().GetEpisodesAsync(From, To, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Get, seen.Method);
        Assert.Equal(
            "https://arr.example/sonarr/api/v3/calendar?start=2026-10-10T02%3A00%3A00Z&end=2026-10-17T14%3A00%3A00Z"
            + "&includeSeries=true&unmonitored=false",
            seen.Uri.OriginalString);
        Assert.Equal("sonarr-key", seen.ApiKey);
        Assert.Equal(ArrClient.HttpClientName, _http.LastClientName);

        var episode = Assert.Single(episodes)!;
        Assert.Equal(12, episode.SeriesId);
        Assert.Equal(1, episode.SeasonNumber);
        Assert.Equal(5, episode.EpisodeNumber);
        Assert.Equal("Episode 5", episode.Title);
        Assert.Equal(new DateTimeOffset(2026, 10, 12, 1, 0, 0, TimeSpan.Zero), episode.AirDateUtc);
        Assert.False(episode.HasFile);
        var series = episode.Series!;
        Assert.Equal("American Hostage", series.Title);
        Assert.Equal(462907, series.TvdbId);
        Assert.Equal(239618, series.TmdbId);
        Assert.Equal("tt1234567", series.ImdbId);
        Assert.Equal(
            new[] { "https://artworks.thetvdb.com/b.jpg", "https://artworks.thetvdb.com/p.jpg", "https://artworks.thetvdb.com/f.jpg" },
            series.Images!.Select(image => image!.RemoteUrl));
    }

    [Fact]
    public async Task TheRadarrCalendarAsksOnlyForTheRange()
    {
        Answer(HttpStatusCode.OK, RadarrCalendar);

        var movies = await Client().GetMoviesAsync(From, To, CancellationToken.None);

        var seen = Assert.Single(_http.Requests);
        Assert.Equal(
            "https://arr.example/radarr/api/v3/calendar?start=2026-10-10T02%3A00%3A00Z&end=2026-10-17T14%3A00%3A00Z&unmonitored=false",
            seen.Uri.OriginalString);
        Assert.Equal("radarr-key", seen.ApiKey);
        var movie = Assert.Single(movies)!;
        Assert.Equal("Hope", movie.Title);
        Assert.Equal(2026, movie.Year);
        Assert.Equal(1058424, movie.TmdbId);
        Assert.Equal(new DateTimeOffset(2026, 10, 13, 0, 0, 0, TimeSpan.Zero), movie.DigitalRelease);
        Assert.False(movie.HasFile);
        Assert.Equal("https://image.tmdb.org/t/p/original/p.jpg", movie.Images![0]!.RemoteUrl);
    }

    [Fact]
    public async Task StatusGivesTheVersionOfEachService()
    {
        _http.Respond = (request, _) => Task.FromResult(FakeSeerrHttp.Json(
            HttpStatusCode.OK,
            request.RequestUri!.AbsolutePath.StartsWith("/sonarr", StringComparison.Ordinal)
                ? """{"appName":"Sonarr","version":"4.0.20.3014"}"""
                : """{"appName":"Radarr","version":"6.4.4.10685"}"""));

        Assert.Equal("4.0.20.3014", (await Client().GetStatusAsync(ArrKind.Sonarr, CancellationToken.None)).Version);
        Assert.Equal("6.4.4.10685", (await Client().GetStatusAsync(ArrKind.Radarr, CancellationToken.None)).Version);
        Assert.Equal("https://arr.example/sonarr/api/v3/system/status", _http.Requests[0].Uri.OriginalString);
        Assert.Equal("sonarr-key", _http.Requests[0].ApiKey);
        Assert.Equal("https://arr.example/radarr/api/v3/system/status", _http.Requests[1].Uri.OriginalString);
        Assert.Equal("radarr-key", _http.Requests[1].ApiKey);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, ArrError.Unauthorized)]
    [InlineData(HttpStatusCode.Forbidden, ArrError.Unauthorized)]
    [InlineData(HttpStatusCode.NotFound, ArrError.Unreachable)]
    [InlineData(HttpStatusCode.Found, ArrError.Unreachable)]
    [InlineData(HttpStatusCode.InternalServerError, ArrError.Unreachable)]
    public async Task RefusedKeysAreUnauthorizedOtherAnswersUnreachable(HttpStatusCode status, ArrError expected)
    {
        Answer(status, "{}");

        var error = await Assert.ThrowsAsync<ArrException>(() => Client().GetEpisodesAsync(From, To, CancellationToken.None));

        Assert.Equal(expected, error.Error);
    }

    [Fact]
    public async Task NetworkErrorsTimeoutsHtmlAndNullAreUnreachable()
    {
        async Task<ArrError> ErrorOf(ArrClient client) =>
            (await Assert.ThrowsAsync<ArrException>(() => client.GetMoviesAsync(From, To, CancellationToken.None))).Error;

        _http.Respond = (_, _) => throw new HttpRequestException("rete");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));

        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "[]");
        };
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client(TimeSpan.FromMilliseconds(50))));

        // Una pagina di login invece del JSON (indirizzo senza l'UrlBase).
        Answer(HttpStatusCode.OK, "<html>");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));

        Answer(HttpStatusCode.OK, "null");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));

        _settings.Radarr = new ArrEndpoint("radarr-senza-schema", "radarr-key");
        Assert.Equal(ArrError.Unreachable, await ErrorOf(Client()));
    }

    [Fact]
    public async Task NotConfiguredSendsNothing()
    {
        _settings.Sonarr = ArrEndpoint.None;

        var error = await Assert.ThrowsAsync<ArrException>(() => Client().GetEpisodesAsync(From, To, CancellationToken.None));

        Assert.Equal(ArrError.NotConfigured, error.Error);
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task AKeyThatCannotBeAHeaderIsUnreachableAndSendsNothing()
    {
        _settings.Sonarr = new ArrEndpoint("https://arr.example/sonarr", "chiave\r\nsegreta");

        var error = await Assert.ThrowsAsync<ArrException>(() => Client().GetStatusAsync(ArrKind.Sonarr, CancellationToken.None));

        Assert.Equal(ArrError.Unreachable, error.Error);
        Assert.Empty(_http.Requests);
        Assert.NotEmpty(_logger.Entries);
        Assert.DoesNotContain(_logger.Entries, e => e.Message.Contains("segreta", StringComparison.Ordinal));
    }

    [Fact]
    public async Task TheLogHasThePathButNeverTheKeyOrTheQuery()
    {
        Answer(HttpStatusCode.Unauthorized, "{}");

        await Assert.ThrowsAsync<ArrException>(() => Client().GetEpisodesAsync(From, To, CancellationToken.None));

        var entry = Assert.Single(_logger.Entries);
        Assert.Contains("calendar", entry.Message, StringComparison.Ordinal);
        Assert.Contains("Sonarr", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("sonarr-key", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("2026-10", entry.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ACancelledCallerGetsTheCancellation()
    {
        using var cancel = new CancellationTokenSource();
        _http.Respond = async (_, ct) =>
        {
            await cancel.CancelAsync();
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "[]");
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Client().GetEpisodesAsync(From, To, cancel.Token));
    }

    [Fact]
    public async Task NullsInsideTheListsDoNotBreakTheParsing()
    {
        Answer(
            HttpStatusCode.OK,
            """[null,{"seriesId":1,"seasonNumber":1,"episodeNumber":1,"airDateUtc":null,"hasFile":false,"series":{"title":"X","images":null}}]""");

        var episodes = await Client().GetEpisodesAsync(From, To, CancellationToken.None);

        Assert.Equal(2, episodes.Count);
        Assert.Null(episodes[0]);
        Assert.Null(episodes[1]!.AirDateUtc);
        Assert.Null(episodes[1]!.Series!.Images);
    }
}
```

In `PluginConfigurationTests.cs` aggiungi:

```csharp
    [Fact]
    public void SonarrAndRadarrAreEmptyByDefaultAndSurviveTheXml()
    {
        var empty = new PluginConfiguration();
        Assert.Equal(string.Empty, empty.SonarrUrl);
        Assert.Equal(string.Empty, empty.SonarrApiKey);
        Assert.Equal(string.Empty, empty.RadarrUrl);
        Assert.Equal(string.Empty, empty.RadarrApiKey);
        Assert.Equal(7, empty.UpcomingSeriesDays);
        Assert.Equal(90, empty.UpcomingMoviesDays);

        var read = RoundTrip(new PluginConfiguration
        {
            SonarrUrl = "https://host/sonarr",
            SonarrApiKey = "s",
            RadarrUrl = "https://host/radarr",
            RadarrApiKey = "r",
            UpcomingSeriesDays = 14,
            UpcomingMoviesDays = 30,
        });
        Assert.Equal("https://host/sonarr", read.SonarrUrl);
        Assert.Equal("s", read.SonarrApiKey);
        Assert.Equal("https://host/radarr", read.RadarrUrl);
        Assert.Equal("r", read.RadarrApiKey);
        Assert.Equal(14, read.UpcomingSeriesDays);
        Assert.Equal(30, read.UpcomingMoviesDays);
    }

    [Fact]
    public void WithoutThePluginInstanceSonarrAndRadarrAreOffWithTheDefaultDays()
    {
        var settings = new PluginArrSettings();
        Assert.False(settings.Sonarr.IsConfigured);
        Assert.False(settings.Radarr.IsConfigured);
        Assert.Equal(7, settings.SeriesDays);
        Assert.Equal(90, settings.MovieDays);
    }

    [Theory]
    [InlineData(" https://host/sonarr/ ", " key ", "https://host/sonarr", "key", true)]
    [InlineData("https://host/sonarr", "", "https://host/sonarr", "", false)]
    [InlineData("", "key", "", "key", false)]
    [InlineData(null, null, "", "", false)]
    public void AnEndpointIsTrimmedAndNeedsBothAddressAndKey(
        string? url, string? key, string expectedUrl, string expectedKey, bool configured)
    {
        var endpoint = PluginArrSettings.Endpoint(url, key);
        Assert.Equal(expectedUrl, endpoint.Url);
        Assert.Equal(expectedKey, endpoint.ApiKey);
        Assert.Equal(configured, endpoint.IsConfigured);
    }

    [Theory]
    [InlineData(0, 60, 1)]
    [InlineData(-5, 60, 1)]
    [InlineData(14, 60, 14)]
    [InlineData(1000, 60, 60)]
    [InlineData(1000, 365, 365)]
    public void DaysStayInTheirRange(int days, int max, int expected) =>
        Assert.Equal(expected, PluginArrSettings.ClampDays(days, max));

    [Fact]
    public void AnEndpointNeverPrintsItsKey()
    {
        Assert.DoesNotContain("segreta", new ArrEndpoint("https://host/sonarr", "segreta").ToString(), StringComparison.Ordinal);
    }
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~ArrClientTests|FullyQualifiedName~PluginConfigurationTests"`
Expected: errore di compilazione (`ArrClient`, `IArrSettings`, `SonarrUrl` non esistono).

- [ ] **Step 3: il codice**

In `Configuration/PluginConfiguration.cs`, dopo `HomeRows`:

```csharp

    /// <summary>
    /// Indirizzo di Sonarr visto dal server Jellyfin, con l'UrlBase, per
    /// esempio https://host/sonarr (spec M §7.1). Vuoto: niente "Serie in arrivo".
    /// </summary>
    public string SonarrUrl { get; set; } = string.Empty;

    /// <summary>Chiave API di Sonarr (Settings → General). Il file lo leggono solo gli admin.</summary>
    public string SonarrApiKey { get; set; } = string.Empty;

    /// <summary>Indirizzo di Radarr, come Sonarr. Vuoto: niente "Film in arrivo".</summary>
    public string RadarrUrl { get; set; } = string.Empty;

    /// <summary>Chiave API di Radarr. Il file lo leggono solo gli admin.</summary>
    public string RadarrApiKey { get; set; } = string.Empty;

    /// <summary>Giorni di "Serie in arrivo", da 1 a 60.</summary>
    public int UpcomingSeriesDays { get; set; } = 7;

    /// <summary>Giorni di "Film in arrivo" (uscita digitale), da 1 a 365.</summary>
    public int UpcomingMoviesDays { get; set; } = 90;
```

`Home/IArrSettings.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Sonarr (le serie) o Radarr (i film).</summary>
public enum ArrKind
{
    Sonarr,
    Radarr,
}

/// <summary>Indirizzo (senza "/" finale) e chiave di Sonarr o Radarr.</summary>
public sealed record ArrEndpoint(string Url, string ApiKey)
{
    public static readonly ArrEndpoint None = new(string.Empty, string.Empty);

    /// <summary>Indirizzo e chiave ci sono: la riga "in arrivo" è accesa.</summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Url) && !string.IsNullOrWhiteSpace(ApiKey);

    // Il ToString dei record stamperebbe la chiave.
    public override string ToString() => $"ArrEndpoint {{ Url = {Url} }}";
}

/// <summary>I giorni delle righe "in arrivo" (spec M §7.1).</summary>
public static class ArrLimits
{
    public const int MinDays = 1;

    public const int DefaultSeriesDays = 7;

    public const int MaxSeriesDays = 60;

    public const int DefaultMovieDays = 90;

    public const int MaxMovieDays = 365;
}

/// <summary>Il collegamento a Sonarr e Radarr. Va letto ogni volta: l'admin lo cambia dalla Dashboard.</summary>
public interface IArrSettings
{
    ArrEndpoint Sonarr { get; }

    ArrEndpoint Radarr { get; }

    /// <summary>Giorni di "Serie in arrivo", già fra 1 e 60.</summary>
    int SeriesDays { get; }

    /// <summary>Giorni di "Film in arrivo", già fra 1 e 365.</summary>
    int MovieDays { get; }
}

public static class ArrSettingsExtensions
{
    public static ArrEndpoint Endpoint(this IArrSettings settings, ArrKind kind) =>
        kind == ArrKind.Sonarr ? settings.Sonarr : settings.Radarr;
}
```

`Server/PluginArrSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Sonarr e Radarr dalla configurazione del plugin.</summary>
public sealed class PluginArrSettings : IArrSettings
{
    // Si legge ogni volta, come PluginSeerrSettings. Senza plugin (nei test)
    // niente indirizzi e i giorni predefiniti.
    private static PluginConfiguration? Config => Plugin.Instance?.Configuration;

    public ArrEndpoint Sonarr => Endpoint(Config?.SonarrUrl, Config?.SonarrApiKey);

    public ArrEndpoint Radarr => Endpoint(Config?.RadarrUrl, Config?.RadarrApiKey);

    public int SeriesDays => ClampDays(Config?.UpcomingSeriesDays ?? ArrLimits.DefaultSeriesDays, ArrLimits.MaxSeriesDays);

    public int MovieDays => ClampDays(Config?.UpcomingMoviesDays ?? ArrLimits.DefaultMovieDays, ArrLimits.MaxMovieDays);

    /// <summary>Senza spazi ai lati e senza "/" finale; null diventa vuoto.</summary>
    internal static ArrEndpoint Endpoint(string? url, string? key) =>
        new((url ?? string.Empty).Trim().TrimEnd('/'), (key ?? string.Empty).Trim());

    /// <summary>Un numero scritto male nella Dashboard (0, 1000) non allarga né spegne la riga.</summary>
    internal static int ClampDays(int days, int max) => Math.Clamp(days, ArrLimits.MinDays, max);
}
```

`Home/ArrJson.cs`:

```csharp
using System.Text.Json;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Il JSON di Sonarr e Radarr: nomi in camelCase, letti senza badare alle maiuscole.</summary>
internal static class ArrJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}

/// <summary>Un'immagine: remoteUrl è l'indirizzo pubblico (TVDB, TMDB, Fanart).</summary>
public sealed class ArrImage
{
    public string? CoverType { get; set; }

    public string? RemoteUrl { get; set; }
}

/// <summary>La serie di un episodio del calendario di Sonarr (includeSeries=true).</summary>
public sealed class SonarrSeries
{
    public string? Title { get; set; }

    public int TvdbId { get; set; }

    public int TmdbId { get; set; }

    public string? ImdbId { get; set; }

    // Un null esplicito nel JSON vince sull'inizializzatore: niente "= []".
    public List<ArrImage?>? Images { get; set; }
}

/// <summary>Un episodio del calendario di Sonarr.</summary>
public sealed class SonarrEpisode
{
    public int SeriesId { get; set; }

    public int SeasonNumber { get; set; }

    public int EpisodeNumber { get; set; }

    public string? Title { get; set; }

    /// <summary>Null per un episodio senza data.</summary>
    public DateTimeOffset? AirDateUtc { get; set; }

    public bool HasFile { get; set; }

    public SonarrSeries? Series { get; set; }
}

/// <summary>Un film del calendario di Radarr.</summary>
public sealed class RadarrMovie
{
    public string? Title { get; set; }

    public int Year { get; set; }

    public int TmdbId { get; set; }

    /// <summary>Null se Radarr non conosce l'uscita digitale.</summary>
    public DateTimeOffset? DigitalRelease { get; set; }

    public bool HasFile { get; set; }

    public List<ArrImage?>? Images { get; set; }
}

/// <summary>Risposta di system/status.</summary>
public sealed class ArrStatus
{
    public string? AppName { get; set; }

    public string? Version { get; set; }
}
```

`Home/ArrException.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Perché una chiamata a Sonarr o Radarr non è riuscita (spec M §7.4).</summary>
public enum ArrError
{
    /// <summary>Indirizzo o chiave mancanti nella configurazione.</summary>
    NotConfigured,

    /// <summary>Chiave rifiutata (401 o 403).</summary>
    Unauthorized,

    /// <summary>Irraggiungibile, lento, o con una risposta inattesa (404, 5xx, redirect, non JSON).</summary>
    Unreachable,
}

/// <summary>Errore di Sonarr o Radarr già classificato. Il messaggio non contiene mai la chiave.</summary>
public sealed class ArrException : Exception
{
    public ArrException(ArrError error, Exception? inner = null)
        : base("Sonarr/Radarr: " + error, inner)
    {
        Error = error;
    }

    public ArrError Error { get; }
}

/// <summary>I codici di "Error" nelle risposte di Upcoming (spec M §7.4; decisione 1 del piano 19a).</summary>
public static class UpcomingErrors
{
    public const string NotConfigured = "NotConfigured";

    public const string Unauthorized = "Unauthorized";

    public const string Unreachable = "Unreachable";

    public static string Code(ArrError error) => error switch
    {
        ArrError.NotConfigured => NotConfigured,
        ArrError.Unauthorized => Unauthorized,
        _ => Unreachable,
    };
}
```

`Home/IArrClient.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Sonarr e Radarr (spec M §3). Gli errori sono <see cref="ArrException"/>.</summary>
public interface IArrClient
{
    /// <summary>Gli episodi delle serie seguite, con la serie; gli elementi possono essere null.</summary>
    Task<IReadOnlyList<SonarrEpisode?>> GetEpisodesAsync(DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken);

    /// <summary>I film seguiti con una data nel periodo; gli elementi possono essere null.</summary>
    Task<IReadOnlyList<RadarrMovie?>> GetMoviesAsync(DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken);

    Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken);
}
```

`Home/ArrClient.cs`:

```csharp
using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// HTTP verso Sonarr e Radarr (API v3), con X-Api-Key su ogni chiamata.
/// Nel registro vanno solo servizio, percorso ed esito: mai la chiave, mai la query.
/// </summary>
public sealed class ArrClient(
    IHttpClientFactory httpClientFactory,
    IArrSettings settings,
    ILogger<ArrClient> logger) : IArrClient
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixArr";

    /// <summary>Attesa massima di una risposta (spec M §7.4).</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public async Task<IReadOnlyList<SonarrEpisode?>> GetEpisodesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken) =>
        await GetAsync<List<SonarrEpisode?>>(
            ArrKind.Sonarr,
            $"calendar?start={Iso(from)}&end={Iso(to)}&includeSeries=true&unmonitored=false",
            cancellationToken).ConfigureAwait(false);

    public async Task<IReadOnlyList<RadarrMovie?>> GetMoviesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken) =>
        await GetAsync<List<RadarrMovie?>>(
            ArrKind.Radarr,
            $"calendar?start={Iso(from)}&end={Iso(to)}&unmonitored=false",
            cancellationToken).ConfigureAwait(false);

    public Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken) =>
        GetAsync<ArrStatus>(kind, "system/status", cancellationToken);

    /// <summary>Data e ora UTC in ISO 8601, come le vuole il calendario, pronte per la query.</summary>
    internal static string Iso(DateTimeOffset value) =>
        Uri.EscapeDataString(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));

    /// <summary>401 e 403: chiave rifiutata; ogni altra risposta non riuscita: irraggiungibile.</summary>
    internal static ArrError Classify(int status) => status is 401 or 403 ? ArrError.Unauthorized : ArrError.Unreachable;

    private async Task<T> GetAsync<T>(ArrKind kind, string path, CancellationToken cancellationToken)
    {
        var endpoint = settings.Endpoint(kind);
        if (!endpoint.IsConfigured)
        {
            throw new ArrException(ArrError.NotConfigured);
        }

        var logPath = path.Split('?')[0];
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"{endpoint.Url}/api/v3/{path}");
            request.Headers.Add("X-Api-Key", endpoint.ApiKey);
            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, timeout.Token)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogInformation("{Service} GET {Path}: {Status}", kind, logPath, (int)response.StatusCode);
                throw new ArrException(Classify((int)response.StatusCode));
            }

            return await response.Content.ReadFromJsonAsync<T>(ArrJson.Options, timeout.Token).ConfigureAwait(false)
                ?? throw new JsonException("risposta vuota");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("{Service} GET {Path}: nessuna risposta in {Timeout}", kind, logPath, Timeout);
            throw new ArrException(ArrError.Unreachable);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or NotSupportedException
                                       or InvalidOperationException or FormatException)
        {
            // FormatException copre UriFormatException e Headers.Add con una chiave con a capo.
            // Questi messaggi non contengono né la chiave né la query.
            logger.LogWarning(
                "{Service} GET {Path} non riuscita: {Error} {Message}", kind, logPath, ex.GetType().Name, ex.Message);
            throw new ArrException(ArrError.Unreachable, ex);
        }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Se `TheLogHasThePathButNeverTheKeyOrTheQuery` trova più di una voce, controlla che il 401 scriva una sola riga (`LogInformation`) e nessun `LogWarning`.

- [ ] **Step 5: commit**

Suite intera verde, poi:

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): Sonarr and Radarr settings and client"
```

### Task 3: dal calendario alle uscite

**Files:**
- Create: `Home/ISeriesIndex.cs`, `Home/UpcomingBuilder.cs`
- Test: `UpcomingBuilderTests.cs`

**Interfaces:**
- Consumes (Task 2): `SonarrEpisode`, `SonarrSeries`, `RadarrMovie`, `ArrImage`.
- Produces:
  - `sealed record LibrarySeries(Guid Id, string? TvdbId, string? TmdbId, string? ImdbId)`;
  - `interface ISeriesIndex { IReadOnlyList<LibrarySeries> GetSeries(); }`;
  - `sealed record UpcomingEpisodeGroup(int SonarrSeriesId, string SeriesName, int SeasonNumber, int EpisodeNumber, int? LastEpisodeNumber, string? EpisodeTitle, DateTimeOffset AirDateUtc, int? TvdbId, int? TmdbId, string? ImdbId, string? PosterUrl, string? BackdropUrl)` con `IReadOnlyList<Guid> LibrarySeriesIds { get; init; }`;
  - `sealed record UpcomingMovie(string Title, int? Year, int TmdbId, DateTimeOffset DigitalRelease, string? PosterUrl, string? BackdropUrl)`;
  - `UpcomingBuilder.Episodes(IEnumerable<SonarrEpisode?>, DateTimeOffset from, DateTimeOffset to)`, `UpcomingBuilder.Movies(IEnumerable<RadarrMovie?>, from, to)`, `UpcomingBuilder.MatchSeries(IReadOnlyList<UpcomingEpisodeGroup>, IEnumerable<LibrarySeries>)`.

- [ ] **Step 1: i test che falliscono**

`UpcomingBuilderTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UpcomingBuilderTests
{
    private static readonly DateTimeOffset From = new(2026, 10, 10, 2, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset To = From.AddDays(7);
    private static readonly ArrImage Poster = new() { CoverType = "poster", RemoteUrl = "https://artworks.thetvdb.com/p.jpg" };
    private static readonly ArrImage Fanart = new() { CoverType = "fanart", RemoteUrl = "https://artworks.thetvdb.com/f.jpg" };

    private static SonarrSeries Bear() => new()
    {
        Title = "The Bear", TvdbId = 136311, TmdbId = 136315, ImdbId = "tt14452776", Images = [Poster, Fanart],
    };

    private static SonarrSeries Andor() => new()
    {
        Title = "Andor", TvdbId = 393189, TmdbId = 83867, ImdbId = "tt9253284", Images = [],
    };

    private static SonarrEpisode Episode(
        int seriesId, SonarrSeries? series, int season, int number, DateTimeOffset? at, bool hasFile = false, string? title = null) =>
        new()
        {
            SeriesId = seriesId,
            Series = series,
            SeasonNumber = season,
            EpisodeNumber = number,
            AirDateUtc = at,
            HasFile = hasFile,
            Title = title,
        };

    [Fact]
    public void OnlyEpisodesStillToDownloadInsideTheRangeWithANamedSeries()
    {
        var at = From.AddDays(1);
        var groups = UpcomingBuilder.Episodes(
        [
            Episode(1, Bear(), 1, 1, at, title: " Sistema "),
            Episode(1, Bear(), 1, 3, at.AddHours(1), hasFile: true),
            Episode(1, Bear(), 1, 4, From.AddMinutes(-1)),
            Episode(1, Bear(), 1, 5, To),
            Episode(1, Bear(), 1, 6, null),
            Episode(2, null, 1, 1, at),
            Episode(3, new SonarrSeries { Title = " " }, 1, 1, at),
            null,
        ], From, To);

        var only = Assert.Single(groups);
        Assert.Equal(1, only.SonarrSeriesId);
        Assert.Equal("The Bear", only.SeriesName);
        Assert.Equal(1, only.SeasonNumber);
        Assert.Equal(1, only.EpisodeNumber);
        Assert.Null(only.LastEpisodeNumber);
        Assert.Equal("Sistema", only.EpisodeTitle);
        Assert.Equal(at, only.AirDateUtc);
        Assert.Empty(only.LibrarySeriesIds);
    }

    [Fact]
    public void ConsecutiveEpisodesOutTogetherBecomeOneEntry()
    {
        var first = From.AddDays(1);
        var later = From.AddDays(2);
        var groups = UpcomingBuilder.Episodes(
        [
            Episode(1, Bear(), 1, 9, later),
            Episode(1, Bear(), 1, 6, first, title: "Sei"),
            Episode(2, Andor(), 1, 1, first, title: "Uno"),
            Episode(1, Bear(), 1, 8, first),
            Episode(1, Bear(), 2, 1, first),
            Episode(1, Bear(), 1, 5, first, title: "Cinque"),
        ], From, To);

        // E05 ed E06 escono insieme: una voce, senza titolo. E08 c'è un buco,
        // S02E01 è un'altra stagione, E09 esce un altro giorno: voci a sé.
        Assert.Equal(
            new (string, int, int, int?, string?, DateTimeOffset)[]
            {
                ("Andor", 1, 1, null, "Uno", first),
                ("The Bear", 1, 5, 6, null, first),
                ("The Bear", 1, 8, null, null, first),
                ("The Bear", 2, 1, null, null, first),
                ("The Bear", 1, 9, null, null, later),
            },
            groups.Select(g => (g.SeriesName, g.SeasonNumber, g.EpisodeNumber, g.LastEpisodeNumber, g.EpisodeTitle, g.AirDateUtc)));
    }

    [Fact]
    public void ExternalIdsAndOnlyPublicImageAddresses()
    {
        var shogun = new SonarrSeries
        {
            Title = "Shogun",
            TvdbId = 0,
            TmdbId = 0,
            ImdbId = " ",
            Images =
            [
                null,
                new ArrImage { CoverType = "Poster", RemoteUrl = "/sonarr/MediaCover/7/poster.jpg" },
                new ArrImage { CoverType = "poster", RemoteUrl = " https://image.tmdb.org/t/p/original/p.jpg " },
                new ArrImage { CoverType = "fanart", RemoteUrl = "ftp://example.com/f.jpg" },
                new ArrImage { CoverType = "banner", RemoteUrl = "https://example.com/b.jpg" },
            ],
        };

        var group = Assert.Single(UpcomingBuilder.Episodes([Episode(7, shogun, 1, 1, From.AddDays(1))], From, To));
        Assert.Null(group.TvdbId);
        Assert.Null(group.TmdbId);
        Assert.Null(group.ImdbId);
        Assert.Equal("https://image.tmdb.org/t/p/original/p.jpg", group.PosterUrl);
        Assert.Null(group.BackdropUrl);

        var bare = Assert.Single(UpcomingBuilder.Episodes(
            [Episode(8, new SonarrSeries { Title = "X", Images = null }, 1, 1, From.AddDays(1))], From, To));
        Assert.Null(bare.PosterUrl);
        Assert.Null(bare.BackdropUrl);

        var bear = Assert.Single(UpcomingBuilder.Episodes([Episode(1, Bear(), 1, 1, From.AddDays(1))], From, To));
        Assert.Equal(136311, bear.TvdbId);
        Assert.Equal(136315, bear.TmdbId);
        Assert.Equal("tt14452776", bear.ImdbId);
        Assert.Equal("https://artworks.thetvdb.com/p.jpg", bear.PosterUrl);
        Assert.Equal("https://artworks.thetvdb.com/f.jpg", bear.BackdropUrl);
    }

    [Fact]
    public void MoviesWithADigitalReleaseInTheRangeNotYetDownloaded()
    {
        var from = new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero);
        var to = from.AddDays(91);
        RadarrMovie Movie(string title, int tmdb, DateTimeOffset? digital, bool hasFile = false, int year = 2026) => new()
        {
            Title = title,
            TmdbId = tmdb,
            DigitalRelease = digital,
            HasFile = hasFile,
            Year = year,
            Images = [new ArrImage { CoverType = "poster", RemoteUrl = $"https://image.tmdb.org/t/p/original/{tmdb}.jpg" }],
        };

        var movies = UpcomingBuilder.Movies(
        [
            Movie("Odissea", 1368337, from.AddDays(38)),
            Movie("Hope", 1058424, from.AddDays(3), year: 0),
            Movie("Già uscito", 1564614, from.AddDays(-74)),
            Movie("Scaricato", 1, from.AddDays(5), hasFile: true),
            Movie("Solo al cinema", 2, null),
            Movie("Troppo tardi", 3, to),
            Movie("Senza TMDB", 0, from.AddDays(5)),
            Movie(" ", 4, from.AddDays(5)),
            Movie("Oggi", 5, from),
            null,
        ], from, to);

        Assert.Equal(new[] { "Oggi", "Hope", "Odissea" }, movies.Select(m => m.Title));
        var hope = movies[1];
        Assert.Null(hope.Year);
        Assert.Equal(1058424, hope.TmdbId);
        Assert.Equal(from.AddDays(3), hope.DigitalRelease);
        Assert.Equal("https://image.tmdb.org/t/p/original/1058424.jpg", hope.PosterUrl);
        Assert.Null(hope.BackdropUrl);
        Assert.Equal(2026, movies[2].Year);
    }

    [Fact]
    public void SeriesMatchTheLibraryByAnyExternalId()
    {
        var at = From.AddDays(1);
        var groups = UpcomingBuilder.Episodes(
        [
            Episode(1, Bear(), 1, 1, at),
            Episode(2, Andor(), 1, 1, at),
            Episode(3, new SonarrSeries { Title = "Nuova", TvdbId = 999, Images = [] }, 1, 1, at),
        ], From, To);
        var byTvdb = Guid.NewGuid();
        var byTmdb = Guid.NewGuid();
        var byImdb = Guid.NewGuid();

        var matched = UpcomingBuilder.MatchSeries(
            groups,
            [
                new LibrarySeries(byTvdb, "136311", null, null),
                new LibrarySeries(byTmdb, null, "136315", null),
                new LibrarySeries(byImdb, null, null, "TT9253284"),
                new LibrarySeries(Guid.NewGuid(), "1", "2", "tt0"),
            ]);

        // Due serie della libreria per The Bear (es. due librerie): restano tutte e due.
        Assert.Equal(new[] { byTvdb, byTmdb }, matched.Single(g => g.SeriesName == "The Bear").LibrarySeriesIds);
        Assert.Equal(new[] { byImdb }, matched.Single(g => g.SeriesName == "Andor").LibrarySeriesIds);
        Assert.Empty(matched.Single(g => g.SeriesName == "Nuova").LibrarySeriesIds);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~UpcomingBuilderTests"`
Expected: errore di compilazione (`UpcomingBuilder`, `LibrarySeries` non esistono).

- [ ] **Step 3: il codice**

`Home/ISeriesIndex.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Una serie di Jellyfin con i suoi id esterni (null quelli che non ha).</summary>
public sealed record LibrarySeries(Guid Id, string? TvdbId, string? TmdbId, string? ImdbId);

/// <summary>Le serie della libreria, per riconoscere quelle di Sonarr (adattatore di ILibraryManager).</summary>
public interface ISeriesIndex
{
    /// <summary>Tutte le serie, di tutte le librerie, senza guardare l'utente.</summary>
    IReadOnlyList<LibrarySeries> GetSeries();
}
```

`Home/UpcomingBuilder.cs`:

```csharp
using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>
/// Un episodio, o un blocco di episodi usciti insieme, prima di guardare chi
/// chiede (spec M §7.3). LastEpisodeNumber c'è solo per un blocco, e allora
/// EpisodeTitle no.
/// </summary>
public sealed record UpcomingEpisodeGroup(
    int SonarrSeriesId,
    string SeriesName,
    int SeasonNumber,
    int EpisodeNumber,
    int? LastEpisodeNumber,
    string? EpisodeTitle,
    DateTimeOffset AirDateUtc,
    int? TvdbId,
    int? TmdbId,
    string? ImdbId,
    string? PosterUrl,
    string? BackdropUrl)
{
    /// <summary>Le serie di Jellyfin con gli stessi id esterni; per ogni utente vale la prima che vede.</summary>
    public IReadOnlyList<Guid> LibrarySeriesIds { get; init; } = [];
}

/// <summary>Un film in arrivo (spec M §7.3).</summary>
public sealed record UpcomingMovie(
    string Title,
    int? Year,
    int TmdbId,
    DateTimeOffset DigitalRelease,
    string? PosterUrl,
    string? BackdropUrl);

/// <summary>
/// Dai calendari di Sonarr e Radarr alle uscite della Home: filtri, blocchi
/// di episodi, immagini pubbliche e serie della libreria. I periodi vanno da
/// <c>from</c> compreso a <c>to</c> escluso (decisione 3 del piano 19a).
/// </summary>
public static class UpcomingBuilder
{
    private const string PosterType = "poster";
    private const string BackdropType = "fanart";

    /// <summary>
    /// Gli episodi non ancora scaricati del periodo, con una serie che ha un
    /// nome. Episodi della stessa serie e stagione, con numeri consecutivi e
    /// lo stesso airDateUtc (le uscite in blocco), diventano una voce sola.
    /// In ordine di uscita, poi di serie.
    /// </summary>
    public static IReadOnlyList<UpcomingEpisodeGroup> Episodes(
        IEnumerable<SonarrEpisode?> episodes, DateTimeOffset from, DateTimeOffset to)
    {
        var groups = new List<UpcomingEpisodeGroup>();
        UpcomingEpisodeGroup? current = null;
        foreach (var episode in episodes.OfType<SonarrEpisode>()
                     .Where(e => !e.HasFile
                                 && !string.IsNullOrWhiteSpace(e.Series?.Title)
                                 && e.AirDateUtc is { } at && at >= from && at < to)
                     .OrderBy(e => e.AirDateUtc)
                     .ThenBy(e => e.SeriesId)
                     .ThenBy(e => e.SeasonNumber)
                     .ThenBy(e => e.EpisodeNumber))
        {
            var at = episode.AirDateUtc!.Value;
            if (current is not null
                && current.SonarrSeriesId == episode.SeriesId
                && current.SeasonNumber == episode.SeasonNumber
                && current.AirDateUtc == at
                && (current.LastEpisodeNumber ?? current.EpisodeNumber) + 1 == episode.EpisodeNumber)
            {
                current = current with { LastEpisodeNumber = episode.EpisodeNumber, EpisodeTitle = null };
                groups[^1] = current;
                continue;
            }

            var series = episode.Series!;
            current = new UpcomingEpisodeGroup(
                episode.SeriesId,
                series.Title!.Trim(),
                episode.SeasonNumber,
                episode.EpisodeNumber,
                null,
                Text(episode.Title),
                at,
                Positive(series.TvdbId),
                Positive(series.TmdbId),
                Text(series.ImdbId),
                Image(series.Images, PosterType),
                Image(series.Images, BackdropType));
            groups.Add(current);
        }

        return groups
            .OrderBy(g => g.AirDateUtc)
            .ThenBy(g => g.SeriesName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(g => g.SeasonNumber)
            .ThenBy(g => g.EpisodeNumber)
            .ToList();
    }

    /// <summary>
    /// I film non ancora scaricati con l'uscita digitale nel periodo, un id
    /// TMDB e un titolo; in ordine di uscita, poi di titolo.
    /// </summary>
    public static IReadOnlyList<UpcomingMovie> Movies(IEnumerable<RadarrMovie?> movies, DateTimeOffset from, DateTimeOffset to) =>
        movies.OfType<RadarrMovie>()
            .Where(m => !m.HasFile
                        && m.TmdbId > 0
                        && !string.IsNullOrWhiteSpace(m.Title)
                        && m.DigitalRelease is { } at && at >= from && at < to)
            .Select(m => new UpcomingMovie(
                m.Title!.Trim(),
                Positive(m.Year),
                m.TmdbId,
                m.DigitalRelease!.Value,
                Image(m.Images, PosterType),
                Image(m.Images, BackdropType)))
            .OrderBy(m => m.DigitalRelease)
            .ThenBy(m => m.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();

    /// <summary>Ogni voce con le serie della libreria che hanno lo stesso id TVDB, TMDB o IMDb.</summary>
    public static IReadOnlyList<UpcomingEpisodeGroup> MatchSeries(
        IReadOnlyList<UpcomingEpisodeGroup> groups, IEnumerable<LibrarySeries> library)
    {
        var all = library.ToList();
        return groups
            .Select(group => group with
            {
                LibrarySeriesIds = all.Where(series => Matches(group, series)).Select(series => series.Id).Distinct().ToList(),
            })
            .ToList();
    }

    /// <summary>
    /// Il remoteUrl del tipo chiesto, solo se è un indirizzo http(s) completo:
    /// mai i percorsi locali di Sonarr (/MediaCover/…), che vogliono la chiave.
    /// </summary>
    internal static string? Image(IEnumerable<ArrImage?>? images, string coverType) =>
        images?.OfType<ArrImage>()
            .Where(image => string.Equals(image.CoverType, coverType, StringComparison.OrdinalIgnoreCase))
            .Select(image => image.RemoteUrl?.Trim())
            .FirstOrDefault(url => Uri.TryCreate(url, UriKind.Absolute, out var uri)
                                   && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp));

    private static bool Matches(UpcomingEpisodeGroup group, LibrarySeries series) =>
        (group.TvdbId is { } tvdb && Same(series.TvdbId, tvdb.ToString(CultureInfo.InvariantCulture)))
        || (group.TmdbId is { } tmdb && Same(series.TmdbId, tmdb.ToString(CultureInfo.InvariantCulture)))
        || (group.ImdbId is { } imdb && Same(series.ImdbId, imdb));

    private static bool Same(string? value, string expected) =>
        value is not null && string.Equals(value.Trim(), expected, StringComparison.OrdinalIgnoreCase);

    private static int? Positive(int value) => value > 0 ? value : null;

    private static string? Text(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera verde, poi:

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): build the upcoming episodes and movies"
```

### Task 4: le serie della libreria

**Files:**
- Create: `Server/JellyfinSeriesIndex.cs`
- Test: `SeriesIndexTests.cs`

**Interfaces:**
- Consumes (Task 3): `ISeriesIndex`, `LibrarySeries`.
- Produces: `JellyfinSeriesIndex(ILibraryManager) : ISeriesIndex`.

- [ ] **Step 1: il test che fallisce**

`SeriesIndexTests.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeriesIndexTests
{
    [Fact]
    public void TheIndexReadsEverySeriesWithItsExternalIds()
    {
        var bear = new Series { Id = Guid.NewGuid(), Name = "The Bear" };
        bear.ProviderIds["Tvdb"] = "136311";
        bear.ProviderIds["Tmdb"] = " 136315 ";
        bear.ProviderIds["Imdb"] = "tt14452776";
        var bare = new Series { Id = Guid.NewGuid(), Name = "Senza id" };
        bare.ProviderIds["Tvdb"] = " ";
        var (library, stub) = InterfaceStub<ILibraryManager>.Create();
        InternalItemsQuery? asked = null;
        stub.Handlers["GetItemList"] = args =>
        {
            asked = (InternalItemsQuery)args[0]!;
            return new List<BaseItem> { bear, bare };
        };

        var series = new JellyfinSeriesIndex(library).GetSeries();

        Assert.Equal(new[] { BaseItemKind.Series }, asked!.IncludeItemTypes);
        Assert.False(asked.IsVirtualItem);
        Assert.Equal(
            new[]
            {
                new LibrarySeries(bear.Id, "136311", "136315", "tt14452776"),
                new LibrarySeries(bare.Id, null, null, null),
            },
            series);
    }
}
```

- [ ] **Step 2: il test fallisce**

Run: `dotnet test … --filter "FullyQualifiedName~SeriesIndexTests"`
Expected: errore di compilazione (`JellyfinSeriesIndex` non esiste).

- [ ] **Step 3: il codice**

`Server/JellyfinSeriesIndex.cs`:

```csharp
using Jellyfin.Data.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Le serie di Jellyfin con gli id TVDB, TMDB e IMDb, per riconoscere quelle
/// di Sonarr (spec M §7.3). Una sola query senza utente: chi vede cosa lo
/// decide poi ILibraryAccess.CanSee, per ogni utente.
/// </summary>
public sealed class JellyfinSeriesIndex(ILibraryManager libraryManager) : ISeriesIndex
{
    public IReadOnlyList<LibrarySeries> GetSeries() =>
        libraryManager.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.Series],
                IsVirtualItem = false,
            })
            .Select(item => new LibrarySeries(
                item.Id,
                ProviderId(item, MetadataProvider.Tvdb),
                ProviderId(item, MetadataProvider.Tmdb),
                ProviderId(item, MetadataProvider.Imdb)))
            .ToList();

    private static string? ProviderId(BaseItem item, MetadataProvider provider) =>
        item.TryGetProviderId(provider, out var value) && !string.IsNullOrWhiteSpace(value) ? value.Trim() : null;
}
```

- [ ] **Step 4: il test passa**

Run: lo stesso comando dello Step 2.
Expected: PASS. Se il gestore dello stub non viene chiamato (nessuna corrispondenza per nome), controlla in `Calls` il nome del metodo usato e adegua il gestore.

- [ ] **Step 5: commit**

Suite intera verde, poi:

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): index the library series by external ids"
```

### Task 5: le uscite per ogni utente, con la cache

**Files:**
- Create: `Protocol/UpcomingDtos.cs`, `Home/UpcomingService.cs`
- Test: `FakeArrClient.cs`, `FakeSeriesIndex.cs`, `UpcomingServiceTests.cs`

**Interfaces:**
- Consumes: `IArrClient`, `IArrSettings`, `ArrEndpoint`, `ArrKind`, `ArrException`, `UpcomingErrors` (Task 2); `UpcomingBuilder`, `UpcomingEpisodeGroup`, `UpcomingMovie`, `ISeriesIndex`, `LibrarySeries` (Task 3); `ILibraryAccess.CanSee(Guid, Guid)` (Hub).
- Produces:
  - DTO `UpcomingEpisodeDto`, `UpcomingSeriesResponse(Items, Error)`, `UpcomingMovieDto`, `UpcomingMoviesResponse(Items, Error)`, `ArrTestResult(Configured, Ok, Version, Error)`, `UpcomingTestResponse(Sonarr, Radarr)`;
  - `UpcomingService(IArrClient, IArrSettings, ISeriesIndex, ILibraryAccess, TimeProvider, ILogger<UpcomingService>)` con `GetSeriesAsync(Guid userId, CancellationToken)`, `GetMoviesAsync(CancellationToken)`, `TestAsync(CancellationToken)`, `CacheFor`, `ErrorCacheFor`, `SeriesLookBack`.

- [ ] **Step 1: i test che falliscono**

`FakeArrClient.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Sonarr e Radarr finti: rispondono con i gestori e contano le chiamate.</summary>
internal sealed class FakeArrClient : IArrClient
{
    private readonly Lock _lock = new();

    public Func<DateTimeOffset, DateTimeOffset, Task<IReadOnlyList<SonarrEpisode?>>> Episodes { get; set; } =
        (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>([]);

    public Func<DateTimeOffset, DateTimeOffset, Task<IReadOnlyList<RadarrMovie?>>> Movies { get; set; } =
        (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);

    public Func<ArrKind, Task<ArrStatus>> Status { get; set; } =
        kind => Task.FromResult(new ArrStatus { AppName = kind.ToString(), Version = "1.0" });

    public List<(DateTimeOffset From, DateTimeOffset To)> EpisodeCalls { get; } = [];

    public List<(DateTimeOffset From, DateTimeOffset To)> MovieCalls { get; } = [];

    public List<ArrKind> StatusCalls { get; } = [];

    public Task<IReadOnlyList<SonarrEpisode?>> GetEpisodesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            EpisodeCalls.Add((from, to));
        }

        return Episodes(from, to);
    }

    public Task<IReadOnlyList<RadarrMovie?>> GetMoviesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            MovieCalls.Add((from, to));
        }

        return Movies(from, to);
    }

    public Task<ArrStatus> GetStatusAsync(ArrKind kind, CancellationToken cancellationToken)
    {
        lock (_lock)
        {
            StatusCalls.Add(kind);
        }

        return Status(kind);
    }
}
```

`FakeSeriesIndex.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Serie della libreria in memoria; Fails la fa lanciare, come un errore di Jellyfin.</summary>
internal sealed class FakeSeriesIndex : ISeriesIndex
{
    public List<LibrarySeries> Series { get; } = [];

    public bool Fails { get; set; }

    public IReadOnlyList<LibrarySeries> GetSeries() =>
        Fails ? throw new InvalidOperationException("libreria non disponibile") : Series.ToList();
}
```

`UpcomingServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UpcomingServiceTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 10, 14, 30, 0, TimeSpan.Zero);

    private readonly FakeTimeProvider _time = new(Now);
    private readonly FakeArrClient _client = new();
    private readonly FakeArrSettings _settings = new();
    private readonly FakeSeriesIndex _index = new();
    private readonly FakeServer _server = new();
    private readonly RecordingLogger<UpcomingService> _logger = new();

    private UpcomingService Service() => new(_client, _settings, _index, _server, _time, _logger);

    private static SonarrEpisode Episode(DateTimeOffset at) => new()
    {
        SeriesId = 1,
        SeasonNumber = 2,
        EpisodeNumber = 5,
        Title = "Cinque",
        AirDateUtc = at,
        Series = new SonarrSeries
        {
            Title = "The Bear",
            TvdbId = 136311,
            TmdbId = 136315,
            ImdbId = "tt14452776",
            Images =
            [
                new ArrImage { CoverType = "poster", RemoteUrl = "https://artworks.thetvdb.com/p.jpg" },
                new ArrImage { CoverType = "fanart", RemoteUrl = "https://artworks.thetvdb.com/f.jpg" },
            ],
        },
    };

    private void EpisodesAre(params SonarrEpisode?[] episodes) =>
        _client.Episodes = (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(episodes);

    [Fact]
    public async Task NotConfiguredAnswersWithoutCallingSonarrOrRadarr()
    {
        _settings.Sonarr = ArrEndpoint.None;
        _settings.Radarr = ArrEndpoint.None;
        var service = Service();

        var series = await service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        var movies = await service.GetMoviesAsync(CancellationToken.None);

        Assert.Empty(series.Items);
        Assert.Equal("NotConfigured", series.Error);
        Assert.Empty(movies.Items);
        Assert.Equal("NotConfigured", movies.Error);
        Assert.Empty(_client.EpisodeCalls);
        Assert.Empty(_client.MovieCalls);
    }

    [Fact]
    public async Task SeriesAskFromTwelveHoursAgoToTheConfiguredDays()
    {
        _settings.SeriesDays = 10;

        await Service().GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);

        var (from, to) = Assert.Single(_client.EpisodeCalls);
        Assert.Equal(Now.AddHours(-12), from);
        Assert.Equal(Now.AddDays(10), to);
    }

    [Fact]
    public async Task MoviesAskFromTodayToTheEndOfTheLastDay()
    {
        await Service().GetMoviesAsync(CancellationToken.None);

        var (from, to) = Assert.Single(_client.MovieCalls);
        Assert.Equal(new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero), from);
        // 90 giorni compreso l'ultimo: fino alla mezzanotte del 9 gennaio.
        Assert.Equal(new DateTimeOffset(2027, 1, 9, 0, 0, 0, TimeSpan.Zero), to);
    }

    [Fact]
    public async Task EachUserGetsTheSeriesIdOnlyWhenTheySeeIt()
    {
        var mario = _server.AddUser("mario");
        var luigi = _server.AddUser("luigi");
        var hidden = Guid.NewGuid();
        var visible = Guid.NewGuid();
        _index.Series.Add(new LibrarySeries(hidden, "136311", null, null));
        _index.Series.Add(new LibrarySeries(visible, null, "136315", null));
        _server.Unseen.Add((mario.Id, hidden));
        _server.Unseen.Add((luigi.Id, hidden));
        _server.Unseen.Add((luigi.Id, visible));
        EpisodesAre(Episode(Now.AddDays(1)));
        var service = Service();

        var forMario = Assert.Single((await service.GetSeriesAsync(mario.Id, CancellationToken.None)).Items);
        var forLuigi = Assert.Single((await service.GetSeriesAsync(luigi.Id, CancellationToken.None)).Items);
        var forApiKey = Assert.Single((await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Items);

        Assert.Equal(visible.ToString("N"), forMario.JellyfinSeriesId);
        Assert.Null(forLuigi.JellyfinSeriesId);
        Assert.Null(forApiKey.JellyfinSeriesId);
        Assert.Equal("The Bear", forMario.SeriesName);
        Assert.Equal(2, forMario.SeasonNumber);
        Assert.Equal(5, forMario.EpisodeNumber);
        Assert.Null(forMario.LastEpisodeNumber);
        Assert.Equal("Cinque", forMario.EpisodeTitle);
        Assert.Equal(Now.AddDays(1), forMario.AirDateUtc);
        Assert.Equal(136311, forMario.TvdbId);
        Assert.Equal(136315, forMario.TmdbId);
        Assert.Equal("https://artworks.thetvdb.com/p.jpg", forMario.PosterUrl);
        Assert.Equal("https://artworks.thetvdb.com/f.jpg", forMario.BackdropUrl);
        // Una sola lettura di Sonarr per tre utenti.
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task TheLibraryFailingLeavesTheEpisodesWithoutTheSeries()
    {
        var mario = _server.AddUser("mario");
        _index.Series.Add(new LibrarySeries(Guid.NewGuid(), "136311", null, null));
        EpisodesAre(Episode(Now.AddDays(1)));
        _server.LibraryFails = true;

        var item = Assert.Single((await Service().GetSeriesAsync(mario.Id, CancellationToken.None)).Items);
        Assert.Null(item.JellyfinSeriesId);

        // Un servizio nuovo (cache vuota) con l'elenco delle serie che non si legge.
        _server.LibraryFails = false;
        _index.Fails = true;
        var again = Assert.Single((await Service().GetSeriesAsync(mario.Id, CancellationToken.None)).Items);
        Assert.Null(again.JellyfinSeriesId);
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public async Task AnswersStayCachedForFifteenMinutes()
    {
        EpisodesAre(Episode(Now.AddDays(1)));
        var service = Service();

        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        _time.Advance(TimeSpan.FromMinutes(15) - TimeSpan.FromSeconds(1));
        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Single(_client.EpisodeCalls);

        _time.Advance(TimeSpan.FromSeconds(2));
        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Equal(2, _client.EpisodeCalls.Count);
    }

    [Fact]
    public async Task ChangedSettingsDoNotUseTheOldCache()
    {
        _client.Episodes = (_, _) => throw new ArrException(ArrError.Unreachable);
        var service = Service();

        Assert.Equal("Unreachable", (await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Error);

        // L'admin corregge l'indirizzo: la richiesta dopo non aspetta che l'errore scada.
        EpisodesAre(Episode(Now.AddDays(1)));
        _settings.Sonarr = _settings.Sonarr with { Url = "https://arr.example/sonarr-giusto" };
        var fixedAnswer = await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Null(fixedAnswer.Error);
        Assert.Single(fixedAnswer.Items);

        _settings.SeriesDays = 14;
        await service.GetSeriesAsync(Guid.Empty, CancellationToken.None);
        Assert.Equal(3, _client.EpisodeCalls.Count);
    }

    [Fact]
    public async Task ErrorsAreKeptForAMinute()
    {
        _client.Movies = (_, _) => throw new ArrException(ArrError.Unauthorized);
        var service = Service();

        var refused = await service.GetMoviesAsync(CancellationToken.None);
        Assert.Empty(refused.Items);
        Assert.Equal("Unauthorized", refused.Error);

        _time.Advance(TimeSpan.FromSeconds(59));
        await service.GetMoviesAsync(CancellationToken.None);
        Assert.Single(_client.MovieCalls);

        _time.Advance(TimeSpan.FromSeconds(2));
        _client.Movies = (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>([]);
        Assert.Null((await service.GetMoviesAsync(CancellationToken.None)).Error);
        Assert.Equal(2, _client.MovieCalls.Count);
    }

    [Fact]
    public async Task AnUnexpectedFailureIsUnreachableAndRetriedAfterAMinute()
    {
        _client.Episodes = (_, _) => throw new InvalidOperationException("guasto");
        var service = Service();

        Assert.Equal("Unreachable", (await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Error);
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning && e.Exception is InvalidOperationException);

        _time.Advance(TimeSpan.FromSeconds(61));
        EpisodesAre(Episode(Now.AddDays(1)));
        Assert.Null((await service.GetSeriesAsync(Guid.Empty, CancellationToken.None)).Error);
        Assert.Equal(2, _client.EpisodeCalls.Count);
    }

    [Fact]
    public async Task UsersAskingTogetherShareOneRead()
    {
        var gate = new TaskCompletionSource<IReadOnlyList<SonarrEpisode?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _client.Episodes = (_, _) => gate.Task;
        var service = Service();

        var first = service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        var second = service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        gate.SetResult([Episode(Now.AddDays(1))]);

        Assert.Single((await first).Items);
        Assert.Single((await second).Items);
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task ACancelledCallerDoesNotStopTheReadForTheOthers()
    {
        var gate = new TaskCompletionSource<IReadOnlyList<SonarrEpisode?>>(TaskCreationOptions.RunContinuationsAsynchronously);
        _client.Episodes = (_, _) => gate.Task;
        var service = Service();
        using var cancel = new CancellationTokenSource();

        var leaving = service.GetSeriesAsync(Guid.NewGuid(), cancel.Token);
        var staying = service.GetSeriesAsync(Guid.NewGuid(), CancellationToken.None);
        await cancel.CancelAsync();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => leaving);

        gate.SetResult([Episode(Now.AddDays(1))]);
        Assert.Single((await staying).Items);
        Assert.Single(_client.EpisodeCalls);
    }

    [Fact]
    public async Task MoviesBecomeDtos()
    {
        _client.Movies = (_, _) => Task.FromResult<IReadOnlyList<RadarrMovie?>>(
        [
            new RadarrMovie
            {
                Title = "Hope",
                Year = 2026,
                TmdbId = 1058424,
                DigitalRelease = new DateTimeOffset(2026, 10, 13, 0, 0, 0, TimeSpan.Zero),
                Images = [new ArrImage { CoverType = "poster", RemoteUrl = "https://image.tmdb.org/t/p/original/p.jpg" }],
            },
        ]);

        var answer = await Service().GetMoviesAsync(CancellationToken.None);

        Assert.Null(answer.Error);
        var movie = Assert.Single(answer.Items);
        Assert.Equal("Hope", movie.Title);
        Assert.Equal(2026, movie.Year);
        Assert.Equal(1058424, movie.TmdbId);
        Assert.Equal(new DateTimeOffset(2026, 10, 13, 0, 0, 0, TimeSpan.Zero), movie.DigitalRelease);
        Assert.Equal("https://image.tmdb.org/t/p/original/p.jpg", movie.PosterUrl);
        Assert.Null(movie.BackdropUrl);
    }

    [Fact]
    public async Task TheTestAsksEveryConfiguredServiceWithoutTheCache()
    {
        _client.Status = kind => kind == ArrKind.Sonarr
            ? Task.FromResult(new ArrStatus { AppName = "Sonarr", Version = "4.0.20.3014" })
            : throw new ArrException(ArrError.Unauthorized);
        var service = Service();

        var result = await service.TestAsync(CancellationToken.None);

        Assert.Equal(new ArrTestResult(true, true, "4.0.20.3014", null), result.Sonarr);
        Assert.Equal(new ArrTestResult(true, false, null, "Unauthorized"), result.Radarr);

        _settings.Radarr = ArrEndpoint.None;
        var again = await service.TestAsync(CancellationToken.None);
        Assert.Equal(new ArrTestResult(false, false, null, "NotConfigured"), again.Radarr);
        // Due prove di Sonarr, una sola di Radarr (la seconda volta non è configurato).
        Assert.Equal(3, _client.StatusCalls.Count);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~UpcomingServiceTests"`
Expected: errore di compilazione (`UpcomingService`, `ArrTestResult` non esistono).

- [ ] **Step 3: il codice**

`Protocol/UpcomingDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>
/// Un episodio, o un blocco di episodi, di GET Upcoming/Series (spec M §7.3).
/// I campi null possono mancare: Jellyfin può non scrivere i null.
/// </summary>
public sealed record UpcomingEpisodeDto(
    [property: JsonPropertyName("SeriesName")] string SeriesName,
    [property: JsonPropertyName("SeasonNumber")] int SeasonNumber,
    [property: JsonPropertyName("EpisodeNumber")] int EpisodeNumber,
    [property: JsonPropertyName("LastEpisodeNumber")] int? LastEpisodeNumber,
    [property: JsonPropertyName("EpisodeTitle")] string? EpisodeTitle,
    [property: JsonPropertyName("AirDateUtc")] DateTimeOffset AirDateUtc,
    [property: JsonPropertyName("TvdbId")] int? TvdbId,
    [property: JsonPropertyName("TmdbId")] int? TmdbId,
    [property: JsonPropertyName("PosterUrl")] string? PosterUrl,
    [property: JsonPropertyName("BackdropUrl")] string? BackdropUrl,
    [property: JsonPropertyName("JellyfinSeriesId")] string? JellyfinSeriesId);

/// <summary>Risposta di GET Upcoming/Series: con un errore Items è vuoto (sempre 200).</summary>
public sealed record UpcomingSeriesResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<UpcomingEpisodeDto> Items,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>Un film di GET Upcoming/Movies.</summary>
public sealed record UpcomingMovieDto(
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("DigitalRelease")] DateTimeOffset DigitalRelease,
    [property: JsonPropertyName("PosterUrl")] string? PosterUrl,
    [property: JsonPropertyName("BackdropUrl")] string? BackdropUrl);

/// <summary>Risposta di GET Upcoming/Movies: con un errore Items è vuoto (sempre 200).</summary>
public sealed record UpcomingMoviesResponse(
    [property: JsonPropertyName("Items")] IReadOnlyList<UpcomingMovieDto> Items,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>L'esito della prova di un servizio.</summary>
public sealed record ArrTestResult(
    [property: JsonPropertyName("Configured")] bool Configured,
    [property: JsonPropertyName("Ok")] bool Ok,
    [property: JsonPropertyName("Version")] string? Version,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>Risposta di POST Upcoming/Test (spec M §7.5).</summary>
public sealed record UpcomingTestResponse(
    [property: JsonPropertyName("Sonarr")] ArrTestResult Sonarr,
    [property: JsonPropertyName("Radarr")] ArrTestResult Radarr);
```

`Home/UpcomingService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Home;

/// <summary>Una lettura di Sonarr o Radarr: le uscite, oppure un codice d'errore e nessuna uscita.</summary>
internal sealed record Fetched<T>(IReadOnlyList<T> Items, string? Error);

/// <summary>
/// Le uscite in arrivo per la Home (spec M §7.3, §7.4). Le risposte di
/// Sonarr e Radarr, già filtrate, valgono per tutti e restano in memoria 15
/// minuti (un errore 1 minuto); la serie di Jellyfin si sceglie per ogni
/// utente, tra quelle che vede. La cache è legata alle impostazioni: se
/// l'admin cambia indirizzo, chiave o giorni, la richiesta dopo rilegge.
/// </summary>
public sealed class UpcomingService(
    IArrClient client,
    IArrSettings settings,
    ISeriesIndex seriesIndex,
    ILibraryAccess library,
    TimeProvider time,
    ILogger<UpcomingService> logger)
{
    /// <summary>Quanto vale una risposta riuscita.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(15);

    /// <summary>Quanto vale un errore: abbastanza per non insistere su un servizio fermo.</summary>
    public static readonly TimeSpan ErrorCacheFor = TimeSpan.FromMinutes(1);

    /// <summary>Gli episodi usciti da poco e non ancora scaricati restano (quelli di stanotte).</summary>
    public static readonly TimeSpan SeriesLookBack = TimeSpan.FromHours(12);

    private readonly Lock _lock = new();
    private readonly Slot<UpcomingEpisodeGroup> _series = new();
    private readonly Slot<UpcomingMovie> _movies = new();

    public async Task<UpcomingSeriesResponse> GetSeriesAsync(Guid userId, CancellationToken cancellationToken)
    {
        var endpoint = settings.Sonarr;
        if (!endpoint.IsConfigured)
        {
            return new UpcomingSeriesResponse([], UpcomingErrors.NotConfigured);
        }

        var days = settings.SeriesDays;
        var fetched = await Cached(_series, Key(endpoint, days), () => FetchSeriesAsync(days))
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
        return new UpcomingSeriesResponse(fetched.Items.Select(group => ToDto(group, userId)).ToList(), fetched.Error);
    }

    public async Task<UpcomingMoviesResponse> GetMoviesAsync(CancellationToken cancellationToken)
    {
        var endpoint = settings.Radarr;
        if (!endpoint.IsConfigured)
        {
            return new UpcomingMoviesResponse([], UpcomingErrors.NotConfigured);
        }

        var days = settings.MovieDays;
        var fetched = await Cached(_movies, Key(endpoint, days), () => FetchMoviesAsync(days))
            .WaitAsync(cancellationToken)
            .ConfigureAwait(false);
        return new UpcomingMoviesResponse(
            fetched.Items
                .Select(movie => new UpcomingMovieDto(
                    movie.Title, movie.Year, movie.TmdbId, movie.DigitalRelease, movie.PosterUrl, movie.BackdropUrl))
                .ToList(),
            fetched.Error);
    }

    /// <summary>"Prova collegamento" (spec M §7.5): lo stato di Sonarr e di Radarr insieme, senza cache.</summary>
    public async Task<UpcomingTestResponse> TestAsync(CancellationToken cancellationToken)
    {
        var sonarr = TestOneAsync(ArrKind.Sonarr, cancellationToken);
        var radarr = TestOneAsync(ArrKind.Radarr, cancellationToken);
        return new UpcomingTestResponse(await sonarr.ConfigureAwait(false), await radarr.ConfigureAwait(false));
    }

    // Le impostazioni che decidono la risposta; la chiave resta solo in memoria, mai nel log.
    private static string Key(ArrEndpoint endpoint, int days) => $"{endpoint.Url}\n{endpoint.ApiKey}\n{days}";

    private async Task<ArrTestResult> TestOneAsync(ArrKind kind, CancellationToken cancellationToken)
    {
        if (!settings.Endpoint(kind).IsConfigured)
        {
            return new ArrTestResult(false, false, null, UpcomingErrors.NotConfigured);
        }

        try
        {
            var status = await client.GetStatusAsync(kind, cancellationToken).ConfigureAwait(false);
            return new ArrTestResult(true, true, status.Version, null);
        }
        catch (ArrException ex)
        {
            return new ArrTestResult(true, false, null, UpcomingErrors.Code(ex.Error));
        }
    }

    private async Task<Fetched<UpcomingEpisodeGroup>> FetchSeriesAsync(int days)
    {
        var now = time.GetUtcNow();
        var from = now - SeriesLookBack;
        var to = now.AddDays(days);
        try
        {
            var episodes = await client.GetEpisodesAsync(from, to, CancellationToken.None).ConfigureAwait(false);
            return new(UpcomingBuilder.MatchSeries(UpcomingBuilder.Episodes(episodes, from, to), ReadLibrarySeries()), null);
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Serie in arrivo: Sonarr non ha risposto ({Error})", ex.Error);
            return new([], UpcomingErrors.Code(ex.Error));
        }
    }

    private async Task<Fetched<UpcomingMovie>> FetchMoviesAsync(int days)
    {
        // Da oggi (mezzanotte UTC) alla fine del giorno "days": Radarr dà le date a mezzanotte.
        var from = new DateTimeOffset(time.GetUtcNow().UtcDateTime.Date, TimeSpan.Zero);
        var to = from.AddDays(days + 1);
        try
        {
            var movies = await client.GetMoviesAsync(from, to, CancellationToken.None).ConfigureAwait(false);
            return new(UpcomingBuilder.Movies(movies, from, to), null);
        }
        catch (ArrException ex)
        {
            logger.LogWarning("Film in arrivo: Radarr non ha risposto ({Error})", ex.Error);
            return new([], UpcomingErrors.Code(ex.Error));
        }
    }

    // Senza la libreria le uscite restano, solo senza il collegamento alla serie.
    private IReadOnlyList<LibrarySeries> ReadLibrarySeries()
    {
        try
        {
            return seriesIndex.GetSeries();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Serie in arrivo: le serie della libreria non si leggono");
            return [];
        }
    }

    private UpcomingEpisodeDto ToDto(UpcomingEpisodeGroup group, Guid userId)
    {
        var seriesId = group.LibrarySeriesIds.FirstOrDefault(id => CanSee(userId, id));
        return new UpcomingEpisodeDto(
            group.SeriesName,
            group.SeasonNumber,
            group.EpisodeNumber,
            group.LastEpisodeNumber,
            group.EpisodeTitle,
            group.AirDateUtc,
            group.TvdbId,
            group.TmdbId,
            group.PosterUrl,
            group.BackdropUrl,
            seriesId == Guid.Empty ? null : seriesId.ToString("N"));
    }

    // Un errore della libreria toglie solo il collegamento alla serie, non l'uscita.
    private bool CanSee(Guid userId, Guid seriesId)
    {
        try
        {
            return library.CanSee(userId, seriesId);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Serie in arrivo: visibilità della serie non letta");
            return false;
        }
    }

    /// <summary>
    /// La lettura in cache se è per le stesse impostazioni e non è scaduta
    /// (una in corso vale sempre); altrimenti una nuova, una sola anche con
    /// più richieste insieme. La lettura non usa il token di chi chiede.
    /// </summary>
    private Task<Fetched<T>> Cached<T>(Slot<T> slot, string key, Func<Task<Fetched<T>>> fetch)
    {
        lock (_lock)
        {
            if (slot.Read is { } read && slot.Key == key && (!read.IsCompleted || time.GetUtcNow() < slot.ExpiresAt))
            {
                return read;
            }

            slot.Key = key;
            slot.ExpiresAt = DateTimeOffset.MaxValue;
            // Su un altro thread: la fine della lettura rientra in _lock per la scadenza.
            slot.Read = Task.Run(() => FetchAndExpireAsync(slot, key, fetch));
            return slot.Read;
        }
    }

    private async Task<Fetched<T>> FetchAndExpireAsync<T>(Slot<T> slot, string key, Func<Task<Fetched<T>>> fetch)
    {
        Fetched<T> result;
        try
        {
            result = await fetch().ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            // Un errore inatteso non resta in cache per sempre: vale come un servizio irraggiungibile.
            logger.LogWarning(ex, "Uscite in arrivo non lette");
            result = new([], UpcomingErrors.Unreachable);
        }

        lock (_lock)
        {
            // Se intanto le impostazioni sono cambiate, lo slot è già di un'altra lettura.
            if (slot.Key == key)
            {
                slot.ExpiresAt = time.GetUtcNow() + (result.Error is null ? CacheFor : ErrorCacheFor);
            }
        }

        return result;
    }

    private sealed class Slot<T>
    {
        public string? Key { get; set; }

        public Task<Fetched<T>>? Read { get; set; }

        public DateTimeOffset ExpiresAt { get; set; }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Ripeti il gruppo tre volte di fila (`for` in PowerShell) per escludere test instabili: devono passare tutte e tre.

- [ ] **Step 5: commit**

Suite intera verde, poi:

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): upcoming service with cache"
```

### Task 6: endpoint e funzioni in Info

**Files:**
- Create: `Api/UpcomingController.cs`
- Modify: `Protocol/WatchPartyProtocol.cs`, `Api/InfoController.cs`
- Test: `UpcomingControllerTests.cs` (nuovo), `InfoControllerTests.cs` (modifica)

**Interfaces:**
- Consumes: `UpcomingService` e DTO (Task 5); `IArrSettings`, `ArrEndpoint` (Task 2).
- Produces:
  - `UpcomingController(IAuthorizationContext, UpcomingService)` con `GetSeries()`, `GetMovies()`, `Test()`;
  - `WatchPartyProtocol.Features` con `"home"`, `UpcomingSeriesFeature = "upcomingSeries"`, `UpcomingMoviesFeature = "upcomingMovies"`, `FeaturesWith(bool requests, bool upcomingSeries, bool upcomingMovies)`;
  - `InfoController(ISeerrSettings, IArrSettings)`.

- [ ] **Step 1: i test che falliscono**

`UpcomingControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UpcomingControllerTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 10, 14, 30, 0, TimeSpan.Zero);

    private readonly User _mario = new("mario", "provider", "reset");
    private readonly FakeArrClient _client = new();
    private readonly FakeSeriesIndex _index = new();

    private UpcomingController Controller()
    {
        var (library, stub) = InterfaceStub<ILibraryAccess>.Create();
        stub.Handlers["CanSee"] = args => (Guid)args[0]! == _mario.Id;
        var service = new UpcomingService(
            _client, new FakeArrSettings(), _index, library, new FakeTimeProvider(Now), new RecordingLogger<UpcomingService>());
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new UpcomingController(new FakeAuthorizationContext(auth), service)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task SeriesAreReadForTheCaller()
    {
        var bear = Guid.NewGuid();
        _index.Series.Add(new LibrarySeries(bear, "136311", null, null));
        _client.Episodes = (_, _) => Task.FromResult<IReadOnlyList<SonarrEpisode?>>(
        [
            new SonarrEpisode
            {
                SeriesId = 1,
                SeasonNumber = 1,
                EpisodeNumber = 1,
                AirDateUtc = Now.AddDays(1),
                Series = new SonarrSeries { Title = "The Bear", TvdbId = 136311 },
            },
        ]);

        var answer = (await Controller().GetSeries()).Value!;

        Assert.Equal(bear.ToString("N"), Assert.Single(answer.Items).JellyfinSeriesId);
    }

    [Fact]
    public async Task MoviesAndTheTest()
    {
        Assert.Null((await Controller().GetMovies()).Value!.Error);

        var test = (await Controller().Test()).Value!;
        Assert.True(test.Sonarr.Ok);
        Assert.True(test.Radarr.Ok);
    }

    [Fact]
    public void EveryoneReadsOnlyAdminsTest()
    {
        var authorize = Assert.Single(typeof(UpcomingController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(UpcomingController).GetMethod(nameof(UpcomingController.GetSeries))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Empty(typeof(UpcomingController).GetMethod(nameof(UpcomingController.GetMovies))!
            .GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(
            Policies.RequiresElevation,
            Assert.Single(typeof(UpcomingController).GetMethod(nameof(UpcomingController.Test))!
                .GetCustomAttributes<AuthorizeAttribute>()).Policy);
    }
}
```

In `InfoControllerTests.cs` sostituisci i primi due test con questi (aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Home;`):

```csharp
    private static FakeArrSettings NoArr() => new() { Sonarr = ArrEndpoint.None, Radarr = ArrEndpoint.None };

    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = new InfoController(new FakeSeerrSettings { Url = string.Empty }, NoArr()).GetInfo().Value!;
        Assert.Equal("1.6.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(
            new[] { "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home" },
            info.Features);
    }

    [Fact]
    public void RequestsAndUpcomingAppearOnlyWhenConfigured()
    {
        Assert.Equal(
            new[]
            {
                "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home",
                "requests", "upcomingSeries", "upcomingMovies",
            },
            new InfoController(new FakeSeerrSettings(), new FakeArrSettings()).GetInfo().Value!.Features);

        var features = new InfoController(
                new FakeSeerrSettings { ApiKey = " " }, new FakeArrSettings { Sonarr = ArrEndpoint.None })
            .GetInfo().Value!.Features;
        Assert.DoesNotContain("requests", features);
        Assert.DoesNotContain("upcomingSeries", features);
        Assert.Contains("upcomingMovies", features);
    }
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~UpcomingControllerTests|FullyQualifiedName~InfoControllerTests"`
Expected: errore di compilazione (`UpcomingController` non esiste, `InfoController` ha un solo parametro).

- [ ] **Step 3: il codice**

`Api/UpcomingController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le uscite in arrivo per la Home (spec M §7.3): ogni utente collegato le
/// legge, sempre con 200 (un problema è in "Error"); la prova del
/// collegamento è solo per gli admin.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Upcoming")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class UpcomingController(
    IAuthorizationContext authorizationContext,
    UpcomingService upcoming) : ControllerBase
{
    /// <summary>Gli episodi in arrivo, con la serie di Jellyfin solo se chi chiama la vede.</summary>
    [HttpGet("Series")]
    public async Task<ActionResult<UpcomingSeriesResponse>> GetSeries()
    {
        var caller = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        return await upcoming.GetSeriesAsync(caller, HttpContext.RequestAborted).ConfigureAwait(false);
    }

    [HttpGet("Movies")]
    public async Task<ActionResult<UpcomingMoviesResponse>> GetMovies() =>
        await upcoming.GetMoviesAsync(HttpContext.RequestAborted).ConfigureAwait(false);

    /// <summary>"Prova collegamento" della dashboard admin e della pagina del plugin.</summary>
    [HttpPost("Test")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<UpcomingTestResponse>> Test() =>
        await upcoming.TestAsync(HttpContext.RequestAborted).ConfigureAwait(false);
}
```

In `Protocol/WatchPartyProtocol.cs` sostituisci `Features`, `RequestsFeature` e `FeaturesWith` con:

```csharp
    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7, spec
    /// G §6.3, spec H §7, spec K §7.1 e §7.2, spec L §7.8, spec M §7.6). Il
    /// protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features =
        ["friends", "parties", "inbox", "queue", "collections", "avatars", "account", "home"];

    /// <summary>Le richieste con Seerr (spec I §7.1): in GET Info solo con Seerr configurato.</summary>
    public const string RequestsFeature = "requests";

    /// <summary>"Serie in arrivo" (spec M §7.6): solo con Sonarr configurato.</summary>
    public const string UpcomingSeriesFeature = "upcomingSeries";

    /// <summary>"Film in arrivo" (spec M §7.6): solo con Radarr configurato.</summary>
    public const string UpcomingMoviesFeature = "upcomingMovies";

    /// <summary>Le funzioni di GET Info, con quelle che dipendono dalla configurazione.</summary>
    public static IReadOnlyList<string> FeaturesWith(bool requests, bool upcomingSeries, bool upcomingMovies)
    {
        var features = new List<string>(Features);
        if (requests)
        {
            features.Add(RequestsFeature);
        }

        if (upcomingSeries)
        {
            features.Add(UpcomingSeriesFeature);
        }

        if (upcomingMovies)
        {
            features.Add(UpcomingMoviesFeature);
        }

        return features;
    }
```

In `Api/InfoController.cs`: aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Home;`, nel commento della classe la frase "upcomingSeries e upcomingMovies ci sono solo con Sonarr e Radarr configurati (spec M §7.6).", e cambia costruttore e risposta:

```csharp
public class InfoController(ISeerrSettings seerr, IArrSettings arr) : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin, del protocollo e funzioni in più.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(
            PluginVersion,
            WatchPartyProtocol.Version,
            WatchPartyProtocol.FeaturesWith(seerr.IsConfigured(), arr.Sonarr.IsConfigured, arr.Radarr.IsConfigured));
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS (`InfoReportsVersionProtocolAndFeatures` resta su `"1.6.0"`: la versione cambia nel Task 7).

- [ ] **Step 5: commit**

Suite intera verde, poi:

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): upcoming endpoints and features in Info"
```

---

## Gruppo C — montaggio

### Task 7: servizi, versione 1.7.0 e pagina della Dashboard

**Files:**
- Modify: `PluginServiceRegistrator.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `Configuration/configPage.html`, `../meta.template.json`, `../README.md`
- Test: `ServiceRegistrationTests.cs`, `InfoControllerTests.cs`, `PluginPagesTests.cs` (modifiche)

**Interfaces:**
- Consumes: tutte le classi dei Task 1–6.
- Produces: il plugin 1.7.0 montato, la sezione "Sonarr and Radarr" della Dashboard.

- [ ] **Step 1: i test che falliscono**

In `ServiceRegistrationTests.AllServicesResolve`, prima del conteggio dei servizi in background:

```csharp
        // Home su misura (spec M).
        Assert.IsType<Server.PluginHomeLayoutStore>(provider.GetRequiredService<Home.IHomeLayoutStore>());
        Assert.IsType<Server.PluginArrSettings>(provider.GetRequiredService<Home.IArrSettings>());
        Assert.IsType<Home.ArrClient>(provider.GetRequiredService<Home.IArrClient>());
        Assert.IsType<Server.JellyfinSeriesIndex>(provider.GetRequiredService<Home.ISeriesIndex>());
        Assert.Same(provider.GetRequiredService<Home.UpcomingService>(), provider.GetRequiredService<Home.UpcomingService>());
```

In `InfoControllerTests.InfoReportsVersionProtocolAndFeatures`: `Assert.Equal("1.7.0", info.Version);`.

In `PluginPagesTests.TheDashboardPageIsEmbeddedAndSendsAnnouncements`, prima del controllo finale sull'id del plugin:

```csharp
        // Sonarr e Radarr (spec M §7.1), con le protezioni del recupero:
        // niente Salva prima di aver letto, numeri obbligatori, chiavi non offerte dal browser.
        Assert.Contains("SonarrUrl", html);
        Assert.Contains("SonarrApiKey", html);
        Assert.Contains("RadarrUrl", html);
        Assert.Contains("RadarrApiKey", html);
        Assert.Contains("UpcomingSeriesDays", html);
        Assert.Contains("UpcomingMoviesDays", html);
        Assert.Contains("WonderFlixWatchParty/Upcoming/Test", html);
        Assert.Contains("arrLoaded", html);
        Assert.Contains("numberIn(arrFields.UpcomingSeriesDays, config.UpcomingSeriesDays)", html);
        Assert.Contains("numberIn(arrFields.UpcomingMoviesDays, config.UpcomingMoviesDays)", html);
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixSonarrApiKey"));
        Assert.Contains("autocomplete=\"new-password\"", TagWithId(html, "WonderFlixRadarrApiKey"));
        Assert.Contains(" required", TagWithId(html, "WonderFlixUpcomingSeriesDays"));
        Assert.Contains(" required", TagWithId(html, "WonderFlixUpcomingMoviesDays"));
        Assert.Contains("aria-live=\"polite\"", TagWithId(html, "WonderFlixArrResult"));
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~InfoControllerTests|FullyQualifiedName~PluginPagesTests"`
Expected: FAIL (servizi non registrati, versione 1.6.0, testi mancanti).

- [ ] **Step 3: il codice**

In `PluginServiceRegistrator.cs` aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Home;` e, dopo il blocco del recupero della password (prima di `ILibraryTitles`):

```csharp
        // Home su misura (spec M): la Home dell'admin e le uscite di Sonarr e Radarr.
        serviceCollection.AddSingleton<IHomeLayoutStore, PluginHomeLayoutStore>();
        serviceCollection.AddSingleton<IArrSettings, PluginArrSettings>();
        // La chiave API non va nei log del client HTTP e non segue un redirect.
        serviceCollection.AddHttpClient(ArrClient.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false })
            .RedactLoggedHeaders(["X-Api-Key"]);
        serviceCollection.AddSingleton<IArrClient, ArrClient>();
        serviceCollection.AddSingleton<ISeriesIndex, JellyfinSeriesIndex>();
        serviceCollection.AddSingleton<UpcomingService>();
```

Nel csproj: `<Version>1.7.0</Version>`.

In `Plugin.cs`: nel commento della classe aggiungi "e, dalla 1.7.0, la Home su misura (spec M: la Home dell'admin e le uscite di Sonarr e Radarr)"; `Description` diventa:

```csharp
    public override string Description =>
        "Names, chat, reactions, friends, notifications, password recovery and the Home rows (upcoming from Sonarr and Radarr) for WonderFlix.";
```

In `Configuration/configPage.html`, dopo il `</form>` di `WonderFlixSeerrForm` e prima di `<form id="WonderFlixRecoveryForm">`:

```html
                <form id="WonderFlixArrForm">
                    <div class="verticalSection">
                        <h3 class="sectionTitle">Sonarr and Radarr</h3>
                        <div class="fieldDescription">
                            WonderFlix shows the upcoming episodes (Sonarr) and movies (Radarr) on its Home. The API keys stay on the server.
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="url" id="WonderFlixSonarrUrl" label="Sonarr address" placeholder="https://example.com/sonarr" />
                            <div class="fieldDescription">As seen from the Jellyfin server, with the URL base. Empty: no upcoming episodes.</div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="password" id="WonderFlixSonarrApiKey" label="Sonarr API key" autocomplete="new-password" />
                            <div class="fieldDescription">Sonarr → Settings → General → API Key.</div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="url" id="WonderFlixRadarrUrl" label="Radarr address" placeholder="https://example.com/radarr" />
                            <div class="fieldDescription">Empty: no upcoming movies.</div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="password" id="WonderFlixRadarrApiKey" label="Radarr API key" autocomplete="new-password" />
                            <div class="fieldDescription">Radarr → Settings → General → API Key.</div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="number" id="WonderFlixUpcomingSeriesDays" label="Upcoming episodes for (days)" min="1" max="60" required />
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="number" id="WonderFlixUpcomingMoviesDays" label="Upcoming movies for (days)" min="1" max="365" required />
                            <div class="fieldDescription">Movies count by their digital release date.</div>
                        </div>
                        <button is="emby-button" type="submit" class="raised button-submit block emby-button">
                            <span>Save</span>
                        </button>
                        <button is="emby-button" id="WonderFlixArrTest" type="button" class="raised block emby-button">
                            <span>Test connection</span>
                        </button>
                        <div class="fieldDescription">Save first: the test uses the saved settings.</div>
                        <div id="WonderFlixArrResult" class="fieldDescription" aria-live="polite"></div>
                    </div>
                </form>
```

Nello script, subito prima della chiusura `})();`:

```js

                // Sonarr e Radarr (spec M §7.1): come il recupero, Salva solo dopo aver letto la configurazione.
                var arrFields = {
                    SonarrUrl: page.querySelector('#WonderFlixSonarrUrl'),
                    SonarrApiKey: page.querySelector('#WonderFlixSonarrApiKey'),
                    RadarrUrl: page.querySelector('#WonderFlixRadarrUrl'),
                    RadarrApiKey: page.querySelector('#WonderFlixRadarrApiKey'),
                    UpcomingSeriesDays: page.querySelector('#WonderFlixUpcomingSeriesDays'),
                    UpcomingMoviesDays: page.querySelector('#WonderFlixUpcomingMoviesDays')
                };
                var arrResult = page.querySelector('#WonderFlixArrResult');
                var arrNotLoaded = 'Settings not loaded: reload the page.';
                var arrLoaded = false;

                function loadArr() {
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        Object.keys(arrFields).forEach(function (name) {
                            var value = config[name];
                            arrFields[name].value = value === undefined || value === null ? '' : value;
                        });
                        arrLoaded = true;
                        if (arrResult.textContent === arrNotLoaded) {
                            arrResult.textContent = '';
                        }
                    }, function () {
                        arrLoaded = false;
                        arrResult.textContent = arrNotLoaded;
                    });
                }

                page.addEventListener('pageshow', loadArr);
                loadArr();

                page.querySelector('#WonderFlixArrForm').addEventListener('submit', function (e) {
                    e.preventDefault();
                    arrResult.textContent = '';
                    if (!arrLoaded) {
                        arrResult.textContent = arrNotLoaded;
                        return false;
                    }

                    Dashboard.showLoadingMsg();
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        config.SonarrUrl = arrFields.SonarrUrl.value.trim();
                        config.SonarrApiKey = arrFields.SonarrApiKey.value.trim();
                        config.RadarrUrl = arrFields.RadarrUrl.value.trim();
                        config.RadarrApiKey = arrFields.RadarrApiKey.value.trim();
                        config.UpcomingSeriesDays = numberIn(arrFields.UpcomingSeriesDays, config.UpcomingSeriesDays);
                        config.UpcomingMoviesDays = numberIn(arrFields.UpcomingMoviesDays, config.UpcomingMoviesDays);
                        return ApiClient.updatePluginConfiguration(pluginId, config);
                    }).then(function (saved) {
                        Dashboard.processPluginConfigurationUpdateResult(saved);
                        loadArr();
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        arrResult.textContent = 'Settings not saved.';
                    });
                    return false;
                });

                // L'esito di un servizio: la versione, oppure il motivo (Unauthorized, Unreachable).
                function arrText(name, result) {
                    if (!result.Configured) {
                        return name + ': not set up.';
                    }

                    if (result.Ok) {
                        return name + ': connected (' + result.Version + ').';
                    }

                    return result.Error === 'Unauthorized'
                        ? name + ': the API key was refused.'
                        : name + ': can\'t be reached from the Jellyfin server, check the address.';
                }

                page.querySelector('#WonderFlixArrTest').addEventListener('click', function () {
                    arrResult.textContent = 'Testing…';
                    ApiClient.ajax({
                        type: 'POST',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Upcoming/Test'),
                        dataType: 'json'
                    }).then(function (result) {
                        arrResult.textContent = arrText('Sonarr', result.Sonarr) + ' ' + arrText('Radarr', result.Radarr);
                    }, function () {
                        arrResult.textContent = 'Test failed: try again.';
                    });
                });
```

(`numberIn` è la funzione del recupero, già definita nello stesso script: le dichiarazioni di funzione valgono in tutto lo script.)

In `../meta.template.json`:
- `description`: aggiungi in fondo, prima del punto finale, ", plus the WonderFlix Home rows chosen by the admin and the upcoming episodes and movies from Sonarr and Radarr";
- `overview`: aggiungi in fondo ", Home rows, upcoming from Sonarr and Radarr".

In `../README.md`:
- nell'introduzione, dopo la frase della 1.6.0: "Dalla 1.7.0 dà la Home dell'admin (quali righe vede ogni utente nella Home dell'app) e le uscite in arrivo da Sonarr e Radarr (spec M, `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md`)." e nella frase "Senza il plugin WonderFlix funziona lo stesso" aggiungi "con la Home nell'ordine predefinito e senza le uscite in arrivo";
- nel punto delle impostazioni: "Seerr, il recupero della password e Sonarr e Radarr";
- un punto nuovo dopo "Recupero della password":

```markdown
- **Home (dalla 1.7.0):** `GET Home/Layout` dà la Home dell'admin (gli id
  delle righe accese, in ordine; `null` se mai impostata), `POST Home/Layout`
  la cambia (solo admin, dall'app; gli id sconosciuti si scartano). Le uscite
  in arrivo: `GET Upcoming/Series` (episodi entro N giorni dal calendario di
  Sonarr, non ancora scaricati, con la serie di Jellyfin se l'utente la vede)
  e `GET Upcoming/Movies` (film con l'uscita digitale entro N giorni, da
  Radarr); rispondono sempre 200, con `Error` (`NotConfigured`,
  `Unauthorized`, `Unreachable`) se qualcosa non va. Le risposte restano in
  memoria 15 minuti (gli errori 1 minuto). Nella pagina del plugin: indirizzo
  (con l'UrlBase, es. `https://host/sonarr`) e chiave di Sonarr e Radarr, i
  giorni e **Test connection** (`POST Upcoming/Test`, solo admin). Le chiavi
  non lasciano il server; le immagini sono gli indirizzi pubblici di TVDB e TMDB.
```

- nel punto "Funzioni": "dalla 1.6.0 anche `account`, dalla 1.7.0 anche `home`; `upcomingSeries` e `upcomingMovies` solo con Sonarr e Radarr configurati." e "Quelli di `Home` e `Upcoming` sono aperti a ogni utente che ha fatto l'accesso, tranne le scritture (`POST Home/Layout`, `POST Upcoming/Test`), solo per gli admin.";
- in "Installazione a mano": `pack.sh 1.7.0` e `WonderFlix Watch Party_1.7.0.0/`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi la suite intera.
Expected: PASS; la suite intera è verde (748 di partenza più quelli nuovi).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): register the Home services, plugin 1.7.0 and Dashboard section"
```

---

## Gruppo D — server e chiusura

### Task 8: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo C si ferma qui. L'orchestratore fa i passi seguenti, poi la review finale del branch. Sul server WonderFlix lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando. Gli script vanno scritti in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`). **Nessuno script stampa chiavi o token.**

1. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.7.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.7.0.0/`.
2. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix", come nel 17c e nel 18a: base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - `mkdir -p ~/wfwp-backup`; sposta `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.6.0.0` in `~/wfwp-backup/1.6.0.0-catalogo`; copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.6.0.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.7.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.7.0.0"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.7.0.0, rimetti `~/wfwp-backup/1.6.0.0-catalogo` e la configurazione salvata, riavvia, e segnalalo.
3. **Configurazione via API** (decisione 10), con uno script come questo:

```bash
#!/usr/bin/env bash
# 19a: Sonarr e Radarr nel plugin 1.7.0. Non stampa chiavi né token.
set -euo pipefail
umask 077
base=http://127.0.0.1:17502/jellyfin
plugin=882eb47e-668a-4935-ba55-c2858eb4ed90
token=$(sqlite3 -readonly ~/.apps/jellyfin/data/data/jellyfin.db "select AccessToken from ApiKeys where Name='Wonderflix' limit 1")
auth="Authorization: MediaBrowser Token=\"$token\""
file=$(mktemp ~/wf19a.XXXXXX)
trap 'rm -f "$file"' EXIT
curl -sf -H "$auth" "$base/Plugins/$plugin/Configuration" > "$file"
SK=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' ~/.apps/sonarr/config.xml) \
RK=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' ~/.apps/radarr/config.xml) \
python3 - "$file" <<'PY'
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
# La configurazione vera ha Seerr: se manca, non si riscrive niente.
assert config.get('SeerrUrl'), 'configurazione senza Seerr: non è quella vera'
config['SonarrUrl'] = 'https://hashvps.proton.usbx.me/sonarr'
config['SonarrApiKey'] = os.environ['SK']
config['RadarrUrl'] = 'https://hashvps.proton.usbx.me/radarr'
config['RadarrApiKey'] = os.environ['RK']
config['UpcomingSeriesDays'] = 7
config['UpcomingMoviesDays'] = 90
json.dump(config, open(path, 'w'))
PY
curl -sf -o /dev/null -w 'salvataggio: %{http_code}\n' -H "$auth" -H 'Content-Type: application/json' \
  --data @"$file" "$base/Plugins/$plugin/Configuration"
```

   Se la tabella o la colonna della chiave hanno un altro nome, guardale con `sqlite3 -readonly … ".schema ApiKeys"` (sola lettura). Dopo: `grep -c '<SonarrUrl>https://hashvps.proton' …Jellyfin.Plugin.WonderFlixWatchParty.xml` = 1, `SeerrUrl` e `ContactReminderDays` (14) ancora al loro posto.
4. **Controlli** (stessa base e intestazione; le risposte si riassumono con `python3`, senza stamparle intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.7.0`; funzioni con `home`, `upcomingSeries`, `upcomingMovies`, e ancora `requests` e `account`;
   - `GET /WonderFlixWatchParty/Upcoming/Series`: `Error` null, almeno un elemento; ogni `AirDateUtc` fra ora − 12 h e ora + 7 giorni; nessun indirizzo con `MediaCover`; `JellyfinSeriesId` null (la chiave API non ha un utente: il collegamento si prova con l'app nel 19b);
   - `GET /WonderFlixWatchParty/Upcoming/Movies`: `Error` null; ogni `DigitalRelease` fra oggi e oggi + 90 giorni;
   - `POST /WonderFlixWatchParty/Upcoming/Test`: Sonarr e Radarr `Ok` true, versioni `4.0.20…` e `6.4.4…`;
   - `GET /WonderFlixWatchParty/Home/Layout` → `Rows` null o assente; `POST` con `{"Rows":["resume","bogus","resume","myList"]}` → `["resume","myList"]`; `POST` con `{"Rows":null}` → di nuovo null (l'app 0.12 non legge la Home dell'admin: nessuno se ne accorge);
   - nel log di Jellyfin di oggi le due chiavi non ci sono (`grep -c` con la chiave letta da `config.xml` dentro lo script → 0, senza stamparla).
5. **Riporta all'utente** l'esito in breve: versioni, quanti episodi e film, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 19c). L'app 0.12 non usa le funzioni nuove.

### Task 9: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md`
- Modify: `docs/superpowers/plans/2026-10-10-wonderflix-19a-home-plugin.md` (solo una voce "Dalle review dei gruppi" nelle decisioni, se ci sono differenze)

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvata il 2026-10-10; piano 19a realizzato (`docs/superpowers/plans/2026-10-10-wonderflix-19a-home-plugin.md`), build di prova sul server; piani 19b e 19c da scrivere".
- **§7.2:** `HomeRows` è una stringa di id separati da virgole (null mai impostata, vuota tutte spente), id confrontati con le maiuscole; `POST` senza corpo → 400.
- **§7.3:**
  - i codici d'errore in PascalCase (`NotConfigured`, `Unauthorized`, `Unreachable`; decisione 1);
  - i periodi `[da, a)`: serie da ora − 12 h a ora + giorni, film da oggi 00:00 UTC a oggi + giorni + 1;
  - si saltano gli elementi senza serie, senza nome, senza data o null;
  - immagini solo `http(s)` assolute;
  - più serie della libreria per la stessa uscita: per ogni utente la prima che vede.
- **§7.4:** la cache legata alle impostazioni (una modifica vale dalla richiesta dopo); una lettura sola per tutti, che non si ferma se uno chiude la richiesta; un errore inatteso vale `Unreachable` per 1 minuto.
- **§7.5:** la prova chiama solo `system/status`, i due servizi in parallelo.
- **§8.1 (per il 19b):** i codici in PascalCase; un campo null può mancare nella risposta e va letto come null.
- **§12.1:** i test com'erano previsti, con i nomi veri delle classi di test.
- **§13 e §15:** la configurazione è stata fatta via API il giorno del Task 8; 19a realizzato; il plugin 1.7.0 resta build di prova fino alla fine del 19c.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze (come nei piani 17a–18c).

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the Home spec with plan 19a"
```

### Task 10: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 8: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`). Niente tag e niente manifest: il plugin 1.7.0 si pubblica alla fine del 19c, insieme all'app 0.13.0.
