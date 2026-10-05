# WonderFlix — Piano 15a: chiedere i titoli con Seerr

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prima metà della Spec I. Ci sono:
- il plugin 1.4.0 completo: configurazione di Seerr, client, abbinamento e import degli utenti, endpoint delle richieste, webhook, due tipi nuovi nella cassetta;
- nell'app: `JellyfinItem.tmdbId`, `RequestsApi` e modelli, la disponibilità della funzione, la sezione "Da richiedere" nella ricerca, la scheda da richiedere con le stagioni e Richiedi.

La pagina Richieste, la finestra Approva, "Richiedi stagioni" sulle serie della libreria, le righe nuove della cassetta e la release sono il piano 15b.

**Spec:** `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md` (§3, §7, §8.1–8.4, §9.1–9.2, §10 per le parti del piano, §11, §12).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 21):
1. **Richiesta completata:** lo stato Seerr 5 (completata) dà `Available`. Nell'ordine di §7.3 viene subito dopo "in attesa": una serie con le stagioni chieste tutte arrivate è "Disponibile" anche se la serie è in parte.
2. **Pagina del plugin:** oltre a `POST Requests/Test` c'è `GET Requests/Admin` (solo admin), che dà "configurato" e l'ultimo evento del webhook per la riga "Ultimo evento ricevuto".
3. **Modello del webhook:** le stagioni arrivano con la chiave speciale `"{{extra}}": []`, che Seerr sostituisce con `"extra": [{name, value}]`. Il campo `"extra": "{{extra}}"` della spec non funzionerebbe: `{{extra}}` non è una variabile di testo.
4. **`requestsMeProvider`** è `autoDispose`: si rilegge ogni volta che una pagina lo usa, non a ogni connessione al server (§8.2).
5. **Errori con il codice:** `ForbiddenException` e `ServerErrorException` portano il corpo della risposta (`body`), così `RequestsApi` legge `{Code}`.
6. **Id Jellyfin:** il plugin dà sempre `JellyfinItemId` in formato "N" minuscolo, e l'app li confronta in minuscolo.

**Architecture:**
- **Plugin:**
  - `Seerr/`: impostazioni, forme JSON, `SeerrClient` (HTTP con `IHttpClientFactory`), permessi, regole degli stati (`SeerrMapping`), `SeerrUserMap`, `SeerrTitleCache`.
  - `Hub/RequestsService`: la logica degli endpoint. `Hub/RequestWebhookHandler`: il webhook verso la cassetta.
  - `Api/RequestsController` e `Api/RequestsWebhookController`.
  - Gli errori di Seerr viaggiano come `SeerrException` e il controller li traduce in stato HTTP più `{Code}`.
- **App:**
  - `lib/core/requests/`: `RequestsApi`, modelli, immagini TMDB.
  - `lib/features/requests/`: provider, sezione della ricerca, card, controller della scheda, `SeasonPicker`, `TmdbTitleScreen`.
  - La rotta `/tmdb/:type/:tmdbId` nella shell.

**Tech Stack:** C# net9.0 contro Jellyfin.Controller/Model 10.11.0 (test con le dll 10.11.9), xUnit, `Microsoft.Extensions.Http` (dal framework ASP.NET Core); Flutter 3.47.5, flutter_riverpod 3, go_router 18, dio 5, lucide_icons_flutter, url_launcher.

**Worktree:** `.claude/worktrees/piano-15a`, branch `feat/piano-15a`. **Base:** `main` con questo piano. **Test a inizio piano:** da contare all'avvio (`flutter test` e `dotnet test`); a fine piano 14b erano 1698 Flutter e 249 plugin.

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git già configurata (quella dell'utente).
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `pkill`, `killall`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:**
  - Git Bash su Windows.
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-15a`).
  - Comandi git semplici: niente `git -C`, niente variabili nei comandi git.
  - Mai `git checkout -- <file>` su un file che hai modificato.
- **Prima di ogni commit:**
  - **lato plugin:** `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` tutto verde e senza warning (il plugin ha `TreatWarningsAsErrors`);
  - **lato app:** `flutter analyze` senza problemi e `flutter test` tutto verde.
- **File generati:**
  - Se `flutter test`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` né `dotnet format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: molti file della working copy sono CRLF, l'indice è LF con `core.autocrlf=true`. I file nuovi vanno bene con LF.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese, anche nel C# (commenti `///` in italiano, identificatori in inglese). Nel C# sempre le graffe.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; durate da `WfMotion`; `clock.now()`, mai `DateTime.now()`.
- **Segreti:** la chiave API di Seerr non va mai nei log, nei test con valori veri, nei commit o nei messaggi. Nei test si usa `"key"`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-05 sul server (Seerr 3.4.1, sorgenti in `dist/`, risposte vere con chiamate GET) e sul codice del repository.

**Seerr: accesso**
- `X-API-Key` uguale alla chiave → si agisce come l'utente 1, oppure come `Number(X-API-User)` se c'è l'header. Non ci sono altri controlli.
- **Una chiave sbagliata non dà 401:** senza utente, gli endpoint protetti rispondono **403** `{"status":403,"error":"You do not have permission to access this endpoint"}`. `GET /status` è pubblico.
- Per questo il plugin legge un 403 di una chiamata **senza** `X-API-User` (come utente 1, admin) come "chiave rifiutata" (`SeerrError.Auth`).

**Seerr: forme JSON** (camelCase)
- `GET /status` → `{version, commitTag, updateAvailable, …}`.
- `GET /auth/me` e `GET /user?take=&skip=` → l'utente, oppure `{pageInfo:{pages,pageSize,results,page}, results:[…]}`.
  - Campi dell'utente: `id`, `permissions`, `jellyfinUserId` ("N" minuscolo), `jellyfinUsername`, `displayName`.
- `GET /settings/main` → `{defaultPermissions, …}` (sul server 32).
- `GET /search?query=&page=1&language=it` → `{page, totalPages, totalResults, results:[…]}`.
  - Un risultato ha `id` (tmdb), `mediaType` (`movie`/`tv`/`person`), `title` (film) o `name` (serie), `releaseDate` o `firstAirDate` ("2024-02-27"), `posterPath` ("/abc.jpg").
  - `mediaInfo` è `null` oppure `{status, jellyfinMediaId, …}`.
- `GET /movie/{id}?language=it` → `title`, `releaseDate`, `overview`, `runtime` (minuti, anche `null`), `genres:[{id,name}]`, `posterPath`, `backdropPath`, `relatedVideos`, `mediaInfo`.
  - Un video di `relatedVideos` è `{type:"Trailer"|"Teaser"|…, site:"YouTube", key, url:"https://www.youtube.com/watch?v=…", name}`.
  - `mediaInfo` è `{status, jellyfinMediaId, seasons:[{seasonNumber,status}], requests:[{id,status,seasons:[{seasonNumber,status}],requestedBy:{id,displayName}}], downloadStatus:[{size,sizeLeft,…}]}`.
- `GET /tv/{id}?language=it` → `name`, `firstAirDate`, `overview`, `genres`, `posterPath`, `backdropPath`, `relatedVideos`, `seasons:[{seasonNumber, episodeCount, name}]` (può esserci la **stagione 0**, gli speciali), `mediaInfo`.
- `GET /request?take=&skip=&filter=all|pending&sort=added&sortDirection=desc&requestedBy=<id>` → `{pageInfo, results:[…]}`.
  - Una richiesta ha `id`, `status`, `type`, `is4k`, `createdAt` ("2026-10-03T20:31:16.000Z"), `seasons:[{seasonNumber,status}]`, `requestedBy:{id,displayName,jellyfinUserId}`.
  - E `media:{tmdbId, mediaType, status, jellyfinMediaId, downloadStatus:[…]}`. **Nessun titolo.**
- `POST /request` `{mediaType, mediaId, seasons?}` → 201 con la richiesta.
  - Errori: 403 con `message` "… Quota exceeded." (quota), "This media is blocklisted." (bloccato), "You do not have permission …" (permesso); 409 (già chiesto); **202** "No seasons available to request".
- `GET /request/{id}` → la richiesta (404 se non c'è).
- `PUT /request/{id}` `{mediaType, serverId, profileId, rootFolder, seasons}`: per le serie `seasons` è obbligatorio, e chi ha `MANAGE_REQUESTS` può cambiare qualunque richiesta.
- `POST /request/{id}/approve` e `/decline` (servono `MANAGE_REQUESTS`) → 200 con la richiesta, 404 se non c'è.
- `GET /service/radarr` e `/service/sonarr` → `[{id, name, is4k, isDefault, activeProfileId, activeDirectory, …}]`.
- `GET /service/{radarr|sonarr}/{id}` → `{server, profiles:[{id,name}], rootFolders:[{id,path,freeSpace}], …}`.
- `POST /user/import-from-jellyfin` `{jellyfinUserIds:[…]}` (serve `MANAGE_USERS`) crea gli account mancanti con i permessi predefiniti.

**Seerr: codici**
- Richiesta: 1 in attesa, 2 approvata, 3 rifiutata, 4 non riuscita, 5 completata.
- Titolo: 1 sconosciuto, 2 in attesa, 3 in lavorazione, 4 in parte disponibile, 5 disponibile, 6 bloccato, 7 eliminato.
- Permessi (bit): `ADMIN` 2, `MANAGE_USERS` 8, `MANAGE_REQUESTS` 16, `REQUEST` 32, `REQUEST_MOVIE` 262144, `REQUEST_TV` 524288. Chi ha `ADMIN` ha tutti i permessi.

**Seerr: webhook**
- Un solo webhook per il server. Parte solo per i tipi della maschera (`MEDIA_PENDING` 2, `MEDIA_AVAILABLE` 8); il "Test" di Seerr manda `TEST_NOTIFICATION`.
- Il corpo è il modello JSON con `{{variabile}}` sostituite nei valori di testo.
- Le chiavi speciali `"{{extra}}"`, `"{{media}}"` e `"{{request}}"` diventano `extra`, `media` e `request`. `extra` è `[{name:"Requested Seasons", value:"1, 2"}]` per le serie.
- `subject` è "Titolo (anno)" nella lingua di Seerr (sul server inglese). `media_jellyfinMediaId` è "N" minuscolo o vuoto.

**Jellyfin e plugin**
- `IHttpClientFactory` e `AddHttpClient` stanno in `Microsoft.Extensions.Http`, parte del framework ASP.NET Core che il plugin già usa (`Jellyfin.Common` ha `FrameworkReference Microsoft.AspNetCore.App`).
- `AuthorizationInfo.UserId` viene dall'utente dell'autenticazione. `[AllowAnonymous]` lascia passare le richieste senza header `Authorization`.
- `ActionResult<T>` **non** ha la conversione implicita da un tipo interfaccia (`IReadOnlyList<…>`): si usa `new ActionResult<T>(value)`.
- `GET /Items/{id}` dà tutti i campi, compresi i `ProviderIds` (`{"Tmdb":"438631", …}`).

**App, cose da sapere**
- `JellyfinHttp` converte gli errori con `mapDioException`. Oggi il corpo della risposta si perde (Task 11).
- `SocialAvailability` (in `lib/features/social/social_providers.dart`) legge `Info.Features`. `FakeSocialAvailability` e `socialTestOverrides` sono in `test/support/social_fakes.dart`.
- `pumpApp` (`test/support/pump_app.dart`) monta con `MaterialApp(home:)`: niente router. Per i test di navigazione si usa un `GoRouter` piccolo, come `test/app/router_test.dart`.
- `WfImage` disegna con `imageBuilderProvider`, che nei test è un riquadro grigio; `ImageRef(url)` va bene anche per le immagini TMDB.
- `BackdropImage(backdrop:, fallback:)` (`lib/ui/backdrop_image.dart`) è lo sfondo delle schede.
- `detailHeaderHeight` (560) e `detailHeaderTextBottom` (28) sono in `lib/features/detail/detail_header.dart`.
- `currentUserIdProvider` lancia senza sessione: non va guardato fuori dai provider asincroni.

## Mappa dei file

| File | Azione | Responsabilità |
|---|---|---|
| `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/PluginConfiguration.cs` | modifica | `SeerrUrl`, `SeerrApiKey`, `SeerrWebhookSecret` |
| `…/Seerr/ISeerrSettings.cs` | crea | impostazioni di Seerr, `IsConfigured` |
| `…/Server/PluginSeerrSettings.cs` | crea | impostazioni dalla configurazione del plugin |
| `…/Protocol/WatchPartyProtocol.cs`, `…/Api/InfoController.cs` | modifica | `requests` in `Features` |
| `…/Seerr/SeerrJson.cs` | crea | forme JSON di Seerr e del webhook |
| `…/Seerr/SeerrException.cs` | crea | `SeerrError`, `SeerrException` |
| `…/Seerr/SeerrPermissions.cs`, `…/Seerr/SeerrCodes.cs` | crea | bit dei permessi, codici di stato |
| `…/Seerr/ISeerrClient.cs`, `…/Seerr/SeerrClient.cs` | crea | HTTP verso Seerr |
| `…/Seerr/SeerrMapping.cs` | crea | regole pure: stati, stagioni, anno, trailer, id |
| `…/Seerr/SeerrUserMap.cs` | crea | abbinamento, import, permessi predefiniti, chi approva |
| `…/Seerr/SeerrTitleCache.cs` | crea | titoli per tmdbId e lingua |
| `…/Protocol/RequestsDtos.cs` | crea | oggetti per l'app |
| `…/Hub/RequestsService.cs` | crea | logica degli endpoint |
| `…/Protocol/InboxDtos.cs`, `…/Hub/InboxBook.cs`, `…/Hub/InboxService.cs` | modifica | `RequestAvailable`, `RequestPending` |
| `…/Hub/RequestEvent.cs`, `…/Hub/RequestWebhookHandler.cs` | crea | webhook → cassetta |
| `…/Api/RequestsController.cs`, `…/Api/RequestsWebhookController.cs` | crea | endpoint |
| `…/PluginServiceRegistrator.cs` | modifica | registrazioni |
| `…/Configuration/configPage.html` | modifica | sezione Seerr |
| `…/Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `jellyfin-plugin-watch-party/README.md` | modifica | 1.4.0, documentazione |
| `…Tests/FakeSeerrSettings.cs`, `FakeSeerrClient.cs`, `FakeSeerrHttp.cs` | crea | finti |
| `…Tests/*Seerr*Tests.cs`, `RequestsServiceTests.cs`, `RequestsControllerTests.cs`, `InboxRequestsTests.cs`, `RequestWebhookTests.cs` | crea | test |
| `…Tests/InfoControllerTests.cs`, `PluginConfigurationTests.cs`, `PluginPagesTests.cs`, `ServiceRegistrationTests.cs` | modifica | test |
| `lib/core/jellyfin/api_exception.dart` | modifica | `body` negli errori |
| `lib/core/jellyfin/item_models.dart` | modifica | `JellyfinItem.tmdbId` |
| `lib/core/requests/requests_models.dart`, `tmdb_images.dart`, `requests_api.dart` | crea | modelli, immagini, API |
| `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart` | modifica | funzione `requests` |
| `lib/features/requests/requests_providers.dart` | crea | API, disponibilità, Me |
| `lib/features/requests/requestables_controller.dart` | crea | sezione "Da richiedere" (stato) |
| `lib/features/requests/requestable_poster_card.dart`, `requestables_section.dart`, `requests_navigation.dart` | crea | card, sezione, navigazione |
| `lib/features/search/search_screen.dart` | modifica | sezione sotto i risultati |
| `lib/features/requests/request_title_controller.dart` | crea | scheda: dati, stagioni scelte, invio |
| `lib/features/requests/season_picker.dart` | crea | elenco delle stagioni |
| `lib/features/requests/tmdb_title_screen.dart` | crea | scheda da richiedere |
| `lib/app/router.dart`, `lib/app/error_text.dart` | modifica | rotta, "Seerr non risponde" |
| `l10n/app_it.arb`, `l10n/app_en.arb` | modifica | testi |
| `test/support/requests_fakes.dart` | crea | `FakeRequestsApi`, dati di prova |
| `test/…` | crea/modifica | test |
| `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md` | modifica | allineamento finale |

## Gruppi per i subagent

- **Gruppo A (Task 1–4):** plugin, base: impostazioni, JSON, client, mappature.
- **Gruppo B (Task 5–9):** plugin, logica: utenti, titoli, servizio, cassetta e webhook, controller e pagina.
- **Gruppo C (Task 10):** **STOP**, lo fa l'orchestratore (installazione sul server e prova del collegamento).
- **Gruppo D (Task 11–14):** app, dati: errori, `tmdbId`, modelli, API, disponibilità.
- **Gruppo E (Task 15–17):** app, ricerca: testi, controller, sezione.
- **Gruppo F (Task 18–20):** app, scheda: controller, `SeasonPicker`, `TmdbTitleScreen` e rotta.
- **Gruppo G (Task 21):** allineamento della spec, verifica finale, build.

---

## Gruppo A — plugin, base

### Task 1: impostazioni di Seerr, `requests` in `Info`, versione 1.4.0

**Files:**
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/PluginConfiguration.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Seerr/ISeerrSettings.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/PluginSeerrSettings.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/InfoController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/FakeSeerrSettings.cs`
- Test: `…Tests/InfoControllerTests.cs`, `…Tests/PluginConfigurationTests.cs`

- [ ] **Step 1: il finto delle impostazioni**

`…Tests/FakeSeerrSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Collegamento a Seerr fisso, da cambiare nel test.</summary>
internal sealed class FakeSeerrSettings : ISeerrSettings
{
    public string Url { get; set; } = "https://seerr.example";

    public string ApiKey { get; set; } = "key";

    public string WebhookSecret { get; set; } = "secret";
}
```

- [ ] **Step 2: test che falliscono**

In `InfoControllerTests.cs` sostituisci `InfoReportsVersionProtocolAndFeatures` con:

```csharp
    [Fact]
    public void InfoReportsVersionProtocolAndFeatures()
    {
        var info = new InfoController(new FakeSeerrSettings { Url = string.Empty }).GetInfo().Value!;
        Assert.Equal("1.4.0", info.Version);
        Assert.Equal(1, info.Protocol);
        Assert.Equal(new[] { "friends", "parties", "inbox", "queue" }, info.Features);
    }

    [Fact]
    public void RequestsAppearOnlyWithSeerrConfigured()
    {
        Assert.Equal(
            new[] { "friends", "parties", "inbox", "queue", "requests" },
            new InfoController(new FakeSeerrSettings()).GetInfo().Value!.Features);
        Assert.DoesNotContain(
            "requests", new InfoController(new FakeSeerrSettings { ApiKey = " " }).GetInfo().Value!.Features);
    }
```

In `PluginConfigurationTests.cs` aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;` e questi test:

```csharp
    [Fact]
    public void SeerrSettingsAreEmptyByDefaultAndSurviveTheXml()
    {
        var empty = new PluginConfiguration();
        Assert.Equal(string.Empty, empty.SeerrUrl);
        Assert.Equal(string.Empty, empty.SeerrApiKey);
        Assert.Equal(string.Empty, empty.SeerrWebhookSecret);

        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, new PluginConfiguration
        {
            SeerrUrl = "https://host/seerr",
            SeerrApiKey = "key",
            SeerrWebhookSecret = "secret",
        });
        using var reader = new StringReader(writer.ToString());
        var read = (PluginConfiguration)serializer.Deserialize(reader)!;

        Assert.Equal("https://host/seerr", read.SeerrUrl);
        Assert.Equal("key", read.SeerrApiKey);
        Assert.Equal("secret", read.SeerrWebhookSecret);
    }

    [Fact]
    public void WithoutThePluginInstanceSeerrIsNotConfigured()
    {
        var settings = new PluginSeerrSettings();
        Assert.Equal(string.Empty, settings.Url);
        Assert.Equal(string.Empty, settings.ApiKey);
        Assert.False(settings.IsConfigured());
    }

    [Theory]
    [InlineData("https://host/seerr", "key", true)]
    [InlineData("", "key", false)]
    [InlineData("https://host/seerr", " ", false)]
    public void SeerrIsConfiguredWithUrlAndKey(string url, string key, bool configured) =>
        Assert.Equal(configured, new FakeSeerrSettings { Url = url, ApiKey = key }.IsConfigured());
```

- [ ] **Step 3: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~InfoControllerTests|FullyQualifiedName~PluginConfigurationTests"`
Expected: FAIL di compilazione (`ISeerrSettings`, `SeerrUrl`, `PluginSeerrSettings` non esistono).

- [ ] **Step 4: implementazione**

In `PluginConfiguration.cs`, dopo `NotifyNewTitles`:

```csharp

    /// <summary>
    /// Indirizzo di Seerr visto dal server Jellyfin, per esempio
    /// https://host/seerr (spec I §7.1). Vuoto: richieste spente.
    /// </summary>
    public string SeerrUrl { get; set; } = string.Empty;

    /// <summary>Chiave API di Seerr (Impostazioni → Generali). Il file lo leggono solo gli admin.</summary>
    public string SeerrApiKey { get; set; } = string.Empty;

    /// <summary>Segreto che Seerr mette nel corpo del webhook (spec I §7.5).</summary>
    public string SeerrWebhookSecret { get; set; } = string.Empty;
```

`Seerr/ISeerrSettings.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Il collegamento a Seerr (spec I §7.1). Va letto ogni volta: l'admin lo cambia dalla Dashboard.</summary>
public interface ISeerrSettings
{
    /// <summary>Indirizzo senza "/" finale; vuoto se non impostato.</summary>
    string Url { get; }

    string ApiKey { get; }

    string WebhookSecret { get; }
}

public static class SeerrSettingsExtensions
{
    /// <summary>Indirizzo e chiave ci sono: la funzione "requests" è accesa.</summary>
    public static bool IsConfigured(this ISeerrSettings settings) =>
        !string.IsNullOrWhiteSpace(settings.Url) && !string.IsNullOrWhiteSpace(settings.ApiKey);
}
```

`Server/PluginSeerrSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Il collegamento a Seerr dalla configurazione del plugin.</summary>
public sealed class PluginSeerrSettings : ISeerrSettings
{
    // Si legge ogni volta, come PluginNewTitlesSettings: salvando dalla
    // Dashboard Jellyfin sostituisce l'oggetto della configurazione. Senza
    // plugin (nei test) tutto vuoto.
    public string Url => (Plugin.Instance?.Configuration.SeerrUrl ?? string.Empty).Trim().TrimEnd('/');

    public string ApiKey => (Plugin.Instance?.Configuration.SeerrApiKey ?? string.Empty).Trim();

    public string WebhookSecret => (Plugin.Instance?.Configuration.SeerrWebhookSecret ?? string.Empty).Trim();
}
```

In `WatchPartyProtocol.cs`, sostituisci il commento e la riga di `Features` con:

```csharp
    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7, spec
    /// G §6.3, spec H §7). Il protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends", "parties", "inbox", "queue"];

    /// <summary>Le richieste con Seerr (spec I §7.1): in GET Info solo con Seerr configurato.</summary>
    public const string RequestsFeature = "requests";

    /// <summary>Le funzioni di GET Info, con "requests" se Seerr è configurato.</summary>
    public static IReadOnlyList<string> FeaturesWith(bool requests) =>
        requests ? [.. Features, RequestsFeature] : Features;
```

`InfoController.cs` diventa:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// GET Info per ogni utente autenticato (spec G §7.2): la cassetta delle
/// notifiche vale anche per chi non ha accesso ai watch party. Non può
/// stare nei controller con la policy SyncPlay: un attributo sul metodo si
/// somma a quello della classe, non lo allarga. "requests" c'è solo con
/// Seerr configurato (spec I §7.1).
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class InfoController(ISeerrSettings seerr) : ControllerBase
{
    private static string PluginVersion =>
        typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>Versione del plugin, del protocollo e funzioni in più.</summary>
    [HttpGet("Info")]
    public ActionResult<InfoResponse> GetInfo() =>
        new InfoResponse(
            PluginVersion, WatchPartyProtocol.Version, WatchPartyProtocol.FeaturesWith(seerr.IsConfigured()));
}
```

In `PluginServiceRegistrator.cs` aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;` e, dopo `INewTitlesSettings`:

```csharp
        serviceCollection.AddSingleton<ISeerrSettings, PluginSeerrSettings>();
```

Nel csproj: `<Version>1.4.0</Version>`.

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): read the Seerr settings and announce requests in Info"
```

### Task 2: forme JSON di Seerr, errori, permessi, codici

**Files:**
- Create: `…/Seerr/SeerrJson.cs`, `…/Seerr/SeerrException.cs`, `…/Seerr/SeerrPermissions.cs`, `…/Seerr/SeerrCodes.cs`
- Test: `…Tests/SeerrJsonTests.cs`, `…Tests/SeerrPermissionsTests.cs`

(`…` è `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty`, `…Tests` è `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`.)

- [ ] **Step 1: test che falliscono**

`…Tests/SeerrJsonTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrJsonTests
{
    [Fact]
    public void ReadsASearchPage()
    {
        const string json = """
            {"page":1,"totalPages":65,"results":[
              {"id":438631,"mediaType":"movie","title":"Dune","releaseDate":"2021-09-15","posterPath":"/a.jpg",
               "mediaInfo":{"id":155,"tmdbId":438631,"status":5,"jellyfinMediaId":"ee39bef06f503dd0e9dbd20593df417f"}},
              {"id":90228,"mediaType":"tv","name":"Dune: Prophecy","firstAirDate":"2024-11-17","posterPath":null,"mediaInfo":null},
              {"id":1,"mediaType":"person","name":"Timothée"}]}
            """;

        var page = JsonSerializer.Deserialize<SeerrSearchPage>(json, SeerrJson.Options)!;

        Assert.Equal(3, page.Results.Count);
        Assert.Equal("Dune", page.Results[0].Title);
        Assert.Equal("2021-09-15", page.Results[0].ReleaseDate);
        Assert.Equal(5, page.Results[0].MediaInfo!.Status);
        Assert.Equal("ee39bef06f503dd0e9dbd20593df417f", page.Results[0].MediaInfo!.JellyfinMediaId);
        Assert.Equal("tv", page.Results[1].MediaType);
        Assert.Equal("Dune: Prophecy", page.Results[1].Name);
        Assert.Null(page.Results[1].MediaInfo);
    }

    [Fact]
    public void ReadsASeriesWithSeasonsRequestsAndVideos()
    {
        const string json = """
            {"id":250203,"name":"Brothers","firstAirDate":"2026-09-22","overview":"Due fratelli",
             "genres":[{"id":35,"name":"Commedia"}],"posterPath":"/p.jpg","backdropPath":"/b.jpg",
             "relatedVideos":[{"type":"Trailer","site":"YouTube","key":"x","url":"https://www.youtube.com/watch?v=x"}],
             "seasons":[{"seasonNumber":0,"episodeCount":2},{"seasonNumber":1,"episodeCount":8}],
             "mediaInfo":{"status":4,"jellyfinMediaId":"6d1c8ea33a794f76fdbe92a216959073",
               "seasons":[{"seasonNumber":1,"status":4}],
               "requests":[{"id":432,"status":2,"seasons":[{"seasonNumber":1,"status":2}],
                            "requestedBy":{"id":24,"displayName":"sronweb"}}],
               "downloadStatus":[]}}
            """;

        var tv = JsonSerializer.Deserialize<SeerrTv>(json, SeerrJson.Options)!;

        Assert.Equal("Brothers", tv.Name);
        Assert.Equal("Commedia", Assert.Single(tv.Genres).Name);
        Assert.Equal("https://www.youtube.com/watch?v=x", Assert.Single(tv.RelatedVideos).Url);
        Assert.Equal(new[] { 0, 1 }, tv.Seasons.Select(s => s.SeasonNumber));
        Assert.Equal(8, tv.Seasons[1].EpisodeCount);
        Assert.Equal(4, Assert.Single(tv.MediaInfo!.Seasons).Status);
        var request = Assert.Single(tv.MediaInfo.Requests);
        Assert.Equal(24, request.RequestedBy!.Id);
        Assert.Equal(1, Assert.Single(request.Seasons).SeasonNumber);
    }

    [Fact]
    public void ReadsARequestPage()
    {
        const string json = """
            {"pageInfo":{"pages":138,"pageSize":3,"results":413,"page":1},"results":[
              {"id":434,"status":2,"type":"tv","is4k":false,"createdAt":"2026-10-03T20:31:16.000Z",
               "seasons":[{"seasonNumber":14,"status":2}],
               "requestedBy":{"id":24,"displayName":"sronweb","jellyfinUserId":"150fe35a657b4c5ea4fd644c4c5152b5"},
               "media":{"tmdbId":59941,"mediaType":"tv","status":1,"jellyfinMediaId":null,
                        "downloadStatus":[{"size":1000,"sizeLeft":250,"status":"downloading"}]}}]}
            """;

        var page = JsonSerializer.Deserialize<SeerrPage<SeerrRequest>>(json, SeerrJson.Options)!;

        Assert.Equal(413, page.PageInfo!.Results);
        var request = Assert.Single(page.Results);
        Assert.Equal(434, request.Id);
        Assert.Equal(new DateTimeOffset(2026, 10, 3, 20, 31, 16, TimeSpan.Zero), request.CreatedAt);
        Assert.Equal("sronweb", request.RequestedBy!.DisplayName);
        Assert.Equal(59941, request.Media!.TmdbId);
        Assert.Equal(250, Assert.Single(request.Media.DownloadStatus).SizeLeft);
    }

    [Fact]
    public void WritesANewRequestInCamelCaseWithoutSeasonsForAMovie()
    {
        Assert.Equal(
            """{"mediaType":"movie","mediaId":5}""",
            JsonSerializer.Serialize(new SeerrCreateRequest { MediaType = "movie", MediaId = 5 }, SeerrJson.Options));
        Assert.Equal(
            """{"mediaType":"tv","mediaId":7,"seasons":[1,2]}""",
            JsonSerializer.Serialize(
                new SeerrCreateRequest { MediaType = "tv", MediaId = 7, Seasons = [1, 2] }, SeerrJson.Options));
    }

    [Fact]
    public void ReadsTheWebhookPayload()
    {
        const string json = """
            {"secret":"s","notification_type":"MEDIA_AVAILABLE","subject":"Dune (2021)","request_id":"53",
             "media_type":"movie","media_tmdbid":"438631","media_jellyfinMediaId":"ee39bef06f503dd0e9dbd20593df417f",
             "requestedBy_jellyfinUserId":"150fe35a657b4c5ea4fd644c4c5152b5","requestedBy_username":"sronweb",
             "extra":[{"name":"Requested Seasons","value":"1, 2"}]}
            """;

        var payload = JsonSerializer.Deserialize<SeerrWebhookPayload>(json, SeerrJson.Options)!;

        Assert.Equal("s", payload.Secret);
        Assert.Equal("MEDIA_AVAILABLE", payload.NotificationType);
        Assert.Equal("Dune (2021)", payload.Subject);
        Assert.Equal("53", payload.RequestId);
        Assert.Equal("movie", payload.MediaType);
        Assert.Equal("438631", payload.MediaTmdbId);
        Assert.Equal("ee39bef06f503dd0e9dbd20593df417f", payload.MediaJellyfinMediaId);
        Assert.Equal("150fe35a657b4c5ea4fd644c4c5152b5", payload.RequestedByJellyfinUserId);
        Assert.Equal("sronweb", payload.RequestedByUsername);
        Assert.Equal("1, 2", Assert.Single(payload.Extra!).Value);
    }
}
```

`…Tests/SeerrPermissionsTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrPermissionsTests
{
    [Theory]
    [InlineData(2, true, true)] // ADMIN: tutti i permessi
    [InlineData(34, true, true)] // ADMIN + REQUEST (l'admin del server)
    [InlineData(32, true, false)] // REQUEST (gli amici)
    [InlineData(16, false, true)] // MANAGE_REQUESTS
    [InlineData(262144, true, false)] // REQUEST_MOVIE
    [InlineData(524288, true, false)] // REQUEST_TV
    [InlineData(0, false, false)]
    public void RequestAndManage(int permissions, bool canRequest, bool canManage)
    {
        Assert.Equal(canRequest, SeerrPermissions.CanRequest(permissions));
        Assert.Equal(canManage, SeerrPermissions.CanManage(permissions));
    }
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~SeerrJsonTests|FullyQualifiedName~SeerrPermissionsTests"`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`Seerr/SeerrCodes.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Codici di stato di Seerr (spec I §3).</summary>
public static class SeerrCodes
{
    // Stato di una richiesta (MediaRequestStatus).
    public const int RequestPending = 1;
    public const int RequestApproved = 2;
    public const int RequestDeclined = 3;
    public const int RequestFailed = 4;
    public const int RequestCompleted = 5;

    // Stato di un titolo o di una stagione (MediaStatus).
    public const int MediaUnknown = 1;
    public const int MediaPending = 2;
    public const int MediaProcessing = 3;
    public const int MediaPartial = 4;
    public const int MediaAvailable = 5;
    public const int MediaBlocklisted = 6;
    public const int MediaDeleted = 7;
}

/// <summary>I servizi di Seerr per le approvazioni.</summary>
public static class SeerrServices
{
    public const string Radarr = "radarr";
    public const string Sonarr = "sonarr";
}
```

`Seerr/SeerrPermissions.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Bit dei permessi di Seerr (spec I §3) e i controlli che servono al plugin.</summary>
public static class SeerrPermissions
{
    public const int Admin = 2;
    public const int ManageUsers = 8;
    public const int ManageRequests = 16;
    public const int Request = 32;
    public const int RequestMovie = 262144;
    public const int RequestTv = 524288;

    /// <summary>Ha il permesso; ADMIN li ha tutti, come in Seerr.</summary>
    public static bool Has(int permissions, int permission) =>
        (permissions & Admin) != 0 || (permissions & permission) == permission;

    /// <summary>Può approvare e rifiutare le richieste.</summary>
    public static bool CanManage(int permissions) => Has(permissions, ManageRequests);

    /// <summary>Può chiedere film o serie.</summary>
    public static bool CanRequest(int permissions) =>
        Has(permissions, Request) || Has(permissions, RequestMovie) || Has(permissions, RequestTv);
}
```

`Seerr/SeerrException.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Perché una chiamata a Seerr non è riuscita (spec I §7.3).</summary>
public enum SeerrError
{
    /// <summary>Indirizzo o chiave mancanti nella configurazione.</summary>
    NotConfigured,

    /// <summary>Seerr irraggiungibile, lento o con una risposta inattesa.</summary>
    Unavailable,

    /// <summary>Chiave API rifiutata.</summary>
    Auth,

    NoPermission,

    QuotaExceeded,

    Blocklisted,

    AlreadyRequested,

    /// <summary>Le stagioni sono già tutte chieste o presenti (il 202 di Seerr).</summary>
    NothingToRequest,

    /// <summary>L'utente non ha un account Seerr e l'import non l'ha creato.</summary>
    AccountUnavailable,

    /// <summary>Titolo o richiesta che Seerr non conosce.</summary>
    NotFound,

    /// <summary>Parametri sbagliati.</summary>
    BadRequest,
}

/// <summary>Errore di Seerr già classificato. Il messaggio non contiene mai la chiave.</summary>
public sealed class SeerrException : Exception
{
    public SeerrException(SeerrError error, Exception? inner = null)
        : base("Seerr: " + error, inner)
    {
        Error = error;
    }

    public SeerrError Error { get; }
}
```

`Seerr/SeerrJson.cs`:

```csharp
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

// Le forme JSON di Seerr 3.x usate dal plugin (spec I §3), solo con i campi
// che servono. Si leggono e si scrivono con SeerrJson.Options: camelCase,
// maiuscole ignorate in lettura.

internal static class SeerrJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}

public sealed class SeerrStatusInfo
{
    public string? Version { get; set; }
}

public sealed class SeerrUser
{
    public int Id { get; set; }

    public int Permissions { get; set; }

    /// <summary>Id dell'utente Jellyfin, in formato "N" (può puntare a un utente cancellato).</summary>
    public string? JellyfinUserId { get; set; }

    public string? DisplayName { get; set; }
}

public sealed class SeerrPageInfo
{
    /// <summary>Quanti elementi in tutto.</summary>
    public int Results { get; set; }
}

public sealed class SeerrPage<T>
{
    public SeerrPageInfo? PageInfo { get; set; }

    public List<T> Results { get; set; } = [];
}

public sealed class SeerrMainSettings
{
    public int DefaultPermissions { get; set; }
}

public sealed class SeerrSearchPage
{
    public List<SeerrSearchResult> Results { get; set; } = [];
}

public sealed class SeerrSearchResult
{
    /// <summary>Id TMDB.</summary>
    public int Id { get; set; }

    /// <summary>"movie", "tv" o "person".</summary>
    public string? MediaType { get; set; }

    /// <summary>Film.</summary>
    public string? Title { get; set; }

    /// <summary>Serie e persone.</summary>
    public string? Name { get; set; }

    public string? ReleaseDate { get; set; }

    public string? FirstAirDate { get; set; }

    public string? PosterPath { get; set; }

    public SeerrMediaInfo? MediaInfo { get; set; }
}

public sealed class SeerrMediaInfo
{
    public int Status { get; set; }

    public string? JellyfinMediaId { get; set; }

    public List<SeerrMediaSeason> Seasons { get; set; } = [];

    public List<SeerrRequest> Requests { get; set; } = [];

    public List<SeerrDownload> DownloadStatus { get; set; } = [];
}

public sealed class SeerrMediaSeason
{
    public int SeasonNumber { get; set; }

    public int Status { get; set; }
}

public sealed class SeerrDownload
{
    public double Size { get; set; }

    public double SizeLeft { get; set; }
}

public sealed class SeerrGenre
{
    public string? Name { get; set; }
}

public sealed class SeerrVideo
{
    /// <summary>"Trailer", "Teaser", "Clip"…</summary>
    public string? Type { get; set; }

    public string? Site { get; set; }

    public string? Url { get; set; }
}

public sealed class SeerrMovie
{
    public int Id { get; set; }

    public string? Title { get; set; }

    public string? ReleaseDate { get; set; }

    public string? Overview { get; set; }

    /// <summary>Durata in minuti.</summary>
    public int? Runtime { get; set; }

    public List<SeerrGenre> Genres { get; set; } = [];

    public string? PosterPath { get; set; }

    public string? BackdropPath { get; set; }

    public List<SeerrVideo> RelatedVideos { get; set; } = [];

    public SeerrMediaInfo? MediaInfo { get; set; }
}

public sealed class SeerrTvSeason
{
    public int SeasonNumber { get; set; }

    public int EpisodeCount { get; set; }
}

public sealed class SeerrTv
{
    public int Id { get; set; }

    public string? Name { get; set; }

    public string? FirstAirDate { get; set; }

    public string? Overview { get; set; }

    public List<SeerrGenre> Genres { get; set; } = [];

    public string? PosterPath { get; set; }

    public string? BackdropPath { get; set; }

    public List<SeerrVideo> RelatedVideos { get; set; } = [];

    /// <summary>Anche la stagione 0 (speciali), se TMDB ce l'ha.</summary>
    public List<SeerrTvSeason> Seasons { get; set; } = [];

    public SeerrMediaInfo? MediaInfo { get; set; }
}

public sealed class SeerrRequestUser
{
    public int Id { get; set; }

    public string? DisplayName { get; set; }

    public string? JellyfinUserId { get; set; }
}

public sealed class SeerrRequestSeason
{
    public int SeasonNumber { get; set; }
}

public sealed class SeerrRequestMedia
{
    public int TmdbId { get; set; }

    public string? MediaType { get; set; }

    public int Status { get; set; }

    public string? JellyfinMediaId { get; set; }

    public List<SeerrDownload> DownloadStatus { get; set; } = [];
}

public sealed class SeerrRequest
{
    public int Id { get; set; }

    public int Status { get; set; }

    /// <summary>"movie" o "tv".</summary>
    public string? Type { get; set; }

    public bool Is4k { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public List<SeerrRequestSeason> Seasons { get; set; } = [];

    public SeerrRequestUser? RequestedBy { get; set; }

    public SeerrRequestMedia? Media { get; set; }
}

public sealed class SeerrServer
{
    public int Id { get; set; }

    public string? Name { get; set; }

    public bool Is4k { get; set; }

    public bool IsDefault { get; set; }

    public int? ActiveProfileId { get; set; }

    public string? ActiveDirectory { get; set; }
}

public sealed class SeerrProfile
{
    public int Id { get; set; }

    public string? Name { get; set; }
}

public sealed class SeerrRootFolder
{
    public string? Path { get; set; }
}

public sealed class SeerrServerDetails
{
    public List<SeerrProfile> Profiles { get; set; } = [];

    public List<SeerrRootFolder> RootFolders { get; set; } = [];
}

/// <summary>Corpo di POST /request.</summary>
public sealed class SeerrCreateRequest
{
    public string MediaType { get; set; } = string.Empty;

    /// <summary>Id TMDB.</summary>
    public int MediaId { get; set; }

    /// <summary>Solo per le serie.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<int>? Seasons { get; set; }
}

/// <summary>Corpo di PUT /request/{id}: server, profilo e cartella scelti all'approvazione.</summary>
public sealed class SeerrUpdateRequest
{
    public string MediaType { get; set; } = string.Empty;

    public int ServerId { get; set; }

    public int ProfileId { get; set; }

    public string RootFolder { get; set; } = string.Empty;

    /// <summary>Obbligatorie per le serie: quelle della richiesta.</summary>
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<int>? Seasons { get; set; }
}

/// <summary>Corpo di POST /user/import-from-jellyfin.</summary>
public sealed class SeerrImportUsers
{
    public List<string> JellyfinUserIds { get; set; } = [];
}

/// <summary>
/// Il corpo del webhook, dal modello della pagina del plugin (spec I §7.1):
/// testi già sostituiti da Seerr; "extra" viene dalla chiave speciale
/// "{{extra}}".
/// </summary>
public sealed class SeerrWebhookPayload
{
    public string? Secret { get; set; }

    [JsonPropertyName("notification_type")]
    public string? NotificationType { get; set; }

    public string? Subject { get; set; }

    [JsonPropertyName("request_id")]
    public string? RequestId { get; set; }

    [JsonPropertyName("media_type")]
    public string? MediaType { get; set; }

    [JsonPropertyName("media_tmdbid")]
    public string? MediaTmdbId { get; set; }

    [JsonPropertyName("media_jellyfinMediaId")]
    public string? MediaJellyfinMediaId { get; set; }

    [JsonPropertyName("requestedBy_jellyfinUserId")]
    public string? RequestedByJellyfinUserId { get; set; }

    [JsonPropertyName("requestedBy_username")]
    public string? RequestedByUsername { get; set; }

    public List<SeerrWebhookExtra>? Extra { get; set; }
}

public sealed class SeerrWebhookExtra
{
    public string? Name { get; set; }

    public string? Value { get; set; }
}
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the Seerr JSON shapes, errors and permissions"
```

### Task 3: `SeerrClient`

**Files:**
- Create: `…/Seerr/ISeerrClient.cs`, `…/Seerr/SeerrClient.cs`
- Create: `…Tests/FakeSeerrHttp.cs`
- Test: `…Tests/SeerrClientTests.cs`

- [ ] **Step 1: il finto HTTP**

`…Tests/FakeSeerrHttp.cs`:

```csharp
using System.Net;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Una richiesta vista da <see cref="FakeSeerrHttp"/>.</summary>
internal sealed record SeenRequest(HttpMethod Method, Uri Uri, string? ApiKey, string? ApiUser, string? Body);

/// <summary>HTTP finto per SeerrClient: registra le richieste e risponde con <see cref="Respond"/>.</summary>
internal sealed class FakeSeerrHttp : HttpMessageHandler, IHttpClientFactory
{
    public List<SeenRequest> Requests { get; } = [];

    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Respond { get; set; } =
        (_, _) => Task.FromResult(Json(HttpStatusCode.OK, "{}"));

    /// <summary>Il nome con cui SeerrClient ha chiesto l'ultimo client.</summary>
    public string? LastClientName { get; private set; }

    public HttpClient CreateClient(string name)
    {
        LastClientName = name;
        return new HttpClient(this, disposeHandler: false);
    }

    public static HttpResponseMessage Json(HttpStatusCode status, string json) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(new SeenRequest(
            request.Method, request.RequestUri!, Header(request, "X-API-Key"), Header(request, "X-API-User"), body));
        return await Respond(request, cancellationToken);
    }

    private static string? Header(HttpRequestMessage request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? values.Single() : null;
}
```

- [ ] **Step 2: test che falliscono**

`…Tests/SeerrClientTests.cs`:

```csharp
using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrClientTests
{
    private readonly FakeSeerrHttp _http = new();
    private readonly FakeSeerrSettings _settings = new() { Url = "https://seerr.example/seerr", ApiKey = "segreta" };
    private readonly RecordingLogger<SeerrClient> _logger = new();

    private SeerrClient Client(TimeSpan? timeout = null) =>
        new(_http, _settings, _logger) { Timeout = timeout ?? SeerrClient.DefaultTimeout };

    private void Answer(HttpStatusCode status, string json) =>
        _http.Respond = (_, _) => Task.FromResult(FakeSeerrHttp.Json(status, json));

    [Fact]
    public async Task EveryCallCarriesTheKeyAndTheUserOnlyWhenActingForSomeone()
    {
        Answer(HttpStatusCode.OK, """{"version":"3.4.1"}""");
        var status = await Client().GetStatusAsync(CancellationToken.None);

        Assert.Equal("3.4.1", status.Version);
        var seen = Assert.Single(_http.Requests);
        Assert.Equal("https://seerr.example/seerr/api/v1/status", seen.Uri.OriginalString);
        Assert.Equal("segreta", seen.ApiKey);
        Assert.Null(seen.ApiUser);
        Assert.Equal(SeerrClient.HttpClientName, _http.LastClientName);

        Answer(HttpStatusCode.Created, """{"id":7,"status":1,"type":"tv"}""");
        var created = await Client().CreateRequestAsync(
            12, new SeerrCreateRequest { MediaType = "tv", MediaId = 90228, Seasons = [1] }, CancellationToken.None);

        Assert.Equal(7, created.Id);
        var post = _http.Requests[1];
        Assert.Equal(HttpMethod.Post, post.Method);
        Assert.Equal("https://seerr.example/seerr/api/v1/request", post.Uri.OriginalString);
        Assert.Equal("12", post.ApiUser);
        Assert.Equal("""{"mediaType":"tv","mediaId":90228,"seasons":[1]}""", post.Body);
    }

    [Fact]
    public async Task PathsQueriesAndBodies()
    {
        _http.Respond = (request, _) => Task.FromResult(FakeSeerrHttp.Json(
            HttpStatusCode.OK,
            request.RequestUri!.AbsolutePath.EndsWith("/service/radarr", StringComparison.Ordinal)
                ? "[]"
                : """{"id":1,"status":2,"pageInfo":{"results":0},"results":[]}"""));
        var client = Client();

        await client.SearchAsync("l'ultimo (2)", "it", CancellationToken.None);
        await client.GetRequestsAsync(3, "pending", 20, 40, 3, CancellationToken.None);
        await client.GetRequestsAsync(3, "all", 20, 0, null, CancellationToken.None);
        await client.GetServersAsync(SeerrServices.Radarr, CancellationToken.None);
        await client.GetServerDetailsAsync(SeerrServices.Sonarr, 0, CancellationToken.None);
        await client.GetMovieAsync(438631, "it", CancellationToken.None);
        await client.GetTvAsync(90228, "en", CancellationToken.None);
        await client.GetUsersAsync(CancellationToken.None);
        await client.GetMainSettingsAsync(CancellationToken.None);
        await client.ImportJellyfinUserAsync(Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5"), CancellationToken.None);
        await client.SetRequestStatusAsync(3, 434, approve: true, CancellationToken.None);
        await client.SetRequestStatusAsync(3, 435, approve: false, CancellationToken.None);
        await client.GetRequestAsync(3, 434, CancellationToken.None);
        await client.UpdateRequestAsync(
            3, 434, new SeerrUpdateRequest { MediaType = "movie", ServerId = 1, ProfileId = 7, RootFolder = "/media/anime" },
            CancellationToken.None);

        string Path(int i) => _http.Requests[i].Uri.OriginalString["https://seerr.example/seerr/api/v1/".Length..];
        Assert.Equal("search?query=l%27ultimo%20%282%29&page=1&language=it", Path(0));
        Assert.Equal("request?take=20&skip=40&filter=pending&sort=added&sortDirection=desc&requestedBy=3", Path(1));
        Assert.Equal("3", _http.Requests[1].ApiUser);
        Assert.Equal("request?take=20&skip=0&filter=all&sort=added&sortDirection=desc", Path(2));
        Assert.Equal("service/radarr", Path(3));
        Assert.Null(_http.Requests[3].ApiUser);
        Assert.Equal("service/sonarr/0", Path(4));
        Assert.Equal("movie/438631?language=it", Path(5));
        Assert.Equal("tv/90228?language=en", Path(6));
        Assert.Equal($"user?take={SeerrClient.MaxUsers}&skip=0", Path(7));
        Assert.Equal("settings/main", Path(8));
        Assert.Equal("user/import-from-jellyfin", Path(9));
        Assert.Equal("""{"jellyfinUserIds":["150fe35a657b4c5ea4fd644c4c5152b5"]}""", _http.Requests[9].Body);
        Assert.Equal("request/434/approve", Path(10));
        Assert.Equal(HttpMethod.Post, _http.Requests[10].Method);
        Assert.Equal("request/435/decline", Path(11));
        Assert.Equal("request/434", Path(12));
        Assert.Equal(HttpMethod.Get, _http.Requests[12].Method);
        Assert.Equal(HttpMethod.Put, _http.Requests[13].Method);
        Assert.Equal(
            """{"mediaType":"movie","serverId":1,"profileId":7,"rootFolder":"/media/anime"}""", _http.Requests[13].Body);
    }

    [Theory]
    [InlineData(403, """{"message":"Movie Quota exceeded."}""", false, SeerrError.QuotaExceeded)]
    [InlineData(403, """{"message":"This media is blocklisted."}""", false, SeerrError.Blocklisted)]
    [InlineData(403, """{"message":"You do not have permission to make movie requests."}""", false, SeerrError.NoPermission)]
    [InlineData(403, """{"error":"You do not have permission to access this endpoint"}""", true, SeerrError.Auth)]
    [InlineData(401, "{}", false, SeerrError.Auth)]
    [InlineData(409, "{}", false, SeerrError.AlreadyRequested)]
    [InlineData(404, "{}", false, SeerrError.NotFound)]
    [InlineData(400, "{}", false, SeerrError.BadRequest)]
    [InlineData(500, "{}", false, SeerrError.Unavailable)]
    public void ClassifiesSeerrErrors(int status, string message, bool asAdmin, SeerrError expected) =>
        Assert.Equal(expected, SeerrClient.Classify(status, message, asAdmin));

    [Fact]
    public async Task AnErrorResponseBecomesASeerrExceptionAndTheKeyNeverReachesTheLog()
    {
        Answer(HttpStatusCode.Forbidden, """{"message":"Series Quota exceeded."}""");

        var error = await Assert.ThrowsAsync<SeerrException>(() => Client().CreateRequestAsync(
            5, new SeerrCreateRequest { MediaType = "tv", MediaId = 1, Seasons = [1] }, CancellationToken.None));

        Assert.Equal(SeerrError.QuotaExceeded, error.Error);
        Assert.NotEmpty(_logger.Entries);
        Assert.DoesNotContain(_logger.Entries, e => e.Message.Contains("segreta", StringComparison.Ordinal));
    }

    [Fact]
    public async Task AcceptedOnANewRequestOrAnUpdateMeansNothingToRequest()
    {
        Answer(HttpStatusCode.Accepted, """{"status":202,"message":"No seasons available to request"}""");

        var create = await Assert.ThrowsAsync<SeerrException>(() => Client().CreateRequestAsync(
            1, new SeerrCreateRequest { MediaType = "tv", MediaId = 1, Seasons = [1] }, CancellationToken.None));
        var update = await Assert.ThrowsAsync<SeerrException>(() => Client().UpdateRequestAsync(
            1, 2, new SeerrUpdateRequest { MediaType = "tv", Seasons = [1] }, CancellationToken.None));

        Assert.Equal(SeerrError.NothingToRequest, create.Error);
        Assert.Equal(SeerrError.NothingToRequest, update.Error);
    }

    [Fact]
    public async Task NotConfiguredDoesNotCallSeerr()
    {
        _settings.ApiKey = string.Empty;

        var error = await Assert.ThrowsAsync<SeerrException>(() => Client().GetStatusAsync(CancellationToken.None));

        Assert.Equal(SeerrError.NotConfigured, error.Error);
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task NetworkErrorsTimeoutsBadJsonAndBadUrlsAreUnavailable()
    {
        async Task<SeerrError> ErrorOf(SeerrClient client) =>
            (await Assert.ThrowsAsync<SeerrException>(() => client.GetStatusAsync(CancellationToken.None))).Error;

        _http.Respond = (_, _) => throw new HttpRequestException("rete");
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client()));

        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "{}");
        };
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client(TimeSpan.FromMilliseconds(50))));

        Answer(HttpStatusCode.OK, "<html>");
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client()));

        _settings.Url = "seerr-senza-schema";
        Assert.Equal(SeerrError.Unavailable, await ErrorOf(Client()));
    }

    [Fact]
    public async Task ACancelledCallerGetsTheCancellation()
    {
        using var cancel = new CancellationTokenSource();
        _http.Respond = async (_, ct) =>
        {
            await cancel.CancelAsync();
            await Task.Delay(Timeout.Infinite, ct);
            return FakeSeerrHttp.Json(HttpStatusCode.OK, "{}");
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Client().GetStatusAsync(cancel.Token));
    }
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~SeerrClientTests"`
Expected: FAIL di compilazione (`SeerrClient` non esiste).

- [ ] **Step 4: implementazione**

`Seerr/ISeerrClient.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// Le chiamate a Seerr che servono al plugin (spec I §7.2). asUser è l'id
/// Seerr per conto di cui si agisce (X-API-User); le altre agiscono come
/// l'utente 1 (admin). Lanciano solo SeerrException, o
/// OperationCanceledException se si annulla chi chiama.
/// </summary>
public interface ISeerrClient
{
    Task<SeerrStatusInfo> GetStatusAsync(CancellationToken cancellationToken);

    /// <summary>L'utente della chiave: serve a provarla.</summary>
    Task<SeerrUser> GetMeAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<SeerrUser>> GetUsersAsync(CancellationToken cancellationToken);

    Task ImportJellyfinUserAsync(Guid jellyfinUserId, CancellationToken cancellationToken);

    Task<SeerrMainSettings> GetMainSettingsAsync(CancellationToken cancellationToken);

    /// <summary>La prima pagina della ricerca (film, serie e persone).</summary>
    Task<IReadOnlyList<SeerrSearchResult>> SearchAsync(string query, string language, CancellationToken cancellationToken);

    Task<SeerrMovie> GetMovieAsync(int tmdbId, string language, CancellationToken cancellationToken);

    Task<SeerrTv> GetTvAsync(int tmdbId, string language, CancellationToken cancellationToken);

    Task<SeerrRequest> CreateRequestAsync(int asUser, SeerrCreateRequest body, CancellationToken cancellationToken);

    /// <summary>Le richieste dalla più recente; filter "all" o "pending", requestedBy per le proprie.</summary>
    Task<SeerrPage<SeerrRequest>> GetRequestsAsync(
        int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken cancellationToken);

    Task<SeerrRequest> GetRequestAsync(int asUser, int requestId, CancellationToken cancellationToken);

    Task UpdateRequestAsync(int asUser, int requestId, SeerrUpdateRequest body, CancellationToken cancellationToken);

    /// <summary>Approva o rifiuta; restituisce la richiesta aggiornata.</summary>
    Task<SeerrRequest> SetRequestStatusAsync(int asUser, int requestId, bool approve, CancellationToken cancellationToken);

    /// <summary>I server di un servizio (<see cref="SeerrServices"/>).</summary>
    Task<IReadOnlyList<SeerrServer>> GetServersAsync(string service, CancellationToken cancellationToken);

    Task<SeerrServerDetails> GetServerDetailsAsync(string service, int serverId, CancellationToken cancellationToken);
}
```

`Seerr/SeerrClient.cs`:

```csharp
using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// HTTP verso Seerr (spec I §7.2): X-API-Key su ogni chiamata, X-API-User
/// su quelle fatte per conto di un utente. Nel registro vanno solo metodo,
/// percorso ed esito: mai la chiave, mai la query.
/// </summary>
public sealed class SeerrClient(
    IHttpClientFactory httpClientFactory,
    ISeerrSettings settings,
    ILogger<SeerrClient> logger) : ISeerrClient
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixSeerr";

    /// <summary>Utenti letti in una volta (sul server sono 28).</summary>
    public const int MaxUsers = 1000;

    /// <summary>Attesa massima di una risposta di Seerr (spec I §7.2).</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public Task<SeerrStatusInfo> GetStatusAsync(CancellationToken cancellationToken) =>
        SendAsync<SeerrStatusInfo>(HttpMethod.Get, "status", null, null, cancellationToken);

    public Task<SeerrUser> GetMeAsync(CancellationToken cancellationToken) =>
        SendAsync<SeerrUser>(HttpMethod.Get, "auth/me", null, null, cancellationToken);

    public async Task<IReadOnlyList<SeerrUser>> GetUsersAsync(CancellationToken cancellationToken) =>
        (await SendAsync<SeerrPage<SeerrUser>>(
            HttpMethod.Get, $"user?take={MaxUsers}&skip=0", null, null, cancellationToken).ConfigureAwait(false)).Results;

    public Task ImportJellyfinUserAsync(Guid jellyfinUserId, CancellationToken cancellationToken) =>
        SendAsync<JsonElement>(
            HttpMethod.Post,
            "user/import-from-jellyfin",
            null,
            new SeerrImportUsers { JellyfinUserIds = [jellyfinUserId.ToString("N")] },
            cancellationToken);

    public Task<SeerrMainSettings> GetMainSettingsAsync(CancellationToken cancellationToken) =>
        SendAsync<SeerrMainSettings>(HttpMethod.Get, "settings/main", null, null, cancellationToken);

    public async Task<IReadOnlyList<SeerrSearchResult>> SearchAsync(
        string query, string language, CancellationToken cancellationToken) =>
        (await SendAsync<SeerrSearchPage>(
            HttpMethod.Get,
            $"search?query={Uri.EscapeDataString(query)}&page=1&language={Uri.EscapeDataString(language)}",
            null,
            null,
            cancellationToken).ConfigureAwait(false)).Results;

    public Task<SeerrMovie> GetMovieAsync(int tmdbId, string language, CancellationToken cancellationToken) =>
        SendAsync<SeerrMovie>(
            HttpMethod.Get, $"movie/{tmdbId}?language={Uri.EscapeDataString(language)}", null, null, cancellationToken);

    public Task<SeerrTv> GetTvAsync(int tmdbId, string language, CancellationToken cancellationToken) =>
        SendAsync<SeerrTv>(
            HttpMethod.Get, $"tv/{tmdbId}?language={Uri.EscapeDataString(language)}", null, null, cancellationToken);

    public Task<SeerrRequest> CreateRequestAsync(int asUser, SeerrCreateRequest body, CancellationToken cancellationToken) =>
        SendAsync<SeerrRequest>(
            HttpMethod.Post, "request", asUser, body, cancellationToken, acceptedMeans: SeerrError.NothingToRequest);

    public Task<SeerrPage<SeerrRequest>> GetRequestsAsync(
        int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken cancellationToken)
    {
        var path = $"request?take={take}&skip={skip}&filter={Uri.EscapeDataString(filter)}&sort=added&sortDirection=desc";
        if (requestedBy is { } user)
        {
            path += $"&requestedBy={user}";
        }

        return SendAsync<SeerrPage<SeerrRequest>>(HttpMethod.Get, path, asUser, null, cancellationToken);
    }

    public Task<SeerrRequest> GetRequestAsync(int asUser, int requestId, CancellationToken cancellationToken) =>
        SendAsync<SeerrRequest>(HttpMethod.Get, $"request/{requestId}", asUser, null, cancellationToken);

    public Task UpdateRequestAsync(
        int asUser, int requestId, SeerrUpdateRequest body, CancellationToken cancellationToken) =>
        SendAsync<JsonElement>(
            HttpMethod.Put, $"request/{requestId}", asUser, body, cancellationToken,
            acceptedMeans: SeerrError.NothingToRequest);

    public Task<SeerrRequest> SetRequestStatusAsync(
        int asUser, int requestId, bool approve, CancellationToken cancellationToken) =>
        SendAsync<SeerrRequest>(
            HttpMethod.Post, $"request/{requestId}/{(approve ? "approve" : "decline")}", asUser, null, cancellationToken);

    public async Task<IReadOnlyList<SeerrServer>> GetServersAsync(string service, CancellationToken cancellationToken) =>
        await SendAsync<List<SeerrServer>>(HttpMethod.Get, $"service/{service}", null, null, cancellationToken)
            .ConfigureAwait(false);

    public Task<SeerrServerDetails> GetServerDetailsAsync(string service, int serverId, CancellationToken cancellationToken) =>
        SendAsync<SeerrServerDetails>(HttpMethod.Get, $"service/{service}/{serverId}", null, null, cancellationToken);

    /// <summary>
    /// Da stato e messaggio di Seerr all'errore. Una chiamata senza
    /// X-API-User agisce come l'utente 1 (admin): lì un 403 vuol dire chiave
    /// rifiutata, perché Seerr risponde 403 (non 401) senza utente.
    /// </summary>
    internal static SeerrError Classify(int status, string message, bool asAdmin) => status switch
    {
        401 => SeerrError.Auth,
        403 when asAdmin => SeerrError.Auth,
        403 when message.Contains("quota", StringComparison.OrdinalIgnoreCase) => SeerrError.QuotaExceeded,
        403 when message.Contains("blocklist", StringComparison.OrdinalIgnoreCase) => SeerrError.Blocklisted,
        403 => SeerrError.NoPermission,
        404 => SeerrError.NotFound,
        409 => SeerrError.AlreadyRequested,
        400 => SeerrError.BadRequest,
        _ => SeerrError.Unavailable,
    };

    private async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        int? asUser,
        object? body,
        CancellationToken cancellationToken,
        SeerrError? acceptedMeans = null)
    {
        var baseUrl = settings.Url;
        var key = settings.ApiKey;
        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(key))
        {
            throw new SeerrException(SeerrError.NotConfigured);
        }

        var logPath = path.Split('?')[0];
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var request = new HttpRequestMessage(method, $"{baseUrl}/api/v1/{path}");
            request.Headers.Add("X-API-Key", key);
            if (asUser is { } user)
            {
                request.Headers.Add("X-API-User", user.ToString(CultureInfo.InvariantCulture));
            }

            if (body is not null)
            {
                request.Content = JsonContent.Create(body, body.GetType(), options: SeerrJson.Options);
            }

            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, timeout.Token)
                .ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.Accepted && acceptedMeans is { } accepted)
            {
                throw new SeerrException(accepted);
            }

            if (!response.IsSuccessStatusCode)
            {
                var message = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
                logger.LogInformation("Seerr {Method} {Path}: {Status}", method, logPath, (int)response.StatusCode);
                throw new SeerrException(Classify((int)response.StatusCode, message, asAdmin: asUser is null));
            }

            return await response.Content.ReadFromJsonAsync<T>(SeerrJson.Options, timeout.Token).ConfigureAwait(false)
                ?? throw new JsonException("risposta vuota");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Seerr {Method} {Path}: nessuna risposta in {Timeout}", method, logPath, Timeout);
            throw new SeerrException(SeerrError.Unavailable);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or NotSupportedException
                                       or InvalidOperationException or UriFormatException)
        {
            logger.LogWarning("Seerr {Method} {Path} non riuscita: {Error}", method, logPath, ex.GetType().Name);
            throw new SeerrException(SeerrError.Unavailable, ex);
        }
    }
}
```

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): call Seerr with the API key and the acting user"
```

### Task 4: oggetti per l'app e regole degli stati (`SeerrMapping`)

**Files:**
- Create: `…/Protocol/RequestsDtos.cs`
- Create: `…/Seerr/SeerrMapping.cs`
- Test: `…Tests/SeerrMappingTests.cs`

- [ ] **Step 1: gli oggetti per l'app**

Servono già ai test di questo task. `Protocol/RequestsDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Stato di un titolo o di una stagione per l'app (spec I §7.3).</summary>
public static class TitleStatuses
{
    public const string None = "None";
    public const string Pending = "Pending";
    public const string Processing = "Processing";
    public const string Partial = "Partial";
    public const string Available = "Available";
}

/// <summary>Stato di una richiesta per l'app (spec I §7.3).</summary>
public static class RequestStatuses
{
    public const string Pending = "Pending";
    public const string Approved = "Approved";
    public const string Downloading = "Downloading";
    public const string Partial = "Partial";
    public const string Available = "Available";
    public const string Declined = "Declined";
    public const string Failed = "Failed";
}

/// <summary>I due tipi di titolo, con i nomi di Seerr.</summary>
public static class RequestMediaTypes
{
    public const string Movie = "movie";
    public const string Tv = "tv";
}

/// <summary>Risposta di GET Requests/Me.</summary>
public sealed record RequestsMeResponse(
    [property: JsonPropertyName("CanRequest")] bool CanRequest,
    [property: JsonPropertyName("CanManage")] bool CanManage,
    [property: JsonPropertyName("HasAccount")] bool HasAccount);

/// <summary>Un risultato di GET Requests/Search.</summary>
public sealed record RequestableTitleDto(
    [property: JsonPropertyName("MediaType")] string MediaType,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("PosterPath")] string? PosterPath,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId);

/// <summary>Una stagione di una serie, senza gli speciali.</summary>
public sealed record SeasonDto(
    [property: JsonPropertyName("SeasonNumber")] int SeasonNumber,
    [property: JsonPropertyName("EpisodeCount")] int EpisodeCount,
    [property: JsonPropertyName("Status")] string Status);

/// <summary>Risposta di GET Requests/Movie/{id} e Requests/Tv/{id}; Seasons solo per le serie.</summary>
public sealed record TitleDetailsDto(
    [property: JsonPropertyName("MediaType")] string MediaType,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("Overview")] string? Overview,
    [property: JsonPropertyName("Genres")] IReadOnlyList<string> Genres,
    [property: JsonPropertyName("RuntimeMinutes")] int? RuntimeMinutes,
    [property: JsonPropertyName("PosterPath")] string? PosterPath,
    [property: JsonPropertyName("BackdropPath")] string? BackdropPath,
    [property: JsonPropertyName("TrailerUrl")] string? TrailerUrl,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId,
    [property: JsonPropertyName("RequestedByMe")] bool RequestedByMe,
    [property: JsonPropertyName("Requested")] bool Requested,
    [property: JsonPropertyName("Seasons"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    IReadOnlyList<SeasonDto>? Seasons);

/// <summary>Corpo di POST Requests.</summary>
public sealed class CreateRequestBody
{
    [JsonPropertyName("MediaType")]
    public string? MediaType { get; set; }

    [JsonPropertyName("TmdbId")]
    public int TmdbId { get; set; }

    /// <summary>Solo per le serie: le stagioni scelte.</summary>
    [JsonPropertyName("Seasons")]
    public List<int>? Seasons { get; set; }
}

/// <summary>Risposta di POST Requests: Status è "Pending" o, se Seerr l'ha approvata da sola, un altro stato.</summary>
public sealed record CreatedRequestDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("Status")] string Status);

/// <summary>Chi ha chiesto il titolo.</summary>
public sealed record RequesterDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("IsMe")] bool IsMe);

/// <summary>Una richiesta negli elenchi (spec I §7.3); Title vuoto se Seerr non l'ha dato.</summary>
public sealed record MediaRequestDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("MediaType")] string MediaType,
    [property: JsonPropertyName("TmdbId")] int TmdbId,
    [property: JsonPropertyName("Title")] string Title,
    [property: JsonPropertyName("Year")] int? Year,
    [property: JsonPropertyName("PosterPath")] string? PosterPath,
    [property: JsonPropertyName("Seasons")] IReadOnlyList<int> Seasons,
    [property: JsonPropertyName("RequestedBy")] RequesterDto RequestedBy,
    [property: JsonPropertyName("CreatedAt")] DateTimeOffset CreatedAt,
    [property: JsonPropertyName("Status")] string Status,
    [property: JsonPropertyName("Progress")] double? Progress,
    [property: JsonPropertyName("JellyfinItemId")] string? JellyfinItemId);

/// <summary>Risposta di GET Requests.</summary>
public sealed record RequestPageDto(
    [property: JsonPropertyName("Items")] IReadOnlyList<MediaRequestDto> Items,
    [property: JsonPropertyName("HasMore")] bool HasMore);

public sealed record ProfileDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("Name")] string Name);

/// <summary>Un server di Radarr o Sonarr per la finestra Approva.</summary>
public sealed record ServiceDto(
    [property: JsonPropertyName("Id")] int Id,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("IsDefault")] bool IsDefault,
    [property: JsonPropertyName("Profiles")] IReadOnlyList<ProfileDto> Profiles,
    [property: JsonPropertyName("RootFolders")] IReadOnlyList<string> RootFolders,
    [property: JsonPropertyName("DefaultProfileId")] int? DefaultProfileId,
    [property: JsonPropertyName("DefaultRootFolder")] string? DefaultRootFolder);

/// <summary>Corpo di POST Requests/{id}/Approve: tutto vuoto = valori predefiniti di Seerr.</summary>
public sealed class ApproveBody
{
    [JsonPropertyName("ServerId")]
    public int? ServerId { get; set; }

    [JsonPropertyName("ProfileId")]
    public int? ProfileId { get; set; }

    [JsonPropertyName("RootFolder")]
    public string? RootFolder { get; set; }
}

/// <summary>Corpo degli errori degli endpoint delle richieste (spec I §7.3).</summary>
public sealed record RequestsErrorDto(
    [property: JsonPropertyName("Code")] string Code);

/// <summary>Risposta di POST Requests/Test (pagina del plugin).</summary>
public sealed record SeerrTestResponse(
    [property: JsonPropertyName("Ok")] bool Ok,
    [property: JsonPropertyName("Version")] string? Version,
    [property: JsonPropertyName("Error")] string? Error);

/// <summary>Risposta di GET Requests/Admin (pagina del plugin).</summary>
public sealed record RequestsAdminStatus(
    [property: JsonPropertyName("Configured")] bool Configured,
    [property: JsonPropertyName("LastEventAt")] DateTimeOffset? LastEventAt,
    [property: JsonPropertyName("LastEventType")] string? LastEventType);
```

- [ ] **Step 2: test che falliscono**

`…Tests/SeerrMappingTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrMappingTests
{
    private static SeerrRequest Request(int status, int mediaStatus = SeerrCodes.MediaUnknown, params int[] seasons) => new()
    {
        Status = status,
        Seasons = seasons.Select(n => new SeerrRequestSeason { SeasonNumber = n }).ToList(),
        Media = new SeerrRequestMedia { Status = mediaStatus },
    };

    [Theory]
    [InlineData("2024-02-27", 2024)]
    [InlineData("2026", 2026)]
    [InlineData("", null)]
    [InlineData(null, null)]
    [InlineData("abcd-01-01", null)]
    public void YearFromASeerrDate(string? date, int? year) => Assert.Equal(year, SeerrMapping.Year(date));

    [Theory]
    [InlineData("EE39BEF06F503DD0E9DBD20593DF417F", "ee39bef06f503dd0e9dbd20593df417f")]
    [InlineData("ee39bef0-6f50-3dd0-e9db-d20593df417f", "ee39bef06f503dd0e9dbd20593df417f")]
    [InlineData("00000000000000000000000000000000", null)]
    [InlineData("", null)]
    [InlineData(null, null)]
    public void JellyfinIdsInNFormat(string? raw, string? id) => Assert.Equal(id, SeerrMapping.JellyfinId(raw));

    [Theory]
    [InlineData(null, TitleStatuses.None)]
    [InlineData(SeerrCodes.MediaUnknown, TitleStatuses.None)]
    [InlineData(SeerrCodes.MediaPending, TitleStatuses.Pending)]
    [InlineData(SeerrCodes.MediaProcessing, TitleStatuses.Processing)]
    [InlineData(SeerrCodes.MediaPartial, TitleStatuses.Partial)]
    [InlineData(SeerrCodes.MediaAvailable, TitleStatuses.Available)]
    [InlineData(SeerrCodes.MediaBlocklisted, TitleStatuses.None)]
    [InlineData(SeerrCodes.MediaDeleted, TitleStatuses.None)]
    public void TitleStatusFromSeerr(int? status, string expected) =>
        Assert.Equal(expected, SeerrMapping.TitleStatus(status));

    [Fact]
    public void SeasonsWithoutSpecialsAndWithTheirStatus()
    {
        var tv = new SeerrTv
        {
            Seasons =
            [
                new() { SeasonNumber = 3, EpisodeCount = 10 },
                new() { SeasonNumber = 0, EpisodeCount = 2 },
                new() { SeasonNumber = 1, EpisodeCount = 8 },
                new() { SeasonNumber = 2, EpisodeCount = 9 },
                new() { SeasonNumber = 4, EpisodeCount = 6 },
                new() { SeasonNumber = 5, EpisodeCount = 6 },
            ],
            MediaInfo = new SeerrMediaInfo
            {
                Status = SeerrCodes.MediaPartial,
                Seasons = [new() { SeasonNumber = 1, Status = SeerrCodes.MediaAvailable }],
                Requests =
                [
                    Request(SeerrCodes.RequestPending, SeerrCodes.MediaPartial, 2),
                    Request(SeerrCodes.RequestApproved, SeerrCodes.MediaPartial, 3),
                    Request(SeerrCodes.RequestDeclined, SeerrCodes.MediaPartial, 4),
                ],
            },
        };

        var seasons = SeerrMapping.Seasons(tv);

        Assert.Equal(new[] { 1, 2, 3, 4, 5 }, seasons.Select(s => s.SeasonNumber));
        Assert.Equal(8, seasons[0].EpisodeCount);
        Assert.Equal(
            new[] { TitleStatuses.Available, TitleStatuses.Pending, TitleStatuses.Processing, TitleStatuses.None, TitleStatuses.None },
            seasons.Select(s => s.Status));
    }

    [Fact]
    public void SeasonsOfASeriesSeerrDoesNotKnowAreAllRequestable()
    {
        var tv = new SeerrTv { Seasons = [new() { SeasonNumber = 1, EpisodeCount = 6 }] };

        Assert.Equal(TitleStatuses.None, Assert.Single(SeerrMapping.Seasons(tv)).Status);
    }

    [Fact]
    public void RequestStatusInTheOrderOfThePlan()
    {
        Assert.Equal(RequestStatuses.Declined, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestDeclined, SeerrCodes.MediaAvailable)));
        Assert.Equal(RequestStatuses.Failed, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestFailed)));
        Assert.Equal(RequestStatuses.Pending, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestPending, SeerrCodes.MediaPartial)));
        Assert.Equal(RequestStatuses.Available, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestCompleted, SeerrCodes.MediaPartial)));
        Assert.Equal(RequestStatuses.Available, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaAvailable)));
        Assert.Equal(RequestStatuses.Partial, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestApproved, SeerrCodes.MediaPartial)));
        Assert.Equal(RequestStatuses.Approved, SeerrMapping.RequestStatus(Request(SeerrCodes.RequestApproved)));

        var downloading = Request(SeerrCodes.RequestApproved, SeerrCodes.MediaProcessing);
        downloading.Media!.DownloadStatus.Add(new SeerrDownload { Size = 1000, SizeLeft = 250 });
        Assert.Equal(RequestStatuses.Downloading, SeerrMapping.RequestStatus(downloading));
    }

    [Fact]
    public void ProgressOfTheFirstDownload()
    {
        Assert.Null(SeerrMapping.Progress([]));
        Assert.Null(SeerrMapping.Progress([new SeerrDownload { Size = 0, SizeLeft = 0 }]));
        Assert.Equal(0.75, SeerrMapping.Progress([new SeerrDownload { Size = 1000, SizeLeft = 250 }]));
        Assert.Equal(0.0, SeerrMapping.Progress([new SeerrDownload { Size = 1000, SizeLeft = 2000 }]));
    }

    [Fact]
    public void TrailerFirstThenTeaserOnlyFromYouTubeOverHttp()
    {
        Assert.Equal(
            "https://www.youtube.com/watch?v=t",
            SeerrMapping.TrailerUrl(
            [
                new() { Type = "Teaser", Site = "YouTube", Url = "https://www.youtube.com/watch?v=s" },
                new() { Type = "Trailer", Site = "Vimeo", Url = "https://vimeo.com/1" },
                new() { Type = "Trailer", Site = "YouTube", Url = "https://www.youtube.com/watch?v=t" },
            ]));
        Assert.Equal(
            "https://www.youtube.com/watch?v=s",
            SeerrMapping.TrailerUrl([new() { Type = "Teaser", Site = "YouTube", Url = "https://www.youtube.com/watch?v=s" }]));
        Assert.Null(SeerrMapping.TrailerUrl([new() { Type = "Trailer", Site = "YouTube", Url = "javascript:alert(1)" }]));
        Assert.Null(SeerrMapping.TrailerUrl([]));
    }

    [Fact]
    public void RequestedAndRequestedByMeCountOnlyOpenRequests()
    {
        var info = new SeerrMediaInfo
        {
            Requests =
            [
                new() { Status = SeerrCodes.RequestDeclined, RequestedBy = new() { Id = 5 } },
                new() { Status = SeerrCodes.RequestApproved, RequestedBy = new() { Id = 7 } },
            ],
        };

        Assert.True(SeerrMapping.Requested(info));
        Assert.True(SeerrMapping.RequestedBy(info, 7));
        Assert.False(SeerrMapping.RequestedBy(info, 5));
        Assert.False(SeerrMapping.RequestedBy(info, null));
        Assert.False(SeerrMapping.Requested(null));
    }
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~SeerrMappingTests"`
Expected: FAIL di compilazione (`SeerrMapping` non esiste).

- [ ] **Step 4: implementazione**

`Seerr/SeerrMapping.cs`:

```csharp
using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Regole pure da Seerr agli oggetti per l'app (spec I §7.3).</summary>
public static class SeerrMapping
{
    /// <summary>L'anno da una data di Seerr ("2024-02-27"); null se manca.</summary>
    public static int? Year(string? date) =>
        date is { Length: >= 4 }
        && int.TryParse(date.AsSpan(0, 4), NumberStyles.None, CultureInfo.InvariantCulture, out var year)
            ? year
            : null;

    /// <summary>Un id Jellyfin in qualunque formato; null se non è un Guid valido o è vuoto.</summary>
    public static Guid? ParseGuid(string? raw) =>
        Guid.TryParse(raw, out var id) && id != Guid.Empty ? id : null;

    /// <summary>L'id Jellyfin per l'app: formato "N" minuscolo, o null.</summary>
    public static string? JellyfinId(string? raw) => ParseGuid(raw)?.ToString("N");

    /// <summary>Stato di un titolo o di una stagione; sconosciuto, bloccato ed eliminato valgono None.</summary>
    public static string TitleStatus(int? mediaStatus) => mediaStatus switch
    {
        SeerrCodes.MediaPending => TitleStatuses.Pending,
        SeerrCodes.MediaProcessing => TitleStatuses.Processing,
        SeerrCodes.MediaPartial => TitleStatuses.Partial,
        SeerrCodes.MediaAvailable => TitleStatuses.Available,
        _ => TitleStatuses.None,
    };

    public static bool IsBlocklisted(SeerrMediaInfo? info) => info?.Status == SeerrCodes.MediaBlocklisted;

    /// <summary>Richiesta ancora aperta: in attesa o approvata.</summary>
    public static bool IsActive(SeerrRequest request) =>
        request.Status is SeerrCodes.RequestPending or SeerrCodes.RequestApproved;

    /// <summary>C'è una richiesta aperta per il titolo.</summary>
    public static bool Requested(SeerrMediaInfo? info) => info is not null && info.Requests.Any(IsActive);

    /// <summary>C'è una richiesta aperta dell'utente Seerr seerrUserId.</summary>
    public static bool RequestedBy(SeerrMediaInfo? info, int? seerrUserId) =>
        seerrUserId is { } me && info is not null && info.Requests.Any(r => IsActive(r) && r.RequestedBy?.Id == me);

    /// <summary>Le stagioni della serie senza gli speciali (0), in ordine, con lo stato di ognuna.</summary>
    public static IReadOnlyList<SeasonDto> Seasons(SeerrTv tv) =>
        tv.Seasons
            .Where(s => s.SeasonNumber > 0)
            .OrderBy(s => s.SeasonNumber)
            .Select(s => new SeasonDto(s.SeasonNumber, s.EpisodeCount, SeasonStatus(tv.MediaInfo, s.SeasonNumber)))
            .ToList();

    /// <summary>
    /// Lo stato della stagione in Seerr; senza uno stato suo, In attesa o In
    /// lavorazione se una richiesta aperta la contiene (spec I §7.3).
    /// </summary>
    public static string SeasonStatus(SeerrMediaInfo? info, int seasonNumber)
    {
        var own = TitleStatus(info?.Seasons.FirstOrDefault(s => s.SeasonNumber == seasonNumber)?.Status);
        if (own != TitleStatuses.None || info is null)
        {
            return own;
        }

        var requests = info.Requests.Where(r => r.Seasons.Any(s => s.SeasonNumber == seasonNumber)).ToList();
        if (requests.Any(r => r.Status == SeerrCodes.RequestPending))
        {
            return TitleStatuses.Pending;
        }

        return requests.Any(r => r.Status == SeerrCodes.RequestApproved) ? TitleStatuses.Processing : TitleStatuses.None;
    }

    /// <summary>
    /// Stato di una richiesta per l'app, nell'ordine: rifiutata, non
    /// riuscita, in attesa, completata, titolo disponibile, titolo in parte,
    /// download in corso, approvata (spec I §7.3 e decisione 1 del piano 15a).
    /// </summary>
    public static string RequestStatus(SeerrRequest request) => request.Status switch
    {
        SeerrCodes.RequestDeclined => RequestStatuses.Declined,
        SeerrCodes.RequestFailed => RequestStatuses.Failed,
        SeerrCodes.RequestPending => RequestStatuses.Pending,
        SeerrCodes.RequestCompleted => RequestStatuses.Available,
        _ => request.Media?.Status switch
        {
            SeerrCodes.MediaAvailable => RequestStatuses.Available,
            SeerrCodes.MediaPartial => RequestStatuses.Partial,
            _ => request.Media?.DownloadStatus.Count > 0 ? RequestStatuses.Downloading : RequestStatuses.Approved,
        },
    };

    /// <summary>Avanzamento del primo download, da 0 a 1; null senza dimensione.</summary>
    public static double? Progress(IReadOnlyList<SeerrDownload> downloads) =>
        downloads.Count > 0 && downloads[0].Size > 0
            ? Math.Clamp(1 - (downloads[0].SizeLeft / downloads[0].Size), 0, 1)
            : null;

    /// <summary>Il trailer su YouTube: prima "Trailer", poi "Teaser"; solo indirizzi http o https.</summary>
    public static string? TrailerUrl(IEnumerable<SeerrVideo> videos)
    {
        var youtube = videos.Where(v => v.Site == "YouTube" && IsWebUrl(v.Url)).ToList();
        return (youtube.FirstOrDefault(v => v.Type == "Trailer") ?? youtube.FirstOrDefault(v => v.Type == "Teaser"))?.Url;
    }

    /// <summary>I nomi dei generi, senza quelli vuoti.</summary>
    public static IReadOnlyList<string> Genres(IEnumerable<SeerrGenre> genres) =>
        genres.Select(g => g.Name).OfType<string>().Where(n => n.Length > 0).ToList();

    private static bool IsWebUrl(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri)
        && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp);
}
```

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): map Seerr statuses, seasons and trailers for the app"
```

## Gruppo B — plugin, logica

### Task 5: Seerr finto, `SeerrUserMap`, `SeerrTitleCache`

**Files:**
- Create: `…Tests/FakeSeerrClient.cs`
- Create: `…/Seerr/SeerrUserMap.cs`, `…/Seerr/SeerrTitleCache.cs`
- Test: `…Tests/SeerrUserMapTests.cs`, `…Tests/SeerrTitleCacheTests.cs`

- [ ] **Step 1: il Seerr finto**

Serve a questo task e ai successivi. `…Tests/FakeSeerrClient.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Seerr finto, in memoria: dati da preparare e chiamate registrate per nome.</summary>
internal sealed class FakeSeerrClient : ISeerrClient
{
    public string Version { get; set; } = "3.4.1";

    public List<SeerrUser> Users { get; } = [];

    public int DefaultPermissions { get; set; } = SeerrPermissions.Request;

    public List<SeerrSearchResult> SearchResults { get; } = [];

    public Dictionary<int, SeerrMovie> Movies { get; } = [];

    public Dictionary<int, SeerrTv> Shows { get; } = [];

    /// <summary>Tutte le richieste: GetRequests ne dà una pagina, Approve e Decline le cambiano.</summary>
    public List<SeerrRequest> Requests { get; } = [];

    /// <summary>Totale per pageInfo; -1 = quante sono in <see cref="Requests"/>.</summary>
    public int TotalRequests { get; set; } = -1;

    public Dictionary<string, List<SeerrServer>> Servers { get; } = [];

    public Dictionary<(string Service, int Id), SeerrServerDetails> ServerDetails { get; } = [];

    /// <summary>Se impostato, ogni chiamata lancia questo errore.</summary>
    public SeerrError? FailWith { get; set; }

    /// <summary>Errore solo per la chiamata con quel nome (es. "Import", "CreateRequest").</summary>
    public Dictionary<string, SeerrError> FailOn { get; } = [];

    /// <summary>Il nome di ogni chiamata, in ordine.</summary>
    public List<string> Calls { get; } = [];

    public List<(string Query, string Language)> Searches { get; } = [];

    public List<(int AsUser, SeerrCreateRequest Body)> Created { get; } = [];

    public List<(int AsUser, string Filter, int Take, int Skip, int? RequestedBy)> Listed { get; } = [];

    public List<(int AsUser, int RequestId, SeerrUpdateRequest Body)> Updated { get; } = [];

    public List<(int AsUser, int RequestId, bool Approve)> StatusChanges { get; } = [];

    /// <summary>L'utente che l'import crea per un id Jellyfin; null = l'import riesce ma non crea nessuno.</summary>
    public Func<Guid, SeerrUser?> OnImport { get; set; } = _ => null;

    /// <summary>La risposta a una nuova richiesta.</summary>
    public Func<int, SeerrCreateRequest, SeerrRequest> OnCreate { get; set; } =
        (_, body) => new SeerrRequest { Id = 100, Status = SeerrCodes.RequestPending, Type = body.MediaType };

    public Task<SeerrStatusInfo> GetStatusAsync(CancellationToken cancellationToken)
    {
        Call("GetStatus");
        return Task.FromResult(new SeerrStatusInfo { Version = Version });
    }

    public Task<SeerrUser> GetMeAsync(CancellationToken cancellationToken)
    {
        Call("GetMe");
        return Task.FromResult(new SeerrUser { Id = 1, Permissions = SeerrPermissions.Admin });
    }

    public Task<IReadOnlyList<SeerrUser>> GetUsersAsync(CancellationToken cancellationToken)
    {
        Call("GetUsers");
        return Task.FromResult<IReadOnlyList<SeerrUser>>(Users.ToList());
    }

    public Task ImportJellyfinUserAsync(Guid jellyfinUserId, CancellationToken cancellationToken)
    {
        Call("Import");
        if (OnImport(jellyfinUserId) is { } user)
        {
            Users.Add(user);
        }

        return Task.CompletedTask;
    }

    public Task<SeerrMainSettings> GetMainSettingsAsync(CancellationToken cancellationToken)
    {
        Call("GetMainSettings");
        return Task.FromResult(new SeerrMainSettings { DefaultPermissions = DefaultPermissions });
    }

    public Task<IReadOnlyList<SeerrSearchResult>> SearchAsync(
        string query, string language, CancellationToken cancellationToken)
    {
        Call("Search");
        Searches.Add((query, language));
        return Task.FromResult<IReadOnlyList<SeerrSearchResult>>(SearchResults.ToList());
    }

    public Task<SeerrMovie> GetMovieAsync(int tmdbId, string language, CancellationToken cancellationToken)
    {
        Call("GetMovie");
        return Movies.TryGetValue(tmdbId, out var movie)
            ? Task.FromResult(movie)
            : throw new SeerrException(SeerrError.NotFound);
    }

    public Task<SeerrTv> GetTvAsync(int tmdbId, string language, CancellationToken cancellationToken)
    {
        Call("GetTv");
        return Shows.TryGetValue(tmdbId, out var tv)
            ? Task.FromResult(tv)
            : throw new SeerrException(SeerrError.NotFound);
    }

    public Task<SeerrRequest> CreateRequestAsync(int asUser, SeerrCreateRequest body, CancellationToken cancellationToken)
    {
        Call("CreateRequest");
        Created.Add((asUser, body));
        return Task.FromResult(OnCreate(asUser, body));
    }

    public Task<SeerrPage<SeerrRequest>> GetRequestsAsync(
        int asUser, string filter, int take, int skip, int? requestedBy, CancellationToken cancellationToken)
    {
        Call("GetRequests");
        Listed.Add((asUser, filter, take, skip, requestedBy));
        return Task.FromResult(new SeerrPage<SeerrRequest>
        {
            Results = Requests.Skip(skip).Take(take).ToList(),
            PageInfo = new SeerrPageInfo { Results = TotalRequests < 0 ? Requests.Count : TotalRequests },
        });
    }

    public Task<SeerrRequest> GetRequestAsync(int asUser, int requestId, CancellationToken cancellationToken)
    {
        Call("GetRequest");
        return Task.FromResult(Find(requestId));
    }

    public Task UpdateRequestAsync(int asUser, int requestId, SeerrUpdateRequest body, CancellationToken cancellationToken)
    {
        Call("UpdateRequest");
        Updated.Add((asUser, requestId, body));
        return Task.CompletedTask;
    }

    public Task<SeerrRequest> SetRequestStatusAsync(
        int asUser, int requestId, bool approve, CancellationToken cancellationToken)
    {
        Call(approve ? "Approve" : "Decline");
        StatusChanges.Add((asUser, requestId, approve));
        var request = Find(requestId);
        request.Status = approve ? SeerrCodes.RequestApproved : SeerrCodes.RequestDeclined;
        return Task.FromResult(request);
    }

    public Task<IReadOnlyList<SeerrServer>> GetServersAsync(string service, CancellationToken cancellationToken)
    {
        Call("GetServers");
        return Task.FromResult<IReadOnlyList<SeerrServer>>(Servers.GetValueOrDefault(service) ?? []);
    }

    public Task<SeerrServerDetails> GetServerDetailsAsync(string service, int serverId, CancellationToken cancellationToken)
    {
        Call("GetServerDetails");
        return Task.FromResult(ServerDetails[(service, serverId)]);
    }

    private SeerrRequest Find(int requestId) =>
        Requests.FirstOrDefault(r => r.Id == requestId) ?? throw new SeerrException(SeerrError.NotFound);

    private void Call(string name)
    {
        Calls.Add(name);
        if (FailWith is { } error)
        {
            throw new SeerrException(error);
        }

        if (FailOn.TryGetValue(name, out var one))
        {
            throw new SeerrException(one);
        }
    }
}
```

- [ ] **Step 2: test che falliscono**

`…Tests/SeerrUserMapTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrUserMapTests
{
    private static readonly Guid Mario = Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5");
    private static readonly Guid Davide = Guid.Parse("ab8240c5-fc16-49e1-86f6-62fa00ca0fb0");
    private static readonly Guid Stale = Guid.Parse("4135c572-21bd-4677-a3ab-5a7bf3a2fa61");
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new();

    private SeerrUserMap Map() => new(_seerr, _time, NullLogger<SeerrUserMap>.Instance);

    [Fact]
    public async Task MatchesByJellyfinIdInAnyFormatAndTheLowestSeerrIdWins()
    {
        _seerr.Users.Add(new SeerrUser { Id = 9, Permissions = 32, JellyfinUserId = "ab8240c5fc1649e186f662fa00ca0fb0" });
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = "AB8240C5-FC16-49E1-86F6-62FA00CA0FB0" });
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = 2, JellyfinUserId = Stale.ToString("N") });
        var map = Map();

        Assert.Equal(3, (await map.FindAsync(Davide, Ct))!.Id);
        Assert.Null(await map.FindAsync(Mario, Ct));
    }

    [Fact]
    public async Task UsersStayInMemoryForTenMinutes()
    {
        var map = Map();
        await map.FindAsync(Mario, Ct);
        await map.FindAsync(Davide, Ct);
        Assert.Single(_seerr.Calls, "GetUsers");

        _time.Advance(SeerrUserMap.CacheFor);
        await map.FindAsync(Mario, Ct);

        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetUsers"));
    }

    [Fact]
    public async Task EnsureImportsAMissingAccountOnce()
    {
        _seerr.OnImport = id => new SeerrUser { Id = 30, Permissions = 32, JellyfinUserId = id.ToString("N") };
        var map = Map();

        Assert.Equal(30, (await map.EnsureAsync(Mario, Ct)).Id);
        Assert.Equal(new[] { "GetUsers", "Import", "GetUsers" }, _seerr.Calls);
        Assert.Equal(30, (await map.EnsureAsync(Mario, Ct)).Id);
        Assert.Single(_seerr.Calls, "Import");
    }

    [Fact]
    public async Task AnImportThatCreatesNobodyOrIsRefusedMeansAccountUnavailable()
    {
        var map = Map();
        async Task<SeerrError> ErrorOf() =>
            (await Assert.ThrowsAsync<SeerrException>(() => map.EnsureAsync(Mario, Ct))).Error;

        Assert.Equal(SeerrError.AccountUnavailable, await ErrorOf());

        _seerr.FailOn["Import"] = SeerrError.NoPermission;
        Assert.Equal(SeerrError.AccountUnavailable, await ErrorOf());

        // Seerr giù non è un problema dell'account: passa com'è.
        _seerr.FailOn["Import"] = SeerrError.Unavailable;
        Assert.Equal(SeerrError.Unavailable, await ErrorOf());
    }

    [Fact]
    public async Task ManagersAreAdminsAndRequestManagersWithAJellyfinId()
    {
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = 2, JellyfinUserId = Stale.ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = Davide.ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 4, Permissions = 16, JellyfinUserId = null });
        _seerr.Users.Add(new SeerrUser { Id = 5, Permissions = 32, JellyfinUserId = Mario.ToString("N") });

        Assert.Equal(new[] { Stale, Davide }, await Map().ManagerJellyfinIdsAsync(Ct));
    }

    [Fact]
    public async Task DefaultPermissionsAreReadOnceInTenMinutes()
    {
        _seerr.DefaultPermissions = 32;
        var map = Map();

        Assert.Equal(32, await map.DefaultPermissionsAsync(Ct));
        Assert.Equal(32, await map.DefaultPermissionsAsync(Ct));

        Assert.Single(_seerr.Calls, "GetMainSettings");
    }
}
```

`…Tests/SeerrTitleCacheTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrTitleCacheTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new();

    [Fact]
    public async Task TitlesComeFromSeerrOnceAnHourPerLanguage()
    {
        _seerr.Movies[438631] = new SeerrMovie { Title = "Dune", ReleaseDate = "2021-09-15", PosterPath = "/a.jpg" };
        _seerr.Shows[90228] = new SeerrTv { Name = "Dune: Prophecy", FirstAirDate = "2024-11-17" };
        var cache = new SeerrTitleCache(_seerr, _time);

        Assert.Equal(new SeerrTitle("Dune", 2021, "/a.jpg"), await cache.GetAsync("movie", 438631, "it", Ct));
        Assert.Equal(new SeerrTitle("Dune: Prophecy", 2024, null), await cache.GetAsync("tv", 90228, "it", Ct));
        await cache.GetAsync("movie", 438631, "it", Ct);
        Assert.Single(_seerr.Calls, "GetMovie");

        await cache.GetAsync("movie", 438631, "en", Ct);
        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetMovie"));

        _time.Advance(SeerrTitleCache.CacheFor);
        await cache.GetAsync("movie", 438631, "it", Ct);
        Assert.Equal(3, _seerr.Calls.Count(c => c == "GetMovie"));
    }

    [Fact]
    public async Task AMissingTitleIsNullAndNotRemembered()
    {
        var cache = new SeerrTitleCache(_seerr, _time);

        Assert.Null(await cache.GetAsync("movie", 1, "it", Ct));

        _seerr.Movies[1] = new SeerrMovie { Title = "Uno" };
        Assert.Equal("Uno", (await cache.GetAsync("movie", 1, "it", Ct))!.Title);
    }

    [Fact]
    public async Task PutWarmsTheCache()
    {
        var cache = new SeerrTitleCache(_seerr, _time);
        cache.Put("tv", 5, "it", new SeerrTitle("Cinque", null, null));

        Assert.Equal("Cinque", (await cache.GetAsync("tv", 5, "it", Ct))!.Title);
        Assert.Empty(_seerr.Calls);
    }
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~SeerrUserMapTests|FullyQualifiedName~SeerrTitleCacheTests"`
Expected: FAIL di compilazione.

- [ ] **Step 4: implementazione**

`Seerr/SeerrUserMap.cs`:

```csharp
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>
/// Utente Jellyfin → utente Seerr, per jellyfinUserId (spec I §7.2): con più
/// account per lo stesso utente vince l'id Seerr più basso. Utenti e
/// permessi predefiniti restano in memoria per <see cref="CacheFor"/>.
/// Sicuro tra thread.
/// </summary>
public sealed class SeerrUserMap(ISeerrClient seerr, TimeProvider time, ILogger<SeerrUserMap> logger)
{
    /// <summary>Quanto valgono gli utenti e i permessi predefiniti letti da Seerr.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(10);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private Snapshot<IReadOnlyList<SeerrUser>>? _users;
    private Snapshot<int>? _defaultPermissions;

    /// <summary>L'utente Seerr dell'utente Jellyfin; null se non ha un account.</summary>
    public async Task<SeerrUser?> FindAsync(Guid jellyfinUserId, CancellationToken cancellationToken) =>
        Match(await UsersAsync(cancellationToken).ConfigureAwait(false), jellyfinUserId);

    /// <summary>
    /// L'utente Seerr, creato con l'import da Jellyfin se manca (spec I
    /// §7.2). AccountUnavailable se l'import non lo crea; Unavailable e
    /// NotConfigured passano come sono.
    /// </summary>
    public async Task<SeerrUser> EnsureAsync(Guid jellyfinUserId, CancellationToken cancellationToken)
    {
        var user = await FindAsync(jellyfinUserId, cancellationToken).ConfigureAwait(false);
        if (user is not null)
        {
            return user;
        }

        try
        {
            await seerr.ImportJellyfinUserAsync(jellyfinUserId, cancellationToken).ConfigureAwait(false);
        }
        catch (SeerrException ex) when (ex.Error is not (SeerrError.Unavailable or SeerrError.NotConfigured))
        {
            logger.LogWarning("Account Seerr non creato per l'utente {UserId}: {Error}", jellyfinUserId, ex.Error);
            throw new SeerrException(SeerrError.AccountUnavailable, ex);
        }

        Invalidate();
        user = await FindAsync(jellyfinUserId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            logger.LogWarning("Import in Seerr senza account per l'utente {UserId}", jellyfinUserId);
            throw new SeerrException(SeerrError.AccountUnavailable);
        }

        logger.LogInformation("Account Seerr {SeerrId} creato per l'utente {UserId}", user.Id, jellyfinUserId);
        return user;
    }

    /// <summary>Gli id Jellyfin di chi può approvare: account Seerr con ADMIN o MANAGE_REQUESTS.</summary>
    public async Task<IReadOnlyList<Guid>> ManagerJellyfinIdsAsync(CancellationToken cancellationToken) =>
        (await UsersAsync(cancellationToken).ConfigureAwait(false))
            .Where(u => SeerrPermissions.CanManage(u.Permissions))
            .Select(u => SeerrMapping.ParseGuid(u.JellyfinUserId))
            .OfType<Guid>()
            .Distinct()
            .ToList();

    /// <summary>I permessi che Seerr dà ai nuovi account (spec I §7.3, GET Me senza account).</summary>
    public Task<int> DefaultPermissionsAsync(CancellationToken cancellationToken) =>
        CachedAsync(
            () => _defaultPermissions,
            fresh => _defaultPermissions = fresh,
            async ct => (await seerr.GetMainSettingsAsync(ct).ConfigureAwait(false)).DefaultPermissions,
            cancellationToken);

    /// <summary>La prossima lettura chiede di nuovo gli utenti a Seerr (dopo un import).</summary>
    public void Invalidate() => _users = null;

    internal static SeerrUser? Match(IEnumerable<SeerrUser> users, Guid jellyfinUserId) =>
        users.Where(u => SeerrMapping.ParseGuid(u.JellyfinUserId) == jellyfinUserId).MinBy(u => u.Id);

    private Task<IReadOnlyList<SeerrUser>> UsersAsync(CancellationToken cancellationToken) =>
        CachedAsync(() => _users, fresh => _users = fresh, seerr.GetUsersAsync, cancellationToken);

    // Una lettura sola alla volta: chi arriva mentre un'altra è in corso
    // aspetta e usa il suo risultato.
    private async Task<T> CachedAsync<T>(
        Func<Snapshot<T>?> read,
        Action<Snapshot<T>> write,
        Func<CancellationToken, Task<T>> load,
        CancellationToken cancellationToken)
    {
        if (Fresh(read()) is { } hit)
        {
            return hit.Value;
        }

        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (Fresh(read()) is { } again)
            {
                return again.Value;
            }

            var value = await load(cancellationToken).ConfigureAwait(false);
            write(new Snapshot<T>(value, time.GetUtcNow()));
            return value;
        }
        finally
        {
            _gate.Release();
        }
    }

    private Snapshot<T>? Fresh<T>(Snapshot<T>? snapshot) =>
        snapshot is not null && time.GetUtcNow() - snapshot.LoadedAt < CacheFor ? snapshot : null;

    private sealed record Snapshot<T>(T Value, DateTimeOffset LoadedAt);
}
```

`Seerr/SeerrTitleCache.cs`:

```csharp
using System.Collections.Concurrent;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Titolo, anno e locandina di un titolo TMDB.</summary>
public sealed record SeerrTitle(string Title, int? Year, string? PosterPath);

/// <summary>
/// I titoli degli elenchi delle richieste, che Seerr non dà (spec I §7.2):
/// per tipo, id TMDB e lingua, per <see cref="CacheFor"/>, al massimo
/// <see cref="MaxEntries"/>. Sicuro tra thread.
/// </summary>
public sealed class SeerrTitleCache(ISeerrClient seerr, TimeProvider time)
{
    /// <summary>Quanto vale un titolo letto.</summary>
    public static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);

    /// <summary>Titoli al massimo in memoria; oltre si ricomincia da capo.</summary>
    public const int MaxEntries = 2000;

    private readonly ConcurrentDictionary<(string MediaType, int TmdbId, string Language), Entry> _titles = new();

    /// <summary>Il titolo; null se Seerr non lo dà (l'elenco va avanti senza).</summary>
    public async Task<SeerrTitle?> GetAsync(
        string mediaType, int tmdbId, string language, CancellationToken cancellationToken)
    {
        if (_titles.TryGetValue((mediaType, tmdbId, language), out var hit) && time.GetUtcNow() - hit.At < CacheFor)
        {
            return hit.Title;
        }

        SeerrTitle title;
        try
        {
            title = mediaType == RequestMediaTypes.Tv
                ? From(await seerr.GetTvAsync(tmdbId, language, cancellationToken).ConfigureAwait(false))
                : From(await seerr.GetMovieAsync(tmdbId, language, cancellationToken).ConfigureAwait(false));
        }
        catch (SeerrException)
        {
            return null;
        }

        Put(mediaType, tmdbId, language, title);
        return title;
    }

    /// <summary>Mette in memoria un titolo appena letto (dalle schede).</summary>
    public void Put(string mediaType, int tmdbId, string language, SeerrTitle title)
    {
        if (_titles.Count >= MaxEntries)
        {
            _titles.Clear();
        }

        _titles[(mediaType, tmdbId, language)] = new Entry(title, time.GetUtcNow());
    }

    public static SeerrTitle From(SeerrMovie movie) =>
        new(movie.Title ?? string.Empty, SeerrMapping.Year(movie.ReleaseDate), movie.PosterPath);

    public static SeerrTitle From(SeerrTv tv) =>
        new(tv.Name ?? string.Empty, SeerrMapping.Year(tv.FirstAirDate), tv.PosterPath);

    private sealed record Entry(SeerrTitle Title, DateTimeOffset At);
}
```

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): match Jellyfin users to Seerr accounts and cache titles"
```

### Task 6: `RequestsService`

**Files:**
- Create: `…/Hub/RequestsService.cs`
- Test: `…Tests/RequestsServiceTests.cs`

- [ ] **Step 1: test che falliscono**

`…Tests/RequestsServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class RequestsServiceTests
{
    private static readonly Guid Mario = Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5");
    private static readonly Guid Davide = Guid.Parse("ab8240c5-fc16-49e1-86f6-62fa00ca0fb0");
    private static readonly Guid Luigi = Guid.Parse("2c447101-5284-4cc7-9d20-3334f51e8397");
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeTimeProvider _time = new();
    private readonly RequestsService _service;

    public RequestsServiceTests()
    {
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = Davide.ToString("N"), DisplayName = "davide" });
        _seerr.Users.Add(new SeerrUser { Id = 24, Permissions = 32, JellyfinUserId = Mario.ToString("N"), DisplayName = "mario" });
        _service = new RequestsService(
            _seerr, new SeerrUserMap(_seerr, _time, NullLogger<SeerrUserMap>.Instance), new SeerrTitleCache(_seerr, _time));
    }

    private static async Task<SeerrError> ErrorOf(Func<Task> action) =>
        (await Assert.ThrowsAsync<SeerrException>(action)).Error;

    private static SeerrRequest Request(int id, int tmdbId, string type = "movie", int status = SeerrCodes.RequestPending) => new()
    {
        Id = id,
        Status = status,
        Type = type,
        CreatedAt = new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero),
        RequestedBy = new SeerrRequestUser { Id = 24, DisplayName = "mario" },
        Media = new SeerrRequestMedia { TmdbId = tmdbId, MediaType = type, Status = SeerrCodes.MediaUnknown },
    };

    [Theory]
    [InlineData("it", "it")]
    [InlineData("en", "en")]
    [InlineData("IT", "en")]
    [InlineData("ita", "en")]
    [InlineData(null, "en")]
    public void LanguageIsTwoLowercaseLettersOrEnglish(string? raw, string language) =>
        Assert.Equal(language, RequestsService.Language(raw));

    [Fact]
    public async Task MeComesFromTheAccountOrFromTheDefaults()
    {
        Assert.Equal(new RequestsMeResponse(true, false, true), await _service.MeAsync(Mario, Ct));
        Assert.Equal(new RequestsMeResponse(true, true, true), await _service.MeAsync(Davide, Ct));
        Assert.Equal(new RequestsMeResponse(true, false, false), await _service.MeAsync(Luigi, Ct));

        var noDefaults = new FakeSeerrClient { DefaultPermissions = 0 };
        var service = new RequestsService(
            noDefaults, new SeerrUserMap(noDefaults, _time, NullLogger<SeerrUserMap>.Instance), new SeerrTitleCache(noDefaults, _time));
        Assert.Equal(new RequestsMeResponse(false, false, false), await service.MeAsync(Luigi, Ct));
    }

    [Fact]
    public async Task SearchKeepsMoviesAndSeriesWithTheirStatus()
    {
        _seerr.SearchResults.AddRange(
        [
            new SeerrSearchResult
            {
                Id = 438631, MediaType = "movie", Title = "Dune", ReleaseDate = "2021-09-15", PosterPath = "/a.jpg",
                MediaInfo = new SeerrMediaInfo { Status = SeerrCodes.MediaAvailable, JellyfinMediaId = "EE39BEF06F503DD0E9DBD20593DF417F" },
            },
            new SeerrSearchResult { Id = 90228, MediaType = "tv", Name = "Dune: Prophecy", FirstAirDate = "2024-11-17" },
            new SeerrSearchResult { Id = 1, MediaType = "person", Name = "Timothée" },
            new SeerrSearchResult
            {
                Id = 2, MediaType = "movie", Title = "Bloccato", MediaInfo = new SeerrMediaInfo { Status = SeerrCodes.MediaBlocklisted },
            },
        ]);

        var titles = await _service.SearchAsync("  dune ", "it", Ct);

        Assert.Equal(("dune", "it"), Assert.Single(_seerr.Searches));
        Assert.Equal(
            new[]
            {
                new RequestableTitleDto("movie", 438631, "Dune", 2021, "/a.jpg", TitleStatuses.Available, "ee39bef06f503dd0e9dbd20593df417f"),
                new RequestableTitleDto("tv", 90228, "Dune: Prophecy", 2024, null, TitleStatuses.None, null),
            },
            titles);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public async Task SearchNeedsAQuery(string? query)
    {
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.SearchAsync(query, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.SearchAsync(new string('a', RequestsService.MaxQueryLength + 1), "it", Ct)));
        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task MovieDetailsSayWhoRequestedItAndWarmTheTitles()
    {
        _seerr.Movies[1170608] = new SeerrMovie
        {
            Title = "Dune - Parte tre", ReleaseDate = "2026-12-15", Overview = "Paul", Runtime = 140,
            Genres = [new() { Name = "Fantascienza" }, new() { Name = "" }],
            PosterPath = "/p.jpg", BackdropPath = "/b.jpg",
            RelatedVideos = [new() { Type = "Trailer", Site = "YouTube", Url = "https://www.youtube.com/watch?v=x" }],
            MediaInfo = new SeerrMediaInfo
            {
                Status = SeerrCodes.MediaProcessing,
                Requests = [new() { Status = SeerrCodes.RequestApproved, RequestedBy = new() { Id = 24 } }],
            },
        };

        var mario = await _service.MovieAsync(Mario, 1170608, "it", Ct);
        var davide = await _service.MovieAsync(Davide, 1170608, "it", Ct);

        Assert.Equal(
            new TitleDetailsDto(
                "movie", 1170608, "Dune - Parte tre", 2026, "Paul", mario.Genres, 140, "/p.jpg", "/b.jpg",
                "https://www.youtube.com/watch?v=x", TitleStatuses.Processing, null, true, true, null),
            mario);
        Assert.Equal(new[] { "Fantascienza" }, mario.Genres);
        Assert.False(davide.RequestedByMe);
        Assert.True(davide.Requested);

        // Il titolo è già in memoria per gli elenchi.
        _seerr.Requests.Add(Request(1, 1170608));
        await _service.ListAsync(Mario, RequestsService.FilterMine, 0, 20, "it", Ct);
        Assert.Equal(2, _seerr.Calls.Count(c => c == "GetMovie"));
    }

    [Fact]
    public async Task SeriesDetailsHaveTheSeasons()
    {
        _seerr.Shows[90228] = new SeerrTv
        {
            Name = "Dune: Prophecy", FirstAirDate = "2024-11-17",
            Seasons = [new() { SeasonNumber = 0, EpisodeCount = 1 }, new() { SeasonNumber = 1, EpisodeCount = 6 }],
        };

        var tv = await _service.TvAsync(Mario, 90228, "it", Ct);

        Assert.Equal("tv", tv.MediaType);
        Assert.Equal(new[] { new SeasonDto(1, 6, TitleStatuses.None) }, tv.Seasons);
        Assert.Equal(TitleStatuses.None, tv.Status);
    }

    [Fact]
    public async Task UnknownTitlesAndBadIdsAreErrors()
    {
        Assert.Equal(SeerrError.NotFound, await ErrorOf(() => _service.MovieAsync(Mario, 5, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.TvAsync(Mario, 0, "it", Ct)));
    }

    [Fact]
    public async Task CreateImportsTheAccountAndSendsTheChosenSeasons()
    {
        _seerr.OnImport = id => new SeerrUser { Id = 30, Permissions = 32, JellyfinUserId = id.ToString("N") };

        var created = await _service.CreateAsync(
            Luigi, new CreateRequestBody { MediaType = "tv", TmdbId = 90228, Seasons = [2, 1, 2] }, Ct);

        Assert.Equal(new CreatedRequestDto(100, RequestStatuses.Pending), created);
        var (asUser, body) = Assert.Single(_seerr.Created);
        Assert.Equal(30, asUser);
        Assert.Equal("tv", body.MediaType);
        Assert.Equal(90228, body.MediaId);
        Assert.Equal(new[] { 1, 2 }, body.Seasons!);
    }

    [Fact]
    public async Task AMovieRequestHasNoSeasonsAndCanBeApprovedAtOnce()
    {
        _seerr.OnCreate = (_, body) => new SeerrRequest { Id = 7, Status = SeerrCodes.RequestApproved, Type = body.MediaType };

        var created = await _service.CreateAsync(
            Davide, new CreateRequestBody { MediaType = "movie", TmdbId = 841, Seasons = [1] }, Ct);

        Assert.Equal(new CreatedRequestDto(7, RequestStatuses.Approved), created);
        Assert.Null(Assert.Single(_seerr.Created).Body.Seasons);
        Assert.Equal(3, _seerr.Created[0].AsUser);
    }

    [Fact]
    public async Task BadRequestBodies()
    {
        foreach (var body in new CreateRequestBody?[]
                 {
                     null,
                     new() { MediaType = "movie", TmdbId = 0 },
                     new() { MediaType = "person", TmdbId = 1 },
                     new() { MediaType = "tv", TmdbId = 1 },
                     new() { MediaType = "tv", TmdbId = 1, Seasons = [] },
                     new() { MediaType = "tv", TmdbId = 1, Seasons = [0] },
                 })
        {
            Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.CreateAsync(Mario, body, Ct)));
        }

        Assert.Empty(_seerr.Calls);
    }

    [Fact]
    public async Task MineUsesRequestedByAndCompletesTheTitles()
    {
        _seerr.Movies[841] = new SeerrMovie { Title = "Dune", ReleaseDate = "1984-12-14", PosterPath = "/d.jpg" };
        var tv = Request(2, 59941, "tv", SeerrCodes.RequestApproved);
        tv.Seasons = [new() { SeasonNumber = 14 }, new() { SeasonNumber = 13 }];
        tv.Media!.JellyfinMediaId = "6D1C8EA33A794F76FDBE92A216959073";
        _seerr.Requests.AddRange([Request(1, 841), tv]);
        _seerr.TotalRequests = 3;

        var page = await _service.ListAsync(Mario, RequestsService.FilterMine, 0, 2, "it", Ct);

        Assert.Equal((24, "all", 2, 0, (int?)24), Assert.Single(_seerr.Listed));
        Assert.True(page.HasMore);
        var movie = page.Items[0];
        Assert.Equal(
            new MediaRequestDto(
                1, "movie", 841, "Dune", 1984, "/d.jpg", movie.Seasons, new RequesterDto("mario", true),
                new DateTimeOffset(2026, 10, 3, 20, 0, 0, TimeSpan.Zero), RequestStatuses.Pending, null, null),
            movie);
        Assert.Empty(movie.Seasons);
        // Seerr non conosce il titolo della serie: resta vuoto.
        Assert.Equal(string.Empty, page.Items[1].Title);
        Assert.Equal(new[] { 13, 14 }, page.Items[1].Seasons);
        Assert.Equal("6d1c8ea33a794f76fdbe92a216959073", page.Items[1].JellyfinItemId);
        Assert.Equal(RequestStatuses.Approved, page.Items[1].Status);
    }

    [Fact]
    public async Task PendingAndAllAreForManagersOnly()
    {
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ListAsync(Mario, RequestsService.FilterPending, 0, 20, "it", Ct)));
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ListAsync(Luigi, RequestsService.FilterAll, 0, 20, "it", Ct)));

        var page = await _service.ListAsync(Davide, RequestsService.FilterPending, 20, 20, "it", Ct);

        Assert.Equal((3, "pending", 20, 20, (int?)null), Assert.Single(_seerr.Listed));
        Assert.False(page.HasMore);
    }

    [Fact]
    public async Task MineWithoutAnAccountIsEmptyAndBadPagesAreErrors()
    {
        var page = await _service.ListAsync(Luigi, RequestsService.FilterMine, 0, 20, "it", Ct);

        Assert.Empty(page.Items);
        Assert.False(page.HasMore);
        Assert.Empty(_seerr.Listed);
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ListAsync(Mario, "altro", 0, 20, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ListAsync(Mario, RequestsService.FilterMine, -1, 20, "it", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ListAsync(Mario, RequestsService.FilterMine, 0, RequestsService.MaxTake + 1, "it", Ct)));
    }

    [Fact]
    public async Task ServicesForManagersWithout4k()
    {
        _seerr.Servers[SeerrServices.Radarr] =
        [
            new() { Id = 0, Name = "Radarr", IsDefault = true, ActiveProfileId = 8, ActiveDirectory = "/media/movies" },
            new() { Id = 1, Name = "Radarr Anime", ActiveProfileId = 7, ActiveDirectory = "/media/anime" },
            new() { Id = 2, Name = "Radarr 4K", Is4k = true },
        ];
        _seerr.ServerDetails[(SeerrServices.Radarr, 0)] = new SeerrServerDetails
        {
            Profiles = [new() { Id = 8, Name = "Main Profile" }],
            RootFolders = [new() { Path = "/media/movies" }, new() { Path = null }],
        };
        _seerr.ServerDetails[(SeerrServices.Radarr, 1)] = new SeerrServerDetails
        {
            Profiles = [new() { Id = 7, Name = "Anime Main Profile" }],
            RootFolders = [new() { Path = "/media/anime" }],
        };

        var services = await _service.ServicesAsync(Davide, "movie", Ct);

        Assert.Equal(
            new[] { "Radarr", "Radarr Anime" }, services.Select(s => s.Name));
        Assert.Equal(new ProfileDto(8, "Main Profile"), Assert.Single(services[0].Profiles));
        Assert.Equal(new[] { "/media/movies" }, services[0].RootFolders);
        Assert.True(services[0].IsDefault);
        Assert.Equal(7, services[1].DefaultProfileId);
        Assert.Equal("/media/anime", services[1].DefaultRootFolder);
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ServicesAsync(Mario, "movie", Ct)));
        Assert.Equal(SeerrError.BadRequest, await ErrorOf(() => _service.ServicesAsync(Davide, "music", Ct)));
    }

    [Fact]
    public async Task ApproveWithTheDefaultsDoesNotChangeTheRequest()
    {
        _seerr.Requests.Add(Request(53, 841));
        _seerr.Movies[841] = new SeerrMovie { Title = "Dune" };

        var approved = await _service.ApproveAsync(Davide, 53, new ApproveBody(), "it", Ct);

        Assert.Empty(_seerr.Updated);
        Assert.Equal((3, 53, true), Assert.Single(_seerr.StatusChanges));
        Assert.Equal(RequestStatuses.Approved, approved.Status);
        Assert.Equal("Dune", approved.Title);
        Assert.False(approved.RequestedBy.IsMe);
    }

    [Fact]
    public async Task ApproveWithAServerChangesTheRequestFirst()
    {
        var tv = Request(60, 59941, "tv");
        tv.Seasons = [new() { SeasonNumber = 1 }, new() { SeasonNumber = 2 }];
        _seerr.Requests.Add(tv);

        await _service.ApproveAsync(
            Davide, 60, new ApproveBody { ServerId = 0, ProfileId = 8, RootFolder = "/media/anime" }, "it", Ct);

        var (asUser, requestId, body) = Assert.Single(_seerr.Updated);
        Assert.Equal((3, 60), (asUser, requestId));
        Assert.Equal("tv", body.MediaType);
        Assert.Equal(0, body.ServerId);
        Assert.Equal(8, body.ProfileId);
        Assert.Equal("/media/anime", body.RootFolder);
        Assert.Equal(new[] { 1, 2 }, body.Seasons!);
        Assert.Equal(new[] { "GetUsers", "GetRequest", "UpdateRequest", "Approve", "GetTv" }, _seerr.Calls);
    }

    [Fact]
    public async Task ApproveAndDeclineNeedAManagerAndAWholeChoice()
    {
        _seerr.Requests.Add(Request(53, 841));

        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.ApproveAsync(Mario, 53, null, "it", Ct)));
        Assert.Equal(SeerrError.NoPermission, await ErrorOf(() => _service.DeclineAsync(Mario, 53, "it", Ct)));
        Assert.Equal(
            SeerrError.BadRequest,
            await ErrorOf(() => _service.ApproveAsync(Davide, 53, new ApproveBody { ServerId = 1 }, "it", Ct)));
        Assert.Equal(SeerrError.NotFound, await ErrorOf(() => _service.DeclineAsync(Davide, 99, "it", Ct)));

        var declined = await _service.DeclineAsync(Davide, 53, "it", Ct);

        Assert.Equal(RequestStatuses.Declined, declined.Status);
        Assert.Equal((3, 53, false), _seerr.StatusChanges.Last());
    }
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~RequestsServiceTests"`
Expected: FAIL di compilazione (`RequestsService` non esiste).

- [ ] **Step 3: implementazione**

`Hub/RequestsService.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Gli endpoint delle richieste (spec I §7.3): Seerr per conto dell'utente
/// Seerr abbinato a chi chiama, oggetti del plugin per l'app. Lancia
/// SeerrException, che il controller traduce in risposta.
/// </summary>
public sealed class RequestsService(ISeerrClient seerr, SeerrUserMap users, SeerrTitleCache titles)
{
    /// <summary>Richieste al massimo per pagina.</summary>
    public const int MaxTake = 50;

    /// <summary>Lunghezza massima di una ricerca.</summary>
    public const int MaxQueryLength = 100;

    public const string FilterMine = "mine";
    public const string FilterPending = "pending";
    public const string FilterAll = "all";

    /// <summary>La lingua per TMDB dalla lingua dell'app: due lettere minuscole, altrimenti "en".</summary>
    public static string Language(string? raw) =>
        raw is { Length: 2 } && raw.All(char.IsAsciiLetterLower) ? raw : "en";

    /// <summary>
    /// Cosa può fare chi chiama. Senza account vale ciò che Seerr darebbe al
    /// nuovo account (l'import arriva con la prima richiesta).
    /// </summary>
    public async Task<RequestsMeResponse> MeAsync(Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            var defaults = await users.DefaultPermissionsAsync(cancellationToken).ConfigureAwait(false);
            return new RequestsMeResponse(SeerrPermissions.CanRequest(defaults), CanManage: false, HasAccount: false);
        }

        return new RequestsMeResponse(
            SeerrPermissions.CanRequest(user.Permissions), SeerrPermissions.CanManage(user.Permissions), HasAccount: true);
    }

    /// <summary>La prima pagina di Seerr, solo film e serie, senza i titoli bloccati.</summary>
    public async Task<IReadOnlyList<RequestableTitleDto>> SearchAsync(
        string? query, string language, CancellationToken cancellationToken)
    {
        var trimmed = query?.Trim() ?? string.Empty;
        if (trimmed.Length == 0 || trimmed.Length > MaxQueryLength)
        {
            throw BadRequest();
        }

        var results = await seerr.SearchAsync(trimmed, language, cancellationToken).ConfigureAwait(false);
        var titles = new List<RequestableTitleDto>();
        foreach (var result in results)
        {
            var mediaType = MediaTypeOf(result.MediaType);
            if (mediaType is null || SeerrMapping.IsBlocklisted(result.MediaInfo))
            {
                continue;
            }

            var tv = mediaType == RequestMediaTypes.Tv;
            titles.Add(new RequestableTitleDto(
                mediaType,
                result.Id,
                (tv ? result.Name : result.Title) ?? string.Empty,
                SeerrMapping.Year(tv ? result.FirstAirDate : result.ReleaseDate),
                result.PosterPath,
                SeerrMapping.TitleStatus(result.MediaInfo?.Status),
                SeerrMapping.JellyfinId(result.MediaInfo?.JellyfinMediaId)));
        }

        return titles;
    }

    public async Task<TitleDetailsDto> MovieAsync(
        Guid userId, int tmdbId, string language, CancellationToken cancellationToken)
    {
        Positive(tmdbId);
        var movie = await seerr.GetMovieAsync(tmdbId, language, cancellationToken).ConfigureAwait(false);
        var me = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        titles.Put(RequestMediaTypes.Movie, tmdbId, language, SeerrTitleCache.From(movie));
        var info = movie.MediaInfo;
        return new TitleDetailsDto(
            RequestMediaTypes.Movie,
            tmdbId,
            movie.Title ?? string.Empty,
            SeerrMapping.Year(movie.ReleaseDate),
            movie.Overview,
            SeerrMapping.Genres(movie.Genres),
            movie.Runtime,
            movie.PosterPath,
            movie.BackdropPath,
            SeerrMapping.TrailerUrl(movie.RelatedVideos),
            SeerrMapping.TitleStatus(info?.Status),
            SeerrMapping.JellyfinId(info?.JellyfinMediaId),
            SeerrMapping.RequestedBy(info, me?.Id),
            SeerrMapping.Requested(info),
            Seasons: null);
    }

    public async Task<TitleDetailsDto> TvAsync(
        Guid userId, int tmdbId, string language, CancellationToken cancellationToken)
    {
        Positive(tmdbId);
        var tv = await seerr.GetTvAsync(tmdbId, language, cancellationToken).ConfigureAwait(false);
        var me = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        titles.Put(RequestMediaTypes.Tv, tmdbId, language, SeerrTitleCache.From(tv));
        var info = tv.MediaInfo;
        return new TitleDetailsDto(
            RequestMediaTypes.Tv,
            tmdbId,
            tv.Name ?? string.Empty,
            SeerrMapping.Year(tv.FirstAirDate),
            tv.Overview,
            SeerrMapping.Genres(tv.Genres),
            RuntimeMinutes: null,
            tv.PosterPath,
            tv.BackdropPath,
            SeerrMapping.TrailerUrl(tv.RelatedVideos),
            SeerrMapping.TitleStatus(info?.Status),
            SeerrMapping.JellyfinId(info?.JellyfinMediaId),
            SeerrMapping.RequestedBy(info, me?.Id),
            SeerrMapping.Requested(info),
            SeerrMapping.Seasons(tv));
    }

    /// <summary>Una richiesta per conto di chi chiama, con l'import se non ha un account (spec I §7.2).</summary>
    public async Task<CreatedRequestDto> CreateAsync(
        Guid userId, CreateRequestBody? body, CancellationToken cancellationToken)
    {
        var mediaType = MediaTypeOf(body?.MediaType);
        if (body is null || mediaType is null || body.TmdbId <= 0)
        {
            throw BadRequest();
        }

        List<int>? seasons = null;
        if (mediaType == RequestMediaTypes.Tv)
        {
            seasons = body.Seasons?.Distinct().Order().ToList() ?? [];
            if (seasons.Count == 0 || seasons.Any(s => s <= 0))
            {
                throw BadRequest();
            }
        }

        var user = await users.EnsureAsync(userId, cancellationToken).ConfigureAwait(false);
        var created = await seerr.CreateRequestAsync(
            user.Id,
            new SeerrCreateRequest { MediaType = mediaType, MediaId = body.TmdbId, Seasons = seasons },
            cancellationToken).ConfigureAwait(false);
        return new CreatedRequestDto(created.Id, SeerrMapping.RequestStatus(created));
    }

    /// <summary>
    /// Le richieste dalla più recente: "mine" quelle di chi chiama, "pending"
    /// e "all" solo per chi può approvare. Il titolo viene da
    /// <see cref="SeerrTitleCache"/>.
    /// </summary>
    public async Task<RequestPageDto> ListAsync(
        Guid userId, string? filter, int skip, int take, string language, CancellationToken cancellationToken)
    {
        if (filter is not (FilterMine or FilterPending or FilterAll) || skip < 0 || take < 1 || take > MaxTake)
        {
            throw BadRequest();
        }

        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        if (user is null)
        {
            return filter == FilterMine ? new RequestPageDto([], false) : throw NoPermission();
        }

        if (filter != FilterMine && !SeerrPermissions.CanManage(user.Permissions))
        {
            throw NoPermission();
        }

        var page = await seerr.GetRequestsAsync(
            user.Id,
            filter == FilterPending ? "pending" : "all",
            take,
            skip,
            filter == FilterMine ? user.Id : null,
            cancellationToken).ConfigureAwait(false);
        var items = await Task.WhenAll(page.Results.Select(r => ToDtoAsync(r, user.Id, language, cancellationToken)))
            .ConfigureAwait(false);
        return new RequestPageDto(items, skip + page.Results.Count < (page.PageInfo?.Results ?? 0));
    }

    /// <summary>I server non 4K del servizio del tipo (Radarr per i film, Sonarr per le serie), per chi può approvare.</summary>
    public async Task<IReadOnlyList<ServiceDto>> ServicesAsync(
        Guid userId, string? mediaType, CancellationToken cancellationToken)
    {
        var type = MediaTypeOf(mediaType) ?? throw BadRequest();
        await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var service = type == RequestMediaTypes.Tv ? SeerrServices.Sonarr : SeerrServices.Radarr;
        var servers = (await seerr.GetServersAsync(service, cancellationToken).ConfigureAwait(false))
            .Where(s => !s.Is4k)
            .ToList();
        var details = await Task.WhenAll(servers.Select(s => seerr.GetServerDetailsAsync(service, s.Id, cancellationToken)))
            .ConfigureAwait(false);
        return servers
            .Zip(details, (server, detail) => new ServiceDto(
                server.Id,
                server.Name ?? string.Empty,
                server.IsDefault,
                detail.Profiles.Select(p => new ProfileDto(p.Id, p.Name ?? string.Empty)).ToList(),
                detail.RootFolders.Select(f => f.Path).OfType<string>().ToList(),
                server.ActiveProfileId,
                server.ActiveDirectory))
            .ToList();
    }

    /// <summary>
    /// Approva. Senza scelte valgono i predefiniti di Seerr; con server,
    /// profilo e cartella (tutti e tre) la richiesta si cambia prima (spec I §7.3).
    /// </summary>
    public async Task<MediaRequestDto> ApproveAsync(
        Guid userId, int requestId, ApproveBody? body, string language, CancellationToken cancellationToken)
    {
        Positive(requestId);
        var manager = await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var choice = body ?? new ApproveBody();
        if (choice.ServerId is not null || choice.ProfileId is not null || choice.RootFolder is not null)
        {
            if (choice.ServerId is not { } serverId || serverId < 0
                || choice.ProfileId is not { } profileId || profileId <= 0
                || string.IsNullOrWhiteSpace(choice.RootFolder))
            {
                throw BadRequest();
            }

            var request = await seerr.GetRequestAsync(manager.Id, requestId, cancellationToken).ConfigureAwait(false);
            var mediaType = MediaTypeOf(request.Type ?? request.Media?.MediaType) ?? RequestMediaTypes.Movie;
            await seerr.UpdateRequestAsync(
                manager.Id,
                requestId,
                new SeerrUpdateRequest
                {
                    MediaType = mediaType,
                    ServerId = serverId,
                    ProfileId = profileId,
                    RootFolder = choice.RootFolder,
                    Seasons = mediaType == RequestMediaTypes.Tv
                        ? request.Seasons.Select(s => s.SeasonNumber).ToList()
                        : null,
                },
                cancellationToken).ConfigureAwait(false);
        }

        var approved = await seerr.SetRequestStatusAsync(manager.Id, requestId, approve: true, cancellationToken)
            .ConfigureAwait(false);
        return await ToDtoAsync(approved, manager.Id, language, cancellationToken).ConfigureAwait(false);
    }

    public async Task<MediaRequestDto> DeclineAsync(
        Guid userId, int requestId, string language, CancellationToken cancellationToken)
    {
        Positive(requestId);
        var manager = await ManagerAsync(userId, cancellationToken).ConfigureAwait(false);
        var declined = await seerr.SetRequestStatusAsync(manager.Id, requestId, approve: false, cancellationToken)
            .ConfigureAwait(false);
        return await ToDtoAsync(declined, manager.Id, language, cancellationToken).ConfigureAwait(false);
    }

    private async Task<MediaRequestDto> ToDtoAsync(
        SeerrRequest request, int me, string language, CancellationToken cancellationToken)
    {
        var mediaType = MediaTypeOf(request.Media?.MediaType ?? request.Type) ?? RequestMediaTypes.Movie;
        var tmdbId = request.Media?.TmdbId ?? 0;
        var title = tmdbId > 0
            ? await titles.GetAsync(mediaType, tmdbId, language, cancellationToken).ConfigureAwait(false)
            : null;
        return new MediaRequestDto(
            request.Id,
            mediaType,
            tmdbId,
            title?.Title ?? string.Empty,
            title?.Year,
            title?.PosterPath,
            request.Seasons.Select(s => s.SeasonNumber).Order().ToList(),
            new RequesterDto(request.RequestedBy?.DisplayName ?? string.Empty, request.RequestedBy?.Id == me),
            request.CreatedAt,
            SeerrMapping.RequestStatus(request),
            SeerrMapping.Progress(request.Media?.DownloadStatus ?? []),
            SeerrMapping.JellyfinId(request.Media?.JellyfinMediaId));
    }

    private async Task<SeerrUser> ManagerAsync(Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.FindAsync(userId, cancellationToken).ConfigureAwait(false);
        return user is not null && SeerrPermissions.CanManage(user.Permissions) ? user : throw NoPermission();
    }

    private static string? MediaTypeOf(string? raw) => raw switch
    {
        RequestMediaTypes.Movie => RequestMediaTypes.Movie,
        RequestMediaTypes.Tv => RequestMediaTypes.Tv,
        _ => null,
    };

    private static void Positive(int id)
    {
        if (id <= 0)
        {
            throw BadRequest();
        }
    }

    private static SeerrException BadRequest() => new(SeerrError.BadRequest);

    private static SeerrException NoPermission() => new(SeerrError.NoPermission);
}
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): search, request and approve titles through Seerr"
```

### Task 7: cassetta delle notifiche e webhook

**Files:**
- Modify: `…/Protocol/InboxDtos.cs`, `…/Hub/InboxBook.cs`, `…/Hub/InboxService.cs`
- Create: `…/Hub/RequestEvent.cs`, `…/Hub/RequestWebhookHandler.cs`
- Test: `…Tests/InboxRequestsTests.cs`, `…Tests/RequestWebhookTests.cs`

- [ ] **Step 1: test che falliscono**

`…Tests/InboxRequestsTests.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InboxRequestsTests
{
    [Fact]
    public void ARequestEntryReplacesTheOneOfTheSameTypeAndRequest()
    {
        var book = new InboxBook();
        var user = Guid.NewGuid();
        var now = DateTimeOffset.UnixEpoch;
        book.UpsertRequest(user, new InboxEntry { Type = InboxEntryTypes.RequestPending, RequestId = 1, Title = "A", CreatedAt = now });
        book.UpsertRequest(user, new InboxEntry { Type = InboxEntryTypes.RequestAvailable, RequestId = 1, Title = "A", CreatedAt = now });
        book.UpsertRequest(user, new InboxEntry { Type = InboxEntryTypes.RequestPending, RequestId = 2, Title = "B", CreatedAt = now });
        book.MarkRead(user, long.MaxValue);

        var again = book.UpsertRequest(
            user, new InboxEntry { Type = InboxEntryTypes.RequestPending, RequestId = 1, Title = "A2", CreatedAt = now });

        var entries = book.List(user);
        Assert.Equal(new[] { "A2", "B", "A" }, entries.Select(e => e.Title));
        Assert.Equal(again.Id, entries[0].Id);
        Assert.False(entries[0].Read);
        Assert.Equal(InboxEntryTypes.RequestAvailable, entries[2].Type);
    }

    [Fact]
    public void RequestFieldsAreWrittenOnlyWhenSet()
    {
        var json = JsonSerializer.Serialize(new InboxEntry
        {
            Id = "x",
            Type = InboxEntryTypes.RequestAvailable,
            RequestId = 53,
            MediaType = "tv",
            TmdbId = 9,
            Title = "Brothers (2026)",
            Seasons = [1, 2],
            ItemId = "6d1c8ea33a794f76fdbe92a216959073",
        });

        Assert.Contains("\"RequestId\":53", json, StringComparison.Ordinal);
        Assert.Contains("\"MediaType\":\"tv\"", json, StringComparison.Ordinal);
        Assert.Contains("\"TmdbId\":9", json, StringComparison.Ordinal);
        Assert.Contains("\"Seasons\":[1,2]", json, StringComparison.Ordinal);
        Assert.Contains("\"ItemId\":\"6d1c8ea33a794f76fdbe92a216959073\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("RequesterName", json, StringComparison.Ordinal);
        Assert.DoesNotContain("GroupId", json, StringComparison.Ordinal);
        Assert.DoesNotContain("RequestId", JsonSerializer.Serialize(new InboxEntry { Type = InboxEntryTypes.Announcement }), StringComparison.Ordinal);
    }
}
```

`…Tests/RequestWebhookTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RequestWebhookTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeSeerrSettings _settings = new();
    private readonly RecordingLogger<RequestWebhookHandler> _logger = new();
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _davide;
    private readonly RequestWebhookHandler _handler;

    public RequestWebhookTests()
    {
        _mario = _server.AddUser("Mario");
        _davide = _server.AddUser("Davide");
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = _davide.Id.ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 24, Permissions = 32, JellyfinUserId = _mario.Id.ToString("N") });
        _inbox = TestInbox.Create(_server, _folder, _time);
        _handler = Handler();
    }

    public void Dispose() => _folder.Dispose();

    private RequestWebhookHandler Handler() => new(
        _settings, new SeerrUserMap(_seerr, _time, NullLogger<SeerrUserMap>.Instance), _server, _inbox, _time, _logger);

    private SeerrWebhookPayload Payload(string type, string? secret = "secret") => new()
    {
        Secret = secret,
        NotificationType = type,
        Subject = "Dune (2021)",
        RequestId = "53",
        MediaType = "movie",
        MediaTmdbId = "438631",
        MediaJellyfinMediaId = "EE39BEF06F503DD0E9DBD20593DF417F",
        RequestedByJellyfinUserId = _mario.Id.ToString("N"),
        RequestedByUsername = "Mario",
    };

    [Fact]
    public async Task AWrongOrMissingSecretIsRejectedAndLoggedOnceAMinute()
    {
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", "sbagliato"), Ct));
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", null), Ct));
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(null, Ct));
        Assert.Single(_logger.Entries);

        _time.Advance(RequestWebhookHandler.RejectedLogEvery);
        await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", "sbagliato"), Ct);
        Assert.Equal(2, _logger.Entries.Count);

        // Senza segreto nella configurazione nessun webhook passa.
        _settings.WebhookSecret = string.Empty;
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", string.Empty), Ct));

        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Null(_handler.LastEvent.At);
    }

    [Fact]
    public async Task AvailableGoesToTheRequesterWithTheLibraryItem()
    {
        _server.AddSession("s1", _mario);

        Assert.Equal(WebhookResult.Accepted, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE"), Ct));

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.RequestAvailable, entry.Type);
        Assert.Equal(53, entry.RequestId);
        Assert.Equal("movie", entry.MediaType);
        Assert.Equal(438631, entry.TmdbId);
        Assert.Equal("Dune (2021)", entry.Title);
        Assert.Equal("ee39bef06f503dd0e9dbd20593df417f", entry.ItemId);
        Assert.Null(entry.Seasons);
        Assert.Null(entry.RequesterName);
        Assert.Empty(_inbox.Get(_davide.Id).Entries);
        Assert.Single(_server.SentTo("s1"));
        Assert.Equal(_time.GetUtcNow(), _handler.LastEvent.At);
        Assert.Equal("MEDIA_AVAILABLE", _handler.LastEvent.Type);
    }

    [Fact]
    public async Task AvailableForASeriesKeepsTheSeasonsAndARepeatReplacesTheEntry()
    {
        var payload = Payload("MEDIA_AVAILABLE");
        payload.MediaType = "tv";
        payload.Extra = [new SeerrWebhookExtra { Name = "Requested Seasons", Value = "2, 1, x, 2" }];

        await _handler.HandleAsync(payload, Ct);
        await _inbox.MarkReadAsync(_mario.Id, long.MaxValue);
        await _handler.HandleAsync(payload, Ct);

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(new[] { 1, 2 }, entry.Seasons!);
        Assert.False(entry.Read);
    }

    [Fact]
    public async Task PendingGoesToWhoCanApproveButNotToTheRequester()
    {
        await _handler.HandleAsync(Payload("MEDIA_PENDING"), Ct);

        var entry = Assert.Single(_inbox.Get(_davide.Id).Entries);
        Assert.Equal(InboxEntryTypes.RequestPending, entry.Type);
        Assert.Equal("Mario", entry.RequesterName);
        Assert.Null(entry.ItemId);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);

        // L'admin che chiede (se Seerr non approvasse da solo) non avvisa sé stesso.
        var own = Payload("MEDIA_PENDING");
        own.RequestId = "54";
        own.RequestedByJellyfinUserId = _davide.Id.ToString("N");
        await _handler.HandleAsync(own, Ct);
        Assert.Single(_inbox.Get(_davide.Id).Entries);
    }

    [Fact]
    public async Task PendingSkipsManagersThatAreDisabledOrGoneAndSurvivesSeerrDown()
    {
        var off = _server.AddUser("Spento", enabled: false);
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = 2, JellyfinUserId = Guid.NewGuid().ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 5, Permissions = 16, JellyfinUserId = off.Id.ToString("N") });

        await _handler.HandleAsync(Payload("MEDIA_PENDING"), Ct);

        Assert.Single(_inbox.Get(_davide.Id).Entries);
        Assert.Empty(_inbox.Get(off.Id).Entries);

        _seerr.FailWith = SeerrError.Unavailable;
        var next = Payload("MEDIA_PENDING");
        next.RequestId = "60";
        Assert.Equal(WebhookResult.Accepted, await Handler().HandleAsync(next, Ct));
        Assert.Single(_inbox.Get(_davide.Id).Entries);
    }

    [Fact]
    public async Task IncompleteEventsAndOtherTypesAreAcceptedWithoutEntries()
    {
        var noId = Payload("MEDIA_AVAILABLE");
        noId.RequestId = string.Empty;
        var person = Payload("MEDIA_AVAILABLE");
        person.MediaType = "person";
        var noSubject = Payload("MEDIA_AVAILABLE");
        noSubject.Subject = " ";
        var unknownUser = Payload("MEDIA_AVAILABLE");
        unknownUser.RequestedByJellyfinUserId = Guid.NewGuid().ToString("N");

        foreach (var payload in new[] { noId, person, noSubject, unknownUser, Payload("MEDIA_APPROVED"), Payload("TEST_NOTIFICATION") })
        {
            Assert.Equal(WebhookResult.Accepted, await _handler.HandleAsync(payload, Ct));
        }

        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Empty(_inbox.Get(_davide.Id).Entries);
        Assert.Equal("TEST_NOTIFICATION", _handler.LastEvent.Type);
    }
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~InboxRequestsTests|FullyQualifiedName~RequestWebhookTests"`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

In `Protocol/InboxDtos.cs`, in `InboxEntryTypes` dopo `NewTitles`:

```csharp

    /// <summary>Un titolo chiesto è arrivato (spec I §7.6), a chi l'ha chiesto.</summary>
    public const string RequestAvailable = "RequestAvailable";

    /// <summary>Una richiesta da approvare (spec I §7.6), a chi può approvare.</summary>
    public const string RequestPending = "RequestPending";
```

In `InboxEntry` cambia il commento di `Title` in `/// <summary>Invite: il titolo, dal nome del gruppo ("Host · Titolo"). RequestAvailable e RequestPending: il titolo da Seerr ("Dune (2021)").</summary>` e aggiungi, prima di `Copy()`:

```csharp
    /// <summary>RequestAvailable, RequestPending: la richiesta in Seerr.</summary>
    [JsonPropertyName("RequestId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? RequestId { get; set; }

    /// <summary>RequestAvailable, RequestPending: "movie" o "tv".</summary>
    [JsonPropertyName("MediaType")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? MediaType { get; set; }

    /// <summary>RequestAvailable, RequestPending: l'id TMDB.</summary>
    [JsonPropertyName("TmdbId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? TmdbId { get; set; }

    /// <summary>RequestAvailable, RequestPending: le stagioni chieste, per le serie.</summary>
    [JsonPropertyName("Seasons")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<int>? Seasons { get; set; }

    /// <summary>RequestAvailable: il titolo nella libreria, in formato "N", se Seerr lo conosce.</summary>
    [JsonPropertyName("ItemId")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? ItemId { get; set; }

    /// <summary>RequestPending: chi ha chiesto il titolo.</summary>
    [JsonPropertyName("RequesterName")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? RequesterName { get; set; }

```

Cambia anche il commento di `Copy()` in `/// <summary>Copia superficiale: le liste (NewTitles, Seasons) non si cambiano mai dopo la creazione.</summary>`.

In `Hub/InboxBook.cs`, dopo `UpsertInvite`:

```csharp
    /// <summary>
    /// La voce di una richiesta (spec I §7.6): sostituisce quella dello
    /// stesso tipo e della stessa richiesta, quindi torna non letta e in cima.
    /// Restituisce una copia.
    /// </summary>
    public InboxEntry UpsertRequest(Guid userId, InboxEntry entry)
    {
        Inbox(userId).Entries.RemoveAll(e => e.Type == entry.Type && e.RequestId == entry.RequestId);
        return Add(userId, entry);
    }
```

`Hub/RequestEvent.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// Un evento del webhook di Seerr già letto (spec I §7.5): Title è il
/// subject di Seerr, ItemId l'id Jellyfin in formato "N" se Seerr lo conosce.
/// </summary>
public sealed record RequestEvent(
    int RequestId, string MediaType, int TmdbId, string Title, IReadOnlyList<int>? Seasons, string? ItemId);
```

In `Hub/InboxService.cs`, dopo `AddNewTitlesAsync`:

```csharp
    /// <summary>"Ora disponibile" a chi ha chiesto il titolo (spec I §7.5). Non lancia.</summary>
    public Task AddRequestAvailableAsync(Guid userId, RequestEvent request) =>
        AddRequestAsync(InboxEntryTypes.RequestAvailable, [userId], request, requesterName: null);

    /// <summary>"Nuova richiesta" a chi può approvare (spec I §7.5). Non lancia.</summary>
    public Task AddRequestPendingAsync(IReadOnlyList<Guid> userIds, RequestEvent request, string requesterName) =>
        AddRequestAsync(InboxEntryTypes.RequestPending, userIds, request, requesterName);
```

e, prima di `Cleanup`:

```csharp
    private async Task AddRequestAsync(
        string type, IReadOnlyList<Guid> userIds, RequestEvent request, string? requesterName)
    {
        if (userIds.Count == 0)
        {
            return;
        }

        try
        {
            var now = time.GetUtcNow();
            lock (_lock)
            {
                foreach (var userId in userIds)
                {
                    Book.UpsertRequest(userId, new InboxEntry
                    {
                        Type = type,
                        CreatedAt = now,
                        RequestId = request.RequestId,
                        MediaType = request.MediaType,
                        TmdbId = request.TmdbId,
                        Title = request.Title,
                        Seasons = request.Seasons?.ToList(),
                        ItemId = type == InboxEntryTypes.RequestAvailable ? request.ItemId : null,
                        RequesterName = requesterName,
                    });
                }

                Persist();
            }

            logger.LogDebug(
                "Voce {Type} della richiesta {RequestId} a {Count} utenti", type, request.RequestId, userIds.Count);
            await NotifyAsync(userIds).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Voci della richiesta {RequestId} non create o non notificate", request.RequestId);
        }
    }
```

`Hub/RequestWebhookHandler.cs`:

```csharp
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito del webhook: 401 con il segreto sbagliato, altrimenti 200.</summary>
public enum WebhookResult
{
    Accepted,
    Unauthorized,
}

/// <summary>
/// Il webhook di Seerr (spec I §7.5): controlla il segreto e trasforma
/// "disponibile" e "in attesa" in voci della cassetta. Ricorda l'ultimo
/// evento per la pagina del plugin. Un evento incompleto si scarta con una
/// riga nel registro e risponde comunque 200, così Seerr non insiste.
/// </summary>
public sealed class RequestWebhookHandler(
    ISeerrSettings settings,
    SeerrUserMap seerrUsers,
    IUserDirectory users,
    InboxService inbox,
    TimeProvider time,
    ILogger<RequestWebhookHandler> logger)
{
    /// <summary>Corpo massimo del webhook.</summary>
    public const long MaxBodyBytes = 64 * 1024;

    /// <summary>Al massimo una riga nel registro per i segreti sbagliati in questo intervallo.</summary>
    public static readonly TimeSpan RejectedLogEvery = TimeSpan.FromMinutes(1);

    public const string MediaAvailable = "MEDIA_AVAILABLE";
    public const string MediaPending = "MEDIA_PENDING";

    /// <summary>Il nome della voce di "extra" con le stagioni chieste.</summary>
    public const string RequestedSeasons = "Requested Seasons";

    private readonly Lock _lock = new();
    private DateTimeOffset? _lastEventAt;
    private string? _lastEventType;
    private DateTimeOffset _lastRejectedLog = DateTimeOffset.MinValue;

    /// <summary>Data e tipo dell'ultimo evento con il segreto giusto (pagina del plugin).</summary>
    public (DateTimeOffset? At, string? Type) LastEvent
    {
        get
        {
            lock (_lock)
            {
                return (_lastEventAt, _lastEventType);
            }
        }
    }

    public async Task<WebhookResult> HandleAsync(SeerrWebhookPayload? payload, CancellationToken cancellationToken)
    {
        var secret = settings.WebhookSecret;
        if (payload is null || string.IsNullOrEmpty(secret) || !SecretMatches(payload.Secret, secret))
        {
            LogRejected();
            return WebhookResult.Unauthorized;
        }

        lock (_lock)
        {
            _lastEventAt = time.GetUtcNow();
            _lastEventType = payload.NotificationType;
        }

        switch (payload.NotificationType)
        {
            case MediaAvailable:
                await AvailableAsync(payload).ConfigureAwait(false);
                break;
            case MediaPending:
                await PendingAsync(payload, cancellationToken).ConfigureAwait(false);
                break;
            default:
                // TEST_NOTIFICATION e gli altri tipi: solo "Ultimo evento ricevuto".
                break;
        }

        return WebhookResult.Accepted;
    }

    /// <summary>Confronto in tempo costante (a parità di lunghezza).</summary>
    internal static bool SecretMatches(string? given, string expected) =>
        given is not null
        && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(given), Encoding.UTF8.GetBytes(expected));

    /// <summary>L'evento, o null se mancano richiesta, tipo, id TMDB o titolo.</summary>
    internal static RequestEvent? Parse(SeerrWebhookPayload payload)
    {
        var mediaType = payload.MediaType switch
        {
            RequestMediaTypes.Movie => RequestMediaTypes.Movie,
            RequestMediaTypes.Tv => RequestMediaTypes.Tv,
            _ => null,
        };
        if (mediaType is null
            || !int.TryParse(payload.RequestId, NumberStyles.None, CultureInfo.InvariantCulture, out var requestId)
            || requestId <= 0
            || !int.TryParse(payload.MediaTmdbId, NumberStyles.None, CultureInfo.InvariantCulture, out var tmdbId)
            || tmdbId <= 0
            || string.IsNullOrWhiteSpace(payload.Subject))
        {
            return null;
        }

        return new RequestEvent(
            requestId,
            mediaType,
            tmdbId,
            payload.Subject.Trim(),
            mediaType == RequestMediaTypes.Tv ? ParseSeasons(payload.Extra) : null,
            SeerrMapping.JellyfinId(payload.MediaJellyfinMediaId));
    }

    /// <summary>Le stagioni da "Requested Seasons" ("1, 2"), in ordine e senza doppioni; null se nessuna.</summary>
    internal static IReadOnlyList<int>? ParseSeasons(IEnumerable<SeerrWebhookExtra>? extra)
    {
        var value = extra?.FirstOrDefault(e => e.Name == RequestedSeasons)?.Value;
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var seasons = value
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Select(s => int.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : 0)
            .Where(n => n > 0)
            .Distinct()
            .Order()
            .ToList();
        return seasons.Count == 0 ? null : seasons;
    }

    private async Task AvailableAsync(SeerrWebhookPayload payload)
    {
        var request = Parse(payload);
        var requester = SeerrMapping.ParseGuid(payload.RequestedByJellyfinUserId);
        if (request is null || requester is not { } userId || users.GetUser(userId) is null)
        {
            logger.LogInformation(
                "Webhook di Seerr {Type} scartato: dati mancanti o utente sconosciuto", payload.NotificationType);
            return;
        }

        await inbox.AddRequestAvailableAsync(userId, request).ConfigureAwait(false);
    }

    private async Task PendingAsync(SeerrWebhookPayload payload, CancellationToken cancellationToken)
    {
        var request = Parse(payload);
        if (request is null)
        {
            logger.LogInformation("Webhook di Seerr {Type} scartato: dati mancanti", payload.NotificationType);
            return;
        }

        IReadOnlyList<Guid> managers;
        try
        {
            managers = await seerrUsers.ManagerJellyfinIdsAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (SeerrException ex)
        {
            logger.LogWarning("Webhook di Seerr {Type}: chi approva non letto ({Error})", payload.NotificationType, ex.Error);
            return;
        }

        var requester = SeerrMapping.ParseGuid(payload.RequestedByJellyfinUserId);
        var recipients = managers
            .Where(id => id != requester && users.GetUser(id) is { Enabled: true })
            .ToList();
        await inbox.AddRequestPendingAsync(recipients, request, payload.RequestedByUsername?.Trim() ?? string.Empty)
            .ConfigureAwait(false);
    }

    private void LogRejected()
    {
        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (now - _lastRejectedLog < RejectedLogEvery)
            {
                return;
            }

            _lastRejectedLog = now;
        }

        logger.LogWarning("Webhook di Seerr rifiutato: segreto mancante o sbagliato");
    }
}
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): turn Seerr webhooks into request notifications"
```

### Task 8: controller e registrazioni

**Files:**
- Create: `…/Api/RequestsController.cs`, `…/Api/RequestsWebhookController.cs`
- Modify: `…/PluginServiceRegistrator.cs`
- Test: `…Tests/RequestsControllerTests.cs`, `…Tests/ServiceRegistrationTests.cs`

- [ ] **Step 1: test che falliscono**

`…Tests/RequestsControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RequestsControllerTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeSeerrSettings _settings = new();
    private readonly User _mario = new("mario", "provider", "reset");
    private readonly RequestsService _service;
    private readonly RequestWebhookHandler _webhook;

    public RequestsControllerTests()
    {
        _server.Users[_mario.Id] = new UserRef(_mario.Id, "Mario", true, false);
        _seerr.Users.Add(new SeerrUser { Id = 24, Permissions = 32, JellyfinUserId = _mario.Id.ToString("N") });
        var map = new SeerrUserMap(_seerr, _time, NullLogger<SeerrUserMap>.Instance);
        _service = new RequestsService(_seerr, map, new SeerrTitleCache(_seerr, _time));
        _webhook = new RequestWebhookHandler(
            _settings, map, _server, TestInbox.Create(_server, _folder, _time), _time,
            NullLogger<RequestWebhookHandler>.Instance);
    }

    public void Dispose() => _folder.Dispose();

    private RequestsController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new RequestsController(new FakeAuthorizationContext(auth), _service, _settings, _seerr, _webhook)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    private static int Status<T>(ActionResult<T> result) => result.Result switch
    {
        null => StatusCodes.Status200OK,
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException("risultato inatteso"),
    };

    private static string? Code<T>(ActionResult<T> result) =>
        ((result.Result as ObjectResult)?.Value as RequestsErrorDto)?.Code;

    [Fact]
    public async Task MeIsForTheCaller()
    {
        var me = await Controller().Me();

        Assert.Equal(new RequestsMeResponse(true, false, true), me.Value);
    }

    [Fact]
    public async Task WithoutSeerrEveryEndpointSaysNotConfigured()
    {
        _settings.Url = string.Empty;

        var me = await Controller().Me();
        var search = await Controller().Search("dune", "it");

        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Status(me));
        Assert.Equal("NotConfigured", Code(me));
        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Status(search));
        Assert.Empty(_seerr.Calls);
    }

    [Theory]
    [InlineData(SeerrError.NotConfigured, 503, "NotConfigured")]
    [InlineData(SeerrError.Unavailable, 502, "SeerrUnavailable")]
    [InlineData(SeerrError.Auth, 502, "SeerrAuth")]
    [InlineData(SeerrError.NoPermission, 403, "NoPermission")]
    [InlineData(SeerrError.QuotaExceeded, 403, "QuotaExceeded")]
    [InlineData(SeerrError.Blocklisted, 403, "Blocklisted")]
    [InlineData(SeerrError.AlreadyRequested, 409, "AlreadyRequested")]
    [InlineData(SeerrError.NothingToRequest, 409, "NothingToRequest")]
    [InlineData(SeerrError.AccountUnavailable, 409, "AccountUnavailable")]
    [InlineData(SeerrError.NotFound, 400, "UnknownRequest")]
    [InlineData(SeerrError.BadRequest, 400, "Invalid")]
    public void SeerrErrorsBecomeStatusAndCode(SeerrError error, int status, string code)
    {
        var result = RequestsController.Error(error);

        Assert.Equal(status, result.StatusCode);
        Assert.Equal(new RequestsErrorDto(code), result.Value);
    }

    [Fact]
    public async Task SeerrDownAndBadIdsAreErrorsNever404()
    {
        var badId = await Controller().Movie("abc", "it");
        var zero = await Controller().Tv("0", "it");
        var unknown = await Controller().Movie("5", "it");
        _seerr.FailWith = SeerrError.Unavailable;
        var down = await Controller().Search("dune", "it");

        Assert.Equal((400, "Invalid"), (Status(badId), Code(badId)));
        Assert.Equal((400, "Invalid"), (Status(zero), Code(zero)));
        Assert.Equal((400, "UnknownRequest"), (Status(unknown), Code(unknown)));
        Assert.Equal((502, "SeerrUnavailable"), (Status(down), Code(down)));
    }

    [Fact]
    public async Task CreateListAndManagerEndpoints()
    {
        var created = await Controller().Create(new CreateRequestBody { MediaType = "movie", TmdbId = 841 });
        var mine = await Controller().List("mine", null, null, "it");
        var pending = await Controller().List("pending", null, null, "it");
        var services = await Controller().Services("movie");
        var approve = await Controller().Approve("53", null, "it");

        Assert.Equal(new CreatedRequestDto(100, RequestStatuses.Pending), created.Value);
        Assert.Equal((24, "all", RequestsController.DefaultTake, 0, (int?)24), Assert.Single(_seerr.Listed));
        Assert.NotNull(mine.Value);
        Assert.Equal((403, "NoPermission"), (Status(pending), Code(pending)));
        Assert.Equal((403, "NoPermission"), (Status(services), Code(services)));
        Assert.Equal((403, "NoPermission"), (Status(approve), Code(approve)));
    }

    [Fact]
    public async Task TestSaysVersionOrWhatIsWrong()
    {
        var ok = await Controller().Test();
        _seerr.FailOn["GetMe"] = SeerrError.Auth;
        var badKey = await Controller().Test();
        _seerr.FailOn.Clear();
        _seerr.FailWith = SeerrError.Unavailable;
        var down = await Controller().Test();
        _settings.ApiKey = string.Empty;
        var unset = await Controller().Test();

        Assert.Equal(new SeerrTestResponse(true, "3.4.1", null), ok.Value);
        Assert.Equal(new SeerrTestResponse(false, null, "SeerrAuth"), badKey.Value);
        Assert.Equal(new SeerrTestResponse(false, null, "SeerrUnavailable"), down.Value);
        Assert.Equal(new SeerrTestResponse(false, null, "NotConfigured"), unset.Value);
    }

    [Fact]
    public async Task AdminShowsTheLastWebhookEvent()
    {
        Assert.Equal(new RequestsAdminStatus(true, null, null), Controller().Admin().Value);

        await _webhook.HandleAsync(new SeerrWebhookPayload { Secret = "secret", NotificationType = "TEST_NOTIFICATION" }, CancellationToken.None);

        Assert.Equal(new RequestsAdminStatus(true, _time.GetUtcNow(), "TEST_NOTIFICATION"), Controller().Admin().Value);
    }

    [Fact]
    public async Task TheWebhookAnswers401OnlyForAWrongSecret()
    {
        var controller = new RequestsWebhookController(_webhook)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

        Assert.IsType<UnauthorizedResult>(await controller.Receive(new SeerrWebhookPayload { Secret = "no" }));
        Assert.IsType<OkResult>(await controller.Receive(new SeerrWebhookPayload { Secret = "secret", NotificationType = "TEST_NOTIFICATION" }));
    }

    [Fact]
    public void AuthorizationAndRoutes()
    {
        var authorize = Assert.Single(typeof(RequestsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        foreach (var name in new[] { nameof(RequestsController.Test), nameof(RequestsController.Admin) })
        {
            Assert.Equal(
                Policies.RequiresElevation,
                Assert.Single(typeof(RequestsController).GetMethod(name)!.GetCustomAttributes<AuthorizeAttribute>()).Policy);
        }

        Assert.NotNull(typeof(RequestsWebhookController).GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.NotNull(typeof(RequestsWebhookController).GetMethod(nameof(RequestsWebhookController.Receive))!
            .GetCustomAttribute<RequestSizeLimitAttribute>());

        // Nessun vincolo di tipo nelle rotte: un id sbagliato darebbe 404.
        var templates = typeof(RequestsController).GetMethods()
            .SelectMany(m => m.GetCustomAttributes<HttpMethodAttribute>())
            .Select(a => a.Template ?? string.Empty);
        Assert.DoesNotContain(templates, t => t.Contains(':', StringComparison.Ordinal));
    }
}
```

In `ServiceRegistrationTests.AllServicesResolve`, prima di `Assert.Equal(2, …IHostedService…)`:

```csharp
        Assert.NotNull(provider.GetRequiredService<RequestsService>());
        Assert.NotNull(provider.GetRequiredService<RequestWebhookHandler>());
        Assert.IsType<Seerr.SeerrClient>(provider.GetRequiredService<Seerr.ISeerrClient>());
        Assert.IsType<Server.PluginSeerrSettings>(provider.GetRequiredService<Seerr.ISeerrSettings>());
```

- [ ] **Step 2: verifica che falliscano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~RequestsControllerTests|FullyQualifiedName~ServiceRegistrationTests"`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`Api/RequestsController.cs`:

```csharp
using System.Globalization;
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Le richieste con Seerr (spec I §7.3), per ogni utente autenticato: chi
/// chiama è l'utente dell'autenticazione, mai un campo della richiesta. Gli
/// errori sono stato HTTP più {Code}. Come il resto del plugin, mai 404:
/// gli id sono stringhe senza vincoli di rotta.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Requests")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class RequestsController(
    IAuthorizationContext authorizationContext,
    RequestsService requests,
    ISeerrSettings settings,
    ISeerrClient seerr,
    RequestWebhookHandler webhook) : ControllerBase
{
    /// <summary>Richieste per pagina se l'app non lo dice.</summary>
    public const int DefaultTake = 20;

    /// <summary>Cosa può fare chi chiama.</summary>
    [HttpGet("Me")]
    public Task<ActionResult<RequestsMeResponse>> Me() =>
        RunAsync((user, ct) => requests.MeAsync(user, ct));

    /// <summary>Film e serie di Seerr per la sezione "Da richiedere".</summary>
    [HttpGet("Search")]
    public Task<ActionResult<IReadOnlyList<RequestableTitleDto>>> Search(
        [FromQuery] string? query, [FromQuery] string? language) =>
        RunAsync((_, ct) => requests.SearchAsync(query, RequestsService.Language(language), ct));

    [HttpGet("Movie/{tmdbId}")]
    public Task<ActionResult<TitleDetailsDto>> Movie([FromRoute] string tmdbId, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.MovieAsync(user, Id(tmdbId), RequestsService.Language(language), ct));

    [HttpGet("Tv/{tmdbId}")]
    public Task<ActionResult<TitleDetailsDto>> Tv([FromRoute] string tmdbId, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.TvAsync(user, Id(tmdbId), RequestsService.Language(language), ct));

    /// <summary>Una richiesta per conto di chi chiama.</summary>
    [HttpPost("")]
    public Task<ActionResult<CreatedRequestDto>> Create([FromBody] CreateRequestBody? body) =>
        RunAsync((user, ct) => requests.CreateAsync(user, body, ct));

    /// <summary>Le richieste: filter "mine", "pending" o "all".</summary>
    [HttpGet("")]
    public Task<ActionResult<RequestPageDto>> List(
        [FromQuery] string? filter, [FromQuery] int? skip, [FromQuery] int? take, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.ListAsync(
            user, filter, skip ?? 0, take ?? DefaultTake, RequestsService.Language(language), ct));

    /// <summary>I server per la finestra Approva; mediaType "movie" o "tv".</summary>
    [HttpGet("Services/{mediaType}")]
    public Task<ActionResult<IReadOnlyList<ServiceDto>>> Services([FromRoute] string mediaType) =>
        RunAsync((user, ct) => requests.ServicesAsync(user, mediaType, ct));

    [HttpPost("{requestId}/Approve")]
    public Task<ActionResult<MediaRequestDto>> Approve(
        [FromRoute] string requestId, [FromBody] ApproveBody? body, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.ApproveAsync(user, Id(requestId), body, RequestsService.Language(language), ct));

    [HttpPost("{requestId}/Decline")]
    public Task<ActionResult<MediaRequestDto>> Decline([FromRoute] string requestId, [FromQuery] string? language) =>
        RunAsync((user, ct) => requests.DeclineAsync(user, Id(requestId), RequestsService.Language(language), ct));

    /// <summary>"Prova collegamento" della pagina del plugin; solo per gli admin. Sempre 200.</summary>
    [HttpPost("Test")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public async Task<ActionResult<SeerrTestResponse>> Test()
    {
        if (!settings.IsConfigured())
        {
            return new SeerrTestResponse(false, null, "NotConfigured");
        }

        try
        {
            var status = await seerr.GetStatusAsync(HttpContext.RequestAborted).ConfigureAwait(false);
            await seerr.GetMeAsync(HttpContext.RequestAborted).ConfigureAwait(false);
            return new SeerrTestResponse(true, status.Version, null);
        }
        catch (SeerrException ex)
        {
            return new SeerrTestResponse(false, null, ex.Error == SeerrError.Auth ? "SeerrAuth" : "SeerrUnavailable");
        }
    }

    /// <summary>Configurato e ultimo evento del webhook (pagina del plugin); solo per gli admin.</summary>
    [HttpGet("Admin")]
    [Authorize(Policy = Policies.RequiresElevation)]
    public ActionResult<RequestsAdminStatus> Admin()
    {
        var (at, type) = webhook.LastEvent;
        return new RequestsAdminStatus(settings.IsConfigured(), at, type);
    }

    /// <summary>Da errore di Seerr a stato HTTP e {Code} (spec I §7.3).</summary>
    internal static ObjectResult Error(SeerrError error)
    {
        var (status, code) = error switch
        {
            SeerrError.NotConfigured => (StatusCodes.Status503ServiceUnavailable, "NotConfigured"),
            SeerrError.Unavailable => (StatusCodes.Status502BadGateway, "SeerrUnavailable"),
            SeerrError.Auth => (StatusCodes.Status502BadGateway, "SeerrAuth"),
            SeerrError.NoPermission => (StatusCodes.Status403Forbidden, "NoPermission"),
            SeerrError.QuotaExceeded => (StatusCodes.Status403Forbidden, "QuotaExceeded"),
            SeerrError.Blocklisted => (StatusCodes.Status403Forbidden, "Blocklisted"),
            SeerrError.AlreadyRequested => (StatusCodes.Status409Conflict, "AlreadyRequested"),
            SeerrError.NothingToRequest => (StatusCodes.Status409Conflict, "NothingToRequest"),
            SeerrError.AccountUnavailable => (StatusCodes.Status409Conflict, "AccountUnavailable"),
            SeerrError.NotFound => (StatusCodes.Status400BadRequest, "UnknownRequest"),
            _ => (StatusCodes.Status400BadRequest, "Invalid"),
        };
        return new ObjectResult(new RequestsErrorDto(code)) { StatusCode = status };
    }

    private static int Id(string raw) =>
        int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id > 0
            ? id
            : throw new SeerrException(SeerrError.BadRequest);

    private async Task<ActionResult<T>> RunAsync<T>(Func<Guid, CancellationToken, Task<T>> action)
    {
        if (!settings.IsConfigured())
        {
            return Error(SeerrError.NotConfigured);
        }

        var userId = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        try
        {
            // Costruito a mano: ActionResult<T> non converte da un tipo interfaccia.
            return new ActionResult<T>(await action(userId, HttpContext.RequestAborted).ConfigureAwait(false));
        }
        catch (SeerrException ex)
        {
            return Error(ex.Error);
        }
    }
}
```

`Api/RequestsWebhookController.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il webhook di Seerr (spec I §7.5): senza accesso Jellyfin, protetto dal
/// segreto nel corpo. Solo 401 (segreto) o 200: mai altro, così Seerr non
/// insiste con gli eventi che il plugin scarta.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Requests")]
[AllowAnonymous]
public class RequestsWebhookController(RequestWebhookHandler handler) : ControllerBase
{
    [HttpPost("Webhook")]
    [RequestSizeLimit(RequestWebhookHandler.MaxBodyBytes)]
    public async Task<ActionResult> Receive([FromBody] SeerrWebhookPayload? payload) =>
        await handler.HandleAsync(payload, HttpContext.RequestAborted).ConfigureAwait(false) == WebhookResult.Unauthorized
            ? Unauthorized()
            : (ActionResult)Ok();
}
```

In `PluginServiceRegistrator.cs`, dopo `ISeerrSettings`:

```csharp
        serviceCollection.AddHttpClient(SeerrClient.HttpClientName);
        serviceCollection.AddSingleton<ISeerrClient, SeerrClient>();
        serviceCollection.AddSingleton<SeerrUserMap>();
        serviceCollection.AddSingleton<SeerrTitleCache>();
        serviceCollection.AddSingleton<RequestsService>();
        serviceCollection.AddSingleton<RequestWebhookHandler>();
```

- [ ] **Step 4: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 5: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): expose the request endpoints and the Seerr webhook"
```

### Task 9: la pagina del plugin e il README

**Files:**
- Modify: `…/Configuration/configPage.html`
- Modify: `jellyfin-plugin-watch-party/README.md`
- Test: `…Tests/PluginPagesTests.cs`

- [ ] **Step 1: test che fallisce**

In `PluginPagesTests.TheDashboardPageIsEmbeddedAndSendsAnnouncements`, prima del commento sull'id:

```csharp
        // Sezione Seerr (spec I §7.1).
        Assert.Contains("SeerrUrl", html);
        Assert.Contains("SeerrApiKey", html);
        Assert.Contains("SeerrWebhookSecret", html);
        Assert.Contains("WonderFlixWatchParty/Requests/Test", html);
        Assert.Contains("WonderFlixWatchParty/Requests/Admin", html);
        Assert.Contains("WonderFlixWatchParty/Requests/Webhook", html);
        Assert.Contains("'{{extra}}': []", html);
        Assert.Contains("requestedBy_jellyfinUserId", html);
        Assert.Contains("crypto.getRandomValues", html);
```

- [ ] **Step 2: verifica che fallisca**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --filter "FullyQualifiedName~PluginPagesTests"`
Expected: FAIL (`SeerrUrl` non è nella pagina).

- [ ] **Step 3: la sezione Seerr**

In `configPage.html`:
- aggiungi `emby-input` a `data-require` (`data-require="emby-button,emby-textarea,emby-checkbox,emby-input"`);
- dopo la `</div>` che chiude la sezione "New titles" (prima di `</div>` di `content-primary`) aggiungi:

```html
                <form id="WonderFlixSeerrForm">
                    <div class="verticalSection">
                        <h3 class="sectionTitle">Seerr</h3>
                        <div class="inputContainer">
                            <input is="emby-input" type="url" id="WonderFlixSeerrUrl" label="Seerr address" placeholder="https://example.com/seerr" />
                            <div class="fieldDescription">As seen from the Jellyfin server. Empty: requests are off in WonderFlix.</div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="password" id="WonderFlixSeerrApiKey" label="Seerr API key" autocomplete="off" />
                            <div class="fieldDescription">Seerr → Settings → General → API Key.</div>
                        </div>
                        <button is="emby-button" type="submit" class="raised button-submit block emby-button">
                            <span>Save</span>
                        </button>
                        <button is="emby-button" id="WonderFlixSeerrTest" type="button" class="raised block emby-button">
                            <span>Test connection</span>
                        </button>
                        <div id="WonderFlixSeerrResult" class="fieldDescription"></div>
                        <h3 class="sectionTitle">Seerr webhook</h3>
                        <div class="fieldDescription">
                            In Seerr → Settings → Notifications → Webhook: turn it on, paste the URL and the JSON payload below,
                            and tick only "Request Pending Approval" and "Request Available".
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="text" id="WonderFlixSeerrWebhookUrl" label="Webhook URL" readonly />
                        </div>
                        <div class="inputContainer">
                            <textarea is="emby-textarea" id="WonderFlixSeerrTemplate" class="emby-textarea" rows="13" readonly></textarea>
                        </div>
                        <button is="emby-button" id="WonderFlixSeerrCopy" type="button" class="raised block emby-button">
                            <span>Copy the JSON payload</span>
                        </button>
                        <button is="emby-button" id="WonderFlixSeerrRegenerate" type="button" class="raised block emby-button">
                            <span>New secret</span>
                        </button>
                        <div class="fieldDescription">A new secret needs the new JSON payload in Seerr too.</div>
                        <div id="WonderFlixSeerrLastEvent" class="fieldDescription"></div>
                    </div>
                </form>
```

Nello script, dopo `var newTitlesResult = …;`:

```js
                var seerrUrl = page.querySelector('#WonderFlixSeerrUrl');
                var seerrKey = page.querySelector('#WonderFlixSeerrApiKey');
                var seerrResult = page.querySelector('#WonderFlixSeerrResult');
                var webhookUrl = page.querySelector('#WonderFlixSeerrWebhookUrl');
                var template = page.querySelector('#WonderFlixSeerrTemplate');
                var lastEvent = page.querySelector('#WonderFlixSeerrLastEvent');
                var webhookSecret = '';

                // Segreto del webhook: 24 byte casuali in esadecimale.
                function newSecret() {
                    var bytes = new Uint8Array(24);
                    crypto.getRandomValues(bytes);
                    return Array.from(bytes, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
                }

                // Il modello che Seerr riempie; '{{extra}}' è una chiave speciale
                // che Seerr sostituisce con "extra": [{ name, value }].
                function webhookTemplate(secret) {
                    return JSON.stringify({
                        secret: secret,
                        notification_type: '{{notification_type}}',
                        subject: '{{subject}}',
                        request_id: '{{request_id}}',
                        media_type: '{{media_type}}',
                        media_tmdbid: '{{media_tmdbid}}',
                        media_jellyfinMediaId: '{{media_jellyfinMediaId}}',
                        requestedBy_jellyfinUserId: '{{requestedBy_jellyfinUserId}}',
                        requestedBy_username: '{{requestedBy_username}}',
                        '{{extra}}': []
                    }, null, 2);
                }

                function renderWebhook() {
                    webhookUrl.value = ApiClient.getUrl('WonderFlixWatchParty/Requests/Webhook');
                    template.value = webhookSecret ? webhookTemplate(webhookSecret) : '';
                }

                function refreshSeerrStatus() {
                    ApiClient.ajax({
                        type: 'GET',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Requests/Admin'),
                        dataType: 'json'
                    }).then(function (status) {
                        lastEvent.textContent = status.LastEventAt
                            ? 'Last event received: ' + new Date(status.LastEventAt).toLocaleString() + ' (' + status.LastEventType + ').'
                            : 'No event received since Jellyfin started.';
                    }, function () {
                        lastEvent.textContent = '';
                    });
                }

                function loadSeerr() {
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        seerrUrl.value = config.SeerrUrl || '';
                        seerrKey.value = config.SeerrApiKey || '';
                        webhookSecret = config.SeerrWebhookSecret || '';
                        renderWebhook();
                        refreshSeerrStatus();
                    });
                }

                // Salva indirizzo, chiave e segreto; il segreto nasce al primo salvataggio.
                function saveSeerr(secret) {
                    seerrResult.textContent = '';
                    Dashboard.showLoadingMsg();
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        config.SeerrUrl = seerrUrl.value.trim();
                        config.SeerrApiKey = seerrKey.value.trim();
                        config.SeerrWebhookSecret = secret || config.SeerrWebhookSecret || newSecret();
                        return ApiClient.updatePluginConfiguration(pluginId, config);
                    }).then(function (saved) {
                        Dashboard.processPluginConfigurationUpdateResult(saved);
                        loadSeerr();
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        seerrResult.textContent = 'Settings not saved.';
                    });
                }

                page.addEventListener('pageshow', loadSeerr);
                loadSeerr();

                page.querySelector('#WonderFlixSeerrForm').addEventListener('submit', function (e) {
                    e.preventDefault();
                    saveSeerr(null);
                    return false;
                });

                page.querySelector('#WonderFlixSeerrRegenerate').addEventListener('click', function () {
                    saveSeerr(newSecret());
                });

                page.querySelector('#WonderFlixSeerrCopy').addEventListener('click', function () {
                    navigator.clipboard.writeText(template.value).then(function () {
                        seerrResult.textContent = 'JSON payload copied.';
                    }, function () {
                        template.select();
                        seerrResult.textContent = 'Copy it by hand (Ctrl+C).';
                    });
                });

                page.querySelector('#WonderFlixSeerrTest').addEventListener('click', function () {
                    seerrResult.textContent = 'Testing…';
                    ApiClient.ajax({
                        type: 'POST',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Requests/Test'),
                        dataType: 'json'
                    }).then(function (result) {
                        seerrResult.textContent = result.Ok
                            ? 'Connected to Seerr ' + result.Version + '.'
                            : result.Error === 'NotConfigured' ? 'Save the address and the API key first.'
                            : result.Error === 'SeerrAuth' ? 'Seerr refused the API key.'
                            : 'Seerr can\'t be reached from the Jellyfin server: check the address.';
                    }, function () {
                        seerrResult.textContent = 'Test failed: try again.';
                    });
                });
```

- [ ] **Step 4: README**

In `jellyfin-plugin-watch-party/README.md`, dopo il paragrafo che parla della 1.3.0 (prima di "Senza il plugin WonderFlix funziona lo stesso…"), aggiungi: `Dalla 1.4.0 fa da tramite verso Seerr per chiedere film e serie dall'app (spec I, docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md).`

Nell'elenco puntato, dopo **Party:**:

```markdown
- **Seerr (dalla 1.4.0):** nella pagina del plugin si mettono l'indirizzo di
  Seerr (come lo vede il server Jellyfin) e la sua chiave API; **Test
  connection** li prova. Con indirizzo e chiave `GET Info` annuncia
  `requests` e l'app mostra le richieste. Il plugin agisce in Seerr per
  conto dell'utente (`X-API-User`) e crea l'account Seerr mancante alla
  prima richiesta. Il **webhook** di Seerr (indirizzo, modello JSON con il
  segreto e i tipi "Request Pending Approval" e "Request Available"
  sono nella stessa pagina) porta nella cassetta "Ora disponibile" a chi ha
  chiesto il titolo e "Nuova richiesta" a chi può approvare. Indirizzo,
  chiave e segreto stanno nella configurazione del plugin, leggibile solo
  dagli admin.
```

Nella sezione "Installazione a mano (prove)" sostituisci `1.3.0` con `1.4.0` (comando e nome della cartella).

- [ ] **Step 5: verifica**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
Expected: PASS, tutti, senza warning.

- [ ] **Step 6: commit**

```bash
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): add the Seerr section to the plugin page"
```

## Gruppo C — STOP

### Task 10: STOP — installazione sul server (lo fa l'orchestratore)

Il subagent del Gruppo B si ferma qui. L'orchestratore, con l'ok dell'utente per ogni passo che tocca il server:

1. **Pacchetto:** dalla root del worktree `bash jellyfin-plugin-watch-party/pack.sh 1.4.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.4.0.0/`.
2. **Server** (`ssh ultra`; vedi la memoria `ultra-ssh` per le virgolette con `scp`):
   - controlla che nessuno stia guardando (`/Sessions` o log), come per le release passate;
   - `app-jellyfin stop`;
   - sposta la cartella del plugin dal Catalogo (`~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.3.0.0`) in `~/wfwp-backup/1.3.0.0-catalogo`;
   - `scp -r "<cartella 1.4.0.0>" ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.4.0.0"` e nessun errore del plugin.
3. **Collegamento:**
   - l'utente apre la pagina del plugin nella Dashboard e mette l'indirizzo `https://hashvps.proton.usbx.me/seerr` e la chiave API di Seerr (la incolla lui: l'orchestratore non la scrive);
   - salva e preme **Test connection**: deve comparire "Connected to Seerr 3.4.1".
   - Se non si collega (container di Jellyfin che non raggiunge l'indirizzo pubblico), si prova un indirizzo interno (spec I §13) e si riporta all'utente.
4. **Controllo:** `GET /WonderFlixWatchParty/Info` con un token dell'app dice `requests`.

Il webhook in Seerr **non** si configura in questo piano (piano 15b).

## Gruppo D — app, dati

### Task 11: il corpo negli errori e `JellyfinItem.tmdbId`

**Files:**
- Modify: `lib/core/jellyfin/api_exception.dart`
- Modify: `lib/core/jellyfin/item_models.dart`
- Test: `test/core/jellyfin/api_exception_body_test.dart`, `test/core/jellyfin/item_tmdb_id_test.dart`

- [ ] **Step 1: test che falliscono**

`test/core/jellyfin/api_exception_body_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late JellyfinHttp http;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    http = JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
  });

  test('403 e 409 portano il corpo della risposta (spec I §7.3)', () async {
    adapter.handler = (_) => const FakeResponse(403, {'Code': 'QuotaExceeded'});
    await expectLater(
        http.get('/x'),
        throwsA(isA<ForbiddenException>()
            .having((e) => e.body, 'body', {'Code': 'QuotaExceeded'})));

    adapter.handler = (_) => const FakeResponse(409, {'Code': 'AlreadyRequested'});
    await expectLater(
        http.post('/x'),
        throwsA(isA<ServerErrorException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.body, 'body', {'Code': 'AlreadyRequested'})));
  });

  test('senza corpo il campo è vuoto', () async {
    adapter.handler = (_) => const FakeResponse(500);
    await expectLater(
        http.get('/x'),
        throwsA(isA<ServerErrorException>()
            .having((e) => e.body, 'body', anyOf(isNull, ''))));
  });
}
```

`test/core/jellyfin/item_tmdb_id_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';

void main() {
  JellyfinItem item(Object? providerIds) => JellyfinItem.fromJson({
        'Id': 'ee39bef06f503dd0e9dbd20593df417f',
        'Name': 'Dune',
        'Type': 'Movie',
        'ProviderIds': providerIds,
      });

  test('tmdbId dai ProviderIds (spec I §8.1)', () {
    expect(item({'Tmdb': '438631', 'Imdb': 'tt1160419'}).tmdbId, 438631);
    expect(item({'Imdb': 'tt1160419'}).tmdbId, isNull);
    expect(item({'Tmdb': 'abc'}).tmdbId, isNull);
    expect(item(null).tmdbId, isNull);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/jellyfin/api_exception_body_test.dart test/core/jellyfin/item_tmdb_id_test.dart`
Expected: FAIL di compilazione (`body`, `tmdbId` non esistono).

- [ ] **Step 3: implementazione**

In `api_exception.dart`:

```dart
final class ForbiddenException extends ApiException {
  const ForbiddenException([this.body]);

  /// Corpo della risposta, se c'era (es. `{Code}` del plugin, spec I §7.3).
  final Object? body;
}
```

```dart
final class ServerErrorException extends ApiException {
  const ServerErrorException(this.statusCode, [this.body]);
  final int? statusCode;

  /// Corpo della risposta, se c'era (es. `{Code}` del plugin, spec I §7.3).
  final Object? body;

  @override
  String toString() => 'ServerErrorException($statusCode)';
}
```

e in `mapDioException`:

```dart
      return switch (e.response?.statusCode) {
        401 => const UnauthorizedException(),
        403 => ForbiddenException(e.response?.data),
        404 => const NotFoundException(),
        final code => ServerErrorException(code, e.response?.data),
      };
```

In `item_models.dart`:
- nel costruttore di `JellyfinItem`, dopo `this.trickplay = const {},`: `this.tmdbId,`;
- in `fromJson`, dopo `trickplay: _trickplay(json['Trickplay']),`: `tmdbId: _providerId(json['ProviderIds'], 'Tmdb'),`;
- tra i campi, dopo `trickplay`:

```dart

  /// Id TMDB dai `ProviderIds`, se c'è (spec I §8.1): serve alle richieste
  /// con Seerr. `GET /Items/{id}` lo dà sempre; gli elenchi solo se chiesto.
  final int? tmdbId;
```

- in fondo al file, accanto agli altri helper privati (`_int`, `_stringMap`…):

```dart
int? _providerId(Object? raw, String key) {
  if (raw is! Map) return null;
  final value = raw[key];
  return value is String ? int.tryParse(value) : null;
}
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/core/jellyfin test/core/jellyfin
git commit -m "feat(app): keep the error body and read the TMDB id of items"
```

### Task 12: modelli delle richieste e immagini TMDB

**Files:**
- Create: `lib/core/requests/requests_models.dart`, `lib/core/requests/tmdb_images.dart`
- Test: `test/core/requests/requests_models_test.dart`

- [ ] **Step 1: test che falliscono**

`test/core/requests/requests_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/core/requests/tmdb_images.dart';

void main() {
  test('Me', () {
    final me = RequestsMe.fromJson(
        {'CanRequest': true, 'CanManage': false, 'HasAccount': true});
    expect((me.canRequest, me.canManage, me.hasAccount), (true, false, true));
    expect(RequestsMe.none.canRequest, isFalse);
  });

  test('titolo della ricerca', () {
    final title = RequestableTitle.fromJson({
      'MediaType': 'tv',
      'TmdbId': 90228,
      'Title': 'Dune: Prophecy',
      'Year': 2024,
      'PosterPath': '/p.jpg',
      'Status': 'Processing',
      'JellyfinItemId': null,
    });
    expect(title.mediaType, RequestMediaType.tv);
    expect(title.tmdbId, 90228);
    expect(title.title, 'Dune: Prophecy');
    expect(title.year, 2024);
    expect(title.status, TitleStatus.processing);
    expect(title.jellyfinItemId, isNull);
    expect(() => RequestableTitle.fromJson({'MediaType': 'person', 'TmdbId': 1}),
        throwsFormatException);
  });

  test('stati sconosciuti', () {
    expect(TitleStatus.parse('Boh'), TitleStatus.none);
    expect(TitleStatus.none.isRequestable, isTrue);
    expect(TitleStatus.pending.isRequestable, isFalse);
    expect(RequestStatus.parse('Downloading'), RequestStatus.downloading);
    expect(RequestStatus.parse('Boh'), RequestStatus.approved);
  });

  test('scheda di una serie: stagioni da chiedere', () {
    final details = TitleDetails.fromJson({
      'MediaType': 'tv',
      'TmdbId': 250203,
      'Title': 'Brothers',
      'Year': 2026,
      'Overview': 'Due fratelli',
      'Genres': ['Commedia'],
      'RuntimeMinutes': null,
      'PosterPath': '/p.jpg',
      'BackdropPath': '/b.jpg',
      'TrailerUrl': 'https://www.youtube.com/watch?v=x',
      'Status': 'Partial',
      'JellyfinItemId': '6d1c8ea33a794f76fdbe92a216959073',
      'RequestedByMe': false,
      'Requested': true,
      'Seasons': [
        {'SeasonNumber': 1, 'EpisodeCount': 8, 'Status': 'Partial'},
        {'SeasonNumber': 2, 'EpisodeCount': 8, 'Status': 'None'},
      ],
    });
    expect(details.genres, ['Commedia']);
    expect(details.trailerUrl, 'https://www.youtube.com/watch?v=x');
    expect(details.seasons.map((s) => s.seasonNumber), [1, 2]);
    expect(details.requestableSeasons.map((s) => s.seasonNumber), [2]);
    expect(details.canBeRequested, isTrue);
    expect(details.requested, isTrue);
  });

  test('scheda di un film', () {
    final details = TitleDetails.fromJson({
      'MediaType': 'movie',
      'TmdbId': 841,
      'Title': 'Dune',
      'Genres': [],
      'RuntimeMinutes': 137,
      'Status': 'Pending',
      'RequestedByMe': true,
      'Requested': true,
    });
    expect(details.seasons, isEmpty);
    expect(details.runtimeMinutes, 137);
    expect(details.canBeRequested, isFalse);
  });

  test('richiesta, pagina, servizi, nuova richiesta', () {
    final page = RequestPage.fromJson({
      'Items': [
        {
          'Id': 434,
          'MediaType': 'tv',
          'TmdbId': 59941,
          'Title': 'Grey\'s Anatomy',
          'Year': 2005,
          'PosterPath': null,
          'Seasons': [14],
          'RequestedBy': {'Name': 'sronweb', 'IsMe': false},
          'CreatedAt': '2026-10-03T20:31:16+00:00',
          'Status': 'Downloading',
          'Progress': 0.75,
          'JellyfinItemId': null,
        },
      ],
      'HasMore': true,
    });
    final request = page.items.single;
    expect(page.hasMore, isTrue);
    expect(request.seasons, [14]);
    expect(request.requestedBy.name, 'sronweb');
    expect(request.createdAt, DateTime.utc(2026, 10, 3, 20, 31, 16));
    expect(request.status, RequestStatus.downloading);
    expect(request.progress, 0.75);

    final service = ServiceOption.fromJson({
      'Id': 1,
      'Name': 'Radarr Anime',
      'IsDefault': false,
      'Profiles': [
        {'Id': 7, 'Name': 'Anime Main Profile'},
      ],
      'RootFolders': ['/media/anime'],
      'DefaultProfileId': 7,
      'DefaultRootFolder': '/media/anime',
    });
    expect(service.profiles.single.name, 'Anime Main Profile');
    expect(service.rootFolders, ['/media/anime']);

    expect(CreatedRequest.fromJson({'Id': 7, 'Status': 'Pending'}).status,
        RequestStatus.pending);
    expect(ApproveChoice.defaults.toJson(), isEmpty);
    expect(
        const ApproveChoice(serverId: 1, profileId: 7, rootFolder: '/media/anime')
            .toJson(),
        {'ServerId': 1, 'ProfileId': 7, 'RootFolder': '/media/anime'});
  });

  test('immagini TMDB', () {
    expect(TmdbImages.poster('/p.jpg')!.url, 'https://image.tmdb.org/t/p/w342/p.jpg');
    expect(TmdbImages.backdrop('/b.jpg')!.url,
        'https://image.tmdb.org/t/p/w1280/b.jpg');
    expect(TmdbImages.poster(null), isNull);
    expect(TmdbImages.poster('p.jpg'), isNull);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/requests/requests_models_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/core/requests/requests_models.dart`:

```dart
// Modelli delle richieste con Seerr (spec I §8.1), dalle risposte del plugin.

/// Film o serie, con i nomi di Seerr.
enum RequestMediaType {
  movie('movie'),
  tv('tv');

  const RequestMediaType(this.wire);

  /// Il nome nelle rotte dell'app e negli endpoint del plugin.
  final String wire;

  static RequestMediaType? tryParse(Object? raw) => switch (raw) {
        'movie' => movie,
        'tv' => tv,
        _ => null,
      };
}

/// Stato di un titolo o di una stagione (spec I §7.3).
enum TitleStatus {
  none,
  pending,
  processing,
  partial,
  available;

  static TitleStatus parse(Object? raw) => switch (raw) {
        'Pending' => pending,
        'Processing' => processing,
        'Partial' => partial,
        'Available' => available,
        _ => none,
      };

  /// Si può ancora chiedere: nessuno l'ha chiesto e non c'è.
  bool get isRequestable => this == none;
}

/// Stato di una richiesta (spec I §7.3). Uno sconosciuto vale "approvata".
enum RequestStatus {
  pending,
  approved,
  downloading,
  partial,
  available,
  declined,
  failed;

  static RequestStatus parse(Object? raw) => switch (raw) {
        'Pending' => pending,
        'Downloading' => downloading,
        'Partial' => partial,
        'Available' => available,
        'Declined' => declined,
        'Failed' => failed,
        _ => approved,
      };
}

/// Gli elenchi delle richieste (spec I §7.3).
enum RequestsFilter {
  mine('mine'),
  pending('pending'),
  all('all');

  const RequestsFilter(this.wire);

  final String wire;
}

/// Cosa può fare l'utente con Seerr (`GET Requests/Me`).
class RequestsMe {
  const RequestsMe({
    required this.canRequest,
    required this.canManage,
    required this.hasAccount,
  });

  factory RequestsMe.fromJson(Map<String, dynamic> json) => RequestsMe(
        canRequest: json['CanRequest'] == true,
        canManage: json['CanManage'] == true,
        hasAccount: json['HasAccount'] == true,
      );

  /// Funzione spenta o non ancora nota: niente pulsanti.
  static const none =
      RequestsMe(canRequest: false, canManage: false, hasAccount: false);

  final bool canRequest;

  /// Può approvare e rifiutare (piano 15b).
  final bool canManage;
  final bool hasAccount;
}

/// Un risultato della ricerca di Seerr (sezione "Da richiedere").
class RequestableTitle {
  const RequestableTitle({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    this.year,
    this.posterPath,
    this.status = TitleStatus.none,
    this.jellyfinItemId,
  });

  factory RequestableTitle.fromJson(Map<String, dynamic> json) =>
      RequestableTitle(
        mediaType: _mediaType(json['MediaType']),
        tmdbId: _int(json['TmdbId']),
        title: json['Title'] as String? ?? '',
        year: _intOrNull(json['Year']),
        posterPath: json['PosterPath'] as String?,
        status: TitleStatus.parse(json['Status']),
        jellyfinItemId: json['JellyfinItemId'] as String?,
      );

  final RequestMediaType mediaType;
  final int tmdbId;
  final String title;
  final int? year;

  /// Percorso TMDB ("/abc.jpg"), per [TmdbImages].
  final String? posterPath;
  final TitleStatus status;

  /// L'elemento della libreria, in formato "N" minuscolo, se Seerr lo conosce.
  final String? jellyfinItemId;
}

/// Una stagione di una serie, senza gli speciali.
class SeasonInfo {
  const SeasonInfo({
    required this.seasonNumber,
    required this.episodeCount,
    this.status = TitleStatus.none,
  });

  factory SeasonInfo.fromJson(Map<String, dynamic> json) => SeasonInfo(
        seasonNumber: _int(json['SeasonNumber']),
        episodeCount: _intOrNull(json['EpisodeCount']) ?? 0,
        status: TitleStatus.parse(json['Status']),
      );

  final int seasonNumber;
  final int episodeCount;
  final TitleStatus status;
}

/// La scheda di un titolo di Seerr (`GET Requests/Movie|Tv/{id}`).
class TitleDetails {
  const TitleDetails({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    this.year,
    this.overview,
    this.genres = const [],
    this.runtimeMinutes,
    this.posterPath,
    this.backdropPath,
    this.trailerUrl,
    this.status = TitleStatus.none,
    this.jellyfinItemId,
    this.requestedByMe = false,
    this.requested = false,
    this.seasons = const [],
  });

  factory TitleDetails.fromJson(Map<String, dynamic> json) => TitleDetails(
        mediaType: _mediaType(json['MediaType']),
        tmdbId: _int(json['TmdbId']),
        title: json['Title'] as String? ?? '',
        year: _intOrNull(json['Year']),
        overview: json['Overview'] as String?,
        genres: [
          for (final genre in json['Genres'] as List? ?? const []) genre as String,
        ],
        runtimeMinutes: _intOrNull(json['RuntimeMinutes']),
        posterPath: json['PosterPath'] as String?,
        backdropPath: json['BackdropPath'] as String?,
        trailerUrl: json['TrailerUrl'] as String?,
        status: TitleStatus.parse(json['Status']),
        jellyfinItemId: json['JellyfinItemId'] as String?,
        requestedByMe: json['RequestedByMe'] == true,
        requested: json['Requested'] == true,
        seasons: [
          for (final season in json['Seasons'] as List? ?? const [])
            SeasonInfo.fromJson(season as Map<String, dynamic>),
        ],
      );

  final RequestMediaType mediaType;
  final int tmdbId;
  final String title;
  final int? year;
  final String? overview;
  final List<String> genres;
  final int? runtimeMinutes;
  final String? posterPath;
  final String? backdropPath;

  /// Trailer su YouTube (http o https), già controllato dal plugin.
  final String? trailerUrl;
  final TitleStatus status;
  final String? jellyfinItemId;

  /// C'è una richiesta aperta dell'utente.
  final bool requestedByMe;

  /// C'è una richiesta aperta di qualcuno.
  final bool requested;

  /// Solo per le serie, senza gli speciali.
  final List<SeasonInfo> seasons;

  /// Le stagioni che si possono ancora chiedere.
  List<SeasonInfo> get requestableSeasons =>
      [for (final season in seasons) if (season.status.isRequestable) season];

  /// C'è qualcosa da chiedere: per un film lo stato, per una serie almeno
  /// una stagione.
  bool get canBeRequested => mediaType == RequestMediaType.movie
      ? status.isRequestable
      : requestableSeasons.isNotEmpty;
}

/// Risposta di `POST Requests`.
class CreatedRequest {
  const CreatedRequest({required this.id, required this.status});

  factory CreatedRequest.fromJson(Map<String, dynamic> json) => CreatedRequest(
      id: _int(json['Id']), status: RequestStatus.parse(json['Status']));

  final int id;

  /// `pending`, oppure un altro stato se Seerr l'ha approvata da sola.
  final RequestStatus status;
}

/// Chi ha chiesto un titolo.
class Requester {
  const Requester({required this.name, required this.isMe});

  factory Requester.fromJson(Map<String, dynamic> json) => Requester(
      name: json['Name'] as String? ?? '', isMe: json['IsMe'] == true);

  final String name;
  final bool isMe;
}

/// Una richiesta negli elenchi (piano 15b).
class MediaRequest {
  const MediaRequest({
    required this.id,
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.seasons,
    required this.requestedBy,
    required this.createdAt,
    required this.status,
    this.year,
    this.posterPath,
    this.progress,
    this.jellyfinItemId,
  });

  factory MediaRequest.fromJson(Map<String, dynamic> json) => MediaRequest(
        id: _int(json['Id']),
        mediaType: _mediaType(json['MediaType']),
        tmdbId: _int(json['TmdbId']),
        title: json['Title'] as String? ?? '',
        year: _intOrNull(json['Year']),
        posterPath: json['PosterPath'] as String?,
        seasons: [
          for (final season in json['Seasons'] as List? ?? const [])
            (season as num).toInt(),
        ],
        requestedBy: Requester.fromJson(
            json['RequestedBy'] as Map<String, dynamic>? ?? const {}),
        createdAt: DateTime.parse(json['CreatedAt'] as String),
        status: RequestStatus.parse(json['Status']),
        progress: (json['Progress'] as num?)?.toDouble(),
        jellyfinItemId: json['JellyfinItemId'] as String?,
      );

  final int id;
  final RequestMediaType mediaType;
  final int tmdbId;

  /// Vuoto se Seerr non l'ha dato.
  final String title;
  final int? year;
  final String? posterPath;
  final List<int> seasons;
  final Requester requestedBy;
  final DateTime createdAt;
  final RequestStatus status;

  /// Avanzamento del download, da 0 a 1.
  final double? progress;
  final String? jellyfinItemId;
}

/// Una pagina di richieste.
class RequestPage {
  const RequestPage({required this.items, required this.hasMore});

  factory RequestPage.fromJson(Map<String, dynamic> json) => RequestPage(
        items: [
          for (final item in json['Items'] as List? ?? const [])
            MediaRequest.fromJson(item as Map<String, dynamic>),
        ],
        hasMore: json['HasMore'] == true,
      );

  final List<MediaRequest> items;
  final bool hasMore;
}

/// Un profilo di qualità di Radarr o Sonarr.
class ProfileOption {
  const ProfileOption({required this.id, required this.name});

  factory ProfileOption.fromJson(Map<String, dynamic> json) => ProfileOption(
      id: _int(json['Id']), name: json['Name'] as String? ?? '');

  final int id;
  final String name;
}

/// Un server di Radarr o Sonarr per la finestra Approva (piano 15b).
class ServiceOption {
  const ServiceOption({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.profiles,
    required this.rootFolders,
    this.defaultProfileId,
    this.defaultRootFolder,
  });

  factory ServiceOption.fromJson(Map<String, dynamic> json) => ServiceOption(
        id: _int(json['Id']),
        name: json['Name'] as String? ?? '',
        isDefault: json['IsDefault'] == true,
        profiles: [
          for (final profile in json['Profiles'] as List? ?? const [])
            ProfileOption.fromJson(profile as Map<String, dynamic>),
        ],
        rootFolders: [
          for (final folder in json['RootFolders'] as List? ?? const [])
            folder as String,
        ],
        defaultProfileId: _intOrNull(json['DefaultProfileId']),
        defaultRootFolder: json['DefaultRootFolder'] as String?,
      );

  final int id;
  final String name;
  final bool isDefault;
  final List<ProfileOption> profiles;
  final List<String> rootFolders;
  final int? defaultProfileId;
  final String? defaultRootFolder;
}

/// Server, profilo e cartella scelti all'approvazione; tutto vuoto =
/// predefiniti di Seerr.
class ApproveChoice {
  const ApproveChoice({this.serverId, this.profileId, this.rootFolder});

  static const defaults = ApproveChoice();

  final int? serverId;
  final int? profileId;
  final String? rootFolder;

  Map<String, Object> toJson() => {
        'ServerId': ?serverId,
        'ProfileId': ?profileId,
        'RootFolder': ?rootFolder,
      };
}

RequestMediaType _mediaType(Object? raw) =>
    RequestMediaType.tryParse(raw) ?? (throw FormatException('MediaType: $raw'));

int _int(Object? raw) => (raw as num).toInt();

int? _intOrNull(Object? raw) => raw is num ? raw.toInt() : null;
```

`lib/core/requests/tmdb_images.dart`:

```dart
import '../jellyfin/image_urls.dart';

/// Immagini di TMDB per i titoli che non sono nella libreria (spec I §8.1).
abstract final class TmdbImages {
  static const _base = 'https://image.tmdb.org/t/p';

  /// Larghezza delle locandine: card larghe 150 su schermi fino a 2x.
  static const posterSize = 'w342';

  /// Larghezza degli sfondi della scheda.
  static const backdropSize = 'w1280';

  static ImageRef? poster(String? path) => _ref(posterSize, path);

  static ImageRef? backdrop(String? path) => _ref(backdropSize, path);

  static ImageRef? _ref(String size, String? path) =>
      path == null || !path.startsWith('/') ? null : ImageRef('$_base/$size$path');
}
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/core/requests test/core/requests
git commit -m "feat(app): add the request models and TMDB images"
```

### Task 13: `RequestsApi`

**Files:**
- Create: `lib/core/requests/requests_api.dart`
- Test: `test/core/requests/requests_api_test.dart`

- [ ] **Step 1: test che falliscono**

`test/core/requests/requests_api_test.dart`:

```dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late RequestsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = RequestsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  RequestOptions last() => adapter.requests.last;

  test('Me e ricerca', () async {
    adapter.handler = (_) => const FakeResponse(
        200, {'CanRequest': true, 'CanManage': true, 'HasAccount': false});
    final me = await api.me();
    expect(last().path, '/WonderFlixWatchParty/Requests/Me');
    expect(me.canManage, isTrue);

    adapter.handler = (_) => const FakeResponse(200, [
          {'MediaType': 'movie', 'TmdbId': 841, 'Title': 'Dune', 'Status': 'None'},
        ]);
    final titles = await api.search('dune', language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/Search');
    expect(last().queryParameters, {'query': 'dune', 'language': 'it'});
    expect(titles.single.tmdbId, 841);
  });

  test('schede, richiesta, elenchi, servizi, approva e rifiuta', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'MediaType': 'tv',
          'TmdbId': 90228,
          'Title': 'Dune: Prophecy',
          'Status': 'None',
          'Seasons': [],
        });
    await api.title(RequestMediaType.tv, 90228, language: 'en');
    expect(last().path, '/WonderFlixWatchParty/Requests/Tv/90228');
    expect(last().queryParameters, {'language': 'en'});
    await api.title(RequestMediaType.movie, 841, language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/Movie/841');

    adapter.handler = (_) => const FakeResponse(200, {'Id': 7, 'Status': 'Pending'});
    final created = await api.create(RequestMediaType.tv, 90228, seasons: [1, 2]);
    expect(last().method, 'POST');
    expect(last().path, '/WonderFlixWatchParty/Requests');
    expect(last().data, {'MediaType': 'tv', 'TmdbId': 90228, 'Seasons': [1, 2]});
    expect(created.id, 7);
    await api.create(RequestMediaType.movie, 841);
    expect(last().data, {'MediaType': 'movie', 'TmdbId': 841});

    adapter.handler = (_) => const FakeResponse(200, {'Items': [], 'HasMore': false});
    await api.list(RequestsFilter.pending, skip: 20, take: 20, language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests');
    expect(last().queryParameters,
        {'filter': 'pending', 'skip': 20, 'take': 20, 'language': 'it'});

    adapter.handler = (_) => const FakeResponse(200, []);
    await api.services(RequestMediaType.movie);
    expect(last().path, '/WonderFlixWatchParty/Requests/Services/movie');

    adapter.handler = (_) => const FakeResponse(200, {
          'Id': 53,
          'MediaType': 'movie',
          'TmdbId': 841,
          'Title': 'Dune',
          'Seasons': [],
          'RequestedBy': {'Name': 'mario', 'IsMe': false},
          'CreatedAt': '2026-10-03T20:31:16+00:00',
          'Status': 'Approved',
        });
    await api.approve(53,
        const ApproveChoice(serverId: 1, profileId: 7, rootFolder: '/media/anime'),
        language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/53/Approve');
    expect(last().data, {'ServerId': 1, 'ProfileId': 7, 'RootFolder': '/media/anime'});
    expect(last().queryParameters, {'language': 'it'});
    final declined = await api.decline(53, language: 'it');
    expect(last().path, '/WonderFlixWatchParty/Requests/53/Decline');
    expect(declined.title, 'Dune');
  });

  test('errori con il codice del plugin', () async {
    Future<RequestsFailure> failureOf(int status, [Object? body]) async {
      adapter.handler = (_) => FakeResponse(status, body);
      try {
        await api.me();
      } on RequestsException catch (error) {
        return error.failure;
      }
      fail('nessun errore');
    }

    expect(await failureOf(404), RequestsFailure.unavailable);
    expect(await failureOf(503, {'Code': 'NotConfigured'}), RequestsFailure.notConfigured);
    expect(await failureOf(502, {'Code': 'SeerrUnavailable'}), RequestsFailure.seerrUnavailable);
    expect(await failureOf(502, {'Code': 'SeerrAuth'}), RequestsFailure.seerrUnavailable);
    expect(await failureOf(403, {'Code': 'NoPermission'}), RequestsFailure.noPermission);
    expect(await failureOf(403, {'Code': 'QuotaExceeded'}), RequestsFailure.quotaExceeded);
    expect(await failureOf(403, {'Code': 'Blocklisted'}), RequestsFailure.blocklisted);
    expect(await failureOf(409, {'Code': 'AlreadyRequested'}), RequestsFailure.alreadyRequested);
    expect(await failureOf(409, {'Code': 'NothingToRequest'}), RequestsFailure.nothingToRequest);
    expect(await failureOf(409, {'Code': 'AccountUnavailable'}), RequestsFailure.accountUnavailable);
    expect(await failureOf(409), RequestsFailure.network);
    expect(await failureOf(400, {'Code': 'Invalid'}), RequestsFailure.invalid);
    expect(await failureOf(500), RequestsFailure.network);
    expect(await failureOf(200, ['non', 'un', 'oggetto']), RequestsFailure.network);

    adapter.handler = (_) => throw const SocketException('rete');
    await expectLater(api.me(),
        throwsA(isA<RequestsException>().having((e) => e.failure, 'failure', RequestsFailure.network)));
  });

  test('una ricerca annullata resta annullata', () async {
    final cancel = CancelToken()..cancel();
    await expectLater(api.search('dune', language: 'it', cancelToken: cancel),
        throwsA(isA<RequestCancelledException>()));
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/requests/requests_api_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/core/requests/requests_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'requests_models.dart';

final _log = Logger('requests');

/// Perché una chiamata delle richieste non è riuscita (spec I §7.3).
enum RequestsFailure {
  /// 404: plugin assente o vecchio.
  unavailable,

  /// 503: Seerr non configurato nel plugin.
  notConfigured,

  /// 502: Seerr irraggiungibile, lento o con la chiave rifiutata.
  seerrUnavailable,

  noPermission,
  quotaExceeded,
  blocklisted,
  alreadyRequested,

  /// Le stagioni scelte sono già tutte chieste o presenti.
  nothingToRequest,

  /// L'account Seerr dell'utente non si è potuto creare.
  accountUnavailable,

  /// 400: parametri sbagliati o richiesta che non c'è più.
  invalid,

  /// Rete, errore del server o risposta di forma inattesa.
  network,
}

class RequestsException implements Exception {
  const RequestsException(this.failure);

  final RequestsFailure failure;

  @override
  String toString() => 'RequestsException(${failure.name})';
}

/// Endpoint delle richieste del plugin (spec I §7.3). Lancia solo
/// [RequestsException], oppure [RequestCancelledException] per una ricerca
/// annullata.
class RequestsApi {
  RequestsApi(this._http);

  static const _base = '/WonderFlixWatchParty/Requests';

  /// Esiti previsti (Seerr giù, già chiesto, permessi): nel log come info,
  /// non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {400, 403, 404, 409, 502, 503};

  final JellyfinHttp _http;

  Future<RequestsMe> me() => _call(() async => RequestsMe.fromJson(
      asJsonMap(await _http.get('$_base/Me', quietStatuses: _quiet))));

  /// Film e serie di Seerr per [query] (prima pagina).
  Future<List<RequestableTitle>> search(String query,
          {required String language, CancelToken? cancelToken}) =>
      _call(() async {
        final json = await _http.get('$_base/Search',
            query: {'query': query, 'language': language},
            cancelToken: cancelToken,
            quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            RequestableTitle.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<TitleDetails> title(RequestMediaType type, int tmdbId,
          {required String language}) =>
      _call(() async => TitleDetails.fromJson(asJsonMap(await _http.get(
          '$_base/${type == RequestMediaType.movie ? 'Movie' : 'Tv'}/$tmdbId',
          query: {'language': language},
          quietStatuses: _quiet))));

  /// Una richiesta; per le serie con le stagioni scelte.
  Future<CreatedRequest> create(RequestMediaType type, int tmdbId,
          {List<int>? seasons}) =>
      _call(() async => CreatedRequest.fromJson(asJsonMap(await _http.post(
          _base,
          body: {'MediaType': type.wire, 'TmdbId': tmdbId, 'Seasons': ?seasons},
          quietStatuses: _quiet))));

  Future<RequestPage> list(RequestsFilter filter,
          {required int skip, required int take, required String language}) =>
      _call(() async => RequestPage.fromJson(asJsonMap(await _http.get(_base,
          query: {
            'filter': filter.wire,
            'skip': skip,
            'take': take,
            'language': language,
          },
          quietStatuses: _quiet))));

  Future<List<ServiceOption>> services(RequestMediaType type) =>
      _call(() async {
        final json = await _http.get('$_base/Services/${type.wire}',
            quietStatuses: _quiet);
        return [
          for (final raw in json as List)
            ServiceOption.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<MediaRequest> approve(int requestId, ApproveChoice choice,
          {required String language}) =>
      _call(() async => MediaRequest.fromJson(asJsonMap(await _http.post(
          '$_base/$requestId/Approve',
          body: choice.toJson(),
          query: {'language': language},
          quietStatuses: _quiet))));

  Future<MediaRequest> decline(int requestId, {required String language}) =>
      _call(() async => MediaRequest.fromJson(asJsonMap(await _http.post(
          '$_base/$requestId/Decline',
          query: {'language': language},
          quietStatuses: _quiet))));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on RequestCancelledException {
      rethrow;
    } on NotFoundException {
      throw const RequestsException(RequestsFailure.unavailable);
    } on UnauthorizedException {
      throw const RequestsException(RequestsFailure.noPermission);
    } on ForbiddenException catch (error) {
      throw RequestsException(switch (_code(error.body)) {
        'QuotaExceeded' => RequestsFailure.quotaExceeded,
        'Blocklisted' => RequestsFailure.blocklisted,
        _ => RequestsFailure.noPermission,
      });
    } on ServerErrorException catch (error) {
      throw RequestsException(switch ((error.statusCode, _code(error.body))) {
        (409, 'AlreadyRequested') => RequestsFailure.alreadyRequested,
        (409, 'NothingToRequest') => RequestsFailure.nothingToRequest,
        (409, 'AccountUnavailable') => RequestsFailure.accountUnavailable,
        (400, _) => RequestsFailure.invalid,
        (502, _) => RequestsFailure.seerrUnavailable,
        (503, _) => RequestsFailure.notConfigured,
        _ => RequestsFailure.network,
      });
    } on ApiException {
      throw const RequestsException(RequestsFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta delle richieste non valida: ${error.runtimeType}');
      throw const RequestsException(RequestsFailure.network);
    }
  }

  static String? _code(Object? body) {
    if (body is! Map) return null;
    final code = body['Code'];
    return code is String ? code : null;
  }
}
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/core/requests test/core/requests
git commit -m "feat(app): call the request endpoints of the plugin"
```

### Task 14: la funzione `requests`, i provider e i finti

**Files:**
- Modify: `lib/core/social/social_models.dart`
- Modify: `lib/features/social/social_providers.dart`
- Create: `lib/features/requests/requests_providers.dart`
- Create: `test/support/requests_fakes.dart`
- Test: `test/features/social/social_providers_test.dart`, `test/features/requests/requests_providers_test.dart`

- [ ] **Step 1: i finti**

`test/support/requests_fakes.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';

/// Il plugin delle richieste finto: dati da preparare e chiamate registrate.
class FakeRequestsApi implements RequestsApi {
  RequestsMe meValue =
      const RequestsMe(canRequest: true, canManage: false, hasAccount: true);

  /// Risultati della ricerca per termine; un termine assente dà lista vuota.
  final searchResults = <String, List<RequestableTitle>>{};

  /// Schede per id TMDB; uno assente dà `invalid`.
  final titles = <int, TitleDetails>{};

  /// Se impostato, ogni chiamata lancia questo errore.
  RequestsFailure? failure;

  /// Errore solo per `create`.
  RequestsFailure? createFailure;

  RequestStatus createdStatus = RequestStatus.pending;

  /// Se impostati, `search` e `create` aspettano che si completino.
  Completer<void>? searchGate;
  Completer<void>? createGate;

  final calls = <String>[];
  final searchLanguages = <String>[];
  final created =
      <({RequestMediaType type, int tmdbId, List<int>? seasons})>[];

  void _fail() {
    final f = failure;
    if (f != null) throw RequestsException(f);
  }

  @override
  Future<RequestsMe> me() async {
    calls.add('me');
    _fail();
    return meValue;
  }

  @override
  Future<List<RequestableTitle>> search(String query,
      {required String language, CancelToken? cancelToken}) async {
    calls.add('search:$query');
    searchLanguages.add(language);
    final gate = searchGate;
    if (gate != null) await gate.future;
    if (cancelToken?.isCancelled ?? false) {
      throw const RequestCancelledException();
    }
    _fail();
    return searchResults[query] ?? const [];
  }

  @override
  Future<TitleDetails> title(RequestMediaType type, int tmdbId,
      {required String language}) async {
    calls.add('title:${type.wire}:$tmdbId');
    _fail();
    final details = titles[tmdbId];
    if (details == null) {
      throw const RequestsException(RequestsFailure.invalid);
    }
    return details;
  }

  @override
  Future<CreatedRequest> create(RequestMediaType type, int tmdbId,
      {List<int>? seasons}) async {
    calls.add('create:${type.wire}:$tmdbId');
    created.add((type: type, tmdbId: tmdbId, seasons: seasons));
    final gate = createGate;
    if (gate != null) await gate.future;
    _fail();
    final f = createFailure;
    if (f != null) throw RequestsException(f);
    return CreatedRequest(id: 100, status: createdStatus);
  }

  @override
  Future<RequestPage> list(RequestsFilter filter,
      {required int skip, required int take, required String language}) async {
    calls.add('list:${filter.wire}:$skip');
    _fail();
    return const RequestPage(items: [], hasMore: false);
  }

  @override
  Future<List<ServiceOption>> services(RequestMediaType type) async {
    calls.add('services:${type.wire}');
    _fail();
    return const [];
  }

  @override
  Future<MediaRequest> approve(int requestId, ApproveChoice choice,
          {required String language}) =>
      throw UnimplementedError('piano 15b');

  @override
  Future<MediaRequest> decline(int requestId, {required String language}) =>
      throw UnimplementedError('piano 15b');
}

/// Provider per i test delle richieste: plugin [api], funzione [available].
List<Override> requestsTestOverrides(FakeRequestsApi api,
        {bool available = true}) =>
    [
      requestsApiProvider.overrideWithValue(api),
      requestsAvailableProvider.overrideWithValue(available),
    ];

RequestableTitle testRequestable({
  int tmdbId = 693134,
  String title = 'Dune - Parte due',
  RequestMediaType type = RequestMediaType.movie,
  int? year = 2024,
  TitleStatus status = TitleStatus.none,
  String? jellyfinItemId,
}) =>
    RequestableTitle(
      mediaType: type,
      tmdbId: tmdbId,
      title: title,
      year: year,
      posterPath: '/p$tmdbId.jpg',
      status: status,
      jellyfinItemId: jellyfinItemId,
    );

TitleDetails testDetails({
  int tmdbId = 693134,
  String title = 'Dune - Parte due',
  RequestMediaType type = RequestMediaType.movie,
  TitleStatus status = TitleStatus.none,
  String? jellyfinItemId,
  bool requestedByMe = false,
  bool requested = false,
  String? trailerUrl,
  List<SeasonInfo> seasons = const [],
}) =>
    TitleDetails(
      mediaType: type,
      tmdbId: tmdbId,
      title: title,
      year: 2024,
      overview: 'Paul Atreides si unisce ai Fremen.',
      genres: const ['Fantascienza', 'Avventura'],
      runtimeMinutes: type == RequestMediaType.movie ? 166 : null,
      posterPath: '/p$tmdbId.jpg',
      backdropPath: '/b$tmdbId.jpg',
      trailerUrl: trailerUrl,
      status: status,
      jellyfinItemId: jellyfinItemId,
      requestedByMe: requestedByMe,
      requested: requested,
      seasons: seasons,
    );
```

- [ ] **Step 2: test che falliscono**

In `test/features/social/social_providers_test.dart`, dopo il test `'Info con la cassetta: funzione inbox'`:

```dart
  test('Info con le richieste: funzione requests, anche senza watch party',
      () async {
    api.install(features: const {PluginFeatures.inbox, PluginFeatures.requests});
    final c = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(inbox: true, requests: true));
  });
```

`test/features/requests/requests_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/requests_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  test('la funzione segue Info del plugin', () {
    final availability =
        FakeSocialAvailability(const SocialFeatures(inbox: true));
    final container = ProviderContainer.test(overrides: [
      socialAvailabilityProvider.overrideWith(() => availability),
    ]);
    expect(container.read(requestsAvailableProvider), isFalse);
    availability.set(const SocialFeatures(inbox: true, requests: true));
    expect(container.read(requestsAvailableProvider), isTrue);
  });

  test('Me: dal plugin solo con la funzione', () async {
    final api = FakeRequestsApi()
      ..meValue =
          const RequestsMe(canRequest: true, canManage: true, hasAccount: true);
    final off = ProviderContainer.test(
        overrides: requestsTestOverrides(api, available: false));
    expect((await off.read(requestsMeProvider.future)).canRequest, isFalse);
    expect(api.calls, isEmpty);

    final on = ProviderContainer.test(overrides: requestsTestOverrides(api));
    expect((await on.read(requestsMeProvider.future)).canManage, isTrue);
    expect(api.calls, ['me']);
  });
}
```

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/social/social_providers_test.dart test/features/requests/requests_providers_test.dart`
Expected: FAIL di compilazione (`PluginFeatures.requests`, `requests:`, `requests_providers.dart`).

- [ ] **Step 4: implementazione**

In `lib/core/social/social_models.dart`, in `PluginFeatures` dopo `inbox`:

```dart

  /// Le richieste con Seerr (spec I §7.1): solo con Seerr configurato nel plugin.
  static const requests = 'requests';
```

In `lib/features/social/social_providers.dart`, in `SocialFeatures`:
- nel costruttore, dopo `this.inbox = false,`: `this.requests = false,`;
- dopo il campo `inbox`:

```dart

  /// Le richieste con Seerr (spec I §8.2): non dipendono dai watch party.
  final bool requests;
```

- `operator ==`: aggiungi `other.requests == requests &&` dopo `other.inbox == inbox &&`;
- `hashCode`: `Object.hash(friends, parties, inbox, requests, known)`;
- `toString`: `'inbox: $inbox, requests: $requests, known: $known)'`.

In `SocialAvailability.refresh`, nel `SocialFeatures(...)` passato ad `_apply`, dopo `inbox: …`:

```dart
        requests: info.features.contains(PluginFeatures.requests),
```

`lib/features/requests/requests_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/requests/requests_api.dart';
import '../../core/requests/requests_models.dart';
import '../social/social_providers.dart';

final requestsApiProvider =
    Provider<RequestsApi>((ref) => RequestsApi(ref.watch(jellyfinHttpProvider)));

/// Il plugin ha le richieste con Seerr (spec I §8.2). Senza, nell'app non
/// cambia nulla.
final requestsAvailableProvider = Provider<bool>((ref) =>
    ref.watch(socialAvailabilityProvider.select((f) => f.requests)));

/// Cosa può fare l'utente con Seerr. Si rilegge ogni volta che una pagina
/// lo usa di nuovo (`autoDispose`); senza la funzione, niente.
final requestsMeProvider = FutureProvider.autoDispose<RequestsMe>((ref) async {
  if (!ref.watch(requestsAvailableProvider)) return RequestsMe.none;
  return ref.watch(requestsApiProvider).me();
});
```

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 6: commit**

```bash
git add lib test
git commit -m "feat(app): know when the plugin offers requests"
```

## Gruppo E — app, ricerca

### Task 15: testi del piano e "Seerr non risponde"

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify: `lib/app/error_text.dart`
- Test: `test/app/l10n_plan15a_test.dart`, `test/app/error_text_test.dart`

- [ ] **Step 1: test che falliscono**

`test/app/l10n_plan15a_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 15a', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.requestsSectionTitle, 'Da richiedere');
    expect(it.requestsSectionSubtitle, 'Non sono ancora su WonderFlix');
    expect(it.requestsSeerrDown, 'Seerr non risponde');
    expect(it.requestsBadgeOnWonderflix, 'Su WonderFlix');
    expect(it.requestsRequestSeasons(1), 'Richiedi 1 stagione');
    expect(it.requestsRequestSeasons(3), 'Richiedi 3 stagioni');
    expect(it.requestsSeasonLine(2, 1), 'Stagione 2 · 1 episodio');
    expect(it.requestsSeasonLine(1, 8), 'Stagione 1 · 8 episodi');
    expect(it.requestsAlreadyRequested, "Qualcuno l'ha già chiesto");
    expect(en.requestsSectionTitle, 'Available to request');
    expect(en.requestsRequestSeasons(1), 'Request 1 season');
    expect(en.requestsRequestSeasons(3), 'Request 3 seasons');
    expect(en.requestsSeasonLine(1, 8), 'Season 1 · 8 episodes');
    expect(en.requestsQuota, "You've reached your request limit");
  });
}
```

In `test/app/error_text_test.dart` aggiungi l'import `package:wonderflix/core/requests/requests_api.dart` e, dopo `'errori della riproduzione'` (usa la `l` già definita in cima a `main`):

```dart
  test('Seerr giù o non configurato', () {
    expect(describeError(l, const RequestsException(RequestsFailure.seerrUnavailable)),
        'Seerr non risponde');
    expect(describeError(l, const RequestsException(RequestsFailure.notConfigured)),
        'Seerr non risponde');
    expect(describeError(l, const RequestsException(RequestsFailure.network)),
        l.errorGeneric);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/app/l10n_plan15a_test.dart test/app/error_text_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: testi**

In fondo a `l10n/app_it.arb` (togli la `}` finale, aggiungi la virgola dopo l'ultima voce):

```json
  "requestsSectionTitle": "Da richiedere",
  "requestsSectionSubtitle": "Non sono ancora su WonderFlix",
  "requestsSeerrDown": "Seerr non risponde",
  "requestsKindMovie": "Film",
  "requestsKindSeries": "Serie",
  "requestsBadgeRequested": "Richiesto",
  "requestsBadgeComing": "In arrivo",
  "requestsBadgePartial": "In parte",
  "requestsBadgeOnWonderflix": "Su WonderFlix",
  "requestsRequestedByYou": "Richiesto da te",
  "requestsPartlyAvailable": "In parte disponibile",
  "requestsRequest": "Richiedi",
  "requestsRequestSeasons": "{count, plural, =1{Richiedi 1 stagione} other{Richiedi {count} stagioni}}",
  "@requestsRequestSeasons": {"placeholders": {"count": {"type": "int"}}},
  "requestsWatch": "Guarda",
  "requestsSeasons": "Stagioni",
  "requestsAllSeasons": "Tutte",
  "requestsSeasonLine": "Stagione {season} · {episodes, plural, =1{1 episodio} other{{episodes} episodi}}",
  "@requestsSeasonLine": {"placeholders": {"season": {"type": "int"}, "episodes": {"type": "int"}}},
  "requestsStatusToRequest": "Da richiedere",
  "requestsStatusPending": "In attesa",
  "requestsStatusAvailable": "Disponibile",
  "requestsSent": "Richiesta inviata",
  "requestsApprovedNow": "Richiesta approvata",
  "requestsAlreadyRequested": "Qualcuno l'ha già chiesto",
  "requestsQuota": "Hai raggiunto il limite di richieste",
  "requestsAccount": "Non è stato possibile creare il tuo account Seerr",
  "requestsBlocklisted": "Questo titolo non si può richiedere",
  "requestsNoPermission": "Non puoi richiedere titoli",
  "requestsFailed": "Non riuscito, riprova"
}
```

In fondo a `l10n/app_en.arb`, allo stesso modo:

```json
  "requestsSectionTitle": "Available to request",
  "requestsSectionSubtitle": "Not on WonderFlix yet",
  "requestsSeerrDown": "Seerr isn't responding",
  "requestsKindMovie": "Movie",
  "requestsKindSeries": "Series",
  "requestsBadgeRequested": "Requested",
  "requestsBadgeComing": "Coming soon",
  "requestsBadgePartial": "Partly here",
  "requestsBadgeOnWonderflix": "On WonderFlix",
  "requestsRequestedByYou": "Requested by you",
  "requestsPartlyAvailable": "Partly available",
  "requestsRequest": "Request",
  "requestsRequestSeasons": "{count, plural, =1{Request 1 season} other{Request {count} seasons}}",
  "requestsWatch": "Watch",
  "requestsSeasons": "Seasons",
  "requestsAllSeasons": "All",
  "requestsSeasonLine": "Season {season} · {episodes, plural, =1{1 episode} other{{episodes} episodes}}",
  "requestsStatusToRequest": "Not requested",
  "requestsStatusPending": "Pending",
  "requestsStatusAvailable": "Available",
  "requestsSent": "Request sent",
  "requestsApprovedNow": "Request approved",
  "requestsAlreadyRequested": "Someone already requested it",
  "requestsQuota": "You've reached your request limit",
  "requestsAccount": "Your Seerr account couldn't be created",
  "requestsBlocklisted": "This title can't be requested",
  "requestsNoPermission": "You can't request titles",
  "requestsFailed": "Didn't work, try again"
}
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: "Seerr non risponde" negli errori**

In `lib/app/error_text.dart` aggiungi `import '../core/requests/requests_api.dart';` e, nello `switch`, prima di `_ => l.errorGeneric,`:

```dart
      RequestsException(
        failure: RequestsFailure.seerrUnavailable || RequestsFailure.notConfigured
      ) =>
        l.requestsSeerrDown,
```

- [ ] **Step 5: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 6: commit**

```bash
git add l10n lib/app/error_text.dart test/app
git commit -m "feat(app): add the texts for requesting titles"
```

### Task 16: il controller della sezione "Da richiedere"

**Files:**
- Create: `lib/features/requests/requestables_controller.dart`
- Test: `test/features/requests/requestables_controller_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/requestables_controller_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requestables_controller.dart';
import 'package:wonderflix/features/search/search_controller.dart';

import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;

  ProviderContainer makeContainer({bool available = true}) {
    final container = ProviderContainer.test(
      overrides: requestsTestOverrides(api, available: available),
      retry: (_, _) => null,
    );
    container.listen(requestablesControllerProvider, (_, _) {});
    return container;
  }

  setUp(() {
    api = FakeRequestsApi()
      ..searchResults['dune'] = [
        testRequestable(tmdbId: 1, title: 'Dune'),
        testRequestable(
            tmdbId: 2, title: 'Dune: Prophecy', type: RequestMediaType.tv),
      ];
  });

  test('attende come la ricerca e cerca una volta, nella lingua data', () {
    fakeAsync((async) {
      final container = makeContainer();
      final controller = container.read(requestablesControllerProvider.notifier);
      controller.setTerm('du', language: 'it');
      async.elapse(const Duration(milliseconds: 100));
      controller.setTerm(' dune ', language: 'it');
      expect(container.read(requestablesControllerProvider).loading, isTrue);

      async.elapse(SearchController.debounce);
      async.flushMicrotasks();

      expect(api.calls, ['search:dune']);
      expect(api.searchLanguages, ['it']);
      final state = container.read(requestablesControllerProvider);
      expect(state.term, 'dune');
      expect(state.loading, isFalse);
      expect(state.titles!.map((t) => t.title), ['Dune', 'Dune: Prophecy']);
    });
  });

  test('meno di 2 lettere o funzione spenta: nessuna ricerca', () {
    fakeAsync((async) {
      final short = makeContainer();
      short.read(requestablesControllerProvider.notifier).setTerm('d', language: 'it');
      final off = makeContainer(available: false);
      off.read(requestablesControllerProvider.notifier).setTerm('dune', language: 'it');
      async.elapse(const Duration(seconds: 1));

      expect(api.calls, isEmpty);
      expect(short.read(requestablesControllerProvider).loading, isFalse);
      expect(off.read(requestablesControllerProvider).titles, isNull);
    });
  });

  test('la risposta di un termine superato si scarta', () {
    fakeAsync((async) {
      final gate = api.searchGate = Completer<void>();
      api.searchResults['dunes'] = [testRequestable(tmdbId: 3, title: 'Dunes')];
      final container = makeContainer();
      final controller = container.read(requestablesControllerProvider.notifier);
      controller.setTerm('dune', language: 'it');
      async.elapse(SearchController.debounce);
      controller.setTerm('dunes', language: 'it');
      async.elapse(SearchController.debounce);
      gate.complete();
      async.flushMicrotasks();

      final state = container.read(requestablesControllerProvider);
      expect(state.term, 'dunes');
      expect(state.titles!.single.title, 'Dunes');
    });
  });

  test('errore, poi Riprova', () {
    fakeAsync((async) {
      api.failure = RequestsFailure.seerrUnavailable;
      final container = makeContainer();
      final controller = container.read(requestablesControllerProvider.notifier);
      controller.setTerm('dune', language: 'it');
      async.elapse(SearchController.debounce);
      async.flushMicrotasks();
      expect(container.read(requestablesControllerProvider).error,
          isA<RequestsException>());

      api.failure = null;
      controller.retry(language: 'it');
      expect(container.read(requestablesControllerProvider).loading, isTrue);
      async.flushMicrotasks();

      final state = container.read(requestablesControllerProvider);
      expect(state.error, isNull);
      expect(state.titles, hasLength(2));
    });
  });

  test('i titoli già trovati nella libreria non si ripetono', () {
    final titles = [
      testRequestable(
          tmdbId: 1,
          status: TitleStatus.available,
          jellyfinItemId: 'ee39bef06f503dd0e9dbd20593df417f'),
      testRequestable(tmdbId: 2, status: TitleStatus.available, jellyfinItemId: 'aaa'),
      testRequestable(tmdbId: 3),
    ];
    expect(
        visibleRequestables(titles, {'EE39BEF06F503DD0E9DBD20593DF417F'.toLowerCase()})
            .map((t) => t.tmdbId),
        [2, 3]);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/requestables_controller_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/features/requests/requestables_controller.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/requests/requests_models.dart';
import '../search/search_controller.dart';
import 'requests_providers.dart';

class RequestablesState {
  const RequestablesState({
    this.term = '',
    this.titles,
    this.loading = false,
    this.error,
  });

  final String term;

  /// I titoli dell'ultima ricerca riuscita; restano mentre si scrive.
  final List<RequestableTitle>? titles;
  final bool loading;
  final Object? error;
}

/// I titoli per la sezione "Da richiedere" (spec I §8.3): segue il termine
/// della ricerca con la stessa attesa, ma è indipendente, così la libreria
/// non aspetta Seerr. Ogni nuova lettera annulla la ricerca precedente.
class RequestablesController extends Notifier<RequestablesState> {
  Timer? _debounce;
  CancelToken? _cancel;

  @override
  RequestablesState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancel?.cancel();
    });
    return const RequestablesState();
  }

  void setTerm(String raw, {required String language}) {
    final term = raw.trim();
    _debounce?.cancel();
    _cancel?.cancel();
    if (term.length < SearchController.minLength ||
        !ref.read(requestsAvailableProvider)) {
      state = RequestablesState(term: term);
      return;
    }
    state = RequestablesState(term: term, titles: state.titles, loading: true);
    _debounce = Timer(
        SearchController.debounce, () => unawaited(_search(term, language)));
  }

  /// Rifà subito la ricerca del termine di adesso (dopo un errore).
  void retry({required String language}) {
    final term = state.term;
    if (term.length < SearchController.minLength) return;
    _debounce?.cancel();
    _cancel?.cancel();
    state = RequestablesState(term: term, titles: state.titles, loading: true);
    unawaited(_search(term, language));
  }

  Future<void> _search(String term, String language) async {
    final cancel = _cancel = CancelToken();
    try {
      final titles = await ref
          .read(requestsApiProvider)
          .search(term, language: language, cancelToken: cancel);
      if (!ref.mounted || cancel.isCancelled) return;
      state = RequestablesState(term: term, titles: titles);
    } on RequestCancelledException {
      return;
    } on Object catch (error) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = RequestablesState(term: term, error: error);
    }
  }
}

final requestablesControllerProvider =
    NotifierProvider.autoDispose<RequestablesController, RequestablesState>(
        RequestablesController.new);

/// I titoli da mostrare in "Da richiedere" (spec I §8.3): senza quelli che
/// la ricerca nella libreria ha già trovato ([libraryIds], in minuscolo).
List<RequestableTitle> visibleRequestables(
        List<RequestableTitle> titles, Set<String> libraryIds) =>
    [
      for (final title in titles)
        if (title.jellyfinItemId == null ||
            !libraryIds.contains(title.jellyfinItemId!.toLowerCase()))
          title,
    ];
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/features/requests test/features/requests
git commit -m "feat(app): search Seerr alongside the library"
```

### Task 17: la sezione "Da richiedere" nella ricerca

**Files:**
- Create: `lib/features/requests/requests_navigation.dart`
- Create: `lib/features/requests/requestable_poster_card.dart`
- Create: `lib/features/requests/requestables_section.dart`
- Modify: `lib/features/search/search_screen.dart`
- Test: `test/features/requests/requests_navigation_test.dart`, `test/features/search/search_screen_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/requests_navigation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/requests_navigation.dart';

import '../../support/requests_fakes.dart';

void main() {
  test('rotta della scheda da richiedere', () {
    expect(tmdbRoute(RequestMediaType.movie, 693134), '/tmdb/movie/693134');
    expect(tmdbRoute(RequestMediaType.tv, 90228), '/tmdb/tv/90228');
  });

  testWidgets(
      'apre la scheda da richiedere, o quella della libreria se il titolo è già lì',
      (tester) async {
    final titles = {
      'film': testRequestable(tmdbId: 693134),
      'serie in parte': testRequestable(
          tmdbId: 90228,
          type: RequestMediaType.tv,
          status: TitleStatus.partial,
          jellyfinItemId: 'abc'),
      'già qui': testRequestable(
          tmdbId: 438631, status: TitleStatus.available, jellyfinItemId: 'ee39'),
    };
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Column(children: [
            for (final entry in titles.entries)
              TextButton(
                onPressed: () => openRequestable(context, entry.value),
                child: Text(entry.key),
              ),
          ]),
        ),
      ),
      GoRoute(
          path: '/tmdb/:type/:tmdbId',
          builder: (context, state) => const Text('scheda tmdb')),
      GoRoute(
          path: '/item/:id', builder: (context, state) => const Text('scheda')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    String path() => router.routerDelegate.currentConfiguration.uri.path;

    await tester.tap(find.text('film'));
    await tester.pumpAndSettle();
    expect(path(), '/tmdb/movie/693134');
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('serie in parte'));
    await tester.pumpAndSettle();
    expect(path(), '/tmdb/tv/90228');
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('già qui'));
    await tester.pumpAndSettle();
    expect(path(), '/item/ee39');
  });
}
```

In `test/features/search/search_screen_test.dart`:
- aggiungi gli import `package:wonderflix/core/requests/requests_api.dart`, `package:wonderflix/core/requests/requests_models.dart`, `package:wonderflix/features/requests/requests_providers.dart` e `'../../support/requests_fakes.dart'`;
- nei due test che ci sono, aggiungi agli `overrides` `requestsAvailableProvider.overrideWithValue(false),`;
- aggiungi:

```dart
  List<Override> overrides(FakeLibraryApi library, FakeRequestsApi requests,
          {bool available = true}) =>
      [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        ...requestsTestOverrides(requests, available: available),
      ];

  FakeLibraryApi libraryWithDune() => FakeLibraryApi()
    ..onItems = ((query, start, limit) => query.kinds.contains(ItemKind.movie)
        ? pageOf([testItem(id: 'ee39bef06f503dd0e9dbd20593df417f', name: 'Dune')])
        : pageOf([]))
    ..people = [];

  Future<void> search(WidgetTester tester, String term) async {
    await tester.enterText(find.byType(TextField), term);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('"Da richiedere" sotto i risultati, senza i titoli già in libreria',
      (tester) async {
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [
        testRequestable(
            tmdbId: 438631,
            title: 'Dune',
            status: TitleStatus.available,
            jellyfinItemId: 'ee39bef06f503dd0e9dbd20593df417f'),
        testRequestable(tmdbId: 693134, title: 'Dune - Parte due'),
        testRequestable(
            tmdbId: 90228,
            title: 'Dune: Prophecy',
            type: RequestMediaType.tv,
            status: TitleStatus.pending),
      ];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Da richiedere'), findsOneWidget);
    expect(find.text('Non sono ancora su WonderFlix'), findsOneWidget);
    expect(find.text('Dune - Parte due'), findsOneWidget);
    expect(find.text('Dune: Prophecy'), findsOneWidget);
    expect(find.text('Richiesto'), findsOneWidget);
    // "Film" è il titolo della sezione della libreria e l'etichetta della card.
    expect(find.text('Film'), findsNWidgets(2));
    // Dune c'è una volta sola: la card della libreria.
    expect(find.text('Dune'), findsOneWidget);
    expect(requests.searchLanguages, ['it']);
  });

  testWidgets('Seerr giù: messaggio e Riprova, la libreria resta', (tester) async {
    final requests = FakeRequestsApi()..failure = RequestsFailure.seerrUnavailable;
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Seerr non risponde'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);

    requests
      ..failure = null
      ..searchResults['dune'] = [testRequestable(title: 'Dune - Parte due')];
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Seerr non risponde'), findsNothing);
    expect(find.text('Dune - Parte due'), findsOneWidget);
  });

  testWidgets('senza titoli da richiedere la sezione non c\'è', (tester) async {
    final requests = FakeRequestsApi();
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests));

    await search(tester, 'dune');

    expect(find.text('Da richiedere'), findsNothing);
    expect(requests.calls, ['search:dune']);
  });

  testWidgets('senza la funzione: niente sezione e niente Seerr', (tester) async {
    final requests = FakeRequestsApi()
      ..searchResults['dune'] = [testRequestable()];
    await pumpApp(tester, const Scaffold(body: SearchScreen()),
        overrides: overrides(libraryWithDune(), requests, available: false));

    await search(tester, 'dune');

    expect(find.text('Da richiedere'), findsNothing);
    expect(requests.calls, isEmpty);
  });
```

(`Override` viene da `package:flutter_riverpod/misc.dart`: aggiungi l'import.)

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/requests_navigation_test.dart test/features/search/search_screen_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: navigazione**

`lib/features/requests/requests_navigation.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../core/requests/requests_models.dart';

/// La rotta della scheda da richiedere (spec I §9.2).
String tmdbRoute(RequestMediaType type, int tmdbId) =>
    '/tmdb/${type.wire}/$tmdbId';

/// Apre un titolo di Seerr: la scheda della libreria se c'è già tutto
/// ("Su WonderFlix"), altrimenti la scheda da richiedere.
void openRequestable(BuildContext context, RequestableTitle title) {
  final itemId = title.jellyfinItemId;
  if (title.status == TitleStatus.available && itemId != null) {
    openItemById(context, itemId);
    return;
  }
  unawaited(context.push(tmdbRoute(title.mediaType, title.tmdbId)));
}
```

- [ ] **Step 4: la card**

`lib/features/requests/requestable_poster_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';

/// L'etichetta di una card "Da richiedere" (spec I §9.1).
String requestableBadge(AppLocalizations l, RequestableTitle title) =>
    switch (title.status) {
      TitleStatus.none => title.mediaType == RequestMediaType.movie
          ? l.requestsKindMovie
          : l.requestsKindSeries,
      TitleStatus.pending => l.requestsBadgeRequested,
      TitleStatus.processing => l.requestsBadgeComing,
      TitleStatus.partial => l.requestsBadgePartial,
      TitleStatus.available => l.requestsBadgeOnWonderflix,
    };

/// Locandina 2:3 di un titolo di Seerr (spec I §9.1): immagine di TMDB,
/// etichetta in alto a sinistra, titolo e anno. Come `PosterCard` ma senza
/// l'anteprima al passaggio del mouse.
class RequestablePosterCard extends StatefulWidget {
  const RequestablePosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.width = 150,
  });

  final RequestableTitle title;
  final VoidCallback onTap;
  final double width;

  @override
  State<RequestablePosterCard> createState() => _RequestablePosterCardState();
}

class _RequestablePosterCardState extends State<RequestablePosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = widget.title;
    final year = title.year;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WfImage(image: TmdbImages.poster(title.posterPath)),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: RequestBadge(
                            label: requestableBadge(l, title),
                            highlighted: title.status != TitleStatus.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(title.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (year != null)
                Text('$year',
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etichetta piccola: oro per lo stato di una richiesta, scura per il tipo.
class RequestBadge extends StatelessWidget {
  const RequestBadge({super.key, required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  /// Fondo dell'etichetta del tipo: il nero dell'app, quasi opaco.
  static const _darkFill = Color(0xCC0A0A0A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted ? WfColors.gold : _darkFill,
        borderRadius: BorderRadius.circular(3),
        border: highlighted ? null : Border.all(color: WfColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: highlighted ? WfColors.bg : WfColors.cream,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: la sezione**

`lib/features/requests/requestables_section.dart`:

```dart
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shimmer.dart';
import '../../ui/states.dart';
import '../search/search_controller.dart';
import 'requestable_poster_card.dart';
import 'requestables_controller.dart';
import 'requests_navigation.dart';
import 'requests_providers.dart';

/// "Da richiedere" in fondo alla ricerca (spec I §9.1): i titoli di Seerr
/// che la ricerca nella libreria non ha trovato. Senza la funzione, o senza
/// titoli da mostrare, non c'è.
class RequestablesSection extends ConsumerWidget {
  const RequestablesSection({super.key, required this.libraryIds});

  /// Id dei risultati della libreria per il termine di adesso, in
  /// minuscolo; `null` mentre la ricerca nella libreria è in corso (la
  /// sezione aspetta, per non mostrare doppioni).
  final Set<String>? libraryIds;

  /// Larghezza delle card, come quelle della libreria.
  static const cardWidth = 150.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(requestsAvailableProvider)) return const SizedBox.shrink();
    final state = ref.watch(requestablesControllerProvider);
    if (state.term.length < SearchController.minLength) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final ids = libraryIds;
    final titles = state.titles;
    final Widget body;
    if (state.error != null) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.requestsSeerrDown,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => ref
                .read(requestablesControllerProvider.notifier)
                .retry(language: Localizations.localeOf(context).languageCode),
            child: Text(l.retry),
          ),
        ],
      );
    } else if (titles == null || ids == null) {
      body = const _RequestablesSkeleton();
    } else {
      final visible = visibleRequestables(titles, ids);
      if (visible.isEmpty) return const SizedBox.shrink();
      body = Wrap(
        spacing: 16,
        runSpacing: 24,
        children: [
          for (final title in visible)
            RequestablePosterCard(
              key: ValueKey('requestable-${title.mediaType.wire}-${title.tmdbId}'),
              title: title,
              width: cardWidth,
              onTap: () => openRequestable(context, title),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.requestsSectionTitle, style: WfText.display(26)),
          const SizedBox(height: 4),
          Text(l.requestsSectionSubtitle,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

/// Una riga di locandine vuote mentre Seerr risponde.
class _RequestablesSkeleton extends StatelessWidget {
  const _RequestablesSkeleton();

  /// Locandine nello scheletro.
  static const _count = 6;

  @override
  Widget build(BuildContext context) {
    return WfShimmer(
      child: Wrap(
        spacing: 16,
        children: [
          for (var i = 0; i < _count; i++)
            const SkeletonBox(
                width: RequestablesSection.cardWidth,
                height: RequestablesSection.cardWidth * 3 / 2),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: la ricerca**

In `lib/features/search/search_screen.dart`:
- import `../requests/requestables_controller.dart` e `../requests/requestables_section.dart`;
- il `TextField` diventa:

```dart
        TextField(
          autofocus: true,
          onChanged: (value) {
            controller.setTerm(value);
            ref.read(requestablesControllerProvider.notifier).setTerm(value,
                language: Localizations.localeOf(context).languageCode);
          },
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: l.searchHint,
            prefixIcon: const Icon(LucideIcons.search, color: WfColors.creamMuted),
          ),
        ),
```

- dopo `WfSwitcher(child: _results(context, l, state)),`:

```dart
        RequestablesSection(libraryIds: _libraryIds(state)),
```

- e il metodo, dopo `_results`:

```dart
  /// Id dei film e delle serie trovati nella libreria, in minuscolo, per
  /// non ripeterli in "Da richiedere"; `null` mentre la ricerca è in corso.
  /// Con un errore della libreria la sezione non aspetta.
  static Set<String>? _libraryIds(SearchState state) {
    if (state.error != null) return const {};
    final results = state.results;
    if (state.loading || results == null) return null;
    return {
      for (final item in [...results.movies, ...results.series])
        item.id.toLowerCase(),
    };
  }
```

- [ ] **Step 7: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 8: commit**

```bash
git add lib/features/requests lib/features/search test/features/requests test/features/search
git commit -m "feat(app): show titles to request at the end of the search"
```

## Gruppo F — app, scheda

### Task 18: il controller della scheda da richiedere

**Files:**
- Create: `lib/features/requests/request_title_controller.dart`
- Test: `test/features/requests/request_title_controller_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/request_title_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_title_controller.dart';

import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  const movieKey = (type: RequestMediaType.movie, tmdbId: 693134, language: 'it');
  const seriesKey = (type: RequestMediaType.tv, tmdbId: 90228, language: 'it');

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
        overrides: requestsTestOverrides(api), retry: (_, _) => null);
    container.listen(requestTitleControllerProvider(movieKey), (_, _) {});
    container.listen(requestTitleControllerProvider(seriesKey), (_, _) {});
    return container;
  }

  setUp(() {
    api = FakeRequestsApi()
      ..titles[693134] = testDetails()
      ..titles[90228] = testDetails(
        tmdbId: 90228,
        title: 'Dune: Prophecy',
        type: RequestMediaType.tv,
        seasons: const [
          SeasonInfo(seasonNumber: 1, episodeCount: 6, status: TitleStatus.available),
          SeasonInfo(seasonNumber: 2, episodeCount: 8),
          SeasonInfo(seasonNumber: 3, episodeCount: 8),
        ],
      );
  });

  test('carica la scheda e sceglie le stagioni che si possono chiedere', () async {
    final container = makeContainer();
    await pumpEventQueue();

    final state = container.read(requestTitleControllerProvider(seriesKey));
    expect(state.details!.title, 'Dune: Prophecy');
    expect(state.selected, {2, 3});
    expect(api.calls, contains('title:tv:90228'));
  });

  test('caselle: solo le stagioni da chiedere, e "Tutte"', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(seriesKey).notifier);
    RequestTitleState state() =>
        container.read(requestTitleControllerProvider(seriesKey));

    controller.toggleSeason(1);
    expect(state().selected, {2, 3});
    controller.toggleSeason(2);
    expect(state().selected, {3});
    controller.toggleAll();
    expect(state().selected, {2, 3});
    controller.toggleAll();
    expect(state().selected, isEmpty);
  });

  test('richiesta di una serie con le stagioni scelte, poi ricarica', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(seriesKey).notifier);
    controller.toggleSeason(3);

    final outcome = await controller.submit();
    await pumpEventQueue();

    expect(outcome, RequestOutcome.sent);
    expect(api.created.single.seasons, [2]);
    expect(api.calls.where((c) => c == 'title:tv:90228'), hasLength(2));
    expect(container.read(requestTitleControllerProvider(seriesKey)).sending,
        isFalse);
  });

  test('un film approvato da solo', () async {
    api.createdStatus = RequestStatus.approved;
    final container = makeContainer();
    await pumpEventQueue();

    final outcome = await container
        .read(requestTitleControllerProvider(movieKey).notifier)
        .submit();

    expect(outcome, RequestOutcome.approved);
    expect(api.created.single.seasons, isNull);
  });

  test('gli errori diventano esiti per l\'avviso', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);

    Future<RequestOutcome?> withFailure(RequestsFailure failure) async {
      api.createFailure = failure;
      final outcome = await controller.submit();
      await pumpEventQueue();
      return outcome;
    }

    expect(await withFailure(RequestsFailure.alreadyRequested),
        RequestOutcome.alreadyRequested);
    expect(await withFailure(RequestsFailure.nothingToRequest),
        RequestOutcome.alreadyRequested);
    expect(await withFailure(RequestsFailure.quotaExceeded), RequestOutcome.quota);
    expect(await withFailure(RequestsFailure.accountUnavailable),
        RequestOutcome.account);
    expect(await withFailure(RequestsFailure.seerrUnavailable),
        RequestOutcome.failed);
  });

  test('niente da mandare: nessuna richiesta', () async {
    api.titles[693134] = testDetails(status: TitleStatus.pending);
    final container = makeContainer();
    await pumpEventQueue();
    final series =
        container.read(requestTitleControllerProvider(seriesKey).notifier);
    series.toggleAll();

    expect(await series.submit(), isNull);
    expect(
        await container
            .read(requestTitleControllerProvider(movieKey).notifier)
            .submit(),
        isNull);
    expect(api.created, isEmpty);
  });

  test('un secondo clic durante l\'invio non manda niente', () async {
    final gate = api.createGate = Completer<void>();
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);

    final first = controller.submit();
    expect(container.read(requestTitleControllerProvider(movieKey)).sending,
        isTrue);
    expect(await controller.submit(), isNull);
    gate.complete();

    expect(await first, RequestOutcome.sent);
    expect(api.created, hasLength(1));
  });

  test('errore al primo caricamento; una ricarica fallita tiene la scheda',
      () async {
    api.failure = RequestsFailure.seerrUnavailable;
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);
    expect(container.read(requestTitleControllerProvider(movieKey)).error,
        isA<RequestsException>());

    api.failure = null;
    await controller.load();
    expect(container.read(requestTitleControllerProvider(movieKey)).details,
        isNotNull);

    api.failure = RequestsFailure.network;
    await controller.load();
    final state = container.read(requestTitleControllerProvider(movieKey));
    expect(state.details, isNotNull);
    expect(state.error, isNull);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/request_title_controller_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/features/requests/request_title_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/requests/requests_api.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'requests_providers.dart';

/// La scheda: tipo, id TMDB e lingua dell'app.
typedef RequestTitleKey = ({RequestMediaType type, int tmdbId, String language});

class RequestTitleState {
  const RequestTitleState({
    this.details,
    this.error,
    this.selected = const {},
    this.sending = false,
  });

  final TitleDetails? details;

  /// Errore del primo caricamento. Con la scheda già caricata un errore di
  /// ricarica non si mostra.
  final Object? error;

  /// Stagioni scelte (solo serie).
  final Set<int> selected;

  /// Una richiesta è in viaggio: Richiedi è bloccato.
  final bool sending;

  RequestTitleState copyWith({Set<int>? selected, bool? sending}) =>
      RequestTitleState(
        details: details,
        error: error,
        selected: selected ?? this.selected,
        sending: sending ?? this.sending,
      );
}

/// Esito di Richiedi, per l'avviso (spec I §9.2).
enum RequestOutcome {
  sent,
  approved,
  alreadyRequested,
  quota,
  account,
  blocklisted,
  noPermission,
  failed,
}

String requestOutcomeText(AppLocalizations l, RequestOutcome outcome) =>
    switch (outcome) {
      RequestOutcome.sent => l.requestsSent,
      RequestOutcome.approved => l.requestsApprovedNow,
      RequestOutcome.alreadyRequested => l.requestsAlreadyRequested,
      RequestOutcome.quota => l.requestsQuota,
      RequestOutcome.account => l.requestsAccount,
      RequestOutcome.blocklisted => l.requestsBlocklisted,
      RequestOutcome.noPermission => l.requestsNoPermission,
      RequestOutcome.failed => l.requestsFailed,
    };

/// La scheda da richiedere (spec I §8.4): carica i dati, tiene le stagioni
/// scelte, manda la richiesta e poi ricarica lo stato da Seerr.
class RequestTitleController extends Notifier<RequestTitleState> {
  RequestTitleController(this.titleKey);

  final RequestTitleKey titleKey;

  /// Numera i caricamenti: vale solo l'ultimo.
  int _loads = 0;

  @override
  RequestTitleState build() {
    unawaited(Future.microtask(load));
    return const RequestTitleState();
  }

  /// Carica (o ricarica) la scheda. Le stagioni scelte diventano tutte
  /// quelle che si possono ancora chiedere.
  Future<void> load() async {
    final current = ++_loads;
    if (state.details == null && state.error != null) {
      state = const RequestTitleState();
    }
    try {
      final details = await ref.read(requestsApiProvider).title(
          titleKey.type, titleKey.tmdbId,
          language: titleKey.language);
      if (!ref.mounted || current != _loads) return;
      state = RequestTitleState(
        details: details,
        selected: {
          for (final season in details.requestableSeasons) season.seasonNumber,
        },
      );
    } on Object catch (error) {
      if (!ref.mounted || current != _loads) return;
      if (state.details == null) state = RequestTitleState(error: error);
    }
  }

  void toggleSeason(int seasonNumber) {
    final details = state.details;
    if (details == null ||
        state.sending ||
        !details.requestableSeasons.any((s) => s.seasonNumber == seasonNumber)) {
      return;
    }
    final selected = {...state.selected};
    if (!selected.remove(seasonNumber)) selected.add(seasonNumber);
    state = state.copyWith(selected: selected);
  }

  /// "Tutte": sceglie tutte le stagioni da chiedere, o nessuna se lo erano già.
  void toggleAll() {
    final details = state.details;
    if (details == null || state.sending) return;
    final all = {
      for (final season in details.requestableSeasons) season.seasonNumber,
    };
    state = state.copyWith(
        selected: state.selected.containsAll(all) ? <int>{} : all);
  }

  /// Manda la richiesta: l'esito per l'avviso, `null` se non c'era niente
  /// da mandare o una richiesta era già in viaggio.
  Future<RequestOutcome?> submit() async {
    final details = state.details;
    if (details == null || state.sending || !details.canBeRequested) {
      return null;
    }
    final seasons = details.mediaType == RequestMediaType.tv
        ? (state.selected.toList()..sort())
        : null;
    if (seasons != null && seasons.isEmpty) return null;
    state = state.copyWith(sending: true);
    RequestOutcome outcome;
    try {
      final created = await ref
          .read(requestsApiProvider)
          .create(details.mediaType, details.tmdbId, seasons: seasons);
      outcome = created.status == RequestStatus.pending
          ? RequestOutcome.sent
          : RequestOutcome.approved;
    } on RequestsException catch (error) {
      outcome = switch (error.failure) {
        RequestsFailure.alreadyRequested ||
        RequestsFailure.nothingToRequest =>
          RequestOutcome.alreadyRequested,
        RequestsFailure.quotaExceeded => RequestOutcome.quota,
        RequestsFailure.accountUnavailable => RequestOutcome.account,
        RequestsFailure.blocklisted => RequestOutcome.blocklisted,
        RequestsFailure.noPermission => RequestOutcome.noPermission,
        _ => RequestOutcome.failed,
      };
    } on Object {
      outcome = RequestOutcome.failed;
    }
    if (ref.mounted) {
      state = state.copyWith(sending: false);
      // Il nuovo stato (Richiesto, In arrivo) lo dice Seerr.
      unawaited(load());
    }
    return outcome;
  }
}

final requestTitleControllerProvider = NotifierProvider.autoDispose
    .family<RequestTitleController, RequestTitleState, RequestTitleKey>(
        RequestTitleController.new);
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/features/requests test/features/requests
git commit -m "feat(app): load a title from Seerr and send the request"
```

### Task 19: `SeasonPicker`

**Files:**
- Create: `lib/features/requests/season_picker.dart`
- Test: `test/features/requests/season_picker_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/season_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/season_picker.dart';

import '../../support/pump_app.dart';

void main() {
  const seasons = [
    SeasonInfo(seasonNumber: 1, episodeCount: 6, status: TitleStatus.available),
    SeasonInfo(seasonNumber: 2, episodeCount: 1),
    SeasonInfo(seasonNumber: 3, episodeCount: 8, status: TitleStatus.pending),
    SeasonInfo(seasonNumber: 4, episodeCount: 8),
  ];

  Future<List<String>> pumpPicker(WidgetTester tester,
      {Set<int> selected = const {2, 4},
      bool enabled = true,
      List<SeasonInfo> list = seasons}) async {
    final taps = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: SeasonPicker(
          seasons: list,
          selected: selected,
          enabled: enabled,
          onToggle: (n) => taps.add('stagione $n'),
          onToggleAll: () => taps.add('tutte'),
        ),
      ),
    );
    return taps;
  }

  Checkbox checkboxOf(WidgetTester tester, String key) => tester.widget<Checkbox>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Checkbox)));

  testWidgets('righe con episodi e stato; "Tutte" in cima', (tester) async {
    await pumpPicker(tester, selected: const {2});

    expect(find.text('Tutte'), findsOneWidget);
    expect(find.text('Stagione 1 · 6 episodi'), findsOneWidget);
    expect(find.text('Stagione 2 · 1 episodio'), findsOneWidget);
    expect(find.text('Disponibile'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Da richiedere'), findsNWidgets(2));
    // Le stagioni già presenti o chieste sono segnate e bloccate.
    expect(checkboxOf(tester, 'season-1').value, isTrue);
    expect(checkboxOf(tester, 'season-1').onChanged, isNull);
    expect(checkboxOf(tester, 'season-2').value, isTrue);
    expect(checkboxOf(tester, 'season-4').value, isFalse);
    // Una sola su due scelta: "Tutte" a metà.
    expect(checkboxOf(tester, 'season-all').value, isNull);
  });

  testWidgets('clic: solo sulle stagioni da chiedere', (tester) async {
    final taps = await pumpPicker(tester);

    await tester.tap(find.text('Stagione 4 · 8 episodi'));
    await tester.tap(find.text('Stagione 1 · 6 episodi'));
    await tester.tap(find.text('Tutte'));

    expect(taps, ['stagione 4', 'tutte']);
    expect(checkboxOf(tester, 'season-all').value, isTrue);
  });

  testWidgets('spento durante l\'invio', (tester) async {
    final taps = await pumpPicker(tester, enabled: false);

    await tester.tap(find.text('Stagione 4 · 8 episodi'));
    await tester.tap(find.text('Tutte'));

    expect(taps, isEmpty);
  });

  testWidgets('una sola stagione da chiedere: niente "Tutte"', (tester) async {
    await pumpPicker(tester,
        selected: const {2}, list: seasons.take(2).toList());

    expect(find.text('Tutte'), findsNothing);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/season_picker_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/features/requests/season_picker.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// L'etichetta dello stato di una stagione (spec I §9.2).
String seasonStatusLabel(AppLocalizations l, TitleStatus status) =>
    switch (status) {
      TitleStatus.none => l.requestsStatusToRequest,
      TitleStatus.pending => l.requestsStatusPending,
      TitleStatus.processing => l.requestsBadgeComing,
      TitleStatus.partial => l.requestsBadgePartial,
      TitleStatus.available => l.requestsStatusAvailable,
    };

/// Le stagioni con le caselle (spec I §9.2): "Tutte" in cima se ce n'è più
/// di una da chiedere; quelle già presenti o già chieste sono segnate e
/// bloccate, con il loro stato a destra.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
    this.enabled = true,
  });

  final List<SeasonInfo> seasons;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final VoidCallback onToggleAll;

  /// Spento durante l'invio, o se l'utente non può chiedere.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final requestable = [
      for (final season in seasons)
        if (season.status.isRequestable) season.seasonNumber,
    ];
    final chosen = requestable.where(selected.contains).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (requestable.length > 1)
          _SeasonRow(
            key: const ValueKey('season-all'),
            value: chosen == 0
                ? false
                : chosen == requestable.length
                    ? true
                    : null,
            label: l.requestsAllSeasons,
            onTap: enabled ? onToggleAll : null,
          ),
        for (final season in seasons)
          _SeasonRow(
            key: ValueKey('season-${season.seasonNumber}'),
            value: season.status.isRequestable
                ? selected.contains(season.seasonNumber)
                : true,
            label: l.requestsSeasonLine(season.seasonNumber, season.episodeCount),
            status: seasonStatusLabel(l, season.status),
            onTap: enabled && season.status.isRequestable
                ? () => onToggle(season.seasonNumber)
                : null,
          ),
      ],
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({
    super.key,
    required this.value,
    required this.label,
    required this.onTap,
    this.status,
  });

  /// `null`: in parte (solo "Tutte").
  final bool? value;
  final String label;
  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final status = this.status;
    return InkWell(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WfColors.border)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              tristate: value == null,
              onChanged: tap == null ? null : (_) => tap(),
              activeColor: WfColors.gold,
              checkColor: WfColors.bg,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: tap == null ? WfColors.creamMuted : WfColors.cream)),
            ),
            if (status != null)
              Text(status,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde.

- [ ] **Step 5: commit**

```bash
git add lib/features/requests test/features/requests
git commit -m "feat(app): pick the seasons to request"
```

### Task 20: la scheda da richiedere e la rotta

**Files:**
- Create: `lib/features/requests/tmdb_title_screen.dart`
- Modify: `lib/app/router.dart`
- Test: `test/features/requests/tmdb_title_screen_test.dart`

- [ ] **Step 1: test che falliscono**

`test/features/requests/tmdb_title_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/tmdb_title_screen.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;

  setUp(() => api = FakeRequestsApi());

  Future<void> pumpScreen(WidgetTester tester,
      {RequestMediaType type = RequestMediaType.movie, int tmdbId = 693134}) async {
    await pumpApp(
      tester,
      Scaffold(body: TmdbTitleScreen(type: type, tmdbId: tmdbId)),
      overrides: requestsTestOverrides(api),
    );
    await tester.pump();
    await tester.pump();
  }

  test('scheda da una rotta', () {
    expect(TmdbTitleScreen.fromRoute('movie', '693134')!.tmdbId, 693134);
    expect(TmdbTitleScreen.fromRoute('tv', '90228')!.type, RequestMediaType.tv);
    expect(TmdbTitleScreen.fromRoute('person', '1'), isNull);
    expect(TmdbTitleScreen.fromRoute('movie', 'abc'), isNull);
    expect(TmdbTitleScreen.fromRoute('movie', '0'), isNull);
  });

  testWidgets('film: dati, trailer e Richiedi con l\'avviso', (tester) async {
    api.titles[693134] =
        testDetails(trailerUrl: 'https://www.youtube.com/watch?v=x');
    await pumpScreen(tester);

    expect(find.text('DUNE - PARTE DUE'), findsOneWidget);
    expect(find.text('2024 · Film · 2h 46m'), findsOneWidget);
    expect(find.text('Fantascienza · Avventura'), findsOneWidget);
    expect(find.text('Paul Atreides si unisce ai Fremen.'), findsOneWidget);
    expect(find.text('Trailer'), findsOneWidget);
    expect(find.text('Guarda'), findsNothing);

    await tester.tap(find.text('Richiedi'));
    await tester.pump();
    await tester.pump();

    expect(api.created.single.type, RequestMediaType.movie);
    expect(find.text('Richiesta inviata'), findsOneWidget);
  });

  testWidgets('serie: stagioni e Richiedi con le stagioni scelte', (tester) async {
    api.titles[90228] = testDetails(
      tmdbId: 90228,
      title: 'Dune: Prophecy',
      type: RequestMediaType.tv,
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 6),
        SeasonInfo(seasonNumber: 2, episodeCount: 8),
      ],
    );
    await pumpScreen(tester, type: RequestMediaType.tv, tmdbId: 90228);

    expect(find.text('2024 · Serie · 2 stagioni'), findsOneWidget);
    expect(find.text('Stagioni'), findsOneWidget);
    expect(find.text('Richiedi'), findsOneWidget);

    await tester.tap(find.text('Stagione 2 · 8 episodi'));
    await tester.pump();
    expect(find.text('Richiedi 1 stagione'), findsOneWidget);

    await tester.tap(find.text('Richiedi 1 stagione'));
    await tester.pump();
    await tester.pump();

    expect(api.created.single.seasons, [1]);
  });

  testWidgets('già chiesto da te: l\'etichetta al posto di Richiedi', (tester) async {
    api.titles[693134] = testDetails(
        status: TitleStatus.pending, requestedByMe: true, requested: true);
    await pumpScreen(tester);

    expect(find.text('Richiesto da te'), findsOneWidget);
    expect(find.text('Richiedi'), findsNothing);
  });

  testWidgets('in parte nella libreria: Richiedi e Guarda', (tester) async {
    api.titles[90228] = testDetails(
      tmdbId: 90228,
      type: RequestMediaType.tv,
      status: TitleStatus.partial,
      jellyfinItemId: 'abc',
      seasons: const [
        SeasonInfo(seasonNumber: 1, episodeCount: 6, status: TitleStatus.available),
        SeasonInfo(seasonNumber: 2, episodeCount: 8),
      ],
    );
    await pumpScreen(tester, type: RequestMediaType.tv, tmdbId: 90228);

    expect(find.text('Richiedi'), findsOneWidget);
    expect(find.text('Guarda'), findsOneWidget);
    expect(find.text('Tutte'), findsNothing);
  });

  testWidgets('chi non può chiedere vede solo i dati', (tester) async {
    api
      ..meValue = const RequestsMe(canRequest: false, canManage: false, hasAccount: true)
      ..titles[693134] = testDetails();
    await pumpScreen(tester);

    expect(find.text('Richiedi'), findsNothing);
    expect(api.calls, contains('me'));
  });

  testWidgets('Seerr giù: errore e Riprova', (tester) async {
    api.failure = RequestsFailure.seerrUnavailable;
    await pumpScreen(tester);

    expect(find.text('Seerr non risponde'), findsOneWidget);

    api
      ..failure = null
      ..titles[693134] = testDetails();
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('DUNE - PARTE DUE'), findsOneWidget);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/requests/tmdb_title_screen_test.dart`
Expected: FAIL di compilazione.

- [ ] **Step 3: implementazione**

`lib/features/requests/tmdb_title_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/skeletons.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_switcher.dart';
import '../detail/detail_header.dart';
import '../library/item_labels.dart';
import 'request_title_controller.dart';
import 'requests_providers.dart';
import 'season_picker.dart';

/// L'etichetta al posto di Richiedi (spec I §9.2); `null` se non serve.
String? titleStatusLabel(AppLocalizations l, TitleDetails details) =>
    switch (details.status) {
      TitleStatus.pending => details.requestedByMe
          ? l.requestsRequestedByYou
          : l.requestsBadgeRequested,
      TitleStatus.processing => l.requestsBadgeComing,
      TitleStatus.partial => l.requestsPartlyAvailable,
      TitleStatus.none => details.requested
          ? (details.requestedByMe
              ? l.requestsRequestedByYou
              : l.requestsBadgeRequested)
          : null,
      TitleStatus.available => null,
    };

/// La scheda di un titolo che non è (tutto) nella libreria (spec I §9.2):
/// dati di Seerr, Richiedi e, per le serie, le stagioni.
class TmdbTitleScreen extends ConsumerWidget {
  const TmdbTitleScreen({super.key, required this.type, required this.tmdbId});

  /// La scheda di una rotta `/tmdb/:type/:tmdbId`; `null` se tipo o id non
  /// valgono.
  static TmdbTitleScreen? fromRoute(String? type, String? tmdbId, {Key? key}) {
    final mediaType = RequestMediaType.tryParse(type);
    final id = int.tryParse(tmdbId ?? '');
    if (mediaType == null || id == null || id <= 0) return null;
    return TmdbTitleScreen(key: key, type: mediaType, tmdbId: id);
  }

  final RequestMediaType type;
  final int tmdbId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleKey = (
      type: type,
      tmdbId: tmdbId,
      language: Localizations.localeOf(context).languageCode,
    );
    final provider = requestTitleControllerProvider(titleKey);
    final state = ref.watch(provider);
    final error = state.error;
    final (name, content) = switch (state.details) {
      TitleDetails() => ('data', _TmdbTitleView(titleKey: titleKey)),
      null when error != null => (
          'error',
          ErrorView(
              error: error,
              onRetry: () => unawaited(ref.read(provider.notifier).load())),
        ),
      null => (
          'loading',
          const DetailSkeleton(headerHeight: detailHeaderHeight),
        ),
    };
    return WfSwitcher(
      expand: true,
      child: KeyedSubtree(key: ValueKey(name), child: content),
    );
  }
}

class _TmdbTitleView extends ConsumerWidget {
  const _TmdbTitleView({required this.titleKey});

  final RequestTitleKey titleKey;

  /// Larghezza massima dell'elenco delle stagioni.
  static const _seasonsMaxWidth = 560.0;

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(requestTitleControllerProvider(titleKey).notifier)
        .submit();
    if (outcome == null) return;
    messenger.showSnackBar(
        SnackBar(content: Text(requestOutcomeText(l, outcome))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final provider = requestTitleControllerProvider(titleKey);
    final state = ref.watch(provider);
    final details = state.details!;
    final controller = ref.read(provider.notifier);
    final canRequest = ref.watch(requestsMeProvider).value?.canRequest ?? false;
    final showSeasons =
        details.mediaType == RequestMediaType.tv && details.seasons.isNotEmpty;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          child: BackdropImage(
            backdrop: TmdbImages.backdrop(details.backdropPath),
            fallback: TmdbImages.poster(details.posterPath),
          ),
        ),
        Positioned.fill(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              TmdbTitleHeader(
                details: details,
                state: state,
                canRequest: canRequest,
                onRequest: () => unawaited(_request(context, ref)),
              ),
              if (showSeasons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.requestsSeasons, style: WfText.display(26)),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _seasonsMaxWidth),
                        child: SeasonPicker(
                          seasons: details.seasons,
                          selected: canRequest ? state.selected : const {},
                          enabled: canRequest && !state.sending,
                          onToggle: controller.toggleSeason,
                          onToggleAll: controller.toggleAll,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La testata della scheda da richiedere: come la testata delle schede
/// della libreria (`DetailHeader`), con i dati di Seerr.
class TmdbTitleHeader extends StatelessWidget {
  const TmdbTitleHeader({
    super.key,
    required this.details,
    required this.state,
    required this.canRequest,
    required this.onRequest,
  });

  final TitleDetails details;
  final RequestTitleState state;
  final bool canRequest;
  final VoidCallback onRequest;

  /// Larghezza massima della trama, come nelle schede della libreria.
  static const _overviewMaxWidth = 680.0;

  static Uri? _trailerUri(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted);
    final isSeries = details.mediaType == RequestMediaType.tv;
    final year = details.year;
    final runtime = details.runtimeMinutes;
    final overview = details.overview;
    final meta = [
      if (year != null) '$year',
      isSeries ? l.requestsKindSeries : l.requestsKindMovie,
      if (!isSeries && runtime != null && runtime > 0)
        formatRuntime(Duration(minutes: runtime)),
      if (isSeries && details.seasons.isNotEmpty)
        l.detailSeasons(details.seasons.length),
    ].join(' · ');
    final itemId = details.jellyfinItemId;
    final watchable = details.status == TitleStatus.available ||
        details.status == TitleStatus.partial;
    final trailer = _trailerUri(details.trailerUrl);
    final showRequest = canRequest && details.canBeRequested;
    final status = showRequest ? null : titleStatusLabel(l, details);
    final chosen = state.selected.length;
    final allChosen = chosen == details.requestableSeasons.length;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(details.title.toUpperCase(),
                    maxLines: 2, style: WfText.display(56)),
                const SizedBox(height: 12),
                Text(meta, style: muted),
                if (details.genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(details.genres.join(' · '), style: muted),
                ],
                if (overview != null && overview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _overviewMaxWidth),
                    child: Text(overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45)),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showRequest)
                      WfButton.primary(
                        label: isSeries && !allChosen
                            ? l.requestsRequestSeasons(chosen)
                            : l.requestsRequest,
                        icon: LucideIcons.plus,
                        onPressed: state.sending || (isSeries && chosen == 0)
                            ? null
                            : onRequest,
                      ),
                    if (status != null) RequestStatusChip(label: status),
                    if (itemId != null && watchable)
                      WfButton.secondary(
                        label: l.requestsWatch,
                        icon: LucideIcons.play,
                        onPressed: () => openItemById(context, itemId),
                      ),
                    if (trailer != null)
                      WfButton.secondary(
                        label: l.actionTrailer,
                        icon: LucideIcons.clapperboard,
                        onPressed: () => unawaited(launchUrl(trailer,
                            mode: LaunchMode.externalApplication)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo stato di un titolo già chiesto o arrivato, al posto di Richiedi.
class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WfColors.gold),
      ),
      child: Text(label,
          style: const TextStyle(
              color: WfColors.gold, fontWeight: FontWeight.w600)),
    );
  }
}
```

In `lib/app/router.dart`:
- import `../features/requests/tmdb_title_screen.dart`;
- nella `ShellRoute`, dopo la rotta `/person/:id`:

```dart
          GoRoute(
            path: '/tmdb/:type/:tmdbId',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              // Tipo o id non validi: pagina vuota (si torna indietro).
              TmdbTitleScreen.fromRoute(
                    state.pathParameters['type'],
                    state.pathParameters['tmdbId'],
                    key: ValueKey(state.uri.toString()),
                  ) ??
                  const SizedBox.shrink(),
              underBar: false,
            ),
          ),
```

- [ ] **Step 4: verifica**

Run: `flutter analyze` e `flutter test`
Expected: nessun problema, tutto verde. Se il testo della durata non è "2h 46m", controlla `formatRuntime` e allinea il test al formato dell'app (166 minuti).

- [ ] **Step 5: commit**

```bash
git add lib test
git commit -m "feat(app): open titles to request in their own page"
```

## Gruppo G — allineamento e verifica finale

### Task 21: spec allineata, verifica, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md`

- [ ] **Step 1: allinea la spec**

In `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md`:
- **Stato:** `in revisione` → `approvato; piano 15a realizzato (docs/superpowers/plans/2026-10-05-wonderflix-15a-richieste-seerr.md)`.
- **§7.1:**
  - il modello JSON usa la chiave speciale `"{{extra}}": []` (decisione 3 del piano);
  - la riga "Ultimo evento ricevuto" viene da `GET Requests/Admin` (decisione 2).
- **§7.3:**
  - nella tabella aggiungi `GET Admin` (solo admin: configurato e ultimo evento del webhook);
  - nell'ordine dello stato di una richiesta, dopo "in attesa", aggiungi "richiesta completata → `Available`" (decisione 1).
- **§8.2:** `requestsMeProvider` è `autoDispose` e si rilegge quando una pagina lo usa di nuovo (decisione 4).
- **§8.1:** `ForbiddenException` e `ServerErrorException` portano `body` (decisione 5).

```bash
git add docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md
git commit -m "docs: align spec I with plan 15a"
```

- [ ] **Step 2: verifica finale**

Run:
- `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`
- `flutter analyze`
- `flutter test`

Expected: tutto verde, nessun warning né problema. Annota i numeri dei test per il riepilogo.

- [ ] **Step 3: build per la prova manuale**

Copia `config/wonderflix.json` dalla root del repository principale nella stessa cartella del worktree (non si committa), poi:

Run: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
Expected: `build/windows/x64/runner/Release/wonderflix.exe`. Senza `--dart-define-from-file` l'exe mostra "Configurazione mancante".

## Prova manuale (con l'utente, dopo la review finale)

Con il plugin 1.4.0 installato e collegato (Task 10) e l'app del worktree:

1. **Ricerca:** cerca "dune".
   - Sotto i risultati della libreria compare "Da richiedere".
   - Dune (2021), che è in libreria, non si ripete.
   - Le etichette sono giuste (Film/Serie, Richiesto, In arrivo).
2. **Film non presente:** clic su un film che non c'è → si apre la scheda con sfondo, dati e trailer.
   - **Richiedi** → "Richiesta inviata" (con un account normale) o "Richiesta approvata" (con l'admin).
   - Lo stato si aggiorna; in Seerr la richiesta c'è.
3. **Serie:**
   - Una serie che non c'è: stagioni con le caselle, "Tutte", "Richiedi 1 stagione" dopo aver tolto le altre.
   - Una serie in parte in libreria (es. Brothers): "Guarda" e le stagioni presenti bloccate.
4. **Già chiesto:** un titolo già chiesto mostra "Richiesto" o "Richiesto da te" e niente Richiedi.
5. **Account nuovo:** con un utente Jellyfin senza account Seerr (es. un utente di prova), la prima richiesta crea l'account in Seerr.
6. **Seerr spento:** con l'indirizzo sbagliato nel plugin, la ricerca mostra "Seerr non risponde" e la libreria funziona; poi ripristina l'indirizzo.
7. **Plugin senza Seerr:** svuotando indirizzo e chiave la sezione sparisce (dopo la riconnessione dell'app). Poi rimettili.

Dopo l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria del flusso). La release del plugin dal Catalogo e dell'app è nel piano 15b.
