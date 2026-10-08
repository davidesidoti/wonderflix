# WonderFlix — Piano 17c: immagini del profilo e release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** l'ultima parte della Spec K. Ci sono:
- **plugin 1.5.0:** `GET WonderFlixWatchParty/Users/Avatars` e la funzione `avatars`;
- **la finestra dell'immagine del profilo:** galleria di 24 avatar a tema cinema, immagine dal PC con il ritaglio quadrato, rimozione. Si apre da "Gestisci profili" ("Modifica immagine") e da Impostazioni → Account ("Cambia immagine");
- **`UserAvatar` dovunque** al posto delle iniziali: menu dell'avatar, "Chi guarda?", Impostazioni, amici, inviti, party, chat, richiesta d'amicizia, sessioni dell'admin;
- **la release:** plugin 1.5.0 dal Catalogo, app 0.11.0 non obbligatoria, `docs/IDEE.md`.

**Spec:** `docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md` (§3.2, §4, §5, §6, §7.2, §7.3, §9.4, §9.5, §10, §11, §12, §13, §14, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 10):
1. **Il corpo di `POST /UserImage` è base64: verificato nel sorgente** di Jellyfin 10.11.9 (`ImageController.PostUserImage` legge il corpo con `FromBase64Transform`; `Content-Type` `image/*`, altrimenti 400; risposta 204). Non serve una prova sull'account dell'utente prima del piano (§14): la prova vera è nella prova a mano.
2. **`GET /UserImage?userId=&tag=` non chiede l'accesso e non ridimensiona** (accetta solo `userId`, `tag`, `format`). `UserAvatar` decodifica alla dimensione mostrata (`WfImage`), e funziona anche in "Chi guarda?", senza sessione.
3. **Il plugin elenca gli utenti una volta per richiesta e confronta in memoria** (id, e nomi senza maiuscole): con Jellyfin 10.11.9 ogni `GetUserById`/`GetUserByName` è una query al database, e `GetUserByName` lancia con un nome vuoto (che diventerebbe un 400). Gli id che non sono GUID si ignorano.
4. **Chi cercare:** `AvatarLookup.byId` (amici, inviti, chat, richiesta d'amicizia) o `AvatarLookup.byName` (i membri del party: SyncPlay dà solo i nomi). La risposta dà sempre l'id dell'utente, che serve per l'indirizzo dell'immagine.
5. **`UserAvatar` ha due costruttori:**
   - `UserAvatar(...)` con il tag già noto (l'utente aperto, i profili, le sessioni dell'admin): `null` vuol dire senza immagine;
   - `UserAvatar.lookup(...)`: il tag lo cerca `avatarImageProvider`.
6. **Sessioni dell'admin:** il tag viene da Jellyfin (`UserPrimaryImageTag` di `SessionInfoDto`), non dal plugin: c'è anche senza plugin.
7. **La cache degli avatar** (`AvatarDirectory`) c'è solo con un profilo aperto e con la funzione `avatars`; è nuova a ogni profilo. Senza, `UserAvatar.lookup` mostra l'iniziale e non chiama niente (anche nei widget test senza sessione).
8. **Stile `muted`:** il party, gli amici, la chat e la richiesta d'amicizia tengono l'iniziale di oggi (oro su grigio); il resto ha l'iniziale scura su oro.
9. **Galleria:** al posto del gufo c'è l'uccello (`LucideIcons.bird`): `lucide_icons_flutter` 3.1.20 non ha `owl`.
10. **Immagine dal PC:** in un isolate, il file si decodifica con il pacchetto `image`, si gira secondo l'EXIF e si riduce a 2048 px di lato al massimo (l'immagine "di lavoro", in PNG); il ritaglio lavora su quella. Di una GIF animata vale il primo fotogramma. Il JPEG finale non ha trasparenza: le parti trasparenti diventano nere.
11. **Il flusso dell'immagine** sta in `SessionController.setProfileImage(userId, {image})`: carica o toglie con le credenziali di quel profilo (`AuthService.clientFor`), rilegge `/Users/Me`, aggiorna il profilo (e la sessione, se è quello aperto) e restituisce l'utente riletto. La finestra aggiorna poi la cache degli avatar.
12. **Profilo scaduto:** in "Gestisci profili" la matita è spenta. Un 401 durante il caricamento segna scaduto un profilo non aperto, e la finestra si chiude.
13. **Il file e il lavoro sulle immagini stanno dietro provider** (`avatarFilePickerProvider`, `avatarImageToolsProvider`), da sostituire nei widget test: `file_selector` apre una finestra di sistema, e gli isolate e `toImage` nei widget test richiedono `runAsync`.
14. **Pacchetti nuovi:** `file_selector` e `image`. Con `file_selector` cambiano davvero `windows/flutter/generated_plugin_registrant.cc` e `generated_plugins.cmake`: in quel commit si committano.
15. **Dalle review dei gruppi** (il codice dei task sotto è quello di partenza: dove differisce, vale questa lista, e la spec è già allineata):
    - **Plugin:**
      - senza voci valide (solo voci vuote o id che non sono GUID, compreso il GUID vuoto) il controller risponde `{"Users":[]}` senza chiamare l'adattatore, quindi senza leggere gli utenti. Test in più: un GUID con i trattini vale, e i nomi con lettere non ASCII si confrontano senza maiuscole;
      - una ricerca per nome conferma che un account esiste, anche nascosto: rischio basso, accettato (`/Users/Public` elenca già gli utenti non nascosti, e la ricerca degli amici trova i nomi per sottostringa).
    - **Cache degli avatar** (`AvatarDirectory`):
      - le richieste già partite si condividono (`_inFlight`), e `dispose` chiude anche quelle;
      - un'immagine di `remember` (dopo un caricamento) vince su una chiamata già partita (`_Cached.remembered`); un errore o un "senza immagine" non copre mai un'immagine trovata da un'altra chiamata;
      - `avatarImageProvider` si rilegge da solo dopo `ttl`, con il timer che parte dalla risposta: dopo un errore si riprova così;
      - `AvatarLookup.query`: il nome va al plugin come è scritto, e solo la chiave è in minuscolo (Dart e .NET non sono d'accordo su qualche lettera);
      - un id vuoto o un nome vuoto non fanno chiamate; un utente senza nome non vale per il nome vuoto (né in `remember`).
    - **`UserAvatar`:**
      - decorativo per lo screen reader (`ExcludeSemantics`);
      - con un id vuoto cerca per nome; l'id di un tag noto si normalizza con `jellyfinIdKey`;
      - non va misurato con il layout "a secco" (`WfImage` usa un `LayoutBuilder`). `PartyChatMessage` diventa uno `StatefulWidget` che tiene lo stesso avatar nel `WidgetSpan` finché il mittente non cambia.
    - **Immagine dal PC** (`avatar_image.dart`):
      - l'intestazione si legge prima di decodificare. Un JPEG con un parser suo (`readJpegSize`), che accetta solo i marcatori che il decoder legge allo stesso modo (DQT, DHT, DRI, APPn, COM, RST/TEM, byte di riempimento): ogni altra cosa è "Immagine non valida". Gli altri formati con `startDecode`;
      - oltre 64 milioni di pixel (`maxSourcePixels`): "Immagine troppo grande". Qualche foto da 108 o 200 megapixel si rifiuta; la maggior parte dei telefoni ne salva da 12;
      - si decodifica solo il primo fotogramma (`decodeFrame(0)`), non tutta l'animazione;
      - l'orientamento dell'EXIF si applica dopo la riduzione a 2048 px (con la media dei pixel); tavolozza e 16 bit diventano 8 bit;
      - **la decisione 10 cambia:** le parti trasparenti prendono il grigio scuro dell'app (`transparentFill`, `0xFF1B1B1B` come `WfColors.surfaceHigh`), non il nero, già nell'immagine di lavoro: l'anteprima è uguale all'immagine caricata;
      - l'EXIF non arriva mai al server, GPS compreso (provato da un test);
      - nel ritaglio, un riquadro che esce dall'immagine si sposta dentro invece di stringersi; ingrandendo un ritaglio piccolo, la bicubica invece della lineare.
    - **Ritaglio** (`avatar_cropper.dart`): la rotella ignora gli scorrimenti solo orizzontali; il cursore ha l'etichetta "Ingrandimento" con il valore ("2,0×").
    - **Finestra** (`avatar_dialog.dart`):
      - la scheda "Dal PC" resta viva (cambiando scheda il ritaglio resta), e le schede non cambiano trascinando;
      - durante il caricamento la finestra non si chiude (`PopScope`); mentre si prepara un'immagine dal PC, Esc la chiude;
      - si chiude solo se è ancora in cima; la cache degli avatar si aggiorna anche se la finestra sparisce durante il caricamento;
      - il messaggio d'errore sparisce cambiando scheda; la barra di avanzamento ha uno spazio fisso sotto le linguette;
      - la galleria ha caselle fisse con gli avatar da 56 px, e 4 righe stanno nella finestra più piccola anche con un errore;
      - gli avatar della galleria sono pulsanti per lo screen reader, con il testo nuovo `profileImageGalleryItem` ("Avatar {number}");
      - come dice la decisione 12, un 401 chiude la finestra: cambia la frase della spec (§10.4) "in tutti i casi la finestra resta aperta".
    - **Sessione:** `AuthService.isActive`. `setProfileImage` ignora una rilettura che dà un altro utente, aggiorna sempre il profilo salvato (`updateStoredProfile`) e la sessione solo se è aperta con quell'utente.
    - **Limiti noti** (spec §12): un'immagine non quadrata caricata da jellyfin-web può sembrare sfocata, e una trasparente lascia vedere l'iniziale; niente zoom con due dita sul touchpad; Invio su un avatar della galleria non carica; un `refreshUser` durante un caricamento può rimettere per un momento il tag vecchio; un caricamento riuscito con la rilettura fallita dice "Caricamento non riuscito".
    - **Da verificare:** che `GetImageCacheTag(User)` dia lo stesso `PrimaryImageTag` di `/Users`, con la build di prova del Task 2 (non ancora installata: sul server c'era qualcuno che guardava).

**Architecture:**
- **Plugin:** `Hub/IUserAvatars`, `Server/JellyfinUserAvatars`, `Protocol/AvatarDtos`, `Api/AvatarsController`, funzione `avatars`.
- **App, dati:**
  - `ImageUrls.user`;
  - `UserImageApi` (POST in base64 e DELETE);
  - `AvatarsApi`;
  - `JellyfinHttp.post(contentType:)`;
  - `SocialFeatures.avatars`;
  - `SessionEntry.userImageTag`;
  - `AvatarDirectory`, `avatarDirectoryProvider` e `avatarImageProvider` (`lib/features/social/avatars_provider.dart`);
  - `UserAvatar` (`lib/ui/user_avatar.dart`).
- **App, immagine del profilo** (`lib/features/profiles/`):
  - `avatar_gallery.dart`: le icone e il disegno in PNG;
  - `avatar_image.dart`: preparazione e ritaglio, in isolate;
  - `avatar_cropper.dart`: il ritaglio, widget e conti;
  - `avatar_dialog.dart`: la finestra;
  - `AuthService.clientFor`, `updateStoredProfile`, `markProfileExpired`, e `SessionController.setProfileImage`.
- **App, avatar ovunque:** `MemberAvatar` diventa un uso di `UserAvatar.lookup`. Ci sono anche il menu dell'avatar, "Chi guarda?", Impostazioni, la riga degli amici, la chat, la richiesta d'amicizia e `AdminUserLine`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, lucide_icons_flutter 3.1.20, `file_selector`, `image` 4, fake_async, mocktail; plugin .NET 9, Jellyfin 10.11.0 (riferimento) e 10.11.9 (test), xUnit.

**Worktree:** `.claude/worktrees/piano-17c`, branch `feat/piano-17c`. **Base:** `main` con questo piano. **Test a inizio piano:** 2343 Flutter e 390 plugin (fine del piano 17b, `3a33643`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-17c`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`. Un messaggio su più righe va in un file e si usa `git commit -F <file>`.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.5.0`.
- **Prima di ogni commit:**
  - per i task dell'app: `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera);
  - per i task del plugin: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` tutto verde (il csproj ha `TreatWarningsAsErrors`), poi `dotnet build-server shutdown`.
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit. **Eccezione:** nel Task 7 `flutter pub add file_selector` li cambia davvero (un plugin nuovo): quei cambi si committano.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors` (le sfumature della galleria sono costanti nominate in `avatar_gallery.dart`); `clock.now()`, mai `DateTime.now()`.
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` o un `LinearProgressIndicator` senza valore non si ferma mai, quindi `pumpAndSettle` va in timeout. Mentre c'è un indicatore, usa `pump()` o `pump(durata)`.
- **Provider:** nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`. I container dei test hanno `retry: (_, _) => null`.
- **`dart:ui` nei test:** `Picture.toImage`, `Image.toByteData` e `Isolate.run` vanno chiamati dentro `tester.runAsync(...)` in un `testWidgets`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, per esempio nel pacchetto `image`):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-08 sul codice di `main` (`3a33643`), sui pacchetti NuGet di Jellyfin 10.11.0 e 10.11.9 (riflessione) e sul sorgente di Jellyfin `v10.11.9`, in sola lettura.

**Plugin**
- Il modello è il `CollectionsController` del 17a:
  - `[ApiController]`, `[Route("WonderFlixWatchParty")]`, `[Authorize]` senza policy, `[Produces(MediaTypeNames.Application.Json)]`;
  - i DTO sono `record` con `[property: JsonPropertyName("…")]`;
  - gli id sono `Guid.ToString("N")`.
- Un 400 è un semplice `BadRequest()`. Il middleware di Jellyfin trasforma un `ArgumentException` in 400 e ogni eccezione sconosciuta in 500: mai 404.
- **Utenti:**
  - la lista si legge con `UserListing.For(typeof(IUserManager))` (`Server/UserListing.cs`): in 10.11.0 è la proprietà `Users`, in 10.11.9 il metodo `GetUsers()`. Nei test lo stub è `Handlers["GetUsers"]`;
  - un utente è disattivato se `user.HasPermission(PermissionKind.IsDisabled)` (`Jellyfin.Data`, `Jellyfin.Database.Implementations.Enums`);
  - il nome è `user.Username`.
- **Il tag dell'immagine dell'utente:** `IImageProcessor.GetImageCacheTag(User user)` → `string?` (uguale in 10.11.0 e 10.11.9; `null` senza `user.ProfileImage`). È lo stesso che Jellyfin mette in `UserDto.PrimaryImageTag`.
  - Nei test: `new User("Mario", "provider", "reset") { ProfileImage = new ImageInfo("mario.png") }` (`Jellyfin.Database.Implementations.Entities`).
  - Lo stub `GetImageCacheTag` riceve l'utente in `args[0]`.
- **JSON sul server vero:** Jellyfin non scrive i valori nulli (`WhenWritingNull`), quindi un `ImageTag` nullo **manca**. `ProtocolJsonTests` usa invece `JsonSerializer.Serialize`, che scrive `null`.
- `ServiceRegistrationTests` registra già gli stub di `IUserManager` e `IImageProcessor`. `InfoControllerTests` controlla la versione `"1.5.0"` e le funzioni.

**Jellyfin** (sorgente `v10.11.9`, `Jellyfin.Api/Controllers/ImageController.cs`)
- **`POST /UserImage?userId=`:**
  - accesso richiesto (`[Authorize]`); risposta 204;
  - corpo **base64** dell'immagine; `Content-Type` `image/jpeg` o `image/png` (altrimenti 400 "Incorrect ContentType.");
  - 403 se l'utente non ha `EnableUserPreferenceAccess` (tutti i 23 utenti ce l'hanno);
  - il tag cambia a ogni caricamento.
- **`DELETE /UserImage?userId=`:** 204, anche senza immagine.
- **`GET /UserImage?userId=&tag=`:** anonimo; nessun ridimensionamento; con il tag la cache dura un anno.

**App**
- **Le iniziali di oggi:**
  - `MemberAvatar(name)` (`lib/features/watch_party/party_badge.dart` ~61): cerchio di 26 px (`radius: 13`), `surfaceHigh`, iniziale `gold` 12 px.
    - Lo usano la pila e il menu del badge del party (solo nomi), il menu degli inviti (`FriendEntry`: id e nome) e la riga degli amici `_PersonRow` (`lib/features/friends/friends_panel.dart` ~554: ha solo `name`; i chiamanti hanno l'id).
  - `AdminUserLine(name, detail)` (`lib/features/admin/admin_widgets.dart` ~34): cerchio di 28 px dorato. La usano `sessions_tab.dart` ~150 e ~223, con `SessionEntry` (`userId`, `userName`).
  - `_UserMenu` (`lib/app/app_shell.dart` ~347): `CircleAvatar` di 30 px dorato; ha `JellyfinUser user` (id, nome, `primaryImageTag`).
  - `_InitialAvatar` (`lib/features/profiles/profiles_screen.dart` ~311): 120 px dorato; il profilo ha `imageTag`.
- **Dove oggi non c'è un avatar:**
  - Impostazioni → Account (`settings_screen.dart` ~117);
  - la chat (`PartyChatMessage` in `lib/features/watch_party/party_chat_bubble.dart` ~23: `Text.rich` con il nome dorato e il testo; `entry.event` ha `userId` e `userName`);
  - la richiesta d'amicizia (`lib/features/friends/friend_request_card.dart`: icona `userPlus` di 18 px, pulsanti rientrati di 26 px; `request.fromUserId`, `request.fromName`).
- **Immagini:**
  - `ImageUrls` (`lib/core/jellyfin/image_urls.dart`) costruisce gli indirizzi senza token; `imageUrlsProvider` è in `lib/features/library/library_providers.dart`;
  - `WfImage(image:, fit:, fallbackIcon:)` decodifica alla larghezza mostrata (`memCacheWidth`), con la cache `wonderflixImages`;
  - `imageBuilderProvider` si sostituisce nei widget test (`pumpApp` lo fa già);
  - sotto `TransparentPlaceholders` il segnaposto è trasparente.
- **`JellyfinHttp.post`** non ha un `Content-Type`: con un corpo `String` dio manda `application/json` (`ImplyContentTypeInterceptor`).
- **Plugin dal lato dell'app:**
  - `CollectionsApi` (`lib/core/social/collections_api.dart`) è il modello per `AvatarsApi`;
  - `PluginFeatures` è in `social_models.dart`;
  - `SocialFeatures` ha `friends`, `parties`, `inbox`, `requests`, `collections`, `known`, con `==`, `hashCode`, `toString`;
  - `SocialAvailability.refresh` legge `info.features` (~162);
  - senza utente `SocialAvailability` dà `none`, e per costruirsi crea la sessione (`jellyfinHttpProvider` → `clientInfoProvider`, che nei widget test senza override lancia).
- **Sessione e profili:**
  - `profilesProvider` (`lib/features/auth/profiles_state.dart`) non dipende da niente: `activeUserId` c'è solo con un profilo aperto;
  - `AuthService` ha `withCredentials` (in `_revoke`), `updateActiveProfile(JellyfinUser)` (solo il profilo aperto), `_save` (chiama `onProfilesChanged`) e `_book`;
  - `SessionController._publishProfiles()` aggiorna `profilesProvider`;
  - `JellyfinUser ==` confronta anche `primaryImageTag`.
- **Test:**
  - `FakeAdapter` (`test/support/fake_adapter.dart`) registra le `RequestOptions` (`method`, `path`, `queryParameters`, `data`, `contentType`); il gestore può essere asincrono;
  - `FakeSocialAvailability(features)` è in `test/support/social_fakes.dart`;
  - `FixedProfiles`, `testProfile` e `MemoryProfileStore` sono in `test/support/profile_fakes.dart`;
  - `FakeSessionController` è in `test/support/fake_session_controller.dart`;
  - `testUser` è `JellyfinUser(id: 'u1', name: 'Mario')`;
  - `pumpApp` usa il server `https://media.example.com`.
- **Pacchetti:**
  - `image` 4.10.1 c'è già nel lock, ma solo come dipendenza di `media_kit`: va aggiunto alle dipendenze;
  - `file_selector` non c'è;
  - nessun uso di `compute`/`Isolate.run` o di `PictureRecorder` in `lib/`.
- **Icone Lucide 3.1.20:** `popcorn`, `clapperboard`, `film`, `ticket`, `tv`, `projector`, `video`, `star`, `rocket`, `ghost`, `cat`, `dog`, `rabbit`, `bird`, `fish`, `skull`, `crown`, `heart`, `music`, `gamepad2`, `pizza`, `coffee`, `sparkles`, `moon`; e `imagePlus`, `pencil`, `trash2`, `check`.

---

## Gruppo A — plugin

### Task 1: `GET WonderFlixWatchParty/Users/Avatars`

**Files:**
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/AvatarDtos.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Hub/IUserAvatars.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Server/JellyfinUserAvatars.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Api/AvatarsController.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/PluginServiceRegistrator.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/AvatarsControllerTests.cs`
- Create: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/UserAvatarsTests.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ProtocolJsonTests.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/InfoControllerTests.cs`
- Modify: `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/ServiceRegistrationTests.cs`

- [ ] **Step 1: i test**

Crea `AvatarsControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AvatarsControllerTests
{
    private readonly FakeAvatars _avatars = new();

    private AvatarsController Controller() => new(_avatars)
    {
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
    };

    [Fact]
    public void AsksForIdsAndNamesAndAnswersWithJellyfinIds()
    {
        var mario = Guid.NewGuid();
        _avatars.Result = [new UserAvatarInfo(mario, "Mario", "tag-m"), new UserAvatarInfo(Guid.NewGuid(), "Luigi", null)];

        var users = Controller().GetAvatars($"{mario:N}, non-un-id,", "luigi, ").Value!.Users;

        var (ids, names) = Assert.Single(_avatars.Calls);
        // Gli id che non sono GUID e le voci vuote si saltano.
        Assert.Equal(new[] { mario }, ids);
        Assert.Equal(new[] { "luigi" }, names);
        Assert.Equal(mario.ToString("N"), users[0].UserId);
        Assert.Equal("Mario", users[0].Name);
        Assert.Equal("tag-m", users[0].ImageTag);
        Assert.Null(users[1].ImageTag);
    }

    [Fact]
    public void WithoutIdsOrNamesTheListIsEmpty()
    {
        Assert.Empty(Controller().GetAvatars(null, null).Value!.Users);
        Assert.Empty(Controller().GetAvatars(" ", ",").Value!.Users);
    }

    [Fact]
    public void MoreThanAHundredEntriesIsABadRequest()
    {
        var ids = string.Join(',', Enumerable.Range(0, 60).Select(_ => Guid.NewGuid().ToString("N")));
        static string Names(int count) => string.Join(',', Enumerable.Range(0, count).Select(i => $"utente{i}"));

        Assert.IsType<BadRequestResult>(Controller().GetAvatars(ids, Names(41)).Result);
        Assert.Empty(_avatars.Calls);

        // Esattamente 100 voci vanno bene.
        Assert.NotNull(Controller().GetAvatars(ids, Names(40)).Value);
    }

    [Fact]
    public void EveryAuthenticatedUserCanAsk()
    {
        // Le immagini non dipendono dal watch party: nessuna policy.
        var authorize = Assert.Single(typeof(AvatarsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(AvatarsController).GetMethod(nameof(AvatarsController.GetAvatars))!
            .GetCustomAttributes<AuthorizeAttribute>());
    }

    private sealed class FakeAvatars : IUserAvatars
    {
        public List<(IReadOnlyCollection<Guid> Ids, IReadOnlyCollection<string> Names)> Calls { get; } = [];

        public IReadOnlyList<UserAvatarInfo> Result { get; set; } = [];

        public IReadOnlyList<UserAvatarInfo> Find(IReadOnlyCollection<Guid> ids, IReadOnlyCollection<string> names)
        {
            Calls.Add((ids, names));
            return Result;
        }
    }
}
```

Crea `UserAvatarsTests.cs`:

```csharp
using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class UserAvatarsTests
{
    private readonly User _mario = new("Mario", "provider", "reset") { ProfileImage = new ImageInfo("mario.png") };
    private readonly User _luigi = new("Luigi", "provider", "reset");
    private readonly User _bowser = new("Bowser", "provider", "reset") { ProfileImage = new ImageInfo("bowser.png") };

    private (JellyfinUserAvatars Avatars, InterfaceStub<IUserManager> Users) Create()
    {
        _bowser.SetPermission(PermissionKind.IsDisabled, true);
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUsers"] = _ => new[] { _mario, _luigi, _bowser };
        var (images, imageStub) = InterfaceStub<IImageProcessor>.Create();
        // Come Jellyfin: un tag solo con l'immagine.
        imageStub.Handlers["GetImageCacheTag"] = args =>
            args[0] is User { ProfileImage: not null } user ? "tag-" + user.Username : null;
        return (new JellyfinUserAvatars(users, images), userStub);
    }

    [Fact]
    public void FindsUsersByIdAndByNameIgnoringCase()
    {
        var (avatars, _) = Create();

        var found = avatars.Find([_mario.Id], ["LUIGI"]);

        Assert.Equal(new[] { "Mario", "Luigi" }, found.Select(user => user.Name));
        Assert.Equal(_mario.Id, found[0].Id);
        Assert.Equal("tag-Mario", found[0].ImageTag);
        Assert.Null(found[1].ImageTag);
    }

    [Fact]
    public void TheSameUserOnlyOnce()
    {
        var (avatars, _) = Create();

        var found = Assert.Single(avatars.Find([_mario.Id], ["mario"]));

        Assert.Equal(_mario.Id, found.Id);
    }

    [Fact]
    public void DisabledAndUnknownUsersAreMissing()
    {
        var (avatars, _) = Create();

        Assert.Empty(avatars.Find([_bowser.Id, Guid.NewGuid(), Guid.Empty], ["bowser", "nessuno"]));
    }

    [Fact]
    public void NothingAskedNothingRead()
    {
        var (avatars, users) = Create();

        Assert.Empty(avatars.Find([], []));
        Assert.Empty(users.Calls);
    }
}
```

In `ProtocolJsonTests.cs`, dopo `CollectionsUseProtocolNames`:

```csharp
    [Fact]
    public void AvatarsUseProtocolNames()
    {
        Assert.Equal(
            "{\"Users\":[{\"UserId\":\"u1\",\"Name\":\"mario\",\"ImageTag\":null}]}",
            JsonSerializer.Serialize(new AvatarsResponse([new AvatarEntry("u1", "mario", null)])));
    }
```

In `InfoControllerTests.cs`, nelle due liste delle funzioni aggiungi `"avatars"` dopo `"collections"`:
- `new[] { "friends", "parties", "inbox", "queue", "collections", "avatars" }`;
- `new[] { "friends", "parties", "inbox", "queue", "collections", "avatars", "requests" }`.

In `ServiceRegistrationTests.cs`, dopo l'`Assert.IsType<Server.JellyfinCollectionDirectory>(…)`:

```csharp
        Assert.IsType<Server.JellyfinUserAvatars>(provider.GetRequiredService<IUserAvatars>());
```

- [ ] **Step 2: i test non compilano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
Expected: errori di compilazione (`AvatarsController`, `IUserAvatars`, `AvatarsResponse` non esistono).

- [ ] **Step 3: il codice**

Crea `Protocol/AvatarDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un utente in GET Users/Avatars (spec K §7.2): l'id nel formato di Jellyfin ("N").</summary>
public sealed record AvatarEntry(
    [property: JsonPropertyName("UserId")] string UserId,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("ImageTag")] string? ImageTag);

/// <summary>Risposta di GET Users/Avatars.</summary>
public sealed record AvatarsResponse(
    [property: JsonPropertyName("Users")] IReadOnlyList<AvatarEntry> Users);
```

Crea `Hub/IUserAvatars.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Un utente con il tag della sua immagine (spec K §7.2); null senza immagine.</summary>
public sealed record UserAvatarInfo(Guid Id, string Name, string? ImageTag);

/// <summary>Le immagini degli utenti (adattatore di IUserManager e IImageProcessor).</summary>
public interface IUserAvatars
{
    /// <summary>
    /// Gli utenti attivi con uno degli id o dei nomi chiesti (i nomi senza
    /// badare alle maiuscole), ognuno una volta sola; gli altri mancano.
    /// </summary>
    IReadOnlyList<UserAvatarInfo> Find(IReadOnlyCollection<Guid> ids, IReadOnlyCollection<string> names);
}
```

Crea `Server/JellyfinUserAvatars.cs`:

```csharp
using Jellyfin.Data;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Database.Implementations.Enums;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Gli utenti chiesti, con il tag dell'immagine che Jellyfin mette in
/// UserDto.PrimaryImageTag (spec K §7.2). Elenca gli utenti una volta e
/// confronta in memoria: con Jellyfin 10.11.9 ogni GetUserById o
/// GetUserByName è una query, e GetUserByName lancia con un nome vuoto.
/// </summary>
public sealed class JellyfinUserAvatars(IUserManager userManager, IImageProcessor imageProcessor) : IUserAvatars
{
    private static readonly Func<object, IEnumerable<User>>? ListUsers = UserListing.For(typeof(IUserManager));

    public IReadOnlyList<UserAvatarInfo> Find(IReadOnlyCollection<Guid> ids, IReadOnlyCollection<string> names)
    {
        if (ids.Count == 0 && names.Count == 0)
        {
            return [];
        }

        var wantedIds = ids.ToHashSet();
        var wantedNames = names.ToHashSet(StringComparer.OrdinalIgnoreCase);
        // Ogni utente compare una volta nell'elenco: niente doppioni.
        return (ListUsers ?? throw new MissingMemberException(typeof(IUserManager).FullName, "GetUsers"))(userManager)
            .Where(user => !user.HasPermission(PermissionKind.IsDisabled))
            .Where(user => wantedIds.Contains(user.Id) || wantedNames.Contains(user.Username))
            .Select(user => new UserAvatarInfo(user.Id, user.Username, imageProcessor.GetImageCacheTag(user)))
            .ToList();
    }
}
```

Crea `Api/AvatarsController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I tag delle immagini degli utenti chiesti, per ogni utente autenticato
/// (spec K §7.2): l'app li mostra per gli amici, i membri del party e la
/// chat. Mai l'elenco completo: solo gli utenti chiesti. Come il resto del
/// plugin, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class AvatarsController(IUserAvatars avatars) : ControllerBase
{
    /// <summary>Voci al massimo per chiamata, sommando id e nomi.</summary>
    public const int MaxEntries = 100;

    /// <summary>Gli utenti chiesti per id e per nome, separati da virgole.</summary>
    [HttpGet("Users/Avatars")]
    public ActionResult<AvatarsResponse> GetAvatars([FromQuery] string? ids, [FromQuery] string? names)
    {
        var idValues = Split(ids);
        var nameValues = Split(names);
        if (idValues.Count + nameValues.Count > MaxEntries)
        {
            return BadRequest();
        }

        // Un id che non è un GUID non è di nessuno.
        var parsedIds = idValues
            .Select(raw => Guid.TryParse(raw, out var id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty)
            .ToList();
        return new AvatarsResponse(avatars.Find(parsedIds, nameValues)
            .Select(user => new AvatarEntry(user.Id.ToString("N"), user.Name, user.ImageTag))
            .ToList());
    }

    private static List<string> Split(string? raw) =>
        string.IsNullOrWhiteSpace(raw)
            ? []
            : [.. raw.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)];
}
```

In `Protocol/WatchPartyProtocol.cs`:
- aggiungi `"avatars"` in fondo a `Features`:

```csharp
    public static readonly IReadOnlyList<string> Features = ["friends", "parties", "inbox", "queue", "collections", "avatars"];
```

- nel commento sopra, aggiungi "§7.2" accanto a "spec K §7.1".

In `PluginServiceRegistrator.cs`, dopo la riga di `ICollectionDirectory`:

```csharp
        serviceCollection.AddSingleton<IUserAvatars, JellyfinUserAvatars>();
```

- [ ] **Step 4: i test passano**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
Expected: tutti verdi (390 + 9 = 399). Poi `dotnet build-server shutdown`.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): look up user avatars"
```

### Task 2: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo A si ferma qui. L'orchestratore:

1. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.5.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.5.0.0/`.
2. **Server** (`ssh ultra`; vedi la memoria `ultra-ssh` per le virgolette con `scp` e per gli script):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave "Wonderflix"); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - sostituisci la dll nella cartella della build di prova `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.5.0.0/` (la stessa cartella del 17a: il nome non cambia);
   - `app-jellyfin start`, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.5.0.0"` e nessun errore del plugin. L'avvio può durare minuti.
3. **Controllo** con la chiave "Wonderflix" (base `http://127.0.0.1:17502/jellyfin`):
   - `GET /WonderFlixWatchParty/Info` ha `avatars`;
   - `GET /Users` → i 2 utenti con `PrimaryImageTag`. Per ognuno, `GET /WonderFlixWatchParty/Users/Avatars?ids=<id>` dà lo **stesso** `ImageTag` (§14), e `?names=<nome in maiuscolo>` lo stesso utente;
   - un utente senza immagine ha l'`ImageTag` assente.

## Gruppo B — app, dati

### Task 3: i testi

**Files:**
- Modify: `l10n/app_it.arb`
- Modify: `l10n/app_en.arb`
- Create: `test/app/l10n_plan17c_test.dart`

- [ ] **Step 1: il test**

Crea `test/app/l10n_plan17c_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 17c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.profilesEditImage, 'Modifica immagine');
    expect(it.settingsChangeImage, 'Cambia immagine');
    expect(it.profileImageTitle, 'Immagine del profilo');
    expect(it.profileImageAvatars, 'Avatar');
    expect(it.profileImageFromPc, 'Dal PC');
    expect(it.profileImageUseAvatar, 'Usa questo');
    expect(it.profileImageChoose, 'Scegli un\'immagine…');
    expect(it.profileImageUseFile, 'Usa questa');
    expect(it.profileImageRemove, 'Rimuovi immagine');
    expect(it.profileImageTooLarge, 'Immagine troppo grande');
    expect(it.profileImageInvalid, 'Immagine non valida');
    expect(it.profileImageForbidden,
        'Non hai il permesso di cambiare l\'immagine');
    expect(it.profileImageFailed, 'Caricamento non riuscito');
    expect(it.profileImageFiles, 'Immagini');
    expect(it.profileImageZoom, 'Ingrandimento');
    expect(en.profileImageTitle, 'Profile picture');
    expect(en.settingsChangeImage, 'Change picture');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.profilesEditImage,
        l.settingsChangeImage,
        l.profileImageTitle,
        l.profileImageAvatars,
        l.profileImageFromPc,
        l.profileImageUseAvatar,
        l.profileImageChoose,
        l.profileImageUseFile,
        l.profileImageRemove,
        l.profileImageTooLarge,
        l.profileImageInvalid,
        l.profileImageForbidden,
        l.profileImageFailed,
        l.profileImageFiles,
        l.profileImageZoom,
      ], everyElement(isNotEmpty));
    }
  });
}
```

- [ ] **Step 2: il test non compila**

Run: `flutter test test/app/l10n_plan17c_test.dart`
Expected: errore di compilazione (`profilesEditImage` non esiste).

- [ ] **Step 3: le chiavi**

La scheda "Rimuovi" della finestra usa la chiave che c'è già (`profilesRemove`).

In `l10n/app_it.arb`, in fondo (aggiungi la virgola alla riga prima):

```json
  "profilesEditImage": "Modifica immagine",
  "settingsChangeImage": "Cambia immagine",
  "profileImageTitle": "Immagine del profilo",
  "profileImageAvatars": "Avatar",
  "profileImageFromPc": "Dal PC",
  "profileImageUseAvatar": "Usa questo",
  "profileImageChoose": "Scegli un'immagine…",
  "profileImageUseFile": "Usa questa",
  "profileImageRemove": "Rimuovi immagine",
  "profileImageTooLarge": "Immagine troppo grande",
  "profileImageInvalid": "Immagine non valida",
  "profileImageForbidden": "Non hai il permesso di cambiare l'immagine",
  "profileImageFailed": "Caricamento non riuscito",
  "profileImageFiles": "Immagini",
  "profileImageZoom": "Ingrandimento"
```

In `l10n/app_en.arb`, in fondo (aggiungi la virgola alla riga prima):

```json
  "profilesEditImage": "Edit picture",
  "settingsChangeImage": "Change picture",
  "profileImageTitle": "Profile picture",
  "profileImageAvatars": "Avatars",
  "profileImageFromPc": "From PC",
  "profileImageUseAvatar": "Use this",
  "profileImageChoose": "Choose an image…",
  "profileImageUseFile": "Use this",
  "profileImageRemove": "Remove picture",
  "profileImageTooLarge": "Image too large",
  "profileImageInvalid": "Invalid image",
  "profileImageForbidden": "You're not allowed to change the picture",
  "profileImageFailed": "Upload failed",
  "profileImageFiles": "Images",
  "profileImageZoom": "Zoom"
```

Run: `flutter gen-l10n`

- [ ] **Step 4: il test passa**

Run: `flutter test test/app/l10n_plan17c_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add l10n test/app/l10n_plan17c_test.dart
git commit -m "feat(app): add the texts for profile pictures"
```

### Task 4: API delle immagini e degli avatar

**Files:**
- Modify: `lib/core/jellyfin/jellyfin_http.dart`
- Modify: `lib/core/jellyfin/image_urls.dart`
- Create: `lib/core/jellyfin/user_image_api.dart`
- Create: `lib/core/social/avatars_api.dart`
- Modify: `lib/core/social/social_models.dart`
- Modify: `lib/features/social/social_providers.dart`
- Modify: `lib/core/jellyfin/admin_models.dart`
- Modify: `test/core/jellyfin/jellyfin_http_test.dart`
- Modify: `test/core/jellyfin/image_urls_test.dart`
- Create: `test/core/jellyfin/user_image_api_test.dart`
- Create: `test/core/social/avatars_api_test.dart`
- Modify: `test/features/social/social_providers_test.dart`
- Modify: `test/core/jellyfin/admin_models_test.dart`

- [ ] **Step 1: i test**

In `test/core/jellyfin/jellyfin_http_test.dart` (ha già `adapter` e `http` nel `setUp`), in fondo a `main`:

```dart
  test('post con un corpo che non è JSON: il suo Content-Type', () async {
    await http.post('/UserImage', body: 'QUJD', contentType: 'image/png');

    final request = adapter.requests.last;
    expect(request.data, 'QUJD');
    expect(request.contentType, 'image/png');
  });
```

In `test/core/jellyfin/image_urls_test.dart` (usa `ImageUrls(Uri.parse('https://media.example.com/jf'))`: adatta il nome della variabile a quello del file), in fondo a `main`:

```dart
  test('immagine di un utente: con il tag, senza ridimensionare', () {
    expect(urls.user('u1', 't1').url,
        'https://media.example.com/jf/UserImage?userId=u1&tag=t1');
  });
```

Crea `test/core/jellyfin/user_image_api_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/user_image_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late UserImageApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = UserImageApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('carica l\'immagine in base64, con il suo tipo', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 250]);

    await api.upload('u1', ImageUpload(bytes, 'image/png'));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/UserImage');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, base64Encode(bytes));
    expect(request.contentType, 'image/png');
  });

  test('toglie l\'immagine', () async {
    await api.remove('u1');

    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/UserImage');
    expect(request.queryParameters, {'userId': 'u1'});
  });

  test('senza permesso 403, con un token scaduto 401', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(
        api.upload('u1', ImageUpload(Uint8List(1), 'image/jpeg')),
        throwsA(isA<ForbiddenException>()));

    adapter.handler = (_) => const FakeResponse(401);
    await expectLater(api.remove('u1'), throwsA(isA<UnauthorizedException>()));
  });
}
```

Crea `test/core/social/avatars_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/avatars_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AvatarsApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, {'Users': []}));
    api = AvatarsApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('chiede id e nomi separati da virgole', () async {
    await api.avatars(ids: ['u1', 'u2'], names: ['mario']);

    final request = adapter.requests.single;
    expect(request.path, '/WonderFlixWatchParty/Users/Avatars');
    expect(request.queryParameters, {'ids': 'u1,u2', 'names': 'mario'});

    await api.avatars(names: ['luigi']);
    expect(adapter.requests.last.queryParameters, {'names': 'luigi'});
  });

  test('letture tolleranti: id senza trattini, tag assente, voci rotte saltate',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Users': [
            {'UserId': 'AB-CD', 'Name': 'Mario', 'ImageTag': 't1'},
            {'UserId': 'ef01', 'Name': 'Luigi'},
            {'Name': 'senza id'},
            'non un oggetto',
          ]
        });

    final users = await api.avatars(ids: ['abcd']);

    expect(users.map((user) => user.userId), ['abcd', 'ef01']);
    expect(users[0].name, 'Mario');
    expect(users[0].imageTag, 't1');
    expect(users[1].imageTag, isNull);
  });

  test('corpo di forma inattesa; plugin assente', () async {
    adapter.handler = (_) => const FakeResponse(200, ['x']);
    await expectLater(
        api.avatars(ids: ['u1']), throwsA(isA<ServerErrorException>()));

    adapter.handler = (_) => const FakeResponse(404);
    await expectLater(
        api.avatars(ids: ['u1']), throwsA(isA<NotFoundException>()));
  });
}
```

In `test/features/social/social_providers_test.dart`, dopo il test "Info con le saghe…":

```dart
  test('Info con gli avatar: funzione avatars, anche senza watch party',
      () async {
    api.install(features: const {PluginFeatures.avatars});
    final c = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(avatars: true));
  });
```

In `test/core/jellyfin/admin_models_test.dart`, nel gruppo `sessioni`:

```dart
    test('il tag dell\'immagine dell\'utente, se c\'è', () {
      final sessions = parseSessions([
        {'Id': 's1', 'UserId': 'u1', 'UserName': 'Mario', 'UserPrimaryImageTag': 'img1'},
        {'Id': 's2', 'UserId': 'u2', 'UserName': 'Luigi'},
      ]);

      expect(sessions[0].userImageTag, 'img1');
      expect(sessions[1].userImageTag, isNull);
    });
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/core test/features/social/social_providers_test.dart`
Expected: errori di compilazione (`contentType`, `user`, `UserImageApi`, `AvatarsApi`, `PluginFeatures.avatars`, `userImageTag`).

- [ ] **Step 3: il codice**

In `lib/core/jellyfin/jellyfin_http.dart`, `post` prende anche un `Content-Type`:

```dart
  /// [quietStatuses] come in [get]. [contentType] per un corpo che non è
  /// JSON (l'immagine di un utente, spec K §10.4): senza, dio manda
  /// `application/json`.
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? contentType,
    Set<int> quietStatuses = const {},
  }) =>
      _send(
          () => dio.post<dynamic>(path,
              data: body,
              queryParameters: query,
              options:
                  contentType == null ? null : Options(contentType: contentType)),
          quietStatuses: quietStatuses);
```

In `lib/core/jellyfin/image_urls.dart`, dopo `primaryWithTag`:

```dart
  /// Immagine di un utente (spec K §10.5). Il server non la ridimensiona (si
  /// decodifica alla dimensione mostrata) e non chiede l'accesso; con il tag
  /// l'indirizzo cambia quando cambia l'immagine.
  ImageRef user(String userId, String tag) =>
      ImageRef('$_base/UserImage?userId=$userId&tag=$tag');
```

Crea `lib/core/jellyfin/user_image_api.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'jellyfin_http.dart';

/// Un'immagine da caricare: i byte e il loro tipo (`image/png`, `image/jpeg`).
class ImageUpload {
  const ImageUpload(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// L'immagine di un utente su Jellyfin (spec K §10.4). Gli errori sono
/// `ApiException`: 403 senza il permesso di cambiarla, 401 con un token che
/// non vale più.
class UserImageApi {
  UserImageApi(this._http);

  final JellyfinHttp _http;

  /// Jellyfin vuole il corpo in base64 e il tipo nel `Content-Type`
  /// (`ImageController.PostUserImage` di 10.11.9, come jellyfin-web).
  Future<void> upload(String userId, ImageUpload image) => _http.post(
        '/UserImage',
        query: {'userId': userId},
        body: base64Encode(image.bytes),
        contentType: image.contentType,
      );

  Future<void> remove(String userId) =>
      _http.delete('/UserImage', query: {'userId': userId});
}
```

Crea `lib/core/social/avatars_api.dart`:

```dart
import '../jellyfin/jellyfin_http.dart';
import '../jellyfin/json_fields.dart';

/// Un utente con il tag della sua immagine (spec K §7.2).
class UserAvatarInfo {
  const UserAvatarInfo({required this.userId, required this.name, this.imageTag});

  /// `null` senza `UserId`.
  static UserAvatarInfo? fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'UserId');
    if (id == null) return null;
    return UserAvatarInfo(
      userId: jellyfinIdKey(id),
      name: jsonString(json, 'Name') ?? '',
      imageTag: jsonString(json, 'ImageTag'),
    );
  }

  /// Senza trattini e in minuscolo ([jellyfinIdKey]).
  final String userId;
  final String name;

  /// `null` senza immagine (sul server vero il campo manca).
  final String? imageTag;
}

/// I tag delle immagini degli utenti chiesti, dal plugin (spec K §7.2). Gli
/// errori sono `ApiException`; un corpo di forma inattesa è
/// `ServerErrorException`.
class AvatarsApi {
  AvatarsApi(this._http);

  final JellyfinHttp _http;

  static const _path = '/WonderFlixWatchParty/Users/Avatars';

  /// Jellyfin che si riavvia: nel log come info.
  static const _quiet = restartGatewayStatuses;

  /// Voci al massimo per chiamata, sommando id e nomi (oltre, il plugin
  /// risponde 400).
  static const maxEntries = 100;

  Future<List<UserAvatarInfo>> avatars({
    Iterable<String> ids = const [],
    Iterable<String> names = const [],
  }) async {
    final json = asJsonMap(await _http.get(_path,
        query: {
          if (ids.isNotEmpty) 'ids': ids.join(','),
          if (names.isNotEmpty) 'names': names.join(','),
        },
        quietStatuses: _quiet));
    return jsonList(json['Users'], UserAvatarInfo.fromJson);
  }
}
```

In `lib/core/social/social_models.dart`, in `PluginFeatures` dopo `collections`:

```dart
  /// Le immagini degli altri utenti (spec K §7.2).
  static const avatars = 'avatars';
```

In `lib/features/social/social_providers.dart`, `SocialFeatures` ha anche `avatars`, come `collections`:
- nel costruttore `this.avatars = false,` dopo `this.collections = false,`;
- il campo:

```dart
  /// Le immagini degli altri utenti (spec K §10.5): non dipendono dai watch
  /// party.
  final bool avatars;
```

- in `==` `other.avatars == avatars &&`, in `hashCode` `Object.hash(friends, parties, inbox, requests, collections, avatars, known)`, in `toString` `avatars: $avatars, ` prima di `known`;
- in `refresh()`, dopo `collections: …`:

```dart
        avatars: info.features.contains(PluginFeatures.avatars),
```

In `lib/core/jellyfin/admin_models.dart`, `SessionEntry`:
- nel costruttore `this.userImageTag,` dopo `required this.userName,`;
- in `fromJson`, dopo `userName: …`:

```dart
      userImageTag: jsonString(json, 'UserPrimaryImageTag'),
```

- il campo, dopo `userName`:

```dart
  /// Tag dell'immagine dell'utente (spec K §10.5); `null` senza immagine.
  final String? userImageTag;
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/core test/features/social`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): user image and avatars api"
```

### Task 5: `AvatarDirectory` e `UserAvatar`

**Files:**
- Create: `lib/features/social/avatars_provider.dart`
- Create: `lib/ui/user_avatar.dart`
- Create: `test/support/avatar_fakes.dart`
- Create: `test/features/social/avatars_provider_test.dart`
- Create: `test/ui/user_avatar_test.dart`

- [ ] **Step 1: il supporto e i test**

Crea `test/support/avatar_fakes.dart`:

```dart
import 'package:wonderflix/core/social/avatars_api.dart';

/// `AvatarsApi` finto: risponde con gli utenti di [users] che corrispondono
/// agli id o ai nomi (senza maiuscole), oppure lancia [error].
class FakeAvatarsApi implements AvatarsApi {
  List<UserAvatarInfo> users = const [];
  Object? error;
  final calls = <({List<String> ids, List<String> names})>[];

  @override
  Future<List<UserAvatarInfo>> avatars({
    Iterable<String> ids = const [],
    Iterable<String> names = const [],
  }) async {
    calls.add((ids: ids.toList(), names: names.toList()));
    final failure = error;
    if (failure != null) throw failure;
    final wantedIds = ids.toSet();
    final wantedNames = {for (final name in names) name.toLowerCase()};
    return [
      for (final user in users)
        if (wantedIds.contains(user.userId) ||
            wantedNames.contains(user.name.toLowerCase()))
          user,
    ];
  }
}
```

Crea `test/features/social/avatars_provider_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/avatar_fakes.dart';
import '../../support/profile_fakes.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeAvatarsApi api;

  setUp(() => api = FakeAvatarsApi()
    ..users = const [
      UserAvatarInfo(userId: 'u1', name: 'Mario', imageTag: 't1'),
      UserAvatarInfo(userId: 'u2', name: 'Luigi'),
    ]);

  group('AvatarDirectory', () {
    test('raccoglie le richieste di 50 ms in una sola chiamata', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        AvatarImage? byId;
        AvatarImage? sameAgain;
        AvatarImage? luigi = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('U-1')).then((v) => byId = v);
        async.elapse(const Duration(milliseconds: 20));
        directory.imageFor(AvatarLookup.byName('LUIGI')).then((v) => luigi = v);
        // La stessa richiesta: 'U-1' e 'u1' sono lo stesso id.
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => sameAgain = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(api.calls, hasLength(1));
        expect(api.calls.single.ids, ['u1']);
        expect(api.calls.single.names, ['luigi']);
        expect(byId, const AvatarImage('u1', 't1'));
        expect(sameAgain, const AvatarImage('u1', 't1'));
        // Luigi non ha un'immagine: l'iniziale.
        expect(luigi, isNull);
      });
    });

    test('per nome: l\'id viene dalla risposta, e vale anche per id', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        AvatarImage? byName;
        directory.imageFor(AvatarLookup.byName('Mario')).then((v) => byName = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(byName, const AvatarImage('u1', 't1'));

        AvatarImage? byId;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        async.flushMicrotasks();
        expect(byId, const AvatarImage('u1', 't1'));
        expect(api.calls, hasLength(1));
      });
    });

    test('un risultato vale 10 minuti', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);

        async.elapse(const Duration(minutes: 9));
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));

        async.elapse(const Duration(minutes: 2));
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(2));
      });
    });

    test('un errore lascia le iniziali, e si riprova dopo 10 minuti', () {
      fakeAsync((async) {
        api.error = const ServerUnreachableException();
        final directory = AvatarDirectory(api);
        AvatarImage? first = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => first = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(first, isNull);

        api.error = null;
        directory.imageFor(AvatarLookup.byId('u1'));
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(api.calls, hasLength(1));

        async.elapse(AvatarDirectory.defaultTtl);
        AvatarImage? later;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => later = v);
        async.elapse(AvatarDirectory.defaultBatchDelay);
        expect(later, const AvatarImage('u1', 't1'));
      });
    });

    test('al massimo 100 voci per chiamata', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        for (var i = 0; i < 150; i++) {
          directory.imageFor(AvatarLookup.byId('id$i'));
        }
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(api.calls.map((call) => call.ids.length), [100, 50]);
      });
    });

    test('remember: un\'immagine appena cambiata vale subito', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api)
          ..remember(userId: 'U1', name: 'Mario', tag: 't9');
        AvatarImage? byId;
        AvatarImage? byName;
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => byId = v);
        directory.imageFor(AvatarLookup.byName('mario')).then((v) => byName = v);
        async.flushMicrotasks();

        expect(byId, const AvatarImage('u1', 't9'));
        expect(byName, const AvatarImage('u1', 't9'));
        expect(api.calls, isEmpty);
      });
    });

    test('dispose: le richieste in attesa finiscono con l\'iniziale', () {
      fakeAsync((async) {
        final directory = AvatarDirectory(api);
        AvatarImage? pending = const AvatarImage('x', 'x');
        directory.imageFor(AvatarLookup.byId('u1')).then((v) => pending = v);
        directory.dispose();
        async.elapse(AvatarDirectory.defaultBatchDelay);

        expect(pending, isNull);
        expect(api.calls, isEmpty);
      });
    });
  });

  group('provider', () {
    ProviderContainer container(FixedProfiles profiles,
            {SocialFeatures features = const SocialFeatures(avatars: true)}) =>
        ProviderContainer.test(
          overrides: [
            profilesProvider.overrideWith(() => profiles),
            socialAvailabilityProvider
                .overrideWith(() => FakeSocialAvailability(features)),
            avatarsApiProvider.overrideWithValue(api),
          ],
          retry: (_, _) => null,
        );

    test('senza un profilo aperto: niente cache, e la sessione non si crea', () {
      // Senza override della sessione: se si leggesse, lancerebbe
      // (clientInfoProvider va sovrascritto).
      final c = ProviderContainer.test(
        overrides: [avatarsApiProvider.overrideWithValue(api)],
        retry: (_, _) => null,
      );
      expect(c.read(avatarDirectoryProvider), isNull);
    });

    test('senza la funzione avatars: niente cache', () {
      final c = container(FixedProfiles(const ProfilesState(activeUserId: 'u1')),
          features: const SocialFeatures());
      expect(c.read(avatarDirectoryProvider), isNull);
    });

    test('una cache per profilo', () {
      final profiles = FixedProfiles(const ProfilesState(activeUserId: 'u1'));
      final c = container(profiles);
      final first = c.read(avatarDirectoryProvider);
      expect(first, isNotNull);

      profiles.set(const ProfilesState(activeUserId: 'u2'));
      final second = c.read(avatarDirectoryProvider);
      expect(second, isNotNull);
      expect(second, isNot(same(first)));
    });

    test('avatarImageProvider senza cache: null, nessuna chiamata', () async {
      final c = ProviderContainer.test(
        overrides: [avatarsApiProvider.overrideWithValue(api)],
        retry: (_, _) => null,
      );
      final lookup = AvatarLookup.byName('Mario');
      c.listen(avatarImageProvider(lookup), (_, _) {});

      expect(await c.read(avatarImageProvider(lookup).future), isNull);
      expect(api.calls, isEmpty);
    });
  });
}
```

Crea `test/ui/user_avatar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/avatars_api.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/ui/user_avatar.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../support/avatar_fakes.dart';
import '../support/pump_app.dart';

void main() {
  late List<String> urls;

  Override captureImages() =>
      imageBuilderProvider.overrideWithValue((image, fit) {
        urls.add(image.url);
        return const SizedBox.expand();
      });

  setUp(() => urls = []);

  Color background(WidgetTester tester) =>
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor!;

  testWidgets('con il tag: l\'immagine sopra l\'iniziale', (tester) async {
    await pumpApp(
        tester,
        const Center(
            child: UserAvatar(userId: 'u1', name: 'mario', size: 40, imageTag: 't1')),
        overrides: [captureImages()]);

    expect(urls.last, 'https://media.example.com/UserImage?userId=u1&tag=t1');
    // L'iniziale resta sotto: si vede finché l'immagine non c'è.
    expect(find.text('M'), findsOneWidget);
    expect(tester.getSize(find.byType(UserAvatar)), const Size(40, 40));
  });

  testWidgets('senza tag: solo l\'iniziale, scura su oro', (tester) async {
    await pumpApp(
        tester, const Center(child: UserAvatar(userId: 'u1', name: '', size: 30)),
        overrides: [captureImages()]);

    expect(urls, isEmpty);
    expect(find.text('?'), findsOneWidget);
    expect(background(tester), WfColors.gold);
  });

  testWidgets('muted: l\'iniziale dorata su grigio', (tester) async {
    await pumpApp(
        tester,
        const Center(
            child: UserAvatar(userId: 'u1', name: 'Luigi', size: 26, muted: true)),
        overrides: [captureImages()]);

    expect(background(tester), WfColors.surfaceHigh);
  });

  testWidgets('lookup senza un profilo aperto: l\'iniziale, nessuna chiamata',
      (tester) async {
    final api = FakeAvatarsApi();
    await pumpApp(tester,
        const Center(child: UserAvatar.lookup(name: 'Mario', size: 26)),
        overrides: [captureImages(), avatarsApiProvider.overrideWithValue(api)]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);

    expect(urls, isEmpty);
    expect(api.calls, isEmpty);
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('lookup per nome: l\'immagine con l\'id della risposta',
      (tester) async {
    final api = FakeAvatarsApi()
      ..users = const [UserAvatarInfo(userId: 'u1', name: 'Mario', imageTag: 't1')];
    await pumpApp(tester,
        const Center(child: UserAvatar.lookup(name: 'Mario', size: 26, muted: true)),
        overrides: [
          captureImages(),
          avatarDirectoryProvider.overrideWithValue(AvatarDirectory(api)),
        ]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    expect(api.calls.single.names, ['mario']);
    expect(urls.last, 'https://media.example.com/UserImage?userId=u1&tag=t1');
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/social/avatars_provider_test.dart test/ui/user_avatar_test.dart`
Expected: errori di compilazione (`avatars_provider.dart` e `user_avatar.dart` non esistono).

- [ ] **Step 3: il codice**

Crea `lib/features/social/avatars_provider.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/avatars_api.dart';
import '../auth/profiles_state.dart';
import 'social_providers.dart';

final _log = Logger('avatars');

/// Chi cercare (spec K §10.5): per id, o per nome quando c'è solo quello (i
/// membri del party: SyncPlay dà solo i nomi). Id senza trattini e nomi in
/// minuscolo, come li confronta il plugin.
class AvatarLookup {
  AvatarLookup.byId(String userId)
      : userId = jellyfinIdKey(userId),
        name = null;

  AvatarLookup.byName(String name)
      : userId = null,
        name = name.toLowerCase();

  final String? userId;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is AvatarLookup && other.userId == userId && other.name == name;

  @override
  int get hashCode => Object.hash(userId, name);

  @override
  String toString() =>
      userId != null ? 'AvatarLookup(id: $userId)' : 'AvatarLookup(name: $name)';
}

/// L'immagine di un utente: il suo id (anche cercandolo per nome) e il tag.
class AvatarImage {
  const AvatarImage(this.userId, this.tag);

  final String userId;
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is AvatarImage && other.userId == userId && other.tag == tag;

  @override
  int get hashCode => Object.hash(userId, tag);

  @override
  String toString() => 'AvatarImage($userId, $tag)';
}

/// I tag delle immagini degli altri utenti, chiesti al plugin (spec K §10.5).
///
/// - Le richieste dei widget si raccolgono per [batchDelay] e partono in una
///   sola chiamata, con al massimo [AvatarsApi.maxEntries] voci (le altre in
///   una chiamata subito dopo).
/// - Un risultato vale [ttl]; anche un errore, che lascia le iniziali: si
///   riprova dopo [ttl].
/// - Un utente trovato vale per id e per nome.
class AvatarDirectory {
  AvatarDirectory(this._api,
      {this.batchDelay = defaultBatchDelay, this.ttl = defaultTtl});

  /// Quanto si aspettano altre richieste prima di chiamare il plugin.
  static const defaultBatchDelay = Duration(milliseconds: 50);

  /// Quanto vale un risultato.
  static const defaultTtl = Duration(minutes: 10);

  final AvatarsApi _api;
  final Duration batchDelay;
  final Duration ttl;

  final _cache = <AvatarLookup, _Cached>{};
  final _waiting = <AvatarLookup, Completer<AvatarImage?>>{};
  Timer? _timer;
  bool _disposed = false;

  /// L'immagine di [lookup]; `null` senza immagine, per un utente che non
  /// c'è o dopo un errore: si mostra l'iniziale.
  Future<AvatarImage?> imageFor(AvatarLookup lookup) {
    if (_disposed) return Future.value(null);
    final cached = _cache[lookup];
    if (cached != null && clock.now().difference(cached.at) < ttl) {
      return Future.value(cached.image);
    }
    final waiting = _waiting[lookup];
    if (waiting != null) return waiting.future;
    final completer = Completer<AvatarImage?>();
    _waiting[lookup] = completer;
    _timer ??= Timer(batchDelay, _flush);
    return completer.future;
  }

  /// Un'immagine appena cambiata (spec K §10.4): vale subito, per id e per
  /// nome.
  void remember(
      {required String userId, required String name, required String? tag}) {
    final entry = _Cached(
        tag == null ? null : AvatarImage(jellyfinIdKey(userId), tag),
        clock.now());
    _cache[AvatarLookup.byId(userId)] = entry;
    _cache[AvatarLookup.byName(name)] = entry;
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = _waiting.keys.take(AvatarsApi.maxEntries).toList();
    final completers = [for (final key in batch) _waiting.remove(key)!];
    // Oltre il limite: un'altra chiamata, subito.
    if (_waiting.isNotEmpty) _timer = Timer(Duration.zero, _flush);
    final found = <AvatarLookup, AvatarImage?>{};
    try {
      final users = await _api.avatars(
        ids: [for (final key in batch) ?key.userId],
        names: [for (final key in batch) ?key.name],
      );
      for (final user in users) {
        final tag = user.imageTag;
        final image = tag == null ? null : AvatarImage(user.userId, tag);
        found[AvatarLookup.byId(user.userId)] = image;
        found[AvatarLookup.byName(user.name)] = image;
      }
    } on Object catch (error) {
      final message = 'immagini degli utenti non lette: ${error.runtimeType}';
      if (error is ApiException) {
        _log.info(message);
      } else {
        _log.warning(message);
      }
    }
    final now = clock.now();
    for (final MapEntry(:key, :value) in found.entries) {
      _cache[key] = _Cached(value, now);
    }
    for (var i = 0; i < batch.length; i++) {
      final image = found[batch[i]];
      _cache[batch[i]] = _Cached(image, now);
      completers[i].complete(image);
    }
  }

  /// Le richieste in attesa finiscono con l'iniziale.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final completer in _waiting.values) {
      completer.complete(null);
    }
    _waiting.clear();
  }
}

class _Cached {
  const _Cached(this.image, this.at);

  final AvatarImage? image;
  final DateTime at;
}

final avatarsApiProvider =
    Provider<AvatarsApi>((ref) => AvatarsApi(ref.watch(jellyfinHttpProvider)));

/// La cache degli avatar del profilo aperto (spec K §10.5). `null` senza un
/// profilo aperto o senza la funzione `avatars` del plugin: nessuna
/// chiamata, solo iniziali. Un altro profilo ha una cache nuova.
final avatarDirectoryProvider = Provider<AvatarDirectory?>((ref) {
  // Prima i profili, che non dipendono dal client HTTP: senza un profilo
  // aperto la sessione non si crea (nei widget test senza sessione
  // lancerebbe).
  final userId = ref
      .watch(profilesProvider.select((profiles) => profiles.activeUserId));
  if (userId == null) return null;
  final available = ref.watch(
      socialAvailabilityProvider.select((features) => features.avatars));
  if (!available) return null;
  final directory = AvatarDirectory(ref.watch(avatarsApiProvider));
  ref.onDispose(directory.dispose);
  return directory;
});

/// L'immagine di un utente (spec K §10.5); `null`: l'iniziale.
final avatarImageProvider = FutureProvider.autoDispose
    .family<AvatarImage?, AvatarLookup>((ref, lookup) async {
  final directory = ref.watch(avatarDirectoryProvider);
  if (directory == null) return null;
  return directory.imageFor(lookup);
});
```

Crea `lib/ui/user_avatar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../features/library/library_providers.dart';
import '../features/social/avatars_provider.dart';
import 'wf_image.dart';

/// Dimensione dell'iniziale rispetto al diametro.
const _initialScale = 0.45;

/// L'immagine di un utente, o la sua iniziale (spec K §10.5).
///
/// - [UserAvatar.new]: il tag è già noto (l'utente aperto, un profilo
///   salvato, una sessione dell'admin); `null` vuol dire senza immagine.
/// - [UserAvatar.lookup]: il tag lo cerca [avatarImageProvider], per id o,
///   senza id, per nome (i membri del party).
///
/// L'immagine sta sopra l'iniziale, con il segnaposto trasparente: mentre si
/// carica, o se non si carica, si vede l'iniziale.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    required this.size,
    this.imageTag,
    this.muted = false,
  }) : _lookup = false;

  const UserAvatar.lookup({
    super.key,
    this.userId,
    required this.name,
    required this.size,
    this.muted = false,
  })  : imageTag = null,
        _lookup = true;

  final String? userId;
  final String name;

  /// Diametro.
  final double size;
  final String? imageTag;

  /// Iniziale dorata su grigio (party, amici, chat) invece che scura su oro.
  final bool muted;
  final bool _lookup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image =
        _lookup ? ref.watch(avatarImageProvider(_lookupKey)).value : _known;
    final initial = _Initial(name: name, size: size, muted: muted);
    if (image == null) return initial;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          initial,
          ClipOval(
            child: TransparentPlaceholders(
              child: WfImage(
                image: ref.watch(imageUrlsProvider).user(image.userId, image.tag),
                fallbackIcon: null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AvatarLookup get _lookupKey {
    final id = userId;
    return id == null ? AvatarLookup.byName(name) : AvatarLookup.byId(id);
  }

  AvatarImage? get _known {
    final id = userId;
    final tag = imageTag;
    return id == null || tag == null ? null : AvatarImage(id, tag);
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.size, required this.muted});

  final String name;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: muted ? WfColors.surfaceHigh : WfColors.gold,
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(
            color: muted ? WfColors.gold : WfColors.bg,
            fontSize: size * _initialScale,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/social test/ui/user_avatar_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): user avatars with a batched cache"
```

## Gruppo C — l'immagine del profilo

### Task 6: la galleria

**Files:**
- Create: `lib/features/profiles/avatar_gallery.dart`
- Create: `test/features/profiles/avatar_gallery_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/profiles/avatar_gallery_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/profiles/avatar_gallery.dart';

/// Un intero a 32 bit big-endian (l'intestazione IHDR di un PNG).
int _uint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void main() {
  test('24 avatar, icone tutte diverse, colori diversi da quelli vicini', () {
    expect(galleryGradients, hasLength(8));
    expect(galleryAvatars, hasLength(24));
    expect(galleryAvatars.map((avatar) => avatar.icon).toSet(), hasLength(24));
    for (var i = 1; i < galleryAvatars.length; i++) {
      expect(galleryAvatars[i].colors, isNot(galleryAvatars[i - 1].colors));
    }
  });

  testWidgets('ogni avatar è un PNG di 512×512', (tester) async {
    final pngs = await tester
        .runAsync(() => Future.wait(galleryAvatars.map(renderGalleryAvatar)));

    for (final png in pngs!) {
      expect(String.fromCharCodes(png.sublist(1, 4)), 'PNG');
      expect(_uint32(png, 16), galleryAvatarSize);
      expect(_uint32(png, 20), galleryAvatarSize);
    }
  });

  testWidgets('l\'anteprima ha il suo lato', (tester) async {
    await tester.pumpWidget(Center(
        child: GalleryAvatarView(avatar: galleryAvatars.first, size: 64)));

    expect(tester.getSize(find.byType(GalleryAvatarView)), const Size(64, 64));
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/profiles/avatar_gallery_test.dart`
Expected: errore di compilazione (`avatar_gallery.dart` non esiste).

- [ ] **Step 3: il codice**

Crea `lib/features/profiles/avatar_gallery.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Lato delle immagini della galleria, in pixel (spec K §10.2).
const galleryAvatarSize = 512;

/// L'icona occupa questa parte del lato.
const _iconScale = 0.55;

/// Colore dell'icona.
const _iconColor = Color(0xFFFFFFFF);

/// Le 8 sfumature, dai colori di WonderFlix: dall'alto a sinistra al basso a
/// destra.
const galleryGradients = <(Color, Color)>[
  (Color(0xFFD4A64A), Color(0xFF7A5A1E)), // oro
  (Color(0xFFC8463C), Color(0xFF5E1C17)), // rosso sipario
  (Color(0xFF2E8B85), Color(0xFF123B38)), // verde acqua
  (Color(0xFF4F5BD5), Color(0xFF1F2560)), // blu notte
  (Color(0xFF8E4FC8), Color(0xFF3D1C5A)), // viola
  (Color(0xFF5BBF6A), Color(0xFF24502B)), // verde
  (Color(0xFFE07A2E), Color(0xFF6E3410)), // arancio
  (Color(0xFF5A6472), Color(0xFF22262D)), // ardesia
];

/// Le icone, a tema cinema e serate. Lucide 3.1.20 non ha il gufo: c'è
/// l'uccello.
const _icons = <IconData>[
  LucideIcons.popcorn,
  LucideIcons.clapperboard,
  LucideIcons.film,
  LucideIcons.ticket,
  LucideIcons.tv,
  LucideIcons.projector,
  LucideIcons.video,
  LucideIcons.star,
  LucideIcons.rocket,
  LucideIcons.ghost,
  LucideIcons.cat,
  LucideIcons.dog,
  LucideIcons.rabbit,
  LucideIcons.bird,
  LucideIcons.fish,
  LucideIcons.skull,
  LucideIcons.crown,
  LucideIcons.heart,
  LucideIcons.music,
  LucideIcons.gamepad2,
  LucideIcons.pizza,
  LucideIcons.coffee,
  LucideIcons.sparkles,
  LucideIcons.moon,
];

/// Un avatar della galleria: un'icona bianca su una sfumatura.
class GalleryAvatar {
  const GalleryAvatar(this.icon, this.colors);

  final IconData icon;
  final (Color, Color) colors;
}

/// I 24 avatar (spec K §10.2): le sfumature si ripetono in ordine, quindi due
/// icone vicine hanno colori diversi.
final galleryAvatars = List<GalleryAvatar>.unmodifiable([
  for (var i = 0; i < _icons.length; i++)
    GalleryAvatar(_icons[i], galleryGradients[i % galleryGradients.length]),
]);

/// Disegna [avatar] in un quadrato di lato [size].
void paintGalleryAvatar(Canvas canvas, double size, GalleryAvatar avatar) {
  final rect = Offset.zero & Size.square(size);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
          rect.topLeft, rect.bottomRight, [avatar.colors.$1, avatar.colors.$2]),
  );
  final icon = avatar.icon;
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size * _iconScale,
        height: 1,
        color: _iconColor,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2));
  painter.dispose();
}

/// [avatar] come PNG di [galleryAvatarSize]×[galleryAvatarSize] (spec K §10.2):
/// l'immagine che si carica.
Future<Uint8List> renderGalleryAvatar(GalleryAvatar avatar) async {
  final recorder = ui.PictureRecorder();
  paintGalleryAvatar(Canvas(recorder), galleryAvatarSize.toDouble(), avatar);
  final picture = recorder.endRecording();
  final image = await picture.toImage(galleryAvatarSize, galleryAvatarSize);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// L'anteprima di un avatar della galleria: lo stesso disegno, in piccolo e
/// rotondo.
class GalleryAvatarView extends StatelessWidget {
  const GalleryAvatarView({super.key, required this.avatar, required this.size});

  final GalleryAvatar avatar;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: CustomPaint(
            size: Size.square(size), painter: _GalleryAvatarPainter(avatar)),
      );
}

class _GalleryAvatarPainter extends CustomPainter {
  _GalleryAvatarPainter(this.avatar);

  final GalleryAvatar avatar;

  @override
  void paint(Canvas canvas, Size size) =>
      paintGalleryAvatar(canvas, size.shortestSide, avatar);

  @override
  bool shouldRepaint(_GalleryAvatarPainter oldDelegate) =>
      oldDelegate.avatar != avatar;
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/profiles/avatar_gallery_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): a gallery of cinema avatars"
```

### Task 7: l'immagine dal PC e il ritaglio

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Modify: `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake` (cambi veri del plugin `file_selector_windows`)
- Create: `lib/features/profiles/avatar_image.dart`
- Create: `lib/features/profiles/avatar_cropper.dart`
- Create: `test/features/profiles/avatar_image_test.dart`
- Create: `test/features/profiles/avatar_cropper_test.dart`

- [ ] **Step 1: i pacchetti**

Run: `flutter pub add file_selector image`

Controlla `git diff windows/flutter/`: ci deve essere il plugin `file_selector_windows` in `generated_plugin_registrant.cc` e in `generated_plugins.cmake`. Questi cambi si committano (vedi le regole). Se invece cambiano solo le fini riga, non c'è niente da tenere.

- [ ] **Step 2: i test**

Crea `test/features/profiles/avatar_image_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/features/profiles/avatar_image.dart';

Uint8List _png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

Matcher _fails(AvatarImageError reason) => throwsA(
    isA<AvatarImageException>().having((e) => e.reason, 'reason', reason));

void main() {
  group('preparazione', () {
    test('un PNG: stesso lato, in PNG', () {
      final working = prepareAvatarImageSync(_png(300, 200));

      expect((working.width, working.height), (300, 200));
      expect(img.decodePng(working.bytes)!.width, 300);
    });

    test('oltre 2048 px: ridotta', () {
      final working = prepareAvatarImageSync(_png(4096, 1024));

      expect((working.width, working.height), (maxWorkingSide, 512));
    });

    test('una foto girata: raddrizzata secondo l\'EXIF', () {
      final photo = img.Image(width: 300, height: 200);
      photo.exif.imageIfd.orientation = 6;

      final working = prepareAvatarImageSync(img.encodeJpg(photo));

      expect((working.width, working.height), (200, 300));
    });

    test('un file che non è un\'immagine: non valida', () {
      expect(() => prepareAvatarImageSync(Uint8List.fromList([1, 2, 3, 4])),
          _fails(AvatarImageError.invalid));
    });

    test('oltre 20 MB: troppo grande, senza decodificare', () {
      expect(() => prepareAvatarImageSync(Uint8List(maxAvatarFileBytes + 1)),
          _fails(AvatarImageError.tooLarge));
    });

    testWidgets('in un isolate', (tester) async {
      final working =
          await tester.runAsync(() => prepareAvatarImage(_png(30, 20)));

      expect(working!.width, 30);
    });
  });

  group('ritaglio', () {
    test('un JPEG di 512×512', () {
      final working = prepareAvatarImageSync(_png(400, 200));

      final jpeg = cropAvatarImageSync(working.bytes, const CropArea(100, 0, 200));

      final out = img.decodeJpg(jpeg)!;
      expect((out.width, out.height), (avatarOutputSize, avatarOutputSize));
    });

    test('un riquadro che esce dall\'immagine si stringe dentro', () {
      final working = prepareAvatarImageSync(_png(400, 200));

      final jpeg =
          cropAvatarImageSync(working.bytes, const CropArea(350, -10, 300));

      expect(img.decodeJpg(jpeg)!.width, avatarOutputSize);
    });
  });
}
```

Se `encodeJpg` del pacchetto `image` non scrive l'EXIF, il test della foto girata va scritto con un JPEG che ha l'orientamento 6 nei suoi byte (per esempio costruito con le API EXIF del pacchetto): adattalo in modo minimo, senza toglierlo.

Crea `test/features/profiles/avatar_cropper_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/features/profiles/avatar_cropper.dart';
import 'package:wonderflix/features/profiles/avatar_image.dart';

import '../../support/pump_app.dart';

void main() {
  const image = Size(400, 200);

  test('i conti del ritaglio', () {
    expect(cropBaseScale(image, 200), 1.0);
    expect(centeredCropOffset(image, 200), const Offset(-100, 0));
    expect(initialCropArea(image, 200), const CropArea(100, 0, 200));
    // Due volte più grande: il riquadro è la metà.
    expect(cropAreaFor(image, 200, 2, const Offset(-200, -100)),
        const CropArea(100, 50, 100));
  });

  test('l\'immagine copre sempre il riquadro', () {
    expect(clampCropOffset(const Offset(50, 20), image, 200, 1), Offset.zero);
    expect(clampCropOffset(const Offset(-500, -20), image, 200, 1),
        const Offset(-200, 0));
    expect(clampCropOffset(const Offset(-1000, -1000), image, 200, 2),
        const Offset(-600, -200));
  });

  testWidgets('trascinare, il cursore e la rotella', (tester) async {
    final areas = <CropArea>[];
    final working = WorkingImage(
        img.encodePng(img.Image(width: 4, height: 2)), 400, 200);
    await pumpApp(
        tester,
        Center(
            child: AvatarCropper(
                image: working, viewport: 200, onChanged: areas.add)));

    // Trascinata verso destra oltre il bordo: si ferma al bordo sinistro.
    await tester.drag(
        find.byKey(const Key('avatar-crop-area')), const Offset(300, 0));
    await tester.pump();
    expect(areas.last, const CropArea(0, 0, 200));

    // Il cursore in fondo: 4×.
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pump();
    expect(areas.last.side, 50);

    // La rotella verso il basso rimpicciolisce di uno scatto.
    final center = tester.getCenter(find.byKey(const Key('avatar-crop-area')));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: center, scrollDelta: const Offset(0, 20)));
    await tester.pump();
    expect(areas.last.side, closeTo(55, 0.01));
  });
}
```

- [ ] **Step 3: i test non compilano**

Run: `flutter test test/features/profiles/avatar_image_test.dart test/features/profiles/avatar_cropper_test.dart`
Expected: errori di compilazione (`avatar_image.dart` e `avatar_cropper.dart` non esistono).

- [ ] **Step 4: il codice**

Crea `lib/features/profiles/avatar_image.dart`:

```dart
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Le estensioni che si possono scegliere (spec K §10.3).
const avatarFileExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];

/// Un file più grande: "Immagine troppo grande" (spec K §10.3).
const maxAvatarFileBytes = 20 * 1024 * 1024;

/// Lato massimo dell'immagine di lavoro: basta per un avatar di 512 px anche
/// a 4×, e tiene leggero il ritaglio.
const maxWorkingSide = 2048;

/// Lato dell'immagine caricata (spec K §10.3).
const avatarOutputSize = 512;

/// Qualità del JPEG caricato.
const avatarJpegQuality = 90;

enum AvatarImageError { tooLarge, invalid }

class AvatarImageException implements Exception {
  const AvatarImageException(this.reason);

  final AvatarImageError reason;

  @override
  String toString() => 'AvatarImageException($reason)';
}

/// L'immagine da ritagliare: raddrizzata secondo l'EXIF, al massimo
/// [maxWorkingSide] per lato, in PNG.
class WorkingImage {
  const WorkingImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// La parte da tenere, in pixel dell'immagine di lavoro: un quadrato.
class CropArea {
  const CropArea(this.left, this.top, this.side);

  final double left;
  final double top;
  final double side;

  @override
  bool operator ==(Object other) =>
      other is CropArea &&
      other.left == left &&
      other.top == top &&
      other.side == side;

  @override
  int get hashCode => Object.hash(left, top, side);

  @override
  String toString() => 'CropArea($left, $top, $side)';
}

/// Prepara in un isolate il file scelto (spec K §10.3). Lancia
/// [AvatarImageException].
Future<WorkingImage> prepareAvatarImage(Uint8List bytes) =>
    Isolate.run(() => prepareAvatarImageSync(bytes));

/// Come [prepareAvatarImage], nel thread di chi chiama.
WorkingImage prepareAvatarImageSync(Uint8List bytes) {
  if (bytes.length > maxAvatarFileBytes) {
    throw const AvatarImageException(AvatarImageError.tooLarge);
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw const AvatarImageException(AvatarImageError.invalid);
  }
  // Di una GIF animata vale il primo fotogramma.
  var image = img.bakeOrientation(decoded.frames.first);
  if (math.max(image.width, image.height) > maxWorkingSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxWorkingSide)
        : img.copyResize(image, height: maxWorkingSide);
  }
  return WorkingImage(img.encodePng(image), image.width, image.height);
}

/// Ritaglia in un isolate [area] dall'immagine di lavoro: un JPEG di
/// [avatarOutputSize] di lato. Le parti trasparenti diventano nere.
Future<Uint8List> cropAvatarImage(Uint8List workingPng, CropArea area) =>
    Isolate.run(() => cropAvatarImageSync(workingPng, area));

/// Come [cropAvatarImage], nel thread di chi chiama. Un riquadro che esce
/// dall'immagine si stringe dentro.
Uint8List cropAvatarImageSync(Uint8List workingPng, CropArea area) {
  final image = img.decodePng(workingPng)!;
  final x = area.left.round().clamp(0, image.width - 1);
  final y = area.top.round().clamp(0, image.height - 1);
  final side =
      area.side.round().clamp(1, math.min(image.width - x, image.height - y));
  final square = img.copyCrop(image, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(
    square,
    width: avatarOutputSize,
    height: avatarOutputSize,
    interpolation: side > avatarOutputSize
        ? img.Interpolation.average
        : img.Interpolation.linear,
  );
  return img.encodeJpg(resized, quality: avatarJpegQuality);
}
```

Crea `lib/features/profiles/avatar_cropper.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'avatar_image.dart';

/// Ingrandimento massimo nel ritaglio (spec K §10.3).
const maxCropZoom = 4.0;

/// Ingrandimento per uno scatto della rotella.
const _wheelStep = 1.1;

/// Opacità del velo fuori dal cerchio.
const _maskAlpha = 0.55;

/// La scala che fa riempire il riquadro all'immagine (zoom 1).
double cropBaseScale(Size image, double viewport) =>
    viewport / math.min(image.width, image.height);

/// L'immagine centrata nel riquadro, a zoom 1.
Offset centeredCropOffset(Size image, double viewport) {
  final scale = cropBaseScale(image, viewport);
  return Offset((viewport - image.width * scale) / 2,
      (viewport - image.height * scale) / 2);
}

/// Lo spostamento più vicino a [offset] con cui l'immagine copre ancora
/// tutto il riquadro.
Offset clampCropOffset(Offset offset, Size image, double viewport, double zoom) {
  final scale = cropBaseScale(image, viewport) * zoom;
  return Offset(
    offset.dx.clamp(math.min(viewport - image.width * scale, 0.0), 0.0),
    offset.dy.clamp(math.min(viewport - image.height * scale, 0.0), 0.0),
  );
}

/// La parte dell'immagine che si vede nel riquadro, in pixel dell'immagine.
CropArea cropAreaFor(Size image, double viewport, double zoom, Offset offset) {
  final scale = cropBaseScale(image, viewport) * zoom;
  return CropArea(-offset.dx / scale, -offset.dy / scale, viewport / scale);
}

/// La parte che si vede all'inizio: l'immagine centrata, a zoom 1.
CropArea initialCropArea(Size image, double viewport) =>
    cropAreaFor(image, viewport, 1, centeredCropOffset(image, viewport));

/// Il ritaglio quadrato (spec K §10.3): l'immagine si trascina e si
/// ingrandisce con la rotella o con il cursore, da "riempie il riquadro" a
/// [maxCropZoom]. A ogni cambio [onChanged] riceve la parte da tenere.
class AvatarCropper extends StatefulWidget {
  const AvatarCropper({
    super.key,
    required this.image,
    required this.viewport,
    required this.onChanged,
  });

  final WorkingImage image;

  /// Lato del riquadro.
  final double viewport;
  final ValueChanged<CropArea> onChanged;

  @override
  State<AvatarCropper> createState() => _AvatarCropperState();
}

class _AvatarCropperState extends State<AvatarCropper> {
  double _zoom = 1;
  late Offset _offset = centeredCropOffset(_size, widget.viewport);

  Size get _size =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  void _update(double zoom, Offset offset) {
    setState(() {
      _zoom = zoom;
      _offset = clampCropOffset(offset, _size, widget.viewport, zoom);
    });
    widget.onChanged(cropAreaFor(_size, widget.viewport, _zoom, _offset));
  }

  /// Ingrandisce tenendo fermo il centro del riquadro.
  void _zoomTo(double zoom) {
    final next = zoom.clamp(1.0, maxCropZoom);
    final center = Offset(widget.viewport / 2, widget.viewport / 2);
    _update(next, center - (center - _offset) * (next / _zoom));
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      _zoomTo(scroll.scrollDelta.dy < 0 ? _zoom * _wheelStep : _zoom / _wheelStep);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scale = cropBaseScale(_size, widget.viewport) * _zoom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            key: const Key('avatar-crop-area'),
            onPanUpdate: (details) => _update(_zoom, _offset + details.delta),
            child: SizedBox.square(
              dimension: widget.viewport,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned(
                      left: _offset.dx,
                      top: _offset.dy,
                      width: _size.width * scale,
                      height: _size.height * scale,
                      child: Image.memory(widget.image.bytes,
                          fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                    // Il cerchio che diventa l'avatar.
                    IgnorePointer(
                      child: CustomPaint(
                          size: Size.square(widget.viewport),
                          painter: _CircleMaskPainter()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: widget.viewport,
          child: Semantics(
            label: l.profileImageZoom,
            child: Slider(value: _zoom, min: 1, max: maxCropZoom, onChanged: _zoomTo),
          ),
        ),
      ],
    );
  }
}

/// Il velo fuori dal cerchio, e il bordo del cerchio.
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect), circle),
      Paint()..color = WfColors.bg.withValues(alpha: _maskAlpha),
    );
    canvas.drawOval(
      rect.deflate(1),
      Paint()
        ..color = WfColors.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter oldDelegate) => false;
}
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/profiles`
Expected: PASS.

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`. `windows/flutter/` resta con i soli cambi veri del plugin nuovo (le fini riga si ripristinano). Poi:

```powershell
git add pubspec.yaml pubspec.lock windows/flutter lib test
git commit -m "feat(app): pick and crop a profile picture"
```

### Task 8: la finestra dell'immagine

**Files:**
- Modify: `lib/features/auth/auth_service.dart`
- Modify: `lib/features/auth/session_controller.dart`
- Create: `lib/features/profiles/avatar_dialog.dart`
- Modify: `lib/features/profiles/profiles_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `test/support/fake_session_controller.dart`
- Modify: `test/features/auth/auth_service_test.dart`
- Modify: `test/features/auth/session_controller_test.dart`
- Create: `test/features/profiles/avatar_dialog_test.dart`
- Modify: `test/features/profiles/profiles_screen_test.dart`
- Modify: `test/features/settings/settings_test.dart`

- [ ] **Step 1: i test della sessione**

In `test/features/auth/auth_service_test.dart` (usa le sue funzioni `anyGetMe`, `bookOf`, `mario`, `luigi`), in fondo a `main`:

```dart
  group('immagine del profilo (spec K §10)', () {
    setUp(() async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
      when(() => anyGetMe(api)).thenAnswer((_) async => testUser);
      await service.openProfile('u1');
    });

    test('clientFor: il client principale per il profilo aperto, '
        'uno con le sue credenziali per gli altri', () {
      expect(service.clientFor('U1'), same(http));
      final other = service.clientFor('u2')!;
      expect(other, isNot(same(http)));
      expect(other.token, 'tok-u2');
      expect(other.deviceId, 'dev-u2');
      expect(service.clientFor('u9'), isNull);
    });

    test('updateStoredProfile: nome e immagine di un profilo non aperto',
        () async {
      final writes = store.writes;
      const luigiNew =
          JellyfinUser(id: 'u2', name: 'Luigi', primaryImageTag: 'img2');

      await service.updateStoredProfile(luigiNew);
      expect(store.book.byId('u2')!.imageTag, 'img2');

      // Uguale: nessun salvataggio.
      await service.updateStoredProfile(luigiNew);
      expect(store.writes, writes + 1);

      // Un utente senza profilo: niente.
      await service.updateStoredProfile(const JellyfinUser(id: 'u9', name: 'X'));
      expect(store.book.byId('u9'), isNull);
    });

    test('markProfileExpired: un profilo non aperto, senza toccare quello '
        'aperto', () async {
      await service.markProfileExpired('u2');

      expect(store.book.byId('u2')!.expired, isTrue);
      expect(service.activeUserId, 'u1');
      expect(http.token, 'tok-u1');
    });
  });
```

In `test/features/auth/session_controller_test.dart` (usa le sue funzioni `controller`, `state`, `signIn` e il finto `auth`), gli import `dart:typed_data`, `package:wonderflix/core/jellyfin/user_image_api.dart` e `../../support/fake_adapter.dart`, poi in fondo a `main`:

```dart
  group('setProfileImage (spec K §10.4)', () {
    late FakeAdapter adapter;
    late JellyfinHttp client;
    final upload = ImageUpload(Uint8List.fromList([1, 2, 3]), 'image/png');

    FakeResponse me(String id, String name, String tag) => FakeResponse(
        200, {'Id': id, 'Name': name, 'PrimaryImageTag': tag});

    setUp(() {
      adapter = FakeAdapter((options) => options.path == '/Users/Me'
          ? me('u1', 'Mario', 'img2')
          : const FakeResponse(204));
      client = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      when(() => auth.updateStoredProfile(any())).thenAnswer((_) async {});
      when(() => auth.markProfileExpired(any())).thenAnswer((_) async {});
    });

    test('profilo aperto: carica, rilegge, aggiorna la sessione e il profilo',
        () async {
      when(() => auth.clientFor('u1')).thenReturn(client);
      signIn(testUser);

      final user = await controller().setProfileImage('u1', image: upload);

      expect(adapter.requests.map((r) => '${r.method} ${r.path}'),
          ['POST /UserImage', 'GET /Users/Me']);
      expect(user!.primaryImageTag, 'img2');
      expect((state() as SessionSignedIn).user.primaryImageTag, 'img2');
      verify(() => auth.updateActiveProfile(user)).called(1);
      verifyNever(() => auth.updateStoredProfile(any()));
    });

    test('profilo non aperto: solo il profilo salvato', () async {
      adapter.handler = (options) => options.path == '/Users/Me'
          ? me('u2', 'Luigi', 'img3')
          : const FakeResponse(204);
      when(() => auth.clientFor('u2')).thenReturn(client);
      final before = state();

      final user = await controller().setProfileImage('u2', image: upload);

      expect(user!.id, 'u2');
      verify(() => auth.updateStoredProfile(user)).called(1);
      expect(state(), same(before));
    });

    test('senza immagine: la toglie', () async {
      when(() => auth.clientFor('u2')).thenReturn(client);

      await controller().setProfileImage('u2');

      expect(adapter.requests.first.method, 'DELETE');
    });

    test('403: lancia, e niente si aggiorna', () async {
      adapter.handler = (_) => const FakeResponse(403);
      when(() => auth.clientFor('u2')).thenReturn(client);

      await expectLater(controller().setProfileImage('u2', image: upload),
          throwsA(isA<ForbiddenException>()));
      verifyNever(() => auth.updateStoredProfile(any()));
      verifyNever(() => auth.markProfileExpired(any()));
    });

    test('401 di un profilo non aperto: scaduto, e lancia', () async {
      adapter.handler = (_) => const FakeResponse(401);
      when(() => auth.clientFor('u2')).thenReturn(client);

      await expectLater(controller().setProfileImage('u2', image: upload),
          throwsA(isA<UnauthorizedException>()));
      verify(() => auth.markProfileExpired('u2')).called(1);
    });

    test('un profilo che non c\'è: niente', () async {
      when(() => auth.clientFor('u9')).thenReturn(null);

      expect(await controller().setProfileImage('u9', image: upload), isNull);
      expect(adapter.requests, isEmpty);
    });
  });
```

- [ ] **Step 2: i test della finestra**

In `test/support/fake_session_controller.dart`, gli import `dart:async` e `package:wonderflix/core/jellyfin/user_image_api.dart`, e nella classe:

```dart
  final profileImageCalls = <(String, ImageUpload?)>[];
  Object? profileImageError;
  Completer<void>? profileImageGate;

  /// L'utente che [setProfileImage] dà, come riletto dal server.
  JellyfinUser? profileImageResult;

  @override
  Future<JellyfinUser?> setProfileImage(String userId,
      {ImageUpload? image}) async {
    profileImageCalls.add((userId, image));
    await profileImageGate?.future;
    final error = profileImageError;
    if (error != null) throw error;
    return profileImageResult;
  }
```

Crea `test/features/profiles/avatar_dialog_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/avatar_cropper.dart';
import 'package:wonderflix/features/profiles/avatar_dialog.dart';
import 'package:wonderflix/features/profiles/avatar_gallery.dart';
import 'package:wonderflix/features/profiles/avatar_image.dart';
import 'package:wonderflix/features/social/avatars_provider.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/avatar_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

/// Il lavoro sulle immagini, senza isolate né `toImage`.
class _FakeTools extends AvatarImageTools {
  Object? prepareError;
  final prepared = <Uint8List>[];
  final cropped = <CropArea>[];

  @override
  Future<Uint8List> renderGallery(GalleryAvatar avatar) async =>
      Uint8List.fromList([7]);

  @override
  Future<WorkingImage> prepare(Uint8List bytes) async {
    prepared.add(bytes);
    final error = prepareError;
    if (error != null) throw error;
    return WorkingImage(
        img.encodePng(img.Image(width: 4, height: 2)), 400, 200);
  }

  @override
  Future<Uint8List> crop(WorkingImage image, CropArea area) async {
    cropped.add(area);
    return Uint8List.fromList([8]);
  }
}

void main() {
  late FakeSessionController session;
  late _FakeTools tools;
  PickedAvatarFile? picked;

  setUp(() {
    tools = _FakeTools();
    picked = null;
  });

  Future<void> openDialog(WidgetTester tester,
      {String? imageTag, List<Override> overrides = const []}) async {
    session = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(showAvatarDialog(context,
              userId: 'u1', name: 'Mario', imageTag: imageTag)),
          child: const Text('apri'),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        avatarImageToolsProvider.overrideWithValue(tools),
        avatarFilePickerProvider.overrideWithValue((label) async => picked),
        ...overrides,
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  VoidCallback? onPressed(WidgetTester tester, String label) =>
      tester.widget<WfButton>(find.widgetWithText(WfButton, label)).onPressed;

  Future<void> chooseGalleryAvatar(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('gallery-3')));
    await tester.pump();
    await tester.tap(find.text('Usa questo'));
    await tester.pump();
  }

  testWidgets('tre schede; "Usa questo" solo con un avatar scelto',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Immagine del profilo'), findsOneWidget);
    expect(find.text('Avatar'), findsOneWidget);
    expect(find.text('Dal PC'), findsOneWidget);
    expect(find.text('Rimuovi'), findsOneWidget);
    expect(onPressed(tester, 'Usa questo'), isNull);

    await tester.tap(find.byKey(const ValueKey('gallery-3')));
    await tester.pump();
    expect(onPressed(tester, 'Usa questo'), isNotNull);
  });

  testWidgets('un avatar della galleria: un PNG, poi la finestra si chiude',
      (tester) async {
    await openDialog(tester);

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    final (userId, upload) = session.profileImageCalls.single;
    expect(userId, 'u1');
    expect(upload!.contentType, 'image/png');
    expect(upload.bytes, [7]);
    expect(find.text('Immagine del profilo'), findsNothing);
  });

  testWidgets('senza permesso: il messaggio, e la finestra resta',
      (tester) async {
    await openDialog(tester);
    session.profileImageError = const ForbiddenException();

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Non hai il permesso di cambiare l\'immagine'),
        findsOneWidget);
    expect(find.text('Immagine del profilo'), findsOneWidget);
  });

  testWidgets('un altro errore: "Caricamento non riuscito"', (tester) async {
    await openDialog(tester);
    session.profileImageError = const ServerErrorException(500);

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Caricamento non riuscito'), findsOneWidget);
  });

  testWidgets('durante il caricamento i pulsanti sono spenti', (tester) async {
    await openDialog(tester);
    final gate = Completer<void>();
    session.profileImageGate = gate;

    await chooseGalleryAvatar(tester);

    expect(onPressed(tester, 'Usa questo'), isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Immagine del profilo'), findsNothing);
  });

  testWidgets('Dal PC: annullato, troppo grande, non valido', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(tools.prepared, isEmpty);

    picked = PickedAvatarFile(
        length: maxAvatarFileBytes + 1, read: () async => Uint8List(0));
    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(find.text('Immagine troppo grande'), findsOneWidget);
    expect(tools.prepared, isEmpty);

    picked = PickedAvatarFile(
        length: 3, read: () async => Uint8List.fromList([1, 2, 3]));
    tools.prepareError = const AvatarImageException(AvatarImageError.invalid);
    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(find.text('Immagine non valida'), findsOneWidget);
  });

  testWidgets('Dal PC: il ritaglio, poi un JPEG', (tester) async {
    picked = PickedAvatarFile(
        length: 3, read: () async => Uint8List.fromList([1, 2, 3]));
    await openDialog(tester);
    await tester.tap(find.text('Dal PC'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scegli un\'immagine…'));
    await tester.pumpAndSettle();
    expect(find.byType(AvatarCropper), findsOneWidget);

    await tester.tap(find.text('Usa questa'));
    await tester.pumpAndSettle();

    // L'immagine di lavoro (400×200) centrata e intera in altezza.
    expect(tools.cropped.single, const CropArea(100, 0, 200));
    final (_, upload) = session.profileImageCalls.single;
    expect(upload!.contentType, 'image/jpeg');
    expect(upload.bytes, [8]);
  });

  testWidgets('Rimuovi: spento senza immagine', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    expect(onPressed(tester, 'Rimuovi immagine'), isNull);
  });

  testWidgets('Rimuovi: con un\'immagine la toglie', (tester) async {
    await openDialog(tester, imageTag: 't1');
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rimuovi immagine'));
    await tester.pumpAndSettle();

    expect(session.profileImageCalls.single, ('u1', null));
  });

  testWidgets('dopo il caricamento la cache degli avatar ha l\'immagine nuova',
      (tester) async {
    final api = FakeAvatarsApi();
    final directory = AvatarDirectory(api);
    await openDialog(tester,
        overrides: [avatarDirectoryProvider.overrideWithValue(directory)]);
    session.profileImageResult =
        const JellyfinUser(id: 'u1', name: 'Mario', primaryImageTag: 't9');

    await chooseGalleryAvatar(tester);
    await tester.pumpAndSettle();

    AvatarImage? image;
    unawaited(directory
        .imageFor(AvatarLookup.byName('mario'))
        .then((value) => image = value));
    await tester.pump();
    expect(image, const AvatarImage('u1', 't9'));
    expect(api.calls, isEmpty);
  });
}
```

In `test/features/profiles/profiles_screen_test.dart` (usa la sua funzione `pumpProfiles` e i profili di prova del file), in fondo a `main`:

```dart
  testWidgets('Gestisci profili: la matita apre la finestra dell\'immagine; '
      'spenta per un profilo scaduto', (tester) async {
    await pumpProfiles(tester, [
      testProfile(userId: 'u1', name: 'Mario'),
      testProfile(userId: 'u2', name: 'Luigi', expired: true),
    ]);
    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();

    final expired = tester
        .widget<IconButton>(find.byKey(const ValueKey('profile-image-u2')));
    expect(expired.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('profile-image-u1')));
    await tester.pumpAndSettle();
    expect(find.text('Immagine del profilo'), findsOneWidget);
  });
```

In `test/features/settings/settings_test.dart`, nel test `schermata: utente, lingua, versione, esci`, dopo `expect(find.text('Accesso come Mario'), findsOneWidget);` (import `package:wonderflix/ui/user_avatar.dart`):

```dart
    expect(find.byType(UserAvatar), findsOneWidget);
    await tester.tap(find.text('Cambia immagine'));
    await tester.pumpAndSettle();
    expect(find.text('Immagine del profilo'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
```

(il clic fuori chiude la finestra, come Esc).

- [ ] **Step 3: i test non compilano**

Run: `flutter test test/features/auth test/features/profiles test/features/settings`
Expected: errori di compilazione (`clientFor`, `setProfileImage`, `avatar_dialog.dart`).

- [ ] **Step 4: la sessione**

In `lib/features/auth/auth_service.dart`, dopo `updateActiveProfile`:

```dart
  /// Il client per le chiamate del profilo [userId] (spec K §10.1): quello
  /// principale per il profilo aperto, altrimenti uno con le credenziali del
  /// profilo (che non segnala i 401). `null` se il profilo non c'è.
  JellyfinHttp? clientFor(String userId) {
    final active = _activeUserId;
    if (active != null && jellyfinIdKey(active) == jellyfinIdKey(userId)) {
      return _http;
    }
    final profile = _book.byId(userId);
    return profile == null
        ? null
        : _http.withCredentials(
            token: profile.accessToken, deviceId: profile.deviceId);
  }

  /// Nome e immagine di un profilo salvato, anche non aperto (spec K
  /// §10.4), solo se cambiano.
  Future<void> updateStoredProfile(JellyfinUser user) async {
    final profile = _book.byId(user.id);
    if (profile == null ||
        (profile.name == user.name &&
            profile.imageTag == user.primaryImageTag)) {
      return;
    }
    await _save(_book.upsert(
        profile.copyWith(name: user.name, imageTag: user.primaryImageTag)));
  }

  /// Un profilo non aperto il cui token il server ha rifiutato (401):
  /// "Accedi di nuovo" in "Chi guarda?".
  Future<void> markProfileExpired(String userId) async {
    final profile = _book.byId(userId);
    if (profile == null || profile.expired) return;
    await _save(_book.upsert(profile.copyWith(expired: true)));
  }
```

In `lib/features/auth/session_controller.dart` (import `../../core/jellyfin/auth_api.dart`, `../../core/jellyfin/user_image_api.dart` e, se manca, `../../core/jellyfin/json_fields.dart`), dopo `removeProfile`:

```dart
  /// Cambia o toglie l'immagine di un profilo salvato (spec K §10.4): con
  /// [image] la carica, senza la toglie, con le credenziali di quel profilo.
  /// Poi rilegge l'utente e aggiorna il profilo (e la sessione, se è quello
  /// aperto). Dà l'utente riletto; `null` se il profilo non c'è.
  ///
  /// Lancia `ApiException`: 403 senza il permesso, 401 se il token non vale
  /// più. Un profilo non aperto si segna scaduto; per quello aperto ci pensa
  /// già il client (`_onUnauthorized`).
  Future<JellyfinUser?> setProfileImage(String userId,
      {ImageUpload? image}) async {
    final client = _auth.clientFor(userId);
    if (client == null) return null;
    final active = _auth.activeUserId;
    final isActive =
        active != null && jellyfinIdKey(active) == jellyfinIdKey(userId);
    try {
      final images = UserImageApi(client);
      if (image == null) {
        await images.remove(userId);
      } else {
        await images.upload(userId, image);
      }
      final user = await AuthApi(client).getMe();
      if (isActive) {
        final current = state;
        if (current is SessionSignedIn &&
            jellyfinIdKey(current.user.id) == jellyfinIdKey(user.id)) {
          _apply(SessionSignedIn(user));
        }
        await _auth.updateActiveProfile(user);
      } else {
        await _auth.updateStoredProfile(user);
      }
      _publishProfiles();
      return user;
    } on UnauthorizedException {
      if (!isActive) {
        await _auth.markProfileExpired(userId);
        _publishProfiles();
      }
      rethrow;
    }
  }
```

- [ ] **Step 5: la finestra**

Crea `lib/features/profiles/avatar_dialog.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/user_image_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../social/avatars_provider.dart';
import 'avatar_cropper.dart';
import 'avatar_gallery.dart';
import 'avatar_image.dart';

/// Larghezza della finestra.
const _dialogWidth = 560.0;

/// Altezza delle schede: la galleria (4 righe) o il ritaglio con i pulsanti.
const _tabHeight = 380.0;

/// Lato di un avatar nella galleria.
const _galleryTileSize = 56.0;

/// Avatar per riga nella galleria.
const _galleryColumns = 6;

/// Lato del riquadro del ritaglio.
const _cropViewport = 240.0;

/// Lato dell'anteprima nella scheda "Rimuovi".
const _previewSize = 120.0;

/// Spessore del bordo dell'avatar scelto.
const _selectedBorder = 3.0;

/// Un file scelto: la dimensione si legge prima del contenuto.
class PickedAvatarFile {
  const PickedAvatarFile({required this.length, required this.read});

  final int length;
  final Future<Uint8List> Function() read;
}

/// Sceglie un'immagine dal PC; `null` se si annulla. [label] è il nome del
/// filtro nella finestra di Windows.
typedef AvatarFilePicker = Future<PickedAvatarFile?> Function(String label);

/// Con `file_selector` (nei test si sostituisce: apre una finestra di
/// sistema).
final avatarFilePickerProvider = Provider<AvatarFilePicker>((ref) => (label) async {
      final file = await openFile(acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: avatarFileExtensions),
      ]);
      if (file == null) return null;
      return PickedAvatarFile(length: await file.length(), read: file.readAsBytes);
    });

/// Il lavoro sulle immagini: isolate e `toImage`, che nei widget test si
/// sostituiscono.
class AvatarImageTools {
  const AvatarImageTools();

  Future<Uint8List> renderGallery(GalleryAvatar avatar) =>
      renderGalleryAvatar(avatar);

  Future<WorkingImage> prepare(Uint8List bytes) => prepareAvatarImage(bytes);

  Future<Uint8List> crop(WorkingImage image, CropArea area) =>
      cropAvatarImage(image.bytes, area);
}

final avatarImageToolsProvider =
    Provider<AvatarImageTools>((ref) => const AvatarImageTools());

/// Apre la finestra dell'immagine del profilo [userId] (spec K §10.1).
Future<void> showAvatarDialog(
  BuildContext context, {
  required String userId,
  required String name,
  required String? imageTag,
}) =>
    showWfDialog<void>(
      context,
      maxWidth: _dialogWidth,
      semanticLabel: AppLocalizations.of(context).profileImageTitle,
      builder: (context) =>
          AvatarDialog(userId: userId, name: name, imageTag: imageTag),
    );

/// La finestra dell'immagine del profilo (spec K §10.1): le schede Avatar,
/// Dal PC e Rimuovi. Mentre carica i pulsanti sono spenti; riuscita, si
/// chiude; con un errore resta aperta con il messaggio.
class AvatarDialog extends ConsumerStatefulWidget {
  const AvatarDialog({
    super.key,
    required this.userId,
    required this.name,
    required this.imageTag,
  });

  final String userId;
  final String name;
  final String? imageTag;

  @override
  ConsumerState<AvatarDialog> createState() => _AvatarDialogState();
}

class _AvatarDialogState extends ConsumerState<AvatarDialog> {
  int? _selected;
  WorkingImage? _working;
  CropArea? _area;
  bool _busy = false;
  String? _error;

  AvatarImageTools get _tools => ref.read(avatarImageToolsProvider);

  /// Prepara l'immagine (`null`: la toglie) e la manda al server.
  Future<void> _save(Future<ImageUpload?> Function() prepare) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(sessionControllerProvider.notifier)
          .setProfileImage(widget.userId, image: await prepare());
      if (user != null) {
        ref
            .read(avatarDirectoryProvider)
            ?.remember(userId: user.id, name: user.name, tag: user.primaryImageTag);
        ref.invalidate(avatarImageProvider);
      }
      if (mounted) Navigator.of(context).pop();
    } on UnauthorizedException {
      // Il profilo è scaduto: la finestra si chiude, e "Chi guarda?" lo
      // mostra con "Accedi di nuovo".
      if (mounted) Navigator.of(context).pop();
    } on ForbiddenException {
      if (mounted) setState(() => _error = l.profileImageForbidden);
    } on Object {
      if (mounted) setState(() => _error = l.profileImageFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final l = AppLocalizations.of(context);
    final file = await ref.read(avatarFilePickerProvider)(l.profileImageFiles);
    if (file == null || !mounted) return;
    if (file.length > maxAvatarFileBytes) {
      setState(() => _error = l.profileImageTooLarge);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final working = await _tools.prepare(await file.read());
      if (!mounted) return;
      setState(() {
        _working = working;
        _area = initialCropArea(
            Size(working.width.toDouble(), working.height.toDouble()),
            _cropViewport);
      });
    } on AvatarImageException catch (error) {
      if (mounted) {
        setState(() => _error = error.reason == AvatarImageError.tooLarge
            ? l.profileImageTooLarge
            : l.profileImageInvalid);
      }
    } on Object {
      if (mounted) setState(() => _error = l.profileImageInvalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = _error;
    return DefaultTabController(
      length: 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.profileImageTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TabBar(tabs: [
            Tab(text: l.profileImageAvatars),
            Tab(text: l.profileImageFromPc),
            Tab(text: l.profilesRemove),
          ]),
          const SizedBox(height: 16),
          if (error != null) ...[
            ErrorBanner(error),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: _tabHeight,
            child: TabBarView(
                children: [_galleryTab(l), _fileTab(l), _removeTab(l)]),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _galleryTab(AppLocalizations l) {
    final selected = _selected;
    return Column(
      children: [
        Expanded(
          child: GridView.count(
            crossAxisCount: _galleryColumns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var i = 0; i < galleryAvatars.length; i++)
                _GalleryTile(
                  key: ValueKey('gallery-$i'),
                  avatar: galleryAvatars[i],
                  selected: selected == i,
                  onTap: _busy ? null : () => setState(() => _selected = i),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: WfButton.primary(
            label: l.profileImageUseAvatar,
            icon: LucideIcons.check,
            onPressed: _busy || selected == null
                ? null
                : () => unawaited(_save(() async => ImageUpload(
                    await _tools.renderGallery(galleryAvatars[selected]),
                    'image/png'))),
          ),
        ),
      ],
    );
  }

  Widget _fileTab(AppLocalizations l) {
    final working = _working;
    final area = _area;
    if (working == null) {
      return Center(
        child: WfButton.secondary(
          label: l.profileImageChoose,
          icon: LucideIcons.imagePlus,
          onPressed: _busy ? null : () => unawaited(_pick()),
        ),
      );
    }
    return Column(
      children: [
        AvatarCropper(
          key: ObjectKey(working),
          image: working,
          viewport: _cropViewport,
          // Serve solo al clic su "Usa questa": niente setState.
          onChanged: (next) => _area = next,
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => unawaited(_pick()),
              child: Text(l.profileImageChoose),
            ),
            const SizedBox(width: 12),
            WfButton.primary(
              label: l.profileImageUseFile,
              icon: LucideIcons.check,
              onPressed: _busy || area == null
                  ? null
                  : () => unawaited(_save(() async => ImageUpload(
                      await _tools.crop(working, _area!), 'image/jpeg'))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _removeTab(AppLocalizations l) => Column(
        children: [
          const SizedBox(height: 24),
          UserAvatar(
            userId: widget.userId,
            name: widget.name,
            size: _previewSize,
            imageTag: widget.imageTag,
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: WfButton.secondary(
              label: l.profileImageRemove,
              icon: LucideIcons.trash2,
              onPressed: _busy || widget.imageTag == null
                  ? null
                  : () => unawaited(_save(() async => null)),
            ),
          ),
        ],
      );
}

/// Un avatar della galleria: si sceglie con un clic, il bordo dorato dice
/// quale.
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    super.key,
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final GalleryAvatar avatar;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        focusColor: WfColors.gold.withValues(alpha: 0.18),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? WfColors.gold : Colors.transparent,
              width: _selectedBorder,
            ),
          ),
          padding: const EdgeInsets.all(_selectedBorder),
          child: GalleryAvatarView(avatar: avatar, size: _galleryTileSize),
        ),
      );
}
```

`Colors.transparent` è l'unico colore fuori da `WfColors`: è l'assenza del bordo. Se l'analyzer o una regola del progetto lo vieta, usa `WfColors.bg.withValues(alpha: 0)`.

- [ ] **Step 6: dove si apre**

In `lib/features/profiles/profiles_screen.dart` (import `avatar_dialog.dart`), nello `Stack` di `_ProfileCard`, accanto al pulsante "Rimuovi" (`if (managing) Positioned(top: 0, right: 0, …)`):

```dart
                    if (managing)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: IconButton(
                          key: ValueKey('profile-image-${profile.userId}'),
                          tooltip: l.profilesEditImage,
                          style: IconButton.styleFrom(
                              backgroundColor: WfColors.surfaceHigh),
                          // Un profilo scaduto non ha un token valido.
                          onPressed: profile.expired
                              ? null
                              : () => unawaited(showAvatarDialog(context,
                                  userId: profile.userId,
                                  name: name,
                                  imageTag: profile.imageTag)),
                          icon: const Icon(LucideIcons.pencil,
                              color: WfColors.cream),
                        ),
                      ),
```

In `lib/features/settings/settings_screen.dart` (import `../../ui/user_avatar.dart` e `../profiles/avatar_dialog.dart`):
- in cima al file:

```dart
/// Diametro dell'avatar in Impostazioni → Account.
const _accountAvatarSize = 64.0;
```

- nella sezione Account, al posto di `if (session is SessionSignedIn) Text(l.settingsSignedInAs(session.user.name)),`:

```dart
              if (session is SessionSignedIn)
                Row(
                  children: [
                    UserAvatar(
                      userId: session.user.id,
                      name: session.user.name,
                      size: _accountAvatarSize,
                      imageTag: session.user.primaryImageTag,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(l.settingsSignedInAs(session.user.name))),
                  ],
                ),
```

- nel `Wrap` dei pulsanti, come primo:

```dart
                  if (session is SessionSignedIn)
                    WfButton.secondary(
                      label: l.settingsChangeImage,
                      icon: LucideIcons.imagePlus,
                      onPressed: () => unawaited(showAvatarDialog(context,
                          userId: session.user.id,
                          name: session.user.name,
                          imageTag: session.user.primaryImageTag)),
                    ),
```

- [ ] **Step 7: i test passano**

Run: `flutter test test/features/auth test/features/profiles test/features/settings`
Expected: PASS.

- [ ] **Step 8: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): change the profile picture"
```

## Gruppo D — avatar ovunque

### Task 9: `UserAvatar` al posto delle iniziali

**Files:**
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/profiles/profiles_screen.dart`
- Modify: `lib/features/watch_party/party_badge.dart`
- Modify: `lib/features/watch_party/party_invite_menu.dart`
- Modify: `lib/features/watch_party/party_chat_bubble.dart`
- Modify: `lib/features/friends/friends_panel.dart`
- Modify: `lib/features/friends/friend_request_card.dart`
- Modify: `lib/features/admin/admin_widgets.dart`
- Modify: `lib/features/admin/sessions_tab.dart`
- Modify: `test/support/avatar_fakes.dart`
- Modify: i test dei widget toccati (vedi Step 1)
- Create: `test/features/admin/admin_user_line_test.dart`

- [ ] **Step 1: i test**

In `test/support/avatar_fakes.dart` aggiungi (import `package:flutter/widgets.dart`, `package:flutter_riverpod/misc.dart`, `package:wonderflix/features/social/avatars_provider.dart` e `package:wonderflix/ui/wf_image.dart`):

```dart
/// Sostituisce il disegno delle immagini e ne registra gli indirizzi.
Override captureImageUrls(List<String> urls) =>
    imageBuilderProvider.overrideWithValue((image, fit) {
      urls.add(image.url);
      return const SizedBox.expand();
    });

/// Una cache degli avatar che conosce [users] (come con un profilo aperto e
/// la funzione `avatars`).
Override avatarsFor(List<UserAvatarInfo> users) =>
    avatarDirectoryProvider
        .overrideWithValue(AvatarDirectory(FakeAvatarsApi()..users = users));
```

I test nuovi aggiungono questi due override a quelli che il file usa già, e il loro indirizzo atteso è sempre `https://media.example.com/UserImage?userId=<id>&tag=<tag>`. Per gli avatar cercati, dopo il primo `pump` serve `await tester.pump(AvatarDirectory.defaultBatchDelay); await tester.pump();`.

1. **Menu dell'avatar** (`test/app/app_shell_test.dart`), con lo stesso `pumpApp` dei test che ci sono:

```dart
  testWidgets('l\'avatar del menu è l\'immagine dell\'utente', (tester) async {
    final urls = <String>[];
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            const SessionSignedIn(
                JellyfinUser(id: 'u1', name: 'Mario', primaryImageTag: 't1')))),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        captureImageUrls(urls),
      ],
    );

    expect(urls, contains('https://media.example.com/UserImage?userId=u1&tag=t1'));
  });
```

2. **"Chi guarda?"** (`test/features/profiles/profiles_screen_test.dart`): con `pumpProfiles` e un profilo `testProfile(userId: 'u1', name: 'Mario', imageTag: 't1')` (aggiungi `captureImageUrls(urls)` agli override del helper, per esempio con un parametro `overrides`): l'indirizzo con `u1` e `t1` c'è; un profilo senza `imageTag` mostra la sua iniziale.

3. **Badge del party** (`test/features/watch_party/party_badge_test.dart`):

```dart
  testWidgets('i membri con un\'immagine la mostrano, cercati per nome',
      (tester) async {
    final urls = <String>[];
    await pumpApp(tester, const MemberAvatarStack(members: ['Mario', 'Luigi']),
        overrides: [
          captureImageUrls(urls),
          avatarsFor(const [
            UserAvatarInfo(userId: 'u1', name: 'Mario', imageTag: 't1'),
          ]),
        ]);
    await tester.pump(AvatarDirectory.defaultBatchDelay);
    await tester.pump();

    expect(urls.toSet(), {'https://media.example.com/UserImage?userId=u1&tag=t1'});
    // Luigi non ha un'immagine: l'iniziale.
    expect(find.text('L'), findsOneWidget);
  });
```

4. **Pannello amici** (`test/features/friends/friends_panel_test.dart`): con il pannello aperto come negli altri test, un amico `testFriend('u2', 'Luigi')` e `avatarsFor(const [UserAvatarInfo(userId: 'u2', name: 'Luigi', imageTag: 't2')])`: c'è l'indirizzo con `u2` e `t2` (cercato per id), e il pallino `online-dot` resta.

5. **Chat del party:** nel test che c'è per `PartyChatMessage` (o in uno nuovo accanto, costruendo il messaggio come fanno i test della chat), il messaggio ha un `UserAvatar` (`find.byType(UserAvatar)`), e con `avatarsFor` dell'utente del messaggio c'è il suo indirizzo. **I test che cercano il testo intero di un messaggio** (`find.text('Mario  ciao')` e simili) ora trovano anche il segnaposto dell'avatar: usa `find.textContaining(…)` o `find.text(…, findRichText: true)` sul pezzo che serve.

6. **Richiesta d'amicizia** (`test/features/friends/friend_request_card_test.dart`): la scheda ha un `UserAvatar` al posto dell'icona `userPlus`, e con `avatarsFor` del mittente c'è il suo indirizzo (cercato per id).

7. Crea `test/features/admin/admin_user_line_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';

import '../../support/avatar_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('l\'immagine dell\'utente della sessione, dal tag di Jellyfin',
      (tester) async {
    final urls = <String>[];
    await pumpApp(
        tester,
        const AdminUserLine(
            name: 'Mario', detail: 'PC', userId: 'u1', imageTag: 't1'),
        overrides: [captureImageUrls(urls)]);

    expect(urls.last, 'https://media.example.com/UserImage?userId=u1&tag=t1');
    expect(find.text('Mario'), findsOneWidget);
  });

  testWidgets('senza tag: l\'iniziale', (tester) async {
    final urls = <String>[];
    await pumpApp(tester, const AdminUserLine(name: 'Mario', userId: 'u1'),
        overrides: [captureImageUrls(urls)]);

    expect(urls, isEmpty);
    expect(find.text('M'), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test non passano**

Run: `flutter test test/app/app_shell_test.dart test/features/profiles test/features/watch_party test/features/friends test/features/admin`
Expected: i test nuovi falliscono (nessun indirizzo `UserImage`) o non compilano (`AdminUserLine` senza `userId`).

- [ ] **Step 3: il codice**

**`MemberAvatar`** (`lib/features/watch_party/party_badge.dart`, import `../../ui/user_avatar.dart`) diventa un uso di `UserAvatar.lookup`, con lo stesso diametro e lo stesso stile di oggi:

```dart
/// L'avatar di un membro del party o di un amico (spec K §10.5): l'immagine
/// dell'utente, cercata per id o, senza id, per nome (SyncPlay dà solo i
/// nomi); altrimenti l'iniziale.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.name, this.userId});

  final String name;
  final String? userId;

  @override
  Widget build(BuildContext context) => UserAvatar.lookup(
        userId: userId,
        name: name,
        size: MemberAvatarStack.avatarSize,
        muted: true,
      );
}
```

**Menu degli inviti** (`party_invite_menu.dart`): `MemberAvatar(name: friend.name, userId: friend.userId)`.

**Riga degli amici** (`lib/features/friends/friends_panel.dart`), `_PersonRow`:
- il campo, con il parametro `required this.userId,` nel costruttore:

```dart
  /// L'utente: l'avatar si cerca per id.
  final String userId;
```

- `MemberAvatar(name: name, userId: userId)`;
- i quattro chiamanti passano l'id che hanno già: `result.userId` (ricerca), `person.userId` (richieste ricevute e inviate), `widget.friend.userId` (`_FriendRow`).

**Menu dell'avatar** (`lib/app/app_shell.dart`, import `../ui/user_avatar.dart`):
- in cima al file:

```dart
/// Diametro dell'avatar del menu.
const _menuAvatarSize = 30.0;
```

- in `_UserMenu` togli `final initial = …` e, al posto del `CircleAvatar`:

```dart
            UserAvatar(
              userId: user.id,
              name: user.name,
              size: _menuAvatarSize,
              imageTag: user.primaryImageTag,
            ),
```

**"Chi guarda?"** (`profiles_screen.dart`, import `../../ui/user_avatar.dart`): al posto di `_InitialAvatar(name: profile.name)`:

```dart
                        child: UserAvatar(
                          userId: profile.userId,
                          name: profile.name,
                          size: profileAvatarSize,
                          imageTag: profile.imageTag,
                        ),
```

e togli la classe `_InitialAvatar`.

**Chat** (`lib/features/watch_party/party_chat_bubble.dart`, import `../../ui/user_avatar.dart`):
- in cima:

```dart
/// Diametro dell'avatar accanto al nome nella chat.
const partyChatAvatarSize = 18.0;
```

- in `PartyChatMessage.build`, primo figlio del `TextSpan`:

```dart
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: UserAvatar.lookup(
                userId: entry.event.userId,
                name: entry.event.userName,
                size: partyChatAvatarSize,
                muted: true,
              ),
            ),
          ),
```

**Richiesta d'amicizia** (`lib/features/friends/friend_request_card.dart`, import `../../ui/user_avatar.dart`):
- in cima:

```dart
/// Diametro dell'avatar di chi chiede l'amicizia.
const _requestAvatarSize = 24.0;

/// Spazio tra l'avatar e il titolo; i pulsanti si allineano al titolo.
const _requestAvatarGap = 8.0;
```

- al posto di `const Icon(LucideIcons.userPlus, …)` e del `SizedBox(width: 8)` che lo segue:

```dart
                  UserAvatar.lookup(
                    userId: request.fromUserId,
                    name: request.fromName,
                    size: _requestAvatarSize,
                    muted: true,
                  ),
                  const SizedBox(width: _requestAvatarGap),
```

- il rientro dei pulsanti: `padding: const EdgeInsets.only(left: _requestAvatarSize + _requestAvatarGap),`.

**Sessioni dell'admin** (`lib/features/admin/admin_widgets.dart`, import `../../ui/user_avatar.dart`):
- in cima:

```dart
/// Diametro dell'avatar di una riga utente.
const _adminAvatarSize = 28.0;
```

- `AdminUserLine` prende anche l'utente e il tag:

```dart
  const AdminUserLine({
    super.key,
    required this.name,
    this.detail = '',
    this.userId,
    this.imageTag,
  });

  final String name;
  final String detail;

  /// Con [imageTag], l'immagine dell'utente (spec K §10.5): il tag lo dà
  /// Jellyfin con la sessione.
  final String? userId;
  final String? imageTag;
```

- in `build` togli `final initial = …` e, al posto del `CircleAvatar`:

```dart
        UserAvatar(
          userId: userId,
          name: name,
          size: _adminAvatarSize,
          imageTag: imageTag,
        ),
```

- in `lib/features/admin/sessions_tab.dart` (~150 e ~223) i due `AdminUserLine` passano anche `userId: session.userId, imageTag: session.userImageTag`.

- [ ] **Step 4: i test passano**

Run: `flutter test test/app test/features test/ui`
Expected: PASS (i test che cercano un'iniziale, come `find.text('M')`, la trovano ancora: senza immagine resta l'iniziale).

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): user pictures instead of initials"
```

## Gruppo E — chiusura

### Task 10: allineamento della spec, checklist, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md`
- Modify: `docs/superpowers/plans/2026-10-08-wonderflix-17c-immagini.md` (solo la decisione "Dalle review dei gruppi", se ci sono differenze)
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "piano 17c realizzato (`docs/superpowers/plans/2026-10-08-wonderflix-17c-immagini.md`); release da fare" (la release la segna il commit della release).
- **§6:** i file veri delle immagini: `avatar_gallery.dart`, `avatar_image.dart`, `avatar_cropper.dart`, `avatar_dialog.dart` in `lib/features/profiles/`; `lib/features/social/avatars_provider.dart` (`AvatarLookup`, `AvatarImage`, `AvatarDirectory`, `avatarDirectoryProvider`, `avatarImageProvider`); `lib/core/social/avatars_api.dart`; `lib/core/jellyfin/user_image_api.dart` (`ImageUpload`); `lib/ui/user_avatar.dart`. Togli "indicativi".
- **§7.2:** come risponde davvero:
  - utenti elencati una volta e confrontati in memoria;
  - gli id che non sono GUID e le voci vuote si ignorano;
  - oltre 100 voci, 400;
  - un `ImageTag` nullo manca dal JSON del server vero.
- **§10.1–§10.3:**
  - le schede e i testi veri;
  - la matita spenta per un profilo scaduto;
  - la galleria con l'uccello al posto del gufo;
  - l'immagine di lavoro (EXIF, 2048 px, PNG), la GIF animata (primo fotogramma), la trasparenza (nera nel JPEG);
  - il ritaglio con la rotella (1,1× a scatto) e il cursore.
- **§10.4:**
  - il base64 è verificato nel sorgente di Jellyfin 10.11.9 (non più "da verificare");
  - `SessionController.setProfileImage` e `AuthService.clientFor`, `updateStoredProfile`, `markProfileExpired`;
  - un 401 di un profilo non aperto lo segna scaduto e chiude la finestra.
- **§10.5:**
  - i due costruttori di `UserAvatar` e lo stile `muted`;
  - `AvatarLookup` per id o per nome;
  - la cache solo con un profilo aperto e la funzione `avatars`, nuova a ogni profilo;
  - le sessioni dell'admin con il tag di Jellyfin (`UserPrimaryImageTag`);
  - `GET /UserImage` anonimo e senza ridimensionamento.
- **§11:** i testi veri (chiavi `profileImage…`, `profilesEditImage`, `settingsChangeImage`); la scheda "Rimuovi" usa `profilesRemove`.
- **§13:** i test delle immagini che esistono davvero.
- **§14:** il base64 e `GetImageCacheTag` sono verificati (il secondo nel Task 2, sul server).
- **§15:** 17c realizzato; la release è il passo successivo.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze (come nei piani 17a e 17b).

- [ ] **Step 2: la checklist**

In `docs/RELEASING.md`, nella checklist dei test a mano, dopo le voci dei profili, aggiungi (in italiano, nello stesso stile):
- immagine del profilo dalla galleria, da un file (con il ritaglio) e rimozione, da Impostazioni e da "Gestisci profili";
- le immagini degli altri: amici, inviti, party (fila, menu, chat), richiesta d'amicizia, sessioni dell'admin;
- con il plugin senza `avatars`: solo iniziali, nessun errore.

- [ ] **Step 3: build**

`config/wonderflix.json` deve esserci nel worktree (`config/`); se manca, fermati e segnalalo. Poi:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Non lanciare l'app.

- [ ] **Step 4: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add docs
git commit -m "docs: align the sagas and profiles spec with plan 17c"
```

### Task 11: prova a mano (orchestratore e utente)

L'utente avvia la build del Task 10 **da Esplora file** (un'app lanciata da Claude scrive AppData in una cartella separata). Sul server c'è la build di prova 1.5.0.0 del Task 2.

1. **Galleria:** Impostazioni → "Cambia immagine" → Avatar → un'icona → "Usa questo". L'immagine compare subito nel menu, in Impostazioni e, dopo un riavvio, in "Chi guarda?". In jellyfin-web l'utente ha la stessa immagine.
2. **Dal PC:**
   - un JPEG, un PNG e una foto del telefono (girata, con l'EXIF): il ritaglio la mostra dritta, la rotella e il cursore ingrandiscono, "Usa questa" la carica;
   - un file oltre 20 MB: "Immagine troppo grande";
   - un file che non è un'immagine (rinominato in `.jpg`): "Immagine non valida".
3. **Rimuovi:** "Rimuovi immagine" torna all'iniziale, anche in jellyfin-web.
4. **"Chi guarda?" → "Gestisci profili" → matita** su un profilo non aperto: l'immagine cambia per quel profilo. Su un profilo scaduto la matita è spenta.
5. **Gli altri:** con la seconda istanza (`WONDERFLIX_PROFILE=b`, un altro account) in un party insieme:
   - l'immagine di A si vede nella fila del party, nel suo menu e nella chat;
   - si vede negli amici, negli inviti e nella richiesta d'amicizia;
   - si vede nelle sessioni dell'admin.
6. **Senza immagine:** chi non ce l'ha resta con l'iniziale, dappertutto.

Con l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`), poi la release.

## Release (orchestratore, dopo il merge)

Ogni passo che pubblica (push dei tag, manifest, pubblicazione della release) va fatto con l'ok dell'utente.

1. **Plugin 1.5.0** (vedi `docs/RELEASING.md`, sezione del plugin):
   - il csproj è già a `1.5.0`;
   - `git tag watch-party-plugin-v1.5.0` e push del tag. Il workflow pubblica una **pre-release** con `wonderflix-watch-party_1.5.0.zip` e `.zip.md5`; `releases/latest` resta l'app;
   - **controllo dei riferimenti** della dll della release contro Jellyfin 10.11.9 (progetto `refprobe` nella scratchpad, da ricreare: console `net9.0`, `FrameworkReference Microsoft.AspNetCore.App`, `Jellyfin.Controller`/`Jellyfin.Model` 10.11.9, risoluzione di ogni `TypeReference`/`MemberReference`). Atteso: 0 non risolti;
   - in `jellyfin-plugin-watch-party/manifest.json`, una voce in cima a `versions`:
     - `"version": "1.5.0.0"`, `"targetAbi": "10.11.0.0"`;
     - `sourceUrl` della pre-release, `checksum` uguale al contenuto del `.md5`, `timestamp` in UTC;
     - `changelog` in italiano, per esempio: "Saghe per WonderFlix 0.11.0: le collezioni di Jellyfin con i loro film (riga «Fa parte di», pagina della saga, vista Saghe, ricerca). Immagini degli utenti per amici, party e chat.";
   - aggiorna la `description` in inglese (aggiungi "collections (sagas) and user pictures") e anche l'`overview` (aggiungi "collections, user pictures"), come in `meta.template.json`;
   - commit `chore: publish the watch party plugin 1.5.0`, push.
2. **Server:**
   - controlla che nessuno stia guardando;
   - `app-jellyfin stop`;
   - sposta la cartella di prova `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.5.0.0` in `~/wfwp-backup/1.5.0.0-manuale` (altrimenti il Catalogo non la sostituirebbe mai: ha la stessa versione);
   - `app-jellyfin start`;
   - l'utente installa 1.5.0 da Dashboard → Plugin → Catalogo;
   - riavvio, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.5.0.0"`, e l'md5 della dll uguale a quello della dll nello zip.
3. **App 0.11.0, non obbligatoria** (vedi `docs/RELEASING.md`, sezione dell'app):
   - versione nel `pubspec.yaml`, commit `chore: release 0.11.0`, tag `v0.11.0`, push;
   - il workflow crea la bozza con `WonderFlix-Setup-0.11.0.exe` e `.sha256`;
   - le note in italiano le scrivo io nella bozza, senza `min-version`. Devono dire:
     - le saghe;
     - i profili "Chi guarda?", con la migrazione automatica (nessun nuovo accesso);
     - le immagini del profilo e degli altri;
     - che saghe e immagini degli altri vogliono il plugin 1.5.0 (senza, l'app funziona con le iniziali);
   - la pubblica l'utente.
4. **`docs/IDEE.md`:**
   - dall'idea 3 escono collezioni e profili, e resta il download offline;
   - tra le fatte entra "Spec K — saghe e profili (plugin 1.5.0, app 0.11.0)";
   - commit `docs: Spec K done in the ideas list`, push.
