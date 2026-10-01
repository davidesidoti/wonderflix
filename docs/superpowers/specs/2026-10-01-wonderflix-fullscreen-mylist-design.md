# WonderFlix — Piano 7: schermo intero vero e filtri in "La mia lista"

- **Data:** 2026-10-01
- **Stato:** realizzato nel piano 7 (`docs/superpowers/plans/2026-10-01-wonderflix-07-fullscreen-mylist.md`), provato dall'utente il 2026-10-01
- **Ambito:** correzione dell'issue #2 (bug) e realizzazione dell'issue #1 (enhancement), poi release 0.3.1. Si appoggia allo Spec A (`2026-09-29-wonderflix-client-core-design.md`: player, catalogo, La mia lista) e allo Spec C (`2026-09-30-wonderflix-rinnovo-grafico-design.md`: scheletri, entrate delle griglie).

## 1. Obiettivo

- **#2 — "Fullscreen Mode non è davvero schermo intero":** a finestra massimizzata, lo schermo intero del player lascia la barra del titolo (Chiudi, Minimizza, Allarga) e dei bordi grigi. Deve coprire tutto lo schermo, senza bordi né barre, qualunque sia lo stato della finestra.
- **#1 — "Filtri e Ordinamento in pagina My List":** la pagina "La mia lista" deve avere ordinamento e filtri come le pagine Film e Serie.
- **Release 0.3.1**, non obbligatoria.

## 2. Situazione di partenza

### 2.1 Schermo intero

- Il player chiama `PlayerWindow.setFullScreen` (`lib/features/player/player_window.dart`), che passa a `windowManager.setFullScreen` (`window_manager` 0.5.2, ultima versione pubblicata).
- Nel codice nativo del plugin (`windows/window_manager.cpp`, `SetFullScreen`):
  - finestra **non** massimizzata → `SetAsFrameless()`: la finestra perde la cornice, lo schermo intero è vero;
  - finestra **massimizzata** → niente `SetAsFrameless()`: vengono tolti solo `WS_THICKFRAME` e `WS_MAXIMIZEBOX`, **`WS_CAPTION` resta**. La finestra viene allargata a tutto il monitor (la taskbar sparisce), ma la barra del titolo e il bordo restano.
- Causa confermata dall'utente: a finestra non massimizzata lo schermo intero funziona.
- `media_kit_video` (già dipendenza) ha un proprio schermo intero nativo (`defaultEnterNativeFullscreen` / `defaultExitNativeFullscreen`, canale `com.alexmercerind/media_kit_video`, `Utils.EnterNativeFullscreen` / `Utils.ExitNativeFullscreen`). È il codice da cui `window_manager` dice di aver preso il suo, ma toglie **tutto** `WS_OVERLAPPEDWINDOW` (barra del titolo compresa) e quindi funziona anche a finestra massimizzata. All'uscita rimette lo stile; se la finestra era massimizzata resta massimizzata, altrimenti torna alla posizione normale.
- `isFullScreen()` è usato da `lib/features/watch_party/watch_party_routing.dart` (il player riaperto per il gruppo resta a schermo intero). `windowManager.isFullScreen()` è usato da `_BoundsSaver` in `lib/app/window_setup.dart` per non salvare le dimensioni dello schermo intero.

### 2.2 La mia lista

- `lib/features/mylist/my_list_screen.dart`: `favoritesProvider` carica con una sola richiesta tutti i preferiti (film e serie, `limit: 500`, ordinati per data di aggiunta). La griglia non ha filtri; il titolo "LA MIA LISTA" scorre con la griglia.
- Film e Serie (`lib/features/catalog/`): titolo con conteggio "N titoli", barra `CatalogFiltersBar` (Ordina per Titolo/Data di aggiunta/Anno/Voto, Genere, Anno, Tutti/Non visti/Visti, Azzera filtri), griglia paginata dal server. Generi e anni arrivano da `GET /Items/Filters`.
- `GET /Items/Filters` (e `/Items/Filters2`) **non** accetta `isFavorite` (verificato su OpenAPI 10.11.9): non può dare i generi e gli anni dei soli preferiti.
- Jellyfin **non** registra quando un titolo viene messo nei preferiti: "Data di aggiunta" è la data di aggiunta alla libreria, come in Film e Serie.

## 3. Decisioni

| Tema | Decisione |
|---|---|
| Schermo intero | Nativo di `media_kit_video` al posto di `windowManager.setFullScreen`. Scartato "togli massimizzazione → schermo intero → rimassimizza": si vede la finestra cambiare dimensione. |
| Stato schermo intero | Tenuto da noi in un modulo condiviso, letto dal player e dal salvataggio della posizione. |
| Controlli di La mia lista | **Come il catalogo, senza filtro per tipo**: Ordina per, Genere, Anno, Tutti/Non visti/Visti, Azzera filtri, conteggio "N titoli". |
| Dove si filtra | **Nell'app**, sulla lista già caricata: filtri istantanei, niente scheletro a ogni cambio, generi e anni presi dai titoli della lista, "visto" cambiato in sessione considerato subito. |
| Stato dei filtri | Vive finché la pagina resta montata (si conserva aprendo una scheda e tornando indietro), si azzera lasciando la pagina. Nessun salvataggio. |
| Release | 0.3.1 non obbligatoria (nessun marcatore `min-version`). |

## 4. Schermo intero vero (#2)

### 4.1 `NativeFullScreen` (`lib/core/system/native_fullscreen.dart`)

Modulo piccolo con lo stato e i due comandi:

- `bool get active`: `true` tra un ingresso e la relativa uscita;
- `Future<void> enter()`: se non è già attivo, segna `active = true` e chiama `defaultEnterNativeFullscreen()`;
- `Future<void> exit()`: se è attivo, segna `active = false` e chiama `defaultExitNativeFullscreen()`.

Lo stato cambia **prima** della chiamata nativa: anche due richieste ravvicinate arrivano una volta sola.

Chiamate ripetute (entra due volte, esci senza essere entrato) non arrivano al codice nativo. Lo stato è unico per l'app (una sola finestra): un'istanza condivisa, raggiungibile sia da `window_setup.dart` (che gira prima di `ProviderScope`) sia dal player.

### 4.2 `WindowManagerPlayerWindow`

- `setFullScreen(true/false)` → `NativeFullScreen.enter()` / `exit()`.
- `isFullScreen()` → `NativeFullScreen.active`.
- Chiusura, blocco della chiusura e `destroy` restano su `window_manager`.
- L'interfaccia `PlayerWindow` e `FakePlayerWindow` non cambiano: i chiamanti (`player_screen.dart`, `watch_party_routing.dart`) restano identici.

### 4.3 Salvataggio della posizione

`_BoundsSaver._save` in `lib/app/window_setup.dart` salta il salvataggio anche quando `NativeFullScreen.active` è vero (oggi controlla `windowManager.isFullScreen()`, che con il nuovo schermo intero resterebbe sempre falso). La decisione passa in una funzione pura `shouldSaveBounds({minimized, maximized, fullScreen})`, testabile; `_save` le passa lo stato letto da `windowManager` e da `NativeFullScreen`.

### 4.4 Compatibilità con `window_manager`

Il gestore dei messaggi di `window_manager` interviene su `WM_NCCALCSIZE` solo se il suo schermo intero è attivo, se la finestra è senza cornice o se la barra è nascosta: nessuno dei tre casi si verifica (l'app non usa più il suo schermo intero e ha la barra normale). La finestra senza `WS_OVERLAPPEDWINDOW` non ha quindi area non client: il contenuto Flutter copre tutto il monitor.

## 5. Filtri e ordinamento in La mia lista (#1)

### 5.1 Dati

- `JellyfinItem` legge due campi nuovi: `sortName` (`SortName`, `String?`) e `dateCreated` (`DateCreated`, `DateTime?`).
- `ItemQuery` ha un'opzione nuova `includeSortFields` (predefinita `false`): se vera, `fields` diventa `PrimaryImageAspectRatio,Genres,SortName,DateCreated`. Solo `favoritesProvider` la usa; le altre richieste non cambiano.
- `favoritesProvider` resta una sola richiesta senza filtri (preferiti, film e serie, `limit: 500`).

### 5.2 Filtri e ordine (`lib/features/mylist/my_list_view.dart`)

Funzione pura che riceve i preferiti, i filtri scelti (un `ItemQuery`: `sort`, `genres`, `year`, `watched`) e i dati utente aggiornati in sessione (`userDataOverridesProvider`) e restituisce i titoli da mostrare:

1. **Solo i preferiti ancora col cuore**, come oggi (un titolo tolto dalla lista sparisce subito).
2. **Filtri:**
   - Genere: il titolo ha quel genere;
   - Anno: `productionYear` uguale;
   - Non visti / Visti: `played` dei dati utente aggiornati (per una serie, Jellyfin la segna vista quando lo sono tutti gli episodi).
3. **Ordine**, come Jellyfin nel catalogo. Chiave del titolo = `sortName`, o `name` se manca, confrontata senza maiuscole:
   - Titolo: chiave del titolo, crescente;
   - Data di aggiunta: `dateCreated` dalla più recente; a parità chiave del titolo;
   - Anno: `productionYear` dal più alto; a parità chiave del titolo;
   - Voto: `communityRating` dal più alto; a parità chiave del titolo.
   I titoli senza data, anno o voto vanno in fondo, ordinati per chiave del titolo.

La stessa funzione ricava anche le **opzioni** dalla lista dei preferiti ancora col cuore:

- generi: tutti i generi presenti, senza doppioni, in ordine alfabetico senza maiuscole;
- anni: tutti gli anni presenti, dal più recente.

Se il genere o l'anno scelto non è più presente (es. l'unico titolo con quel genere è stato tolto dal cuore), viene comunque aggiunto alle opzioni, così il menu mostra la scelta attiva e la pagina mostra "Nessun titolo con questi filtri".

### 5.3 Barra dei filtri condivisa

- `CatalogFiltersBar` riceve generi e anni come parametro (`LibraryFilters filters`) invece di leggerli da `catalogFiltersProvider`. Il parametro `kind` sparisce. `CatalogScreen` passa i filtri del server, La mia lista quelli ricavati (§5.2).
- Nuovo `ItemQuery.clearFilters()`: toglie genere, anno e visti, conserva tutto il resto (tipi, ordinamento, `favoritesOnly`, `includeSortFields`, ricerca, persona). La barra e lo stato vuoto del catalogo lo usano al posto di `ItemQuery(kinds: …, sort: …)`.
- La barra esporta `filtersBarHeight` (altezza di una riga di menu): La mia lista lo usa per lasciare libero lo spazio della barra durante il caricamento.
- Aspetto e testi della barra non cambiano.

### 5.4 Pagina

- Disposizione come `CatalogScreen`: in alto, fisso, il titolo "LA MIA LISTA" con il conteggio "N titoli" (titoli **dopo** i filtri, `catalogCount`), sotto la barra dei filtri, poi la griglia che scorre. Il titolo sta **fuori** dalla dissolvenza tra gli stati (caricamento, errore, lista vuota, contenuto): sfuma solo quello che sta sotto.
- Lo stato dei filtri sta nello `State` della pagina (`ItemQuery` iniziale: film e serie, `sort: dateAdded`, cioè l'ordine di oggi). Cambiare un filtro ricalcola subito la griglia, senza scheletro e senza richieste.
- Griglia, card, `heroSource: 'mylist.$i'`, anteprima delle card e `BatchedEntrance` restano come oggi.
- Ogni cambio di filtro o di ordinamento dà alla griglia una chiave nuova (contatore dei cambi): `WfSwitcher` dissolve solo il contenuto sotto la barra e le card rientrano, come nel catalogo dopo un cambio di filtro. Togliere un cuore **non** cambia la chiave: il titolo sparisce e basta, come oggi.
- **Stati:**
  - caricamento: titolo senza conteggio, scheletro della griglia (`PosterGridSkeleton`) sotto lo spazio della barra;
  - errore: `ErrorView` con "Riprova", come oggi;
  - lista vuota (nessun preferito): titolo e testo `myListEmpty` di oggi, **senza barra** né conteggio;
  - nessun risultato con i filtri: `catalogEmpty` ("Nessun titolo con questi filtri.") con il pulsante `catalogClearFilters`.
- Nessuna stringa nuova: si riusano quelle del catalogo.

## 6. Test

### 6.1 Automatici

- `NativeFullScreen`: canale `com.alexmercerind/media_kit_video` simulato. Entrare chiama `Utils.EnterNativeFullscreen` una volta e segna attivo; un secondo ingresso non chiama di nuovo; uscire chiama `Utils.ExitNativeFullscreen` e segna non attivo; uscire senza essere entrati non chiama nulla.
- `WindowManagerPlayerWindow`: `setFullScreen`/`isFullScreen` passano per `NativeFullScreen`.
- `shouldSaveBounds`: falso se minimizzata, massimizzata o a schermo intero; vero altrimenti.
- `JellyfinItem.fromJson` legge `SortName` e `DateCreated`; `ItemQuery` con `includeSortFields` chiede i due campi in più, senza li lascia fuori; `clearFilters()` conserva i campi non di filtro.
- Funzioni di La mia lista: ogni ordinamento, parità, valori mancanti in fondo, `sortName` mancante, ogni filtro, combinazioni, "visto" e cuore cambiati in sessione, opzioni con doppioni e scelta attiva non più presente.
- Pagina: barra e conteggio visibili, filtro per genere riduce la griglia e il conteggio, ordinamento cambia l'ordine delle card, filtro senza risultati mostra testo e "Azzera filtri" che riporta tutti i titoli, lista vuota senza barra, i test esistenti restano verdi.
- Catalogo: i test esistenti restano verdi con la barra che riceve i filtri come parametro.

### 6.2 Manuali (utente, server vero)

- Schermo intero con finestra **massimizzata** e **non massimizzata**, con `F`, doppio click e pulsante: niente barra del titolo né bordi, taskbar nascosta. All'uscita la finestra torna com'era (massimizzata, o stessa posizione e dimensione).
- Uscita dallo schermo intero chiudendo il player (freccia indietro) e passando all'episodio successivo.
- Watch party: dal player da solo a schermo intero → "Guarda insieme": il player riaperto resta a schermo intero.
- Posizione della finestra ricordata dopo un riavvio, anche dopo aver usato lo schermo intero.
- La mia lista: ogni ordinamento, genere, anno, visti/non visti, azzera; togliere un cuore e segnare un titolo visto dall'anteprima aggiornano subito la griglia filtrata.

## 7. Release 0.3.1

- Procedura di `docs/RELEASING.md`: versione 0.3.1 in `pubspec.yaml`, commit `chore: release 0.3.1`, tag `v0.3.1`, workflow, note in italiano scritte nella bozza della release. Non obbligatoria: nessun marcatore `min-version`.
- Dopo la pubblicazione (fatta dall'utente), chiusura delle issue #1 e #2 con un commento che rimanda alla 0.3.1, solo con l'ok dell'utente.

## 8. Fuori ambito

- Filtro per tipo (Film/Serie) in La mia lista.
- Ordinamento per "aggiunti di recente alla lista" (Jellyfin non registra la data).
- Salvataggio dei filtri tra una sessione e l'altra, in La mia lista come nel catalogo.
- Più di 500 preferiti (limite attuale invariato).
- Modifiche a `window_manager` o un suo fork.
