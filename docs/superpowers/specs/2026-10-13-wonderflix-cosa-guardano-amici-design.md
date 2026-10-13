# WonderFlix — Spec O: cosa guardano gli amici

- **Data:** 2026-10-13
- **Stato:** approvata nel brainstorming del 2026-10-13; da rivedere per iscritto.
- **Ambito:** Spec O. Realizza l'idea 5 di `docs/IDEE.md` ("Cosa guardano gli amici"): nel pannello Amici compare cosa sta guardando un amico anche fuori dai watch party, con "Guarda insieme" per aprire un party su quel titolo e invitarlo; in Home la riga "Visti dagli amici"; un interruttore per non mostrare cosa si guarda.

## 1. Obiettivo

- **Sta guardando.** Nel pannello Amici, al posto di "Online", "Sta guardando *Dune*" (o "*Breaking Bad* · S2 E3").
- **Guarda insieme.** Un tasto sulla riga dell'amico apre un party privato sullo stesso titolo, dal punto in cui è l'amico, e lo invita.
- **Visti dagli amici.** Una riga della Home con i titoli che gli amici hanno guardato negli ultimi 30 giorni e che io non ho mai visto né iniziato.
- **Privacy.** Un interruttore "Mostra agli amici cosa guardo", acceso se non lo si tocca.

Nota sul modello: somiglia allo stato "Sta giocando a…" di Steam o Discord, non a Netflix (che non ha niente del genere). "Visti dagli amici" non è un algoritmo di consigli: sono le ultime visioni degli amici dentro WonderFlix, registrate dal plugin. Conta solo WonderFlix: chi guarda con un'altra app Jellyfin (web, telefono, TV) non compare.

## 2. Situazione di partenza

App 0.14.0, plugin 1.8.0, Jellyfin 10.11.9 su Ultra.cc.

- **Presenza** (Spec F): `GET Friends` restituisce `FriendEntry(UserId, Name, Online, Party?)`; "Online" = una sessione Jellyfin con `Client == "WonderFlix"` (`ISessionDirectory.GetAppSessions`). Gli aggiornamenti arrivano con l'avviso `FriendsChanged` (senza dati: l'app rilegge), mandato da `PresenceTracker.Changed(userId)` con 2 s di attesa per unire le ripetizioni. Oggi lo chiamano inizio e fine sessione, registrazione del party, ingresso e uscita dal canale del party: **l'inizio e la fine di una riproduzione non lo chiamano**.
- **Cosa riproduce una sessione:** `ILibraryAccess.NowPlaying(sessionId)` → `PlayingItem(ItemId, ImageItemId)` (per un episodio l'immagine è della serie), usato dalla cassetta per gli inviti.
- **Permessi:** `ILibraryAccess.CanSee(userId, itemId)`.
- **Visioni:** `IRecommendationLibrary.LastWatched(userId, itemId)` (film: `LastPlayedDate`; serie: l'episodio visto più di recente). `GetTitle(itemId)` dà nome e tipo di film e serie.
- **Party:** l'app crea il gruppo SyncPlay (`startWatchParty`, con `start` e `mode`), lo registra (`POST Parties/{groupId}`) e invita (`POST Parties/{groupId}/Invites`).
- **Home** (Spec M, N): id stabili (`HomeRowIds.Known`, `HomeRowKind`), righe aggiunte dopo con `HomeRowIds.AddedLater` + `HomeRowsSeen` (`AddLaterRows` all'avvio), gate con motivo (`HomeRowGate`).
- **Archivi per utente** nel plugin: file JSON in `<PluginConfigurationsPath>/WonderFlixWatchParty/` con versione, scrittura atomica e `.bad` (`InboxStore`, `RecommendationStore`, `ContactStore`). Nessuna impostazione di privacy per utente esiste oggi.
- **Annuncio dell'admin:** `POST Inbox/Announcements` manda un testo nella cassetta di tutti.

## 3. Decisioni

Prese con l'utente nel brainstorming del 2026-10-13:

1. **Visibile se non si tocca nulla.** La novità si spiega con un annuncio dell'admin nella cassetta all'uscita della release (nessun codice).
2. **Solo WonderFlix**, come "Online".
3. **Guarda insieme dal punto dell'amico:** il party parte dalla posizione in cui l'amico è adesso; per un episodio, lo stesso episodio.
4. **Riga Home:** visioni degli amici degli ultimi 30 giorni (anche solo iniziate), tolti i titoli che ho già visto o iniziato io, dal più recente.
5. **Un solo interruttore** per "Sta guardando" e per la riga.
6. **Solo da quando c'è la funzione:** il plugin registra le visioni da sé, dalla 1.9.0; nessuna visione precedente (né di altre app) diventa visibile.
7. **Approccio A:** il plugin legge le sessioni di Jellyfin e tiene il suo registro; l'app non manda niente di nuovo.
8. **App 0.15.0 obbligatoria:** con la 0.14.0 si condivide senza poter spegnere.

## 4. Perimetro

### Incluso

- Plugin 1.9.0: `NowPlaying` in `GET Friends`, posizione per "Guarda insieme", aggiornamento della presenza a inizio e fine riproduzione, registro delle visioni, impostazione `ShareActivity`, riga `friendsWatched`, funzione `friendsActivity` in `Info`.
- App 0.15.0: "Sta guardando" e "Guarda insieme" nel pannello Amici, interruttore nelle impostazioni, riga "Visti dagli amici", testi it/en.

### Escluso

- Visioni da altre app Jellyfin; visioni precedenti alla 1.9.0.
- Avviso "Luca ha iniziato a guardare…" (niente notifiche, solo lo stato nel pannello).
- "In pausa", barra di avanzamento o tempo rimanente dell'amico.
- Due interruttori separati; scelta di quali amici vedono cosa.
- "Non mi interessa" e messaggi nella riga "Visti dagli amici".
- Cronologia personale (idee 13 e 14): il registro non è esposto a chi l'ha prodotto.

## 5. Architettura

```
Jellyfin (sessioni WonderFlix) ──PlaybackStart/Progress/Stopped──▶ Plugin
    ├──▶ PresenceTracker.Changed ──FriendsChanged──▶ app degli amici ──GET Friends──▶ NowPlaying (dal vivo)
    └──▶ activity.json (visioni ≥ 5 min)
App (Guarda insieme) ──GET Friends/{id}/NowPlaying──▶ posizione ──▶ startWatchParty(Private) ──▶ Invites
App (Home) ──GET Activity/FriendsWatched──▶ Plugin (amici, interruttore, CanSee, non visti da me)
App (Impostazioni) ──GET/PUT Activity/Settings──▶ privacy.json
```

- "Sta guardando" non si salva: si legge dalle sessioni a ogni `GET Friends`.
- Solo la riga usa il registro.

## 6. Plugin 1.9.0

### 6.1 Impostazione `ShareActivity`

- File `privacy.json`: `{"Version": 1, "Users": {"<userId>": {"ShareActivity": false}}}`. Un utente assente vale `ShareActivity = true` (si scrivono solo le scelte fatte). Stesse regole di file degli altri archivi (caricamento all'avvio con il suo `try/catch`, scrittura atomica sotto lock, `.bad`).
- `GET Activity/Settings` → `{ShareActivity}`; `PUT Activity/Settings` `{ShareActivity}` → 204. Corpo mancante o senza il campo → 400.
- **Spegnere:**
  1. salva;
  2. cancella dal registro (§6.4) tutte le visioni di quell'utente;
  3. `PresenceTracker.Changed(userId)`, così gli amici vedono subito solo "Online".
- **Accendere:** salva e `PresenceTracker.Changed(userId)`. Le visioni cancellate non tornano; si registrano quelle nuove.

### 6.2 "Sta guardando" in `GET Friends`

`FriendEntry` riceve `NowPlaying` (assente se non vale):

```
NowPlaying {ItemId, Title, SeriesId?, SeriesName?, Season?, Episode?}
```

- `ItemId` e `Title`: il film o l'episodio. Per un episodio anche `SeriesId`, `SeriesName`, `Season` (`ParentIndexNumber`) ed `Episode` (`IndexNumber`), ciascuno assente se Jellyfin non lo conosce.
- Si calcola solo per gli amici online e solo se valgono **tutte**:
  1. l'amico non è in un party che chi chiama vede (`Party` assente). Se l'amico è in un party che chi chiama non vede, `NowPlaying` resta assente: non si rivela cosa guarda un party nascosto;
  2. l'amico ha `ShareActivity` acceso;
  3. una sua sessione WonderFlix riproduce un film o un episodio (non trailer, video, musica);
  4. chi chiama può vedere quell'elemento (`CanSee`). Altrimenti l'amico risulta solo "Online", senza indizi.
- Più sessioni WonderFlix dello stesso amico che riproducono: vale quella con l'ultimo resoconto più recente (`LastPlaybackCheckIn`).
- Errore della libreria per un amico: `NowPlaying` assente (`Warning`), il resto della risposta arriva.

### 6.3 Aggiornamento della presenza

- Il servizio a orario nuovo `ActivityHostedService` ascolta `ISessionManager.PlaybackStart` e `PlaybackStopped` delle sessioni WonderFlix e chiama `PresenceTracker.Changed(userId)`: gli amici ricevono `FriendsChanged` (2 s di attesa come oggi). Cambiare episodio dà `Stopped` + `Start`, uniti dall'attesa.
- Con `ShareActivity` spento non si chiama (non c'è niente da cambiare per gli amici).
- Nessun controllo periodico.

### 6.4 Registro delle visioni (`activity.json`)

- Contenuto: `{"Version": 1, "Users": {"<userId>": [{"ItemId": "…", "WatchedAt": "…"}]}}`. `ItemId` è il film o la **serie** (per un episodio si registra la serie). Id in formato `N`, date ISO-8601 UTC.
- **Quando si registra:** per una sessione WonderFlix con un film o un episodio, la prima volta che `PlaybackProgress` riporta una posizione ≥ 5 minuti, oppure a `PlaybackStopped` con `PlayedToCompletion` o posizione ≥ 5 minuti. Per non riscrivere il file a ogni resoconto, in memoria si ricorda la coppia (sessione, elemento) già registrata; si dimentica a `PlaybackStopped`.
- Contano anche le visioni nei watch party.
- Solo con `ShareActivity` acceso (letto al momento della registrazione).
- **Un titolo una volta per utente:** se c'è già, si aggiorna `WatchedAt`.
- **Tetto:** 100 titoli per utente; oltre si toglie il `WatchedAt` più vecchio.
- **Pulizia** in `ActivityHostedService`, ogni 5 minuti con il suo `try/catch`: via le visioni con più di 30 giorni e gli utenti che non esistono più. Salvataggio solo se qualcosa è cambiato.

### 6.5 Posizione per "Guarda insieme"

`GET Friends/{userId}/NowPlaying` → `{ItemId, PositionTicks}`:

- Stessi controlli di §6.2 (amico di chi chiama, online, non in un party, `ShareActivity`, sessione WonderFlix che riproduce un film o un episodio, `CanSee` di chi chiama). Se uno non vale → **409** (mai 404); `userId` senza vincoli di rotta.
- `PositionTicks`: la posizione dell'ultimo resoconto; se la riproduzione non è in pausa, più il tempo passato da `LastPlaybackCheckIn`, senza superare la durata dell'elemento.

### 6.6 Riga "Visti dagli amici"

`GET Activity/FriendsWatched` → `{Items: [{ItemId, By: [{UserId, Name, WatchedAt}]}]}`:

1. si prendono le visioni degli amici attuali di chi chiama, non disabilitati, con `ShareActivity` acceso, degli ultimi 30 giorni;
2. si raggruppano per titolo; la data del titolo è il `WatchedAt` più recente; dal più recente, `By` dal più recente;
3. si scartano i titoli che chi chiama non vede (`CanSee`) e quelli che ha già visto o iniziato (`LastWatched(chiChiama, titolo)` non `null`, da qualunque app e in qualunque momento);
4. al massimo 30 titoli nella risposta (i controlli del punto 3 si fanno in ordine fino a riempire i 30, su al massimo 60 titoli).

- Errore della libreria per un titolo: si salta (`Warning`), la risposta arriva.
- Il filtro è solo a lettura: il registro non cambia.

### 6.7 Endpoint, policy, `Info`, Home

- `ActivityController` (`Activity/Settings`, `Activity/FriendsWatched`) e la nuova rotta in `FriendsController`, con la stessa policy degli amici (accesso a SyncPlay). Chi chiama si ricava dal token.
- `Info.Features` aggiunge `"friendsActivity"`; `Protocol` resta 1; `Version` "1.9.0".
- `HomeRowIds.Known` aggiunge `"friendsWatched"` subito dopo `"recommended"`; `HomeRowIds.AddedLater` diventa `["recommended", "friendsWatched"]`. L'inserimento nella Home dell'admin e `HomeRowsSeen` seguono Spec N §6.7 (una volta sola, dopo l'ultima riga accesa che la precede nell'ordine predefinito).
- Log: **mai titoli o nomi**, solo id e numeri. `Debug` per visione registrata e impostazione cambiata; `Warning` per file illeggibile, errori di scrittura, errori della libreria.

## 7. App 0.15.0

### 7.1 Nucleo

- `FriendEntry.nowPlaying` (`FriendNowPlaying{itemId, title, seriesId?, seriesName?, season?, episode?}`).
- `SocialApi`: `friendNowPlaying(userId)` → `{itemId, position}` (409 → eccezione dedicata), `activitySettings()`, `setActivitySettings(share)`, `friendsWatched()`; stessi in `FakeSocialApi`.
- `SocialFeatures.friendsActivity` (funzione `friendsActivity` del plugin). Vale solo con l'accesso ai watch party, come gli amici.

### 7.2 Pannello Amici

- **Testo sotto il nome:**
  - film: "Sta guardando *Dune*" (`friendsWatching`);
  - episodio: "Sta guardando *Breaking Bad* · S2 E3" (`friendsWatchingEpisode`), senza "S… E…" se mancano stagione o numero, con il nome dell'episodio se manca la serie.
  - "Nel watch party: …" resta com'è e ha la precedenza (il plugin non manda `NowPlaying` in quel caso).
- **Guarda insieme** (pulsante sulla riga, dove sta "Unisciti" per i party): solo con `nowPlaying` e se non sono già in un gruppo SyncPlay. Al clic:
  1. `friendNowPlaying(userId)` per la posizione aggiornata;
  2. l'elemento da Jellyfin;
  3. `startWatchParty(item, start: posizione, mode: PartyMode.private)` **senza il menu delle modalità**;
  4. appena il party è registrato, `invite(groupId, [userId])` e `currentPartyProvider.invited`.
  - Il pulsante è spento mentre parte.
- **Esiti:**
  - 409 → "Non sta più guardando" e l'elenco si rilegge;
  - errore dell'invito dopo che il party è partito → il party resta e un avviso dice "Invito non inviato" (si può reinvitare dal menu del party);
  - altri errori → l'avviso che si usa già quando il watch party non parte.
- Aggiornamento con `FriendsChanged`, come oggi.

### 7.3 Interruttore nelle impostazioni

- Sezione **Account**: interruttore "Mostra agli amici cosa guardo" con sotto "Gli amici vedono il titolo che stai guardando e quelli che hai visto negli ultimi 30 giorni in WonderFlix".
- Vale per l'account Jellyfin (si legge e si scrive nel plugin), non per il dispositivo: con un altro profilo cambia.
- Compare solo con la funzione `friendsActivity`. Mentre si legge è spento; se la lettura non riesce, la riga dice "Impossibile caricare l'impostazione" con "Riprova".
- Salvataggio subito al cambio; se non riesce l'interruttore torna com'era e un avviso dice "Impostazione non salvata".

### 7.4 Riga "Visti dagli amici"

- `HomeRowKind.friendsWatched('friendsWatched')`, dopo `recommended`; `fromJellyfin` falso.
- `homeRowGate`: senza la funzione → nuovo motivo `HomeRowGate.friendsActivityOff` ("Serve il plugin 1.9.0 e l'accesso ai watch party").
- Caricamento come "Consigliati per te" (Spec N §7.3): `GET Activity/FriendsWatched`, poi gli elementi da Jellyfin per id nell'ordine del plugin, id mancanti saltati, riga vuota nascosta, riletta a ogni apertura della Home e quando cambiano libreria o dati di visione.
- **Card:** locandina; sotto il titolo "Visto da Luca", "Visto da Luca e Marta", "Visto da Luca e altri 2" (nomi dal più recente).
- Anteprima delle card come le altre righe di locandine, senza aggiunte.

## 8. Senza plugin ed errori

- **Plugin senza `friendsActivity`** (< 1.9.0): niente "Sta guardando", niente interruttore, riga non disponibile con il motivo, nessuna chiamata nuova.
- **`GET Activity/FriendsWatched` fallisce:** la riga non si vede, log con il solo tipo dell'errore.
- **L'amico spegne la condivisione mentre lo guardo:** `FriendsChanged` → l'elenco si rilegge e il testo torna "Online"; un "Guarda insieme" già partito riceve 409.
- **App 0.14.0 con plugin 1.9.0:** ignora `NowPlaying` e l'id di riga sconosciuto; non mostra l'interruttore, quindi i suoi utenti condividono senza poterlo spegnere. Per questo la **0.15.0 è obbligatoria**.

## 9. Testi nuovi (ARB, it + en)

| Chiave | it | en |
|---|---|---|
| `friendsWatching` | Sta guardando {title} | Watching {title} |
| `friendsWatchingEpisode` | Sta guardando {series} · S{season} E{episode} | Watching {series} · S{season} E{episode} |
| `friendsWatchTogether` | Guarda insieme | Watch together |
| `friendsNoLongerWatching` | Non sta più guardando | Not watching anymore |
| `friendsInviteNotSent` | Invito non inviato | Invite not sent |
| `settingsShareActivity` | Mostra agli amici cosa guardo | Show friends what I watch |
| `settingsShareActivityHint` | Gli amici vedono il titolo che stai guardando e quelli che hai visto negli ultimi 30 giorni in WonderFlix | Friends see what you're watching and what you watched in WonderFlix in the last 30 days |
| `settingsShareActivityLoadError` | Impossibile caricare l'impostazione | Couldn't load the setting |
| `settingsShareActivitySaveError` | Impostazione non salvata | Setting not saved |
| `homeRowFriendsWatched` | Visti dagli amici | Watched by friends |
| `friendsWatchedByOne` | Visto da {name} | Watched by {name} |
| `friendsWatchedByTwo` | Visto da {first} e {second} | Watched by {first} and {second} |
| `friendsWatchedByMany` | Visto da {name} e altri {count} | Watched by {name} and {count} others |
| `homeRowUnavailableFriendsActivity` | Serve il plugin 1.9.0 e l'accesso ai watch party | Needs plugin 1.9.0 and watch party access |

"Riprova" c'è già. "Visto da" si riferisce al titolo, non alla persona: i testi non danno per scontato il genere di nessuno.

## 10. Sicurezza e privacy

- Le visioni arrivano solo agli amici, ricontrollati a ogni lettura; un amico rimosso non vede più niente alla lettura successiva.
- Nessun titolo arriva a chi non può vederlo (`CanSee` a ogni lettura); in quel caso non c'è nemmeno un indizio che l'amico stia guardando qualcosa.
- Un party nascosto non si rivela con "Sta guardando".
- Interruttore spento: niente "Sta guardando", visioni registrate cancellate, nessuna nuova registrazione.
- Solo visioni WonderFlix dalla 1.9.0 in poi; il registro tiene 30 giorni.
- La mia cronologia di Jellyfin (`LastWatched`) serve solo a togliere dalla mia riga i titoli che ho già visto; non arriva a nessun altro.
- Nei log nessun titolo né nome.

## 11. Test

### 11.1 Plugin (xUnit)

- `privacy.json`: predefinito acceso, spegnere cancella le visioni e chiama `Changed`, file illeggibile → `.bad`.
- `NowPlaying` in `GET Friends`: ogni condizione di §6.2 (offline, in un party visibile e nascosto, condivisione spenta, sessione non WonderFlix, tipo non valido, `CanSee` falso), episodio con e senza stagione/numero, più sessioni, errore della libreria.
- `Friends/{id}/NowPlaying`: 409 per ogni condizione, non amico, posizione con e senza pausa, tetto alla durata.
- Registro: soglia dei 5 minuti, `PlayedToCompletion`, una registrazione per (sessione, elemento), serie al posto dell'episodio, aggiornamento di `WatchedAt`, tetto 100, pulizia dei 30 giorni e degli utenti spariti, nessuna registrazione con la condivisione spenta.
- `FriendsWatched`: raggruppamento e ordine, amici non più amici o disabilitati o con la condivisione spenta, `CanSee`, già visto da chi chiama, tetto 30, errore della libreria.
- Presenza: `PlaybackStart`/`Stopped` WonderFlix chiamano `Changed`, le altre sessioni no.
- `HomeRowIds` con `friendsWatched` e inserimento una volta sola; controllo dei riferimenti della dll contro Jellyfin 10.11.9.

### 11.2 App

- Modelli e JSON (`nowPlaying` presente o assente).
- Pannello: testi film ed episodio, precedenza del party, pulsante solo fuori da un gruppo, flusso "Guarda insieme" (posizione, modalità privata senza menu, invito), 409, errore dell'invito.
- Interruttore: solo con la funzione, lettura, errore e Riprova, salvataggio e ritorno indietro.
- Riga: gate, ordine, elementi mancanti saltati, riga vuota nascosta, testi "Visto da …".

### 11.3 Prova a mano

Due istanze (`WONDERFLIX_PROFILE=b`) con due utenti amici: "Sta guardando" film ed episodio, cambio episodio, stop; "Guarda insieme" con l'amico a metà; visione oltre 5 minuti e riga "Visti dagli amici" dall'altra parte; interruttore spento (sparisce lo stato e la riga si svuota); un utente con limite d'età per `CanSee`.

## 12. Rischi e punti da verificare

Da verificare sul sorgente di Jellyfin 10.11.9 all'inizio del piano 21a:

- `ISessionManager.PlaybackStart`/`PlaybackProgress`/`PlaybackStopped` e i loro argomenti (`Session`, `Item`, `PlaybackPositionTicks`, `PlayedToCompletion`) per le sessioni che riportano con `/Sessions/Playing*`.
- `SessionInfo.PlayState` (`PositionTicks`, `IsPaused`) e `LastPlaybackCheckIn`: quanto è aggiornato tra un resoconto e l'altro (l'app riporta ogni 10 s).
- Un player WonderFlix chiuso male: Jellyfin toglie `NowPlayingItem` quando la sessione non riporta più? Se resta, "Sta guardando" può durare fino alla fine della sessione (accettabile, da annotare).
- Nei watch party ogni partecipante riporta la riproduzione dalla propria sessione: le visioni nei party si registrano senza codice dedicato.

## 13. Piani e release

- **21a — plugin 1.9.0:** verifiche di §12, `privacy.json`, `NowPlaying`, posizione, presenza, registro, `FriendsWatched`, `Info`, riga `friendsWatched`; build di prova installata a mano sul server (backup della 1.8.0 del Catalogo e della configurazione in `~/wfwp-backup/`). Nessuna release.
- **21b — app 0.15.0:** nucleo, pannello Amici, interruttore, riga, testi; prova con l'utente.
- **Release** (con l'OK dell'utente a ogni passo): plugin **1.9.0** dal Catalogo, poi app **0.15.0 obbligatoria** con le note in italiano nella bozza; poi l'annuncio dell'admin nella cassetta che spiega la novità e dove si spegne l'interruttore.
- **Alla fine**, in `docs/IDEE.md`: l'idea 5 esce dalla lista e tra le fatte c'è "Spec O — cosa guardano gli amici (plugin 1.9.0, app 0.15.0)".
