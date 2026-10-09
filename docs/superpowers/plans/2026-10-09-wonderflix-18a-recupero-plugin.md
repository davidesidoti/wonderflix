# WonderFlix — Piano 18a: recupero della password, plugin 1.6.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server dello Spec L nel plugin 1.6.0. Comprende:
- i contatti per il recupero (Discord, email) con la verifica a codice;
- il recupero della password senza accesso;
- le funzioni dell'admin (elenco, codice, scollegamento, stato, prova);
- i promemoria nella cassetta;
- la pagina nella Dashboard e una build di prova sul server.

L'app arriva nei piani 18b e 18c.

**Architecture:** la logica sta nella nuova cartella `Account/` e non conosce Jellyfin: parla con interfacce (`IDiscordSender`, `IMailSender`, `IPasswordReset`, `IAccountSettings`, `IUserDirectory`). Gli adattatori stanno in `Server/`:
- Discord via REST con `HttpClient`;
- email con `System.Net.Mail`;
- password con `IUserManager` (via riflessione) e `ISessionManager`.

I controller stanno in `Api/`. Le classi sono piccole e ognuna fa una cosa:
- `ContactRegistry`: i contatti su disco;
- `CodeBook`: i codici in memoria;
- `AccountSender`: gli invii e l'ultimo errore;
- `ContactLinking`: il collegamento;
- `PasswordRecovery`: il recupero;
- `AccountAdmin`: le funzioni dell'admin;
- `ContactReminders`: i promemoria.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`, `System.Net.Mail`, API REST di Discord v10. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md` (§3, §4, §5, §7, §8, §11, §12, §13, §14, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 15):
1. **`IUserManager.ChangePassword` cambia firma fra le due versioni** (riflessione sui pacchetti NuGet):
   - 10.11.0: `ChangePassword(User, string)`;
   - 10.11.9: `ChangePassword(Guid, string)`.

   Il plugin compilato contro la 10.11.0 andrebbe in `MissingMethodException` sul server. Come per `UserListing`, si cerca a runtime (`Server/PasswordChanging.cs`). `RevokeUserTokens(Guid, string)` e `GetUserById(Guid)` sono uguali nelle due versioni.
2. **`RevokeUserTokens(id, "")` chiude tutte le sessioni:** verificato nel sorgente `v10.11.9` (`SessionManager`). Confronta il token di ogni dispositivo con quello passato e chiude quelli diversi.
3. **Mai 404 dal plugin:** per l'app un 404 vuol dire plugin senza la funzione. Quindi:
   - `MemberNotFound` è 400, non 404;
   - un utente sconosciuto nelle rotte admin è 400 `UnknownUser`;
   - canali e id nelle rotte sono stringhe, senza vincoli di rotta (un vincolo risponderebbe 404).
4. **Un limite globale anche sugli errori del recupero** (`RecoveryFailGlobal`, 100 al giorno dopo la review del Gruppo A, voce 11). Senza, chi inventa nomi a raffica riempirebbe la memoria dei limiti e potrebbe tentare per sempre. È un compromesso accettato: chi lo esaurisce (bastano circa 100 richieste al giorno) tiene chiuso il recupero di tutti, anche il completamento dei codici mandati dall'admin. La via d'uscita resta "Imposta password" dell'admin, che passa da Jellyfin e non dal plugin.
5. **`Recovery/Complete` ha anche `Language`:** serve per l'avviso "password cambiata".
6. **`Admin/Test` accetta `Discord` (nome utente) ed `Email`, tutti e due facoltativi.** Così la prova funziona prima che l'admin abbia collegato i suoi contatti (serve alla prova del Task 14). Esiti possibili: `Ok`, `NotConfigured`, `NoContact`, `Invalid`, `MemberNotFound`, `InvalidTarget`, `DmClosed`, `SendFailed`. La Dashboard ha i due campi; l'app (18c) li lascia vuoti.
7. **L'ultimo errore di un canale sparisce con il primo invio riuscito su quel canale:** descrive com'è il canale adesso.
8. **L'`AccountService` della spec diventa sei classi** (vedi *Architecture*). Il codice d'invio dell'admin sta in `PasswordRecovery.SendForAdminAsync` (stessi codici e messaggi del recupero).
9. **Rilascio:** il plugin 1.6.0 va nel Catalogo insieme all'app 0.12.0, alla fine del 18c (non dopo il 18a). Fino ad allora sul server resta la build di prova del Task 14, con i promemoria spenti (`ContactReminderDays` = 0): l'app 0.11 salta le voci di tipo sconosciuto, ma `LastReminderAt` verrebbe segnato per tutti.
10. **Dettagli:**
    - i codici accettano spazi e trattini ("123 456");
    - un nome Discord valido ha da 2 a 32 caratteri fra lettere, cifre, `_` e `.`, con una `@` iniziale facoltativa;
    - una password nuova va da 6 a 1024 caratteri (`WeakPassword` fuori da lì);
    - un nome utente scritto ha al massimo 256 caratteri;
    - con l'admin, anche un utente disattivato è `NotAllowed`;
    - una chiamata senza utente (chiave API) non può collegare contatti (`Invalid`).
11. **Dalle review dei gruppi** (il codice dei task sotto è già aggiornato dove serve; la spec si allinea nel Task 15):
    - **Gruppo A:**
      - **limiti giornalieri sugli errori del recupero.** Con i soli limiti orari, un attacco lento e continuo avrebbe circa il 7% al mese di indovinare il codice di qualche account. Ci sono quindi `RecoveryFailDay` (20 errori al giorno per nome) e `RecoveryFailGlobal` diventa di 100 errori **al giorno** (era all'ora). `PasswordRecovery` li controlla e li conta, e scrive un avviso nel log quando un nome viene fermato;
      - `RateLimiter` toglie le chiavi vecchie quando ne ha 1024: i nomi scritti nel recupero non passano mai da `Forget`;
      - `ContactRegistry` salva copie e rifiuta un contatto non valido (`ArgumentException`): il file si rifiuta tutto intero se una voce non è valida;
      - in `JellyfinPasswordReset`, se `RevokeUserTokens` non riesce dopo il cambio, l'errore va nel log e il recupero riesce lo stesso (la password è cambiata e il codice è usato);
      - `ContactReminderDays` è limitato a 0–365;
      - `PasswordChanging` usa `BindingFlags.DoNotWrapExceptions`.
    - **Blocco dopo i login sbagliati di Jellyfin:** un utente bloccato risulta disattivato, quindi niente recupero. Sul server `LoginAttemptsBeforeLockout` è NULL per tutti e 23 gli utenti (verificato il 2026-10-09): con NULL Jellyfin non blocca mai (sorgente `v10.11.9`, `UserManager.IncrementInvalidLoginAttemptCount`). Caso accettato: se un giorno il blocco si attiva, l'utente bloccato passa dall'admin.
    - **`ContactReminders`** non toglie contatti quando Jellyfin dà un elenco utenti vuoto.
    - **Gruppo B:**
      - **tempi:** l'app aspetta al massimo 30 s una risposta. `DiscordBotClient` ha un solo limite di 8 s per operazione intera (ricerca, messaggio diretto con i suoi due passi, controllo), non 10 s per richiesta. `AccountSender.SendToAllAsync` e `AccountAdmin.TestAsync` lavorano sui due canali in parallelo. Così i casi peggiori sono circa 16 s per collegare Discord, 15 s per il codice dell'admin e 24 s per la prova;
      - il token del bot va nell'intestazione con `AuthenticationHeaderValue` (validata), e un token con spazi o a capo vale come "non configurato";
      - il controllo di Discord prova anche la ricerca dei membri: senza l'intent o senza accesso dà `Invalid` (spec §11);
      - nel log anche il codice d'errore numerico di Discord; la ricerca legge 100 risultati e salta i bot;
      - `SmtpMailSender` prende ogni errore tranne l'annullamento di chi chiama, scrive nel log la causa prima (`GetBaseException`) e, con la porta 465, ricorda che serve la 587; `SmtpServer` non stampa la password;
      - due prove del vero `SmtpClient` su un server finto locale (silenzioso, senza STARTTLS);
      - nello stato dell'admin un canale spento non mostra il vecchio errore; il recupero scrive un avviso quando nessun canale ha funzionato.
    - **Gruppo C:**
      - **password attuale per cambiare i contatti** (decisione dell'utente, 2026-10-09). Senza, chi ha in mano una sessione altrui (per esempio un profilo salvato su un PC condiviso, Spec K) potrebbe collegare la sua email, togliere i contatti del proprietario e cambiare la password con il recupero, chiudendo fuori il proprietario. Oggi una sessione da sola non basta a cambiare la password: Jellyfin chiede quella attuale. Quindi:
        - collegare, sostituire e scollegare un contatto chiedono la password attuale (vuota per gli account senza password); la conferma con il codice no;
        - la verifica passa da `IPasswordCheck` / `JellyfinPasswordCheck`, che usa `IUserManager.AuthenticateUser` (firma uguale in 10.11.0 e 10.11.9) con `isUserSession` falso; una password sbagliata conta come un login sbagliato;
        - limite `PasswordChecks`, 10 verifiche all'ora per utente; errore `WrongPassword` (403);
        - scollegare diventa `POST Contacts/{canale}/Unlink` con `{Password}` (un corpo in una DELETE non è affidabile);
        - chi ha già dimenticato la password e non ha contatti passa dall'admin;
      - **limiti del collegamento:** il limite al minuto vale per utente e canale e scatta solo quando parte un codice, quindi un nome Discord sbagliato si riscrive subito, e Discord ed email si collegano uno dopo l'altro. Il limite all'ora resta per utente e conta ogni ricerca (frena la scoperta dei membri del server);
      - email più severa: solo ASCII, niente indirizzi IP, etichette del dominio valide;
      - un membro Discord senza id valido o senza nome è `SendFailed`;
      - il limite all'ora del collegamento si guarda prima della password e si spende dopo: una password sbagliata non lo consuma.
    - **Gruppo D:**
      - **scollegare annulla il codice di recupero in sospeso** (dall'utente e dall'admin): scollegare è lo strumento per "questo contatto è compromesso". Un cambio password dall'app o "Imposta password" non lo annullano (servirebbe l'evento di Jellyfin): resta come punto aperto;
      - in `CompleteAsync` controllo dei limiti, verifica del codice e conteggio degli errori stanno sotto un solo lock: richieste insieme non superano i limiti;
      - `Start` guarda tutti i limiti prima di spenderli, e c'è `RecoveryStartDay` (10 richieste di codice al giorno per nome): frena i codici a raffica a una persona e il consumo della quota del servizio email;
      - nel log, quando un nome viene fermato, c'è l'id dell'utente anche se è admin o disattivato (il log è solo sul server);
      - le azioni dell'admin (scollegare, mandare un codice) finiscono nel log con l'id dell'admin;
      - "ha un contatto" vuol dire un contatto su un canale configurato (`HasReachableContact`), nello stato dell'admin e nei promemoria;
      - i promemoria tolgono i contatti degli utenti cancellati anche quando sono spenti, e contano gli N giorni con un'ora di tolleranza;
      - nella Dashboard "Send a test" non parte due volte.
    - **SMTP:** meglio credenziali che possono solo spedire (Brevo, Resend) di una password per app di Gmail.

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-18a`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(plugin): …"`.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.6.0`.
- **Test:**
  - un solo gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj del plugin ha `TreatWarningsAsErrors`: un warning è un errore), poi `dotnet build-server shutdown`;
  - la base di partenza è di 401 test verdi.
- **Formattazione e fine riga:**
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Stile del plugin:**
  - commenti in italiano, codice in inglese;
  - durate, misure e limiti come costanti nominate e commentate;
  - `TimeProvider`, mai `DateTimeOffset.UtcNow`;
  - DTO `record` con `[property: JsonPropertyName("…")]`, oppure classi con `[JsonPropertyName]` per i corpi delle richieste;
  - id in formato `"N"`;
  - nel registro mai codici, password, token o email complete.
- **Se il codice del piano ha un errore** (compilazione, nullability, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-09 sul codice di `main` (`217bf98`), sui pacchetti NuGet di Jellyfin 10.11.0 e 10.11.9 (riflessione) e sul sorgente di Jellyfin `v10.11.9`, in sola lettura.

**Jellyfin**
- `IUserManager` (riflessione):
  - 10.11.0: `ChangePassword(User, string)`, proprietà `Users`, `ResetPassword(User)`;
  - 10.11.9: `ChangePassword(Guid, string)`, `GetUsers()`, `ResetPassword(Guid)`;
  - uguali nelle due: `GetUserById(Guid)` e `GetUserByName(string)`.
- `ISessionManager.RevokeUserTokens(Guid userId, string currentAccessToken)` è uguale nelle due versioni. Con `""` chiude ogni dispositivo dell'utente.
- `POST /Users/Password` (lo usa l'app, non il plugin) chiude le altre sessioni dopo il cambio.
- Admin e disattivati: `user.HasPermission(PermissionKind.IsAdministrator)`, `user.HasPermission(PermissionKind.IsDisabled)` (`Jellyfin.Data`, `Jellyfin.Database.Implementations.Enums`). Nei test: `user.SetPermission(PermissionKind.IsAdministrator, true)`.
- `[AllowAnonymous]` su un controller del plugin funziona già in produzione: è il webhook di Seerr (`Api/RequestsWebhookController.cs`).
- `Policies.RequiresElevation` è in `MediaBrowser.Common.Api`.
- Il proxy di Ultra.cc: Jellyfin vede tutte le richieste da `172.17.0.1`, quindi i limiti per IP non servono.

**Discord** (documentazione ufficiale)
- Base `https://discord.com/api/v10/`, intestazioni `Authorization: Bot <token>` e `User-Agent: DiscordBot (<url>, <versione>)` (senza un User-Agent valido la richiesta può essere bloccata).
- `GET /guilds/{id}/members/search?query=&limit=` (`limit` da 1 a 1000, di default 1) cerca **per prefisso** su username e nickname. La documentazione non chiede l'intent "Server Members" (lo chiede solo per l'elenco dei membri); si attiva comunque, per sicurezza. Risposta: un array di membri `{ "user": { "id", "username", … }, "nick", … }`.
- `POST /users/@me/channels` con `{"recipient_id": "<id>"}` restituisce il canale DM (`{"id": …}`). Poi `POST /channels/{id}/messages` con `{"content": "…"}`.
- Un errore ha il corpo `{"code": n, "message": "…"}`. Con i messaggi diretti chiusi la risposta è 403 con `code` 50007. Un 429 ha `retry_after`.
- `GET /users/@me` controlla il token; `GET /guilds/{id}` dice se il bot è nel server.

**.NET**
- `System.Net.Mail.SmtpClient` compila senza warning in net9.0 (provato con `TreatWarningsAsErrors`). `EnableSsl = true` vuol dire STARTTLS. Il TLS implicito sulla porta 465 non c'è.
- `SendMailAsync(MailMessage, CancellationToken)` esiste. `SmtpClient.Timeout` vale solo per l'invio sincrono: il limite di tempo lo fa un `CancellationTokenSource`.
- `JsonContent.Create(body, body.GetType())` usa i default "Web" (niente rientri, caratteri non ASCII scritti come `\uXXXX`). I nomi dei tipi anonimi `recipient_id` e `content` restano come sono.

**Plugin** (`main`)
- `UserRef(Guid Id, string Name, bool Enabled, bool CanJoinParties)` sta in `Hub/IUserDirectory.cs`. Lo costruiscono `JellyfinUserDirectory.ToRef`, `FakeServer.AddUser` e alcuni test.
- `RateLimiter` (`Hub/RateLimiter.cs`) ha i limiti per tipo nel dizionario `Limits`, con `TryAcquire(key, type)` e `Forget(sessionId)`. `LimitTypes` sta in `Hub/LimitTypes.cs`.
- `InboxService` modifica la cassetta sotto `_lock` con `Book` e `Persist()`, e avvisa con `NotifyAsync`. `ChangeAsync(userId, Func<InboxBook,bool>)` avvisa solo se qualcosa è cambiato.
- `InboxEntry` (`Protocol/InboxDtos.cs`) ha un campo per ogni tipo, con `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]`. I tipi stanno in `InboxEntryTypes`.
- `InboxStore` e `FriendStore.FolderName` (`"WonderFlixWatchParty"`): il file va accanto a `inbox.json`, e se è illeggibile diventa `.bad`.
- `PluginSeerrSettings` legge `Plugin.Instance?.Configuration` a ogni uso.
- `SeerrClient` è il modello per il client HTTP: nome registrato, `Timeout` interno, nel registro solo il percorso senza query.
- I controller prendono l'utente da `IAuthorizationContext.GetAuthorizationInfo(HttpContext)` (`.UserId`).
- **Test:**
  - `FakeServer` implementa `IUserDirectory`, `ISessionDirectory` e il resto, con `AddUser(name, enabled, canJoinParties)` e `AddSession(id, user)`;
  - `TestInbox.Create(server, folder, time)`;
  - `TempFolder` ha `FriendsFile` e `InboxFile`;
  - `RecordingLogger<T>`, `InterfaceStub<T>` (`Handlers["Nome"]`, `Calls`), `FakeAuthorizationContext(AuthorizationInfo)`;
  - utenti di Jellyfin nei test: `new User("mario", "provider", "reset")`;
  - `ServiceRegistrationTests` registra gli stub di `ISessionManager` e `IUserManager` e conta 2 servizi in background;
  - `InfoControllerTests` controlla la versione `"1.5.0"` e le funzioni;
  - `PluginPagesTests` controlla i testi della pagina.
- **App 0.11:** `inboxEntryFromJson` restituisce `null` per un `Type` sconosciuto e la voce si salta, quindi i promemoria non rompono la cassetta delle app vecchie.

## File

| File | Responsabilità |
|---|---|
| `Hub/IUserDirectory.cs` (modifica) | `UserRef.IsAdmin` |
| `Hub/LimitTypes.cs`, `Hub/RateLimiter.cs` (modifica) | limiti del recupero e del collegamento, `IsLimited` |
| `Account/AccountChannel.cs` | `AccountChannel`, `AccountChannels` (nomi, lettura) |
| `Account/DiscordIds.cs` | controllo degli id Discord |
| `Account/CodeBook.cs` | codici a 6 cifre in memoria |
| `Account/ContactFile.cs` | `DiscordContact`, `EmailContact`, `UserContacts`, `ContactFile` |
| `Account/ContactStore.cs` | `contacts.json` su disco |
| `Account/ContactRegistry.cs` | contatti in memoria, sicuri tra thread, salvati a ogni cambio |
| `Account/IAccountSettings.cs` | impostazioni e canali configurati |
| `Account/AccountMessages.cs` | testi dei messaggi (it, en) |
| `Account/IDiscordSender.cs`, `Account/IMailSender.cs`, `Account/IPasswordReset.cs` | interfacce verso l'esterno |
| `Account/AccountSender.cs` | invii per canale, ultimo errore |
| `Account/AccountError.cs` | errori ed esiti |
| `Account/ContactLinking.cs` | collegamento e verifica dei contatti |
| `Account/PasswordRecovery.cs` | recupero e codice mandato dall'admin |
| `Account/AccountAdmin.cs` | elenco, scollegamento, stato, prova |
| `Account/ContactReminders.cs` | promemoria nella cassetta |
| `ContactReminderHostedService.cs` | timer dei promemoria |
| `Server/PasswordChanging.cs`, `Server/JellyfinPasswordReset.cs` | cambio password su Jellyfin |
| `Server/PluginAccountSettings.cs` | impostazioni dalla configurazione del plugin |
| `Server/DiscordBotClient.cs` | API REST di Discord |
| `Server/SmtpMailSender.cs` | email via SMTP |
| `Protocol/AccountDtos.cs` | corpi e risposte degli endpoint |
| `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs` (modifica) | voce `ContactReminder` |
| `Api/AccountErrors.cs`, `Api/AccountController.cs`, `Api/RecoveryController.cs`, `Api/AccountAdminController.cs` | endpoint |
| `Configuration/PluginConfiguration.cs`, `Configuration/configPage.html` (modifica) | impostazioni e pagina della Dashboard |
| `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `meta.template.json`, `README.md` (modifica) | montaggio, funzione `account`, versione 1.6.0 |

Tutti i percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test), se non è detto altro.

---

## Gruppo A — fondamenta

### Task 1: admin, cambio password e chiusura delle sessioni

**Files:**
- Modify: `Hub/IUserDirectory.cs`, `Server/JellyfinUserDirectory.cs`
- Create: `Account/IPasswordReset.cs`, `Server/PasswordChanging.cs`, `Server/JellyfinPasswordReset.cs`
- Modify (test): `FakeServer.cs`, `ServerAdapterTests.cs`
- Create (test): `PasswordChangingTests.cs`, `PasswordResetTests.cs`

- [ ] **Step 1: i test**

In `ServerAdapterTests.cs`, dopo `UsersWithoutSyncPlayAccessCannotJoinParties`, aggiungi:

```csharp
    [Fact]
    public void AdministratorsAreMarked()
    {
        var peach = new User("Peach", "provider", "reset");
        peach.SetPermission(PermissionKind.IsAdministrator, true);
        var toad = new User("Toad", "provider", "reset");
        var (manager, stub) = InterfaceStub<IUserManager>.Create();
        stub.Handlers["GetUsers"] = _ => new[] { peach, toad };
        stub.Handlers["GetUserById"] = args => (Guid)args[0]! == peach.Id ? peach : null;
        var directory = new JellyfinUserDirectory(manager);

        Assert.Equal(
            new[] { new UserRef(peach.Id, "Peach", true, true, IsAdmin: true), new UserRef(toad.Id, "Toad", true, true) },
            directory.GetUsers());
        Assert.True(directory.GetUser(peach.Id)!.IsAdmin);
    }
```

Crea `PasswordChangingTests.cs`:

```csharp
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PasswordChangingTests
{
    // La forma di IUserManager in Jellyfin 10.11.0: l'utente.
    public interface IOldPasswords
    {
        Task ChangePassword(User user, string newPassword);
    }

    // La forma di IUserManager in Jellyfin 10.11.9: l'id.
    public interface INewPasswords
    {
        Task ChangePassword(Guid userId, string newPassword);
    }

    private sealed class OldPasswords : IOldPasswords
    {
        public List<(User User, string Password)> Calls { get; } = [];

        public Task ChangePassword(User user, string newPassword)
        {
            Calls.Add((user, newPassword));
            return Task.CompletedTask;
        }
    }

    private sealed class NewPasswords : INewPasswords
    {
        public List<(Guid UserId, string Password)> Calls { get; } = [];

        public Task ChangePassword(Guid userId, string newPassword)
        {
            Calls.Add((userId, newPassword));
            return Task.CompletedTask;
        }
    }

    private sealed class FailingPasswords : INewPasswords
    {
        public Task ChangePassword(Guid userId, string newPassword) => throw new InvalidOperationException("database");
    }

    [Fact]
    public async Task ChangesByUserOnJellyfin10110()
    {
        var mario = new User("Mario", "provider", "reset");
        var manager = new OldPasswords();

        var change = PasswordChanging.For(typeof(IOldPasswords));

        Assert.NotNull(change);
        await change!(manager, mario, "nuova-password");
        Assert.Equal(new[] { (mario, "nuova-password") }, manager.Calls);
    }

    [Fact]
    public async Task ChangesByIdOnLaterJellyfin()
    {
        var mario = new User("Mario", "provider", "reset");
        var manager = new NewPasswords();

        var change = PasswordChanging.For(typeof(INewPasswords));

        Assert.NotNull(change);
        await change!(manager, mario, "nuova-password");
        Assert.Equal(new[] { (mario.Id, "nuova-password") }, manager.Calls);
    }

    [Fact]
    public async Task AnErrorOfJellyfinComesOutAsItIs()
    {
        var change = PasswordChanging.For(typeof(INewPasswords))!;

        var error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => change(new FailingPasswords(), new User("Mario", "provider", "reset"), "nuova-password"));

        Assert.Equal("database", error.Message);
    }

    [Fact]
    public void ReturnsNullWhenTheTypeHasNoChangePassword() =>
        Assert.Null(PasswordChanging.For(typeof(IDisposable)));

    [Fact]
    public void TheJellyfinOfTheTestsHasOne() =>
        Assert.NotNull(PasswordChanging.For(typeof(IUserManager)));
}
```

Crea `PasswordResetTests.cs`:

```csharp
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class PasswordResetTests
{
    [Fact]
    public async Task ThePasswordChangesThenEverySessionCloses()
    {
        var mario = new User("Mario", "provider", "reset");
        var (users, userStub) = InterfaceStub<IUserManager>.Create();
        userStub.Handlers["GetUserById"] = args => (Guid)args[0]! == mario.Id ? mario : null;
        var (sessions, sessionStub) = InterfaceStub<ISessionManager>.Create();
        var reset = new JellyfinPasswordReset(users, sessions);

        await reset.ResetAsync(mario.Id, "nuova-password");

        var change = Assert.Single(userStub.Calls, c => c.Name == "ChangePassword");
        Assert.Equal(new object?[] { mario.Id, "nuova-password" }, change.Args);
        var revoke = Assert.Single(sessionStub.Calls, c => c.Name == "RevokeUserTokens");
        Assert.Equal(new object?[] { mario.Id, string.Empty }, revoke.Args);
    }

    [Fact]
    public async Task AnUnknownUserIsAnError()
    {
        var (users, _) = InterfaceStub<IUserManager>.Create();
        var (sessions, sessionStub) = InterfaceStub<ISessionManager>.Create();
        var reset = new JellyfinPasswordReset(users, sessions);

        await Assert.ThrowsAsync<ArgumentException>(() => reset.ResetAsync(Guid.NewGuid(), "nuova-password"));
        await Assert.ThrowsAsync<ArgumentException>(() => reset.ResetAsync(Guid.Empty, "nuova-password"));
        Assert.Empty(sessionStub.Calls);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~PasswordChangingTests|FullyQualifiedName~PasswordResetTests|FullyQualifiedName~ServerAdapterTests"`
Expected: errore di compilazione (`PasswordChanging`, `JellyfinPasswordReset`, `IsAdmin` non esistono).

- [ ] **Step 3: il codice**

In `Hub/IUserDirectory.cs` il record diventa:

```csharp
/// <summary>
/// Un utente di Jellyfin, come serve agli amici. <paramref name="CanJoinParties"/>:
/// può usare i watch party (accesso SyncPlay diverso da nessuno).
/// <paramref name="IsAdmin"/>: amministratore di Jellyfin; per lui non vale
/// il recupero della password da soli (spec L §8).
/// </summary>
public sealed record UserRef(Guid Id, string Name, bool Enabled, bool CanJoinParties, bool IsAdmin = false);
```

In `Server/JellyfinUserDirectory.cs`, `ToRef` diventa:

```csharp
    private static UserRef ToRef(User user) => new(
        user.Id,
        user.Username,
        !user.HasPermission(PermissionKind.IsDisabled),
        user.SyncPlayAccess != SyncPlayUserAccessType.None,
        user.HasPermission(PermissionKind.IsAdministrator));
```

In `FakeServer.cs` (test), `AddUser(string name, …)` diventa:

```csharp
    public UserRef AddUser(string name, bool enabled = true, bool canJoinParties = true, bool isAdmin = false)
    {
        var user = new UserRef(Guid.NewGuid(), name, enabled, canJoinParties, isAdmin);
        Users[user.Id] = user;
        return user;
    }
```

Crea `Account/IPasswordReset.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Cambiare la password di un utente e chiuderne tutte le sessioni (spec L §7.4).</summary>
public interface IPasswordReset
{
    /// <summary>Lancia se l'utente non c'è o se Jellyfin non riesce.</summary>
    Task ResetAsync(Guid userId, string newPassword);
}
```

Crea `Server/PasswordChanging.cs`:

```csharp
using System.Reflection;
using System.Runtime.ExceptionServices;
using Jellyfin.Database.Implementations.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Come chiedere a IUserManager di cambiare una password (spec L §14). In
/// Jellyfin 10.11.0 è ChangePassword(User, string); nella 10.11.9 del server
/// è diventata ChangePassword(Guid, string). Il plugin è compilato contro
/// 10.11.0, il minimo: si cerca a runtime quella che il server ha davvero,
/// come in UserListing.
/// </summary>
internal static class PasswordChanging
{
    /// <summary>La funzione che cambia la password con un manager di managerType; null se non ha nessuna delle due.</summary>
    public static Func<object, User, string, Task>? For(Type managerType)
    {
        var byId = managerType.GetMethod("ChangePassword", [typeof(Guid), typeof(string)]);
        if (byId is not null && byId.ReturnType == typeof(Task))
        {
            return (manager, user, password) => Call(byId, manager, [user.Id, password]);
        }

        var byUser = managerType.GetMethod("ChangePassword", [typeof(User), typeof(string)]);
        if (byUser is not null && byUser.ReturnType == typeof(Task))
        {
            return (manager, user, password) => Call(byUser, manager, [user, password]);
        }

        return null;
    }

    // L'errore di Jellyfin esce com'è, non avvolto in TargetInvocationException.
    private static Task Call(MethodInfo method, object manager, object?[] args)
    {
        try
        {
            return (Task)method.Invoke(manager, args)!;
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
            throw;
        }
    }
}
```

Crea `Server/JellyfinPasswordReset.cs`:

```csharp
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// La password nuova con IUserManager, poi tutte le sessioni chiuse:
/// RevokeUserTokens con un token vuoto non ne risparmia nessuna (spec L §3).
/// </summary>
public sealed class JellyfinPasswordReset(IUserManager userManager, ISessionManager sessionManager) : IPasswordReset
{
    // Quale ChangePassword usare si decide una volta sola (vedi PasswordChanging).
    private static readonly Func<object, User, string, Task>? Change = PasswordChanging.For(typeof(IUserManager));

    public async Task ResetAsync(Guid userId, string newPassword)
    {
        // Con un id vuoto UserManager lancia un'altra eccezione: l'utente non c'è e basta.
        var user = (userId == Guid.Empty ? null : userManager.GetUserById(userId))
            ?? throw new ArgumentException("utente sconosciuto", nameof(userId));
        var change = Change ?? throw new MissingMemberException(typeof(IUserManager).FullName, "ChangePassword");
        await change(userManager, user, newPassword).ConfigureAwait(false);
        await sessionManager.RevokeUserTokens(userId, string.Empty).ConfigureAwait(false);
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro dello Step 2. Expected: PASS. Poi la suite intera: tutta verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): admins in the user directory and password reset on Jellyfin"
```

### Task 2: i limiti del recupero e del collegamento

**Files:**
- Modify: `Hub/LimitTypes.cs`, `Hub/RateLimiter.cs`
- Modify (test): `RateLimiterTests.cs`

- [ ] **Step 1: i test**

In `RateLimiterTests.cs` aggiungi:

```csharp
    [Theory]
    [InlineData(LimitTypes.RecoveryStartMinute, 1, 1)]
    [InlineData(LimitTypes.RecoveryStartHour, 5, 60)]
    [InlineData(LimitTypes.RecoveryStartGlobal, 30, 60)]
    [InlineData(LimitTypes.RecoveryFail, 10, 60)]
    [InlineData(LimitTypes.RecoveryFailGlobal, 100, 60)]
    [InlineData(LimitTypes.LinkStartMinute, 1, 1)]
    [InlineData(LimitTypes.LinkStartHour, 5, 60)]
    public void AccountLimits(string type, int count, int minutes)
    {
        var limiter = new RateLimiter(_time);
        Allow(limiter, type, count);
        Assert.False(limiter.TryAcquire("s1", type));
        Assert.True(limiter.TryAcquire("s2", type), "ogni chiave ha i suoi limiti");
        _time.Advance(TimeSpan.FromMinutes(minutes) - TimeSpan.FromSeconds(1));
        Assert.False(limiter.TryAcquire("s1", type));
        _time.Advance(TimeSpan.FromSeconds(1));
        Assert.True(limiter.TryAcquire("s1", type));
    }

    [Fact]
    public void IsLimitedLooksWithoutCounting()
    {
        var limiter = new RateLimiter(_time);
        for (var i = 0; i < 9; i++)
        {
            Assert.True(limiter.TryAcquire("mario", LimitTypes.RecoveryFail));
        }

        Assert.False(limiter.IsLimited("mario", LimitTypes.RecoveryFail));
        Assert.False(limiter.IsLimited("mario", LimitTypes.RecoveryFail), "guardare non conta");
        Assert.True(limiter.TryAcquire("mario", LimitTypes.RecoveryFail));
        Assert.True(limiter.IsLimited("mario", LimitTypes.RecoveryFail));
        Assert.False(limiter.IsLimited("luigi", LimitTypes.RecoveryFail));
        _time.Advance(TimeSpan.FromHours(1));
        Assert.False(limiter.IsLimited("mario", LimitTypes.RecoveryFail));
        Assert.False(limiter.IsLimited("mario", "TipoSconosciuto"));
    }
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~RateLimiterTests"`
Expected: errore di compilazione (`LimitTypes.RecoveryStartMinute`, `IsLimited`).

- [ ] **Step 3: il codice**

In `Hub/LimitTypes.cs` il commento della classe diventa:

```csharp
/// <summary>
/// Limiti che non sono tipi di evento (spec F §6.9, spec L §7.5). La chiave
/// passata a <see cref="RateLimiter.TryAcquire"/> è l'id dell'utente
/// (formato "N"); per il recupero è il nome scritto (in minuscolo), e "*"
/// per i limiti di tutti.
/// </summary>
```

e in fondo alla classe aggiungi:

```csharp
    /// <summary>Richieste di recupero per nome scritto: una al minuto (spec L §7.5).</summary>
    public const string RecoveryStartMinute = "RecoveryStartMinute";

    /// <summary>Richieste di recupero per nome scritto: cinque all'ora.</summary>
    public const string RecoveryStartHour = "RecoveryStartHour";

    /// <summary>Richieste di recupero di tutti insieme (chiave "*").</summary>
    public const string RecoveryStartGlobal = "RecoveryStartGlobal";

    /// <summary>Codici di recupero sbagliati per nome scritto.</summary>
    public const string RecoveryFail = "RecoveryFail";

    /// <summary>
    /// Codici di recupero sbagliati di tutti insieme (chiave "*"): limita
    /// anche la memoria dei limiti per nomi inventati.
    /// </summary>
    public const string RecoveryFailGlobal = "RecoveryFailGlobal";

    /// <summary>Codici per collegare un contatto, per utente: uno al minuto.</summary>
    public const string LinkStartMinute = "LinkStartMinute";

    /// <summary>Codici per collegare un contatto, per utente: cinque all'ora.</summary>
    public const string LinkStartHour = "LinkStartHour";
```

In `Hub/RateLimiter.cs`, nel dizionario `Limits`, dopo `[LimitTypes.Invites] = …`, aggiungi:

```csharp
            [LimitTypes.RecoveryStartMinute] = (1, TimeSpan.FromMinutes(1)),
            [LimitTypes.RecoveryStartHour] = (5, TimeSpan.FromHours(1)),
            [LimitTypes.RecoveryStartGlobal] = (30, TimeSpan.FromHours(1)),
            [LimitTypes.RecoveryFail] = (10, TimeSpan.FromHours(1)),
            [LimitTypes.RecoveryFailGlobal] = (100, TimeSpan.FromHours(1)),
            [LimitTypes.LinkStartMinute] = (1, TimeSpan.FromMinutes(1)),
            [LimitTypes.LinkStartHour] = (5, TimeSpan.FromHours(1)),
```

e dopo `TryAcquire` aggiungi:

```csharp
    /// <summary>true se la chiave ha già finito quelli di questo tipo adesso; non conta niente.</summary>
    public bool IsLimited(string key, string type)
    {
        if (!Limits.TryGetValue(type, out var limit))
        {
            return false;
        }

        var now = time.GetUtcNow();
        lock (_lock)
        {
            return _sent.TryGetValue((key, type), out var times)
                && times.Count(t => now - t < limit.Window) >= limit.Count;
        }
    }
```

Il commento della classe `RateLimiter` diventa: "Limiti di frequenza per chiave e tipo, a finestra scorrevole (spec E §6.6, spec F §6.9, spec L §7.5). La chiave è la sessione per gli eventi del canale, l'utente per gli amici e i contatti, il nome scritto per il recupero. Sicuro tra thread."

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): rate limits for password recovery and contact links"
```

### Task 3: canali e codici

**Files:**
- Create: `Account/AccountChannel.cs`, `Account/DiscordIds.cs`, `Account/CodeBook.cs`
- Create (test): `AccountChannelTests.cs`, `CodeBookTests.cs`

- [ ] **Step 1: i test**

Crea `AccountChannelTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AccountChannelTests
{
    [Theory]
    [InlineData("Discord", AccountChannel.Discord)]
    [InlineData("discord", AccountChannel.Discord)]
    [InlineData("EMAIL", AccountChannel.Email)]
    public void ChannelsAreReadWithoutCase(string raw, AccountChannel expected)
    {
        Assert.True(AccountChannels.TryParse(raw, out var channel));
        Assert.Equal(expected, channel);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("0")]
    [InlineData("1")]
    [InlineData("Telegram")]
    public void NumbersAndOtherNamesAreNotChannels(string? raw) =>
        Assert.False(AccountChannels.TryParse(raw, out _));

    [Fact]
    public void NamesAndOrder()
    {
        Assert.Equal("Discord", AccountChannel.Discord.Name());
        Assert.Equal("Email", AccountChannel.Email.Name());
        Assert.Equal(new[] { AccountChannel.Discord, AccountChannel.Email }, AccountChannels.All);
    }

    [Theory]
    [InlineData("12345678901234567", true)]
    [InlineData("12345678901234567890", true)]
    [InlineData("1234567890123456", false)]
    [InlineData("123456789012345678901", false)]
    [InlineData("12345678901234567a", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void DiscordIdsAreSeventeenToTwentyDigits(string? value, bool valid) =>
        Assert.Equal(valid, DiscordIds.IsSnowflake(value));
}
```

Crea `CodeBookTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class CodeBookTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 9, 12, 0, 0, TimeSpan.Zero));
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();

    [Fact]
    public void SixDigitCodesThatWorkOnce()
    {
        var book = new CodeBook(_time);

        var (code, expiresAt) = book.Issue(_mario, CodePurpose.Recovery);

        Assert.Matches("^[0-9]{6}$", code);
        Assert.Equal(_time.GetUtcNow() + CodeBook.Lifetime, expiresAt);
        var check = book.Check(_mario, CodePurpose.Recovery, code);
        Assert.True(check.Ok);
        Assert.Null(check.Pending);
        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void ThePendingContactComesBack()
    {
        var book = new CodeBook(_time);
        var pending = new PendingContact("222222222222222222", "mario");

        var (code, _) = book.Issue(_mario, CodePurpose.VerifyDiscord, pending);

        Assert.Equal(pending, book.Check(_mario, CodePurpose.VerifyDiscord, code).Pending);
    }

    [Fact]
    public void ACodeLastsTenMinutes()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        _time.Advance(CodeBook.Lifetime - TimeSpan.FromSeconds(1));
        var (other, _) = book.Issue(_luigi, CodePurpose.Recovery);
        Assert.True(book.Check(_luigi, CodePurpose.Recovery, other).Ok);

        _time.Advance(TimeSpan.FromSeconds(1));

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void FourWrongAttemptsLeaveTheCodeTheFifthDropsIt()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        var wrong = code == "000000" ? "111111" : "000000";
        for (var i = 0; i < CodeBook.MaxAttempts - 1; i++)
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, wrong).Ok);
        }

        Assert.True(book.Check(_mario, CodePurpose.Recovery, code).Ok);

        (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        wrong = code == "000000" ? "111111" : "000000";
        for (var i = 0; i < CodeBook.MaxAttempts; i++)
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, wrong).Ok);
        }

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void ANewCodeReplacesTheOldOne()
    {
        var book = new CodeBook(_time);
        var (first, _) = book.Issue(_mario, CodePurpose.Recovery);
        var (second, _) = book.Issue(_mario, CodePurpose.Recovery);

        // Uguali per caso una volta su un milione: allora il primo vale come il secondo.
        if (first != second)
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, first).Ok);
        }

        Assert.True(book.Check(_mario, CodePurpose.Recovery, second).Ok);
    }

    [Fact]
    public void UsersAndPurposesAreSeparate()
    {
        var book = new CodeBook(_time);
        var (discord, _) = book.Issue(_mario, CodePurpose.VerifyDiscord);
        var (email, _) = book.Issue(_mario, CodePurpose.VerifyEmail);
        var (luigi, _) = book.Issue(_luigi, CodePurpose.Recovery);

        Assert.False(book.Check(_mario, CodePurpose.Recovery, discord).Ok);
        Assert.False(book.Check(_luigi, CodePurpose.VerifyDiscord, discord).Ok);
        Assert.True(book.Check(_mario, CodePurpose.VerifyDiscord, discord).Ok);
        Assert.True(book.Check(_mario, CodePurpose.VerifyEmail, email).Ok);
        Assert.True(book.Check(_luigi, CodePurpose.Recovery, luigi).Ok);
    }

    [Fact]
    public void SpacesAndDashesAreFine()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        Assert.True(book.Check(_mario, CodePurpose.Recovery, $" {code[..3]} {code[3..]} ").Ok);

        (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        Assert.True(book.Check(_mario, CodePurpose.Recovery, $"{code[..3]}-{code[3..]}").Ok);
    }

    [Fact]
    public void MalformedCodesAreWrongAttempts()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        foreach (var bad in new string?[] { null, string.Empty, "abc", "12345", "1234567" })
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, bad).Ok);
        }

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void DiscardRemovesTheCode()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);

        book.Discard(_mario, CodePurpose.Recovery);

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
        Assert.Equal(0, book.Count);
    }

    [Fact]
    public void ExpiredCodesGoAwayWithTheNextIssue()
    {
        var book = new CodeBook(_time);
        book.Issue(_mario, CodePurpose.Recovery);
        _time.Advance(CodeBook.Lifetime);

        book.Issue(_luigi, CodePurpose.Recovery);

        Assert.Equal(1, book.Count);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~AccountChannelTests|FullyQualifiedName~CodeBookTests"`
Expected: errore di compilazione (lo spazio dei nomi `Account` non esiste).

- [ ] **Step 3: il codice**

Crea `Account/AccountChannel.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>I canali dei codici (spec L §4).</summary>
public enum AccountChannel
{
    Discord,
    Email,
}

/// <summary>Nomi e lettura dei canali.</summary>
public static class AccountChannels
{
    /// <summary>Tutti, nell'ordine in cui si mandano i codici.</summary>
    public static readonly IReadOnlyList<AccountChannel> All = [AccountChannel.Discord, AccountChannel.Email];

    /// <summary>Il nome nelle rotte e nelle risposte: "Discord" o "Email".</summary>
    public static string Name(this AccountChannel channel) =>
        channel == AccountChannel.Discord ? "Discord" : "Email";

    /// <summary>Dal nome nella rotta, senza badare alle maiuscole. Niente numeri: "0" non è un canale.</summary>
    public static bool TryParse(string? raw, out AccountChannel channel)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(raw, candidate.Name(), StringComparison.OrdinalIgnoreCase))
            {
                channel = candidate;
                return true;
            }
        }

        channel = default;
        return false;
    }
}
```

Crea `Account/DiscordIds.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Gli id di Discord (snowflake): da 17 a 20 cifre. Vanno nei percorsi dell'API.</summary>
public static class DiscordIds
{
    public static bool IsSnowflake(string? value) =>
        value is { Length: >= 17 and <= 20 } && value.All(char.IsAsciiDigit);
}
```

Crea `Account/CodeBook.cs`:

```csharp
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>A cosa serve un codice (spec L §7.2).</summary>
public enum CodePurpose
{
    VerifyDiscord,
    VerifyEmail,
    Recovery,
}

/// <summary>Il contatto in attesa di verifica: l'id Discord con il nome utente, oppure l'email (Name null).</summary>
public sealed record PendingContact(string Value, string? Name);

/// <summary>Esito di un controllo: con Ok, il contatto in attesa (null per il recupero).</summary>
public sealed record CodeCheck(bool Ok, PendingContact? Pending)
{
    public static readonly CodeCheck Wrong = new(false, null);
}

/// <summary>
/// I codici a 6 cifre (spec L §7.2), solo in memoria: un riavvio li perde.
/// Uno per utente e scopo; si salva l'hash con un sale, mai il codice.
/// Sicuro tra thread.
/// </summary>
public sealed class CodeBook(TimeProvider time)
{
    /// <summary>Quanto vale un codice.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    /// <summary>Tentativi sbagliati dopo i quali il codice sparisce.</summary>
    public const int MaxAttempts = 5;

    /// <summary>Cifre di un codice.</summary>
    public const int Digits = 6;

    // Codici possibili: da 000000 a 999999.
    private const int CodeSpace = 1_000_000;

    private const int SaltBytes = 16;

    private readonly Lock _lock = new();
    private readonly Dictionary<(Guid UserId, CodePurpose Purpose), Entry> _entries = [];

    /// <summary>Voci in memoria (per i test).</summary>
    internal int Count
    {
        get
        {
            lock (_lock)
            {
                return _entries.Count;
            }
        }
    }

    /// <summary>Un codice nuovo, che sostituisce quello di prima con lo stesso scopo.</summary>
    public (string Code, DateTimeOffset ExpiresAt) Issue(Guid userId, CodePurpose purpose, PendingContact? pending = null)
    {
        var code = RandomNumberGenerator.GetInt32(0, CodeSpace).ToString("D6", CultureInfo.InvariantCulture);
        var salt = RandomNumberGenerator.GetBytes(SaltBytes);
        var now = time.GetUtcNow();
        var expiresAt = now + Lifetime;
        lock (_lock)
        {
            // Gli scaduti vanno via qui: senza, resterebbero finché lo stesso utente non ne chiede un altro.
            foreach (var key in _entries.Where(e => e.Value.ExpiresAt <= now).Select(e => e.Key).ToList())
            {
                _entries.Remove(key);
            }

            _entries[(userId, purpose)] = new Entry(Hash(salt, code), salt, expiresAt, pending);
        }

        return (code, expiresAt);
    }

    /// <summary>
    /// Controlla un codice. Giusto: la voce sparisce (vale una volta) e torna
    /// il contatto in attesa. Sbagliato: conta un tentativo, e al
    /// <see cref="MaxAttempts"/>-esimo la voce sparisce. Assente o scaduto: Wrong.
    /// </summary>
    public CodeCheck Check(Guid userId, CodePurpose purpose, string? code)
    {
        var given = Normalize(code);
        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (!_entries.TryGetValue((userId, purpose), out var entry))
            {
                return CodeCheck.Wrong;
            }

            if (entry.ExpiresAt <= now)
            {
                _entries.Remove((userId, purpose));
                return CodeCheck.Wrong;
            }

            if (given is not null && CryptographicOperations.FixedTimeEquals(entry.Hash, Hash(entry.Salt, given)))
            {
                _entries.Remove((userId, purpose));
                return new CodeCheck(true, entry.Pending);
            }

            entry.Attempts++;
            if (entry.Attempts >= MaxAttempts)
            {
                _entries.Remove((userId, purpose));
            }

            return CodeCheck.Wrong;
        }
    }

    /// <summary>Toglie il codice (per esempio se l'invio non è riuscito).</summary>
    public void Discard(Guid userId, CodePurpose purpose)
    {
        lock (_lock)
        {
            _entries.Remove((userId, purpose));
        }
    }

    // Spazi e trattini via ("123 456", "123-456"); poi devono restare 6 cifre.
    private static string? Normalize(string? code)
    {
        if (code is null)
        {
            return null;
        }

        var digits = new string(code.Where(c => !char.IsWhiteSpace(c) && c != '-').ToArray());
        return digits.Length == Digits && digits.All(char.IsAsciiDigit) ? digits : null;
    }

    private static byte[] Hash(byte[] salt, string code)
    {
        var text = Encoding.UTF8.GetBytes(code);
        var data = new byte[salt.Length + text.Length];
        salt.CopyTo(data, 0);
        text.CopyTo(data, salt.Length);
        return SHA256.HashData(data);
    }

    private sealed class Entry(byte[] hash, byte[] salt, DateTimeOffset expiresAt, PendingContact? pending)
    {
        public byte[] Hash { get; } = hash;

        public byte[] Salt { get; } = salt;

        public DateTimeOffset ExpiresAt { get; } = expiresAt;

        public PendingContact? Pending { get; } = pending;

        public int Attempts { get; set; }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): account channels and one-time codes"
```

### Task 4: i contatti su disco

**Files:**
- Create: `Account/ContactFile.cs`, `Account/ContactStore.cs`, `Account/ContactRegistry.cs`
- Modify (test): `TempFolder.cs`
- Create (test): `TestAccount.cs`, `ContactStoreTests.cs`, `ContactRegistryTests.cs`

- [ ] **Step 1: i test**

In `TempFolder.cs`, dopo `InboxFile`, aggiungi:

```csharp
    /// <summary>Percorso di contacts.json, accanto a inbox.json.</summary>
    public string ContactsFile => System.IO.Path.Combine(Path, "WonderFlixWatchParty", "contacts.json");
```

Crea `TestAccount.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I contatti dei test: file in una cartella temporanea.</summary>
internal static class TestAccount
{
    public static ContactRegistry Registry(TempFolder folder) =>
        new(new ContactStore(folder.ContactsFile, NullLogger<ContactStore>.Instance), NullLogger<ContactRegistry>.Instance);
}
```

Crea `ContactStoreTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactStoreTests : IDisposable
{
    private static readonly Guid Mario = Guid.Parse("150fe35a-657b-4c5e-a4fd-644c4c5152b5");
    private static readonly DateTimeOffset Now = new(2026, 10, 9, 12, 0, 0, TimeSpan.Zero);
    private readonly TempFolder _folder = new();

    public void Dispose() => _folder.Dispose();

    private ContactStore Store(ILogger<ContactStore>? logger = null) =>
        new(_folder.ContactsFile, logger ?? NullLogger<ContactStore>.Instance);

    [Fact]
    public void AMissingFileIsEmpty() => Assert.Empty(Store().Load());

    [Fact]
    public void ContactsSurviveTheFile()
    {
        var store = Store();
        store.Save(new Dictionary<Guid, UserContacts>
        {
            [Mario] = new()
            {
                Discord = new DiscordContact { Id = "222222222222222222", Name = "mario", VerifiedAt = Now },
                Email = new EmailContact { Address = "mario@example.com", VerifiedAt = Now },
                LastReminderAt = Now.AddDays(-1),
            },
        });

        var read = Assert.Single(store.Load());

        Assert.Equal(Mario, read.Key);
        Assert.Equal("222222222222222222", read.Value.Discord!.Id);
        Assert.Equal("mario", read.Value.Discord.Name);
        Assert.Equal(Now, read.Value.Discord.VerifiedAt);
        Assert.Equal("mario@example.com", read.Value.Email!.Address);
        Assert.Equal(Now.AddDays(-1), read.Value.LastReminderAt);
        var text = File.ReadAllText(_folder.ContactsFile);
        Assert.Contains("\"Users\"", text);
        Assert.Contains(Mario.ToString("N"), text);
        Assert.False(File.Exists(_folder.ContactsFile + ".tmp"));
    }

    [Theory]
    [InlineData("non è json")]
    [InlineData("null")]
    [InlineData("""{"Users":{"non-un-guid":{}}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":null}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":{"Discord":{"Id":"abc","Name":"mario"}}}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":{"Discord":{"Id":"222222222222222222","Name":" "}}}}""")]
    [InlineData("""{"Users":{"150fe35a657b4c5ea4fd644c4c5152b5":{"Email":{"Address":""}}}}""")]
    public void AnUnreadableFileMovesToBadAndStartsEmpty(string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ContactsFile)!);
        File.WriteAllText(_folder.ContactsFile, content);
        var logger = new RecordingLogger<ContactStore>();

        Assert.Empty(Store(logger).Load());

        Assert.False(File.Exists(_folder.ContactsFile));
        Assert.Equal(content, File.ReadAllText(_folder.ContactsFile + ".bad"));
        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning);
    }
}
```

Crea `ContactRegistryTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactRegistryTests : IDisposable
{
    private static readonly DateTimeOffset Now = new(2026, 10, 9, 12, 0, 0, TimeSpan.Zero);
    private readonly TempFolder _folder = new();
    private readonly Guid _mario = Guid.NewGuid();

    public void Dispose() => _folder.Dispose();

    private ContactRegistry Registry() => TestAccount.Registry(_folder);

    private static DiscordContact Discord() => new() { Id = "222222222222222222", Name = "mario", VerifiedAt = Now };

    private static EmailContact Email() => new() { Address = "mario@example.com", VerifiedAt = Now };

    [Fact]
    public void AnUnknownUserHasNoContacts()
    {
        var contacts = Registry().Get(_mario);

        Assert.False(contacts.HasContact);
        Assert.Null(contacts.LastReminderAt);
    }

    [Fact]
    public void ContactsAreSavedAndReadBack()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());
        registry.SetEmail(_mario, Email());

        var reloaded = Registry().Get(_mario);

        Assert.Equal("222222222222222222", reloaded.Discord!.Id);
        Assert.Equal("mario@example.com", reloaded.Email!.Address);
        Assert.True(reloaded.HasContact);
    }

    [Fact]
    public void CopiesDoNotChangeTheRegistry()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());

        var copy = registry.Get(_mario);
        copy.Discord!.Name = "altro";
        copy.Email = Email();

        Assert.Equal("mario", registry.Get(_mario).Discord!.Name);
        Assert.Null(registry.Get(_mario).Email);
        Assert.Equal("mario", registry.All()[_mario].Discord!.Name);
    }

    [Fact]
    public void RemoveTakesOneChannelRemoveAllBoth()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());
        registry.SetEmail(_mario, Email());

        Assert.True(registry.Remove(_mario, AccountChannel.Email));
        Assert.False(registry.Remove(_mario, AccountChannel.Email));
        Assert.NotNull(registry.Get(_mario).Discord);
        Assert.True(registry.RemoveAll(_mario));
        Assert.False(registry.RemoveAll(_mario));
        Assert.False(Registry().Get(_mario).HasContact);
    }

    [Fact]
    public void AUserWithNothingLeftLeavesTheFile()
    {
        var registry = Registry();
        registry.SetDiscord(_mario, Discord());

        registry.RemoveAll(_mario);

        Assert.Empty(registry.All());
        Assert.DoesNotContain(_mario.ToString("N"), File.ReadAllText(_folder.ContactsFile));
    }

    [Fact]
    public void TheLastReminderStaysWithoutContacts()
    {
        var registry = Registry();
        registry.MarkReminded(_mario, Now);

        Assert.Equal(Now, Registry().Get(_mario).LastReminderAt);
        Assert.False(registry.RemoveAll(_mario));
        Assert.Equal(Now, registry.Get(_mario).LastReminderAt);
    }

    [Fact]
    public void PruneDropsTheUsersJellyfinNoLongerHas()
    {
        var registry = Registry();
        var luigi = Guid.NewGuid();
        registry.SetDiscord(_mario, Discord());
        registry.SetEmail(luigi, Email());

        Assert.Equal(1, registry.Prune(id => id == _mario));

        Assert.Equal(new[] { _mario }, Registry().All().Keys);
        Assert.Equal(0, registry.Prune(id => id == _mario));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ContactStoreTests|FullyQualifiedName~ContactRegistryTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/ContactFile.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Il Discord verificato di un utente.</summary>
public sealed class DiscordContact
{
    /// <summary>L'id dell'utente Discord (snowflake).</summary>
    [JsonPropertyName("Id")]
    public string Id { get; set; } = string.Empty;

    /// <summary>Il nome utente Discord al momento della verifica.</summary>
    [JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("VerifiedAt")]
    public DateTimeOffset VerifiedAt { get; set; }
}

/// <summary>L'email verificata di un utente, come l'ha scritta.</summary>
public sealed class EmailContact
{
    [JsonPropertyName("Address")]
    public string Address { get; set; } = string.Empty;

    [JsonPropertyName("VerifiedAt")]
    public DateTimeOffset VerifiedAt { get; set; }
}

/// <summary>
/// I contatti verificati di un utente e l'ultimo promemoria (spec L §7.2):
/// la stessa forma in contacts.json e in memoria. Fuori dal registro girano
/// solo copie (<see cref="Copy"/>).
/// </summary>
public sealed class UserContacts
{
    [JsonPropertyName("Discord")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DiscordContact? Discord { get; set; }

    [JsonPropertyName("Email")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public EmailContact? Email { get; set; }

    /// <summary>Quando è arrivato l'ultimo promemoria "Proteggi il tuo account".</summary>
    [JsonPropertyName("LastReminderAt")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTimeOffset? LastReminderAt { get; set; }

    /// <summary>Almeno un contatto verificato.</summary>
    [JsonIgnore]
    public bool HasContact => Discord is not null || Email is not null;

    /// <summary>Copia profonda.</summary>
    public UserContacts Copy() => new()
    {
        Discord = Discord is null ? null : new DiscordContact { Id = Discord.Id, Name = Discord.Name, VerifiedAt = Discord.VerifiedAt },
        Email = Email is null ? null : new EmailContact { Address = Email.Address, VerifiedAt = Email.VerifiedAt },
        LastReminderAt = LastReminderAt,
    };
}

/// <summary>
/// Contenuto di contacts.json (spec L §7.2). Id utente in formato "N". Tutto
/// nullable: un file scritto a mano o rovinato si scopre in
/// <see cref="ContactStore.Load"/>.
/// </summary>
public sealed class ContactFile
{
    /// <summary>Versione del formato.</summary>
    public const int CurrentVersion = 1;

    [JsonPropertyName("Version")]
    public int Version { get; set; } = CurrentVersion;

    [JsonPropertyName("Users")]
    public Dictionary<string, UserContacts?>? Users { get; set; } = [];
}
```

Crea `Account/ContactStore.cs`:

```csharp
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// contacts.json su disco (spec L §7.2), accanto a inbox.json nelle
/// configurazioni dei plugin. Non è sicuro tra thread: lo usa solo
/// ContactRegistry, sotto lock.
/// </summary>
public sealed class ContactStore(string filePath, ILogger<ContactStore> logger)
{
    public const string FileName = "contacts.json";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public string FilePath { get; } = filePath;

    public static string DefaultPath(IApplicationPaths paths) =>
        Path.Combine(paths.PluginConfigurationsPath, FriendStore.FolderName, FileName);

    /// <summary>
    /// Legge il file; vuoto se non c'è. Un file illeggibile va in
    /// contacts.json.bad e si riparte vuoti; se non si riesce a spostarlo si
    /// riparte vuoti lo stesso (il prossimo salvataggio lo sovrascrive).
    /// </summary>
    public Dictionary<Guid, UserContacts> Load()
    {
        if (!File.Exists(FilePath))
        {
            return [];
        }

        try
        {
            var file = JsonSerializer.Deserialize<ContactFile>(File.ReadAllText(FilePath))
                ?? throw new FormatException("file vuoto");
            return FromFile(file);
        }
        catch (Exception ex) when (ex is JsonException or FormatException)
        {
            var bad = FilePath + ".bad";
            try
            {
                File.Move(FilePath, bad, overwrite: true);
                logger.LogWarning(ex, "Contatti illeggibili: file spostato in {Path}, si riparte vuoti", bad);
            }
            catch (Exception moveError) when (moveError is IOException or UnauthorizedAccessException)
            {
                // Nel log solo il percorso, mai il contenuto (ci sono le email).
                logger.LogWarning(moveError, "Contatti illeggibili e non spostabili in {Path}: si riparte vuoti, il prossimo salvataggio sovrascrive {File}", bad, FilePath);
            }

            return [];
        }
    }

    /// <summary>
    /// Scrive il file in modo atomico: prima un file temporaneo nella stessa
    /// cartella, poi lo rinomina sopra quello vecchio.
    /// </summary>
    public void Save(IReadOnlyDictionary<Guid, UserContacts> users)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, ToFile(users), Options);

            // Su disco prima della rinomina: senza, una caduta di corrente lascia il file vuoto.
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporary, FilePath, overwrite: true);
    }

    /// <summary>Dal file; FormatException se un utente o un contatto non è valido.</summary>
    internal static Dictionary<Guid, UserContacts> FromFile(ContactFile file)
    {
        var users = new Dictionary<Guid, UserContacts>();
        foreach (var (key, value) in file.Users ?? [])
        {
            if (!Guid.TryParse(key, out var userId) || value is null)
            {
                throw new FormatException("contatti di un utente non validi");
            }

            if (value.Discord is { } discord && (!DiscordIds.IsSnowflake(discord.Id) || string.IsNullOrWhiteSpace(discord.Name)))
            {
                throw new FormatException("Discord non valido");
            }

            if (value.Email is { } email && string.IsNullOrWhiteSpace(email.Address))
            {
                throw new FormatException("email non valida");
            }

            users[userId] = value;
        }

        return users;
    }

    private static ContactFile ToFile(IReadOnlyDictionary<Guid, UserContacts> users) => new()
    {
        Users = users.ToDictionary(pair => pair.Key.ToString("N"), pair => (UserContacts?)pair.Value.Copy()),
    };
}
```

Crea `Account/ContactRegistry.cs`:

```csharp
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// I contatti di tutti gli utenti (spec L §7.2): in memoria, salvati con
/// <see cref="ContactStore"/> a ogni cambio. Un utente senza contatti e
/// senza promemoria esce dal file. Fuori di qui girano copie. Sicuro tra
/// thread.
/// </summary>
public sealed class ContactRegistry(ContactStore store, ILogger<ContactRegistry> logger)
{
    private readonly Lock _lock = new();
    private Dictionary<Guid, UserContacts>? _users;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private Dictionary<Guid, UserContacts> Users
    {
        get
        {
            if (_users is null)
            {
                _users = store.Load();
                logger.LogInformation("Contatti per il recupero in {Path}", store.FilePath);
            }

            return _users;
        }
    }

    /// <summary>Legge subito il file (all'avvio): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Users;
        }
    }

    /// <summary>I contatti dell'utente, come copia; vuoti se non ne ha.</summary>
    public UserContacts Get(Guid userId)
    {
        lock (_lock)
        {
            return Users.TryGetValue(userId, out var contacts) ? contacts.Copy() : new UserContacts();
        }
    }

    /// <summary>Tutti, come copie.</summary>
    public IReadOnlyDictionary<Guid, UserContacts> All()
    {
        lock (_lock)
        {
            return Users.ToDictionary(pair => pair.Key, pair => pair.Value.Copy());
        }
    }

    public void SetDiscord(Guid userId, DiscordContact contact) =>
        Change(userId, contacts =>
        {
            contacts.Discord = contact;
            return true;
        });

    public void SetEmail(Guid userId, EmailContact contact) =>
        Change(userId, contacts =>
        {
            contacts.Email = contact;
            return true;
        });

    /// <summary>Toglie il contatto di un canale; true se c'era.</summary>
    public bool Remove(Guid userId, AccountChannel channel) =>
        Change(userId, contacts =>
        {
            if (channel == AccountChannel.Discord)
            {
                var had = contacts.Discord is not null;
                contacts.Discord = null;
                return had;
            }

            var hadEmail = contacts.Email is not null;
            contacts.Email = null;
            return hadEmail;
        });

    /// <summary>Toglie tutti i contatti (resta l'ultimo promemoria); true se ce n'era almeno uno.</summary>
    public bool RemoveAll(Guid userId) =>
        Change(userId, contacts =>
        {
            var had = contacts.HasContact;
            contacts.Discord = null;
            contacts.Email = null;
            return had;
        });

    /// <summary>Segna l'ora dell'ultimo promemoria.</summary>
    public void MarkReminded(Guid userId, DateTimeOffset at) =>
        Change(userId, contacts =>
        {
            contacts.LastReminderAt = at;
            return true;
        });

    /// <summary>Toglie gli utenti che Jellyfin non ha più; restituisce quanti.</summary>
    public int Prune(Func<Guid, bool> userExists)
    {
        lock (_lock)
        {
            var gone = Users.Keys.Where(userId => !userExists(userId)).ToList();
            foreach (var userId in gone)
            {
                Users.Remove(userId);
            }

            if (gone.Count > 0)
            {
                Persist();
            }

            return gone.Count;
        }
    }

    private bool Change(Guid userId, Func<UserContacts, bool> change)
    {
        lock (_lock)
        {
            if (!Users.TryGetValue(userId, out var contacts))
            {
                contacts = new UserContacts();
                Users[userId] = contacts;
            }

            var changed = change(contacts);
            if (!contacts.HasContact && contacts.LastReminderAt is null)
            {
                Users.Remove(userId);
            }

            if (changed)
            {
                Persist();
            }

            return changed;
        }
    }

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        try
        {
            store.Save(Users);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Contatti non salvati in {Path}", store.FilePath);
        }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recovery contacts stored in contacts.json"
```

### Task 5: impostazioni e messaggi

**Files:**
- Modify: `Configuration/PluginConfiguration.cs`
- Create: `Account/IAccountSettings.cs`, `Server/PluginAccountSettings.cs`, `Account/AccountMessages.cs`
- Create (test): `FakeAccountSettings.cs`, `AccountSettingsTests.cs`, `AccountMessagesTests.cs`

- [ ] **Step 1: i test**

Crea `FakeAccountSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Impostazioni del recupero con tutti e due i canali configurati, da cambiare nel test.</summary>
internal sealed class FakeAccountSettings : IAccountSettings
{
    public string DiscordBotToken { get; set; } = "bot-token";

    public string DiscordGuildId { get; set; } = "123456789012345678";

    public string SmtpHost { get; set; } = "smtp.example.com";

    public int SmtpPort { get; set; } = 587;

    public string SmtpUser { get; set; } = "wonderflix";

    public string SmtpPassword { get; set; } = "smtp-secret";

    public string MailFrom { get; set; } = "wonderflix@example.com";

    public int ContactReminderDays { get; set; } = 14;
}
```

Crea `AccountSettingsTests.cs`:

```csharp
using System.Xml.Serialization;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AccountSettingsTests
{
    [Fact]
    public void TheDefaultsHaveNoChannelsAndRemindEveryFourteenDays()
    {
        var config = new PluginConfiguration();
        Assert.Equal(string.Empty, config.DiscordBotToken);
        Assert.Equal(string.Empty, config.DiscordGuildId);
        Assert.Equal(string.Empty, config.SmtpHost);
        Assert.Equal(587, config.SmtpPort);
        Assert.Equal(string.Empty, config.SmtpUser);
        Assert.Equal(string.Empty, config.SmtpPassword);
        Assert.Equal(string.Empty, config.MailFrom);
        Assert.Equal(14, config.ContactReminderDays);

        // Nei test Jellyfin non crea il plugin: valgono i predefiniti.
        var settings = new PluginAccountSettings();
        Assert.False(settings.IsDiscordConfigured());
        Assert.False(settings.IsEmailConfigured());
        Assert.Empty(settings.Channels());
        Assert.Equal(587, settings.SmtpPort);
        Assert.Equal(14, settings.ContactReminderDays);
    }

    [Fact]
    public void TheSettingsSurviveTheXml()
    {
        // Jellyfin salva la configurazione con XmlSerializer.
        var serializer = new XmlSerializer(typeof(PluginConfiguration));
        using var writer = new StringWriter();
        serializer.Serialize(writer, new PluginConfiguration
        {
            DiscordBotToken = "token",
            DiscordGuildId = "123456789012345678",
            SmtpHost = "smtp.example.com",
            SmtpPort = 2525,
            SmtpUser = "user",
            SmtpPassword = "password",
            MailFrom = "wonderflix@example.com",
            ContactReminderDays = 0,
        });
        using var reader = new StringReader(writer.ToString());

        var read = (PluginConfiguration)serializer.Deserialize(reader)!;

        Assert.Equal("token", read.DiscordBotToken);
        Assert.Equal("123456789012345678", read.DiscordGuildId);
        Assert.Equal("smtp.example.com", read.SmtpHost);
        Assert.Equal(2525, read.SmtpPort);
        Assert.Equal("user", read.SmtpUser);
        Assert.Equal("password", read.SmtpPassword);
        Assert.Equal("wonderflix@example.com", read.MailFrom);
        Assert.Equal(0, read.ContactReminderDays);
    }

    [Fact]
    public void BothChannelsWhenEverythingIsThere()
    {
        var settings = new FakeAccountSettings();

        Assert.True(settings.IsDiscordConfigured());
        Assert.True(settings.IsEmailConfigured());
        Assert.True(settings.IsConfigured(AccountChannel.Email));
        Assert.Equal(new[] { AccountChannel.Discord, AccountChannel.Email }, settings.Channels());
    }

    [Theory]
    [InlineData("", "123456789012345678")]
    [InlineData(" ", "123456789012345678")]
    [InlineData("token", "")]
    [InlineData("token", "server")]
    [InlineData("token", "1234")]
    public void DiscordNeedsATokenAndANumericServerId(string token, string guild) =>
        Assert.False(new FakeAccountSettings { DiscordBotToken = token, DiscordGuildId = guild }.IsDiscordConfigured());

    [Theory]
    [InlineData("", 587, "u", "p", "f@example.com")]
    [InlineData("smtp.example.com", 0, "u", "p", "f@example.com")]
    [InlineData("smtp.example.com", 70000, "u", "p", "f@example.com")]
    [InlineData("smtp.example.com", 587, "", "p", "f@example.com")]
    [InlineData("smtp.example.com", 587, "u", "", "f@example.com")]
    [InlineData("smtp.example.com", 587, "u", "p", " ")]
    public void EmailNeedsServerPortUserPasswordAndSender(string host, int port, string user, string password, string from)
    {
        var settings = new FakeAccountSettings
        {
            SmtpHost = host,
            SmtpPort = port,
            SmtpUser = user,
            SmtpPassword = password,
            MailFrom = from,
        };

        Assert.False(settings.IsEmailConfigured());
        Assert.Equal(new[] { AccountChannel.Discord }, settings.Channels());
    }
}
```

Crea `AccountMessagesTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AccountMessagesTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("it")]
    [InlineData("de")]
    [InlineData("english")]
    public void ItalianUnlessEnglish(string? language)
    {
        var message = AccountMessages.Verify(language, "012345");

        Assert.Equal("WonderFlix — codice", message.Subject);
        Assert.Contains("012345", message.Text);
        Assert.Contains("Scade tra 10 minuti", message.Text);
    }

    [Theory]
    [InlineData("en")]
    [InlineData(" EN ")]
    public void English(string language)
    {
        var message = AccountMessages.Verify(language, "012345");

        Assert.Equal("WonderFlix — code", message.Subject);
        Assert.Contains("012345", message.Text);
        Assert.Contains("expires in 10 minutes", message.Text);
    }

    [Fact]
    public void RecoveryNamesTheUserAndSaysThePasswordStays()
    {
        var italian = AccountMessages.Recovery("it", "Mario", "654321");
        Assert.Contains("«Mario»", italian.Text);
        Assert.Contains("654321", italian.Text);
        Assert.Contains("la password non cambia", italian.Text);

        var english = AccountMessages.Recovery("en", "Mario", "654321");
        Assert.Contains("«Mario»", english.Text);
        Assert.Contains("the password doesn't change", english.Text);
    }

    [Fact]
    public void PasswordChangedAndTest()
    {
        Assert.Equal("WonderFlix — password cambiata", AccountMessages.PasswordChanged("it", "Mario").Subject);
        Assert.Contains("«Mario»", AccountMessages.PasswordChanged("en", "Mario").Text);
        Assert.Equal("WonderFlix — prova", AccountMessages.Test(null).Subject);
        Assert.Equal("WonderFlix — test", AccountMessages.Test("en").Subject);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~AccountSettingsTests|FullyQualifiedName~AccountMessagesTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

In `Configuration/PluginConfiguration.cs`, dopo `SeerrWebhookSecret`, aggiungi:

```csharp
    /// <summary>Token del bot Discord dei codici di recupero (spec L §7.1). Il file lo leggono solo gli admin.</summary>
    public string DiscordBotToken { get; set; } = string.Empty;

    /// <summary>Id del server Discord dove si cercano i membri.</summary>
    public string DiscordGuildId { get; set; } = string.Empty;

    /// <summary>Server SMTP delle email di recupero.</summary>
    public string SmtpHost { get; set; } = string.Empty;

    /// <summary>Porta SMTP con STARTTLS (di solito 587).</summary>
    public int SmtpPort { get; set; } = 587;

    public string SmtpUser { get; set; } = string.Empty;

    /// <summary>Password SMTP. Il file lo leggono solo gli admin.</summary>
    public string SmtpPassword { get; set; } = string.Empty;

    /// <summary>Indirizzo del mittente; il nome visualizzato è "WonderFlix".</summary>
    public string MailFrom { get; set; } = string.Empty;

    /// <summary>Ogni quanti giorni il promemoria a chi non ha contatti; 0 lo spegne.</summary>
    public int ContactReminderDays { get; set; } = 14;
```

Crea `Account/IAccountSettings.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// Le impostazioni del recupero (spec L §7.1). Vanno lette ogni volta:
/// l'admin le cambia dalla Dashboard.
/// </summary>
public interface IAccountSettings
{
    string DiscordBotToken { get; }

    string DiscordGuildId { get; }

    string SmtpHost { get; }

    int SmtpPort { get; }

    string SmtpUser { get; }

    string SmtpPassword { get; }

    string MailFrom { get; }

    /// <summary>Ogni quanti giorni il promemoria; 0 lo spegne.</summary>
    int ContactReminderDays { get; }
}

public static class AccountSettingsExtensions
{
    /// <summary>Porta TCP più alta.</summary>
    private const int MaxPort = 65535;

    /// <summary>Token e id numerico del server.</summary>
    public static bool IsDiscordConfigured(this IAccountSettings settings) =>
        !string.IsNullOrWhiteSpace(settings.DiscordBotToken) && DiscordIds.IsSnowflake(settings.DiscordGuildId);

    /// <summary>Server, porta, utente, password e mittente.</summary>
    public static bool IsEmailConfigured(this IAccountSettings settings) =>
        !string.IsNullOrWhiteSpace(settings.SmtpHost)
        && settings.SmtpPort is > 0 and <= MaxPort
        && !string.IsNullOrWhiteSpace(settings.SmtpUser)
        && !string.IsNullOrEmpty(settings.SmtpPassword)
        && !string.IsNullOrWhiteSpace(settings.MailFrom);

    public static bool IsConfigured(this IAccountSettings settings, AccountChannel channel) =>
        channel == AccountChannel.Discord ? settings.IsDiscordConfigured() : settings.IsEmailConfigured();

    /// <summary>I canali configurati, nell'ordine Discord, Email.</summary>
    public static IReadOnlyList<AccountChannel> Channels(this IAccountSettings settings) =>
        AccountChannels.All.Where(settings.IsConfigured).ToList();
}
```

Crea `Server/PluginAccountSettings.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Le impostazioni del recupero dalla configurazione del plugin.</summary>
public sealed class PluginAccountSettings : IAccountSettings
{
    // Senza plugin (nei test) valgono i predefiniti.
    private static readonly PluginConfiguration Defaults = new();

    // Si legge ogni volta, come PluginSeerrSettings: salvando dalla
    // Dashboard Jellyfin sostituisce l'oggetto della configurazione.
    private static PluginConfiguration Config => Plugin.Instance?.Configuration ?? Defaults;

    public string DiscordBotToken => (Config.DiscordBotToken ?? string.Empty).Trim();

    public string DiscordGuildId => (Config.DiscordGuildId ?? string.Empty).Trim();

    public string SmtpHost => (Config.SmtpHost ?? string.Empty).Trim();

    public int SmtpPort => Config.SmtpPort;

    public string SmtpUser => (Config.SmtpUser ?? string.Empty).Trim();

    // La password si usa com'è: gli spazi possono farne parte.
    public string SmtpPassword => Config.SmtpPassword ?? string.Empty;

    public string MailFrom => (Config.MailFrom ?? string.Empty).Trim();

    public int ContactReminderDays => Math.Max(0, Config.ContactReminderDays);
}
```

Crea `Account/AccountMessages.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Un messaggio da mandare: l'oggetto (per le email) e il testo.</summary>
public sealed record AccountMessage(string Subject, string Text);

/// <summary>I testi dei messaggi del plugin (spec L §7.3), in italiano o in inglese.</summary>
public static class AccountMessages
{
    private static int Minutes => (int)CodeBook.Lifetime.TotalMinutes;

    /// <summary>"en" è inglese; tutto il resto, anche vuoto o sconosciuto, italiano.</summary>
    public static bool IsEnglish(string? language) =>
        string.Equals(language?.Trim(), "en", StringComparison.OrdinalIgnoreCase);

    public static AccountMessage Verify(string? language, string code) => IsEnglish(language)
        ? new(
            "WonderFlix — code",
            $"Your WonderFlix code to link this account is {code}. It expires in {Minutes} minutes. If you didn't ask for it, ignore this message.")
        : new(
            "WonderFlix — codice",
            $"Il tuo codice WonderFlix per collegare questo account è {code}. Scade tra {Minutes} minuti. Se non l'hai chiesto tu, ignora questo messaggio.");

    public static AccountMessage Recovery(string? language, string userName, string code) => IsEnglish(language)
        ? new(
            "WonderFlix — code",
            $"Your WonderFlix code to change the password of «{userName}» is {code}. It expires in {Minutes} minutes. If you didn't ask for it, ignore this message: the password doesn't change until the code is used.")
        : new(
            "WonderFlix — codice",
            $"Il tuo codice WonderFlix per cambiare la password di «{userName}» è {code}. Scade tra {Minutes} minuti. Se non l'hai chiesto tu, ignora questo messaggio: la password non cambia finché il codice non viene usato.");

    public static AccountMessage PasswordChanged(string? language, string userName) => IsEnglish(language)
        ? new(
            "WonderFlix — password changed",
            $"The WonderFlix password of «{userName}» has been changed. If it wasn't you, write to the administrator.")
        : new(
            "WonderFlix — password cambiata",
            $"La password WonderFlix di «{userName}» è stata cambiata. Se non sei stato tu, scrivi all'amministratore.");

    public static AccountMessage Test(string? language) => IsEnglish(language)
        ? new("WonderFlix — test", "Test message from WonderFlix: the channel works.")
        : new("WonderFlix — prova", "Messaggio di prova di WonderFlix: il canale funziona.");
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera (`PluginConfigurationTests` deve restare verde).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): recovery settings and message texts"
```

## Gruppo B — canali

### Task 6: il bot Discord

**Files:**
- Create: `Account/IDiscordSender.cs`, `Server/DiscordBotClient.cs`
- Create (test): `FakeDiscordHttp.cs`, `DiscordBotClientTests.cs`

- [ ] **Step 1: i test**

Crea `FakeDiscordHttp.cs`:

```csharp
using System.Net;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Una richiesta vista da <see cref="FakeDiscordHttp"/>.</summary>
internal sealed record DiscordRequest(HttpMethod Method, string PathAndQuery, string? Authorization, string? UserAgent, string? Body);

/// <summary>HTTP finto per DiscordBotClient: registra le richieste e risponde con <see cref="Respond"/>.</summary>
internal sealed class FakeDiscordHttp : HttpMessageHandler, IHttpClientFactory
{
    public List<DiscordRequest> Requests { get; } = [];

    public Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> Respond { get; set; } =
        (_, _) => Task.FromResult(Json(HttpStatusCode.OK, "{}"));

    /// <summary>Il nome con cui DiscordBotClient ha chiesto l'ultimo client.</summary>
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
        Requests.Add(new DiscordRequest(
            request.Method, request.RequestUri!.PathAndQuery, Header(request, "Authorization"), Header(request, "User-Agent"), body));
        return await Respond(request, cancellationToken);
    }

    private static string? Header(HttpRequestMessage request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? string.Join(" ", values) : null;
}
```

Crea `DiscordBotClientTests.cs`:

```csharp
using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class DiscordBotClientTests
{
    private const string ChannelsPath = "/api/v10/users/@me/channels";
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeDiscordHttp _http = new();
    private readonly FakeAccountSettings _settings = new();
    private readonly RecordingLogger<DiscordBotClient> _logger = new();

    private DiscordBotClient Client(TimeSpan? timeout = null) =>
        new(_http, _settings, _logger) { Timeout = timeout ?? DiscordBotClient.DefaultTimeout };

    private static HttpResponseMessage Json(HttpStatusCode status, string json) => FakeDiscordHttp.Json(status, json);

    // Il canale DM si apre sempre; il messaggio risponde con status e body.
    private void MessagesAnswer(HttpStatusCode status, string body) =>
        _http.Respond = (request, _) => Task.FromResult(request.RequestUri!.AbsolutePath == ChannelsPath
            ? Json(HttpStatusCode.OK, """{"id":"333333333333333333"}""")
            : Json(status, body));

    [Fact]
    public async Task FindsTheExactNameAmongThePrefixMatches()
    {
        _http.Respond = (_, _) => Task.FromResult(Json(
            HttpStatusCode.OK,
            """[{"user":{"id":"111111111111111111","username":"mario64"}},{"user":{"id":"222222222222222222","username":"Mario"}}]"""));

        var lookup = await Client().FindMemberAsync("mario", Ct);

        Assert.Equal(new DiscordMember("222222222222222222", "Mario"), lookup.Member);
        var request = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v10/guilds/123456789012345678/members/search?query=mario&limit=10", request.PathAndQuery);
        Assert.Equal("Bot bot-token", request.Authorization);
        Assert.StartsWith("DiscordBot (https://github.com/davidesidoti/wonderflix, ", request.UserAgent);
        Assert.Equal(DiscordBotClient.HttpClientName, _http.LastClientName);
    }

    [Fact]
    public async Task OnlyPrefixMatchesIsNotFound()
    {
        _http.Respond = (_, _) => Task.FromResult(Json(
            HttpStatusCode.OK, """[{"user":{"id":"111111111111111111","username":"mario64"}}]"""));

        var lookup = await Client().FindMemberAsync("mario", Ct);

        Assert.Null(lookup.Member);
        Assert.False(lookup.Failed);
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, """{"code":50001,"message":"Missing Access"}""")]
    [InlineData(HttpStatusCode.OK, "non è json")]
    [InlineData(HttpStatusCode.OK, """{"user":{}}""")]
    public async Task SearchErrorsAreFailures(HttpStatusCode status, string body)
    {
        _http.Respond = (_, _) => Task.FromResult(Json(status, body));

        Assert.True((await Client().FindMemberAsync("mario", Ct)).Failed);
    }

    [Fact]
    public async Task ANetworkErrorIsAFailure()
    {
        _http.Respond = (_, _) => throw new HttpRequestException("rete");

        Assert.True((await Client().FindMemberAsync("mario", Ct)).Failed);
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));
        Assert.Equal(DiscordCheck.Failed, await Client().CheckAsync(Ct));
    }

    [Fact]
    public async Task ADirectMessageOpensTheChannelThenWrites()
    {
        MessagesAnswer(HttpStatusCode.OK, "{}");

        Assert.Equal(SendOutcome.Sent, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));

        Assert.Equal(2, _http.Requests.Count);
        Assert.Equal(HttpMethod.Post, _http.Requests[0].Method);
        Assert.Equal(ChannelsPath, _http.Requests[0].PathAndQuery);
        Assert.Equal("""{"recipient_id":"222222222222222222"}""", _http.Requests[0].Body);
        Assert.Equal(HttpMethod.Post, _http.Requests[1].Method);
        Assert.Equal("/api/v10/channels/333333333333333333/messages", _http.Requests[1].PathAndQuery);
        Assert.Equal("""{"content":"Codice 654321"}""", _http.Requests[1].Body);
    }

    [Fact]
    public async Task ClosedDirectMessagesAreDmClosed()
    {
        MessagesAnswer(HttpStatusCode.Forbidden, """{"code":50007,"message":"Cannot send messages to this user"}""");

        Assert.Equal(SendOutcome.DmClosed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));
    }

    [Theory]
    [InlineData(HttpStatusCode.TooManyRequests, """{"retry_after":1.5,"global":false}""")]
    [InlineData(HttpStatusCode.Forbidden, """{"code":50001,"message":"Missing Access"}""")]
    [InlineData(HttpStatusCode.InternalServerError, "")]
    public async Task OtherErrorsAreFailures(HttpStatusCode status, string body)
    {
        MessagesAnswer(status, body);
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));

        // Anche quando non si apre il canale.
        _http.Respond = (_, _) => Task.FromResult(Json(status, body));
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));
    }

    [Fact]
    public async Task NoAnswerInTimeIsAFailure()
    {
        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return Json(HttpStatusCode.OK, "{}");
        };

        Assert.Equal(
            SendOutcome.Failed,
            await Client(TimeSpan.FromMilliseconds(50)).SendDmAsync("222222222222222222", "Codice 654321", Ct));
    }

    [Fact]
    public async Task CheckReadsTheBotThenTheServer()
    {
        Assert.Equal(DiscordCheck.Ok, await Client().CheckAsync(Ct));

        Assert.Equal(
            new[] { "/api/v10/users/@me", "/api/v10/guilds/123456789012345678" },
            _http.Requests.Select(r => r.PathAndQuery));
    }

    [Theory]
    [InlineData("/api/v10/users/@me", HttpStatusCode.Unauthorized, DiscordCheck.Invalid)]
    [InlineData("/api/v10/guilds/123456789012345678", HttpStatusCode.NotFound, DiscordCheck.Invalid)]
    [InlineData("/api/v10/guilds/123456789012345678", HttpStatusCode.Forbidden, DiscordCheck.Invalid)]
    [InlineData("/api/v10/users/@me", HttpStatusCode.BadGateway, DiscordCheck.Failed)]
    public async Task CheckErrors(string failing, HttpStatusCode status, DiscordCheck expected)
    {
        _http.Respond = (request, _) => Task.FromResult(request.RequestUri!.AbsolutePath == failing
            ? Json(status, "{}")
            : Json(HttpStatusCode.OK, "{}"));

        Assert.Equal(expected, await Client().CheckAsync(Ct));
    }

    [Fact]
    public async Task WithoutSettingsOrWithABadIdNothingIsSent()
    {
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("non-un-id", "x", Ct));
        _settings.DiscordBotToken = " ";

        Assert.True((await Client().FindMemberAsync("mario", Ct)).Failed);
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "x", Ct));
        Assert.Equal(DiscordCheck.Invalid, await Client().CheckAsync(Ct));
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task TheTokenAndTheQueryNeverGoToTheLog()
    {
        _http.Respond = (_, _) => Task.FromResult(Json(HttpStatusCode.Forbidden, """{"code":50001,"message":"Missing Access"}"""));

        await Client().FindMemberAsync("mario", Ct);
        await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct);

        Assert.NotEmpty(_logger.Entries);
        Assert.All(_logger.Entries, e =>
        {
            Assert.DoesNotContain("bot-token", e.Message);
            Assert.DoesNotContain("query=", e.Message);
            Assert.DoesNotContain("654321", e.Message);
        });
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~DiscordBotClientTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/IDiscordSender.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Esito di un invio (spec L §7.3).</summary>
public enum SendOutcome
{
    Sent,

    /// <summary>Discord: l'utente non accetta messaggi diretti dal bot.</summary>
    DmClosed,

    Failed,
}

/// <summary>Un membro del server Discord.</summary>
public sealed record DiscordMember(string Id, string Username);

/// <summary>Esito della ricerca di un membro: trovato, non trovato, oppure errore di Discord.</summary>
public sealed record DiscordLookup(DiscordMember? Member, bool Failed)
{
    public static readonly DiscordLookup NotFound = new(null, false);

    public static readonly DiscordLookup Error = new(null, true);

    public static DiscordLookup Found(DiscordMember member) => new(member, false);
}

/// <summary>Esito del controllo di token e server.</summary>
public enum DiscordCheck
{
    Ok,

    /// <summary>Discord ha rifiutato il token, o il bot non è nel server.</summary>
    Invalid,

    /// <summary>Discord non ha risposto, o ha risposto con un altro errore.</summary>
    Failed,
}

/// <summary>Il bot Discord dei codici (spec L §7.3). Non lancia: gli errori sono esiti.</summary>
public interface IDiscordSender
{
    /// <summary>Il membro del server con esattamente questo nome utente (senza badare alle maiuscole).</summary>
    Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken);

    /// <summary>Un messaggio diretto all'utente Discord con questo id.</summary>
    Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken);

    /// <summary>Token e server validi.</summary>
    Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken);
}
```

Crea `Server/DiscordBotClient.cs`:

```csharp
using System.Net.Http.Json;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// L'API REST di Discord per il bot dei codici (spec L §7.3): cerca un
/// membro del server, manda un messaggio diretto, controlla token e
/// server. Nel registro solo metodo, percorso senza query ed esito: mai il
/// token, mai il testo.
/// </summary>
public sealed class DiscordBotClient(
    IHttpClientFactory httpClientFactory,
    IAccountSettings settings,
    ILogger<DiscordBotClient> logger) : IDiscordSender
{
    /// <summary>Nome del client HTTP registrato nel DI.</summary>
    public const string HttpClientName = "WonderFlixDiscord";

    /// <summary>L'API v10 di Discord.</summary>
    public const string ApiBase = "https://discord.com/api/v10/";

    /// <summary>Codice d'errore di Discord: l'utente non accetta messaggi diretti dal bot.</summary>
    public const int CannotMessageUser = 50007;

    /// <summary>Risultati della ricerca: va per prefisso, il nome giusto è fra i primi.</summary>
    public const int SearchLimit = 10;

    /// <summary>Attesa massima di una risposta di Discord.</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    // Discord vuole un User-Agent "DiscordBot (url, versione)".
    private static readonly string UserAgent =
        $"DiscordBot (https://github.com/davidesidoti/wonderflix, {typeof(Plugin).Assembly.GetName().Version?.ToString(3) ?? "0.0.0"})";

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    public async Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured())
        {
            return DiscordLookup.Error;
        }

        var reply = await SendAsync(
            HttpMethod.Get,
            $"guilds/{settings.DiscordGuildId}/members/search?query={Uri.EscapeDataString(username)}&limit={SearchLimit}",
            null,
            cancellationToken).ConfigureAwait(false);
        if (reply is not { Status: 200 })
        {
            return DiscordLookup.Error;
        }

        try
        {
            using var json = JsonDocument.Parse(reply.Body);
            foreach (var member in json.RootElement.EnumerateArray())
            {
                if (member.TryGetProperty("user", out var user)
                    && user.TryGetProperty("id", out var id)
                    && user.TryGetProperty("username", out var name)
                    && name.GetString() is { } found
                    && string.Equals(found, username, StringComparison.OrdinalIgnoreCase)
                    && id.GetString() is { } memberId
                    && DiscordIds.IsSnowflake(memberId))
                {
                    return DiscordLookup.Found(new DiscordMember(memberId, found));
                }
            }

            return DiscordLookup.NotFound;
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            logger.LogWarning("Discord: risposta della ricerca dei membri non valida ({Error})", ex.GetType().Name);
            return DiscordLookup.Error;
        }
    }

    public async Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured() || !DiscordIds.IsSnowflake(userId))
        {
            return SendOutcome.Failed;
        }

        var channel = await SendAsync(HttpMethod.Post, "users/@me/channels", new { recipient_id = userId }, cancellationToken)
            .ConfigureAwait(false);
        if (channel is not { Status: 200 })
        {
            return Outcome(channel);
        }

        var channelId = ReadString(channel.Body, "id");
        if (!DiscordIds.IsSnowflake(channelId))
        {
            logger.LogWarning("Discord: il canale del messaggio diretto non ha un id valido");
            return SendOutcome.Failed;
        }

        var message = await SendAsync(HttpMethod.Post, $"channels/{channelId}/messages", new { content = text }, cancellationToken)
            .ConfigureAwait(false);
        return message is { Status: 200 } ? SendOutcome.Sent : Outcome(message);
    }

    public async Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured())
        {
            return DiscordCheck.Invalid;
        }

        var me = await SendAsync(HttpMethod.Get, "users/@me", null, cancellationToken).ConfigureAwait(false);
        if (me is null)
        {
            return DiscordCheck.Failed;
        }

        if (me.Status is 401 or 403)
        {
            return DiscordCheck.Invalid;
        }

        if (me.Status != 200)
        {
            return DiscordCheck.Failed;
        }

        var guild = await SendAsync(HttpMethod.Get, $"guilds/{settings.DiscordGuildId}", null, cancellationToken)
            .ConfigureAwait(false);
        return guild switch
        {
            null => DiscordCheck.Failed,
            { Status: 200 } => DiscordCheck.Ok,
            { Status: 401 or 403 or 404 } => DiscordCheck.Invalid,
            _ => DiscordCheck.Failed,
        };
    }

    // 403 con il codice 50007: messaggi diretti chiusi. Ogni altro errore (429 compreso): Failed.
    private static SendOutcome Outcome(Reply? reply) =>
        reply is { Status: 403 } && ReadCode(reply.Body) == CannotMessageUser ? SendOutcome.DmClosed : SendOutcome.Failed;

    private static int? ReadCode(string body)
    {
        try
        {
            using var json = JsonDocument.Parse(body);
            return json.RootElement.ValueKind == JsonValueKind.Object
                && json.RootElement.TryGetProperty("code", out var code)
                && code.TryGetInt32(out var value)
                ? value
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? ReadString(string body, string property)
    {
        try
        {
            using var json = JsonDocument.Parse(body);
            return json.RootElement.ValueKind == JsonValueKind.Object
                && json.RootElement.TryGetProperty(property, out var value)
                && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>La risposta, o null se Discord non ha risposto (rete, tempo scaduto).</summary>
    private async Task<Reply?> SendAsync(HttpMethod method, string path, object? body, CancellationToken cancellationToken)
    {
        var logPath = path.Split('?')[0];
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var request = new HttpRequestMessage(method, ApiBase + path);
            request.Headers.TryAddWithoutValidation("Authorization", "Bot " + settings.DiscordBotToken);
            request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
            if (body is not null)
            {
                request.Content = JsonContent.Create(body, body.GetType());
            }

            using var response = await httpClientFactory.CreateClient(HttpClientName)
                .SendAsync(request, timeout.Token)
                .ConfigureAwait(false);
            var text = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogInformation("Discord {Method} {Path}: {Status}", method, logPath, (int)response.StatusCode);
            }

            return new Reply((int)response.StatusCode, text);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Discord {Method} {Path}: nessuna risposta in {Timeout}", method, logPath, Timeout);
            return null;
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException or FormatException or NotSupportedException)
        {
            // Questi messaggi non contengono né il token né la query.
            logger.LogWarning("Discord {Method} {Path} non riuscita: {Error} {Message}", method, logPath, ex.GetType().Name, ex.Message);
            return null;
        }
    }

    private sealed record Reply(int Status, string Body);
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): Discord bot client for recovery codes"
```

### Task 7: l'email e gli invii

**Files:**
- Create: `Account/IMailSender.cs`, `Server/SmtpMailSender.cs`, `Account/AccountSender.cs`
- Create (test): `SmtpMailSenderTests.cs`, `FakeAccountChannels.cs`, `AccountRig.cs`, `AccountSenderTests.cs`

- [ ] **Step 1: i test**

Crea `SmtpMailSenderTests.cs`:

```csharp
using System.Net.Mail;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SmtpMailSenderTests
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private static readonly AccountMessage Message = new("WonderFlix — codice", "Il tuo codice è 123456.");
    private readonly FakeAccountSettings _settings = new();
    private readonly RecordingLogger<SmtpMailSender> _logger = new();

    private sealed record SeenMail(
        SmtpServer Server, string From, string FromName, string To, string Subject, string Body, bool Html);

    [Fact]
    public async Task APlainTextMailFromWonderFlix()
    {
        SeenMail? seen = null;
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (server, mail, _) =>
            {
                seen = new SeenMail(
                    server, mail.From!.Address, mail.From.DisplayName, mail.To.Single().Address, mail.Subject, mail.Body, mail.IsBodyHtml);
                return Task.CompletedTask;
            },
        };

        Assert.Equal(SendOutcome.Sent, await sender.SendAsync("mario@example.com", Message, Ct));

        Assert.Equal(
            new SeenMail(
                new SmtpServer("smtp.example.com", 587, "wonderflix", "smtp-secret"),
                "wonderflix@example.com",
                "WonderFlix",
                "mario@example.com",
                "WonderFlix — codice",
                "Il tuo codice è 123456.",
                false),
            seen);
    }

    [Fact]
    public async Task WithoutSettingsNothingIsSent()
    {
        var called = false;
        _settings.SmtpPassword = string.Empty;
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) =>
            {
                called = true;
                return Task.CompletedTask;
            },
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));
        Assert.False(called);
    }

    [Fact]
    public async Task AnSmtpErrorIsAFailureWithoutAddressesInTheLog()
    {
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Transport = (_, _, _) => throw new SmtpException(
                SmtpStatusCode.MailboxUnavailable, "Mailbox unavailable: <mario@example.com> user unknown"),
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));

        var entry = Assert.Single(_logger.Entries);
        Assert.Equal(LogLevel.Warning, entry.Level);
        Assert.Contains("smtp.example.com", entry.Message);
        Assert.Contains("user unknown", entry.Message);
        Assert.DoesNotContain("mario@example.com", entry.Message);
        Assert.DoesNotContain("smtp-secret", entry.Message);
    }

    [Theory]
    [InlineData("non valido")]
    [InlineData("")]
    public async Task AnInvalidAddressIsAFailure(string to)
    {
        var sender = new SmtpMailSender(_settings, _logger) { Transport = (_, _, _) => Task.CompletedTask };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync(to, Message, Ct));
    }

    [Fact]
    public async Task NoAnswerInTimeIsAFailure()
    {
        var sender = new SmtpMailSender(_settings, _logger)
        {
            Timeout = TimeSpan.FromMilliseconds(50),
            Transport = (_, _, ct) => Task.Delay(System.Threading.Timeout.Infinite, ct),
        };

        Assert.Equal(SendOutcome.Failed, await sender.SendAsync("mario@example.com", Message, Ct));
    }
}
```

Crea `FakeAccountChannels.cs`:

```csharp
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il codice a 6 cifre in un messaggio.</summary>
internal static class FakeCodes
{
    public static string In(string text) => Regex.Match(text, @"\b\d{6}\b").Value;
}

/// <summary>Il bot Discord finto: membri, esiti degli invii e messaggi mandati.</summary>
internal sealed class FakeDiscordSender : IDiscordSender
{
    /// <summary>Membri del server per nome utente (senza maiuscole).</summary>
    public Dictionary<string, DiscordMember> Members { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Se true, la ricerca dei membri dà errore.</summary>
    public bool SearchFails { get; set; }

    /// <summary>Esito degli invii per id Discord; di default Sent.</summary>
    public Dictionary<string, SendOutcome> Outcomes { get; } = [];

    public DiscordCheck Check { get; set; } = DiscordCheck.Ok;

    /// <summary>I messaggi arrivati, in ordine.</summary>
    public List<(string UserId, string Text)> Sent { get; } = [];

    /// <summary>I nomi cercati, in ordine.</summary>
    public List<string> Searches { get; } = [];

    public Task<DiscordLookup> FindMemberAsync(string username, CancellationToken cancellationToken)
    {
        Searches.Add(username);
        return Task.FromResult(
            SearchFails ? DiscordLookup.Error
            : Members.TryGetValue(username, out var member) ? DiscordLookup.Found(member)
            : DiscordLookup.NotFound);
    }

    public Task<SendOutcome> SendDmAsync(string userId, string text, CancellationToken cancellationToken)
    {
        var outcome = Outcomes.GetValueOrDefault(userId, SendOutcome.Sent);
        if (outcome == SendOutcome.Sent)
        {
            Sent.Add((userId, text));
        }

        return Task.FromResult(outcome);
    }

    public Task<DiscordCheck> CheckAsync(CancellationToken cancellationToken) => Task.FromResult(Check);

    /// <summary>L'ultimo codice mandato a questo id.</summary>
    public string LastCode(string userId) => FakeCodes.In(Sent.Last(s => s.UserId == userId).Text);
}

/// <summary>Le email finte: esiti per indirizzo e messaggi mandati.</summary>
internal sealed class FakeMailSender : IMailSender
{
    /// <summary>Esito degli invii per indirizzo (senza maiuscole); di default Sent.</summary>
    public Dictionary<string, SendOutcome> Outcomes { get; } = new(StringComparer.OrdinalIgnoreCase);

    public List<(string To, AccountMessage Message)> Sent { get; } = [];

    public Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken)
    {
        var outcome = Outcomes.GetValueOrDefault(to, SendOutcome.Sent);
        if (outcome == SendOutcome.Sent)
        {
            Sent.Add((to, message));
        }

        return Task.FromResult(outcome);
    }

    /// <summary>L'ultimo codice mandato a questo indirizzo.</summary>
    public string LastCode(string to) =>
        FakeCodes.In(Sent.Last(s => string.Equals(s.To, to, StringComparison.OrdinalIgnoreCase)).Message.Text);
}
```

Crea `AccountRig.cs` (i task 9–12 aggiungono un metodo ciascuno):

```csharp
using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Time.Testing;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Il modulo Account dei test: server finto, canali finti, file in una cartella temporanea.</summary>
internal sealed class AccountRig : IDisposable
{
    public AccountRig()
    {
        Contacts = TestAccount.Registry(Folder);
        Codes = new CodeBook(Time);
        Limiter = new RateLimiter(Time);
        Inbox = TestInbox.Create(Server, Folder, Time);
        Sender = new AccountSender(Discord, Mail, Settings, Time);
    }

    public TempFolder Folder { get; } = new();

    public FakeServer Server { get; } = new();

    public FakeTimeProvider Time { get; } = new(new DateTimeOffset(2026, 10, 9, 12, 0, 0, TimeSpan.Zero));

    public FakeAccountSettings Settings { get; } = new();

    public FakeDiscordSender Discord { get; } = new();

    public FakeMailSender Mail { get; } = new();

    public ContactRegistry Contacts { get; }

    public CodeBook Codes { get; }

    public RateLimiter Limiter { get; }

    public InboxService Inbox { get; }

    public AccountSender Sender { get; }

    /// <summary>
    /// Un utente con Discord ed email già verificati: l'id Discord è un
    /// numero di 18 cifre, il nome Discord e l'email sono il nome in minuscolo.
    /// </summary>
    public UserRef UserWithContacts(string name, bool isAdmin = false, bool enabled = true)
    {
        var user = Server.AddUser(name, enabled, isAdmin: isAdmin);
        var lower = name.ToLowerInvariant();
        var discordId = (100_000_000_000_000_000L + Server.Users.Count).ToString(CultureInfo.InvariantCulture);
        Contacts.SetDiscord(user.Id, new DiscordContact { Id = discordId, Name = lower, VerifiedAt = Time.GetUtcNow() });
        Contacts.SetEmail(user.Id, new EmailContact { Address = lower + "@example.com", VerifiedAt = Time.GetUtcNow() });
        return user;
    }

    public void Dispose() => Folder.Dispose();
}
```

Crea `AccountSenderTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountSenderTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private static readonly AccountMessage Message = new("Oggetto", "Testo 123456");
    private readonly AccountRig _rig = new();

    public void Dispose() => _rig.Dispose();

    [Fact]
    public async Task EachChannelGoesToItsSender()
    {
        Assert.Equal(SendOutcome.Sent, await _rig.Sender.SendAsync(AccountChannel.Discord, "222222222222222222", Message, Ct));
        Assert.Equal(SendOutcome.Sent, await _rig.Sender.SendAsync(AccountChannel.Email, "mario@example.com", Message, Ct));

        Assert.Equal(new[] { ("222222222222222222", "Testo 123456") }, _rig.Discord.Sent);
        var mail = Assert.Single(_rig.Mail.Sent);
        Assert.Equal("mario@example.com", mail.To);
        Assert.Equal(Message, mail.Message);
    }

    [Fact]
    public async Task AChannelThatIsOffSendsAndRecordsNothing()
    {
        _rig.Settings.SmtpHost = string.Empty;

        Assert.Equal(SendOutcome.Failed, await _rig.Sender.SendAsync(AccountChannel.Email, "mario@example.com", Message, Ct));

        Assert.Empty(_rig.Mail.Sent);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Email));
    }

    [Fact]
    public async Task SendToAllUsesTheConfiguredChannelsWithAContact()
    {
        var mario = _rig.UserWithContacts("Mario");
        var contacts = _rig.Contacts.Get(mario.Id);

        Assert.Equal(
            new[] { AccountChannel.Discord, AccountChannel.Email },
            await _rig.Sender.SendToAllAsync(contacts, Message, Ct));
        _rig.Settings.DiscordBotToken = string.Empty;
        Assert.Equal(new[] { AccountChannel.Email }, await _rig.Sender.SendToAllAsync(contacts, Message, Ct));
        Assert.Equal(new[] { (AccountChannel.Email, "mario@example.com") }, _rig.Sender.Targets(contacts));
        Assert.Empty(await _rig.Sender.SendToAllAsync(new UserContacts(), Message, Ct));
    }

    [Fact]
    public async Task TheLastErrorStaysUntilASend()
    {
        _rig.Discord.Outcomes["222222222222222222"] = SendOutcome.DmClosed;
        await _rig.Sender.SendAsync(AccountChannel.Discord, "222222222222222222", Message, Ct);
        Assert.Equal(new SendError(_rig.Time.GetUtcNow(), "DmClosed"), _rig.Sender.LastError(AccountChannel.Discord));
        Assert.Null(_rig.Sender.LastError(AccountChannel.Email));

        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        await _rig.Sender.SendAsync(AccountChannel.Email, "mario@example.com", Message, Ct);
        Assert.Equal(new SendError(_rig.Time.GetUtcNow(), "SendFailed"), _rig.Sender.LastError(AccountChannel.Email));

        _rig.Sender.RecordInvalid(AccountChannel.Discord);
        Assert.Equal("Invalid", _rig.Sender.LastError(AccountChannel.Discord)!.Code);

        await _rig.Sender.SendAsync(AccountChannel.Discord, "333333333333333333", Message, Ct);
        Assert.Null(_rig.Sender.LastError(AccountChannel.Discord));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~SmtpMailSenderTests|FullyQualifiedName~AccountSenderTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/IMailSender.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Le email dei codici (spec L §7.3). Non lancia: gli errori sono esiti.</summary>
public interface IMailSender
{
    /// <summary>Un'email di solo testo a questo indirizzo.</summary>
    Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken);
}
```

Crea `Server/SmtpMailSender.cs`:

```csharp
using System.Net;
using System.Net.Mail;
using System.Text;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>Il server SMTP letto dalla configurazione al momento dell'invio.</summary>
public sealed record SmtpServer(string Host, int Port, string User, string Password);

/// <summary>
/// Le email dei codici con System.Net.Mail (spec L §7.3): STARTTLS
/// (EnableSsl), solo testo, mittente "WonderFlix". Nel registro il server
/// e l'errore, mai la password e mai un indirizzo.
/// </summary>
public sealed class SmtpMailSender(IAccountSettings settings, ILogger<SmtpMailSender> logger) : IMailSender
{
    /// <summary>Il nome del mittente.</summary>
    public const string FromName = "WonderFlix";

    /// <summary>Attesa massima di un invio.</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(15);

    // Gli indirizzi nei messaggi del server SMTP ("<mario@example.com> unknown").
    private static readonly Regex Address = new(@"[^\s<>""']+@[^\s<>""']+", RegexOptions.CultureInvariant);

    /// <summary>Attesa massima; i test la accorciano.</summary>
    internal TimeSpan Timeout { get; init; } = DefaultTimeout;

    /// <summary>Chi spedisce davvero; i test lo sostituiscono.</summary>
    internal Func<SmtpServer, MailMessage, CancellationToken, Task> Transport { get; init; } = SendWithSmtpAsync;

    public async Task<SendOutcome> SendAsync(string to, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsEmailConfigured())
        {
            return SendOutcome.Failed;
        }

        var server = new SmtpServer(settings.SmtpHost, settings.SmtpPort, settings.SmtpUser, settings.SmtpPassword);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            using var mail = new MailMessage(new MailAddress(settings.MailFrom, FromName), new MailAddress(to))
            {
                Subject = message.Subject,
                Body = message.Text,
                IsBodyHtml = false,
                SubjectEncoding = Encoding.UTF8,
                BodyEncoding = Encoding.UTF8,
            };
            await Transport(server, mail, timeout.Token).ConfigureAwait(false);
            return SendOutcome.Sent;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("Email non inviata: nessuna risposta da {Host}:{Port} in {Timeout}", server.Host, server.Port, Timeout);
            return SendOutcome.Failed;
        }
        catch (Exception ex) when (ex is SmtpException or FormatException or ArgumentException or InvalidOperationException or IOException)
        {
            logger.LogWarning(
                "Email non inviata tramite {Host}:{Port}: {Error} {Message} {Inner}",
                server.Host,
                server.Port,
                ex.GetType().Name,
                Redact(ex.Message),
                Redact(ex.InnerException?.Message));
            return SendOutcome.Failed;
        }
    }

    private static string Redact(string? text) => text is null ? string.Empty : Address.Replace(text, "[email]");

    private static async Task SendWithSmtpAsync(SmtpServer server, MailMessage mail, CancellationToken cancellationToken)
    {
        using var client = new SmtpClient(server.Host, server.Port)
        {
            EnableSsl = true,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Credentials = new NetworkCredential(server.User, server.Password),
        };
        await client.SendMailAsync(mail, cancellationToken).ConfigureAwait(false);
    }
}
```

Crea `Account/AccountSender.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>L'ultimo errore d'invio di un canale (spec L §7.3), senza il destinatario.</summary>
public sealed record SendError(DateTimeOffset At, string Code);

/// <summary>I codici di <see cref="SendError"/>.</summary>
public static class SendErrorCodes
{
    public const string DmClosed = "DmClosed";

    public const string SendFailed = "SendFailed";

    /// <summary>Discord ha rifiutato token o server.</summary>
    public const string Invalid = "Invalid";
}

/// <summary>
/// Manda i messaggi ai contatti, canale per canale, e ricorda l'ultimo
/// errore di ogni canale per lo stato dell'admin; un invio riuscito lo
/// cancella. Un canale spento non manda niente e non conta come errore.
/// Sicuro tra thread.
/// </summary>
public sealed class AccountSender(IDiscordSender discord, IMailSender mail, IAccountSettings settings, TimeProvider time)
{
    private readonly Lock _lock = new();
    private readonly Dictionary<AccountChannel, SendError> _lastErrors = [];

    /// <summary>Un messaggio a un contatto: l'id Discord o l'indirizzo email.</summary>
    public async Task<SendOutcome> SendAsync(
        AccountChannel channel, string target, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsConfigured(channel))
        {
            return SendOutcome.Failed;
        }

        var outcome = channel == AccountChannel.Discord
            ? await discord.SendDmAsync(target, message.Text, cancellationToken).ConfigureAwait(false)
            : await mail.SendAsync(target, message, cancellationToken).ConfigureAwait(false);
        Record(channel, outcome);
        return outcome;
    }

    /// <summary>I contatti dell'utente sui canali configurati, nell'ordine Discord, Email.</summary>
    public IReadOnlyList<(AccountChannel Channel, string Target)> Targets(UserContacts contacts)
    {
        var targets = new List<(AccountChannel, string)>();
        if (contacts.Discord is { } discordContact && settings.IsDiscordConfigured())
        {
            targets.Add((AccountChannel.Discord, discordContact.Id));
        }

        if (contacts.Email is { } emailContact && settings.IsEmailConfigured())
        {
            targets.Add((AccountChannel.Email, emailContact.Address));
        }

        return targets;
    }

    /// <summary>Un messaggio a tutti i contatti dell'utente; restituisce i canali dove è arrivato.</summary>
    public async Task<IReadOnlyList<AccountChannel>> SendToAllAsync(
        UserContacts contacts, AccountMessage message, CancellationToken cancellationToken)
    {
        var sent = new List<AccountChannel>();
        foreach (var (channel, target) in Targets(contacts))
        {
            if (await SendAsync(channel, target, message, cancellationToken).ConfigureAwait(false) == SendOutcome.Sent)
            {
                sent.Add(channel);
            }
        }

        return sent;
    }

    /// <summary>L'ultimo errore del canale; null se l'ultimo invio è riuscito o non ce ne sono stati.</summary>
    public SendError? LastError(AccountChannel channel)
    {
        lock (_lock)
        {
            return _lastErrors.GetValueOrDefault(channel);
        }
    }

    /// <summary>Registra l'esito di un invio (o di una ricerca) fatto altrove.</summary>
    public void Record(AccountChannel channel, SendOutcome outcome)
    {
        lock (_lock)
        {
            if (outcome == SendOutcome.Sent)
            {
                _lastErrors.Remove(channel);
            }
            else
            {
                _lastErrors[channel] = new SendError(
                    time.GetUtcNow(), outcome == SendOutcome.DmClosed ? SendErrorCodes.DmClosed : SendErrorCodes.SendFailed);
            }
        }
    }

    /// <summary>Discord ha rifiutato token o server.</summary>
    public void RecordInvalid(AccountChannel channel)
    {
        lock (_lock)
        {
            _lastErrors[channel] = new SendError(time.GetUtcNow(), SendErrorCodes.Invalid);
        }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): SMTP mail sender and account message delivery"
```

## Gruppo C — cassetta e collegamento

### Task 8: il promemoria nella cassetta

**Files:**
- Modify: `Protocol/InboxDtos.cs`, `Hub/InboxBook.cs`, `Hub/InboxService.cs`
- Create (test): `InboxContactReminderTests.cs`

- [ ] **Step 1: i test**

Crea `InboxContactReminderTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxContactReminderTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 9, 12, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly UserRef _mario;

    public InboxContactReminderTests()
    {
        _mario = _server.AddUser("Mario");
        _server.AddSession("s1", _mario);
        _inbox = TestInbox.Create(_server, _folder, _time);
    }

    public void Dispose() => _folder.Dispose();

    [Fact]
    public async Task ThereIsAlwaysOneReminder()
    {
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);
        _time.Advance(TimeSpan.FromDays(14));
        await _inbox.AddContactReminderAsync(_mario.Id, ["Email"]);

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.ContactReminder, entry.Type);
        Assert.Equal(new[] { "Email" }, entry.Channels);
        Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);
        Assert.False(entry.Read);
        Assert.Equal(2, _server.SentTo("s1").Count);
    }

    [Fact]
    public async Task RemovingTakesOnlyTheReminders()
    {
        await _inbox.AnnounceAsync("ciao");
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord"]);

        await _inbox.RemoveContactRemindersAsync(_mario.Id);

        Assert.Equal(InboxEntryTypes.Announcement, Assert.Single(_inbox.Get(_mario.Id).Entries).Type);
        var notices = _server.SentTo("s1").Count;
        await _inbox.RemoveContactRemindersAsync(_mario.Id);
        Assert.Equal(notices, _server.SentTo("s1").Count);
    }

    [Fact]
    public async Task TheChannelsSurviveTheFile()
    {
        await _inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);

        var reloaded = TestInbox.Create(_server, _folder, _time);

        Assert.Equal(new[] { "Discord", "Email" }, Assert.Single(reloaded.Get(_mario.Id).Entries).Channels);
        Assert.Contains("\"Channels\"", File.ReadAllText(_folder.InboxFile));
    }

    [Fact]
    public void RemoveTypeInTheBook()
    {
        var book = new InboxBook();
        var userId = Guid.NewGuid();
        book.Add(userId, new InboxEntry { Type = InboxEntryTypes.ContactReminder });
        book.Add(userId, new InboxEntry { Type = InboxEntryTypes.Announcement, Text = "ciao" });

        Assert.True(book.RemoveType(userId, InboxEntryTypes.ContactReminder));
        Assert.False(book.RemoveType(userId, InboxEntryTypes.ContactReminder));
        Assert.False(book.RemoveType(Guid.NewGuid(), InboxEntryTypes.ContactReminder));
        Assert.Equal(InboxEntryTypes.Announcement, Assert.Single(book.List(userId)).Type);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~InboxContactReminderTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

In `Protocol/InboxDtos.cs`, in `InboxEntryTypes` dopo `RequestPending`:

```csharp
    /// <summary>"Proteggi il tuo account" (spec L §7.7), a chi non ha contatti per il recupero.</summary>
    public const string ContactReminder = "ContactReminder";
```

e in `InboxEntry`, dopo `RequesterName`:

```csharp
    /// <summary>ContactReminder: i canali che si possono collegare ("Discord", "Email").</summary>
    [JsonPropertyName("Channels")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<string>? Channels { get; set; }
```

Il commento di `Copy()` diventa: "Copia superficiale: le liste (NewTitles, Seasons, Channels) non si cambiano mai dopo la creazione."

In `Hub/InboxBook.cs`, dopo `Remove`:

```csharp
    /// <summary>Toglie le voci di questo tipo; true se ce n'erano.</summary>
    public bool RemoveType(Guid userId, string type) =>
        _users.TryGetValue(userId, out var inbox)
        && inbox.Entries.RemoveAll(e => e.Type == type) > 0;
```

In `Hub/InboxService.cs`, dopo `AddRequestPendingAsync`:

```csharp
    /// <summary>
    /// Il promemoria "Proteggi il tuo account" (spec L §7.7): sostituisce
    /// quello di prima, quindi ce n'è sempre uno solo. Non lancia: un errore
    /// finisce nel log.
    /// </summary>
    public async Task AddContactReminderAsync(Guid userId, IReadOnlyList<string> channels)
    {
        try
        {
            var now = time.GetUtcNow();
            lock (_lock)
            {
                Book.RemoveType(userId, InboxEntryTypes.ContactReminder);
                Book.Add(userId, new InboxEntry
                {
                    Type = InboxEntryTypes.ContactReminder,
                    CreatedAt = now,
                    Channels = channels.ToList(),
                });
                Persist();
            }

            await NotifyAsync([userId]).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Promemoria dei contatti non creato per {UserId}", userId);
        }
    }

    /// <summary>Toglie i promemoria dei contatti (un contatto è stato verificato). Non lancia.</summary>
    public async Task RemoveContactRemindersAsync(Guid userId)
    {
        try
        {
            await ChangeAsync(userId, book => book.RemoveType(userId, InboxEntryTypes.ContactReminder)).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Promemoria dei contatti non tolti per {UserId}", userId);
        }
    }
```

Il commento della classe `InboxService` prende anche "i promemoria dei contatti (spec L)".

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera (`InboxServiceTests`, `InboxBookTests` e `ProtocolJsonTests` restano verdi).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): contact reminder entries in the inbox"
```

### Task 9: collegare i contatti

**Files:**
- Create: `Account/AccountError.cs`, `Protocol/AccountDtos.cs`, `Account/ContactLinking.cs`, `Api/AccountErrors.cs`, `Api/AccountController.cs`
- Modify (test): `AccountRig.cs`
- Create (test): `ActionResults.cs`, `ContactLinkingTests.cs`, `AccountControllerTests.cs`

- [ ] **Step 1: i test**

In `AccountRig.cs`, prima di `Dispose`, aggiungi (con `using Microsoft.Extensions.Logging.Abstractions;` in cima):

```csharp
    public ContactLinking Linking() =>
        new(Contacts, Codes, Limiter, Discord, Sender, Settings, Inbox, Time, NullLogger<ContactLinking>.Instance);
```

Crea `ActionResults.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Stato e codice d'errore delle risposte dei controller Account.</summary>
internal static class ActionResults
{
    public static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    public static string Code(IActionResult result) =>
        Assert.IsType<AccountErrorDto>(Assert.IsType<ObjectResult>(result).Value).Code;

    public static void AssertError(int status, string code, IActionResult? result)
    {
        Assert.NotNull(result);
        Assert.Equal(status, Status(result));
        Assert.Equal(code, Code(result));
    }
}
```

Crea `ContactLinkingTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactLinkingTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly AccountRig _rig = new();
    private readonly ContactLinking _linking;
    private readonly UserRef _mario;

    public ContactLinkingTests()
    {
        _mario = _rig.Server.AddUser("Mario");
        _rig.Discord.Members["mario"] = new DiscordMember("222222222222222222", "mario");
        _linking = _rig.Linking();
    }

    public void Dispose() => _rig.Dispose();

    [Fact]
    public async Task DiscordIsLinkedWithTheCodeSentByDirectMessage()
    {
        var start = await _linking.StartAsync(_mario.Id, AccountChannel.Discord, " @Mario ", "it", Ct);

        Assert.Null(start.Error);
        Assert.Equal(_rig.Time.GetUtcNow() + CodeBook.Lifetime, start.Value!.ExpiresAt);
        Assert.Equal(new[] { "Mario" }, _rig.Discord.Searches);
        Assert.Contains("collegare questo account", _rig.Discord.Sent.Single().Text);
        var code = _rig.Discord.LastCode("222222222222222222");

        var confirm = await _linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, code);

        Assert.Null(confirm.Error);
        Assert.Equal(new DiscordContactDto("mario", _rig.Time.GetUtcNow()), confirm.Value!.Discord);
        Assert.Null(confirm.Value.Email);
        Assert.Equal("222222222222222222", _rig.Contacts.Get(_mario.Id).Discord!.Id);
        // Il codice vale una volta.
        Assert.Equal(AccountError.InvalidCode, (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, code)).Error);
    }

    [Fact]
    public async Task TheEmailIsLinkedAsWritten()
    {
        Assert.Null((await _linking.StartAsync(_mario.Id, AccountChannel.Email, " Mario@Example.com ", "en", Ct)).Error);

        var sent = Assert.Single(_rig.Mail.Sent);
        Assert.Equal("Mario@Example.com", sent.To);
        Assert.Equal("WonderFlix — code", sent.Message.Subject);
        var confirm = await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, _rig.Mail.LastCode("Mario@Example.com"));
        Assert.Equal("Mario@Example.com", confirm.Value!.Email!.Address);
    }

    [Fact]
    public async Task AWrongCodeIsInvalidAndTheChannelsAreSeparate()
    {
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "it", Ct);
        var code = _rig.Mail.LastCode("mario@example.com");

        Assert.Equal(AccountError.InvalidCode, (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Discord, code)).Error);
        Assert.Equal(
            AccountError.InvalidCode,
            (await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, code == "000000" ? "111111" : "000000")).Error);
        Assert.Null((await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, code)).Error);
    }

    [Fact]
    public async Task AChannelThatIsOffComesFirst()
    {
        _rig.Settings.DiscordBotToken = string.Empty;

        Assert.Equal(AccountError.ChannelOff, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "x", "it", Ct)).Error);

        Assert.Empty(_rig.Discord.Searches);
        Assert.False(_linking.Get(_mario.Id).Channels.Discord);
        Assert.True(_linking.Get(_mario.Id).Channels.Email);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("m")]
    [InlineData("nome con spazi")]
    [InlineData("mario#1234")]
    [InlineData("abcdefghijklmnopqrstuvwxyz1234567")]
    public async Task DiscordNamesMustLookLikeDiscordNames(string? name) =>
        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, name, "it", Ct)).Error);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("mario")]
    [InlineData("mario@localhost")]
    [InlineData("Mario <mario@example.com>")]
    [InlineData("mario@example.com.")]
    public async Task EmailsMustBeJustAnAddress(string? address) =>
        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, address, "it", Ct)).Error);

    [Fact]
    public async Task TooLongEmailsAreInvalid()
    {
        var address = new string('a', ContactLinking.MaxEmailLength - "@example.com".Length + 1) + "@example.com";

        Assert.Equal(AccountError.InvalidTarget, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, address, "it", Ct)).Error);
    }

    [Fact]
    public async Task UnknownMembersAndSearchErrors()
    {
        Assert.Equal(AccountError.MemberNotFound, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "luigi", "it", Ct)).Error);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        _rig.Discord.SearchFails = true;

        Assert.Equal(AccountError.SendFailed, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "it", Ct)).Error);
        Assert.Equal("SendFailed", _rig.Sender.LastError(AccountChannel.Discord)!.Code);
    }

    [Fact]
    public async Task AFailedSendDropsTheCode()
    {
        _rig.Discord.Outcomes["222222222222222222"] = SendOutcome.DmClosed;
        Assert.Equal(AccountError.DmClosed, (await _linking.StartAsync(_mario.Id, AccountChannel.Discord, "mario", "it", Ct)).Error);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        Assert.Equal(AccountError.SendFailed, (await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "it", Ct)).Error);

        Assert.Equal(0, _rig.Codes.Count);
    }

    [Fact]
    public async Task OneStartAMinuteFiveAnHour()
    {
        Assert.Null((await Start()).Error);
        Assert.Equal(AccountError.RateLimited, (await Start()).Error);
        for (var i = 0; i < 4; i++)
        {
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
            Assert.Null((await Start()).Error);
        }

        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(AccountError.RateLimited, (await Start()).Error);

        Task<AccountResult<LinkStartResponse>> Start() =>
            _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "it", Ct);
    }

    [Fact]
    public async Task ConfirmingRemovesTheReminders()
    {
        await _rig.Inbox.AddContactReminderAsync(_mario.Id, ["Discord", "Email"]);
        await _linking.StartAsync(_mario.Id, AccountChannel.Email, "mario@example.com", "it", Ct);

        await _linking.ConfirmAsync(_mario.Id, AccountChannel.Email, _rig.Mail.LastCode("mario@example.com"));

        Assert.Empty(_rig.Inbox.Get(_mario.Id).Entries);
    }

    [Fact]
    public void UnlinkRemovesOneChannel()
    {
        var luigi = _rig.UserWithContacts("Luigi");

        _linking.Unlink(luigi.Id, AccountChannel.Discord);

        var contacts = _linking.Get(luigi.Id);
        Assert.Null(contacts.Discord);
        Assert.Equal("luigi@example.com", contacts.Email!.Address);
    }

    [Fact]
    public async Task WithoutAUserNothingIsLinked() =>
        Assert.Equal(AccountError.Invalid, (await _linking.StartAsync(Guid.Empty, AccountChannel.Email, "mario@example.com", "it", Ct)).Error);
}
```

Crea `AccountControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Database.Implementations.Entities;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountControllerTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly User _mario = new("mario", "provider", "reset");

    public AccountControllerTests()
    {
        _rig.Server.Users[_mario.Id] = new UserRef(_mario.Id, "mario", true, true);
        _rig.Discord.Members["mario"] = new DiscordMember("222222222222222222", "mario");
    }

    public void Dispose() => _rig.Dispose();

    private AccountController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _mario, IsAuthenticated = true };
        return new AccountController(new FakeAuthorizationContext(auth), _rig.Linking())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public async Task StartAnswers202ThenConfirmGivesTheContacts()
    {
        var controller = Controller();

        var start = (await controller.Start("discord", new LinkStartRequest { Target = "mario", Language = "it" })).Result!;

        Assert.Equal(202, ActionResults.Status(start));
        Assert.IsType<LinkStartResponse>(Assert.IsType<ObjectResult>(start).Value);
        var confirm = await controller.Confirm("Discord", new LinkConfirmRequest { Code = _rig.Discord.LastCode("222222222222222222") });
        Assert.Equal("mario", confirm.Value!.Discord!.Name);
        Assert.Equal("mario", (await controller.GetContacts()).Value!.Discord!.Name);
        Assert.Equal(204, ActionResults.Status(await controller.Unlink("DISCORD")));
        Assert.Null((await controller.GetContacts()).Value!.Discord);
    }

    [Fact]
    public async Task ErrorsHaveAStatusAndACode()
    {
        var controller = Controller();

        ActionResults.AssertError(400, "Invalid", (await controller.Start("Telegram", new LinkStartRequest { Target = "mario" })).Result);
        ActionResults.AssertError(400, "Invalid", (await controller.Start("Discord", null)).Result);
        ActionResults.AssertError(400, "InvalidTarget", (await controller.Start("Email", new LinkStartRequest { Target = "mario" })).Result);
        ActionResults.AssertError(400, "MemberNotFound", (await controller.Start("Discord", new LinkStartRequest { Target = "luigi" })).Result);
        ActionResults.AssertError(429, "RateLimited", (await controller.Start("Discord", new LinkStartRequest { Target = "mario" })).Result);
        ActionResults.AssertError(400, "InvalidCode", (await controller.Confirm("Discord", new LinkConfirmRequest { Code = "000000" })).Result);
        ActionResults.AssertError(400, "Invalid", (await controller.Confirm("Discord", null)).Result);
        ActionResults.AssertError(400, "Invalid", await controller.Unlink("0"));
        _rig.Settings.SmtpHost = string.Empty;
        ActionResults.AssertError(503, "ChannelOff", (await controller.Start("Email", new LinkStartRequest { Target = "mario@example.com" })).Result);
    }

    [Fact]
    public async Task SendErrorsAre409And502()
    {
        _rig.Discord.Outcomes["222222222222222222"] = SendOutcome.DmClosed;
        ActionResults.AssertError(409, "DmClosed", (await Controller().Start("Discord", new LinkStartRequest { Target = "mario" })).Result);
        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;

        ActionResults.AssertError(502, "SendFailed", (await Controller().Start("Email", new LinkStartRequest { Target = "mario@example.com" })).Result);
    }

    [Theory]
    [InlineData(AccountError.ChannelOff, 503)]
    [InlineData(AccountError.RateLimited, 429)]
    [InlineData(AccountError.InvalidTarget, 400)]
    [InlineData(AccountError.MemberNotFound, 400)]
    [InlineData(AccountError.DmClosed, 409)]
    [InlineData(AccountError.SendFailed, 502)]
    [InlineData(AccountError.InvalidCode, 400)]
    [InlineData(AccountError.WeakPassword, 400)]
    [InlineData(AccountError.NotAllowed, 403)]
    [InlineData(AccountError.NoContacts, 409)]
    [InlineData(AccountError.UnknownUser, 400)]
    [InlineData(AccountError.Invalid, 400)]
    public void EveryErrorHasItsStatusAndNever404(AccountError error, int status)
    {
        var result = AccountErrors.Result(error);

        Assert.Equal(status, result.StatusCode);
        Assert.Equal(error.ToString(), Assert.IsType<AccountErrorDto>(result.Value).Code);
    }

    [Fact]
    public void ContactsAreForEveryAuthenticatedUser()
    {
        var authorize = Assert.Single(typeof(AccountController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Equal("WonderFlixWatchParty/Account", typeof(AccountController).GetCustomAttribute<RouteAttribute>()!.Template);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ContactLinkingTests|FullyQualifiedName~AccountControllerTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/AccountError.cs`:

```csharp
namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Gli errori dei contatti e del recupero (spec L §7.6): il nome è il Code della risposta.</summary>
public enum AccountError
{
    ChannelOff,
    RateLimited,
    InvalidTarget,
    MemberNotFound,
    DmClosed,
    SendFailed,
    InvalidCode,
    WeakPassword,
    NotAllowed,
    NoContacts,
    UnknownUser,
    Invalid,
}

/// <summary>Esito di un'operazione: un valore oppure un errore.</summary>
public sealed record AccountResult<T>(AccountError? Error, T? Value)
    where T : class
{
    public static AccountResult<T> Ok(T value) => new(null, value);

    public static AccountResult<T> Fail(AccountError error) => new(error, null);
}
```

Crea `Protocol/AccountDtos.cs`:

```csharp
using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Corpo degli errori degli endpoint Account (spec L §7.6).</summary>
public sealed record AccountErrorDto(
    [property: JsonPropertyName("Code")] string Code);

/// <summary>I canali configurati sul server.</summary>
public sealed record AccountChannelsDto(
    [property: JsonPropertyName("Discord")] bool Discord,
    [property: JsonPropertyName("Email")] bool Email);

/// <summary>Il proprio Discord verificato.</summary>
public sealed record DiscordContactDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("VerifiedAt")] DateTimeOffset VerifiedAt);

/// <summary>La propria email verificata, intera.</summary>
public sealed record EmailContactDto(
    [property: JsonPropertyName("Address")] string Address,
    [property: JsonPropertyName("VerifiedAt")] DateTimeOffset VerifiedAt);

/// <summary>Risposta di GET Account/Contacts e di Confirm.</summary>
public sealed record ContactsResponse(
    [property: JsonPropertyName("Channels")] AccountChannelsDto Channels,
    [property: JsonPropertyName("Discord")] DiscordContactDto? Discord,
    [property: JsonPropertyName("Email")] EmailContactDto? Email);

/// <summary>Corpo di POST Account/Contacts/{canale}/Start: nome utente Discord o email.</summary>
public sealed class LinkStartRequest
{
    [JsonPropertyName("Target")]
    public string? Target { get; set; }

    /// <summary>"it" o "en": la lingua del messaggio.</summary>
    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Risposta di Start: quando scade il codice.</summary>
public sealed record LinkStartResponse(
    [property: JsonPropertyName("ExpiresAt")] DateTimeOffset ExpiresAt);

/// <summary>Corpo di POST Account/Contacts/{canale}/Confirm.</summary>
public sealed class LinkConfirmRequest
{
    [JsonPropertyName("Code")]
    public string? Code { get; set; }
}

/// <summary>Corpo di POST Account/Recovery/Start.</summary>
public sealed class RecoveryStartRequest
{
    [JsonPropertyName("Username")]
    public string? Username { get; set; }

    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Corpo di POST Account/Recovery/Complete.</summary>
public sealed class RecoveryCompleteRequest
{
    [JsonPropertyName("Username")]
    public string? Username { get; set; }

    [JsonPropertyName("Code")]
    public string? Code { get; set; }

    [JsonPropertyName("NewPassword")]
    public string? NewPassword { get; set; }

    /// <summary>La lingua dell'avviso "password cambiata".</summary>
    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Corpo con la sola lingua (codice mandato dall'admin).</summary>
public sealed class AccountLanguageRequest
{
    [JsonPropertyName("Language")]
    public string? Language { get; set; }
}

/// <summary>Corpo di POST Account/Admin/Test: nome Discord ed email facoltativi.</summary>
public sealed class AccountTestRequest
{
    [JsonPropertyName("Language")]
    public string? Language { get; set; }

    /// <summary>Un nome utente Discord a cui mandare la prova; vuoto: il Discord dell'admin.</summary>
    [JsonPropertyName("Discord")]
    public string? Discord { get; set; }

    /// <summary>Un indirizzo a cui mandare la prova; vuoto: l'email dell'admin.</summary>
    [JsonPropertyName("Email")]
    public string? Email { get; set; }
}

/// <summary>Il Discord di un utente nell'elenco dell'admin.</summary>
public sealed record AdminDiscordDto(
    [property: JsonPropertyName("Name")] string Name);

/// <summary>L'email di un utente nell'elenco dell'admin, mascherata.</summary>
public sealed record AdminEmailDto(
    [property: JsonPropertyName("Masked")] string Masked);

/// <summary>Un utente in GET Account/Admin/Users.</summary>
public sealed record AdminUserDto(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("IsAdmin")] bool IsAdmin,
    [property: JsonPropertyName("Enabled")] bool Enabled,
    [property: JsonPropertyName("Discord")] AdminDiscordDto? Discord,
    [property: JsonPropertyName("Email")] AdminEmailDto? Email,
    [property: JsonPropertyName("LastReminderAt")] DateTimeOffset? LastReminderAt);

/// <summary>Risposta di POST Account/Admin/Users/{id}/Recovery: i canali dove è arrivato il codice.</summary>
public sealed record AdminRecoveryResponse(
    [property: JsonPropertyName("Channels")] IReadOnlyList<string> Channels);

/// <summary>L'ultimo errore d'invio di un canale.</summary>
public sealed record SendErrorDto(
    [property: JsonPropertyName("At")] DateTimeOffset At,
    [property: JsonPropertyName("Code")] string Code);

/// <summary>Lo stato di un canale.</summary>
public sealed record ChannelStatusDto(
    [property: JsonPropertyName("Configured")] bool Configured,
    [property: JsonPropertyName("LastError")] SendErrorDto? LastError);

/// <summary>Risposta di GET Account/Admin/Status.</summary>
public sealed record AccountStatusResponse(
    [property: JsonPropertyName("Discord")] ChannelStatusDto Discord,
    [property: JsonPropertyName("Email")] ChannelStatusDto Email,
    [property: JsonPropertyName("WithContacts")] int WithContacts,
    [property: JsonPropertyName("Users")] int Users,
    [property: JsonPropertyName("ReminderDays")] int ReminderDays);

/// <summary>Risposta di POST Account/Admin/Test: l'esito per canale (vedi AccountTestCodes).</summary>
public sealed record AccountTestResponse(
    [property: JsonPropertyName("Discord")] string Discord,
    [property: JsonPropertyName("Email")] string Email);
```

Crea `Account/ContactLinking.cs`:

```csharp
using System.Net.Mail;
using System.Text.RegularExpressions;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// Collegare e verificare i contatti di un utente (spec L §7.4): il nome
/// Discord o l'email, un codice mandato lì, il codice scritto nell'app.
/// Nel file entrano solo i contatti verificati.
/// </summary>
public sealed class ContactLinking(
    ContactRegistry contacts,
    CodeBook codes,
    RateLimiter limiter,
    IDiscordSender discord,
    AccountSender sender,
    IAccountSettings settings,
    InboxService inbox,
    TimeProvider time,
    ILogger<ContactLinking> logger)
{
    /// <summary>Lunghezza massima di un indirizzo email.</summary>
    public const int MaxEmailLength = 254;

    // I nomi utente Discord di oggi: da 2 a 32 lettere, cifre, "_" e ".".
    private static readonly Regex DiscordName = new("^[A-Za-z0-9_.]{2,32}$", RegexOptions.CultureInvariant);

    /// <summary>I propri contatti e i canali del server.</summary>
    public ContactsResponse Get(Guid userId)
    {
        var mine = contacts.Get(userId);
        return new ContactsResponse(
            new AccountChannelsDto(settings.IsDiscordConfigured(), settings.IsEmailConfigured()),
            mine.Discord is { } discordContact ? new DiscordContactDto(discordContact.Name, discordContact.VerifiedAt) : null,
            mine.Email is { } emailContact ? new EmailContactDto(emailContact.Address, emailContact.VerifiedAt) : null);
    }

    /// <summary>
    /// Manda il codice per collegare un contatto. Nell'ordine: canale spento,
    /// contatto scritto male, limiti, membro Discord che non c'è, invio.
    /// Un invio non riuscito toglie il codice.
    /// </summary>
    public async Task<AccountResult<LinkStartResponse>> StartAsync(
        Guid userId, AccountChannel channel, string? target, string? language, CancellationToken cancellationToken)
    {
        if (userId == Guid.Empty)
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.Invalid);
        }

        if (!settings.IsConfigured(channel))
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.ChannelOff);
        }

        var cleaned = channel == AccountChannel.Discord ? CleanDiscordName(target) : CleanEmail(target);
        if (cleaned is null)
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.InvalidTarget);
        }

        var key = userId.ToString("N");
        if (!limiter.TryAcquire(key, LimitTypes.LinkStartMinute) || !limiter.TryAcquire(key, LimitTypes.LinkStartHour))
        {
            return AccountResult<LinkStartResponse>.Fail(AccountError.RateLimited);
        }

        PendingContact pending;
        if (channel == AccountChannel.Discord)
        {
            var lookup = await discord.FindMemberAsync(cleaned, cancellationToken).ConfigureAwait(false);
            if (lookup.Failed)
            {
                sender.Record(AccountChannel.Discord, SendOutcome.Failed);
                return AccountResult<LinkStartResponse>.Fail(AccountError.SendFailed);
            }

            if (lookup.Member is null)
            {
                return AccountResult<LinkStartResponse>.Fail(AccountError.MemberNotFound);
            }

            pending = new PendingContact(lookup.Member.Id, lookup.Member.Username);
        }
        else
        {
            pending = new PendingContact(cleaned, null);
        }

        var purpose = PurposeFor(channel);
        var (code, expiresAt) = codes.Issue(userId, purpose, pending);
        var outcome = await sender.SendAsync(channel, pending.Value, AccountMessages.Verify(language, code), cancellationToken)
            .ConfigureAwait(false);
        if (outcome != SendOutcome.Sent)
        {
            codes.Discard(userId, purpose);
            return AccountResult<LinkStartResponse>.Fail(
                outcome == SendOutcome.DmClosed ? AccountError.DmClosed : AccountError.SendFailed);
        }

        logger.LogInformation("Codice per collegare {Channel} mandato all'utente {UserId}", channel, userId);
        return AccountResult<LinkStartResponse>.Ok(new LinkStartResponse(expiresAt));
    }

    /// <summary>Con il codice giusto il contatto è verificato e i promemoria spariscono.</summary>
    public async Task<AccountResult<ContactsResponse>> ConfirmAsync(Guid userId, AccountChannel channel, string? code)
    {
        var check = codes.Check(userId, PurposeFor(channel), code);
        if (!check.Ok || check.Pending is null)
        {
            return AccountResult<ContactsResponse>.Fail(AccountError.InvalidCode);
        }

        var now = time.GetUtcNow();
        if (channel == AccountChannel.Discord)
        {
            contacts.SetDiscord(userId, new DiscordContact
            {
                Id = check.Pending.Value,
                Name = check.Pending.Name ?? string.Empty,
                VerifiedAt = now,
            });
        }
        else
        {
            contacts.SetEmail(userId, new EmailContact { Address = check.Pending.Value, VerifiedAt = now });
        }

        await inbox.RemoveContactRemindersAsync(userId).ConfigureAwait(false);
        logger.LogInformation("{Channel} collegato all'utente {UserId}", channel, userId);
        return AccountResult<ContactsResponse>.Ok(Get(userId));
    }

    /// <summary>Toglie il contatto di un canale.</summary>
    public void Unlink(Guid userId, AccountChannel channel) => contacts.Remove(userId, channel);

    /// <summary>Il nome Discord senza spazi ai lati né "@" iniziale; null se non sembra un nome Discord.</summary>
    internal static string? CleanDiscordName(string? raw)
    {
        var name = raw?.Trim().TrimStart('@');
        return name is not null && DiscordName.IsMatch(name) ? name : null;
    }

    /// <summary>Solo l'indirizzo, com'è scritto, con un dominio che ha un punto; null altrimenti.</summary>
    internal static string? CleanEmail(string? raw)
    {
        var address = raw?.Trim();
        if (string.IsNullOrEmpty(address) || address.Length > MaxEmailLength)
        {
            return null;
        }

        if (!MailAddress.TryCreate(address, out var parsed)
            || parsed.Address != address
            || !string.IsNullOrEmpty(parsed.DisplayName))
        {
            return null;
        }

        var domain = address[(address.LastIndexOf('@') + 1)..];
        return domain.Contains('.', StringComparison.Ordinal) && !domain.StartsWith('.') && !domain.EndsWith('.')
            ? address
            : null;
    }

    private static CodePurpose PurposeFor(AccountChannel channel) =>
        channel == AccountChannel.Discord ? CodePurpose.VerifyDiscord : CodePurpose.VerifyEmail;
}
```

Crea `Api/AccountErrors.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Da errore a stato HTTP e {Code} (spec L §7.6). Mai 404: per l'app un 404
/// vuol dire plugin senza la funzione.
/// </summary>
internal static class AccountErrors
{
    public static ObjectResult Result(AccountError error)
    {
        var status = error switch
        {
            AccountError.ChannelOff => StatusCodes.Status503ServiceUnavailable,
            AccountError.RateLimited => StatusCodes.Status429TooManyRequests,
            AccountError.DmClosed or AccountError.NoContacts => StatusCodes.Status409Conflict,
            AccountError.SendFailed => StatusCodes.Status502BadGateway,
            AccountError.NotAllowed => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status400BadRequest,
        };
        return new ObjectResult(new AccountErrorDto(error.ToString())) { StatusCode = status };
    }
}
```

Crea `Api/AccountController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// I contatti per il recupero di chi chiama (spec L §7.6), per ogni utente
/// autenticato. Il canale è una stringa nella rotta: uno sconosciuto è
/// 400 Invalid, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Account")]
[Authorize]
[Produces(MediaTypeNames.Application.Json)]
public class AccountController(IAuthorizationContext authorizationContext, ContactLinking linking) : ControllerBase
{
    /// <summary>I propri contatti verificati e i canali del server.</summary>
    [HttpGet("Contacts")]
    public async Task<ActionResult<ContactsResponse>> GetContacts() =>
        linking.Get(await CallerAsync().ConfigureAwait(false));

    /// <summary>Manda il codice al contatto scritto; 202 con la scadenza.</summary>
    [HttpPost("Contacts/{channel}/Start")]
    public async Task<ActionResult<LinkStartResponse>> Start([FromRoute] string channel, [FromBody] LinkStartRequest? request)
    {
        if (!AccountChannels.TryParse(channel, out var parsed) || request is null)
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        var result = await linking.StartAsync(
                await CallerAsync().ConfigureAwait(false), parsed, request.Target, request.Language, HttpContext.RequestAborted)
            .ConfigureAwait(false);
        if (result.Error is { } error)
        {
            return AccountErrors.Result(error);
        }

        return StatusCode(StatusCodes.Status202Accepted, result.Value);
    }

    /// <summary>Il codice ricevuto: il contatto è verificato.</summary>
    [HttpPost("Contacts/{channel}/Confirm")]
    public async Task<ActionResult<ContactsResponse>> Confirm([FromRoute] string channel, [FromBody] LinkConfirmRequest? request)
    {
        if (!AccountChannels.TryParse(channel, out var parsed) || request is null)
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        var result = await linking.ConfirmAsync(await CallerAsync().ConfigureAwait(false), parsed, request.Code)
            .ConfigureAwait(false);
        if (result.Error is { } error)
        {
            return AccountErrors.Result(error);
        }

        return result.Value!;
    }

    /// <summary>Toglie il contatto del canale; 204 anche se non c'era.</summary>
    [HttpDelete("Contacts/{channel}")]
    public async Task<ActionResult> Unlink([FromRoute] string channel)
    {
        if (!AccountChannels.TryParse(channel, out var parsed))
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        linking.Unlink(await CallerAsync().ConfigureAwait(false), parsed);
        return NoContent();
    }

    private async Task<Guid> CallerAsync() =>
        (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): link and verify recovery contacts"
```

## Gruppo D — recupero, admin e promemoria

### Task 10: il recupero della password

**Files:**
- Create: `Account/PasswordRecovery.cs`, `Api/RecoveryController.cs`
- Modify (test): `FakeAccountChannels.cs`, `AccountRig.cs`
- Create (test): `PasswordRecoveryTests.cs`, `RecoveryControllerTests.cs`

- [ ] **Step 1: i test**

In fondo a `FakeAccountChannels.cs` aggiungi:

```csharp
/// <summary>Il cambio di password finto: registra le chiamate, o lancia Error.</summary>
internal sealed class FakePasswordReset : IPasswordReset
{
    public List<(Guid UserId, string Password)> Calls { get; } = [];

    public Exception? Error { get; set; }

    public Task ResetAsync(Guid userId, string newPassword)
    {
        if (Error is not null)
        {
            throw Error;
        }

        Calls.Add((userId, newPassword));
        return Task.CompletedTask;
    }
}
```

In `AccountRig.cs` aggiungi la proprietà, dopo `Mail`:

```csharp
    public FakePasswordReset Passwords { get; } = new();
```

e il metodo, dopo `Linking()`:

```csharp
    public PasswordRecovery Recovery() =>
        new(Server, Contacts, Codes, Limiter, Sender, Passwords, NullLogger<PasswordRecovery>.Instance);
```

Crea `PasswordRecoveryTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PasswordRecoveryTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly AccountRig _rig = new();
    private readonly PasswordRecovery _recovery;
    private readonly UserRef _mario;

    public PasswordRecoveryTests()
    {
        _mario = _rig.UserWithContacts("Mario");
        _recovery = _rig.Recovery();
    }

    public void Dispose() => _rig.Dispose();

    private string DiscordId(UserRef user) => _rig.Contacts.Get(user.Id).Discord!.Id;

    // Chiede il codice scrivendo il nome così, aspetta l'invio e lo legge dal DM.
    private async Task<string> CodeFor(UserRef user, string typed)
    {
        var start = _recovery.Start(typed, "it");
        Assert.Null(start.Error);
        await start.Sending;
        return _rig.Discord.LastCode(DiscordId(user));
    }

    [Fact]
    public async Task TheCodeGoesToEveryContact()
    {
        var code = await CodeFor(_mario, " MARIO ");

        Assert.Contains("«Mario»", _rig.Discord.Sent.Single().Text);
        Assert.Equal(code, _rig.Mail.LastCode("mario@example.com"));
    }

    [Theory]
    [InlineData("nessuno")]
    [InlineData("Peach")]
    [InlineData("Daisy")]
    [InlineData("Luigi")]
    public async Task StartLooksTheSameForEveryone(string name)
    {
        _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.UserWithContacts("Daisy", enabled: false);
        _rig.Server.AddUser("Luigi");

        var start = _recovery.Start(name, "it");

        Assert.Null(start.Error);
        await start.Sending;
        Assert.Empty(_rig.Discord.Sent);
        Assert.Empty(_rig.Mail.Sent);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ANameIsNeeded(string? name) =>
        Assert.Equal(AccountError.Invalid, _recovery.Start(name, "it").Error);

    [Fact]
    public void TooLongNamesAreInvalid() =>
        Assert.Equal(AccountError.Invalid, _recovery.Start(new string('a', PasswordRecovery.MaxUsernameLength + 1), "it").Error);

    [Fact]
    public async Task OneStartAMinuteAndFiveAnHourForEachName()
    {
        await CodeFor(_mario, "mario");
        Assert.Equal(AccountError.RateLimited, _recovery.Start("MARIO", "it").Error);
        Assert.Null(_recovery.Start("luigi", "it").Error);
        for (var i = 0; i < 4; i++)
        {
            _rig.Time.Advance(TimeSpan.FromMinutes(1));
            Assert.Null(_recovery.Start("mario", "it").Error);
        }

        _rig.Time.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(AccountError.RateLimited, _recovery.Start("mario", "it").Error);
    }

    [Fact]
    public void ThirtyStartsAnHourForEveryone()
    {
        for (var i = 0; i < 30; i++)
        {
            Assert.Null(_recovery.Start("nome" + i, "it").Error);
        }

        Assert.Equal(AccountError.RateLimited, _recovery.Start("altro", "it").Error);
    }

    [Fact]
    public async Task TheCodeChangesThePasswordAndTheUserIsWarned()
    {
        var code = await CodeFor(_mario, "mario");

        var complete = await _recovery.CompleteAsync("Mario", code, "nuova-password", "it");

        Assert.Null(complete.Error);
        await complete.Notifying;
        Assert.Equal(new[] { (_mario.Id, "nuova-password") }, _rig.Passwords.Calls);
        Assert.Contains("è stata cambiata", _rig.Discord.Sent.Last().Text);
        Assert.Equal("WonderFlix — password cambiata", _rig.Mail.Sent.Last().Message.Subject);
        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("mario", code, "altra-password", "it")).Error);
    }

    [Fact]
    public async Task AWrongLengthPasswordDoesNotUseAnAttempt()
    {
        var code = await CodeFor(_mario, "mario");
        for (var i = 0; i < CodeBook.MaxAttempts; i++)
        {
            Assert.Equal(AccountError.WeakPassword, (await _recovery.CompleteAsync("mario", code, "12345", "it")).Error);
        }

        Assert.Equal(
            AccountError.WeakPassword,
            (await _recovery.CompleteAsync("mario", code, new string('x', PasswordRecovery.MaxPasswordLength + 1), "it")).Error);
        var complete = await _recovery.CompleteAsync("mario", code, "123456", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;
    }

    [Fact]
    public async Task OnlyEligibleUsersCanUseACode()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);
        var (code, _) = _rig.Codes.Issue(peach.Id, CodePurpose.Recovery);

        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("peach", code, "nuova-password", "it")).Error);
        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("nessuno", "123456", "nuova-password", "it")).Error);
        Assert.Empty(_rig.Passwords.Calls);
    }

    [Fact]
    public async Task TenFailuresStopTheNameForAnHour()
    {
        for (var i = 0; i < 10; i++)
        {
            Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("mario", "000000", "nuova-password", "it")).Error);
        }

        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        Assert.Equal(AccountError.RateLimited, (await _recovery.CompleteAsync("MARIO", code, "nuova-password", "it")).Error);
        Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("luigi", "000000", "nuova-password", "it")).Error);

        _rig.Time.Advance(TimeSpan.FromHours(1));
        (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        var complete = await _recovery.CompleteAsync("mario", code, "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;
    }

    [Fact]
    public async Task TwentyFailuresStopTheNameForADay()
    {
        for (var hour = 0; hour < 2; hour++)
        {
            for (var i = 0; i < 10; i++)
            {
                Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("mario", "000000", "nuova-password", "it")).Error);
            }

            _rig.Time.Advance(TimeSpan.FromHours(1));
        }

        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        Assert.Equal(AccountError.RateLimited, (await _recovery.CompleteAsync("mario", code, "nuova-password", "it")).Error);

        // Un giorno dopo il primo errore il nome torna libero.
        _rig.Time.Advance(TimeSpan.FromHours(22));
        (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        var complete = await _recovery.CompleteAsync("mario", code, "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;
    }

    [Fact]
    public async Task AHundredFailuresStopEveryone()
    {
        for (var i = 0; i < 100; i++)
        {
            Assert.Equal(AccountError.InvalidCode, (await _recovery.CompleteAsync("nome" + i, "000000", "nuova-password", "it")).Error);
        }

        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);
        Assert.Equal(AccountError.RateLimited, (await _recovery.CompleteAsync("mario", code, "nuova-password", "it")).Error);
    }

    [Fact]
    public async Task WithoutAnySendTheCodeIsDropped()
    {
        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.DmClosed;
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;

        var start = _recovery.Start("mario", "it");
        await start.Sending;

        Assert.Equal(0, _rig.Codes.Count);
    }

    [Fact]
    public async Task AJellyfinErrorComesOut()
    {
        var code = await CodeFor(_mario, "mario");
        _rig.Passwords.Error = new InvalidOperationException("database");

        await Assert.ThrowsAsync<InvalidOperationException>(() => _recovery.CompleteAsync("mario", code, "nuova-password", "it"));
    }

    [Fact]
    public async Task TheAdminSendsTheCodeAndGetsTheTruth()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);
        var daisy = _rig.UserWithContacts("Daisy", enabled: false);
        var luigi = _rig.Server.AddUser("Luigi");

        Assert.Equal(AccountError.UnknownUser, (await _recovery.SendForAdminAsync(Guid.NewGuid(), "it", Ct)).Error);
        Assert.Equal(AccountError.NotAllowed, (await _recovery.SendForAdminAsync(peach.Id, "it", Ct)).Error);
        Assert.Equal(AccountError.NotAllowed, (await _recovery.SendForAdminAsync(daisy.Id, "it", Ct)).Error);
        Assert.Equal(AccountError.NoContacts, (await _recovery.SendForAdminAsync(luigi.Id, "it", Ct)).Error);
        Assert.Equal(new[] { "Discord", "Email" }, (await _recovery.SendForAdminAsync(_mario.Id, "it", Ct)).Value!.Channels);

        // Nessun limite per l'admin: subito di nuovo.
        _rig.Mail.Outcomes["mario@example.com"] = SendOutcome.Failed;
        Assert.Equal(new[] { "Discord" }, (await _recovery.SendForAdminAsync(_mario.Id, "it", Ct)).Value!.Channels);
        var complete = await _recovery.CompleteAsync("mario", _rig.Discord.LastCode(DiscordId(_mario)), "nuova-password", "it");
        Assert.Null(complete.Error);
        await complete.Notifying;

        _rig.Discord.Outcomes[DiscordId(_mario)] = SendOutcome.Failed;
        Assert.Equal(AccountError.SendFailed, (await _recovery.SendForAdminAsync(_mario.Id, "it", Ct)).Error);
        Assert.Equal(0, _rig.Codes.Count);
    }
}
```

Crea `RecoveryControllerTests.cs`:

```csharp
using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RecoveryControllerTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly UserRef _mario;
    private readonly RecoveryController _controller;

    public RecoveryControllerTests()
    {
        _mario = _rig.UserWithContacts("Mario");
        _controller = new RecoveryController(_rig.Recovery())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    public void Dispose() => _rig.Dispose();

    [Fact]
    public void RecoveryNeedsNoAccess()
    {
        Assert.NotNull(typeof(RecoveryController).GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.Empty(typeof(RecoveryController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(
            "WonderFlixWatchParty/Account/Recovery",
            typeof(RecoveryController).GetCustomAttribute<RouteAttribute>()!.Template);
    }

    [Fact]
    public void StartAnswers202ThenTooMany()
    {
        Assert.Equal(202, ActionResults.Status(_controller.Start(new RecoveryStartRequest { Username = "nessuno", Language = "it" })));
        ActionResults.AssertError(429, "RateLimited", _controller.Start(new RecoveryStartRequest { Username = "nessuno" }));
        ActionResults.AssertError(400, "Invalid", _controller.Start(null));
        ActionResults.AssertError(400, "Invalid", _controller.Start(new RecoveryStartRequest { Username = " " }));
    }

    [Fact]
    public async Task CompleteAnswers204OrTheError()
    {
        ActionResults.AssertError(400, "Invalid", await _controller.Complete(null));
        ActionResults.AssertError(
            400, "WeakPassword",
            await _controller.Complete(new RecoveryCompleteRequest { Username = "mario", Code = "000000", NewPassword = "123" }));
        ActionResults.AssertError(
            400, "InvalidCode",
            await _controller.Complete(new RecoveryCompleteRequest { Username = "mario", Code = "000000", NewPassword = "nuova-password" }));
        var (code, _) = _rig.Codes.Issue(_mario.Id, CodePurpose.Recovery);

        var done = await _controller.Complete(new RecoveryCompleteRequest
        {
            Username = "mario",
            Code = code,
            NewPassword = "nuova-password",
            Language = "it",
        });

        Assert.Equal(204, ActionResults.Status(done));
        Assert.Equal(new[] { (_mario.Id, "nuova-password") }, _rig.Passwords.Calls);
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~PasswordRecoveryTests|FullyQualifiedName~RecoveryControllerTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/PasswordRecovery.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Esito di <see cref="PasswordRecovery.Start"/>: subito. L'invio continua in Sending (i test lo aspettano).</summary>
public sealed record RecoveryStartResult(AccountError? Error, Task Sending);

/// <summary>Esito di <see cref="PasswordRecovery.CompleteAsync"/>. L'avviso "password cambiata" continua in Notifying.</summary>
public sealed record RecoveryCompleteResult(AccountError? Error, Task Notifying);

/// <summary>
/// Il recupero della password senza accesso (spec L §7.4, §8): un codice ai
/// contatti verificati, poi la password nuova con il codice. Le risposte
/// non dicono se un account esiste. Non vale per gli admin né per gli
/// utenti disattivati. Anche il codice mandato dall'admin passa da qui.
/// </summary>
public sealed class PasswordRecovery(
    IUserDirectory users,
    ContactRegistry contacts,
    CodeBook codes,
    RateLimiter limiter,
    AccountSender sender,
    IPasswordReset passwords,
    ILogger<PasswordRecovery> logger)
{
    /// <summary>Lunghezza minima di una password nuova (spec L §8).</summary>
    public const int MinPasswordLength = 6;

    /// <summary>Lunghezza massima di una password nuova.</summary>
    public const int MaxPasswordLength = 1024;

    /// <summary>Lunghezza massima di un nome utente scritto.</summary>
    public const int MaxUsernameLength = 256;

    /// <summary>La chiave dei limiti di tutti.</summary>
    internal const string EveryoneKey = "*";

    /// <summary>
    /// Chiede un codice. Risponde subito, uguale per tutti (tranne i limiti,
    /// che contano il nome scritto, esista o no). Dopo, in background: se
    /// l'utente può usare il recupero e ha contatti, il codice va a tutti.
    /// </summary>
    public RecoveryStartResult Start(string? username, string? language)
    {
        var name = Trimmed(username);
        if (name is null)
        {
            return new RecoveryStartResult(AccountError.Invalid, Task.CompletedTask);
        }

        var key = Key(name);
        if (!limiter.TryAcquire(EveryoneKey, LimitTypes.RecoveryStartGlobal)
            || !limiter.TryAcquire(key, LimitTypes.RecoveryStartMinute)
            || !limiter.TryAcquire(key, LimitTypes.RecoveryStartHour))
        {
            return new RecoveryStartResult(AccountError.RateLimited, Task.CompletedTask);
        }

        // Utente, contatti e invio non si vedono dal tempo di risposta.
        return new RecoveryStartResult(null, Task.Run(() => SendCodeAsync(name, language)));
    }

    /// <summary>
    /// La password nuova con il codice. Una password troppo corta o troppo
    /// lunga non consuma tentativi. Utente sconosciuto, non ammesso o codice
    /// sbagliato: InvalidCode, e conta per i limiti. Un errore di Jellyfin
    /// esce come eccezione.
    /// </summary>
    public async Task<RecoveryCompleteResult> CompleteAsync(string? username, string? code, string? newPassword, string? language)
    {
        var name = Trimmed(username);
        if (name is null)
        {
            return Done(AccountError.Invalid);
        }

        var key = Key(name);
        if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryFailGlobal)
            || limiter.IsLimited(key, LimitTypes.RecoveryFail)
            || limiter.IsLimited(key, LimitTypes.RecoveryFailDay))
        {
            return Done(AccountError.RateLimited);
        }

        if (newPassword is null || newPassword.Length < MinPasswordLength || newPassword.Length > MaxPasswordLength)
        {
            return Done(AccountError.WeakPassword);
        }

        var user = Eligible(name);
        var check = user is null ? CodeCheck.Wrong : codes.Check(user.Id, CodePurpose.Recovery, code);
        if (user is null || !check.Ok)
        {
            limiter.TryAcquire(EveryoneKey, LimitTypes.RecoveryFailGlobal);
            limiter.TryAcquire(key, LimitTypes.RecoveryFail);
            limiter.TryAcquire(key, LimitTypes.RecoveryFailDay);

            // Nel log si vede quando qualcuno prova a indovinare i codici: una volta
            // sola, quando il limite scatta (dopo si risponde 429 prima di arrivare qui),
            // e mai il testo scritto, che potrebbe essere un'email o contenere a capo.
            if (limiter.IsLimited(key, LimitTypes.RecoveryFail) || limiter.IsLimited(key, LimitTypes.RecoveryFailDay))
            {
                logger.LogWarning(
                    "Recupero della password fermato dai limiti per {Who}",
                    user is null ? "un nome che non è un utente" : user.Id.ToString("N"));
            }

            if (limiter.IsLimited(EveryoneKey, LimitTypes.RecoveryFailGlobal))
            {
                logger.LogWarning("Recupero della password fermato per tutti: troppi codici sbagliati oggi");
            }

            return Done(AccountError.InvalidCode);
        }

        try
        {
            await passwords.ResetAsync(user.Id, newPassword).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Password di {UserId} non cambiata", user.Id);
            throw;
        }

        logger.LogInformation("Password di {UserId} cambiata con il codice di recupero", user.Id);

        // L'avviso non trattiene la risposta.
        return new RecoveryCompleteResult(null, Task.Run(() => NotifyChangedAsync(user, language)));
    }

    /// <summary>
    /// Il codice mandato dall'admin (spec L §7.4): la risposta dice com'è
    /// andata, e non ci sono i limiti del recupero.
    /// </summary>
    public async Task<AccountResult<AdminRecoveryResponse>> SendForAdminAsync(
        Guid userId, string? language, CancellationToken cancellationToken)
    {
        var user = users.GetUser(userId);
        if (user is null)
        {
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.UnknownUser);
        }

        if (user.IsAdmin || !user.Enabled)
        {
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.NotAllowed);
        }

        var mine = contacts.Get(userId);
        if (sender.Targets(mine).Count == 0)
        {
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.NoContacts);
        }

        var (code, _) = codes.Issue(userId, CodePurpose.Recovery);
        var sent = await sender.SendToAllAsync(mine, AccountMessages.Recovery(language, user.Name, code), cancellationToken)
            .ConfigureAwait(false);
        if (sent.Count == 0)
        {
            codes.Discard(userId, CodePurpose.Recovery);
            return AccountResult<AdminRecoveryResponse>.Fail(AccountError.SendFailed);
        }

        logger.LogInformation("Codice di recupero di {UserId} mandato dall'admin su {Count} canali", userId, sent.Count);
        return AccountResult<AdminRecoveryResponse>.Ok(new AdminRecoveryResponse(sent.Select(c => c.Name()).ToList()));
    }

    private async Task SendCodeAsync(string name, string? language)
    {
        try
        {
            var user = Eligible(name);
            if (user is null)
            {
                return;
            }

            var mine = contacts.Get(user.Id);
            if (sender.Targets(mine).Count == 0)
            {
                return;
            }

            var (code, _) = codes.Issue(user.Id, CodePurpose.Recovery);
            var sent = await sender.SendToAllAsync(mine, AccountMessages.Recovery(language, user.Name, code), CancellationToken.None)
                .ConfigureAwait(false);
            if (sent.Count == 0)
            {
                codes.Discard(user.Id, CodePurpose.Recovery);
                logger.LogWarning("Codice di recupero di {UserId} non mandato: nessun canale ha funzionato", user.Id);
                return;
            }

            logger.LogInformation("Codice di recupero di {UserId} mandato su {Count} canali", user.Id, sent.Count);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Codice di recupero non mandato");
        }
    }

    private async Task NotifyChangedAsync(UserRef user, string? language)
    {
        try
        {
            await sender.SendToAllAsync(contacts.Get(user.Id), AccountMessages.PasswordChanged(language, user.Name), CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Avviso del cambio password non mandato a {UserId}", user.Id);
        }
    }

    // L'utente può usare il recupero: esiste, è attivo e non è admin. Il nome senza maiuscole, come Jellyfin.
    private UserRef? Eligible(string name) =>
        users.GetUsers().FirstOrDefault(u => string.Equals(u.Name, name, StringComparison.OrdinalIgnoreCase))
            is { Enabled: true, IsAdmin: false } user
            ? user
            : null;

    private static string? Trimmed(string? raw)
    {
        var name = raw?.Trim();
        return string.IsNullOrEmpty(name) || name.Length > MaxUsernameLength ? null : name;
    }

    private static string Key(string name) => name.ToLowerInvariant();

    private static RecoveryCompleteResult Done(AccountError error) => new(error, Task.CompletedTask);
}
```

Crea `Api/RecoveryController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il recupero della password (spec L §7.6): senza accesso, come il webhook
/// di Seerr. Un controller a parte, perché un [Authorize] sulla classe non
/// si allarga con un attributo sul metodo.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Account/Recovery")]
[AllowAnonymous]
[Produces(MediaTypeNames.Application.Json)]
public class RecoveryController(PasswordRecovery recovery) : ControllerBase
{
    /// <summary>Chiede un codice; 202 per tutti, che l'account esista o no.</summary>
    [HttpPost("Start")]
    public ActionResult Start([FromBody] RecoveryStartRequest? request)
    {
        var result = recovery.Start(request?.Username, request?.Language);
        return result.Error is { } error
            ? AccountErrors.Result(error)
            : StatusCode(StatusCodes.Status202Accepted);
    }

    /// <summary>La password nuova con il codice; 204.</summary>
    [HttpPost("Complete")]
    public async Task<ActionResult> Complete([FromBody] RecoveryCompleteRequest? request)
    {
        if (request is null)
        {
            return AccountErrors.Result(AccountError.Invalid);
        }

        var result = await recovery.CompleteAsync(request.Username, request.Code, request.NewPassword, request.Language)
            .ConfigureAwait(false);
        return result.Error is { } error ? AccountErrors.Result(error) : NoContent();
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): password recovery with codes"
```

### Task 11: le funzioni dell'admin

**Files:**
- Create: `Account/AccountAdmin.cs`, `Api/AccountAdminController.cs`
- Modify (test): `AccountRig.cs`
- Create (test): `AccountAdminTests.cs`, `AccountAdminControllerTests.cs`

- [ ] **Step 1: i test**

In `AccountRig.cs`, dopo `Recovery()`:

```csharp
    public AccountAdmin Admin() => new(Server, Contacts, Sender, Discord, Settings);
```

Crea `AccountAdminTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountAdminTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly AccountRig _rig = new();
    private readonly AccountAdmin _admin;

    public AccountAdminTests() => _admin = _rig.Admin();

    public void Dispose() => _rig.Dispose();

    [Fact]
    public void UsersAreListedByNameWithMaskedEmails()
    {
        var mario = _rig.UserWithContacts("mario");
        _rig.Server.AddUser("Peach", isAdmin: true);
        var bowser = _rig.Server.AddUser("Bowser", enabled: false);
        _rig.Contacts.MarkReminded(bowser.Id, _rig.Time.GetUtcNow());

        var users = _admin.Users();

        Assert.Equal(new[] { "Bowser", "mario", "Peach" }, users.Select(u => u.Name));
        Assert.Equal(
            new AdminUserDto(bowser.Id.ToString("N"), "Bowser", false, false, null, null, _rig.Time.GetUtcNow()),
            users[0]);
        Assert.Equal(mario.Id.ToString("N"), users[1].Id);
        Assert.Equal(new AdminDiscordDto("mario"), users[1].Discord);
        Assert.Equal(new AdminEmailDto("m•••@example.com"), users[1].Email);
        Assert.True(users[2].IsAdmin);
    }

    [Theory]
    [InlineData("mario@example.com", "m•••@example.com")]
    [InlineData("a@b.it", "a•••@b.it")]
    [InlineData("strano", "•••")]
    [InlineData("@example.com", "•••")]
    public void EmailsAreMasked(string address, string masked) =>
        Assert.Equal(masked, AccountAdmin.MaskEmail(address));

    [Fact]
    public void UnlinkRemovesEveryContactOfAKnownUser()
    {
        var mario = _rig.UserWithContacts("Mario");

        Assert.Equal(AccountError.UnknownUser, _admin.Unlink(Guid.NewGuid()));
        Assert.Null(_admin.Unlink(mario.Id));
        Assert.False(_rig.Contacts.Get(mario.Id).HasContact);
    }

    [Fact]
    public async Task StatusCountsActiveNonAdminUsersAndShowsTheLastErrors()
    {
        _rig.UserWithContacts("Mario");
        _rig.Server.AddUser("Luigi");
        _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.UserWithContacts("Daisy", enabled: false);
        _rig.Settings.ContactReminderDays = 7;
        _rig.Discord.Outcomes["999999999999999999"] = SendOutcome.DmClosed;
        await _rig.Sender.SendAsync(AccountChannel.Discord, "999999999999999999", AccountMessages.Test("it"), Ct);
        _rig.Settings.SmtpHost = string.Empty;

        var status = _admin.Status();

        Assert.Equal(new ChannelStatusDto(true, new SendErrorDto(_rig.Time.GetUtcNow(), "DmClosed")), status.Discord);
        Assert.Equal(new ChannelStatusDto(false, null), status.Email);
        Assert.Equal(1, status.WithContacts);
        Assert.Equal(2, status.Users);
        Assert.Equal(7, status.ReminderDays);
    }

    [Fact]
    public async Task TheTestGoesToTheAdminsOwnContacts()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);

        Assert.Equal(new AccountTestResponse("Ok", "Ok"), await _admin.TestAsync(peach.Id, "it", null, null, Ct));

        Assert.Contains("Messaggio di prova", _rig.Discord.Sent.Single().Text);
        Assert.Equal("peach@example.com", _rig.Mail.Sent.Single().To);
    }

    [Fact]
    public async Task WithoutContactsTheTestStillChecksDiscord()
    {
        Assert.Equal(new AccountTestResponse("NoContact", "NoContact"), await _admin.TestAsync(Guid.Empty, "it", null, " ", Ct));

        _rig.Discord.Check = DiscordCheck.Invalid;
        Assert.Equal("Invalid", (await _admin.TestAsync(Guid.Empty, "it", null, null, Ct)).Discord);
        Assert.Equal("Invalid", _rig.Sender.LastError(AccountChannel.Discord)!.Code);

        _rig.Discord.Check = DiscordCheck.Failed;
        Assert.Equal("SendFailed", (await _admin.TestAsync(Guid.Empty, "it", null, null, Ct)).Discord);
    }

    [Fact]
    public async Task TheTestCanGoToANameAndAnAddress()
    {
        _rig.Discord.Members["davide"] = new DiscordMember("444444444444444444", "davide");

        Assert.Equal(
            new AccountTestResponse("Ok", "Ok"),
            await _admin.TestAsync(Guid.Empty, "en", "@Davide", "davide@example.com", Ct));

        Assert.Equal("444444444444444444", _rig.Discord.Sent.Single().UserId);
        Assert.Equal("WonderFlix — test", _rig.Mail.Sent.Single().Message.Subject);
        Assert.Equal(
            new AccountTestResponse("MemberNotFound", "InvalidTarget"),
            await _admin.TestAsync(Guid.Empty, "it", "luigi", "luigi", Ct));
        Assert.Equal("MemberNotFound", (await _admin.TestAsync(Guid.Empty, "it", "nome con spazi", null, Ct)).Discord);
        _rig.Discord.SearchFails = true;
        Assert.Equal("SendFailed", (await _admin.TestAsync(Guid.Empty, "it", "davide", null, Ct)).Discord);
    }

    [Fact]
    public async Task TheTestSaysWhatWentWrong()
    {
        var peach = _rig.UserWithContacts("Peach", isAdmin: true);
        _rig.Discord.Outcomes[_rig.Contacts.Get(peach.Id).Discord!.Id] = SendOutcome.DmClosed;
        _rig.Mail.Outcomes["peach@example.com"] = SendOutcome.Failed;

        Assert.Equal(new AccountTestResponse("DmClosed", "SendFailed"), await _admin.TestAsync(peach.Id, "it", null, null, Ct));

        _rig.Settings.DiscordBotToken = string.Empty;
        _rig.Settings.MailFrom = string.Empty;
        Assert.Equal(new AccountTestResponse("NotConfigured", "NotConfigured"), await _admin.TestAsync(peach.Id, "it", null, null, Ct));
    }
}
```

Crea `AccountAdminControllerTests.cs`:

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
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class AccountAdminControllerTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly User _peach = new("peach", "provider", "reset");

    public AccountAdminControllerTests() =>
        _rig.Server.Users[_peach.Id] = new UserRef(_peach.Id, "peach", true, true, IsAdmin: true);

    public void Dispose() => _rig.Dispose();

    private AccountAdminController Controller()
    {
        var auth = new AuthorizationInfo { DeviceId = "d", Client = "WonderFlix", User = _peach, IsAuthenticated = true };
        return new AccountAdminController(new FakeAuthorizationContext(auth), _rig.Admin(), _rig.Recovery())
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };
    }

    [Fact]
    public void OnlyForAdmins()
    {
        var authorize = Assert.Single(typeof(AccountAdminController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Equal(Policies.RequiresElevation, authorize.Policy);
        Assert.Equal(
            "WonderFlixWatchParty/Account/Admin",
            typeof(AccountAdminController).GetCustomAttribute<RouteAttribute>()!.Template);
    }

    [Fact]
    public async Task UsersStatusAndTest()
    {
        _rig.UserWithContacts("Mario");
        var controller = Controller();

        Assert.Equal(new[] { "Mario", "peach" }, controller.GetUsers().Value!.Select(u => u.Name));
        Assert.Equal(1, controller.Status().Value!.WithContacts);
        Assert.Equal(new AccountTestResponse("NoContact", "NoContact"), (await controller.Test(new AccountTestRequest { Language = "it" })).Value);
        Assert.Equal(new AccountTestResponse("NoContact", "NoContact"), (await controller.Test(null)).Value);
    }

    [Fact]
    public async Task RecoveryAndUnlinkByUserId()
    {
        var mario = _rig.UserWithContacts("Mario");
        var controller = Controller();

        Assert.Equal(
            new[] { "Discord", "Email" },
            (await controller.SendRecovery(mario.Id.ToString("N"), new AccountLanguageRequest { Language = "it" })).Value!.Channels);
        ActionResults.AssertError(403, "NotAllowed", (await controller.SendRecovery(_peach.Id.ToString(), null)).Result);
        ActionResults.AssertError(400, "UnknownUser", (await controller.SendRecovery("non-un-id", null)).Result);
        ActionResults.AssertError(400, "UnknownUser", (await controller.SendRecovery(Guid.NewGuid().ToString(), null)).Result);
        Assert.Equal(204, ActionResults.Status(controller.Unlink(mario.Id.ToString())));
        ActionResults.AssertError(409, "NoContacts", (await controller.SendRecovery(mario.Id.ToString(), null)).Result);
        ActionResults.AssertError(400, "UnknownUser", controller.Unlink("non-un-id"));
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~AccountAdminTests|FullyQualifiedName~AccountAdminControllerTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/AccountAdmin.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Gli esiti di POST Account/Admin/Test, per canale.</summary>
public static class AccountTestCodes
{
    public const string Ok = "Ok";
    public const string NotConfigured = "NotConfigured";

    /// <summary>Né il contatto dell'admin né uno scritto nella richiesta.</summary>
    public const string NoContact = "NoContact";

    /// <summary>Discord ha rifiutato token o server.</summary>
    public const string Invalid = "Invalid";

    public const string MemberNotFound = "MemberNotFound";
    public const string InvalidTarget = "InvalidTarget";
    public const string DmClosed = "DmClosed";
    public const string SendFailed = "SendFailed";
}

/// <summary>
/// Le funzioni dell'admin sul recupero (spec L §7.4): gli utenti con i loro
/// contatti (email mascherate), lo scollegamento, lo stato dei canali e la
/// prova d'invio. Il codice mandato dall'admin sta in PasswordRecovery.
/// </summary>
public sealed class AccountAdmin(
    IUserDirectory users,
    ContactRegistry contacts,
    AccountSender sender,
    IDiscordSender discord,
    IAccountSettings settings)
{
    /// <summary>Tutti gli utenti per nome, con i loro contatti.</summary>
    public List<AdminUserDto> Users()
    {
        var all = contacts.All();
        return users.GetUsers()
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .Select(u =>
            {
                var mine = all.GetValueOrDefault(u.Id);
                return new AdminUserDto(
                    u.Id.ToString("N"),
                    u.Name,
                    u.IsAdmin,
                    u.Enabled,
                    mine?.Discord is { } discordContact ? new AdminDiscordDto(discordContact.Name) : null,
                    mine?.Email is { } emailContact ? new AdminEmailDto(MaskEmail(emailContact.Address)) : null,
                    mine?.LastReminderAt);
            })
            .ToList();
    }

    /// <summary>Toglie tutti i contatti di un utente; UnknownUser se Jellyfin non lo conosce.</summary>
    public AccountError? Unlink(Guid userId)
    {
        if (users.GetUser(userId) is null)
        {
            return AccountError.UnknownUser;
        }

        contacts.RemoveAll(userId);
        return null;
    }

    /// <summary>I canali e quanti utenti attivi e non admin hanno almeno un contatto.</summary>
    public AccountStatusResponse Status()
    {
        var all = contacts.All();
        var eligible = users.GetUsers().Where(u => u.Enabled && !u.IsAdmin).ToList();
        return new AccountStatusResponse(
            Channel(AccountChannel.Discord),
            Channel(AccountChannel.Email),
            eligible.Count(u => all.TryGetValue(u.Id, out var mine) && mine.HasContact),
            eligible.Count,
            settings.ContactReminderDays);
    }

    /// <summary>
    /// Un messaggio di prova per canale: al nome Discord e all'indirizzo
    /// scritti, oppure ai contatti dell'admin. Discord controlla prima token
    /// e server.
    /// </summary>
    public async Task<AccountTestResponse> TestAsync(
        Guid adminId, string? language, string? discordName, string? email, CancellationToken cancellationToken)
    {
        var mine = contacts.Get(adminId);
        var message = AccountMessages.Test(language);

        // In parallelo: l'attesa è quella del canale più lento, non la somma (l'app aspetta al massimo 30 s).
        var discordTest = TestDiscordAsync(mine, discordName, message, cancellationToken);
        var emailTest = TestEmailAsync(mine, email, message, cancellationToken);
        await Task.WhenAll(discordTest, emailTest).ConfigureAwait(false);
        return new AccountTestResponse(await discordTest.ConfigureAwait(false), await emailTest.ConfigureAwait(false));
    }

    /// <summary>"m•••@example.com": prima lettera, puntini, dominio intero.</summary>
    internal static string MaskEmail(string address)
    {
        var at = address.LastIndexOf('@');
        return at <= 0 ? "•••" : address[..1] + "•••" + address[at..];
    }

    private async Task<string> TestDiscordAsync(
        UserContacts mine, string? name, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsDiscordConfigured())
        {
            return AccountTestCodes.NotConfigured;
        }

        var check = await discord.CheckAsync(cancellationToken).ConfigureAwait(false);
        if (check == DiscordCheck.Invalid)
        {
            sender.RecordInvalid(AccountChannel.Discord);
            return AccountTestCodes.Invalid;
        }

        if (check == DiscordCheck.Failed)
        {
            sender.Record(AccountChannel.Discord, SendOutcome.Failed);
            return AccountTestCodes.SendFailed;
        }

        var target = mine.Discord?.Id;
        if (!string.IsNullOrWhiteSpace(name))
        {
            var cleaned = ContactLinking.CleanDiscordName(name);
            if (cleaned is null)
            {
                return AccountTestCodes.MemberNotFound;
            }

            var lookup = await discord.FindMemberAsync(cleaned, cancellationToken).ConfigureAwait(false);
            if (lookup.Failed)
            {
                return AccountTestCodes.SendFailed;
            }

            if (lookup.Member is null)
            {
                return AccountTestCodes.MemberNotFound;
            }

            target = lookup.Member.Id;
        }

        return target is null
            ? AccountTestCodes.NoContact
            : Outcome(await sender.SendAsync(AccountChannel.Discord, target, message, cancellationToken).ConfigureAwait(false));
    }

    private async Task<string> TestEmailAsync(
        UserContacts mine, string? email, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsEmailConfigured())
        {
            return AccountTestCodes.NotConfigured;
        }

        var target = mine.Email?.Address;
        if (!string.IsNullOrWhiteSpace(email))
        {
            target = ContactLinking.CleanEmail(email);
            if (target is null)
            {
                return AccountTestCodes.InvalidTarget;
            }
        }

        return target is null
            ? AccountTestCodes.NoContact
            : Outcome(await sender.SendAsync(AccountChannel.Email, target, message, cancellationToken).ConfigureAwait(false));
    }

    private static string Outcome(SendOutcome outcome) => outcome switch
    {
        SendOutcome.Sent => AccountTestCodes.Ok,
        SendOutcome.DmClosed => AccountTestCodes.DmClosed,
        _ => AccountTestCodes.SendFailed,
    };

    // Di un canale spento non si mostra l'ultimo errore: è di quando era acceso.
    private ChannelStatusDto Channel(AccountChannel channel)
    {
        var configured = settings.IsConfigured(channel);
        return new ChannelStatusDto(
            configured,
            configured && sender.LastError(channel) is { } error ? new SendErrorDto(error.At, error.Code) : null);
    }
}
```

Crea `Api/AccountAdminController.cs`:

```csharp
using System.Net.Mime;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using MediaBrowser.Common.Api;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Il recupero visto dall'admin (spec L §7.6): utenti, codice, scollegamento,
/// stato e prova. L'id dell'utente è una stringa nella rotta: uno non
/// valido o sconosciuto è 400 UnknownUser, mai 404.
/// </summary>
[ApiController]
[Route("WonderFlixWatchParty/Account/Admin")]
[Authorize(Policy = Policies.RequiresElevation)]
[Produces(MediaTypeNames.Application.Json)]
public class AccountAdminController(
    IAuthorizationContext authorizationContext,
    AccountAdmin admin,
    PasswordRecovery recovery) : ControllerBase
{
    [HttpGet("Users")]
    public ActionResult<List<AdminUserDto>> GetUsers() => admin.Users();

    /// <summary>Manda un codice di recupero all'utente; la risposta dice dove è arrivato.</summary>
    [HttpPost("Users/{userId}/Recovery")]
    public async Task<ActionResult<AdminRecoveryResponse>> SendRecovery(
        [FromRoute] string userId, [FromBody] AccountLanguageRequest? request)
    {
        if (!Guid.TryParse(userId, out var id))
        {
            return AccountErrors.Result(AccountError.UnknownUser);
        }

        var result = await recovery.SendForAdminAsync(id, request?.Language, HttpContext.RequestAborted).ConfigureAwait(false);
        if (result.Error is { } error)
        {
            return AccountErrors.Result(error);
        }

        return result.Value!;
    }

    /// <summary>Toglie Discord ed email dell'utente; 204.</summary>
    [HttpDelete("Users/{userId}/Contacts")]
    public ActionResult Unlink([FromRoute] string userId)
    {
        if (!Guid.TryParse(userId, out var id))
        {
            return AccountErrors.Result(AccountError.UnknownUser);
        }

        return admin.Unlink(id) is { } error ? AccountErrors.Result(error) : NoContent();
    }

    [HttpGet("Status")]
    public ActionResult<AccountStatusResponse> Status() => admin.Status();

    /// <summary>Un messaggio di prova per canale (Dashboard e app).</summary>
    [HttpPost("Test")]
    public async Task<ActionResult<AccountTestResponse>> Test([FromBody] AccountTestRequest? request)
    {
        var caller = (await authorizationContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false)).UserId;
        return await admin.TestAsync(caller, request?.Language, request?.Discord, request?.Email, HttpContext.RequestAborted)
            .ConfigureAwait(false);
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): admin endpoints for password recovery"
```

### Task 12: i promemoria

**Files:**
- Create: `Account/ContactReminders.cs`, `ContactReminderHostedService.cs`
- Modify (test): `AccountRig.cs`
- Create (test): `ContactRemindersTests.cs`, `ContactReminderHostedServiceTests.cs`

- [ ] **Step 1: i test**

In `AccountRig.cs`, dopo `Admin()`:

```csharp
    public ContactReminders Reminders() =>
        new(Server, Contacts, Inbox, Settings, Time, NullLogger<ContactReminders>.Instance);
```

Crea `ContactRemindersTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactRemindersTests : IDisposable
{
    private readonly AccountRig _rig = new();
    private readonly ContactReminders _reminders;
    private readonly UserRef _mario;

    public ContactRemindersTests()
    {
        _mario = _rig.Server.AddUser("Mario");
        _rig.UserWithContacts("Luigi");
        _rig.Server.AddUser("Peach", isAdmin: true);
        _rig.Server.AddUser("Daisy", enabled: false);
        _reminders = _rig.Reminders();
    }

    public void Dispose() => _rig.Dispose();

    private List<InboxEntry> RemindersOf(UserRef user) =>
        _rig.Inbox.Get(user.Id).Entries.Where(e => e.Type == InboxEntryTypes.ContactReminder).ToList();

    [Fact]
    public async Task OnlyActiveNonAdminUsersWithoutContacts()
    {
        Assert.Equal(1, await _reminders.RunAsync());

        var entry = Assert.Single(RemindersOf(_mario));
        Assert.Equal(new[] { "Discord", "Email" }, entry.Channels);
        Assert.Equal(_rig.Time.GetUtcNow(), _rig.Contacts.Get(_mario.Id).LastReminderAt);
        Assert.All(_rig.Server.Users.Values.Where(u => u.Id != _mario.Id), u => Assert.Empty(RemindersOf(u)));
    }

    [Fact]
    public async Task EveryNDaysAndAlwaysOne()
    {
        await _reminders.RunAsync();
        Assert.Equal(0, await _reminders.RunAsync());
        _rig.Time.Advance(TimeSpan.FromDays(14) - TimeSpan.FromMinutes(1));
        Assert.Equal(0, await _reminders.RunAsync());

        _rig.Time.Advance(TimeSpan.FromMinutes(1));

        Assert.Equal(1, await _reminders.RunAsync());
        Assert.Equal(_rig.Time.GetUtcNow(), Assert.Single(RemindersOf(_mario)).CreatedAt);
    }

    [Fact]
    public async Task OffWithZeroDaysOrWithoutChannels()
    {
        _rig.Settings.ContactReminderDays = 0;
        Assert.Equal(0, await _reminders.RunAsync());
        _rig.Settings.ContactReminderDays = 14;
        _rig.Settings.DiscordBotToken = string.Empty;
        _rig.Settings.SmtpHost = string.Empty;

        Assert.Equal(0, await _reminders.RunAsync());

        Assert.Empty(RemindersOf(_mario));
        Assert.Null(_rig.Contacts.Get(_mario.Id).LastReminderAt);
    }

    [Fact]
    public async Task OnlyTheConfiguredChannels()
    {
        _rig.Settings.SmtpHost = string.Empty;

        await _reminders.RunAsync();

        Assert.Equal(new[] { "Discord" }, Assert.Single(RemindersOf(_mario)).Channels);
    }

    [Fact]
    public async Task UsersGoneFromJellyfinLeaveTheContacts()
    {
        var ghost = Guid.NewGuid();
        _rig.Contacts.SetEmail(ghost, new EmailContact { Address = "ghost@example.com", VerifiedAt = _rig.Time.GetUtcNow() });

        await _reminders.RunAsync();

        Assert.DoesNotContain(ghost, _rig.Contacts.All().Keys);
    }

    [Fact]
    public async Task AnEmptyUserListRemovesNothing()
    {
        var luigi = _rig.Server.Users.Values.Single(u => u.Name == "Luigi");
        _rig.Server.Users.Clear();

        Assert.Equal(0, await _reminders.RunAsync());

        Assert.True(_rig.Contacts.Get(luigi.Id).HasContact);
    }
}
```

Crea `ContactReminderHostedServiceTests.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ContactReminderHostedServiceTests : IDisposable
{
    private readonly AccountRig _rig = new();

    public void Dispose() => _rig.Dispose();

    [Fact]
    public async Task FirstAfterFiveMinutesThenEveryDay()
    {
        var mario = _rig.Server.AddUser("Mario");
        _rig.Settings.ContactReminderDays = 1;
        using var service = new ContactReminderHostedService(
            _rig.Reminders(), _rig.Contacts, _rig.Time, NullLogger<ContactReminderHostedService>.Instance);
        await service.StartAsync(CancellationToken.None);

        _rig.Time.Advance(ContactReminderHostedService.FirstRun - TimeSpan.FromSeconds(1));
        Assert.Empty(_rig.Inbox.Get(mario.Id).Entries);
        _rig.Time.Advance(TimeSpan.FromSeconds(1));
        var first = Assert.Single(_rig.Inbox.Get(mario.Id).Entries);
        _rig.Time.Advance(ContactReminderHostedService.Interval);
        var second = Assert.Single(_rig.Inbox.Get(mario.Id).Entries);
        Assert.True(second.Seq > first.Seq);

        await service.StopAsync(CancellationToken.None);
        _rig.Time.Advance(ContactReminderHostedService.Interval);

        Assert.Equal(second.Seq, Assert.Single(_rig.Inbox.Get(mario.Id).Entries).Seq);
    }

    [Fact]
    public async Task AFailureEndsInTheLog()
    {
        _rig.Settings.ContactReminderDays = 1;
        var logger = new RecordingLogger<ContactReminderHostedService>();
        var failing = new ContactReminders(
            new ThrowingUsers(), _rig.Contacts, _rig.Inbox, _rig.Settings, _rig.Time, NullLogger<ContactReminders>.Instance);
        using var service = new ContactReminderHostedService(failing, _rig.Contacts, _rig.Time, logger);
        await service.StartAsync(CancellationToken.None);

        _rig.Time.Advance(ContactReminderHostedService.FirstRun);

        Assert.Contains(logger.Entries, e => e.Level == LogLevel.Warning);
        await service.StopAsync(CancellationToken.None);
    }

    private sealed class ThrowingUsers : IUserDirectory
    {
        public IReadOnlyList<UserRef> GetUsers() => throw new InvalidOperationException("database");

        public UserRef? GetUser(Guid userId) => throw new InvalidOperationException("database");
    }
}
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ContactRemindersTests|FullyQualifiedName~ContactReminderHostedServiceTests"`
Expected: errore di compilazione.

- [ ] **Step 3: il codice**

Crea `Account/ContactReminders.cs`:

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>
/// I promemoria "Proteggi il tuo account" (spec L §7.7): ogni N giorni, a chi
/// non ha contatti verificati. Solo utenti attivi e non admin, e solo con
/// almeno un canale configurato. Toglie anche i contatti degli utenti che
/// Jellyfin non ha più.
/// </summary>
public sealed class ContactReminders(
    IUserDirectory users,
    ContactRegistry contacts,
    InboxService inbox,
    IAccountSettings settings,
    TimeProvider time,
    ILogger<ContactReminders> logger)
{
    /// <summary>Manda i promemoria dovuti; restituisce quanti.</summary>
    public async Task<int> RunAsync()
    {
        var days = settings.ContactReminderDays;
        var channels = settings.Channels();
        if (days <= 0 || channels.Count == 0)
        {
            return 0;
        }

        var all = users.GetUsers();

        // Un elenco vuoto (errore momentaneo di Jellyfin) toglierebbe i contatti di tutti.
        if (all.Count > 0)
        {
            var known = all.Select(u => u.Id).ToHashSet();
            contacts.Prune(known.Contains);
        }
        var now = time.GetUtcNow();
        var every = TimeSpan.FromDays(days);
        var names = channels.Select(c => c.Name()).ToList();
        var sent = 0;
        foreach (var user in all.Where(u => u.Enabled && !u.IsAdmin))
        {
            var mine = contacts.Get(user.Id);
            if (mine.HasContact || (mine.LastReminderAt is { } last && now - last < every))
            {
                continue;
            }

            await inbox.AddContactReminderAsync(user.Id, names).ConfigureAwait(false);
            contacts.MarkReminded(user.Id, now);
            sent++;
        }

        if (sent > 0)
        {
            logger.LogInformation("Promemoria dei contatti a {Count} utenti", sent);
        }

        return sent;
    }
}
```

Crea `ContactReminderHostedService.cs` (nella root del progetto, accanto a `NewTitlesHostedService.cs`):

```csharp
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Legge i contatti all'avvio e manda i promemoria (spec L §7.7): la prima
/// volta dopo <see cref="FirstRun"/>, poi ogni <see cref="Interval"/>. Un
/// errore finisce nel log e si riprova al giro dopo.
/// </summary>
public sealed class ContactReminderHostedService(
    ContactReminders reminders,
    ContactRegistry contacts,
    TimeProvider time,
    ILogger<ContactReminderHostedService> logger) : IHostedService, IDisposable
{
    /// <summary>Il primo giro: dopo l'avvio, con Jellyfin già tranquillo.</summary>
    public static readonly TimeSpan FirstRun = TimeSpan.FromMinutes(5);

    /// <summary>Ogni quanto si guarda chi deve ricevere il promemoria.</summary>
    public static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    private ITimer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            contacts.Load();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Contatti per il recupero non caricati all'avvio");
        }

        _timer = time.CreateTimer(_ => _ = RunSafelyAsync(), null, FirstRun, Interval);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _timer?.Dispose();
        _timer = null;
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();

    private async Task RunSafelyAsync()
    {
        try
        {
            await reminders.RunAsync().ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Promemoria dei contatti non riusciti");
        }
    }
}
```

- [ ] **Step 4: i test passano**

Run: lo stesso filtro. Expected: PASS. Poi la suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): contact reminders in the inbox"
```

## Gruppo E — montaggio

### Task 13: servizi, funzione `account`, versione 1.6.0 e pagina della Dashboard

**Files:**
- Modify: `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `Configuration/configPage.html`
- Modify: `jellyfin-plugin-watch-party/meta.template.json`, `jellyfin-plugin-watch-party/README.md`, `docs/RELEASING.md`
- Modify (test): `ServiceRegistrationTests.cs`, `InfoControllerTests.cs`, `PluginPagesTests.cs`

- [ ] **Step 1: i test**

In `ServiceRegistrationTests.AllServicesResolve`, prima dell'ultima riga, aggiungi:

```csharp
        Assert.IsType<Server.PluginAccountSettings>(provider.GetRequiredService<Account.IAccountSettings>());
        Assert.EndsWith(
            Path.Combine("WonderFlixWatchParty", "contacts.json"),
            provider.GetRequiredService<Account.ContactStore>().FilePath);
        Assert.IsType<Server.DiscordBotClient>(provider.GetRequiredService<Account.IDiscordSender>());
        Assert.IsType<Server.SmtpMailSender>(provider.GetRequiredService<Account.IMailSender>());
        Assert.IsType<Server.JellyfinPasswordReset>(provider.GetRequiredService<Account.IPasswordReset>());
        Assert.IsType<Server.JellyfinPasswordCheck>(provider.GetRequiredService<Account.IPasswordCheck>());
        Assert.NotNull(provider.GetRequiredService<Account.ContactLinking>());
        Assert.NotNull(provider.GetRequiredService<Account.PasswordRecovery>());
        Assert.NotNull(provider.GetRequiredService<Account.AccountAdmin>());
        Assert.NotNull(provider.GetRequiredService<Account.ContactReminders>());
```

e l'ultima riga diventa:

```csharp
        Assert.Equal(3, provider.GetServices<IHostedService>().Count());
```

In `InfoControllerTests.cs`:
- in `InfoReportsVersionProtocolAndFeatures`: `Assert.Equal("1.6.0", info.Version);` e le funzioni `new[] { "friends", "parties", "inbox", "queue", "collections", "avatars", "account" }`;
- in `RequestsAppearOnlyWithSeerrConfigured`: `new[] { "friends", "parties", "inbox", "queue", "collections", "avatars", "account", "requests" }`.

In `PluginPagesTests.TheDashboardPageIsEmbeddedAndSendsAnnouncements`, prima del controllo dell'id del plugin, aggiungi:

```csharp
        // Recupero della password (spec L §7.1).
        Assert.Contains("DiscordBotToken", html);
        Assert.Contains("DiscordGuildId", html);
        Assert.Contains("SmtpHost", html);
        Assert.Contains("SmtpPort", html);
        Assert.Contains("SmtpUser", html);
        Assert.Contains("SmtpPassword", html);
        Assert.Contains("MailFrom", html);
        Assert.Contains("ContactReminderDays", html);
        Assert.Contains("WonderFlixWatchParty/Account/Admin/Status", html);
        Assert.Contains("WonderFlixWatchParty/Account/Admin/Test", html);
```

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~InfoControllerTests|FullyQualifiedName~PluginPagesTests"`
Expected: FAIL (servizi non registrati, versione 1.5.0, testi assenti dalla pagina).

- [ ] **Step 3: il codice**

In `PluginServiceRegistrator.cs` aggiungi `using Jellyfin.Plugin.WonderFlixWatchParty.Account;` e, dopo `serviceCollection.AddSingleton<RequestWebhookHandler>();`:

```csharp
        // Recupero della password (spec L).
        serviceCollection.AddSingleton<IAccountSettings, PluginAccountSettings>();
        serviceCollection.AddSingleton(provider => new ContactStore(
            ContactStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<ContactStore>>()));
        serviceCollection.AddSingleton<ContactRegistry>();
        serviceCollection.AddSingleton<CodeBook>();
        // Il token del bot non va nei log del client HTTP e non segue un redirect.
        serviceCollection.AddHttpClient(DiscordBotClient.HttpClientName)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false })
            .RedactLoggedHeaders(["Authorization"]);
        serviceCollection.AddSingleton<IDiscordSender, DiscordBotClient>();
        serviceCollection.AddSingleton<IMailSender, SmtpMailSender>();
        serviceCollection.AddSingleton<IPasswordReset, JellyfinPasswordReset>();
        serviceCollection.AddSingleton<IPasswordCheck, JellyfinPasswordCheck>();
        serviceCollection.AddSingleton<AccountSender>();
        serviceCollection.AddSingleton<ContactLinking>();
        serviceCollection.AddSingleton<PasswordRecovery>();
        serviceCollection.AddSingleton<AccountAdmin>();
        serviceCollection.AddSingleton<ContactReminders>();
```

e in fondo, dopo `AddHostedService<NewTitlesHostedService>()`:

```csharp
        serviceCollection.AddHostedService<ContactReminderHostedService>();
```

In `Protocol/WatchPartyProtocol.cs`:

```csharp
    /// <summary>
    /// Funzioni in più rispetto allo spec E, in GET Info (spec F §6.7, spec
    /// G §6.3, spec H §7, spec K §7.1 e §7.2, spec L §7.8). Il protocollo resta 1: le app 0.5.x accettano solo quello.
    /// </summary>
    public static readonly IReadOnlyList<string> Features = ["friends", "parties", "inbox", "queue", "collections", "avatars", "account"];
```

Nel csproj: `<Version>1.6.0</Version>`.

In `Plugin.cs`, `Description` diventa:

```csharp
    public override string Description =>
        "Names, chat, reactions, friends, notifications and password recovery for SyncPlay watch parties in WonderFlix.";
```

e il commento della classe dice anche: "Dalla 1.6.0 anche il recupero della password (spec L): la stessa pagina ha le impostazioni di Discord, dell'email e dei promemoria."

In `Configuration/configPage.html`:
- nel `data-require` del `div` della pagina, la lista resta `emby-button,emby-textarea,emby-checkbox,emby-input`;
- dopo `</form>` della sezione Seerr (prima di `</div>` di `content-primary`), aggiungi:

```html
                <form id="WonderFlixRecoveryForm">
                    <div class="verticalSection">
                        <h3 class="sectionTitle">Password recovery</h3>
                        <div class="fieldDescription">
                            WonderFlix users link their Discord or e-mail, and get a code there when they forget the password.
                            Administrators can't use it.
                        </div>
                        <div id="WonderFlixRecoveryStatus" class="fieldDescription"></div>
                        <div class="inputContainer">
                            <input is="emby-input" type="password" id="WonderFlixDiscordBotToken" label="Discord bot token" autocomplete="off" />
                            <div class="fieldDescription">
                                Discord Developer Portal → your app → Bot: the token, and turn on "Server Members Intent".
                            </div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="text" id="WonderFlixDiscordGuildId" label="Discord server ID" inputmode="numeric" />
                            <div class="fieldDescription">
                                Invite the bot to your server (scope "bot", no permissions), then right click on the server → Copy Server ID
                                (Discord developer mode).
                            </div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="text" id="WonderFlixSmtpHost" label="SMTP server" placeholder="smtp.gmail.com" />
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="number" id="WonderFlixSmtpPort" label="SMTP port" min="1" max="65535" />
                            <div class="fieldDescription">STARTTLS, usually 587 (port 465 is not supported).</div>
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="text" id="WonderFlixSmtpUser" label="SMTP user" autocomplete="off" />
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="password" id="WonderFlixSmtpPassword" label="SMTP password" autocomplete="off" />
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="email" id="WonderFlixMailFrom" label="Sender address" />
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="number" id="WonderFlixContactReminderDays" label="Reminder every (days)" min="0" max="365" />
                            <div class="fieldDescription">Users without a linked contact get a reminder in their notifications. 0: no reminders.</div>
                        </div>
                        <button is="emby-button" type="submit" class="raised button-submit block emby-button">
                            <span>Save</span>
                        </button>
                        <h3 class="sectionTitle">Test</h3>
                        <div class="fieldDescription">
                            Sends a test message to your own linked contacts, or to the Discord user name and the e-mail below.
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="text" id="WonderFlixTestDiscord" label="Discord user name (optional)" autocomplete="off" />
                        </div>
                        <div class="inputContainer">
                            <input is="emby-input" type="email" id="WonderFlixTestEmail" label="E-mail (optional)" autocomplete="off" />
                        </div>
                        <button is="emby-button" id="WonderFlixRecoveryTest" type="button" class="raised block emby-button">
                            <span>Send a test</span>
                        </button>
                        <div id="WonderFlixRecoveryResult" class="fieldDescription"></div>
                    </div>
                </form>
```

- nello script, prima della riga finale `})();`, aggiungi:

```javascript
                // Recupero della password (spec L §7.1).
                var recoveryFields = {
                    DiscordBotToken: page.querySelector('#WonderFlixDiscordBotToken'),
                    DiscordGuildId: page.querySelector('#WonderFlixDiscordGuildId'),
                    SmtpHost: page.querySelector('#WonderFlixSmtpHost'),
                    SmtpPort: page.querySelector('#WonderFlixSmtpPort'),
                    SmtpUser: page.querySelector('#WonderFlixSmtpUser'),
                    SmtpPassword: page.querySelector('#WonderFlixSmtpPassword'),
                    MailFrom: page.querySelector('#WonderFlixMailFrom'),
                    ContactReminderDays: page.querySelector('#WonderFlixContactReminderDays')
                };
                var recoveryStatus = page.querySelector('#WonderFlixRecoveryStatus');
                var recoveryResult = page.querySelector('#WonderFlixRecoveryResult');
                var testDiscord = page.querySelector('#WonderFlixTestDiscord');
                var testEmail = page.querySelector('#WonderFlixTestEmail');

                function refreshRecoveryStatus() {
                    ApiClient.ajax({
                        type: 'GET',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Account/Admin/Status'),
                        dataType: 'json'
                    }).then(function (status) {
                        recoveryStatus.textContent = 'Discord: ' + (status.Discord.Configured ? 'configured' : 'not configured')
                            + '. E-mail: ' + (status.Email.Configured ? 'configured' : 'not configured')
                            + '. ' + status.WithContacts + ' of ' + status.Users + ' users have a linked contact.';
                    }, function () {
                        recoveryStatus.textContent = '';
                    });
                }

                function loadRecovery() {
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        Object.keys(recoveryFields).forEach(function (name) {
                            var value = config[name];
                            recoveryFields[name].value = value === undefined || value === null ? '' : value;
                        });
                        refreshRecoveryStatus();
                    });
                }

                function numberIn(field, fallback) {
                    var value = parseInt(field.value, 10);
                    return isNaN(value) ? fallback : value;
                }

                page.addEventListener('pageshow', loadRecovery);
                loadRecovery();

                page.querySelector('#WonderFlixRecoveryForm').addEventListener('submit', function (e) {
                    e.preventDefault();
                    recoveryResult.textContent = '';
                    Dashboard.showLoadingMsg();
                    ApiClient.getPluginConfiguration(pluginId).then(function (config) {
                        config.DiscordBotToken = recoveryFields.DiscordBotToken.value.trim();
                        config.DiscordGuildId = recoveryFields.DiscordGuildId.value.trim();
                        config.SmtpHost = recoveryFields.SmtpHost.value.trim();
                        config.SmtpPort = numberIn(recoveryFields.SmtpPort, 587);
                        config.SmtpUser = recoveryFields.SmtpUser.value.trim();
                        config.SmtpPassword = recoveryFields.SmtpPassword.value;
                        config.MailFrom = recoveryFields.MailFrom.value.trim();
                        config.ContactReminderDays = Math.max(0, numberIn(recoveryFields.ContactReminderDays, 14));
                        return ApiClient.updatePluginConfiguration(pluginId, config);
                    }).then(function (saved) {
                        Dashboard.processPluginConfigurationUpdateResult(saved);
                        loadRecovery();
                    }, function () {
                        Dashboard.hideLoadingMsg();
                        recoveryResult.textContent = 'Settings not saved.';
                    });
                    return false;
                });

                var testLabels = {
                    Ok: 'sent',
                    NotConfigured: 'not configured',
                    NoContact: 'link your own contact in WonderFlix first, or fill the field above',
                    Invalid: 'bot token or server ID refused',
                    MemberNotFound: 'nobody with that user name in the server',
                    InvalidTarget: 'not a valid address',
                    DmClosed: 'the bot can\'t write to that user (direct messages closed)',
                    SendFailed: 'sending failed: check the settings and the Jellyfin log'
                };

                var testButton = page.querySelector('#WonderFlixRecoveryTest');
                testButton.addEventListener('click', function () {
                    // Una prova alla volta: può durare fino a 24 s.
                    if (testButton.disabled) {
                        return;
                    }

                    testButton.disabled = true;
                    recoveryResult.textContent = 'Sending…';
                    ApiClient.ajax({
                        type: 'POST',
                        url: ApiClient.getUrl('WonderFlixWatchParty/Account/Admin/Test'),
                        data: JSON.stringify({
                            Language: (navigator.language || 'en').slice(0, 2),
                            Discord: testDiscord.value.trim() || null,
                            Email: testEmail.value.trim() || null
                        }),
                        contentType: 'application/json',
                        dataType: 'json'
                    }).then(function (result) {
                        testButton.disabled = false;
                        recoveryResult.textContent = 'Discord: ' + (testLabels[result.Discord] || result.Discord)
                            + '. E-mail: ' + (testLabels[result.Email] || result.Email) + '.';
                        refreshRecoveryStatus();
                    }, function () {
                        testButton.disabled = false;
                        recoveryResult.textContent = 'Test failed: try again.';
                    });
                });
```

In `jellyfin-plugin-watch-party/meta.template.json`:
- in `description`, dopo "collections (sagas) and user pictures", aggiungi ", and password recovery by Discord or e-mail";
- in `overview`, alla fine, aggiungi ", password recovery".

In `jellyfin-plugin-watch-party/README.md`:
- nel primo paragrafo, dopo la frase sulla 1.5.0: "Dalla 1.6.0 porta il recupero della password con un codice su Discord o per email (spec L, `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md`)." Nella frase "Senza il plugin WonderFlix funziona lo stesso, …" aggiungi "e senza il recupero della password";
- dopo la voce **Immagini degli utenti**, aggiungi:

```markdown
- **Recupero della password (dalla 1.6.0):** ogni utente collega e verifica
  il suo Discord o la sua email (`Account/Contacts`, con la password attuale e
  un codice a 6 cifre mandato lì: chi ha solo una sessione aperta non può
  cambiare i contatti). Chi dimentica la password chiede un codice dal login
  (`Account/Recovery`, senza accesso: la risposta non dice se l'account
  esiste) e sceglie la password nuova; tutte le sue sessioni si chiudono.
  Gli admin non possono usarlo. Nella pagina del plugin: token del bot e id
  del server Discord, server SMTP (STARTTLS, di solito 587), mittente, ogni
  quanti giorni il promemoria nella cassetta a chi non ha contatti (0:
  spento) e **Send a test**. Il bot: Discord Developer Portal → l'app →
  Bot (il token, "Server Members Intent" acceso), poi l'invito nel server
  con lo scope `bot`, senza permessi. I contatti stanno in
  `plugins/configurations/WonderFlixWatchParty/contacts.json` (un file
  illeggibile diventa `contacts.json.bad`); i codici solo in memoria (10
  minuti, 5 tentativi). Gli endpoint dell'admin stanno sotto
  `Account/Admin`.
```

- nella voce **Funzioni**, aggiungi: "dalla 1.6.0 anche `account`.";
- in **Installazione a mano (prove)**, l'esempio diventa `bash jellyfin-plugin-watch-party/pack.sh 1.6.0` e la cartella `WonderFlix Watch Party_1.6.0.0/`;
- in **Sviluppo**, dopo la frase su `IUserManager.Users`, aggiungi: "Anche `IUserManager.ChangePassword` ha cambiato firma (`User` nella 10.11.0, `Guid` nella 10.11.9): `Server/PasswordChanging.cs`."

In `docs/RELEASING.md`, nella sezione del plugin, al passo 1 dopo "…e l'impostazione dei nuovi titoli in `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`" aggiungi: "I contatti per il recupero della password stanno in `plugins/configurations/WonderFlixWatchParty/contacts.json`, le sue impostazioni (bot Discord, SMTP, promemoria) nello stesso XML." (la frase "un aggiornamento del plugin non le tocca" resta in fondo).

- [ ] **Step 4: i test passano**

Run: lo stesso filtro, poi la suite intera. Expected: tutto verde.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party docs/RELEASING.md
git commit -m "feat(plugin): wire password recovery, Dashboard settings and version 1.6.0"
```

## Gruppo F — server e chiusura

### Task 14: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo E si ferma qui. L'orchestratore fa i passi seguenti. Sul server WonderFlix lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando.

1. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.6.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.6.0.0/`.
2. **Server** (`ssh ultra`; vedi la memoria `ultra-ssh` per le virgolette con `scp` e per gli script con BOM/CRLF):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave "Wonderflix", come nel 17c); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - `mkdir -p ~/wfwp-backup` e sposta il plugin del Catalogo `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.5.0.0` in `~/wfwp-backup/1.5.0.0-catalogo`;
   - **promemoria spenti** (decisione 9):
     - copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.5.0.xml`;
     - aggiungi `<ContactReminderDays>0</ContactReminderDays>` prima di `</PluginConfiguration>` (`sed -i 's#</PluginConfiguration>#  <ContactReminderDays>0</ContactReminderDays>\n</PluginConfiguration>#'`);
     - controlla con `grep ContactReminderDays`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.6.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.6.0.0"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.6.0.0, rimetti `~/wfwp-backup/1.5.0.0-catalogo` e la configurazione salvata, riavvia, e segnalalo.
3. **Controlli senza canali** (base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave Wonderflix>"`, script in un file come dice la memoria):
   - `GET /WonderFlixWatchParty/Info` ha `account` e la versione `1.6.0`;
   - `GET /WonderFlixWatchParty/Account/Admin/Status`: `Configured` false per tutti e due i canali, `ReminderDays` 0, `Users` uguale agli utenti attivi non admin, `WithContacts` 0;
   - `GET /WonderFlixWatchParty/Account/Admin/Users`: tutti gli utenti, nessun contatto;
   - **senza intestazione** `POST /WonderFlixWatchParty/Account/Recovery/Start` con `{"Username":"nessuno-18a","Language":"it"}` → 202; la stessa richiesta subito dopo → 429 `{"Code":"RateLimited"}`;
   - senza intestazione `POST …/Account/Recovery/Complete` con `{"Username":"nessuno-18a","Code":"000000","NewPassword":"abcdef"}` → 400 `{"Code":"InvalidCode"}`;
   - `GET …/Account/Contacts` senza intestazione → 401 (le rotte dell'utente vogliono l'accesso).
   - Mai il recupero su un account vero.
4. **STOP — preparazione dell'utente** (credenziali e consensi li gestisce l'utente; spec §13). Chiedigli di:
   - **Discord:**
     - nel Developer Portal, nell'app `1397884246692986970`, scheda Bot: creare il bot, copiare il token, attivare "Server Members Intent";
     - in OAuth2 → URL Generator, scope `bot`, nessun permesso: aprire l'URL e invitare il bot nel server di WonderFlix;
     - copiare l'id del server (modalità sviluppatore → clic destro sul server → Copia ID server);
   - **Email:** scegliere un SMTP sulla porta 587. Meglio credenziali che possono solo spedire (una chiave SMTP di Brevo o di Resend) che una password per app di Gmail: chi la legge dalla configurazione potrebbe anche leggere la posta inviata, codici compresi;
   - **Dashboard:** Plugin → WonderFlix Watch Party → "Password recovery": inserire tutto, con **"Reminder every (days)" a 0**, poi **Save**;
   - **Send a test**, con il suo nome utente Discord e la sua email nei due campi: deve leggere "Discord: sent. E-mail: sent." e ricevere il DM del bot e l'email (controllare anche lo spam).
5. **Dopo la prova dell'utente:**
   - `grep ContactReminderDays` nella configurazione: ancora 0;
   - `GET …/Account/Admin/Status`: tutti e due `Configured` true, nessun `LastError`;
   - nel log di Jellyfin nessun token, password o indirizzo (`grep -i` sul token e sull'email dell'utente → niente).

Il collegamento dei contatti e il recupero veri si provano con l'app, nel 18b. La build di prova resta sul server fino al rilascio (fine del 18c), con i promemoria spenti.

### Task 15: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md`
- Modify: `docs/superpowers/plans/2026-10-09-wonderflix-18a-recupero-plugin.md` (solo la decisione "Dalle review dei gruppi", se ci sono differenze)

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvato; piano 18a realizzato (`docs/superpowers/plans/2026-10-09-wonderflix-18a-recupero-plugin.md`); piani 18b e 18c da scrivere".
- **§3:** le firme diverse di `ChangePassword` fra 10.11.0 e 10.11.9, risolte con `Server/PasswordChanging.cs`; `RevokeUserTokens(id, "")` verificato nel sorgente `v10.11.9`.
- **§6:** lo schema con le classi vere: `ContactRegistry`, `CodeBook`, `AccountSender`, `ContactLinking`, `PasswordRecovery`, `AccountAdmin`, `ContactReminders`, `ContactReminderHostedService`, e gli adattatori `DiscordBotClient`, `SmtpMailSender`, `JellyfinPasswordReset`, `PluginAccountSettings`.
- **§7.1:** la pagina della Dashboard con i campi di prova facoltativi (nome Discord, email).
- **§7.3:** l'ultimo errore sparisce con il primo invio riuscito sul canale; nel log niente indirizzi (anche nei messaggi del server SMTP); `User-Agent` di Discord; i tempi (8 s per operazione Discord, 15 s per l'email, canali in parallelo) e il motivo (i 30 s dell'app); il controllo che prova la ricerca dei membri; la ricerca a 100 risultati senza bot.
- **§14:** la porta 465 non funziona (solo STARTTLS) e lo dice il log.
- **§7.4:** `AccountService` diventa le sei classi (decisione 8); il codice dell'admin sta in `PasswordRecovery.SendForAdminAsync` e con un utente disattivato risponde `NotAllowed`; `Admin/Test` accetta `Discord` ed `Email` e risponde con gli esiti di `AccountTestCodes`.
- **§7.5:** i limiti giornalieri (`RecoveryFailDay` 20 al giorno per nome, `RecoveryFailGlobal` 100 al giorno) e il motivo; i tipi veri (`RecoveryStartMinute`, `RecoveryStartHour`, `RecoveryStartGlobal`, `RecoveryFail`, `RecoveryFailDay`, `RecoveryFailGlobal`, `LinkStartMinute`, `LinkStartHour`), `IsLimited` e la pulizia delle chiavi vecchie.
- **§11:** il blocco dopo i login sbagliati (spento sul server, caso accettato); un elenco utenti vuoto non toglie contatti; un errore di `RevokeUserTokens` dopo il cambio va nel log; scollegare annulla il codice di recupero in sospeso; un cambio password fuori dal recupero non lo annulla (punto aperto); un contatto su un canale spento non conta.
- **§7.5 (seguito):** `RecoveryStartDay` (10 al giorno per nome) e i limiti guardati prima di essere spesi; il limite globale delle richieste (30 all'ora) si può usare per bloccare il recupero di tutti ancora più a buon mercato di quello degli errori (compromesso accettato, la via d'uscita è "Imposta password").
- **§13 (seguito):** il numero massimo di email al giorno che un estraneo può far partire (i limiti per nome e quello globale) accanto al consiglio sul servizio SMTP.
- **§13:** il consiglio sulle credenziali SMTP che possono solo spedire.
- **§7.6:**
  - niente 404: `MemberNotFound` è 400 e un utente sconosciuto è 400 `UnknownUser`;
  - `Recovery/Complete` ha `Language`;
  - `Admin/Test` ha `Discord` ed `Email`;
  - una chiamata senza utente non collega contatti (`Invalid`).
- **§8:** password da 6 a 1024 caratteri; i codici accettano spazi e trattini; **la password attuale per collegare, sostituire e scollegare un contatto** (decisione 11, Gruppo C), con il limite `PasswordChecks` e l'errore `WrongPassword`.
- **§7.4 e §7.6:** l'ordine dei controlli di Start (canale, contatto, limite al minuto per canale, limite all'ora, password, ricerca, codice); `Password` in Start; `POST Contacts/{canale}/Unlink` con `{Password}` al posto della DELETE; `WrongPassword` 403.
- **§9.2 (per il 18b):** la finestra "Collega" chiede anche la password attuale (passo 1), e "Scollega" la chiede nella conferma; un account senza password la lascia vuota.
- **§14:** i punti verificati (firme, `RevokeUserTokens`, `[AllowAnonymous]` già usato dal webhook di Seerr). La ricerca dei membri e l'SMTP sono stati provati nel Task 14, con l'esito.
- **§15:** 18a realizzato; il plugin 1.6.0 esce con l'app 0.12.0 alla fine del 18c; fino ad allora sul server c'è la build di prova con i promemoria spenti.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze (come nei piani 17a–17c).

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the password recovery spec with plan 18a"
```

### Task 16: ok dell'utente e merge

Con l'ok dell'utente sulla prova del Task 14: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`). Niente tag e niente manifest: il plugin 1.6.0 si pubblica alla fine del 18c, insieme all'app 0.12.0.
