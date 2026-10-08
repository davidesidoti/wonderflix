# WonderFlix — Spec L: recupero e cambio della password

- **Data:** 2026-10-09
- **Stato:** approvato nel brainstorming; piani da scrivere
- **Ambito:** Spec L. Realizza l'idea 5 di `docs/IDEE.md` ("Recupero e cambio della password") al livello più ampio: cambio della propria password nell'app, reset da parte dell'admin nell'app e **recupero in autonomia** con un codice mandato su **Discord o per email**. Solo nell'app WonderFlix: il "Password dimenticata" di jellyfin-web resta com'è.

## 1. Obiettivo

- **Cambio password.** Ogni utente cambia la sua password da Impostazioni → Account, con la password attuale.
- **Contatti per il recupero.** Ogni utente collega e verifica il suo account Discord, la sua email o tutti e due.
- **Recupero in autonomia.** Al login, "Password dimenticata?" manda un codice ai contatti verificati; con il codice l'utente sceglie una nuova password ed entra.
- **Admin.** In Amministrazione una scheda Utenti: impostare una password, mandare un codice di recupero, scollegare i contatti. Nella scheda WonderFlix lo stato dei canali e una prova d'invio.
- **Adozione.** Chi non ha contatti verificati riceve ogni N giorni un promemoria nella cassetta.

Non è il classico "password dimenticata" dei siti con il link per email: il codice arriva su Discord o per email, ma si scrive nell'app, e la nuova password si sceglie nell'app. Il contatto va collegato e verificato prima, da loggati: senza un contatto verificato il recupero non parte e resta l'admin.

## 2. Situazione di partenza

App 0.11.0, plugin 1.5.0, Jellyfin 10.11.9 su Ultra.cc dietro il proxy.

### 2.1 App

- **Login.** `PasswordLoginForm` (`lib/features/auth/password_login_form.dart`) mostra "Password dimenticata?" (`loginForgotPassword`) solo se c'è `supportUrl` (invito Discord in `config/wonderflix.json`) e apre quel link. `AuthApi` (`lib/core/jellyfin/auth_api.dart`) ha solo `authenticateByName`.
- **Impostazioni.** `SettingsScreen` ha le sezioni Aspetto, Player, Lingua, Discord, Supporto. Nessuna sezione sull'account, nessun cambio password.
- **Amministrazione.** `AdminTab` (`lib/features/admin/admin_navigation.dart`): `sessions`, `maintenance`, `activity`, `wonderflix`. Nessuna scheda sugli utenti. La scheda WonderFlix ha le schede Annuncio, Titoli nuovi, Seerr (stato e "Prova").
- **Cassetta.** `InboxEntry` (`lib/core/social/inbox_models.dart`) è sealed: `Invite`, `Announcement`, `NewTitles`, `RequestAvailable`, `RequestPending`, scelti da `Type`.
- **Funzioni del plugin.** `SocialAvailability` (`lib/features/social/social_providers.dart`) legge `Info.Features` e ne ricava `SocialFeatures`.
- **Profili (Spec K).** `ProfileStore` (`lib/core/storage/profile_store.dart`) tiene un token per ogni account salvato sul PC; un token rifiutato fa chiedere di nuovo la password a quel profilo.

### 2.2 Plugin 1.5.0

- Logica in `Hub/` (e `Seerr/`) con interfacce, adattatori Jellyfin in `Server/`, controller in `Api/` sotto `WonderFlixWatchParty/`.
- File di dati in `PluginConfigurationsPath/<FriendStore.FolderName>/` (`friends.json`, `inbox.json`), con spostamento in `.bad` se illeggibili.
- `RateLimiter` (`Hub/RateLimiter.cs`) con limiti per chiave e tipo; `InboxService` con le voci della cassetta (durata massima 30 giorni, `Cleanup`).
- `PluginConfiguration` + `configPage.html` nella Dashboard: Annuncio, Titoli nuovi, Seerr (URL, chiave API, segreto del webhook, "Prova").
- Errori verso l'app come stato HTTP + `{Code}` (`RequestsController.Error`).
- `JellyfinUserDirectory` chiede gli utenti via riflessione (`UserListing`) perché `IUserManager` è cambiato tra 10.11.0 e le 10.11.x successive.
- Nessun bot Discord, nessuna email.

### 2.3 Server

- Il "Password dimenticata" di jellyfin-web scrive un PIN in `passwordreset*.json` nella cartella dati, valido 30 minuti, leggibile solo da chi entra nel server. Al 2026-10-08 ce n'erano 5, tutti scaduti: per un amico il recupero non ha mai funzionato.
- Dietro il proxy di Ultra.cc Jellyfin vede le richieste come locali (il `ForgotPassword` di jellyfin-web le accetta): l'IP del client non è affidabile per i limiti.
- Esiste un server Discord (l'invito di `supportUrl`) e un'app Discord (`discordAppId` 1397884246692986970, usata per Rich Presence).

## 3. Jellyfin: cosa offre

Verificato sul ramo `release-10.11.z` (da confermare sui riferimenti 10.11.9, §14).

- **`POST /Users/Password`** (e il vecchio `POST /Users/{userId}/Password`), corpo `{CurrentPw, NewPw, ResetPassword}`:
  - la password attuale serve se chi chiama non è admin **o** cambia la propria;
  - un admin che cambia quella di un altro non la deve conoscere;
  - dopo `ChangePassword` chiama `RevokeUserTokens(user.Id, tokenAttuale)`: chiude le sessioni dell'utente tranne quella che ha fatto la richiesta;
  - `ResetPassword: true` lascia la password **vuota** e non chiude nessuna sessione: l'app non lo usa.
- **`IUserManager`**: `Task ChangePassword(Guid userId, string newPassword)`, `User? GetUserByName(string name)`, `User? GetUserById(Guid id)`, `IEnumerable<User> GetUsers()`.
- **`ISessionManager`**: `Task RevokeUserTokens(Guid userId, string currentAccessToken)`. Con `string.Empty` le chiude tutte.
- **Provider di reset** (`IPasswordResetProvider`): scartato (§4), il recupero resta fuori dal flusso di Jellyfin.

## 4. Decisioni

| Tema | Decisione | Perché |
|---|---|---|
| Livello | Cambio + reset admin + recupero in autonomia | L'utente ha scelto il recupero senza passare dall'admin. |
| Canali | Discord **ed** email; ognuno collega quelli che vuole | Gli amici sono su Discord, ma l'email copre chi non lo usa. |
| Verifica del contatto | Codice a 6 cifre mandato al contatto e scritto nell'app | Stesso flusso per i due canali; il plugin invia soltanto, non riceve. |
| Perimetro | Solo WonderFlix | Il flusso di jellyfin-web imposta il PIN come password, va assegnato utente per utente e dipende dalla "rete locale". |
| Architettura | Tutto nel plugin: Discord via REST con `HttpClient`, email via `System.Net.Mail` | Nessun servizio in più da tenere vivo, nessuna connessione Gateway, nessuna DLL in più nel pacchetto. |
| Discord | Bot sull'app Discord esistente, ricerca del membro per nome utente nel server | L'app c'è già; basta aggiungere il bot e l'intent "Server Members". |
| Email | SMTP con STARTTLS (porta 587) | `System.Net.Mail` non fa il TLS implicito della 465; Gmail, Brevo e Resend vanno bene sulla 587. |
| Admin | Niente recupero in autonomia per gli account admin | Con un token del bot rubato o un Discord compromesso si prenderebbe il server. |
| Limiti | Per nome utente scritto e globali, non per IP | Dietro il proxy tutte le richieste hanno lo stesso IP. |
| Adozione | Promemoria nella cassetta ogni N giorni (14) finché non c'è un contatto verificato | Scelto dall'utente. |
| Segreti | Nella pagina del plugin della Dashboard, come Seerr | Il file lo leggono solo gli admin; non passano mai dall'app. |

## 5. Perimetro

### Incluso

- Plugin 1.6.0: modulo `Account/` (contatti, codici, invio Discord ed email, recupero, admin, promemoria), endpoint, configurazione nella Dashboard, funzione `account` in `Info`.
- App: Impostazioni → Account (cambio password, contatti), "Password dimenticata?" al login, voce `ContactReminder` nella cassetta, scheda Amministrazione → Utenti, scheda "Recupero password" in Amministrazione → WonderFlix.
- Testi in italiano e inglese, nell'app e nei messaggi del plugin.

### Escluso

- Il "Password dimenticata" di jellyfin-web e delle app ufficiali (restano col PIN nel file).
- Collegare Discord con OAuth o con un comando dentro Discord.
- Altri canali (Telegram, SMS) e il TLS implicito sulla porta 465.
- Recupero in autonomia per gli admin.
- Regole sulla forza della password oltre la lunghezza minima.
- Mostrare all'admin i PIN di jellyfin-web.

## 6. Architettura

```
App (AccountApi)                    Plugin 1.6.0
────────────────                    ────────────
Impostazioni → Account   ─┐         Api/AccountController       (utente)
Login → recupero         ─┼──────▶  Api/RecoveryController      (anonimo)
Amministrazione          ─┘         Api/AccountAdminController  (admin)
                                              │
                                              ▼
                                    Account/AccountService
                                      ├─ ContactStore      → contacts.json
                                      ├─ CodeBook          (memoria)
                                      ├─ RateLimiter
                                      ├─ IDiscordSender    → Discord REST
                                      ├─ IMailSender       → SMTP
                                      └─ IPasswordReset    → IUserManager, ISessionManager

Cassetta  ◀── InboxService ◀── Account/ContactReminderHostedService

App (AuthApi): cambio password, "Imposta password" ──▶ Jellyfin POST /Users/Password
```

- **Il cambio della propria password e "Imposta password" dell'admin** passano dall'API di Jellyfin, senza il plugin.
- **Tutto il resto** (contatti, codici, recupero, invio di codici dall'admin, stato) passa dal plugin.

## 7. Plugin 1.6.0

Nuova cartella `Account/` per la logica (non conosce Jellyfin), adattatori in `Server/`, controller in `Api/`.

### 7.1 Configurazione

Nuove proprietà di `PluginConfiguration`:

| Proprietà | Valore iniziale | Note |
|---|---|---|
| `DiscordBotToken` | vuoto | Token del bot. |
| `DiscordGuildId` | vuoto | ID del server Discord dove cercare i membri. |
| `SmtpHost` | vuoto | |
| `SmtpPort` | 587 | |
| `SmtpUser`, `SmtpPassword` | vuoti | |
| `MailFrom` | vuoto | Indirizzo del mittente; nome visualizzato "WonderFlix". |
| `ContactReminderDays` | 14 | 0 spegne i promemoria. |

- **Discord configurato:** token e ID del server non vuoti. **Email configurata:** host, utente, password e mittente non vuoti.
- `IAccountSettings` (adattatore `PluginAccountSettings`, come `PluginSeerrSettings`) legge la configurazione corrente a ogni uso: un cambio nella Dashboard vale subito.
- **`configPage.html`**: nuova parte "Password recovery" con i campi qui sopra (token e password SMTP come campi password) e un pulsante "Test" che chiama `POST Account/Admin/Test` e mostra l'esito.

### 7.2 Dati

**`ContactStore`** — file `contacts.json` accanto a `inbox.json`, stesse regole (scrittura atomica, `.bad` se illeggibile):

```json
{
  "Users": {
    "<userId>": {
      "Discord": { "Id": "123456789012345678", "Name": "garg", "VerifiedAt": "2026-10-09T10:00:00Z" },
      "Email": { "Address": "a@example.com", "VerifiedAt": "2026-10-09T10:05:00Z" },
      "LastReminderAt": "2026-10-01T09:00:00Z"
    }
  }
}
```

- Nel file entrano solo contatti **verificati**; un contatto in attesa vive nel `CodeBook`.
- Un utente cancellato da Jellyfin viene tolto al primo giro dei promemoria.

**`CodeBook`** — solo in memoria, thread-safe, con `TimeProvider`:

- voce per `(userId, scopo)`, dove lo scopo è `VerifyDiscord`, `VerifyEmail` o `Recovery`;
- contiene: hash `SHA-256(sale + codice)`, sale casuale di 16 byte, scadenza (10 minuti), tentativi rimasti (5), e per le verifiche il contatto in attesa (ID e nome Discord, oppure indirizzo);
- un nuovo codice per lo stesso `(userId, scopo)` sostituisce il precedente;
- confronto con `CryptographicOperations.FixedTimeEquals`; al quinto errore la voce sparisce; scaduta = assente;
- codice: 6 cifre da `RandomNumberGenerator.GetInt32(0, 1_000_000)`, con gli zeri iniziali;
- dopo l'uso la voce sparisce.

### 7.3 Invio

**`IDiscordSender`** (`Server/DiscordBotClient`, `HttpClient` su `https://discord.com/api/v10`, intestazione `Authorization: Bot <token>`):

- `FindMemberAsync(name)`: `GET /guilds/{guildId}/members/search?query=<name>&limit=10`. Tiene solo il membro il cui `user.username` coincide **esattamente** con il nome scritto (senza `@` iniziale, maiuscole e minuscole indifferenti). Restituisce ID e nome utente, oppure "non trovato".
- `SendDmAsync(userId, text)`: `POST /users/@me/channels {recipient_id}`, poi `POST /channels/{id}/messages {content}`. L'errore 50007 ("Cannot send messages to this user") diventa `DmClosed`; ogni altro errore o un 429 diventano `SendFailed`.
- `CheckAsync()`: `GET /users/@me` e `GET /guilds/{guildId}`; dice se token e server sono validi.
- Timeout di 10 s per ogni richiesta.

**`IMailSender`** (`Server/SmtpMailSender`, `System.Net.Mail.SmtpClient`, `EnableSsl = true`, credenziali di rete):

- `SendAsync(to, subject, text)`: messaggio di solo testo, mittente `WonderFlix <MailFrom>`. Ogni eccezione diventa `SendFailed`; timeout di 15 s.

**Messaggi** (`Account/AccountMessages`, italiano e inglese; la lingua arriva dalla richiesta, `it` se manca o è sconosciuta). Esempi in italiano:

- Verifica: *"Il tuo codice WonderFlix per collegare questo account è 123456. Scade tra 10 minuti. Se non l'hai chiesto tu, ignora questo messaggio."*
- Recupero: *"Il tuo codice WonderFlix per cambiare la password di «garg» è 123456. Scade tra 10 minuti. Se non l'hai chiesto tu, ignora questo messaggio: la password non cambia finché il codice non viene usato."*
- Password cambiata: *"La password WonderFlix di «garg» è stata cambiata. Se non sei stato tu, scrivi all'amministratore."*
- Prova: *"Messaggio di prova di WonderFlix: il canale funziona."*

L'oggetto delle email è "WonderFlix — codice" oppure "WonderFlix — password cambiata", e "WonderFlix — prova" per la prova.

**Ultimo errore.** `AccountService` ricorda l'ultimo errore d'invio per canale (ora e tipo, senza il destinatario), mostrato nello stato dell'admin.

### 7.4 `AccountService`

Dipende da `ContactStore`, `CodeBook`, `RateLimiter`, `IDiscordSender`, `IMailSender`, `IAccountSettings`, `IUserDirectory` (esteso con `IsAdmin`), `IPasswordReset`, `InboxService`, `TimeProvider`.

**Collegamento (utente autenticato)**

1. `StartLinkAsync(userId, channel, target, language)`:
   - canale non configurato → `ChannelOff`;
   - limite superato → `RateLimited`;
   - Discord: `target` ripulito (spazi, `@`), poi `FindMemberAsync`; non trovato → `MemberNotFound`;
   - email: `target` ripulito e controllato con `MailAddress` e una forma `x@y.z`, al massimo 254 caratteri; altrimenti `InvalidTarget`;
   - nuovo codice `Verify<canale>` con il contatto in attesa, poi invio **in attesa della risposta**: `DmClosed` o `SendFailed` tolgono il codice e tornano all'app. Così l'utente sa subito se il canale funziona.
2. `ConfirmLinkAsync(userId, channel, code)`: codice giusto → il contatto entra in `ContactStore` con `VerifiedAt`, e i promemoria dell'utente spariscono dalla cassetta. Codice sbagliato → `InvalidCode` (lo stesso per sbagliato, scaduto o assente).
3. `UnlinkAsync(userId, channel)`: toglie il contatto.

**Recupero (anonimo)**

1. `StartRecovery(username, language)`:
   - limiti per nome scritto (normalizzato: senza spazi ai lati, in minuscolo) e globale; superati → `RateLimited`, indipendentemente dall'esistenza dell'utente;
   - altrimenti risponde subito e manda in background (`Task.Run`, eccezioni nel log): utente esistente, attivo, non admin, con almeno un contatto verificato su un canale configurato → nuovo codice `Recovery` mandato a tutti quei contatti; negli altri casi non succede niente.
2. `CompleteRecoveryAsync(username, code, newPassword)`:
   - limite errori per nome → `RateLimited`;
   - `newPassword` di almeno 6 caratteri, altrimenti `WeakPassword`. Il controllo viene prima del codice, così non consuma tentativi;
   - utente inesistente, disattivato, admin, codice assente o sbagliato → `InvalidCode` (un errore conta per il limite);
   - codice giusto → `IPasswordReset.ResetAsync(userId, newPassword)` (`ChangePassword`, poi `RevokeUserTokens(userId, string.Empty)`), poi in background l'avviso "password cambiata" agli stessi contatti.

**Admin**

- `AdminUsers()`: per ogni utente ID, nome, admin, attivo, Discord (nome) ed email **mascherata** (`a•••@gmail.com`: prima lettera, `•••`, dominio intero), `LastReminderAt`.
- `AdminSendRecoveryAsync(userId, language)`: come il recupero ma con la risposta vera:
  - utente admin → `NotAllowed`;
  - nessun contatto verificato su un canale configurato → `NoContacts`;
  - nessun invio riuscito → `SendFailed`;
  - altrimenti ok, con i canali usati. Non passa dai limiti del recupero.
- `AdminUnlinkAsync(userId)`: toglie tutti i contatti.
- `Status()`: per canale configurato sì/no e ultimo errore; quanti utenti attivi non admin hanno almeno un contatto, su quanti.
- `TestAsync(adminId, language)`: Discord: `CheckAsync`, poi, se l'admin ha Discord verificato, un DM di prova. Email: se l'admin ha l'email verificata, una mail di prova. Restituisce per canale `Ok`, `NotConfigured`, `NoContact`, `Invalid` (token o server sbagliati) o `SendFailed`.

### 7.5 Limiti

Nuovi tipi nel `RateLimiter`:

| Tipo | Chiave | Limite |
|---|---|---|
| `RecoveryStart` | nome scritto normalizzato | 1 al minuto e 5 all'ora |
| `RecoveryStartGlobal` | `*` | 30 all'ora |
| `RecoveryFail` | nome scritto normalizzato | 10 errori all'ora; superati, il recupero di quel nome si ferma finché la finestra non si libera |
| `LinkStart` | userId | 1 al minuto e 5 all'ora |

Il `RateLimiter` di oggi ha un solo limite per tipo: le coppie "al minuto e all'ora" sono due tipi (per esempio `RecoveryStartMinute`, `RecoveryStartHour`). Per `RecoveryFail` si conta solo un errore, quindi serve un "controlla senza contare" (`IsLimited`) accanto a `TryAcquire`.

### 7.6 Endpoint

Base `WonderFlixWatchParty/Account`. JSON in PascalCase come il resto del plugin. Errori come `{Code}` con lo stato indicato.

**Utente** (`[Authorize]`, `AccountController`)

| Metodo e percorso | Corpo | Esito |
|---|---|---|
| `GET Contacts` | — | 200 `{Channels: {Discord, Email}, Discord: {Name, VerifiedAt}?, Email: {Address, VerifiedAt}?}` (l'email dell'utente stesso, intera) |
| `POST Contacts/{Discord\|Email}/Start` | `{Target, Language}` | 202 `{ExpiresAt}` · 400 `InvalidTarget` · 404 `MemberNotFound` · 409 `DmClosed` · 502 `SendFailed` · 503 `ChannelOff` · 429 `RateLimited` |
| `POST Contacts/{canale}/Confirm` | `{Code}` | 200 come `GET Contacts` · 400 `InvalidCode` |
| `DELETE Contacts/{canale}` | — | 204 |

**Recupero** (`[AllowAnonymous]`, `RecoveryController`, controller a parte perché un `[Authorize]` sulla classe non si allarga)

| Metodo e percorso | Corpo | Esito |
|---|---|---|
| `POST Recovery/Start` | `{Username, Language}` | 202 sempre · 429 `RateLimited` · 400 `Invalid` se `Username` è vuoto o più lungo di 256 |
| `POST Recovery/Complete` | `{Username, Code, NewPassword}` | 204 · 400 `InvalidCode` · 400 `WeakPassword` · 429 `RateLimited` |

**Admin** (`[Authorize(Policy = Policies.RequiresElevation)]`, `AccountAdminController`)

| Metodo e percorso | Corpo | Esito |
|---|---|---|
| `GET Admin/Users` | — | 200 `[{Id, Name, IsAdmin, Enabled, Discord: {Name}?, Email: {Masked}?, LastReminderAt?}]` |
| `POST Admin/Users/{id}/Recovery` | `{Language}` | 200 `{Channels: [...]}` · 403 `NotAllowed` · 404 · 409 `NoContacts` · 502 `SendFailed` |
| `DELETE Admin/Users/{id}/Contacts` | — | 204 · 404 |
| `GET Admin/Status` | — | 200 `{Discord: {Configured, LastError?}, Email: {Configured, LastError?}, WithContacts, Users, ReminderDays}` |
| `POST Admin/Test` | `{Language}` | 200 `{Discord, Email}` con gli esiti di §7.4 |

`LastError` = `{At, Code}` con `Code` fra `DmClosed`, `SendFailed`, `Invalid`.

### 7.7 Promemoria

`ContactReminderHostedService` (come `NewTitlesHostedService`): primo giro 5 minuti dopo l'avvio, poi ogni 24 ore.

- `ContactReminderDays` = 0, oppure nessun canale configurato → niente.
- Per ogni utente attivo non admin senza contatti verificati, con `LastReminderAt` assente o più vecchio di N giorni:
  - toglie dalla sua cassetta le voci `ContactReminder` precedenti;
  - aggiunge una voce `ContactReminder` (`{Type: "ContactReminder", Id, Seq, CreatedAt, Read: false, Channels: ["Discord", "Email"]}` con i canali configurati);
  - aggiorna `LastReminderAt`.
- `InboxService` riceve `AddContactReminderAsync(userId, channels)` e `RemoveContactRemindersAsync(userId)`.

### 7.8 `Info` e versione

- `WatchPartyProtocol.Features` riceve `account` (sempre presente nel plugin 1.6.0, anche con i canali spenti: il cambio di stato lo dice `Contacts.Channels`).
- Plugin **1.6.0.0**: `.csproj`, `build.yaml`, manifesto, readme.

## 8. Sicurezza

- **Account nascosti.** `Recovery/Start` risponde prima di inviare; `Recovery/Complete` dà lo stesso `InvalidCode` per ogni causa. I limiti del recupero valgono per il nome scritto, che esista o no.
- **Codici.** Vedi §7.2: casuali crittografici, salvati come hash, a tempo costante, 10 minuti, 5 tentativi, sostituiti da un nuovo invio, persi al riavvio.
- **Sessioni.** Dopo un recupero tutte le sessioni dell'utente si chiudono; dopo un cambio dall'app o "Imposta password" ci pensa Jellyfin (§3).
- **Avvisi.** Dopo un recupero riuscito arriva "password cambiata" su tutti i contatti verificati.
- **Admin.** Nessun recupero in autonomia, nessun promemoria; possono collegare i contatti per la prova. Un admin che perde la password rimedia via SSH o con un altro admin.
- **Utenti disattivati.** Nessun codice, nessun promemoria.
- **Password nuove.** Almeno 6 caratteri, sia nell'app sia nel plugin (`Recovery/Complete`).
- **Contatti condivisi.** Lo stesso Discord o la stessa email possono stare su più account: collegarli richiede comunque il codice.
- **Segreti.** Token del bot e password SMTP solo nel file di configurazione del plugin (letto dagli admin); l'app vede solo `Configured`.
- **Log.** Il plugin non scrive codici, password o email complete; l'ID Discord e lo username sì (servono per capire gli errori). Nell'app `redact.dart` copre i nuovi corpi delle richieste (`Code`, `NewPassword`, `CurrentPw`, `NewPw`, `Target`).

## 9. App

### 9.1 Client e disponibilità

- **`AccountApi`** (`lib/core/social/account_api.dart`, sul client del plugin come `SocialApi`): i metodi degli endpoint di §7.6, con errori tipizzati (`AccountError` con i `Code`). Le chiamate di `Recovery/*` partono senza token: servono un client senza sessione (lo stesso usato per il login).
- **`AuthApi`**: `changePassword(userId, currentPw, newPw)` → `POST /Users/Password?userId=` con `{CurrentPw, NewPw}`; lo stesso per l'admin, senza `CurrentPw`.
- **`SocialFeatures.account`**: dalla funzione `account` di `Info`.
- **Prima del login** non c'è `Info` (serve un token): l'app prova `POST Recovery/Start` e, con un 404 (plugin vecchio, rotta assente), mostra il messaggio con il link `supportUrl` invece della risposta neutra.

### 9.2 Impostazioni → Account

Nuova sezione in cima a Impostazioni, `AccountSettingsSection`.

**Cambia password** → finestra con password attuale, nuova, conferma:

- nuova di almeno 6 caratteri e uguale alla conferma, altrimenti l'errore sotto il campo;
- per un account senza password la password attuale resta vuota (è un campo normale, si lascia vuoto);
- 403 → "Password attuale sbagliata";
- ok → avviso "Password cambiata. Gli altri dispositivi dovranno rientrare." Il profilo di questo PC tiene il suo token.

**Contatti per il recupero** (solo con `SocialFeatures.account`), una riga per canale:

- stato: "Non collegato" / "Collegato: garg" / "Collegato: a@example.com"; canale spento → riga grigia "Non disponibile su questo server";
- azioni: *Collega* (o *Cambia*), *Scollega* (con conferma);
- *Collega* apre una finestra a due passi:
  1. campo "Nome utente Discord" oppure "Email" e "Invia codice";
  2. "Ti abbiamo mandato un codice su Discord / a a@example.com", campo per le 6 cifre, "Conferma" e "Rimanda il codice" (attivo dopo 60 s);
- gli errori di §7.6 diventano testi (§10), mostrati nella finestra.

Testo sotto le righe: "Servono per recuperare la password se la dimentichi. Gli admin non possono usare il recupero automatico." (la seconda frase solo per gli admin).

### 9.3 Login → "Password dimenticata?"

- Il link compare sempre (non più solo con `supportUrl`) e apre `/login/recover` (rotta fuori dalla shell, come `/login`).
- **Passo 1:** campo nome utente (precompilato da quello del login), "Invia codice". Risposta: "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato un codice su Discord o per email." 429 → "Aspetta un momento prima di riprovare". Plugin vecchio → il messaggio di §9.1.
- **Passo 2:** codice, nuova password, conferma, "Cambia password". "Rimanda il codice" dopo 60 s.
  - 204 → login con la nuova password (`SessionController.loginWithPassword`): l'app entra e aggiorna il profilo salvato;
  - `InvalidCode` → "Codice non valido o scaduto";
  - `WeakPassword` → errore sotto il campo;
  - 429 → "Troppi tentativi: riprova tra un'ora o contatta l'amministratore".
- Sotto: "Nessun contatto collegato? Contatta l'amministratore" (link `supportUrl`, se c'è).
- Si torna al login con la freccia indietro.

### 9.4 Cassetta

- `ContactReminderEntry` (`Type: "ContactReminder"`, `channels`).
- Riga: icona `LucideIcons.shieldCheck`, "Proteggi il tuo account", "Collega Discord o la tua email per recuperare la password se la dimentichi." (solo i canali disponibili).
- Clic → `/settings?section=account` (scorre alla sezione Account). Si cancella come le altre voci.

### 9.5 Amministrazione → Utenti

- `AdminTab.users`, fra Sessioni e Manutenzione, solo con `SocialFeatures.account`.
- Elenco da `GET Admin/Users`, in ordine di nome: `UserAvatar`, nome, etichetta "Admin" / "Disattivato", icone Discord ed email (piene se collegate, con nome / email mascherata nel tooltip).
- Menu della riga:
  - **Imposta password** → finestra con nuova password e conferma; `changePassword` senza `CurrentPw`; avviso "Password impostata. Le sessioni di garg sono state chiuse.";
  - **Invia codice di recupero** (non per gli admin, solo con almeno un contatto) → conferma, poi "Codice mandato su Discord ed email" oppure l'errore;
  - **Scollega contatti** (solo con contatti) → conferma con `AdminConfirmDialog`.
- Aggiornamento all'apertura della scheda e dopo ogni azione (niente `AdminPoller`).

### 9.6 Amministrazione → WonderFlix: "Recupero password"

Nuova scheda accanto a Seerr:

- Discord: "Configurato" / "Non configurato"; email lo stesso; l'eventuale ultimo errore con l'ora ("Ultimo errore: DM chiusi, 2 ore fa").
- "5 utenti su 23 hanno un contatto", "Promemoria ogni 14 giorni" (o "Promemoria spenti").
- "Invia prova a me" → esiti per canale ("Discord: inviato", "Email: collega prima la tua email", "Discord: token o server non validi").
- Nessun campo modificabile: la configurazione è nella Dashboard ("Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix").

## 10. Testi nuovi (ARB, it + en)

Italiano (l'inglese segue):

- Impostazioni: "Account", "Cambia password", "Password attuale", "Nuova password", "Conferma la password", "Almeno 6 caratteri", "Le password non coincidono", "Password attuale sbagliata", "Password cambiata. Gli altri dispositivi dovranno rientrare.", "Contatti per il recupero", "Non collegato", "Collegato: {nome}", "Non disponibile su questo server", "Collega", "Cambia", "Scollega", "Scollegare {canale}?", "Nome utente Discord", "Email", "Invia codice", "Ti abbiamo mandato un codice su Discord", "Ti abbiamo mandato un codice a {email}", "Codice", "Conferma", "Rimanda il codice", "Rimanda tra {secondi} s", "Servono per recuperare la password se la dimentichi.", "Gli admin non possono usare il recupero automatico."
- Errori: "Non ti trovo nel server Discord: usa il nome utente (non il nome visualizzato) e controlla di essere nel server", "Il bot non riesce a scriverti: in Discord abilita i messaggi diretti dai membri del server", "Email non valida", "Invio non riuscito, riprova più tardi", "Aspetta un momento prima di riprovare", "Codice non valido o scaduto", "Troppi tentativi: riprova tra un'ora o contatta l'amministratore".
- Recupero: "Recupera la password", "Nome utente", "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato un codice su Discord o per email.", "Cambia password", "Nessun contatto collegato? Contatta l'amministratore", "Il recupero automatico non è disponibile su questo server: contatta l'amministratore".
- Cassetta: "Proteggi il tuo account", "Collega Discord o la tua email per recuperare la password se la dimentichi.", "Collega Discord per recuperare la password se la dimentichi.", "Collega la tua email per recuperare la password se la dimentichi."
- Admin: "Utenti", "Admin", "Disattivato", "Imposta password", "Password impostata. Le sessioni di {nome} sono state chiuse.", "Invia codice di recupero", "Mandare a {nome} un codice per cambiare la password?", "Codice mandato su {canali}", "{nome} non ha contatti collegati", "Gli admin non possono usare il recupero automatico", "Scollega contatti", "Scollegare Discord ed email di {nome}?", "Recupero password", "Configurato", "Non configurato", "Ultimo errore: {errore}, {quando}", "{n} utenti su {totale} hanno un contatto", "Promemoria ogni {n} giorni", "Promemoria spenti", "Invia prova a me", "Inviato", "Collega prima il tuo contatto", "Token o server non validi", "Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix".

## 11. Errori e casi limite

- **Discord, nome non esatto.** La ricerca di Discord va per prefisso: senza una corrispondenza esatta dello username → `MemberNotFound`. Il nome visualizzato non vale.
- **Discord, intent mancante.** Se "Server Members" non è attivo la ricerca risponde con un errore: `SendFailed` all'utente, `Invalid` nella prova dell'admin.
- **DM chiusi** (50007) → `DmClosed` al collegamento. Se l'utente chiude i DM dopo, il recupero fallisce in silenzio per l'utente; l'admin vede l'errore nella scheda.
- **Discord in 429.** Trattato come `SendFailed`, senza ritentare.
- **SMTP in errore.** `SendFailed`; la causa precisa va nel log del plugin.
- **Plugin vecchio.** Niente righe dei contatti, niente scheda Utenti, niente voce nella cassetta; il cambio password funziona; il recupero mostra il link `supportUrl` (§9.1).
- **Canali spenti dopo il collegamento.** I contatti restano; il recupero usa solo i canali configurati; nessun canale → nessun codice (risposta neutra lo stesso).
- **Profili salvati (Spec K).** Cambio dall'app: questo PC tiene il token. Recupero: login nuovo e profilo aggiornato. Altri PC: token rifiutato, nuovo login.
- **Utente rinominato.** I contatti sono legati all'ID, non al nome.
- **Utente diventato admin.** Il recupero si ferma; i contatti restano.
- **Riavvio del server.** I codici si perdono ("Codice non valido o scaduto", se ne chiede un altro); contatti e `LastReminderAt` restano.
- **Promemoria cancellato a mano.** Il prossimo arriva dopo N giorni da quello cancellato.
- **Due richieste di collegamento insieme** (Discord ed email) → due codici con scopi diversi, nessun conflitto.

## 12. Test

**Plugin** (xUnit, TDD):

- `CodeBook`: codice di 6 cifre, hash e sale, scadenza a 10 minuti con `FakeTimeProvider`, 5 tentativi, sostituzione, uso singolo.
- `ContactStore`: lettura, scrittura, file illeggibile in `.bad`, utenti spariti.
- `RateLimiter`: nuovi tipi, `IsLimited`.
- `AccountService` con oggetti finti:
  - collegamento: canale spento, membro non trovato, DM chiusi (il codice sparisce), email non valida, conferma giusta e sbagliata, promemoria tolti;
  - recupero: risposta uguale per utente inesistente, disattivato, admin, senza contatti; codice a tutti i contatti; limiti per nome e globali; `WeakPassword` prima del codice; `ChangePassword` + `RevokeUserTokens(id, "")`; avviso "password cambiata";
  - admin: elenco con email mascherata, invio a un admin vietato, senza contatti, scollegamento, stato, prova.
- `DiscordBotClient` con un `HttpMessageHandler` finto: corrispondenza esatta fra più risultati, `@` iniziale, 50007, 401, 429, timeout.
- `AccountMessages`: italiano e inglese, lingua sconosciuta → italiano.
- Promemoria: N, canali spenti, admin e disattivati esclusi, sostituzione della voce, `LastReminderAt`.
- Controller: stati HTTP e `{Code}` di §7.6, `[AllowAnonymous]` solo sul recupero, `RequiresElevation` sull'admin.

**App** (TDD):

- `AccountApi`: corpi, rotte, errori tipizzati; `AuthApi.changePassword`.
- `redact.dart`: i nuovi campi non finiscono nei log.
- `ContactReminderEntry` nel parser della cassetta.
- Widget: sezione Account (stati delle righe, finestra a due passi, errori, "Rimanda" a tempo), cambio password, schermata di recupero (passi, risposta neutra, plugin vecchio, login finale), voce della cassetta (testi per canali, navigazione), scheda Utenti (righe, menu per admin e non admin, azioni), scheda "Recupero password".
- Testi in `app_it.arb` e `app_en.arb` con le stesse chiavi.

**Prova a mano sul server:**

1. Configurazione nella Dashboard e "Test".
2. Collegare Discord (nome sbagliato, nome giusto, codice sbagliato, codice giusto) ed email.
3. Recupero dal login con un account di prova; la sessione su un secondo dispositivo si chiude; avviso "password cambiata".
4. Dall'admin: "Invia codice di recupero", "Imposta password", "Scollega contatti".
5. Promemoria con `ContactReminderDays` basso (1) e un utente senza contatti; sparisce dopo il collegamento.
6. Cambio della propria password; il profilo su questo PC resta dentro.

## 13. Preparazione (a cura dell'utente)

Credenziali e consensi li gestisce l'utente.

- **Discord:** nel Developer Portal, sull'app 1397884246692986970, aggiungere il bot, copiare il token, attivare l'intent "Server Members"; invitare il bot nel server (scope `bot`, nessun permesso speciale); copiare l'ID del server (modalità sviluppatore → clic destro sul server).
- **Email:** scegliere un SMTP sulla 587 (per esempio una password per app di Gmail) e un mittente.
- **Dashboard:** inserire tutto nella pagina del plugin e premere "Test".

## 14. Rischi e punti da verificare

- **Firme di Jellyfin 10.11.9.** `IUserManager.ChangePassword(Guid, string)` e `ISessionManager.RevokeUserTokens(Guid, string)` sono verificate sul ramo `release-10.11.z`, non sui riferimenti 10.11.9 con cui si compila il plugin. Come `UserListing`, se la firma cambia fra le 10.11.x serve la riflessione. Da controllare con refprobe prima di scrivere `JellyfinPasswordReset`, insieme al fatto che `RevokeUserTokens(id, string.Empty)` chiuda davvero tutte le sessioni (confronta il token di ogni dispositivo con quello passato).
- **Ricerca dei membri su Discord.** Da confermare che `members/search` funzioni con l'intent attivo e che basti un bot senza permessi; in alternativa `GET /guilds/{id}/members` con paginazione.
- **`System.Net.Mail` nel processo di Jellyfin** su Linux (Ultra.cc): STARTTLS e autenticazione da provare col provider scelto.
- **Rotta anonima.** Da confermare che `[AllowAnonymous]` su un controller del plugin funzioni con lo schema di autenticazione di Jellyfin (nessuna rotta anonima finora nel plugin, a parte il webhook di Seerr, che usa un segreto).
- **Recupero bloccato da terzi.** Chi conosce un nome utente può esaurire i tentativi e bloccarne il recupero per un'ora; l'admin resta la via d'uscita.

## 15. Piani e release

- **Piano 18a — plugin.** Modulo `Account/`, adattatori, endpoint, configurazione e pagina della Dashboard, promemoria, `Info`. Prova del plugin sul server con un pacchetto di prova (come per il 17c), poi plugin **1.6.0** nel catalogo.
- **Piano 18b — app, lato utente.** `AccountApi`, `changePassword`, Impostazioni → Account, `/login/recover`, voce della cassetta, testi.
- **Piano 18c — app, lato admin.** Scheda Utenti, scheda "Recupero password", testi; release dell'app **0.12.0** con le note in italiano.
- A lavoro finito l'idea 5 esce da `docs/IDEE.md` e va fra le fatte: "Spec L — recupero e cambio della password (plugin 1.6.0, app 0.12.0)".
