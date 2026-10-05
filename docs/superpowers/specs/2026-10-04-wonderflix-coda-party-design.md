# WonderFlix — Spec H: coda del watch party

- **Data:** 2026-10-04
- **Stato:** approvato; piano 14a realizzato (`docs/superpowers/plans/2026-10-04-wonderflix-14a-coda-party.md`), piano 14b realizzato (`docs/superpowers/plans/2026-10-04-wonderflix-14b-aggiungere-release.md`)
- **Ambito:** Spec H. Riprende l'esclusione della Spec B (`2026-09-30-wonderflix-watch-party-design.md`, §3 "Escluso": "Gestione avanzata della coda") e si appoggia alla Spec D (player: `2026-10-01-wonderflix-rinnovo-player-design.md`), alla Spec E (nomi dal plugin: `2026-10-02-wonderflix-watch-party-sociale-design.md` §8) e alla Spec F (disponibilità del plugin, `Features`).

## 1. Obiettivo

Oggi la coda del gruppo si imposta solo alla creazione del party (un film, oppure un episodio e i successivi, al massimo 50) e si scorre solo in avanti (⏭). La Spec H dà al party una **coda vera**:

- vederla, nel player, in un pannello "Coda";
- **aggiungere** film ed episodi ("Riproduci dopo" o "Aggiungi in coda"), cercandoli o da La mia lista;
- **saltare** a un titolo, **togliere**, **riordinare** trascinando;
- **titolo precedente** (⏮), anche da soli, per l'episodio precedente;
- **ordine casuale**;
- avvisi con il nome di chi ha cambiato la coda.

## 2. Situazione di partenza

- **App 0.7.0, coda:**
  - `buildPartyQueue` (`lib/features/watch_party/party_queue.dart`) dà `[film]` o l'episodio e i successivi, al massimo `maxPartyQueue = 50`.
  - `SyncPlayApi` (`lib/core/syncplay/syncplay_api.dart`) ha per la coda solo `setNewQueue` e `nextItem`.
  - `PlayQueue` (`syncplay_models.dart`) legge `Reason`, `LastUpdate`, `Playlist`, `PlayingItemIndex`, `StartPositionTicks` e `IsPlaying`. **Non** legge `ShuffleMode` e `RepeatMode`.
  - `WatchPartySession._onGroupUpdate` scarta solo le code con `LastUpdate` strettamente più vecchio e non distingue le `Reason`.
- **Player:**
  - In fondo, nella fila destra: ⏭ (episodio successivo), watch party, chat, reazioni, tracce, schermo intero.
  - Il tasto N e il tasto multimediale "successivo" fanno ⏭.
  - `PlayerPopup { tracks, chat, reactions }`: un pannello alla volta, Esc lo chiude.
  - `MediaButton { play, pause, next, stop }`: non c'è "precedente".
  - Quando l'elemento in corso del gruppo cambia, il player si sostituisce (`_handOverTo`, `pushReplacement`).
  - Nel party post-play e schedina "prossimo" mostrano il prossimo episodio della **libreria**, e solo se coincide con il prossimo della coda.
- **Avvisi** (`PartyNotices`):
  - quando l'elemento in corso cambia: `NextItem` → "Episodio successivo: X", tutto il resto → "Si guarda: X";
  - il nome arriva dal plugin, con le azioni `NextItem` e `NewQueue`;
  - gli altri cambi della coda non producono avvisi.
- **Plugin 1.2.0:**
  - `EventValidator` accetta le azioni `Pause`, `Unpause`, `Seek`, `NextItem` e `NewQueue`;
  - `Features: ["friends", "parties", "inbox"]`, `Protocol` 1;
  - il plugin non conosce la coda del gruppo.
- **Chiudere il player fa uscire dal party** (Spec B §2): chi è nel party sta nel player. Per questo la coda si gestisce **dal player**.

## 3. Il server (Jellyfin 10.11.9)

La ricerca sul codice di `jellyfin/jellyfin` al tag `v10.11.9` ha dato questi fatti. Da 10.11.9 a 10.11.11 i file SyncPlay non cambiano.

- **Endpoint** (`POST /SyncPlay/…`). Servono l'accesso a SyncPlay e lo stare in un gruppo. Chiunque nel gruppo può usarli: non c'è un proprietario.

  | Endpoint | Corpo |
  |---|---|
  | `Queue` | `ItemIds`, `Mode: "Queue"` (in fondo) o `"QueueNext"` (subito dopo l'elemento in corso); l'ordine dato si mantiene |
  | `SetPlaylistItem` | `PlaylistItemId` |
  | `PreviousItem` | `PlaylistItemId` dell'elemento in corso, che il server usa come controllo |
  | `RemoveFromPlaylist` | `PlaylistItemIds`, `ClearPlaylist`, `ClearPlayingItem` |
  | `MovePlaylistItem` | `PlaylistItemId`, `NewIndex` |
  | `SetShuffleMode` | `Mode: "Shuffle"` o `"Sorted"` |
- **Le risposte sono sempre 204**, anche quando il server scarta la richiesta. Si capisce com'è andata solo dall'aggiornamento `PlayQueue` sul WebSocket.
- **Aggiornamento `PlayQueue`.** Tutti ricevono la coda intera.
  - `Reason` vale `NewPlaylist`, `SetCurrentItem`, `RemoveItems`, `MoveItem`, `Queue`, `QueueNext`, `NextItem`, `PreviousItem`, `RepeatMode` o `ShuffleMode`.
  - Con l'ordine casuale `Playlist` è **nell'ordine mescolato**, e `PlayingItemIndex` è l'indice in quella lista.
  - Alcune correzioni riusano lo stesso `LastUpdate`.
- **Coda e permessi.**
  - `Queue` non cambia lo stato del gruppo e non avvia nulla.
  - Se **un membro qualsiasi non può vedere** uno dei titoli, la richiesta si scarta in silenzio.
  - Un id inesistente fa rispondere 500.
  - Il server non ha un limite di lunghezza.
- **Salto, precedente, successivo.**
  - `SetPlaylistItem`, `PreviousItem` e `NextItem` portano il gruppo in attesa: tutti caricano l'elemento, da 0, e si parte quando sono tutti pronti.
  - `PreviousItem` sul primo elemento non fa nulla.
  - Con `PlaylistItemId` diverso da quello in corso, `PreviousItem` e `NextItem` **lasciano il gruppo in attesa**: bug del server. `SetPlaylistItem` con un id che non esiste lascia il gruppo **senza elemento in corso**.
- **Rimozione.**
  - Se si toglie l'elemento in corso, il server passa al precedente **senza** fase di attesa.
  - Con più id, tra cui quello in corso, l'indice può andare fuori dalla lista: errore 500 e gruppo rotto (bug del server, corretto solo su master).
  - Togliere un solo elemento che non è quello in corso è sicuro.
- **Spostamento.** Agisce sulla lista attiva (quella mescolata, se c'è l'ordine casuale) e conserva l'elemento in corso. `NewIndex` si conta dopo aver tolto l'elemento dalla sua posizione.
- **Ordine casuale.**
  - **Acceso:** l'elemento in corso va in testa e **tutti** gli altri si mescolano, anche quelli già visti.
  - **Spento:** torna l'ordine originale, e gli spostamenti fatti da mescolato si perdono.
  - Mandare `Sorted` quando la coda è già ordinata dà **errore 500** (bug del server).
  - `SetNewQueue` riporta la coda all'ordine originale e la ripetizione a "nessuna".

## 4. Decisioni

| Tema | Decisione |
|---|---|
| Funzioni | pannello Coda, aggiungere (dopo / in fondo), togliere, riordinare, titolo precedente, ordine casuale |
| Ripetizione | **esclusa** |
| Dove | solo nel player, pannello "Coda" a destra (360 px); il pulsante Coda c'è solo nel party |
| Pannello | una vista alla volta: Coda → Aggiungi → Serie → Stagione, ← per tornare indietro |
| Aggiungere | ricerca (film e serie) e, a campo vuoto, La mia lista; una serie si apre su stagioni ed episodi |
| Tetto | **100** titoli in tutta la coda; la coda iniziale di una serie resta di 50 |
| Doppioni | un titolo in corso o tra i prossimi non si riaggiunge (✓ "In coda"); uno già visto sì |
| Chi può | tutti i membri (come pausa e salto) |
| Precedente | ⏮, tasto P, tasto multimediale "indietro", SMTC; nel party il titolo precedente della coda, da soli l'episodio precedente della serie |
| Prossimo nel post-play | nel party il prossimo titolo **della coda** (anche un film) |
| Nomi | plugin **1.3.0** con 5 azioni nuove e la funzione `queue` |
| Release | plugin 1.3.0, poi app **0.8.0 non obbligatoria** |

## 5. Perimetro

### Incluso

- **App 0.8.0:**
  - API e modelli della coda;
  - regole e `PartyQueueEditor`;
  - pannello Coda con le quattro viste;
  - ⏮ nel party e da soli;
  - post-play dalla coda;
  - avvisi.
- **Plugin 1.3.0:** azioni nuove e `Features`.

### Escluso

- **Ripetizione** (`SetRepeatMode`): con film e serie serve poco.
- **Gestire la coda fuori dal player** (pagine della scheda, anteprime delle card): chi è nel party sta nel player (§2).
- **"Aggiunto da"** sulle righe della coda: il plugin non segue la coda.
- **Svuotare la coda** (`ClearPlaylist`).
- **Togliere il titolo in corso:** si cambia con ⏭, o con un clic su un altro titolo.
- **Episodi nella ricerca:** si arriva agli episodi passando dalla serie.
- **Dire *chi* non può vedere un titolo:** il server non lo dice, e il plugin non fa da intermediario.

## 6. Architettura

```
App 0.8.0
  lib/core/syncplay/      SyncPlayApi (+6 metodi), PlayQueue.shuffled
  lib/core/jellyfin/      LibraryApi.itemsByIds, LibraryApi.previousEpisode, LibraryApi.allEpisodes
  lib/core/party_channel/  PartyPluginInfo.features, PartyAction (+5)
  lib/features/watch_party/
    party_queue_rules.dart   funzioni pure: sezioni, posto libero, doppioni, indici
    party_queue_editor.dart  PartyQueueEditor: comandi, controlli, conferme, annunci
    party_queue_items.dart   partyQueueItemsProvider: dettagli dei titoli in coda
    watch_party_session.dart + previousItem, previousEntry/hasPrevious
    party_notices.dart       + avvisi della coda
  lib/features/player/
    player_side_panel_host.dart  PlayerSidePanelHost (estratto da TracksPanelHost)
    queue_panel/                 QueuePanel e le quattro viste, righe, ricerca
    player_screen.dart / player_overlay.dart / player_chrome.dart / player_commands.dart
  lib/core/media_session/  MediaButton.previous

Plugin 1.3.0
  Protocol/EventValidator.cs     + PreviousItem, SetCurrentItem, Queue, QueueNext, ShuffleMode
  Protocol/WatchPartyProtocol.cs Features + "queue"
```

L'app parla direttamente con gli endpoint SyncPlay; il plugin serve solo per i nomi. `WatchPartySession` (già 627 righe) riceve solo il "precedente", simmetrico al "successivo". Tutto il resto della coda passa da `PartyQueueEditor`.

## 7. Plugin 1.3.0

- `EventValidator`: le azioni valide diventano `Pause`, `Unpause`, `Seek`, `NextItem`, `NewQueue`, `PreviousItem`, `SetCurrentItem`, `Queue`, `QueueNext` e `ShuffleMode`. Nessuna richiede `PositionTicks`.
- `WatchPartyProtocol.Features`: `["friends", "parties", "inbox", "queue"]`. `Protocol` resta 1.
- Versione 1.3.0 e voce nel manifest alla release.
- **Test:** validatore (le 5 azioni nuove valide, una sconosciuta rifiutata) e `Info`.
- **App vecchie con plugin 1.3.0:** non annunciano le azioni nuove. Se ne ricevono una da un'app 0.8.0, `parsePartyEvent` la scarta (§2).

## 8. App: dati e comandi

### 8.1 API e modelli

- **`SyncPlayApi`:**
  - `queue(List<String> itemIds, {required bool next})`
  - `setPlaylistItem(String playlistItemId)`
  - `previousItem(String playlistItemId)`
  - `removeFromPlaylist(String playlistItemId)`: un solo id per richiesta, sempre con `ClearPlaylist` e `ClearPlayingItem` falsi
  - `movePlaylistItem(String playlistItemId, int newIndex)`
  - `setShuffleMode({required bool shuffle})`

  `FakeSyncPlayApi` le registra in `calls` come le altre.
- **`PlayQueue.shuffled`:** `true` se `ShuffleMode == "Shuffle"`.
- **`LibraryApi.itemsByIds(userId, ids)`:** `GET /Items?ids=…`, con i campi per le righe (serie, numeri di stagione ed episodio, durata, immagini) e la sinossi (`Overview`, per il post-play del party). Con una lista vuota non parte nessuna richiesta.
- **`LibraryApi.allEpisodes(userId, seriesId)`:** `GET /Shows/{seriesId}/Episodes` con `isMissing=false` e senza `seasonId`: tutti gli episodi veri della serie, una richiesta sola per le viste Serie e Stagione (§9.2).
- **`LibraryApi.previousEpisode(userId, seriesId, episodeId)`:** `GET /Shows/{seriesId}/Episodes` con `adjacentTo` e `isMissing=false`. Restituisce l'episodio prima di quello dato, anche nella stagione precedente, oppure `null`.
- **`WatchPartyState`:** `previousEntry`, cioè l'elemento prima di quello in corso, `null` se è il primo; e `hasPrevious`.
- **Funzione `queue` del plugin:** `PartyPluginInfo.features` (l'`Info` che chiede il canale del party) → `PartyChannelState.queueActions`, vera solo con il nostro protocollo; `PartyChannel.announce` manda le azioni della coda solo con questa funzione.
- **`PartyAction`:** `previousItem('PreviousItem')`, `setCurrentItem('SetCurrentItem')`, `queue('Queue')`, `queueNext('QueueNext')`, `shuffleMode('ShuffleMode')`.

### 8.2 Regole (`party_queue_rules.dart`)

Funzioni pure, testate a parte:

- `partyQueueLimit = 100`. La costante `maxPartyQueue = 50`, per la coda iniziale di una serie, resta.
- **Sezioni:** già visti (gli indici prima di `playingIndex`), in corso, prossimi (gli indici dopo).
- **Posto libero:** `100 - entries.length`, mai meno di 0.
- **Già in coda:** gli `ItemId` dell'elemento in corso e dei prossimi.
- **Titoli da aggiungere:** dati i candidati in ordine, si tolgono quelli già in coda, quelli di un'aggiunta ancora in attesa e i doppioni tra i candidati, poi si taglia al posto libero. Il risultato dice quanti si mandano, quanti erano già in coda e quanti restano fuori per il tetto.
- **Serie di un'aggiunta:** il nome della serie se i titoli sono tutti episodi della stessa serie, anche uno solo (`partyQueueSeriesOf`); serve agli avvisi.
- **Indice dello spostamento:** un titolo dei prossimi trascinato alla posizione *k* tra i prossimi (contata dopo averlo tolto) va al `NewIndex` = `playingIndex + 1 + k`. L'elemento in corso resta prima dei prossimi, perché trascinare un prossimo non ne cambia la posizione. Senza elemento in corso (tutti prossimi) il `NewIndex` è *k*.
- **Ordine provvisorio:** dopo un trascinamento i prossimi si mostrano nell'ordine scelto finché sono gli stessi elementi, senza ripetizioni.

### 8.3 `PartyQueueEditor`

È un provider, e lavora sempre sullo stato **attuale** della sessione. Se non si è in un gruppo, o se un id non è più nella coda, il comando non fa nulla.

- **`add(items, {required bool next})`:**
  1. calcola i titoli da mandare con le regole (§8.2);
  2. se non ne resta nessuno, risponde subito: tutti già in coda, oppure coda piena;
  3. altrimenti manda `queue` e, se il plugin ha `queue`, annuncia `Queue` o `QueueNext`;
  4. aspetta **la conferma**: un aggiornamento `PlayQueue` con `Reason` `Queue` o `QueueNext` che contenga nuovi `PlaylistItemId` con gli `ItemId` mandati. L'attesa dura al massimo `addConfirmTimeout = 4 s`. Si ascolta il flusso `updates` della sessione **prima** della richiesta: la coda può arrivare prima della risposta HTTP.

  Il risultato è `PartyQueueAddOutcome`: `added` (anche solo una parte, per il tetto), `alreadyQueued`, `full`, `rejected` (tempo scaduto), `failed` (eccezione dell'API, o fuori dal gruppo). Due aggiunte alla volta vanno bene: ognuna aspetta la sua conferma. Gli id di un'aggiunta in attesa (`_pendingAdds`) non si rimandano.

  L'eco registrata prima della richiesta porta gli `ItemId` mandati (`PartyNotices.mine(kind, itemIds: …)`), e vale solo per l'aggiornamento che li contiene tutti (§10). Si rinnova quando la richiesta riesce (`PartyNotices.renew`), così dura quanto l'attesa della conferma, e si dimentica se la richiesta non riesce (`PartyNotices.forget`). `renew` e `forget` agiscono sull'eco con quegli id, non sull'ultima dello stesso tipo: con due aggiunte in corso ognuna tiene la sua. Scaduto il tempo della conferma l'eco non si dimentica: si rinnova per `PartyNotices.lateAddEchoWindow = 30 s`, così una conferma che arriva tardi non diventa, dopo "Non aggiunto…", l'aggiunta anonima di un altro.
- **`jumpTo(playlistItemId)`:** solo per un elemento che non è quello in corso. Manda `setPlaylistItem` e annuncia `SetCurrentItem`.
- **`remove(playlistItemId)`:** mai per l'elemento in corso. Manda `removeFromPlaylist`, senza annuncio.
- **`move(playlistItemId, k)`:** solo per un prossimo. Calcola il `NewIndex` (§8.2) e manda `movePlaylistItem`, senza annuncio.
- **`setShuffle(bool on)`:** manda solo se lo stato è diverso da `queue.shuffled`. È il modo per evitare `Sorted` su una coda ordinata (§3). Annuncia `ShuffleMode`. Se la richiesta non riesce, l'azione registrata per l'eco si dimentica (`PartyNotices.forget`): l'ordine casuale cambiato da un altro nei 4 s dopo dà il suo avviso.
- **Errori:**
  - un'eccezione dell'API (rete, 4xx, 5xx) dà l'avviso "Non riuscito, riprova" (§10), se si è ancora nel gruppo, e una riga di log con solo il tipo dell'errore;
  - un 429 del plugin sull'annuncio si ignora: l'avviso esce senza nome.

### 8.4 Precedente

- **Nel party:** `WatchPartySession.previousItem(party)` funziona come `nextItem`. Procede solo se l'elemento in corso è ancora quello passato e c'è un precedente, così il server non resta in attesa per un id sbagliato (§3). Il player annuncia `PreviousItem` solo se la chiamata è partita.
- **Da soli:** `PlayerViewState.previousEpisode`, calcolato come oggi `nextEpisode` ma con `LibraryApi.previousEpisode`. ⏮ apre l'episodio precedente nello stesso modo in cui ⏭ apre il successivo.

### 8.5 Dettagli dei titoli in coda

`partyQueueItemsProvider` tiene una mappa `ItemId → JellyfinItem`:
- quando nella coda compaiono id che non conosce, li chiede con `itemsByIds`, solo quelli nuovi e 50 alla volta (gli id stanno nell'indirizzo, e una coda costruita da un altro client può essere lunga);
- segue solo l'ingresso, l'uscita e la coda della sessione, non gli altri cambi;
- una richiesta non riuscita si riprova dopo 5 s, o prima se la coda cambia;
- un id che il server non restituisce (titolo cancellato o non più visibile) diventa una riga "Titolo non disponibile";
- la mappa si svuota all'uscita dal gruppo, e le risposte arrivate dopo non valgono.

## 9. App: interfaccia

### 9.1 Player

- **Fila destra in fondo:**
  - ⏮ (`LucideIcons.skipBack`) subito prima di ⏭;
  - il pulsante **Coda** (`LucideIcons.listVideo`) tra reazioni e tracce, **solo nel party**.
- **⏮ c'è** nel party se `hasPrevious`, da soli se c'è `previousEpisode`; altrimenti non compare, come ⏭.
- **Ai bordi della coda** (P sul primo, N sull'ultimo) non si chiede nulla al gruppo, e un salto in sospeso parte lo stesso.
- **Suggerimenti:**
  - nel party "Titolo precedente" e "Titolo successivo";
  - da soli "Episodio precedente" e "Episodio successivo" (quello di oggi).
- **Tasti:** `PlayerCommand.previous` per **P** e `mediaTrackPrevious`, che è anche tra i tasti multimediali. `MediaButton.previous` arriva dall'SMTC, che lo accende o lo spegne come ⏭.
- **Pannello:** `PlayerPopup.queue`. Il pulsante apre e chiude il pannello, e uno solo è aperto alla volta (come oggi).
  - Come quello delle tracce, prende tutta l'altezza a destra, sopra i controlli, e i controlli restano visibili.
  - Si chiude con ✕, con un clic sul film, con Esc (vedi §9.3), quando compare il post-play o quando il video va in errore (ma non mentre il campo di ricerca ha il focus, vedi §9.3), oppure quando il player esce dal party.
  - Resta aperto quando il gruppo passa a un altro titolo (clic su una riga, ⏮, ⏭, azioni degli altri): il player nuovo lo riapre subito (`partyQueuePanelCarryProvider`), sulla stessa vista, con la stessa serie o stagione e lo stesso testo di ricerca (`queuePanelNavProvider`, `queueAddSearchProvider`, globali). Lo stato si azzera aprendo il pannello dal pulsante e uscendo dal gruppo. Un'aggiunta in attesa continua: si perde solo l'indicatore sul pulsante.
- **`PlayerSidePanelHost`:** l'entrata da destra, il velo e il clic sul film che chiude, oggi in `TracksPanelHost`, vanno in un contenitore comune alle tracce e alla coda. Il comportamento delle tracce non cambia.
  - Con un pannello aperto (tracce o coda) la pillola dei tasti e degli avvisi sta al centro dello spazio libero alla sua sinistra, e si sposta con il pannello: il pannello è disegnato sopra di lei, e in una finestra stretta la coprirebbe in parte. La larghezza viene da `PlayerSidePanelHost.widthFor`, la stessa del pannello.
- **Post-play e schedina "prossimo" nel party.**
  - Il titolo offerto è `nextEntry` della coda, con i dettagli da `partyQueueItemsProvider`. Restano le regole di oggi: post-play solo con il segmento Outro, schedina negli ultimi 30 s, nel party niente conto alla rovescia, alla vera fine si va avanti da soli.
  - L'etichetta è "Prossimo episodio" se è l'episodio che segue nella stessa serie, altrimenti "Prossimo nella coda".
  - La schedina mostra il nome di un film (non solo l'anno), e per un episodio di un'altra serie anche il nome della serie.
  - I dettagli possono arrivare dopo: la schedina compare appena ci sono.
  - Da soli resta tutto come oggi.

### 9.2 Pannello "Coda"

La cartella è `lib/features/player/queue_panel/`. Largo 360 px, stile del pannello tracce: fondo `WfColors.surface` al 94 %, bordo sinistro, titoli in Bebas Neue. Le viste si sostituiscono una all'altra, con una sfumatura breve da `WfMotion`. Il fondo è uno solo per tutte le viste (`QueuePanelBackdrop`), quindi durante la sfumatura il film non traspare; ogni apertura di una vista è una vista nuova, anche tornando indietro e avanti in fretta. I dati delle viste ancora nella pila (La mia lista, stagioni ed episodi di una serie) restano in memoria finché ci sono: tornando indietro (Serie → ←, Stagione → ←) la vista si vede subito, senza una seconda richiesta.

**Vista Coda**
- **Intestazione:**
  - "Coda";
  - ⤮ (`LucideIcons.shuffle`), dorato con fondo leggero quando è attivo, con il suggerimento "Ordine casuale";
  - ✕.
- **Sotto l'intestazione:** "14 titoli · 3h 40m dopo questo". La somma conta solo i prossimi; i titoli senza durata non contano. Le durate sono nel formato dell'app (`formatRuntime`).
- **Sezioni:**
  - "Già visti": righe attenuate (opacità 0,5);
  - "In riproduzione": la riga ha fondo e bordo sinistro dorati, e "ora" al posto della durata;
  - "Prossimi".

  Le sezioni vuote non compaiono. All'apertura la lista è già scorsa sulla riga in corso.
- **Riga:** immagine 16:9 (64×36). Il titolo è il nome dell'episodio o del film. Sotto:
  - per un episodio "The Office · S2:E5 · 22m";
  - per un film "Film · 1979 · 1h 57m";
  - mentre i dettagli arrivano, "…".
- **Clic** su una riga che non è quella in corso: `jumpTo`.
- **Passando sopra** una riga dei prossimi:
  - a sinistra la maniglia (`LucideIcons.gripVertical`) per trascinarla;
  - a destra ✕ "Togli dalla coda", che compare anche sulle righe già viste.

  La riga in corso non ha né ✕ né maniglia. Finché non compaiono, maniglia e ✕ non prendono i clic.
- **Trascinamento:** solo tra i prossimi. Se durante il trascinamento arriva un aggiornamento, l'elemento trascinato si ritrova per id e l'indice si calcola alla fine sulla coda aggiornata. Se l'elemento non c'è più, non si manda nulla. Rilasciata la riga, il titolo resta dove lo si è lasciato finché arriva la coda nuova del server; se dopo 4 s non è arrivata, le righe tornano nell'ordine della coda.
- **In fondo,** fisso: "＋ Aggiungi titoli" (bordo dorato) apre la vista Aggiungi.
- **Con l'ordine casuale** non c'è la sezione "Già visti", perché il server mette l'elemento in corso in testa (§3).

**Vista Aggiungi**
- **Intestazione:** ← (torna alla Coda), "Aggiungi", ✕.
- **Campo "Cerca film e serie":** prende il focus all'apertura, chiesto dopo il fotogramma (lezione della Spec F).
  - A campo vuoto la sezione è **"La mia lista"**: i preferiti film e serie, per titolo (gli stessi dati della pagina La mia lista, `favoritesProvider`, che resta in memoria anche mentre si cerca).
  - **Da 2 lettere**, dopo 300 ms dall'ultima battuta, la sezione diventa "Risultati": film e serie che contengono il testo, al massimo 20, in ordine di titolo. Una ricerca nuova annulla la vecchia (`CancelToken`), e le risposte vecchie si scartano. Mentre una ricerca nuova è in corso restano i risultati di prima.
- **Riga di un film:**
  - locandina 2:3 (34×51), titolo, "Film · 1995 · 2h 50m";
  - a destra ↳ (`LucideIcons.listStart`, "Riproduci dopo") e ＋ (`LucideIcons.listPlus`, "Aggiungi in coda");
  - se è già in coda, ✓ "In coda" al posto dei pulsanti.
- **Riga di una serie:** "Serie" e › (`LucideIcons.chevronRight`). Il clic apre la vista Serie. Il numero di stagioni non c'è: Jellyfin manda `ChildCount` di una serie solo se lo si chiede nei campi, e ricerca e La mia lista non lo chiedono.
- **Stati:** se la lista è vuota, "La tua lista è vuota" o "Nessun risultato". Se c'è un errore, "Non riesco a caricare i titoli" con "Riprova".

**Vista Serie**
- **Intestazione:** ←, il nome della serie con "2 stagioni" sotto (le stagioni mostrate, quando sono arrivate), ✕.
- **Una riga per stagione** con episodi veri (le altre non compaiono): locandina della stagione, "Stagione 1" e "10 episodi". Se serve, la riga aggiunge "· 2 già in coda".
  - ↳ e ＋ aggiungono **tutta la stagione**, saltando gli episodi già in coda.
  - Se sono tutti in coda, al posto dei pulsanti c'è ✓ "In coda".
  - Il clic sulla riga, o ›, apre la vista Stagione. Un clic su un pulsante spento o in attesa non apre la stagione.
- Le stagioni vengono da `/Shows/{id}/Seasons`; gli episodi di tutta la serie da `allEpisodes`, una richiesta sola all'apertura della serie, che serve anche alla vista Stagione.
- **Stati:** se nessuna stagione ha episodi veri (solo mancanti), niente "0 stagioni" sotto il nome e, al posto della lista, "Nessun episodio disponibile". Con un errore, "Non riesco a caricare i titoli" con "Riprova".

**Vista Stagione**
- **Intestazione:** ←, "Stagione 1" con "Dark · 10 episodi" sotto (solo "Dark" finché gli episodi non sono arrivati), ✕.
- **Sotto l'intestazione:** "Tutta dopo" (pieno, dorato) e "Tutta in coda" (bordo dorato), un'aggiunta alla volta, con l'indicatore dell'attesa accanto al pulsante premuto; con la coda piena sono spenti, con il suggerimento "La coda è piena (100 titoli)".
- **Una riga per episodio:** immagine 16:9, "3. Passato e presente", durata, ↳ e ＋ oppure ✓ "In coda".

**Pulsanti di aggiunta**
- Mentre un'aggiunta aspetta la conferma, i suoi pulsanti mostrano un piccolo indicatore e non si ripremono.
- Con la conferma diventano ✓ "In coda".
- Con la coda piena tutti i pulsanti di aggiunta sono spenti, con il suggerimento "La coda è piena (100 titoli)".

### 9.3 Tasti e focus

- **Esc nel pannello:** se il campo di ricerca ha del testo, lo svuota. Altrimenti chiude il pannello, da qualunque vista. Tenendo premuto Esc conta una pressione sola. La freccia ← torna indietro di una vista.
- **Campo di ricerca con il focus:** i tasti vanno al campo e i comandi del player non scattano (spazio, frecce, P, N, 1–6, Invio per la chat), come con la chat (Spec E). I tasti multimediali funzionano lo stesso; Tab non porta fuori dal campo.
- **Il campo tiene il focus** finché la vista Aggiungi è aperta: Invio non lo lascia, un clic altrove (↳, ＋, righe, intestazione) nemmeno, e dopo Alt-Tab lo ritrova. Lo lascia quando la vista cambia o il pannello si chiude.
- **Post-play o errore mentre si scrive:** con il focus nel campo il pannello non si chiude da solo (§9.1): il focus tornerebbe al player e le lettere dopo diventerebbero comandi (la N di "dune" farebbe passare il gruppo al titolo dopo). Il pannello resta sopra il post-play o lo strato dell'errore finché lo si chiude con Esc o ✕. Senza focus nel campo si chiude come sempre.
- **Senza focus nel campo:** valgono i tasti del player (spazio, frecce, P, N…), come con il pannello tracce aperto.
- La rotella sul pannello fa scorrere la lista e non cambia il volume, come nel pannello tracce.
- Alla chiusura del pannello il focus torna subito al player, senza aspettare la fine dell'animazione.
- Il pannello non sta dentro `ExcludeFocus` nel player: è `QueuePanelFrame` a escludere dal focus tutto tranne il campo.
- Ogni vista Aggiungi ha il nodo di focus del suo campo. Andando e tornando durante la sfumatura ci sono due viste Aggiungi, e con un nodo comune la connessione della tastiera resterebbe al campo che esce, che uscendo la chiude: il campo nuovo sembrerebbe a fuoco ma non scriverebbe. Il player sa che il campo ha il focus da un nodo intorno al pannello, che non lo prende ma ce l'ha quando ce l'ha il campo.

## 10. Avvisi

**Da dove nascono**
- Gli avvisi della coda nascono dagli aggiornamenti `PlayQueue`, come oggi quelli di "successivo" e "si guarda".
- `PartyNotices` ricorda gli id della coda precedente: con `Reason` `Queue` o `QueueNext` i titoli aggiunti sono i `PlaylistItemId` nuovi. Per il testo chiede i dettagli dei titoli aggiunti, con una richiesta sola; oltre 50 titoli (`additionDetails`) non li chiede e dice solo "N titoli". Senza dettagli (errore, o uscita dal gruppo nel frattempo) nessun avviso.
- Il nome si aggancia come oggi (Spec E §8): dall'annuncio già arrivato (che vale 2 s), oppure aspettandolo al massimo 300 ms.

**Testi**

| Evento (`Reason`) | Azione del plugin | Avviso agli altri | Con il nome | Chi ha agito |
|---|---|---|---|---|
| `PreviousItem` | `PreviousItem` | "Precedente: {title}" | "{name} ha avviato il precedente: {title}" | come ⏭ oggi: lo stesso avviso, senza nome |
| `SetCurrentItem` | `SetCurrentItem` | "Si guarda: {title}" (c'è già); per un episodio {title} è l'episodio ("S1:E5 · Titolo"), come per successivo e precedente | "{name} ha scelto: {title}" (c'è già) | come sopra |
| `Queue` | `Queue` | "Aggiunto alla coda: {what}" | "{name} ha aggiunto alla coda: {what}" | "Hai aggiunto alla coda: {what}" |
| `QueueNext` | `QueueNext` | "Subito dopo: {what}" | "{name} ha messo subito dopo: {what}" | "Hai messo subito dopo: {what}" |
| `ShuffleMode` (acceso) | `ShuffleMode` | "Ordine casuale attivato" | "{name} ha attivato l'ordine casuale" | nessun avviso (si vede ⤮) |
| `ShuffleMode` (spento) | `ShuffleMode` | "Ordine casuale tolto" | "{name} ha tolto l'ordine casuale" | nessun avviso |
| `RemoveItems`, `MoveItem` | — | nessun avviso | — | — |

Nella tabella, `{what}` vale:
- il titolo, se l'aggiunta è di un solo titolo;
- "{count} episodi di {series}", se sono tutti episodi della stessa serie;
- altrimenti "{count} titoli".

**Le proprie azioni**
- Per le proprie aggiunte e per l'ordine casuale, `PartyQueueEditor` registra l'azione prima di mandarla. L'aggiornamento che ne nasce non produce l'avviso "degli altri": per l'aggiunta compare "Hai…" alla conferma, per l'ordine casuale nulla.
- Per un'aggiunta la registrazione porta gli `ItemId` mandati: l'eco è solo l'aggiornamento che li contiene tutti. Un'aggiunta di un altro negli stessi secondi ha il suo avviso, e la propria non viene poi annunciata come di un altro.
- L'attesa di questa registrazione è lunga quanto la conferma (4 s), non i 3 s dell'eco delle pause. Scaduta la conferma ("Non aggiunto…") l'eco resta altri 30 s (`lateAddEchoWindow`): una conferma tardiva non produce un "Aggiunto…" anonimo. Passati i 30 s, un aggiornamento uguale si annuncia come quello di un altro.

**Avvisi di errore**, solo per chi ha agito:
- "Non aggiunto: qualcuno nel party non può vedere questo titolo", quando scade il tempo della conferma;
- "Aggiunti {added} episodi su {wanted}: la coda è piena" ("Aggiunto 1 episodio su …"), e "Aggiunti {added} titoli su {wanted}: la coda è piena" ("Aggiunto 1 titolo su …") se non sono tutti episodi della stessa serie;
- "La coda è piena (100 titoli)", se non c'era posto per nulla;
- "Non riuscito, riprova", per un errore dell'API.

Un'aggiunta in cui tutti i titoli erano già in coda non produce avvisi: i pulsanti mostrano già ✓.

**Icone della pillola**
- `listPlus` per aggiunto;
- `listStart` per subito dopo;
- `shuffle` per l'ordine casuale;
- `skipBack` per il precedente;
- `circleAlert` per gli errori.

**Testi in ARB:** `app_it.arb` è il modello, poi `app_en.arb`.

## 11. Casi limite

- **Fine coda:** il gruppo resta sull'ultimo titolo (Spec B §5.4). Se qualcuno aggiunge, `hasNext` torna vero e ⏭ si accende. Nel post-play già aperto compare il prossimo titolo appena arriva.
- **Aggiunta mentre il gruppo aspetta (`Waiting`):** funziona, perché il server non cambia stato per `Queue`.
- **Due membri che fanno cose insieme:** ogni comando parte dallo stato attuale. Se un id non c'è più, il comando non fa nulla. Un salto a un id appena tolto da un altro rientra nel bug del server (§3): la finestra è piccolissima e si accetta.
- **Ordine casuale e trascinamento:** si trascina nella lista mescolata, quella che si vede. Spegnendo l'ordine casuale gli spostamenti si perdono (§3); lo si accetta.
- **Titolo cancellato dal server mentre è in coda:** la riga diventa "Titolo non disponibile" e si può togliere. Il bug di Jellyfin sull'elenco dei gruppi con un elemento cancellato resta come oggi: il plugin lo contiene già.
- **Un membro senza accesso a un titolo già in coda:** non succede, perché il server controlla tutti i membri a ogni aggiunta e all'ingresso nel gruppo.
- **Plugin assente o vecchio:** la coda funziona lo stesso, e gli avvisi escono senza nome.
- **App vecchie (0.7.x) nello stesso party:**
  - vedono i cambi della coda, perché il player si sostituisce quando cambia l'elemento in corso;
  - non vedono gli avvisi nuovi e non hanno il pannello;
  - l'avviso di un salto lo vedono come "Si guarda: X".

## 12. Test

- **Regole:** sezioni (anche con l'ordine casuale e con la coda vuota), posto libero, doppioni, taglio al tetto, indice dello spostamento.
- **`SyncPlayApi`:** corpo e percorso di ogni metodo nuovo. **`PlayQueue.shuffled`.**
- **`PartyQueueEditor`** con `fake_async` e `FakeSyncPlayApi`:
  - conferma dell'aggiunta, tempo scaduto, aggiunte contemporanee;
  - coda piena, tutti già in coda;
  - niente rimozione dell'elemento in corso;
  - niente `Sorted` su coda ordinata;
  - annunci solo con `queue`;
  - id spariti, errori dell'API.
- **`previousItem`:** controllo dell'elemento in corso; primo elemento.
- **`LibraryApi.previousEpisode`:** cambio di stagione, primo episodio.
- **`PartyNotices`:**
  - ogni riga della tabella di §10, con e senza nome;
  - `{what}` nei tre casi;
  - le proprie azioni non producono l'avviso degli altri;
  - l'aggiunta di un altro durante l'attesa della propria ha il suo avviso; due aggiunte proprie in corso tengono ognuna la sua eco; la conferma tardiva non fa avvisi.
- **Widget:**
  - le quattro viste: sezioni, righe, pulsanti, ✓, coda piena, stati vuoti ed errore, ← ed Esc, trascinamento, clic per saltare;
  - il player: ⏮ acceso e spento, P, pulsante Coda solo nel party, focus del campo (anche con post-play ed errore, e tra due viste Aggiungi nella sfumatura), post-play dalla coda con un film come prossimo, pillola accanto al pannello.
- **Plugin:** `EventValidator` e `Info.Features`.

## 13. Divisione in piani

1. **Piano 14a — la coda:**
   - plugin 1.3.0, installato a mano sul server per le prove;
   - API e modelli;
   - regole ed editor (salto, rimozione, spostamento, ordine casuale);
   - ⏮ nel party e da soli, con tasti e SMTC;
   - post-play dalla coda;
   - `PlayerSidePanelHost` e vista Coda;
   - avvisi di precedente, salto e ordine casuale.
2. **Piano 14b — aggiungere:**
   - viste Aggiungi, Serie e Stagione, con ricerca e La mia lista;
   - `add` con conferma, tetto e doppioni;
   - avvisi delle aggiunte e degli errori;
   - allineamento di questa spec.

   Poi la release: plugin 1.3.0 dal Catalogo, quindi app **0.8.0 non obbligatoria**.
