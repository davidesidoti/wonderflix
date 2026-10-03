# WonderFlix — Spec G: notifiche nell'app

- **Data:** 2026-10-03
- **Stato:** approvato; piano 13a realizzato (`docs/superpowers/plans/2026-10-03-wonderflix-13a-cassetta-notifiche.md`); nuovi titoli e release nel piano 13b
- **Ambito:** Spec G. Nasce dall'issue #7 (collegamento a Discord); dopo la ricerca l'utente ha **scartato Discord** e scelto una **cassetta delle notifiche dentro WonderFlix**, conservata dal plugin. Si appoggia alla Spec F (`2026-10-03-wonderflix-amici-party-privati-design.md`: §6 plugin, §7 nucleo sociale, §8.3 pannello Amici, §9.5 inviti), realizzata nella v0.6.0.

## 1. Obiettivo

Oggi gli avvisi dell'app sono solo dal vivo: la scheda d'invito dura 10 s, e chi ha l'app chiusa non sa che è stato invitato, che sul server sono arrivati titoli nuovi o che l'admin vuole dire qualcosa. La Spec G aggiunge una **cassetta delle notifiche**:

- un'icona nella barra con il numero dei non letti e un pannello laterale "Notifiche";
- tre tipi di voce: **inviti ai watch party**, **nuovi titoli** (riepilogo a fine ondata), **annunci dell'admin**;
- tutto conservato dal plugin: aprendo l'app si trova anche quello che è successo mentre era chiusa.

Nessuna notifica fuori dall'app (né Discord né notifiche di Windows): chi ha l'app chiusa vede le voci alla prossima apertura.

## 2. Situazione di partenza

- **Plugin 1.1.0** (`jellyfin-plugin-watch-party/`): amici su disco (`FriendStore`, `friends.json` in `<PluginConfigurationsPath>/WonderFlixWatchParty/`), party in RAM (`PartyDirectory`), `PartyService.InviteAsync` con l'avviso `PartyInvite` alle sessioni degli invitati che vedono la coda (Spec F §6.6). Pulizia periodica ogni 5 minuti (`WatchPartyHostedService.CleanupInterval`). Il plugin non ha impostazioni (`BasePlugin<BasePluginConfiguration>`, niente pagina nella Dashboard). `Info` risponde `{Version, Protocol: 1, Features: ["friends", "parties"]}`.
- **App 0.6.0:** `SocialAvailability` legge `Info.Features` (`SocialFeatures`, `known: false` finché `Info` non risponde); `SocialEvents` smista gli avvisi del plugin; `parseSocialEvent` scarta in silenzio i tipi sconosciuti, mentre `parsePartyEvent` scrive una riga `info` ("evento del canale non riconosciuto") per i tipi che non sono in `socialEventTypes`.
- **Barra in alto** (`lib/app/app_shell.dart`): `WatchPartyButton`, `FriendsButton`, avatar. Il pannello Amici (`FriendsPanelHost`, `FriendsPanelController`) sta a destra, largo 360 px.
- **Scheda d'invito** (`WatchPartyInvites`): "{nome} ti invita a un watch party" per 10 s, fuori dal player.
- **Nell'app non ci sono dialoghi** (Spec C): le conferme sono pulsanti che diventano "Conferma" per 4 s.

## 3. Decisioni

| Tema | Decisione |
|---|---|
| Canale | solo dentro l'app; Discord e notifiche di sistema scartati |
| Archivio | nel plugin, su disco (`inbox.json`), per utente |
| Tipi | inviti ai watch party, nuovi titoli, annunci dell'admin |
| Dove | icona Lucide `inbox` nella barra (dopo Amici, prima dell'avatar) con il numero dorato dei non letti; pannello "Notifiche" da destra, 360 px |
| Lettura | aprire il pannello segna lette tutte le voci presenti; restano evidenziate finché il pannello è aperto; una voce che arriva a pannello aperto prende il pallino e si segna subito letta |
| Durata | 30 giorni, al massimo 100 voci per utente; × su ogni voce e "Svuota" |
| Dal vivo | la scheda resta solo per gli inviti (come oggi); nuovi titoli e annunci fanno solo salire il numero |
| Inviti | una voce per party: un nuovo invito allo stesso party aggiorna la voce |
| Nuovi titoli | una voce per ondata; film tutti, episodi solo delle serie seguite; righe cliccabili |
| Annunci | scritti dall'admin nella pagina del plugin nella Dashboard di Jellyfin; arrivano a tutti gli utenti attivi |
| Compatibilità | `Protocol` resta 1; `Info.Features` aggiunge `"inbox"` |
| Release | plugin 1.2.0, poi app **0.7.0 non obbligatoria** |
| Issue #7 | chiusa come "non pianificata" alla release, con un commento |

## 4. Perimetro

### Incluso

- Plugin 1.2.0: archivio delle voci, endpoint della cassetta, voci d'invito, raccolta dei nuovi titoli, annunci, pagina di configurazione nella Dashboard.
- App 0.7.0: disponibilità, icona, pannello, tre tipi di voce.

### Escluso

- **Discord** (messaggi diretti, bot, collegamento dell'account): scartato dopo la ricerca (§13).
- **Notifiche fuori dall'app**: toast di Windows, push sul telefono.
- **Richieste d'amicizia** nella cassetta: restano nel pannello Amici con il numero sull'icona Amici.
- **Party avviati** (`PartyStarted`) nella cassetta: restano solo nella scheda e nell'elenco dei party.
- **Interruttori per tipo** di voce: tutti i tipi arrivano a tutti; l'unico interruttore è quello dell'admin sui nuovi titoli.
- **Annunci scritti dall'app**: solo dalla Dashboard.

## 5. Architettura

```
Plugin 1.2.0
  InboxStore (inbox.json, su disco)  ── InboxService ── InboxController (REST)
        ▲                                   │
        │                                   └─ avviso InboxChanged (SendString)
  PartyService.InviteAsync ──── voce Invite
  NewTitlesCollector (ItemAdded/ItemRemoved, ondate) ──── voce NewTitles (13b)
  POST Inbox/Announcements (admin) ──── voce Announcement
  Configuration page (Dashboard) ── annunci; PluginConfiguration.NotifyNewTitles (13b)

App 0.7.0
  lib/core/social/   modelli InboxEntry, SocialApi (cassetta), parseSocialEvent (InboxChanged)
  SocialAvailability  + feature inbox
  InboxController     voci, non letti, azioni
  ShellPanelController / ShellSidePanel   un pannello alla volta, contenitore comune (anche Amici)
  InboxButton/Panel   icona, pannello, tre tipi di voce
```

Come in 1.1.0, il nucleo del plugin non conosce Jellyfin: le nuove classi parlano con interfacce (accesso agli elementi, dati utente, eventi della libreria) con adattatori in `Server/`.

## 6. Plugin 1.2.0

### 6.1 Archivio

- File `inbox.json` in `<PluginConfigurationsPath>/WonderFlixWatchParty/`, accanto a `friends.json`.
- Contenuto: `{"Version": 1, "Users": {"<userId>": {"NextSeq": 42, "Entries": [ … ]}}}`. Id in formato `N`.
- Stesse regole di `FriendStore`: caricato all'avvio; ogni modifica riscrive il file in modo atomico (file temporaneo + rinomina), scritture serializzate da un lock; file illeggibile rinominato in `inbox.json.bad`, riga `Warning`, si riparte vuoti.
- **Limiti:** oltre 100 voci per utente si toglie quella con `Seq` più basso. Alla pulizia periodica (ogni 5 minuti) spariscono le voci con `CreatedAt` più vecchio di 30 giorni e gli utenti che non esistono più in Jellyfin. La pulizia delle notifiche ha il suo `try/catch` in `WatchPartyHostedService`, separato da quello dei gruppi e dei party: un errore dell'una non salta l'altra (riga `Warning`). Anche la lettura di `inbox.json` all'avvio ha il suo, separato da quello di `friends.json`.

### 6.2 Voci

Campi comuni: `Id` (Guid `N`), `Seq` (intero per utente, da `NextSeq`), `Type`, `CreatedAt` (ISO-8601 UTC), `Read`.

| `Type` | Campi propri |
|---|---|
| `Invite` | `GroupId`, `FromName`, `Title`, `ImageItemId` |
| `NewTitles` | `Movies: [{ItemId, Name, Year}]`, `Series: [{SeriesId, Name, Episodes: [{Season, Episode}]}]`, `More` |
| `Announcement` | `Text` |

- Ogni voce nuova **e ogni voce aggiornata** prende un nuovo `Seq` (il più alto): l'ordine della cassetta è per `Seq` decrescente.
- `Year`, `Season`, `Episode` mancano se Jellyfin non li ha; `More` manca se è 0 (`WhenWritingNull`, come il resto del protocollo).

### 6.3 Endpoint (sotto `/WonderFlixWatchParty`)

`InboxController` ha `[Authorize]` semplice: gli endpoint valgono per **ogni utente autenticato**, anche senza accesso ai watch party. Chi chiama si ricava come negli altri controller (`UserId`). Il plugin **non risponde mai 404** (404 = plugin assente).

| Metodo e percorso | Corpo / risposta |
|---|---|
| `GET Inbox` | `{Entries: [...], Unread}`; voci per `Seq` decrescente; `Unread` = voci con `Read == false` |
| `POST Inbox/Read` `{UpTo}` | 204; segna lette le voci con `Seq <= UpTo` |
| `DELETE Inbox/Entries/{id}` | 204, anche se la voce non c'è |
| `DELETE Inbox` | 204; svuota la cassetta di chi chiama (`NextSeq` resta) |
| `POST Inbox/Announcements` `{Text}` | `{Recipients}`; **solo admin** (`[Authorize(Policy = Policies.RequiresElevation)]`); 400 se il testo, senza spazi ai bordi, è vuoto o supera 500 caratteri |

`GET Info` risponde `{Version: "1.2.0", Protocol: 1, Features: ["friends", "parties", "inbox"]}`: `Version` ha 3 numeri, come prima (non "1.2.0.0").

`GET Info` sta in un controller suo (`InfoController`) con `[Authorize]` semplice: un attributo sul metodo non allarga la policy SyncPlay della classe. L'id di una voce in `DELETE Inbox/Entries/{id}` è una stringa senza vincoli di rotta (un vincolo risponderebbe 404, cioè "plugin assente").

### 6.4 Avviso `InboxChanged`

`{Protocol: 1, Type: "InboxChanged"}`, stesso trasporto della Spec E/F (`SendString`, chiave `WonderFlixWatchParty`), a tutte le sessioni WonderFlix dell'utente quando la sua cassetta cambia: voce nuova o aggiornata, lettura, cancellazione, svuotamento. L'app rilegge `GET Inbox`. Le app 0.6.0 lo scartano (`parseSocialEvent` → `null`) con una riga `info` di `parsePartyEvent`: innocuo.

### 6.5 Voci d'invito

In `PartyService.InviteAsync`, dopo aver scelto gli invitati validi (amici, non già partecipanti, entro il limite di 20 al minuto, Spec F §6.6) e dopo l'avviso `PartyInvite`, che resta com'è:

- **Elemento del party:** si prende solo dalle sessioni WonderFlix registrate nel canale del party (`PartyRegistry`, riempito dal Join dell'app) il cui utente è ancora tra i partecipanti del gruppo (la voce del registro può essere vecchia). Prima la sessione di chi invita, poi le altre: vale il primo elemento in riproduzione (`NowPlayingItem`). Mai l'elemento di una sessione fuori dal party. Se nessuna di quelle sessioni sta riproducendo (es. gruppo ancora fermo), **nessuna voce**.
- **Accesso:** per ogni invitato **attivo** (non disabilitato), la voce si crea solo se l'invitato può vedere l'elemento (accesso alla libreria e limiti d'età del suo profilo, controllati sull'utente, non su una sessione: vale anche per chi è offline). Altrimenti niente voce.
- **Errori:** un errore nella creazione delle voci o nell'avviso `InboxChanged` va nel log (`Warning`) e non arriva mai all'invito: l'avviso `PartyInvite` e la risposta restano quelli di sempre.
- **Campi:** `FromName` = nome di chi invita; `Title` = la parte del nome del gruppo dopo "Host · " (come `Party.Title` in `GET Friends`); `ImageItemId` = la serie per un episodio, l'elemento stesso per un film.
- **Una voce per party:** se l'invitato ha già una voce `Invite` con lo stesso `GroupId`, la voce si aggiorna (`FromName`, `CreatedAt`, `Read = false`, nuovo `Seq`) invece di aggiungerne un'altra.
- **Party finito:** la voce resta; è l'app a mostrarla come finita (§7.6).

### 6.6 Nuovi titoli

Arriva con il piano 13b: il plugin del 13a non ha `NewTitlesCollector`, né la casella che lo spegne (§6.8).

`NewTitlesCollector` (servizio del plugin):

- **Raccolta:** ascolta `ILibraryManager.ItemAdded` e `ItemRemoved`. Tiene solo **film** ed **episodi** non virtuali (niente episodi "mancanti" segnaposto, collezioni, trailer, extra). Con `NotifyNewTitles` spento non raccoglie niente.
- **Ondata:** comincia col primo titolo raccolto e si chiude dopo **15 minuti** senza nuovi titoli, o al massimo **2 ore** dopo il primo.
- **Sostituzioni:** un titolo aggiunto non si annuncia se nella stessa ondata è stato tolto un elemento dello stesso tipo con un id esterno uguale (TMDB, IMDb o TVDB): è un file sostituito (es. qualità migliore da Radarr/Sonarr). Un titolo aggiunto e tolto nella stessa ondata sparisce.
- **Alla chiusura** il collector rilegge ogni elemento per id: quelli che non esistono più si scartano, i nomi sono quelli definitivi (metadati aggiornati). Poi, per **ogni utente attivo** (non disabilitato):
  - **film:** tutti quelli che l'utente può vedere;
  - **episodi:** quelli che l'utente può vedere, solo delle serie che **segue**: la serie è tra i suoi preferiti (La mia lista), oppure l'utente ha almeno un altro episodio della serie visto o iniziato;
  - se resta qualcosa, una voce `NewTitles` e `InboxChanged` alle sue sessioni.
- **Ordine:** film per nome; serie per nome; episodi per stagione ed episodio.
- **Tetto:** al massimo 500 righe per voce (un film o una serie = una riga); le righe escluse vanno in `More` (numero di film e serie esclusi).
- **Riavvio** di Jellyfin durante un'ondata: l'ondata si perde (accettato).

### 6.7 Annunci

`POST Inbox/Announcements {Text}` (solo admin): testo senza spazi ai bordi, da 1 a 500 caratteri, conservato come testo semplice con gli a capo. Una voce `Announcement` per **ogni utente Jellyfin attivo**, admin compreso (così vede com'è venuta); `InboxChanged` alle sessioni aperte. La risposta `{Recipients}` dice a quanti utenti è arrivata.

### 6.8 Pagina di configurazione

- `Plugin` implementa `IHasWebPages`. Nel 13a resta `BasePlugin<BasePluginConfiguration>`; con il 13b diventa `BasePlugin<PluginConfiguration>`, con `PluginConfiguration : BasePluginConfiguration` e `bool NotifyNewTitles { get; set; } = true`. Il passaggio da `BasePluginConfiguration` è sicuro: Jellyfin, se l'XML non corrisponde, salva i valori predefiniti e continua.
- Una pagina HTML incorporata (`Configuration/configPage.html`, `EnableInMainMenu = true`, `DisplayName = "WonderFlix Watch Party"`, `Name` unico `WonderFlixWatchParty`), in inglese come il resto del plugin:
  - riquadro **"Announcement"**: testo (massimo 500 caratteri, con contatore) e **"Send to everyone"**, che chiama `POST Inbox/Announcements`; esito "Sent to N user(s)" (testo: "Sent to 1 user." / "Sent to N users.") o l'errore;
  - casella **"Notify new titles"** salvata con `ApiClient.updatePluginConfiguration`: arriva con il piano 13b; nel 13a la pagina ha solo l'annuncio.
- La pagina HTML si scarica senza login (`/web/ConfigurationPage`): non contiene dati.

### 6.9 Limiti e log

- Nessun limite di frequenza nuovo: gli inviti hanno già i loro (20 destinatari al minuto), gli annunci sono solo dell'admin, la cassetta è dell'utente stesso.
- Log come in 1.0.0/1.1.0: **mai testi, titoli o nomi**, solo id, tipi e numeri; `Debug` per le operazioni (voce creata, ondata chiusa con N titoli e M destinatari), `Warning` per il file illeggibile e gli errori di scrittura.
- Gli errori della cassetta (voci d'invito, avviso `InboxChanged`, pulizia) vanno nel log come `Warning` e non hanno effetto su inviti, party e sul resto della pulizia (§6.1, §6.5).

## 7. App 0.7.0

### 7.1 Nucleo (`lib/core/social/`, Dart puro)

- Modelli: `InboxEntry` sigillato con `InviteEntry {groupId, fromName, title, imageItemId}` e `AnnouncementEntry {text}`; `NewTitlesEntry {movies, series, more}` arriva con il 13b. Campi comuni `id`, `seq`, `createdAt`, `read`. `InboxSnapshot {entries, unread}`.
  - Una voce di tipo sconosciuto si salta (versioni future del plugin). Anche una voce **malformata** si salta, con una riga `info` nel log (solo il tipo dell'errore, mai il contenuto): non rompe la cassetta.
  - `unread` lo calcola l'app dalle voci che può mostrare (le non lette di `entries`). L'`Unread` del server si ignora: conterebbe anche le voci di tipi sconosciuti (un plugin più nuovo), che l'app non vede e non può segnare lette, e il numero resterebbe acceso per sempre.
- `SocialApi`: `inbox()`, `markInboxRead(upTo)`, `removeInboxEntry(id)`, `clearInbox()`; errori come gli altri (`SocialException`).
- `parseSocialEvent` riconosce `InboxChanged` (`InboxChangedEvent`); `socialEventTypes` lo include, così `parsePartyEvent` non lo scrive nel log.
- Funzioni pure: `inboxTimeLabel(createdAt, now, l)` per l'ora relativa (§7.6; sta in `lib/features/inbox/inbox_time.dart`, perché usa i testi localizzati). `formatEpisodeRanges(episodes)` arriva con il 13b: `S3 E1–E10`, `S3 E1–E4, E6`, più stagioni unite da ` · ` (`S2 E10 · S3 E1–E3`); se manca anche un solo numero la riga dice "{n} episodi nuovi".

### 7.2 Disponibilità

`SocialFeatures` aggiunge `inbox` (da `Info.Features`), con le stesse regole della Spec F §7.2: finché `Info` non ha una risposta certa niente icona; errore di rete = ignoto e si riprova; solo 400/401/403/404 = plugin assente. La diagnostica aggiunge "notifiche" alla riga "Funzioni del plugin". Senza accesso ai watch party l'app chiede `Info` lo stesso e tiene solo `inbox`: amici e party restano spenti.

### 7.3 `InboxController`

- Stato `InboxState {snapshot, loaded, failed, highlighted}`, vivo per tutta la sessione dell'utente (si azzera al logout). `loaded`: almeno un caricamento è riuscito. `failed`: l'ultimo non è riuscito (resta la cassetta di prima). `highlighted`: gli id delle voci con il pallino (§7.5), che si svuota alla chiusura del pannello.
- Rilegge `GET Inbox` quando `inbox` diventa disponibile, a ogni `InboxChanged`, a ogni riconnessione del WebSocket e all'apertura del pannello. Le risposte superate da una lettura più recente si scartano (contatore, come in `FriendsController`); anche le azioni fanno avanzare il contatore, così una lettura partita prima non rimette la voce tolta.
- Azioni: `remove(id)`, `clear()`. Si vedono subito e **dopo ogni azione si rilegge, anche se è riuscita**: il plugin manda `InboxChanged` solo se qualcosa è cambiato, e la lettura scartata non tornerebbe. Se la chiamata fallisce compare la snackbar `inboxActionFailed` (la mostra il pannello, l'azione restituisce l'esito).
- `ShellPanelController` chiama `panelOpened()` e `panelClosed()`: con il pannello aperto le voci non lette diventano lette (`markInboxRead(upTo)`, sul plugin fino alla più recente) e prendono il pallino; alla chiusura i pallini spariscono. Il flag "pannello aperto" si azzera solo al cambio di utente (non quando la funzione va e viene).
- `unread` per il numero sull'icona.

### 7.4 Icona nella barra

`InboxButton` dopo `FriendsButton` e prima dell'avatar: icona Lucide `inbox`, tooltip "Notifiche", numero dorato dei non letti come `PartyChip` (oltre 99: "99+"). Compare con `inbox` disponibile, **anche senza accesso ai watch party**.

### 7.5 Pannello

- Lo stato è unico (`shellPanelProvider`: nessuno / amici / notifiche) e il contenitore è comune (`ShellSidePanel`, usato anche dal pannello Amici): `Positioned(top: 0, right: 0, bottom: 0)`, 360 px, `WfColors.surface`, resto della finestra scurito; ×, Esc, clic sullo scuro, tasto indietro / Alt+← / tasto indietro del mouse lo chiudono; Esc con un menu aperto chiude prima il menu; entrata da destra, con "Ridotte" solo dissolvenza.
- **Un pannello alla volta:** aprire Notifiche chiude Amici e viceversa. Quando si apre il player i pannelli si chiudono (la shell resta montata sotto).
- **Apertura:** se `unread > 0`, `markInboxRead(seq della prima voce)` e il numero sull'icona sparisce. Le voci che erano non lette all'apertura hanno un pallino dorato finché il pannello resta aperto. Una voce che arriva a pannello aperto prende il pallino e viene segnata subito come letta. La tastiera parte dalla × dell'intestazione. Se la cassetta ha inviti (e c'è l'accesso ai watch party), l'elenco dei party (`WatchPartyDirectory`, che si rilegge ogni 30 s) si rilegge all'apertura e dopo un ingresso non riuscito.
- **Intestazione:** "Notifiche", **Svuota** (diventa **Conferma** per 4 s; nascosto se la cassetta è vuota), × (testo "Chiudi").
- **Voci** per `Seq` decrescente; le liste lunghe scorrono dentro il pannello. Ogni voce: icona o miniatura, contenuto, ora relativa, × (visibile al passaggio del mouse e col fuoco; tooltip "Rimuovi").
- **Vuota:** "Nessuna notifica". **Errore** del caricamento: "Notifiche non disponibili" + **Riprova**. Al primo caricamento il pannello resta vuoto (niente indicatore che gira), come Amici.

### 7.6 Le voci

- **Ora relativa:** "adesso" (meno di 1 minuto), "{n} min fa", "{n} h fa" (solo nello **stesso giorno di calendario**), "ieri" (giorno di calendario precedente), "{n} giorni fa" (fino a 6), poi la data breve nella lingua dell'app. Da `clock.now()`.
- **× di ogni voce:** invisibile senza mouse o fuoco, ma resta nell'albero dell'accessibilità (per i lettori di schermo).
- **Invito:** miniatura della locandina (`ImageItemId`), "**{nome}** ti invita a guardare" (il nome di chi invita in grassetto e color crema, il resto attenuato) e sotto il titolo. Azione:
  - **Unisciti** se il gruppo è nell'elenco dei party (`WatchPartyDirectory`: l'invito lo rende visibile finché il party esiste) e non ci siamo già: stesso ingresso del pannello Amici, che chiude il pannello solo se l'ingresso riesce. Il pulsante resta **disattivato mentre l'ingresso è in corso**: un secondo clic non ne fa partire un altro;
  - "Ci sei già" se siamo in quel gruppo;
  - "Party finito" (attenuato) altrimenti.
- **Novità** (piano 13b): icona Lucide `sparkles`, "Novità: 2 film, 10 episodi" (solo le parti presenti, con i plurali). Sotto le prime 5 righe — film "Dune: Parte Due (2024)", serie "The Bear · S3 E1–E10" — poi **Mostra tutto ({n})**, che apre l'elenco dentro la voce. Ogni riga apre la scheda (film o serie) e chiude il pannello. In fondo "…e altri {n} titoli" se `More > 0` (non cliccabile).
- **Annuncio:** icona Lucide `megaphone`, "Annuncio" e il testo intero (selezionabile, con gli a capo).

### 7.7 Dal vivo e player

- La scheda d'invito (`WatchPartyInvites`) resta com'è; l'invito arriva anche nella cassetta e fa salire il numero.
- Nuovi titoli e annunci non hanno scheda.
- Con il player aperto i pannelli laterali sono chiusi (si chiudono quando il player si apre) e si aggiorna solo il numero sull'icona.

## 8. Senza plugin ed errori

| Caso | Comportamento |
|---|---|
| Plugin 1.0/1.1 o assente | niente icona; l'app si comporta come la 0.6.0 |
| `Info` non ancora risposto / errore di rete | niente icona finché `inbox` non è noto (§7.2) |
| `GET Inbox` fallisce | pannello "Notifiche non disponibili" + Riprova; il numero resta l'ultimo noto |
| `markInboxRead` fallisce | il numero torna alla prossima lettura; nessun messaggio |
| Rimuovi / Svuota falliscono | si rilegge, snackbar `inboxActionFailed` |
| Annuncio con testo non valido | 400; la pagina della Dashboard mostra l'errore |
| Elemento di una riga Novità cancellato | la scheda mostra l'errore che mostra già per un elemento mancante |
| App 0.6.0 con plugin 1.2.0 | `InboxChanged` scartato (riga `info`); il resto invariato |

## 9. Testi nuovi (ARB, it + en)

| Chiave | Italiano | English |
|---|---|---|
| `inboxTitle` (titolo del pannello e tooltip dell'icona) | Notifiche | Notifications |
| `inboxClear` | Svuota | Clear all |
| `inboxClearConfirm` | Conferma | Confirm |
| `inboxRemove` | Rimuovi | Remove |
| `inboxEmpty` | Nessuna notifica | No notifications |
| `inboxUnavailable` | Notifiche non disponibili | Notifications unavailable |
| `inboxActionFailed` | Non è stato possibile aggiornare le notifiche | Couldn't update notifications |
| `inboxInviteFrom` | {name} ti invita a guardare | {name} invited you to watch |
| `inboxAlreadyIn` | Ci sei già | You're in it |
| `inboxPartyEnded` | Party finito | Party ended |
| `inboxAnnouncement` | Annuncio | Announcement |
| `inboxNow` | adesso | just now |
| `inboxMinutesAgo` | {count} min fa | {count} min ago |
| `inboxHoursAgo` | {count} h fa | {count} h ago |
| `inboxYesterday` | ieri | yesterday |
| `inboxDaysAgo` | {count} giorni fa | {count} days ago |

Chiavi che restano per il piano 13b (voce Novità):

| Chiave | Italiano | English |
|---|---|---|
| `inboxNewTitles` | Novità: {summary} | New: {summary} |
| `inboxMovies` | {count, plural, =1{1 film} other{{count} film}} | {count, plural, =1{1 movie} other{{count} movies}} |
| `inboxEpisodes` | {count, plural, =1{1 episodio} other{{count} episodi}} | {count, plural, =1{1 episode} other{{count} episodes}} |
| `inboxNewEpisodes` | {count, plural, =1{1 episodio nuovo} other{{count} episodi nuovi}} | {count, plural, =1{1 new episode} other{{count} new episodes}} |
| `inboxShowAll` | Mostra tutto ({count}) | Show all ({count}) |
| `inboxMore` | {count, plural, =1{…e un altro titolo} other{…e altri {count} titoli}} | {count, plural, =1{…and 1 more} other{…and {count} more}} |

Chiavi già esistenti, riusate (niente doppioni): `retry` ("Riprova", per il caricamento fallito), `watchPartyJoin` ("Unisciti"), `friendsClose` ("Chiudi", la × dell'intestazione). Il segnaposto dei numeri è sempre `{count}`. Non c'è una chiave per la diagnostica: la riga "Funzioni del plugin" scrive "notifiche" come testo fisso, come "amici" e "party".

## 10. Test

- **Plugin** (xUnit, `FakeServer`, `FakeTimeProvider`):
  - `InboxStore`: scrittura atomica, file `.bad`, 100 voci per utente, 30 giorni, utenti cancellati;
  - `InboxService`: `Seq`, lettura fino a `UpTo` (una voce aggiornata dopo resta non letta), cancellazione ripetibile, svuotamento, annunci (bordi, 0/500/501 caratteri, destinatari solo attivi, admin compreso), `InboxChanged` alle sole sessioni WonderFlix dell'utente;
  - voci d'invito: elemento dalle sole sessioni del party ancora tra i partecipanti (prima chi invita), mai da una sessione fuori dal party, nessuna voce senza elemento, senza accesso o per un invitato disabilitato, errori solo nel log (l'invito riesce lo stesso), aggiornamento invece del doppione;
  - pulizia periodica: notifiche scadute tolte; un errore dei party non salta le notifiche e viceversa;
  - `NewTitlesCollector` (13b): 15 minuti / 2 ore, sostituzioni per id esterno, aggiunto+tolto, elementi spariti alla chiusura, film visibili, episodi solo di serie seguite (preferita / altro episodio visto o iniziato), tetto di 500 righe e `More`, casella spenta;
  - controller: annunci solo admin, endpoint della cassetta e `Info` per un utente senza accesso ai watch party, mai 404;
  - pagina di configurazione incorporata e registrata.
- **Controllo dei riferimenti** della dll contro Jellyfin 10.11.9 prima di ogni deploy (eventi della libreria, dati utente, visibilità degli elementi, `NowPlayingItem`).
- **App:** modelli (voci sconosciute o malformate saltate, `unread` calcolato dall'app) e `parseSocialEvent`; `inboxTimeLabel` (e `formatEpisodeRanges`, 13b); `InboxController` (letture, risposte superate, azioni ottimistiche ed errori, rilettura dopo ogni azione, pallini); `InboxButton` (numero, 99+, visibilità); `shellPanelProvider` e `ShellSidePanel` (un pannello alla volta, chiusura all'apertura del player, tasti di chiusura); pannello (stati, pallini, Unisciti / Ci sei già / Party finito, Svuota → Conferma, ×, fuoco sulla × dell'intestazione; Mostra tutto con il 13b).
- **Prova manuale sul server** (due istanze, `WONDERFLIX_PROFILE=b`): annuncio dalla Dashboard; invito a chi ha l'app chiusa, poi apertura; con il 13b, un titolo nuovo aggiunto alla libreria e attesa della fine dell'ondata (15 minuti).

## 11. Piani e release

- **13a — cassetta da capo a fondo:** plugin (archivio, servizio, endpoint, `InboxChanged`, voci d'invito, annunci, pagina di configurazione); app (nucleo, disponibilità, controller, icona, pannello e contenitore comune dei pannelli laterali, voci Invito e Annuncio). Plugin copiato a mano sul server per la prova (`ssh ultra`, stop → copia → avvio).
- **13b — nuovi titoli e release:** plugin (`NewTitlesCollector`, `PluginConfiguration` con la casella "Notify new titles"); app (voce Novità, `formatEpisodeRanges`); poi plugin **1.2.0** (tag `watch-party-plugin-v1.2.0`, pre-release, voce nel manifest; sul server la copia manuale va in `~/wfwp-backup/`, poi aggiornamento dal Catalogo) e app **0.7.0 non obbligatoria** (niente `min-version`).
- **Issue #7:** dopo la pubblicazione e con l'ok dell'utente, commento ("Discord scartato; al suo posto la cassetta delle notifiche in [WonderFlix 0.7.0](link)") e chiusura come **non pianificata**.

## 12. Rischi e punti da verificare

- **API di Jellyfin 10.11.x:** argomenti di `ItemAdded`/`ItemRemoved`, il controllo di visibilità di un elemento per un utente, i dati utente della serie (preferito, episodi visti o iniziati), `NowPlayingItem` della sessione. Jellyfin cambia API anche nelle patch: si verifica sulla 10.11.9 con il controllo dei riferimenti.
- **Ondate durante le scansioni** (13b): `ItemAdded` arriva prima dei metadati definitivi; la rilettura alla chiusura lo copre. Una sostituzione con id esterni diversi o assenti si annuncia come titolo nuovo.
- **Prima scansione di una libreria grande** (13b): una voce con 500 righe e "…e altri N titoli" per tutti; l'admin può spegnere la casella prima dell'importazione.
- **Costo delle serie seguite** (13b): una domanda per utente per serie a ogni ondata; con 5–20 utenti è poco, ma va fatta fuori dai thread delle richieste (lo è: la chiusura dell'ondata gira su un timer).
- **Dashboard 10.11:** la pagina legacy si carica ancora dentro la dashboard React; l'icona del menu è sempre quella predefinita (`MenuIcon` ignorato nella 10.11).
- **Backup di Jellyfin:** il backup integrato della 10.11 non copre `plugins/configurations`: amici e cassetta non sono nel backup (come oggi per `friends.json`).

## 13. Ricerca su Discord (per il futuro)

Fatta il 2026-10-03 sulla documentazione ufficiale (`docs.discord.com`, repository `discord-api-docs` al 2026-10-02). Conclusioni, nel caso si torni sull'idea:

- **Collegamento dell'account:** OAuth2 con `identify` senza approvazione; PKCE supportato (S256), opzione "Public Client" nel portale; redirect da registrare esatto. Token d'accesso di 7 giorni; revoca con `POST /oauth2/token/revoke`.
- **Lista amici:** nessun endpoint REST; solo il **Social SDK** (DLL nativa con API C, attivazione self-service, amici e presenza senza approvazione, documentazione e termini pensati per i giochi).
- **Messaggi a un utente:** un bot può mandare DM solo a chi condivide un server con lui e accetta i DM dai membri (errori 50007/50278); funziona solo REST, senza gateway. Con `guilds.join` il collegamento può aggiungere l'utente a un server.
- **Inviti cliccabili / Ask to Join:** richiedono un comando di avvio registrato (`discord-<id>://`), cioè l'ingresso da Discord escluso dall'utente.
- **Pulsanti della Rich Presence:** massimo 2, solo link, invisibili a chi li imposta: non sono un canale di notifica.
