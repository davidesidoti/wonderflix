# WonderFlix — "Serve te" spiegato e risolvibile dall'app

- **Data:** 2026-10-31
- **Stato:** design approvato in chat, da pianificare. Branch `feat/serve-te`.
- **Mockup approvato:** `.superpowers/brainstorm/1765-1793482907/content/needs-you-rows.html` (non nel repo).
- **Ambito:** estende la Spec T (download automatici, `2026-10-28-wonderflix-download-automatici-design.md`), §5.5 e §8.1. Plugin + app.

## 1. Perché

Nella scheda Download, la sezione "Serve te" ("Needs you") dice *che* serve l'admin ma non *cosa* può fare. Le righe mostrano solo il motivo ("only low-score files", "no valid file", "Radarr/Sonarr will not import it") e il pulsante "Watch", che apre la ricerca manuale anche quando non serve a niente: per esempio un file già scaricato e bloccato nell'import. L'admin non sa cosa fare e finisce per aprire Sonarr/Radarr.

Obiettivo: **ogni riga "Serve te" spiega cosa è successo, con i numeri, e offre i pulsanti giusti per quel caso**, così che l'admin risolva tutto dall'app.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Una frase di spiegazione per ogni caso, con i dati che servono per decidere.
- Pulsanti specifici per ogni caso (§4), con l'azione consigliata in evidenza.
- Un titolo "tappabuchi" scaricato con punteggio basso continua a cercare un file migliore e lo sostituisce da solo.

**Non obiettivi**
- Scaricare il tappabuchi *in automatico*. L'admin ha scelto un pulsante: decide caso per caso.
- Associare a mano file ed episodi (la schermata di import interattivo di Sonarr).
- Cambiare la regola di scelta (§4 della Spec T) o le soglie.
- Annullare "Va bene, aspetto" con un pulsante dedicato (vedi §4.3).

**Anti-obiettivi** (cose che renderebbero il lavoro un fallimento anche se funziona)
- Un pulsante che scarica un file che Radarr/Sonarr poi non importano: il titolo tornerebbe subito in "Serve te", in un altro caso.
- Testi tecnici o in codice dove serve una spiegazione. L'unica eccezione è il messaggio di Sonarr/Radarr, che si mostra così com'è.

## 3. Situazione di partenza (letta nel codice il 2026-10-31)

- Plugin: `DownloadEntry.State = NeedsYou` con `Reason` tra `NothingFound`, `BelowMinScore`, `ImportBlocked`, `GrabRefused`. `SearchFailed` è solo un motivo, non porta in "Serve te". Lo decidono `NothingChosen` (`DownloadService.Search.cs`), `OnImportBlocked` (`DownloadService.cs`), `GrabChoiceAsync` e `ImportByHandAsync`.
- Le voci in `NeedsYou` diventano avvisi e notifiche push (`NeedsYouAlerts`, `DownloadNeedsYou`).
- Endpoint di oggi: `GET Downloads`, `GET Downloads/Search`, `POST Downloads/Grab`, `POST Downloads/Accept`, `POST Downloads/SearchNow`.
- L'import a mano esiste già: `DownloadService.ImportDownloadAsync(kind, downloadId)`, usato dalla scheda Spazio ("Importa" su un download bloccato).
- App: `DownloadItemRow` (`download_rows.dart`) mostra "Watch" e, solo fuori da "Serve te", "Cerca ora".
- Dopo un download di WonderFlix sotto l'obiettivo, il titolo passa in `UpgradeWatch` per 30 giorni (`UpgradeWindow`), poi esce e finisce in "Da ripassare".

## 4. I casi e i pulsanti

Il testo di ogni riga lo compone l'app dai dati (come nella Spec T, il plugin non manda testi), tranne il messaggio di Sonarr/Radarr. Lo stato in rosso resta quello di oggi. Sotto lo stato c'è una frase di spiegazione, poi i pulsanti. Quello in evidenza (dorato) è il consigliato. Nelle righe "Serve te" "Watch" diventa **"Scegli tu"**: apre la stessa ricerca manuale di oggi.

### 4.1 Solo file con punteggio basso (`BelowMinScore`)

- **Spiegazione:** "6 file trovati, il migliore ha punteggio 40 (minimo 100). Puoi scaricarlo intanto: appena arriva un file migliore lo sostituisco." Il minimo è quello di WonderFlix per il profilo (`MinScore` delle soglie), non quello di Sonarr.
- **Pulsanti:** **Scarica il migliore intanto** (consigliato), Scegli tu, Cerca ora.
- "Scarica il migliore intanto" scarica il primo dei candidati con la regola di sempre (§4 della Spec T, punto 4), ignorando solo il punteggio minimo di WonderFlix. Il titolo diventa un **tappabuchi** (§5.1).

### 4.2 Nessun file valido (`NothingFound`)

Due varianti, secondo cosa ha dato l'ultima ricerca.

**a) Qualcosa trovato, tutto scartato**
- **Spiegazione:** "14 file trovati, tutti scartati: 9 troppo piccoli, 5 rifiutati da Radarr (lingua)." Per i rifiuti di Radarr/Sonarr si mostra il motivo più frequente tra parentesi, il testo del primo rifiuto così come arriva da Radarr/Sonarr (vedi §8).
- **Pulsanti:** **Scarica il migliore intanto** (consigliato, solo se c'è almeno uno scarto "troppo piccolo"), Scegli tu, Cerca ora, Va bene, aspetto.
- Qui "Scarica il migliore intanto" sceglie **solo tra gli scarti per peso** (`TooSmall`), mai tra quelli rifiutati da Radarr/Sonarr: Radarr/Sonarr non li importerebbero (anti-obiettivo). L'ordine è punteggio, poi risoluzione, poi **peso dal più pesante** (il più vicino alla soglia). Il titolo diventa un tappabuchi (§5.1).

**b) Nessun risultato**
- **Spiegazione:** "Nessun risultato sugli indexer. Spesso succede perché non è ancora uscito in digitale: continuo a cercare."
- **Pulsanti:** Cerca ora, **Va bene, aspetto** (consigliato).

### 4.3 "Va bene, aspetto"

- Toglie il titolo da "Serve te" e lo rimette in "In attesa", con l'etichetta **"senza avvisi"**. L'avviso e la notifica push spariscono, perché la voce non è più `NeedsYou`.
- Il plugin continua a cercare, una volta alla settimana.
- Il silenzio vale solo per "nessun file valido". Se una ricerca successiva trova candidati sotto il minimo (`BelowMinScore`), la novità merita un avviso: il titolo torna in "Serve te" e il silenzio si toglie.
- Si toglie anche quando il titolo scarica, o quando esce dal ciclo. Non c'è un pulsante "riattiva avvisi". La riga "In attesa" ha comunque "Watch" e "Cerca ora".

### 4.4 Radarr/Sonarr non importano (`ImportBlocked`)

- **Spiegazione:** "Il file è scaricato ma Sonarr non lo importa. Motivo di Sonarr:" seguito dal messaggio della coda (`statusMessages`), così com'è, in monospazio. Senza messaggio, solo la prima frase.
- **Pulsanti:** **Importa comunque** (consigliato), Scarta e cerca un altro. Niente "Scegli tu" né "Cerca ora": il file c'è già.
- **Importa comunque:** lo stesso import a mano della scheda Spazio (`ImportDownloadAsync`). Se parte, la riga va in "In download" finché Radarr/Sonarr non importano, poi segue il percorso normale (`OnImported`). Se non parte (`NoFiles` o un errore), la riga resta in "Serve te" e l'app mostra l'errore in uno SnackBar.
- **Scarta e cerca un altro:** toglie il download dalla coda e da qBittorrent **con la blocklist** (`RemoveFromQueueAsync(blocklist: true, removeFromClient: true)`), poi chiede una ricerca subito, come "Cerca ora". La voce torna "In attesa", oppure in `UpgradeWatch` se era un upgrade: per un upgrade il file vecchio c'è ancora.

### 4.5 Il client ha rifiutato il file (`GrabRefused`)

- **Spiegazione:** "qBittorrent ha rifiutato il file scelto (di solito perché c'è già). Al prossimo giro provo il successivo della lista, oppure scegline uno tu."
- **Pulsanti:** **Scegli un altro file** (consigliato, apre la ricerca manuale), Cerca ora.
- Nuovo comportamento del giro: una release rifiutata dal client si ricorda per quella voce, e la scelta automatica la salta e passa alla successiva (§5.3).

### 4.6 "Cerca ora" in "Serve te"

Oggi è nascosto proprio lì. Compare in tutti i casi tranne `ImportBlocked`.

## 5. Plugin

### 5.1 Tappabuchi

- Una voce scaricata con "Scarica il migliore intanto" è segnata come tappabuchi, con il perché: **punteggio** (§4.1) o **peso** (§4.2a).
- Dopo l'import va in `UpgradeWatch` **senza il limite dei 30 giorni**, anche se il punteggio è già pari o sopra l'obiettivo (un tappabuchi per peso può esserlo). Resta tappabuchi finché non ha un file che rispetta **tutte** le regole: peso minimo e punteggio minimo. Da quel momento vale la regola normale: 30 giorni dalla scelta che l'ha portato in regola, poi "Da ripassare" se è ancora sotto l'obiettivo, oppure esce dal libro se è all'obiettivo.
- Ritmo: quello di §5.2 della Spec T. Dopo il trentesimo giorno resta settimanale.
- **Cosa lo sostituisce:**
  - tappabuchi per punteggio: una release con **punteggio più alto** del file presente, anche se ancora sotto il minimo (per esempio da 40 a 70 con minimo 100: l'admin ha chiesto "appena arriva un file migliore prende quello migliore"). Deve rispettare il peso minimo e gli altri rifiuti di Radarr/Sonarr; si ignora solo il punteggio minimo di WonderFlix. Se il nuovo file è ancora sotto il minimo, resta tappabuchi.
  - tappabuchi per punteggio: Radarr/Sonarr devono importarla (`WouldImport`, §5.3b della Spec T).
  - tappabuchi per peso: una release che rispetta tutte le regole, con punteggio **pari o più alto** del file presente. **Si scarica anche se Radarr/Sonarr non la importerebbero** (stessa qualità e stesso punteggio: per loro non è un upgrade). In quel caso il plugin forza l'import a mano con sostituzione, come per le scelte dell'admin (`ManualImportPending`, decisione 9 della Spec T: una volta sola, se resta bloccata va in "Serve te" con `ImportBlocked`). Deciso dall'admin il 2026-10-31.

### 5.2 Riassunto dell'ultima ricerca

Dopo ogni ricerca che non sceglie niente (`NothingChosen`) la voce conserva quanto serve alle spiegazioni di §4.1 e §4.2:

- quanti risultati;
- il punteggio del miglior candidato sotto il minimo e il minimo usato;
- quanti scartati per peso e quanti rifiutati da Radarr/Sonarr;
- il testo del rifiuto più frequente;
- se esiste uno scarto per peso utilizzabile come tappabuchi.

Il riassunto si toglie quando la voce scarica.

### 5.3 Release rifiutate dal client

Su `GrabRefused` la voce conserva guid e indexer della release (al massimo le ultime 20). La scelta automatica e `GrabBest` le escludono prima della regola. **(Mia scelta per `GrabBest`:** altrimenti riproverebbe sempre la stessa release rifiutata.) Si dimenticano quando la voce esce dal libro. Il grab a mano dell'admin dalla ricerca ("Scegli tu") non le esclude: se l'admin la sceglie di nuovo, è una sua decisione.

Visto che la release rifiutata non si riprova più, il ritmo lento di §5.5 della Spec T non serve: dopo un `GrabRefused` la prossima ricerca è al giro successivo (`CycleInterval`), come promette il testo di §4.5. **(Mia scelta.)**

### 5.4 Import bloccato

- Mentre traccia la coda, la voce conserva il `downloadId` e i `statusMessages` dell'elemento bloccato. `ArrQueueItem` legge già `statusMessages` (`ArrStatusMessage`), e `SpaceService.Lighten.cs` li unisce già senza duplicati: si riusa quel modo.
- Import e scarto lavorano sulla voce in `ImportBlocked`. Su una voce in un altro stato rispondono `409 Conflict`.

### 5.5 Endpoint nuovi (solo admin, come gli altri)

| Endpoint | Cosa fa | Risposte |
|---|---|---|
| `POST Downloads/GrabBest` `{ key }` | ricerca subito, sceglie come in §4.1/§4.2a, scarica, segna il tappabuchi | 204; 409 `NothingToGrab` se nel frattempo non c'è più niente da prendere; poi gli stessi errori di `Grab` (`Busy`, `Refused`, `Unavailable`, ...) |
| `POST Downloads/Snooze` `{ key }` | "Va bene, aspetto" | 204; 400 se la voce non è in `NeedsYou`/`NothingFound` |
| `POST Downloads/Import` `{ key }` | "Importa comunque" | 204; 409 se non è `ImportBlocked`; 502 con il codice di `ImportDownloadAsync` (`NoFiles`, ...) |
| `POST Downloads/Discard` `{ key }` | "Scarta e cerca un altro" | 204; 409 se non è `ImportBlocked`; 503 se Radarr/Sonarr non rispondono |

`GrabBest` rifà la ricerca invece di riusare una release salvata, perché Radarr/Sonarr accettano il grab solo di release della loro cache recente. Può durare fino a 2 minuti: lato app ci vuole `receiveTimeout: DownloadsApi.searchTimeout`, lato plugin `CancellationToken.None` per la ricerca e il grab (vedi CLAUDE.md): se l'app si chiude, perde la rete o supera il suo limite, il download parte lo stesso.

### 5.6 Dati nella panoramica

Ogni `DownloadItemDto` aggiunge:

- `Actions`: i pulsanti che valgono per quella voce, come codici (`GrabBest`, `Pick`, `SearchNow`, `Snooze`, `Import`, `Discard`). Li decide il plugin, che conosce lo stato. **(Mia scelta.)** Così un'app nuova con un plugin vecchio vede il campo vuoto e mostra i pulsanti di oggi, e il plugin può cambiare le regole senza aggiornare l'app.
- `Summary` (§5.2), `BlockedMessage` (§5.4) e `Snoozed`.

I campi nullable che devono esserci sempre vanno marcati `JsonIgnore(Condition = Never)` (CLAUDE.md).

## 6. App

- `DownloadItemRow`: frase di spiegazione (§4) sotto le righe di oggi; pulsanti da `Actions`, con il consigliato in evidenza. Senza `Actions` (plugin vecchio) i pulsanti restano quelli di oggi.
- Pulsante consigliato per caso: `GrabBest` dove c'è, altrimenti `Import`, `Pick` per `GrabRefused`, `Snooze` per "nessun risultato". **(Mia scelta, rivista nel piano:** il plugin mette il consigliato per primo in `Actions` e l'app evidenzia il primo nelle righe "Serve te".)
- Ogni azione: pulsante occupato mentre lavora (come `AdminActionButton`), SnackBar con l'esito o l'errore, poi rilettura della panoramica. `GrabBest` mostra "Cerco e scarico…" perché può durare.
- Riga "In attesa" silenziata: etichetta "senza avvisi" accanto al titolo.
- Testi in italiano e inglese negli ARB. I numeri si formattano come nel resto della scheda.

## 7. Versioni

Plugin 1.18.0 (aggiornare anche `InfoControllerTests`), app 0.27.0. L'app nuova funziona col plugin 1.17.0, con i pulsanti di oggi.

## 8. Lasciato a chi costruisce

- I nomi dei campi e dei tipi, e dove mettere il codice nei file parziali di `DownloadService`.
- Come contare il "rifiuto più frequente" quando i testi di Sonarr variano (per esempio con numeri dentro). Basta il primo rifiuto di ogni release, raggruppato per testo esatto. Se sono tutti diversi, si mostra il primo.
- La verifica sul seedbox che `statusMessages` arrivi davvero nella coda di Radarr e di Sonarr, e il suo formato.
- I test: regola del tappabuchi (scelta tra i `TooSmall`, ordine per peso), riassunto in `NothingChosen`, silenzio e suo ritorno con `BelowMinScore`, finestra upgrade del tappabuchi, esclusione delle release rifiutate, import e scarto con i loro 409. Lato app: pulsanti per caso e fallback senza `Actions`.
