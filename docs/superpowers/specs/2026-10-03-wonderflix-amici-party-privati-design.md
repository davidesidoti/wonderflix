# WonderFlix — Spec F: amici e party privati

- **Data:** 2026-10-03
- **Stato:** approvato; piano 12a realizzato (`docs/superpowers/plans/2026-10-03-wonderflix-12a-amici.md`); piano 12b da scrivere
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
  FriendService (richieste, regole)      ├─ SocialHub ── SocialController (REST)
  PresenceTracker (sessioni WonderFlix)  │            └─ avvisi (SendString)
  PartyDirectory (modalità, codici,     ─┘
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
- **Nel party:** l'utente è registrato nel `PartyRegistry` di 1.0.0 (l'app fa `Join` sul canale entrando in un gruppo).
- Il plugin ascolta `ISessionManager.SessionStarted` / `SessionEnded` (solo client WonderFlix) e i propri `Join` / `Leave`: quando lo stato di un utente cambia manda `FriendsChanged` ai suoi amici online, **al massimo uno ogni 2 s per utente** (raccoglie i cambi ravvicinati, es. riconnessioni).

### 6.4 Registro dei party (RAM)

- Per ogni gruppo SyncPlay registrato: `GroupId`, `CreatorId`, `Mode` (`Public` | `Friends` | `Private`), `Code` (solo `Private`), `Invited` (insieme di id utente), `RegisteredAt`.
- **Registrazione** (`POST Parties/{groupId}`): solo un partecipante del gruppo (come il `Join` di 1.0.0); una sola volta (la seconda risponde 409); il creatore è chi registra.
- **Visibile a U** se: U è partecipante del gruppo, oppure `Mode == Public`, oppure `Mode == Friends` e U è amico del creatore, oppure U è in `Invited`.
- **Gruppi non registrati** (creati da jellyfin-web, da app 0.5.x o non ancora registrati): trattati come `Public`, ma solo dopo **10 s** dalla prima volta che il plugin li vede (`FirstSeen`, in RAM). Così un party privato appena creato non compare mai per un attimo come pubblico.
- **Pulizia:** quando il gruppo SyncPlay non esiste più, la voce sparisce (stessa pulizia del registro di 1.0.0).

### 6.5 Codici

- 6 caratteri da `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (31 simboli, senza 0/O/1/I/L), generati con `RandomNumberGenerator`; unici tra i party attivi. In rete viaggiano senza trattino; l'app mostra `K7P-Q2X`.
- `POST Parties/Join {Code}`: il codice si normalizza (maiuscole, senza spazi e trattini). Se corrisponde a un party attivo l'utente entra in `Invited` (così il party compare nel suo elenco) e la risposta è `{GroupId}`; l'app poi entra nel gruppo con SyncPlay come oggi.
- Codice sbagliato o party finito: **403**. Oltre **5 tentativi sbagliati al minuto** per utente: **429**.

### 6.6 Inviti

- `POST Parties/{groupId}/Invites {UserIds}`: chi chiama deve essere partecipante del gruppo; ogni destinatario deve essere suo amico e non già partecipante (gli altri si saltano in silenzio). I destinatari entrano in `Invited` e ricevono `PartyInvite` sulle sessioni aperte.

### 6.7 Endpoint (nuovi, sotto `/WonderFlixWatchParty`)

Tutti autenticati come in 1.0.0 (`[Authorize]`, chi chiama da `UserId` + `DeviceId` + `Client`). Il plugin **non risponde mai 404** (404 = plugin assente, Spec E §6.2): "non trovato" diventa 403. JSON PascalCase, id in formato `N`.

| Metodo e percorso | Corpo / risposta |
|---|---|
| `GET Info` | `{Version, Protocol: 1, Features: ["friends", "parties"]}` |
| `GET Friends` | `{Friends: [{UserId, Name, Online, Party: {GroupId, Title} \| null}], Incoming: [{UserId, Name}], Outgoing: [{UserId, Name}]}`; `Party` è omesso o `null` se l'amico non è in un party visibile |
| `GET Users/Search?q=` | `[{UserId, Name, Relation}]` (`Relation`: `None`, `Friend`, `Incoming`, `Outgoing`) |
| `POST Friends/Requests/{userId}` | 204; 409 se non ammessa (§6.2) |
| `POST Friends/Requests/{userId}/Accept` · `/Decline` | 204; 403 se la richiesta non c'è |
| `DELETE Friends/Requests/{userId}` | 204 (annulla la propria) |
| `DELETE Friends/{userId}` | 204 |
| `POST Parties/{groupId}` `{Mode}` | `{Code}` (`null` se non privato); 403 se non partecipante; 409 se già registrato |
| `GET Parties` | `[{GroupId, Name, Participants, State, Mode}]`: i party visibili (§6.4), dall'elenco SyncPlay visto dalla sessione di chi chiama |
| `GET Parties/{groupId}` | `{Mode, Code}`: solo per i partecipanti (il codice di un privato); 403 altrimenti |
| `POST Parties/Join` `{Code}` | `{GroupId}`; 403 codice non valido; 429 troppi tentativi |
| `POST Parties/{groupId}/Invites` `{UserIds}` | 204; 403 se non partecipante |

`Party` in `GET Friends` è presente solo se l'amico è in un party visibile a chi chiama; `Title` è la parte del nome dopo "Host · ".

### 6.8 Avvisi

Stesso trasporto di 1.0.0 (`SendString`, chiave `WonderFlixWatchParty`), **solo alle sessioni con client WonderFlix**. Questi eventi non hanno `GroupId` del canale: le app 0.5.x li scartano (tipo sconosciuto).

| `Type` | A chi | Campi |
|---|---|---|
| `FriendRequest` | sessioni di B quando A gli chiede l'amicizia | `FromUserId`, `FromName` |
| `FriendsChanged` | le due persone a ogni accetta / rifiuta / annulla / rimuovi / richiesta incrociata; gli amici online a ogni cambio di presenza (§6.3) | — (l'app rilegge `GET Friends`) |
| `PartyStarted` | alla registrazione: `Public` → tutte le sessioni WonderFlix tranne quelle del creatore; `Friends` → gli amici online del creatore; `Private` → nessuno | `GroupId`, `Name`, `Mode` |
| `PartyInvite` | sessioni degli invitati | `GroupId`, `Name`, `FromName` |

### 6.9 Limiti e log

| Cosa | Limite | Oltre |
|---|---|---|
| Amici per utente | 200 | 409 |
| Richieste inviate in sospeso | 50 | 409 |
| Nuove richieste | 20 all'ora per utente | 429 |
| Ricerche | 30 al minuto per utente | 429 |
| Codici sbagliati | 5 al minuto per utente | 429 |
| Inviti | 20 destinatari al minuto per utente | 429 |

Log come in 1.0.0: mai testi o codici, solo id e tipi di esito; `Debug` per le operazioni, `Warning` per il file illeggibile e gli errori di scrittura.

## 7. App: il nucleo sociale

### 7.1 `lib/core/social/` (Dart puro)

- Modelli: `PartyMode` (`public` / `friends` / `private`, in rete `Public` / `Friends` / `Private`), `FriendEntry {userId, name, online, party: (groupId, title)?}`, `FriendRequestEntry {userId, name}`, `FriendsSnapshot {friends, incoming, outgoing}`, `UserSearchResult {userId, name, relation}`, `PartySummary {groupId, name, participants, state, mode}`, `PartyDetails {mode, code}`.
- `formatPartyCode('K7PQ2X') → 'K7P-Q2X'`, `normalizePartyCode` (maiuscole, senza spazi e trattini).
- `SocialApi` (HTTP verso gli endpoint §6.7, con `JellyfinHttp` e `quietStatuses` come `PartyChannelApi`): errori come `SocialException(SocialFailure.{unavailable, forbidden, conflict, rateLimited, network})`.
- `parseSocialEvent(payload)` → `FriendRequestEvent`, `FriendsChangedEvent`, `PartyStartedEvent`, `PartyInviteEvent`, oppure `null` (gli eventi del canale con `GroupId` restano a `parsePartyEvent`).

### 7.2 Disponibilità

`SocialAvailability` (`Notifier`): chiede `Info` dopo il login e a ogni connessione del WebSocket (anche la prima: un controllo fallito al login si ripete); una risposta arrivata dopo un cambio di utente si scarta; `friends` e `parties` valgono se `Features` li contiene. Errore o 404 → nessuna funzione (l'app si comporta come la 0.5.1). La diagnostica aggiunge la riga "Funzioni del plugin: amici, party" (o "nessuna"; assente se il plugin non risponde).

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
  3. **"Ho un codice"** (§9.4).
  4. **Richieste ({n})**, solo se ce ne sono: in arrivo con **Accetta / Rifiuta**, poi quelle inviate con "In attesa" + **Annulla**.
  5. **Amici**: online prima (pallino verde), poi offline (nome attenuato), in ordine alfabetico. Amico in un party visibile: seconda riga "Nel watch party: {titolo}" + **Unisciti** (nascosto se siamo già in quel gruppo). **⋯** (sempre visibile) → "Rimuovi dagli amici" → la riga mostra **Conferma rimozione** per 4 s.
  6. Vuoto: "Nessun amico ancora. Cerca qualcuno per nome qui sopra."
- **Errore** del caricamento: "Amici non disponibili" + **Riprova**.
- Le liste lunghe scorrono dentro il pannello; il campo di ricerca resta fermo in alto.

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

### 9.2 Creazione

`startWatchParty(context, ref, item, start:, mode:)`:

1. crea il gruppo e la coda come oggi;
2. con `parties` disponibile, `POST Parties/{groupId} {mode}` appena il gruppo esiste;
3. se la registrazione fallisce: esce dal gruppo e mostra "Non è stato possibile creare il watch party". Nessun party è meglio di un privato visibile a tutti (§6.4: dopo 10 s un gruppo non registrato diventa pubblico).

Per un privato, il codice ricevuto si mostra subito nella pillola del player: "Party privato · codice K7P-Q2X" (avviso del party, una volta).

### 9.3 Il party corrente

`CurrentPartyDetails` (`Notifier`): entrando in un gruppo (creato o raggiunto) legge `GET Parties/{groupId}` → modalità e codice; si azzera all'uscita. Serve al menu del chip e al distintivo nel player.

### 9.4 Codice

- **Mostrarlo:** nel menu del chip "Nel watch party" e nel menu del distintivo del party nel player, una voce `Codice K7P-Q2X` con icona `copy`: copia `K7P-Q2X` negli appunti e mostra "Codice copiato" (snackbar nella shell, pillola nel player). Solo per i privati.
- **Usarlo:** nel pannello Amici, "Ho un codice" apre un campo (6 caratteri, maiuscole automatiche, il trattino si aggiunge da sé) + **Entra** → `POST Parties/Join` → `joinWatchParty(groupId)`; il pannello si chiude. Errori: 403 → "Codice non valido o party finito"; 429 → "Troppi tentativi, riprova tra un minuto".

### 9.5 Invita amici

- Voce **"Invita amici"** negli stessi due menu (chip e distintivo), con `friends` disponibile. Apre un secondo menu ancorato allo stesso punto con gli amici non partecipanti: online prima, poi offline (attenuati). Nessuno: "Nessun amico da invitare" (non cliccabile).
- Un clic manda l'invito a quell'amico (`POST …/Invites`), mostra "Invito mandato a {nome}" e, finché si resta nel party, quell'amico compare come "Invitato ✓" (non cliccabile).
- L'invitato con l'app aperta e il player chiuso vede la scheda "{nome} ti invita" con il titolo e **Unisciti** (10 s), come la scheda d'avviso di oggi.

### 9.6 Elenco dei party e schede

- Con `parties` disponibile, `WatchPartyDirectory` legge `GET Parties` invece di `/SyncPlay/List` (stessi tempi: ogni 30 s, alla chiusura del player, all'apertura del menu) e rilegge subito a ogni `PartyStarted` / `PartyInvite`. Ogni riga del chip mostra l'icona della modalità (`globe` / `users` / `lock`).
- `WatchPartyInvites`: con `parties` disponibile la scheda nasce da `PartyStarted` ("{host} ha avviato un watch party") e da `PartyInvite` ("{nome} ti invita"), non più dal confronto tra due letture; restano le regole di oggi (non dentro un gruppo, non con il player aperto, non per i gruppi già visitati, 10 s). Senza `parties`: logica di oggi.

## 10. Senza plugin ed errori

| Situazione | Comportamento |
|---|---|
| Plugin assente o 1.0.0 | come la 0.5.1: niente icona Amici, menu, codice, inviti; elenco da `/SyncPlay/List` |
| `Info` non risponde | come plugin assente; si riprova alla riconnessione successiva |
| Registrazione del party fallita | si esce dal gruppo + errore (§9.2) |
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

Se una chiave equivalente esiste già (es. "Riprova", "Annulla"), il piano la riusa invece di crearne una nuova.

## 12. Test

- **Plugin (xUnit, `Jellyfin.Plugin.WonderFlixWatchParty.Tests`):** `FriendStore` (salvataggio atomico, ricarica, file illeggibile → `.bad`, utenti spariti); `FriendService` (richiesta, incrociata → amicizia, accetta, rifiuta, annulla, rimuovi, casi rifiutati, limiti); ricerca (contiene, maiuscole, minimo 2, massimo 10, esclusi sé e disabilitati, relazione); `PartyDirectory` (registrazione una volta sola e solo da partecipante, visibilità per modalità, invitati, 10 s dei non registrati con `FakeTimeProvider`, pulizia); codici (alfabeto, unicità, normalizzazione, 5 tentativi); inviti (solo amici, solo partecipanti); destinatari di ogni avviso; presenza (online/offline, raggruppamento di 2 s); controller (codici HTTP, mai 404).
- **App:** `FakeSocialApi`; `parseSocialEvent`; `formatPartyCode` / `normalizePartyCode`; `SocialAvailability` (Features, 404, riconnessione); `FriendsController` (ricarica sugli avvisi, ricerca con attesa e richieste superate, errori); widget test di icona e numero, pannello (stati, ricerca, azioni, Esc, conferma rimozione), scheda della richiesta, menu delle modalità e ultima usata, registrazione fallita → uscita, codice (mostra, copia, entra, errori), "Invita amici", elenco dal plugin con icone, schede da `PartyStarted` / `PartyInvite`; senza plugin: tutto come la 0.5.1.
- **Prova manuale** sul server reale con due istanze (`WONDERFLIX_PROFILE=b`) e due utenti Jellyfin diversi.

## 13. Piani e release

- **12a — amici da capo a fondo:** plugin (`FriendStore`, `FriendService`, ricerca, presenza, endpoint Friends/Users, `FriendRequest` / `FriendsChanged`, `Features: ["friends"]`) + app (`lib/core/social/` per la parte amici, `SocialAvailability`, `SocialEvents`, `FriendsController`, icona, pannello senza "Ho un codice", scheda della richiesta). Fino al 12b `Party` in `GET Friends` è sempre `null`. Il plugin si prova copiandolo a mano sul server (`ssh ultra`, come in 10a), senza release. Fine: due utenti diventano amici e si vedono online.
- **12b — modalità da capo a fondo:** plugin (`PartyDirectory`, codici, inviti, endpoint Parties, `PartyStarted` / `PartyInvite`, `Features: [..., "parties"]`) + app (menu, registrazione, `CurrentPartyDetails`, codice nei menu e nel pannello, "Invita amici", elenco dal plugin, schede dagli avvisi, "Nel watch party" nella lista amici). Poi:
  1. plugin **1.1.0**: tag `watch-party-plugin-v1.1.0` → pre-release, voce nel `manifest.json`, cartella copiata a mano tolta dal server, aggiornamento dal Catalogo;
  2. app **0.6.0 obbligatoria** (`<!-- wonderflix:min-version=0.6.0 -->`), da pubblicare solo dopo il plugin;
  3. commento e chiusura di #5 e #6 con l'ok dell'utente.
- `docs/RELEASING.md`: nessuna procedura nuova; si aggiunge solo che i dati del plugin stanno in `plugins/configurations/WonderFlixWatchParty/`.

## 14. Rischi e punti da verificare

- **`ISyncPlayManager.ListGroups`** in Jellyfin 10.11: firma e risultato (gruppi visti dalla sessione) da verificare con un prototipo all'inizio del 12b, come in 10a.
- **`IApplicationPaths.PluginConfigurationsPath`** scrivibile su Ultra.cc (seedbox senza root): da verificare all'inizio del 12a (il plugin scrive già la sua configurazione XML lì).
- **`SessionStarted` / `SessionEnded`**: arrivano anche per le sessioni WonderFlix che non hanno ancora il WebSocket? Da verificare nel 12a; in alternativa la presenza si calcola alla lettura e gli avvisi di presenza si mandano dal `PartyRegistry` e da un controllo ogni 30 s.
- **Due istanze sulla stessa macchina** devono usare due utenti diversi, altrimenti la presenza di uno nasconde l'uscita dell'altro.
- **Esc nella shell:** oggi torna indietro di pagina (`BackNavigationHandler`); con il pannello aperto deve chiuderlo e basta (come l'anteprima della card).
- **Secondo menu "Invita amici" dentro il player:** il player non dà il focus ai suoi elementi; i menu esistenti (distintivo) funzionano già, il secondo va aperto dopo la chiusura del primo.
