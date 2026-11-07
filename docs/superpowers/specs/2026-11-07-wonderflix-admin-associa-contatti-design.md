# WonderFlix — l'admin associa Discord ed email

- **Data:** 2026-11-07
- **Stato:** design approvato il 2026-11-07; piano `docs/superpowers/plans/2026-11-07-wonderflix-admin-associa-contatti.md`. Branch `associa-contatti` (worktree `.claude/worktrees/associa-contatti`).
- **Ambito:** estende la Spec L (recupero password, `2026-10-09-wonderflix-recupero-password-design.md`), §7.4 (funzioni dell'admin) e la tab Utenti dell'app. Plugin + app.

## 1. Perché

Oggi i contatti per il recupero li collega solo l'utente, da Impostazioni: nome Discord o email, password attuale, codice mandato lì, codice scritto nell'app (Spec L §7.4, `ContactLinking`). Quasi nessuno lo fa, e chi poi dimentica la password non può recuperarla da solo: resta l'admin.

L'admin spesso sa già il nome Discord (o l'email) delle persone. Vuole associarlo lui, dalla lista utenti, in un attimo.

## 2. Obiettivi e non obiettivi

**Obiettivi**

- Nel menu a tre puntini di ogni utente (tab Utenti) due voci nuove: **"Associa Discord"** e **"Associa email"**.
- Il contatto associato dall'admin **vale subito** per il recupero, come uno verificato dall'utente.
- Per Discord l'admin vede **chi ha trovato il bot** (nome utente e nome visualizzato) prima di confermare: un errore di battitura darebbe a un estraneo il recupero dell'account.

**Non obiettivi**

- **Nessun avviso** all'utente (né DM né email) quando l'admin associa un contatto. Deciso dall'utente.
- Nessuna conferma da parte dell'utente (codice o pulsante): il contatto vale subito. Deciso dall'utente.
- Nessuna scelta da un elenco dei membri del server Discord: l'admin scrive il nome.
- Nessun cambio alla Dashboard di Jellyfin (`configPage.html`).
- Nessun avviso se lo stesso Discord o la stessa email è già di un altro utente: oggi è permesso anche all'utente.

**Anti-obiettivo:** associare un contatto non deve aprire una strada a chi non è admin. Gli endpoint nuovi sono solo per admin, come quelli di `AccountAdminController`.

## 3. Sicurezza

La Spec L chiede password e codice perché chi ha solo una sessione aperta non metta i propri contatti sull'account di un altro. Per l'admin non servono: può già cambiare qualsiasi password ("Imposta password"), quindi associare un contatto non gli dà niente in più. **Niente password dell'admin e niente limiti di frequenza** sugli endpoint nuovi (come "Imposta password" e "Scollega contatti").

Il rischio che resta è l'errore di battitura, coperto dall'anteprima di §5.1.

## 4. Plugin (1.24.0)

### 4.1 Endpoint

In `AccountAdminController` (`WonderFlixWatchParty/Account/Admin`, stessa autorizzazione admin). Un `userId` non valido o sconosciuto è 400 `UnknownUser`, come gli altri.

| Metodo e rotta | Corpo | Risposta |
|---|---|---|
| `POST Discord/Lookup` | `{Name}` | 200 `{Id, Username, DisplayName?}` |
| `PUT Users/{userId}/Discord` | `{Id, Username}` | 204 |
| `PUT Users/{userId}/Email` | `{Address}` | 204 |

Errori: i codici `AccountError` di oggi, resi da `AccountErrors.Result` così com'è (400 per `UnknownUser`, `InvalidTarget` e `MemberNotFound`; 503 per `ChannelOff`; 502 per `SendFailed`, sempre con `{Code}` nel corpo):

- `ChannelOff`: il canale non è configurato (`settings.IsConfigured`). Un contatto su un canale spento non serve al recupero.
- `InvalidTarget`: nome Discord scritto male (`ContactLinking.CleanDiscordName`), indirizzo non valido (`ContactLinking.CleanEmail`), oppure, nel `PUT …/Discord`, `Id` non snowflake (`DiscordIds.IsSnowflake`) o `Username` vuoto.
- `MemberNotFound`: il bot non trova il nome tra i membri del server.
- `SendFailed`: la ricerca su Discord non è riuscita; si registra come errore del canale (`sender.Record(AccountChannel.Discord, SendOutcome.Failed)`), come in `ContactLinking.StartAsync`.

### 4.2 `AccountAdmin`

- `LookupDiscordAsync(name, ct)`: pulisce il nome, `discord.FindMemberAsync`, rende il membro trovato.
- `SetDiscord(userId, id, username, adminId)` e `SetEmail(userId, address, adminId)`:
  1. utente sconosciuto per Jellyfin (`users.GetUser`) → `UnknownUser`;
  2. canale spento → `ChannelOff`; contatto non valido → `InvalidTarget`;
  3. `contacts.SetDiscord` / `contacts.SetEmail` con `VerifiedAt` = adesso: un contatto dato dall'admin conta come verificato;
  4. annulla il codice di verifica di quel canale e il codice di recupero già mandati (`codes.Discard`): come per "Scollega", il contatto vecchio potrebbe essere quello compromesso;
  5. toglie i promemoria per i contatti dalla posta (`inbox.RemoveContactRemindersAsync`), come `ContactLinking.ConfirmAsync`. Il costruttore di `AccountAdmin` prende `InboxService` e `TimeProvider` (per `VerifiedAt`): vanno aggiornati i `new AccountAdmin(...)` scritti a mano nei test (`AccountRig.Admin()`, `AccountAdminTests`, `AccountAdminControllerTests`);
  6. log "Discord (o email) di {UserId} associato dall'admin {AdminId}" con `AdminCaller.Describe`. Mai il nome Discord né l'indirizzo nel log.

Il `PUT …/Discord` salva l'`Id` e lo `Username` venuti dall'anteprima, senza una seconda ricerca: si salva esattamente la persona che l'admin ha visto. È una scelta mia (vedi §8).

### 4.3 Nome visualizzato

`DiscordMember` prende un ultimo parametro facoltativo `string? DisplayName = null` (così `FakeAccountChannels` e gli altri chiamanti compilano ancora): il soprannome nel server (`nick` del membro) se c'è, altrimenti il nome globale (`user.global_name`), altrimenti null. `DiscordBotClient.FindMemberAsync` lo legge dalla stessa risposta di `members/search`. Chi usa già `DiscordMember` lo ignora.

### 4.4 Funzione in `Info`

`Info.Features` prende `accountAdminLink`, come gli altri flag (per esempio `downloadsSearchJobs`). L'app mostra le voci nuove solo se c'è: con un plugin più vecchio non darebbero altro che un 404.

### 4.5 Test

In `AccountAdminTests` (o un file nuovo accanto) e nei test del controller, se ci sono per `AccountAdminController`: ogni errore di §4.1, il contatto salvato con `VerifiedAt`, i codici annullati, i promemoria tolti, un contatto esistente sostituito. In `DiscordBotClientTests`: `DisplayName` da `nick`, da `global_name`, null senza nessuno dei due. Aggiornare la versione in `InfoControllerTests`.

## 5. App (0.33.0)

### 5.1 Tab Utenti

Nel `PopupMenuButton<UserAction>` di `users_tab.dart` due azioni nuove, prima di "Scollega contatti": **"Associa Discord"** e **"Associa email"**. Ci sono per ogni utente, anche se ha già quel contatto (l'associazione lo sostituisce) e anche per gli admin. Così ogni riga ha il menu, anche quelle dove oggi `userActions` non rende niente. La voce non c'è se il canale è spento (`Configured` false in `GET Admin/Status`) o se il plugin non ha la funzione `accountAdminLink` (§4.4).

**Associa Discord** apre un dialogo:

1. titolo "Associa Discord a {name}", campo "Nome utente Discord" con l'aiuto "Il nome utente, non il nome visualizzato" (stessi testi di `link_contact_dialog.dart`), pulsante **"Cerca"** → `POST Discord/Lookup`;
2. trovato: sotto il campo "@{username}" e, se c'è, il nome visualizzato. Il pulsante diventa **"Associa"** → `PUT Users/{id}/Discord`. Se l'admin cambia il nome nel campo, l'anteprima sparisce e si torna a "Cerca";
3. errori sotto il campo: nome non valido, nome non trovato nel server (testo per l'admin, come `adminRecoveryTestMemberNotFound`, non `accountErrorMemberNotFound`, che parla all'utente), errore di Discord, canale spento. `accountAdminErrorText` oggi non ha `InvalidTarget`, `MemberNotFound` né `ChannelOff`: vanno aggiunti lì, oppure i dialoghi hanno i loro testi.

**Associa email**: dialogo "Associa email a {name}", campo "Email", pulsante **"Associa"** → `PUT Users/{id}/Email`. Errore sotto il campo per un indirizzo non valido.

Dopo il salvataggio: il dialogo si chiude, uno SnackBar "Discord associato a {name}" (o "Email associata a {name}") e la lista si ricarica, così le icone di Discord ed email si aggiornano.

Le chiamate vanno in `plugin_admin_api.dart`, accanto a `sendRecoveryCode` e allo scollegamento. Testi nuovi in `app/l10n` (italiano e inglese).

### 5.2 Test

Widget test della tab Utenti o dei dialoghi: le due voci nel menu, il flusso Cerca → anteprima → Associa, l'anteprima che sparisce cambiando il nome, un errore mostrato, la voce nascosta con il canale spento.

## 6. Rilascio

Prima il plugin 1.24.0, poi l'app 0.33.0 (ordine di `docs/RELEASING.md`). Una riga nuova nella checklist manuale di `docs/RELEASING.md`, nello stesso commit del bump dell'app: "Utenti → ⋮ → Associa Discord: cerca, anteprima, associa; poi il recupero dell'utente arriva su quel Discord. Associa email: lo stesso con l'indirizzo".

## 7. Lasciato al builder

- La forma dei dialoghi (uno solo con il canale come parametro o due) e dove stanno i file.
- I testi esatti di SnackBar e titoli, oltre a quelli scritti qui.
- Come l'app sa che il canale è spento: oggi la tab Utenti non legge lo stato, lo legge solo la card del recupero con `accountAdminControllerProvider`. Si può guardare quel provider oppure chiamare `GET Admin/Status`.

## 8. Scelte mie (da controllare)

- Niente password dell'admin né limiti di frequenza (§3).
- Il `PUT …/Discord` salva `Id` e `Username` dell'anteprima, senza ripetere la ricerca (§4.2).
- `ChannelOff` anche per l'associazione, non solo per l'invio (§4.1).
- Associare annulla i codici di verifica e di recupero già mandati per quell'utente (§4.2).
- Le voci ci sono anche per gli admin e anche quando il contatto esiste già (§5.1).
- Nome visualizzato: soprannome nel server, poi nome globale (§4.3).
- La funzione `accountAdminLink` in `Info` nasconde le voci con un plugin vecchio (§4.4).
