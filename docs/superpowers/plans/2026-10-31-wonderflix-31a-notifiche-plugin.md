# WonderFlix — Piano 31a: notifiche push, plugin 1.17.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec V nel plugin 1.17.0: Web Push con VAPID, iscrizioni e preferenze per utente, una push per ogni voce **nuova** della cassetta, le voci admin nuove (download, spazio, sicurezza, server) che si chiudono da sole, richiesta accettata e rifiutata da Seerr. L'app arriva nel piano 31b, che usa i JSON di "Global Constraints": **i nomi delle proprietà JSON e dei tipi non si cambiano**.

**Architecture:**
- **Parti pure**, con i loro test:
  - `WebPushCrypto`, la cifratura RFC 8291 (`aes128gcm`);
  - `VapidSigner`, il JWT ES256 di RFC 8292 e la generazione delle chiavi;
  - `NotificationCatalog`: per ogni tipo il pubblico, la rotta dell'app e i testi it/en.
- **Niente pacchetti NuGet nuovi:** basta .NET 9 (`ECDiffieHellman`, `ECDsa`, `HKDF`, `AesGcm`). Così `plugin/pack.sh` e lo zip restano una sola dll.
- **Archivio:** `NotificationStore` salva in `notifications.json` iscrizioni e tipi spenti.
- **Invio:** `PushService` filtra per preferenze, ruolo e accesso del dispositivo (`IDeviceAccess`), poi manda tramite `IPushTransport` (HTTP). Non lancia e non blocca chi lo chiama.
- **Cassetta:** `InboxService` segna le voci *nuove* (non gli aggiornamenti) e le passa a `PushService`.
- **Voci admin:** `AdminAlerts` crea, aggiorna e toglie le voci admin per chiave. I servizi esistenti la chiamano: download, spazio, recupero password, un servizio nuovo per il riavvio, il webhook di Seerr.

**Tech Stack:** C# / .NET 9, ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Compilato contro Jellyfin 10.11.0; test e server con la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-31-wonderflix-notifiche-push-design.md` (tutta, tranne le parti dell'app: §4.2 lato app, §4.5 schermata, §5 app).

**Decisioni del piano** (rispetto alla spec; il Task 14 le riporta nella spec):
1. **Web Push scritto a mano** con le primitive di .NET, provato con il vettore di esempio di RFC 8291 §5. Niente librerie esterne: il plugin si distribuisce come dll singola.
2. **I testi delle push nascono nel plugin**, in it/en, nella lingua salvata con l'iscrizione. Il service worker dell'app mostra solo quello che riceve.
3. **"Download fermo" è uno storico** (§4.4b): è un evento, non uno stato in cui il download resta.
4. **La soglia del disco sta nella configurazione del plugin**, nella sezione Spazio di `configPage.html`, dove ci sono già le altre impostazioni dello spazio. La spec dice "scheda Spazio": nell'app non c'è una pagina di impostazioni dello spazio.
5. **Profili sullo stesso dispositivo:** l'iscrizione è per coppia (endpoint, utente). Ogni profilo attiva le sue; uscire da un profilo toglie solo le sue.

## Global Constraints

- Versione del plugin **1.17.0**. Commit in italiano, senza `closes`/`fixes`/`resolves` e senza trailer `Co-Authored-By`.
- Non uccidere mai processi per nome dell'immagine (`taskkill /IM`, `pkill`).
- Test del plugin (da `plugin/`): `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`.
- Jellyfin cambia API anche nelle patch: ogni API nuova di Jellyfin (`IDeviceManager`, `IServerApplicationHost.HasPendingRestart`) va verificata sulla 10.11.0 con cui si compila.
- Nei DTO, i campi nullable che devono esserci sempre vogliono `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]`.
- **Niente dati sensibili nelle push** (spec §2): niente ApiKey, token, codici, email o percorsi. Nel log l'endpoint di un'iscrizione compare solo con l'host.
- **Tipi delle voci** (nuovi in `InboxEntryTypes`): `RequestApproved`, `RequestDeclined`, `DownloadNeedsYou`, `DownloadStalled`, `LightenBlocked`, `SpaceOperationFailed`, `DiskAlmostFull`, `RecoveryStarted`, `RecoveryBlocked`, `RestartPending`.
- **Campi nuovi di `InboxEntry`**, tutti nullable e omessi se null:
  - `AlertKey` (string);
  - `Reason` (string: motivo del download, come `DownloadReasons`);
  - `Percent` (int);
  - `UserName` (string);
  - `Scope` (`"User"` o `"Everyone"`, solo `RecoveryBlocked`).

  `Title` resta quello di sempre. `RequestApproved`/`RequestDeclined` usano gli stessi campi di `RequestAvailable`.
- **Endpoint**, tutti con `[Authorize(Policy = Policies.SyncPlayHasAccess)]`; chi chiama è l'utente dell'autenticazione e il dispositivo è `auth.DeviceId`:
  - `GET WonderFlixWatchParty/Notifications` → `{"VapidPublicKey":"<base64url>","Types":[{"Type":"RequestApproved","Enabled":true}, …]}`. Solo i tipi che chi chiama può ricevere, nell'ordine del catalogo.
  - `PUT WonderFlixWatchParty/Notifications/Types/{type}` con `{"Enabled":bool}` → 204. 400 se il tipo è sconosciuto o non visibile a chi chiama.
  - `POST WonderFlixWatchParty/Notifications/Subscriptions` con `{"Endpoint","P256dh","Auth","Language"}` → 204. Crea o aggiorna per (Endpoint, utente) e salva `DeviceId` e `Language`. 400 se `Endpoint` non è `https://` o se le chiavi non sono base64url valide.
  - `DELETE WonderFlixWatchParty/Notifications/Subscriptions` con `{"Endpoint"}` → 204, solo l'iscrizione di chi chiama. 204 anche se non c'è.
- **`Info`:** la funzione `push` compare sempre in `Features`.
- **Contenuto della push** (JSON cifrato): `{"title":"…","body":"…","route":"/requests","tag":"<Id della voce>"}`. `route` è una rotta GoRouter dell'app, senza `#`.
- **Pubblico dei tipi:**
  - **tutti:** `Invite`, `Announcement`, `NewTitles`, `RequestAvailable`, `RequestApproved`, `RequestDeclined`, `ContactReminder`, `Recommendation`, `MatchInvite`, `ReportResolved`;
  - **chi approva** (`seerrUsers.ManagerJellyfinIdsAsync`): `RequestPending`;
  - **admin:** `ReportPending`, `DownloadNeedsYou`, `DownloadStalled`, `LightenBlocked`, `SpaceOperationFailed`, `DiskAlmostFull`, `RecoveryStarted`, `RecoveryBlocked`, `RestartPending`.

## Review Focus

1. **Un'iscrizione morta non deve fermare le altre.** Un endpoint che risponde 404/410 si cancella; un timeout o un 5xx si registra nel log e basta. L'invio agli altri dispositivi continua. Test nel Task 5.
2. **Una sessione revocata dalla dashboard non riceve più nulla.** Se `IDeviceAccess.HasAccess` è falso, la push non parte e l'iscrizione si cancella. Test nel Task 5.
3. **Un nome inventato nel recupero non deve mandare push agli admin.** Recupero avviato o bloccato per un nome che non è un utente: nessuna voce. Il blocco generale invece sì. Test nel Task 10.
4. **Un giro dei download che rivede le stesse voci "Serve te" non deve notificare di nuovo.** Notifica solo se cambia la coppia (tipo, motivo) per quella chiave. Test nel Task 7 e nel Task 8.
5. **Il promemoria del contatto riscritto a ogni giro deve notificare una volta sola.** Test nel Task 6.

---

### Task 1: Prove dei due rischi (fermo se fallisce la rete)

Nessun codice da tenere: si decide se il design regge (spec §6).

**Files:** nessuno nel repo. Esito scritto nel Task 14.

- [ ] **Step 1: il seedbox raggiunge i servizi push.** Esegui:
  ```bash
  ssh ultra 'for u in https://web.push.apple.com https://fcm.googleapis.com https://wns2-par02p.notify.windows.com; do printf "%s " $u; curl -sS -o /dev/null -m 10 -w "%{http_code}\n" $u || echo ERRORE; done'
  ```
  Expected: tre codici HTTP qualsiasi (anche 4xx/405), nessun `ERRORE` e nessun timeout. Se anche uno solo dà errore di rete, **fermati** e torna dall'utente (spec §6): ogni alternativa va decisa con lui.
- [ ] **Step 2: il tocco Flutter basta a iOS.**
  1. In un worktree usa e getta, sotto `.claude/worktrees/`, aggiungi a `lib/features/settings/settings_screen.dart` (solo web) un pulsante. Il suo `onPressed` chiama `web.Notification.requestPermission()` di `package:web` e mostra il risultato in uno `SnackBar`.
  2. Fai la build web per `/wonderflix-prova/` e pubblicala come dice `docs/RELEASING.md` (con `MSYS_NO_PATHCONV=1` in Git Bash).
  3. Chiedi all'utente di aprirla dalla web app aggiunta alla Home (iOS 27.2), di toccare il pulsante e di dirti se compare la richiesta di permesso.
  
  Expected: compare la richiesta di iOS. Se non compare, il piano 31b usa il ripiego della spec (pulsante HTML sopra la tela solo per quel passo): annotalo per il Task 4 del 31b. Poi ripubblica sul sito di prova la build di `main` e cancella il worktree.

### Task 2: Web Push puro (RFC 8291 e RFC 8292)

**Files:**
- Create: `Push/WebPushCrypto.cs`, `Push/VapidSigner.cs`
- Test: `Jellyfin.Plugin.WonderFlixWatchParty.Tests/WebPushCryptoTests.cs`, `VapidSignerTests.cs`

**Interfaces:**
- Produces:
  - `static byte[] WebPushCrypto.Encrypt(byte[] plaintext, byte[] uaPublic, byte[] authSecret)` (sale e chiave del server casuali);
  - per i test, `internal static byte[] Encrypt(byte[] plaintext, byte[] uaPublic, byte[] authSecret, byte[] salt, ECDiffieHellman serverKey)`;
  - `sealed record VapidKeys(string PublicKey, string PrivateKey)`, in base64url: punto non compresso di 65 byte e scalare `D` di 32 byte;
  - `static VapidKeys VapidSigner.Generate()`;
  - `static string VapidSigner.AuthorizationHeader(string endpoint, VapidKeys keys, string subject, DateTimeOffset now)`, che restituisce `vapid t=<jwt>, k=<public>`;
  - `static class Base64Url { string Encode(byte[]); byte[] Decode(string); bool TryDecode(string, out byte[]) }`.

- [ ] **Step 1: test che falliscono**
  - `Encrypt_MatchesRfc8291Example`: con le chiavi, il sale, il segreto e il testo di RFC 8291 §5 ("When I grow up, I want to be a watermelon"), il risultato in base64url è uguale a quello della RFC.
  - `Encrypt_RandomSaltDiffers`: due chiamate pubbliche danno risultati diversi, entrambi lunghi `86 + plaintext.Length + 1 + 16`.
  - `AuthorizationHeader_VerifiesWithPublicKey`:
    - il JWT ha `aud` uguale all'origine dell'endpoint (`https://web.push.apple.com` per `https://web.push.apple.com/abc`);
    - `exp` è `now + 12 h`;
    - `sub` è quello passato;
    - la firma ES256 si verifica con `VapidKeys.PublicKey`.
  - `Generate_ProducesValidKeys`: `PublicKey` decodificata è lunga 65 byte e comincia con `0x04`; `PrivateKey` è lunga 32 byte.
- [ ] **Step 2:** `dotnet test … --filter "WebPushCrypto|VapidSigner"`. Expected: FAIL, i tipi non esistono.
- [ ] **Step 3: implementa.**
  - **Cifratura** (RFC 8291 §3.4): ECDH sulla P-256; `HKDF.Extract`/`Expand` con `"WebPush: info\0" + ua_public + as_public`, poi `"Content-Encoding: aes128gcm\0"` e `"Content-Encoding: nonce\0"`; un solo record con delimitatore `0x02`; `AesGcm` con tag di 16 byte. L'header è sale(16) ‖ rs=4096 (uint32 big endian) ‖ idlen=65 ‖ as_public.
  - **JWT:** `ECDsa.SignData(…, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation)`.
- [ ] **Step 4:** stessi test. Expected: PASS.
- [ ] **Step 5: commit** `feat(plugin): cifratura Web Push e firma VAPID`.

### Task 3: Catalogo dei tipi, archivio e chiavi VAPID

**Files:**
- Create: `Push/NotificationCatalog.cs`, `Push/NotificationStore.cs`, `Push/NotificationBook.cs`
- Modify:
  - `Protocol/InboxDtos.cs`: i tipi e i campi nuovi di "Global Constraints";
  - `Configuration/PluginConfiguration.cs`: `VapidPublicKey`, `VapidPrivateKey`, stringhe vuote all'inizio;
  - `PluginServiceRegistrator.cs`.
- Test: `NotificationCatalogTests.cs`, `NotificationBookTests.cs`, `NotificationStoreTests.cs`

**Interfaces:**
- Produces:
  - `enum NotificationAudience { Everyone, Approvers, Admins }`;
  - `sealed record PushMessage(string Title, string Body, string Route)`;
  - `static class NotificationCatalog`:
    - `IReadOnlyList<string> Types` (l'ordine di "Global Constraints": prima "tutti", poi `RequestPending`, poi gli admin);
    - `NotificationAudience AudienceOf(string type)`;
    - `PushMessage? Message(InboxEntry entry, string language)`: null per un tipo sconosciuto. Una lingua diversa da `"it"` vale `"en"`;
  - `sealed class PushSubscription { Guid UserId; string Endpoint; string P256dh; string Auth; string DeviceId; string Language; DateTimeOffset CreatedAt }`;
  - `NotificationBook`:
    - `Upsert(PushSubscription)`;
    - `bool Remove(Guid userId, string endpoint)`;
    - `bool RemoveEndpoint(string endpoint)`;
    - `IReadOnlyList<PushSubscription> For(Guid userId)`;
    - `bool IsEnabled(Guid userId, string type)`;
    - `bool SetEnabled(Guid userId, string type, bool enabled)`;
    - `int Prune(Func<Guid,bool> userExists)`;
  - `NotificationStore`: `Load()`, `Save(NotificationBook)`, `FilePath`, come `InboxStore`. Il file è `notifications.json`;
  - `VapidKeyProvider.Get()`, che restituisce `VapidKeys` e genera e salva nella configurazione al primo uso.

- [ ] **Step 1: test che falliscono**
  - `Message_UsesItalianAndEnglishCopy`: le righe della tabella qui sotto, per `RequestPending`, `DownloadNeedsYou` con `GrabRefused`, `RecoveryBlocked` con `Everyone` e `DiskAlmostFull` con `Percent=93`, in it e in en.
  - `Message_FallsBackToEnglish` per `"de"`.
  - `Message_RoutesRequestAvailable`: `/item/{ItemId}` con `ItemId`, `/requests` senza.
  - `Book_DisabledTypeSurvivesRoundTrip`: dopo `Save`/`Load` il tipo resta spento.
  - `Book_UpsertReplacesSameEndpointAndUser`.
  - `Book_SameEndpointTwoUsersAreTwoSubscriptions` (decisione 5).
  - `Provider_GeneratesOnceAndReuses`.
- [ ] **Step 2:** i test falliscono (tipi assenti).
- [ ] **Step 3: implementa con questi testi** (`{…}` sono campi della voce):

  | Tipo | it: titolo / testo | en: titolo / testo | Rotta |
  |---|---|---|---|
  | Invite | `{FromName} ti invita a un watch party` / `{Title}` | `{FromName} invited you to a watch party` / `{Title}` | `/inbox` |
  | Announcement | `Annuncio` / `{Text}` | `Announcement` / `{Text}` | `/inbox` |
  | NewTitles | `Nuovi titoli su WonderFlix` / i primi 3 nomi tra film e serie, separati da `, ` | `New on WonderFlix` / idem | `/home` |
  | RequestAvailable | `Ora disponibile` / `{Title}` | `Now available` / `{Title}` | `/item/{ItemId}` o `/requests` |
  | RequestPending | `Nuova richiesta da approvare` / `{Title} — da {RequesterName}` | `New request to approve` / `{Title} — from {RequesterName}` | `/requests` |
  | RequestApproved | `Richiesta accettata` / `{Title}` | `Request approved` / `{Title}` | `/requests` |
  | RequestDeclined | `Richiesta rifiutata` / `{Title}` | `Request declined` / `{Title}` | `/requests` |
  | ContactReminder | `Proteggi il tuo account` / `Aggiungi un contatto per recuperare la password` | `Protect your account` / `Add a contact to recover your password` | `/settings` |
  | Recommendation | `{FromName} ti consiglia un titolo` / `{Title}` | `{FromName} recommends a title` / `{Title}` | `/item/{ItemId}` |
  | MatchInvite | `{FromName} ti invita a un match` / `Scegliete insieme cosa guardare` | `{FromName} invited you to a match` / `Pick something to watch together` | `/match/{RoomId}` |
  | ReportPending | `Nuova segnalazione` / `{Title} — da {FromName}` | `New report` / `{Title} — from {FromName}` | `/admin?tab=wonderflix` |
  | ReportResolved | `Segnalazione chiusa` / `{Title}` | `Report closed` / `{Title}` | `/inbox` |
  | DownloadNeedsYou | `Download da sistemare` / `{Title} — {motivo}` | `Download needs you` / `{Title} — {reason}` | `/admin?tab=downloads` |
  | DownloadStalled | `Download fermo` / `{Title} — tolto dalla coda` | `Download stalled` / `{Title} — removed from the queue` | `/admin?tab=downloads` |
  | LightenBlocked | `Alleggerisci bloccato` / `{Title} — import da fare a mano` | `Lighten blocked` / `{Title} — manual import needed` | `/admin?tab=space` |
  | SpaceOperationFailed | `Pulizia dello spazio fallita` / `Apri la scheda Spazio per i dettagli` | `Space cleanup failed` / `Open the Space tab for details` | `/admin?tab=space` |
  | DiskAlmostFull | `Disco quasi pieno` / `Usato il {Percent}% della quota` | `Disk almost full` / `{Percent}% of the quota used` | `/admin?tab=space` |
  | RecoveryStarted | `Recupero password avviato` / `{UserName}` | `Password recovery started` / `{UserName}` | `/admin?tab=users` |
  | RecoveryBlocked | `Recupero password bloccato` / `Troppi tentativi per {UserName}` oppure `Troppi tentativi: bloccato per tutti` | `Password recovery blocked` / `Too many attempts for {UserName}` oppure `Too many attempts: blocked for everyone` | `/admin?tab=users` |
  | RestartPending | `Jellyfin chiede un riavvio` / `Riavvia il server dalla dashboard admin` | `Jellyfin needs a restart` / `Restart the server from the admin dashboard` | `/admin` |

  **Motivi** di `DownloadNeedsYou`:

  | `Reason` | it | en |
  |---|---|---|
  | `NothingFound` | `nessun risultato` | `nothing found` |
  | `BelowMinScore` | `punteggio sotto il minimo` | `score below minimum` |
  | `GrabRefused` | `grab rifiutato` | `grab refused` |
  | `SearchFailed` | `ricerca fallita` | `search failed` |
  | `ImportBlocked` | `import da fare a mano` | `manual import needed` |

- [ ] **Step 4:** i test passano.
- [ ] **Step 5: commit** `feat(plugin): catalogo delle notifiche, iscrizioni e chiavi VAPID`.

### Task 4: Accesso dei dispositivi e trasporto HTTP

**Files:**
- Create: `Push/IDeviceAccess.cs`, `Server/JellyfinDeviceAccess.cs`, `Push/IPushTransport.cs`, `Push/HttpPushTransport.cs`
- Test: `HttpPushTransportTests.cs`, `FakePushTransport.cs`, `FakeDeviceAccess.cs`

**Interfaces:**
- Produces:
  - `interface IDeviceAccess { bool HasAccess(Guid userId, string deviceId); }`. Implementazione: `IDeviceManager.GetDevices(new DeviceQuery { UserId = userId, DeviceId = deviceId })`, con almeno un risultato (da verificare sulla 10.11.0);
  - `enum PushResult { Sent, Gone, Failed }`;
  - `interface IPushTransport { Task<PushResult> SendAsync(PushSubscription sub, byte[] body, string authorization, CancellationToken ct); }`.

- [ ] **Step 1: test che falliscono** (con un `HttpMessageHandler` finto, come `FakeDiscordHttp`):
  - `Send_PostsEncryptedBodyWithHeaders`: richiesta `POST` all'endpoint con `Content-Encoding: aes128gcm`, `TTL: 86400`, `Urgency: normal`, `Authorization` passato e `Content-Type: application/octet-stream`;
  - `Send_404And410AreGone`;
  - `Send_5xxAndTimeoutAreFailed`, con un timeout di 10 s.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.** `HttpPushTransport` usa `IHttpClientFactory` come `DiscordBotClient`. Nel log solo l'host dell'endpoint.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(plugin): trasporto Web Push e controllo dei dispositivi`.

### Task 5: PushService

**Files:**
- Create: `Push/PushService.cs`
- Modify: `PluginServiceRegistrator.cs`
- Test: `PushServiceTests.cs`

**Interfaces:**
- Consumes: Task 2, 3 e 4; `IUserDirectory`.
- Produces:
  - `void PushService.Deliver(IReadOnlyList<(Guid UserId, InboxEntry Entry)> fresh)`: non blocca. Un `Task.Run` per chiamata, con gli errori nel log;
  - `internal Task DeliverAsync(…)` per i test;
  - le operazioni dell'API: `NotificationsResponse Get(Guid userId, bool isAdmin, bool isApprover)`, `bool SetEnabled(…)`, `HubResult Subscribe(Guid userId, string deviceId, SubscribeRequest req)`, `void Unsubscribe(Guid userId, string endpoint)`.

- [ ] **Step 1: test che falliscono** (con `FakePushTransport`, `FakeDeviceAccess`, `FakeServer`/directory utenti esistente):
  - `Deliver_SendsToEveryDeviceOfUser` (due iscrizioni, due invii);
  - `Deliver_SkipsDisabledType`;
  - `Deliver_AdminTypeToUserNoLongerAdmin_NotSent`;
  - `Deliver_DisabledUser_NotSentAndSubscriptionsKept`: l'utente può essere riattivato;
  - `Deliver_DeviceWithoutAccess_NotSentAndSubscriptionRemoved`;
  - `Deliver_GoneRemovesOnlyThatSubscription`;
  - `Deliver_FailedKeepsSubscriptionAndOthersStillSent`;
  - `Deliver_PayloadHasNoSecrets`: il JSON in chiaro passato a `Encrypt` ha solo `title`, `body`, `route` e `tag`;
  - `Deliver_UsesSubscriptionLanguage`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.**
  - Ordine dei controlli: tipo nel catalogo, tipo acceso per l'utente, utente attivo, ruolo per `Admins`, accesso del dispositivo, invio.
  - Archivio sotto un lock, come `InboxService`.
  - Il `subject` VAPID è `mailto:noreply@wonderflix.invalid`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(plugin): invio delle notifiche push`.

### Task 6: La cassetta passa le voci nuove

**Files:**
- Modify: `Hub/InboxBook.cs`, `Hub/InboxService.cs` (costruttore + `PushService`)
- Test: `InboxPushTests.cs`

**Interfaces:**
- Produces:
  - `InboxBook.Add(Guid userId, InboxEntry entry, bool fresh = true)`: con `fresh` la copia va in una lista interna;
  - `IReadOnlyList<(Guid, InboxEntry)> InboxBook.TakeFresh()`, che svuota la lista.

  Dopo ogni `Persist()`, `InboxService` chiama `push.Deliver(Book.TakeFresh())` fuori dal lock, se la lista non è vuota.

- [ ] **Step 1: test che falliscono** (`PushService` finto o registratore):
  - `NewInvite_Pushes`;
  - `SameGroupInviteAgain_DoesNotPush` (`UpsertInvite` su voce esistente);
  - `RecommendationUpdate_DoesNotPush`;
  - `ContactReminderRewritten_PushesOnlyFirstTime`. Il promemoria esistente si riscrive con `fresh: false`; la voce torna in cima come oggi;
  - `RequestPendingSameRequestAgain_DoesNotPush`. `UpsertRequest` passa `fresh: false` se esisteva una voce dello stesso tipo e della stessa richiesta;
  - `MarkReadRemoveClear_DoNotPush`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.**
  - Gli `Upsert*` chiamano `Add(..., fresh: true)` solo quando la voce non c'era.
  - `AddContactReminderAsync` calcola prima se un promemoria c'era già.
- [ ] **Step 4:** PASS, insieme a tutti i test `Inbox*` di prima.
- [ ] **Step 5: commit** `feat(plugin): push per le voci nuove della cassetta`.

### Task 7: AdminAlerts, le voci admin per chiave

**Files:**
- Create: `Hub/AdminAlerts.cs`
- Modify: `Hub/InboxService.cs` (due metodi sotto il lock), `PluginServiceRegistrator.cs`
- Test: `AdminAlertsTests.cs`

**Interfaces:**
- Produces:
  - `sealed record AdminAlert(string Key, string Type, string Title, string? Reason = null, int? Percent = null, string? UserName = null, string? Scope = null)`;
  - `Task AdminAlerts.SyncAsync(string keyPrefix, IReadOnlyList<AdminAlert> current)`: per ogni admin attivo (`users.GetUsers().Where(u => u.IsAdmin && u.Enabled)`, come `ReportService`):
    - toglie le voci con `AlertKey` che comincia con `keyPrefix` e non è più in `current`;
    - per ogni alert, se c'è già una voce con la stessa `AlertKey`, lo stesso `Type` e la stessa `Reason`, aggiorna i campi senza notificare (per esempio `Percent`);
    - altrimenti toglie la voce con quella chiave e ne aggiunge una nuova, che notifica;
  - `Task AdminAlerts.RaiseAsync(AdminAlert alert)`: una voce nuova di storico per ogni admin attivo. Non si toglie mai da sola.

  Nessuno dei due lancia: gli errori vanno nel log.

- [ ] **Step 1: test che falliscono**
  - `Sync_NewKey_AddsAndPushes`;
  - `Sync_SameKeyTypeReason_NoPush`;
  - `Sync_SameKeyNewReason_Replaces`;
  - `Sync_MissingKey_RemovedFromAllAdmins`;
  - `Sync_OtherPrefixUntouched`;
  - `Sync_PercentChange_UpdatesWithoutPush`;
  - `Raise_AddsToEveryEnabledAdminOnly`;
  - `Sync_NewAdminGetsCurrentAlerts`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa** sopra `InboxService` (stesso lock, `Persist`, `NotifyAsync`, `TakeFresh`).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(plugin): voci admin che si aprono e si chiudono per chiave`.

### Task 8: Download

**Files:**
- Modify: `Downloads/DownloadService.Admin.cs` (metodo nuovo), `Downloads/DownloadService.cs` (`RemoveStalledAsync`), `DownloadsHostedService.cs`
- Test: `DownloadAlertsTests.cs`

**Interfaces:**
- Consumes: `AdminAlerts` (Task 7).
- Produces: `IReadOnlyList<AdminAlert> DownloadService.NeedsYouAlerts()`, con un alert per ogni voce in `NeedsYou`:
  - `Key = "download:" + entry.Key`;
  - `Type = DownloadNeedsYou`;
  - `Title = entry.Title`;
  - `Reason = entry.Reason`.

- [ ] **Step 1: test che falliscono**
  - `NeedsYouAlerts_OnePerNeedsYouEntry`;
  - `Cycle_SyncsDownloadAlerts`: dopo `RunCycleAsync` il servizio chiama `SyncAsync("download:", …)`. Lo stesso dopo `BuildReviewAsync`;
  - `Cycle_TwiceSameState_SinglePush`;
  - `RemoveStalled_RaisesHistory`: dopo una rimozione riuscita, `RaiseAsync` con `Type = DownloadStalled`, `Key = "stalled:" + key + ":" + now.Ticks` e il titolo della voce.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.** La sincronizzazione sta in `DownloadsHostedService`, dopo ogni giro e dopo ogni revisione, anche quelle avviate da un nudge.
- [ ] **Step 4:** PASS, insieme a tutti i test `Download*`.
- [ ] **Step 5: commit** `feat(plugin): notifiche admin dei download`.

### Task 9: Spazio

**Files:**
- Modify:
  - `Space/SpaceService.cs` (`Abort`, metodo quota);
  - `Space/SpaceService.Lighten.cs` (metodo alert);
  - `SpaceHostedService.cs`;
  - `Space/ISpaceSettings.cs`, `Server/PluginSpaceSettings.cs`;
  - `Configuration/PluginConfiguration.cs` (`QuotaAlertPercent = 90`);
  - `Configuration/configPage.html`: campo nella sezione Spazio, intero tra 50 e 99.
- Test: `SpaceAlertsTests.cs`, `FakeSpaceSettings.cs`, `PluginSpaceSettingsTests.cs`

**Interfaces:**
- Produces:
  - `int ISpaceSettings.QuotaAlertPercent`: fuori da 50–99 vale 90;
  - `AdminAlert? SpaceService.QuotaAlert()`, che usa `ReadQuota()`. Restituisce `Key = "quota"`, `Type = DiskAlmostFull`, `Percent = floor(Used*100/Limit)` quando `Percent >= QuotaAlertPercent`; null altrimenti e senza quota;
  - `Task<IReadOnlyList<AdminAlert>> SpaceService.LightenAlertsAsync(CancellationToken)`: rinfresca gli stati di Alleggerisci come fa la sezione Alleggerire di GET Space (`SpaceService.Lighten.cs`, il ciclo su `tracked`) sulle righe dell'ultimo calcolo. Poi un alert per ogni riga in `Blocked`: `Key = "lighten:" + key`, `Type = LightenBlocked`, `Title` del titolo. Senza calcolo, nessun alert.

- [ ] **Step 1: test che falliscono**
  - `QuotaAlert_AtThreshold_Returned` (90% esatto);
  - `QuotaAlert_Below_Null`;
  - `QuotaAlert_NoQuotaFile_Null`;
  - `QuotaAlertPercent_OutOfRange_Is90`;
  - `Abort_RaisesSpaceOperationFailed` (`Key = "space-op:" + operation.Id`);
  - `LightenAlerts_BlockedOnly`;
  - `HostedService_PendingTimer_SyncsQuotaAndLighten`: al timer dei torrent in attesa, `SyncAsync("quota", …)` e `SyncAsync("lighten:", …)`. Lo stesso dopo ogni calcolo.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.**
  - Controlla che `SyncAsync("quota", …)` non tocchi altre chiavi: il prefisso `quota` non deve coincidere con nessun'altra chiave.
  - Il disco torna sotto la soglia → la voce sparisce. Quando la supera di nuovo, notifica di nuovo (spec §4.4).
- [ ] **Step 4:** PASS, insieme a tutti i test `Space*`.
- [ ] **Step 5: commit** `feat(plugin): notifiche admin dello spazio e soglia del disco`.

### Task 10: Recupero della password

**Files:**
- Modify: `Account/PasswordRecovery.cs`
- Test: `RecoveryAlertsTests.cs`

**Interfaces:**
- Consumes: `AdminAlerts.RaiseAsync`.

- [ ] **Step 1: test che falliscono**
  - `Start_EligibleUser_RaisesRecoveryStarted`, con `UserName` dell'utente. Parte da `SendCodeAsync` dopo `Eligible(name)`, anche se l'utente non ha contatti;
  - `Start_UnknownOrDisabledOrAdminName_NoAlert`;
  - `SendForAdmin_NoAlert`;
  - `Start_HourOrDayLimitTrips_RaisesBlockedOnce`: `Scope = "User"`. Parte solo se il nome è un utente (`Find(name)` non null), quando dopo i `TryAcquire` di `Start` scatta `RecoveryStartHour` o `RecoveryStartDay`. Le richieste dopo, già rifiutate prima dei `TryAcquire`, non notificano;
  - `Start_GlobalLimitTrips_RaisesBlockedEveryone`: `Scope = "Everyone"`, senza `UserName`;
  - `WrongCodes_FailLimitTrips_RaisesBlocked`: nel punto che oggi scrive "Recupero della password fermato" nel log, con le stesse regole di nome e `Scope`;
  - `Alerts_NeverContainCode`.
  
  Le chiavi sono `"recovery:" + Guid.NewGuid()`: è uno storico.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.** Le chiamate a `RaiseAsync` fuori da `_startLock`, senza aspettarle.
- [ ] **Step 4:** PASS, insieme a tutti i test `*Recovery*`.
- [ ] **Step 5: commit** `feat(plugin): notifiche admin del recupero della password`.

### Task 11: Riavvio richiesto

**Files:**
- Create: `ServerAlertsHostedService.cs`, `Hub/IRestartState.cs`, `Server/JellyfinRestartState.cs`
- Modify: `PluginServiceRegistrator.cs`
- Test: `ServerAlertsHostedServiceTests.cs`

**Interfaces:**
- Produces:
  - `interface IRestartState { bool PendingRestart { get; } }`. Implementazione: `IServerApplicationHost.HasPendingRestart` (da verificare sulla 10.11.0);
  - servizio con un timer ogni 5 minuti (primo giro dopo 1 minuto) che chiama `SyncAsync("restart", pending ? [new("restart", RestartPending, "Jellyfin")] : [])`.

- [ ] **Step 1: test che falliscono**
  - `Pending_RaisesOnce` (due giri, una push);
  - `NoLongerPending_Removes`;
  - `PendingAgain_PushesAgain`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa** con `TimeProvider`, come gli altri hosted service.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(plugin): notifica admin del riavvio richiesto`.

### Task 12: Richiesta accettata e rifiutata

**Files:**
- Modify:
  - `Hub/RequestWebhookHandler.cs` (switch dei tipi);
  - `Hub/InboxService.cs`: `AddRequestApprovedAsync(Guid, RequestEvent)` e `AddRequestDeclinedAsync(Guid, RequestEvent)`, come `AddRequestAvailableAsync`;
  - `README.md` del plugin (sezione Seerr).
- Test: `InboxRequestsTests.cs`, `RequestsServiceTests.cs` o i test del webhook esistenti

**Interfaces:**
- I tipi del webhook di Seerr sono `MEDIA_APPROVED`, `MEDIA_AUTO_APPROVED` e `MEDIA_DECLINED`; i nomi esatti vanno verificati sul payload di Seerr, accanto a `MEDIA_AVAILABLE`/`MEDIA_PENDING`. Il richiedente si trova come in `AvailableAsync`.

- [ ] **Step 1: test che falliscono**
  - `Approved_AddsRequestApprovedToRequester`;
  - `AutoApproved_AddsRequestApproved`;
  - `Declined_AddsRequestDeclined`;
  - `Approved_RequesterUnknown_NoEntry`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.** Nel README aggiungi: in Seerr → Impostazioni → Notifiche → Webhook, attiva anche "Richiesta approvata", "Richiesta approvata automaticamente" e "Richiesta rifiutata".
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(plugin): richiesta accettata e rifiutata nella cassetta`.

### Task 13: Endpoint e Info

**Files:**
- Create: `Api/NotificationsController.cs`, `Protocol/NotificationDtos.cs`
- Modify: `Protocol/WatchPartyProtocol.cs` (`FeaturesWith`: `push` sempre)
- Test: `NotificationsControllerTests.cs`, `InfoControllerTests.cs`

**Interfaces:**
- Consumes: `PushService` (Task 5). `isApprover` viene da `seerrUsers.ManagerJellyfinIdsAsync` (lista vuota se Seerr non è configurato); `isAdmin` dall'utente.
- Produces: gli endpoint e i JSON di "Global Constraints".

- [ ] **Step 1: test che falliscono**
  - `Get_UserSeesEveryoneTypesOnly`;
  - `Get_AdminSeesAdminTypes`;
  - `Get_ApproverSeesRequestPending`;
  - `Get_ReturnsVapidPublicKey`;
  - `Put_UnknownOrHiddenType_400`;
  - `Subscribe_StoresDeviceIdFromAuth`;
  - `Subscribe_NonHttpsEndpoint_400`;
  - `Subscribe_BadKeys_400`;
  - `Unsubscribe_OnlyCallers`;
  - `Info_HasPushFeature`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa** con `FakeAuthorizationContext`, come gli altri controller.
- [ ] **Step 4:** PASS, e poi tutta la suite.
- [ ] **Step 5: commit** `feat(plugin): endpoint delle notifiche`.

### Task 14: Versione, documenti e prova sul server

**Files:**
- Modify:
  - `Jellyfin.Plugin.WonderFlixWatchParty.csproj` (versione 1.17.0);
  - test della versione in `InfoControllerTests.cs`;
  - `README.md`;
  - la spec: stato, esito del Task 1 e decisioni 1–5 di questo piano.

- [ ] **Step 1:** versione 1.17.0 e test della versione.
- [ ] **Step 2:** tutta la suite. Expected: PASS.
- [ ] **Step 3: pacchetto a mano e prova sul seedbox.**
  1. `bash plugin/pack.sh 1.17.0`.
  2. Copia la cartella in `~/.apps/jellyfin/data/plugins/` e riavvia con `app-jellyfin restart`.
  3. `curl` autenticato su `GET WonderFlixWatchParty/Notifications`. Expected: 200 con `VapidPublicKey` lunga 87 caratteri.
  4. In `~/.apps/jellyfin/log/` nessun errore del plugin all'avvio.
- [ ] **Step 4: commit** `chore(plugin): versione 1.17.0 con le notifiche push`.
