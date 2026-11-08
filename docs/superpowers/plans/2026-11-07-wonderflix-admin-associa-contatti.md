# L'admin associa Discord ed email — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dal menu ⋮ della tab Utenti l'admin associa a un utente un Discord (cercato dal bot, con anteprima) o un'email, che valgono subito per il recupero.

**Architecture:** il plugin aggiunge a `AccountAdmin` una ricerca Discord e due salvataggi senza password né codice, esposti da `AccountAdminController`, e la funzione `accountAdminLink` in `Info`. L'app aggiunge tre chiamate a `PluginAdminApi`, due azioni al menu della riga e due dialoghi.

**Tech Stack:** .NET 9 (plugin Jellyfin 10.11, xUnit), Flutter 3.47.5 (Riverpod 3, dio).

**Spec:** `docs/superpowers/specs/2026-11-07-wonderflix-admin-associa-contatti-design.md`

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/associa-contatti`, branch `associa-contatti`.
- Plugin **1.24.0**, app **0.33.0**.
- Nessun avviso all'utente quando l'admin associa un contatto; nessuna password dell'admin, nessun limite di frequenza.
- Log: mai il nome Discord né l'indirizzo email, solo gli id (`userId.ToString("N")`, `AdminCaller.Describe(adminId)`).
- Errori con `AccountErrors.Result` com'è (400 `UnknownUser`/`InvalidTarget`/`MemberNotFound`, 503 `ChannelOff`, 502 `SendFailed`).
- Commenti e messaggi di commit in italiano, codice in inglese. Commit senza `Co-Authored-By`, senza le parole `closes`, `fixes`, `resolves`.
- Mai chiudere processi per nome dell'eseguibile (`taskkill /IM`, `pkill`).
- Comandi: plugin da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`. App da `app/` (Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`): `flutter gen-l10n`, `flutter analyze`, `flutter test`. Build di rilascio: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Dopo i comandi Flutter, `git checkout -- windows/flutter/generated_plugin*` se cambiano solo i fine riga.

## Review Focus

1. Nome Discord con "@" davanti o spazi ai lati (`" @Mario "`): va pulito come per l'utente e trovato. → test in Task 2.
2. Un utente che ha già Discord: l'associazione lo sostituisce e un codice di recupero già mandato al vecchio non vale più. → test in Task 2.
3. L'admin cerca, vede l'anteprima, poi corregge il nome: "Associa" non deve salvare la persona vecchia. → test in Task 5.
4. Plugin vecchio (senza `accountAdminLink`) o canale spento: la voce non c'è, invece di un errore. → test in Task 5.
5. L'admin associa sé stesso o un altro admin: funziona (le voci ci sono per tutti). → test in Task 5.

---

### Task 1: nome visualizzato nel membro Discord

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Account/IDiscordSender.cs` (record `DiscordMember`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Server/DiscordBotClient.cs` (`FindMemberAsync`)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/DiscordBotClientTests.cs`

**Interfaces:**
- Produces: `public sealed record DiscordMember(string Id, string Username, string? DisplayName = null);`

- [ ] **Step 1: test che falliscono**, accanto a `FindsTheExactNameAmongThePrefixMatches`, con `_http.Respond` come lì:
  - `TheDisplayNameIsTheServerNickname`: `[{"nick":"Super Mario","user":{"id":"222222222222222222","username":"Mario","global_name":"Mario Rossi"}}]` → `Assert.Equal(new DiscordMember("222222222222222222", "Mario", "Super Mario"), lookup.Member)`.
  - `WithoutNicknameTheDisplayNameIsTheGlobalName`: senza `nick` (e con `"nick":null`, `[Theory]`) → `DisplayName` `"Mario Rossi"`.
  - `WithoutNamesThereIsNoDisplayName`: né `nick` né `global_name` (anche `"global_name":null`) → `DisplayName` null.
- [ ] **Step 2:** `dotnet test … --filter DiscordBotClientTests` → i tre nuovi falliscono.
- [ ] **Step 3:** aggiungere `DisplayName` al record; in `FindMemberAsync` leggere `member.nick`, poi `user.global_name`, solo se `JsonValueKind.String` e non vuoti dopo `Trim`. I test esistenti con `new DiscordMember(id, name)` restano uguali.
- [ ] **Step 4:** `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` → tutto verde.
- [ ] **Step 5:** commit `feat(plugin): nome visualizzato del membro Discord`.

### Task 2: `AccountAdmin` cerca e associa

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Account/AccountAdmin.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/AccountRig.cs` (`Admin()`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/AccountAdminTests.cs` (i due `new AccountAdmin(...)` alle righe ~108 e ~132)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/AccountAdminControllerTests.cs` (il `new AccountAdmin(...)` alla riga ~82)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/AccountAdminTests.cs`

**Interfaces:**
- Consumes: `DiscordMember` di Task 1.
- Produces (in `AccountAdmin`):
  - costruttore: `AccountAdmin(IUserDirectory users, ContactRegistry contacts, CodeBook codes, AccountSender sender, IDiscordSender discord, IAccountSettings settings, InboxService inbox, TimeProvider time, ILogger<AccountAdmin> logger)`
  - `Task<AccountResult<DiscordMember>> LookupDiscordAsync(string? name, CancellationToken cancellationToken)`
  - `Task<AccountError?> SetDiscordAsync(Guid userId, string? id, string? username, Guid adminId)`
  - `Task<AccountError?> SetEmailAsync(Guid userId, string? address, Guid adminId)`

- [ ] **Step 1: aggiornare i costruttori nei test** (`AccountRig.Admin()` passa `Inbox` e `Time` del rig; gli altri tre `new AccountAdmin(...)` lo stesso) e scrivere i test che falliscono in `AccountAdminTests`:
  - `LookupFindsTheMember`: `_rig.Discord` trova `" @Mario "` pulito in `"Mario"` → `Ok` con il membro del finto; il finto ha ricevuto `"Mario"`.
  - `LookupWithDiscordOffIsChannelOff`, `LookupOfABadNameIsInvalidTarget` (`"a"`), `LookupOfAMissingMemberIsMemberNotFound`, `AFailedLookupIsSendFailedAndRecorded` (dopo, `_rig.Sender.LastError(AccountChannel.Discord)` non è null).
  - `SetDiscordSavesAVerifiedContact`: utente senza contatti → `null`; `_rig.Contacts.Get(id).Discord` ha `Id`, `Name` e `VerifiedAt == _rig.Time.GetUtcNow()`.
  - `SetDiscordReplacesTheContactAndCancelsTheCodes`: `UserWithContacts`, un codice `CodePurpose.Recovery` e uno `VerifyDiscord` emessi con `_rig.Codes.Issue` → dopo `SetDiscordAsync` il Discord è quello nuovo e `_rig.Codes.Check(...)` di entrambi i codici non è `Ok`.
  - `SetDiscordRemovesTheContactReminders`: come in `ContactLinkingTests` per `ConfirmAsync` (stesso modo di creare e contare il promemoria) → dopo, nessun promemoria.
  - `SetDiscordErrors` (`[Theory]` o un test per caso): utente sconosciuto → `UnknownUser`; Discord spento → `ChannelOff`; `id` `"123"` o `username` `" "` → `InvalidTarget`. In nessun caso cambia il contatto.
  - `SetEmailSavesAVerifiedContact`, `SetEmailErrors` (sconosciuto, email spenta, `"non-email"` → `InvalidTarget`), `SetEmailCancelsTheRecoveryCode` (con `VerifyEmail` e `Recovery`).
  - `SetDiscordIsInTheLogWithTheAdmin`: come `UnlinkIsInTheLogWithTheAdmin`; il log contiene l'id dell'utente e dell'admin e **non** contiene il nome Discord. Lo stesso per l'email (non contiene l'indirizzo).
- [ ] **Step 2:** `dotnet test … --filter AccountAdminTests` → i nuovi falliscono.
- [ ] **Step 3: implementare** in `AccountAdmin.cs`, ordine dei controlli come nella spec §4.2:
  - `LookupDiscordAsync`: `settings.IsDiscordConfigured()` → `ChannelOff`; `ContactLinking.CleanDiscordName` → `InvalidTarget`; `discord.FindMemberAsync`: `Failed` → `sender.Record(AccountChannel.Discord, SendOutcome.Failed)` e `SendFailed`; `Member` null → `MemberNotFound`.
  - `SetDiscordAsync` / `SetEmailAsync`: `users.GetUser(userId)` null → `UnknownUser`; `settings.IsConfigured(channel)` → `ChannelOff`; `DiscordIds.IsSnowflake(id)` e `username` non vuoto (salvato con `Trim`) / `ContactLinking.CleanEmail(address)` → `InvalidTarget`; poi `contacts.SetDiscord`/`SetEmail` con `VerifiedAt = time.GetUtcNow()`, `codes.Discard(userId, CodePurpose.Recovery)` e `codes.Discard(userId, CodePurpose.VerifyDiscord|VerifyEmail)`, `await inbox.RemoveContactRemindersAsync(userId)`, log `"{Channel} di {UserId} associato dall'admin {AdminId}"`.
  - Il `<summary>` della classe cita anche l'associazione.
- [ ] **Step 4:** tutti i test del plugin verdi (`ServiceRegistrationTests` compreso: `InboxService` e `TimeProvider` sono già registrati).
- [ ] **Step 5:** commit `feat(plugin): l'admin associa Discord ed email`.

### Task 3: endpoint, funzione `accountAdminLink`, versione 1.24.0

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Api/AccountAdminController.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/AccountDtos.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Protocol/WatchPartyProtocol.cs` (lista `Features`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` (`<Version>1.24.0</Version>`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/…` o `plugin/README.md` solo se elencano gli endpoint (cercare `Admin/Test`)
- Test: `plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests/AccountAdminControllerTests.cs`, `InfoControllerTests.cs`

**Interfaces:**
- Consumes: i tre metodi di Task 2.
- Produces (wire, sotto `WonderFlixWatchParty/Account/Admin`):
  - `POST Discord/Lookup` corpo `AdminDiscordLookupRequest { Name }` → 200 `AdminDiscordMemberDto(Id, Username, DisplayName)`; `DisplayName` con `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]`.
  - `PUT Users/{userId}/Discord` corpo `AdminSetDiscordRequest { Id, Username }` → 204.
  - `PUT Users/{userId}/Email` corpo `AdminSetEmailRequest { Address }` → 204.
  - I request sono classi con setter e `[JsonPropertyName]`, come `AccountTestRequest`.
  - Funzione `"accountAdminLink"` (costante `AccountAdminLinkFeature`) in coda alla lista fissa `Features`, sempre presente.

- [ ] **Step 1: test che falliscono.** In `AccountAdminControllerTests`, con lo stile dei test di `Unlink`: lookup trovato → 200 con `DisplayName`; lookup `MemberNotFound` → 400 con `Code`; `ChannelOff` → 503; `PUT …/Discord` → 204 e contatto salvato; `userId` `"non-guid"` → 400 `UnknownUser` per entrambi i `PUT`; corpo null → `InvalidTarget`. In `InfoControllerTests`: versione `"1.24.0"`, `"accountAdminLink"` dopo `"push"` nella lista attesa, e `Skip(14)` diventa `Skip(15)`.
- [ ] **Step 2:** i nuovi falliscono.
- [ ] **Step 3:** implementare (l'admin dal `CallerAsync()` come `Unlink`; `HttpContext.RequestAborted` per la ricerca).
- [ ] **Step 4:** tutti i test del plugin verdi.
- [ ] **Step 5:** commit `feat(plugin): endpoint per associare i contatti, versione 1.24.0`.

### Task 4: app, API e funzione

**Files:**
- Modify: `app/lib/core/social/social_models.dart` (`PluginFeatures`)
- Modify: `app/lib/features/social/social_providers.dart` (`SocialFeatures`: campo, `==`, `hashCode`, `toString`, lettura da `info.features`)
- Modify: `app/lib/core/social/plugin_admin_models.dart`
- Modify: `app/lib/core/social/plugin_admin_api.dart`
- Modify: `app/lib/features/admin/account_admin_controllers.dart`
- Modify: `app/test/support/admin_fakes.dart` (`FakePluginAdminApi`)
- Test: `app/test/core/social/account_admin_api_test.dart`, il test di `SocialFeatures` che già controlla le altre funzioni (cercare `downloadsSearchJobs` in `app/test`)

**Interfaces:**
- Produces:
  - `PluginFeatures.accountAdminLink = 'accountAdminLink'`; `SocialFeatures.accountAdminLink` (bool, default false).
  - `class AdminDiscordMember { const AdminDiscordMember({required this.id, required this.username, this.displayName}); factory AdminDiscordMember.fromJson(Map<String, dynamic>); final String id; final String username; final String? displayName; }` (`Id` e `Username` obbligatori con `_required`).
  - `PluginAdminApi.lookupDiscordMember(String name) → Future<AdminDiscordMember>`: `POST $_account/Discord/Lookup`, corpo `{'Name': name}`.
  - `PluginAdminApi.setUserDiscord(String userId, AdminDiscordMember member) → Future<void>`: `PUT $_account/Users/$userId/Discord`, corpo `{'Id': member.id, 'Username': member.username}`.
  - `PluginAdminApi.setUserEmail(String userId, String address) → Future<void>`: `PUT $_account/Users/$userId/Email`, corpo `{'Address': address}`.
  - Tutte con `quietStatuses: _accountQuiet`.
  - `AccountUsersController.setDiscord(String userId, AdminDiscordMember member)` e `setEmail(String userId, String address)` con `act(...)` (rilegge l'elenco). La ricerca non passa dal controller: il dialogo chiama `ref.read(pluginAdminApiProvider).lookupDiscordMember`.
  - `FakePluginAdminApi`: `AdminDiscordMember? lookupValue` (null → lancia `ServerErrorException` con body `{'Code': 'MemberNotFound'}` e stato 400), `Object? lookupError`; chiamate registrate `lookup:<name>`, `setDiscord:<id>:<discordId>`, `setEmail:<id>:<address>`; `setUserDiscord`/`setUserEmail` aspettano `accountActionGate`, lanciano `actionError` e aggiornano `accountUsersValue` (`discordName: member.username`, o `maskedEmail` mascherata come il plugin).

- [ ] **Step 1: test che falliscono** in `account_admin_api_test.dart`, con il `FakeAdapter` come gli altri test del file: metodo, percorso e corpo di ciascuna delle tre chiamate; `lookupDiscordMember` legge `DisplayName` (e null quando è `null` nel JSON); un 400 `{"Code":"MemberNotFound"}` arriva come errore con `pluginErrorCode(error) == 'MemberNotFound'`. Nel test di `SocialFeatures`: `accountAdminLink` vero solo con `'accountAdminLink'` in `features`.
- [ ] **Step 2:** `flutter test test/core/social/account_admin_api_test.dart` → falliscono.
- [ ] **Step 3:** implementare.
- [ ] **Step 4:** `flutter analyze` pulito, `flutter test` verde.
- [ ] **Step 5:** commit `feat(app): API per associare i contatti`.

### Task 5: app, menu e dialoghi; versione 0.33.0

**Files:**
- Create: `app/lib/features/admin/admin_link_contact_dialog.dart`
- Modify: `app/lib/features/admin/users_tab.dart`
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb` (poi `flutter gen-l10n`)
- Modify: `app/pubspec.yaml` (`version: 0.33.0`, il numero di build come nei bump precedenti: `git log -p -1 --grep "versione 0.32.1" -- app/pubspec.yaml`)
- Modify: `docs/RELEASING.md` (checklist manuale dell'app, dopo la riga di Discord Rich Presence)
- Test: `app/test/features/admin/users_tab_test.dart`, `app/test/features/admin/admin_link_contact_dialog_test.dart`

**Interfaces:**
- Consumes: Task 4.
- Produces:
  - `enum UserAction { setPassword, sendRecovery, linkDiscord, linkEmail, unlink }`.
  - `List<UserAction> userActions(AdminAccountUser user, {required bool isMe, bool canLinkDiscord = false, bool canLinkEmail = false})`: `linkDiscord`/`linkEmail` per ogni utente quando il flag è vero, prima di `unlink`. Default false: i test esistenti di `userActions` restano validi.
  - Nella riga: `canLinkDiscord = features.accountAdminLink && status?.discord.configured == true`, lo stesso con `email`; `features` da `socialAvailabilityProvider`, `status` da `ref.watch(accountAdminControllerProvider).value`. Senza stato (ancora in lettura o errore) le voci non ci sono.
  - `Future<bool> showAdminLinkDiscordDialog(BuildContext context, {required String userId, required String name})` e `Future<bool> showAdminLinkEmailDialog(…)`, con `showWfDialog` come `showSetPasswordDialog`; true se salvato.
  - Chiavi: campo `Key('admin-link-field')`, pulsante `Key('admin-link-submit')`.

Testi nuovi (it / en):

| Chiave | it | en |
|---|---|---|
| `adminUsersLinkDiscord` | Associa Discord | Link Discord |
| `adminUsersLinkEmail` | Associa email | Link email |
| `adminUsersLinkDiscordTitle(name)` | Associa Discord a {name} | Link Discord to {name} |
| `adminUsersLinkEmailTitle(name)` | Associa email a {name} | Link email to {name} |
| `adminUsersLinkSearch` | Cerca | Search |
| `adminUsersLinkSubmit` | Associa | Link |
| `adminUsersDiscordLinkedTo(name)` | Discord associato a {name} | Discord linked to {name} |
| `adminUsersEmailLinkedTo(name)` | Email associata a {name} | Email linked to {name} |
| `adminUsersMemberNotFound` | Nome non trovato nel server Discord | Name not found in the Discord server |
| `adminUsersChannelOff` | Canale non configurato sul server | Channel not set up on the server |

Riusati: `accountDiscordName`, `accountDiscordNameHint`, `accountChannelEmail` (etichetta del campo email), `accountErrorInvalidDiscordName`, `accountErrorInvalidEmail`. Errori nei dialoghi, sotto il campo: `InvalidTarget` → il testo del canale; `MemberNotFound` → `adminUsersMemberNotFound`; `ChannelOff` → `adminUsersChannelOff`; il resto `accountAdminErrorText(l, error, name)`.

Comportamento del dialogo Discord: "Cerca" con il campo vuoto non fa niente; durante una richiesta il pulsante è spento e il dialogo non si chiude (come `SetPasswordDialog`); trovato, sotto il campo `@{username}` e, se c'è, `displayName`, e il pulsante diventa "Associa"; un cambio del testo del campo toglie anteprima ed errore e torna a "Cerca". "Associa" salva il membro dell'anteprima con `AccountUsersController.setDiscord`. Dialogo email: un campo e "Associa" → `setEmail`. Salvato: il dialogo rende true e la riga mostra lo SnackBar `adminUsersDiscordLinkedTo`/`adminUsersEmailLinkedTo`.

- [ ] **Step 1: test che falliscono.**
  - `users_tab_test.dart`: con `features: SocialFeatures(inbox: true, account: true, accountAdminLink: true)` e i due canali configurati nello stato finto, il menu di un utente senza contatti ha "Associa Discord" e "Associa email"; anche la riga dell'admin che guarda e quella di un altro admin. Senza `accountAdminLink` le voci non ci sono. Con `discord.configured` false c'è solo "Associa email". `userActions` con i flag mette le due voci prima di `unlink`.
  - `admin_link_contact_dialog_test.dart`: scrivere `mario` → "Cerca" → si vede `@Mario` e il nome visualizzato → "Associa" → `plugin.calls` contiene `lookup:mario` e `setDiscord:<id>:<discordId>`, lo SnackBar "Discord associato a …" e l'icona di Discord accesa nella riga. Cambiare il testo dopo l'anteprima: il pulsante torna "Cerca" e "Associa" non parte senza una nuova ricerca. `MemberNotFound` → "Nome non trovato nel server Discord" sotto il campo, dialogo aperto. Email: `mario@example.com` → "Associa" → `setEmail:<id>:mario@example.com`; `InvalidTarget` → "Email non valida".
- [ ] **Step 2:** `flutter test test/features/admin` → i nuovi falliscono.
- [ ] **Step 3:** implementare: testi negli `.arb`, `flutter gen-l10n`, il dialogo, le azioni nella riga (`_select` e `_actionLabel`). Ogni riga ora ha almeno una voce se il plugin ha la funzione: il ramo `actions.isEmpty` resta per i plugin vecchi.
- [ ] **Step 4:** `flutter gen-l10n`, `flutter analyze` pulito, `flutter test` verde.
- [ ] **Step 5:** bump `version: 0.33.0` e, in `docs/RELEASING.md`, la riga `- [ ] Admin → Utenti → ⋮ → "Associa Discord": cerca, anteprima, associa; poi il recupero di quell'utente arriva su quel Discord. "Associa email": lo stesso con l'indirizzo.` Commit `feat(app): l'admin associa Discord ed email, versione 0.33.0`.

### Task 6: prova a mano

- [ ] Build del plugin in Release e deploy della dll sul seedbox, seguendo le regole di CLAUDE.md (nessuno che guarda, data/md5 della dll, le altre sessioni con `ListAgents`).
- [ ] Build di rilascio dell'app (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`) e avvio di `build\windows\x64\runner\Release\wonderflix.exe` con `Start-Process`; chiudere solo la propria istanza precedente, per PID.
- [ ] Chiedere all'utente di provare la riga nuova della checklist. Niente merge su `main` né push prima del suo ok.

### Task 7: ricerca Discord in più server (prima del Task 6)

Chiesto dall'utente il 2026-11-07 durante l'esecuzione: il bot sta nel server di WonderFlix, gli amici in un altro. Oggi `FindMemberAsync` cerca solo in `DiscordGuildId`, quindi gli amici risultano "non trovati" sia quando collegano Discord da soli sia con "Associa Discord". I DM funzionano già con un server in comune: non cambiano.

**Files:**
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/PluginConfiguration.cs` (`DiscordExtraGuildIds`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Account/IAccountSettings.cs` (`DiscordExtraGuildIds` + estensione `DiscordGuildIds()`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Server/PluginAccountSettings.cs`
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Server/DiscordBotClient.cs` (`FindMemberAsync`, `CheckAsync`)
- Modify: `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Configuration/configPage.html` (campo sotto "Discord server ID")
- Modify: `plugin/README.md` se descrive i campi della configurazione del recupero
- Modify: `docs/RELEASING.md` (checklist del plugin)
- Test: `DiscordBotClientTests.cs`, `AccountSettingsTests.cs`, `FakeAccountSettings.cs`

**Interfaces:**
- `PluginConfiguration.DiscordExtraGuildIds`: `string`, default `string.Empty`. Gli id degli altri server, separati da virgole, spazi o a capo.
- `IAccountSettings.DiscordExtraGuildIds { get; }` (`string`, trim come `DiscordGuildId`); `FakeAccountSettings` lo prende con default `string.Empty`.
- `AccountSettingsExtensions.DiscordGuildIds(this IAccountSettings settings) → IReadOnlyList<string>`: prima `DiscordGuildId`, poi gli id in più nell'ordine scritto; solo snowflake (`DiscordIds.IsSnowflake`), senza doppioni (anche il principale ripetuto). Un id non valido si salta.
- `IsDiscordConfigured()` non cambia: serve sempre il principale. `DiscordGuildId` resta il server di `supportUrl` / "Unisciti al server".

- [ ] **Step 1: test che falliscono.**
  - `AccountSettingsTests`: default vuoto del campo nuovo; il valore si legge e si salva come gli altri; `DiscordGuildIds()` con `"222222222222222222, 333333333333333333\n123456789012345678 abc"` e principale `123456789012345678` → `["123456789012345678", "222222222222222222", "333333333333333333"]`; con il campo vuoto → solo il principale.
  - `DiscordBotClientTests`, con due server (`DiscordExtraGuildIds = "222222222222222222"` nel finto delle impostazioni) e `_http.Respond` che risponde per percorso:
    - `FindsTheMemberInTheSecondServer`: il primo server non ha il nome, il secondo sì → trovato; due richieste, nell'ordine principale poi secondo.
    - `StopsAtTheFirstServerThatHasTheMember`: il primo lo trova → una sola richiesta.
    - `AnErrorInOneServerDoesNotHideAMemberInAnother`: il primo dà 500, il secondo lo trova → trovato.
    - `NotFoundAnywhereIsNotFound`: nessuno dei due → `DiscordLookup.NotFound`.
    - `AnErrorAndNoMemberIsAnError`: il primo 500, il secondo vuoto → `DiscordLookup.Error` (non si sa se c'era).
    - `CheckLooksAtEveryServer`: il secondo server dà 404 su `guilds/{id}` → `Invalid`; 403 sulla sua ricerca dei membri → `Invalid`; 502 → `Failed`; tutti 200 → `Ok`.
  - I test di oggi con un server solo restano uguali.
- [ ] **Step 2:** i nuovi falliscono.
- [ ] **Step 3: implementare.** `FindMemberAsync` prova `settings.DiscordGuildIds()` in ordine con la ricerca di oggi (stesso filtro su bot, nome esatto e snowflake). Il primo trovato vince. Alla fine `Error` se almeno un server ha dato errore, altrimenti `NotFound`. Ogni richiesta ha il suo `Timeout`, come oggi, con il commento `// shortcut: un Timeout per server; con più di 2-3 server l'attesa supera i 30 s dell'app, passare a un budget unico.`. `CheckAsync`: `users/@me` una volta, poi `guilds/{id}` e la ricerca di prova per ogni server, con gli stessi esiti di oggi. Il primo `Invalid` o `Failed` si rende subito. Dashboard: un campo di testo `WonderFlixDiscordExtraGuildIds` con l'etichetta "Other Discord server IDs" e la descrizione "Optional. Servers where the bot also looks for members (for example your friends' server), separated by commas. Invite the bot there the same way.", letto e salvato come `DiscordGuildId`.
- [ ] **Step 4:** tutti i test del plugin verdi.
- [ ] **Step 5:** nella checklist del plugin in `docs/RELEASING.md` la riga `- [ ] Dashboard → "Other Discord server IDs" con il server degli amici (bot invitato lì): un utente che è solo in quel server collega Discord da Impostazioni, e "Associa Discord" lo trova.`. Commit `feat(plugin): ricerca Discord anche negli altri server`.
