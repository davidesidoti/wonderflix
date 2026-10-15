# WonderFlix — Spec P: match del film

- **Data:** 2026-10-14
- **Stato:** approvata il 2026-10-14; piano 22a realizzato (`docs/superpowers/plans/2026-10-14-wonderflix-22a-match-plugin.md`), build di prova sul server; piani 22b e 22c da scrivere
- **Ambito:** Spec P. Realizza l'idea 9 di `docs/IDEE.md` ("Match del film"): prima di un watch party, gli amici in una sala votano sì o no su una pila di titoli; i titoli che piacciono a tutti finiscono nella coda di un party privato. Si appoggia alla Spec F (amici, party privati, `PartyDirectory`), alla Spec G (cassetta), alla Spec H (coda del party), alla Spec M ("Cosa guardo stasera?") e alla Spec O (`LastWatched`, `CanSee`).

## 1. Obiettivo

- **Sala del match.** Chi la apre sceglie i filtri e invita amici. Quando sono entrati preme "Inizia".
- **Pila.** Il plugin pesca 30 titoli a caso dalla libreria: non visti né iniziati da nessun membro, visibili a tutti, uguali per tutti e nello stesso ordine.
- **Voto.** Una carta grande da trascinare a destra (sì) o a sinistra (no), oppure ✓/✗ o le frecce →/←. I voti sono segreti.
- **Match.** Un titolo a cui tutti i membri hanno detto sì: "È un match!" per tutti e il titolo entra nella lista dei match.
- **Avvia il party.** Chi ha aperto la sala sceglie il titolo che parte per primo. Il party privato parte con i match in coda, e gli altri membri entrano da soli.

Nota sul modello: lo stile è quello di Tinder (carte da scorrere, "È un match!"), ma si votano titoli, non persone. "Match" vuol dire un titolo che piace a **tutti** i membri della sala, non una coppia. La sala esiste solo dal vivo: non è una proposta da votare con calma nelle ore successive.

## 2. Situazione di partenza

App 0.15.1, plugin 1.9.0, Jellyfin 10.11.9 su Ultra.cc.

- **Party** (Spec B, F, H):
  - `startWatchParty(context, ref, item, {start, mode, invite})` (`lib/features/watch_party/watch_party_actions.dart`) costruisce la coda con `buildPartyQueue` (un film, oppure l'episodio e i successivi, al massimo `maxPartyQueue = 50`), crea il gruppo SyncPlay (`WatchPartySession.create`), lo registra (`POST Parties/{groupId}`) e, con `invite`, invita senza aspettare.
  - `joinWatchParty(context, ref, groupId)` entra in un gruppo.
  - Il tetto della coda è `partyQueueLimit = 100` (`party_queue_rules.dart`).
  - Il player si apre da solo quando il gruppo ha un elemento in corso (`watchPartyRoutingProvider`). Chiudere il player fa uscire dal party.
  - Un gruppo SyncPlay senza coda è `Idle` e, dopo 10 s senza registrazione (`PartyDirectory.UnregisteredGrace`), è visibile a tutti. Per questo **la sala non può essere un gruppo SyncPlay**.
- **Plugin, party:** `PartyDirectory` tiene per gruppo `PartyView(GroupId, CreatorId, Mode, Code)` e gli utenti con accesso (`Grant(groupId, users)`, `IsVisible`).
- **Canale push:** il plugin manda gli avvisi con un `GeneralCommand` `SendString` e `Arguments["WonderFlixWatchParty"]`. Gli avvisi sociali (`SocialEvent`: `FriendRequest`, `FriendsChanged`, `PartyStarted`, `PartyInvite`, `InboxChanged`) arrivano all'app in `parseSocialEvent` (`lib/core/social/social_models.dart`), che restituisce `null` per i tipi che non conosce.
- **Cassetta:** `inboxEntryFromJson` (`lib/core/social/inbox_models.dart`) restituisce `null` per i tipi che non conosce. L'invito al party crea una voce `Invite` e un avviso `PartyInvite` (`PartyService.InviteAsync`, solo amici, limite `Invites` 20 al minuto).
- **Carta d'invito:** `WatchPartyInvites` / `WatchPartyInviteCard` (`lib/features/watch_party/watch_party_invites.dart`) mostrano un invito alla volta con "Unisciti".
- **Libreria nel plugin:** `ILibraryAccess.CanSee(userId, itemId)`; `IRecommendationLibrary.LastWatched(userId, itemId)` (film: `LastPlayedDate`; serie: l'episodio visto più di recente), che per la Spec O vale "visto o iniziato". Nessuna query del plugin filtra oggi per genere o durata.
- **"Cosa guardo stasera?"** (Spec M, `lib/features/tonight/`): `TonightFilters` (tipo `movies`/`series`/`both`, durata `any`/`under90`/`under120` solo per i film, genere) ricordati nel profilo; `tonightEligible` scarta i film con durata sconosciuta quando c'è un limite. Il pulsante `TonightButton` sta in tre posizioni della Home (`home_screen.dart`).
- **App:** `LibraryApi.itemsByIds` (con la trama), `LibraryApi.allEpisodes(userId, seriesId)`; nessuna pagina con carte da trascinare (niente `Dismissible` né `Draggable`).
- **Sessioni:** `WatchPartyHostedService` ascolta `SessionStarted`/`SessionEnded`. Una caduta del WebSocket **chiude** la sessione Jellyfin.

## 3. Decisioni

Prese con l'utente nel brainstorming del 2026-10-14:

1. **Dal vivo:** si vota tutti insieme adesso; la sala vive in memoria nel plugin.
2. **Pila dalla libreria con filtri** (tipo, durata, genere come "Cosa guardo stasera?"): titoli che nessun membro ha visto o iniziato e che tutti possono vedere.
3. **Su invito degli amici**; il party finale è privato e i membri ci entrano da soli.
4. **Decide chi ha aperto:** a ogni match "È un match!" e si continua; chi ha aperto avvia il party quando vuole e sceglie il primo titolo; gli altri match seguono in coda.
5. **Attesa, poi "Inizia":** dopo l'inizio non entra più nessuno.
6. **Pagina intera**, aperta da un pulsante "Match" in Home e da "Match del film" nel pannello Amici.
7. **Approccio A:** sala nel plugin, endpoint REST nuovi e avvisi sul canale push esistente.
8. **App 0.16.0 obbligatoria:** con la 0.15.x l'invito al match si perde in silenzio.

Valori scelti: 30 titoli per pila, 8 membri al massimo, quasi match a fine pila, serie in coda con il solo primo episodio (tranne il primo titolo).

## 4. Perimetro

### Incluso

- **Plugin 1.10.0:** sala in memoria, pila, voti, match e quasi match, inviti con voce in cassetta, accesso dei membri al party, avvisi `MatchInvite` e `MatchUpdated`, funzione `match` in `Info`.
- **App 0.16.0:** pulsanti d'ingresso, pagina della sala (attesa, votazione, fine pila), carta da trascinare, "È un match!", lista dei match, avvio del party con la coda dei match, ingresso automatico degli altri membri, carta d'invito e voce in cassetta, testi it/en.

### Escluso

- Votare con calma, sale che sopravvivono al riavvio del plugin, avvisi a votazione in corso fuori dalla pagina.
- Entrare a votazione iniziata.
- Annullare l'ultimo voto; vedere chi ha votato cosa.
- La sala nel pannello Amici ("Nel match") e l'ingresso con un codice.
- Pila da La mia lista dei membri.
- Legame con le serate programmate (idea 8, non fatta).
- Tornare all'attesa per cambiare i filtri: si chiude e si riapre la sala.

## 5. Architettura

```
App (chi apre) ──POST Match──▶ Plugin: MatchRooms (RAM)
App (chi apre) ──POST Match/{id}/Invites──▶ MatchInvite (push) + voce MatchInvite (cassetta)
App (invitati) ──POST Match/{id}/Join──▶
App (chi apre) ──POST Match/{id}/Start {filtri}──▶ MatchStackBuilder (IMatchLibrary, CanSee, LastWatched) ──▶ pila (30 id)
App (tutti) ──POST Match/{id}/Votes──▶ match / quasi match
Plugin ──MatchUpdated {stato}──▶ tutte le sessioni WonderFlix dei membri
App (chi apre) ──startWatchParty(queue, Private)──▶ gruppo SyncPlay registrato
App (chi apre) ──POST Match/{id}/Party {GroupId}──▶ Grant ai membri, sala chiusa con PartyGroupId
App (altri membri) ──MatchUpdated chiusa──▶ joinWatchParty(GroupId)
```

- I voti restano nel plugin: lo stato mandato alle app ha solo i conteggi, i match e i quasi match.
- Il gruppo SyncPlay nasce solo alla fine, con la coda già pronta: nessun gruppo vuoto visibile a tutti.

## 6. Plugin 1.10.0

### 6.1 Sala (`MatchRooms`, in memoria)

- **Stato:** `RoomId` (Guid), `CreatorId`, `Phase` (`Waiting`, `Voting`, `Closed`), `Rev` (cresce a ogni cambio), membri (`UserId`, `Name`, `Voted`, cioè quanti voti ha dato), `Invited` (insieme di utenti), `Drawing` (il plugin sta pescando; non esce nello stato), `Stack` (id in ordine), `Shown` (tutti gli id mai messi nella pila), voti (`UserId → ItemId → bool`), `LastVoteAt`, `ClosedReason`, `PartyGroupId`.
- **Una sala per utente:** chi è membro di una sala aperta non può aprirne o raggiungerne un'altra. Una sala chiusa non conta.
- **Membri al massimo:** 8, compreso chi ha aperto.
- **Membri per utente, non per sessione.** Un membro esce:
  - con `Leave`;
  - quando non ha nessuna sessione WonderFlix da 60 s (la pulizia gira ogni 30 s: esce tra 60 e 90 s). Una caduta del WebSocket chiude la sessione Jellyfin: l'app riconnessa rilegge lo stato e resta dentro.
- **Chiusura:**
  - esce chi ha aperto (`Leave` o 60 s senza sessione) → `ClosedReason = CreatorLeft`;
  - nessun voto, ingresso, "Inizia" o "Altri 30" da 1 h (in attesa: da quando è stata aperta o dall'ultimo ingresso) → `Inactive`;
  - party avviato (§6.6) → `PartyStarted`, con `PartyGroupId`.
- **Sala chiusa tenuta 5 minuti** per rispondere a `GET` (un membro che si riconnette vede `PartyGroupId` ed entra nel party), poi dimenticata.
- **Pulizia** in `MatchHostedService`, ogni 30 s con il suo `try/catch`: membri senza sessione, inattività, sale chiuse scadute.

### 6.2 Pila (`MatchStackBuilder`, `IMatchLibrary`)

`MatchStackBuilder.Draw(creatorId, memberIds, filters, exclude)` costruisce la pila; `IMatchLibrary.Candidates(userId, filters, exclude, limit)`, implementata in `JellyfinMatchLibrary`, fa solo la query:

1. **una query per tipo** (film e serie separati: con i due tipi insieme Jellyfin guarda "visto" sulla riga della serie, che non vale) sulla libreria di chi ha aperto: `new InternalItemsQuery(user)` (porta i limiti d'età e i tag bloccati dell'utente), `Recursive`, `IncludeItemTypes`, `IsVirtualItem = false`, `Genres` se c'è un genere, `IsPlayed = false`, `OrderBy` `Random`, `ExcludeItemIds` = `exclude`. `Limit` totale 300 (`CandidateLimit`): 150 per tipo con film e serie, 300 con un tipo solo. Le liste dei tipi si mescolano. Jellyfin ricontrolla la visibilità dopo la query, quindi i candidati possono essere meno del limite;
2. dopo la query, in `MatchStackBuilder` (Jellyfin non ha un filtro sulla durata): si ricontrollano tipo, doppioni ed esclusi, e per i film con un limite di durata restano solo quelli con `RunTimeTicks` noto e minore del limite (come `tonightEligible`). La durata non vale per le serie;
3. in quell'ordine, si tiene un candidato solo se **ogni** membro, compreso chi ha aperto, lo può vedere (`CanSee`) e non l'ha né visto né iniziato (`LastWatched == null`). `IsPlayed = false` non basta: per un film iniziato ma non finito la query dice sì, e lo toglie `LastWatched`;
4. ci si ferma a `StackSize` (30) titoli o alla fine dei candidati.

- I controlli si fanno uno alla volta e si fermano al primo che non passa: in pratica poche decine di candidati per pila.
- **La pescata è fuori dal lock** (la libreria fa query al database). `Start` e `More` mettono la sala in `Drawing`; finché pesca, `Join` e un secondo `Start` rispondono `Started`, `More` risponde `NotFinished`, `Invites` risponde `Started`, e non parte nessun avviso. Se intanto la sala si chiude (per esempio esce chi l'ha aperta), la pescata si butta e la risposta è `Closed`. Se la pescata lanciasse un errore, la sala non resta bloccata in `Drawing`.
- Un errore della libreria su un candidato lo scarta (`Warning`). Un errore della query, o un utente che la libreria non conosce, dà una pila vuota (`Warning`): `Start` e `More` rispondono normalmente e l'app mostra "Nessun titolo con questi filtri".
- **Filtri** (`Type`: `movies`/`series`/`both`; `Duration`: `any`/`90`/`120`; `Genre`: nome o assente) con gli stessi valori `wire` dell'app (`TonightType`, `TonightDuration`). `Type` e `Duration` mancanti valgono `both` e `any`; un genere vuoto vale "tutti". Un valore sconosciuto, o un genere oltre 100 caratteri → 400.

### 6.3 Voti, match, quasi match

- **In ordine:** il voto di un membro vale solo per `Stack[Voted]`; un altro `ItemId` → **409** (l'app si riallinea dallo stato).
- **Match:** un titolo della pila a cui hanno detto sì **tutti i membri attuali**. In ordine di uscita: quando un titolo diventa match la prima volta gli si dà un numero progressivo; l'elenco dei match segue quel numero.
- **Uscita di un membro:** i suoi voti si tolgono e i match si ricalcolano su chi resta. Un titolo può diventare match in quel momento. Se resta solo chi ha aperto, la sala continua: ogni suo sì è un match. Succede anche se un membro esce mentre il plugin sta pescando la pila: la votazione parte con chi resta, anche da solo.
- **Quasi match:** solo quando tutti i membri hanno votato tutta la pila. I titoli non match con almeno `ceil(membri / 2)` sì, dal più votato, a parità nell'ordine della pila; al massimo 5. Ciascuno porta `Yes` e `Of` (membri).
- **Altri 30** (`More`): solo chi ha aperto, solo quando tutti hanno finito. Pesca con `exclude = Shown` e aggiunge in fondo alla pila. Con la pila vuota si può chiedere subito. Il risultato può essere vuoto: allora lo stato non cambia (`Rev` resta) e non parte nessun avviso.
- **Limite:** voti 4 al secondo per utente (`LimitTypes.MatchVotes`) → 429.

### 6.4 Endpoint

`MatchController`, rotta `WonderFlixWatchParty`, stessa policy degli amici (accesso a SyncPlay). Chi chiama si ricava dal token. **Mai 404** (404 vuol dire plugin mancante). Le risposte 409 hanno il corpo `{Reason}`; solo `InAnotherRoom` ha anche `RoomId`, la sala aperta di chi chiama (§8). Una sala sconosciuta dà `Closed` a tutti gli endpoint tranne `GET` (`NotMember`) e `Leave` (204).

| Endpoint | Chi | Risposta |
|---|---|---|
| `POST Match` | chiunque | stato della sala nuova (chi chiama è membro e creatore); 409 `InAnotherRoom` con `RoomId` |
| `GET Match/{roomId}` | membro (anche di una sala chiusa, entro 5 minuti) | stato; 409 `NotMember` |
| `POST Match/{roomId}/Invites` `{UserIds}` | chi ha aperto, `Waiting` | 204; solo amici attivi di chi chiama, non già membri (gli altri si ignorano), al massimo 50 id per richiesta (i successivi si ignorano); 409 `NotCreator`, `Started`, `Closed`; 429 con il limite `Invites`: si invitano quelli che ci stanno e si risponde 429 |
| `POST Match/{roomId}/Join` | invitato | stato (anche per chi è già membro, senza cambi); 409 `Started`, `Closed`, `Full`, `NotInvited`, `InAnotherRoom` con `RoomId` |
| `POST Match/{roomId}/Leave` | membro | 204 sempre (anche se non è più membro o la sala non c'è) |
| `POST Match/{roomId}/Start` `{Type, Duration, Genre}` | chi ha aperto, `Waiting`, almeno 2 membri | stato (la pila può essere vuota); 409 `NotCreator`, `Started`, `Closed`, `NotEnoughMembers`; 400 filtri non validi |
| `POST Match/{roomId}/Votes` `{ItemId, Yes}` | membro, `Voting` | 204 (senza stato); 409 `NotNext`, `NotStarted`, `Closed`, `NotMember`; 400 senza `ItemId` valido o senza `Yes`; 429 |
| `POST Match/{roomId}/More` | chi ha aperto, `Voting`, tutti hanno finito | stato; 409 `NotCreator`, `NotStarted` (in attesa), `NotFinished` (anche durante una pescata), `Closed` |
| `POST Match/{roomId}/Party` `{GroupId}` | chi ha aperto, `Voting` | 204; il party deve essere registrato da chi chiama (`PartyDirectory.Get(groupId).CreatorId`); altrimenti 409 `NotYourParty`; 409 anche `NotCreator`, `NotStarted` (in attesa), `Closed` |

- `{roomId}`, `{GroupId}` e `ItemId` in formato `N`; un id non valido → 400.
- **Stato** (risposte e `MatchUpdated`):

```
{RoomId, Rev, Phase, CreatorId, CreatorName,
 Members: [{UserId, Name, Voted}],
 Stack: [ItemId],
 Matches: [ItemId],
 NearMatches: [{ItemId, Yes, Of}],
 ClosedReason?, PartyGroupId?}
```

  `Stack` è vuoto in attesa. Non ci sono mai i voti dei singoli. `Rev` cresce solo con un cambio visibile nello stato.

### 6.5 Inviti e avvisi

- **Invito:** per ogni amico invitato si aggiunge a `Invited`, si manda `MatchInvite{RoomId, FromName}` alle sue sessioni WonderFlix e si crea nella sua cassetta una voce `MatchInvite{RoomId, FromName}`. Reinvitare la stessa persona rimanda l'avviso e non duplica la voce (stesso `RoomId`): la voce torna in cima e non letta.
- **Limite:** gli inviti usano il limite `Invites` dei party, con la stessa chiave per chi invita: ogni destinatario conta uno e gli inviti al match e ai party si sommano.
- **`MatchUpdated{…stato…}`** a tutte le sessioni WonderFlix dei membri attuali. Chi esce non riceve più niente: l'app che esce lo sa già, e quella riconnessa rilegge con `GET` (409 `NotMember`).
- **Raggruppamento:** al massimo un `MatchUpdated` ogni 250 ms per sala, sempre con l'ultimo stato. Il primo cambio dopo una pausa parte subito.
- **App vecchie:** ignorano `MatchInvite`, `MatchUpdated` e la voce di cassetta (§2). `parsePartyEvent` delle app vecchie può scrivere una riga di log per il tipo sconosciuto.

### 6.6 Avvio del party

`POST Match/{roomId}/Party {GroupId}`:

1. controlla chi chiama, fase e proprietà del party (§6.4);
2. `PartyDirectory.Grant(groupId, membri)`: gli altri membri (chi ha aperto lo vede già) vedono il party privato e ci possono entrare;
3. chiude la sala con `ClosedReason = PartyStarted` e `PartyGroupId`, e manda subito `MatchUpdated` (senza aspettare i 250 ms).

### 6.7 `Info`, limiti, log

- `Info.Features` aggiunge `"match"`; `Protocol` resta 1; `Version` "1.10.0".
- `LimitTypes.MatchVotes` (4 al secondo per utente); gli inviti usano `Invites` (20 al minuto) come i party (§6.5).
- Log: **mai titoli o nomi**, solo id e numeri. `Debug` per sala aperta, chiusa (con il motivo), pila pescata (quanti titoli); `Warning` per errori della libreria.
- Controllo dei riferimenti della dll contro Jellyfin 10.11.9 (`refprobe`), come per ogni release.

## 7. App 0.16.0

### 7.1 Nucleo

- `lib/core/social/match_models.dart`: `MatchState`, `MatchMember`, `MatchNearMatch`, `MatchPhase`, `MatchClosedReason`, `MatchJoinError` (motivi del 409 di `Join`), da JSON.
- `SocialApi`: `openMatch()`, `match(roomId)`, `inviteToMatch(roomId, userIds)`, `joinMatch(roomId)`, `leaveMatch(roomId)`, `startMatch(roomId, TonightFilters)`, `voteMatch(roomId, itemId, yes)`, `moreMatch(roomId)`, `matchParty(roomId, groupId)`; stessi in `FakeSocialApi`. Il 409 diventa un'eccezione con il motivo.
- `parseSocialEvent`: `MatchInviteEvent{roomId, fromName}`, `MatchUpdatedEvent{state}`.
- `inboxEntryFromJson`: `MatchInviteEntry{roomId, fromName}`.
- `SocialFeatures.match`: la funzione `match` del plugin. Gli ingressi compaiono solo con questa funzione **e** se l'account può creare gruppi SyncPlay (`syncPlayAccess` con `canCreate`), come "Guarda insieme".

### 7.2 Ingressi

- **Home:** un pulsante "Match" accanto a `TonightButton`, nelle tre posizioni in cui c'è oggi.
- **Pannello Amici:** "Match del film" in cima.
- Al clic: `openMatch()` e poi la pagina `/match/:roomId`. Un 409 `InAnotherRoom` porta `RoomId`, la sala aperta di chi chiama (succede con due istanze dello stesso utente, o dopo un `Leave` perso, §8): l'app (22b) la usa per tornare in quella sala o lasciarla, e non resta bloccata con il solo avviso "Sei già in un'altra sala".
- **Invito:** l'avviso `MatchInvite` mostra una carta nello stesso posto e con lo stesso aspetto dell'invito al party ("{name} ti invita a un match", "Unisciti"). `WatchPartyInviteCard` diventa una carta comune con due varianti; resta un invito alla volta, l'ultimo arrivato. La voce `MatchInviteEntry` nella cassetta ha "Unisciti".
- **Unisciti:** `joinMatch(roomId)` e la pagina della sala. Il 409 dà un avviso: `Started` → "Il match è già iniziato", `Closed` → "Sala chiusa", `Full` → "Sala piena", `InAnotherRoom` → "Sei già in un'altra sala" (con `RoomId`, come sopra), `NotInvited` → "Sala chiusa". `Join` di chi è già membro risponde con lo stato.
- Dentro un watch party non c'è nessun ingresso (si è nel player).

### 7.3 Pagina della sala

Route `/match/:id` nella shell, sotto la barra come la scheda di un titolo, titolo nella barra "Match del film".

- **Stato:** `MatchController` (provider per `roomId`): legge con `match(roomId)` all'apertura e a ogni riconnessione al server; si aggiorna con `MatchUpdatedEvent` dello stesso `roomId`, scartando quelli con `Rev` minore o uguale a quella che ha, anche le risposte degli endpoint: gli avvisi partono fuori dal lock e possono arrivare fuori ordine.
- **Uscire:** lasciare la pagina (←, Esc, un'altra voce della barra, cambio di profilo) chiama `leaveMatch` senza aspettare. Chiudere l'app lo prova senza aspettare; altrimenti ci pensa la pulizia del plugin (60 s).
- **In alto, sempre:** i membri con l'avatar e il nome; in votazione anche "12/30" e ✓ quando hanno finito.

#### Attesa

- **Chi ha aperto:**
  - i filtri di "Cosa guardo stasera?" (stessi controlli e stessi `TonightFilters` salvati nel profilo);
  - gli amici online e non in un watch party, ciascuno con "Invita" (poi "Invitato"; un nuovo clic rimanda l'invito);
  - "Inizia", attivo con almeno 2 membri; sotto, se manca: "Serve almeno un amico nella sala".
- **Gli altri:** "In attesa che {name} inizi…".

#### Votazione

- **Carta** al centro, grande: sfondo del titolo, titolo, riga dei dati come `tonightMeta` (anno, durata o stagioni, generi), trama su tre righe. I dettagli della pila si chiedono con `itemsByIds` (100 alla volta); gli id che il server non restituisce si votano "no" da soli e si saltano. Si caricano in anticipo le immagini delle 2 carte successive.
- **Gesto:** trascinamento orizzontale. Oltre il 30% della larghezza della carta, o con una velocità oltre 800 px/s, la carta vola via dal lato del gesto ruotando fino a ±12°; durante il trascinamento compare "SÌ" (verde) o "NO" (rosso) in proporzione alla distanza. Sotto la soglia torna al centro. Con le animazioni ridotte: niente volo né rotazione, dissolvenza breve.
- **Pulsanti e tasti:** ✗ e ✓ sotto la carta; ← e → con il focus sulla pagina. Fanno volare la carta come il gesto.
- **Voto ottimista:** la carta successiva compare subito e il voto parte. Un 409 `NotNext` riallinea la posizione da `Voted` nello stato; un errore di rete o un 429 riporta indietro la carta e mostra "Voto non inviato".
- **Colonna a destra:** "Match" con locandina e titolo, nell'ordine di uscita; a fine pila, sotto, "Piaciuti a quasi tutti" con "{yes} su {of}". Vuota: "Ancora nessun match".
- **"È un match!"** Per ogni id che entra in `Matches` per la prima volta (anche per un ricalcolo dopo un'uscita): uno strato sopra la carta per 2 s con la locandina e il testo oro. Un tasto o un clic lo chiudono prima. Più match insieme: uno dopo l'altro.

#### Fine della pila

- Chi ha votato tutto: "Hai votato tutto, aspetta gli altri".
- Quando hanno finito tutti, chi ha aperto vede "Altri 30 titoli" (`moreMatch`).
- Pila vuota dopo `Start` o `More`: "Nessun titolo con questi filtri".

#### Avvia il party

- Solo chi ha aperto, con almeno un match o un quasi match. Un clic su una voce della colonna la sceglie come prima ("Parte per primo"); senza scelta, il primo match (o il primo quasi match).
- **Coda:**
  1. il primo titolo come "Guarda insieme": un film; per una serie il primo episodio (`allEpisodes`, il primo con stagione ≥ 1, altrimenti il primo) con i successivi (`buildPartyQueue`, al massimo 50);
  2. poi gli altri match, nell'ordine di uscita: un film intero, una serie con il solo primo episodio;
  3. i quasi match non entrano, salvo quello scelto come primo;
  4. tagliata a `partyQueueLimit` (100).
- `startWatchParty` riceve un parametro `queue` (la coda già pronta, che sostituisce `buildPartyQueue`), con `mode: PartyMode.private` e senza menu delle modalità.
- Appena il party è registrato: `matchParty(roomId, groupId)`, senza bloccare l'avvio. Se fallisce, il party resta: si può invitare dal menu del party.
- Il pulsante è spento mentre parte. Se il party non parte, l'avviso che si usa già e la sala resta aperta.
- **Gli altri membri:** quando arriva lo stato `Closed` con `PartyGroupId`, la pagina si chiude da sola e l'app chiama `joinWatchParty(groupId)`; il player si apre quando il gruppo ha l'elemento in corso.
- **Chi ha aperto:** il player si apre sopra la pagina; allo stato `Closed` la pagina si chiude sotto il player, senza avvisi.

#### Chiusura senza party

Stato `Closed` senza `PartyGroupId` (`CreatorLeft`, `Inactive`) o 409 `NotMember` alla rilettura: si torna alla pagina precedente con l'avviso "Sala chiusa".

### 7.4 Versione

`pubspec.yaml` 0.16.0; release **obbligatoria** (`<!-- wonderflix:min-version=0.16.0 -->` nelle note).

## 8. Senza plugin ed errori

- **Plugin senza `match`** (< 1.10.0): nessun pulsante, nessuna chiamata; la carta e la voce `MatchInvite` non arrivano.
- **Errori di rete sulle azioni** (invita, inizia, altri 30): avviso "Non riuscito, riprova"; nei log solo il tipo dell'errore.
- **Riconnessione** al server durante la sala: `match(roomId)`; un 409 `NotMember` chiude la pagina con "Sala chiusa".
- **Un membro non può entrare nel party** (per esempio un episodio successivo con un limite d'età diverso, che Jellyfin controlla all'ingresso nel gruppo): l'errore che `joinWatchParty` mostra già.
- **`Leave` perso** (app chiusa di colpo, rete caduta): la sala resta aperta finché la pulizia non toglie il membro (60 s senza sessioni WonderFlix; se è chi ha aperto, la sala si chiude per tutti) o per 1 h senza attività. Intanto `POST Match` e `Join` rispondono `InAnotherRoom` con `RoomId`, e l'app (22b) può tornare in quella sala o lasciarla.
- **Due istanze dello stesso utente:** la seconda non apre né raggiunge altre sale (`InAnotherRoom`, con `RoomId`); se apre la pagina della stessa sala, ci sono due app sullo stesso membro: accettato, i voti di una portano avanti anche l'altra dallo stato.
- **App 0.15.x con plugin 1.10.0:** non vede gli inviti. Per questo la 0.16.0 è obbligatoria.

## 9. Testi nuovi (ARB, it + en)

| Chiave | it | en |
|---|---|---|
| `matchButton` | Match | Match |
| `matchTitle` | Match del film | Movie match |
| `matchInviteFriend` | Invita | Invite |
| `matchInvited` | Invitato | Invited |
| `matchStart` | Inizia | Start |
| `matchNeedFriend` | Serve almeno un amico nella sala | At least one friend has to join |
| `matchWaitingFor` | In attesa che {name} inizi… | Waiting for {name} to start… |
| `matchYes` | Sì | Yes |
| `matchNo` | No | No |
| `matchItsAMatch` | È un match! | It's a match! |
| `matchMatches` | Match | Matches |
| `matchNoMatches` | Ancora nessun match | No matches yet |
| `matchNearMatches` | Piaciuti a quasi tutti | Almost everyone liked |
| `matchYesOf` | {yes} su {of} | {yes} of {of} |
| `matchAllVoted` | Hai votato tutto, aspetta gli altri | You've voted on everything, wait for the others |
| `matchMore` | Altri 30 titoli | 30 more titles |
| `matchEmpty` | Nessun titolo con questi filtri | No titles match these filters |
| `matchPlaysFirst` | Parte per primo | Plays first |
| `matchStartParty` | Avvia il party | Start the party |
| `matchVoteNotSent` | Voto non inviato | Vote not sent |
| `matchFailed` | Non riuscito, riprova | Didn't work, try again |
| `matchClosed` | Sala chiusa | Room closed |
| `matchAlreadyStarted` | Il match è già iniziato | The match has already started |
| `matchFull` | Sala piena | Room full |
| `matchInAnotherRoom` | Sei già in un'altra sala | You're already in another room |
| `matchInviteFrom` | {name} ti invita a un match | {name} invited you to a movie match |

"Unisciti" c'è già. "Parte per primo" si riferisce al titolo; nessun testo dà per scontato il genere di qualcuno.

## 10. Sicurezza e privacy

- I voti dei singoli non escono mai dal plugin: si vedono solo i conteggi, i match e i quasi match.
- Si invitano solo amici; si entra solo su invito e solo in attesa.
- La pila contiene solo titoli che **tutti** i membri possono vedere (`CanSee`), quindi nessuno vede titoli che la sua libreria gli nasconde; il fatto che un titolo manchi non dice niente su nessuno.
- La cronologia dei membri (`LastWatched`) serve solo a togliere titoli dalla pila; non arriva a nessuno.
- Il party finale è privato e lo vedono solo i membri (`Grant`).
- Nei log nessun titolo né nome.

## 11. Test

### 11.1 Plugin (xUnit)

- Fasi e permessi di ogni endpoint, con ogni 409 della tabella di §6.4 (`InAnotherRoom` con il `RoomId` giusto); id non validi → 400; mai 404.
- Pila: tipo, genere, durata (film senza durata scartati con un limite), `CanSee` falso per un membro, visto o iniziato da un membro (anche chi ha aperto), "Altri 30" senza ripetizioni, pila vuota, errore della query e di un candidato.
- Voti in ordine e `NotNext`; match; ricalcolo all'uscita di un membro (anche un match nuovo); quasi match (soglia, ordine, tetto 5, solo a fine pila); `More` solo a fine pila.
- Uscita per 60 s senza sessione; uscita di chi ha aperto; inattività di 1 h; sala chiusa tenuta 5 minuti.
- `Party`: proprietà del party, `Grant` ai membri, chiusura con `PartyGroupId`, invio subito.
- Stato senza voti dei singoli; raggruppamento dei `MatchUpdated` (250 ms, ultimo stato).
- Inviti: solo amici, voce in cassetta senza doppioni, limite, al massimo 50 id per richiesta.
- Sala che si chiude durante la pescata: risposta `Closed`.
- Limite dei voti; `Info` con `match`; riferimenti della dll contro 10.11.9.

### 11.2 App

- Modelli e JSON (stato, voce di cassetta, avvisi).
- `MatchController`: `Rev`, voto ottimista, `NotNext`, errore di rete, chiusura con e senza party, ingresso automatico nel party, uscita alla chiusura della pagina.
- Pagina: attesa (chi ha aperto e gli altri), votazione, fine pila, colonna dei match, strato "È un match!" (uno per id, in fila), gesto (soglia, velocità, ritorno), pulsanti e tasti, animazioni ridotte.
- Coda del party: film, serie come primo titolo, serie dopo il primo, tetto 100, scelta del primo.
- Ingressi: pulsanti solo con la funzione e con `canCreate`; carta d'invito e voce in cassetta con gli esiti del 409.

### 11.3 Prova a mano

Due istanze (`WONDERFLIX_PROFILE=b`) con due utenti amici: apertura e invito (carta e cassetta), "Inizia", voti con un match e un no, uscita di un membro, "Altri 30", quasi match, avvio del party con ingresso automatico dell'altro, chiusura della sala da parte di chi l'ha aperta, filtri che danno una pila vuota.

## 12. Verifiche sul sorgente di Jellyfin 10.11.9

Fatte il 2026-10-14 (piano 22a, Task 7) sul sorgente ai tag `v10.11.9` e `v10.11.0`:

- `InternalItemsQuery` ha in entrambe le versioni `User`, `Recursive`, `IncludeItemTypes`, `Genres` (per nome), `IsPlayed`, `IsVirtualItem`, `ExcludeItemIds`, `OrderBy` e `Limit`. **Non** ha un filtro sulla durata: la controlla il plugin dopo la query (§6.2).
- Il costruttore `new InternalItemsQuery(user)` porta i limiti d'età e i tag bloccati dell'utente; `GetItemList` aggiunge le sue librerie e ricontrolla la visibilità, quindi i risultati possono essere meno di `Limit`. `ItemSortBy.Random` è un campione a caso vero prima del `Limit`.
- `IsPlayed = false`: con le sole serie vuol dire "nessun episodio visto"; con film e serie insieme guarda la riga della serie, che non vale. Per questo una query per tipo. Per un film vale solo "visto": quello iniziato passa, e lo toglie `LastWatched`.
- `LastPlayedDate` e `PlayCount` cambiano all'inizio della riproduzione: `LastWatched` vale anche per i titoli solo iniziati, come assume la Spec O.
- L'ingresso in un gruppo SyncPlay rifiuta chi non vede tutta la coda (avviso `LibraryAccessDenied`) con lo stesso controllo di `CanSee`; un episodio eredita la classificazione della serie (§8).
- `/Shows/{id}/Episodes` senza stagione: gli speciali (stagione 0) vengono prima, o in mezzo se la libreria li mostra dentro le stagioni; `isMissing=false` toglie gli episodi virtuali. Il "primo episodio" si sceglie con stagione ≥ 1 (§7.3).
- Il controllo dei riferimenti della dll (`refprobe`) contro 10.11.9: 0 non risolti.

## 13. Piani e release

- **22a — plugin 1.10.0 (realizzato):** verifiche di §12, sala, pila, voti, endpoint, avvisi, cassetta, `Info`. Il plugin 1.10.0 è una build di prova installata a mano sul server (con l'OK dell'utente al riavvio di Jellyfin e il backup della 1.9.0 del Catalogo in `~/wfwp-backup/`) e lo resta fino alla fine del 22c. Nessuna release: il Catalogo resta alla 1.9.0.
- **22b — app, sala:** nucleo (§7.1), ingressi, carta d'invito e cassetta, pagina in attesa, uscita.
- **22c — app, votazione:** carta e gesto, match e quasi match, fine pila, avvio del party, versione 0.16.0; poi la prova a mano con l'utente.
- **Release** (con l'OK dell'utente a ogni passo): plugin **1.10.0** dal Catalogo, poi app **0.16.0 obbligatoria** con le note in italiano nella bozza.
- **Alla fine**, in `docs/IDEE.md`: l'idea 9 esce dalla lista e tra le fatte c'è "Spec P — match del film (plugin 1.10.0, app 0.16.0)".
