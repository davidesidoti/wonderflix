# Scarica subito: trovare un titolo nella lista Download e farlo passare davanti

## Perché

Un utente chiede una serie che gli serve subito. L'admin apre la scheda Download, ma la lista è lunga e non la trova. Anche trovandola, "Cerca ora" non basta:

- mette la riga a "scaduta adesso", e la coda parte dalla più vecchia: finisce dietro tutte quelle già scadute;
- agisce su una riga sola, mentre una serie occupa una riga per ogni episodio o stagione mancante;
- un giro fa al massimo 10 ricerche, una alla volta, e un `Nudge` a giro in corso aspetta la fine del giro;
- un titolo appena aggiunto entra nella lista solo al giro dopo, perché le voci nascono in `Apply`, all'inizio del giro.

Successo: l'admin scrive il nome, preme un pulsante, e la prossima ricerca che parte è quella della sua serie.

## Obiettivi

1. Campo di ricerca in cima alla scheda Download che restringe tutte le sezioni.
2. "Scarica subito": un pulsante solo che porta davanti tutta la serie (o il film).
3. "Aggiorna ora": se il titolo non è ancora in lista, lo si fa comparire senza aspettare il giro.

## Fuori scopo

- Interrompere una ricerca già partita.
- Ricerche in parallelo: Sonarr gira in un container da 2 GB e va in OutOfMemory sulle ricerche grosse. Una alla volta resta la regola.
- Cambiare le regole di scelta delle release: "Scarica subito" usa le stesse del giro automatico, e se non trova nulla di adatto la riga va in "Serve te" come sempre.
- Anticipare una sola stagione con un pulsante dedicato: per la riga singola restano "Cerca ora" e "Scegli tu".

## Da evitare

- Che il giro si fermi in continuazione: la richiesta di fermarsi è un evento una tantum, non una condizione letta dalle voci (una voce con la precedenza che non è più cercabile lo fermerebbe per sempre).
- Che una serie "scavalchi" le ricerche manuali dell'admin: quelle hanno la precedenza dalla 1.26 e continuano ad averla.

## Decisioni dell'utente

- Soluzione A del mockup: campo in cima alla lista, non finestra dedicata.
- Il pulsante agisce su tutta la serie.
- La ricerca già partita non si interrompe, la tua inizia quando finisce (di solito minuti, una stagione anime fino a circa 30). Comportamento mostrato e approvato.
- Il comportamento descritto qui sotto in "Saltare la coda" e "Titolo appena aggiunto" è stato approvato in chat.

## Comportamento

### Campo di ricerca (app)

- In `DownloadsTab`, nel `ListView`, subito dopo il pulsante di aggiornamento. Sempre presente, così i figli sotto non cambiano posizione e lo scroll non si azzera (vedi gotcha in `CLAUDE.md`).
- Filtra mentre scrivi, in locale, sul titolo: "contiene", senza distinguere maiuscole né accenti.
- Con il campo non vuoto:
  - valgono tutte le sezioni (Serve te, sconosciuti, scelte, in attesa, da ripassare); una sezione senza risultati sparisce;
  - le sezioni chiuse si mostrano aperte senza toccare la preferenza salvata (`_collapsed`);
  - i limiti di visualizzazione non valgono: scelte oltre i 7 giorni e tutte le righe di "Da ripassare", non solo le prime `_reviewShown`.
- Una pressione su ✕ svuota il campo. Il filtro non si salva tra una visita e l'altra.
- I ricaricamenti periodici non toccano il testo né il focus.

### Righe "Scarica subito" (app)

- Le righe di `overview.waiting` (la lista del DTO, qualunque stato) si raggruppano per `SeriesId` (nuovo campo del DTO). Il nome della serie è il titolo fino all'ultimo ` · `. Un film è un gruppo da solo con il suo titolo intero.
- Con il campo non vuoto, in testa ai risultati, una riga per ogni gruppo in cui almeno una riga corrisponde al filtro e almeno una riga ha `CanRush` o `Rush`. Una serie solo in download o in `UpgradeWatch` non ha la riga; una tutta in "Serve te" sì.
- Testo della riga: nome, poster, e quante righe mancano (es. "28 mancanti"): le righe del gruppo intero con `CanRush` o `Rush`, anche quelle che il filtro non mostra.
- Il pulsante c'è solo se almeno una riga del gruppo ha `CanRush`, nessuna ha `Rush` e i download automatici sono accesi (`overview.enabled`).
- Se almeno una riga del gruppo ha `Rush`, al posto del pulsante si legge "In testa alla coda" (solo con i download automatici accesi: da spenti c'è la nota che lo dice).

### Saltare la coda (plugin)

Nuovo `POST Downloads/Rush` con `{ "Key": ... }`, 202 se accettato, 400 per chiave non valida o senza voce (stessa forma di `SearchNow`). `DownloadService.Rush(key)`:

- film: la sua voce; episodio o stagione: tutte le voci con lo stesso `SeriesId`. L'espansione la fa il plugin perché la lista dell'app può essere vecchia;
- solo le voci che mancano davvero: `State` `Waiting` o `NeedsYou` senza `ImportBlocked` (`CanRush`). Niente `UpgradeWatch`: quei file ci sono già e rallenterebbero la serie urgente. Le rimandate (`Snoozed`) sono comprese;
- su ognuna: `RushAt = now` (nuovo campo di `DownloadEntry`, persistito) e `NextSearchAt = now`;
- chiede al giro in corso di fermarsi (`_rushRequested`, solo in memoria, sotto `_lock`) e chiede un giro.

Il giro:

- `_rushRequested` si azzera all'inizio di `RunCycleAsync`, prima di leggere Sonarr e Radarr;
- in `SearchDueAsync`, nello stesso blocco `lock` del controllo `ManualSearching()`: se `_rushRequested` è vero si esce dal ciclo. La ricerca in corso finisce normalmente;
- ordine delle voci scadute: prima quelle con `RushAt`, dalla più vecchia, poi le altre per `NextSearchAt` come oggi. A pari `RushAt` stagioni ed episodi in ordine crescente, così una serie si scarica dall'inizio;
- `MaxSearchesPerCycle` non si applica alle voci con `RushAt`: una serie lunga non aspetta il giro dopo per il limite di 10;
- alla fine della ricerca di una voce, qualunque esito, `RushAt` torna null e la voce riprende il ritmo normale. `RushAt` torna null anche quando la voce esce da `Waiting`/`NeedsYou` per altre vie (scelta manuale, import, ecc.);
- una stagione con `RushAt` divisa in episodi (`Split`, nessun pack adatto o timeout) passa il suo `RushAt` agli episodi, e una stagione ricomposta da episodi (`GroupSeasons`) prende il più vecchio dei loro. Dopo un `Split` di una voce con `RushAt` il giro imposta `_rushRequested`: si ferma e ne riparte uno che comprende gli episodi nuovi, che l'elenco `due` del giro in corso non ha;
- le ricerche manuali continuano a tenere fermo il giro come oggi; alla ripresa le voci con `RushAt` sono comunque le prime.

**Ritardo.** `DownloadService.NudgeDelay` è 1 minuto. Per `Rush` e `Refresh`, compreso il giro che riparte dopo un giro fermato, il ritardo è di pochi secondi (costante nuova, al massimo 5 s). Gli altri `Nudge` restano a 1 minuto.

### Titolo appena aggiunto

- Se il campo non è vuoto e nessuna riga di `overview.waiting` corrisponde, sopra le altre sezioni l'app mostra "Non è in lista" e il pulsante "Aggiorna ora" (solo con i download automatici accesi: da spento il giro non crea voci). Vale anche se il filtro trova righe vecchie in "Scelte" o "Da ripassare": è il caso di una stagione nuova di una serie già vista.
- Nuovo `POST Downloads/Refresh`, 202: imposta `_rushRequested` e `_refreshPending` e chiede un giro con il ritardo breve.
- Il giro nuovo rilegge Sonarr e Radarr, e `Apply` crea le voci. Poi `_refreshPending` torna false.
- Quel giro non avvia ricerche, a meno che qualche voce abbia `RushAt`: altrimenti partirebbe subito la voce più vecchia e il titolo appena comparso si troverebbe dietro di lei. Le ricerche normali riprendono al giro periodico successivo (al massimo 15 minuti) o con "Scarica subito".
- L'overview ha il nuovo campo `RefreshPending`. Finché è vero l'app mostra "Aggiornamento…" al posto del pulsante e rilegge ogni 5 secondi (`_fastPoll`). Quando torna falso e il titolo non c'è (non è monitorato o non è ancora uscito), torna "Non è in lista" con il pulsante.
- Nessuna ricerca parte da sola per il titolo comparso: l'admin preme "Scarica subito".

### Contratto (`DownloadItemDto`)

Campi nuovi, sempre presenti (`JsonIgnore(Condition = Never)` per quelli nullable):

- `SeriesId`: `int?`, null per i film;
- `CanRush`: `bool`, la regola di cui sopra, calcolata solo nel plugin;
- `Rush`: `bool`, la voce ha `RushAt`.

`SearchPhase` non cambia: una voce con la precedenza si vede già "In coda".

`DownloadsOverviewDto` ha il nuovo campo `RefreshPending` (`bool`).

## Compatibilità

- App nuova con plugin vecchio: i campi mancano, `CanRush` vale false e `SeriesId` null. Il filtro funziona, il pulsante "Scarica subito" non compare. "Aggiorna ora" si mostra solo se l'overview contiene `RefreshPending`: nell'app il campo è nullable, null vuol dire plugin vecchio.
- `RushAt` manca nei `downloads.json` esistenti: vale null.
- Il riavvio di Jellyfin perde `_rushRequested` ma non `RushAt`: il primo giro parte comunque dalle voci con la precedenza.

## Versioni e rilascio

Plugin 1.27.0 (aggiornare anche `InfoControllerTests`), app 0.38.0, nuova riga nella checklist di `docs/RELEASING.md`. Etichette nuove in `app_it.arb` e `app_en.arb`.

## Test

- Plugin: espansione su serie e film, esclusione di `UpgradeWatch` e `ImportBlocked`, ordine con precedenza, nessun limite di 10 per le voci con la precedenza, stop del giro dopo la ricerca in corso, `RushAt` azzerato per qualunque esito, `RushAt` passato da stagione a episodi e viceversa, ricerche manuali ancora prima, giro di `Refresh` senza ricerche e `RefreshPending`, `Rush`/`Refresh` nel controller.
- App: filtro su ogni sezione, sezioni chiuse e limiti ignorati durante il filtro, testo conservato ai ricaricamenti, raggruppamento per `SeriesId`, riga e conteggio con righe tutte in "Serve te", stati del pulsante, "Non è in lista" anche con righe vecchie trovate, "Aggiornamento…" con `RefreshPending`.
- A mano sul seedbox, con coda piena e una ricerca in corso: serie nuova richiesta, "Aggiorna ora", "Scarica subito", verifica nei log che sia la prima ricerca dopo quella in corso.

## Scelte fatte da chi ha scritto il documento, da confermare

- Il giro di "Aggiorna ora" non avvia ricerche.
- Le stagioni divise in episodi mantengono la precedenza.
- Le righe in `UpgradeWatch` non passano davanti.
- "Non è in lista" compare anche se il filtro trova solo righe vecchie.
- Il ritardo prima del giro scende da 1 minuto a pochi secondi per `Rush` e `Refresh`.

## Scelte lasciate a chi costruisce

- Nomi interni, struttura del widget del campo e della riga serie.
- Come normalizzare gli accenti: non esiste un helper nell'app e `package:collection` non è una dipendenza diretta.
- Come passare il ritardo breve da `DownloadService` a `DownloadsHostedService`.
- Il campo vale ovunque si veda la scheda Download. Su TV si usa con la tastiera a schermo; nessun lavoro dedicato.
