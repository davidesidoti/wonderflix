# WonderFlix — Spec F: amici e party privati

- **Data:** 2026-10-03
- **Stato:** approvato; piani 12a e 12b realizzati (`docs/superpowers/plans/2026-10-03-wonderflix-12a-amici.md`, `docs/superpowers/plans/2026-10-03-wonderflix-12b-modalita-party.md`)
- **Ambito:** Spec F. Realizza l'issue #6 (lista amici) e l'issue #5 (watch party pubblico / solo amici / privato). L'issue #7 (collegamento a Discord) resta fuori: sarà la Spec G. Si appoggia allo Spec B (`2026-09-30-wonderflix-watch-party-design.md`: §5.8 elenco e inviti, §7 interfaccia) e allo Spec E (`2026-10-02-wonderflix-watch-party-sociale-design.md`: §6 plugin, §7 canale), entrambi realizzati (v0.5.1).

## 1. Obiettivo

Oggi ogni watch party è visibile a tutti e chi lo crea fa comparire la scheda "X ha avviato un watch party" a chiunque abbia l'app aperta. La Spec F aggiunge:

- una **lista amici** con richiesta e accettazione, ricerca per nome e stato online;
- tre **modalità** per il party: **Pubblico** (come oggi), **Solo amici**, **Privato** (codice o invito);
- **"Invita amici"** da dentro il party, in qualunque modalità.

Tutto passa dal plugin "WonderFlix Watch Party", che diventa la 1.1.0. **Senza il plugin aggiornato l'app funziona come la 0.5.1.**

## 2. Situazione di partenza

- **Elenco dei party** (`lib/features/watch_party/watch_party_directory.dart`): `WatchPartyDirectory` legge `/SyncPlay/List` ogni 30 s e quando il player si chiude; con il player aperto non legge.
- **Scheda d'invito** (`watch_party_invites.dart`): `WatchPartyInvites` confronta due letture dell'elenco; l'ultimo gruppo nuovo diventa la scheda "{host} ha avviato un watch party" per 10 s (non dentro un gruppo, non con il player aperto, non per i gruppi in cui siamo stati). Il nome del gruppo è "Host · Titolo" (`partyNameParts`).
- **Barra in alto** (`lib/app/app_shell.dart`): voci di navigazione, titolo, `WatchPartyButton` (chip con l'elenco, nascosto se non ci sono party; "Nel watch party" con Torna al player / Esci se siamo in un gruppo), avatar con menu Impostazioni / Esci. La scheda d'invito sta in `Positioned(top: 72, right: 24)`.
- **"Guarda insieme"**: nell'intestazione della scheda (`detail_header.dart`) e nella barra del player (`player_screen.dart`, solo fuori da un gruppo). Entrambi chiamano `startWatchParty` (`watch_party_actions.dart`), che crea il gruppo o, dentro un gruppo, cambia la coda.
- **Distintivo del party nel player** (`party_badge.dart`): menu con i membri ed Esci.
- **Plugin 1.0.0** (`jellyfin-plugin-watch-party/`): tutto in RAM (registro dei membri, storico della chat, limiti). Endpoint `Info`, `Groups/{id}/Join|Leave|Events`. Gli eventi arrivano alle app come `GeneralCommand` `SendString` con `Arguments["WonderFlixWatchParty"]`. `Info` risponde `{Version, Protocol: 1}`.
- **App e plugin** (`lib/features/watch_party/party_channel.dart`): l'app accetta il plugin solo se `Protocol == 1` (righe ~306 e ~338) e chiede `Info` solo entrando in un gruppo o dalla diagnostica. Gli eventi senza un `GroupId` del gruppo corrente sono scartati (`_onEvent`); i tipi sconosciuti sono scartati con una riga di log (`parsePartyEvent`).
- **Client:** le app si presentano a Jellyfin come client `WonderFlix` (`main.dart`, `ClientInfo`).
- **Nell'app non ci sono dialoghi** (Spec C): conferme e scelte passano da menu, pulsanti e pillole.

## 3. Decisioni

| Tema | Decisione |
|---|---|
| Ambito | #5 + #6; Discord (#7) in una Spec G separata |
| Amicizia | richiesta + accetta/rifiuta; reciproca. Richieste incrociate diventano subito amicizia. "Rifiuta" è silenzioso |
| Ricerca | nome che **contiene** il testo, da 2 lettere, massimo 10 risultati; mai l'elenco completo degli utenti |
| Dove | icona "Amici" nella barra (tra il chip dei party e l'avatar) con numero delle richieste; pannello laterale da destra |
| Stato | online (sessione WonderFlix aperta) + "Nel watch party: Titolo" con Unisciti, se quel party è visibile a chi guarda |
| Modalità | menu su "Guarda insieme" con Pubblico / Solo amici / Privato; ultima usata evidenziata; fissa per tutta la vita del party |
| Codice | solo per Privato; 6 caratteri senza 0/O/1/I/L, mostrato `K7P-Q2X`; lo vedono e lo condividono tutti i membri |
| Inviti | "Invita amici" in tutte le modalità, da qualunque membro, solo verso i propri amici; l'invito rende il party visibile all'invitato finché esiste |
| Architettura | tutto nel plugin: amicizie su disco, party in RAM, elenco filtrato e avvisi in tempo reale |
| Compatibilità | `Protocol` resta 1; `Info` aggiunge `Features: ["friends", "parties"]` |
| Release | plugin 1.1.0 prima; app **0.6.0 obbligatoria** (`min-version=0.6.0`) |
| Piani | 12a amici da capo a fondo; 12b modalità da capo a fondo + release |

## 4. Perimetro

### Incluso

- Plugin 1.1.0: archivio delle amicizie, ricerca utenti, richieste, presenza, registro dei party con modalità, codici, inviti, elenco filtrato, nuovi avvisi.
- App 0.6.0: disponibilità delle funzioni del plugin, icona e pannello Amici, scheda della richiesta, menu delle modalità, codice, "Invita amici", elenco dei party dal plugin, schede d'avviso spinte dal plugin.

### Escluso

- **Discord** (#7): Spec G.
- **Blocco** di un utente: "Rifiuta" e "Rimuovi" bastano tra amici.
- **Cambiare modalità** dopo la creazione.
- **Immagini profilo**: si usano le iniziali, come per i membri del party.
- **Avvisi a chi è offline**: arrivano solo alle sessioni aperte; l'invito resta comunque nell'elenco dell'invitato.
- **Privacy verso altri client Jellyfin**: il server SyncPlay mostra ogni gruppo a qualunque client lo chieda (`/SyncPlay/List`). Un party privato è nascosto dentro WonderFlix, non a jellyfin-web. Accettato: si usa solo WonderFlix.

## 5. Architettura

```
Plugin 1.1.0
  FriendStore (friends.json, su disco)  ─┐
  PresenceTracker (sessioni WonderFlix)  ├─ FriendService / PartyService / PartyAnnouncer ── FriendsController / PartiesController (REST)
  PartyDirectory (modalità, codici,     ─┘  └─ avvisi (SendString)
                  inviti, visibilità; RAM)

App 0.6.0
  lib/core/social/        SocialApi, modelli, parseSocialEvent (Dart puro)
  SocialAvailability      Info + Features, al login e alla riconnessione
  SocialEvents            avvisi del plugin senza gruppo → controller
  FriendsController       amici, richieste, ricerca
  FriendsButton/Panel     icona, pannello, scheda della richiesta
  PartyModeMenu           menu su "Guarda insieme"
  WatchPartyDirectory     /SyncPlay/List oppure GET Parties
  WatchPartyInvites       confronto delle letture oppure avvisi del plugin
```

Il plugin continua a non conoscere Jellyfin dentro il nucleo: le nuove classi parlano con interfacce (`IUserDirectory`, `ISessionDirectory`, `IGroupDirectory`, `IEventSender`, `TimeProvider`) con adattatori in `Server/`, come in 1.0.0.

## 6. Plugin 1.1.0

### 6.1 Archivio delle amicizie

- File `friends.json` in `<PluginConfigurationsPath>/WonderFlixWatchParty/` (in genere `plugins/configurations/`). **Non** nella cartella del plugin: quella ha la versione nel nome e si perderebbe a ogni aggiornamento.
- Contenuto: `{"Version": 1, "Friendships": [["<userId>", "<userId>"], …], "Requests": [{"From": "<userId>", "To": "<userId>", "CreatedAt": "<ISO-8601>"}, …]}`. Id utente in formato `N` (senza trattini, minuscolo), come nel resto del protocollo.
- Caricato all'avvio; ogni modifica riscrive il file in modo atomico (file temporaneo nella stessa cartella + rinomina). Le scritture sono serializzate da un lock.
- **File illeggibile:** rinominato in `friends.json.bad` (sovrascrivendo un eventuale `.bad` precedente), riga di log `Warning`, si riparte vuoti.
- Gli utenti che non esistono più in Jellyfin vengono ignorati in lettura e tolti alla prima scrittura.
- I nomi non si salvano: si leggono da Jellyfin a ogni risposta, così un utente rinominato compare subito con il nome nuovo.

### 6.2 Regole degli amici

- **Richiesta A → B:** rifiutata (409) se A = B, se B non esiste, è disabilitato o non ha accesso ai watch party (SyncPlay "None": non potrebbe rispondere e la richiesta resterebbe in sospeso per sempre), se sono già amici o se A ha già una richiesta verso B. Se esiste la richiesta B → A, diventano subito amici (e la richiesta sparisce).
- **Accetta** (B accetta A): diventano amici. **Rifiuta**: la richiesta sparisce, A non riceve niente di diverso da "la richiesta non c'è più". **Annulla** (A): la richiesta sparisce. **Rimuovi** (uno dei due): l'amicizia sparisce per tutti e due.
- **Ricerca:** almeno 2 caratteri dopo `Trim`; confronto senza maiuscole (`OrdinalIgnoreCase`) sul nome Jellyfin che **contiene** il testo; esclusi chi cerca, gli utenti disabilitati e quelli senza accesso ai watch party (SyncPlay "None": non possono usare gli endpoint degli amici); ordinati per nome; massimo 10. Ogni risultato porta la relazione con chi cerca: `None`, `Friend`, `Incoming`, `Outgoing`.

### 6.3 Presenza

- **Online:** l'utente ha almeno una sessione Jellyfin con `Client == "WonderFlix"`.
- **Nel party:** una sessione WonderFlix dell'utente è nel canale del gruppo (`PartyRegistry` di 1.0.0: l'app fa `Join` sul canale entrando in un gruppo) e l'utente è ancora tra i partecipanti del gruppo SyncPlay (una voce del registro può essere vecchia, es. un `Leave` non riuscito).
- Il plugin ascolta `ISessionManager.SessionStarted` / `SessionEnded` (solo client WonderFlix) e i propri `Join` / `Leave`: quando lo stato di un utente cambia manda `FriendsChanged` ai suoi amici online, **al massimo uno ogni 2 s per utente** (raccoglie i cambi ravvicinati, es. riconnessioni).
- `Join` / `Leave` del canale e `POST Parties/{groupId}` contano come cambio di presenza (stesso raggruppamento di 2 s): la registrazione arriva dopo il `Join`, quando il party non era ancora visibile, e gli amici lo rileggono.

### 6.4 Registro dei party (RAM)

- Per ogni gruppo SyncPlay registrato: `GroupId`, `CreatorId`, `Mode` (`Public` | `Friends` | `Private`), `Code` (solo `Private`), `Invited` (insieme di id utente).
- **Registrazione** (`POST Parties/{groupId}`): solo se chi chiama è l'**unico** partecipante del gruppo (l'app registra appena creato il gruppo, prima della coda: un gruppo con altri dentro, es. di jellyfin-web, non si nasconde da fuori); altrimenti 403. Una sola volta (la seconda risponde 409); il creatore è chi registra. Un gruppo già dimenticato dalla pulizia (sotto) non si registra più: 409.
- **Visibile a U** se: U è partecipante del gruppo, oppure U è il creatore, oppure `Mode == Public`, oppure `Mode == Friends` e U è amico del creatore, oppure U è in `Invited`.
- **Gruppi non registrati** (creati da jellyfin-web, da app 0.5.x o non ancora registrati): trattati come `Public`, ma solo dopo **10 s** (`FirstSeen`, in RAM). Il conto parte la prima volta che il gruppo compare in un `GET Parties` di chiunque; un gruppo mai elencato non compare nemmeno in `GET Friends`. Così un party privato appena creato non compare mai per un attimo come pubblico.
- **Pulizia:** ogni 5 minuti (con la pulizia del registro di 1.0.0) un party sparisce quando nessuna sessione WonderFlix vede più il suo gruppo; il suo codice non vale più. Il suo id resta per 24 h (al massimo 1000, poi si dimentica il più vecchio): se il gruppo ricompare (per esempio un errore di Jellyfin nella lettura della coda, §14) non diventa pubblico, lo vedono solo i partecipanti (che lo vedono senza modalità, come "Pubblico").

### 6.5 Codici

- 6 caratteri da `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (31 simboli, senza 0/O/1/I/L), generati con `RandomNumberGenerator`; unici tra i party attivi. In rete viaggiano senza trattino; l'app mostra `K7P-Q2X`.
- `POST Parties/Join {Code}`: il codice si normalizza (maiuscole, senza spazi e trattini). Se corrisponde a un party attivo l'utente entra in `Invited` (così il party compare nel suo elenco) e la risposta è `{GroupId}`; l'app poi entra nel gruppo con SyncPlay come oggi.
- Codice sbagliato o party finito: **403**. 403 anche se chi chiama non può vedere il gruppo (coda in una libreria a cui non ha accesso): l'app mostra "Codice non valido o party finito".
- **Ogni tentativo** conta per il limite: oltre 5 al minuto per utente, **429**.

### 6.6 Inviti

- `POST Parties/{groupId}/Invites {UserIds}`: chi chiama deve essere partecipante del gruppo; ogni destinatario deve essere suo amico e non già partecipante (gli altri si saltano in silenzio). I destinatari entrano in `Invited` e ricevono `PartyInvite` sulle sessioni aperte che vedono il gruppo (sotto).
- Oltre 20 destinatari al minuto (§6.9) si invitano quelli che ci stanno e la risposta è 429.
- L'avviso `PartyInvite` arriva solo alle sessioni degli invitati che possono vedere la coda del gruppo (da Jellyfin: accesso alla libreria degli elementi in coda); il permesso di vederlo (`Invited`) resta comunque.

### 6.7 Endpoint (nuovi, sotto `/WonderFlixWatchParty`)

Tutti autenticati come in 1.0.0 (`[Authorize]`, chi chiama da `UserId` + `DeviceId` + `Client`). Il plugin **non risponde mai 404** (404 = plugin assente, Spec E §6.2): "non trovato" diventa 403. JSON PascalCase, id in formato `N`.

| Metodo e percorso | Corpo / risposta |
|---|---|
| `GET Info` | `{Version, Protocol: 1, Features: ["friends", "parties"]}` |
| `GET Friends` | `{Friends: [{UserId, Name, Online, Party: {GroupId, Title}}], Incoming: [{UserId, Name}], Outgoing: [{UserId, Name}]}`; `Party` solo per gli amici online in un party visibile, e solo se chi chiama può vedere la coda del gruppo dalla propria sessione; senza la sessione di chi chiama nessun `Party` |
| `GET Users/Search?q=` | `[{UserId, Name, Relation}]` (`Relation`: `None`, `Friend`, `Incoming`, `Outgoing`) |
| `POST Friends/Requests/{userId}` | 204; 409 se non ammessa (§6.2) |
| `POST Friends/Requests/{userId}/Accept` · `/Decline` | 204; 403 se la richiesta non c'è |
| `DELETE Friends/Requests/{userId}` | 204 (annulla la propria) |
| `DELETE Friends/{userId}` | 204 |
| `POST Parties/{groupId}` `{Mode}` | `{Code}` (omesso se non privato); 400 se la modalità non è valida; 403 se chi chiama non è l'unico partecipante; 409 se già registrato o già dimenticato (§6.4) |
| `GET Parties` | `[{GroupId, Name, Participants, State, Mode}]`: i party visibili (§6.4), dall'elenco SyncPlay visto dalla sessione di chi chiama |
| `GET Parties/{groupId}` | `{Mode, Code}`: solo per i partecipanti (il codice di un privato); un gruppo non registrato risponde `{Mode: "Public"}`; 403 altrimenti |
| `POST Parties/Join` `{Code}` | `{GroupId}`; 403 codice non valido, party finito o gruppo non visibile a chi chiama; 429 troppi tentativi |
| `POST Parties/{groupId}/Invites` `{UserIds}` | 204; 403 se non partecipante; 429 oltre il limite (§6.6) |

`Party` in `GET Friends` è presente solo se l'amico è online e in un party visibile a chi chiama (§6.3, §6.4); `Title` è la parte del nome dopo "Host · ".

Gli endpoint dei party vogliono la sessione di chi chiama (i gruppi SyncPlay si vedono da una sessione): senza, 409.

I campi `null` mancano dalle risposte (`WhenWritingNull`): `Code`, `Party`.

### 6.8 Avvisi

Stesso trasporto di 1.0.0 (`SendString`, chiave `WonderFlixWatchParty`), **solo alle sessioni con client WonderFlix**. Questi eventi non hanno `GroupId` del canale: le app 0.5.x li scartano (tipo sconosciuto).

| `Type` | A chi | Campi |
|---|---|---|
| `FriendRequest` | sessioni di B quando A gli chiede l'amicizia | `FromUserId`, `FromName` |
| `FriendsChanged` | le due persone a ogni accetta / rifiuta / annulla / rimuovi / richiesta incrociata; gli amici online a ogni cambio di presenza (§6.3) | — (l'app rilegge `GET Friends`) |
| `PartyStarted` | quando il gruppo ha la coda (sotto): `Public` → le sessioni WonderFlix di tutti tranne il creatore; `Friends` → quelle degli amici del creatore in quel momento; `Private` → nessuno. Solo le sessioni che possono vedere la coda e i cui utenti non fanno già parte del gruppo | `GroupId`, `Name`, `Mode` |
| `PartyInvite` | sessioni degli invitati che possono vedere la coda del gruppo (§6.6) | `GroupId`, `Name`, `FromName` |

`PartyStarted` (Pubblico e Solo amici) non parte alla registrazione: l'app registra il gruppo prima di mandare la coda, e un gruppo senza coda lo vede chiunque (Jellyfin controlla l'accesso alla libreria sugli elementi in coda). `PartyAnnouncer` controlla ogni 2 s, per al massimo 20 s, che il gruppo abbia la coda (stato diverso da `Idle`); poi manda l'avviso alle sessioni della tabella. Se nel frattempo il gruppo o il party non ci sono più, o la coda non arriva in 20 s, niente avviso. Il `POST Parties/{groupId}` non aspetta l'invio.

I gruppi non registrati (jellyfin-web, app 0.5.x) non hanno avviso: compaiono solo nell'elenco, dopo 10 s (§6.4).

### 6.9 Limiti e log

| Cosa | Limite | Oltre |
|---|---|---|
| Amici per utente | 200 | 409 |
| Richieste inviate in sospeso | 50 | 409 |
| Nuove richieste | 20 all'ora per utente | 429 |
| Ricerche | 30 al minuto per utente | 429 |
| Codici provati | 5 al minuto per utente | 429 |
| Inviti | 20 destinatari al minuto per utente | 429 (invitati quelli che ci stanno) |

Log come in 1.0.0: mai testi o codici, solo id e tipi di esito; `Debug` per le operazioni, `Warning` per il file illeggibile, gli errori di scrittura e gli errori di SyncPlay (§14).

## 7. App: il nucleo sociale

### 7.1 `lib/core/social/` (Dart puro)

- Modelli: `PartyMode` (`public` / `friends` / `private`, in rete `Public` / `Friends` / `Private`; sta in `lib/core/syncplay/party_mode.dart`, perché lo porta anche `GroupInfo`), `FriendEntry {userId, name, online, party: (groupId, title)?}`, `PersonEntry {userId, name}` (richieste in arrivo e inviate), `FriendsSnapshot {friends, incoming, outgoing}`, `UserSearchResult {userId, name, relation}`, `PartyDetails {mode, code}`. L'app legge `GET Parties` come `GroupInfo` con `mode` (`partyGroupFromJson`), lo stesso modello di `/SyncPlay/List`.
- `formatPartyCode('K7PQ2X') → 'K7P-Q2X'`, `normalizePartyCode` (maiuscole, senza spazi e trattini).
- `SocialApi` (HTTP verso gli endpoint §6.7, con `JellyfinHttp` e `quietStatuses` come `PartyChannelApi`): errori come `SocialException(SocialFailure.{unavailable, forbidden, conflict, rateLimited, network})`; 400 vale come `forbidden`, come 401 e 403.
- `parseSocialEvent(payload)` → `FriendRequestEvent`, `FriendsChangedEvent`, `PartyStartedEvent`, `PartyInviteEvent`, oppure `null` (gli eventi del canale con `GroupId` restano a `parsePartyEvent`).

### 7.2 Disponibilità

`SocialAvailability` (`Notifier`): chiede `Info` dopo il login e a ogni connessione del WebSocket (anche la prima: un controllo fallito al login si ripete); una risposta arrivata dopo un cambio di utente si scarta; `friends` e `parties` valgono se `Features` li contiene. 400/401/403/404 → nessuna funzione (l'app si comporta come la 0.5.1). La diagnostica aggiunge la riga "Funzioni del plugin: amici, party" (o "nessuna"; assente se il plugin non risponde).

Dal login, e a ogni cambio di utente, fino alla prima risposta certa di `Info` le funzioni sono `SocialFeatures.unknown` (`known: false`): niente elenco dei party né schede (l'elenco di Jellyfin non è filtrato per modalità), niente icona Amici, e "Guarda insieme" aspetta al massimo 2 s che diventino note prima di decidere se mostrare il menu (§9.1). I controlli successivi non tornano a `unknown`.

Un errore di rete, un timeout o un 5xx (anche 409, 429 o una risposta di forma inattesa) non dice nulla del plugin: prima della prima risposta lascia `unknown` e si riprova ogni 30 s e a ogni connessione del WebSocket; dopo, restano le funzioni che ci sono. Solo 400/401/403/404 valgono come plugin assente. Una risposta riuscita non viene scavalcata dall'errore di un controllo già in corso quando è arrivata (al login partono insieme il controllo del login e quello della prima connessione del WebSocket); quello di un controllo partito dopo vale (plugin tolto e server riavviato, §10).

`party_channel.dart` continua ad accettare solo `Protocol == 1`: niente da cambiare lì.

### 7.3 Avvisi del plugin

`SocialEvents` ascolta gli eventi del server (`PartyChannelReceived`) e passa a `parseSocialEvent` quelli che `parsePartyEvent` non riconosce; li smista a `FriendsController` (`FriendRequest`, `FriendsChanged`) e a `WatchPartyInvites` / `WatchPartyDirectory` (`PartyStarted`, `PartyInvite`). Niente eliminazione dei doppioni: gli avvisi sociali non hanno un Id; `FriendsChanged` fa solo rileggere e una `FriendRequest` doppia rimostra la stessa scheda. Il canale del gruppo (`parsePartyEvent`) scarta questi tipi senza scriverli nel log.

## 8. App: amici

### 8.1 `FriendsController`

- Stato `FriendsState {snapshot, loading, failed}`; vivo per tutta la sessione dell'utente (si azzera al logout).
- Rilegge `GET Friends` quando il pannello si apre, a ogni `FriendRequest` / `FriendsChanged`, a ogni riconnessione e dopo ogni azione riuscita.
- Azioni: `request`, `accept`, `decline`, `cancel`, `remove`, `search(text)` (attesa di 300 ms dall'ultima lettera; richieste superate scartate). Un errore mostra la snackbar `friendsActionFailed`; 429 mostra `friendsTooMany`.
- `incomingCount` per il numero sull'icona.

### 8.2 Icona nella barra

`FriendsButton` tra `WatchPartyButton` e l'avatar: icona Lucide `users`, tooltip "Amici", numero dorato (come `PartyChip`) con le richieste in arrivo. Compare solo con `friends` disponibile e con l'accesso ai watch party (`syncPlayAccessProvider.canJoin`).

### 8.3 Pannello

- **Posizione:** nella shell, sopra la barra e la pagina: `Positioned(top: 0, right: 0, bottom: 0)`, largo 360 px, sfondo `WfColors.surface`; il resto della finestra scurito (`Colors.black54`). Si chiude con ×, Esc (consumato dal pannello, non torna indietro di pagina) o un clic sullo scuro. Con il pannello aperto Alt+←, il tasto indietro e il tasto indietro del mouse chiudono il pannello invece di cambiare pagina; Esc con un menu aperto chiude prima il menu. Entrata e uscita come `TracksPanelHost` (entra tutto da destra; con "Ridotte" solo dissolvenza). Mentre carica la prima volta il pannello resta vuoto (niente indicatore che gira).
- **Contenuto**, dall'alto:
  1. Titolo "Amici" + ×.
  2. Campo "Cerca per nome" (prende il fuoco all'apertura). Con 2+ lettere i risultati sostituiscono le sezioni 3–5. Ogni risultato: iniziale, nome, azione secondo la relazione — `None` → **Aggiungi**; `Outgoing` → "Inviata" + **Annulla**; `Incoming` → **Accetta**; `Friend` → "Amici ✓" (non cliccabile). Nessun risultato: "Nessun utente trovato". La ricerca si ripete quando cambia la lista amici.
  3. **"Ho un codice"** (§9.4), solo con la funzione `parties`.
  4. **Richieste ({n})**, solo se ce ne sono: in arrivo con **Accetta / Rifiuta**, poi quelle inviate con "In attesa" + **Annulla**.
  5. **Amici**: online prima (pallino verde), poi offline (nome attenuato), in ordine alfabetico. Amico in un party visibile: seconda riga "Nel watch party: {titolo}" + **Unisciti** (nascosto se siamo già in quel gruppo, e durante "Conferma rimozione"). **⋯** (sempre visibile) → "Rimuovi dagli amici" → la riga mostra **Conferma rimozione** per 4 s.
  6. Vuoto: "Nessun amico ancora. Cerca qualcuno per nome qui sopra."
- **Errore** del caricamento: "Amici non disponibili" + **Riprova**.
- Le liste lunghe scorrono dentro il pannello; il campo di ricerca resta fermo in alto.
- **Unisciti** ed **Entra** (§9.4) chiudono il pannello solo se l'ingresso nel gruppo riesce.

### 8.4 Scheda della richiesta

Su `FriendRequest`, con l'app aperta e il player chiuso: scheda nello stesso posto dell'invito (in alto a destra), "{nome} vuole essere tuo amico" con **Accetta / Rifiuta / ×**, per 10 s. L'invito ai watch party e la richiesta stanno in colonna (invito sopra), 8 px l'una dall'altra. I pulsanti della scheda vanno a capo (`Wrap`) se non c'è spazio. Con il player aperto si aggiorna solo il numero sull'icona.

## 9. App: modalità e inviti

### 9.1 Menu delle modalità

- Con `parties` disponibile, "Guarda insieme" fuori da un gruppo (scheda e player) apre un menu ancorato al pulsante (`wfPopUpAnimation`) con tre voci, ognuna icona + titolo + riga di spiegazione:
  - `globe` **Pubblico** — "Lo vedono tutti, avviso a tutti";
  - `users` **Solo amici** — "Lo vedono i tuoi amici, avviso solo a loro";
  - `lock` **Privato** — "Nessun avviso; si entra con il codice o con un invito".
- L'ultima modalità usata è evidenziata (bordo oro) ed è salvata in `party.lastMode` (`SharedPreferences`; predefinita Pubblico).
- Senza `parties`: nessun menu, il party nasce come oggi. Dentro un gruppo "Guarda insieme" cambia la coda, senza menu.
- Finché le funzioni del plugin non sono note (§7.2), si aspetta al massimo 2 s; poi, se ancora ignote, si parte senza menu.
- Il menu è largo 380 px; se sotto il pulsante non c'è posto (nel player), si apre sopra il pulsante. La modalità scelta si salva subito.
- Nel player: con il menu aperto i controlli non si nascondono e la schermata di pausa aspetta; un secondo clic su "Guarda insieme" non apre un altro menu; il punto di partenza si legge dopo la scelta (il video intanto va avanti).
- Se il player si chiude da solo (fine del video, tasto Stop) con un menu aperto sopra (modalità, distintivo, inviti), prima si chiudono i menu.

### 9.2 Creazione

`startWatchParty(context, ref, item, start:, mode:)`:

1. crea il gruppo come oggi;
2. con `parties` disponibile, il party si registra (`POST Parties/{groupId} {mode}`) dentro `WatchPartySession.create`, appena il gruppo esiste e **prima della coda** (§6.4: solo l'unico partecipante registra). La registrazione ha un limite di 5 s, ben sotto i 10 s dopo cui il plugin mostra come pubblico un gruppo non registrato;
3. poi la coda, come oggi;
4. se la registrazione fallisce o scade: si esce dal gruppo, ma solo se si è ancora in quel gruppo, e si mostra "Non è stato possibile creare il watch party". Nessun party è meglio di un privato visibile a tutti (§6.4: dopo 10 s un gruppo non registrato diventa pubblico);
5. se la registrazione (riuscita o no) finisce quando siamo già usciti dal gruppo, o siamo in un altro: niente coda, nessuna uscita, errore "Questo watch party non esiste più".

Per un privato, il codice ricevuto si mostra subito nella pillola del player: "Party privato · codice K7P-Q2X" (avviso del party, una volta).

### 9.3 Il party corrente

`CurrentParty` (`currentPartyProvider`, `Notifier`): `{groupId, mode, code, invited, announceCode}`. Entrando in un gruppo (creato o raggiunto) legge `GET Parties/{groupId}` → modalità e codice; si azzera all'uscita. Serve al menu del chip e al distintivo nel player.

- Il codice c'è solo per i privati, anche se il plugin lo manda.
- Senza `parties` nessuna lettura.
- Una lettura finita dopo un cambio di gruppo si scarta e non sovrascrive il party appena registrato da noi (§9.2, che lo scrive con la risposta della registrazione).
- Una registrazione o un invito per un gruppo che non è più il nostro si ignora.
- `invited`: gli amici invitati da noi in questo party (§9.5).
- `announceCode`: il codice di un privato appena creato da noi si mostra una volta nella pillola (lo fa il distintivo del party).

### 9.4 Codice

- **Mostrarlo:** nel menu del chip "Nel watch party" e nel menu del distintivo del party nel player, una voce `Codice K7P-Q2X` con icona `copy`: copia `K7P-Q2X` negli appunti e mostra "Codice copiato" (snackbar nella shell, pillola nel player). Solo per i privati.
- **Usarlo:** nel pannello Amici, "Ho un codice" (icona `ticket`) apre un campo, che prende il focus (6 caratteri, maiuscole automatiche, il trattino si aggiunge da sé) + **Entra** (o Invio) → `POST Parties/Join` → `joinWatchParty(groupId)`; se l'ingresso riesce il pannello si chiude.
  - Esc nel campo lo svuota e lo chiude, e il focus torna su "Ho un codice"; un secondo Esc chiude il pannello.
  - Durante una ricerca il campo si nasconde ma tiene il testo.
  - Backspace/Canc accanto al trattino tolgono il carattere vicino (il trattino si rimetterebbe da sé).
  - Con meno di 6 caratteri appare "Codice non valido o party finito" senza chiamare il plugin.
  - Errori: 403 → "Codice non valido o party finito"; 429 → "Troppi tentativi, riprova tra un minuto"; altri errori (rete, 404, 409) → "Operazione non riuscita". Il testo dell'errore sta sotto il campo.

### 9.5 Invita amici

- Voce **"Invita amici"** negli stessi due menu (chip e distintivo), con `friends` e `parties` disponibili. Apre un secondo menu ancorato allo stesso punto con gli amici non partecipanti: online prima, poi offline (attenuati). Nessuno: "Nessun amico da invitare" (non cliccabile).
- La lista degli amici si rilegge prima di aprire il menu, aspettando al massimo 2 s; poi vale quella che l'app ha. Senza nessuna lista: "Amici non disponibili" (non cliccabile).
- Un secondo "Invita amici" mentre uno è in corso non fa nulla. Se intanto cambiano la pagina, un menu sopra o il gruppo, il menu non si apre; se il gruppo cambia a menu aperto, l'invito non parte.
- Un clic manda l'invito a quell'amico (`POST …/Invites`); l'esito è una snackbar nella shell e la pillola nel player: "Invito mandato a {nome}"; 429 → "Troppe richieste, riprova più tardi"; altri errori → "Operazione non riuscita". Finché si resta nel party, quell'amico compare come "Invitato ✓" (non cliccabile): vale per gli inviti mandati da noi in questo party.
- L'invitato con l'app aperta e il player chiuso vede la scheda "{nome} ti invita" con il titolo e **Unisciti** (10 s), come la scheda d'avviso di oggi.

### 9.6 Elenco dei party e schede

- Con `parties` disponibile, `WatchPartyDirectory` legge `GET Parties` invece di `/SyncPlay/List` (stessi tempi: ogni 30 s, alla chiusura del player, all'apertura del menu) e rilegge subito a ogni `PartyStarted` / `PartyInvite`. Ogni riga del chip mostra l'icona della modalità (`globe` / `users` / `lock`); le righe dall'elenco di Jellyfin non hanno icona.
- L'elenco si rilegge anche a ogni riconnessione del WebSocket e quando le funzioni del plugin diventano note o cambiano. Passando a `parties`, l'elenco di Jellyfin si svuota subito, e una risposta lenta dell'altra fonte si scarta. Finché le funzioni non sono note (§7.2), niente elenco né schede.
- `WatchPartyInvites` tiene un `WatchPartyInvite` (gruppo + chi invita): con `parties` disponibile la scheda nasce da `PartyStarted` ("{host} ha avviato un watch party") e da `PartyInvite` ("{nome} ti invita"), non più dal confronto tra due letture; a ogni avviso del plugin anche l'elenco si rilegge. Restano le regole di oggi (non dentro un gruppo, non con il player aperto, non per i gruppi già visitati, 10 s). Senza `parties`: logica di oggi.

## 10. Senza plugin ed errori

| Situazione | Comportamento |
|---|---|
| Plugin assente o 1.0.0 | come la 0.5.1: niente icona Amici, menu, codice, inviti; elenco da `/SyncPlay/List` |
| `Info` non risponde (rete, timeout, 5xx) | prima della prima risposta resta `unknown` e si riprova ogni 30 s e alla riconnessione; dopo restano le funzioni già note (§7.2) |
| `Info` risponde 400/401/403/404 | come plugin assente |
| Plugin tolto mentre l'app gira | `GET Parties` risponde 404 e resta l'ultimo elenco fino alla riconnessione (riavvio di Jellyfin); poi `Info` risponde 404 → come plugin assente |
| Registrazione del party fallita | si esce dal gruppo + errore (§9.2) |
| Registrazione oltre 5 s | errore di creazione, si esce dal gruppo (§9.2) |
| Registrazione finita dopo l'uscita dal gruppo | niente coda, "Questo watch party non esiste più" (§9.2) |
| Azione sugli amici fallita | snackbar; lo stato si rilegge |
| `GET Parties` fallisce | resta l'ultimo elenco; riga di log `info` come oggi |
| Avviso perso (WebSocket giù) | alla riconnessione si rileggono amici ed elenco |

## 11. Testi nuovi (ARB, it + en)

| Chiave | it | en |
|---|---|---|
| `friendsTitle` | Amici | Friends |
| `friendsClose` | Chiudi | Close |
| `friendsSearchHint` | Cerca per nome | Search by name |
| `friendsSearchEmpty` | Nessun utente trovato | No users found |
| `friendsAdd` | Aggiungi | Add |
| `friendsSent` | Inviata | Sent |
| `friendsCancel` | Annulla | Cancel |
| `friendsAccept` | Accetta | Accept |
| `friendsDecline` | Rifiuta | Decline |
| `friendsAlready` | Amici | Friends |
| `friendsRequests(count)` | Richieste ({count}) | Requests ({count}) |
| `friendsPending` | In attesa | Pending |
| `friendsEmpty` | Nessun amico ancora. Cerca qualcuno per nome qui sopra. | No friends yet. Search for someone by name above. |
| `friendsInParty(title)` | Nel watch party: {title} | In a watch party: {title} |
| `friendsMore` | Altre azioni | More actions |
| `friendsRemove` | Rimuovi dagli amici | Remove friend |
| `friendsRemoveConfirm` | Conferma rimozione | Confirm removal |
| `friendsUnavailable` | Amici non disponibili | Friends unavailable |
| `friendsActionFailed` | Operazione non riuscita | Something went wrong |
| `friendsTooMany` | Troppe richieste, riprova più tardi | Too many requests, try again later |
| `friendsOnline` / `friendsOffline` | Online / Offline | Online / Offline |
| `friendRequestTitle(name)` | {name} vuole essere tuo amico | {name} wants to be your friend |
| `partyModePublic` / `…Hint` | Pubblico / Lo vedono tutti, avviso a tutti | Public / Everyone sees it and gets notified |
| `partyModeFriends` / `…Hint` | Solo amici / Lo vedono i tuoi amici, avviso solo a loro | Friends only / Only your friends see it and get notified |
| `partyModePrivate` / `…Hint` | Privato / Nessun avviso; si entra con il codice o con un invito | Private / No notifications; join with the code or an invite |
| `partyCreateFailed` | Non è stato possibile creare il watch party | Couldn't create the watch party |
| `partyHaveCode` | Ho un codice | I have a code |
| `partyCodeHint` | Codice del party | Party code |
| `partyCodeJoin` | Entra | Join |
| `partyCodeInvalid` | Codice non valido o party finito | Invalid code or the party has ended |
| `partyCodeTooMany` | Troppi tentativi, riprova tra un minuto | Too many attempts, try again in a minute |
| `partyCode(code)` | Codice {code} | Code {code} |
| `partyCodeCopied` | Codice copiato | Code copied |
| `partyPrivateCreated(code)` | Party privato · codice {code} | Private party · code {code} |
| `partyInviteFriends` | Invita amici | Invite friends |
| `partyInvited` | Invitato | Invited |
| `partyInviteSent(name)` | Invito mandato a {name} | Invite sent to {name} |
| `partyNoFriendsToInvite` | Nessun amico da invitare | No friends to invite |
| `partyInviteTitle(name)` | {name} ti invita | {name} invites you |

Se una chiave equivalente esiste già (es. "Riprova", "Annulla"), il piano la riusa invece di crearne una nuova. Riusate anche: `watchPartyJoin` (Unisciti), `friendsUnavailable` (menu degli inviti senza lista), `friendsActionFailed` (esiti di inviti e codice), `friendsTooMany` (429 degli inviti; nel player la pillola `inviteRateLimited` usa questo testo, il codice ha `partyCodeTooMany`), `watchPartyGone` (registrazione finita dopo l'uscita dal gruppo).

## 12. Test

- **Plugin (xUnit, `Jellyfin.Plugin.WonderFlixWatchParty.Tests`):** `FriendStore` (salvataggio atomico, ricarica, file illeggibile → `.bad`, utenti spariti); `FriendService` (richiesta, incrociata → amicizia, accetta, rifiuta, annulla, rimuovi, casi rifiutati, limiti); ricerca (contiene, maiuscole, minimo 2, massimo 10, esclusi sé e disabilitati, relazione); `PartyDirectory` (registrazione una volta sola e solo da partecipante, visibilità per modalità, invitati, 10 s dei non registrati con `FakeTimeProvider`, pulizia); codici (alfabeto, unicità, normalizzazione, 5 tentativi); inviti (solo amici, solo partecipanti); destinatari di ogni avviso; presenza (online/offline, raggruppamento di 2 s); controller (codici HTTP, mai 404).
- **App:** `FakeSocialApi`; `parseSocialEvent`; `formatPartyCode` / `normalizePartyCode`; `SocialAvailability` (Features, 404, riconnessione); `FriendsController` (ricarica sugli avvisi, ricerca con attesa e richieste superate, errori); widget test di icona e numero, pannello (stati, ricerca, azioni, Esc, conferma rimozione), scheda della richiesta, menu delle modalità e ultima usata, registrazione fallita → uscita, codice (mostra, copia, entra, errori), "Invita amici", elenco dal plugin con icone, schede da `PartyStarted` / `PartyInvite`; senza plugin: tutto come la 0.5.1.
- **Prova manuale** sul server reale con due istanze (`WONDERFLIX_PROFILE=b`) e due utenti Jellyfin diversi.

## 13. Piani e release

- **12a — amici da capo a fondo:** plugin (`FriendStore`, `FriendService`, ricerca, presenza, endpoint Friends/Users, `FriendRequest` / `FriendsChanged`, `Features: ["friends"]`) + app (`lib/core/social/` per la parte amici, `SocialAvailability`, `SocialEvents`, `FriendsController`, icona, pannello senza "Ho un codice", scheda della richiesta). Fino al 12b `Party` in `GET Friends` è sempre `null`. Il plugin si prova copiandolo a mano sul server (`ssh ultra`, come in 10a), senza release. Fine: due utenti diventano amici e si vedono online.
- **12b — modalità da capo a fondo:** plugin (`PartyDirectory`, codici, inviti, endpoint Parties, `PartyStarted` / `PartyInvite`, `Features: [..., "parties"]`) + app (menu, registrazione, `CurrentParty`, codice nei menu e nel pannello, "Invita amici", elenco dal plugin, schede dagli avvisi, "Nel watch party" nella lista amici). Poi:
  1. plugin **1.1.0**: tag `watch-party-plugin-v1.1.0` → pre-release, voce nel `manifest.json`, cartella copiata a mano tolta dal server, aggiornamento dal Catalogo;
  2. app **0.6.0 obbligatoria** (`<!-- wonderflix:min-version=0.6.0 -->`), da pubblicare solo dopo il plugin;
  3. commento e chiusura di #5 e #6 con l'ok dell'utente.
- `docs/RELEASING.md`: nessuna procedura nuova; si aggiungono solo le versioni di Jellyfin dei test (quella del server) e del plugin (10.11.0) e che i dati del plugin stanno in `plugins/configurations/WonderFlixWatchParty/`.

## 14. Rischi e punti da verificare

- **`ISyncPlayManager.ListGroups`** in Jellyfin 10.11: firma e risultato (gruppi visti dalla sessione) da verificare con un prototipo all'inizio del 12b, come in 10a.
- **`IApplicationPaths.PluginConfigurationsPath`** scrivibile su Ultra.cc (seedbox senza root): da verificare all'inizio del 12a (il plugin scrive già la sua configurazione XML lì).
- **`SessionStarted` / `SessionEnded`**: arrivano anche per le sessioni WonderFlix che non hanno ancora il WebSocket? Da verificare nel 12a; in alternativa la presenza si calcola alla lettura e gli avvisi di presenza si mandano dal `PartyRegistry` e da un controllo ogni 30 s.
- **Due istanze sulla stessa macchina** devono usare due utenti diversi, altrimenti la presenza di uno nasconde l'uscita dell'altro.
- **Esc nella shell:** oggi torna indietro di pagina (`BackNavigationHandler`); con il pannello aperto deve chiuderlo e basta (come l'anteprima della card).
- **Secondo menu "Invita amici" dentro il player:** il player non dà il focus ai suoi elementi; i menu esistenti (distintivo) funzionano già, il secondo va aperto dopo la chiusura del primo.
- **Jellyfin 10.11.9, coda con un elemento cancellato:** `Group.HasAccessToQueue` va in `NullReferenceException` (anche in `ListGroups` / `GetGroup`). Il plugin risponde "nessun gruppo" (niente 500 da `Friends` o `Parties`) e lo scrive nel log come `Warning` una volta ogni 10 minuti per gruppo (le ripetizioni a `Debug`). Il party sparisce alla pulizia e, se il gruppo torna leggibile, non diventa pubblico (§6.4).
- **Copiare la dll sopra quella caricata** (prova a mano sul server) fa cadere il vecchio processo in chiusura (`BadImageFormatException: Bad IL range`); il riavvio va comunque a buon fine.
