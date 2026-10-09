# WonderFlix — Spec L: recupero e cambio della password

- **Data:** 2026-10-09
- **Stato:** approvato; piani 18a, 18b e 18c realizzati (`docs/superpowers/plans/2026-10-09-wonderflix-18a-recupero-plugin.md`, `docs/superpowers/plans/2026-10-09-wonderflix-18b-recupero-app-utente.md`, `docs/superpowers/plans/2026-10-09-wonderflix-18c-recupero-app-admin.md`); release da fare
- **Sul server:** dal 2026-10-09 c'è la build di prova del plugin 1.6.0.0 (dll md5 `bc707ef63f1df9dddbc70ce6539ed537`), provata con Discord ed email (§14), con i promemoria spenti (`ContactReminderDays` = 0). Il plugin 1.6.0 esce nel Catalogo con l'app 0.12.0, alla fine del 18c (§15).
- **Ambito:** Spec L. Realizza l'idea 5 di `docs/IDEE.md` ("Recupero e cambio della password") al livello più ampio: cambio della propria password nell'app, reset da parte dell'admin nell'app e **recupero in autonomia** con un codice mandato su **Discord o per email**. Solo nell'app WonderFlix: il "Password dimenticata" di jellyfin-web resta com'è.

## 1. Obiettivo

- **Cambio password.** Ogni utente cambia la sua password da Impostazioni → Account, con la password attuale.
- **Contatti per il recupero.** Ogni utente collega e verifica il suo account Discord, la sua email o tutti e due. Per collegare, cambiare o scollegare un contatto serve la password attuale (§8).
- **Recupero in autonomia.** Al login, "Password dimenticata?" manda un codice ai contatti verificati; con il codice l'utente sceglie una nuova password ed entra.
- **Admin.** In Amministrazione una scheda Utenti: impostare una password, mandare un codice di recupero, scollegare i contatti. Nella scheda WonderFlix lo stato dei canali e una prova d'invio.
- **Adozione.** Chi non ha contatti verificati riceve ogni N giorni un promemoria nella cassetta.

Non è il classico "password dimenticata" dei siti con il link per email: il codice arriva su Discord o per email, ma si scrive nell'app, e la nuova password si sceglie nell'app. Il contatto va collegato e verificato prima, da loggati: senza un contatto verificato il recupero non parte e resta l'admin.

## 2. Situazione di partenza

App 0.11.0, plugin 1.5.0, Jellyfin 10.11.9 su Ultra.cc dietro il proxy.

### 2.1 App

- **Login.** `PasswordLoginForm` (`lib/features/auth/password_login_form.dart`) mostra "Password dimenticata?" (`loginForgotPassword`) solo se c'è `supportUrl` (invito Discord in `config/wonderflix.json`) e apre quel link. `AuthApi` (`lib/core/jellyfin/auth_api.dart`) ha solo `authenticateByName`.
- **Impostazioni.** `SettingsScreen` ha le sezioni Lingua (la lingua dell'app), Aspetto, Player, Lingue di riproduzione, Discord, Account e Supporto, in quest'ordine. Account ha l'avatar, "Accesso come …", "Cambia immagine", "Cambia profilo" ed "Esci", senza cambio password.
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

Verificato sul ramo `release-10.11.z`, sul sorgente `v10.11.9` e, per le firme, sui pacchetti NuGet 10.11.0 (contro cui si compila il plugin) e 10.11.9 (quella del server), per riflessione. La prova sul server è in §14.

- **`POST /Users/Password`** (e il vecchio `POST /Users/{userId}/Password`), corpo `{CurrentPw, NewPw, ResetPassword}`:
  - la password attuale serve se chi chiama non è admin **o** cambia la propria;
  - un admin che cambia quella di un altro non la deve conoscere;
  - dopo `ChangePassword` chiama `RevokeUserTokens(user.Id, tokenAttuale)`: chiude le sessioni dell'utente tranne quella che ha fatto la richiesta;
  - `ResetPassword: true` lascia la password **vuota** e non chiude nessuna sessione: l'app non lo usa.
- **`IUserManager`**:
  - **`ChangePassword` cambia firma fra le due versioni:** `ChangePassword(User, string)` nella 10.11.0, `ChangePassword(Guid, string)` nella 10.11.9. Il plugin compilato contro la 10.11.0 andrebbe in `MissingMethodException` sul server: come per `UserListing`, il metodo si cerca a runtime (`Server/PasswordChanging.cs`, con `BindingFlags.DoNotWrapExceptions` perché l'errore di Jellyfin esca com'è);
  - uguali nelle due versioni: `GetUserById(Guid)`, `GetUserByName(string)` e `AuthenticateUser(nome, password, indirizzo, isUserSession)`, che serve a controllare la password attuale (§8);
  - gli utenti: proprietà `Users` nella 10.11.0, `GetUsers()` nella 10.11.9 (`UserListing`).
- **`ISessionManager`**: `Task RevokeUserTokens(Guid userId, string currentAccessToken)`, uguale nelle due versioni. **Con `string.Empty` chiude tutte le sessioni dell'utente:** verificato nel sorgente `v10.11.9` (`SessionManager` confronta il token di ogni dispositivo con quello passato e chiude quelli diversi).
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
| Limiti | Per nome utente scritto e globali, al minuto, all'ora e al giorno; non per IP | Dietro il proxy tutte le richieste hanno lo stesso IP. |
| Contatti | Collegare, cambiare e scollegare un contatto chiede la password attuale | Senza, chi ha in mano una sessione altrui (per esempio un profilo salvato su un PC condiviso, Spec K) potrebbe collegare la sua email, togliere i contatti del proprietario e cambiare la password con il recupero. Oggi una sessione da sola non basta nemmeno a cambiare la password: Jellyfin chiede quella attuale. Scelto dall'utente. |
| Adozione | Promemoria nella cassetta ogni N giorni (14) finché non c'è un contatto verificato | Scelto dall'utente. |
| Segreti | Nella pagina del plugin della Dashboard, come Seerr | Il file lo leggono solo gli admin; non passano mai dall'app. |

## 5. Perimetro

### Incluso

- Plugin 1.6.0: modulo `Account/` (contatti, codici, invio Discord ed email, recupero, admin, promemoria), endpoint, configurazione nella Dashboard, funzione `account` in `Info`.
- App: Impostazioni → Account (cambio password, contatti), "Password dimenticata?" al login, voce `ContactReminder` nella cassetta, scheda Amministrazione → Utenti, card "Recupero password" nella scheda Amministrazione → WonderFlix.
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
App (AccountApi, PluginAdminApi)    Plugin 1.6.0
────────────────────────────────    ────────────
Impostazioni → Account   ─┐         Api/AccountController       (utente)  ──▶ ContactLinking
Login → recupero         ─┼──────▶  Api/RecoveryController      (anonimo) ──▶ PasswordRecovery
Amministrazione          ─┘         Api/AccountAdminController  (admin)   ──▶ AccountAdmin, PasswordRecovery

Sotto, secondo il compito (`Account/` non conosce Jellyfin; gli adattatori stanno in `Server/`):
  ContactRegistry     → ContactStore → contacts.json
  CodeBook            (memoria)
  RateLimiter         (Hub/)
  AccountSender       → IDiscordSender → Server/DiscordBotClient  → Discord REST
                      → IMailSender    → Server/SmtpMailSender    → SMTP
  IPasswordCheck      → Server/JellyfinPasswordCheck → IUserManager.AuthenticateUser
  IPasswordReset      → Server/JellyfinPasswordReset → IUserManager (PasswordChanging), ISessionManager
  IAccountSettings    → Server/PluginAccountSettings → configurazione del plugin
  IUserDirectory      (Hub/, con IsAdmin)

Cassetta  ◀── InboxService ◀── ContactReminders ◀── ContactReminderHostedService

App (AuthApi): cambio password, "Imposta password" ──▶ Jellyfin POST /Users/Password
```

Le classi di `Account/`, ognuna con un compito solo:

| Classe | Compito |
|---|---|
| `ContactRegistry` | I contatti verificati in memoria, sicuri tra thread, salvati a ogni cambio (§7.2). |
| `CodeBook` | I codici in memoria (§7.2). |
| `AccountSender` | Gli invii per canale e l'ultimo errore di ognuno (§7.3). |
| `ContactLinking` | Il collegamento dei contatti (§7.4). |
| `PasswordRecovery` | Il recupero e il codice mandato dall'admin (§7.4). |
| `AccountAdmin` | Elenco, scollegamento, stato e prova (§7.4). |
| `ContactReminders` | I promemoria (§7.7); li fa partire `ContactReminderHostedService`. |

- **Il cambio della propria password e "Imposta password" dell'admin** passano dall'API di Jellyfin, senza il plugin. Ma nell'app "Imposta password" sta nel menu delle righe della scheda Utenti (§9.5), che c'è solo con la funzione `account` del plugin: la chiamata è di Jellyfin, il posto dove sceglierla viene dal plugin 1.6.0. Senza la funzione l'admin imposta la password dalla Dashboard di Jellyfin.
- **Tutto il resto** (contatti, codici, recupero, invio di codici dall'admin, stato) passa dal plugin.
- **Nell'app** gli endpoint dell'utente e del recupero li chiama `AccountApi`, quelli dell'admin `PluginAdminApi` (§9.1).

## 7. Plugin 1.6.0

Nuova cartella `Account/` per la logica (non conosce Jellyfin), adattatori in `Server/`, controller in `Api/`.

### 7.1 Configurazione

Nuove proprietà di `PluginConfiguration`:

| Proprietà | Valore iniziale | Note |
|---|---|---|
| `DiscordBotToken` | vuoto | Token del bot. |
| `DiscordGuildId` | vuoto | ID del server Discord dove cercare i membri. |
| `SmtpHost` | vuoto | |
| `SmtpPort` | 587 | STARTTLS; la 465 (TLS implicito) non è supportata. |
| `SmtpUser`, `SmtpPassword` | vuoti | |
| `MailFrom` | vuoto | Indirizzo del mittente; nome visualizzato "WonderFlix". |
| `ContactReminderDays` | 14 | 0 spegne i promemoria; i valori fuori da 0–365 si portano nei limiti. |

- **Discord configurato:** un token fatto come un token di Discord (solo lettere, cifre, `.`, `_` e `-`: finisce in un'intestazione HTTP, con spazi o a capo non può esserci) e un ID del server di 17–20 cifre.
- **Email configurata:** host, utente, password e mittente non vuoti, e una porta fra 1 e 65535.
- `IAccountSettings` (adattatore `PluginAccountSettings`, come `PluginSeerrSettings`) legge la configurazione corrente a ogni uso: un cambio nella Dashboard vale subito. Toglie gli spazi ai lati dei valori, tranne che dalla password SMTP.
- **`configPage.html`**: nuova parte "Password recovery" e, a parte, "Password recovery test".
  - **"Password recovery"** (un form con il suo "Save"):
    - in alto lo stato di `GET Account/Admin/Status`: i due canali configurati o no, con l'ultimo errore d'invio e l'ora, e quanti utenti hanno un contatto;
    - i campi qui sopra (token e password SMTP come campi password), con le istruzioni per Discord e per la porta;
    - il salvataggio è rifiutato finché la configurazione non è stata letta ("Settings not loaded: reload the page"): con i campi ancora vuoti cancellerebbe tutto;
    - porta e giorni sono campi numerici obbligatori; uno vuoto o illeggibile lascia il valore di adesso, e i giorni non scendono sotto 0.
  - **"Password recovery test"** (fuori dal form, perché Invio in questi campi non deve salvare):
    - due campi facoltativi, il nome utente Discord e l'email a cui mandare la prova; vuoti, la prova va ai contatti verificati dell'admin (`POST Account/Admin/Test`, §7.4). Così la prova funziona anche prima che l'admin abbia collegato i suoi contatti;
    - il pulsante "Send a test" usa le impostazioni salvate, quindi si salva prima; non parte due volte insieme (può durare fino a 24 s);
    - l'esito per canale: per esempio "Discord: sent. E-mail: sent."

### 7.2 Dati

**`ContactStore`** — file `contacts.json` accanto a `inbox.json`, stesse regole (scrittura atomica con sincronizzazione su disco, `.bad` se illeggibile; se il file non si riesce a spostare si riparte vuoti e il prossimo salvataggio lo sovrascrive):

```json
{
  "Version": 1,
  "Users": {
    "<userId>": {
      "Discord": { "Id": "123456789012345678", "Name": "garg", "VerifiedAt": "2026-10-09T10:00:00Z" },
      "Email": { "Address": "a@example.com", "VerifiedAt": "2026-10-09T10:05:00Z" },
      "LastReminderAt": "2026-10-01T09:00:00Z"
    }
  }
}
```

- `<userId>` è l'ID in formato `N`. Nel file entrano solo contatti **verificati**; un contatto in attesa vive nel `CodeBook`.
- Il file si rifiuta **tutto intero** (e va in `.bad`) se una voce non è valida: ID utente illeggibile, Discord senza ID di 17–20 cifre o senza nome, email vuota.
- **`ContactRegistry`** tiene i contatti in memoria, sotto lock, e li salva a ogni cambio; fuori dal registro girano solo copie. Per lo stesso motivo di sopra rifiuta un contatto non valido (`ArgumentException`): una voce sbagliata non deve mai arrivare nel file. Un utente senza contatti e senza `LastReminderAt` esce dal file. Un errore di disco va nel log e non annulla il cambio in memoria: si riprova al salvataggio dopo.
- Un utente cancellato da Jellyfin viene tolto al primo giro dei promemoria (§7.7).

**`CodeBook`** — solo in memoria, thread-safe, con `TimeProvider`:

- voce per `(userId, scopo)`, dove lo scopo è `VerifyDiscord`, `VerifyEmail` o `Recovery`;
- contiene: hash `SHA-256(sale + codice)`, sale casuale di 16 byte, scadenza (10 minuti), tentativi rimasti (5), e per le verifiche il contatto in attesa (ID e nome Discord, oppure indirizzo);
- un nuovo codice per lo stesso `(userId, scopo)` sostituisce il precedente;
- confronto con `CryptographicOperations.FixedTimeEquals`; al quinto errore la voce sparisce; scaduta = assente;
- codice: 6 cifre da `RandomNumberGenerator.GetInt32(0, 1_000_000)`, con gli zeri iniziali;
- il codice scritto può avere spazi e trattini ("123 456", "123-456"): si tolgono prima del confronto, e devono restare 6 cifre;
- dopo l'uso la voce sparisce; quando se ne emette una nuova vanno via anche quelle scadute;
- `Discard` toglie una voce: serve se l'invio non riesce e quando si scollega un contatto (§7.4).

### 7.3 Invio

Le interfacce non lanciano: gli errori sono esiti (`Sent`, `DmClosed`, `Failed`). Esce solo l'annullamento di chi chiama.

**`IDiscordSender`** (`Server/DiscordBotClient`, `HttpClient` su `https://discord.com/api/v10`, nessun redirect seguito):

- Intestazioni: `Authorization: Bot <token>` (con `AuthenticationHeaderValue`, che la valida) e `User-Agent: DiscordBot (https://github.com/davidesidoti/wonderflix, <versione>)`: senza un User-Agent valido Discord può bloccare la richiesta.
- `FindMemberAsync(name)`: `GET /guilds/{guildId}/members/search?query=<name>&limit=100`. La ricerca di Discord va per prefisso e non dice in che ordine dà i risultati, quindi si leggono 100 risultati. Tiene solo il membro il cui `user.username` coincide **esattamente** con il nome scritto (maiuscole e minuscole indifferenti) e che **non è un bot** (un bot con lo stesso nome non deve nascondere la persona). Restituisce ID e nome utente, "non trovato" oppure "errore di Discord". Spazi e `@` iniziale li toglie prima `ContactLinking` (§7.4).
- `SendDmAsync(userId, text)`: `POST /users/@me/channels {recipient_id}`, poi `POST /channels/{id}/messages {content}`. Una risposta 403 con codice 50007 ("Cannot send messages to this user") diventa `DmClosed`; ogni altro errore, un 429 compreso (non si ritenta), diventa `Failed`.
- `CheckAsync()`: `GET /users/@me` (401 o 403: `Invalid`), `GET /guilds/{guildId}` (401, 403 o 404: `Invalid`: token o server sbagliati) e `GET /guilds/{guildId}/members/search?query=a&limit=1`. Il terzo prova la ricerca dei membri: senza l'intent "Server Members" o senza accesso risponde 401/403 e dà `Invalid`, e il collegamento fallirebbe per tutti. Nessuna risposta o un altro errore: `Failed`.
- **Tempo:** un solo limite di 8 s per ogni operazione intera (la ricerca, il messaggio diretto con i suoi due passi, il controllo con i suoi tre), non per ogni richiesta. Il motivo: l'app aspetta al massimo 30 s una risposta del server.
- **Log:** metodo, percorso senza query, stato e, se c'è, il codice d'errore numerico di Discord. Mai il token, mai il testo del messaggio, mai il nome cercato.

**`IMailSender`** (`Server/SmtpMailSender`, `System.Net.Mail.SmtpClient`, `EnableSsl = true` cioè STARTTLS, credenziali di rete):

- `SendAsync(to, message)`: messaggio di solo testo in UTF-8, mittente `WonderFlix <MailFrom>`. Ogni errore (tranne l'annullamento di chi chiama) diventa `Failed`; attesa massima di 15 s, fatta con un `CancellationTokenSource` perché `SmtpClient.Timeout` vale solo per l'invio sincrono.
- **Log:** server e porta, tipo e messaggio dell'errore e la causa originale (`GetBaseException`, di solito la rete). Mai la password (il server SMTP letto dalla configurazione non la stampa) e **mai un indirizzo**: anche nei messaggi del server SMTP ("<mario@example.com> unknown") gli indirizzi diventano `[email]`. Con la porta 465 il log aggiunge che serve la 587 con STARTTLS.

**`AccountSender`** manda un messaggio a un contatto o a tutti i contatti di un utente:

- solo sui canali configurati: un canale spento non manda niente e non conta come errore;
- `SendToAllAsync` fa partire i canali **in parallelo**: l'attesa è quella del canale più lento, non la somma. Così, con il limite dell'app di 30 s, i casi peggiori sono circa 16 s per collegare Discord (ricerca e messaggio, 8 + 8), 15 s per il codice mandato dall'admin e 24 s per la prova (§7.4).

**Messaggi** (`Account/AccountMessages`, italiano e inglese; la lingua arriva dalla richiesta, `it` se manca o è sconosciuta). Esempi in italiano:

- Verifica: *"Il tuo codice WonderFlix per collegare questo account è 123456. Scade tra 10 minuti. Se non l'hai chiesto tu, ignora questo messaggio."*
- Recupero: *"Il tuo codice WonderFlix per cambiare la password di «garg» è 123456. Scade tra 10 minuti. Se non l'hai chiesto tu, ignora questo messaggio: la password non cambia finché il codice non viene usato."*
- Password cambiata: *"La password WonderFlix di «garg» è stata cambiata. Se non sei stato tu, scrivi all'amministratore."*
- Prova: *"Messaggio di prova di WonderFlix: il canale funziona."*

L'oggetto delle email è "WonderFlix — codice" oppure "WonderFlix — password cambiata", e "WonderFlix — prova" per la prova (in inglese "code", "password changed", "test").

**Ultimo errore.** `AccountSender` ricorda l'ultimo errore d'invio per canale (ora e codice, senza il destinatario), mostrato nello stato dell'admin.

- I codici sono `DmClosed`, `SendFailed` e `Invalid` (Discord ha rifiutato token o server, dal controllo della prova).
- **Sparisce con il primo invio riuscito sul canale:** descrive com'è il canale adesso, non com'è stato una volta.
- Una ricerca dei membri che fallisce conta come un errore d'invio del canale. Di un canale spento lo stato non mostra il vecchio errore.

### 7.4 Collegamento, recupero e funzioni dell'admin

Un solo `AccountService` sarebbe stato troppo grosso: la logica sta in classi piccole (§6), ognuna con le sue dipendenze.

- `ContactLinking`: `ContactRegistry`, `CodeBook`, `RateLimiter`, `IDiscordSender`, `IPasswordCheck`, `AccountSender`, `IAccountSettings`, `InboxService`, `TimeProvider`.
- `PasswordRecovery`: `IUserDirectory` (esteso con `UserRef.IsAdmin`), `ContactRegistry`, `CodeBook`, `RateLimiter`, `AccountSender`, `IPasswordReset`.
- `AccountAdmin`: `IUserDirectory`, `ContactRegistry`, `CodeBook`, `AccountSender`, `IDiscordSender`, `IAccountSettings`.

**"Ha un contatto" vuol dire un contatto raggiungibile** (`HasReachableContact`): su un canale oggi configurato. Un contatto su un canale spento non serve al recupero, quindi è come non averlo: nel recupero, nel codice dell'admin, nello stato dell'admin e nei promemoria.

**Collegamento (utente autenticato)** — `ContactLinking`

1. `StartAsync(userId, channel, target, password, language)`. L'ordine dei controlli conta:
   1. nessun utente (chiamata con una chiave API) → `Invalid`;
   2. canale non configurato → `ChannelOff`;
   3. `target` non valido → `InvalidTarget`:
      - Discord: ripulito (spazi e `@` iniziale), poi 2–32 caratteri fra lettere, cifre, `_` e `.`;
      - email: al massimo 254 caratteri, solo ASCII, senza parentesi quadre (niente indirizzi IP), un `MailAddress` senza nome visualizzato che coincide con quanto scritto, e un dominio con almeno due etichette non vuote che non iniziano né finiscono con `-`;
   4. limiti guardati, senza contarli: `LinkStartMinute` (per utente e canale) e `LinkStartHour` (per utente) → `RateLimited`;
   5. **password attuale** (§8): `PasswordChecks` finito → `RateLimited`; password sbagliata → `WrongPassword`;
   6. si conta `LinkStartHour`, con la password giusta e prima della ricerca;
   7. Discord, `FindMemberAsync`: errore di Discord → `SendFailed`; nessun membro → `MemberNotFound`; un membro senza ID valido o senza nome (risposta strana di Discord) → `SendFailed`;
   8. si conta `LinkStartMinute`; nuovo codice `Verify<canale>` con il contatto in attesa, poi invio **in attesa della risposta**: `DmClosed` o `SendFailed` tolgono il codice e tornano all'app. Così l'utente sa subito se il canale funziona.

   I due limiti hanno scopi diversi:
   - **un codice al minuto per utente e canale:** si conta solo quando il codice sta per partire. Un nome Discord scritto male si riscrive subito, e Discord ed email si collegano uno dopo l'altro;
   - **cinque all'ora per utente:** conta ogni ricerca, e frena chi prova nomi per scoprire i membri del server. Si guarda prima della password e si conta dopo, così una password sbagliata non lo consuma (le password a caso le ferma `PasswordChecks`).
2. `ConfirmAsync(userId, channel, code)`: codice giusto → il contatto entra in `ContactRegistry` con `VerifiedAt`, e i promemoria dell'utente spariscono dalla cassetta. Codice sbagliato → `InvalidCode` (lo stesso per sbagliato, scaduto o assente). **Non chiede la password:** il codice prova che l'avvio era autorizzato.
3. `UnlinkAsync(userId, channel, password)`: nessun utente → `Invalid`; password attuale come sopra (`RateLimited`, `WrongPassword`). Poi toglie il contatto, e nessun errore se non c'era. **Annulla anche il codice di recupero in sospeso**, anche se il contatto non c'era: scollegare è lo strumento per "questo contatto è compromesso", e un codice già partito lì non deve restare buono.

**Recupero (anonimo)** — `PasswordRecovery`

1. `Start(username, language)`:
   - nome vuoto o più lungo di 256 caratteri → `Invalid`;
   - limiti per nome scritto e globali (§7.5); superati → `RateLimited`, indipendentemente dall'esistenza dell'utente. **La chiave è il nome senza spazi ai lati e in maiuscolo** (`ToUpperInvariant`), come il confronto senza maiuscole di Jellyfin (`OrdinalIgnoreCase`): in minuscolo restano diverse lettere che per quel confronto sono uguali (il sigma finale e quello normale), e con due chiavi per lo stesso utente il limite si aggirerebbe scrivendolo in un altro modo;
   - altrimenti risponde subito e manda in background (`Task.Run`, eccezioni nel log): utente esistente, attivo, non admin, con almeno un contatto raggiungibile → nuovo codice `Recovery` mandato a tutti quei contatti, in parallelo; negli altri casi non succede niente. Se nessun canale ha funzionato il codice si toglie e il log lo dice (un avviso).
2. `CompleteAsync(username, code, newPassword, language)`:
   - nome vuoto o più lungo di 256 caratteri → `Invalid`;
   - limiti degli errori (per nome all'ora e al giorno, globale al giorno) → `RateLimited`;
   - `newPassword` da 6 a 1024 caratteri, altrimenti `WeakPassword`. Il controllo viene prima del codice, così non consuma tentativi;
   - utente inesistente, disattivato, admin, codice assente o sbagliato → `InvalidCode`, e l'errore conta per i limiti;
   - controllo dei limiti, verifica del codice e conteggio degli errori stanno **sotto un solo lock**: richieste insieme non superano i limiti;
   - quando un nome viene fermato dai limiti, nel log (un avviso, una volta sola) c'è l'ID dell'utente, anche se è un admin o un disattivato: il log è solo sul server. Mai il testo scritto, che potrebbe essere un'email o contenere a capo;
   - codice giusto → `IPasswordReset.ResetAsync(userId, newPassword)` (`ChangePassword` via `PasswordChanging`, poi `RevokeUserTokens(userId, string.Empty)`). Se Jellyfin non cambia la password l'errore esce (500) e il codice è già usato (§11). Se invece solo la chiusura delle sessioni fallisce, il recupero riesce lo stesso e l'errore va nel log: la password è già cambiata;
   - poi, in background e senza trattenere la risposta, l'avviso "password cambiata" a tutti i contatti raggiungibili.

**Admin** — `AccountAdmin` e `PasswordRecovery`

- `AccountAdmin.Users()`: per ogni utente, in ordine di nome, ID (formato `N`), nome, admin, attivo, Discord (nome) ed email **mascherata** (`a•••@gmail.com`: prima lettera, `•••`, dominio intero), `LastReminderAt`.
- `PasswordRecovery.SendForAdminAsync(userId, adminId, language)`: come il recupero ma con la risposta vera:
  - utente sconosciuto → `UnknownUser`;
  - utente admin **o disattivato** → `NotAllowed`;
  - nessun contatto raggiungibile → `NoContacts`;
  - nessun invio riuscito → `SendFailed` (e il codice si toglie);
  - altrimenti ok, con i canali usati. Non passa dai limiti del recupero. Nel log finisce l'admin che l'ha chiesto (il suo ID, oppure "chiave API").
- `AccountAdmin.Unlink(userId, adminId)`: utente sconosciuto → `UnknownUser`; altrimenti toglie tutti i contatti **e annulla i codici già mandati**, di recupero e di collegamento (un contatto compromesso non si ricollega con un codice già partito). Nel log finisce l'admin.
- `AccountAdmin.Status()`: per canale configurato sì/no e ultimo errore (nascosto se il canale è spento); quanti utenti attivi non admin hanno almeno un contatto raggiungibile, su quanti; i giorni dei promemoria.
- `AccountAdmin.TestAsync(adminId, language, discordName, email)`: i due canali partono in parallelo (l'app aspetta al massimo 30 s, la prova al peggio ne dura 24).
  - **Discord:** non configurato → `NotConfigured`; `CheckAsync` → `Invalid` (e si ricorda come errore del canale) oppure `SendFailed`; poi il destinatario:
    - se c'è un nome scritto: non valido come nome Discord → `InvalidTarget`; ricerca fallita → `SendFailed` (conta come errore del canale, come al collegamento); nessun membro → `MemberNotFound`; altrimenti il membro trovato;
    - senza nome scritto, il Discord verificato dell'admin; se non c'è → `NoContact`;
    - il DM di prova dà `Ok`, `DmClosed` o `SendFailed`.
  - **Email:** non configurata → `NotConfigured`; un indirizzo scritto non valido → `InvalidTarget`; senza indirizzo scritto, l'email verificata dell'admin, o `NoContact`; la mail di prova dà `Ok` o `SendFailed`.
  - Gli esiti per canale sono quelli di `AccountTestCodes`: `Ok`, `NotConfigured`, `NoContact`, `Invalid` (token o server sbagliati, o intent mancante), `MemberNotFound`, `InvalidTarget`, `DmClosed`, `SendFailed`.

### 7.5 Limiti

Nuovi tipi nel `RateLimiter`:

| Tipo | Chiave | Limite |
|---|---|---|
| `RecoveryStartMinute` | nome scritto (in maiuscolo) | 1 al minuto |
| `RecoveryStartHour` | nome scritto | 5 all'ora |
| `RecoveryStartDay` | nome scritto | 10 al giorno |
| `RecoveryStartGlobal` | `*` | 30 all'ora |
| `RecoveryFail` | nome scritto | 10 errori all'ora; superati, il recupero di quel nome si ferma finché la finestra non si libera |
| `RecoveryFailDay` | nome scritto | 20 errori al giorno |
| `RecoveryFailGlobal` | `*` | 100 errori al giorno |
| `LinkStartMinute` | userId e canale (`<userId>:Discord`) | 1 al minuto |
| `LinkStartHour` | userId | 5 all'ora |
| `PasswordChecks` | userId | 10 controlli della password attuale all'ora |

- Il `RateLimiter` ha un solo limite per tipo: le coppie "al minuto e all'ora" sono tipi diversi.
- **`IsLimited(chiave, tipo)`** controlla senza contare, accanto a `TryAcquire`. Serve per gli errori, che si contano solo quando sbagliano, e per guardare tutti i limiti di una richiesta prima di spenderne uno: una richiesta rifiutata non ne consuma nessuno (altrimenti chi insiste su un nome già fermato svuoterebbe il limite di tutti).
- **Pulizia:** con 1024 chiavi in memoria, prima di crearne una nuova si tolgono quelle senza invii nella finestra del loro tipo. I nomi scritti nel recupero sono anonimi e non passano mai da `Forget`: senza, resterebbero per sempre.
- **Limiti giornalieri sugli errori.** Con i soli limiti orari un tentativo lento e continuo resterebbe possibile: 10 tentativi all'ora per nome sono 240 al giorno, fino a circa lo 0,7% al mese di indovinare il codice di un account (uno su 1 000 000, se ce n'è sempre uno valido). Con `RecoveryFailDay` (20 al giorno) scende a circa lo 0,06%, per ogni account. `RecoveryFailGlobal` serve anche a non far crescere la memoria dei limiti con nomi inventati e a non lasciare tentare per sempre chi li inventa a raffica.
- **`RecoveryStartDay`** frena i codici a raffica a una persona e il consumo della quota del servizio email (§13).
- **Compromessi accettati.** Chi esaurisce un limite globale tiene chiuso il recupero di tutti:
  - bastano circa 100 richieste sbagliate al giorno per `RecoveryFailGlobal`; blocca anche il completamento dei codici mandati dall'admin;
  - bastano 30 richieste all'ora per `RecoveryStartGlobal`, ancora meno care.

  La via d'uscita è "Imposta password" dell'admin, che passa da Jellyfin e non dal plugin.

### 7.6 Endpoint

Base `WonderFlixWatchParty/Account`. JSON in PascalCase come il resto del plugin. Errori come `{Code}` con lo stato indicato.

**Mai un 404 dal plugin.** Per l'app un 404 vuol dire "plugin senza la funzione" (§9.1). Quindi: `MemberNotFound` è un 400, un utente sconosciuto nelle rotte dell'admin è un 400 `UnknownUser`, e canali e ID nelle rotte sono stringhe senza vincoli di rotta (un vincolo risponderebbe 404).

**Utente** (`[Authorize]`, `AccountController`)

| Metodo e percorso | Corpo | Esito |
|---|---|---|
| `GET Contacts` | — | 200 `{Channels: {Discord, Email}, Discord: {Name, VerifiedAt}?, Email: {Address, VerifiedAt}?}` (l'email dell'utente stesso, intera) |
| `POST Contacts/{Discord\|Email}/Start` | `{Target, Password, Language}` | 202 `{ExpiresAt}` · 400 `InvalidTarget` · 400 `MemberNotFound` · 400 `Invalid` · 403 `WrongPassword` · 409 `DmClosed` · 502 `SendFailed` · 503 `ChannelOff` · 429 `RateLimited` |
| `POST Contacts/{canale}/Confirm` | `{Code}` | 200 come `GET Contacts` · 400 `InvalidCode` |
| `POST Contacts/{canale}/Unlink` | `{Password}` | 204 (anche se il contatto non c'era) · 400 `Invalid` · 403 `WrongPassword` · 429 `RateLimited` |

- `Password` è la password attuale dell'account, vuota (o assente) per un account senza password.
- Lo scollegamento è un `POST` e non un `DELETE`: un corpo in una DELETE non è affidabile, e la password non deve stare nell'indirizzo.

**Recupero** (`[AllowAnonymous]`, `RecoveryController`, controller a parte perché un `[Authorize]` sulla classe non si allarga)

| Metodo e percorso | Corpo | Esito |
|---|---|---|
| `POST Recovery/Start` | `{Username, Language}` | 202 sempre · 429 `RateLimited` · 400 `Invalid` se `Username` è vuoto o più lungo di 256 |
| `POST Recovery/Complete` | `{Username, Code, NewPassword, Language}` | 204 · 400 `InvalidCode` · 400 `WeakPassword` · 400 `Invalid` (nome vuoto o più lungo di 256) · 429 `RateLimited` |

`Language` di `Complete` è la lingua dell'avviso "password cambiata". Un errore di Jellyfin nel cambio è un 500 (§11).

**Admin** (`[Authorize(Policy = Policies.RequiresElevation)]`, `AccountAdminController`)

| Metodo e percorso | Corpo | Esito |
|---|---|---|
| `GET Admin/Users` | — | 200 `[{Id, Name, IsAdmin, Enabled, Discord: {Name}?, Email: {Masked}?, LastReminderAt?}]` |
| `POST Admin/Users/{id}/Recovery` | `{Language}` | 200 `{Channels: [...]}` · 403 `NotAllowed` · 400 `UnknownUser` · 409 `NoContacts` · 502 `SendFailed` |
| `DELETE Admin/Users/{id}/Contacts` | — | 204 · 400 `UnknownUser` |
| `GET Admin/Status` | — | 200 `{Discord: {Configured, LastError?}, Email: {Configured, LastError?}, WithContacts, Users, ReminderDays}` |
| `POST Admin/Test` | `{Language, Discord?, Email?}` | 200 `{Discord, Email}` con gli esiti di `AccountTestCodes` (§7.4) |

- `LastError` = `{At, Code}` con `Code` fra `DmClosed`, `SendFailed`, `Invalid`.
- `Discord` ed `Email` di `Admin/Test` sono facoltativi: un nome utente Discord e un indirizzo a cui mandare la prova, al posto dei contatti dell'admin. La Dashboard li usa; l'app (18c) non li manda.

**Stati HTTP degli errori.** `ChannelOff` 503 · `RateLimited` 429 · `DmClosed` e `NoContacts` 409 · `SendFailed` 502 · `NotAllowed` e `WrongPassword` 403 · tutti gli altri 400 (`InvalidTarget`, `MemberNotFound`, `InvalidCode`, `WeakPassword`, `UnknownUser`, `Invalid`).

**400 `Invalid`:** un canale che non è `Discord` o `Email`, il corpo mancante, una chiamata senza utente (con una chiave API) su `Start` e `Unlink` (non collega contatti), un nome vuoto o più lungo di 256 caratteri nel recupero.

**Corpo malformato.** Un JSON rotto o un `Code` numerico al posto di una stringa danno il 400 automatico di ASP.NET, senza `{Code}`: l'app lo tratta come un errore generico.

`Language` è `it` o `en`; se manca o è sconosciuta vale `it`.

### 7.7 Promemoria

`ContactReminderHostedService` (come `NewTitlesHostedService`): all'avvio legge `contacts.json` (un problema va nel log); primo giro 5 minuti dopo l'avvio, poi ogni 24 ore. Un errore di un giro va nel log e si riprova al giro dopo. Il giro è `ContactReminders.RunAsync`.

- **Pulizia degli utenti cancellati, prima di tutto:** toglie i contatti degli utenti che Jellyfin non ha più, **anche con i promemoria spenti o senza canali** (le email degli utenti cancellati non devono restare nel file). Con un elenco utenti vuoto (un errore momentaneo di Jellyfin) non toglie niente: toglierebbe i contatti di tutti.
- `ContactReminderDays` = 0, oppure nessun canale configurato → nessun promemoria.
- Per ogni utente attivo non admin **senza un contatto raggiungibile** (§7.4: un contatto su un canale spento è come non averlo), con `LastReminderAt` assente o più vecchio di N giorni:
  - sostituisce nella sua cassetta la voce `ContactReminder` precedente con una nuova (`{Type: "ContactReminder", Id, Seq, CreatedAt, Read: false, Channels: ["Discord", "Email"]}` con i canali configurati): ce n'è sempre una sola;
  - aggiorna `LastReminderAt`, ma solo se la voce è stata scritta; se no, al giro dopo si riprova;
  - se nel frattempo (a metà giro) è arrivato un collegamento, la sua conferma ha già tolto i promemoria prima che questo giro scrivesse il suo: con un contatto raggiungibile adesso, la voce appena scritta si toglie.
- **Un'ora di tolleranza:** gli N giorni si contano meno un'ora. Il giro è ogni 24 ore e qualche millisecondo di ritardo non deve spostare il promemoria di un giorno.
- `InboxService` riceve `AddContactReminderAsync(userId, channels)` e `RemoveContactRemindersAsync(userId)`; non lanciano, un errore va nel log.

### 7.8 `Info` e versione

- `WatchPartyProtocol.Features` riceve `account` (sempre presente nel plugin 1.6.0, anche con i canali spenti: il cambio di stato lo dice `Contacts.Channels`). Il protocollo resta 1.
- Plugin **1.6.0.0**:
  - la versione sta nel `.csproj` (`<Version>1.6.0</Version>`); `InfoController` la legge dall'assembly. In `meta.template.json` (che usa `pack.sh`) si aggiornano anche `description` e `overview`, e la descrizione in `Plugin.cs`; il readme del plugin;
  - il pacchetto lo fa `pack.sh` (`WonderFlix Watch Party_1.6.0.0/` con la dll e `meta.json`), lo zip lo fa il workflow `watch-party-plugin.yml` su un tag `watch-party-plugin-vX.Y.Z`;
  - il `manifest.json` del Catalogo si aggiorna al rilascio (§15), non prima.

## 8. Sicurezza

- **Account nascosti.** `Recovery/Start` risponde prima di inviare; `Recovery/Complete` dà lo stesso `InvalidCode` per ogni causa. I limiti del recupero valgono per il nome scritto, che esista o no.
- **Codici.** Vedi §7.2: casuali crittografici, salvati come hash, a tempo costante, 10 minuti, 5 tentativi, sostituiti da un nuovo invio, persi al riavvio. Scollegare un contatto annulla il codice di recupero in sospeso (§7.4).
- **Password attuale per i contatti.** Collegare, sostituire e scollegare un contatto chiedono la password attuale dell'account (vuota per gli account senza password); la conferma con il codice no. Il motivo è in §4: una sessione da sola non deve bastare a prendersi l'account.
  - La verifica passa da `IPasswordCheck` / `JellyfinPasswordCheck`, che usa `IUserManager.AuthenticateUser` (stessa firma in 10.11.0 e 10.11.9) con `isUserSession` falso: Jellyfin non tocca `LastLoginDate`.
  - Una password sbagliata conta come un accesso sbagliato di Jellyfin (`InvalidLoginAttemptCount`, come in jellyfin-web); vedi il blocco in §11.
  - Limite `PasswordChecks`: 10 controlli all'ora per utente, perché chi ha la sessione non provi password all'infinito. Errore `WrongPassword` (403).
  - Chi ha già dimenticato la password e non ha contatti passa dall'admin.
- **Sessioni.** Dopo un recupero tutte le sessioni dell'utente si chiudono; dopo un cambio dall'app o "Imposta password" ci pensa Jellyfin (§3).
- **Avvisi.** Dopo un recupero riuscito arriva "password cambiata" su tutti i contatti raggiungibili.
- **Admin.** Nessun recupero in autonomia, nessun promemoria; possono collegare i contatti per la prova. Un admin che perde la password rimedia via SSH o con un altro admin.
- **Utenti disattivati.** Nessun codice, nessun promemoria; l'admin che prova a mandarglielo ottiene `NotAllowed`.
- **Password nuove.** Da 6 a 1024 caratteri nel plugin (`Recovery/Complete`, altrimenti `WeakPassword`); nell'app almeno 6.
- **Contatti condivisi.** Lo stesso Discord o la stessa email possono stare su più account: collegarli richiede comunque il codice (e la password dell'account).
- **Segreti.** Token del bot e password SMTP solo nel file di configurazione del plugin (letto dagli admin); l'app vede solo `Configured`. Le credenziali SMTP che possono solo spedire, o di un account senza niente di prezioso, sono più sicure (§13). Il client HTTP di Discord non segue i redirect e non scrive l'intestazione `Authorization` nei suoi log.
- **Log.** Il plugin non scrive codici, password, token, indirizzi email né nomi utente Discord (§7.3). Scrive l'ID Jellyfin dell'utente (formato `N`), gli esiti e, per gli errori di Discord, metodo, percorso senza query e codice d'errore; per l'SMTP il server e la porta (mai l'utente, il mittente o la password). Nell'app `redact.dart` copre i nuovi corpi delle richieste: `Code`, `NewPassword`, `CurrentPw`, `NewPw` e `Target` entrano nella regola del JSON, dove c'era già `Password` (quello di `Start` e `Unlink`). Solo con un valore stringa: un `"Code"` numerico e la forma a mappa dei frame di Discord IPC (`{code: 4000}`) restano leggibili. `AccountException` nel log dice solo il tipo di errore.

## 9. App

### 9.1 Client e disponibilità

- **`AccountApi`** (`lib/core/social/account_api.dart`): i metodi degli endpoint dell'utente e del recupero di §7.6 (`contacts`, `startLink`, `confirmLink`, `unlink`, `startRecovery`, `completeRecovery`); quelli dell'admin stanno in `PluginAdminApi` (più sotto).
  - **Sul client principale** (`jellyfinHttpProvider`, tramite `accountApiProvider`), non su uno a parte: nell'accesso `LoginScreen` chiama `prepareLogin`, che toglie il token dal client, quindi le chiamate di `Recovery/*` partono senza. È il client senza sessione del login.
  - Il `Code` di `Confirm` e `Complete` va come stringa: lo zero iniziale conta.
  - `startLink` non legge `ExpiresAt` e `AccountContacts` non ha `VerifiedAt`: l'app non li mostra.
  - Gli esiti previsti (400, 403, 404, 409, 429, 502, 503) vanno nel log come info.
- **Errori:** `AccountApi` lancia solo `AccountException`, con un `AccountFailure`:

| Risposta | `AccountFailure` |
|---|---|
| 404 | `unavailable`: plugin assente o vecchio (il plugin non risponde mai 404) |
| 400 `InvalidTarget`, `MemberNotFound`, `InvalidCode`, `WeakPassword` | `invalidTarget`, `memberNotFound`, `invalidCode`, `weakPassword` |
| 403 `WrongPassword` | `wrongPassword` (la sessione resta aperta: la chiude solo un 401) |
| 409 `DmClosed` · 502 `SendFailed` · 503 `ChannelOff` | `dmClosed` · `sendFailed` · `channelOff` |
| 429 | `rateLimited` |
| ogni altro 400, 401, 403 e 409, anche senza `Code` (`Invalid`, `NotAllowed`, il 400 di ASP.NET per un JSON rotto) | `invalid` |
| 500 | `serverError`: in `Recovery/Complete` il codice è già usato (§11) |
| 502, 503 e 504 senza il loro `Code` (nginx durante un riavvio), rete, risposta di forma inattesa | `network` |

`AccountFailure` è solo del lato utente: niente valori per `NotAllowed`, `NoContacts` e `UnknownUser`, che arrivano solo alle rotte dell'admin.

- **Gli endpoint dell'admin** (`Admin/*` di §7.6) stanno in **`PluginAdminApi`** (`lib/core/social/plugin_admin_api.dart`), non in `AccountApi`: `accountUsers`, `sendRecoveryCode`, `unlinkContacts`, `accountStatus` e `testAccountChannels`.
  - Lanciano `ApiException` come il resto di `PluginAdminApi` e come Jellyfin: valgono le regole della pagina Amministrazione (`AdminTabController.act`, che a un 403 rilegge l'utente e porta via la pagina a chi non è più admin; `AdminActionButton`; `describeError`).
  - Il `{Code}` del plugin si legge con `pluginErrorCode(error)`, dal corpo di un 403 o di un altro errore del server; i testi sono in §9.5.
  - I modelli sono in `lib/core/social/plugin_admin_models.dart`: `AdminAccountUser`, `AccountAdminStatus` (con `AccountChannelStatus` e `AccountSendError`) e `AccountTestResult`. Una risposta senza un campo obbligatorio non vale (`ServerErrorException`), e nemmeno un 200 di `sendRecoveryCode` senza un canale che l'app conosce.
  - Nel log come info: per il codice e lo scollegamento 400, 403, 404, 409, 502, 503 e 504; per le letture e la prova 400, 404, 502, 503 e 504, come le altre rotte del plugin.
- **`AuthApi.changePassword(userId, {currentPassword, newPassword})`** → `POST /Users/Password?userId=` con `{CurrentPw, NewPw}`. Senza `currentPassword` il corpo non ha `CurrentPw`: è "Imposta password" dell'admin (§9.5). Il 403 della password sbagliata va nel log come info.
- **`SocialFeatures.account`**: dalla funzione `account` di `Info` (`PluginFeatures.account`), che si chiede anche senza accesso ai watch party. La legge `accountAvailableProvider`: senza, Impostazioni → Account ha solo il cambio della password.
- **I contatti** (`AccountContactsController`, `accountContactsProvider`, `autoDispose`) si leggono solo con un utente aperto e la funzione `account`: ogni volta che la sezione torna a vedersi e a ogni cambio di profilo.
  - dopo `Confirm` valgono quelli della risposta (`replace`), senza rileggerli;
  - dopo uno scollegamento si rileggono (`reload`): intanto restano quelli di prima, senza spinner, e se a metà rilettura cambia l'utente la risposta vecchia si scarta.
- **Prima del login** non c'è `Info` (serve un token): l'app prova `POST Recovery/Start` e, con un 404 (plugin vecchio, rotta assente), dice che il recupero non è disponibile (§9.3) invece della risposta neutra. Con "Ho già un codice" (§9.3) `Start` non si chiama: il 404 arriva a `Recovery/Complete`, e dice lo stesso.

### 9.2 Impostazioni → Account

La sezione Account è la prima di Impostazioni (prima era in fondo, sopra Supporto): `AccountSettingsSection` (`lib/features/settings/account_settings_section.dart`). Tiene quello che c'era (avatar, "Accesso come …", "Cambia immagine", "Cambia profilo", "Esci") e aggiunge "Cambia password" e, con la funzione `account` (§9.1), i contatti per il recupero (`AccountContactsBlock`, `lib/features/account/account_contacts_block.dart`).

**Cambia password** (`ChangePasswordDialog`) → finestra con password attuale, nuova, conferma:

- sotto la password attuale: "Lascia vuoto se l'account non ha una password" (è un campo normale, si lascia vuoto);
- nuova di almeno 6 caratteri ("Almeno 6 caratteri") e uguale alla conferma ("Le password non coincidono"), altrimenti l'errore sotto il campo e nessuna richiesta;
- 403 → "Password attuale sbagliata" sotto la password attuale (vale anche per un caso raro, §11), con il fuoco e il testo selezionato (vedi "il fuoco dopo un errore" più sotto);
- un altro errore va sopra i campi: senza rete e con 502, 503 o 504 (nginx mentre Jellyfin si riavvia) "WonderFlix non è raggiungibile. Controlla la connessione.", come nei contatti; altrimenti il testo di `describeError`, di solito "Qualcosa è andato storto. Riprova." (un 401 di una sessione scaduta dà "Nome utente o password errati.", ma la sessione si chiude comunque e si torna all'accesso);
- ok → la finestra si chiude e arriva l'avviso "Password cambiata. Gli altri dispositivi dovranno rientrare." Il profilo di questo PC tiene il suo token.

**Contatti per il recupero** (solo con `SocialFeatures.account`), una riga per canale, larghe al più 640 px (su uno schermo largo le azioni restano vicine al contatto):

- stato: "Non collegato" / "Collegato: garg" / "Collegato: a@example.com"; canale spento → riga grigia "Non disponibile su questo server", anche con il contatto;
- azioni:
  - *Collega* (o *Cambia*) solo con il canale acceso;
  - *Scollega* se c'è il contatto, **anche su un canale spento**: i contatti restano (§11), e l'utente può toglierlo;
  - allo screen reader i pulsanti dicono anche il canale ("Collega Discord");
- mentre i contatti arrivano, uno spinner; se la lettura non riesce, "Non è stato possibile leggere i contatti" e "Riprova";
- *Collega* apre la finestra "Collega {canale}" (`LinkContactDialog`), a due passi:
  1. "Nome utente Discord" (sotto: "Il nome utente, non il nome visualizzato") oppure "Email", **"Password attuale"** (vuota per un account senza password, come nel cambio) e "Invia codice". Un nome vuoto dà l'errore senza richiesta;
  2. "Ti abbiamo mandato un codice su Discord" / "Ti abbiamo mandato un codice a a@example.com", campo "Codice", "Conferma" (senza password) e "Rimanda il codice";
- **la password resta nella finestra fra i due passi** (nello `State`, fino alla chiusura): rimandare rifà `Start`, che la vuole di nuovo. Ogni rinvio conta un controllo della password (`PasswordChecks`) e un invio dell'ora (`LinkStartHour`);
- **"Rimanda il codice"** (`ResendCodeButton`):
  - dice "Rimanda tra {secondi} s" per 60 s da quando il codice è partito, come il limite di un codice al minuto (il conto è dell'app);
  - è spento mentre un'altra richiesta (la conferma) è in volo;
  - il conto riparte dopo un invio riuscito e dopo un 429; dopo un altro errore si può riprovare subito;
  - dopo un invio riuscito il campo del codice si svuota: il codice nuovo sostituisce il vecchio sul server, e con quello vecchio nel campo "Conferma" darebbe "Codice non valido o scaduto". Dopo un 429 o un altro errore nessun codice è partito, e quello scritto resta;
  - `WrongPassword` a un rinvio (la password è cambiata altrove dopo il primo passo) riporta al primo passo, con l'errore sotto la password e il fuoco sulla password, con il testo selezionato;
- conferma riuscita → la finestra si chiude, la riga prende i contatti della risposta e arriva l'avviso "Contatto collegato";
- *Scollega* apre la finestra "Scollegare {canale}?" (`UnlinkContactDialog`): "Non potrai più usarlo per recuperare la password. Scrivi la password attuale per confermare.", la **password attuale** e "Scollega" (`POST Contacts/{canale}/Unlink`, §7.6). Riuscito → "Contatto scollegato" e i contatti riletti;
- gli errori di §7.6 diventano testi (§10, `accountFailureText`), sotto il campo che riguardano:
  - il nome per `InvalidTarget` e `MemberNotFound` al primo passo, la password per `WrongPassword`, il codice per `InvalidCode`;
  - gli altri sopra i campi;
  - il 429 (troppi invii o troppi controlli della password) è "Troppe richieste: riprova più tardi": i limiti arrivano a un giorno (§7.5);
  - `ChannelOff` e il 404: "Non disponibile su questo server"; senza rete: "WonderFlix non è raggiungibile. Controlla la connessione."; `Invalid` e il 500: "Qualcosa è andato storto. Riprova.";
- **il fuoco dopo un errore sotto un campo**: Invio nell'ultimo campo gli toglie il fuoco, e senza questo ogni errore costringerebbe a cliccare di nuovo. Il fuoco torna al campo dell'errore, con il testo selezionato per riscriverlo: nel collegamento il nome o l'email per `InvalidTarget` e `MemberNotFound`, la password attuale per `WrongPassword` e il codice per `InvalidCode`; nello scollegamento la password attuale per `WrongPassword`; nel cambio la password attuale per il 403; nel recupero il codice per `InvalidCode` (§9.3). Lo fa `focusAndSelectAfterFrame` (`lib/features/account/field_focus.dart`), dopo il frame, quando il campo c'è;
- **le tre finestre non si chiudono mentre una richiesta è in volo**: Esc, il clic fuori e "Annulla" sono spenti. Altrimenti la password cambierebbe senza l'avviso, o il contatto si collegherebbe (o scollegherebbe) sul server con la riga vecchia;
- errori e suggerimenti sotto i campi vanno a capo (fino a 3 e 2 righe): "Non ti trovo nel server Discord…" non si tronca.

Testo sotto le righe: "Servono per recuperare la password se la dimentichi. Gli admin non possono usare il recupero automatico." (la seconda frase solo per gli admin).

### 9.3 Login → "Password dimenticata?"

- **Il recupero è una seconda vista di `LoginScreen`** (`RecoveryPanel`, `lib/features/auth/recovery_panel.dart`), non la rotta `/login/recover`: `sessionRedirect` manda chi non è dentro a `/login` e basta (una rotta in più andrebbe tolta dal redirect), e con Quick Connect il modulo sta in una scheda alta 300 px. Il recupero prende tutto il pannello, al posto del modulo e delle schede.
- **"Password dimenticata?"** nel modulo c'è sempre (non più solo con `supportUrl`), accanto a "Scrivi all'admin" (solo con `supportUrl`, come prima). È spento mentre un accesso è in volo: il recupero smonterebbe il modulo, e l'errore o l'ingresso andrebbero persi.
- **"Torna all'accesso"** (freccia, in alto) riporta al modulo. Il nome scritto passa dall'accesso al recupero e ritorno. È spento durante una richiesta: tornando indietro a metà cambio la password cambierebbe senza l'accesso e senza un avviso.
- Titolo: "Recupera la password".
- **Passo 1:** campo nome utente (con il nome scritto nell'accesso), "Invia codice" e, sotto, "Ho già un codice" (più avanti).
  - nome vuoto → "Scrivi il nome utente", senza richiesta;
  - 202 → il passo 2, con la risposta neutra "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato un codice su Discord o per email.";
  - 429 → "Troppe richieste: riprova più tardi";
  - senza rete → "WonderFlix non è raggiungibile. Controlla la connessione.", e si resta al passo 1;
  - plugin vecchio (404) → "Il recupero automatico non è disponibile su questo server: contatta l'amministratore", al posto dei campi (§9.1);
  - un altro errore → "Qualcosa è andato storto. Riprova."
- **Passo 2:** codice, nuova password, conferma, "Cambia password" e "Rimanda il codice" (come in §9.2: 60 s, il conto che riparte dopo un invio riuscito o un 429, il campo del codice che si svuota dopo un invio riuscito). "Rimanda" è spento mentre il cambio è in volo: un codice nuovo sostituirebbe quello che si sta usando.
  - **il nome per cui vale il codice** sta sopra il campo del codice, subito sotto il testo ("Scrivi il codice…" o "Se l'account esiste…"), in grigio: "Account: {name}" (`recoveryForUser`), in tutti e due i casi del passo 2. Con "Ho già un codice" un errore di battitura nel nome darebbe "Codice non valido o scaduto" e consumerebbe i tentativi, senza che il nome si veda più;
  - codice vuoto, password più corta di 6 caratteri o diversa dalla conferma → l'errore sotto il campo, senza richiesta;
  - 204 → accesso con la nuova password (`SessionController.loginWithPassword`): l'app entra e aggiorna il profilo salvato;
  - `InvalidCode` → "Codice non valido o scaduto", sotto il codice, con il fuoco e il testo selezionato (§9.2);
  - `WeakPassword` → "Almeno 6 caratteri", sotto la nuova password;
  - 429 → "Troppi tentativi: riprova più tardi o contatta l'amministratore" (i limiti arrivano a un giorno, §7.5);
  - senza rete → "WonderFlix non è raggiungibile. Controlla la connessione.": il codice può essere ancora buono, e chiederne un altro costa uno dei limiti di `Start`;
  - 404 (plugin vecchio) → "Il recupero automatico non è disponibile su questo server: contatta l'amministratore", al posto dei campi. Arriva solo con "Ho già un codice", che non passa da `Start`;
  - 500 (Jellyfin non ha cambiato la password e il codice è già usato, §11) e ogni altro errore → "Cambio non riuscito: chiedi un nuovo codice".
- **"Ho già un codice"** (piano 18c): per il codice mandato dall'admin (§9.5). Senza, quel codice non serviva: il passo 1 ne chiedeva un altro, che lo sostituiva.
  - porta al passo 2 con il nome scritto, **senza** chiamare `Start`; nome vuoto → "Scrivi il nome utente", come "Invia codice";
  - sopra il campo del codice, al posto della risposta neutra: "Scrivi il codice che hai ricevuto su Discord o per email.";
  - "Rimanda il codice" c'è anche qui, con il conto di 60 s che parte quando compare il passo 2. Dopo un rinvio riuscito il testo torna "Se l'account esiste…" e il campo del codice si svuota: il codice nuovo sostituisce quello che si aveva. Dopo un rinvio non riuscito restano il testo e il codice scritto: quello di prima vale ancora.
- **Password cambiata, accesso no.** Se il cambio riesce e l'accesso no, il passo 2 mostra solo "Password cambiata: accedi con quella nuova.", l'errore dell'accesso e "ACCEDI", che riprova l'accesso con la password già cambiata. Niente campi né "Rimanda": il codice è già usato, e una password riscritta lì sarebbe ignorata. A fine accesso "ACCEDI" ha il fuoco.
- Sotto, solo con `supportUrl`: "Nessun contatto collegato?" e "Scrivi all'admin" (il link `supportUrl`). Con il plugin vecchio resta solo "Scrivi all'admin".

### 9.4 Cassetta

- `ContactReminderEntry` (`Type: "ContactReminder"`, `channels`: i canali che l'app conosce; uno sconosciuto si salta).
- Riga (`lib/features/inbox/inbox_account_row.dart`): icona `InboxRequestIcon` con `LucideIcons.shieldCheck`, "Proteggi il tuo account", il testo per i canali della voce e l'ora. Il testo è "Collega Discord o la tua email per recuperare la password se la dimentichi.", oppure quello solo per Discord o solo per l'email; senza un canale noto, quello per tutti e due.
- Clic → chiude il pannello e apre `/settings`, senza `?section=account`: la sezione Account è la prima. Se si è già in Impostazioni, la pagina resta dov'è (accettato). Si cancella come le altre voci.
- Il promemoria vero si prova al rilascio (18c): sul server i promemoria restano spenti fino ad allora (§15), e nel 18b la voce la coprono i test.

### 9.5 Amministrazione → Utenti

- `AdminTab.users` ("Utenti"), fra Sessioni e Manutenzione, solo con `SocialFeatures.account`. Senza la funzione, o se sparisce mentre la si guarda, `/admin?tab=users` mostra Sessioni; finché le funzioni del plugin non sono note (subito dopo il login) la pagina aspetta, come per WonderFlix.
- **`UsersTab`** (`lib/features/admin/users_tab.dart`) legge `GET Admin/Users` con `AccountUsersController` (`account_admin_controllers.dart`), un `AdminTabController`: all'apertura della scheda, dopo ogni azione e **ogni 2 minuti**. La prima stesura diceva "niente `AdminPoller`", ma l'infrastruttura delle schede (dati non aggiornati, "Riprova", rilettura dopo un riavvio di Jellyfin, 403) vuole un intervallo, e una lettura ogni 2 minuti costa poco: il plugin ha utenti e contatti in memoria.
  - elenco non letto → l'errore e "Riprova"; rilettura fallita → "Dati non aggiornati" sopra l'elenco di prima; elenco vuoto → "Nessun utente".
- **Una riga per utente** (`AccountUserRow`), nell'ordine del plugin (per nome):
  - l'avatar con `UserAvatar.lookup` (l'elenco del plugin non ha il tag dell'immagine), il nome (si tronca solo quando non c'è più posto) e le etichette "Admin" e "Disattivato";
  - le icone di Discord ed email, oro se collegate e grigie se no, con il tooltip "Discord: garg" / "Discord non collegato" e "Email: g•••@example.com" / "Email non collegata" (l'email arriva già mascherata dal plugin);
  - il menu delle azioni, che allo screen reader dice "Azioni per {name}".
- **Le azioni** (`userActions`):
  - **"Imposta password"** su tutte le righe tranne la propria: per la propria Jellyfin vuole `CurrentPw` anche da un admin (§3), e c'è "Cambia password" (§9.2). La propria riga si riconosce con `jellyfinIdKey`: il plugin dà l'id nel formato `N`, Jellyfin con i trattini;
  - **"Invia codice di recupero"** solo per chi non è admin, è attivo e ha almeno un contatto;
  - **"Scollega contatti"** solo con almeno un contatto;
  - una riga senza azioni non ha il menu;
  - mentre un'azione è in corso (anche con la finestra di conferma o di "Imposta password" aperta) la riga si vede al lavoro: al posto dell'icona del menu c'è uno spinner piccolo (16 px, nello stesso posto, `CircularProgressIndicator` con `strokeWidth` 2) e il menu è spento. Il menu non sparisce: resta, spento, così il posto e l'altezza della riga non cambiano;
  - la riga resta viva anche se si scorre fuori vista (`AutomaticKeepAliveClientMixin`): la `ListView` la smonterebbe, l'avviso andrebbe perso, il menu tornerebbe acceso e un secondo codice sostituirebbe il primo.
- **"Imposta password"** apre `SetPasswordDialog` (`set_password_dialog.dart`): "Imposta la password di {name}", "Le sessioni di {name} verranno chiuse.", nuova password e conferma, "Annulla" e "Imposta password".
  - almeno 6 caratteri e uguale alla conferma, altrimenti l'errore sotto il campo e nessuna richiesta;
  - passa da `AccountUsersController.setPassword`, cioè da `act`: `AuthApi.changePassword` senza `currentPassword` (§9.1), e Jellyfin chiude le sessioni dell'utente;
  - come le finestre del 18b non si chiude durante la richiesta (Esc, clic fuori e "Annulla" spenti); gli errori vanno sopra i campi, con i testi qui sotto;
  - riuscita → la finestra si chiude e arriva l'avviso "Password impostata. Le sessioni di {name} sono state chiuse.".
- **"Invia codice di recupero"** → la conferma "Mandare a {name} un codice per cambiare la password?" e "Invia", poi `POST Admin/Users/{id}/Recovery` con la lingua dell'app e l'avviso dei canali dove è arrivato: "Codice mandato su Discord ed email", "Codice mandato su Discord" o "Codice mandato per email". È un codice di recupero come gli altri: l'utente lo usa con "Ho già un codice" (§9.3).
- **"Scollega contatti"** → la conferma "Scollegare i contatti di {name}?" (va bene anche con un solo contatto) e "Scollega", poi `DELETE Admin/Users/{id}/Contacts` e l'avviso "Contatti di {name} scollegati". Il plugin annulla anche i codici già mandati (§7.4); la rilettura mostra la riga senza contatti.
- **Gli errori delle azioni** (`accountAdminErrorText`, `account_admin_labels.dart`), in un avviso o, per "Imposta password", sopra i campi:
  - `NotAllowed` → "Gli admin e gli utenti disattivati non possono usare il recupero automatico": il plugin lo dà per tutti e due, e arriva solo con un elenco vecchio, perché il menu non offre il codice a loro;
  - `NoContacts` → "{name} non ha contatti su un canale attivo": il menu offre il codice solo a chi ha un contatto, quindi arriva con un contatto su un canale spento (§11);
  - `SendFailed` → "Invio non riuscito, riprova più tardi"; `UnknownUser` → "Questo utente non c'è più";
  - 502, 503 e 504 senza `Code` (nginx mentre Jellyfin si riavvia) → "WonderFlix non è raggiungibile. Controlla la connessione.", come nel resto dell'app;
  - altrimenti `describeError`. Un 403 fa anche rileggere l'utente (`act`, §9.1);
  - **"Imposta password" con un 404** → "Questo utente non c'è più" (`adminUsersUnknown`): l'utente è stato cancellato nel frattempo e Jellyfin non lo trova (`NotFoundException`). Lo dice solo `SetPasswordDialog`, non `accountAdminErrorText`: per le chiamate del plugin un 404 vuol dire "funzione assente", non "utente sparito".

### 9.6 Amministrazione → WonderFlix: "Recupero password"

Una card nuova della scheda WonderFlix, come Annuncio, Titoli nuovi e Seerr: **`AccountRecoveryCard`** (`lib/features/admin/account_recovery_card.dart`), l'ultima, dopo Seerr. C'è solo con `SocialFeatures.account`; senza, lo stato non si legge.

- Lo stato da `GET Admin/Status` con `AccountAdminController` (un `AdminTabController`): all'apertura, ogni 30 s e dopo ogni prova. Lettura fallita → l'errore della card e "Riprova"; rilettura fallita → "Dati non aggiornati" sotto i dati di prima.
- Una riga per canale: "Discord: configurato" / "Discord: non configurato", lo stesso per "Email". Sotto, se c'è, l'ultimo errore con l'ora: "Ultimo errore: DM chiusi, 2 h fa" (oppure "token o server non validi", "invio non riuscito").
- "5 utenti su 23 hanno un contatto" (gli utenti attivi e non admin, e quelli fra loro con un contatto raggiungibile), "Promemoria ogni 14 giorni" (o "Promemoria spenti").
- **"Invia prova a me"** (`AdminActionButton`) → `POST Admin/Test` con la sola lingua, senza i campi `Discord` ed `Email`: la prova va ai contatti dell'admin.
  - accanto al pulsante l'esito per canale, per esempio "Discord: inviato · Email: collega prima il tuo contatto". Gli esiti sono "inviato", "non configurato", "collega prima il tuo contatto", "token o server non validi", "il bot non riesce a scriverti" e "invio non riuscito"; "nome non trovato nel server" e "contatto non valido" (`MemberNotFound`, `InvalidTarget`) non arrivano dall'app, solo dalla Dashboard;
  - una richiesta non riuscita (non un esito) dà un avviso con `describeError`;
  - all'inizio di una prova l'esito di prima sparisce: dopo una prova fallita non resta quello vecchio;
  - la prova dura fino a 24 s: intanto il pulsante è spento. La card resta viva anche fuori vista (`AutomaticKeepAliveClientMixin`) finché la prova dura e finché c'è un esito: la `ListView` la smonterebbe, e si perderebbero l'esito e lo stato del pulsante (se ne potrebbe far partire un'altra).
- Nessun campo modificabile: in fondo "Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix".

## 10. Testi nuovi (ARB, it + en)

Italiano (l'inglese segue, con le stesse chiavi in `app_it.arb` e `app_en.arb`). Fra parentesi la chiave; quelle segnate "c'era" esistevano già.

- Impostazioni: "Account" (`settingsAccount`, c'era), "Cambia password" (`settingsChangePassword`), "Password attuale" (`accountCurrentPassword`), "Lascia vuoto se l'account non ha una password" (`accountNoPasswordHint`), "Nuova password" (`accountNewPassword`), "Conferma la password" (`accountConfirmPassword`), "Almeno 6 caratteri" (`accountPasswordTooShort`), "Le password non coincidono" (`accountPasswordsDiffer`), "Password attuale sbagliata" (`accountWrongPassword`), "Password cambiata. Gli altri dispositivi dovranno rientrare." (`accountPasswordChanged`), "Annulla" (`accountCancel`).
- Contatti: "Contatti per il recupero" (`accountContactsTitle`), "Servono per recuperare la password se la dimentichi." (`accountContactsHint`), "Gli admin non possono usare il recupero automatico." (`accountContactsAdminHint`), "Non è stato possibile leggere i contatti" (`accountContactsError`), "Discord" (`accountChannelDiscord`), "Email" (`accountChannelEmail`), "Non collegato" (`accountNotLinked`), "Collegato: {name}" (`accountLinked`), "Non disponibile su questo server" (`accountChannelOff`), "Collega" (`accountLink`), "Cambia" (`accountChange`), "Scollega" (`accountUnlink`), "Collega {channel}" (`accountLinkTitle`), "Scollegare {channel}?" (`accountUnlinkTitle`), "Non potrai più usarlo per recuperare la password. Scrivi la password attuale per confermare." (`accountUnlinkBody`), "Nome utente Discord" (`accountDiscordName`), "Il nome utente, non il nome visualizzato" (`accountDiscordNameHint`), "Invia codice" (`accountSendCode`), "Ti abbiamo mandato un codice su Discord" (`accountCodeSentDiscord`), "Ti abbiamo mandato un codice a {email}" (`accountCodeSentEmail`), "Codice" (`accountCode`), "Conferma" (`accountConfirm`), "Rimanda il codice" (`accountResendCode`), "Rimanda tra {seconds} s" (`accountResendIn`), "Contatto collegato" (`accountLinkedDone`), "Contatto scollegato" (`accountUnlinkedDone`).
- Errori: "Non ti trovo nel server Discord: usa il nome utente (non il nome visualizzato) e controlla di essere nel server" (`accountErrorMemberNotFound`), "Il bot non riesce a scriverti: in Discord abilita i messaggi diretti dai membri del server" (`accountErrorDmClosed`), "Email non valida" (`accountErrorInvalidEmail`), "Nome utente Discord non valido" (`accountErrorInvalidDiscordName`), "Invio non riuscito, riprova più tardi" (`accountErrorSendFailed`), "Troppe richieste: riprova più tardi" (`accountErrorRateLimited`), "Codice non valido o scaduto" (`accountErrorInvalidCode`). Senza rete e per gli errori generici: "WonderFlix non è raggiungibile. Controlla la connessione." (`errorServerUnreachable`, c'era) e "Qualcosa è andato storto. Riprova." (`errorGeneric`, c'era).
- Recupero: "Password dimenticata?" (`loginForgotPassword`, c'era), "Recupera la password" (`recoveryTitle`), "Torna all'accesso" (`recoveryBack`), "Nome utente" (`loginUsername`, c'era), "Scrivi il nome utente" (`recoveryNameNeeded`), "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato un codice su Discord o per email." (`recoveryCodeSent`), "Nessun contatto collegato?" (`recoveryNoContact`) con "Scrivi all'admin" (`loginContactAdmin`, c'era), "Il recupero automatico non è disponibile su questo server: contatta l'amministratore" (`recoveryUnavailable`), "Troppi tentativi: riprova più tardi o contatta l'amministratore" (`recoveryTooMany`), "Cambio non riuscito: chiedi un nuovo codice" (`recoveryFailed`), "Password cambiata: accedi con quella nuova." (`recoveryChanged`), "ACCEDI" (`loginSubmit`, c'era). Gli altri vengono dai contatti: "Invia codice", "Codice", "Nuova password", "Conferma la password", "Cambia password", "Rimanda il codice".
- Cassetta: "Proteggi il tuo account" (`inboxContactReminderTitle`), "Collega Discord o la tua email per recuperare la password se la dimentichi." (`inboxContactReminderBoth`), "Collega Discord per recuperare la password se la dimentichi." (`inboxContactReminderDiscord`), "Collega la tua email per recuperare la password se la dimentichi." (`inboxContactReminderEmail`).

Rispetto alla prima stesura:

- il 429 dice "più tardi" (i limiti arrivano a un giorno, §7.5): "Troppe richieste: riprova più tardi" per collegamento, scollegamento e primo passo del recupero, al posto di "Aspetta un momento prima di riprovare". Il secondo passo è "Troppi tentativi: riprova più tardi o contatta l'amministratore" (all'inizio diceva "riprova tra un'ora", ma un limite giornaliero lo smentisce);
- "Nessun contatto collegato? Contatta l'amministratore" è diventato "Nessun contatto collegato?" con il pulsante "Scrivi all'admin" che c'era già;
- testi in più: i suggerimenti sotto la password attuale e sotto il nome Discord, "Nome utente Discord non valido", "Non è stato possibile leggere i contatti", "Contatto collegato" / "Contatto scollegato", "Torna all'accesso", "Scrivi il nome utente", "Cambio non riuscito: chiedi un nuovo codice", "Password cambiata: accedi con quella nuova.", "Annulla", "Collega {channel}" e il testo della finestra di scollegamento.

Amministrazione e recupero (piano 18c):

- Utenti: "Utenti" (`adminTabUsers`), "Admin" (`adminUsersAdmin`), "Disattivato" (`adminUsersDisabled`), "Nessun utente" (`adminUsersEmpty`), "Azioni per {name}" (`adminUsersActionsFor`), "Discord: {name}" (`adminUsersDiscordLinked`), "Discord non collegato" (`adminUsersDiscordNone`), "Email: {email}" (`adminUsersEmailLinked`), "Email non collegata" (`adminUsersEmailNone`).
- Azioni sugli utenti: "Imposta password" (`adminUsersSetPassword`), "Imposta la password di {name}" (`adminUsersSetPasswordTitle`), "Le sessioni di {name} verranno chiuse." (`adminUsersSetPasswordHint`), "Password impostata. Le sessioni di {name} sono state chiuse." (`adminUsersPasswordSet`), "Invia codice di recupero" (`adminUsersSendRecovery`), "Mandare a {name} un codice per cambiare la password?" (`adminUsersSendRecoveryConfirm`), "Codice mandato su Discord ed email" (`adminUsersRecoverySentBoth`), "Codice mandato su Discord" (`adminUsersRecoverySentDiscord`), "Codice mandato per email" (`adminUsersRecoverySentEmail`), "{name} non ha contatti su un canale attivo" (`adminUsersNoContacts`), "Gli admin e gli utenti disattivati non possono usare il recupero automatico" (`adminUsersNotAllowed`), "Questo utente non c'è più" (`adminUsersUnknown`), "Scollega contatti" (`adminUsersUnlink`), "Scollegare i contatti di {name}?" (`adminUsersUnlinkConfirm`), "Contatti di {name} scollegati" (`adminUsersUnlinked`). Dal resto dell'app: "Invia" (`adminSend`, c'era), "Annulla" (`adminCancel` nelle conferme, c'era; `accountCancel` nella finestra), "Scollega" (`accountUnlink`), "Nuova password", "Conferma la password", "Almeno 6 caratteri", "Le password non coincidono", "Invio non riuscito, riprova più tardi" (`accountErrorSendFailed`) e "WonderFlix non è raggiungibile. Controlla la connessione." (`errorServerUnreachable`).
- Card "Recupero password": "Recupero password" (`adminRecovery`), "configurato" (`adminRecoveryConfigured`), "non configurato" (`adminRecoveryNotConfigured`), "{channel}: {state}" (`adminRecoveryChannelLine`, con "Discord" ed "Email" dei contatti), "Ultimo errore: {error}, {when}" (`adminRecoveryLastError`), "DM chiusi" (`adminRecoveryErrorDmClosed`), "token o server non validi" (`adminRecoveryErrorInvalid`), "invio non riuscito" (`adminRecoveryErrorSendFailed`), "{count} utenti su {total} hanno un contatto" / "1 utente su {total} ha un contatto" (`adminRecoveryWithContacts`), "Promemoria ogni {days} giorni" / "Promemoria ogni giorno" (`adminRecoveryReminders`), "Promemoria spenti" (`adminRecoveryRemindersOff`), "Invia prova a me" (`adminRecoveryTest`), "inviato" (`adminRecoveryTestSent`), "collega prima il tuo contatto" (`adminRecoveryTestNoContact`), "il bot non riesce a scriverti" (`adminRecoveryTestDmClosed`), "nome non trovato nel server" (`adminRecoveryTestMemberNotFound`), "contatto non valido" (`adminRecoveryTestInvalidTarget`), "Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix" (`adminRecoveryConfigHint`).
- Recupero: "Ho già un codice" (`recoveryHaveCode`), "Scrivi il codice che hai ricevuto su Discord o per email." (`recoveryEnterCode`), "Account: {name}" (`recoveryForUser`, in inglese uguale: "Account: {name}").

Rispetto alla lista della prima stesura:

- "{nome} non ha contatti collegati" è diventato "{name} non ha contatti su un canale attivo": `NoContacts` arriva solo con un contatto su un canale spento (§9.5);
- "Scollegare Discord ed email di {nome}?" è diventato "Scollegare i contatti di {name}?": vale anche con un solo contatto;
- "Gli admin non possono usare il recupero automatico" dice anche "e gli utenti disattivati": il plugin dà `NotAllowed` per tutti e due;
- "Codice mandato su {canali}" sono tre testi, uno per ogni combinazione di canali;
- stati ed esiti sono in minuscolo, dentro "{channel}: {state}" ("Discord: configurato", "Email: inviato");
- testi in più: "Nessun utente", "Azioni per {name}", i tooltip dei contatti, il titolo e l'avviso di "Imposta password", "Questo utente non c'è più", "Contatti di {name} scollegati", gli altri errori dell'ultimo invio e gli altri esiti della prova, "Promemoria ogni giorno", "Ho già un codice" con il suo testo, "Account: {name}" sopra il codice.

## 11. Errori e casi limite

- **Discord, nome non esatto.** La ricerca di Discord va per prefisso: senza una corrispondenza esatta dello username → `MemberNotFound`. Il nome visualizzato non vale. Un nome che non sembra un nome Discord (2–32 caratteri fra lettere, cifre, `_` e `.`) è `InvalidTarget`, senza chiedere a Discord.
- **Discord, intent mancante.** Se "Server Members" non è attivo la ricerca risponde con un errore: `SendFailed` all'utente. Il controllo dell'admin prova anche la ricerca, quindi lo scopre: `Invalid` nella prova, con l'errore ricordato nello stato del canale.
- **DM chiusi** (50007) → `DmClosed` al collegamento. Se l'utente chiude i DM dopo, il recupero fallisce in silenzio per l'utente; l'admin vede l'errore nella scheda.
- **Discord in 429.** Trattato come `SendFailed`, senza ritentare.
- **SMTP in errore.** `SendFailed`; la causa precisa va nel log del plugin, senza indirizzi. Con la porta 465 il log dice che serve la 587.
- **Plugin vecchio.** Niente righe dei contatti, niente scheda Utenti né card "Recupero password", niente voce nella cassetta; il cambio password funziona; il recupero dice che non è disponibile, con "Scrivi all'admin" se c'è `supportUrl` (§9.1, §9.3).
- **Canali spenti dopo il collegamento.** I contatti restano; il recupero usa solo i canali configurati; nessun canale → nessun codice (risposta neutra lo stesso). **Un contatto su un canale spento non conta** (§7.4): né per il recupero, né per `WithContacts` nello stato dell'admin, né per i promemoria (l'utente li riceve come chi non ha contatti). L'admin che manda un codice a un utente così ottiene `NoContacts` ("{name} non ha contatti su un canale attivo", §9.5). Nell'app la riga è grigia e "Scollega" resta (§9.2).
- **Cambio password senza il permesso delle preferenze.** Jellyfin risponde 403 a `POST /Users/Password` anche a un utente senza `EnableUserPreferenceAccess`: l'app dice "Password attuale sbagliata". Raro, accettato.
- **429 al primo passo del recupero con un codice già in arrivo.** Un 429 al primo passo lascia al primo passo, anche se un codice chiesto poco prima è in arrivo: si riprova più tardi (dopo un minuto, o di più se è scattato un limite all'ora o al giorno), e quel codice si può usare solo se il pannello è ancora al secondo passo. Accettato.
- **Accesso non riuscito dopo il recupero.** La password è cambiata e il codice è usato: il recupero resta sulla vista "password cambiata" e "ACCEDI" riprova solo l'accesso (§9.3).
- **Profili salvati (Spec K).** Cambio dall'app: questo PC tiene il token. Recupero: login nuovo e profilo aggiornato. Altri PC: token rifiutato, nuovo login.
- **Utente rinominato.** I contatti sono legati all'ID, non al nome.
- **Utente diventato admin.** Il recupero si ferma, anche per un codice già mandato (`InvalidCode`); i contatti restano.
- **Riavvio del server.** I codici si perdono ("Codice non valido o scaduto", se ne chiede un altro); contatti e `LastReminderAt` restano.
- **Promemoria cancellato a mano.** Il prossimo arriva N giorni dopo l'ultimo mandato (meno l'ora di tolleranza), non dalla cancellazione.
- **Due richieste di collegamento insieme** (Discord ed email) → due codici con scopi diversi, nessun conflitto.
- **Blocco dopo i login sbagliati di Jellyfin.** Un utente bloccato da Jellyfin risulta disattivato, quindi senza recupero: passa dall'admin. Sul server `LoginAttemptsBeforeLockout` è NULL per tutti e 23 gli utenti (verificato il 2026-10-09) e con NULL Jellyfin non blocca mai (sorgente `v10.11.9`, `UserManager.IncrementInvalidLoginAttemptCount`). Caso accettato: se un giorno il blocco si accende, l'utente bloccato passa dall'admin.
  - Chi ha solo una sessione può far crescere `InvalidLoginAttemptCount` con password sbagliate sui contatti (§8), fino a 10 all'ora. Innocuo con il blocco spento; da ricordare se si accende.
- **Elenco utenti vuoto.** Se Jellyfin dà un elenco vuoto (errore momentaneo) la pulizia dei promemoria non toglie nessun contatto (§7.7).
- **`RevokeUserTokens` fallisce dopo il cambio.** La password è cambiata e il codice è usato: l'errore va nel log e il recupero riesce lo stesso.
- **`ChangePassword` fallisce** (Jellyfin in errore, utente sparito proprio allora). L'errore esce come 500 e il codice, già usato, non vale più: se ne chiede un altro (nell'app "Cambio non riuscito: chiedi un nuovo codice", §9.3).
- **Codice mandato dall'admin sostituito.** Se l'utente preme "Invia codice" invece di "Ho già un codice", il codice nuovo sostituisce quello dell'admin (§7.2) e arriva agli stessi contatti: quello dell'admin non vale più, e se l'utente non guarda i messaggi nuovi scrive un codice che non va (`InvalidCode`, e un tentativo in meno). Accettato: le note della 0.12.0 dicono come si usa ("Password dimenticata?" → "Ho già un codice", entro 10 minuti), e il nome sopra il campo (§9.3) evita almeno l'errore di battitura nel nome.
- **Scollegare annulla il codice di recupero in sospeso** (dall'utente e dall'admin). **Un cambio di password fuori dal recupero non lo annulla:** dall'app o con "Imposta password" non c'è un evento di Jellyfin da ascoltare. Punto aperto: il codice dura al più 10 minuti e arriva solo ai contatti verificati.

## 12. Test

**Plugin** (xUnit, TDD):

- `CodeBook`: codice di 6 cifre, hash e sale, scadenza a 10 minuti con `FakeTimeProvider`, 5 tentativi, sostituzione, uso singolo, spazi e trattini.
- `ContactStore` e `ContactRegistry`: lettura, scrittura, file illeggibile in `.bad`, voci non valide rifiutate, copie, utenti spariti.
- `RateLimiter`: nuovi tipi, `IsLimited`, pulizia delle chiavi vecchie.
- `ContactLinking`, `PasswordRecovery`, `AccountAdmin`, `AccountSender` con oggetti finti (`AccountRig`):
  - collegamento: canale spento, ordine dei controlli, limiti (il minuto si conta solo quando il codice parte), password sbagliata, membro non trovato, DM chiusi (il codice sparisce), email non valida, conferma giusta e sbagliata, promemoria tolti, scollegamento che annulla il codice di recupero;
  - recupero: risposta uguale per utente inesistente, disattivato, admin, senza contatti; codice a tutti i contatti; limiti per nome e globali, anche con richieste insieme; `WeakPassword` prima del codice; `ChangePassword` + `RevokeUserTokens(id, "")`; avviso "password cambiata"; chiave dei limiti in maiuscolo;
  - admin: elenco con email mascherata, invio a un admin o a un disattivato vietato, senza contatti, scollegamento (con i codici annullati), stato, prova con nome ed email scritti.
- `DiscordBotClient` con un `HttpMessageHandler` finto: corrispondenza esatta fra più risultati, bot saltati, `@` iniziale, 50007, 401, 429, tempo massimo per operazione, token mai nel log.
- `SmtpMailSender`: trasporto finto (errori, tempo massimo, indirizzi tolti dal log, porta 465) e due prove del vero `SmtpClient` su un server finto locale (silenzioso, senza STARTTLS).
- `PasswordChanging` (le due firme di `ChangePassword`), `JellyfinPasswordReset`, `JellyfinPasswordCheck`.
- `AccountMessages`: italiano e inglese, lingua sconosciuta → italiano.
- Promemoria: N con un'ora di tolleranza, canali spenti, admin e disattivati esclusi, sostituzione della voce, `LastReminderAt`, pulizia degli utenti cancellati (anche a promemoria spenti, non con l'elenco vuoto), collegamento a metà giro.
- Controller: stati HTTP e `{Code}` di §7.6, `[AllowAnonymous]` solo sul recupero, `RequiresElevation` sull'admin, `Invalid` per canale sconosciuto o corpo mancante.
- Pagina della Dashboard (`PluginPagesTests`) e registrazione dei servizi (`ServiceRegistrationTests`).

**App, piano 18b** (TDD), sotto `test/`:

- `core/social/account_api_test.dart`: corpi e rotte (il `Code` come stringa, lo scollegamento con la password anche vuota), la tabella degli errori di §9.1, rete e risposta di forma inattesa, esiti previsti nel log come info.
- `core/jellyfin/auth_api_test.dart`: `changePassword` con e senza la password attuale, il 403 nel log come info.
- `core/logging/redact_test.dart`: i nuovi campi non finiscono nei log; un `"Code"` numerico e la forma a mappa `{code: 4000}` restano com'erano.
- `core/social/inbox_models_test.dart`: `ContactReminderEntry` nel parser della cassetta, con i canali sconosciuti saltati e senza canali.
- `features/social/social_providers_test.dart`: la funzione `account` da `Info`, anche senza watch party.
- `features/account/account_providers_test.dart`: i contatti senza la funzione o senza un utente (nessuna chiamata), la lettura con l'errore, `replace` e `reload` (senza spinner), la funzione che si accende con il provider aperto, il cambio di utente a metà rilettura.
- `features/account/resend_code_button_test.dart`: attivo dopo 60 s, il conto che riparte solo quando deve, spento senza `onResend`, di nuovo attivo se `onResend` lancia.
- `features/account/change_password_dialog_test.dart`: i controlli prima della richiesta, la password attuale sbagliata e quella vuota, il server irraggiungibile, errori e suggerimenti a più righe, Esc e "Annulla" spenti durante la richiesta.
- `features/account/link_contact_dialog_test.dart`: i due passi con gli errori al loro posto, il doppio clic, "Rimanda" con la stessa password (dopo un 429, dopo un invio fallito, con la password cambiata altrove, spento durante la conferma), la finestra che non si chiude durante la richiesta.
- `features/account/unlink_contact_dialog_test.dart`: la password sbagliata e quella giusta, il 429, la finestra che non si chiude durante la richiesta.
- `features/settings/account_settings_section_test.dart`: la sezione senza la funzione, le righe (collegato, canale spento con "Scollega", admin), lo spinner, i pulsanti per lo screen reader, la larghezza su uno schermo largo, "Collega" e "Scollega" con i loro avvisi, i contatti non letti con "Riprova", l'avviso del cambio password.
- `features/settings/settings_test.dart`: "Cambia password", e Account come prima sezione.
- `features/auth/recovery_panel_test.dart`: andata e ritorno con il nome, Quick Connect, i due passi con i loro errori (nome vuoto, 429, plugin vecchio, rete, `WeakPassword`, codice già usato), l'accesso finale, la vista "password cambiata" con il fuoco su "ACCEDI", "Torna all'accesso" e "Password dimenticata?" spenti durante una richiesta, il link senza `supportUrl`, "Rimanda".
- `features/inbox/inbox_contact_reminder_test.dart`: i testi per i canali, il clic che chiude il pannello e apre Impostazioni.
- `app/l10n_plan18b_test.dart`: i testi del 18b, e `app_it.arb` e `app_en.arb` con le stesse chiavi.

**App, piano 18c** (TDD), sotto `test/`:

- `core/social/account_admin_api_test.dart`: rotte e corpi degli endpoint dell'admin, l'email mascherata, i campi obbligatori (ogni campo tolto da solo, con la risposta completa come controllo: `Id`, `Name`, `IsAdmin` ed `Enabled` di un utente; `Discord`, `Email`, `WithContacts`, `Users` e `ReminderDays` dello stato; e `LastError` senza `At` o senza `Code`; non si prova invece `Configured` dentro un canale), un 200 del codice senza un canale che l'app conosce, il `Code` con `pluginErrorCode` e il tipo degli errori (403 `ForbiddenException`, gli altri `ServerErrorException` con il loro stato), gli esiti previsti nel log come info.
- `features/admin/account_admin_controllers_test.dart`: le letture, le azioni che chiamano il plugin e rileggono (lo scollegamento rilegge la riga senza contatti), "Imposta password" senza la password attuale, un 403 che fa rileggere l'utente.
- `features/admin/account_admin_labels_test.dart`: dove è arrivato il codice, i `Code` del plugin, 502/503/504 senza `Code` "non raggiungibile" (e un 502 `SendFailed` che resta "invio non riuscito"), l'ultimo errore e gli esiti della prova.
- `features/admin/set_password_dialog_test.dart`: titolo e avviso sulle sessioni, i controlli prima della richiesta, la riuscita senza la password attuale, il 403 sopra i campi con l'utente riletto, il 404 "Questo utente non c'è più", Esc spento durante la richiesta (con `pumpAndSettle`, che senza il `PopScope` diventa rosso).
- `features/admin/users_tab_test.dart`: `userActions`; le righe con le etichette e i tooltip; il menu (le tre azioni, "Azioni per {name}", la propria riga anche con l'id scritto in un altro modo, la riga senza menu, lo spinner al posto dell'icona e il menu spento durante un'azione, anche con la riga fuori vista); il nome lungo; le tre azioni con i loro avvisi, l'errore `NoContacts` e "Annulla"; l'elenco vuoto e quello non letto con "Riprova".
- `features/admin/account_recovery_card_test.dart`: senza la funzione niente card e niente letture; canali, ultimo errore, conteggi, promemoria (anche spenti) e dove si configura; la prova con l'esito per canale, non riuscita (l'avviso e nessun esito vecchio) e con la card fuori vista; la lettura fallita con "Riprova"; "Dati non aggiornati".
- `features/admin/admin_navigation_test.dart`, `admin_screen_test.dart`, `wonderflix_tab_test.dart`: Utenti fra Sessioni e Manutenzione solo con `account`, Sessioni se la funzione manca o sparisce, l'attesa delle funzioni del plugin; la card dopo Seerr, solo con `account`.
- `features/auth/recovery_panel_test.dart`: "Ho già un codice" (senza `Start`, senza il nome, "Rimanda" riuscito e non riuscito, il 404 a `Complete`); "Account: {name}" sopra il codice, dopo "Ho già un codice" e dopo "Invia codice".
- `app/l10n_plan18c_test.dart`: i testi del 18c, in italiano e in inglese.

**Prova a mano sul server:**

1. Configurazione nella Dashboard e "Send a test". **Fatto il 2026-10-09 (§14):** Discord ed email hanno mandato la prova.
2. Collegare Discord (password sbagliata, nome sbagliato, nome giusto, codice sbagliato, codice giusto) ed email.
3. Recupero dal login con un account di prova; la sessione su un secondo dispositivo si chiude; avviso "password cambiata".
4. Dall'admin: "Invia codice di recupero" (il codice si usa con "Ho già un codice"), "Imposta password", "Scollega contatti", la card "Recupero password" con "Invia prova a me".
5. Promemoria con `ContactReminderDays` basso (1) e un utente senza contatti; sparisce dopo il collegamento. Sul server i promemoria restano spenti (0) fino al rilascio (§15): il giro segna `LastReminderAt` per tutti gli utenti senza contatti, e l'app 0.11 non mostra la voce. **Si prova al rilascio, nel 18c**, quando i promemoria si riaccendono: nel 18b la voce della cassetta la coprono i test.
6. Cambio della propria password; il profilo su questo PC resta dentro.

I punti 2, 3 e 6 si provano con l'app nuova alla fine del 18b, con una build locale e un account di prova non admin; il 4 con la build locale del 18c, prima del merge (Task 9 del piano 18c); il 5 al rilascio, dopo aver riacceso i promemoria. Nel 18a, oltre alla prova del punto 1, sul server sono stati provati i controlli anonimi (§14).

## 13. Preparazione (a cura dell'utente)

Credenziali e consensi li gestisce l'utente.

- **Discord:** nel Developer Portal, sull'app 1397884246692986970, aggiungere il bot, copiare il token, attivare l'intent "Server Members"; invitare il bot nel server (scope `bot`, nessun permesso speciale); copiare l'ID del server (modalità sviluppatore → clic destro sul server).
- **Email:** scegliere un SMTP sulla porta 587 con STARTTLS (la 465 non funziona) e un mittente. Le credenziali stanno nella configurazione del plugin, che gli admin leggono: meglio che non aprano niente di prezioso. Due strade:
  - **un account Gmail dedicato con una password per app** (gratis, `smtp.gmail.com`, porta 587): contiene soltanto codici monouso già scaduti, quindi chi ne trova la password non ci guadagna nulla. Non l'account personale: una password per app dà accesso alla posta dell'account, e chi la legge dalla configurazione potrebbe leggere anche i codici appena inviati;
  - **la chiave per solo invio di un servizio con un dominio** (Resend, Brevo): può spedire e basta, non legge la posta. Serve un dominio proprio: Resend, per esempio, richiede un dominio verificato.

  Sul server c'è la prima: un Gmail dedicato con password per app (provato il 2026-10-09, §14), perché non c'è un dominio per Resend.
- **Quante email può far partire un estraneo.** Chi scrive un nome utente nel recupero fa partire un'email solo se quell'utente ha l'email collegata, e i limiti (§7.5) tengono basso il numero: al più 1 al minuto, 5 all'ora e 10 al giorno per ogni nome, e al più 30 richieste all'ora in tutto (720 al giorno). Con N utenti che hanno un'email collegata sono al più 10 × N email al giorno, e mai più di 720: da confrontare con il tetto giornaliero del servizio scelto. Il codice mandato dall'admin e la prova non passano da questi limiti.
- **Dashboard:** inserire tutto nella pagina del plugin, con "Reminder every (days)" a 0 finché non esce l'app 0.12 (§15), poi "Save" e "Send a test". Se non si hanno ancora contatti collegati, la prova accetta il proprio nome utente Discord e la propria email nei due campi; deve leggere "Discord: sent. E-mail: sent." e arrivano il DM del bot e l'email (da guardare anche nello spam).

## 14. Rischi e punti da verificare

**Verificati, e stato sul server** (piano 18a e prova del 2026-10-09):

- **Firme di Jellyfin 10.11.9.** Controllate sui pacchetti NuGet 10.11.0 e 10.11.9 (riflessione) e sul sorgente `v10.11.9`:
  - `ChangePassword` cambia firma fra le due versioni: `ChangePassword(User, string)` nella 10.11.0, `ChangePassword(Guid, string)` nella 10.11.9. È risolto a runtime da `Server/PasswordChanging.cs` (§3);
  - `ISessionManager.RevokeUserTokens(Guid, string)` è uguale nelle due versioni e con `string.Empty` chiude **tutte** le sessioni: `SessionManager` confronta il token di ogni dispositivo con quello passato;
  - `GetUserById`, `GetUserByName` e `AuthenticateUser` sono uguali nelle due versioni.
- **Build di prova sul server.** Il pacchetto 1.6.0.0 (dll md5 `bc707ef63f1df9dddbc70ce6539ed537`), con tutti i riferimenti a tipi e membri risolti contro Jellyfin 10.11.9, si è caricato sul server in 60 s senza errori. `GET Info` ha `account` e ancora `requests`: Seerr è sopravvissuto.
- **Rotta anonima.** `[AllowAnonymous]` su un controller del plugin funziona con lo schema di autenticazione di Jellyfin: lo usa già il webhook di Seerr, e sul server `Recovery/Start` ha risposto 202 e subito dopo 429, `Recovery/Complete` con un codice sbagliato 400 `InvalidCode`, mentre le rotte dell'utente e dell'admin senza accesso 401.
- **Plugin vecchio prima dell'accesso.** Una rotta del plugin che non esiste, chiamata senza accesso, risponde 404 (provato il 2026-10-09 sul server: `POST WonderFlixWatchParty/Account/Recovery/Nope` e `POST WonderFlixWatchParty/Nope/Recovery/Start` danno 404): così l'app riconosce il plugin senza recupero (§9.1).
- **Ricerca dei membri su Discord.** Con l'intent "Server Members" attivo e un bot senza permessi speciali, `members/search` e il messaggio diretto funzionano: la prova della Dashboard ("Send a test") ha mandato il DM e l'utente l'ha ricevuto. Basta quindi la ricerca per prefisso, senza passare da `GET /guilds/{id}/members` con la paginazione.
- **`System.Net.Mail` nel processo di Jellyfin su Linux (Ultra.cc).** STARTTLS e autenticazione col vero `SmtpClient` verso `smtp.gmail.com:587` (account Gmail dedicato con password per app, §13) funzionano: la prova della Dashboard ha mandato l'email e l'utente l'ha ricevuta.
- **Porta 465.** Non funziona (il TLS implicito non c'è, solo STARTTLS): lo dicono la pagina della Dashboard e, con quella porta, il log del plugin.
- **Log.** Nel log di Jellyfin non compaiono il token del bot, la password SMTP, l'utente SMTP né l'indirizzo del mittente.
- **Promemoria.** Sul server restano spenti (`ContactReminderDays` = 0) fino al rilascio con l'app 0.12.0 (§15).

**Rischi che restano:**

- **Recupero bloccato da terzi.** Chi conosce un nome utente può esaurire i suoi tentativi (10 errori all'ora, 20 al giorno) e bloccarne il recupero per quella finestra; con i limiti globali (§7.5) chi insiste può tenerlo chiuso a tutti. L'admin resta la via d'uscita: "Imposta password" passa da Jellyfin, non dal plugin.
- **Blocco dopo i login sbagliati di Jellyfin.** Spento sul server (§11); da ricordare se si accende.
- **Cambio password fuori dal recupero.** Non annulla un codice di recupero già mandato (§11): punto aperto.

## 15. Piani e release

- **Piano 18a — plugin: realizzato.** Modulo `Account/`, adattatori, endpoint, configurazione e pagina della Dashboard, promemoria, `Info`. Prova del plugin sul server con un pacchetto di prova (come per il 17c): fatta il 2026-10-09 (§14).
  - Fino al rilascio sul server resta la build di prova 1.6.0.0, con i promemoria spenti (`ContactReminderDays` = 0): l'app 0.11 salta le voci di tipo sconosciuto, ma `LastReminderAt` verrebbe segnato per tutti.
  - **Il plugin 1.6.0 non esce dopo il 18a:** esce nel Catalogo con l'app 0.12.0, alla fine del 18c. Niente tag e niente `manifest.json` prima.
  - **Al rilascio**, nel `manifest.json` si aggiunge la versione in `versions` e si aggiornano anche `description` e `overview` (come in `meta.template.json`), non solo `versions`. Poi si riaccendono i promemoria (14 giorni) dalla pagina del plugin nella Dashboard.
- **Piano 18b — app, lato utente: realizzato.** `AccountApi` e `AccountFailure`, `changePassword`, la funzione `account`, Impostazioni → Account in cima (cambio password e contatti, con la password attuale per collegare e scollegare, §9.2), "Password dimenticata?" come seconda vista dell'accesso (§9.3), voce della cassetta, `redact.dart`, testi.
  - Niente release dopo il 18b: l'app 0.12.0 esce alla fine del 18c.
  - La prova a mano (punti 2, 3 e 6 di §12) si fa con una build locale, prima del merge.
- **Piano 18c — app, lato admin: realizzato.** Gli endpoint dell'admin in `PluginAdminApi` (§9.1), la scheda Utenti con "Imposta password", "Invia codice di recupero" e "Scollega contatti" (§9.5), la card "Recupero password" nella scheda WonderFlix (§9.6), "Ho già un codice" nel recupero (§9.3), testi.
  - Le note del 18b: `NotAllowed`, `NoContacts` e `UnknownUser` non sono entrati in `AccountFailure`, che resta del lato utente: le rotte dell'admin stanno in `PluginAdminApi` e il loro `Code` si legge con `pluginErrorCode` (§9.1). "Imposta password" non c'è sulla propria riga (§9.5).
  - La prova a mano (punto 4 di §12) si fa con una build locale, prima del merge.
  - **La release è il passo successivo:** plugin 1.6.0 dal Catalogo, app **0.12.0** non obbligatoria con le note in italiano, poi i promemoria riaccesi (14 giorni) e la prova del punto 5 di §12.
- A lavoro finito l'idea 5 esce da `docs/IDEE.md` e va fra le fatte: "Spec L — recupero e cambio della password (plugin 1.6.0, app 0.12.0)".
